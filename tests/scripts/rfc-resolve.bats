#!/usr/bin/env bats
# Tests for `bw rfc-resolve`

setup() {
  load "helpers"
  setup_common
  # Initialize a minimal git repo so git status works.
  git init -q
  git config commit.gpgsign false
  git config tag.gpgsign false
  git config user.email "test@test.com"
  git config user.name "Test"
  create_rfc_fixture 2026-01-01-alpha
  create_rfc_fixture 2026-02-01-beta
  create_rfc_fixture 2026-03-01-gamma
  git add . && git commit -q -m "initial"
}

teardown() {
  teardown_common
}

@test "explicit arg — matched file returns path and label" {
  run bw rfc-resolve "2026-01-01-alpha"
  assert_success
  path="$(echo "$output" | jq -r .path)"
  assert_equal "$(basename "$path")" "2026-01-01-alpha.md"
  label="$(echo "$output" | jq -r .label)"
  assert [ "$label" = "RFC 2026-01-01-alpha (matched argument)" ]
}

@test "explicit arg — accepts .md suffix" {
  run bw rfc-resolve "2026-01-01-alpha.md"
  assert_success
  path="$(echo "$output" | jq -r .path)"
  assert_equal "$(basename "$path")" "2026-01-01-alpha.md"
}

@test "explicit arg — accepts docs/rfcs/ prefix" {
  run bw rfc-resolve "docs/rfcs/2026-01-01-alpha.md"
  assert_success
  path="$(echo "$output" | jq -r .path)"
  assert_equal "$(basename "$path")" "2026-01-01-alpha.md"
}

@test "explicit arg — no match exits 1 with error field" {
  run bw rfc-resolve "does-not-exist"
  assert_failure 1
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "explicit arg — path separator exits 2 with error field" {
  run bw rfc-resolve "foo/bar"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arg — unique modified RFC picked by heuristic" {
  # Modify exactly one RFC so git status --short shows it.
  echo "extra line" >> docs/rfcs/2026-02-01-beta.md
  run bw rfc-resolve
  assert_success
  path="$(echo "$output" | jq -r .path)"
  assert_equal "$(basename "$path")" "2026-02-01-beta.md"
  label="$(echo "$output" | jq -r .label)"
  case "$label" in
    *"unique modified file"*) ;;
    *) fail "Expected label to contain 'unique modified file', got: $label" ;;
  esac
}

@test "no arg — falls back to most recent file when 0 modified" {
  # No untracked or modified files — all committed in setup.
  run bw rfc-resolve
  assert_success
  path="$(echo "$output" | jq -r .path)"
  # Most recent lexicographically is 2026-03-01-gamma.md
  assert_equal "$(basename "$path")" "2026-03-01-gamma.md"
  label="$(echo "$output" | jq -r .label)"
  case "$label" in
    *"most recently dated file"*) ;;
    *) fail "Expected label to contain 'most recently dated file', got: $label" ;;
  esac
}

@test "no arg — exits 1 when docs/rfcs/ is empty" {
  rm -f docs/rfcs/*.md
  git add . && git commit -q -m "remove all rfcs"
  run bw rfc-resolve
  assert_failure 1
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "exits 2 when docs/rfcs/ does not exist" {
  rm -rf docs/rfcs
  run bw rfc-resolve
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
