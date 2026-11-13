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

# --- ci_jobs_section --------------------------------------------------------
# templates/ci.yml.tpl ends in `jobs:` + <CI_JOBS_SECTION>. With no detected
# language the rendered workflow must still be valid: GitHub rejects a
# workflow whose `jobs:` map is empty, and a literal placeholder is not YAML.

# Render templates/ci.yml.tpl with the enriched inputs and print the parsed
# `jobs` mapping as JSON (exits non-zero if the result is not valid YAML).
_rendered_ci_jobs() {
  local inputs="$1"
  bash "$SCRIPT" "$inputs" > enriched.json || return 1
  bash "$SCRIPT_ROOT/scripts/sync-render-template.sh" "$SCRIPT_ROOT/templates/ci.yml.tpl" enriched.json > ci.yml || return 1
  python3 -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))["jobs"]))' ci.yml
}

_require_pyyaml() {
  python3 -c 'import yaml' 2>/dev/null || skip "python3 with PyYAML is required to parse the rendered workflow"
}

@test "ci.yml.tpl with no detected language renders a valid workflow with one no-op job" {
  _require_pyyaml
  echo '{"languages":[],"has_rust":false,"has_js":false,"installed_plugins":[]}' > in.json
  run _rendered_ci_jobs in.json
  assert_success
  assert_equal "$(echo "$output" | jq -c 'keys')" '["ci"]'
  assert_equal "$(echo "$output" | jq -r '.ci["runs-on"]')" "ubuntu-latest"
  assert_equal "$(echo "$output" | jq -r '.ci.steps | length')" "1"
  refute grep -q 'CI_JOBS_SECTION' ci.yml
}

@test "has_github alone is not a language: still renders the no-op job" {
  _require_pyyaml
  echo '{"languages":[],"has_github":true,"installed_plugins":[]}' > in.json
  run _rendered_ci_jobs in.json
  assert_success
  assert_equal "$(echo "$output" | jq -c 'keys')" '["ci"]'
}

@test "a detected language leaves ci_jobs_section unset for /sync Step 4c" {
  echo '{"languages":["rust"],"has_rust":true,"installed_plugins":[]}' > in.json
  run bash "$SCRIPT" in.json
  assert_success
  assert_equal "$(echo "$output" | jq -r 'has("ci_jobs_section")')" "false"
}

@test "a has_* language flag without a languages array also counts as detected" {
  echo '{"has_python":"true","installed_plugins":[]}' > in.json
  run bash "$SCRIPT" in.json
  assert_success
  assert_equal "$(echo "$output" | jq -r 'has("ci_jobs_section")')" "false"
}

@test "skills/sync/SKILL.md documents the same no-op ci job the script emits" {
  echo '{"languages":[]}' > in.json
  expected="$(bash "$SCRIPT" in.json | jq -r '.ci_jobs_section')"
  documented="$(awk '/render `<CI_JOBS_SECTION>` as exactly this no-op/ {found=1}
                     found && /^```yaml$/ {inside=1; next}
                     inside && /^```$/ {exit}
                     inside {print}' "$SCRIPT_ROOT/skills/sync/SKILL.md")"
  [ -n "$documented" ] || fail "no-op ci job block not found in skills/sync/SKILL.md"
  assert_equal "$documented" "$expected"
}
