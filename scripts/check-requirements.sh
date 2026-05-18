#!/usr/bin/env bash
# Bytewyrd plugin: per-session requirement check.
# Probes installed plugins, MCP servers, and tool availability.
# Emits a JSON hook response per
# https://docs.claude.com/en/docs/claude-code/hooks#hook-output

set -u

# --- Configuration ----------------------------------------------------------

# Required companion plugins (enable-state probed in user + project settings).
REQUIRED_PLUGINS=(
  "github@claude-plugins-official"
  "context7@claude-plugins-official"
  "code-review@claude-plugins-official"
)

# Required MCP tool prefixes. Presence is inferred from settings files that
# declare permissions for these tools (we cannot probe the live tool list from
# inside a hook). If any "allow" entry under any settings file matches one of
# these prefixes, the MCP server is considered configured.
REQUIRED_MCP_PREFIXES=(
  "mcp__exa__"
  "mcp__firefox-devtools__"
)

# Comma-separated list of requirement IDs to skip from warning output, read
# from the environment. Hard failures cannot be skipped.
BYTEWYRD_SKIP_WARN="${BYTEWYRD_SKIP_WARN:-}"

# --- Helpers ----------------------------------------------------------------

# emit_json <continue:bool> <suppressOutput:bool> <systemMessage:string> <additionalContext:string>
emit_json() {
  local cont="$1" suppress="$2" sys_msg="$3" ctx="$4"
  # Escape backslashes and double-quotes for JSON-safe embedding.
  sys_msg="${sys_msg//\\/\\\\}"; sys_msg="${sys_msg//\"/\\\"}"; sys_msg="${sys_msg//$'\n'/\\n}"
  ctx="${ctx//\\/\\\\}"; ctx="${ctx//\"/\\\"}"; ctx="${ctx//$'\n'/\\n}"
  printf '{"continue":%s,"suppressOutput":%s,"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$cont" "$suppress" "$sys_msg" "$ctx"
}

# is_skipped <requirement_id>: returns 0 if the requirement ID is in the
# BYTEWYRD_SKIP_WARN comma-separated list.
is_skipped() {
  local id="$1"
  case ",${BYTEWYRD_SKIP_WARN}," in
    *",${id},"*) return 0 ;;
    *) return 1 ;;
  esac
}

# plugin_enabled <plugin@marketplace>: returns 0 if enabled in either user or
# project settings, 1 otherwise. Project settings take precedence.
plugin_enabled() {
  local id="$1"
  local user_settings="$HOME/.claude/settings.json"
  local proj_settings="$CLAUDE_PROJECT_DIR/.claude/settings.json"
  # We use grep rather than jq because jq is not guaranteed on PATH; the
  # check is a simple string match against the canonical JSON encoding.
  # Project setting (precedence): explicit true/false.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$proj_settings"; then return 0; fi
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*false" "$proj_settings"; then return 1; fi
  # Fall back to user setting.
  if [ -f "$user_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$user_settings"; then return 0; fi
  return 1
}

# plugin_installed <plugin@marketplace>: returns 0 if the plugin appears in
# the installed_plugins.json registry (any scope), 1 otherwise.
plugin_installed() {
  local id="$1"
  local registry="$HOME/.claude/plugins/installed_plugins.json"
  [ -f "$registry" ] && grep -q "\"$id\"" "$registry"
}

# mcp_configured <prefix>: returns 0 if any of the settings files contains
# an "allow" permission with the given tool prefix, 1 otherwise. Strict
# proxy for "this MCP server is reachable in this session."
mcp_configured() {
  local prefix="$1"
  for f in \
    "$HOME/.claude/settings.json" \
    "$CLAUDE_PROJECT_DIR/.claude/settings.json" \
    "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    if grep -q "\"${prefix}" "$f"; then return 0; fi
  done
  return 1
}

# --- Probes -----------------------------------------------------------------

warnings=()
failures=()

# Hard requirement: git on PATH.
if ! command -v git >/dev/null 2>&1; then
  failures+=("[fail] git is not on PATH. Fix: install git (https://git-scm.com/downloads).")
fi

# Hard requirement: CLAUDE_PROJECT_DIR set (we use it to probe project settings).
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  # Not fatal — fall back to PWD.
  CLAUDE_PROJECT_DIR="${PWD}"
fi

# Hard failure: project's .claude/settings.json references a plugin that
# isn't installed in installed_plugins.json. Claude Code itself errors at
# startup when this happens (per the existing /sync skill comment around
# line 968 of skills/sync/SKILL.md).
proj_settings="$CLAUDE_PROJECT_DIR/.claude/settings.json"
if [ -f "$proj_settings" ]; then
  while IFS= read -r enabled_id; do
    # enabled_id is a line like:   "github@claude-plugins-official": true,
    id="$(printf '%s' "$enabled_id" | sed -E 's/^[[:space:]]*"([^"]+)"[[:space:]]*:.*$/\1/')"
    [ -z "$id" ] && continue
    # Only check claude-plugins-official entries — third-party marketplaces
    # may legitimately have their own install/enable mechanisms.
    case "$id" in
      *@claude-plugins-official)
        if ! plugin_installed "$id"; then
          failures+=("[fail] .claude/settings.json references \"$id\" but it is not installed. Fix: claude plugin install $id  OR remove the entry from .claude/settings.json's enabledPlugins block.")
        fi
        ;;
    esac
  done < <(awk '/"enabledPlugins"/,/^[[:space:]]*}/' "$proj_settings" | grep -E '^[[:space:]]*"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*(true|false)')
fi

# Soft requirements: companion plugins enabled.
for id in "${REQUIRED_PLUGINS[@]}"; do
  short="$(printf '%s' "$id" | sed -E 's/@.*//')"
  is_skipped "$short" && continue
  if ! plugin_enabled "$id"; then
    warnings+=("[warn] $id not enabled. Fix: claude plugin install $id")
  fi
done

# Soft requirements: MCP servers reachable via configured tool permissions.
for prefix in "${REQUIRED_MCP_PREFIXES[@]}"; do
  short="$(printf '%s' "$prefix" | sed -E 's/^mcp__//; s/__$//')"
  is_skipped "$short" && continue
  if ! mcp_configured "$prefix"; then
    case "$prefix" in
      "mcp__exa__")
        warnings+=("[warn] Exa MCP server not configured (no \"${prefix}\" permissions found). Fix: add an entry under \"mcpServers\" to ~/.claude.json or .mcp.json. See https://docs.exa.ai/reference/mcp.")
        ;;
      "mcp__firefox-devtools__")
        warnings+=("[warn] Firefox MCP server not configured (no \"${prefix}\" permissions found). Fix: install Firefox MCP. See https://github.com/mozilla/firefox-mcp.")
        ;;
      *)
        warnings+=("[warn] MCP server \"$prefix\" not configured. Fix: add the matching entry under \"mcpServers\".")
        ;;
    esac
  fi
done

# Soft requirement: gh CLI on PATH (used by /sync metadata pre-fill; not critical).
if ! is_skipped "gh-cli" && ! command -v gh >/dev/null 2>&1; then
  warnings+=("[warn] gh CLI not on PATH. Fix: install gh (https://cli.github.com). Used by /sync to read GitHub repo metadata; non-critical.")
fi

# --- Output -----------------------------------------------------------------

# Silent path: no warnings, no failures.
if [ "${#warnings[@]}" -eq 0 ] && [ "${#failures[@]}" -eq 0 ]; then
  emit_json true true "" ""
  exit 0
fi

# Failure path: print failure bundle to stderr and exit 2 (blocking).
if [ "${#failures[@]}" -gt 0 ]; then
  {
    echo "Bytewyrd plugin: requirement check FAILED."
    printf '%s\n' "${failures[@]}"
    if [ "${#warnings[@]}" -gt 0 ]; then
      echo "Also warnings (review after fixing failures):"
      printf '%s\n' "${warnings[@]}"
    fi
  } >&2
  exit 2
fi

# Warning path: print warning bundle, inject one-line summary into context,
# exit 0.
warning_count="${#warnings[@]}"
sys_msg="Bytewyrd plugin: $warning_count requirement(s) missing.
$(printf '%s\n' "${warnings[@]}")
Suppress individual warnings with BYTEWYRD_SKIP_WARN=<id1>,<id2>."
warning_bundle="$(printf '%s\n' "${warnings[@]}")"
ctx="Bytewyrd plugin warnings active: $(printf '%s; ' "${warnings[@]}" | sed 's/; $//')"

# The systemMessage is shown to the user. The additionalContext goes to
# Claude. We also print the full bundle to stderr so a user reviewing
# transcripts can see it.
{
  echo "Bytewyrd plugin: requirement check warnings."
  printf '%s\n' "${warnings[@]}"
  echo "Suppress individual warnings with: BYTEWYRD_SKIP_WARN=<id1>,<id2>  (comma-separated)"
  echo "Suppressible IDs: github, context7, code-review, exa, firefox-devtools, gh-cli"
} >&2

emit_json true false "$sys_msg" "$ctx"
exit 0
