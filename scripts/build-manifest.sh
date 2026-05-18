#!/usr/bin/env bash
# Regenerate bootstrap-manifest.json from current artifact content.
# Usage: build-manifest.sh           — regenerate in place
#        build-manifest.sh --check    — exit non-zero if regenerated differs from committed
set -euo pipefail

PLUGIN_ROOT="$(git rev-parse --show-toplevel)"
MANIFEST="$PLUGIN_ROOT/bootstrap-manifest.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Cross-platform sha256: prefer sha256sum, fall back to shasum -a 256.
hash_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | cut -d' ' -f1
  else
    shasum -a 256 "$f" | cut -d' ' -f1
  fi
}

# Source compute_upstream_key from the shared lib.
# shellcheck source=_lib/common.bash
source "$PLUGIN_ROOT/scripts/_lib/common.bash"

# Walk the existing manifest, recompute each artifact's sha256 from its source path
# and its upstream_key from strategy fingerprint.
# For templated artifacts (templated == true), the field name is template_sha;
# for non-templated artifacts, it is sha256. The script preserves all other fields
# (source, target, extension_strategy, owned_sections, owned_paths, templated,
#  template_inputs) from the existing manifest. upstream_key is always recomputed.

jq -c '.artifacts[]' "$MANIFEST" \
  | while read -r artifact; do
      source_rel=$(echo "$artifact" | jq -r '.source')
      source_abs="$PLUGIN_ROOT/$source_rel"
      if [[ ! -f "$source_abs" ]]; then
        echo "manifest references missing source: $source_rel" >&2
        exit 2
      fi
      full_hash=$(hash_file "$source_abs")
      # Manifest stores the full 64-char hash; the diff engine truncates to 12 at marker-write time.
      templated=$(echo "$artifact" | jq -r '.templated // false')
      field=$([[ "$templated" == "true" ]] && echo "template_sha" || echo "sha256")
      # Recompute upstream_key from strategy fingerprint (never preserved from existing manifest).
      upstream_key="$(compute_upstream_key "$artifact")"
      # Emit the updated artifact JSON on stdout.
      echo "$artifact" | jq --arg h "$full_hash" --arg f "$field" --arg uk "$upstream_key" \
        '.[$f] = $h | .upstream_key = $uk'
    done \
  | jq -s '{artifacts: (sort_by(.upstream_key))}' > "$TMP"

if [[ "${1:-}" == "--check" ]]; then
  if ! diff -q "$MANIFEST" "$TMP" >/dev/null; then
    echo "bootstrap-manifest.json is stale; run scripts/build-manifest.sh to regenerate." >&2
    diff "$MANIFEST" "$TMP" >&2 || true
    exit 1
  fi
  exit 0
fi

mv "$TMP" "$MANIFEST"
echo "Regenerated $MANIFEST"
