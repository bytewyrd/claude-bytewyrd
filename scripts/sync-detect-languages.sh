#!/usr/bin/env bash
# Detect language manifests and component roots in the current directory.
# Used by: skills/sync/SKILL.md (Step 3 — component-structure detection).
#
# Consolidates the find/grep dance that the sync skill used to spell out as
# a series of separate Bash tool calls. The benefit of one script is a single
# round-trip to the agent and a single JSON object to consume.
#
# Args: none. Must be run from `repo_root` (returned by sync-preflight.sh).
#
# Behavior:
#   For each language, scans for the canonical manifest file:
#     - Rust:    Cargo.toml (excluding target/)
#     - JS/TS:   package.json (excluding node_modules/)
#     - Go:      go.mod
#     - Python:  pyproject.toml, setup.py
#   For each detected manifest, emits one entry to `component_roots`. For
#   Rust workspaces (Cargo.toml with [workspace]), uses python3 + tomllib to
#   read the members array and emits one entry per workspace member.
#
#   Stack-detection flags signal which best-practice sections should be
#   appended to docs/BEST_PRACTICES.md in Step 5 of /sync. They are
#   independent of component_roots — a project can have has_svelte=true
#   without an explicit Svelte component root.
#
# Output:
#   stdout: a single JSON object on success.
#     {
#       "languages":         ["rust", "js", "go", "python"],
#       "component_roots":   [{"language": "...", "path": "...", "name": "..."}, ...],
#       "has_rust":          <bool>,
#       "has_js":            <bool>,
#       "has_go":            <bool>,
#       "has_python":        <bool>,
#       "has_svelte":        <bool>,
#       "has_ruby":          <bool>,
#       "has_rails":         <bool>,
#       "has_k8s_cue":       <bool>,
#       "has_terraform":     <bool>
#     }
#   stderr: empty on success; JSON error envelope on failure.
#
# Exit codes:
#   0  Detection succeeded.
#   2  Bad arguments or missing required tool (jq, python3 for workspace
#      parsing). The success path tolerates missing python3 by treating the
#      workspace as standalone — only a hard jq failure surfaces here.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

# --- Find manifest files ---
# Use `2>/dev/null` to swallow find's complaint about non-existent paths
# (e.g. running in a brand-new directory). The `|| true` guard keeps pipefail
# happy when find returns no matches.

cargo_files="$(find . -name "Cargo.toml" -not -path "*/target/*" 2>/dev/null | sort || true)"
package_files="$(find . -name "package.json" -not -path "*/node_modules/*" 2>/dev/null | sort || true)"
gomod_files="$(find . -name "go.mod" 2>/dev/null | sort || true)"
# Python: combine pyproject.toml and setup.py.
# Note: the original skill prose had `grep -v "*/node_modules/*"` which is a
# literal-string match that almost never hits — we follow the same intent
# (no node_modules exclusion for Python) and just dedupe.
python_files="$( { find . -name "pyproject.toml" 2>/dev/null; find . -name "setup.py" 2>/dev/null; } | sort -u || true)"

# Stack-detection one-shots.
svelte_first="$(find . -name "*.svelte" -not -path "*/node_modules/*" 2>/dev/null | head -1 || true)"
gemfile_first="$(find . -name "Gemfile" -not -path "*/vendor/*" 2>/dev/null | head -1 || true)"
rails_app_first="$(find . -name "application.rb" -path "*/config/application.rb" 2>/dev/null | head -1 || true)"
k8s_cue_first="$(find . -name "*.cue" -path "*/k8s/*" 2>/dev/null | head -1 || true)"
tf_first="$(find . -name "*.tf" -not -path "*/.terraform/*" 2>/dev/null | head -1 || true)"
terragrunt_first="$(find . -name "terragrunt.hcl" 2>/dev/null | head -1 || true)"

# --- Helpers ---

# Detect svelte dependency in any package.json. Falls back to false if
# package.json is malformed.
svelte_in_package_json() {
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if jq -e '
      (.dependencies // {} | has("svelte")) or
      (.devDependencies // {} | has("svelte"))
    ' "$f" >/dev/null 2>&1; then
      return 0
    fi
  done <<< "$package_files"
  return 1
}

# Detect rails gem in Gemfile. Tolerates malformed/missing Gemfile.
rails_in_gemfile() {
  [ -z "$gemfile_first" ] && return 1
  grep -qE '^[[:space:]]*gem[[:space:]]+["'"'"']rails["'"'"']' "$gemfile_first" 2>/dev/null
}

# Extract Cargo workspace members. Returns nothing on parse failure (treated
# as standalone crate). Requires python3 + tomllib (3.11+) — when missing or
# the file is not a workspace, returns nothing.
cargo_workspace_members() {
  local cargo="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  python3 - "$cargo" <<'PY' 2>/dev/null || true
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(0)
members = data.get("workspace", {}).get("members") or []
for m in members:
    if isinstance(m, str) and m:
        print(m)
PY
}

# Check whether a Cargo.toml declares a [workspace] table.
cargo_is_workspace() {
  grep -q '^\[workspace\]' "$1" 2>/dev/null
}

# --- Build component_roots ---

# Start with an empty JSON array and append entries via jq.
component_roots="[]"

append_component() {
  local language="$1" path="$2" name="$3"
  component_roots="$(jq -nc \
    --argjson roots "$component_roots" \
    --arg language "$language" \
    --arg path "$path" \
    --arg name "$name" \
    '$roots + [{"language": $language, "path": $path, "name": $name}]')"
}

# Rust: root Cargo.toml controls workspace expansion.
if [ -n "$cargo_files" ]; then
  if [ -f "./Cargo.toml" ] && cargo_is_workspace "./Cargo.toml"; then
    # Workspace mode. Each member becomes a component_root.
    members="$(cargo_workspace_members "./Cargo.toml")"
    if [ -z "$members" ]; then
      # Fall back to standalone if tomllib was unavailable or the file had no members.
      append_component "rust" "." "$(basename "$(pwd)")"
    else
      while IFS= read -r member; do
        [ -z "$member" ] && continue
        # Member is a relative path like "crates/foo" or "."
        member_path="./$member"
        member_name="$(basename "$member")"
        # If the member directory contains a Cargo.toml, try to read its package.name.
        if [ -f "$member_path/Cargo.toml" ]; then
          pkg_name="$(grep -m1 '^name[[:space:]]*=' "$member_path/Cargo.toml" 2>/dev/null \
            | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' || true)"
          [ -n "$pkg_name" ] && member_name="$pkg_name"
        fi
        append_component "rust" "$member_path" "$member_name"
      done <<< "$members"
    fi
  else
    # Standalone crate(s). One entry per Cargo.toml.
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      dir="$(dirname "$f")"
      pkg_name="$(grep -m1 '^name[[:space:]]*=' "$f" 2>/dev/null \
        | sed -E 's/^name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' || true)"
      [ -z "$pkg_name" ] && pkg_name="$(basename "$(cd "$dir" && pwd)")"
      append_component "rust" "$dir" "$pkg_name"
    done <<< "$cargo_files"
  fi
fi

# JS/TS: one component per package.json. Read .name; fall back to dirname.
if [ -n "$package_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    dir="$(dirname "$f")"
    pkg_name="$(jq -r '.name // ""' "$f" 2>/dev/null || echo "")"
    [ -z "$pkg_name" ] && pkg_name="$(basename "$(cd "$dir" && pwd)")"
    append_component "js" "$dir" "$pkg_name"
  done <<< "$package_files"
fi

# Go: one component per go.mod. Use dirname for the name.
if [ -n "$gomod_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    dir="$(dirname "$f")"
    name="$(basename "$(cd "$dir" && pwd)")"
    append_component "go" "$dir" "$name"
  done <<< "$gomod_files"
fi

# Python: one component per pyproject.toml or setup.py.
if [ -n "$python_files" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    dir="$(dirname "$f")"
    name="$(basename "$(cd "$dir" && pwd)")"
    append_component "python" "$dir" "$name"
  done <<< "$python_files"
fi

# --- Compute stack flags ---

has_rust=false;     [ -n "$cargo_files" ] && has_rust=true
has_js=false;       [ -n "$package_files" ] && has_js=true
has_go=false;       [ -n "$gomod_files" ] && has_go=true
has_python=false;   [ -n "$python_files" ] && has_python=true

has_svelte=false
if [ -n "$svelte_first" ]; then
  has_svelte=true
elif [ -n "$package_files" ] && svelte_in_package_json; then
  has_svelte=true
fi

has_ruby=false
[ -n "$gemfile_first" ] && has_ruby=true

has_rails=false
if [ -n "$rails_app_first" ]; then
  has_rails=true
elif rails_in_gemfile; then
  has_rails=true
fi

has_k8s_cue=false
[ -n "$k8s_cue_first" ] && has_k8s_cue=true

has_terraform=false
if [ -n "$tf_first" ] || [ -n "$terragrunt_first" ]; then
  has_terraform=true
fi

# --- Languages list (detection order: rust, js, go, python) ---
languages_json="[]"
for lang in rust js go python; do
  flag_var="has_$lang"
  if [ "${!flag_var}" = "true" ]; then
    languages_json="$(jq -nc --argjson l "$languages_json" --arg n "$lang" '$l + [$n]')"
  fi
done

# --- Emit final JSON ---
jq -n \
  --argjson languages "$languages_json" \
  --argjson component_roots "$component_roots" \
  --argjson has_rust "$has_rust" \
  --argjson has_js "$has_js" \
  --argjson has_go "$has_go" \
  --argjson has_python "$has_python" \
  --argjson has_svelte "$has_svelte" \
  --argjson has_ruby "$has_ruby" \
  --argjson has_rails "$has_rails" \
  --argjson has_k8s_cue "$has_k8s_cue" \
  --argjson has_terraform "$has_terraform" \
  '{
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
