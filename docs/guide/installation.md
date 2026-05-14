## Installation

The plugin installs at user scope by default — install once per machine, use everywhere:

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
```

The default scope is `user` (per Claude Code's `claude plugin install` documentation), which writes the enable-flag to `~/.claude/settings.json` and makes the plugin available in every project you open.

## What the plugin checks at session start

Every time you start a session in any project, the plugin runs a one-shot requirement check via a `SessionStart` hook. The check is silent when everything is satisfied. When something is missing, you'll see one of two outputs:

- **Warning bundle** (most common): the plugin lists each missing soft dependency (companion plugins not enabled, MCP servers not configured, optional CLI tools not on PATH) with the exact fix command for each. The session continues normally. Suppress individual warnings by exporting `BYTEWYRD_SKIP_WARN=<id1>,<id2>` in your shell — e.g., `export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli` if you're working on a backend project and don't want UI/CLI nudges.

- **Hard failure** (rare): the plugin exits with a blocking error in one of two conditions:
  1. The project's `.claude/settings.json` references a `claude-plugins-official` plugin that is not installed (Claude Code itself would error during a tool call later — the hook surfaces this at startup with the exact fix).
  2. `git` is not on your `PATH` (the plugin cannot do anything without it).

In both cases the error message includes the exact command to fix the condition.

## Team-wide enforcement

`/sync` automatically adds `bytewyrd@bytewyrd` to `enabledPlugins` in the project's `.claude/settings.json`. This entry should be committed to source control.

The rationale: the plugin writes RFC docs, BEST_PRACTICES.md, and other project-level artifacts that every team member needs to interact with. Project-scope enablement ensures any collaborator who hasn't installed the plugin is prompted by Claude Code on first open. If a collaborator already has the plugin installed at user scope, the entry is a no-op.

Per Claude Code's settings precedence, project settings layer on top of user settings — the project entry does not override or conflict with a user-scope install.
