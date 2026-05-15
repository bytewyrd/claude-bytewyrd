#!/usr/bin/env bats
# Tests for scripts/tool-probe.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/tool-probe.sh"
}

teardown() {
  teardown_common
}

@test "jq — available (exit 0, result=available)" {
  run bash "$SCRIPT" jq
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
  assert_equal "$(echo "$output" | jq -r .name)"   "jq"
}

@test "git — available when git is on PATH" {
  run bash "$SCRIPT" git
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
}

@test "gh — present on PATH and auth status determines result" {
  # gh is either available, missing, or unauthenticated on the test machine.
  run bash "$SCRIPT" gh
  # Both exit codes 0 and 1 are valid; exit 2 would be an error.
  if [ "$status" -eq 2 ]; then
    fail "tool-probe.sh gh exited 2 (usage error): $output"
  fi
  result="$(echo "$output" | jq -r .result)"
  case "$result" in
    available|missing|unauthenticated) ;;
    *) fail "Unexpected result value: $result" ;;
  esac
}

@test "gh not available — result is missing or unauthenticated, hint non-empty" {
  # On machines where gh is installed but not authenticated, the result is
  # "unauthenticated" (exit 1); on machines where gh is absent it is "missing"
  # (exit 1). Both are valid non-available outcomes with a non-empty hint.
  # Skip when gh is fully available and authenticated.
  if bash "$SCRIPT" gh >/dev/null 2>&1; then
    skip "gh is fully available and authenticated on this machine"
  fi
  run bash "$SCRIPT" gh
  assert_failure 1
  result="$(echo "$output" | jq -r .result)"
  case "$result" in
    missing|unauthenticated) ;;
    *) fail "Expected missing or unauthenticated, got: $result" ;;
  esac
  hint="$(echo "$output" | jq -r .hint)"
  [ -n "$hint" ]
}

@test "unrecognized probe name — exits 2 with error field" {
  run bash "$SCRIPT" nonsense
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2 with error field" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "github-mcp — missing when no settings.json present" {
  # TEST_TMPDIR has no .claude/settings.json, and HOME is unset.
  run env HOME="$TEST_TMPDIR" bash "$SCRIPT" github-mcp
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .result)" "missing"
  hint="$(echo "$output" | jq -r .hint)"
  [ -n "$hint" ]
}

@test "github-mcp — available when user settings has plugin enabled" {
  mkdir -p "$TEST_TMPDIR/.claude"
  printf '{"enabledPlugins":{"github@claude-plugins-official":true}}\n' \
    > "$TEST_TMPDIR/.claude/settings.json"
  run env HOME="$TEST_TMPDIR" bash "$SCRIPT" github-mcp
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
}

@test "github-mcp — missing when project settings overrides with false" {
  # User settings has it true, but project settings says false.
  mkdir -p "$TEST_TMPDIR/.claude"
  printf '{"enabledPlugins":{"github@claude-plugins-official":true}}\n' \
    > "$TEST_TMPDIR/.claude/settings.json"
  mkdir -p .claude
  printf '{"enabledPlugins":{"github@claude-plugins-official":false}}\n' \
    > .claude/settings.json
  run env HOME="$TEST_TMPDIR" bash "$SCRIPT" github-mcp
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .result)" "missing"
}

@test "code-review-mcp — missing when not configured" {
  run env HOME="$TEST_TMPDIR" bash "$SCRIPT" code-review-mcp
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .result)" "missing"
}
