#!/usr/bin/env bats
# Tests for scripts/sync-classify-all.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-classify-all.sh"
  PLUGIN_ROOT="$TEST_TMPDIR/plugin-root"
  mkdir -p "$PLUGIN_ROOT/templates"
}

teardown() {
  teardown_common
}

# ---- error paths ----

@test "missing plugin root exits 2" {
  run bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "missing manifest exits 2" {
  # PLUGIN_ROOT exists (we created it in setup) but no manifest is present.
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_failure 2
}

@test "no arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}

# ---- happy paths ----

@test "empty manifest emits empty array" {
  printf '%s\n' '{"artifacts":[]}' > "$PLUGIN_ROOT/bootstrap-manifest.json"
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  # Use jq to compare the parsed array directly so whitespace differences do
  # not break the assertion.
  run bash -c "echo '$output' | jq -c ."
  assert_success
  assert_output "[]"
}

@test "classifies bootstrap artifact as bootstrap_create when file absent" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Sample
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {
      "upstream_key": "x/README.md@v1",
      "source": "templates/README.md.tpl",
      "target": "README.md",
      "sha256": "abc",
      "extension_strategy": "bootstrap",
      "templated": false
    }
  ]
}
EOF
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  classification="$(echo "$output" | jq -r '.[0].classification')"
  assert_equal "$classification" "bootstrap_create"
}

@test "classifies authoritative artifact as unchanged when file matches" {
  cat > "$PLUGIN_ROOT/rfc-process.md" <<'EOF'
# RFC Process

body.
EOF
  mkdir -p docs
  cp "$PLUGIN_ROOT/rfc-process.md" docs/rfc-process.md
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {
      "upstream_key": "x/docs/rfc-process.md@v1",
      "source": "rfc-process.md",
      "target": "docs/rfc-process.md",
      "sha256": "abc",
      "extension_strategy": "authoritative",
      "templated": false
    }
  ]
}
EOF
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  classification="$(echo "$output" | jq -r '.[0].classification')"
  assert_equal "$classification" "unchanged"
}

@test "result array length matches artifact count" {
  cat > "$PLUGIN_ROOT/templates/a.tpl" <<'EOF'
A
EOF
  cat > "$PLUGIN_ROOT/templates/b.tpl" <<'EOF'
B
EOF
  cat > "$PLUGIN_ROOT/templates/c.tpl" <<'EOF'
C
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {"upstream_key":"x/a@v1","source":"templates/a.tpl","target":"a.md","sha256":"x","extension_strategy":"bootstrap","templated":false},
    {"upstream_key":"x/b@v1","source":"templates/b.tpl","target":"b.md","sha256":"x","extension_strategy":"bootstrap","templated":false},
    {"upstream_key":"x/c@v1","source":"templates/c.tpl","target":"c.md","sha256":"x","extension_strategy":"bootstrap","templated":false}
  ]
}
EOF
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  length="$(echo "$output" | jq 'length')"
  assert_equal "$length" "3"
}

@test "each result includes upstream_key from manifest" {
  cat > "$PLUGIN_ROOT/templates/a.tpl" <<'EOF'
A
EOF
  cat > "$PLUGIN_ROOT/templates/b.tpl" <<'EOF'
B
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {"upstream_key":"x/a@v1","source":"templates/a.tpl","target":"a.md","sha256":"x","extension_strategy":"bootstrap","templated":false},
    {"upstream_key":"x/b@v1","source":"templates/b.tpl","target":"b.md","sha256":"x","extension_strategy":"bootstrap","templated":false}
  ]
}
EOF
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  all_have="$(echo "$output" | jq '[.[] | has("upstream_key")] | all')"
  assert_equal "$all_have" "true"
  keys="$(echo "$output" | jq -r '[.[].upstream_key] | join(",")')"
  assert_equal "$keys" "x/a@v1,x/b@v1"
}

@test "merged result includes manifest fields (source, templated, owned_*) " {
  cat > "$PLUGIN_ROOT/templates/best.tpl" <<'EOF'
# Sample

## Workflow

content
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {
      "upstream_key": "x/best@v1",
      "source": "templates/best.tpl",
      "target": "BEST_PRACTICES.md",
      "template_sha": "abc",
      "extension_strategy": "owned-regions",
      "owned_boundaries": [
        {"type": "heading", "heading": "## Workflow"}
      ],
      "templated": true,
      "template_inputs": ["languages"]
    }
  ]
}
EOF
  run bash "$SCRIPT" "$PLUGIN_ROOT"
  assert_success
  source_field="$(echo "$output" | jq -r '.[0].source')"
  templated="$(echo "$output" | jq -r '.[0].templated')"
  owned_boundaries_len="$(echo "$output" | jq -r '.[0].owned_boundaries | length')"
  template_inputs_len="$(echo "$output" | jq -r '.[0].template_inputs | length')"
  assert_equal "$source_field" "templates/best.tpl"
  assert_equal "$templated" "true"
  assert_equal "$owned_boundaries_len" "1"
  assert_equal "$template_inputs_len" "1"
}

@test "per-artifact error is non-fatal; reports error element" {
  # Plugin source for the second artifact is missing — the classifier will
  # emit a per-artifact error for it; the first one still resolves normally.
  cat > "$PLUGIN_ROOT/templates/a.tpl" <<'EOF'
A
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {"upstream_key":"x/a@v1","source":"templates/a.tpl","target":"a.md","sha256":"x","extension_strategy":"bootstrap","templated":false},
    {"upstream_key":"x/missing@v1","source":"templates/missing.tpl","target":"missing.md","sha256":"x","extension_strategy":"authoritative","templated":false}
  ]
}
EOF
  # Use 2>/dev/null so the stderr error message does not pollute $output.
  run bash -c "bash \"$SCRIPT\" \"$PLUGIN_ROOT\" 2>/dev/null"
  assert_success
  length="$(echo "$output" | jq 'length')"
  assert_equal "$length" "2"
  error_elt="$(echo "$output" | jq -r '.[1].classification')"
  assert_equal "$error_elt" "error"
  has_error_field="$(echo "$output" | jq -r '.[1].error | length > 0')"
  assert_equal "$has_error_field" "true"
}

@test "uses provided repo root when target is in a separate tree" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Sample
EOF
  cat > "$PLUGIN_ROOT/bootstrap-manifest.json" <<'EOF'
{
  "artifacts": [
    {
      "upstream_key": "x/README.md@v1",
      "source": "templates/README.md.tpl",
      "target": "README.md",
      "sha256": "abc",
      "extension_strategy": "bootstrap",
      "templated": false
    }
  ]
}
EOF
  # Build a separate "repo" with the README already present so classification
  # should report local_only when invoked with that repo root.
  mkdir -p other-repo
  echo "local content" > other-repo/README.md
  run bash "$SCRIPT" "$PLUGIN_ROOT" "$TEST_TMPDIR/other-repo"
  assert_success
  classification="$(echo "$output" | jq -r '.[0].classification')"
  assert_equal "$classification" "local_only"
}
