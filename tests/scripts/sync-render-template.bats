#!/usr/bin/env bats
# Tests for scripts/sync-render-template.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-render-template.sh"
}

teardown() {
  teardown_common
}

@test "substitutes lowercase placeholder" {
  cat > t.tpl <<'EOF'
# <project_name>

<description>
EOF
  cat > inputs.json <<'EOF'
{"project_name": "Foo", "description": "Bar."}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  case "$output" in
    *"# Foo"*) ;;
    *) fail "expected '# Foo' in output: $output" ;;
  esac
  case "$output" in
    *"Bar."*) ;;
    *) fail "expected 'Bar.' in output: $output" ;;
  esac
}

@test "substitutes uppercase placeholder via lowercased key" {
  cat > t.tpl <<'EOF'
# Title

<LANGUAGE_TOOLCHAIN_SECTION>
EOF
  cat > inputs.json <<'EOF'
{"language_toolchain_section": "Rust line."}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  case "$output" in
    *"Rust line."*) ;;
    *) fail "expected 'Rust line.' in output: $output" ;;
  esac
}

@test "unrecognized placeholder becomes empty string when key in inputs is empty" {
  cat > t.tpl <<'EOF'
A <foo> B
EOF
  cat > inputs.json <<'EOF'
{"foo": ""}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  assert_equal "$output" "A  B"
}

@test "missing key — placeholder left in output (no substitution applied)" {
  # The script substitutes only known keys; unknown placeholders survive.
  cat > t.tpl <<'EOF'
A <some_unknown_thing> B
EOF
  cat > inputs.json <<'EOF'
{"other": "X"}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  # When a key is not present in inputs, the script does NOT do a substitution
  # for the placeholder — preserves literal `<some_unknown_thing>`.
  case "$output" in
    *"<some_unknown_thing>"*) ;;
    *) fail "expected literal placeholder to survive when not in inputs, got: $output" ;;
  esac
}

@test "lang-* conditional block included when language in languages array" {
  cat > t.tpl <<'EOF'
Top
<!--lang:rust-start-->
- rust line
<!--lang:rust-end-->
Bottom
EOF
  cat > inputs.json <<'EOF'
{"languages": ["rust"]}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  case "$output" in
    *"- rust line"*) ;;
    *) fail "expected rust line in output: $output" ;;
  esac
  # Delimiter comments are stripped.
  case "$output" in
    *"lang:rust-start"*) fail "expected delimiter to be stripped: $output" ;;
    *) ;;
  esac
}

@test "lang-* conditional block stripped when language absent" {
  cat > t.tpl <<'EOF'
Top
<!--lang:python-start-->
- python line
<!--lang:python-end-->
Bottom
EOF
  cat > inputs.json <<'EOF'
{"languages": ["rust"]}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  case "$output" in
    *"- python line"*) fail "expected python line to be stripped: $output" ;;
    *) ;;
  esac
}

@test "has_<lang> truthy value also enables conditional block" {
  cat > t.tpl <<'EOF'
<!--lang:svelte-start-->
- svelte line
<!--lang:svelte-end-->
EOF
  cat > inputs.json <<'EOF'
{"has_svelte": true}
EOF
  run bash "$SCRIPT" t.tpl inputs.json
  assert_success
  case "$output" in
    *"- svelte line"*) ;;
    *) fail "expected svelte line in output: $output" ;;
  esac
}

@test "missing template exits 2" {
  cat > inputs.json <<'EOF'
{}
EOF
  run bash "$SCRIPT" does-not-exist.tpl inputs.json
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing inputs exits 2" {
  cat > t.tpl <<'EOF'
content
EOF
  run bash "$SCRIPT" t.tpl does-not-exist.json
  assert_failure 2
}

@test "non-object inputs exits 2" {
  cat > t.tpl <<'EOF'
content
EOF
  printf '["array", "not", "object"]\n' > inputs.json
  run bash "$SCRIPT" t.tpl inputs.json
  assert_failure 2
}

@test "no arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}
