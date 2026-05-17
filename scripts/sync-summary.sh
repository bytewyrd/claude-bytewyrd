#!/usr/bin/env bash
# Generate the /sync change summary from sync-run.sh JSON output.
# Reads from a file path argument or stdin.
#
# Args:
#   $1  Optional. Path to JSON file. If absent, reads from stdin.
#
# Output:
#   stdout: formatted change-summary text.
#   stderr: error message if JSON cannot be read.
#
# Exit codes:
#   0  Success.
#   1  JSON read or parse error.

set -uo pipefail

# --- Input ---
if [ "${1:-}" != "" ]; then
  if ! data="$(cat "$1" 2>/dev/null)"; then
    printf 'sync-summary: error reading input: %s\n' "$1" >&2
    exit 1
  fi
else
  data="$(cat)"
fi

if ! printf '%s' "$data" | jq -e . >/dev/null 2>&1; then
  printf 'sync-summary: error reading input: invalid JSON\n' >&2
  exit 1
fi

# --- Classification sets ---
NEW_FILTER='.classification == "bootstrap_create" or .classification == "authoritative_add" or .classification == "add"'
UPDATE_FILTER='.classification == "authoritative_update" or .classification == "fast_forward" or .classification == "conflict" or .classification == "conflict_legacy" or .classification == "unchanged_legacy" or .classification == "additive_merge_apply"'
REVIEW_FILTER='.classification == "additive_merge_with_diff_apply"'
NOTSHOWN_FILTER='.classification == "unchanged" or .classification == "local_only"'
ALL_FILTER="${NEW_FILTER} or ${UPDATE_FILTER} or ${REVIEW_FILTER} or ${NOTSHOWN_FILTER}"

new_items="$(    printf '%s' "$data" | jq -c "[.classifications[] | select(${NEW_FILTER})]")"
update_items="$(  printf '%s' "$data" | jq -c "[.classifications[] | select(${UPDATE_FILTER})]")"
review_items="$(  printf '%s' "$data" | jq -c "[.classifications[] | select(${REVIEW_FILTER})]")"
notshown_items="$(printf '%s' "$data" | jq -c "[.classifications[] | select(${NOTSHOWN_FILTER})]")"
error_items="$(   printf '%s' "$data" | jq -c "[.classifications[] | select(${ALL_FILTER} | not)]")"

new_count="$(    printf '%s' "$new_items"     | jq 'length')"
update_count="$( printf '%s' "$update_items"  | jq 'length')"
review_count="$( printf '%s' "$review_items"  | jq 'length')"
error_count="$(  printf '%s' "$error_items"   | jq 'length')"
notshown_count="$(printf '%s' "$notshown_items" | jq 'length')"

total=$((new_count + update_count + review_count + error_count))

# --- Helpers ---

# plural N SINGULAR [PLURAL]
plural() {
  local n="$1" s="$2" p="${3:-${2}s}"
  [ "$n" -eq 1 ] && printf '%s' "$s" || printf '%s' "$p"
}

# format_chunks CHUNKS_JSON STRATEGY
# Prints detail lines for one classification item (may be empty output).
format_chunks() {
  local chunks="$1" strategy="$2"
  local n
  n="$(printf '%s' "$chunks" | jq 'length')"

  if [ "$n" -eq 0 ]; then
    case "$strategy" in
      "additive-merge")
        printf '      ~ additive merge (no user input required)\n' ;;
      "additive-merge-with-diff")
        printf '      ! additive merge — you cherry-pick which sections to accept\n' ;;
      "authoritative")
        printf '      \xe2\x9c\x93 (full file)  \xe2\x86\x92 authoritative overwrite (plugin-owned)\n' ;;
      "bootstrap")
        printf '      \xe2\x9c\x93 (full file)  \xe2\x86\x92 rendered from template\n' ;;
    esac
    return
  fi

  while IFS= read -r chunk; do
    local cid owned status label
    cid="$(    printf '%s' "$chunk" | jq -r '.id    // "?"')"
    owned="$(  printf '%s' "$chunk" | jq -r '.owned // false')"
    status="$( printf '%s' "$chunk" | jq -r '.status // ""')"
    if [ "$owned" = "true" ]; then
      case "$status" in
        "changed")   label="updated (changed)" ;;
        "unchanged") label="unchanged (preserved)" ;;
        *)           label="$status" ;;
      esac
      # ✓ U+2713, → U+2192
      printf '      \xe2\x9c\x93 %s  \xe2\x86\x92 %s\n' "$cid" "$label"
    else
      # · U+00B7
      printf '      \xc2\xb7 %s  \xe2\x86\x92 preserved (user-owned)\n' "$cid"
    fi
  done < <(printf '%s' "$chunks" | jq -c '.[]')
}

# --- Main output ---

printf '/sync \xe2\x80\x94 change summary:\n'

if [ "$total" -eq 0 ]; then
  printf '\nEverything is up to date.\n'
  exit 0
fi

# New files
if [ "$new_count" -gt 0 ]; then
  printf '\nNew %s (%d):\n' "$(plural "$new_count" "file")" "$new_count"
  while IFS= read -r item; do
    target="$(  printf '%s' "$item" | jq -r '.target   // "?"')"
    strategy="$(printf '%s' "$item" | jq -r '.strategy // ""')"
    chunks="$(  printf '%s' "$item" | jq -c '.chunks   // []')"
    printf '  + %s\n' "$target"
    format_chunks "$chunks" "$strategy"
  done < <(printf '%s' "$new_items" | jq -c '.[]')
fi

# Updates
if [ "$update_count" -gt 0 ]; then
  printf '\n%s (%d %s):\n' \
    "$(plural "$update_count" "Update" "Updates")" \
    "$update_count" \
    "$(plural "$update_count" "file")"
  while IFS= read -r item; do
    target="$(  printf '%s' "$item" | jq -r '.target   // "?"')"
    strategy="$(printf '%s' "$item" | jq -r '.strategy // ""')"
    chunks="$(  printf '%s' "$item" | jq -c '.chunks   // []')"
    printf '  ~ %s\n' "$target"
    format_chunks "$chunks" "$strategy"
  done < <(printf '%s' "$update_items" | jq -c '.[]')
fi

# Review needed
if [ "$review_count" -gt 0 ]; then
  printf '\nReview needed (%d %s \xe2\x80\x94 additive-merge-with-diff):\n' \
    "$review_count" "$(plural "$review_count" "file")"
  while IFS= read -r item; do
    printf '  ! %s\n' "$(printf '%s' "$item" | jq -r '.target // "?"')"
  done < <(printf '%s' "$review_items" | jq -c '.[]')
fi

# Warnings (unknown classifications)
if [ "$error_count" -gt 0 ]; then
  printf '\n%s (%d %s need attention):\n' \
    "$(plural "$error_count" "Warning" "Warnings")" \
    "$error_count" \
    "$(plural "$error_count" "item")"
  while IFS= read -r item; do
    target="$(printf '%s' "$item" | jq -r '.target // "?"')"
    err="$(    printf '%s' "$item" | jq -r '.error // .classification // "unknown"')"
    printf '  ? %s \xe2\x80\x94 %s\n' "$target" "$err"
  done < <(printf '%s' "$error_items" | jq -c '.[]')
fi

# Not shown footer
if [ "$notshown_count" -gt 0 ]; then
  local_only_list="$(printf '%s' "$notshown_items" \
    | jq -r '[.[] | select(.classification == "local_only") | .target] | join(", ")')"
  unchanged_list="$(printf '%s' "$notshown_items" \
    | jq -r '[.[] | select(.classification == "unchanged") | .target] | join(", ")')"

  parts=()
  [ -n "$local_only_list" ] && parts+=("${local_only_list} (local-only, preserved)")
  [ -n "$unchanged_list"   ] && parts+=("${unchanged_list} (unchanged)")

  if [ "${#parts[@]}" -gt 0 ]; then
    # Join parts with "; "
    joined="${parts[0]}"
    for p in "${parts[@]:1}"; do joined="${joined}; ${p}"; done
    printf '\nNot shown: %s.\n' "$joined"
  fi
fi
