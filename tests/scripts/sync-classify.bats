#!/usr/bin/env bats
# Tests for scripts/sync-classify.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-classify.sh"
  PLUGIN_ROOT="$TEST_TMPDIR/plugin-root"
  mkdir -p "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/rfc-process.md.d"
}

teardown() {
  teardown_common
}

# ---------- bootstrap ----------

@test "bootstrap — target absent -> bootstrap_create" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Sample
EOF
  m='{"upstream_key":"x@v1","source":"templates/README.md.tpl","target":"README.md","extension_strategy":"bootstrap","templated":false}'
  run bash "$SCRIPT" "$m" README.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "bootstrap_create"
}

@test "bootstrap — target present -> local_only" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Sample
EOF
  m='{"upstream_key":"x@v1","source":"templates/README.md.tpl","target":"README.md","extension_strategy":"bootstrap","templated":false}'
  echo "local content" > README.md
  run bash "$SCRIPT" "$m" README.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "local_only"
}

# ---------- authoritative ----------

@test "authoritative — target absent -> authoritative_add" {
  cat > "$PLUGIN_ROOT/rfc-process.md" <<'EOF'
# RFC Process

body.
EOF
  m='{"upstream_key":"r@v1","source":"rfc-process.md","target":"docs/rfc-process.md","extension_strategy":"authoritative","templated":false}'
  mkdir -p docs
  run bash "$SCRIPT" "$m" docs/rfc-process.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "authoritative_add"
}

@test "authoritative — content matches -> unchanged" {
  cat > "$PLUGIN_ROOT/rfc-process.md" <<'EOF'
# RFC

body.
EOF
  mkdir -p docs
  cp "$PLUGIN_ROOT/rfc-process.md" docs/rfc-process.md
  m='{"upstream_key":"r@v1","source":"rfc-process.md","target":"docs/rfc-process.md","extension_strategy":"authoritative","templated":false}'
  run bash "$SCRIPT" "$m" docs/rfc-process.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "unchanged"
}

@test "authoritative — content differs -> authoritative_update" {
  cat > "$PLUGIN_ROOT/rfc-process.md" <<'EOF'
# RFC

body.
EOF
  mkdir -p docs
  cp "$PLUGIN_ROOT/rfc-process.md" docs/rfc-process.md
  echo "extra line" >> docs/rfc-process.md
  m='{"upstream_key":"r@v1","source":"rfc-process.md","target":"docs/rfc-process.md","extension_strategy":"authoritative","templated":false}'
  run bash "$SCRIPT" "$m" docs/rfc-process.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "authoritative_update"
}

# ---------- additive-merge ----------

@test "additive-merge — target absent -> additive_merge_apply" {
  cat > "$PLUGIN_ROOT/templates/CLAUDE.md.tpl" <<'EOF'
# Title

## Tool Usage

- foo
EOF
  m='{"upstream_key":"c@v1","source":"templates/CLAUDE.md.tpl","target":"CLAUDE.md","extension_strategy":"additive-merge","owned_sections":["## Tool Usage"],"templated":true}'
  run bash "$SCRIPT" "$m" CLAUDE.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "additive_merge_apply"
}

@test "additive-merge — present, no marker -> additive_merge_apply" {
  cat > "$PLUGIN_ROOT/templates/CLAUDE.md.tpl" <<'EOF'
## Tool Usage

- a
EOF
  cat > CLAUDE.md <<'EOF'
# Title

## Tool Usage

- old
EOF
  m='{"upstream_key":"c@v1","source":"templates/CLAUDE.md.tpl","target":"CLAUDE.md","extension_strategy":"additive-merge","owned_sections":["## Tool Usage"]}'
  run bash "$SCRIPT" "$m" CLAUDE.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "additive_merge_apply"
}

@test "additive-merge — marker matches plugin canonical -> unchanged" {
  cat > "$PLUGIN_ROOT/templates/CLAUDE.md.tpl" <<'EOF'
## Tool Usage

- a
EOF
  m_base='{"source":"templates/CLAUDE.md.tpl","target":"CLAUDE.md","extension_strategy":"additive-merge","owned_sections":["## Tool Usage"]}'
  expected_key="$(compute_upstream_key "$m_base")"
  m="$(printf '%s' "$m_base" | jq --arg k "$expected_key" '. + {upstream_key: $k}')"
  # First, compute the plugin canonical SHA so we can construct a matching marker.
  plug_sha="$(bash "$SCRIPT_ROOT/scripts/sync-canonical.sh" additive-merge "$PLUGIN_ROOT/templates/CLAUDE.md.tpl" --owned-sections '["## Tool Usage"]' | jq -r .sha12)"
  cat > CLAUDE.md <<EOF
# Title
<!-- bootstrap-content-version: ${expected_key}:$plug_sha -->

## Tool Usage

- whatever the user wants
EOF
  run bash "$SCRIPT" "$m" CLAUDE.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "unchanged"
}

@test "additive-merge-with-diff — uses _with_diff classification name" {
  cat > "$PLUGIN_ROOT/templates/ci.yml.tpl" <<'EOF'
name: ci
EOF
  m='{"upstream_key":"y@v1","source":"templates/ci.yml.tpl","target":"ci.yml","extension_strategy":"additive-merge-with-diff","owned_sections":[]}'
  run bash "$SCRIPT" "$m" ci.yml "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "additive_merge_with_diff_apply"
}

# ---------- ci.yml target-aware canonical through the real pipeline (Fix 3) ----------
# These go through sync-classify with a .tpl plugin source and a .yml target, so
# they catch the round-1 regression: if the type dispatch keyed off the incoming
# file (the .tpl) instead of the target (the .yml), plugin_sha would collapse to
# the degenerate empty SHA and ci.yml would be inert end to end.

@test "ci.yml — classify computes a non-degenerate plugin_sha from the .tpl source" {
  cat > "$PLUGIN_ROOT/templates/ci.yml.tpl" <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  mkdir -p .github/workflows
  m='{"upstream_key":"ci@v1","source":"templates/ci.yml.tpl","target":".github/workflows/ci.yml","extension_strategy":"additive-merge-with-diff","owned_paths":["*"],"templated":true}'
  run bash "$SCRIPT" "$m" ".github/workflows/ci.yml" "$PLUGIN_ROOT"
  assert_success
  plug="$(echo "$output" | jq -r .plugin_sha)"
  [[ "$plug" =~ ^[0-9a-f]{12}$ ]] || fail "plugin_sha not 12 hex: $plug"
  refute [ "$plug" = "e3b0c44298fc" ]
}

@test "ci.yml — an in-sync consumer classifies unchanged" {
  cat > "$PLUGIN_ROOT/templates/ci.yml.tpl" <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
EOF
  m_base='{"source":"templates/ci.yml.tpl","target":".github/workflows/ci.yml","extension_strategy":"additive-merge-with-diff","owned_paths":["*"],"templated":true}'
  expected_key="$(compute_upstream_key "$m_base")"
  m="$(printf '%s' "$m_base" | jq --arg k "$expected_key" '. + {upstream_key: $k}')"
  # The recorded marker == the target-aware plugin canonical.
  plug="$(bash "$SCRIPT_ROOT/scripts/sync-canonical.sh" additive-merge-with-diff "$PLUGIN_ROOT/templates/ci.yml.tpl" --owned-sections '[]' --target .github/workflows/ci.yml | jq -r .sha12)"
  mkdir -p .github/workflows
  printf '# bootstrap-content-version: %s:%s\n\nname: CI\njobs:\n  local:\n    runs-on: whatever\n' "$expected_key" "$plug" > .github/workflows/ci.yml
  run bash "$SCRIPT" "$m" ".github/workflows/ci.yml" "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "unchanged"
}

@test "ci.yml — a plugin-template content change is flagged as drift" {
  cat > "$PLUGIN_ROOT/templates/ci.yml.tpl" <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
EOF
  m_base='{"source":"templates/ci.yml.tpl","target":".github/workflows/ci.yml","extension_strategy":"additive-merge-with-diff","owned_paths":["*"],"templated":true}'
  expected_key="$(compute_upstream_key "$m_base")"
  m="$(printf '%s' "$m_base" | jq --arg k "$expected_key" '. + {upstream_key: $k}')"
  plug_old="$(bash "$SCRIPT_ROOT/scripts/sync-canonical.sh" additive-merge-with-diff "$PLUGIN_ROOT/templates/ci.yml.tpl" --owned-sections '[]' --target .github/workflows/ci.yml | jq -r .sha12)"
  mkdir -p .github/workflows
  printf '# bootstrap-content-version: %s:%s\n\nname: CI\n' "$expected_key" "$plug_old" > .github/workflows/ci.yml
  # Plugin template changes materially.
  cat > "$PLUGIN_ROOT/templates/ci.yml.tpl" <<'EOF'
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
  lint:
    runs-on: ubuntu-latest
EOF
  run bash "$SCRIPT" "$m" ".github/workflows/ci.yml" "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "additive_merge_with_diff_apply"
}

# ---------- structured ----------

@test "structured — target absent -> add" {
  cat > "$PLUGIN_ROOT/templates/settings.json.tpl" <<'EOF'
{"a": 1}
EOF
  m='{"upstream_key":"s@v1","source":"templates/settings.json.tpl","target":"settings.json","extension_strategy":"structured","owned_paths":["*"],"templated":false}'
  run bash "$SCRIPT" "$m" settings.json "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "add"
}

@test "structured — legacy match (no marker, content matches) -> unchanged_legacy" {
  cat > "$PLUGIN_ROOT/templates/foo.tpl" <<'EOF'
{"a": 1}
EOF
  cp "$PLUGIN_ROOT/templates/foo.tpl" foo.json
  m='{"upstream_key":"f@v1","source":"templates/foo.tpl","target":"foo.json","extension_strategy":"structured","owned_paths":["*"]}'
  run bash "$SCRIPT" "$m" foo.json "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "unchanged_legacy"
}

@test "structured — legacy mismatch (no marker, content differs) -> conflict_legacy" {
  cat > "$PLUGIN_ROOT/templates/foo.tpl" <<'EOF'
{"a": 1}
EOF
  cat > foo.json <<'EOF'
{"a": 2}
EOF
  m='{"upstream_key":"f@v1","source":"templates/foo.tpl","target":"foo.json","extension_strategy":"structured","owned_paths":["*"]}'
  run bash "$SCRIPT" "$m" foo.json "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "conflict_legacy"
}

# ---------- owned-regions ----------

@test "owned-regions — target absent -> add" {
  cat > "$PLUGIN_ROOT/templates/B.md.tpl" <<'EOF'
# B

## Workflow

content.
EOF
  m='{"upstream_key":"b@v1","source":"templates/B.md.tpl","target":"BEST.md","extension_strategy":"owned-regions","owned_boundaries":[{"type":"heading","heading":"## Workflow"}]}'
  run bash "$SCRIPT" "$m" BEST.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "add"
}

# ---------- error paths ----------

@test "missing arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}

@test "unrecognized strategy exits 2" {
  m='{"upstream_key":"x@v1","source":"x.tpl","target":"x","extension_strategy":"banana"}'
  cat > "$PLUGIN_ROOT/x.tpl" <<'EOF'
x
EOF
  run bash "$SCRIPT" "$m" x "$PLUGIN_ROOT"
  assert_failure 2
}

@test "manifest from stdin works" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Sample
EOF
  m='{"upstream_key":"x@v1","source":"templates/README.md.tpl","target":"README.md","extension_strategy":"bootstrap"}'
  run bash -c "echo '$m' | bash \"$SCRIPT\" - README.md \"$PLUGIN_ROOT\""
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "bootstrap_create"
}

# ---------- chunks output ----------

@test "structured JSON — conflict_legacy emits chunks with owned path changed and preserved keys" {
  cat > "$PLUGIN_ROOT/templates/settings.json.tpl" <<'EOF'
{"hooks": {"Stop": [{"type":"command","command":"echo done"}]}, "enabledPlugins": {}}
EOF
  cat > settings.json <<'EOF'
{"hooks": {}, "enabledPlugins": {"bytewyrd": true}}
EOF
  m='{"upstream_key":"s@v1","source":"templates/settings.json.tpl","target":"settings.json","extension_strategy":"structured","owned_paths":["hooks"],"templated":false}'
  run bash "$SCRIPT" "$m" settings.json "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "conflict_legacy"
  # At least the owned chunk + one preserved chunk.
  chunks_len="$(echo "$output" | jq -r '.chunks | length')"
  [ "$chunks_len" -ge 2 ] || fail "expected chunks length >= 2, got: $chunks_len"
  # First chunk is the owned hooks dotpath, changed.
  assert_equal "$(echo "$output" | jq -r '.chunks[0].id')" "hooks"
  assert_equal "$(echo "$output" | jq -r '.chunks[0].status')" "changed"
  assert_equal "$(echo "$output" | jq -r '.chunks[0].owned')" "true"
  # enabledPlugins (not in owned_paths) is preserved.
  preserved_count="$(echo "$output" | jq '[.chunks[] | select(.id == "enabledPlugins" and .status == "preserved" and .owned == false)] | length')"
  [ "$preserved_count" -ge 1 ] || fail "expected at least one preserved enabledPlugins chunk, got: $preserved_count"
}

@test "structured .gitignore — fast_forward emits chunks with block status" {
  # Plugin source has updated bytewyrd:base block content.
  cat > "$PLUGIN_ROOT/templates/.gitignore.tpl" <<'EOF'
# bytewyrd:base
.worktrees/
.bytewyrd/*
EOF
  # Compute the plugin canonical SHA so the local marker matches the recorded baseline.
  paths='["bytewyrd:base"]'
  # We need recorded == old plugin sha (legacy state) but here we test fast_forward,
  # where local matches the recorded marker and the plugin has advanced.
  # Create local file with an old version of the bytewyrd:base block.
  cat > .gitignore <<'EOF'
# bytewyrd:base
.worktrees/

# user content below
*.log
EOF
  # Compute the canonical sha of the LOCAL file (old block content); use that as
  # the recorded marker — this puts us in the fast_forward branch (local==recorded,
  # plugin!=recorded).
  local_sha="$(bash "$SCRIPT_ROOT/scripts/sync-canonical.sh" structured .gitignore --owned-paths "$paths" | jq -r .sha12)"
  # Prepend the marker as line 1 of .gitignore.
  tmpfile="$(mktemp)"
  m_base='{"source":"templates/.gitignore.tpl","target":".gitignore","extension_strategy":"structured","owned_paths":["bytewyrd:base"],"templated":false}'
  expected_key="$(compute_upstream_key "$m_base")"
  m="$(printf '%s' "$m_base" | jq --arg k "$expected_key" '. + {upstream_key: $k}')"
  printf '# bootstrap-content-version: %s:%s\n\n' "$expected_key" "$local_sha" > "$tmpfile"
  cat .gitignore >> "$tmpfile"
  mv "$tmpfile" .gitignore
  run bash "$SCRIPT" "$m" .gitignore "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "fast_forward"
  chunks_len="$(echo "$output" | jq -r '.chunks | length')"
  [ "$chunks_len" -ge 1 ] || fail "expected chunks length >= 1, got: $chunks_len"
  # First chunk is the owned tag block.
  assert_equal "$(echo "$output" | jq -r '.chunks[0].id')" "bytewyrd:base"
  assert_equal "$(echo "$output" | jq -r '.chunks[0].type')" "gitignore_block"
  assert_equal "$(echo "$output" | jq -r '.chunks[0].owned')" "true"
  # A preserved gitignore_other chunk exists.
  other_count="$(echo "$output" | jq '[.chunks[] | select(.type == "gitignore_other" and .status == "preserved")] | length')"
  [ "$other_count" -ge 1 ] || fail "expected at least one gitignore_other preserved chunk, got: $other_count"
}

@test "owned-regions — conflict emits chunks with owned and user headings" {
  cat > "$PLUGIN_ROOT/templates/BEST.md.tpl" <<'EOF'
# BEST

## Workflow

new workflow content.
EOF
  # Build the local file: a marker (recorded sha unrelated to current local/plugin
  # so all three differ — triggers conflict), the heading, an old body, plus a
  # user-owned heading the plugin doesn't know about.
  paths='[{"type":"heading","heading":"## Workflow"}]'
  m_base='{"source":"templates/BEST.md.tpl","target":"BEST.md","extension_strategy":"owned-regions","owned_boundaries":[{"type":"heading","heading":"## Workflow"}],"templated":false}'
  expected_key="$(compute_upstream_key "$m_base")"
  m="$(printf '%s' "$m_base" | jq --arg k "$expected_key" '. + {upstream_key: $k}')"
  cat > BEST.md <<EOF
<!-- bootstrap-content-version: ${expected_key}:000000000000 -->

# BEST

## Workflow

old workflow content.

## Project Notes

my custom notes.
EOF
  run bash "$SCRIPT" "$m" BEST.md "$PLUGIN_ROOT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .classification)" "conflict"
  chunks_len="$(echo "$output" | jq -r '.chunks | length')"
  [ "$chunks_len" -ge 2 ] || fail "expected chunks length >= 2, got: $chunks_len"
  # Owned heading chunk: ## Workflow, owned=true, status=changed.
  owned_count="$(echo "$output" | jq '[.chunks[] | select(.id == "## Workflow" and .owned == true and .status == "changed")] | length')"
  [ "$owned_count" -ge 1 ] || fail "expected owned ## Workflow chunk changed, got count: $owned_count"
  # User heading chunk: ## Project Notes, owned=false, status=preserved.
  preserved_count="$(echo "$output" | jq '[.chunks[] | select(.id == "## Project Notes" and .owned == false and .status == "preserved")] | length')"
  [ "$preserved_count" -ge 1 ] || fail "expected preserved ## Project Notes chunk, got count: $preserved_count"
}
