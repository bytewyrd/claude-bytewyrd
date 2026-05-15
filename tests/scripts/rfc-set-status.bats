#!/usr/bin/env bats
# Tests for scripts/rfc-set-status.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-set-status.sh"
  create_rfc_fixture 2026-01-01-test-rfc Draft
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "Draft to Approved — returns old/new status in JSON" {
  run bash "$SCRIPT" "$FIXTURE" Approved
  assert_success
  assert_equal "$(echo "$output" | jq -r .old_status)" "Draft"
  assert_equal "$(echo "$output" | jq -r .new_status)" "Approved"
  assert_equal "$(echo "$output" | jq -r .file)" "$FIXTURE"
}

@test "Draft to Approved — mutates the file in place" {
  bash "$SCRIPT" "$FIXTURE" Approved
  run bash "$SCRIPT_ROOT/scripts/rfc-frontmatter.sh" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)" "Approved"
}

@test "Approved to Done" {
  create_rfc_fixture 2026-01-01-approved Approved
  f="docs/rfcs/2026-01-01-approved.md"
  run bash "$SCRIPT" "$f" Done
  assert_success
  assert_equal "$(echo "$output" | jq -r .old_status)" "Approved"
  assert_equal "$(echo "$output" | jq -r .new_status)" "Done"
}

@test "Draft to Dropped with reason — sets drop_reason field" {
  run bash "$SCRIPT" "$FIXTURE" Dropped "Superseded by RFC 2026-02-01."
  assert_success
  assert_equal "$(echo "$output" | jq -r .new_status)" "Dropped"
  # Verify the file was updated.
  run bash "$SCRIPT_ROOT/scripts/rfc-frontmatter.sh" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "Superseded by RFC 2026-02-01."
}

@test "Dropped without reason — exits 2" {
  run bash "$SCRIPT" "$FIXTURE" Dropped
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "drop_reason provided for non-Dropped status — exits 2" {
  run bash "$SCRIPT" "$FIXTURE" Approved "some reason"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "invalid status — exits 2" {
  run bash "$SCRIPT" "$FIXTURE" Invalid
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing file — exits 2" {
  run bash "$SCRIPT" "docs/rfcs/nonexistent.md" Approved
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "injects drop_reason when no existing drop_reason field" {
  # Create an RFC without a drop_reason field.
  cat > docs/rfcs/2026-01-01-nodrop.md <<'EOF'
---
rfc: "2026-01-01-nodrop"
title: "No Drop RFC"
author: "Test User"
status: "Draft"
created: "2026-01-01"
---

## Summary

No drop_reason field in frontmatter.
EOF
  f="docs/rfcs/2026-01-01-nodrop.md"
  run bash "$SCRIPT" "$f" Dropped "No longer needed."
  assert_success
  run bash "$SCRIPT_ROOT/scripts/rfc-frontmatter.sh" "$f"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "No longer needed."
}
