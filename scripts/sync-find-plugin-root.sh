#!/usr/bin/env bash
# Locate the bytewyrd plugin root containing bootstrap-manifest.json.
# Used by: skills/sync/SKILL.md (Step 4 — plugin-root discovery).
#
# Resolution order:
#   1. $CLAUDE_PLUGIN_ROOT, if set AND its bootstrap-manifest.json exists.
#      Reported as source="env". Used when developers point at a checkout
#      of the plugin instead of the cached install.
#   2. $HOME/.claude/bootstrap-manifest.json, if present.
#      Reported as source="home". Used by legacy installations that
#      shipped the manifest directly under ~/.claude/.
#   3. The newest semantic-versioned cache directory under
#      $HOME/.claude/plugins/cache/bytewyrd/bytewyrd/<version>/ that
#      contains bootstrap-manifest.json.
#      Reported as source="cache". This is the common case for users
#      who installed via `claude plugin install bytewyrd@bytewyrd`.
#   4. Otherwise: emit_error + exit 1.
#
# Selecting the "newest" cache directory uses `sort -V` (version sort) and
# picks the lexicographically-last entry. Pre-release suffixes (0.2.0-rc1)
# sort below their release (0.2.0) under -V, which matches semver intent.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object on success.
#     {
#       "plugin_root": "/abs/path/to/plugin/root",
#       "manifest":    "/abs/path/to/bootstrap-manifest.json",
#       "source":      "env" | "home" | "cache"
#     }
#   stderr: empty on success; JSON error envelope on failure.
#
# Exit codes:
#   0  Plugin root located.
#   1  No bootstrap-manifest.json found in any candidate location.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

emit_result() {
  local plugin_root="$1" manifest="$2" source="$3"
  jq -n \
    --arg plugin_root "$plugin_root" \
    --arg manifest "$manifest" \
    --arg source "$source" \
    '{plugin_root: $plugin_root, manifest: $manifest, source: $source}'
}

# 1. Environment override.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/bootstrap-manifest.json" ]; then
  emit_result "$CLAUDE_PLUGIN_ROOT" "$CLAUDE_PLUGIN_ROOT/bootstrap-manifest.json" "env"
  exit 0
fi

# 2. Home fallback (legacy install location).
home_root="${HOME:-/home/$(id -un 2>/dev/null)}/.claude"
if [ -f "$home_root/bootstrap-manifest.json" ]; then
  emit_result "$home_root" "$home_root/bootstrap-manifest.json" "home"
  exit 0
fi

# 3. Plugin cache (claude plugin install location).
cache_dir="$home_root/plugins/cache/bytewyrd/bytewyrd"
if [ -d "$cache_dir" ]; then
  # List directory entries, sort by version, walk newest -> oldest until we
  # find one with a manifest. This guards against half-installed versions.
  while IFS= read -r ver; do
    [ -z "$ver" ] && continue
    candidate="$cache_dir/$ver"
    if [ -f "$candidate/bootstrap-manifest.json" ]; then
      emit_result "$candidate" "$candidate/bootstrap-manifest.json" "cache"
      exit 0
    fi
  done < <(ls -1 "$cache_dir" 2>/dev/null | sort -V -r)
fi

# 4. Nothing matched.
emit_error "sync-find-plugin-root: bootstrap-manifest.json not found; install the bytewyrd plugin or set CLAUDE_PLUGIN_ROOT" >&2
exit 1
