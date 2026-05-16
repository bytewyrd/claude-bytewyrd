#!/usr/bin/env bats
# Tests for scripts/sync-find-plugin-root.sh
#
# Each test isolates HOME and CLAUDE_PLUGIN_ROOT so the resolution logic is
# exercised against fixtures rather than the developer's real ~/.claude/.

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-find-plugin-root.sh"

  # Fresh HOME for every test; the script reads $HOME/.claude/* under the
  # hood, so a clean HOME removes interference from the real install.
  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME"
  export HOME="$FAKE_HOME"
  # Always start with CLAUDE_PLUGIN_ROOT unset.
  unset CLAUDE_PLUGIN_ROOT
}

teardown() {
  teardown_common
}

# --- env override -----------------------------------------------------------

@test "CLAUDE_PLUGIN_ROOT path wins when manifest exists there" {
  mkdir -p "$TEST_TMPDIR/plugin-root"
  printf '{"artifacts":[]}\n' > "$TEST_TMPDIR/plugin-root/bootstrap-manifest.json"
  run env CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/plugin-root" bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$TEST_TMPDIR/plugin-root"
  assert_equal "$(echo "$output" | jq -r .source)" "env"
}

@test "CLAUDE_PLUGIN_ROOT without manifest falls through to next branch" {
  mkdir -p "$TEST_TMPDIR/plugin-root-no-manifest"
  # Provide a home fallback so the test does not fail with not-found.
  mkdir -p "$FAKE_HOME/.claude"
  printf '{"artifacts":[]}\n' > "$FAKE_HOME/.claude/bootstrap-manifest.json"
  run env CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/plugin-root-no-manifest" bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .source)" "home"
}

# --- home fallback ----------------------------------------------------------

@test "home fallback when ~/.claude/bootstrap-manifest.json exists" {
  mkdir -p "$FAKE_HOME/.claude"
  printf '{"artifacts":[]}\n' > "$FAKE_HOME/.claude/bootstrap-manifest.json"
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$FAKE_HOME/.claude"
  assert_equal "$(echo "$output" | jq -r .source)" "home"
  assert_equal "$(echo "$output" | jq -r .manifest)" "$FAKE_HOME/.claude/bootstrap-manifest.json"
}

# --- cache search -----------------------------------------------------------

@test "cache search finds version directory" {
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.1.0"
  printf '{"artifacts":[]}\n' > "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.1.0/bootstrap-manifest.json"
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .source)" "cache"
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.1.0"
}

@test "cache search picks newest semantic version" {
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.1.0"
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.10.0"
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.2.0"
  printf '{}\n' > "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.1.0/bootstrap-manifest.json"
  printf '{}\n' > "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.10.0/bootstrap-manifest.json"
  printf '{}\n' > "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.2.0/bootstrap-manifest.json"
  run bash "$SCRIPT"
  assert_success
  # sort -V treats 0.10.0 > 0.2.0 > 0.1.0
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.10.0"
}

@test "cache search skips a version dir without a manifest" {
  # 0.2.0 has a manifest; 0.10.0 does not. The script must walk newest -> oldest
  # and pick the first one that contains bootstrap-manifest.json.
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.10.0"
  mkdir -p "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.2.0"
  printf '{}\n' > "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.2.0/bootstrap-manifest.json"
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$FAKE_HOME/.claude/plugins/cache/bytewyrd/bytewyrd/0.2.0"
}

# --- not-found -------------------------------------------------------------

@test "exits 1 with error when no manifest is found anywhere" {
  # FAKE_HOME has nothing; CLAUDE_PLUGIN_ROOT is unset; cache dir does not exist.
  run bash "$SCRIPT"
  assert_failure 1
  # Error JSON on stderr (the stdout contract is for success only).
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
