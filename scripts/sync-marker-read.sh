#!/usr/bin/env bash
# Read the bootstrap-content-version marker from the first two lines of a file.
# Used by: sync (classification, canonicalization).
#
# Recognizes both Markdown and TOML/YAML/.gitignore marker styles:
#   - Markdown:   `<!-- bootstrap-content-version: <key>:<sha12> -->` (typically line 2)
#   - TOML/YAML:  `# bootstrap-content-version: <key>:<sha12>`        (typically line 1)
#
# Args:
#   $1  Required. Path to the file to inspect.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"found": true,  "upstream_key": "<key>", "sha12": "<12-hex>", "line": <int>}
#       {"found": false, "upstream_key": null,    "sha12": null,        "line": null}
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Always when the file exists (found=false is a normal result).
#   2  Usage error or file not readable.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ]; then
  emit_error "usage: sync-marker-read.sh <path-to-file>"
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  emit_error "sync-marker-read: file not found: $file"
  exit 2
fi

# Read the first two lines.
line1="$(sed -n '1p' "$file")"
line2="$(sed -n '2p' "$file")"

# Patterns:
#   Markdown: `<!-- bootstrap-content-version: <key>:<sha12> -->`
#   TOML/YAML/gitignore: `# bootstrap-content-version: <key>:<sha12>`
extract_marker() {
  local line="$1"
  # Markdown style: <!-- bootstrap-content-version: KEY:SHA -->
  if [[ "$line" =~ ^"<!--"[[:space:]]*bootstrap-content-version:[[:space:]]*([^:[:space:]]+):([0-9a-f]{12})[[:space:]]*"-->"[[:space:]]*$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  # TOML/YAML/gitignore style: # bootstrap-content-version: KEY:SHA
  if [[ "$line" =~ ^#[[:space:]]*bootstrap-content-version:[[:space:]]*([^:[:space:]]+):([0-9a-f]{12})[[:space:]]*$ ]]; then
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

found_line=""
upstream_key=""
sha12=""

if parsed="$(extract_marker "$line1")"; then
  found_line="1"
  upstream_key="${parsed%$'\t'*}"
  sha12="${parsed#*$'\t'}"
elif parsed="$(extract_marker "$line2")"; then
  found_line="2"
  upstream_key="${parsed%$'\t'*}"
  sha12="${parsed#*$'\t'}"
fi

if [ -n "$found_line" ]; then
  jq -n \
    --arg key "$upstream_key" \
    --arg sha "$sha12" \
    --argjson line "$found_line" \
    '{found: true, upstream_key: $key, sha12: $sha, line: $line}'
else
  jq -n '{found: false, upstream_key: null, sha12: null, line: null}'
fi
exit 0
