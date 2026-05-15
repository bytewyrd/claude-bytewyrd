#!/usr/bin/env bats
# Tests for scripts/rfc-frontmatter.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-frontmatter.sh"
  create_rfc_fixture 2026-01-01-test-rfc
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "emits JSON with all six fields" {
  run bash "$SCRIPT" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .rfc)"         "2026-01-01-test-rfc"
  assert_equal "$(echo "$output" | jq -r .title)"       "Test RFC"
  assert_equal "$(echo "$output" | jq -r .author)"      "Test User"
  assert_equal "$(echo "$output" | jq -r .status)"      "Draft"
  assert_equal "$(echo "$output" | jq -r .created)"     "2026-01-01"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "normalizes drop_reason ~ to empty string" {
  create_rfc_fixture 2026-01-01-tilde Draft "~"
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-tilde.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "parses drop_reason when set to a non-null value" {
  create_rfc_fixture 2026-01-01-dropped Dropped "Superseded by another RFC."
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-dropped.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "Superseded by another RFC."
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
}

@test "exits 2 on missing file — error field present" {
  run bash "$SCRIPT" "docs/rfcs/does-not-exist.md"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 with no arguments — error field present" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 when file has no frontmatter delimiter" {
  printf '# Just a markdown file\n\nNo frontmatter.\n' > docs/rfcs/no-fm.md
  run bash "$SCRIPT" "docs/rfcs/no-fm.md"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
