#!/usr/bin/env bash
# Language detection helpers for scripts/*.sh.
# Source from a script that needs to scan the current directory for language
# manifests and stack signals:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/detect-languages.bash"
#   detect_languages
#
# This file must not set -e / -o pipefail — callers own their strict-mode
# posture (see _lib/common.bash for the same convention). It is safe under
# set -u (no unset-var refs).
#
# Requires `jq` on PATH; callers should have already called `require_jq`
# from _lib/common.bash before invoking detect_languages.

# --- Private helpers (prefixed _dl_ to avoid namespace pollution) ----------

# _dl_cargo_is_workspace <cargo-toml-path>
# Returns 0 if the file declares a [workspace] table, 1 otherwise.
_dl_cargo_is_workspace() {
  grep -q '^\[workspace\]' "$1" 2>/dev/null
}

# _dl_cargo_workspace_members <cargo-toml-path>
# Print workspace members (one per line). Empty output on:
#   - missing python3 (tomllib requires 3.11+)
#   - parse failure
#   - no [workspace].members array
# Caller treats empty output as "fall back to standalone crate".
_dl_cargo_workspace_members() {
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

# _dl_svelte_in_package_json <newline-separated-package-files>
# Returns 0 if any of the listed package.json files declares svelte as a
# dependency or devDependency. Returns 1 otherwise. Tolerates malformed JSON.
_dl_svelte_in_package_json() {
  local package_files="$1"
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

# _dl_rails_in_gemfile <gemfile-path>
# Returns 0 if the Gemfile declares the `rails` gem, 1 otherwise.
# Tolerates a missing/empty path argument.
_dl_rails_in_gemfile() {
  local gemfile="$1"
  [ -z "$gemfile" ] && return 1
  grep -qE '^[[:space:]]*gem[[:space:]]+["'"'"']rails["'"'"']' "$gemfile" 2>/dev/null
}

# --- Public entry point ----------------------------------------------------

# detect_languages
#
# Scan the current directory for language manifests and stack signals.
# Must be invoked from `repo_root` (set by the caller). Requires jq on PATH.
#
# Sets the following output variables on return:
#   DL_LANGUAGES        — JSON array, e.g. '["rust","js"]'
#   DL_COMPONENT_ROOTS  — JSON array of {language,path,name} entries
#   DL_HAS_RUST         — boolean string "true" / "false"
#   DL_HAS_JS           — boolean string "true" / "false"
#   DL_HAS_GO           — boolean string "true" / "false"
#   DL_HAS_PYTHON       — boolean string "true" / "false"
#   DL_HAS_SVELTE       — boolean string "true" / "false"
#   DL_HAS_RUBY         — boolean string "true" / "false"
#   DL_HAS_RAILS        — boolean string "true" / "false"
#   DL_HAS_K8S_CUE      — boolean string "true" / "false"
#   DL_HAS_TERRAFORM    — boolean string "true" / "false"
#
# Detection rules:
#   - Rust:    Cargo.toml (excluding target/). If root Cargo.toml has
#              [workspace], each member becomes a component_root.
#   - JS/TS:   package.json (excluding node_modules/). One component per file.
#   - Go:      go.mod. One component per file.
#   - Python:  pyproject.toml + setup.py. One component per file (deduped).
#   - Svelte:  any *.svelte file (excluding node_modules/) OR svelte in
#              dependencies/devDependencies of any package.json.
#   - Ruby:    Gemfile (excluding vendor/).
#   - Rails:   config/application.rb OR rails gem in Gemfile.
#   - K8s CUE: *.cue under */k8s/*.
#   - TF/TG:   *.tf (excluding .terraform/) OR terragrunt.hcl.
detect_languages() {
  # --- Find manifest files ---
  # `2>/dev/null` swallows find's complaint on missing paths.
  # `|| true` keeps pipefail callers happy when find produces no matches.
  local cargo_files package_files gomod_files python_files
  cargo_files="$(find . -name "Cargo.toml" -not -path "*/target/*" 2>/dev/null | sort || true)"
  package_files="$(find . -name "package.json" -not -path "*/node_modules/*" 2>/dev/null | sort || true)"
  gomod_files="$(find . -name "go.mod" 2>/dev/null | sort || true)"
  # Python: combine pyproject.toml and setup.py. Dedupe via sort -u.
  python_files="$( { find . -name "pyproject.toml" 2>/dev/null; find . -name "setup.py" 2>/dev/null; } | sort -u || true)"

  # Stack-detection one-shots.
  local svelte_first gemfile_first rails_app_first k8s_cue_first tf_first terragrunt_first
  svelte_first="$(find . -name "*.svelte" -not -path "*/node_modules/*" 2>/dev/null | head -1 || true)"
  gemfile_first="$(find . -name "Gemfile" -not -path "*/vendor/*" 2>/dev/null | head -1 || true)"
  rails_app_first="$(find . -name "application.rb" -path "*/config/application.rb" 2>/dev/null | head -1 || true)"
  k8s_cue_first="$(find . -name "*.cue" -path "*/k8s/*" 2>/dev/null | head -1 || true)"
  tf_first="$(find . -name "*.tf" -not -path "*/.terraform/*" 2>/dev/null | head -1 || true)"
  terragrunt_first="$(find . -name "terragrunt.hcl" 2>/dev/null | head -1 || true)"

  # --- Build component_roots ---
  local component_roots="[]"

  # Helper to append one entry. Local-scoped via _dl_append_component to keep
  # detect_languages reentrant: it does not leak outer-scope state.
  _dl_append_component() {
    local language="$1" path="$2" name="$3"
    component_roots="$(jq -nc \
      --argjson roots "$component_roots" \
      --arg language "$language" \
      --arg path "$path" \
      --arg name "$name" \
      '$roots + [{"language": $language, "path": $path, "name": $name}]')"
  }

  # Rust: root Cargo.toml controls workspace expansion.
  local f dir pkg_name member member_path member_name members
  if [ -n "$cargo_files" ]; then
    if [ -f "./Cargo.toml" ] && _dl_cargo_is_workspace "./Cargo.toml"; then
      # Workspace mode. Each member becomes a component_root.
      members="$(_dl_cargo_workspace_members "./Cargo.toml")"
      if [ -z "$members" ]; then
        # Fall back to standalone if tomllib was unavailable or no members listed.
        _dl_append_component "rust" "." "$(basename "$(pwd)")"
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
          _dl_append_component "rust" "$member_path" "$member_name"
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
        _dl_append_component "rust" "$dir" "$pkg_name"
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
      _dl_append_component "js" "$dir" "$pkg_name"
    done <<< "$package_files"
  fi

  # Go: one component per go.mod. Use dirname for the name.
  if [ -n "$gomod_files" ]; then
    local name
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      dir="$(dirname "$f")"
      name="$(basename "$(cd "$dir" && pwd)")"
      _dl_append_component "go" "$dir" "$name"
    done <<< "$gomod_files"
  fi

  # Python: one component per pyproject.toml or setup.py.
  if [ -n "$python_files" ]; then
    local name
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      dir="$(dirname "$f")"
      name="$(basename "$(cd "$dir" && pwd)")"
      _dl_append_component "python" "$dir" "$name"
    done <<< "$python_files"
  fi

  # --- Compute stack flags ---
  local has_rust=false has_js=false has_go=false has_python=false
  [ -n "$cargo_files" ]   && has_rust=true
  [ -n "$package_files" ] && has_js=true
  [ -n "$gomod_files" ]   && has_go=true
  [ -n "$python_files" ]  && has_python=true

  local has_svelte=false
  if [ -n "$svelte_first" ]; then
    has_svelte=true
  elif [ -n "$package_files" ] && _dl_svelte_in_package_json "$package_files"; then
    has_svelte=true
  fi

  local has_ruby=false
  [ -n "$gemfile_first" ] && has_ruby=true

  local has_rails=false
  if [ -n "$rails_app_first" ]; then
    has_rails=true
  elif _dl_rails_in_gemfile "$gemfile_first"; then
    has_rails=true
  fi

  local has_k8s_cue=false
  [ -n "$k8s_cue_first" ] && has_k8s_cue=true

  local has_terraform=false
  if [ -n "$tf_first" ] || [ -n "$terragrunt_first" ]; then
    has_terraform=true
  fi

  # --- Languages list (detection order: rust, js, go, python) ---
  local languages_json="[]"
  local lang flag_var
  for lang in rust js go python; do
    flag_var="has_$lang"
    if [ "${!flag_var}" = "true" ]; then
      languages_json="$(jq -nc --argjson l "$languages_json" --arg n "$lang" '$l + [$n]')"
    fi
  done

  # --- Export results to caller via DL_* variables ---
  DL_LANGUAGES="$languages_json"
  DL_COMPONENT_ROOTS="$component_roots"
  DL_HAS_RUST="$has_rust"
  DL_HAS_JS="$has_js"
  DL_HAS_GO="$has_go"
  DL_HAS_PYTHON="$has_python"
  DL_HAS_SVELTE="$has_svelte"
  DL_HAS_RUBY="$has_ruby"
  DL_HAS_RAILS="$has_rails"
  DL_HAS_K8S_CUE="$has_k8s_cue"
  DL_HAS_TERRAFORM="$has_terraform"
}
