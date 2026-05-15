#!/usr/bin/env bats
# Tests for scripts/rfc-braindump-remove.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-braindump-remove.sh"
}

teardown() {
  teardown_common
}

@test "exact match — removed returns true and exit 0" {
  create_braindump_fixture "First entry." "Second entry to remove." "Third entry."
  run bash "$SCRIPT" "Second entry to remove."
  assert_success
  assert_equal "$(echo "$output" | jq -r .removed)" "true"
}

@test "exact match — matching line is deleted from file" {
  create_braindump_fixture "Alpha." "Beta to remove." "Gamma."
  bash "$SCRIPT" "Beta to remove."
  run grep -c "Beta to remove" docs/rfc-braindump.md
  assert_failure  # grep exits 1 when count is 0
}

@test "exact match — other entries remain" {
  create_braindump_fixture "Alpha." "Beta to remove." "Gamma."
  bash "$SCRIPT" "Beta to remove."
  run grep -q "Alpha." docs/rfc-braindump.md
  assert_success
  run grep -q "Gamma." docs/rfc-braindump.md
  assert_success
}

@test "no match — returns removed=false and exit 1" {
  create_braindump_fixture "Only entry."
  run bash "$SCRIPT" "Nonexistent entry."
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .removed)" "false"
}

@test "only first match removed when duplicates exist" {
  create_braindump_fixture "Duplicate." "Unique." "Duplicate."
  bash "$SCRIPT" "Duplicate."
  # One instance should remain.
  count="$(grep -c "^\* Duplicate\.$" docs/rfc-braindump.md)"
  assert_equal "$count" "1"
}

@test "missing file — exits 2 with error" {
  run bash "$SCRIPT" "Some entry."
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2 with error" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
