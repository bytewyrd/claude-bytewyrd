#!/usr/bin/env bats
# Tests for scripts/sync-run.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-run.sh"

  # Initialize a git repo. sync-preflight.sh requires one.
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  git commit --allow-empty -q -m "init"

  # Redirect HOME so the installed-plugins probe does not touch the real env.
  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME/.claude"
  # Empty manifest — classify-all returns [] but exits 0.
  printf '{"artifacts":[]}\n' > "$FAKE_HOME/.claude/bootstrap-manifest.json"
  export HOME="$FAKE_HOME"

  unset CLAUDE_PLUGIN_ROOT
}

teardown() {
  teardown_common
}

@test "success — exits 0 and emits JSON with preflight and classifications keys" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e 'has(\"preflight\") and has(\"classifications\")'"
  assert_success
}

@test "success — preflight.project_slug is set" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.preflight.project_slug | length > 0'"
  assert_success
}

@test "success — classifications is a JSON array" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.classifications | type == \"array\"'"
  assert_success
}

@test "success — classifications is empty for an empty manifest" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq '.classifications | length'"
  assert_success
  assert_output "0"
}

@test "preflight failure propagates — not a git repo exits non-zero" {
  # Run from a directory that is not a git repo.
  tmp_dir="$(mktemp -d)"
  run bash -c "cd '$tmp_dir' && HOME='$FAKE_HOME' bash '$SCRIPT'"
  assert_failure
  rm -rf "$tmp_dir"
}

@test "success — output includes brief_complete, rfc_process, summary_text, all_unchanged" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e 'has(\"brief_complete\") and has(\"rfc_process\") and has(\"summary_text\") and has(\"all_unchanged\")'"
  assert_success
}

@test "success — all_unchanged is true when no actionable classifications" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.all_unchanged == true'"
  assert_success
}

@test "success — brief_complete is false when docs/project-brief.md is absent" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.brief_complete == false'"
  assert_success
}

@test "success — brief_complete is true when brief has real name and description" {
  mkdir -p docs
  printf '# My Project\n\n## Description\n\nA real project description.\n' > docs/project-brief.md
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -e '.brief_complete == true'"
  assert_success
}

@test "success — summary_text starts with /sync" {
  run bash "$SCRIPT"
  assert_success
  run bash -c "echo '$output' | jq -r '.summary_text' | head -1"
  assert_output "/sync — change summary:"
}
