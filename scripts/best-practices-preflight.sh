#!/usr/bin/env bash
# Probe files needed by /best-practices-extract and /best-practices-record.
# Emits a JSON snapshot of file state so the LLM can reason without extra tool calls.
#
# Args: none. Reads HOME and CWD.
#
# Output:
#   stdout: a single JSON object:
#     {
#       "project_file":         "docs/BEST_PRACTICES.md",
#       "project_file_exists":  <bool>,
#       "project_sections":     ["Architecture", ...],
#       "project_entries":      ["- _Architecture_: Entry 1.", ...],
#       "global_file":          "/home/user/.claude/BEST_PRACTICES.md",
#       "global_file_exists":   <bool>,
#       "global_has_rationale": <bool>,
#       "global_sections":      ["Architecture", ...],
#       "global_entries":       ["- _Architecture_: Entry 1.", ...],
#       "claude_md_has_ref":    <bool>,
#       "gh_available":         <bool>,
#       "gh_result":            "available|missing|unauthenticated"
#     }
#   stderr: empty under normal operation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

project_file="docs/BEST_PRACTICES.md"
global_file="$HOME/.claude/BEST_PRACTICES.md"
claude_md="CLAUDE.md"

# --- Project file ---
project_file_exists=false
project_sections="[]"
project_entries="[]"
if [ -f "$project_file" ]; then
  project_file_exists=true
  project_sections="$(grep '^## ' "$project_file" \
    | sed 's/^## //' \
    | jq -R . | jq -s .)"
  project_entries="$(grep '^- _' "$project_file" \
    | jq -R . | jq -s .)"
fi

# --- Global file ---
global_file_exists=false
global_has_rationale=false
global_sections="[]"
global_entries="[]"
if [ -f "$global_file" ]; then
  global_file_exists=true
  global_sections="$(grep '^## ' "$global_file" \
    | sed 's/^## //' \
    | jq -R . | jq -s .)"
  global_entries="$(grep '^- _' "$global_file" \
    | jq -R . | jq -s .)"
  if grep -q 'Where do entries live' "$global_file" 2>/dev/null; then
    global_has_rationale=true
  fi
fi

# --- CLAUDE.md reference ---
claude_md_has_ref=false
if [ -f "$claude_md" ] && grep -q 'BEST_PRACTICES' "$claude_md" 2>/dev/null; then
  claude_md_has_ref=true
fi

# --- gh CLI probe ---
gh_available=false
gh_result="missing"
if [ -f "$SCRIPT_DIR/tool-probe.sh" ]; then
  probe_output="$(bash "$SCRIPT_DIR/tool-probe.sh" gh 2>/dev/null)" || true
  gh_result="$(printf '%s' "$probe_output" | jq -r '.result // "missing"' 2>/dev/null || echo "missing")"
  [ "$gh_result" = "available" ] && gh_available=true
fi

jq -n \
  --arg     project_file         "$project_file" \
  --argjson project_file_exists  "$project_file_exists" \
  --argjson project_sections     "$project_sections" \
  --argjson project_entries      "$project_entries" \
  --arg     global_file          "$global_file" \
  --argjson global_file_exists   "$global_file_exists" \
  --argjson global_has_rationale "$global_has_rationale" \
  --argjson global_sections      "$global_sections" \
  --argjson global_entries       "$global_entries" \
  --argjson claude_md_has_ref    "$claude_md_has_ref" \
  --argjson gh_available         "$gh_available" \
  --arg     gh_result            "$gh_result" \
  '{
    project_file:         $project_file,
    project_file_exists:  $project_file_exists,
    project_sections:     $project_sections,
    project_entries:      $project_entries,
    global_file:          $global_file,
    global_file_exists:   $global_file_exists,
    global_has_rationale: $global_has_rationale,
    global_sections:      $global_sections,
    global_entries:       $global_entries,
    claude_md_has_ref:    $claude_md_has_ref,
    gh_available:         $gh_available,
    gh_result:            $gh_result
  }'
