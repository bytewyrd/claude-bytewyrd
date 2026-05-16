#!/usr/bin/env bash
# Parse a section body from stdin into discrete items.
# Used by: sync (additive-merge algorithm Step A — item extraction).
#
# Supported file types:
#
# * markdown
#   - A top-level bullet (`- `, `* `, or `1. `) starts a new item.
#     Sub-bullets (indented bullets) and continuation lines travel with
#     their parent until the next top-level bullet or paragraph boundary.
#   - A code fence (` ``` ` or `~~~`) starts a code-block item. The item
#     spans from the opening fence to the matching closing fence and is
#     emitted as type "codeblock".
#   - Otherwise, each standalone paragraph (text separated by one or more
#     blank lines) is one item of type "paragraph".
#
# * yaml
#   - Each top-level YAML key (line where column 0 is non-whitespace and
#     contains `:`) starts a new item of type "yaml-key". Indented lines
#     belong to the most recent top-level key. Standalone comment lines
#     attach to the next key.
#
# Args (stdin = file content):
#   --section <heading>   Optional. When provided, only the body under that
#                          heading is parsed (heading + body to next H2/H1 or
#                          EOF). When omitted, the whole stdin is parsed.
#   <file-type>           Required positional argument. One of: markdown, yaml.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"items": [{"index": 0, "text": "<content>", "type": "bullet|paragraph|codeblock|yaml-key"}],
#        "section": "<heading or null>",
#        "file_type": "<type>"}
#     error (exit 2):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Success (zero or more items).
#   2  Bad arguments or unknown file type.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

section_arg=""
file_type=""
while [ $# -gt 0 ]; do
  case "$1" in
    --section)
      [ "${2:-}" = "" ] && { emit_error "sync-item-parser: --section requires a value"; exit 2; }
      section_arg="$2"; shift 2
      ;;
    -*)
      emit_error "sync-item-parser: unknown option: $1"; exit 2
      ;;
    *)
      if [ -z "$file_type" ]; then
        file_type="$1"; shift
      else
        emit_error "sync-item-parser: unexpected extra argument: $1"; exit 2
      fi
      ;;
  esac
done

if [ -z "$file_type" ]; then
  emit_error "usage: sync-item-parser.sh <markdown|yaml> [--section <heading>]"
  exit 2
fi

case "$file_type" in
  markdown|yaml) ;;
  *) emit_error "sync-item-parser: unknown file_type: $file_type"; exit 2 ;;
esac

# Read all of stdin into a temp file (we may need multiple passes).
tmp_in="$(mktemp)"
trap 'rm -f "$tmp_in"' EXIT
cat > "$tmp_in"

# Step 1 — Slice section body if --section was given.
tmp_body="$tmp_in"
if [ -n "$section_arg" ]; then
  tmp_body="$(mktemp)"
  trap 'rm -f "$tmp_in" "$tmp_body"' EXIT
  awk -v target="$section_arg" '
    BEGIN { in_section = 0 }
    {
      if ($0 == target) { in_section = 1; next }
      if (in_section == 1) {
        if ($0 ~ /^## / || $0 ~ /^# /) { exit }
        print
      }
    }
  ' "$tmp_in" > "$tmp_body"
fi

# Step 2 — Parse items based on file_type.
items_jsonl="$(mktemp)"
trap 'rm -f "$tmp_in" "$tmp_body" "$items_jsonl"' EXIT

# Use a record separator that is unlikely to appear in source text: ASCII RS
# (0x1e) between type and text, and ASCII GS (0x1d) between records.
RS=$'\x1e'
GS=$'\x1d'

if [ "$file_type" = "markdown" ]; then
  # Walk lines, emit one record per item using control-char separators.
  awk -v outfile="$items_jsonl" -v RS_CHAR="$RS" -v GS_CHAR="$GS" '
    function flush_buf(type,    text) {
      if (buf == "") return
      text = buf
      sub(/\n+$/, "", text)
      printf "%s%s%s%s", type, RS_CHAR, text, GS_CHAR >> outfile
      buf = ""
    }
    function append(line) {
      if (buf == "") buf = line
      else           buf = buf "\n" line
    }
    BEGIN {
      buf = ""
      cur_type = ""  # "bullet" | "paragraph" | "codeblock" | ""
      in_fence = 0
      fence_marker = ""
    }
    {
      line = $0
      # Code fence handling.
      if (in_fence == 1) {
        append(line)
        if (line == fence_marker) {
          flush_buf("codeblock")
          cur_type = ""
          in_fence = 0
          fence_marker = ""
        }
        next
      }
      if (line ~ /^```/ || line ~ /^~~~/) {
        if (cur_type != "") flush_buf(cur_type)
        cur_type = "codeblock"
        in_fence = 1
        if (line ~ /^```/) fence_marker = "```"; else fence_marker = "~~~"
        buf = line
        next
      }
      # Blank line.
      if (line ~ /^[[:space:]]*$/) {
        if (cur_type != "") flush_buf(cur_type)
        cur_type = ""
        next
      }
      # Top-level bullet.
      if (line ~ /^- / || line ~ /^\* / || line ~ /^[0-9]+\. /) {
        if (cur_type != "" && cur_type != "bullet") flush_buf(cur_type)
        if (cur_type == "bullet") flush_buf("bullet")
        cur_type = "bullet"
        buf = line
        next
      }
      # Indented continuation of current bullet.
      if (cur_type == "bullet") {
        if (line ~ /^[[:space:]]/) { append(line); next }
        append(line); next
      }
      # Paragraph accumulator.
      if (cur_type != "paragraph") {
        if (cur_type != "") flush_buf(cur_type)
        cur_type = "paragraph"
        buf = line
        next
      }
      append(line)
    }
    END {
      if (cur_type != "") flush_buf(cur_type)
    }
  ' "$tmp_body"
else
  # YAML mode.
  awk -v outfile="$items_jsonl" -v RS_CHAR="$RS" -v GS_CHAR="$GS" '
    function flush() {
      if (buf == "") return
      sub(/\n+$/, "", buf)
      printf "yaml-key%s%s%s", RS_CHAR, buf, GS_CHAR >> outfile
      buf = ""
    }
    BEGIN { buf = "" }
    {
      line = $0
      if (line ~ /^[A-Za-z_"`-][^[:space:]]*[[:space:]]*:/ || line ~ /^[A-Za-z_]+:[[:space:]]*$/) {
        if (buf != "") flush()
        buf = line
        next
      }
      if (buf == "") next
      buf = buf "\n" line
    }
    END { if (buf != "") flush() }
  ' "$tmp_body"
fi

# Step 3 — Build the items JSON array from the GS/RS-separated jsonl.
if [ ! -s "$items_jsonl" ]; then
  items_json='[]'
else
  # Read whole content into Python? No — we have only bash/jq. We use jq's
  # ability to split on a control char to parse the records and then split
  # each record on the inner control char.
  items_json="$(
    jq -R -s --arg RS "$RS" --arg GS "$GS" '
      # Drop trailing GS to avoid an empty trailing record.
      (. | sub("\($GS)$"; ""))
      | split($GS)
      | map(select(length > 0))
      | to_entries
      | map({
          index: .key,
          type:  (.value | split($RS) | .[0]),
          text:  (.value | split($RS) | .[1:] | join($RS))
        })
    ' "$items_jsonl"
  )"
fi

# Build the top-level object.
section_field='null'
if [ -n "$section_arg" ]; then
  section_field="$(jq -n --arg s "$section_arg" '$s')"
fi

jq -n \
  --argjson items "$items_json" \
  --argjson section "$section_field" \
  --arg file_type "$file_type" \
  '{items: $items, section: $section, file_type: $file_type}'
exit 0
