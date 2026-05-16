#!/usr/bin/env bats
# Tests for scripts/sync-apply-batch.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-apply-batch.sh"
  PLUGIN_ROOT="$TEST_TMPDIR/plugin-root"
  mkdir -p "$PLUGIN_ROOT/templates"
  cat > inputs.json <<'EOF'
{"project_name": "Test", "description": "Test project"}
EOF
}

teardown() {
  teardown_common
}

# ---- error paths ----

@test "missing plugin root exits 2" {
  run bash "$SCRIPT" "[]" "$TEST_TMPDIR/does-not-exist" inputs.json
  assert_failure 2
}

@test "missing inputs json exits 2" {
  run bash "$SCRIPT" "[]" "$PLUGIN_ROOT" "$TEST_TMPDIR/does-not-exist.json"
  assert_failure 2
}

@test "items must be a JSON array — non-array exits 2" {
  run bash "$SCRIPT" '{"not":"an array"}' "$PLUGIN_ROOT" inputs.json
  assert_failure 2
}

@test "no arguments exits 2" {
  run bash "$SCRIPT"
  assert_failure 2
}

# ---- happy paths ----

@test "empty items array returns empty array" {
  run bash "$SCRIPT" "[]" "$PLUGIN_ROOT" inputs.json
  assert_success
  run bash -c "echo '$output' | jq -c ."
  assert_success
  assert_output "[]"
}

@test "authoritative_add copies file and stamps header" {
  cat > "$PLUGIN_ROOT/rfc-process.md" <<'EOF'
# RFC Process

body line.
EOF
  mkdir -p docs
  items_json='[{
    "classification": "authoritative_add",
    "strategy": "authoritative",
    "target": "docs/rfc-process.md",
    "recorded_sha": null,
    "plugin_sha": "abc123def456",
    "upstream_key": "x/docs/rfc-process.md@v1",
    "source": "rfc-process.md",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  # File written.
  [ -f "docs/rfc-process.md" ] || fail "expected docs/rfc-process.md to be created"
  # First line carries the marker.
  line1="$(sed -n '1p' docs/rfc-process.md)"
  case "$line1" in
    "<!-- bootstrap-content-version: x/docs/rfc-process.md@v1:"*"-->") ;;
    *) fail "expected line 1 to be the bootstrap marker, got: $line1" ;;
  esac
  # Line 2 carries the Managed tagline (authoritative header type).
  line2="$(sed -n '2p' docs/rfc-process.md)"
  case "$line2" in
    *"Managed by the Bytewyrd plugin"*) ;;
    *) fail "expected line 2 to contain Managed tagline, got: $line2" ;;
  esac
  # Result indicates applied.
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "applied"
}

@test "unchanged_legacy stamps marker on non-JSON file (Markdown)" {
  mkdir -p docs
  cat > docs/BEST.md <<'EOF'
# BEST

## Workflow

content
EOF
  items_json='[{
    "classification": "unchanged_legacy",
    "strategy": "owned-regions",
    "target": "docs/BEST.md",
    "recorded_sha": null,
    "plugin_sha": "abc123def456",
    "upstream_key": "x/best@v1",
    "source": "templates/best.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [{"type":"heading","heading":"## Workflow"}],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "marker_stamped"
  # Marker present.
  marker_count="$(grep -c 'bootstrap-content-version' docs/BEST.md || true)"
  assert_equal "$marker_count" "1"
  # Body content preserved.
  grep -Fq "## Workflow" docs/BEST.md || fail "expected ## Workflow to remain"
  grep -Fq "content" docs/BEST.md || fail "expected body to remain"
}

@test "unchanged_legacy on JSON file records sidecar_update_needed" {
  mkdir -p .claude
  echo '{"a": 1}' > .claude/settings.json
  items_json='[{
    "classification": "unchanged_legacy",
    "strategy": "structured",
    "target": ".claude/settings.json",
    "recorded_sha": null,
    "plugin_sha": "abc123def456",
    "upstream_key": "x/.claude/settings.json@v1",
    "source": "templates/settings.json.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": ["*"],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "marker_stamped"
  sidecar_flag="$(echo "$output" | jq -r '.[0].sidecar_update_needed')"
  assert_equal "$sidecar_flag" "true"
  # JSON file content unchanged (no inline marker injected).
  marker_count="$(grep -c 'bootstrap-content-version' .claude/settings.json || true)"
  assert_equal "$marker_count" "0"
}

@test "bootstrap_create renders template and writes file" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# <project_name>

<description>
EOF
  items_json='[{
    "classification": "bootstrap_create",
    "strategy": "bootstrap",
    "target": "README.md",
    "recorded_sha": null,
    "plugin_sha": null,
    "upstream_key": "x/README.md@v1",
    "source": "templates/README.md.tpl",
    "templated": true,
    "template_inputs": ["project_name", "description"],
    "owned_paths": [],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  [ -f "README.md" ] || fail "expected README.md to be created"
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "applied"
  # Template substitutions happened.
  grep -Fq "# Test" README.md || fail "expected substituted project_name in README"
  grep -Fq "Test project" README.md || fail "expected substituted description in README"
  # Bootstrap header stamped.
  line1="$(sed -n '1p' README.md)"
  case "$line1" in
    "<!-- bootstrap-content-version: x/README.md@v1:"*"-->") ;;
    *) fail "expected line 1 to be the bootstrap marker, got: $line1" ;;
  esac
}

@test "conflict classification returns needs-agent" {
  items_json='[{
    "classification": "conflict",
    "strategy": "owned-regions",
    "target": "docs/BEST.md",
    "recorded_sha": "aaa111aaa111",
    "plugin_sha": "bbb222bbb222",
    "upstream_key": "x/best@v1",
    "source": "templates/best.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [{"type":"heading","heading":"## Workflow"}],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "needs-agent"
}

@test "additive_merge_apply returns needs-agent" {
  items_json='[{
    "classification": "additive_merge_apply",
    "strategy": "additive-merge",
    "target": "CLAUDE.md",
    "recorded_sha": null,
    "plugin_sha": "deadbeefcafe",
    "upstream_key": "x/CLAUDE.md@v1",
    "source": "templates/CLAUDE.md.tpl",
    "templated": true,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [],
    "owned_sections": ["## Tool Usage"]
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "needs-agent"
}

@test "structured JSON fast_forward returns needs-agent" {
  mkdir -p .claude
  echo '{"a": 1}' > .claude/settings.json
  items_json='[{
    "classification": "fast_forward",
    "strategy": "structured",
    "target": ".claude/settings.json",
    "recorded_sha": "aaa111aaa111",
    "plugin_sha": "bbb222bbb222",
    "upstream_key": "x/.claude/settings.json@v1",
    "source": "templates/settings.json.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": ["hooks.PreCompact[]:_meta.bytewyrd_hook_id"],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "needs-agent"
}

@test "unchanged classification returns skipped" {
  items_json='[{
    "classification": "unchanged",
    "strategy": "owned-regions",
    "target": "docs/BEST.md",
    "recorded_sha": "aaa111aaa111",
    "plugin_sha": "aaa111aaa111",
    "upstream_key": "x/best@v1",
    "source": "templates/best.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [{"type":"heading","heading":"## Workflow"}],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "skipped"
}

@test "fast_forward owned-regions merges plugin section into local file" {
  mkdir -p docs
  cat > docs/BEST.md <<'EOF'
<!-- bootstrap-content-version: x/best@v1:abc123def456 -->

# BEST_PRACTICES

## Workflow

old content

## Other

untouched
EOF
  cat > "$PLUGIN_ROOT/templates/best.tpl" <<'EOF'
## Workflow

new content

EOF
  items_json='[{
    "classification": "fast_forward",
    "strategy": "owned-regions",
    "target": "docs/BEST.md",
    "recorded_sha": "abc123def456",
    "plugin_sha": "fff999fff999",
    "upstream_key": "x/best@v1",
    "source": "templates/best.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [{"type":"heading","heading":"## Workflow"}],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "applied"
  # New owned region content present.
  grep -Fq "new content" docs/BEST.md || fail "expected new content under ## Workflow"
  # Non-owned content preserved.
  grep -Fq "untouched" docs/BEST.md || fail "expected untouched content to remain"
  # Marker present once.
  marker_count="$(grep -c 'bootstrap-content-version' docs/BEST.md || true)"
  assert_equal "$marker_count" "1"
}

@test "fast_forward .gitignore replaces tagged block" {
  cat > .gitignore <<'EOF'
# bootstrap-content-version: x/.gitignore@v1:abc123def456

# bytewyrd:base
.worktrees/
.claude/settings.local.json

# user-owned section
build/
EOF
  cat > "$PLUGIN_ROOT/templates/.gitignore.tpl" <<'EOF'
# bytewyrd:base
.worktrees/
.claude/settings.local.json
.bytewyrd/*

EOF
  items_json='[{
    "classification": "fast_forward",
    "strategy": "structured",
    "target": ".gitignore",
    "recorded_sha": "abc123def456",
    "plugin_sha": "fff999fff999",
    "upstream_key": "x/.gitignore@v1",
    "source": "templates/.gitignore.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": ["bytewyrd:base"],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "applied"
  # New plugin block applied (the new line `.bytewyrd/*` is present).
  grep -Fq ".bytewyrd/*" .gitignore || fail "expected new .bytewyrd/* line from plugin block"
  # User-owned section preserved.
  grep -Fq "build/" .gitignore || fail "expected user-owned build/ to remain"
}

@test "missing plugin source produces per-item error, not script failure" {
  items_json='[{
    "classification": "authoritative_add",
    "strategy": "authoritative",
    "target": "docs/rfc-process.md",
    "recorded_sha": null,
    "plugin_sha": "abc123def456",
    "upstream_key": "x/docs/rfc-process.md@v1",
    "source": "does-not-exist.md",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash "$SCRIPT" "$items_json" "$PLUGIN_ROOT" inputs.json
  assert_success
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "error"
  err_field="$(echo "$output" | jq -r '.[0].error | length > 0')"
  assert_equal "$err_field" "true"
}

@test "reads items from stdin when first argument is -" {
  cat > "$PLUGIN_ROOT/templates/README.md.tpl" <<'EOF'
# Stdin test
EOF
  items_json='[{
    "classification": "bootstrap_create",
    "strategy": "bootstrap",
    "target": "README.md",
    "recorded_sha": null,
    "plugin_sha": null,
    "upstream_key": "x/README.md@v1",
    "source": "templates/README.md.tpl",
    "templated": false,
    "template_inputs": [],
    "owned_paths": [],
    "owned_boundaries": [],
    "owned_sections": []
  }]'
  run bash -c "printf '%s' '$items_json' | bash \"$SCRIPT\" - \"$PLUGIN_ROOT\" inputs.json"
  assert_success
  [ -f README.md ] || fail "expected README.md to be created"
  result_val="$(echo "$output" | jq -r '.[0].result')"
  assert_equal "$result_val" "applied"
}
