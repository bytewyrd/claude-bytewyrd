#!/usr/bin/env bash
# Classify a single sync artifact by strategy.
# Used by: sync (Step 4 — diff computation per manifest entry).
#
# Implements the strategy-first dispatch from skills/sync/SKILL.md:
#
#   bootstrap                   target absent -> bootstrap_create
#                               target present -> local_only
#
#   authoritative               compares both sides after strip_two_line_header
#                               absent -> authoritative_add
#                               match  -> unchanged
#                               differ -> authoritative_update
#
#   additive-merge              reads the recorded SHA from the local marker;
#                               compares against the plugin-side canonical SHA.
#                               (Plugin canonical is approximated from the raw
#                               template content under each owned_sections
#                               heading — see "plugin canonical approximation"
#                               below.)
#                               absent      -> additive_merge_apply
#                               no marker   -> additive_merge_apply
#                               sha match   -> unchanged
#                               sha differ  -> additive_merge_apply
#
#   additive-merge-with-diff    same as additive-merge but uses
#                               additive_merge_with_diff_apply for the
#                               "needs work" classification.
#
#   owned-regions               compute SHA on both sides via the strategy's
#                               canonicalization rules. Equal -> unchanged.
#                               Otherwise run the structured matrix using
#                               local_current vs plugin_current and the
#                               marker SHA if present.
#
#   structured                  same matrix as owned-regions.
#
# The "structured matrix" (applied to owned-regions and structured strategies):
#
#   no marker, local==plugin            -> unchanged_legacy
#   no marker, local!=plugin            -> conflict_legacy
#   marker present, marker_sha==plugin  -> unchanged
#   marker, local==marker, marker!=plg  -> fast_forward
#   marker, local!=marker, plg==marker  -> local_only
#   marker, all three differ, l!=p      -> conflict
#   marker, all three differ, l==p      -> unchanged (converged)
#
# Args:
#   $1  Required. Manifest entry as a JSON object (or "-" to read from stdin).
#   $2  Required. Target file path (interpreted relative to caller's pwd).
#   $3  Required. Plugin root path (where the plugin source lives).
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"classification": "<value>", "strategy": "<strategy>",
#        "target": "<path>", "recorded_sha": "<sha or null>",
#        "plugin_sha": "<sha or null>"}
#     error (exit 2):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Success.
#   2  Bad arguments, missing files, or unrecognized strategy.
#
# Plugin canonical approximation (additive-merge):
#   Computing the *true* plugin canonical for additive-merge requires rendering
#   the template with project inputs and hashing the resulting owned-section
#   bodies. For classification only, this script approximates with the
#   canonical SHA of the *raw template source* under each owned_sections
#   heading. This is good enough to detect "the template changed since we last
#   wrote this file" without requiring project inputs at classification time.
#   At apply time the merge re-renders with full inputs and writes the true
#   canonical SHA into the marker.

set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib/common.bash
source "$script_dir/_lib/common.bash"
# shellcheck source=_lib/chunks.bash
source "$script_dir/_lib/chunks.bash"
require_jq

# Detect whether a target path is a .gitignore-style target — controls the
# chunk-extraction branch under the structured strategy.
is_gitignore_target() {
  case "$1" in *.gitignore|*/.gitignore|.gitignore) return 0 ;; *) return 1 ;; esac
}

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ] || [ "${3:-}" = "" ]; then
  emit_error "usage: sync-classify.sh <manifest-entry-json|-> <target-path> <plugin-root> [<project-inputs.json>]"
  exit 2
fi

manifest_arg="$1"
target="$2"
plugin_root="$3"
project_inputs_arg="${4:-}"

# Resolve manifest entry — either argv or stdin.
if [ "$manifest_arg" = "-" ]; then
  manifest_json="$(cat)"
else
  manifest_json="$manifest_arg"
fi

if ! echo "$manifest_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  emit_error "sync-classify: manifest entry must be a JSON object"
  exit 2
fi
if [ ! -d "$plugin_root" ]; then
  emit_error "sync-classify: plugin root not found: $plugin_root"
  exit 2
fi

# Extract fields.
strategy="$(echo "$manifest_json" | jq -r '.extension_strategy // ""')"
source_rel="$(echo "$manifest_json" | jq -r '.source // ""')"
plugin_source="$plugin_root/$source_rel"

emit() {
  local classification="$1"
  local recorded_sha="${2:-null}"
  local plugin_sha="${3:-null}"
  local chunks_json="${4:-[]}"
  local args=( --arg classification "$classification" --arg strategy "$strategy" --arg target "$target" --argjson chunks "$chunks_json" )
  local filter='{classification: $classification, strategy: $strategy, target: $target'
  if [ "$recorded_sha" = "null" ]; then
    filter+=', recorded_sha: null'
  else
    args+=( --arg recorded "$recorded_sha" )
    filter+=', recorded_sha: $recorded'
  fi
  if [ "$plugin_sha" = "null" ]; then
    filter+=', plugin_sha: null'
  else
    args+=( --arg plugin "$plugin_sha" )
    filter+=', plugin_sha: $plugin'
  fi
  filter+=', chunks: $chunks}'
  jq -n "${args[@]}" "$filter"
}

# Helper: read marker sha from a file via the sister script.
read_marker_sha() {
  local f="$1"
  if [ ! -f "$f" ]; then
    printf ''
    return
  fi
  local out
  out="$(bash "$script_dir/sync-marker-read.sh" "$f")"
  echo "$out" | jq -r 'if .found then .sha12 else "" end'
}

# Helper: compute canonical SHA via the sister script. Forwards strategy-
# specific args from the manifest entry.
canonical_sha() {
  local strat="$1"
  local f="$2"
  local args=()
  case "$strat" in
    additive-merge|additive-merge-with-diff)
      local sections
      sections="$(echo "$manifest_json" | jq -c '.owned_sections // []')"
      args=( --owned-sections "$sections" )
      ;;
    owned-regions|section)
      local boundaries
      boundaries="$(echo "$manifest_json" | jq -c '.owned_boundaries // []')"
      args=( --owned-boundaries "$boundaries" )
      ;;
    structured)
      local paths
      paths="$(echo "$manifest_json" | jq -c '.owned_paths // []')"
      args=( --owned-paths "$paths" )
      ;;
  esac
  local out
  if ! out="$(bash "$script_dir/sync-canonical.sh" "$strat" "$f" "${args[@]}" 2>/dev/null)"; then
    printf ''
    return
  fi
  echo "$out" | jq -r '.sha12'
}

# --------- strategy dispatch ----------
case "$strategy" in
  bootstrap)
    if [ ! -f "$target" ]; then
      emit "bootstrap_create"
    else
      emit "local_only"
    fi
    ;;

  authoritative)
    if [ ! -f "$plugin_source" ]; then
      emit_error "sync-classify: plugin source not found for authoritative artifact: $plugin_source"
      exit 2
    fi
    plugin_sha="$(canonical_sha authoritative "$plugin_source")"
    if [ ! -f "$target" ]; then
      emit "authoritative_add" "null" "$plugin_sha"
    else
      local_sha="$(canonical_sha authoritative "$target")"
      if [ "$local_sha" = "$plugin_sha" ]; then
        emit "unchanged" "$local_sha" "$plugin_sha"
      else
        emit "authoritative_update" "$local_sha" "$plugin_sha"
      fi
    fi
    ;;

  additive-merge|additive-merge-with-diff)
    apply_kind="additive_merge_apply"
    if [ "$strategy" = "additive-merge-with-diff" ]; then
      apply_kind="additive_merge_with_diff_apply"
    fi
    if [ ! -f "$plugin_source" ]; then
      emit_error "sync-classify: plugin source not found for additive-merge artifact: $plugin_source"
      exit 2
    fi
    plugin_sha="$(canonical_sha "$strategy" "$plugin_source")"
    if [ ! -f "$target" ]; then
      emit "$apply_kind" "null" "$plugin_sha"
    else
      recorded="$(read_marker_sha "$target")"
      if [ -z "$recorded" ]; then
        emit "$apply_kind" "null" "$plugin_sha"
      elif [ "$recorded" = "$plugin_sha" ]; then
        emit "unchanged" "$recorded" "$plugin_sha"
      else
        emit "$apply_kind" "$recorded" "$plugin_sha"
      fi
    fi
    ;;

  owned-regions|section|structured)
    if [ ! -f "$plugin_source" ]; then
      emit_error "sync-classify: plugin source not found for $strategy artifact: $plugin_source"
      exit 2
    fi

    # For templated structured artifacts, render the template before computing
    # the plugin SHA. The raw .tpl contains unresolved placeholders and is not
    # valid JSON — jq on it returns null, making every file classify as conflict.
    templated="$(echo "$manifest_json" | jq -r '.templated // false')"
    plugin_source_for_sha="$plugin_source"
    tmp_rendered=""
    if [ "$strategy" = "structured" ] && [ "$templated" = "true" ] \
        && [ -n "$project_inputs_arg" ] && [ -f "$project_inputs_arg" ]; then
      tmp_rendered="$(mktemp)"
      if bash "$script_dir/sync-render-template.sh" "$plugin_source" "$project_inputs_arg" \
          > "$tmp_rendered" 2>/dev/null; then
        plugin_source_for_sha="$tmp_rendered"
      fi
    fi

    plugin_sha="$(canonical_sha "$strategy" "$plugin_source_for_sha")"

    # Compute the per-chunk array for display. Chunks are only meaningful when
    # both target and plugin source exist; for the `add` case (no target file)
    # we pass `[]` since the entire plugin file is new content.
    chunks="[]"
    if [ -f "$target" ] && [ -f "$plugin_source_for_sha" ]; then
      case "$strategy" in
        owned-regions|section)
          boundaries="$(echo "$manifest_json" | jq -c '.owned_boundaries // []')"
          chunks="$(owned_regions_chunks "$boundaries" "$target" "$plugin_source_for_sha")"
          ;;
        structured)
          paths="$(echo "$manifest_json" | jq -c '.owned_paths // []')"
          if is_gitignore_target "$target"; then
            chunks="$(gitignore_chunks "$paths" "$target" "$plugin_source_for_sha")"
          else
            chunks="$(json_dotpath_chunks "$paths" "$target" "$plugin_source_for_sha")"
          fi
          ;;
      esac
    fi
    [ -n "$tmp_rendered" ] && rm -f "$tmp_rendered"

    if [ ! -f "$target" ]; then
      emit "add" "null" "$plugin_sha" "[]"
    else
      local_sha="$(canonical_sha "$strategy" "$target")"
      recorded="$(read_marker_sha "$target")"
      if [ -z "$recorded" ]; then
        # legacy file (no marker yet)
        if [ "$local_sha" = "$plugin_sha" ]; then
          emit "unchanged_legacy" "null" "$plugin_sha" "$chunks"
        else
          emit "conflict_legacy" "null" "$plugin_sha" "$chunks"
        fi
      else
        # marker present
        if [ "$recorded" = "$plugin_sha" ]; then
          emit "unchanged" "$recorded" "$plugin_sha" "$chunks"
        elif [ "$local_sha" = "$recorded" ] && [ "$plugin_sha" != "$recorded" ]; then
          emit "fast_forward" "$recorded" "$plugin_sha" "$chunks"
        elif [ "$local_sha" != "$recorded" ] && [ "$plugin_sha" = "$recorded" ]; then
          emit "local_only" "$recorded" "$plugin_sha" "$chunks"
        elif [ "$local_sha" = "$plugin_sha" ]; then
          # all differ but local == plugin: converged
          emit "unchanged" "$recorded" "$plugin_sha" "$chunks"
        else
          emit "conflict" "$recorded" "$plugin_sha" "$chunks"
        fi
      fi
    fi
    ;;

  *)
    emit_error "sync-classify: unrecognized extension_strategy: $strategy"
    exit 2
    ;;
esac

exit 0
