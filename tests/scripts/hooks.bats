#!/usr/bin/env bats
# Tests for hooks/hooks.json (RFC 2026-11-09-scaffold-and-drift, B4, AC-17 and
# AC-20). Each test runs a hook's real command string from hooks.json the way
# Claude Code runs a shell-form hook, with sh -c and CLAUDE_PLUGIN_ROOT set to
# this repository: the rules entry prints hooks/always-on-rules.json within the
# 2,000-character cap, the compact reminder prints only while the SubagentStop
# sentinel is under a day old, and without Python 3.11 or newer every hook
# still exits 0.

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
  load "python-stubs"
  stub_setup
  HOOKS="$SCRIPT_ROOT/hooks/hooks.json"
  RULES="$SCRIPT_ROOT/hooks/always-on-rules.json"
  CLAUDE_PLUGIN_ROOT="$SCRIPT_ROOT"
  export CLAUDE_PLUGIN_ROOT
}

teardown() {
  teardown_common
}

FE_MATCHER='(^|:)feature-engineer$'
RULES_MATCHER='startup|clear|compact'
NEEDS='bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)'
FE_REMINDER='Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, a new CLI flag, a new workflow), ask the user to run /docs-review against the changed paths to check whether docs/guide/** needs updates.'
COMPACT_REMINDER='Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not yet have run. Ask the user to run /docs-review against the implemented files.'

# _hook EVENT MATCHER [INDEX]: print the command of hook INDEX (default 0) in
# the EVENT entry whose matcher is MATCHER; fail when there is none.
_hook() {
  jq -er --arg e "$1" --arg m "$2" --argjson i "${3:-0}" \
    '.hooks[$e][] | select(.matcher == $m) | .hooks[$i].command' "$HOOKS"
}

# _age_sentinel SECONDS: set the sentinel's mtime to SECONDS ago.
_age_sentinel() {
  "$PY" -I -c 'import os, sys, time; t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))' \
    .bytewyrd/last-feature-engineer-stop "$1"
}

@test "hooks.json holds the feature-engineer SubagentStop entry and the compact and startup|clear|compact SessionStart entries" {
  run jq -c '.hooks | with_entries(.value |= map(.matcher))' "$HOOKS"
  assert_success
  assert_output '{"SubagentStop":["(^|:)feature-engineer$"],"SessionStart":["compact","startup|clear|compact"]}'
  run jq -r '[.hooks[][].hooks[].type] | unique | join(",")' "$HOOKS"
  assert_output command
  # No hook calls check-requirements or stat (AC-17, B4).
  run grep -nE 'stat -[cf]|check-requirements' "$HOOKS"
  assert_failure 1
  assert_output ""
}

@test "the startup|clear|compact entry prints hooks/always-on-rules.json, whose context fits in 2,000 characters" {
  cmd="$(_hook SessionStart "$RULES_MATCHER")"
  run --separate-stderr "$SH" -c "$cmd"
  assert_success
  assert_equal "$stderr" ""
  assert_equal "$output" "$(cat "$RULES")"
  # B4's size check, on what the hook printed.
  run jq -e '.hookSpecificOutput | .hookEventName == "SessionStart" and (.additionalContext | length) <= 2000' <<<"$output"
  assert_success
  assert_output true
}

@test "the compact entry prints its reminder only while the sentinel is under a day old" {
  require_bw_python
  PY="$(find_python311)"
  cmd="$(_hook SessionStart compact)"
  run --separate-stderr "$SH" -c "$cmd"
  assert_success
  assert_output ""
  assert_equal "$stderr" ""
  mkdir .bytewyrd
  : >.bytewyrd/last-feature-engineer-stop
  for age in 0 82800 90000; do
    _age_sentinel "$age"
    run --separate-stderr "$SH" -c "$cmd"
    assert_success
    assert_equal "$stderr" ""
    if [ "$age" -lt 86400 ]; then
      assert_output "$COMPACT_REMINDER"
    else
      assert_output ""
    fi
  done
  touch -t 200001010000 .bytewyrd/last-feature-engineer-stop
  run --separate-stderr "$SH" -c "$cmd"
  assert_success
  assert_output ""
}

@test "the feature-engineer SubagentStop entry asks for /docs-review and touches the sentinel that the compact entry reads" {
  require_bw_python
  run --separate-stderr "$SH" -c "$(_hook SubagentStop "$FE_MATCHER" 0)"
  assert_success
  assert_output "$FE_REMINDER"
  assert_equal "$stderr" ""
  run --separate-stderr "$SH" -c "$(_hook SubagentStop "$FE_MATCHER" 1)"
  assert_success
  assert_output ""
  assert_equal "$stderr" ""
  assert_file_exists .bytewyrd/last-feature-engineer-stop
  assert_equal "$(cat .bytewyrd/.gitignore)" "*"
  run --separate-stderr "$SH" -c "$(_hook SessionStart compact)"
  assert_success
  assert_output "$COMPACT_REMINDER"
}

@test "the SubagentStop write refuses a symlinked .bytewyrd and leaves its target unchanged" {
  require_bw_python
  mkdir "$TEST_TMPDIR/outside"
  ln -s "$TEST_TMPDIR/outside" .bytewyrd
  run --separate-stderr "$SH" -c "$(_hook SubagentStop "$FE_MATCHER" 1)"
  assert_success
  assert_output ""
  assert_equal "$stderr" "state-touch: .bytewyrd is a symlink; refusing to write through it"
  assert_equal "$(ls -A "$TEST_TMPDIR/outside")" ""
}

@test "without Python 3.11 or newer, every hook command exits 0, and the SubagentStop write and the compact reminder print nothing" {
  # A fresh sentinel, so that only the missing interpreter keeps the reminder quiet.
  mkdir .bytewyrd
  : >.bytewyrd/last-feature-engineer-stop
  cmds=()
  while IFS= read -r c; do cmds+=("$c"); done < <(jq -r '.hooks[][].hooks[].command' "$HOOKS")
  [ "${#cmds[@]}" -gt 0 ] || fail "hooks.json has no commands"
  write="$(_hook SubagentStop "$FE_MATCHER" 1)"
  remind="$(_hook SessionStart compact)"
  rules="$(_hook SessionStart "$RULES_MATCHER")"
  for setup in none old; do
    for c in "${cmds[@]}"; do
      run --separate-stderr with_python "$setup" "$SH" -c "$c"
      [ "$status" -eq 0 ] || fail "exit $status under the '$setup' setup: $c"
    done
    for c in "$write" "$remind"; do
      run --separate-stderr with_python "$setup" "$SH" -c "$c"
      assert_success
      assert_output ""
      assert_equal "$stderr" "$NEEDS"
    done
    # The rules hook is a plain cat and needs no Python.
    run --separate-stderr with_python "$setup" "$SH" -c "$rules"
    assert_success
    assert_equal "$output" "$(cat "$RULES")"
  done
  assert_equal "$(ls -A .bytewyrd)" "last-feature-engineer-stop"
}
