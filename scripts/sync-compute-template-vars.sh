#!/usr/bin/env bash
# Compute derived scalar template variables from project inputs.
# Adds `enabled_plugins_entries` and `pre_tool_use_hook` string keys so
# sync-render-template.sh can substitute them via its Pass 2 scalar loop.
# Without these keys the settings.json.tpl render produces invalid JSON.
#
# Args:
#   $1  Required. Path to project_inputs.json.
#
# Output:
#   stdout: enriched JSON (original keys + two new string keys).
#   stderr: error message if file cannot be read.
#
# Exit codes:
#   0  Success.
#   1  Missing or unreadable project_inputs file.

set -uo pipefail

if [ "${1:-}" = "" ] || [ ! -f "$1" ]; then
  printf 'sync-compute-template-vars: missing or unreadable project_inputs: %s\n' "${1:-<none>}" >&2
  exit 1
fi
inputs="$1"

# --- enabled_plugins_entries ---
# Expands to the body of the enabledPlugins object:
#   \n    "id1": true,
#   \n    "id2": true
# (leading newline, no trailing comma on last entry, empty string if no plugins)
#
# The leading \n is intentional: the template has `"enabledPlugins": {<VAR>` on
# one line, so the newline opens the next indented line.
enabled_plugins_entries="$(jq -r '
  .installed_plugins // [] |
  if length == 0 then ""
  else
    length as $n |
    to_entries |
    map(
      "\n    \"" + .value + "\": true" +
      if .key < $n - 1 then "," else "" end
    ) |
    join("")
  end
' "$inputs")"

# --- pre_tool_use_hook ---
# Expands to `,\n    "PreToolUse": [...]` when quality-gate languages are
# detected, or empty string to omit the hook.
#
# The template has `]<PRE_TOOL_USE_HOOK>` at the end of the Stop array, so an
# empty string leaves `]` and a non-empty value appends the PreToolUse block:
#   ],
#   "PreToolUse": [...]
pre_tool_use_hook="$(jq -r '
  [
    if .has_rust   // false then "cargo fmt --all --check && cargo clippy --workspace --locked -- -D warnings && cargo test --workspace --locked" else empty end,
    if .has_js     // false then "bun run typecheck && bun run lint && bun test" else empty end,
    if .has_go     // false then "gofmt -l . | grep . && exit 1 || true && go vet ./... && go test ./..." else empty end,
    if .has_python // false then "uv run ruff check . && uv run mypy . && uv run pytest" else empty end
  ] |
  if length == 0 then ""
  else
    join(" && ") |
    ",\n    \"PreToolUse\": [\n      {\n        \"matcher\": \"Bash\",\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"" + . + "\"\n          }\n        ]\n      }\n    ]"
  end
' "$inputs")"

# Output the enriched JSON.
jq \
  --arg epe  "$enabled_plugins_entries" \
  --arg ptuh "$pre_tool_use_hook" \
  '. + {enabled_plugins_entries: $epe, pre_tool_use_hook: $ptuh}' \
  "$inputs"
