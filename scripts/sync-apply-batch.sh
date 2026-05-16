#!/usr/bin/env bash
# Apply all deterministic (non-LLM) sync items in a single invocation.
# Used by: sync (Step 4a/5 — replaces N sequential per-item apply calls).
#
# The script accepts a JSON array of items in the shape emitted by
# sync-classify-all.sh and dispatches each by classification:
#
#   authoritative_add / authoritative_update
#       Render the plugin source (if templated) and copy to target, then stamp
#       the authoritative two-line header. Result: "applied".
#
#   unchanged_legacy
#       Stamp the inline / Markdown marker without changing content. For JSON
#       files, no inline marker — the result carries sidecar_update_needed so
#       the caller can update .bytewyrd/.bootstrap-versions.json. Result:
#       "marker_stamped".
#
#   add (owned-regions / structured)
#       Write the plugin source (rendered if templated) to a new target file,
#       then stamp the marker. Result: "applied".
#
#   fast_forward (owned-regions)
#       Merge plugin-owned regions into the existing local file via
#       sync-owned-regions-apply.sh, then stamp the marker. Result: "applied".
#
#   fast_forward (structured, .gitignore)
#       For each tag in owned_paths, replace the tagged block in the local
#       file with the plugin-side block. Stamp the inline marker. Result:
#       "applied".
#
#   fast_forward (structured, JSON)
#       For each dot-path in owned_paths, overwrite the local JSON value with
#       the plugin value; all other keys are preserved. Result: "applied".
#
#   conflict / conflict_legacy (owned-regions / structured)
#       Apply the same deterministic merge as fast_forward for the matching
#       strategy. Plugin-owned regions/paths always win; project-owned content
#       is preserved. Result: "applied".
#
#   bootstrap_create
#       Render the template, write the rendered content, stamp the bootstrap
#       header. Result: "applied".
#
# Classifications that need agent attention (LLM merge) are reported as
# "needs-agent". The caller handles additive-merge-with-diff interactively.
#
# Args:
#   $1  Required. JSON array of items OR "-" to read the array from stdin.
#   $2  Required. Plugin root.
#   $3  Required. Path to a JSON file with project inputs (used by
#       sync-render-template.sh for templated artifacts).
#
# Output:
#   stdout: a single JSON array. Each element has the shape:
#     {
#       "target": "<path>",
#       "upstream_key": "<key>",
#       "classification": "<input classification>",
#       "result": "applied|marker_stamped|skipped|needs-agent|error",
#       "sha12": "<sha12 or null>",
#       "sidecar_update_needed": false,   // present only for unchanged_legacy on JSON files
#       "error": "<message>"              // present only when result == "error"
#     }
#
# Exit codes:
#   0  Always when args are well-formed (per-item failures are captured in the
#      result string).
#   2  Bad arguments, missing plugin root, or unparseable items JSON.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib/common.bash
source "$SCRIPT_DIR/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ] || [ "${3:-}" = "" ]; then
  emit_error "usage: sync-apply-batch.sh <items-json|-> <plugin-root> <project-inputs-json>"
  exit 2
fi

items_arg="$1"
plugin_root="$2"
project_inputs="$3"

if [ ! -d "$plugin_root" ]; then
  emit_error "sync-apply-batch: plugin root not found: $plugin_root"
  exit 2
fi
plugin_root="$(cd "$plugin_root" && pwd)"

if [ ! -f "$project_inputs" ]; then
  emit_error "sync-apply-batch: project inputs JSON not found: $project_inputs"
  exit 2
fi

if [ "$items_arg" = "-" ]; then
  items_json="$(cat)"
else
  items_json="$items_arg"
fi

if ! printf '%s' "$items_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
  emit_error "sync-apply-batch: items must be a JSON array"
  exit 2
fi

# Temp workspace for rendered templates, awk staging, and per-item stderr.
tmp_workdir="$(mktemp -d)"
trap 'rm -rf "$tmp_workdir"' EXIT

# ---------- Helpers ----------

# Render a template (if templated) or echo the plugin source path. Echoes the
# path to a file holding the plugin-side content for an item. The caller is
# responsible for not deleting the returned path until after it has consumed
# the contents. The path always lives under $tmp_workdir.
plugin_content_path() {
  local item="$1"
  local source_rel templated tpl_path out_path
  source_rel="$(printf '%s' "$item" | jq -r '.source // ""')"
  templated="$(printf '%s' "$item" | jq -r '.templated // false')"
  if [ -z "$source_rel" ]; then
    printf ''
    return 1
  fi
  tpl_path="$plugin_root/$source_rel"
  if [ ! -f "$tpl_path" ]; then
    printf ''
    return 1
  fi
  out_path="$tmp_workdir/plugin-content.$$.$RANDOM"
  if [ "$templated" = "true" ]; then
    if ! bash "$SCRIPT_DIR/sync-render-template.sh" "$tpl_path" "$project_inputs" > "$out_path" 2>>"$tmp_workdir/render.err"; then
      return 1
    fi
  else
    cp "$tpl_path" "$out_path" || return 1
  fi
  printf '%s' "$out_path"
}

# Compute a sha12 for a file under a given strategy. Returns 0 on success and
# writes the sha to stdout; returns 1 on any failure (caller falls back).
canonical_sha12() {
  local strategy="$1"
  local file="$2"
  local extra_key="${3:-}"
  local extra_val="${4:-}"
  local args=( "$strategy" "$file" )
  if [ -n "$extra_key" ]; then
    args+=( "$extra_key" "$extra_val" )
  fi
  local out
  if ! out="$(bash "$SCRIPT_DIR/sync-canonical.sh" "${args[@]}" 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$out" | jq -r '.sha12 // empty'
}

# Pick the canonical args for a given strategy + item. Mutates two outparam
# variables ($_canonical_extra_key, $_canonical_extra_val) by reference.
canonical_args_for() {
  local strategy="$1"
  local item="$2"
  _canonical_extra_key=""
  _canonical_extra_val=""
  case "$strategy" in
    additive-merge|additive-merge-with-diff)
      _canonical_extra_key="--owned-sections"
      _canonical_extra_val="$(printf '%s' "$item" | jq -c '.owned_sections // []')"
      ;;
    owned-regions|section)
      _canonical_extra_key="--owned-boundaries"
      _canonical_extra_val="$(printf '%s' "$item" | jq -c '.owned_boundaries // []')"
      ;;
    structured)
      _canonical_extra_key="--owned-paths"
      _canonical_extra_val="$(printf '%s' "$item" | jq -c '.owned_paths // []')"
      ;;
  esac
}

# Stamp a Markdown two-line header on a file.
stamp_md_header() {
  local file="$1"
  local upstream_key="$2"
  local sha12="$3"
  local kind="$4"  # bootstrap | authoritative
  bash "$SCRIPT_DIR/sync-write-header.sh" "$file" "$upstream_key" "$sha12" "$kind" >/dev/null
}

# Stamp an inline `#`-comment marker as line 1 (followed by a blank line) for
# TOML / .gitignore / shell-comment files. Replaces an existing marker if
# present on line 1; otherwise prepends.
stamp_hash_marker() {
  local file="$1"
  local upstream_key="$2"
  local sha12="$3"
  local marker="# bootstrap-content-version: ${upstream_key}:${sha12}"
  local tmp
  tmp="$(mktemp)"
  awk -v marker="$marker" '
    BEGIN { wrote = 0 }
    NR == 1 {
      if ($0 ~ /^# bootstrap-content-version:/) {
        print marker
        wrote = 1
        next
      }
      print marker
      print ""
      wrote = 1
      print
      next
    }
    NR == 2 && wrote == 1 {
      # If the existing first line was a marker, swallow the blank line that
      # followed it; we always reinsert exactly one. If it was content, keep
      # this line verbatim.
      if ($0 == "") next
      print ""
      print
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Detect whether a target path is a JSON file (and should use the sidecar
# marker rather than an inline one).
is_json_target() {
  case "$1" in
    *.json) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect whether a target is a .gitignore (needs inline-`#` marker + tagged
# block replacement when strategy is structured).
is_gitignore_target() {
  case "$1" in
    *.gitignore|*/.gitignore|.gitignore) return 0 ;;
    *) return 1 ;;
  esac
}

# Replace a tagged block in a local .gitignore with the matching block from
# the plugin source. If the tag does not exist in the local file, the plugin
# block is appended. Tag format: `# bytewyrd:base` etc. A block runs from the
# tag line through the next blank line or next `# bytewyrd:` tag.
replace_gitignore_block() {
  local tag="$1"
  local local_file="$2"
  local plugin_source="$3"
  local tmp_out
  tmp_out="$(mktemp)"

  # Extract the block from the plugin source.
  local plugin_block
  plugin_block="$(awk -v tag="$tag" '
    found && (/^$/ || (/^# bytewyrd:/ && $0 != tag)) { exit }
    $0 == tag { found = 1 }
    found { print }
  ' "$plugin_source")"

  if [ -z "$plugin_block" ]; then
    # Tag not found in the plugin source — leave the local file unchanged.
    rm -f "$tmp_out"
    return 0
  fi

  # Does the tag exist in the local file?
  if grep -Fxq "$tag" "$local_file" 2>/dev/null; then
    awk -v tag="$tag" -v newblock="$plugin_block" '
      BEGIN { in_block = 0; replaced = 0 }
      in_block && (/^$/ || (/^# bytewyrd:/ && $0 != tag)) {
        in_block = 0
        printf "%s\n", newblock
        replaced = 1
        if (/^$/) {
          print ""
          next
        }
      }
      $0 == tag { in_block = 1; next }
      !in_block { print }
      END { if (in_block) printf "%s\n", newblock }
    ' "$local_file" > "$tmp_out"
  else
    # Append the plugin block to the local file, preceded by a blank line if
    # the local file does not already end with one.
    cp "$local_file" "$tmp_out"
    if [ -s "$tmp_out" ]; then
      local last_byte
      last_byte="$(tail -c 1 "$tmp_out")"
      if [ "$last_byte" != $'\n' ]; then
        printf '\n' >> "$tmp_out"
      fi
      # Ensure a blank-line separator before the appended block.
      printf '\n%s\n' "$plugin_block" >> "$tmp_out"
    else
      printf '%s\n' "$plugin_block" > "$tmp_out"
    fi
  fi

  mv "$tmp_out" "$local_file"
}

# Emit a single result element on stdout (one line of JSON, to be array-wrapped
# at the end).
emit_result() {
  local target="$1"
  local upstream_key="$2"
  local classification="$3"
  local result="$4"
  local sha12="${5:-}"
  local extra="${6:-}"

  local sha_arg
  if [ -z "$sha12" ]; then
    sha_arg=null
  else
    sha_arg='"'$sha12'"'
  fi

  if [ -n "$extra" ]; then
    jq -nc \
      --arg target "$target" \
      --arg upstream_key "$upstream_key" \
      --arg classification "$classification" \
      --arg result "$result" \
      --argjson sha12 "$sha_arg" \
      --argjson extra "$extra" \
      '{target: $target, upstream_key: $upstream_key, classification: $classification, result: $result, sha12: $sha12} + $extra'
  else
    jq -nc \
      --arg target "$target" \
      --arg upstream_key "$upstream_key" \
      --arg classification "$classification" \
      --arg result "$result" \
      --argjson sha12 "$sha_arg" \
      '{target: $target, upstream_key: $upstream_key, classification: $classification, result: $result, sha12: $sha12}'
  fi
}

# Apply plugin-owned regions to an existing target via sync-owned-regions-apply.sh.
# Prints the resulting sha12 to stdout on success, or an error message on failure.
# Return codes: 0 = success (sha12 printed), 1 = failure (error message printed).
apply_owned_regions() {
  local item="$1" target="$2" upstream_key="$3"
  local content_path boundaries merged_path sha

  content_path="$(plugin_content_path "$item")" \
    || { printf 'apply_owned_regions: failed to resolve plugin source for %s' "$target"; return 1; }
  [ -f "$target" ] \
    || { printf 'apply_owned_regions: target missing: %s' "$target"; return 1; }

  boundaries="$(printf '%s' "$item" | jq -c '.owned_boundaries // []')"
  merged_path="$tmp_workdir/merged.$$.$RANDOM"

  bash "$SCRIPT_DIR/sync-owned-regions-apply.sh" "$target" "$content_path" "$boundaries" \
      > "$merged_path" 2>>"$tmp_workdir/merge.err" \
    || { printf 'apply_owned_regions: owned-regions merge failed for %s' "$target"; return 1; }
  mv "$merged_path" "$target" \
    || { printf 'apply_owned_regions: failed to write merged content to %s' "$target"; return 1; }

  sha="$(canonical_sha12 owned-regions "$target" --owned-boundaries "$boundaries" 2>/dev/null)"
  [ -n "$sha" ] \
    || { printf 'apply_owned_regions: failed to compute sha for %s' "$target"; return 1; }

  stamp_md_header "$target" "$upstream_key" "$sha" bootstrap 2>/dev/null \
    || { printf 'apply_owned_regions: failed to stamp marker on %s' "$target"; return 1; }

  printf '%s' "$sha"
}

# Replace plugin-owned tagged blocks in a .gitignore target.
# Prints the resulting sha12 to stdout on success, or an error message on failure.
apply_gitignore_blocks() {
  local item="$1" target="$2" upstream_key="$3"
  local content_path owned_paths_json count sha i tag

  content_path="$(plugin_content_path "$item")" \
    || { printf 'apply_gitignore_blocks: failed to resolve plugin source for %s' "$target"; return 1; }
  [ -f "$target" ] \
    || { printf 'apply_gitignore_blocks: target missing: %s' "$target"; return 1; }

  owned_paths_json="$(printf '%s' "$item" | jq -c '.owned_paths // []')"
  count="$(printf '%s' "$owned_paths_json" | jq -r 'length')"

  for ((i = 0; i < count; i++)); do
    tag="$(printf '%s' "$owned_paths_json" | jq -r ".[$i]")"
    replace_gitignore_block "# $tag" "$target" "$content_path" 2>>"$tmp_workdir/gitignore.err" \
      || { printf 'apply_gitignore_blocks: block replacement failed for tag %s in %s' "$tag" "$target"; return 1; }
  done

  sha="$(canonical_sha12 structured "$target" --owned-paths "$owned_paths_json" 2>/dev/null)"
  [ -n "$sha" ] \
    || { printf 'apply_gitignore_blocks: failed to compute sha for %s' "$target"; return 1; }

  stamp_hash_marker "$target" "$upstream_key" "$sha" 2>/dev/null \
    || { printf 'apply_gitignore_blocks: failed to stamp marker on %s' "$target"; return 1; }

  printf '%s' "$sha"
}

# Merge plugin-owned dot-path values into a JSON target (e.g. "hooks" in settings.json).
# All keys not in owned_paths are preserved from the local file.
# Prints the resulting sha12 to stdout on success, or an error message on failure.
# NOTE: JSON files use the sidecar marker; the caller must set sidecar_update_needed.
apply_json_dotpath_merge() {
  local item="$1" target="$2" upstream_key="$3"
  local content_path owned_paths_json count merge_tmp sha i path plugin_val merged

  content_path="$(plugin_content_path "$item")" \
    || { printf 'apply_json_dotpath_merge: failed to resolve plugin source for %s' "$target"; return 1; }
  [ -f "$target" ] \
    || { printf 'apply_json_dotpath_merge: target missing: %s' "$target"; return 1; }

  owned_paths_json="$(printf '%s' "$item" | jq -c '.owned_paths // []')"
  count="$(printf '%s' "$owned_paths_json" | jq -r 'length')"

  merge_tmp="$(mktemp)"
  cp "$target" "$merge_tmp"

  for ((i = 0; i < count; i++)); do
    path="$(printf '%s' "$owned_paths_json" | jq -r ".[$i]")"
    plugin_val="$(jq -S ".${path}" "$content_path" 2>/dev/null)" \
      || { rm -f "$merge_tmp"; printf 'apply_json_dotpath_merge: failed to read plugin value for path .%s in %s' "$path" "$target"; return 1; }
    merged="$(jq --argjson v "$plugin_val" ".${path} = \$v" "$merge_tmp" 2>/dev/null)" \
      || { rm -f "$merge_tmp"; printf 'apply_json_dotpath_merge: failed to merge path .%s into %s' "$path" "$target"; return 1; }
    printf '%s\n' "$merged" > "$merge_tmp"
  done

  cp "$merge_tmp" "$target"
  rm -f "$merge_tmp"

  sha="$(canonical_sha12 structured "$target" --owned-paths "$owned_paths_json" 2>/dev/null)"
  [ -n "$sha" ] \
    || { printf 'apply_json_dotpath_merge: failed to compute sha for %s' "$target"; return 1; }

  printf '%s' "$sha"
}

# Collect results as newline-delimited JSON, wrap into an array at the end.
results_file="$tmp_workdir/results.jsonl"
: > "$results_file"

# ---------- Main loop ----------

# Strategies and classifications that fall back to per-item agent handling.
is_needs_agent() {
  local classification="$1"
  local strategy="$2"
  case "$classification" in
    additive_merge_apply|additive_merge_with_diff_apply)
      return 0
      ;;
    conflict|conflict_legacy)
      # Owned-regions and structured (including JSON dot-paths) are handled
      # deterministically: plugin-owned regions/paths always win.
      case "$strategy" in
        owned-regions|section|structured) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    fast_forward)
      # All structured fast-forwards are deterministic: .gitignore uses
      # tagged-block replacement; JSON uses dot-path merge.
      case "$strategy" in
        owned-regions|section|structured) return 1 ;;
      esac
      ;;
  esac
  return 1
}

# Detect the "no-op" classifications the agent has nothing to do for.
is_skipped() {
  case "$1" in
    unchanged|local_only) return 0 ;;
  esac
  return 1
}

while IFS= read -r item; do
  [ -z "$item" ] && continue

  classification="$(printf '%s' "$item" | jq -r '.classification // ""')"
  target="$(printf '%s' "$item" | jq -r '.target // ""')"
  upstream_key="$(printf '%s' "$item" | jq -r '.upstream_key // ""')"
  strategy="$(printf '%s' "$item" | jq -r '.strategy // ""')"
  plugin_sha="$(printf '%s' "$item" | jq -r '.plugin_sha // empty')"
  templated="$(printf '%s' "$item" | jq -r '.templated // false')"

  # Skip / needs-agent fast paths.
  if [ "$classification" = "error" ]; then
    err_msg="$(printf '%s' "$item" | jq -r '.error // "unknown classify error"')"
    emit_result "$target" "$upstream_key" "$classification" "error" "" "$(jq -nc --arg e "$err_msg" '{error: $e}')" >> "$results_file"
    continue
  fi
  if is_skipped "$classification"; then
    emit_result "$target" "$upstream_key" "$classification" "skipped" "" >> "$results_file"
    continue
  fi
  if is_needs_agent "$classification" "$strategy"; then
    emit_result "$target" "$upstream_key" "$classification" "needs-agent" "" >> "$results_file"
    continue
  fi

  # Per-item error handling: any failure inside this block records an error
  # result and continues.
  err_out=""
  apply_result=""
  apply_sha=""
  apply_extra=""

  case "$classification" in
    authoritative_add|authoritative_update)
      content_path="$(plugin_content_path "$item")" || content_path=""
      if [ -z "$content_path" ] || [ ! -f "$content_path" ]; then
        err_out="failed to read or render plugin source"
      else
        target_dir="$(dirname "$target")"
        mkdir -p "$target_dir" 2>/dev/null || true
        if ! cp "$content_path" "$target"; then
          err_out="failed to write target: $target"
        else
          sha="$(canonical_sha12 authoritative "$target" 2>/dev/null)"
          if [ -z "$sha" ]; then
            err_out="failed to compute canonical sha for $target"
          else
            if stamp_md_header "$target" "$upstream_key" "$sha" authoritative 2>/dev/null; then
              apply_result="applied"
              apply_sha="$sha"
            else
              err_out="failed to stamp authoritative header on $target"
            fi
          fi
        fi
      fi
      ;;

    unchanged_legacy)
      if [ ! -f "$target" ]; then
        err_out="unchanged_legacy: target missing: $target"
      elif [ -z "$plugin_sha" ]; then
        err_out="unchanged_legacy: missing plugin_sha in item"
      else
        if is_json_target "$target"; then
          # JSON files use the sidecar — no inline marker.
          apply_result="marker_stamped"
          apply_sha="$plugin_sha"
          apply_extra="$(jq -nc '{sidecar_update_needed: true}')"
        elif is_gitignore_target "$target"; then
          if stamp_hash_marker "$target" "$upstream_key" "$plugin_sha" 2>/dev/null; then
            apply_result="marker_stamped"
            apply_sha="$plugin_sha"
          else
            err_out="failed to stamp gitignore marker on $target"
          fi
        else
          # Markdown / TOML / shell-comment files. Pick the right stamper.
          case "$target" in
            *.md|*.markdown)
              if stamp_md_header "$target" "$upstream_key" "$plugin_sha" bootstrap 2>/dev/null; then
                apply_result="marker_stamped"
                apply_sha="$plugin_sha"
              else
                err_out="failed to stamp markdown header on $target"
              fi
              ;;
            *)
              if stamp_hash_marker "$target" "$upstream_key" "$plugin_sha" 2>/dev/null; then
                apply_result="marker_stamped"
                apply_sha="$plugin_sha"
              else
                err_out="failed to stamp hash marker on $target"
              fi
              ;;
          esac
        fi
      fi
      ;;

    add)
      content_path="$(plugin_content_path "$item")" || content_path=""
      if [ -z "$content_path" ] || [ ! -f "$content_path" ]; then
        err_out="add: failed to read or render plugin source"
      else
        target_dir="$(dirname "$target")"
        mkdir -p "$target_dir" 2>/dev/null || true
        if ! cp "$content_path" "$target"; then
          err_out="add: failed to write target: $target"
        else
          canonical_args_for "$strategy" "$item"
          sha="$(canonical_sha12 "$strategy" "$target" "$_canonical_extra_key" "$_canonical_extra_val" 2>/dev/null)"
          if [ -z "$sha" ]; then
            err_out="add: failed to compute canonical sha for $target"
          else
            stamp_ok=1
            if is_json_target "$target"; then
              apply_extra="$(jq -nc '{sidecar_update_needed: true}')"
            elif is_gitignore_target "$target"; then
              stamp_hash_marker "$target" "$upstream_key" "$sha" 2>/dev/null || stamp_ok=0
            else
              case "$target" in
                *.md|*.markdown)
                  stamp_md_header "$target" "$upstream_key" "$sha" bootstrap 2>/dev/null || stamp_ok=0
                  ;;
                *)
                  stamp_hash_marker "$target" "$upstream_key" "$sha" 2>/dev/null || stamp_ok=0
                  ;;
              esac
            fi
            if [ "$stamp_ok" = "1" ]; then
              apply_result="applied"
              apply_sha="$sha"
            else
              err_out="add: failed to stamp marker on $target"
            fi
          fi
        fi
      fi
      ;;

    fast_forward)
      case "$strategy" in
        owned-regions|section)
          if result_sha="$(apply_owned_regions "$item" "$target" "$upstream_key" 2>/dev/null)"; then
            apply_result="applied"; apply_sha="$result_sha"
          else
            err_out="fast_forward: $result_sha"
          fi
          ;;
        structured)
          if is_gitignore_target "$target"; then
            if result_sha="$(apply_gitignore_blocks "$item" "$target" "$upstream_key" 2>/dev/null)"; then
              apply_result="applied"; apply_sha="$result_sha"
            else
              err_out="fast_forward: $result_sha"
            fi
          else
            if result_sha="$(apply_json_dotpath_merge "$item" "$target" "$upstream_key" 2>/dev/null)"; then
              apply_result="applied"; apply_sha="$result_sha"
              apply_extra="$(jq -nc '{sidecar_update_needed: true}')"
            else
              err_out="fast_forward: $result_sha"
            fi
          fi
          ;;
        *)
          err_out="fast_forward: unsupported strategy: $strategy"
          ;;
      esac
      ;;

    bootstrap_create)
      content_path="$(plugin_content_path "$item")" || content_path=""
      if [ -z "$content_path" ] || [ ! -f "$content_path" ]; then
        err_out="bootstrap_create: failed to render template"
      else
        target_dir="$(dirname "$target")"
        mkdir -p "$target_dir" 2>/dev/null || true
        if ! cp "$content_path" "$target"; then
          err_out="bootstrap_create: failed to write target: $target"
        else
          sha="$(canonical_sha12 authoritative "$target" 2>/dev/null)"
          # bootstrap files don't have a strategy-specific canonical form; the
          # marker SHA is computed via the authoritative (strip-header)
          # canonical form so it can be re-verified after stamping.
          if [ -z "$sha" ]; then
            err_out="bootstrap_create: failed to compute canonical sha for $target"
          else
            case "$target" in
              *.md|*.markdown)
                if stamp_md_header "$target" "$upstream_key" "$sha" bootstrap 2>/dev/null; then
                  apply_result="applied"
                  apply_sha="$sha"
                else
                  err_out="bootstrap_create: failed to stamp markdown header on $target"
                fi
                ;;
              *)
                if stamp_hash_marker "$target" "$upstream_key" "$sha" 2>/dev/null; then
                  apply_result="applied"
                  apply_sha="$sha"
                else
                  err_out="bootstrap_create: failed to stamp hash marker on $target"
                fi
                ;;
            esac
          fi
        fi
      fi
      ;;

    conflict|conflict_legacy)
      # Plugin-owned regions/paths always win. The extension strategy encodes
      # what the plugin owns vs. what the project owns, so applying it
      # deterministically is strictly correct even without a baseline marker.
      case "$strategy" in
        owned-regions|section)
          if result_sha="$(apply_owned_regions "$item" "$target" "$upstream_key" 2>/dev/null)"; then
            apply_result="applied"; apply_sha="$result_sha"
          else
            err_out="${classification}: $result_sha"
          fi
          ;;
        structured)
          if is_gitignore_target "$target"; then
            if result_sha="$(apply_gitignore_blocks "$item" "$target" "$upstream_key" 2>/dev/null)"; then
              apply_result="applied"; apply_sha="$result_sha"
            else
              err_out="${classification}: $result_sha"
            fi
          else
            if result_sha="$(apply_json_dotpath_merge "$item" "$target" "$upstream_key" 2>/dev/null)"; then
              apply_result="applied"; apply_sha="$result_sha"
              apply_extra="$(jq -nc '{sidecar_update_needed: true}')"
            else
              err_out="${classification}: $result_sha"
            fi
          fi
          ;;
        *)
          apply_result="needs-agent"
          ;;
      esac
      ;;

    *)
      # Any other classification we did not catch above falls back to
      # needs-agent so the per-item flow can handle it without aborting the
      # batch.
      apply_result="needs-agent"
      ;;
  esac

  if [ -n "$err_out" ]; then
    emit_result "$target" "$upstream_key" "$classification" "error" "" \
      "$(jq -nc --arg e "$err_out" '{error: $e}')" \
      >> "$results_file"
  else
    if [ -z "$apply_result" ]; then
      apply_result="needs-agent"
    fi
    emit_result "$target" "$upstream_key" "$classification" "$apply_result" "$apply_sha" "$apply_extra" \
      >> "$results_file"
  fi
done < <(printf '%s' "$items_json" | jq -c '.[]')

if [ -s "$results_file" ]; then
  jq -s '.' < "$results_file"
else
  printf '[]\n'
fi

exit 0
