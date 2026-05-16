#!/usr/bin/env bats
# Tests for scripts/best-practices-preflight.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/best-practices-preflight.sh"

  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME/.claude"
  export HOME="$FAKE_HOME"
}

teardown() {
  teardown_common
}

@test "success — exits 0 and emits valid JSON" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e 'has(\"project_file_exists\")'"
  assert_success
}

@test "project_file_exists is false when docs/BEST_PRACTICES.md is absent" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.project_file_exists == false'"
  assert_success
}

@test "project_file_exists is true when docs/BEST_PRACTICES.md is present" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n- _Architecture_: Entry 1.\n' \
    > docs/BEST_PRACTICES.md
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.project_file_exists == true'"
  assert_success
}

@test "project_sections lists headers from docs/BEST_PRACTICES.md" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n## Testing\n' \
    > docs/BEST_PRACTICES.md
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.project_sections | contains([\"Architecture\", \"Testing\"])'"
  assert_success
}

@test "project_entries lists bullet lines from docs/BEST_PRACTICES.md" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n- _Architecture_: My entry.\n' \
    > docs/BEST_PRACTICES.md
  bash "$SCRIPT" > "$TEST_TMPDIR/preflight.json"
  run jq -e '.project_entries | length > 0' "$TEST_TMPDIR/preflight.json"
  assert_success
  run jq -r '.project_entries[0]' "$TEST_TMPDIR/preflight.json"
  assert_output "- _Architecture_: My entry."
}

@test "global_file_exists is false when ~/.claude/BEST_PRACTICES.md is absent" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.global_file_exists == false'"
  assert_success
}

@test "global_file_exists is true when ~/.claude/BEST_PRACTICES.md is present" {
  printf '# Global Best Practices\n\n## Architecture\n\n- _Architecture_: Global entry.\n' \
    > "$FAKE_HOME/.claude/BEST_PRACTICES.md"
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.global_file_exists == true'"
  assert_success
}

@test "global_has_rationale is true when rationale block is present" {
  printf '# Global Best Practices\n\n## Where do entries live, and why?\n\nSome text.\n' \
    > "$FAKE_HOME/.claude/BEST_PRACTICES.md"
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.global_has_rationale == true'"
  assert_success
}

@test "global_has_rationale is false when rationale block is absent" {
  printf '# Global Best Practices\n\n## Architecture\n\n- _Architecture_: Entry.\n' \
    > "$FAKE_HOME/.claude/BEST_PRACTICES.md"
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.global_has_rationale == false'"
  assert_success
}

@test "claude_md_has_ref is true when CLAUDE.md references BEST_PRACTICES" {
  printf '# CLAUDE\n\nFor accumulated session learnings, see [BEST_PRACTICES.md](BEST_PRACTICES.md).\n' \
    > CLAUDE.md
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.claude_md_has_ref == true'"
  assert_success
}

@test "claude_md_has_ref is false when CLAUDE.md is absent" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.claude_md_has_ref == false'"
  assert_success
}

@test "output includes gh_available and gh_result keys" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e 'has(\"gh_available\") and has(\"gh_result\")'"
  assert_success
}
