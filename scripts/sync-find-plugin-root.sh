#!/usr/bin/env bash
# Locate the bytewyrd plugin root containing bootstrap-manifest.json.
# Used by: skills/sync/SKILL.md (Step 4 — plugin-root discovery).
#
# This script is a thin wrapper around `find_plugin_root` in
# scripts/_lib/plugin.bash — that function holds the authoritative
# resolution logic and is also called directly from sync-preflight.sh.
#
# Resolution order (from _lib/plugin.bash):
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
# shellcheck source=_lib/plugin.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/plugin.bash"
require_jq

if ! find_plugin_root; then
  emit_error "$PLUGIN_ROOT_ERROR" >&2
  exit 1
fi

jq -n \
  --arg plugin_root "$PLUGIN_ROOT" \
  --arg manifest "$PLUGIN_MANIFEST" \
  --arg source "$PLUGIN_SOURCE" \
  '{plugin_root: $plugin_root, manifest: $manifest, source: $source}'
