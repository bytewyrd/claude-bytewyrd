#!/usr/bin/env bats
# Tests for scripts/sync-item-parser.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-item-parser.sh"
}

teardown() {
  teardown_common
}

# --- markdown ---

@test "markdown — each top-level bullet is one item" {
  out="$(printf -- '- One\n- Two\n- Three\n' | bash "$SCRIPT" markdown)"
  assert_equal "$(echo "$out" | jq -r '.items | length')" "3"
  assert_equal "$(echo "$out" | jq -r '.items[0].type')" "bullet"
  assert_equal "$(echo "$out" | jq -r '.items[0].text')" "- One"
  assert_equal "$(echo "$out" | jq -r '.items[2].text')" "- Three"
}

@test "markdown — paragraph and bullet items distinguished by type" {
  out="$(printf 'A paragraph.\n\n- A bullet\n\nAnother paragraph.\n' | bash "$SCRIPT" markdown)"
  assert_equal "$(echo "$out" | jq -r '.items | length')" "3"
  assert_equal "$(echo "$out" | jq -r '.items[0].type')" "paragraph"
  assert_equal "$(echo "$out" | jq -r '.items[1].type')" "bullet"
  assert_equal "$(echo "$out" | jq -r '.items[2].type')" "paragraph"
}

@test "markdown — sub-bullet travels with parent" {
  out="$(printf -- '- Parent\n  - Child\n- Next\n' | bash "$SCRIPT" markdown)"
  assert_equal "$(echo "$out" | jq -r '.items | length')" "2"
  text0="$(echo "$out" | jq -r '.items[0].text')"
  case "$text0" in
    *"Parent"*"Child"*) ;;
    *) fail "expected sub-bullet to travel with parent: $text0" ;;
  esac
}

@test "markdown — code block is one item" {
  in='Intro.

```
fenced
code
```

Outro.'
  out="$(printf '%s\n' "$in" | bash "$SCRIPT" markdown)"
  # Should have 3 items: paragraph, codeblock, paragraph.
  assert_equal "$(echo "$out" | jq -r '.items | length')" "3"
  assert_equal "$(echo "$out" | jq -r '.items[1].type')" "codeblock"
  text1="$(echo "$out" | jq -r '.items[1].text')"
  case "$text1" in
    *"fenced"*"code"*) ;;
    *) fail "expected fenced lines inside codeblock item: $text1" ;;
  esac
}

@test "markdown — section extraction limits to one heading body" {
  in='# Title

Intro.

## Tool Usage

- A
- B

## Security

- C'
  out="$(printf '%s\n' "$in" | bash "$SCRIPT" markdown --section "## Tool Usage")"
  assert_equal "$(echo "$out" | jq -r '.section')" "## Tool Usage"
  assert_equal "$(echo "$out" | jq -r '.items | length')" "2"
}

# --- yaml ---

@test "yaml — top-level keys become one item each" {
  in='name: ci
on:
  push:
    branches:
      - main

jobs:
  rust:
    runs-on: ubuntu-latest'
  out="$(printf '%s\n' "$in" | bash "$SCRIPT" yaml)"
  # Three top-level keys: name, on, jobs.
  assert_equal "$(echo "$out" | jq -r '.items | length')" "3"
  assert_equal "$(echo "$out" | jq -r '.items[0].type')" "yaml-key"
  text0="$(echo "$out" | jq -r '.items[0].text')"
  case "$text0" in
    "name: ci") ;;
    *) fail "first yaml-key text mismatch: $text0" ;;
  esac
}

# --- error paths ---

@test "unknown file_type exits 2" {
  run bash -c "echo 'a' | bash $SCRIPT csv"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no file_type exits 2" {
  run bash -c "echo 'a' | bash $SCRIPT"
  assert_failure 2
}

@test "--section without value exits 2" {
  run bash -c "echo 'a' | bash $SCRIPT markdown --section"
  assert_failure 2
}
