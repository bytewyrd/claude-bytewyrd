#!/usr/bin/env bats
# The /rfc-approve and /rfc-drop skills read RFC frontmatter in Step 2 with
#   fm="$(bash .../rfc-frontmatter.sh "$RFC_PATH")" || { printf ...; exit 1; }
# Whether the script reports a failure as JSON on stdout (e.g. a missing file)
# or as a message on stderr (the bash >= 4 guard), the snippet must fail
# visibly instead of carrying on with an empty status. The snippets are
# extracted verbatim from the SKILL.md files, so these tests run what the
# skills tell the agent to run.

bats_require_minimum_version 1.5.0 # run --separate-stderr

setup() {
  load "helpers"
  setup_common
}

teardown() {
  teardown_common
}

# Print the fenced bash block in skill $1 that runs rfc-frontmatter.sh.
_step2_snippet() {
  awk '/^```bash$/ {inside=1; block=""; next}
       inside && /^```$/ {inside=0; if (block ~ /rfc-frontmatter\.sh/) {printf "%s", block; exit}; next}
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

@test "rfc-approve/rfc-drop Step 2: an error on stderr (the bash guard) stops the snippet" {
  # A stand-in rfc-frontmatter.sh that fails the way require_bash_major does.
  mkdir -p fake-plugin/scripts
  printf '#!/usr/bin/env bash\necho "{\\"error\\":\\"bytewyrd scripts require bash >= 4\\"}" >&2\nexit 2\n' > fake-plugin/scripts/rfc-frontmatter.sh
  for skill in rfc-approve rfc-drop; do
    run --separate-stderr env CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/fake-plugin" RFC_PATH=x.md bash -c "$(_step2_snippet "$skill")"
    assert_failure
    [[ "$stderr" == *"require bash >= 4"* ]] || fail "$skill: guard message not shown, stderr: $stderr"
  done
}
