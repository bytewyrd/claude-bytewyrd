#!/usr/bin/env bats
# Tests for scripts/sync-sidecar-migrate.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-sidecar-migrate.sh"
}

teardown() {
  teardown_common
}

@test "migrates when old exists and new does not" {
  mkdir -p .claude
  printf '{"k":"v"}' > .claude/.bootstrap-versions.json
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .migrated)" "true"
  # Old removed, new present with same content.
  refute [ -f .claude/.bootstrap-versions.json ]
  assert [ -f .bytewyrd/.bootstrap-versions.json ]
  assert_equal "$(cat .bytewyrd/.bootstrap-versions.json)" '{"k":"v"}'
}

@test "no-op when old is absent" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .migrated)" "false"
  refute [ -f .bytewyrd/.bootstrap-versions.json ]
}

@test "no-op when both old and new exist — old kept in place" {
  mkdir -p .claude .bytewyrd
  printf '{"old":1}' > .claude/.bootstrap-versions.json
  printf '{"new":1}' > .bytewyrd/.bootstrap-versions.json
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .migrated)" "false"
  # Both files still exist; content untouched.
  assert_equal "$(cat .claude/.bootstrap-versions.json)" '{"old":1}'
  assert_equal "$(cat .bytewyrd/.bootstrap-versions.json)" '{"new":1}'
}

@test "honors --old-path and --new-path overrides" {
  printf '{"a":1}' > custom-old.json
  run bash "$SCRIPT" --old-path custom-old.json --new-path nested/custom-new.json
  assert_success
  assert_equal "$(echo "$output" | jq -r .migrated)" "true"
  assert [ -f nested/custom-new.json ]
  refute [ -f custom-old.json ]
}

@test "rejects unknown argument" {
  run bash "$SCRIPT" --garbage
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "rejects --old-path without value" {
  run bash "$SCRIPT" --old-path
  assert_failure 2
}
