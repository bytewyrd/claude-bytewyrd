#!/usr/bin/env bash
# Consolidated /sync deterministic phase: preflight + classify-all in one call.
# Used by: skills/sync/SKILL.md (replaces separate Steps 1 and 4 calls).
#
# Chains sync-preflight.sh and sync-classify-all.sh so the LLM makes a single
# Bash tool call for the entire deterministic phase. The LLM still handles the
# interaction between classify and apply (print summary, ask Proceed?) — this
# script covers only what requires no user input.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object on success:
#     {
#       "preflight":       { <all fields from sync-preflight.sh> },
#       "classifications": [ <all elements from sync-classify-all.sh> ]
#     }
#   stderr: error messages propagated from the failing phase.
#
# Exit codes:
#   0  Both phases succeeded; JSON emitted to stdout.
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

# --- Combine and emit ---
jq -n \
  --argjson preflight       "$preflight_json" \
  --argjson classifications "$classifications_json" \
  '{preflight: $preflight, classifications: $classifications}'
