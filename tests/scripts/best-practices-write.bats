#!/usr/bin/env bats
# Tests for scripts/best-practices-write.py

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/best-practices-write.py"

  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME/.claude"
  export HOME="$FAKE_HOME"
  GLOBAL_FILE="$FAKE_HOME/.claude/BEST_PRACTICES.md"
}

teardown() {
  teardown_common
}

run_write() {
  echo "$1" | python3 "$SCRIPT"
}

@test "empty input — exits 0, all counts zero" {
  run run_write '{"project_entries":[],"global_entries":[],"write_sentinel":false,"patch_claude_md":false}'
  assert_success
  run bash -c "echo '$output' | jq -e '.project_count == 0 and .global_count == 0'"
  assert_success
}

@test "project entry — creates docs/BEST_PRACTICES.md and appends entry" {
  run run_write '{
    "project_entries": [{"section":"Architecture","label":"_Architecture_","text":"Test entry."}],
    "global_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  assert_file_exists docs/BEST_PRACTICES.md
  run grep '_Architecture_: Test entry.' docs/BEST_PRACTICES.md
  assert_success
}

@test "project entry — appends to existing section" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n- _Architecture_: Existing entry.\n' \
    > docs/BEST_PRACTICES.md
  run run_write '{
    "project_entries": [{"section":"Architecture","label":"_Architecture_","text":"New entry."}],
    "global_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run grep '_Architecture_: Existing entry.' docs/BEST_PRACTICES.md
  assert_success
  run grep '_Architecture_: New entry.' docs/BEST_PRACTICES.md
  assert_success
}

@test "project entry — creates new section when absent" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n- _Architecture_: Existing.\n' \
    > docs/BEST_PRACTICES.md
  run run_write '{
    "project_entries": [{"section":"Testing","label":"_Testing_","text":"New testing entry."}],
    "global_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run grep '## Testing' docs/BEST_PRACTICES.md
  assert_success
  run grep '_Testing_: New testing entry.' docs/BEST_PRACTICES.md
  assert_success
}

@test "project entry — Project-Specific section gets intro block on first creation" {
  mkdir -p docs
  printf '# Best Practices\n\n## Architecture\n\n- _Architecture_: Existing.\n' \
    > docs/BEST_PRACTICES.md
  run run_write '{
    "project_entries": [{"section":"Project-Specific","label":"_Project-Specific_","text":"A specific rule."}],
    "global_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run grep 'Entries below describe rules' docs/BEST_PRACTICES.md
  assert_success
  run grep '_Project-Specific_: A specific rule.' docs/BEST_PRACTICES.md
  assert_success
}

@test "global entry — creates ~/.claude/BEST_PRACTICES.md with rationale header" {
  run run_write '{
    "global_entries": [{"section":"Architecture","label":"_Architecture_","text":"Global entry."}],
    "project_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  assert_file_exists "$GLOBAL_FILE"
  run grep 'Where do entries live' "$GLOBAL_FILE"
  assert_success
  run grep '_Architecture_: Global entry.' "$GLOBAL_FILE"
  assert_success
}

@test "global entry — backfills rationale block for existing file missing it" {
  printf '# Global Best Practices\n\n## Architecture\n\n- _Architecture_: Old entry.\n' \
    > "$GLOBAL_FILE"
  run run_write '{
    "global_entries": [{"section":"Architecture","label":"_Architecture_","text":"New global."}],
    "project_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run grep 'Where do entries live' "$GLOBAL_FILE"
  assert_success
  run grep '_Architecture_: Old entry.' "$GLOBAL_FILE"
  assert_success
  run grep '_Architecture_: New global.' "$GLOBAL_FILE"
  assert_success
}

@test "write_sentinel true — creates .bytewyrd/precompact-extraction-done" {
  run run_write '{"project_entries":[],"global_entries":[],"write_sentinel":true,"patch_claude_md":false}'
  assert_success
  run bash -c "echo '$output' | jq -e '.sentinel_written == true'"
  assert_success
  assert_file_exists .bytewyrd/precompact-extraction-done
}

@test "patch_claude_md true — adds reference to CLAUDE.md" {
  printf '# My Project\n\nSome content.\n' > CLAUDE.md
  run run_write '{"project_entries":[],"global_entries":[],"write_sentinel":false,"patch_claude_md":true}'
  assert_success
  run bash -c "echo '$output' | jq -e '.claude_md_patched == true'"
  assert_success
  run grep 'BEST_PRACTICES' CLAUDE.md
  assert_success
}

@test "patch_claude_md true — no-op when reference already present" {
  printf '# My Project\n\nFor accumulated session learnings, see [BEST_PRACTICES.md](BEST_PRACTICES.md).\n' \
    > CLAUDE.md
  run run_write '{"project_entries":[],"global_entries":[],"write_sentinel":false,"patch_claude_md":true}'
  assert_success
  run bash -c "echo '$output' | jq -e '.claude_md_patched == false'"
  assert_success
}

@test "project_count reflects number of written entries" {
  run run_write '{
    "project_entries": [
      {"section":"Architecture","label":"_Architecture_","text":"Entry 1."},
      {"section":"Testing","label":"_Testing_","text":"Entry 2."}
    ],
    "global_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run bash -c "echo '$output' | jq -e '.project_count == 2'"
  assert_success
}

@test "global_count reflects number of written global entries" {
  run run_write '{
    "global_entries": [
      {"section":"Architecture","label":"_Architecture_","text":"Global entry 1."},
      {"section":"Workflow","label":"_Workflow_","text":"Global entry 2."}
    ],
    "project_entries": [],
    "write_sentinel": false,
    "patch_claude_md": false
  }'
  assert_success
  run bash -c "echo '$output' | jq -e '.global_count == 2'"
  assert_success
}
