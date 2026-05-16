#!/usr/bin/env bats
# Tests for scripts/sync-unified-diff.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-unified-diff.sh"
}

teardown() {
  teardown_common
}

@test "identical files — empty hunks list, total_hunks 0" {
  cat > a.md <<'EOF'
# Title

body.
EOF
  cp a.md b.md
  run bash "$SCRIPT" a.md b.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .total_hunks)" "0"
  assert_equal "$(echo "$output" | jq -r '.hunks | length')" "0"
  assert_equal "$(echo "$output" | jq -r .diff)" ""
}

@test "single hunk — id hunk-1, label is first changed line" {
  cat > a.md <<'EOF'
# Title

Old line here.

The end.
EOF
  cat > b.md <<'EOF'
# Title

New line here.

The end.
EOF
  run bash "$SCRIPT" a.md b.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .total_hunks)" "1"
  assert_equal "$(echo "$output" | jq -r '.hunks[0].id)')" "hunk-1)'" || true
  assert_equal "$(echo "$output" | jq -r '.hunks[0].id')" "hunk-1"
  label="$(echo "$output" | jq -r '.hunks[0].label')"
  assert_equal "$label" "Old line here."
}

@test "label truncated at 60 chars with trailing ..." {
  cat > a.md <<'EOF'
# Title

A really long original line that is significantly more than sixty characters long to force truncation.

Body.
EOF
  cat > b.md <<'EOF'
# Title

A completely different really long line that is also significantly more than sixty characters long.

Body.
EOF
  run bash "$SCRIPT" a.md b.md
  assert_success
  label="$(echo "$output" | jq -r '.hunks[0].label')"
  # Either it's <= 60 chars or it ends in `...` after exactly 60 chars.
  if [ ${#label} -gt 60 ]; then
    fail "label exceeded 60 chars: $label (len=${#label})"
  fi
}

@test "multiple hunks — sequential ids" {
  cat > a.md <<'EOF'
# Title

Old A line.

Long
gap
between
the
two
diffs
spanning
more
than
six
lines
of
context
.

End old.
EOF
  cat > b.md <<'EOF'
# Title

New A line.

Long
gap
between
the
two
diffs
spanning
more
than
six
lines
of
context
.

End new.
EOF
  run bash "$SCRIPT" a.md b.md
  assert_success
  assert_equal "$(echo "$output" | jq -r .total_hunks)" "2"
  assert_equal "$(echo "$output" | jq -r '.hunks[0].id')" "hunk-1"
  assert_equal "$(echo "$output" | jq -r '.hunks[1].id')" "hunk-2"
}

@test "missing local file exits 2" {
  cat > b.md <<'EOF'
b
EOF
  run bash "$SCRIPT" does-not-exist.md b.md
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing merged file exits 2" {
  cat > a.md <<'EOF'
a
EOF
  run bash "$SCRIPT" a.md does-not-exist.md
  assert_failure 2
}

@test "no arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}
