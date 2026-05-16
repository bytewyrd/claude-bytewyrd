#!/usr/bin/env bash
# Generate a unified diff between two files with 3 lines of context,
# enumerating hunks for use in an `Accept with exclusions` checkbox list.
#
# Used by: sync (Step 4b — additive-merge-with-diff diff display).
#
# A "hunk" is one `@@ ... @@` block in the unified diff output. Each hunk is
# given a stable identifier (`hunk-1`, `hunk-2`, ...) and a one-line label
# derived from the first changed line in the hunk (truncated to 60 chars).
# This is the shape Claude Code needs to surface a multi-select for the
# `Accept with exclusions` flow.
#
# Args:
#   $1  Required. Path to the local file.
#   $2  Required. Path to the merged-content file.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"hunks": [{"id": "hunk-1", "label": "<first-changed-line-truncated>", "diff": "<unified diff of just this hunk>"}, ...],
#        "total_hunks": <int>,
#        "diff": "<full unified diff text>"}
#     error (exit 2):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Success (zero or more hunks).
#   2  Bad arguments or missing file.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  emit_error "usage: sync-unified-diff.sh <local-file> <merged-file>"
  exit 2
fi
local_file="$1"
merged_file="$2"

if [ ! -f "$local_file" ]; then
  emit_error "sync-unified-diff: local file not found: $local_file"
  exit 2
fi
if [ ! -f "$merged_file" ]; then
  emit_error "sync-unified-diff: merged file not found: $merged_file"
  exit 2
fi

# Use `diff -u` with 3 lines of context. `diff` exits 0 when files match,
# 1 when they differ, 2 on hard error.
diff_text="$(diff -U 3 "$local_file" "$merged_file" 2>/dev/null || true)"

if [ -z "$diff_text" ]; then
  jq -n '{hunks: [], total_hunks: 0, diff: ""}'
  exit 0
fi

# Split the diff into per-hunk pieces. Each hunk begins with a line starting
# with "@@ ". The header lines ("--- a/...", "+++ b/...") precede the first
# hunk and are not part of any hunk's `diff` field; we include them only in
# the `diff` field of the top-level object.

# Use awk to split: when we hit a "@@ " line, start a new hunk record.
# Per hunk:
#   - label = first line after `@@ ` whose first column is `-` or `+`
#             (excluding the `@@` header itself), trimmed and truncated.
#   - diff  = the `@@ ` header line and all body lines belonging to this hunk.

tmp_split="$(mktemp -d)"
trap 'rm -rf "$tmp_split"' EXIT

# Pre-pass: extract hunks into numbered files.
awk -v outdir="$tmp_split" '
  BEGIN {
    n = 0
    cur = ""
  }
  /^@@ / {
    n++
    cur = sprintf("%s/hunk-%d.diff", outdir, n)
    print > cur
    next
  }
  cur != "" {
    print >> cur
  }
' <<< "$diff_text"

# Build hunks JSON array.
hunks_json="[]"
n=0
for hunk_file in "$tmp_split"/hunk-*.diff; do
  [ -f "$hunk_file" ] || continue
  n=$((n + 1))
  # Build the full diff text for this hunk: the @@ line plus body.
  # The first line in the file is the @@ header (since awk wrote the header
  # then appended subsequent lines).
  # Find label: first line beginning with `-` or `+` (other than +++/---).
  label="$(awk '
    NR == 1 { next }  # skip the @@ header
    /^[-+]/ {
      line = $0
      # Strip leading sign char.
      first = substr(line, 1, 1)
      rest  = substr(line, 2)
      # Trim leading whitespace.
      sub(/^[[:space:]]+/, "", rest)
      print rest
      exit
    }
  ' "$hunk_file")"
  # Truncate to 60 characters.
  if [ ${#label} -gt 60 ]; then
    label="${label:0:57}..."
  fi
  hunk_diff="$(cat "$hunk_file")"
  id="hunk-$n"

  # Append to hunks_json via jq.
  hunks_json="$(echo "$hunks_json" | jq \
    --arg id "$id" \
    --arg label "$label" \
    --arg diff "$hunk_diff" \
    '. + [{id: $id, label: $label, diff: $diff}]')"
done

rm -rf "$tmp_split"
trap - EXIT

jq -n \
  --argjson hunks "$hunks_json" \
  --argjson total "$n" \
  --arg diff "$diff_text" \
  '{hunks: $hunks, total_hunks: $total, diff: $diff}'
exit 0
