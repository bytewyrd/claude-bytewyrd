#!/usr/bin/env bash
# Plugin-root resolution helpers for scripts/*.sh.
# Source early in each script that needs to locate the bytewyrd plugin checkout:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/plugin.bash"
#
# This file must not set -e / -o pipefail — callers own their strict-mode
# posture (see _lib/common.bash for the same convention). It is safe under
# set -u (no unset-var refs).

# find_plugin_root
#
# Locate the bytewyrd plugin root containing bootstrap-manifest.json.
#
# Resolution order:
#   1. $CLAUDE_PLUGIN_ROOT if set AND its bootstrap-manifest.json exists.
#      Reported as source="env". Used when developers point at a checkout
#      of the plugin instead of the cached install.
#   2. $HOME/.claude/bootstrap-manifest.json if it exists.
#      Reported as source="home". Used by legacy installations that
#      shipped the manifest directly under ~/.claude/.
#   3. The newest semantic-versioned cache directory under
#      $HOME/.claude/plugins/cache/bytewyrd/bytewyrd/<version>/ that
#      contains bootstrap-manifest.json.
#      Reported as source="cache". This is the common case for users
#      who installed via `claude plugin install bytewyrd@bytewyrd`.
#
# Selecting the "newest" cache directory uses `sort -V` (version sort)
# and walks newest -> oldest, picking the first directory that actually
# contains a manifest (guards against half-installed versions).
#
# On success, sets:
#   PLUGIN_ROOT      — absolute path to the directory containing the manifest
#   PLUGIN_MANIFEST  — absolute path to the bootstrap-manifest.json file
#   PLUGIN_SOURCE    — one of "env", "home", "cache"
# Returns 0.
#
# On failure (no manifest found anywhere), sets:
#   PLUGIN_ROOT_ERROR — human-readable error message
# Returns 1.
find_plugin_root() {
  PLUGIN_ROOT=""
  PLUGIN_MANIFEST=""
  PLUGIN_SOURCE=""
  PLUGIN_ROOT_ERROR=""

  # 1. Environment override.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/bootstrap-manifest.json" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
    PLUGIN_MANIFEST="$CLAUDE_PLUGIN_ROOT/bootstrap-manifest.json"
    PLUGIN_SOURCE="env"
    return 0
  fi

  # 2. Home fallback (legacy install location).
  local home_root="${HOME:-/home/$(id -un 2>/dev/null)}/.claude"
  if [ -f "$home_root/bootstrap-manifest.json" ]; then
    PLUGIN_ROOT="$home_root"
    PLUGIN_MANIFEST="$home_root/bootstrap-manifest.json"
    PLUGIN_SOURCE="home"
    return 0
  fi

  # 3. Plugin cache (claude plugin install location).
  local cache_dir="$home_root/plugins/cache/bytewyrd/bytewyrd"
  if [ -d "$cache_dir" ]; then
    # List directory entries, sort by version, walk newest -> oldest until we
    # find one with a manifest. This guards against half-installed versions.
    local ver candidate
    while IFS= read -r ver; do
      [ -z "$ver" ] && continue
      candidate="$cache_dir/$ver"
      if [ -f "$candidate/bootstrap-manifest.json" ]; then
        PLUGIN_ROOT="$candidate"
        PLUGIN_MANIFEST="$candidate/bootstrap-manifest.json"
        PLUGIN_SOURCE="cache"
        return 0
      fi
    done < <(ls -1 "$cache_dir" 2>/dev/null | sort -V -r)
  fi

  # 4. Nothing matched.
  PLUGIN_ROOT_ERROR="sync-find-plugin-root: bootstrap-manifest.json not found; install the bytewyrd plugin or set CLAUDE_PLUGIN_ROOT"
  return 1
}
