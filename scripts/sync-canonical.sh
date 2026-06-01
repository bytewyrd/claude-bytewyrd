#!/usr/bin/env bash
# Compute the canonical SHA-256 (first 12 hex chars) for a file under a given
# sync extension strategy.
#
# Used by: sync (Step 4 classification, Step 5 marker insertion).
#
# The "canonical form" is the strategy-specific projection of the file content
# that both local and plugin sides hash for comparison. Hashes must be directly
# comparable across the two sides, so this script is the single source of truth.
#
# Strategy-specific rules (kept aligned with skills/sync/SKILL.md):
#
# * authoritative
#     Strip the two-line plugin header from the input (the marker comment, the
#     Managed-by tagline, and one immediately following blank line), then hash
#     the remainder.
#
# * owned-regions   (alias: section)
#     For every boundary in --owned-boundaries, extract `<heading line>\n<body
#     to next H2/H1 or EOF, trimmed of leading and trailing blank lines>\n` and
#     concatenate. Missing boundaries contribute `<heading>\n\n`. Hash the
#     concatenation.
#
# * structured (JSON)
#     For every path in --owned-paths, extract the jq value (sorted keys),
#     serialize, and concatenate. The literal "*" wildcard means "hash the
#     whole document sorted-key serialized" (used by the .bootstrap-versions
#     sidecar).
#
# * structured (.gitignore)
#     For every tag in --owned-paths, extract the `# <tag>\n<body until blank
#     line>` block and concatenate. Hash the concatenation. Detection: the
#     file path ends with `.gitignore`.
#
# * additive-merge   (alias: additive-merge-with-diff)
#     For every heading in --owned-sections, extract `<heading line>\n<body to
#     next H2/H1 or EOF, trimmed>\n` and concatenate. Hash the concatenation.
#     (Identical body-extraction rule as owned-regions; what changes is which
#     manifest field provides the heading list.)
#
# Args:
#   $1  Required. Strategy name. One of:
#         authoritative | owned-regions | section | structured |
#         additive-merge | additive-merge-with-diff
#   $2  Required. Path to the file.
#
#   --owned-sections   <json-array>   Required for additive-merge[-with-diff].
#                                     JSON array of heading strings.
#   --owned-boundaries <json-array>   Required for owned-regions/section.
#                                     JSON array of {type,heading} objects.
#   --owned-paths      <json-array>   Required for structured.
#                                     JSON array of strings (jq paths or
#                                     .gitignore tags). May be ["*"].
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"sha12": "<12 hex chars>", "strategy": "<name>", "file": "<path>"}
#     error (exit 1 if file missing, 2 otherwise):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Success.
#   1  File not found (a soft "no" — caller may treat as "no canonical to compare").
#   2  Bad arguments or unrecognized strategy.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

# -------- argument parsing --------
strategy="${1:-}"
file="${2:-}"
shift 2 2>/dev/null || true

owned_sections_json="[]"
owned_boundaries_json="[]"
owned_paths_json="[]"

while [ $# -gt 0 ]; do
  case "$1" in
    --owned-sections)
      [ "${2:-}" = "" ] && { emit_error "sync-canonical: --owned-sections requires a value"; exit 2; }
      owned_sections_json="$2"; shift 2
      ;;
    --owned-boundaries)
      [ "${2:-}" = "" ] && { emit_error "sync-canonical: --owned-boundaries requires a value"; exit 2; }
      owned_boundaries_json="$2"; shift 2
      ;;
    --owned-paths)
      [ "${2:-}" = "" ] && { emit_error "sync-canonical: --owned-paths requires a value"; exit 2; }
      owned_paths_json="$2"; shift 2
      ;;
    *)
      emit_error "sync-canonical: unknown argument: $1"
      exit 2
      ;;
  esac
done

if [ -z "$strategy" ] || [ -z "$file" ]; then
  emit_error "usage: sync-canonical.sh <strategy> <file> [--owned-sections JSON | --owned-boundaries JSON | --owned-paths JSON]"
  exit 2
fi

if [ ! -f "$file" ]; then
  emit_error "sync-canonical: file not found: $file"
  exit 1
fi

# -------- helper: sha12 of stdin --------
sha12_of_stdin() {
  if command -v sha256sum >/dev/null; then
    sha256sum | awk '{print substr($1, 1, 12)}'
  else
    shasum -a 256 | awk '{print substr($1, 1, 12)}'
  fi
}

# -------- helper: strip the two-line plugin header from a file --------
# Removes leading contiguous lines that start with any of:
#   <!-- bootstrap-content-version:
#   <!-- Managed by the Bytewyrd plugin.
#   <!-- Bootstrapped by the Bytewyrd plugin.
# Then drops a single immediately following blank line.
strip_two_line_header() {
  awk '
    BEGIN { in_header = 1 }
    in_header == 1 {
      if ($0 ~ /^<!-- bootstrap-content-version:/ \
          || $0 ~ /^<!-- Managed by the Bytewyrd plugin\./ \
          || $0 ~ /^<!-- Bootstrapped by the Bytewyrd plugin\./) {
        next
      }
      in_header = 0
      if ($0 == "") next
    }
    { print }
  ' "$1"
}

# -------- helper: extract a heading section body (heading + body up to next H2/H1) --------
# stdin = file content
# arg1  = heading literal (e.g. "## Tool Usage")
# Output:
#   <heading>\n<body trimmed of leading/trailing blank lines>\n
# When the heading is absent in the file: emits `<heading>\n\n`.
extract_section() {
  local heading="$1"
  awk -v heading="$heading" '
    BEGIN { in_section = 0; collected = 0; body = ""; found = 0 }
    {
      if ($0 == heading) {
        found = 1; in_section = 1; next
      }
      if (in_section == 1) {
        # End on next H2 or H1.
        if ($0 ~ /^## / || $0 ~ /^# /) {
          in_section = 0
        } else {
          if (body == "") body = $0
          else            body = body "\n" $0
        }
      }
    }
    END {
      # Trim leading blank lines.
      sub(/^[[:space:]\n]+/, "", body)
      # Trim trailing blank lines.
      sub(/[[:space:]\n]+$/, "", body)
      if (found == 0) {
        printf "%s\n\n", heading
      } else {
        printf "%s\n%s\n", heading, body
      }
    }
  '
}

# -------- helper: extract a .gitignore tagged block --------
# stdin = file content
# arg1  = tag (e.g. "bytewyrd:base")
# Output: `# <tag>\n<lines until blank line or EOF>\n`
extract_gitignore_block() {
  local tag="$1"
  awk -v tag="$tag" '
    BEGIN { in_block = 0 }
    {
      if ($0 == "# " tag) {
        in_block = 1
        print $0
        next
      }
      if (in_block == 1) {
        if ($0 == "") { in_block = 0; print ""; next }
        print $0
      }
    }
    END {
      if (in_block == 1) printf "\n"
    }
  '
}

# -------- helper: structured JSON canonicalization --------
# args: json array of path strings.
structured_json_canonical() {
  local paths_json="$1"
  local count
  count="$(echo "$paths_json" | jq -r 'length')"
  if [ "$count" -eq 0 ]; then
    # No owned paths — treat as empty.
    printf ''
    return
  fi
  local i path piece
  for ((i = 0; i < count; i++)); do
    path="$(echo "$paths_json" | jq -r ".[$i]")"
    if [ "$path" = "*" ]; then
      # Whole-document mode.
      piece="$(jq -S '.' < "$file")"
      printf '%s\n' "$piece"
      continue
    fi
    # id-based array path: "<base>[]:<id_key>"
    if [[ "$path" =~ ^(.+)\[\]:([A-Za-z0-9_.-]+)$ ]]; then
      local base="${BASH_REMATCH[1]}"
      local id_key="${BASH_REMATCH[2]}"
      if [ "$id_key" = "union" ]; then
        # set-union — plugin side is not derivable from the local file alone;
        # to make local and plugin SHAs comparable we serialize the whole
        # array sorted by stringified entry. This is the closest deterministic
        # canonical that does not require side information.
        piece="$(jq -S "(.${base} // []) | sort" < "$file")"
        printf '%s\n' "$piece"
      else
        # Serialize entries with a non-empty id field, sorted by id.
        piece="$(jq -S --arg key "$id_key" '
          (.'"$base"' // [])
          | map(select(.[$key] != null and .[$key] != ""))
          | sort_by(.[$key])
        ' < "$file")"
        printf '%s\n' "$piece"
      fi
      continue
    fi
    # Dot-path. Use jq getpath via a tiny eval helper.
    piece="$(jq -S ".${path}" < "$file" 2>/dev/null || printf 'null')"
    printf '%s\n' "$piece"
  done
}

# -------- helper: gitignore canonicalization --------
gitignore_canonical() {
  local paths_json="$1"
  local count
  count="$(echo "$paths_json" | jq -r 'length')"
  if [ "$count" -eq 0 ]; then
    printf ''
    return
  fi
  local i tag
  for ((i = 0; i < count; i++)); do
    tag="$(echo "$paths_json" | jq -r ".[$i]")"
    extract_gitignore_block "$tag" < "$file"
  done
}

# -------- main dispatch --------
emit_sha() {
  local sha="$1"
  jq -n --arg sha "$sha" --arg strategy "$strategy" --arg file "$file" \
    '{sha12: $sha, strategy: $strategy, file: $file}'
}

case "$strategy" in
  authoritative)
    canonical="$(strip_two_line_header "$file")"
    sha="$(printf '%s' "$canonical" | sha12_of_stdin)"
    emit_sha "$sha"
    ;;
  owned-regions|section)
    if [ "$(echo "$owned_boundaries_json" | jq -r 'type')" != "array" ]; then
      emit_error "sync-canonical: --owned-boundaries must be a JSON array"; exit 2
    fi
    count="$(echo "$owned_boundaries_json" | jq -r 'length')"
    out=""
    for ((i = 0; i < count; i++)); do
      heading="$(echo "$owned_boundaries_json" | jq -r ".[$i].heading")"
      piece="$(extract_section "$heading" < "$file")"
      out="${out}${piece}"
    done
    sha="$(printf '%s' "$out" | sha12_of_stdin)"
    emit_sha "$sha"
    ;;
  additive-merge|additive-merge-with-diff)
    if [ "$(echo "$owned_sections_json" | jq -r 'type')" != "array" ]; then
      emit_error "sync-canonical: --owned-sections must be a JSON array"; exit 2
    fi
    count="$(echo "$owned_sections_json" | jq -r 'length')"
    out=""
    for ((i = 0; i < count; i++)); do
      heading="$(echo "$owned_sections_json" | jq -r ".[$i]")"
      piece="$(extract_section "$heading" < "$file")"
      out="${out}${piece}"
    done
    sha="$(printf '%s' "$out" | sha12_of_stdin)"
    emit_sha "$sha"
    ;;
  structured)
    if [ "$(echo "$owned_paths_json" | jq -r 'type')" != "array" ]; then
      emit_error "sync-canonical: --owned-paths must be a JSON array"; exit 2
    fi
    case "$file" in
      *.gitignore)
        canonical="$(gitignore_canonical "$owned_paths_json")"
        ;;
      *)
        canonical="$(structured_json_canonical "$owned_paths_json")"
        ;;
    esac
    sha="$(printf '%s' "$canonical" | sha12_of_stdin)"
    emit_sha "$sha"
    ;;
  *)
    emit_error "sync-canonical: unrecognized strategy: $strategy"
    exit 2
    ;;
esac

exit 0
