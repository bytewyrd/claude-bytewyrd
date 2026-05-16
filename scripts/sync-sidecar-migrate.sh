#!/usr/bin/env bash
# Migrate the bootstrap-versions sidecar from .claude/ to .bytewyrd/ — one-time.
# Used by: sync (Step 3 / Step 4 pre-flight).
#
# Idempotent: only acts when the old path exists AND the new path does not.
# Otherwise, does nothing and reports migrated=false.
#
# Args:
#   --old-path <path>   Optional. Default: ".claude/.bootstrap-versions.json"
#   --new-path <path>   Optional. Default: ".bytewyrd/.bootstrap-versions.json"
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"migrated": true|false, "old_path": "<path>", "new_path": "<path>", "message": "<human-readable>"}
#     error (exit 2):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Always (no-op is a normal result).
#   2  Bad arguments only.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

old_path=".claude/.bootstrap-versions.json"
new_path=".bytewyrd/.bootstrap-versions.json"

while [ $# -gt 0 ]; do
  case "$1" in
    --old-path)
      [ "${2:-}" = "" ] && { emit_error "sync-sidecar-migrate: --old-path requires a value"; exit 2; }
      old_path="$2"
      shift 2
      ;;
    --new-path)
      [ "${2:-}" = "" ] && { emit_error "sync-sidecar-migrate: --new-path requires a value"; exit 2; }
      new_path="$2"
      shift 2
      ;;
    *)
      emit_error "sync-sidecar-migrate: unknown argument: $1"
      exit 2
      ;;
  esac
done

emit_noop() {
  jq -n \
    --arg old "$old_path" \
    --arg new "$new_path" \
    --arg msg "$1" \
    '{migrated: false, old_path: $old, new_path: $new, message: $msg}'
}

# Case 1: old path missing — nothing to migrate.
if [ ! -f "$old_path" ]; then
  emit_noop "no migration needed: $old_path is absent"
  exit 0
fi

# Case 2: both old and new exist — do not overwrite; report and stop.
if [ -f "$new_path" ]; then
  emit_noop "no migration needed: $new_path already exists; old file kept in place"
  exit 0
fi

# Case 3: old exists, new does not — migrate.
new_dir="$(dirname "$new_path")"
mkdir -p "$new_dir"
cp "$old_path" "$new_path"
rm -f "$old_path"

jq -n \
  --arg old "$old_path" \
  --arg new "$new_path" \
  --arg msg "Migrated .bootstrap-versions.json: $old_path → $new_path" \
  '{migrated: true, old_path: $old, new_path: $new, message: $msg}'
exit 0
