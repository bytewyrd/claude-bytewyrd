#!/usr/bin/env bash
# Per-chunk classification helpers for /sync summary.
#
# These functions emit a JSON array of "chunk objects" describing the
# fine-grained units that make up a file under the structured or owned-regions
# strategies. The chunks are display-only — they drive the indented detail
# rendered under each file entry in the /sync change summary, and are never
# used as classification or apply input.
#
# Chunk object shape:
#   {
#     "id":          <path|tag|heading literal>,
#     "type":        "json_dotpath" | "json_key" | "gitignore_block"
#                    | "gitignore_other" | "owned_heading" | "user_heading",
#     "owned":       true | false,
#     "status":      "changed" | "unchanged" | "preserved",
#     "local_keys":  [...],   // optional, json_dotpath only when value is an object
#     "plugin_keys": [...]    // optional, json_dotpath only when value is an object
#   }
#
# All functions return `[]` (a valid empty JSON array) on any failure. Chunks
# are display-only — a missing or malformed chunk array must never block the
# classification or apply path.
#
# Source from a script after the standard common.bash source:
#   source "$script_dir/_lib/chunks.bash"

# ---------------------------------------------------------------------------
# json_dotpath_chunks
#
#   For each path in <owned_paths_json> (simple dot-path strings like "hooks"):
#     - Read the jq value from both files with `jq -Sc ".<path>"`.
#     - Emit a chunk with id=<path>, type=json_dotpath, owned=true.
#       status="changed" when the values differ, "unchanged" when they match.
#     - When the value is a JSON object on either side, attach its top-level
#       keys via local_keys / plugin_keys (sorted, deduplicated). For non-object
#       values, both arrays are [].
#
#   After the owned passes, find every top-level key in the local file that is
#   NOT covered by any owned path's first segment, and emit one preserved chunk
#   per uncovered key with type=json_key, owned=false, status="preserved".
#
#   Wildcard paths ("*") and array-id paths ("foo[]:bar") are not addressable
#   as simple dot-paths and are skipped silently — the entire file is owned
#   under "*" and there are no preserved chunks worth surfacing in that case.
#
# Args:
#   $1  owned_paths_json — JSON array of strings (path expressions)
#   $2  local_file       — path to the local file
#   $3  plugin_file      — path to the plugin source file
# ---------------------------------------------------------------------------
json_dotpath_chunks() {
  local owned_paths_json="$1"
  local local_file="$2"
  local plugin_file="$3"

  [ -f "$local_file" ] && [ -f "$plugin_file" ] || { printf '[]'; return 0; }
  printf '%s' "$owned_paths_json" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { printf '[]'; return 0; }
  jq -e '.' "$local_file" >/dev/null 2>&1 || { printf '[]'; return 0; }
  jq -e '.' "$plugin_file" >/dev/null 2>&1 || { printf '[]'; return 0; }

  # Build the list of owned dot-paths and the set of "covered" top-level keys
  # (the first dot-segment of each path). Wildcards / array-id paths bail out
  # of the dot-path detail entirely.
  local owned_chunks="[]"
  local covered_keys_json="[]"
  local count
  count="$(printf '%s' "$owned_paths_json" | jq -r 'length' 2>/dev/null)" || return 0

  local i path first_seg
  for ((i = 0; i < count; i++)); do
    path="$(printf '%s' "$owned_paths_json" | jq -r ".[$i]" 2>/dev/null)" || continue
    # Skip non-simple paths — chunks are display-only and the simple-path case
    # is by far the common one for JSON targets.
    case "$path" in
      ""|"*"|*"["*) continue ;;
    esac

    first_seg="${path%%.*}"
    covered_keys_json="$(printf '%s' "$covered_keys_json" \
      | jq --arg k "$first_seg" '. + [$k]' 2>/dev/null)" || covered_keys_json="[]"

    # Read both sides with -Sc (sorted keys, compact form so comparison is
    # canonical). Missing values come back as JSON null.
    local local_val plugin_val
    local_val="$(jq -Sc ".${path}" "$local_file" 2>/dev/null || printf 'null')"
    plugin_val="$(jq -Sc ".${path}" "$plugin_file" 2>/dev/null || printf 'null')"

    local status
    if [ "$local_val" = "$plugin_val" ]; then
      status="unchanged"
    else
      status="changed"
    fi

    # Collect top-level keys when the value is a JSON object.
    local local_keys plugin_keys
    local_keys="$(printf '%s' "$local_val" \
      | jq -c 'if type == "object" then (keys | sort) else [] end' 2>/dev/null)" \
      || local_keys="[]"
    plugin_keys="$(printf '%s' "$plugin_val" \
      | jq -c 'if type == "object" then (keys | sort) else [] end' 2>/dev/null)" \
      || plugin_keys="[]"

    owned_chunks="$(printf '%s' "$owned_chunks" | jq -c \
      --arg id "$path" \
      --arg status "$status" \
      --argjson lk "$local_keys" \
      --argjson pk "$plugin_keys" \
      '. + [{
        id: $id,
        type: "json_dotpath",
        owned: true,
        status: $status,
        local_keys: $lk,
        plugin_keys: $pk
      }]' 2>/dev/null)" || owned_chunks="[]"
  done

  # Find preserved top-level keys: any local key not in the covered set.
  local preserved_chunks
  preserved_chunks="$(jq -c --argjson covered "$covered_keys_json" '
    (if type == "object" then keys else [] end)
    | map(select(. as $k | ($covered | index($k)) | not))
    | sort
    | map({
        id:    .,
        type:  "json_key",
        owned: false,
        status: "preserved"
      })
  ' "$local_file" 2>/dev/null)" || preserved_chunks="[]"

  # Concatenate owned + preserved.
  jq -cn \
    --argjson owned "$owned_chunks" \
    --argjson preserved "$preserved_chunks" \
    '$owned + $preserved' 2>/dev/null || printf '[]'
}

# ---------------------------------------------------------------------------
# gitignore_chunks
#
#   <owned_paths_json> contains bare tag strings like ["bytewyrd:base"]. The
#   in-file tag line is "# bytewyrd:base". A block runs from the tag line
#   through the next blank line or next "# bytewyrd:" tag.
#
#   For each tag: extract the block from local and plugin via awk, compare to
#   produce a chunk with id=<tag>, type=gitignore_block, owned=true,
#   status="changed" | "unchanged".
#
#   Always append one preserved chunk:
#     {id: "user content", type: "gitignore_other", owned: false, status: "preserved"}
#   This represents all lines outside tagged blocks.
#
# Args:
#   $1  owned_paths_json — JSON array of bare tag strings
#   $2  local_file       — path to the local .gitignore
#   $3  plugin_file      — path to the plugin .gitignore source
# ---------------------------------------------------------------------------
gitignore_chunks() {
  local owned_paths_json="$1"
  local local_file="$2"
  local plugin_file="$3"

  [ -f "$local_file" ] && [ -f "$plugin_file" ] || { printf '[]'; return 0; }
  printf '%s' "$owned_paths_json" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { printf '[]'; return 0; }

  local count
  count="$(printf '%s' "$owned_paths_json" | jq -r 'length' 2>/dev/null)" || return 0

  local owned_chunks="[]"
  local i tag local_block plugin_block status

  for ((i = 0; i < count; i++)); do
    tag="$(printf '%s' "$owned_paths_json" | jq -r ".[$i]" 2>/dev/null)" || continue
    [ -z "$tag" ] && continue

    local_block="$(_gitignore_extract_block "# $tag" "$local_file" 2>/dev/null)" || local_block=""
    plugin_block="$(_gitignore_extract_block "# $tag" "$plugin_file" 2>/dev/null)" || plugin_block=""

    if [ "$local_block" = "$plugin_block" ]; then
      status="unchanged"
    else
      status="changed"
    fi

    owned_chunks="$(printf '%s' "$owned_chunks" | jq -c \
      --arg id "$tag" \
      --arg status "$status" \
      '. + [{
        id: $id,
        type: "gitignore_block",
        owned: true,
        status: $status
      }]' 2>/dev/null)" || owned_chunks="[]"
  done

  # Always append one preserved "user content" chunk so the summary tells the
  # user their non-tagged lines survive untouched.
  jq -cn --argjson owned "$owned_chunks" '
    $owned + [{
      id:    "user content",
      type:  "gitignore_other",
      owned: false,
      status: "preserved"
    }]
  ' 2>/dev/null || printf '[]'
}

# Internal helper: extract a single tagged block from a .gitignore-style file.
# Block = the tag line plus every following line until the next blank line or
# the next "# bytewyrd:" tag (mirroring the apply-side extraction in
# sync-apply-batch.sh).
_gitignore_extract_block() {
  local tag="$1"
  local file="$2"
  [ -f "$file" ] || { printf ''; return 0; }
  awk -v tag="$tag" '
    BEGIN { in_block = 0 }
    $0 == tag { in_block = 1; print; next }
    in_block == 1 {
      if ($0 == "" || ($0 ~ /^# bytewyrd:/ && $0 != tag)) {
        exit
      }
      print
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# owned_regions_chunks
#
#   <owned_boundaries_json> is an array of {"type": "heading", "heading": "## Foo"}
#   objects.
#
#   For each boundary: extract the section body (lines from the heading line,
#   exclusive, up to the next ##-or-higher heading or EOF) from both local and
#   plugin. Compare to produce a chunk with id=<heading>, type=owned_heading,
#   owned=true, status="changed" | "unchanged".
#
#   Then scan the local file for every "## " heading. Any heading not listed in
#   owned_boundaries becomes a preserved chunk with type=user_heading,
#   owned=false, status="preserved".
#
# Args:
#   $1  owned_boundaries_json — JSON array of {type, heading} objects
#   $2  local_file            — path to the local file
#   $3  plugin_file           — path to the plugin source file
# ---------------------------------------------------------------------------
owned_regions_chunks() {
  local owned_boundaries_json="$1"
  local local_file="$2"
  local plugin_file="$3"

  [ -f "$local_file" ] && [ -f "$plugin_file" ] || { printf '[]'; return 0; }
  printf '%s' "$owned_boundaries_json" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { printf '[]'; return 0; }

  local count
  count="$(printf '%s' "$owned_boundaries_json" | jq -r 'length' 2>/dev/null)" || return 0

  local owned_chunks="[]"
  local owned_headings_json="[]"
  local i heading local_body plugin_body status

  for ((i = 0; i < count; i++)); do
    heading="$(printf '%s' "$owned_boundaries_json" | jq -r ".[$i].heading // empty" 2>/dev/null)" || continue
    [ -z "$heading" ] && continue

    owned_headings_json="$(printf '%s' "$owned_headings_json" \
      | jq --arg h "$heading" '. + [$h]' 2>/dev/null)" || owned_headings_json="[]"

    local_body="$(_owned_region_body "$heading" "$local_file" 2>/dev/null)" || local_body=""
    # If the section is absent from the local file, skip it — we can't compare
    # it against the plugin source (which may be a raw .tpl with template syntax).
    # The apply step handles addition correctly via the rendered template.
    [ -z "$local_body" ] && continue

    plugin_body="$(_owned_region_body "$heading" "$plugin_file" 2>/dev/null)" || plugin_body=""

    if [ "$local_body" = "$plugin_body" ]; then
      status="unchanged"
    else
      status="changed"
    fi

    owned_chunks="$(printf '%s' "$owned_chunks" | jq -c \
      --arg id "$heading" \
      --arg status "$status" \
      '. + [{
        id: $id,
        type: "owned_heading",
        owned: true,
        status: $status
      }]' 2>/dev/null)" || owned_chunks="[]"
  done

  # Scan the local file for all "## " (H2) headings that are NOT in the owned
  # set. Those become preserved user-heading chunks.
  local preserved_chunks="[]"
  if [ -f "$local_file" ]; then
    local all_local_headings_json
    all_local_headings_json="$(awk '/^## / { print }' "$local_file" \
      | jq -Rsc 'split("\n") | map(select(length > 0))' 2>/dev/null)" \
      || all_local_headings_json="[]"

    preserved_chunks="$(jq -cn \
      --argjson all "$all_local_headings_json" \
      --argjson owned "$owned_headings_json" \
      '$all
        | map(select(. as $h | ($owned | index($h)) | not))
        | map({
            id:    .,
            type:  "user_heading",
            owned: false,
            status: "preserved"
          })
      ' 2>/dev/null)" || preserved_chunks="[]"
  fi

  jq -cn \
    --argjson owned "$owned_chunks" \
    --argjson preserved "$preserved_chunks" \
    '$owned + $preserved' 2>/dev/null || printf '[]'
}

# Internal helper: extract the body of a heading section (everything between
# the heading line, exclusive, and the next H2/H1 heading or EOF).
_owned_region_body() {
  local heading="$1"
  local file="$2"
  [ -f "$file" ] || { printf ''; return 0; }
  awk -v heading="$heading" '
    BEGIN { in_section = 0 }
    {
      if ($0 == heading) { in_section = 1; next }
      if (in_section == 1) {
        if ($0 ~ /^## / || $0 ~ /^# /) { exit }
        print
      }
    }
  ' "$file"
}
