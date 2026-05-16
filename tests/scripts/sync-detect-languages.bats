#!/usr/bin/env bats
# Tests for scripts/sync-detect-languages.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/sync-detect-languages.sh"
}

teardown() {
  teardown_common
}

# --- Empty repo -------------------------------------------------------------

@test "empty repo — no languages detected" {
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

# --- Rust -------------------------------------------------------------------

@test "standalone Cargo.toml emits one rust component" {
  cat > Cargo.toml <<'EOF'
[package]
name = "my-crate"
version = "0.1.0"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_rust)" "true"
  assert_equal "$(echo "$output" | jq -c .languages)" '["rust"]'
  assert_equal "$(echo "$output" | jq -r '.component_roots | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].language')" "rust"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].path')" "."
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "my-crate"
}

@test "Cargo workspace expands to multiple components" {
  cat > Cargo.toml <<'EOF'
[workspace]
members = ["crates/foo", "crates/bar"]
resolver = "2"
EOF
  mkdir -p crates/foo crates/bar
  cat > crates/foo/Cargo.toml <<'EOF'
[package]
name = "foo"
version = "0.1.0"
EOF
  cat > crates/bar/Cargo.toml <<'EOF'
[package]
name = "custom-bar"
version = "0.1.0"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.component_roots | length')" "2"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "foo"
  assert_equal "$(echo "$output" | jq -r '.component_roots[1].name')" "custom-bar"
}

@test "target/ excluded from Rust scan" {
  cat > Cargo.toml <<'EOF'
[package]
name = "x"
version = "0.1.0"
EOF
  mkdir -p target/debug
  # A nested Cargo.toml under target/ should be ignored.
  cat > target/debug/Cargo.toml <<'EOF'
[package]
name = "build-artifact"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.component_roots | length')" "1"
}

# --- JS / TS ----------------------------------------------------------------

@test "package.json emits one js component with name from JSON" {
  cat > package.json <<'EOF'
{"name": "my-app", "version": "0.1.0"}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_js)" "true"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].language')" "js"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "my-app"
}

@test "package.json without name falls back to dirname" {
  mkdir -p frontend
  cat > frontend/package.json <<'EOF'
{"version": "0.1.0"}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].path')" "./frontend"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "frontend"
}

@test "node_modules/ excluded from JS scan" {
  cat > package.json <<'EOF'
{"name": "root"}
EOF
  mkdir -p node_modules/foo
  cat > node_modules/foo/package.json <<'EOF'
{"name": "foo"}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r '.component_roots | length')" "1"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].name')" "root"
}

# --- Svelte detection -------------------------------------------------------

@test "has_svelte true when *.svelte file exists" {
  mkdir -p src
  printf '<script>let x = 1;</script>\n' > src/App.svelte
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_svelte)" "true"
}

@test "has_svelte true when svelte is in package.json dependencies" {
  cat > package.json <<'EOF'
{"name": "x", "dependencies": {"svelte": "^4.0.0"}}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_svelte)" "true"
}

@test "has_svelte true when svelte is in devDependencies" {
  cat > package.json <<'EOF'
{"name": "x", "devDependencies": {"svelte": "^4.0.0"}}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_svelte)" "true"
}

# --- Go / Python / Ruby / Rails / Terraform ---------------------------------

@test "go.mod sets has_go and emits a go component" {
  printf 'module example.com/me\n\ngo 1.22\n' > go.mod
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_go)" "true"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].language')" "go"
}

@test "pyproject.toml sets has_python and emits a python component" {
  cat > pyproject.toml <<'EOF'
[project]
name = "x"
version = "0.1.0"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_python)" "true"
  assert_equal "$(echo "$output" | jq -r '.component_roots[0].language')" "python"
}

@test "Gemfile sets has_ruby" {
  printf 'source "https://rubygems.org"\n' > Gemfile
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_ruby)" "true"
  assert_equal "$(echo "$output" | jq -r .has_rails)" "false"
}

@test "has_rails true when config/application.rb exists" {
  mkdir -p config
  printf '# rails app\n' > config/application.rb
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_rails)" "true"
}

@test "has_rails true when rails gem in Gemfile" {
  cat > Gemfile <<'EOF'
source "https://rubygems.org"
gem "rails", "~> 7.1"
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_rails)" "true"
}

@test "has_terraform true when *.tf file exists" {
  printf 'resource "aws_s3_bucket" "x" {}\n' > main.tf
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_terraform)" "true"
}

@test "has_terraform true when terragrunt.hcl exists" {
  printf 'remote_state {}\n' > terragrunt.hcl
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_terraform)" "true"
}

@test "has_k8s_cue true when *.cue under k8s/" {
  mkdir -p k8s
  printf 'package main\n' > k8s/app.cue
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .has_k8s_cue)" "true"
}

# --- Combined detection -----------------------------------------------------

@test "rust + js together — languages list ordered" {
  cat > Cargo.toml <<'EOF'
[package]
name = "x"
version = "0.1.0"
EOF
  cat > package.json <<'EOF'
{"name": "y"}
EOF
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -c .languages)" '["rust","js"]'
}
