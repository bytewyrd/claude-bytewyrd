#!/usr/bin/env bash
# Probe whether a named tool is available.
# Used by: best-practices-extract.
#
# Args:
#   $1  Required. Probe name. Recognized names:
#         gh                    -> command -v gh, plus `gh auth status`
#         git                   -> command -v git
#         jq                    -> command -v jq
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
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ]; then
  emit_error "usage: tool-probe.sh <gh|git|jq>"
  exit 2
fi
name="$1"

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
  *)
    emit_error "unrecognized probe name '$name'"
    exit 2
    ;;
esac
