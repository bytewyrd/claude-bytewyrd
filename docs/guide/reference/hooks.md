# Hooks reference

The plugin ships two hooks that fire automatically during Claude Code sessions. Both are defined in `hooks/hooks.json` and execute shell commands — no network calls, no Claude invocations.

## SubagentStop — feature-engineer reminder

**Trigger:** fires whenever a `bytewyrd:feature-engineer` subagent finishes.

**Behavior:**

1. Prints a reminder to the terminal:
   > Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, a new CLI flag, a new workflow), consider running /docs-review against the changed paths to check whether docs/guide/** needs updates.

2. Creates (or touches) `.bytewyrd/last-feature-engineer-stop` in the project root. This sentinel file is used by the compact SessionStart hook (see below).

**Why it exists:** `docs/guide/**` is the canonical user-facing documentation surface. The `feature-engineer` agent writes code; it does not update docs. The hook closes the gap by prompting you to run `/docs-review` before the session context is lost.

**How to dismiss:** run `/docs-review` (the sentinel is deleted at the end of the review), or delete the sentinel manually:

```bash
rm -f .bytewyrd/last-feature-engineer-stop
```

---

## SessionStart — compact reminder

**Trigger:** fires at the start of every compact Claude Code session (when the conversation is loaded from a compacted snapshot rather than fresh).

**Behavior:** if `.bytewyrd/last-feature-engineer-stop` exists and is less than 24 hours old, prints:

> Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not yet have run. Consider running /docs-review against the implemented files.

**Why it exists:** the SubagentStop reminder appears in the terminal but disappears when the session is compacted. This hook re-surfaces it so the reminder survives context compression.

---

## SessionStart — requirement check

**Trigger:** fires at the start of every Claude Code session.

**Behavior:** runs `scripts/check-requirements.sh`, which probes three categories of dependencies:

### Hard failures (exit 2 — blocks the session)

| ID | Condition | Fix |
|----|-----------|-----|
| `git` | `git` is not on `PATH` | Install git |
| stale plugin reference | `.claude/settings.json` has an `enabledPlugins` entry for a `*@claude-plugins-official` plugin that is not installed | Run `claude plugin install <id>` or remove the entry |

Hard failures are not suppressible — Claude Code would error later in the same session anyway.

### Soft warnings (session continues)

| Suppressible ID | What is checked | Fix |
|-----------------|-----------------|-----|
| `github` | `github@claude-plugins-official` not enabled | `claude plugin install github@claude-plugins-official` |
| `context7` | `context7@claude-plugins-official` not enabled | `claude plugin install context7@claude-plugins-official` |
| `code-review` | `code-review@claude-plugins-official` not enabled | `claude plugin install code-review@claude-plugins-official` |
| `exa` | No `mcp__exa__` permission entry in any settings file | Add Exa under `mcpServers` in `~/.claude.json` or `.mcp.json` |
| `firefox-devtools` | No `mcp__firefox-devtools__` permission entry in any settings file | Install Firefox MCP |
| `gh-cli` | `gh` not on `PATH` | Install the GitHub CLI |

### Suppressing warnings

Set `BYTEWYRD_SKIP_WARN` in your shell environment with a comma-separated list of suppressible IDs:

```bash
# Example: suppress Firefox MCP and gh-cli nudges on a backend-only machine
export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli
```

Add the export to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) to make it permanent. The check is per-session; the variable is read fresh each time.

**Silent path:** when all checks pass, the script exits without output.
