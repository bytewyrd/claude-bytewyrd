#!/usr/bin/env bash
# Consolidated /sync deterministic phase: preflight + classify-all + summary.
# Used by: skills/sync/SKILL.md (single Bash call for the entire no-input phase).
#
# Chains sync-preflight.sh and sync-classify-all.sh, then adds brief_complete,
# rfc_process, and summary_text so the LLM can print the summary and decide
# next steps without reading any additional files or running extra scripts.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object on success:
#     {
#       "preflight":       { <all fields from sync-preflight.sh> },
#       "classifications": [ <all elements from sync-classify-all.sh> ],
#       "brief_complete":  <bool>,
#       "rfc_process":     { "has_extensions": <bool>, ... },
#       "summary_text":    "<formatted /sync change summary>"
#     }
#   stderr: error messages propagated from the failing phase.
#
# Exit codes:
#   0  All phases succeeded; JSON emitted to stdout.
#   1  Preflight hard check failed (see stderr for details).
#   2  Preflight argument or environment error; or classify-all bad arguments.
#   3  Classify-all failed after a successful preflight.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Phase 1: preflight ---
# stderr from sync-preflight.sh flows through naturally; only stdout is captured.
# Use `|| exit $?` so the true exit code propagates (not the `!`-negated one).
preflight_json=""
preflight_json="$(bash "$SCRIPT_DIR/sync-preflight.sh")" || exit $?

# Extract plugin_root — if it's empty preflight already exited non-zero above.
plugin_root="$(printf '%s' "$preflight_json" | jq -r '.plugin_root // ""')"

# --- Phase 2: classify-all ---
# Build a minimal project_inputs.json for template rendering during classify.
# Templated structured artifacts (settings.json.tpl) need enabled_plugins_entries
# and pre_tool_use_hook as scalar keys so jq can parse the rendered output.
classify_inputs="$(mktemp)"
trap 'rm -f "$classify_inputs"' EXIT
printf '%s' "$preflight_json" | jq '{
  project_name:     (.project_slug // ""),
  description:      "",
  project_slug:     (.project_slug // ""),
  has_github:       (.github_remote | length > 0),
  languages:        (.languages // []),
  component_roots:  (.component_roots // []),
  installed_plugins: (.installed_plugins // []),
  has_rust:         (.has_rust // false),
  has_js:           (.has_js // false),
  has_go:           (.has_go // false),
  has_python:       (.has_python // false),
  has_svelte:       (.has_svelte // false),
  has_ruby:         (.has_ruby // false),
  has_rails:        (.has_rails // false),
  has_k8s_cue:      (.has_k8s_cue // false),
  has_terraform:    (.has_terraform // false)
}' > "$classify_inputs"
if enriched="$(bash "$SCRIPT_DIR/sync-compute-template-vars.sh" "$classify_inputs" 2>/dev/null)"; then
  printf '%s' "$enriched" > "$classify_inputs"
fi

classifications_json=""
classifications_json="$(bash "$SCRIPT_DIR/sync-classify-all.sh" "$plugin_root" "" "$classify_inputs" 2>&1)" || exit 3

# --- Phase 3: brief completeness check + identity extraction ---
brief_complete=false
brief_name=""
brief_description=""
if [ -f "docs/project-brief.md" ]; then
  raw_h1="$(grep -m1 '^# ' docs/project-brief.md 2>/dev/null | sed 's/^# //' || echo "")"
  h1_lower="$(printf '%s' "$raw_h1" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || echo "")"
  if [ -n "$h1_lower" ] && [ "$h1_lower" != "project brief" ]; then
    brief_name="$raw_h1"
    brief_description="$(awk '
      /^## Description/ { f=1; next }
      f && /^[^#[:space:]]/ && NF > 0 { print; exit }
      f && /^## / { exit }
    ' docs/project-brief.md 2>/dev/null || echo "")"
    [ -n "$brief_description" ] && brief_complete=true
  fi
fi

# --- Phase 4: RFC process extensions check ---
rfc_process_json='{"has_extensions": false}'
if [ -f "$SCRIPT_DIR/sync-rfc-process-check.sh" ]; then
  rfc_process_json="$(bash "$SCRIPT_DIR/sync-rfc-process-check.sh" 2>/dev/null \
    || echo '{"has_extensions": false}')"
fi

# --- Phase 5: build the formatted change summary ---
partial_json="$(jq -n \
  --argjson preflight       "$preflight_json" \
  --argjson classifications "$classifications_json" \
  '{preflight: $preflight, classifications: $classifications}')"

summary_text=""
summary_text="$(printf '%s' "$partial_json" \
  | bash "$SCRIPT_DIR/sync-summary.sh" 2>/dev/null \
  || echo "(summary generation failed)")"

# --- Combine and emit ---
jq -n \
  --argjson preflight          "$preflight_json" \
  --argjson classifications    "$classifications_json" \
  --argjson brief_complete     "$brief_complete" \
  --arg     brief_name         "$brief_name" \
  --arg     brief_description  "$brief_description" \
  --argjson rfc_process        "$rfc_process_json" \
  --arg     summary_text       "$summary_text" \
  '{
    preflight:         $preflight,
    classifications:   $classifications,
    brief_complete:    $brief_complete,
    brief_name:        $brief_name,
    brief_description: $brief_description,
    rfc_process:       $rfc_process,
    summary_text:      $summary_text
  }'
