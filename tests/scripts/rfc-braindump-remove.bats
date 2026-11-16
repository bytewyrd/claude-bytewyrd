#!/usr/bin/env bats
# Tests for `bw rfc-braindump-remove`

setup() {
  load "helpers"
  setup_common
}

teardown() {
  teardown_common
}

@test "exact match — removed returns true and exit 0" {
  create_braindump_fixture "First entry." "Second entry to remove." "Third entry."
  run bw rfc-braindump-remove "Second entry to remove."
  assert_success
  assert_equal "$(echo "$output" | jq -r .removed)" "true"
}

@test "exact match — matching line is deleted from file" {
  create_braindump_fixture "Alpha." "Beta to remove." "Gamma."
  bw rfc-braindump-remove "Beta to remove."
  run grep -c "Beta to remove" docs/rfc-braindump.md
  assert_failure  # grep exits 1 when count is 0
}

@test "exact match — other entries remain" {
  create_braindump_fixture "Alpha." "Beta to remove." "Gamma."
  bw rfc-braindump-remove "Beta to remove."
  run grep -q "Alpha." docs/rfc-braindump.md
  assert_success
  run grep -q "Gamma." docs/rfc-braindump.md
  assert_success
}

@test "no match — returns removed=false and exit 1" {
  create_braindump_fixture "Only entry."
  run bw rfc-braindump-remove "Nonexistent entry."
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .removed)" "false"
}

@test "only first match removed when duplicates exist" {
  create_braindump_fixture "Duplicate." "Unique." "Duplicate."
  bw rfc-braindump-remove "Duplicate."
  # One instance should remain.
  count="$(grep -c "^\* Duplicate\.$" docs/rfc-braindump.md)"
  assert_equal "$count" "1"
}

@test "missing file — exits 2 with error" {
  run bw rfc-braindump-remove "Some entry."
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2 with error" {
  run bw rfc-braindump-remove
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
