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
  m='{"upstream_key":"c@v1","source":"templates/CLAUDE.md.tpl","target":"CLAUDE.md","extension_strategy":"additive-merge","owned_sections":["## Tool Usage"]}'
  # First, compute the plugin canonical SHA so we can construct a matching marker.
  plug_sha="$(bash "$SCRIPT_ROOT/scripts/sync-canonical.sh" additive-merge "$PLUGIN_ROOT/templates/CLAUDE.md.tpl" --owned-sections '["## Tool Usage"]' | jq -r .sha12)"
  cat > CLAUDE.md <<EOF
# Title
<!-- bootstrap-content-version: c@v1:$plug_sha -->

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
