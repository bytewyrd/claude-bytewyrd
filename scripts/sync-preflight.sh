#!/usr/bin/env bash
# Run /sync environment pre-flight checks and collect project context.
# Used by: skills/sync/SKILL.md (Step 1 and Step 1.5).
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
#   3. Side effect: when docs_agent_drifted is true, writes the plugin's
#      version string to .bytewyrd/docs-agent-version, creating the directory
#      if absent. The skill prints the drift suggestion; the marker is written
#      here so subsequent /sync runs do not re-prompt for the same version.
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
#       "docs_agent_drifted":     <bool>
#     }
#   stderr: empty on success; one of the error envelopes on failure.
#
# Exit codes:
#   0  All hard checks passed; JSON emitted to stdout.
#   1  A hard environment check failed. The script printed an error
#      (plain text for the git-missing case; JSON via emit_error otherwise).
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

# Source the shared lib now that we have a usable shell environment.
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
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

repo_root="$(git rev-parse --show-toplevel)"
git_user="$(git config user.name 2>/dev/null || echo "")"
project_slug="$(basename "$repo_root")"

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
plugin_root="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
plugin_docs_ver=""
plugin_docs_agent="$plugin_root/agents/docs-agent.md"
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
    docs_agent_drifted: $docs_agent_drifted
  }'

exit 0
