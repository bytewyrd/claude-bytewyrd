#!/usr/bin/env bash
# Check whether docs/rfc-process.md has a non-placeholder "## Project Extensions" section.
# Used by: sync (migration-time warning before docs/rfc-process.md authoritative_update).
#
# A non-placeholder section means the body (after trimming) is something other than:
#   - empty
#   - the literal placeholder: *(no project-specific extensions — the global process applies as-is)*
#
# Args:
#   $1  Optional. Path to the RFC process file. Default: docs/rfc-process.md
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"has_extensions": true,  "body": "<section body>", "file": "<path>"}
#       {"has_extensions": false, "body": null,             "file": "<path>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Always (has_extensions=false is a normal result; file absence is also normal).

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

file="${1:-docs/rfc-process.md}"

emit_no() {
  jq -n --arg file "$file" '{has_extensions: false, body: null, file: $file}'
}

if [ ! -f "$file" ]; then
  emit_no
  exit 0
fi

# Extract the body of the "## Project Extensions" section: every line after the
# heading up to the next H2/H1 or EOF. Preserve internal blank lines but trim
# leading and trailing blank lines for comparison.
body="$(awk '
  BEGIN { in_section = 0 }
  /^## Project Extensions[[:space:]]*$/ { in_section = 1; next }
  in_section == 1 {
    # End on next sibling heading.
    if ($0 ~ /^## / || $0 ~ /^# /) { exit }
    print
  }
' "$file")"

# Trim leading/trailing blank lines.
trimmed="$(printf '%s' "$body" | awk '
  BEGIN { started = 0; buf = "" }
  {
    if (started == 0 && $0 ~ /^[[:space:]]*$/) next
    started = 1
    if (buf == "") buf = $0
    else            buf = buf "\n" $0
  }
  END {
    # Trim trailing blanks.
    sub(/[[:space:]\n]+$/, "", buf)
    printf "%s", buf
  }
')"

placeholder='*(no project-specific extensions — the global process applies as-is)*'

if [ -z "$trimmed" ] || [ "$trimmed" = "$placeholder" ]; then
  emit_no
  exit 0
fi

jq -n --arg file "$file" --arg body "$trimmed" \
  '{has_extensions: true, body: $body, file: $file}'
exit 0
