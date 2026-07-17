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

# --- additive-merge: --target-driven type dispatch (Fix 3 / round-1 regression) ---

@test "additive-merge — --target routes a .tpl source through the YAML whole-file canonical" {
  # A YAML workflow stored in a .tpl-named source, exactly as the plugin ships
  # it. Keying the type dispatch off the incoming filename (".tpl") would miss
  # the YAML branch and hash empty owned_sections -> the degenerate empty SHA.
  cat > src.tpl <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
EOF
  # No --target: ".tpl" is not "*.yml" and owned_sections is empty -> degenerate.
  no_target="$(bash "$SCRIPT" additive-merge-with-diff src.tpl --owned-sections '[]' | jq -r .sha12)"
  assert_equal "$no_target" "e3b0c44298fc"
  # With --target=<*.yml>: routed through the whole-file YAML canonical.
  with_target="$(bash "$SCRIPT" additive-merge-with-diff src.tpl --owned-sections '[]' --target .github/workflows/ci.yml | jq -r .sha12)"
  [[ "$with_target" =~ ^[0-9a-f]{12}$ ]] || fail "expected 12 hex chars, got: $with_target"
  refute [ "$with_target" = "e3b0c44298fc" ]
}

@test "additive-merge — target-routed canonical agrees across a .tpl source and a .yml file" {
  # The whole point of keying off --target: the plugin side (a .tpl) and the
  # local side (a real .yml) must hash identically when content agrees,
  # otherwise plugin_sha and local_sha can never be compared.
  content='name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
'
  printf '%s' "$content" > plugin.tpl
  printf '%s' "$content" > local.yml
  plug="$(bash "$SCRIPT" additive-merge-with-diff plugin.tpl --owned-sections '[]' --target x.yml | jq -r .sha12)"
  loc="$(bash "$SCRIPT" additive-merge-with-diff local.yml  --owned-sections '[]' --target x.yml | jq -r .sha12)"
  assert_equal "$plug" "$loc"
  refute [ "$plug" = "e3b0c44298fc" ]
}

@test "additive-merge — YAML whole-file canonical (target-routed) is content-sensitive and marker-stable" {
  # Sources named .tpl (as the plugin ships them) but routed as YAML via --target.
  printf '# bootstrap-content-version: k@v1:000000000000\nname: CI\njobs:\n  a:\n    runs-on: x\n' > a.tpl
  # Same body, different marker line only -> canonical unchanged (marker stripped).
  printf '# bootstrap-content-version: k@v1:ffffffffffff\nname: CI\njobs:\n  a:\n    runs-on: x\n' > a2.tpl
  # Different body -> canonical changes.
  printf '# bootstrap-content-version: k@v1:000000000000\nname: CI\njobs:\n  a:\n    runs-on: x\n  b:\n    runs-on: y\n' > b.tpl
  sha_a="$(bash "$SCRIPT" additive-merge-with-diff a.tpl --owned-sections '[]' --target ci.yml | jq -r .sha12)"
  sha_a2="$(bash "$SCRIPT" additive-merge-with-diff a2.tpl --owned-sections '[]' --target ci.yml | jq -r .sha12)"
  sha_b="$(bash "$SCRIPT" additive-merge-with-diff b.tpl --owned-sections '[]' --target ci.yml | jq -r .sha12)"
  assert_equal "$sha_a" "$sha_a2"
  refute [ "$sha_a" = "$sha_b" ]
  refute [ "$sha_a" = "e3b0c44298fc" ]
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

# --- structured TOML (mise.toml tools[]:union, Fix 6) ---

@test "structured TOML — a real [tools] table is parsed, not degenerate" {
  cat > mise.toml <<'EOF'
[tools]
node = "20"
bun = "1.1"
EOF
  sha="$(bash "$SCRIPT" structured mise.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  [[ "$sha" =~ ^[0-9a-f]{12}$ ]] || fail "expected 12 hex, got: $sha"
  # Pre-fix jq-on-TOML silently produced the empty-string SHA.
  refute [ "$sha" = "e3b0c44298fc" ]
}

@test "structured TOML — canonical is content-sensitive and order-independent" {
  cat > two.toml <<'EOF'
[tools]
node = "20"
bun = "1.1"
EOF
  cat > two_reordered.toml <<'EOF'
[tools]
bun = "1.1"
node = "20"
EOF
  cat > three.toml <<'EOF'
[tools]
node = "20"
bun = "1.1"
python = "3.12"
EOF
  cat > changed.toml <<'EOF'
[tools]
node = "22"
bun = "1.1"
EOF
  sha_two="$(bash "$SCRIPT" structured two.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  sha_reord="$(bash "$SCRIPT" structured two_reordered.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  sha_three="$(bash "$SCRIPT" structured three.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  sha_changed="$(bash "$SCRIPT" structured changed.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  assert_equal "$sha_two" "$sha_reord"     # order-independent
  refute [ "$sha_two" = "$sha_three" ]      # adding a tool changes it
  refute [ "$sha_two" = "$sha_changed" ]    # changing a version changes it
}

@test "structured TOML — unfilled <TOOLS_SECTION> placeholder is stripped, not crashed" {
  # The deterministically-rendered plugin template carries the LLM-filled
  # placeholder; it must decode to an empty [tools] table, not fail to parse.
  cat > placeholder.toml <<'EOF'
[tools]
<TOOLS_SECTION>
EOF
  cat > empty.toml <<'EOF'
[tools]
EOF
  run bash "$SCRIPT" structured placeholder.toml --owned-paths '["tools[]:union"]'
  assert_success
  ph_sha="$(echo "$output" | jq -r .sha12)"
  empty_sha="$(bash "$SCRIPT" structured empty.toml --owned-paths '["tools[]:union"]' | jq -r .sha12)"
  # Placeholder strips to an empty table -> same canonical as a real empty [tools].
  assert_equal "$ph_sha" "$empty_sha"
  # And that empty-table canonical is a real parse, not the degenerate empty SHA.
  refute [ "$empty_sha" = "e3b0c44298fc" ]
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
