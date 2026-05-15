#!/usr/bin/env bats
# Tests for scripts/rfc-braindump-list.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-braindump-list.sh"
}

teardown() {
  teardown_common
}

@test "absent file — returns empty entries array" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.entries | length')" "0"
}

@test "file with entries — numbered correctly from 1" {
  create_braindump_fixture "Alpha idea." "Beta idea." "Gamma idea."
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.entries | length')" "3"
  assert_equal "$(echo "$output" | jq -r '.entries[0].n')"    "1"
  assert_equal "$(echo "$output" | jq -r '.entries[0].body')" "Alpha idea."
  assert_equal "$(echo "$output" | jq -r '.entries[1].n')"    "2"
  assert_equal "$(echo "$output" | jq -r '.entries[1].body')" "Beta idea."
  assert_equal "$(echo "$output" | jq -r '.entries[2].n')"    "3"
  assert_equal "$(echo "$output" | jq -r '.entries[2].body')" "Gamma idea."
}

@test "header lines are not included as entries" {
  create_braindump_fixture "Only real entry."
  run bash "$SCRIPT"
  assert_success
  # Header lines start with #, not "* "; only bullet lines count.
  assert_equal "$(echo "$output" | jq '.entries | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.entries[0].body')" "Only real entry."
}

@test "file with no bullet entries — returns empty array" {
  mkdir -p docs
  printf '# RFC Braindump\n\nNo ideas yet.\n' > docs/rfc-braindump.md
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.entries | length')" "0"
}

@test "entries preserve file order" {
  create_braindump_fixture "First." "Second." "Third." "Fourth."
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.entries[3].body')" "Fourth."
}
