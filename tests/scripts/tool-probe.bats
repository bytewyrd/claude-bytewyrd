#!/usr/bin/env bats
# Tests for `bw tool-probe`

setup() {
  load "helpers"
  setup_common
}

teardown() {
  teardown_common
}

@test "jq — available (exit 0, result=available)" {
  run bw tool-probe jq
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
  assert_equal "$(echo "$output" | jq -r .name)"   "jq"
}

@test "git — available when git is on PATH" {
  run bw tool-probe git
  assert_success
  assert_equal "$(echo "$output" | jq -r .result)" "available"
}

@test "gh — present on PATH and auth status determines result" {
  # gh is either available, missing, or unauthenticated on the test machine.
  run bw tool-probe gh
  # Both exit codes 0 and 1 are valid; exit 2 would be an error.
  if [ "$status" -eq 2 ]; then
    fail "bw tool-probe gh exited 2 (usage error): $output"
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
  if bw tool-probe gh >/dev/null 2>&1; then
    skip "gh is fully available and authenticated on this machine"
  fi
  run bw tool-probe gh
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
  run bw tool-probe nonsense
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments — exits 2 with error field" {
  run bw tool-probe
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
