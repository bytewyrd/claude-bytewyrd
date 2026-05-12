#!/usr/bin/env bash
# Pre-commit hook: fail if bootstrap-manifest.json is stale.
set -euo pipefail
"$(git rev-parse --show-toplevel)/.claude-plugin/scripts/build-manifest.sh" --check
