#!/usr/bin/env bats
# Tests for `bw rfc-set-status`

setup() {
  load "helpers"
  setup_common
  create_rfc_fixture 2026-01-01-test-rfc Draft
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "Draft to Approved — returns old/new status in JSON" {
  run bw rfc-set-status "$FIXTURE" Approved
  assert_success
  assert_equal "$(echo "$output" | jq -r .old_status)" "Draft"
  assert_equal "$(echo "$output" | jq -r .new_status)" "Approved"
  assert_equal "$(echo "$output" | jq -r .file)" "$FIXTURE"
}

@test "Draft to Approved — mutates the file in place" {
  bw rfc-set-status "$FIXTURE" Approved
  run bw rfc-frontmatter "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)" "Approved"
}

@test "Approved to Done" {
  create_rfc_fixture 2026-01-01-approved Approved
  f="docs/rfcs/2026-01-01-approved.md"
  run bw rfc-set-status "$f" Done
  assert_success
  assert_equal "$(echo "$output" | jq -r .old_status)" "Approved"
  assert_equal "$(echo "$output" | jq -r .new_status)" "Done"
}

@test "Draft to Dropped with reason — sets drop_reason field" {
  run bw rfc-set-status "$FIXTURE" Dropped "Superseded by RFC 2026-02-01."
  assert_success
  assert_equal "$(echo "$output" | jq -r .new_status)" "Dropped"
  # Verify the file was updated.
  run bw rfc-frontmatter "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "Superseded by RFC 2026-02-01."
}

@test "Dropped without reason — exits 2" {
  run bw rfc-set-status "$FIXTURE" Dropped
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "drop_reason provided for non-Dropped status — exits 2" {
  run bw rfc-set-status "$FIXTURE" Approved "some reason"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "invalid status — exits 2" {
  run bw rfc-set-status "$FIXTURE" Invalid
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing file — exits 2" {
  run bw rfc-set-status "docs/rfcs/nonexistent.md" Approved
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2" {
  run bw rfc-set-status
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
  run bw rfc-set-status "$f" Dropped "No longer needed."
  assert_success
  run bw rfc-frontmatter "$f"
  assert_success
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "No longer needed."
}

# --- drop_reason escaping ---------------------------------------------------
# The reason ends up inside a YAML double-quoted scalar. Each test checks the
# exact line written, so the contract holds for any implementation of the script.

_require_pyyaml() {
  python3 -c 'import yaml' 2>/dev/null && return 0
  # CI installs PyYAML; never let these tests skip there.
  [ -z "${CI:-}" ] || fail "PyYAML is not importable, and CI must not skip these tests"
  skip "python3 with PyYAML is required to parse the rewritten frontmatter"
}

@test "drop_reason containing double quotes is written as an escaped YAML string" {
  run bw rfc-set-status "$FIXTURE" Dropped 'Superseded by the "init" RFC.'
  assert_success
  run grep -Fx 'drop_reason: "Superseded by the \"init\" RFC."' "$FIXTURE"
  assert_success
}

@test "drop_reason containing backslashes is escaped, not interpreted" {
  # A \t or \n typed in the reason must be written as \\t or \\n: a bare \t or
  # \n inside a YAML double-quoted string reads back as a tab or a newline.
  run bw rfc-set-status "$FIXTURE" Dropped 'Moved to C:\temp\new (see \n in the notes).'
  assert_success
  run grep -Fx 'drop_reason: "Moved to C:\\temp\\new (see \\n in the notes)."' "$FIXTURE"
  assert_success
}

@test "drop_reason ending in a backslash keeps the YAML string terminated" {
  run bw rfc-set-status "$FIXTURE" Dropped 'Folded into the parent RFC\'
  assert_success
  run grep -Fx 'drop_reason: "Folded into the parent RFC\\"' "$FIXTURE"
  assert_success
}

@test "drop_reason with quotes and backslashes round-trips through a YAML parser" {
  _require_pyyaml
  export REASON='say "hi", C:\temp\new, a\nb, trailing\'
  run bw rfc-set-status "$FIXTURE" Dropped "$REASON"
  assert_success
  run python3 - "$FIXTURE" <<'PY'
import os, sys, yaml

text = open(sys.argv[1], encoding="utf-8").read()
front = yaml.safe_load(text.split("---\n")[1])
assert front["status"] == "Dropped", front["status"]
assert front["drop_reason"] == os.environ["REASON"], repr(front["drop_reason"])
PY
  assert_success
}
