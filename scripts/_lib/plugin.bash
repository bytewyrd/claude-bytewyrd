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
#   3. A cache directory under
#      $HOME/.claude/plugins/cache/bytewyrd/bytewyrd/<version>/ that
#      contains bootstrap-manifest.json.
#      Reported as source="cache". This is the common case for users
#      who installed via `claude plugin install bytewyrd@bytewyrd`.
#
# Choosing the cache directory. plugin.json carries no `version`, so Claude
# Code names each cache directory after a commit SHA, and an update leaves the
# previous directory behind (marked with an `.orphaned_at` file) until a
# cleanup about 14 days later. A version sort cannot tell which SHA is
# current, so:
#   a. If this library is itself loaded from a cache directory, use that
#      directory: it is the version that is running.
#   b. Otherwise walk the directories newest -> oldest by `sort -V`, skipping
#      ones marked `.orphaned_at`, and pick the first that contains a
#      manifest (guards against half-installed versions).
#   c. If every directory with a manifest is orphaned, fall back to (b)
#      without skipping, as before.
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
    # 3a. The running copy: this file is <root>/scripts/_lib/plugin.bash.
    local self_root cache_real
    self_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"
    cache_real="$(cd "$cache_dir" 2>/dev/null && pwd -P)"
    if [ -n "$self_root" ] && [ -n "$cache_real" ] \
        && [ "$(dirname "$self_root")" = "$cache_real" ] \
        && [ -f "$self_root/bootstrap-manifest.json" ]; then
      PLUGIN_ROOT="$cache_dir/$(basename "$self_root")"
      PLUGIN_MANIFEST="$PLUGIN_ROOT/bootstrap-manifest.json"
      PLUGIN_SOURCE="cache"
      return 0
    fi

    # 3b/3c. Walk newest -> oldest by version sort until one has a manifest:
    # first skipping directories Claude Code marked orphaned, then not.
    local pass ver candidate
    for pass in live any; do
      while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        candidate="$cache_dir/$ver"
        if [ "$pass" = "live" ] && [ -e "$candidate/.orphaned_at" ]; then
          continue
        fi
        if [ -f "$candidate/bootstrap-manifest.json" ]; then
          PLUGIN_ROOT="$candidate"
          PLUGIN_MANIFEST="$candidate/bootstrap-manifest.json"
          PLUGIN_SOURCE="cache"
          return 0
        fi
      done < <(ls -1 "$cache_dir" 2>/dev/null | sort -V -r)
    done
  fi

  # 4. Nothing matched.
  PLUGIN_ROOT_ERROR="sync-find-plugin-root: bootstrap-manifest.json not found; install the bytewyrd plugin or set CLAUDE_PLUGIN_ROOT"
  return 1
}
