#!/usr/bin/env bats
# Tests for scripts/rfc-summary.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-summary.sh"
}

teardown() {
  teardown_common
}

@test "empty docs/rfcs/ — returns empty rfcs array" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.rfcs | length')" "0"
  assert_equal "$(echo "$output" | jq '.warnings | length')" "0"
}

@test "single RFC — appears in output" {
  create_rfc_fixture 2026-01-01-solo
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.rfcs | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.rfcs[0].rfc')" "2026-01-01-solo"
}

@test "multiple RFCs — sorted by created then rfc" {
  create_rfc_fixture 2026-03-01-charlie Draft
  create_rfc_fixture 2026-01-01-alpha Draft
  create_rfc_fixture 2026-02-01-beta Draft
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.rfcs | length')" "3"
  assert_equal "$(echo "$output" | jq -r '.rfcs[0].rfc')" "2026-01-01-alpha"
  assert_equal "$(echo "$output" | jq -r '.rfcs[1].rfc')" "2026-02-01-beta"
  assert_equal "$(echo "$output" | jq -r '.rfcs[2].rfc')" "2026-03-01-charlie"
}

@test "RFC with unrecognized status — skipped with warning" {
  create_rfc_fixture 2026-01-01-good Draft
  # Create a fixture with invalid status manually.
  cat > docs/rfcs/2026-01-01-bad.md <<'EOF'
---
rfc: "2026-01-01-bad"
title: "Bad RFC"
author: "Test User"
status: "Pending"
created: "2026-01-01"
drop_reason: ~
---

## Summary

Has an invalid status.
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.rfcs | length')" "1"
  assert [ "$(echo "$output" | jq '.warnings | length')" -ge "1" ]
}

@test "RFC with empty rfc field — skipped with warning" {
  cat > docs/rfcs/2026-01-01-norfc.md <<'EOF'
---
rfc: ""
title: "No RFC ID"
author: "Test User"
status: "Draft"
created: "2026-01-01"
drop_reason: ~
---

## Summary

Missing rfc field.
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq '.rfcs | length')" "0"
  assert [ "$(echo "$output" | jq '.warnings | length')" -ge "1" ]
}

@test "exits 2 when docs/rfcs/ does not exist" {
  rmdir docs/rfcs
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "output contains warnings array" {
  create_rfc_fixture 2026-01-01-clean Draft
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.warnings'"
  assert_success
}
