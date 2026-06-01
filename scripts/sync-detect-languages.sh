#!/usr/bin/env bash
# Detect language manifests and component roots in the current directory.
# Used by: skills/sync/SKILL.md (Step 3 — component-structure detection).
#
# This script is a thin wrapper around `detect_languages` in
# scripts/_lib/detect-languages.bash — that function holds the authoritative
# detection logic and is also called directly from sync-preflight.sh.
#
# Args: none. Must be run from `repo_root` (returned by sync-preflight.sh).
#
# Behavior:
#   For each language, scans for the canonical manifest file:
#     - Rust:    Cargo.toml (excluding target/)
#     - JS/TS:   package.json (excluding node_modules/)
#     - Go:      go.mod
#     - Python:  pyproject.toml, setup.py
#   For each detected manifest, emits one entry to `component_roots`. For
#   Rust workspaces (Cargo.toml with [workspace]), uses python3 + tomllib to
#   read the members array and emits one entry per workspace member.
#
#   Stack-detection flags signal which best-practice sections should be
#   appended to docs/BEST_PRACTICES.md in Step 5 of /sync. They are
#   independent of component_roots — a project can have has_svelte=true
#   without an explicit Svelte component root.
#
# Output:
#   stdout: a single JSON object on success.
#     {
#       "languages":         ["rust", "js", "go", "python"],
#       "component_roots":   [{"language": "...", "path": "...", "name": "..."}, ...],
#       "has_rust":          <bool>,
#       "has_js":            <bool>,
#       "has_go":            <bool>,
#       "has_python":        <bool>,
#       "has_svelte":        <bool>,
#       "has_ruby":          <bool>,
#       "has_rails":         <bool>,
#       "has_k8s_cue":       <bool>,
#       "has_terraform":     <bool>
#     }
#   stderr: empty on success; JSON error envelope on failure.
#
# Exit codes:
#   0  Detection succeeded.
#   2  Missing required tool (jq). The success path tolerates missing python3
#      by treating a Cargo workspace as standalone — only a hard jq failure
#      surfaces here.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
# shellcheck source=_lib/detect-languages.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/detect-languages.bash"
require_jq

detect_languages

jq -n \
  --argjson languages "$DL_LANGUAGES" \
  --argjson component_roots "$DL_COMPONENT_ROOTS" \
  --argjson has_rust "$DL_HAS_RUST" \
  --argjson has_js "$DL_HAS_JS" \
  --argjson has_go "$DL_HAS_GO" \
  --argjson has_python "$DL_HAS_PYTHON" \
  --argjson has_svelte "$DL_HAS_SVELTE" \
  --argjson has_ruby "$DL_HAS_RUBY" \
  --argjson has_rails "$DL_HAS_RAILS" \
  --argjson has_k8s_cue "$DL_HAS_K8S_CUE" \
  --argjson has_terraform "$DL_HAS_TERRAFORM" \
  '{
    languages: $languages,
    component_roots: $component_roots,
    has_rust: $has_rust,
    has_js: $has_js,
    has_go: $has_go,
    has_python: $has_python,
    has_svelte: $has_svelte,
    has_ruby: $has_ruby,
    has_rails: $has_rails,
    has_k8s_cue: $has_k8s_cue,
    has_terraform: $has_terraform
  }'

exit 0
