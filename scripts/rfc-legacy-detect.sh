#!/usr/bin/env bash
# Emit a JSON object listing every RFC file under docs/rfcs/ whose basename matches the legacy NNN- prefix.
# Used by: rfc-update.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"legacy_files": ["docs/rfcs/001-foo.md", ...]}
#       Empty array when no legacy files found.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Iteration completed.
#   2  docs/rfcs/ does not exist.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "rfc-legacy-detect: no docs/rfcs/ directory in $(pwd)" '{error: $msg}'
  exit 2
fi

# Collect paths whose basename starts with three digits followed by a hyphen.
# The basename test is necessary because docs/rfcs may itself contain digits in its path.
legacy=()
for f in docs/rfcs/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    [0-9][0-9][0-9]-*) legacy+=("$f") ;;
  esac
done

legacy_array="$(
  if [ "${#legacy[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${legacy[@]}" | jq -R . | jq -s .
  fi
)"

jq -n --argjson legacy_files "$legacy_array" '{legacy_files: $legacy_files}'
exit 0
