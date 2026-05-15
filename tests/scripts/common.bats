#!/usr/bin/env bats
# Tests for scripts/_lib/common.bash

setup() {
  load "helpers"
  setup_common
  LIB="$SCRIPT_ROOT/scripts/_lib/common.bash"
}

teardown() {
  teardown_common
}

# ---------------------------------------------------------------------------
# require_jq
# ---------------------------------------------------------------------------

@test "require_jq: exits 0 when jq is on PATH" {
  run bash -c ". '$LIB' && require_jq"
  assert_success
}

@test "require_jq: exits 2 with static JSON error when jq is absent" {
  # Shadow jq with a wrapper that is not found.
  mkdir -p "$TEST_TMPDIR/bin"
  run bash --norc --noprofile -c "
    export PATH='$TEST_TMPDIR/bin'
    . '$LIB'
    require_jq
  "
  assert_failure 2
  assert_output '{"error":"jq not found on PATH"}'
}

# ---------------------------------------------------------------------------
# emit_error
# ---------------------------------------------------------------------------

@test "emit_error: .error field matches argument" {
  run bash -c ". '$LIB' && require_jq && emit_error 'something went wrong'"
  assert_success
  assert_equal "$(echo "$output" | jq -r .error)" "something went wrong"
}

@test "emit_error: output has no extra top-level keys" {
  run bash -c ". '$LIB' && require_jq && emit_error 'x'"
  assert_success
  assert_equal "$(echo "$output" | jq 'keys | length')" "1"
}

# ---------------------------------------------------------------------------
# emit_available
# ---------------------------------------------------------------------------

@test "emit_available: .result is 'available' and .name matches argument" {
  run bash -c ". '$LIB' && require_jq && emit_available 'gh'"
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
  assert_equal "$(echo "$output" | jq -r .name)"   "gh"
}

# ---------------------------------------------------------------------------
# emit_missing
# ---------------------------------------------------------------------------

@test "emit_missing: .result is 'missing', .name and .hint match arguments" {
  run bash -c ". '$LIB' && require_jq && emit_missing 'gh' 'install gh first'"
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "missing"
  assert_equal "$(echo "$output" | jq -r .name)"   "gh"
  assert_equal "$(echo "$output" | jq -r .hint)"   "install gh first"
}

# ---------------------------------------------------------------------------
# emit_unauth
# ---------------------------------------------------------------------------

@test "emit_unauth: .result is 'unauthenticated', .name and .hint match arguments" {
  run bash -c ". '$LIB' && require_jq && emit_unauth 'gh' 'run gh auth login'"
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "unauthenticated"
  assert_equal "$(echo "$output" | jq -r .name)"   "gh"
  assert_equal "$(echo "$output" | jq -r .hint)"   "run gh auth login"
}

# ---------------------------------------------------------------------------
# plugin_enabled
# ---------------------------------------------------------------------------

@test "plugin_enabled: returns 0 when project settings has true" {
  mkdir -p .claude
  printf '{"myPlugin":true}\n' > .claude/settings.json
  run bash -c ". '$LIB' && plugin_enabled 'myPlugin'"
  assert_success
}

@test "plugin_enabled: returns 1 when project settings has explicit false" {
  mkdir -p .claude
  printf '{"myPlugin":false}\n' > .claude/settings.json
  run bash -c ". '$LIB' && plugin_enabled 'myPlugin'"
  assert_failure
}

@test "plugin_enabled: project false overrides user true" {
  mkdir -p .claude
  printf '{"myPlugin":false}\n' > .claude/settings.json
  local fake_home="$TEST_TMPDIR/home"
  mkdir -p "$fake_home/.claude"
  printf '{"myPlugin":true}\n' > "$fake_home/.claude/settings.json"
  run bash -c "export HOME='$fake_home'; source '$LIB'; plugin_enabled 'myPlugin'"
  assert_failure
}

@test "plugin_enabled: returns 0 when only user settings has true (no project settings)" {
  local fake_home="$TEST_TMPDIR/home"
  mkdir -p "$fake_home/.claude"
  printf '{"myPlugin":true}\n' > "$fake_home/.claude/settings.json"
  run bash -c "export HOME='$fake_home'; source '$LIB'; plugin_enabled 'myPlugin'"
  assert_success
}

@test "plugin_enabled: returns 1 when no settings files exist" {
  local fake_home="$TEST_TMPDIR/home"
  mkdir -p "$fake_home"
  run bash -c "export HOME='$fake_home'; source '$LIB'; plugin_enabled 'myPlugin'"
  assert_failure
}
