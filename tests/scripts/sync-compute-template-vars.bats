#!/usr/bin/env bats
# Tests for scripts/sync-compute-template-vars.sh
#
# Focus: the enabled_plugins_entries allowlist. The variable must expand to only
# the three companion plugins (github / context7 / code-review, all
# @claude-plugins-official) when they are installed — never bytewyrd@bytewyrd
# (user-scoped) and never any other plugin the user happens to have installed.
# Dumping the full installed list would leak the user's local plugin set into a
# committed settings.json.

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-compute-template-vars.sh"
}

teardown() {
  teardown_common
}

# Render enabled_plugins_entries into the enabledPlugins object the settings.json
# template produces (`"enabledPlugins": {<entries>\n  }`) and return its keys as
# a compact JSON array.
_enabled_keys() {
  local inputs="$1" entries
  entries="$(bash "$SCRIPT" "$inputs" | jq -r '.enabled_plugins_entries')"
  printf '{ "enabledPlugins": {%s\n} }\n' "$entries" | jq -c '.enabledPlugins | keys'
}

@test "missing inputs file exits 1" {
  run bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.json"
  assert_failure 1
}

@test "produces valid JSON containing enabled_plugins_entries" {
  echo '{"installed_plugins":["github@claude-plugins-official"]}' > in.json
  run bash "$SCRIPT" in.json
  assert_success
  run bash -c "echo '$output' | jq -e 'has(\"enabled_plugins_entries\")'"
  assert_success
}

@test "all three companions present -> exactly those three, no bytewyrd, no extras" {
  cat > in.json <<'EOF'
{"installed_plugins":["bytewyrd@bytewyrd","github@claude-plugins-official","context7@claude-plugins-official","code-review@claude-plugins-official","some-random@thirdparty"]}
EOF
  keys="$(_enabled_keys in.json)"
  assert_equal "$(echo "$keys" | jq -c 'sort')" '["code-review@claude-plugins-official","context7@claude-plugins-official","github@claude-plugins-official"]'
  echo "$keys" | jq -e 'index("bytewyrd@bytewyrd") == null' >/dev/null || fail "bytewyrd@bytewyrd leaked into enabledPlugins: $keys"
  echo "$keys" | jq -e 'index("some-random@thirdparty") == null' >/dev/null || fail "unrelated plugin leaked into enabledPlugins: $keys"
}

@test "subset present -> only the installed companions appear" {
  cat > in.json <<'EOF'
{"installed_plugins":["bytewyrd@bytewyrd","context7@claude-plugins-official"]}
EOF
  assert_equal "$(_enabled_keys in.json)" '["context7@claude-plugins-official"]'
}

@test "no companions installed -> empty object" {
  cat > in.json <<'EOF'
{"installed_plugins":["bytewyrd@bytewyrd","random-tool@vendor","another@thing"]}
EOF
  assert_equal "$(_enabled_keys in.json)" '[]'
}

@test "empty installed_plugins -> empty object" {
  echo '{"installed_plugins":[]}' > in.json
  assert_equal "$(_enabled_keys in.json)" '[]'
}

@test "bytewyrd alone never appears" {
  echo '{"installed_plugins":["bytewyrd@bytewyrd"]}' > in.json
  assert_equal "$(_enabled_keys in.json)" '[]'
}
