#!/usr/bin/env bats
# Tests for scripts/rfc-braindump-append.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-braindump-append.sh"
}

teardown() {
  teardown_common
}

@test "append to existing file — appended=true, created_file=false" {
  create_braindump_fixture "Existing entry."
  run bash "$SCRIPT" "New entry."
  assert_success
  assert_equal "$(echo "$output" | jq -r .appended)"      "true"
  assert_equal "$(echo "$output" | jq -r .created_file)"  "false"
}

@test "append to existing file — new bullet appears in file" {
  create_braindump_fixture "Existing entry."
  bash "$SCRIPT" "New entry."
  run grep -q "^\* New entry\.$" docs/rfc-braindump.md
  assert_success
}

@test "create file when absent — created_file=true" {
  run bash "$SCRIPT" "First entry ever."
  assert_success
  assert_equal "$(echo "$output" | jq -r .created_file)" "true"
}

@test "create file when absent — file contains standard header" {
  bash "$SCRIPT" "First entry ever."
  run grep -q "# RFC Braindump" docs/rfc-braindump.md
  assert_success
}

@test "create file when absent — bullet is appended" {
  bash "$SCRIPT" "First entry ever."
  run grep -q "^\* First entry ever\.$" docs/rfc-braindump.md
  assert_success
}

@test "multiple appends — all entries accumulate" {
  bash "$SCRIPT" "Entry one."
  bash "$SCRIPT" "Entry two."
  bash "$SCRIPT" "Entry three."
  count="$(grep -c '^\* ' docs/rfc-braindump.md)"
  assert_equal "$count" "3"
}

@test "no argument — exits 2 with error" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
