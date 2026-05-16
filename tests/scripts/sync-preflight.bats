#!/usr/bin/env bats
# Tests for scripts/sync-preflight.sh
#
# The preflight script must run inside a git repository. Each test sets up an
# isolated git repo under TEST_TMPDIR (via the shared setup_common helper),
# initializes it, and runs the script with that directory as the working
# directory.
#
# `HOME` is also redirected to a fresh location under TEST_TMPDIR so the
# installed_plugins.json and docs-agent.md detection works against fixtures,
# not the developer's real ~/.claude.

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-preflight.sh"

  # Initialize an empty git repo. The TEST_TMPDIR is the CWD per setup_common.
  git init -q .
  # Required so commits do not fail under CI; values are irrelevant to the
  # tests because we only read git config user.name (which we explicitly set
  # per-test as needed).
  git config user.email "test@example.com"
  git config user.name "Test User"
  git config commit.gpgsign false
  git commit --allow-empty -q -m "init"

  # Redirect HOME so the installed-plugins probe does not see the real user's
  # plugin registry. Tests that need a registry create one under FAKE_HOME.
  FAKE_HOME="$TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME"
  export HOME="$FAKE_HOME"

  # Clear CLAUDE_PLUGIN_ROOT — its default would otherwise point at the real
  # plugin checkout.
  unset CLAUDE_PLUGIN_ROOT
}

teardown() {
  teardown_common
}

# --- Hard checks ------------------------------------------------------------

@test "missing-git path exits 1 with plain-text error" {
  # Force git off PATH by giving the script a stripped PATH that only contains
  # /usr/bin (which has jq, sha256sum, python3 on most modern Linux), but no
  # git. We add the test sandbox via /usr/bin only to keep core tools.
  # Skip if /usr/bin/git itself exists; on those systems, removing /usr/bin
  # would also remove jq.
  if [ -x /usr/bin/git ]; then
    skip "system /usr/bin/git always reachable; cannot simulate missing-git here without breaking jq"
  fi
  run env PATH="/usr/bin" bash "$SCRIPT"
  assert_failure 1
  # Plain text on stderr (NOT JSON), per the script contract.
  [[ "$output" == *"/sync requires git"* ]] || fail "Expected 'git required' message, got: $output"
}

@test "not in a git repo exits 1" {
  rm -rf .git
  run bash "$SCRIPT"
  assert_failure 1
  [[ "$output" == *"git repository"* ]] || fail "Expected git-repo error, got: $output"
}

# --- Happy path -------------------------------------------------------------

@test "happy path emits expected JSON shape" {
  # No content beyond the initial empty commit — has_substantial_content = false.
  run bash "$SCRIPT"
  assert_success
  # Verify each documented field is present and the right type.
  assert_equal "$(echo "$output" | jq -r 'has("repo_root")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("git_user")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("project_slug")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("has_substantial_content")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("github_remote")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("github_description")')" "true"
  assert_equal "$(echo "$output" | jq -r '.installed_plugins | type')" "array"
  assert_equal "$(echo "$output" | jq -r '.missing_critical | type')" "array"
  assert_equal "$(echo "$output" | jq -r '.missing_recommended | type')" "array"
  assert_equal "$(echo "$output" | jq -r '.has_substantial_content | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.docs_agent_drifted | type')" "boolean"
}

@test "project_slug equals basename of repo_root" {
  run bash "$SCRIPT"
  assert_success
  slug="$(echo "$output" | jq -r .project_slug)"
  root="$(echo "$output" | jq -r .repo_root)"
  assert_equal "$slug" "$(basename "$root")"
}

@test "has_substantial_content false on empty repo" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_substantial_content)" "false"
}

@test "has_substantial_content false with only README and LICENSE" {
  printf '# title\n' > README.md
  printf 'MIT\n' > LICENSE
  git add README.md LICENSE
  git commit -q -m "docs"
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_substantial_content)" "false"
}

@test "has_substantial_content true once a non-doc file is committed" {
  printf 'use std;\n' > src.rs
  git add src.rs
  git commit -q -m "src"
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_substantial_content)" "true"
}

# --- Plugin set / missing-set arithmetic ------------------------------------

@test "installed_plugins is [] when registry is absent" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -c .installed_plugins)" "[]"
}

@test "missing_critical lists github when registry is empty" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -c .missing_critical)" '["github@claude-plugins-official"]'
}

@test "missing_critical is [] when github plugin is installed" {
  mkdir -p "$FAKE_HOME/.claude/plugins"
  cat > "$FAKE_HOME/.claude/plugins/installed_plugins.json" <<'EOF'
{"plugins": {"github@claude-plugins-official": {"version": "1.0.0"}}}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -c .missing_critical)" "[]"
}

@test "missing_recommended lists both when registry is empty" {
  run bash "$SCRIPT"
  assert_success
  rec="$(echo "$output" | jq -c .missing_recommended | tr -d ' ')"
  [[ "$rec" == *"context7@claude-plugins-official"* ]] || fail "context7 missing: $rec"
  [[ "$rec" == *"code-review@claude-plugins-official"* ]] || fail "code-review missing: $rec"
}

# --- docs-agent drift -------------------------------------------------------

@test "docs_agent_drifted is false when no plugin marker exists" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .docs_agent_drifted)" "false"
}

@test "docs_agent_drifted is true when plugin has a marker and project does not" {
  mkdir -p "$FAKE_HOME/.claude/agents"
  cat > "$FAKE_HOME/.claude/agents/docs-agent.md" <<'EOF'
---
docs-agent-version: 2026-05-10-initial
---
body
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_docs_ver)" "2026-05-10-initial"
  assert_equal "$(echo "$output" | jq -r .project_docs_ver)" ""
  assert_equal "$(echo "$output" | jq -r .docs_agent_drifted)" "true"
  # Side effect: .bytewyrd/docs-agent-version was written.
  assert [ -f .bytewyrd/docs-agent-version ]
  assert_equal "$(cat .bytewyrd/docs-agent-version)" "2026-05-10-initial"
}

@test "docs_agent_drifted is false when plugin and project markers match" {
  mkdir -p "$FAKE_HOME/.claude/agents" .bytewyrd
  cat > "$FAKE_HOME/.claude/agents/docs-agent.md" <<'EOF'
docs-agent-version: 2026-05-10-initial
EOF
  printf '2026-05-10-initial\n' > .bytewyrd/docs-agent-version
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .docs_agent_drifted)" "false"
}

@test "docs_agent_drifted is true when versions differ" {
  mkdir -p "$FAKE_HOME/.claude/agents" .bytewyrd
  cat > "$FAKE_HOME/.claude/agents/docs-agent.md" <<'EOF'
docs-agent-version: 2026-06-01-newer
EOF
  printf '2026-05-10-initial\n' > .bytewyrd/docs-agent-version
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_docs_ver)" "2026-06-01-newer"
  assert_equal "$(echo "$output" | jq -r .project_docs_ver)" "2026-05-10-initial"
  assert_equal "$(echo "$output" | jq -r .docs_agent_drifted)" "true"
  # The side-effect write updated the project marker to the plugin's version.
  assert_equal "$(cat .bytewyrd/docs-agent-version)" "2026-06-01-newer"
}

# --- Remote / description ---------------------------------------------------

@test "github_remote is empty when no origin remote" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .github_remote)" ""
}

@test "github_remote is empty when origin is non-github" {
  git remote add origin https://gitlab.com/foo/bar.git
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .github_remote)" ""
}

@test "github_remote is set when origin points at github" {
  git remote add origin git@github.com:foo/bar.git
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .github_remote)" "git@github.com:foo/bar.git"
}
