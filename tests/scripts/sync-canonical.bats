#!/usr/bin/env bats
# Tests for scripts/sync-canonical.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-canonical.sh"
}

teardown() {
  teardown_common
}

# --- helpers ---
write_md_with_sections() {
  cat > "$1" <<'EOF'
<!-- bootstrap-content-version: my/key@v1:000000000000 -->
<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->

# Title

Intro.

## Tool Usage

Use Exa.

## Security

No tokens.
EOF
}

# --- authoritative ---

@test "authoritative — sha12 is 12 hex chars" {
  write_md_with_sections rfc.md
  run bash "$SCRIPT" authoritative rfc.md
  assert_success
  sha="$(echo "$output" | jq -r .sha12)"
  [[ "$sha" =~ ^[0-9a-f]{12}$ ]] || fail "sha12 should be 12 hex chars, got: $sha"
}

@test "authoritative — header changes alone do not change sha" {
  write_md_with_sections a.md
  cp a.md b.md
  # Modify only the header marker line.
  sed -i 's/000000000000/111111111111/' b.md
  run bash "$SCRIPT" authoritative a.md
  assert_success
  sha_a="$(echo "$output" | jq -r .sha12)"
  run bash "$SCRIPT" authoritative b.md
  assert_success
  sha_b="$(echo "$output" | jq -r .sha12)"
  assert_equal "$sha_a" "$sha_b"
}

@test "authoritative — body changes change sha" {
  write_md_with_sections a.md
  cp a.md b.md
  printf '\nExtra body content.\n' >> b.md
  run bash "$SCRIPT" authoritative a.md
  sha_a="$(echo "$output" | jq -r .sha12)"
  run bash "$SCRIPT" authoritative b.md
  sha_b="$(echo "$output" | jq -r .sha12)"
  refute [ "$sha_a" = "$sha_b" ]
}

# --- additive-merge ---

@test "additive-merge — uses --owned-sections only, ignores other content" {
  write_md_with_sections foo.md
  run bash "$SCRIPT" additive-merge foo.md --owned-sections '["## Tool Usage", "## Security"]'
  assert_success
  sha="$(echo "$output" | jq -r .sha12)"
  [[ "$sha" =~ ^[0-9a-f]{12}$ ]] || fail "sha12 must be 12 hex chars, got: $sha"
}

@test "additive-merge — changing non-owned content does not change sha" {
  write_md_with_sections a.md
  cp a.md b.md
  # Append a new heading not in owned_sections.
  cat >> b.md <<'EOF'

## Misc

random content not in owned set.
EOF
  run bash "$SCRIPT" additive-merge a.md --owned-sections '["## Tool Usage", "## Security"]'
  sha_a="$(echo "$output" | jq -r .sha12)"
  run bash "$SCRIPT" additive-merge b.md --owned-sections '["## Tool Usage", "## Security"]'
  sha_b="$(echo "$output" | jq -r .sha12)"
  assert_equal "$sha_a" "$sha_b"
}

@test "additive-merge — changing owned content changes sha" {
  write_md_with_sections a.md
  cp a.md b.md
  # Replace the body of ## Tool Usage with different content.
  sed -i 's/Use Exa\./Use a completely different tool./' b.md
  run bash "$SCRIPT" additive-merge a.md --owned-sections '["## Tool Usage", "## Security"]'
  sha_a="$(echo "$output" | jq -r .sha12)"
  run bash "$SCRIPT" additive-merge b.md --owned-sections '["## Tool Usage", "## Security"]'
  sha_b="$(echo "$output" | jq -r .sha12)"
  refute [ "$sha_a" = "$sha_b" ]
}

# --- owned-regions ---

@test "owned-regions — boundary heading body hashed in order" {
  write_md_with_sections foo.md
  boundaries='[{"type":"heading","heading":"## Tool Usage"},{"type":"heading","heading":"## Security"}]'
  run bash "$SCRIPT" owned-regions foo.md --owned-boundaries "$boundaries"
  assert_success
  sha="$(echo "$output" | jq -r .sha12)"
  [[ "$sha" =~ ^[0-9a-f]{12}$ ]] || fail "sha12 must be 12 hex chars, got: $sha"
}

# --- structured JSON ---

@test "structured JSON — single path extraction" {
  cat > settings.json <<'EOF'
{"a": {"b": 1}, "c": 2}
EOF
  run bash "$SCRIPT" structured settings.json --owned-paths '["a"]'
  assert_success
  sha="$(echo "$output" | jq -r .sha12)"
  [[ "$sha" =~ ^[0-9a-f]{12}$ ]] || fail "sha12 must be 12 hex chars, got: $sha"
}

@test "structured JSON — wildcard hashes whole document" {
  cat > settings.json <<'EOF'
{"a": 1, "b": 2}
EOF
  run bash "$SCRIPT" structured settings.json --owned-paths '["*"]'
  assert_success
  sha_full="$(echo "$output" | jq -r .sha12)"
  # Change the document.
  cat > settings.json <<'EOF'
{"a": 1, "b": 3}
EOF
  run bash "$SCRIPT" structured settings.json --owned-paths '["*"]'
  sha_changed="$(echo "$output" | jq -r .sha12)"
  refute [ "$sha_full" = "$sha_changed" ]
}

# --- structured .gitignore ---

@test "structured .gitignore — tagged block extraction" {
  cat > .gitignore <<'EOF'
# bytewyrd:base
.worktrees/
.claude/settings.local.json

# bytewyrd:rust
target/

# user-owned
custom.bin
EOF
  run bash "$SCRIPT" structured .gitignore --owned-paths '["bytewyrd:base"]'
  assert_success
  sha_a="$(echo "$output" | jq -r .sha12)"
  # Add user-owned line — sha should be unchanged.
  cat >> .gitignore <<'EOF'
another-user-thing.bak
EOF
  run bash "$SCRIPT" structured .gitignore --owned-paths '["bytewyrd:base"]'
  sha_b="$(echo "$output" | jq -r .sha12)"
  assert_equal "$sha_a" "$sha_b"
}

# --- error paths ---

@test "missing file exits 1" {
  run bash "$SCRIPT" authoritative does-not-exist.md
  assert_failure 1
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "unrecognized strategy exits 2" {
  cat > foo.md <<'EOF'
# foo
EOF
  run bash "$SCRIPT" totally-unknown foo.md
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing required arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}
