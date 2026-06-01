{
  "enabledPlugins": {<ENABLED_PLUGINS_ENTRIES>
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "rm -f \"${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done\""
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf '%s\\n' '{\"continue\":true}'; else mkdir -p .bytewyrd; printf '%s\\n' '{\"decision\":\"block\",\"reason\":\"Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is blocked until /best-practices-extract runs in this session. The sentinel file .bytewyrd/precompact-extraction-done does not exist, which means extraction has not yet completed. The expected next action is to invoke /best-practices-extract; the skill itself preserves the per-candidate human-approval prompt, so this gate does not write anything without confirmation. When the skill completes (including the no-op path where nothing passes triage), it creates the sentinel file and the next compaction trigger will be allowed through. To bypass without extraction, the user can run: touch .bytewyrd/precompact-extraction-done then /compact.\"}}'; fi"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit*)",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__push_files",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__create_or_update_file",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
          }
        ]
      }
    ]<PRE_TOOL_USE_HOOK>
  }
}
