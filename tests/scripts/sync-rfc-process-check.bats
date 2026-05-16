#!/usr/bin/env bats
# Tests for scripts/sync-rfc-process-check.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-rfc-process-check.sh"
  mkdir -p docs
}

teardown() {
  teardown_common
}

@test "no file — has_extensions=false" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "false"
  assert_equal "$(echo "$output" | jq -r .body)"           "null"
}

@test "file with placeholder text — has_extensions=false" {
  cat > docs/rfc-process.md <<'EOF'
# RFC Process

Body.

## Project Extensions

*(no project-specific extensions — the global process applies as-is)*

## Trailing
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "false"
}

@test "file with empty section — has_extensions=false" {
  cat > docs/rfc-process.md <<'EOF'
# RFC Process

Body.

## Project Extensions


## Trailing
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "false"
}

@test "file with real content — has_extensions=true and body extracted" {
  cat > docs/rfc-process.md <<'EOF'
# RFC Process

Body.

## Project Extensions

Our team has these rules:
- One
- Two

## Trailing

stuff
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "true"
  body="$(echo "$output" | jq -r .body)"
  case "$body" in
    *"Our team has these rules"*) ;;
    *) fail "body should contain real content, got: $body" ;;
  esac
}

@test "respects explicit file argument" {
  cat > custom.md <<'EOF'
# RFC

## Project Extensions

Real content here.
EOF
  run bash "$SCRIPT" custom.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "true"
  assert_equal "$(echo "$output" | jq -r .file)"           "custom.md"
}

@test "no Project Extensions section — has_extensions=false" {
  cat > docs/rfc-process.md <<'EOF'
# RFC Process

## Some other heading

Body.
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_extensions)" "false"
}
