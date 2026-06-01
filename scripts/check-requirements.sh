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

# version_lt <v1> <v2>: returns 0 if v1 is strictly less than v2.
# Compares dot-separated integer segments (MAJOR.MINOR.PATCH); no dependencies.
version_lt() {
  local IFS=.
  read -r -a _v1 <<< "$1"
  read -r -a _v2 <<< "$2"
  local i
  for i in 0 1 2; do
    local a="${_v1[$i]:-0}" b="${_v2[$i]:-0}"
    [ "$a" -lt "$b" ] && return 0
    [ "$a" -gt "$b" ] && return 1
  done
  return 1  # equal — not less-than
}

# mcp_configured <prefix>: returns 0 if a mcpServers entry matching the
# server name derived from the prefix exists in ~/.claude.json or .mcp.json.
mcp_configured() {
  local prefix="$1"
  # Derive the server name: mcp__<name>__ → <name>
  local server_name
  server_name="$(printf '%s' "$prefix" | sed -E 's/^mcp__//; s/__$//')"

  for f in \
    "$HOME/.claude.json" \
    "$CLAUDE_PROJECT_DIR/.mcp.json"; do
    [ -f "$f" ] || continue
    if grep -q "\"${server_name}\"[[:space:]]*:" "$f"; then return 0; fi
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

# Hard failure: project's .claude/settings.json references a
# claude-plugins-official plugin that isn't installed. Claude Code itself
# errors at startup in this case (the plugin runtime has no marketplace URL
# to fall back to). Third-party entries (e.g. bytewyrd@bytewyrd) are
# intentionally excluded — they declare their source in extraKnownMarketplaces
# so Claude Code can resolve and install them automatically.
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

# Soft requirement: installed plugin version is not older than the version
# that last ran /sync on this project. Catches collaborators on stale installs
# whose /sync-written artifacts may not match their local skill/agent set.
if ! is_skipped "plugin-version"; then
  _expected_ver="$(cat "$CLAUDE_PROJECT_DIR/.bytewyrd/plugin-version" 2>/dev/null || echo "")"
  if [ -n "$_expected_ver" ]; then
    _current_ver="$(jq -r '.version // empty' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/.claude-plugin/plugin.json" 2>/dev/null || echo "")"
    if [ -n "$_current_ver" ] && version_lt "$_current_ver" "$_expected_ver"; then
      warnings+=("[warn] Plugin out of date: installed $_current_ver, project last synced with $_expected_ver. Fix: claude plugin install bytewyrd@bytewyrd")
    fi
  fi
fi

# --- Output -----------------------------------------------------------------

# ANSI color helpers — only when stderr is a real TTY; hooks pipe stderr so
# codes would appear as raw escapes in non-interactive contexts.
if [ -t 2 ]; then
  _RED=$'\033[1;31m'
  _YLW=$'\033[1;33m'
  _RST=$'\033[0m'
else
  _RED='' _YLW='' _RST=''
fi

# Silent path: no warnings, no failures.
if [ "${#warnings[@]}" -eq 0 ] && [ "${#failures[@]}" -eq 0 ]; then
  emit_json true true "" ""
  exit 0
fi

# Failure path: surface details in Claude Code's UI (via systemMessage) AND
# stderr (for non-TUI contexts), then exit 2 to block the session.
if [ "${#failures[@]}" -gt 0 ]; then
  # Build multiline systemMessage so Claude Code's notification shows the details.
  failure_lines="$(printf '%s\n' "${failures[@]}")"
  failure_msg="Bytewyrd plugin: FAILED — session blocked.

${failure_lines}"
  if [ "${#warnings[@]}" -gt 0 ]; then
    warn_lines="$(printf '%s\n' "${warnings[@]}")"
    failure_msg="${failure_msg}

Also warnings (review after fixing failures):
${warn_lines}"
  fi

  # Colorized stderr for non-TUI contexts.
  {
    printf '%s\n' "${_RED}Bytewyrd plugin: requirement check FAILED.${_RST}"
    printf "${_RED}%s${_RST}\n" "${failures[@]}"
    if [ "${#warnings[@]}" -gt 0 ]; then
      printf '%s\n' "${_YLW}Also warnings:${_RST}"
      printf "${_YLW}%s${_RST}\n" "${warnings[@]}"
    fi
  } >&2

  emit_json false false "$failure_msg" ""
  exit 2
fi

# Warning path: put full warning content in systemMessage so it appears
# front-and-center in Claude Code's header notification (not just a count
# pointing at invisible stderr). Stderr gets a minimal one-liner for non-TUI
# contexts only.
warning_count="${#warnings[@]}"
warn_lines="$(printf '%s\n' "${warnings[@]}")"
sys_msg="Bytewyrd plugin: ${warning_count} requirement(s) missing.

${warn_lines}

Suppress: BYTEWYRD_SKIP_WARN=<id1>,<id2>  (comma-separated)
IDs: github, context7, code-review, exa, firefox-devtools, gh-cli, plugin-version"

ctx="Bytewyrd plugin warnings active: $(printf '%s; ' "${warnings[@]}" | sed 's/; $//')"

# Minimal stderr — full details are in the Claude Code header notification.
printf "${_YLW}[bytewyrd] %d warning(s) — details in Claude Code header.${_RST}\n" "$warning_count" >&2

emit_json true false "$sys_msg" "$ctx"
exit 0
