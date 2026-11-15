#!/usr/bin/env bats
# Tests for `bw rfc-frontmatter`

setup() {
  load "helpers"
  setup_common
  create_rfc_fixture 2026-01-01-test-rfc
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "emits JSON with all six fields" {
  run bw rfc-frontmatter "$FIXTURE"
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
  run bw rfc-frontmatter "docs/rfcs/2026-01-01-tilde.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "parses drop_reason when set to a non-null value" {
  create_rfc_fixture 2026-01-01-dropped Dropped "Superseded by another RFC."
  run bw rfc-frontmatter "docs/rfcs/2026-01-01-dropped.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "Superseded by another RFC."
  assert_equal "$(echo "$output" | jq -r .status)"      "Dropped"
}

@test "exits 2 on missing file — error field present" {
  run bw rfc-frontmatter "docs/rfcs/does-not-exist.md"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 with no arguments — error field present" {
  run bw rfc-frontmatter
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 when file has no frontmatter delimiter" {
  printf '# Just a markdown file\n\nNo frontmatter.\n' > docs/rfcs/no-fm.md
  run bw rfc-frontmatter "docs/rfcs/no-fm.md"
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
  run bw rfc-frontmatter "docs/rfcs/2026-01-01-escaped.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .title)"       'Replace "sync" with scaffold'
  assert_equal "$(echo "$output" | jq -r .drop_reason)" 'Superseded by the "init" RFC; see C:\temp\notes.'
}

@test "reads back exactly what rfc-set-status.sh wrote for quotes and backslashes" {
  reason='Superseded by the "init" RFC; see C:\temp\notes, trailing\'
  run bw rfc-set-status "$FIXTURE" Dropped "$reason"
  assert_success
  run bw rfc-frontmatter "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" "$reason"
}

@test "plain values, such as an unquoted date, are read as written" {
  # rfc and created are plain values. The bash and YAML parsers read the plain
  # value holding quotes (title) and the quoted value with a trailing comment
  # (status) differently, so those two stay unchecked here.
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
  run bw rfc-frontmatter "docs/rfcs/2026-01-01-plain.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .rfc)"     "2026-01-01-plain"
  assert_equal "$(echo "$output" | jq -r .created)" "2026-01-01"
}
