#!/usr/bin/env bash
# List bullet entries from docs/rfc-braindump.md as a JSON array of {n, body} objects.
# Used by: rfc-new (step 1 braindump selection).
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0 always):
#       {"entries": [{"n": 1, "body": "<body-without-leading-star-space>"}, ...]}
#       Empty array when file absent or no bullet entries.
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Listing completed (zero or more entries).
#   (never exits non-zero — absence of entries is not an error)

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

file="docs/rfc-braindump.md"

if [ ! -f "$file" ]; then
  jq -n '{entries: []}'
  exit 0
fi

# Collect bodies in file order.
bodies=()
while IFS= read -r line; do
  case "$line" in
    '* '*)
      body="${line#\* }"
      bodies+=("$body")
      ;;
  esac
done < "$file"

entries_array="$(
  if [ "${#bodies[@]}" -eq 0 ]; then
    printf '[]'
  else
    # Use jq to build the array with 1-based indices.
    printf '%s\n' "${bodies[@]}" \
      | jq -R . \
      | jq -s 'to_entries | map({n: (.key + 1), body: .value})'
  fi
)"

jq -n --argjson entries "$entries_array" '{entries: $entries}'
exit 0
