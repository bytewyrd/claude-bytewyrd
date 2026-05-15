#!/usr/bin/env bats
# Tests for scripts/rfc-feedback-list.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-feedback-list.sh"
}

teardown() {
  teardown_common
}

@test "zero markers — empty markers array, exit 0" {
  create_rfc_fixture 2026-01-01-clean
  FIXTURE="docs/rfcs/2026-01-01-clean.md"
  run bash "$SCRIPT" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "0"
}

@test "column-0 FEEDBACK: marker — detected correctly" {
  cat > feedback-test.md <<'EOF'
## Summary

Some text.
FEEDBACK: Add more detail here.
EOF
  run bash "$SCRIPT" "feedback-test.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.markers[0].line')" "4"
  assert_equal "$(echo "$output" | jq -r '.markers[0].text')" "FEEDBACK: Add more detail here."
}

@test "two markers — both detected with correct line numbers" {
  cat > feedback-test2.md <<'EOF'
## Section One

FEEDBACK: First comment.

## Section Two

FEEDBACK: Second comment.
EOF
  run bash "$SCRIPT" "feedback-test2.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "2"
  assert_equal "$(echo "$output" | jq -r '.markers[0].line')" "3"
  assert_equal "$(echo "$output" | jq -r '.markers[1].line')" "7"
}

@test "non-FEEDBACK: lines not included" {
  cat > feedback-test3.md <<'EOF'
## Summary

Normal line.
NOTE: This is not a feedback marker.
FEEDBACK: This one is.
EOF
  run bash "$SCRIPT" "feedback-test3.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.markers[0].text')" "FEEDBACK: This one is."
}

@test "indented marker inside list item — detected" {
  cat > feedback-test4.md <<'EOF'
## Options

- Option A is good.
- FEEDBACK: This needs Y, inside a list item.
EOF
  run bash "$SCRIPT" "feedback-test4.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "1"
}

@test "nested bullet marker — detected" {
  cat > feedback-test5.md <<'EOF'
## Options

- Top level option.
  - FEEDBACK: Nested bullet feedback.
EOF
  run bash "$SCRIPT" "feedback-test5.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "1"
}

@test "blockquote marker — detected" {
  cat > feedback-test6.md <<'EOF'
## Risks

> FEEDBACK: Blockquote feedback here.
EOF
  run bash "$SCRIPT" "feedback-test6.md"
  assert_success
  assert_equal "$(echo "$output" | jq '.markers | length')" "1"
}

@test "missing file — exits 2 with error" {
  run bash "$SCRIPT" "docs/rfcs/nonexistent.md"
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
