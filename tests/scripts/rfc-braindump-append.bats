#!/usr/bin/env bats
# Tests for `bw rfc-braindump-append`

setup() {
  load "helpers"
  setup_common
}

teardown() {
  teardown_common
}

@test "append to existing file — appended=true, created_file=false" {
  create_braindump_fixture "Existing entry."
  run bw rfc-braindump-append "New entry."
  assert_success
  assert_equal "$(echo "$output" | jq -r .appended)"      "true"
  assert_equal "$(echo "$output" | jq -r .created_file)"  "false"
}

@test "append to existing file — new bullet appears in file" {
  create_braindump_fixture "Existing entry."
  bw rfc-braindump-append "New entry."
  run grep -q "^\* New entry\.$" docs/rfc-braindump.md
  assert_success
}

@test "create file when absent — created_file=true" {
  run bw rfc-braindump-append "First entry ever."
  assert_success
  assert_equal "$(echo "$output" | jq -r .created_file)" "true"
}

@test "create file when absent — file contains standard header" {
  bw rfc-braindump-append "First entry ever."
  run grep -q "# RFC Braindump" docs/rfc-braindump.md
  assert_success
}

@test "create file when absent — bullet is appended" {
  bw rfc-braindump-append "First entry ever."
  run grep -q "^\* First entry ever\.$" docs/rfc-braindump.md
  assert_success
}

@test "multiple appends — all entries accumulate" {
  bw rfc-braindump-append "Entry one."
  bw rfc-braindump-append "Entry two."
  bw rfc-braindump-append "Entry three."
  count="$(grep -c '^\* ' docs/rfc-braindump.md)"
  assert_equal "$count" "3"
}

@test "no argument — exits 2 with error" {
  run bw rfc-braindump-append
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
