#!/usr/bin/env bash
# Parse YAML frontmatter of an RFC file and emit a JSON object with field values.
# Used by: rfc-summary, rfc-approve, rfc-drop, rfc-consensus-review, rfc-implement, rfc-read-feedback.
#
# Args:
#   $1  Required. Path to an RFC file (.md). The first '---' line must be on line 1.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"rfc": "...", "title": "...", "author": "...", "status": "...",
#        "created": "...", "drop_reason": ""}
#       Keys parsed: rfc, title, author, status, created, drop_reason.
#       Missing fields are emitted as "" (empty string), so the consumer can always
#       count on a fixed set of keys. drop_reason is "" when the YAML value was `~`.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Parsed successfully (any subset of fields may have been present).
#   2  Usage error or file missing or no frontmatter found.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq
require_bash_major 4 # mapfile / associative arrays

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-frontmatter.sh <path-to-rfc.md>"
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  emit_error "rfc-frontmatter: file not found: $file"
  exit 2
fi

# Confirm the file opens with a frontmatter block.
if ! head -n1 "$file" | grep -q '^---$'; then
  emit_error "rfc-frontmatter: $file does not begin with a YAML frontmatter delimiter"
  exit 2
fi

# Parse fields into newline-separated key=value pairs, then convert to JSON via jq.
parsed="$(awk '
  # Drop the outer double quotes of a YAML double-quoted scalar and undo the two
  # escapes rfc-set-status.sh writes (backslash-backslash and backslash-quote).
  # Any other value keeps the old behaviour: every double quote is dropped.
  function unq(s,    n, i, c, d, out) {
    n = length(s)
    if (n >= 2 && substr(s, 1, 1) == "\"" && substr(s, n, 1) == "\"") {
      s = substr(s, 2, n - 2)
      n = n - 2
      out = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        d = substr(s, i + 1, 1)
        if (c == "\\" && (d == "\\" || d == "\"")) { out = out d; i++ }
        else out = out c
      }
      return out
    }
    gsub(/"/, "", s)
    return s
  }
  BEGIN { fm = 0; rfc=""; title=""; author=""; status=""; created=""; drop_reason="" }
  /^---$/ { fm++; if (fm == 2) exit; next }
  fm == 1 {
    if ($1 == "rfc:")         { sub(/^rfc: */, "");         rfc = unq($0) }
    else if ($1 == "title:")  { sub(/^title: */, "");       title = unq($0) }
    else if ($1 == "author:") { sub(/^author: */, "");      author = unq($0) }
    else if ($1 == "status:") { sub(/^status: */, "");      status = unq($0) }
    else if ($1 == "created:"){ sub(/^created: */, "");     created = unq($0) }
    else if ($1 == "drop_reason:") { sub(/^drop_reason: */, ""); drop_reason = unq($0) }
  }
  END {
    # drop_reason: "~" is the canonical "unset" sentinel — normalize to empty.
    if (drop_reason == "~") drop_reason = ""
    printf "%s\n%s\n%s\n%s\n%s\n%s\n", rfc, title, author, status, created, drop_reason
  }
' "$file")"

# Split parsed output into individual fields. Using mapfile for safety.
mapfile -t fields <<<"$parsed"
jq -n \
  --arg rfc "${fields[0]:-}" \
  --arg title "${fields[1]:-}" \
  --arg author "${fields[2]:-}" \
  --arg status "${fields[3]:-}" \
  --arg created "${fields[4]:-}" \
  --arg drop_reason "${fields[5]:-}" \
  '{rfc: $rfc, title: $title, author: $author, status: $status, created: $created, drop_reason: $drop_reason}'
