# Shared helpers for tests/scripts/*.bats.
# Load in setup() via: load "helpers"
#
# Each test runs with CWD = TEST_TMPDIR (an isolated temp project root).
# Scripts use relative paths (docs/rfcs/, docs/rfc-braindump.md) and will
# find them inside TEST_TMPDIR, never inside the real project.
#
# SCRIPT_ROOT is set to the real project root so test files can reference
# scripts/ via absolute path: bash "$SCRIPT_ROOT/scripts/rfc-resolve.sh"

setup_common() {
  load "../bats-support/load"
  load "../bats-assert/load"
  load "../bats-file/load"
  # bats-file is now loaded; temp_make is available.
  TEST_TMPDIR="$(temp_make --prefix 'rfc-scripts-test-')"
  export TEST_TMPDIR
  # Absolute path to real project scripts/.
  SCRIPT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SCRIPT_ROOT
  # Pre-create the docs/ hierarchy so scripts don't fail on missing dirs.
  mkdir -p "$TEST_TMPDIR/docs/rfcs"
  # Run all scripts with CWD = TEST_TMPDIR so they see the fixture tree.
  cd "$TEST_TMPDIR"
}

teardown_common() {
  cd "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}" || cd / || true
  chmod -R u+w "$TEST_TMPDIR" 2>/dev/null || true
  temp_del "$TEST_TMPDIR"
}

# compute_upstream_key <manifest-entry-json>
# Mirrors _lib/common.bash:compute_upstream_key so tests can build matching
# markers without hard-coding fingerprints.
compute_upstream_key() {
  local entry="$1"
  local target fingerprint_input fingerprint
  target="$(printf '%s' "$entry" | jq -r '.target')"
  fingerprint_input="$(printf '%s' "$entry" | jq -Sc '{
    extension_strategy,
    owned_boundaries: (.owned_boundaries // []),
    owned_paths:      (.owned_paths      // [] | sort),
    owned_sections:   (.owned_sections   // [] | sort)
  }')"
  if command -v sha256sum >/dev/null 2>&1; then
    fingerprint="$(printf '%s' "$fingerprint_input" | sha256sum | cut -c1-8)"
  else
    fingerprint="$(printf '%s' "$fingerprint_input" | shasum -a 256 | cut -c1-8)"
  fi
  printf 'bytewyrd/%s@%s' "$target" "$fingerprint"
}

# Create a minimal docs/rfcs/<name>.md fixture in the current directory.
# Usage: create_rfc_fixture <stem> [status] [drop_reason]
# drop_reason is a raw drop_reason text (any YAML-significant characters are
# safely escaped). Pass "~" (the default) to emit the YAML-null sentinel.
create_rfc_fixture() {
  local name="$1" status="${2:-Draft}" drop_reason_raw="${3:-~}"
  local dr_yaml
  if [ "$drop_reason_raw" = "~" ]; then
    dr_yaml="~"
  else
    local escaped="${drop_reason_raw//\"/\\\"}"
    dr_yaml="\"$escaped\""
  fi
  mkdir -p docs/rfcs
  cat > "docs/rfcs/${name}.md" <<EOF
---
rfc: "$name"
title: "Test RFC"
author: "Test User"
status: "$status"
created: "2026-01-01"
drop_reason: $dr_yaml
---

## Summary

Test summary paragraph.
EOF
}

# Create a docs/rfc-braindump.md fixture in the current directory.
# Usage: create_braindump_fixture <body1> [<body2> ...]
create_braindump_fixture() {
  mkdir -p docs
  printf '# RFC Braindump\n\nPotential RFC ideas.\n\n' > docs/rfc-braindump.md
  for body in "$@"; do
    printf '* %s\n' "$body" >> docs/rfc-braindump.md
  done
}
