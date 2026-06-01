#!/usr/bin/env bash
# Classify every artifact in bootstrap-manifest.json in a single invocation.
# Used by: sync (Step 4 — replaces N sequential sync-classify.sh calls).
#
# Reads the manifest at "<plugin_root>/bootstrap-manifest.json" and walks every
# artifact, calling sync-classify.sh for each one. The output for each artifact
# is enriched with the manifest entry fields the apply step needs (so the apply
# step never has to re-read the manifest):
#
#   - upstream_key       (string)
#   - source             (string, path relative to plugin root)
#   - templated          (bool)
#   - template_inputs    (array of strings)
#   - owned_paths        (array of strings, structured strategy only)
#   - owned_boundaries   (array of objects, owned-regions strategy only)
#   - owned_sections     (array of strings, additive-merge strategy only)
#
# Per-artifact errors (missing plugin source, unrecognized strategy) are
# captured as `{"classification":"error", ..., "error":"..."}` elements in the
# output array; they do not abort the run. The error is also written to stderr
# so it is visible in interactive sessions.
#
# Args:
#   $1  Required. Plugin root (must contain bootstrap-manifest.json).
#   $2  Optional. Repo root (the project where target files live). Defaults to
#       the caller's pwd. The script `cd`s here before the loop so relative
#       target paths in the manifest resolve correctly.
#   $3  Optional. Path to an enriched project_inputs.json (produced by
#       sync-compute-template-vars.sh). When provided, forwarded to
#       sync-classify.sh so templated structured artifacts (e.g.
#       settings.json.tpl) can be rendered before their SHA is computed.
#
# Output:
#   stdout: a single JSON array. Each element has the shape described above
#           plus the classify keys (classification, strategy, target,
#           recorded_sha, plugin_sha) — or the per-artifact error shape.
#   stderr: per-artifact error messages (one line each) when a classify call
#           fails. Empty otherwise.
#
# Exit codes:
#   0  Success (even when some artifacts produced per-element errors).
#   2  Bad arguments or missing manifest.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib/common.bash
source "$SCRIPT_DIR/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ]; then
  emit_error "usage: sync-classify-all.sh <plugin-root> [<repo-root>]"
  exit 2
fi

plugin_root="$1"
repo_root="${2:-$PWD}"
project_inputs_arg="${3:-}"

if [ ! -d "$plugin_root" ]; then
  emit_error "sync-classify-all: plugin root not found: $plugin_root"
  exit 2
fi

manifest="$plugin_root/bootstrap-manifest.json"
if [ ! -f "$manifest" ]; then
  emit_error "sync-classify-all: manifest not found: $manifest"
  exit 2
fi

# Normalize plugin_root to an absolute path so the cd below doesn't break
# relative invocations.
plugin_root="$(cd "$plugin_root" && pwd)"

if [ ! -d "$repo_root" ]; then
  emit_error "sync-classify-all: repo root not found: $repo_root"
  exit 2
fi

cd "$repo_root"

# Collect per-artifact result objects as newline-separated JSON, then wrap in
# an array at the end via `jq -s '.'`. This avoids building a big shell array.
tmp_out="$(mktemp)"
tmp_err="$(mktemp)"
trap 'rm -f "$tmp_out" "$tmp_err"' EXIT

while IFS= read -r entry; do
  [ -z "$entry" ] && continue

  upstream_key="$(printf '%s' "$entry" | jq -r '.upstream_key // ""')"
  target="$(printf '%s' "$entry" | jq -r '.target // ""')"

  if [ -z "$target" ]; then
    msg="sync-classify-all: manifest entry missing target: $upstream_key"
    printf '%s\n' "$msg" >&2
    jq -n \
      --arg upstream_key "$upstream_key" \
      --arg error "$msg" \
      '{classification: "error", target: "", upstream_key: $upstream_key, error: $error}' \
      >> "$tmp_out"
    continue
  fi

  # Run the classifier. Capture both stdout and exit code; never let a single
  # failing artifact abort the loop.
  classify_out=""
  classify_err=""
  classify_rc=0
  : > "$tmp_err"
  classify_out="$(bash "$SCRIPT_DIR/sync-classify.sh" "$entry" "$target" "$plugin_root" "$project_inputs_arg" 2>"$tmp_err")"
  classify_rc=$?
  classify_err="$(cat "$tmp_err" 2>/dev/null || true)"

  if [ "$classify_rc" -ne 0 ] || [ -z "$classify_out" ]; then
    # The classifier emits a JSON error on stdout — surface its message if
    # parseable, otherwise fall back to the captured stderr.
    err_msg="$(printf '%s' "$classify_out" | jq -r '.error // empty' 2>/dev/null || true)"
    if [ -z "$err_msg" ]; then
      err_msg="$classify_err"
    fi
    if [ -z "$err_msg" ]; then
      err_msg="sync-classify-all: classify failed for $upstream_key ($target)"
    fi
    printf '%s\n' "$err_msg" >&2
    jq -n \
      --arg classification "error" \
      --arg target "$target" \
      --arg upstream_key "$upstream_key" \
      --arg error "$err_msg" \
      '{classification: $classification, target: $target, upstream_key: $upstream_key, error: $error}' \
      >> "$tmp_out"
    continue
  fi

  # Make sure the classifier returned a JSON object before we try to merge.
  if ! printf '%s' "$classify_out" | jq -e 'type == "object"' >/dev/null 2>&1; then
    msg="sync-classify-all: classifier returned non-object for $upstream_key"
    printf '%s\n' "$msg" >&2
    jq -n \
      --arg classification "error" \
      --arg target "$target" \
      --arg upstream_key "$upstream_key" \
      --arg error "$msg" \
      '{classification: $classification, target: $target, upstream_key: $upstream_key, error: $error}' \
      >> "$tmp_out"
    continue
  fi

  # Merge classifier output + select manifest fields. The classifier already
  # carries `target`, `strategy`, `recorded_sha`, `plugin_sha`; we add the
  # remaining fields the apply step needs.
  printf '%s\n%s\n' "$entry" "$classify_out" \
    | jq -cs '
        .[1] + {
          upstream_key:     (.[0].upstream_key // ""),
          source:           (.[0].source // ""),
          templated:        (.[0].templated // false),
          template_inputs:  (.[0].template_inputs // []),
          owned_paths:      (.[0].owned_paths // []),
          owned_boundaries: (.[0].owned_boundaries // []),
          owned_sections:   (.[0].owned_sections // [])
        }
      ' \
    >> "$tmp_out"
done < <(jq -c '.artifacts[]' "$manifest")

# Wrap collected per-element objects into a JSON array.
if [ -s "$tmp_out" ]; then
  jq -s '.' < "$tmp_out"
else
  printf '[]\n'
fi

exit 0
