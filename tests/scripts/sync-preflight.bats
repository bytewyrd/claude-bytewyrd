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

  # Plugin-root resolution is now part of preflight (sourced from
  # scripts/_lib/plugin.bash). Provide a default fake plugin manifest under
  # FAKE_HOME so the script can locate it via the "home" branch. Tests that
  # specifically exercise the missing-plugin-root case clear this fixture
  # themselves via `rm -rf "$FAKE_HOME/.claude"`.
  mkdir -p "$FAKE_HOME/.claude"
  printf '{"artifacts":[]}\n' > "$FAKE_HOME/.claude/bootstrap-manifest.json"
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

# --- python3 >= 3.11 gate (tomllib is stdlib only from 3.11) -----------------

# Write a fake `python3` onto PATH that reports the given version, so the
# preflight version gate can be exercised without a second interpreter.
_fake_python3() {
  local ver="$1" ge311="$2"   # ge311: "0" (satisfies >=3.11) or "1" (does not)
  local fakebin="$TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/python3" <<PYEOF
#!/usr/bin/env bash
case "\$*" in
  *"version_info >= (3, 11)"*) exit $ge311 ;;
  *"sys.version_info[:3]"*) echo "$ver"; exit 0 ;;
  *) exit 0 ;;
esac
PYEOF
  chmod +x "$fakebin/python3"
  printf '%s' "$fakebin"
}

@test "python3 3.9 is rejected by the version gate" {
  fakebin="$(_fake_python3 "3.9.18" 1)"
  run env PATH="$fakebin:$PATH" bash "$SCRIPT"
  assert_failure 1
  [[ "$output" == *"python3 >= 3.11"* ]] || fail "expected 3.11 requirement message, got: $output"
  [[ "$output" == *"3.9.18"* ]] || fail "expected the found version in the message, got: $output"
}

@test "python3 3.10 is rejected by the version gate" {
  fakebin="$(_fake_python3 "3.10.12" 1)"
  run env PATH="$fakebin:$PATH" bash "$SCRIPT"
  assert_failure 1
  [[ "$output" == *"python3 >= 3.11"* ]] || fail "expected 3.11 requirement message, got: $output"
}

@test "python3 3.11 is accepted by the version gate" {
  fakebin="$(_fake_python3 "3.11.0" 0)"
  run env PATH="$fakebin:$PATH" bash "$SCRIPT"
  assert_success
}

@test "python3 4.0 is accepted by the version gate" {
  fakebin="$(_fake_python3 "4.0.1" 0)"
  run env PATH="$fakebin:$PATH" bash "$SCRIPT"
  assert_success
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
  # New fields introduced by preflight consolidation:
  assert_equal "$(echo "$output" | jq -r 'has("plugin_root")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("plugin_version")')" "true"
  assert_equal "$(echo "$output" | jq -r '.plugin_version | type')" "string"
  assert_equal "$(echo "$output" | jq -r 'has("sidecar_migrated")')" "true"
  assert_equal "$(echo "$output" | jq -r 'has("sidecar_message")')" "true"
  assert_equal "$(echo "$output" | jq -r '.sidecar_migrated | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.languages | type')" "array"
  assert_equal "$(echo "$output" | jq -r '.component_roots | type')" "array"
  assert_equal "$(echo "$output" | jq -r '.has_rust | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_js | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_go | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_python | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_svelte | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_ruby | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_rails | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_k8s_cue | type')" "boolean"
  assert_equal "$(echo "$output" | jq -r '.has_terraform | type')" "boolean"
}

@test "project_slug equals basename of repo_root" {
  run bash "$SCRIPT"
  assert_success
  slug="$(echo "$output" | jq -r .project_slug)"
  root="$(echo "$output" | jq -r .repo_root)"
  assert_equal "$slug" "$(basename "$root")"
}

@test "project_slug resolves to the main repo name when run inside a worktree" {
  # Regression guard: when /sync runs inside a git worktree,
  # `git rev-parse --show-toplevel` returns the worktree dir, so deriving the
  # slug from it would name the project after the worktree (e.g. a branch dir)
  # instead of the real repository. project_slug must be derived from the shared
  # git-common-dir (the main repo), while repo_root stays the worktree (the write
  # target).
  local main_slug worktree_dir
  main_slug="$(basename "$TEST_TMPDIR")"
  worktree_dir="$TEST_TMPDIR/wt-feature-branch"

  git worktree add -q "$worktree_dir" -b wt-feature-branch >/dev/null 2>&1
  cd "$worktree_dir"

  run bash "$SCRIPT"
  assert_success
  slug="$(echo "$output" | jq -r .project_slug)"
  root="$(echo "$output" | jq -r .repo_root)"

  # slug is the MAIN repo's basename, NOT the worktree directory name.
  assert_equal "$slug" "$main_slug"
  refute [ "$slug" = "wt-feature-branch" ]
  # repo_root stays the worktree — writes must land in the current checkout.
  assert_equal "$(basename "$root")" "wt-feature-branch"
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

# --- Plugin root -----------------------------------------------------------

@test "plugin_root present in output (home fallback fixture)" {
  # The default setup() creates a fake plugin manifest under FAKE_HOME/.claude.
  # The home branch of find_plugin_root should resolve to that.
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .plugin_root)" "$FAKE_HOME/.claude"
}

@test "plugin_root resolves from CLAUDE_PLUGIN_ROOT when set" {
  # Build a separate plugin checkout fixture.
  mkdir -p "$TEST_TMPDIR/checkout"
  printf '{"artifacts":[]}\n' > "$TEST_TMPDIR/checkout/bootstrap-manifest.json"
  run env CLAUDE_PLUGIN_ROOT="$TEST_TMPDIR/checkout" bash "$SCRIPT"
  assert_success
  pr="$(echo "$output" | jq -r .plugin_root)"
  assert_equal "$pr" "$TEST_TMPDIR/checkout"
  # Sanity: non-empty.
  [ -n "$pr" ] || fail "plugin_root should be non-empty"
}

@test "missing plugin root → exit 1 with error envelope" {
  # Remove the default home fixture so no manifest can be located.
  rm -rf "$FAKE_HOME/.claude"
  run bash "$SCRIPT"
  assert_failure 1
  # Error is a JSON envelope on stderr; the assertion below verifies that the
  # output (which `run` captures from both stdout and stderr) parses as JSON
  # with an `.error` key.
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

# --- Sidecar migration -----------------------------------------------------

@test "sidecar_migrated true when legacy sidecar exists and new path is absent" {
  mkdir -p .claude
  printf '{"k":"v"}' > .claude/.bootstrap-versions.json
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .sidecar_migrated)" "true"
  # Message is non-empty (human-readable migration result).
  msg="$(echo "$output" | jq -r .sidecar_message)"
  [ -n "$msg" ] || fail "sidecar_message should be non-empty after migration"
  # File moved: old path removed, new path present with the same content.
  refute [ -f .claude/.bootstrap-versions.json ]
  assert [ -f .bytewyrd/.bootstrap-versions.json ]
  assert_equal "$(cat .bytewyrd/.bootstrap-versions.json)" '{"k":"v"}'
}

@test "sidecar_migrated false when nothing to migrate" {
  # No old sidecar — no-op migration.
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .sidecar_migrated)" "false"
  refute [ -f .bytewyrd/.bootstrap-versions.json ]
}

@test "sidecar_migrated false when both old and new exist" {
  mkdir -p .claude .bytewyrd
  printf '{"old":1}' > .claude/.bootstrap-versions.json
  printf '{"new":1}' > .bytewyrd/.bootstrap-versions.json
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .sidecar_migrated)" "false"
  # Both files preserved untouched.
  assert_equal "$(cat .claude/.bootstrap-versions.json)" '{"old":1}'
  assert_equal "$(cat .bytewyrd/.bootstrap-versions.json)" '{"new":1}'
}

# --- Language detection ----------------------------------------------------

@test "language detection: Cargo.toml sets has_rust and listed in languages" {
  cat > Cargo.toml <<'EOF'
[package]
name = "my-crate"
version = "0.1.0"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_rust)" "true"
  assert_equal "$(echo "$output" | jq -c .languages)" '["rust"]'
  # component_roots has at least one rust entry.
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].language')" "rust"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "my-crate"
}

@test "language detection: bare repo → empty arrays and false flags" {
  # No manifest files in the repo; only the empty git commit exists.
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -c .languages)" "[]"
  assert_equal "$(echo "$output" | jq -c .component_roots)" "[]"
  assert_equal "$(echo "$output" | jq -r .has_rust)" "false"
  assert_equal "$(echo "$output" | jq -r .has_js)" "false"
  assert_equal "$(echo "$output" | jq -r .has_go)" "false"
  assert_equal "$(echo "$output" | jq -r .has_python)" "false"
  assert_equal "$(echo "$output" | jq -r .has_svelte)" "false"
  assert_equal "$(echo "$output" | jq -r .has_ruby)" "false"
  assert_equal "$(echo "$output" | jq -r .has_rails)" "false"
  assert_equal "$(echo "$output" | jq -r .has_k8s_cue)" "false"
  assert_equal "$(echo "$output" | jq -r .has_terraform)" "false"
}
