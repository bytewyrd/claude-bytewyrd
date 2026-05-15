#!/usr/bin/env bash
# Emit a JSON object listing every RFC's frontmatter, sorted by created then rfc.
# Used by: rfc-summary.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"rfcs": [{"status": "...", "created": "...", "rfc": "...", "title": "...", "author": "..."}],
#        "warnings": ["<per-file warning text>"]}
#       `rfcs` is sorted ascending by `created` then `rfc`.
#       `warnings` is an empty array when all files parse cleanly. Exit 0 even when warnings are present.
#     error (exit 2 — no docs/rfcs/ dir):
#       {"error": "no docs/rfcs/ directory in <cwd>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Iteration completed (zero or more rows produced; warnings may be present).
#   2  docs/rfcs/ does not exist.

set -uo pipefail
# shellcheck source=_lib/common.bash
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_LIB_DIR/_lib/common.bash"
require_jq

FRONTMATTER_SH="$_LIB_DIR/rfc-frontmatter.sh"

if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "no docs/rfcs/ directory in $(pwd)" '{error: $msg}'
  exit 2
fi

# Accumulators: one JSON object per row, one string per warning.
rows_json=()
warnings=()

for f in docs/rfcs/*.md; do
  [ -f "$f" ] || continue
  # rfc-frontmatter exits 2 on a file that has no frontmatter; tolerate that here
  # and record a per-file warning rather than aborting the whole listing.
  if ! out="$(bash "$FRONTMATTER_SH" "$f" 2>/dev/null)"; then
    warnings+=("Warning: $f — frontmatter unparseable; skipping.")
    continue
  fi
  # Extract each field via jq -r.
  rfc="$(printf '%s' "$out"     | jq -r .rfc)"
  title="$(printf '%s' "$out"   | jq -r .title)"
  author="$(printf '%s' "$out"  | jq -r .author)"
  status="$(printf '%s' "$out"  | jq -r .status)"
  created="$(printf '%s' "$out" | jq -r .created)"
  if [ -z "$rfc" ] || [ -z "$status" ]; then
    warnings+=("Warning: $f — frontmatter incomplete; skipping.")
    continue
  fi
  case "$status" in
    Draft|Approved|Done|Dropped) ;;
    *) warnings+=("Warning: $f — unrecognized status \"$status\"; skipping."); continue ;;
  esac
  row="$(jq -n \
    --arg status "$status" --arg created "$created" --arg rfc "$rfc" \
    --arg title "$title"   --arg author  "$author" \
    '{status: $status, created: $created, rfc: $rfc, title: $title, author: $author}')"
  rows_json+=("$row")
done

# Combine rows into a JSON array, sort by (created, rfc), then assemble final object.
rows_array="$(
  if [ "${#rows_json[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${rows_json[@]}" | jq -s 'sort_by(.created, .rfc)'
  fi
)"

warnings_array="$(
  if [ "${#warnings[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .
  fi
)"

jq -n --argjson rfcs "$rows_array" --argjson warnings "$warnings_array" \
  '{rfcs: $rfcs, warnings: $warnings}'
exit 0
