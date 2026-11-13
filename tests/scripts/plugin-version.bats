#!/usr/bin/env bats
# The plugin ships without a `version` in .claude-plugin/plugin.json so users
# track commits (a pinned version keeps every install on the cached copy).
# These tests pin down what that does to the three readers of the field: each
# must degrade to a silent no-op, never an error.
#
#   scripts/check-requirements.sh  — "plugin out of date" SessionStart warning
#   scripts/sync-preflight.sh      — `plugin_version` in the preflight JSON
#   skills/sync/SKILL.md (Step 1)  — records .bytewyrd/plugin-version
#
# Each reader also gets a control test with a version present, proving the
# no-version test actually reaches the code path it claims to cover.

setup() {
  load "helpers"
  setup_common

  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME/.claude"
  export HOME="$FAKE_HOME"

  # A plugin root the scripts can resolve: CLAUDE_PLUGIN_ROOT for the hook and
  # the skill snippet, the ~/.claude "home" branch for preflight.
  PLUGIN_DIR="$FAKE_HOME/.claude"
  mkdir -p "$PLUGIN_DIR/.claude-plugin"
  printf '{"artifacts":[]}\n' > "$PLUGIN_DIR/bootstrap-manifest.json"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  export CLAUDE_PROJECT_DIR="$TEST_TMPDIR"

  # This project was last synced by a plugin that still had version 0.2.0.
  mkdir -p .bytewyrd
  printf '0.2.0\n' > .bytewyrd/plugin-version
}

teardown() {
  teardown_common
}

_plugin_json() {
  if [ -n "${1:-}" ]; then
    printf '{"name":"bytewyrd","version":"%s"}\n' "$1" > "$PLUGIN_DIR/.claude-plugin/plugin.json"
  else
    printf '{"name":"bytewyrd"}\n' > "$PLUGIN_DIR/.claude-plugin/plugin.json"
  fi
}

# Run check-requirements.sh with every other probe suppressed, so the only
# warning that can appear is the plugin-version one.
_check_requirements() {
  BYTEWYRD_SKIP_WARN="github,context7,code-review,exa,firefox-devtools,gh-cli" \
    bash "$SCRIPT_ROOT/scripts/check-requirements.sh" 2>/dev/null
}

# The Step 1 snippet that records the plugin version, extracted verbatim from
# skills/sync/SKILL.md so the test runs what the skill tells the agent to run.
_sync_record_version_snippet() {
  awk '/^\*\*Also record the plugin version\*\*/ {found=1}
       found && /^```bash$/ {inside=1; next}
       inside && /^```$/ {exit}
       inside {print}' "$SCRIPT_ROOT/skills/sync/SKILL.md"
}

@test "check-requirements: no version in plugin.json -> no plugin-version warning, silent success" {
  _plugin_json ""
  run _check_requirements
  assert_success
  assert_equal "$(echo "$output" | jq -r .systemMessage)" ""
  assert_equal "$(echo "$output" | jq -r .suppressOutput)" "true"
}

@test "check-requirements control: an older pinned version still warns" {
  _plugin_json "0.1.0"
  run _check_requirements
  assert_success
  [[ "$(echo "$output" | jq -r .systemMessage)" == *"Plugin out of date: installed 0.1.0, project last synced with 0.2.0"* ]] \
    || fail "expected the plugin-version warning, got: $output"
}

@test "sync-preflight: no version in plugin.json -> plugin_version is an empty string" {
  _plugin_json ""
  git init -q .
  unset CLAUDE_PLUGIN_ROOT  # resolve through the ~/.claude home branch
  run bash "$SCRIPT_ROOT/scripts/sync-preflight.sh"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.plugin_version | type')" "string"
  assert_equal "$(echo "$output" | jq -r .plugin_version)" ""
}

@test "sync-preflight control: a pinned version is reported" {
  _plugin_json "0.2.0"
  git init -q .
  unset CLAUDE_PLUGIN_ROOT
  run bash "$SCRIPT_ROOT/scripts/sync-preflight.sh"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_version)" "0.2.0"
}

@test "sync skill Step 1: no version -> snippet exits 0 and leaves .bytewyrd/plugin-version alone" {
  _plugin_json ""
  snippet="$(_sync_record_version_snippet)"
  [ -n "$snippet" ] || fail "version-recording snippet not found in skills/sync/SKILL.md"
  run bash -c "$snippet"
  assert_success
  assert_equal "$(cat .bytewyrd/plugin-version)" "0.2.0"
}

@test "sync skill Step 1 control: a pinned version is recorded" {
  _plugin_json "0.3.0"
  run bash -c "$(_sync_record_version_snippet)"
  assert_success
  assert_equal "$(cat .bytewyrd/plugin-version)" "0.3.0"
}
