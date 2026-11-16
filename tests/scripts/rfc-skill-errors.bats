#!/usr/bin/env bats
# The /rfc-approve and /rfc-drop skills read RFC frontmatter in Step 2 with
#   fm="$(sh .../scripts/bw rfc-frontmatter "$RFC_PATH")" || { printf ...; exit 1; }
# Whether the helper reports a failure as JSON on stdout (e.g. a missing file)
# or as a message on stderr (e.g. the launcher finding no Python 3.11 or
# newer), the snippet must fail visibly instead of carrying on with an empty
# status. The snippets are extracted verbatim from the SKILL.md files, so
# these tests run what the skills tell the agent to run.

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
}

teardown() {
  teardown_common
}

# Print the fenced bash block in skill $1 that runs rfc-frontmatter.
_step2_snippet() {
  awk '/^```bash$/ {inside=1; block=""; next}
       inside && /^```$/ {inside=0; if (block ~ /\/scripts\/bw" rfc-frontmatter /) {printf "%s", block; exit}; next}
       inside {block = block $0 "\n"}' "$SCRIPT_ROOT/skills/$1/SKILL.md"
}

@test "rfc-approve/rfc-drop Step 2: a JSON error on stdout stops the snippet and is shown" {
  for skill in rfc-approve rfc-drop; do
    snippet="$(_step2_snippet "$skill")"
    [ -n "$snippet" ] || fail "Step 2 snippet not found in skills/$skill/SKILL.md"
    run env CLAUDE_PLUGIN_ROOT="$SCRIPT_ROOT" RFC_PATH="$TEST_TMPDIR/docs/rfcs/missing.md" bash -c "$snippet"
    assert_failure
    assert_output --partial '"error"'
    assert_output --partial 'file not found'
  done
}

@test "rfc-approve/rfc-drop Step 2: an error on stderr (no Python 3.11 or newer) stops the snippet" {
  # A stand-in scripts/bw that fails the way the launcher does for a JSON
  # helper when it finds no Python 3.11 or newer.
  mkdir -p fake-plugin/scripts
  printf '#!/bin/sh\necho "{\\"error\\":\\"bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)\\"}" >&2\nexit 2\n' > fake-plugin/scripts/bw
  for skill in rfc-approve rfc-drop; do
    run --separate-stderr env CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/fake-plugin" RFC_PATH=x.md bash -c "$(_step2_snippet "$skill")"
    assert_failure
    [[ "$stderr" == *"needs Python 3.11 or newer"* ]] || fail "$skill: launcher message not shown, stderr: $stderr"
  done
}
