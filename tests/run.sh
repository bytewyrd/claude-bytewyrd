#!/usr/bin/env bash
# Run the script test suite.
# Usage:
#   ./tests/run.sh                           — run all tests
#   ./tests/run.sh tests/scripts/rfc-resolve.bats   — single file
#   ./tests/run.sh tests/scripts/rfc-*.bats         — glob
#   ./tests/run.sh tests/scripts/            — folder
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="$SCRIPT_DIR/bats-core/bin/bats"

if [ $# -eq 0 ]; then
  exec "$BATS" "$SCRIPT_DIR/scripts/"
fi

exec "$BATS" "$@"
