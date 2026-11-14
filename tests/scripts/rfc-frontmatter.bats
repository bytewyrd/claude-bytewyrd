#!/usr/bin/env bats
# Tests for scripts/rfc-frontmatter.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-frontmatter.sh"
  create_rfc_fixture 2026-01-01-test-rfc
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "emits JSON with all six fields" {
  run bash "$SCRIPT" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .rfc)"         "2026-01-01-test-rfc"
  assert_equal "$(echo "$output" | jq -r .title)"       "Test RFC"
  assert_equal "$(echo "$output" | jq -r .author)"      "Test User"
  assert_equal "$(echo "$output" | jq -r .status)"      "Draft"
  assert_equal "$(echo "$output" | jq -r .created)"     "2026-01-01"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "normalizes drop_reason ~ to empty string" {
  create_rfc_fixture 2026-01-01-tilde Draft "~"
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-tilde.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "parses drop_reason when set to a non-null value" {
  create_rfc_fixture 2026-01-01-dropped Dropped "Superseded by another RFC."
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-dropped.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "Superseded by another RFC."
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
}

@test "exits 2 on missing file — error field present" {
  run bash "$SCRIPT" "docs/rfcs/does-not-exist.md"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 with no arguments — error field present" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 when file has no frontmatter delimiter" {
  printf '# Just a markdown file\n\nNo frontmatter.\n' > docs/rfcs/no-fm.md
  run bash "$SCRIPT" "docs/rfcs/no-fm.md"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

# --- YAML double-quoted escapes ---------------------------------------------
# rfc-set-status.sh writes drop_reason as a YAML double-quoted scalar and escapes
# \ and " inside it. The reader must give back the original text.

@test "unescapes \\\" and \\\\ in double-quoted values" {
  cat > docs/rfcs/2026-01-01-escaped.md <<'EOS'
---
rfc: "2026-01-01-escaped"
title: "Replace \"sync\" with scaffold"
author: "Test User"
status: "Dropped"
created: "2026-01-01"
drop_reason: "Superseded by the \"init\" RFC; see C:\\temp\\notes."
---

## Summary
EOS
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-escaped.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .title)"       'Replace "sync" with scaffold'
  assert_equal "$(echo "$output" | jq -r .drop_reason)" 'Superseded by the "init" RFC; see C:\temp\notes.'
}

@test "reads back exactly what rfc-set-status.sh wrote for quotes and backslashes" {
  reason='Superseded by the "init" RFC; see C:\temp\notes, trailing\'
  run bash "$SCRIPT_ROOT/scripts/rfc-set-status.sh" "$FIXTURE" Dropped "$reason"
  assert_success
  run bash "$SCRIPT" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "$reason"
}

@test "a value that is not a clean double-quoted scalar still has its quotes dropped" {
  # Plain and trailing-comment values are not unescaped: the old behaviour stays.
  cat > docs/rfcs/2026-01-01-plain.md <<'EOS'
---
rfc: 2026-01-01-plain
title: Plain "title"
author: "Test User"
status: "Draft" # still a draft
created: 2026-01-01
drop_reason: ~
---
EOS
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-plain.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .rfc)"     "2026-01-01-plain"
  assert_equal "$(echo "$output" | jq -r .title)"   "Plain title"
  assert_equal "$(echo "$output" | jq -r .status)"  "Draft # still a draft"
  assert_equal "$(echo "$output" | jq -r .created)" "2026-01-01"
}
