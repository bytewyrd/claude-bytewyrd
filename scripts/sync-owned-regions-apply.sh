#!/usr/bin/env bash
# Apply an owned-regions merge: for each boundary, replace the body of the
# matching heading in the local file with the body from the plugin source.
#
# Used by: sync (Step 5 — `owned-regions` apply action).
#
# Rules:
#   * For each `{type:"heading", heading: "## Name"}` boundary:
#     - Find the heading in the local file. Take everything between this
#       heading and the next H2/H1 or EOF — the "owned slice".
#     - Find the same heading in the plugin source. Take its slice.
#     - Replace the local slice with the plugin slice.
#   * Content outside owned boundaries is preserved exactly.
#   * If a plugin-owned heading is absent from the local file, insert it
#     after the last preceding owned heading that *is* present.
#   * If none of the preceding owned headings are present either, append the
#     new heading at the end of the file.
#
# Args:
#   $1  Required. Path to the local file.
#   $2  Required. Path to the plugin source file (already rendered if templated).
#   $3  Required. JSON array of boundary objects [{"type":"heading","heading":"## X"}].
#
# Output:
#   stdout: the merged file content (raw, not JSON).
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Success.
#   2  Usage error, missing file, or malformed boundaries JSON.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ] || [ "${3:-}" = "" ]; then
  emit_error "usage: sync-owned-regions-apply.sh <local-file> <plugin-source> <boundaries-json>"
  exit 2
fi
local_file="$1"
plugin_file="$2"
boundaries_json="$3"

if [ ! -f "$local_file" ]; then
  emit_error "sync-owned-regions-apply: local file not found: $local_file"
  exit 2
fi
if [ ! -f "$plugin_file" ]; then
  emit_error "sync-owned-regions-apply: plugin source not found: $plugin_file"
  exit 2
fi

if ! echo "$boundaries_json" | jq -e 'type == "array"' >/dev/null; then
  emit_error "sync-owned-regions-apply: boundaries must be a JSON array"
  exit 2
fi

# Extract the list of headings, in manifest order.
mapfile -t headings < <(
  echo "$boundaries_json" | jq -r '.[].heading'
)

# Read plugin slice for a heading: the line `<heading>` plus every line until
# the next H2/H1 or EOF. Trailing newline characters preserved as-is.
plugin_slice_for() {
  local heading="$1"
  awk -v target="$heading" '
    BEGIN { in_section = 0 }
    {
      if ($0 == target) {
        in_section = 1
        print
        next
      }
      if (in_section == 1) {
        if ($0 ~ /^## / || $0 ~ /^# /) {
          exit
        }
        print
      }
    }
  ' "$plugin_file"
}

# Replace the local slice for each owned heading with the plugin slice.
# When a heading is absent locally, insert after the last preceding owned
# heading that exists, or at EOF if none exist.

# Step 1 — load local content as a numbered line array.
mapfile -t local_lines < "$local_file"
local_count="${#local_lines[@]}"

# Step 2 — find heading positions in the local file (1-based for clarity).
# Map heading => line number; absent headings will not be in the map.
declare -A heading_line_local=()
for ((i = 0; i < local_count; i++)); do
  line="${local_lines[$i]}"
  for h in "${headings[@]}"; do
    if [ "$line" = "$h" ]; then
      heading_line_local["$h"]="$i"
    fi
  done
done

# Step 3 — find the end line of each owned heading's section (the line BEFORE
# the next H2/H1 or EOF).
declare -A heading_end_local=()
for h in "${headings[@]}"; do
  start="${heading_line_local[$h]:-}"
  if [ -z "$start" ]; then continue; fi
  end="$local_count"
  for ((i = start + 1; i < local_count; i++)); do
    line="${local_lines[$i]}"
    if [[ "$line" =~ ^##\ .* ]] || [[ "$line" =~ ^#\ .* ]]; then
      end="$i"
      break
    fi
  done
  heading_end_local["$h"]="$end"
done

# Step 4 — walk the headings list and build "replace" actions plus an
# "insert" list for absent headings. Insertions go after the last preceding
# present heading's end-of-section; if none precede, after EOF.
# Build the merged output in-memory.

# Strategy:
#  - Iterate local lines.
#  - When we hit a present owned heading at index `start`:
#       Skip lines [start, end). Emit the plugin slice for that heading.
#       Set cursor to `end`.
#  - Otherwise: emit the local line.
#  - After the walk: for each absent owned heading, find the insertion point
#    (the end-of-section of the previous present owned heading) and slice in
#    the plugin block. Construct the final output by splicing.

# Build the list of present owned headings in *file* order (sorted by their
# starting line in the local file).
present_in_file_order=()
while IFS= read -r h; do
  present_in_file_order+=("$h")
done < <(
  for h in "${headings[@]}"; do
    start="${heading_line_local[$h]:-}"
    if [ -n "$start" ]; then
      printf '%s\t%s\n' "$start" "$h"
    fi
  done | sort -n | awk -F'\t' '{print $2}'
)

# Build a map of insertion points: heading => insertion-line-index.
# For each absent heading H, walk backwards in manifest order to find the most
# recent preceding present heading P. Insertion point = heading_end_local[P].
# If none precede, insertion point = local_count (append to end of file).
declare -A insert_after=()
prev_present=""
for h in "${headings[@]}"; do
  if [ -n "${heading_line_local[$h]:-}" ]; then
    prev_present="$h"
    continue
  fi
  # Absent heading — record insertion point.
  if [ -n "$prev_present" ]; then
    insert_after["$h"]="${heading_end_local[$prev_present]}"
  else
    insert_after["$h"]="$local_count"
  fi
done

# Build merged content. We emit local lines in order, substituting plugin
# slices when we hit a present owned heading; we also emit insertions of
# absent headings at their resolved positions.

# Build a per-line "inserts_before" list: at line N, which absent headings
# should be emitted before processing line N (or after the current line for
# inserts at EOF, i.e. N == local_count).
declare -A inserts_at=()  # key = numeric position; value = newline-separated headings
for h in "${headings[@]}"; do
  pos="${insert_after[$h]:-}"
  if [ -z "$pos" ]; then continue; fi
  existing="${inserts_at[$pos]:-}"
  if [ -z "$existing" ]; then
    inserts_at["$pos"]="$h"
  else
    inserts_at["$pos"]="${existing}"$'\n'"$h"
  fi
done

emit_plugin_slice() {
  local h="$1"
  plugin_slice_for "$h"
}

# Walk lines.
cursor=0
while [ "$cursor" -lt "$local_count" ]; do
  # Check if we need to emit insertions before this line.
  ins="${inserts_at[$cursor]:-}"
  if [ -n "$ins" ]; then
    while IFS= read -r h; do
      emit_plugin_slice "$h"
    done <<< "$ins"
    unset 'inserts_at['"$cursor"']'
  fi

  line="${local_lines[$cursor]}"
  # Is this line a present owned heading?
  is_owned=""
  for h in "${headings[@]}"; do
    start="${heading_line_local[$h]:-}"
    if [ -n "$start" ] && [ "$start" -eq "$cursor" ]; then
      is_owned="$h"
      break
    fi
  done
  if [ -n "$is_owned" ]; then
    end="${heading_end_local[$is_owned]}"
    # Skip the local slice.
    emit_plugin_slice "$is_owned"
    cursor="$end"
    continue
  fi
  # Plain local line.
  printf '%s\n' "$line"
  cursor=$((cursor + 1))
done

# Handle any insertions at the EOF position.
ins="${inserts_at[$local_count]:-}"
if [ -n "$ins" ]; then
  while IFS= read -r h; do
    emit_plugin_slice "$h"
  done <<< "$ins"
fi

exit 0
