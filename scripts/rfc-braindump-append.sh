#!/usr/bin/env bash
# Append a bullet entry to docs/rfc-braindump.md.
# Creates the file with the standard header if absent.
# Used by: rfc-braindump (step 4).
#
# Args:
#   $1  Required. The full bullet body, *excluding* the leading "* " marker.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"appended": true, "file": "docs/rfc-braindump.md", "created_file": <true|false>}
#       `created_file` is true when the file did not previously exist.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Entry appended.
#   2  Usage error.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-braindump-append.sh <full-bullet-body-without-leading-star-space>"
  exit 2
fi
body="$1"
file="docs/rfc-braindump.md"

created_file=false
if [ ! -f "$file" ]; then
  printf '# RFC Braindump\n\nPotential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.\n\n' > "$file"
  created_file=true
fi

printf '* %s\n' "$body" >> "$file"

jq -n --arg file "$file" --argjson created "$created_file" \
  '{appended: true, file: $file, created_file: $created}'
exit 0
