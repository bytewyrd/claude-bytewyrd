#!/usr/bin/env bats
# Tests for scripts/sync-owned-regions-apply.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-owned-regions-apply.sh"
}

teardown() {
  teardown_common
}

@test "replaces body of owned heading; preserves user-owned content" {
  cat > local.md <<'EOF'
# Title

User intro.

## Tool Usage

Old tools.

## Mine

Preserve me.

## Security

Old security.
EOF
  cat > plugin.md <<'EOF'
# Plugin Title

ignored intro.

## Tool Usage

New tools.

## Security

New security.
EOF
  boundaries='[{"type":"heading","heading":"## Tool Usage"},{"type":"heading","heading":"## Security"}]'
  run bash "$SCRIPT" local.md plugin.md "$boundaries"
  assert_success
  case "$output" in
    *"User intro."*) ;;
    *) fail "user intro should be preserved: $output" ;;
  esac
  case "$output" in
    *"Preserve me."*) ;;
    *) fail "user-owned section should be preserved: $output" ;;
  esac
  case "$output" in
    *"New tools."*) ;;
    *) fail "owned section body should be replaced: $output" ;;
  esac
  case "$output" in
    *"New security."*) ;;
    *) fail "owned security body should be replaced: $output" ;;
  esac
  # Old owned content must be gone.
  case "$output" in
    *"Old tools."*) fail "old owned content should be replaced: $output" ;;
    *) ;;
  esac
}

@test "absent owned heading inserted after last preceding present heading" {
  cat > local.md <<'EOF'
# Title

## Tool Usage

X

## My Custom

Y
EOF
  cat > plugin.md <<'EOF'
## Tool Usage

A

## NewlyOwned

B
EOF
  boundaries='[{"type":"heading","heading":"## Tool Usage"},{"type":"heading","heading":"## NewlyOwned"}]'
  run bash "$SCRIPT" local.md plugin.md "$boundaries"
  assert_success
  # ## NewlyOwned should appear after ## Tool Usage body (i.e., before ## My Custom)
  # find positions in output
  awk_out="$(echo "$output" | awk '
    /^## Tool Usage$/ { tu = NR }
    /^## NewlyOwned$/ { nw = NR }
    /^## My Custom$/  { mc = NR }
    END { printf "%d %d %d", tu, nw, mc }
  ')"
  read tu nw mc <<< "$awk_out"
  [ "$tu" -lt "$nw" ] || fail "## Tool Usage should precede ## NewlyOwned ($awk_out)"
  [ "$nw" -lt "$mc" ] || fail "## NewlyOwned should precede ## My Custom ($awk_out)"
}

@test "absent owned heading with no preceding present heading — appended at EOF" {
  cat > local.md <<'EOF'
# Title

## Mine

X
EOF
  cat > plugin.md <<'EOF'
## Tool Usage

A
EOF
  boundaries='[{"type":"heading","heading":"## Tool Usage"}]'
  run bash "$SCRIPT" local.md plugin.md "$boundaries"
  assert_success
  # Last line should be in the appended block.
  case "$output" in
    *"## Tool Usage"*) ;;
    *) fail "expected appended ## Tool Usage: $output" ;;
  esac
}

@test "no owned boundaries — output equals input verbatim" {
  cat > local.md <<'EOF'
# Title

## A

a
EOF
  cat > plugin.md <<'EOF'
plugin content
EOF
  run bash "$SCRIPT" local.md plugin.md '[]'
  assert_success
  expected="$(cat local.md)"
  # Output may have a trailing newline added by the writer; trim trailing newline.
  actual="$output"
  assert_equal "$actual" "$expected"
}

@test "missing local file exits 2" {
  cat > plugin.md <<'EOF'
plugin
EOF
  run bash "$SCRIPT" does-not-exist.md plugin.md '[]'
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing plugin file exits 2" {
  cat > local.md <<'EOF'
local
EOF
  run bash "$SCRIPT" local.md does-not-exist.md '[]'
  assert_failure 2
}

@test "non-array boundaries exits 2" {
  cat > local.md <<'EOF'
x
EOF
  cat > plugin.md <<'EOF'
y
EOF
  run bash "$SCRIPT" local.md plugin.md '{"not": "an array"}'
  assert_failure 2
}

@test "missing arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}
