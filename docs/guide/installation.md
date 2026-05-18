## Installation

First add the Bytewyrd marketplace, then install the plugin. User scope is the default — install once per machine, active in every project you open:

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
```

`--scope user` is the default and writes the enable-flag to `~/.claude/settings.json`, making the plugin available in every project you open.

For team-wide setups where every collaborator should be prompted to install, use project scope instead:

```bash
claude plugin install bytewyrd@bytewyrd --scope project
```

Once installed, run `/bytewyrd:sync` in any project to bootstrap the conventions.

## What the plugin checks at session start

Every time you start a session in any project, the plugin runs a one-shot requirement check via a `SessionStart` hook. The check is silent when everything is satisfied. When something is missing, you'll see one of two outputs:

- **Warning bundle** (most common): the plugin lists each missing soft dependency (companion plugins not enabled, MCP servers not configured, optional CLI tools not on PATH) with the exact fix command for each. The session continues normally. Suppress individual warnings by exporting `BYTEWYRD_SKIP_WARN=<id1>,<id2>` in your shell — e.g., `export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli` if you're working on a backend project and don't want UI/CLI nudges.

- **Hard failure** (rare): the plugin exits with a blocking error in one of two conditions:
  1. The project's `.claude/settings.json` references a `claude-plugins-official` plugin that is not installed (Claude Code itself would error during a tool call later — the hook surfaces this at startup with the exact fix).
  2. `git` is not on your `PATH` (the plugin cannot do anything without it).

In both cases the error message includes the exact command to fix the condition.

## Team-wide enforcement (optional)

The default posture is user-scope-first: the plugin is installed once per developer, and projects do not assert plugin enablement in their `.claude/settings.json`. If your team wants to *require* every collaborator to have the plugin installed (e.g., for a strict code-review or RFC-discipline policy), add the following to your project's `.claude/settings.json` under `enabledPlugins`:

```json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": true
  }
}
```

Per Claude Code's settings precedence rules, project settings override user settings — so a collaborator who hasn't installed the plugin yet will get an install prompt when they open the project. `/sync` does not write this entry by default; teams that want it must add it manually and check it into source control.
