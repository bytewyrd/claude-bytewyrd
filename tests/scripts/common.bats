#!/usr/bin/env bats
# Tests for scripts/_lib/common.bash

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
  LIB="$SCRIPT_ROOT/scripts/_lib/common.bash"
}

teardown() {
  teardown_common
}

# ---------------------------------------------------------------------------
# require_bash_major
# ---------------------------------------------------------------------------
# The running bash cannot be swapped for 3.2 here, so the failure path is
# exercised with a minimum above any real bash.

@test "require_bash_major: returns quietly when bash meets the minimum" {
  run bash -c ". '$LIB' && require_bash_major 4 && echo still-running"
  assert_success
  assert_output "still-running"
}

@test "require_bash_major: exits 2 with an actionable JSON error on stderr when bash is too old" {
  run --separate-stderr bash -c ". '$LIB' && require_bash_major 999 && echo still-running"
  assert_failure 2
  # Nothing on stdout: callers that capture stdout with $(...) must not swallow it.
  assert_equal "$output" ""
  msg="$(echo "$stderr" | jq -r .error)"
  [[ "$msg" == *"require bash >= 999; this is bash ${BASH_VERSINFO[0]}."* ]] || fail "unexpected message: $msg"
  [[ "$msg" == *"brew install bash"* ]] || fail "missing the macOS hint: $msg"
}

@test "require_bash_major: every script using bash 4 features calls it" {
  # mapfile/readarray and associative arrays do not exist in bash 3.2, the
  # stock /bin/bash on macOS. Any script using them must fail with the clear
  # require_bash_major error rather than "mapfile: command not found". The
  # /sync preflight checks up front as well.
  cd "$SCRIPT_ROOT"
  # mapfile/readarray, associative arrays and namerefs (declare/local/typeset
  # -A, -gA, -n) and case-modifying expansions such as ${x,,} or ${x^^}.
  bash4='\b(mapfile|readarray)\b|\b(declare|local|typeset)[[:space:]]+-[a-zA-Z]*[An]\b|\$\{[A-Za-z_][A-Za-z0-9_]*(,,?|\^\^?)\}'
  uses_bash4() { grep -vE '^[[:space:]]*#' "$1" | grep -qE "$bash4"; }  # ignore comment lines
  guarded() { grep -qE '^require_bash_major 4\b' "$1"; }
  missing=""
  for f in scripts/*.sh; do
    if uses_bash4 "$f" && ! guarded "$f"; then
      missing="$missing $f"
    fi
  done
  # A sourced library runs in its caller's bash, so callers must check too.
  for lib in scripts/_lib/*.bash; do
    uses_bash4 "$lib" || continue
    for f in $(grep -lF "_lib/$(basename "$lib")" scripts/*.sh); do
      guarded "$f" || missing="$missing $f(sources $(basename "$lib"))"
    done
  done
  [ -z "$missing" ] || fail "scripts use bash 4 features without require_bash_major 4:$missing"
  grep -qE '^require_bash_major 4\b' scripts/sync-preflight.sh || fail "sync-preflight.sh must check the bash version"
  # rfc-summary.sh tolerates per-file rfc-frontmatter.sh failures, which would
  # hide the guard's error behind "unparseable" warnings.
  grep -qE '^require_bash_major 4\b' scripts/rfc-summary.sh || fail "rfc-summary.sh must check the bash version"
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
