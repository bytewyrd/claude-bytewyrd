#!/usr/bin/env bats
# Tests for scripts/sync-marker-read.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-marker-read.sh"
}

teardown() {
  teardown_common
}

@test "finds markdown marker on line 2 — emits found=true with key, sha, line" {
  cat > foo.md <<'EOF'
# title
<!-- bootstrap-content-version: foo/bar@v1:abc123def456 -->

body
EOF
  run bash "$SCRIPT" foo.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)"        "true"
  assert_equal "$(echo "$output" | jq -r .upstream_key)" "foo/bar@v1"
  assert_equal "$(echo "$output" | jq -r .sha12)"        "abc123def456"
  assert_equal "$(echo "$output" | jq -r .line)"         "2"
}

@test "finds markdown marker on line 1 — header-only file" {
  cat > foo.md <<'EOF'
<!-- bootstrap-content-version: x/y@v1:000111222333 -->
body
EOF
  run bash "$SCRIPT" foo.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)"        "true"
  assert_equal "$(echo "$output" | jq -r .upstream_key)" "x/y@v1"
  assert_equal "$(echo "$output" | jq -r .sha12)"        "000111222333"
  assert_equal "$(echo "$output" | jq -r .line)"         "1"
}

@test "finds TOML/YAML/gitignore-style marker on line 1" {
  cat > foo.toml <<'EOF'
# bootstrap-content-version: bw/mise@v1:1234567890ab

[tools]
go = "1.22"
EOF
  run bash "$SCRIPT" foo.toml
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)"        "true"
  assert_equal "$(echo "$output" | jq -r .upstream_key)" "bw/mise@v1"
  assert_equal "$(echo "$output" | jq -r .sha12)"        "1234567890ab"
  assert_equal "$(echo "$output" | jq -r .line)"         "1"
}

@test "no marker — found=false, all values null" {
  cat > foo.md <<'EOF'
# title

just regular content.
EOF
  run bash "$SCRIPT" foo.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)"        "false"
  assert_equal "$(echo "$output" | jq -r .upstream_key)" "null"
  assert_equal "$(echo "$output" | jq -r .sha12)"        "null"
  assert_equal "$(echo "$output" | jq -r .line)"         "null"
}

@test "marker beyond line 2 is ignored — found=false" {
  cat > foo.md <<'EOF'
# title

<!-- bootstrap-content-version: foo/bar@v1:abc123def456 -->

body
EOF
  run bash "$SCRIPT" foo.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)"        "false"
}

@test "missing file exits 2 with error" {
  run bash "$SCRIPT" does-not-exist.md
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no arguments exits 2 with error" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "malformed sha (too short) is not matched" {
  cat > foo.md <<'EOF'
# title
<!-- bootstrap-content-version: foo/bar@v1:abc -->

body
EOF
  run bash "$SCRIPT" foo.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .found)" "false"
}
