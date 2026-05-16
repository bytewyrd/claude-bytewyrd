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
classifications_json=""
classifications_json="$(bash "$SCRIPT_DIR/sync-classify-all.sh" "$plugin_root" 2>&1)" || exit 3

# --- Phase 3: brief completeness check (in current repo root) ---
brief_complete=false
if [ -f "docs/project-brief.md" ]; then
  # Real H1 (not the "Project Brief" placeholder) AND a ## Description with content.
  h1="$(grep -m1 '^# ' docs/project-brief.md 2>/dev/null \
    | sed 's/^# //' | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || echo "")"
  if [ -n "$h1" ] && [ "$h1" != "project brief" ]; then
    has_desc="$(awk '
      /^## Description/ { f=1; next }
      f && /^[^#[:space:]]/ && NF > 0 { found=1; exit }
      f && /^## / { exit }
      END { print found+0 }
    ' docs/project-brief.md 2>/dev/null || echo "0")"
    [ "$has_desc" = "1" ] && brief_complete=true
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
  | python3 "$SCRIPT_DIR/sync-summary.py" 2>/dev/null \
  || echo "(summary generation failed)")"

# --- Combine and emit ---
jq -n \
  --argjson preflight       "$preflight_json" \
  --argjson classifications "$classifications_json" \
  --argjson brief_complete  "$brief_complete" \
  --argjson rfc_process     "$rfc_process_json" \
  --arg     summary_text    "$summary_text" \
  '{
    preflight:       $preflight,
    classifications: $classifications,
    brief_complete:  $brief_complete,
    rfc_process:     $rfc_process,
    summary_text:    $summary_text
  }'
