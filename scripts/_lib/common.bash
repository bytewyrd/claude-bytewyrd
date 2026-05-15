#!/usr/bin/env bash
# Shared helpers for scripts/*.sh.
# Source early in each script:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
#   require_jq
#
# This file must not set -e / -o pipefail — callers own their strict-mode
# posture. It is safe under set -u (no unset-var refs).

# require_jq — exit 2 with a static JSON error if jq is not on PATH.
# Call once, immediately after sourcing this file.
require_jq() {
  command -v jq >/dev/null 2>&1 || {
    printf '{"error":"jq not found on PATH"}\n'
    exit 2
  }
}

# emit_error <message>
emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

# emit_available <name>
emit_available() {
  jq -n --arg name "$1" '{result: "available", name: $name}'
}

# emit_missing <name> <hint>
emit_missing() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "missing", name: $name, hint: $hint}'
}

# emit_unauth <name> <hint>
emit_unauth() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "unauthenticated", name: $name, hint: $hint}'
}

# plugin_enabled <plugin-id>
# Returns 0 if enabled, 1 if explicitly disabled or not found.
# Precedence: project-false > project-true > user-true.
plugin_enabled() {
  local id="$1"
  local user_settings="$HOME/.claude/settings.json"
  local proj_settings=".claude/settings.json"
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*false" "$proj_settings"; then return 1; fi
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true"  "$proj_settings"; then return 0; fi
  if [ -f "$user_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true"  "$user_settings"; then return 0; fi
  return 1
}
