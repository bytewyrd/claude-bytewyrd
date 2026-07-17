#!/usr/bin/env bash
# Run /sync environment pre-flight checks and collect project context.
# Used by: skills/sync/SKILL.md (Step 1).
#
# Performs the deterministic environment validation and context collection that
# the /sync skill used to run as a series of separate Bash tool calls. The
# benefit of consolidating into one script is fewer tool-call round-trips and
# a single JSON object the skill can consume.
#
# Args: none.
#
# Behavior:
#   1. Hard environment checks. If any check fails, the script exits with a
#      non-zero status. The first hard check (git) emits plain text to stderr
#      because jq may not be on PATH yet. After git is verified, subsequent
#      hard checks emit structured JSON errors via _lib/common.bash.
#   2. Data collection. Reads git, the GitHub remote (if present), the
#      installed-plugins registry, and the docs-agent version markers.
#   3. Plugin-root resolution via _lib/plugin.bash.
#   4. Sidecar migration: one-time move of .claude/.bootstrap-versions.json
#      to .bytewyrd/.bootstrap-versions.json. Idempotent — only acts when the
#      old path exists and the new path does not.
#   5. Language detection via _lib/detect-languages.bash.
#
#   Side effects:
#     - When docs_agent_drifted is true, writes the plugin's version string
#       to .bytewyrd/docs-agent-version. The skill prints the drift suggestion;
#       the marker is written here so subsequent /sync runs do not re-prompt.
#     - When the legacy sidecar path exists and the new path does not, the
#       file is moved to .bytewyrd/.bootstrap-versions.json.
#
# Output:
#   stdout: a single JSON object on success.
#     {
#       "repo_root":              "<abs path>",
#       "git_user":               "<git config user.name or empty>",
#       "project_slug":           "<basename of repo_root>",
#       "has_substantial_content": <bool>,
#       "github_remote":          "<origin url or empty>",
#       "github_description":     "<gh repo description or empty>",
#       "installed_plugins":      ["<id>", ...],
#       "missing_critical":       ["<id>", ...],
#       "missing_recommended":    ["<id>", ...],
#       "plugin_docs_ver":        "<version string or empty>",
#       "project_docs_ver":       "<version string or empty>",
#       "docs_agent_drifted":     <bool>,
#       "plugin_root":            "<abs path to plugin checkout>",
#       "plugin_version":         "<semver string or empty>",
#       "sidecar_migrated":       <bool>,
#       "sidecar_message":        "<human-readable migration result>",
#       "languages":              ["rust", "js", ...],
#       "component_roots":        [{"language": "...", "path": "...", "name": "..."}, ...],
#       "has_rust":               <bool>,
#       "has_js":                 <bool>,
#       "has_go":                 <bool>,
#       "has_python":             <bool>,
#       "has_svelte":             <bool>,
#       "has_ruby":               <bool>,
#       "has_rails":              <bool>,
#       "has_k8s_cue":            <bool>,
#       "has_terraform":          <bool>
#     }
#   stderr: empty on success; one of the error envelopes on failure.
#
# Exit codes:
#   0  All hard checks passed; JSON emitted to stdout.
#   1  A hard environment check failed (git, sha256sum/shasum, python3, or
#      plugin-root resolution). The script printed an error (plain text for
#      the git-missing case; JSON via emit_error otherwise).
#   2  jq itself is missing. The shared common.bash require_jq function
#      handles this with a static JSON error.

set -uo pipefail

# --- Hard check 1: git must be on PATH. ---
# We do this BEFORE sourcing _lib/common.bash because:
#   1) The git check is independent of jq, and a missing git is the most
#      fundamental failure — surface it with a plain text error.
#   2) require_jq exits 2 on missing jq; we don't want a missing-git error
#      to be shadowed by a missing-jq error.
if ! command -v git >/dev/null 2>&1; then
  echo "/sync requires git. Install: https://git-scm.com/downloads" >&2
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "/sync must be run inside a git repository (no .git found)." >&2
  exit 1
fi

# --- Hard check 2: sha256sum or shasum must be on PATH. ---
# Still pre-jq, because we cannot trust jq is available until require_jq runs.
# Output a static JSON string here.
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  printf '{"error":"/sync requires sha256sum or shasum. Install with: brew install coreutils (macOS) or apt install coreutils (Debian/Ubuntu)"}\n' >&2
  exit 1
fi

# Source the shared libs now that we have a usable shell environment.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib/common.bash
source "$SCRIPT_DIR/_lib/common.bash"
# shellcheck source=_lib/plugin.bash
source "$SCRIPT_DIR/_lib/plugin.bash"
# shellcheck source=_lib/detect-languages.bash
source "$SCRIPT_DIR/_lib/detect-languages.bash"
require_jq

# --- Hard check 3: python3 must be on PATH (used for TOML parsing). ---
if ! command -v python3 >/dev/null 2>&1; then
  # emit_error writes JSON to stdout; we redirect it to stderr because the
  # success JSON is the script's stdout contract — error envelopes go to
  # stderr so the caller can still safely consume stdout as JSON.
  emit_error "/sync requires python3 for TOML parsing. Install with: brew install python3 (macOS) or apt install python3 (Debian/Ubuntu)" >&2
  exit 1
fi

# --- Data collection ---

# repo_root is the *write target*: every file /sync creates or updates lands
# here. It must stay the current checkout — the worktree when /sync runs inside
# one — so writes flow through the worktree's branch and PR. See SKILL.md Step 1
# "Write target". Never redirect this to the main repo via --git-common-dir.
repo_root="$(git rev-parse --show-toplevel)"
git_user="$(git config user.name 2>/dev/null || echo "")"

# project_slug names the *project*, not the checkout. When /sync runs inside a
# worktree, --show-toplevel points at the worktree directory, so basename of
# repo_root would yield the worktree name (e.g. a branch-derived directory)
# instead of the real project name. The shared git-common-dir always resolves to
# the main repository regardless of which worktree we are in, so its parent
# directory is the true project root. Resolve it robustly: --git-common-dir may
# print a relative path (e.g. ".git") depending on git version and cwd, so cd
# into "<common-dir>/.." and let the shell canonicalize to an absolute path.
# Fall back to repo_root if resolution fails for any reason.
project_root="$(cd "$(git rev-parse --git-common-dir)/.." 2>/dev/null && pwd)"
[ -n "$project_root" ] || project_root="$repo_root"
project_slug="$(basename "$project_root")"

# Substantial content: any committed file other than LICENSE, README, or .gitignore.
# Use the `|| true` guard because grep -c returning 0 with -v can exit non-zero
# on some platforms, and pipefail would surface that.
substantial_count="$(git ls-files | grep -cvE '^(LICENSE|README\.md?|\.gitignore)$' || true)"
if [ "$substantial_count" -gt 0 ]; then
  has_substantial_content=true
else
  has_substantial_content=false
fi

# GitHub remote: empty when origin is unset or non-GitHub.
remote_url="$(git remote get-url origin 2>/dev/null || echo "")"
case "$remote_url" in
  *github.com*) github_remote="$remote_url" ;;
  *)            github_remote="" ;;
esac

# GitHub description: only fetched when gh is available AND we found a GH remote.
github_description=""
if [ -n "$github_remote" ] && command -v gh >/dev/null 2>&1; then
  # Suppress all gh errors — gh may be unauthenticated or rate-limited. The
  # description is a pre-fill default, not load-bearing.
  github_description="$(gh repo view --json name,description 2>/dev/null | jq -r '.description // ""' 2>/dev/null || echo "")"
fi

# Installed plugins: read keys of the `.plugins` object in the registry file.
installed_plugins_json="[]"
registry="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$registry" ]; then
  # Use `try / catch` semantics — if the file is malformed JSON, fall back to [].
  if installed_keys="$(jq -c '.plugins // {} | keys' "$registry" 2>/dev/null)"; then
    installed_plugins_json="$installed_keys"
  fi
fi

# Cross-check against critical and recommended sets.
critical_set='["github@claude-plugins-official"]'
recommended_set='["context7@claude-plugins-official","code-review@claude-plugins-official"]'

missing_critical="$(jq -nc \
  --argjson installed "$installed_plugins_json" \
  --argjson critical "$critical_set" \
  '$critical - $installed')"

missing_recommended="$(jq -nc \
  --argjson installed "$installed_plugins_json" \
  --argjson recommended "$recommended_set" \
  '$recommended - $installed')"

# Docs-agent version drift detection.
# NOTE: this `plugin_root` is the docs-agent lookup root, not the bytewyrd
# plugin-root resolved below. The legacy heuristic ($CLAUDE_PLUGIN_ROOT or
# $HOME/.claude) preserves backward-compat for projects that have not yet
# adopted the per-file marker model. The authoritative plugin root used by
# Step 4 of /sync comes from find_plugin_root below.
docs_lookup_root="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
plugin_docs_ver=""
plugin_docs_agent="$docs_lookup_root/agents/docs-agent.md"
if [ -f "$plugin_docs_agent" ]; then
  # Extract the version string from a line like:  docs-agent-version: 2026-05-10-initial
  # Tolerate surrounding HTML comment markers or YAML key prefixes.
  plugin_docs_ver="$(grep -m1 'docs-agent-version:' "$plugin_docs_agent" 2>/dev/null \
    | sed -E 's/.*docs-agent-version:[[:space:]]*([^[:space:]]+).*/\1/' \
    || echo "")"
fi

project_docs_ver=""
if [ -f .bytewyrd/docs-agent-version ]; then
  project_docs_ver="$(cat .bytewyrd/docs-agent-version 2>/dev/null || echo "")"
fi

if [ -n "$plugin_docs_ver" ] && [ "$plugin_docs_ver" != "$project_docs_ver" ]; then
  docs_agent_drifted=true
else
  docs_agent_drifted=false
fi

# Side effect: when drift is detected, record the new version. Guard against
# overwriting a valid marker with an empty string (the [ -n ] check above
# already prevents that, but be explicit here too).
if [ "$docs_agent_drifted" = "true" ] && [ -n "$plugin_docs_ver" ]; then
  mkdir -p .bytewyrd
  printf '%s\n' "$plugin_docs_ver" > .bytewyrd/docs-agent-version
fi

# --- Plugin root resolution ---

if ! find_plugin_root; then
  emit_error "$PLUGIN_ROOT_ERROR" >&2
  exit 1
fi
# find_plugin_root sets PLUGIN_ROOT, PLUGIN_MANIFEST, PLUGIN_SOURCE.

# Plugin version: read from .claude-plugin/plugin.json inside the resolved root.
plugin_version=""
plugin_json="$PLUGIN_ROOT/.claude-plugin/plugin.json"
if [ -f "$plugin_json" ]; then
  plugin_version="$(jq -r '.version // ""' "$plugin_json" 2>/dev/null || echo "")"
fi

# --- Sidecar migration (one-time move) ---
# Inline rather than calling scripts/sync-sidecar-migrate.sh: there is exactly
# one in-process caller (this script) that benefits from the consolidation,
# and avoiding the subshell saves one process per /sync invocation. The
# standalone script is kept for edge-case testing — see invariants in
# the RFC for this consolidation.
old_sidecar=".claude/.bootstrap-versions.json"
new_sidecar=".bytewyrd/.bootstrap-versions.json"
sidecar_migrated=false
sidecar_message=""

if [ ! -f "$old_sidecar" ]; then
  # Nothing to migrate.
  sidecar_message="no migration needed: $old_sidecar is absent"
elif [ -f "$new_sidecar" ]; then
  # Both exist — never overwrite; leave both in place.
  sidecar_message="no migration needed: $new_sidecar already exists; old file kept in place"
else
  # Old exists, new does not — migrate.
  mkdir -p "$(dirname "$new_sidecar")"
  cp "$old_sidecar" "$new_sidecar"
  rm -f "$old_sidecar"
  sidecar_migrated=true
  sidecar_message="Migrated .bootstrap-versions.json: $old_sidecar → $new_sidecar"
fi

# --- Language detection ---
# detect_languages scans the current directory (repo_root) and sets
# DL_LANGUAGES, DL_COMPONENT_ROOTS, and the DL_HAS_* flags.
detect_languages

# --- Emit consolidated JSON ---

jq -n \
  --arg repo_root "$repo_root" \
  --arg git_user "$git_user" \
  --arg project_slug "$project_slug" \
  --argjson has_substantial_content "$has_substantial_content" \
  --arg github_remote "$github_remote" \
  --arg github_description "$github_description" \
  --argjson installed_plugins "$installed_plugins_json" \
  --argjson missing_critical "$missing_critical" \
  --argjson missing_recommended "$missing_recommended" \
  --arg plugin_docs_ver "$plugin_docs_ver" \
  --arg project_docs_ver "$project_docs_ver" \
  --argjson docs_agent_drifted "$docs_agent_drifted" \
  --arg plugin_root "$PLUGIN_ROOT" \
  --arg plugin_version "$plugin_version" \
  --argjson sidecar_migrated "$sidecar_migrated" \
  --arg sidecar_message "$sidecar_message" \
  --argjson languages "$DL_LANGUAGES" \
  --argjson component_roots "$DL_COMPONENT_ROOTS" \
  --argjson has_rust "$DL_HAS_RUST" \
  --argjson has_js "$DL_HAS_JS" \
  --argjson has_go "$DL_HAS_GO" \
  --argjson has_python "$DL_HAS_PYTHON" \
  --argjson has_svelte "$DL_HAS_SVELTE" \
  --argjson has_ruby "$DL_HAS_RUBY" \
  --argjson has_rails "$DL_HAS_RAILS" \
  --argjson has_k8s_cue "$DL_HAS_K8S_CUE" \
  --argjson has_terraform "$DL_HAS_TERRAFORM" \
  '{
    repo_root: $repo_root,
    git_user: $git_user,
    project_slug: $project_slug,
    has_substantial_content: $has_substantial_content,
    github_remote: $github_remote,
    github_description: $github_description,
    installed_plugins: $installed_plugins,
    missing_critical: $missing_critical,
    missing_recommended: $missing_recommended,
    plugin_docs_ver: $plugin_docs_ver,
    project_docs_ver: $project_docs_ver,
    docs_agent_drifted: $docs_agent_drifted,
    plugin_root: $plugin_root,
    plugin_version: $plugin_version,
    sidecar_migrated: $sidecar_migrated,
    sidecar_message: $sidecar_message,
    languages: $languages,
    component_roots: $component_roots,
    has_rust: $has_rust,
    has_js: $has_js,
    has_go: $has_go,
    has_python: $has_python,
    has_svelte: $has_svelte,
    has_ruby: $has_ruby,
    has_rails: $has_rails,
    has_k8s_cue: $has_k8s_cue,
    has_terraform: $has_terraform
  }'

exit 0
