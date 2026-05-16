#!/usr/bin/env bats
# Tests for scripts/sync-write-header.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-write-header.sh"
}

teardown() {
  teardown_common
}

@test "prepends bootstrap header to file with no existing header" {
  cat > foo.md <<'EOF'
# My Project

Hello world.
EOF
  run bash "$SCRIPT" foo.md "my/key@v1" "abc123def456" bootstrap
  assert_success
  assert_equal "$(echo "$output" | jq -r .header_type)"  "bootstrap"
  assert_equal "$(echo "$output" | jq -r .upstream_key)" "my/key@v1"
  assert_equal "$(echo "$output" | jq -r .sha12)"        "abc123def456"

  line1="$(sed -n '1p' foo.md)"
  line2="$(sed -n '2p' foo.md)"
  assert_equal "$line1" "<!-- bootstrap-content-version: my/key@v1:abc123def456 -->"
  case "$line2" in
    *"Bootstrapped by the Bytewyrd plugin"*) ;;
    *) fail "expected line 2 to contain Bootstrapped tagline, got: $line2" ;;
  esac
}

@test "prepends authoritative header" {
  cat > foo.md <<'EOF'
# My Project
EOF
  run bash "$SCRIPT" foo.md "x/y@v1" "111122223333" authoritative
  assert_success
  line2="$(sed -n '2p' foo.md)"
  case "$line2" in
    *"Managed by the Bytewyrd plugin"*) ;;
    *) fail "expected line 2 to contain Managed tagline, got: $line2" ;;
  esac
}

@test "replaces existing bootstrap header" {
  cat > foo.md <<'EOF'
<!-- bootstrap-content-version: old/key@v1:000000000000 -->
<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->

# Body

content.
EOF
  run bash "$SCRIPT" foo.md "new/key@v1" "111111111111" authoritative
  assert_success

  line1="$(sed -n '1p' foo.md)"
  line2="$(sed -n '2p' foo.md)"
  line3="$(sed -n '3p' foo.md)"
  line4="$(sed -n '4p' foo.md)"
  assert_equal "$line1" "<!-- bootstrap-content-version: new/key@v1:111111111111 -->"
  case "$line2" in
    *"Managed by the Bytewyrd plugin"*) ;;
    *) fail "expected line 2 to contain Managed tagline, got: $line2" ;;
  esac
  assert_equal "$line3" ""
  assert_equal "$line4" "# Body"
}

@test "replaces existing authoritative header — header lines are not duplicated" {
  cat > foo.md <<'EOF'
<!-- bootstrap-content-version: a/b@v1:aaaaaaaaaaaa -->
<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->

# Body

text.
EOF
  run bash "$SCRIPT" foo.md "a/b@v1" "bbbbbbbbbbbb" authoritative
  assert_success
  # File should still start with exactly two header lines, blank, then body.
  total_lines="$(wc -l < foo.md)"
  # Count of "bootstrap-content-version" occurrences should be exactly 1.
  marker_count="$(grep -c 'bootstrap-content-version' foo.md || true)"
  assert_equal "$marker_count" "1"
}

@test "rejects invalid header type" {
  cat > foo.md <<'EOF'
# Body
EOF
  run bash "$SCRIPT" foo.md "k@v1" "abcdef012345" totally-wrong
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "rejects bad sha12 (wrong length)" {
  cat > foo.md <<'EOF'
# Body
EOF
  run bash "$SCRIPT" foo.md "k@v1" "abc" bootstrap
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "rejects bad sha12 (non-hex)" {
  cat > foo.md <<'EOF'
# Body
EOF
  run bash "$SCRIPT" foo.md "k@v1" "ZZZZZZZZZZZZ" bootstrap
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing file exits 2" {
  run bash "$SCRIPT" does-not-exist.md "k@v1" "abcdef012345" bootstrap
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}
