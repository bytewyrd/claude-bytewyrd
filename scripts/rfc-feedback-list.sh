#!/usr/bin/env bash
# List every "FEEDBACK:" marker line in an RFC file as a JSON array of {line, text} objects.
# Used by: rfc-read-feedback.
#
# Args:
#   $1  Required. Path to an RFC file (.md).
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"markers": [{"line": 3, "text": "FEEDBACK: Add a step for X."}, ...]}
#       Empty array when no markers found. `text` is the full line including the
#       `FEEDBACK:` prefix and any leading whitespace / markdown list characters.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Matching:
#   The grep pattern is `^\s*[-*>]*\s*FEEDBACK:`, which catches the marker at any
#   indentation level — column 0, indented, inside a `-` or `*` bullet (including
#   nested), and inside a `>` blockquote. The full matched line text (with its
#   original indentation and list/blockquote prefix) is preserved in `text`.
#
# Exit codes:
#   0  Listing completed (zero or more markers found).
#   2  Usage error or file missing.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-feedback-list.sh <path-to-rfc.md>"
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  emit_error "rfc-feedback-list: file not found: $file"
  exit 2
fi

# Collect (line, text) tuples. grep prints "<lineno>:<line>"; split on the first colon.
# Pattern matches `FEEDBACK:` at any indentation — column 0, leading whitespace,
# inside `-`/`*` bullets (including nested), and inside `>` blockquotes.
#
# grep exits 1 when no lines match; this causes pipefail to trigger. We capture the
# raw grep output first (with `|| true` to absorb the non-match exit code), then
# feed it through awk+jq in a separate step. This avoids the double-[] artifact
# that occurs when the pipeline fails and `|| printf '[]'` fires alongside jq output.
grep_out="$(grep -n '^\s*[-*>]*\s*FEEDBACK:' "$file" 2>/dev/null || true)"

if [ -z "$grep_out" ]; then
  markers_json='[]'
else
  markers_json="$(
    printf '%s\n' "$grep_out" \
      | awk -F: '{
          n = $1
          # Reconstruct the line text by stripping the leading "<lineno>:".
          sub(/^[0-9]+:/, "")
          printf "%s\t%s\n", n, $0
        }' \
      | jq -R -s 'split("\n") | map(select(length > 0)) | map(
          split("\t") | {line: (.[0] | tonumber), text: .[1]}
        )'
  )"
fi

jq -n --argjson markers "$markers_json" '{markers: $markers}'
exit 0
