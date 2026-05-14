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

`/sync` automatically writes two entries to the project's `.claude/settings.json` and commits them to source control:

```json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": true
  },
  "extraKnownMarketplaces": {
    "bytewyrd": {
      "source": {
        "source": "github",
        "repo": "bytewyrd/claude-bytewyrd"
      }
    }
  }
}
```

Both entries are required. `enabledPlugins` alone is insufficient — without `extraKnownMarketplaces`, Claude Code doesn't know where to find the `bytewyrd` marketplace and cannot prompt the collaborator to install it. When both are present, a collaborator who opens the repo for the first time is prompted to add the marketplace and then install the plugin.

The rationale: the plugin writes RFC docs, BEST_PRACTICES.md, and other project-level artifacts that every team member needs to interact with. For collaborators who already have the plugin installed at user scope, both entries are no-ops — the install prompts are skipped.
