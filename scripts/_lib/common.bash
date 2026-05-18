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

# hash_string <string> — output full sha256 hex of the string (cross-platform)
hash_string() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

# compute_upstream_key <manifest-entry-json>
# Output: bytewyrd/<target>@<8-char fingerprint>
#
# The fingerprint is sha256[:8] of the canonical JSON of extension_strategy +
# strategy config (owned_paths, owned_sections, owned_boundaries). Template
# content is deliberately excluded: content changes are tracked by the sha12
# in the marker; the key only needs to capture ownership semantics. When
# strategy or config changes the fingerprint changes, invalidating existing
# consumer markers and forcing a legacy re-classification on the next /sync.
compute_upstream_key() {
  local entry="$1"
  local target fingerprint_input fingerprint
  target="$(printf '%s' "$entry" | jq -r '.target')"
  fingerprint_input="$(printf '%s' "$entry" | jq -Sc '{
    extension_strategy,
    owned_boundaries: (.owned_boundaries // []),
    owned_paths:      (.owned_paths      // [] | sort),
    owned_sections:   (.owned_sections   // [] | sort)
  }')"
  fingerprint="$(hash_string "$fingerprint_input" | cut -c1-8)"
  printf 'bytewyrd/%s@%s' "$target" "$fingerprint"
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
