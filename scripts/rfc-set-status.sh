#!/usr/bin/env bash
# Set the status (and optionally drop_reason) of an RFC's frontmatter in place.
# Used by: rfc-approve, rfc-drop, rfc-implement.
#
# Args:
#   $1  Required. Path to an RFC file (.md).
#   $2  Required. New status. Must be one of: Draft, Approved, Done, Dropped.
#   $3  Optional. Drop reason (one-sentence string). Required when $2 = "Dropped"; rejected otherwise.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"file": "...", "old_status": "Draft", "new_status": "Approved"}
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Success.
#   2  Usage error, invalid status value, drop_reason missing when transitioning to Dropped,
#      drop_reason provided when status != Dropped, file missing, or no status line found.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  emit_error "usage: rfc-set-status.sh <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"
  exit 2
fi
file="$1"
new_status="$2"
drop_reason="${3:-}"

case "$new_status" in
  Draft|Approved|Done|Dropped) ;;
  *) emit_error "rfc-set-status: invalid status '$new_status' (allowed: Draft, Approved, Done, Dropped)"; exit 2 ;;
esac

if [ "$new_status" = "Dropped" ] && [ -z "$drop_reason" ]; then
  emit_error "rfc-set-status: drop_reason is required when status=Dropped"
  exit 2
fi
if [ "$new_status" != "Dropped" ] && [ -n "$drop_reason" ]; then
  emit_error "rfc-set-status: drop_reason is only allowed when status=Dropped"
  exit 2
fi

if [ ! -f "$file" ]; then
  emit_error "rfc-set-status: file not found: $file"
  exit 2
fi

# Confirm the file opens with frontmatter and has a status line inside the first block.
old_status="$(awk '
  BEGIN { fm = 0 }
  /^---$/ { fm++; if (fm == 2) exit }
  fm == 1 && $1 == "status:" { sub(/^status: */, ""); gsub(/"/, ""); print; exit }
' "$file")"

if [ -z "$old_status" ]; then
  emit_error "rfc-set-status: $file has no 'status:' line in its frontmatter"
  exit 2
fi

# Escape drop_reason for safe embedding in a YAML double-quoted string.
# Order matters: escape backslashes first, then double quotes.
escaped_reason="${drop_reason//\\/\\\\}"   # \ -> \\
escaped_reason="${escaped_reason//\"/\\\"}"  # " -> \"
# Reject newlines — YAML double-quoted scalars cannot contain raw newlines safely
# without folding, and a single-line drop_reason is the documented contract.
case "$escaped_reason" in
  *$'\n'*) emit_error "rfc-set-status: drop_reason must not contain newlines"; exit 2 ;;
esac

# Use awk to rewrite the 'status:' line inside the first frontmatter block.
# If the new status is Dropped:
#   - rewrite an existing 'drop_reason:' line if present
#   - otherwise inject 'drop_reason: "..."' immediately before the closing '---'
# If the new status is not Dropped: rewrite an existing drop_reason to '~'.
# This avoids touching any later occurrence inside the document body.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -v new_status="$new_status" -v drop_reason="$escaped_reason" '
  BEGIN { fm = 0; wrote_dr = 0 }
  /^---$/ {
    fm++
    # Before closing delimiter, inject drop_reason if not already written.
    if (fm == 2 && new_status == "Dropped" && !wrote_dr) {
      print "drop_reason: \"" drop_reason "\""
      wrote_dr = 1
    }
    print; next
  }
  fm == 1 && $1 == "status:" { print "status: \"" new_status "\""; next }
  fm == 1 && $1 == "drop_reason:" {
    if (new_status == "Dropped") { print "drop_reason: \"" drop_reason "\"" }
    else                          { print "drop_reason: ~" }
    wrote_dr = 1
    next
  }
  { print }
' "$file" > "$tmp"

cat "$tmp" > "$file"
rm -f "$tmp"
trap - EXIT

jq -n --arg file "$file" --arg old "$old_status" --arg new "$new_status" \
  '{file: $file, old_status: $old, new_status: $new}'
exit 0
