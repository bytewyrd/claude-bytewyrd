#!/usr/bin/env bash
# Remove a single bullet entry from docs/rfc-braindump.md whose body matches the argument.
# Used by: rfc-new (after promoting a braindump entry to a full RFC).
#
# Args:
#   $1  Required. The full bullet body to match, *excluding* the leading "* " marker.
#       Whitespace is matched literally; the script does not strip.
#
# Output:
#   stdout: a single JSON object.
#     removed (exit 0):
#       {"removed": true, "file": "docs/rfc-braindump.md"}
#     not found (exit 1):
#       {"removed": false, "file": "docs/rfc-braindump.md"}
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  One entry removed.
#   1  Zero entries matched (no-op).
#   2  Usage error or docs/rfc-braindump.md missing.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-braindump-remove.sh <full-bullet-body-without-leading-star-space>"
  exit 2
fi
body="$1"
file="docs/rfc-braindump.md"

if [ ! -f "$file" ]; then
  emit_error "rfc-braindump-remove: $file not found"
  exit 2
fi

# Compose the exact line to match: "* <body>".
target="* $body"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# awk consumes the line equal to $target exactly once; subsequent matches (if any) are kept.
removed=0
awk -v target="$target" '
  BEGIN { done = 0 }
  {
    if (!done && $0 == target) { done = 1; next }
    print
  }
  END { exit (done ? 0 : 1) }
' "$file" > "$tmp" && removed=1 || removed=0

if [ "$removed" -eq 0 ]; then
  rm -f "$tmp"
  trap - EXIT
  jq -n --arg file "$file" '{removed: false, file: $file}'
  exit 1
fi

cat "$tmp" > "$file"
rm -f "$tmp"
trap - EXIT
jq -n --arg file "$file" '{removed: true, file: $file}'
exit 0
