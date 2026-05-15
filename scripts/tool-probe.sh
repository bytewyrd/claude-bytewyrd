#!/usr/bin/env bash
# Probe whether a named tool or companion plugin is available.
# Used by: best-practices-extract, rfc-implement, refactor.
#
# Args:
#   $1  Required. Probe name. Recognized names:
#         gh                    -> command -v gh, plus `gh auth status`
#         git                   -> command -v git
#         jq                    -> command -v jq
#         github-mcp            -> grep enabledPlugins entry for github@claude-plugins-official
#         context7-mcp          -> grep enabledPlugins entry for context7@claude-plugins-official
#         code-review-mcp       -> grep enabledPlugins entry for code-review@claude-plugins-official
#
# Output:
#   stdout: a single JSON object.
#     available (exit 0):
#       {"result": "available", "name": "<probe-name>"}
#     missing (exit 1):
#       {"result": "missing", "name": "<probe-name>", "hint": "<remediation one-liner>"}
#     unauthenticated — gh only (exit 1):
#       {"result": "unauthenticated", "name": "gh", "hint": "gh CLI present but not authenticated. Run: gh auth login."}
#     usage error (exit 2):
#       {"error": "unrecognized probe name '<name>'"}
#   The `hint` field replaces what was previously on stderr. Callers show it or
#   suppress it based on context.
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Tool is available (and, for gh, authenticated).
#   1  Tool is missing or, for gh, present but not authenticated.
#   2  Usage error (unrecognized probe name).

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_available() {
  jq -n --arg name "$1" '{result: "available", name: $name}'
}

emit_missing() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "missing", name: $name, hint: $hint}'
}

emit_unauth() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "unauthenticated", name: $name, hint: $hint}'
}

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: tool-probe.sh <gh|git|jq|github-mcp|context7-mcp|code-review-mcp>"
  exit 2
fi
name="$1"

# Helper: search project then user settings for an enabledPlugins entry.
# Precedence matches check-requirements.sh: project-false beats user-true (a project
# can explicitly disable a plugin even if the user has it enabled globally).
plugin_enabled() {
  local id="$1"
  local user_settings="$HOME/.claude/settings.json"
  local proj_settings=".claude/settings.json"
  # Project-level explicit false takes priority.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*false" "$proj_settings"; then return 1; fi
  # Project-level true.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$proj_settings"; then return 0; fi
  # User-level true (no project override).
  if [ -f "$user_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$user_settings"; then return 0; fi
  return 1
}

case "$name" in
  gh)
    if ! command -v gh >/dev/null 2>&1; then
      emit_missing "$name" "gh CLI not on PATH. Install: https://cli.github.com."
      exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
      emit_unauth "$name" "gh CLI present but not authenticated. Run: gh auth login."
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  git)
    if ! command -v git >/dev/null 2>&1; then
      emit_missing "$name" "git not on PATH. Install: https://git-scm.com/downloads."
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  jq)
    # By the time we reach here, `jq` is present (the startup guard above would
    # have exited otherwise). Report available; the missing-branch exists in
    # documentation form to keep the probe contract consistent.
    if ! command -v jq >/dev/null 2>&1; then
      # Static JSON string — safe without jq.
      printf '{"result":"missing","name":"jq","hint":"Install jq: https://stedolan.github.io/jq/download/"}\n'
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  github-mcp)
    if plugin_enabled "github@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "github@claude-plugins-official not enabled. Run: claude plugin install github@claude-plugins-official."
    exit 1
    ;;
  context7-mcp)
    if plugin_enabled "context7@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "context7@claude-plugins-official not enabled. Run: claude plugin install context7@claude-plugins-official."
    exit 1
    ;;
  code-review-mcp)
    if plugin_enabled "code-review@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "code-review@claude-plugins-official not enabled. Run: claude plugin install code-review@claude-plugins-official."
    exit 1
    ;;
  *)
    emit_error "unrecognized probe name '$name'"
    exit 2
    ;;
esac
