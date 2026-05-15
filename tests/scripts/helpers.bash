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
  load "../test_helper/bats-support/load"
  load "../test_helper/bats-assert/load"
  load "../test_helper/bats-file/load"
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
  temp_del "$TEST_TMPDIR"
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
