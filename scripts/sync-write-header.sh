#!/usr/bin/env bash
# Write (or replace) the two-line bootstrap header at the top of a file.
# Used by: sync (bootstrap_create / authoritative_add / authoritative_update apply actions).
#
# Header shape (line 1 is always the version marker):
#   Line 1: <!-- bootstrap-content-version: <upstream_key>:<sha12> -->
#   Line 2: <type-specific tagline>:
#     - bootstrap     -> <!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->
#     - authoritative -> <!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->
#
# If the file already starts with a recognized two-line plugin header (detected by
# strip_two_line_header logic — leading contiguous lines starting with the marker
# comment, the Managed comment, or the Bootstrapped comment, plus an immediately
# following blank line), the header is replaced. Otherwise it is prepended.
#
# Args:
#   $1  Required. Path to the file (must exist).
#   $2  Required. upstream_key (e.g. bytewyrd/README.md@v1).
#   $3  Required. sha12 (12 hex chars).
#   $4  Required. header type: "bootstrap" or "authoritative".
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"file": "<path>", "header_type": "<type>", "upstream_key": "<key>", "sha12": "<sha>"}
#     error (exit 2):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Success.
#   2  Usage error, missing file, or bad arguments.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ] || [ "${3:-}" = "" ] || [ "${4:-}" = "" ]; then
  emit_error "usage: sync-write-header.sh <file> <upstream_key> <sha12> <bootstrap|authoritative>"
  exit 2
fi

file="$1"
upstream_key="$2"
sha12="$3"
header_type="$4"

if [ ! -f "$file" ]; then
  emit_error "sync-write-header: file not found: $file"
  exit 2
fi

case "$header_type" in
  bootstrap)
    tagline='<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->'
    ;;
  authoritative)
    tagline='<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->'
    ;;
  *)
    emit_error "sync-write-header: header type must be 'bootstrap' or 'authoritative' (got: $header_type)"
    exit 2
    ;;
esac

if ! [[ "$sha12" =~ ^[0-9a-f]{12}$ ]]; then
  emit_error "sync-write-header: sha12 must be exactly 12 hex chars (got: $sha12)"
  exit 2
fi

marker="<!-- bootstrap-content-version: ${upstream_key}:${sha12} -->"

# Strip an existing two-line header (if any) using the same rule as
# strip_two_line_header: remove leading contiguous lines that start with one of
# the recognized header comment prefixes, then drop one blank line if present.
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

awk '
  BEGIN { in_header = 1 }
  in_header == 1 {
    # Recognized header lines: bootstrap-content-version marker, Managed-by,
    # Bootstrapped-by — match by the leading literal prefix.
    if ($0 ~ /^<!-- bootstrap-content-version:/ \
        || $0 ~ /^<!-- Managed by the Bytewyrd plugin\./ \
        || $0 ~ /^<!-- Bootstrapped by the Bytewyrd plugin\./) {
      next
    }
    # First non-header line: also consume one immediately following blank line.
    in_header = 0
    if ($0 == "") next
  }
  { print }
' "$file" > "$tmp_body"

# Write the new file with the two-line header prepended, followed by the body.
# Insert a blank line between the header and the body to preserve Markdown rendering
# if the body does not already begin with a blank line.
body_first_line="$(head -n1 "$tmp_body")"
{
  printf '%s\n' "$marker"
  printf '%s\n' "$tagline"
  if [ -n "$body_first_line" ]; then
    printf '\n'
  fi
  cat "$tmp_body"
} > "$file"

rm -f "$tmp_body"
trap - EXIT

jq -n \
  --arg file "$file" \
  --arg header_type "$header_type" \
  --arg upstream_key "$upstream_key" \
  --arg sha12 "$sha12" \
  '{file: $file, header_type: $header_type, upstream_key: $upstream_key, sha12: $sha12}'
exit 0
