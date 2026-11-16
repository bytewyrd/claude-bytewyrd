# Helpers for tests that control which Python interpreter scripts/bw finds.
# Load after helpers.bash, in setup():
#   load "python-stubs"
#   stub_setup
#
# A stub interpreter answers the launcher's version report and records each
# call in $STUB_LOG, so a test can tell which candidates were asked and which
# one ran. with_python runs a command under one of two setups in which no
# interpreter qualifies, the way bw.bats and hooks.bats need them.

# The launcher's version report, verbatim (B2 step 2).
BW_REPORT='import sys; sys.exit(sys.version_info < (3, 11))'

# stub_setup: create $STUB_BIN, a PATH directory holding only the tools the
# launcher and the hook commands use without Python (sh, mkdir, cat), and an
# empty $STUB_LOG. Also sets $SH, an absolute path to sh.
stub_setup() {
  STUB_BIN="$TEST_TMPDIR/stub-bin"
  STUB_LOG="$TEST_TMPDIR/stub.log"
  SH="$(command -v sh)"
  mkdir -p "$STUB_BIN"
  : >"$STUB_LOG"
  local tool
  for tool in sh mkdir cat; do
    ln -s "$(command -v "$tool")" "$STUB_BIN/$tool"
  done
  export STUB_BIN STUB_LOG SH
}

# stub_python DIR NAME new|old
#   Create the executable DIR/NAME. Asked the version report, it exits 0 for
#   "new" and 1 for "old", and logs "NAME report". Run the way the launcher
#   execs an interpreter (-I -S -B ...), it logs "NAME exec", prints
#   "ran NAME" and then each argument on its own line, and exits 0. Anything
#   else logs "NAME unexpected" and exits 99.
stub_python() {
  local dir="$1" name="$2" code
  case "$3" in
    new) code=0 ;;
    old) code=1 ;;
    *) return 1 ;;
  esac
  mkdir -p "$dir"
  cat >"$dir/$name" <<EOF
#!/bin/sh
if [ "\$#" -eq 4 ] && [ "\$1" = -I ] && [ "\$2" = -S ] && [ "\$3" = -c ] && [ "\$4" = '$BW_REPORT' ]; then
  echo '$name report' >>'$STUB_LOG'
  exit $code
fi
if [ "\$1" = -I ] && [ "\$2" = -S ] && [ "\$3" = -B ]; then
  echo '$name exec' >>'$STUB_LOG'
  printf '%s\n' 'ran $name' "\$@"
  exit 0
fi
echo '$name unexpected' >>'$STUB_LOG'
exit 99
EOF
  chmod +x "$dir/$name"
}

# with_python none|old COMMAND [ARGS...]
#   Run COMMAND where scripts/bw finds no Python 3.11 or newer:
#   none  PATH is $STUB_BIN, with no interpreter, and BYTEWYRD_PYTHON is unset;
#   old   $BYTEWYRD_PYTHON (the stub "custom"), python3, python3.10 and python
#         report Python 3.9, so each command logs "custom report" and
#         "python3 report". The launcher never asks python3.10 or python, so
#         a stray run of them shows up as "ran ..." output.
with_python() {
  local setup="$1"
  shift
  case "$setup" in
    none)
      env -u BYTEWYRD_PYTHON PATH="$STUB_BIN" "$@"
      ;;
    old)
      [ -x "$TEST_TMPDIR/stub-old/custom" ] || {
        stub_python "$TEST_TMPDIR/stub-old" custom old
        stub_python "$STUB_BIN" python3 old
        stub_python "$STUB_BIN" python3.10 old
        stub_python "$STUB_BIN" python old
      }
      env PATH="$STUB_BIN" BYTEWYRD_PYTHON="$TEST_TMPDIR/stub-old/custom" "$@"
      ;;
    *) return 1 ;;
  esac
}

# find_python311: print an interpreter that reports Python 3.11 or newer,
# trying the launcher's candidates in its order; fail when there is none.
find_python311() {
  local c
  for c in "${BYTEWYRD_PYTHON:-}" python3.15 python3.14 python3.13 python3.12 python3.11 python3; do
    [ -n "$c" ] || continue
    if "$c" -I -S -c "$BW_REPORT" >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}

# require_bw_python: skip the test when scripts/bw finds no Python 3.11 or
# newer on this machine. CI must not skip.
require_bw_python() {
  sh "$SCRIPT_ROOT/scripts/bw" compact-reminder --help >/dev/null 2>&1 && return 0
  [ -z "${CI:-}" ] || fail "scripts/bw finds no Python 3.11 or newer, and CI must not skip"
  skip "scripts/bw finds no Python 3.11 or newer (set BYTEWYRD_PYTHON)"
}
