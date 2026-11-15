#!/usr/bin/env bats
# Tests for scripts/bw, the POSIX-sh launcher (RFC 2026-11-09-scaffold-and-drift,
# B2 and B4): which interpreter it picks, the per-class exit contracts when no
# Python 3.11 or newer is found, the plain-sh PreCompact sentinel, NAME checks,
# and the -I -S -B flags that keep a venv's .pth files and bytecode out.

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
  load "python-stubs"
  stub_setup
  BW="$SCRIPT_ROOT/scripts/bw"
  MAIN="$SCRIPT_ROOT/scripts/_lib/bw_main.py"
  NEEDS='bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)'
}

teardown() {
  teardown_common
}

CLASS_B=(rfc-braindump-append rfc-braindump-list rfc-braindump-remove rfc-feedback-list
  rfc-frontmatter rfc-resolve rfc-set-status rfc-summary tool-probe)

# Lines a setup logs per command: the old setup asks $BYTEWYRD_PYTHON, then python3.
_asked() {
  case "$1" in
    none) printf '' ;;
    old) printf 'custom report\npython3 report' ;;
  esac
}

# --- interpreter selection ---------------------------------------------------

@test "takes \$BYTEWYRD_PYTHON when it reports 3.11 or newer, and passes NAME and ARGS through" {
  stub_python "$TEST_TMPDIR/custom" custom new
  stub_python "$STUB_BIN" python3.15 new
  run --separate-stderr env PATH="$STUB_BIN" BYTEWYRD_PYTHON="$TEST_TMPDIR/custom/custom" "$SH" "$BW" drift --strict 'two words' ''
  assert_success
  assert_equal "$stderr" ""
  assert_equal "$output" "$(printf '%s\n' 'ran custom' -I -S -B "$MAIN" drift --strict 'two words' '')"
  assert_equal "$(cat "$STUB_LOG")" "$(printf 'custom report\ncustom exec')"
}

@test "skips \$BYTEWYRD_PYTHON when it reports 3.9, then takes the highest versioned name" {
  stub_python "$TEST_TMPDIR/custom" custom old
  stub_python "$STUB_BIN" python3.11 new
  stub_python "$STUB_BIN" python3.13 new
  stub_python "$STUB_BIN" python3 new
  run env PATH="$STUB_BIN" BYTEWYRD_PYTHON="$TEST_TMPDIR/custom/custom" "$SH" "$BW" scaffold
  assert_success
  assert_line --index 0 "ran python3.13"
  assert_equal "$(cat "$STUB_LOG")" "$(printf 'custom report\npython3.13 exec')"
}

@test "an unset, empty or unrunnable \$BYTEWYRD_PYTHON falls through to PATH" {
  stub_python "$STUB_BIN" python3.12 new
  for value in unset '' "$TEST_TMPDIR/no-such-python"; do
    if [ "$value" = unset ]; then
      run env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" drift
    else
      run env PATH="$STUB_BIN" BYTEWYRD_PYTHON="$value" "$SH" "$BW" drift
    fi
    assert_success
    assert_line --index 0 "ran python3.12"
  done
}

@test "takes the highest of python3.15 down to python3.11, trusted by name, then python3" {
  # Each versioned stub would report 3.9 if asked; trusted by name, it never is.
  for v in 3.11 3.12 3.13 3.14 3.15; do
    stub_python "$STUB_BIN" "python$v" old
  done
  stub_python "$STUB_BIN" python3 new
  for want in python3.15 python3.14 python3.13 python3.12 python3.11; do
    : >"$STUB_LOG"
    run env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" compact-reminder
    assert_success
    assert_line --index 0 "ran $want"
    assert_equal "$(cat "$STUB_LOG")" "$want exec"
    rm "$STUB_BIN/$want"
  done
  : >"$STUB_LOG"
  run env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" compact-reminder
  assert_success
  assert_line --index 0 "ran python3"
  assert_equal "$(cat "$STUB_LOG")" "$(printf 'python3 report\npython3 exec')"
}

@test "python3 that reports 3.9 is not used" {
  stub_python "$STUB_BIN" python3 old
  run --separate-stderr env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" drift
  assert_failure 1
  assert_equal "$stderr" "$NEEDS"
  assert_equal "$(cat "$STUB_LOG")" "python3 report"
}

# --- without Python 3.11 or newer --------------------------------------------

@test "without Python 3.11+, each class-A command exits 1 with one stderr line" {
  for setup in none old; do
    for cmd in scaffold "scaffold --apply" drift "drift --strict" compact-reminder state-touch \
      "state-touch last-feature-engineer-stop" "state-touch --rm last-feature-engineer-stop" \
      "state-touch --rm precompact-extraction-done" "state-touch precompact-extraction-done extra"; do
      : >"$STUB_LOG"
      # shellcheck disable=SC2086 # $cmd splits into NAME and ARGS on purpose
      run --separate-stderr with_python "$setup" "$SH" "$BW" $cmd
      assert_failure 1
      assert_equal "$output" ""
      assert_equal "$stderr" "$NEEDS"
      assert_equal "$(cat "$STUB_LOG")" "$(_asked "$setup")"
    done
  done
  [ ! -e .bytewyrd ] || fail "a class-A command wrote .bytewyrd without Python"
}

@test "without Python 3.11+, each class-B command exits 2 with a JSON error on stderr" {
  for setup in none old; do
    for name in "${CLASS_B[@]}"; do
      : >"$STUB_LOG"
      run --separate-stderr with_python "$setup" "$SH" "$BW" "$name" some-arg
      assert_failure 2
      assert_equal "$output" ""
      assert_equal "$stderr" "{\"error\":\"$NEEDS\"}"
      assert_equal "$(printf '%s' "$stderr" | jq -r .error)" "$NEEDS"
      assert_equal "$(cat "$STUB_LOG")" "$(_asked "$setup")"
    done
  done
}

@test "without Python 3.11+, state-touch precompact-extraction-done still writes the sentinel" {
  for setup in none old; do
    rm -rf .bytewyrd
    run --separate-stderr with_python "$setup" "$SH" "$BW" state-touch precompact-extraction-done
    assert_success
    assert_equal "$output" ""
    assert_equal "$stderr" ""
    assert_file_exists .bytewyrd/precompact-extraction-done
    # Plain sh writes no .gitignore; repos still on 0.2.x have the seeded one.
    assert_file_not_exists .bytewyrd/.gitignore
    # Again, now that .bytewyrd and the sentinel exist.
    run --separate-stderr with_python "$setup" "$SH" "$BW" state-touch precompact-extraction-done
    assert_success
    assert_equal "$stderr" ""
  done
}

@test "without Python 3.11+, the sentinel write refuses a symlinked .bytewyrd" {
  mkdir "$TEST_TMPDIR/outside"
  for target in "$TEST_TMPDIR/outside" "$TEST_TMPDIR/outside/dangling"; do
    rm -f .bytewyrd
    ln -s "$target" .bytewyrd
    for setup in none old; do
      run --separate-stderr with_python "$setup" "$SH" "$BW" state-touch precompact-extraction-done
      assert_success
      assert_equal "$stderr" "state-touch: .bytewyrd is a symlink; refusing to write through it"
      assert_equal "$(ls -A "$TEST_TMPDIR/outside")" ""
    done
  done
}

@test "without Python 3.11+, the sentinel write refuses a symlinked sentinel" {
  mkdir .bytewyrd "$TEST_TMPDIR/outside"
  printf 'keep\n' >"$TEST_TMPDIR/outside/victim"
  for target in "$TEST_TMPDIR/outside/victim" "$TEST_TMPDIR/outside/new"; do
    rm -f .bytewyrd/precompact-extraction-done
    ln -s "$target" .bytewyrd/precompact-extraction-done
    for setup in none old; do
      run --separate-stderr with_python "$setup" "$SH" "$BW" state-touch precompact-extraction-done
      assert_success
      assert_equal "$stderr" "state-touch: .bytewyrd/precompact-extraction-done is a symlink; refusing to write through it"
    done
  done
  assert_equal "$(cat "$TEST_TMPDIR/outside/victim")" "keep"
  assert_file_not_exists "$TEST_TMPDIR/outside/new"
}

# --- NAME checks ---------------------------------------------------------------

@test "an unknown NAME exits 1 before any interpreter starts" {
  stub_python "$STUB_BIN" python3.15 new
  # ($stderr loses trailing blanks, so 'scaffold x' stands in for 'scaffold '.)
  for name in nope ../x main bw_main 'scaffold x' Drift rfc-legacy-detect; do
    run --separate-stderr env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" "$name"
    assert_failure 1
    assert_equal "$output" ""
    assert_equal "$stderr" "bw: unknown command: $name"
  done
  # An empty NAME too, compared byte for byte for the same reason.
  rc=0
  env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW" '' 2>"$TEST_TMPDIR/err" || rc=$?
  assert_equal "$rc" 1
  printf 'bw: unknown command: \n' | cmp - "$TEST_TMPDIR/err"
  assert_equal "$(cat "$STUB_LOG")" ""
}

@test "no NAME prints the usage line and exits 1" {
  stub_python "$STUB_BIN" python3.15 new
  run --separate-stderr env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$SH" "$BW"
  assert_failure 1
  assert_equal "$stderr" "bw: usage: bw NAME [ARGS...]"
  assert_equal "$(cat "$STUB_LOG")" ""
}

# --- -I -S -B --------------------------------------------------------------------

@test "with a venv's interpreter, its .pth file never runs and no __pycache__/ appears" {
  py="$(find_python311)" || {
    [ -z "${CI:-}" ] || fail "no Python 3.11 or newer, and CI must not skip"
    skip "no Python 3.11 or newer"
  }
  "$py" -m venv --without-pip "$TEST_TMPDIR/venv"
  venv_py="$TEST_TMPDIR/venv/bin/python"
  site="$("$venv_py" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
  marker="$TEST_TMPDIR/pth-ran"
  printf 'import os; open("%s", "w").close()\n' "$marker" >"$site/bw-marker.pth"
  # The marker works: a plain start of the venv's interpreter runs the .pth.
  "$venv_py" -c pass
  assert_file_exists "$marker"
  rm "$marker"
  # Run a copy of the scripts, so bytecode that pytest wrote into the real
  # scripts/_lib can't hide a new __pycache__/.
  mkdir -p "$TEST_TMPDIR/plugin/scripts/_lib"
  cp "$BW" "$TEST_TMPDIR/plugin/scripts/bw"
  cp "$SCRIPT_ROOT"/scripts/_lib/*.py "$TEST_TMPDIR/plugin/scripts/_lib/"
  run --separate-stderr env BYTEWYRD_PYTHON="$venv_py" "$SH" "$TEST_TMPDIR/plugin/scripts/bw" state-touch last-feature-engineer-stop
  assert_success
  assert_equal "$stderr" ""
  run --separate-stderr env BYTEWYRD_PYTHON="$venv_py" "$SH" "$TEST_TMPDIR/plugin/scripts/bw" compact-reminder
  assert_success
  assert_output --partial "Ask the user to run /docs-review"
  assert_file_not_exists "$marker"
  run find "$TEST_TMPDIR/plugin" -name __pycache__
  assert_output ""
}
