#!/usr/bin/env bash
# Render a .tpl file with project inputs.
# Used by: sync (Step 5 — apply actions for any templated artifact).
#
# Two substitution rules:
#
# 1. Placeholders. Each `<placeholder>` token in the template is replaced with
#    the value of the corresponding key (lowercased) in the project inputs JSON.
#    Unrecognized placeholders become empty strings.
#
# 2. Conditional regions. Each pair
#       <!--lang:<NAME>-start-->
#       ...
#       <!--lang:<NAME>-end-->
#    is included (without the delimiter comments) when the corresponding
#    language is enabled in the project inputs JSON; otherwise the entire block
#    including delimiters is stripped.
#
#    A language is "enabled" when project inputs JSON contains either:
#      - `"languages"`: an array of strings containing `<NAME>`
#      - `"has_<name>"`: a truthy value (boolean true or string "true")
#
# Args:
#   $1  Required. Path to the .tpl file.
#   $2  Required. Path to the project inputs JSON file.
#
# Output:
#   stdout: the rendered file content (raw, not JSON). May be empty.
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Success.
#   2  Usage error, missing file, or unparseable inputs JSON.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  emit_error "usage: sync-render-template.sh <template-path> <inputs-json-path>"
  exit 2
fi
template="$1"
inputs="$2"

if [ ! -f "$template" ]; then
  emit_error "sync-render-template: template not found: $template"
  exit 2
fi
if [ ! -f "$inputs" ]; then
  emit_error "sync-render-template: inputs file not found: $inputs"
  exit 2
fi

# Validate inputs is JSON object.
if ! jq -e 'type == "object"' "$inputs" >/dev/null; then
  emit_error "sync-render-template: $inputs is not a JSON object"
  exit 2
fi

# Build the list of enabled languages from the inputs.
# 1. From the `languages` array if present.
# 2. From any `has_<name>` keys with a truthy value.
mapfile -t enabled_langs < <(
  jq -r '
    [
      (try (.languages | .[]) catch empty),
      (to_entries | map(select(.key | startswith("has_")) | select(.value == true or .value == "true") | .key | sub("^has_"; "")) | .[])
    ]
    | unique | .[]
  ' "$inputs"
)

is_enabled() {
  local target="$1"
  local lang
  for lang in "${enabled_langs[@]:-}"; do
    [ "$lang" = "$target" ] && return 0
  done
  return 1
}

# -------- Pass 1: handle conditional regions --------
# Walk the file line-by-line. When we hit `<!--lang:NAME-start-->`, capture
# until `<!--lang:NAME-end-->`. Include the body when NAME is enabled; strip
# the entire block (including delimiters) otherwise.
tmp1="$(mktemp)"
trap 'rm -f "$tmp1"' EXIT

# Pre-render enabled list as a JSON array for the awk pass.
enabled_json="$(printf '%s\n' "${enabled_langs[@]:-}" | jq -R . | jq -s .)"

awk -v enabled_json="$enabled_json" '
  function is_enabled(name,    i, n) {
    n = enabled_count
    for (i = 0; i < n; i++) {
      if (enabled[i] == name) return 1
    }
    return 0
  }
  # Extract the <NAME> from "<!--lang:NAME-start-->" or "<!--lang:NAME-end-->".
  # POSIX-compatible: index/substr, no 3-arg match().
  function extract_name(line, suffix,   p1, p2, p3) {
    p1 = index(line, "<!--lang:")
    if (p1 != 1) return ""
    p2 = index(line, suffix)
    if (p2 == 0) return ""
    # The name is between p1+9 (length of "<!--lang:") and p2.
    return substr(line, p1 + 9, p2 - (p1 + 9))
  }
  BEGIN {
    # Parse enabled_json into an indexed array. Tokens are the contents
    # between adjacent unescaped quotes, ignoring the outer brackets.
    n = split(enabled_json, parts, "\"")
    enabled_count = 0
    for (i = 2; i <= n - 1; i += 2) {
      enabled[enabled_count++] = parts[i]
    }
    in_block = 0
    block_name = ""
  }
  {
    if (in_block == 0) {
      # Detect block start: line must equal "<!--lang:NAME-start-->" exactly.
      name = extract_name($0, "-start-->")
      if (name != "" && $0 == "<!--lang:" name "-start-->") {
        block_name = name
        in_block = 1
        next
      }
      print
    } else {
      # In a block — look for matching end.
      end_name = extract_name($0, "-end-->")
      if (end_name != "" && $0 == "<!--lang:" end_name "-end-->") {
        if (end_name == block_name) {
          in_block = 0
          block_name = ""
        }
        next
      }
      # Body line.
      if (is_enabled(block_name)) print
    }
  }
' "$template" \
  | awk '/^$/{blank++;if(blank>1)next;print;next}{blank=0;print}' \
  > "$tmp1"

# -------- Pass 2: substitute placeholders --------
# Read all top-level scalar keys from the inputs JSON. For each `<key>` in the
# template (case-insensitive match), replace with the inputs value.
# Anything still matching `<word>` after we run the known substitutions is replaced
# with empty string only if it looks like a placeholder we should have known about
# (lowercased identifier characters and underscores). Generic `<word>` patterns
# in the rendered content are left untouched because users may have written
# legitimate `<...>` literals (e.g. `<header>`, `<inline html>`).
#
# Implementation: build a sed command-list of `s|<KEY>|VALUE|g` substitutions for
# every top-level scalar key in inputs, applied to tmp1.

# Get the list of top-level scalar keys (skip arrays, objects, nulls).
keys="$(jq -r 'to_entries | map(select(.value | type | . == "string" or . == "number" or . == "boolean")) | .[].key' "$inputs")"

# Render to stdout.
cp "$tmp1" "$tmp1.work"

# Apply each substitution.
while IFS= read -r key; do
  [ -z "$key" ] && continue
  # The placeholder is lowercase by convention (RFC says key = placeholder
  # lowercased). We also try the upper-case variant for legacy templates that
  # use <UPPER_CASE> placeholders for section blobs.
  value="$(jq -r --arg k "$key" '.[$k] // ""' "$inputs")"

  # Use a delimiter that is unlikely to appear in either string. We escape value
  # for sed. Since values can contain newlines, use a more robust approach: do
  # the substitution with awk.
  python_marker_lower="<${key}>"
  python_marker_upper="<$(echo "$key" | tr '[:lower:]' '[:upper:]')>"

  # awk-based replacement: substitute occurrences of the placeholder with value,
  # preserving newlines in the value.
  for marker in "$python_marker_lower" "$python_marker_upper"; do
    awk -v marker="$marker" -v repl="$value" '
      BEGIN {
        ml = length(marker)
      }
      {
        line = $0
        result = ""
        while ((p = index(line, marker)) > 0) {
          result = result substr(line, 1, p - 1) repl
          line = substr(line, p + ml)
        }
        result = result line
        print result
      }
    ' "$tmp1.work" > "$tmp1.next"
    mv "$tmp1.next" "$tmp1.work"
  done
done <<< "$keys"

cat "$tmp1.work"
rm -f "$tmp1" "$tmp1.work"
trap - EXIT
exit 0
