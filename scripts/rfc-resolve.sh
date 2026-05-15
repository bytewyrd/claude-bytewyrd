#!/usr/bin/env bash
# Resolve an RFC identifier or basename to a single RFC path.
# Used by: rfc-approve, rfc-drop, rfc-consensus-review, rfc-implement, rfc-read-feedback.
#
# Args:
#   $1  Optional. RFC identifier (e.g. 2026-05-14-foo) or basename (2026-05-14-foo.md).
#       If omitted, resolution falls back to: unique modified RFC -> most recent file.
#       RFC filenames follow YYYY-MM-DD-<kebab>.md by convention — no spaces.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"path": "<absolute-path>", "label": "<human-label e.g. RFC 2026-05-14-foo (unique modified file)>"}
#     not-found (exit 1):
#       {"error": "<message>"}
#     usage error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Resolved successfully.
#   1  No RFC found matching the given argument; no modified or existing files to fall back on.
#   2  Usage error (e.g. argument given but contains a path separator that is not a docs/rfcs/ path).

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

# Validate cwd contains docs/rfcs.
if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "rfc-resolve: no docs/rfcs/ directory in $(pwd); run from project root" \
    '{error: $msg}'
  exit 2
fi

# Helper: given a stem (filename without .md), check whether docs/rfcs/<stem>.md exists.
find_by_stem() {
  local stem="$1"
  local f="docs/rfcs/${stem}.md"
  [ -f "$f" ] && printf '%s\n' "$f"
}

emit_result() {
  local path="$1" label="$2"
  jq -n --arg path "$path" --arg label "$label" '{path: $path, label: $label}'
}

# Case 1: explicit argument.
if [ "${1:-}" != "" ]; then
  arg="$1"
  # Strip an optional leading "docs/rfcs/" prefix and trailing ".md".
  arg="${arg#docs/rfcs/}"
  arg="${arg%.md}"
  # Disallow path separators in the cleaned value — only basenames allowed.
  case "$arg" in
    */*) emit_error "rfc-resolve: identifier must not contain '/' (got: $1)"; exit 2 ;;
  esac
  resolved="$(find_by_stem "$arg" || true)"
  if [ -z "$resolved" ]; then
    emit_error "rfc-resolve: no RFC found at docs/rfcs/${arg}.md"
    exit 1
  fi
  abs="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
  emit_result "$abs" "RFC $arg (matched argument)"
  exit 0
fi

# Case 2: heuristic — exactly one modified RFC.
# Parse `git status --short` carefully:
#   - skip rows whose status indicates deletion (D in column 1 or column 2)
#   - for renames "R  old -> new", extract the new path (after " -> ")
#   - otherwise strip the two-char status+space prefix
# RFC filenames have no spaces by convention (YYYY-MM-DD-<kebab>.md).
# Uses index()+substr() for POSIX awk compatibility (no 3-arg match()).
modified=()
while IFS= read -r line; do
  [ -n "$line" ] && modified+=("$line")
done < <(
  git status --short -- docs/rfcs/ 2>/dev/null \
    | awk '
        # Skip deletions: status D in column 1 (staged delete) or column 2 (working-tree delete).
        /^D/ || /^.D/ { next }
        # For renames "R  old -> new", extract the new path (after " -> ").
        / -> / {
          n = index($0, " -> ")
          if (n > 0) { path = substr($0, n + 4); if (path ~ /\.md$/) print path }
          next
        }
        # Normal case: strip two-char status+space prefix, take rest.
        { sub(/^.. /, ""); if ($0 ~ /\.md$/) print $0 }
      ' \
    | sort -u
)
if [ "${#modified[@]}" -eq 1 ]; then
  resolved="${modified[0]}"
  if [ ! -f "$resolved" ]; then
    emit_error "rfc-resolve: modified file $resolved no longer exists"
    exit 1
  fi
  abs="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
  stem="$(basename "${resolved%.md}")"
  emit_result "$abs" "RFC $stem (unique modified file)"
  exit 0
fi

# Case 3: fall back to the most recently dated file (lex sort because filenames lead with YYYY-MM-DD).
latest="$(ls -1 docs/rfcs/*.md 2>/dev/null | sort | tail -n1)"
if [ -z "$latest" ] || [ ! -f "$latest" ]; then
  emit_error "rfc-resolve: no RFC files under docs/rfcs/"
  exit 1
fi
abs="$(cd "$(dirname "$latest")" && pwd)/$(basename "$latest")"
stem="$(basename "${latest%.md}")"
emit_result "$abs" "RFC $stem (most recently dated file)"
exit 0
