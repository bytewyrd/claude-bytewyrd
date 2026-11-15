#!/usr/bin/env bats
# Tests for `bw state-touch [--rm] [NAME]`, the only writer into .bytewyrd/
# (RFC 2026-11-09-scaffold-and-drift, B2 and B4): a symlinked .bytewyrd or NAME
# leaves the outside directory unchanged, --rm removes only a regular file, and
# once running it always exits 0. tests/py/test_bw.py swaps .bytewyrd for a
# symlink after it is opened.

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
  load "python-stubs"
  require_bw_python
  BW="$SCRIPT_ROOT/scripts/bw"
  OUTSIDE="$TEST_TMPDIR/outside"
  mkdir "$OUTSIDE" "$TEST_TMPDIR/repo"
  cd "$TEST_TMPDIR/repo" || return 1
}

teardown() {
  teardown_common
}

_touch() {
  run --separate-stderr sh "$BW" state-touch "$@"
}

@test "creates .bytewyrd/NAME and a .gitignore holding *" {
  _touch last-feature-engineer-stop
  assert_success
  assert_equal "$output" ""
  assert_equal "$stderr" ""
  assert_file_exists .bytewyrd/last-feature-engineer-stop
  assert_equal "$(cat .bytewyrd/.gitignore)" "*"
}

@test "touching again moves the mtime forward and leaves an existing .gitignore alone" {
  mkdir .bytewyrd
  printf 'custom\n' >.bytewyrd/.gitignore
  touch -t 200001010000 .bytewyrd/precompact-extraction-done
  touch -t 200101010000 "$TEST_TMPDIR/ref"
  _touch precompact-extraction-done
  assert_success
  assert_equal "$stderr" ""
  [ .bytewyrd/precompact-extraction-done -nt "$TEST_TMPDIR/ref" ] || fail "mtime did not move"
  assert_equal "$(cat .bytewyrd/.gitignore)" "custom"
}

@test "with no NAME, adds the .gitignore to an existing .bytewyrd/ and nothing else" {
  mkdir .bytewyrd
  printf 'x\n' >.bytewyrd/plugin-version
  _touch
  assert_success
  assert_equal "$stderr" ""
  assert_equal "$(cat .bytewyrd/.gitignore)" "*"
  assert_equal "$(ls -A .bytewyrd | sort | tr '\n' ' ')" ".gitignore plugin-version "
}

@test "a symlinked .bytewyrd leaves the outside directory unchanged" {
  ln -s "$OUTSIDE" .bytewyrd
  printf 'keep\n' >"$OUTSIDE/last-feature-engineer-stop"
  for args in "last-feature-engineer-stop" "--rm last-feature-engineer-stop" ""; do
    # shellcheck disable=SC2086 # $args splits on purpose
    _touch $args
    assert_success
    assert_equal "$stderr" "state-touch: .bytewyrd is a symlink; refusing to write through it"
  done
  assert_equal "$(ls -A "$OUTSIDE")" "last-feature-engineer-stop"
  assert_equal "$(cat "$OUTSIDE/last-feature-engineer-stop")" "keep"
}

@test "a dangling .bytewyrd symlink is refused, and its target never appears" {
  ln -s "$OUTSIDE/made" .bytewyrd
  _touch last-feature-engineer-stop
  assert_success
  assert_equal "$stderr" "state-touch: .bytewyrd is a symlink; refusing to write through it"
  assert_file_not_exists "$OUTSIDE/made"
}

@test "a symlinked NAME leaves its target unchanged" {
  mkdir .bytewyrd
  printf 'keep\n' >"$OUTSIDE/victim"
  touch -t 200001010000 "$OUTSIDE/victim"
  touch -t 200101010000 "$TEST_TMPDIR/ref"
  ln -s "$OUTSIDE/victim" .bytewyrd/last-feature-engineer-stop
  ln -s "$OUTSIDE/new" .bytewyrd/precompact-extraction-done
  for name in last-feature-engineer-stop precompact-extraction-done; do
    _touch "$name"
    assert_success
    assert_equal "$stderr" "state-touch: .bytewyrd/$name is a symlink; refusing to write through it"
  done
  assert_equal "$(cat "$OUTSIDE/victim")" "keep"
  [ ! "$OUTSIDE/victim" -nt "$TEST_TMPDIR/ref" ] || fail "the symlink's target was touched"
  assert_file_not_exists "$OUTSIDE/new"
}

@test "--rm removes a regular file" {
  mkdir .bytewyrd
  : >.bytewyrd/last-feature-engineer-stop
  _touch --rm last-feature-engineer-stop
  assert_success
  assert_equal "$stderr" ""
  assert_file_not_exists .bytewyrd/last-feature-engineer-stop
}

@test "--rm removes only a regular file: a symlink, its target and a directory stay" {
  mkdir -p .bytewyrd/a-dir
  printf 'keep\n' >"$OUTSIDE/victim"
  ln -s "$OUTSIDE/victim" .bytewyrd/a-link
  _touch --rm a-link
  assert_success
  assert_equal "$stderr" "state-touch: .bytewyrd/a-link is a symlink; refusing to remove it"
  [ -L .bytewyrd/a-link ] || fail "the symlink was removed"
  assert_equal "$(cat "$OUTSIDE/victim")" "keep"
  _touch --rm a-dir
  assert_success
  assert_equal "$stderr" "state-touch: .bytewyrd/a-dir is not a regular file; refusing to remove it"
  assert_dir_exists .bytewyrd/a-dir
}

@test "--rm of an absent NAME is quiet" {
  _touch --rm last-feature-engineer-stop
  assert_success
  assert_equal "$output" ""
  assert_equal "$stderr" ""
}

@test "an invalid NAME writes nothing and still exits 0" {
  for name in ../x .gitignore A a/b 'a b' .. ''; do
    _touch "$name"
    assert_success
    assert_output ""
    [[ "$stderr" == "state-touch: invalid name "* ]] || fail "unexpected stderr for '$name': $stderr"
  done
  [ ! -e .bytewyrd ] || fail ".bytewyrd was created for an invalid name"
  assert_equal "$(ls -A "$OUTSIDE" "$TEST_TMPDIR/repo")" "$(printf '%s:\n\n%s:' "$OUTSIDE" "$TEST_TMPDIR/repo")"
}

@test "a usage error prints the usage and still exits 0" {
  _touch --bogus
  assert_success
  assert_equal "${stderr_lines[0]}" "usage: bw state-touch [-h] [--rm] [name]"
  [ ! -e .bytewyrd ] || fail ".bytewyrd was created on a usage error"
}
