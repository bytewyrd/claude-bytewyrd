#!/usr/bin/env bats
# Tests for scripts/rfc-legacy-detect.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-legacy-detect.sh"
}

teardown() {
  teardown_common
}

@test "no legacy files — returns empty array" {
  create_rfc_fixture 2026-01-01-modern
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.legacy_files | length')" "0"
}

@test "one legacy file — returned in array" {
  create_rfc_fixture 2026-01-01-modern
  touch docs/rfcs/001-old-rfc.md
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.legacy_files | length')" "1"
  run bash -c "echo '$output' | jq -r '.legacy_files[0]'"
  assert [ "$output" = "docs/rfcs/001-old-rfc.md" ]
}

@test "mixed modern and legacy — only legacy emitted" {
  create_rfc_fixture 2026-01-01-modern
  create_rfc_fixture 2026-02-01-also-modern
  touch docs/rfcs/042-legacy.md
  touch docs/rfcs/007-another-legacy.md
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.legacy_files | length')" "2"
}

@test "exits 2 when docs/rfcs/ does not exist" {
  rmdir docs/rfcs
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
