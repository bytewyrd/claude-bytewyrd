# Suppress session-start warnings

The plugin ships a `SessionStart` hook (`scripts/check-requirements.sh`) that probes for companion plugins, MCP servers, and CLI tools every time you open a Claude Code session. When something soft is missing, the hook emits a warning bundle. The session continues — these are nudges, not blockers.

Most teams will see at least one warning that does not apply to their project (e.g., a backend-only repo gets a Firefox MCP warning that's irrelevant). This guide shows how to silence those individually.

## Suppress one or more warnings

Set the `BYTEWYRD_SKIP_WARN` environment variable to a comma-separated list of warning IDs in your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli
```

Reload your shell or open a new terminal, then restart Claude Code. The named warnings will no longer appear; everything else still does.

## Available IDs

The full list of suppressible IDs (from `scripts/check-requirements.sh`):

| ID | Suppresses |
|----|-----------|
| `github` | The `github@claude-plugins-official` plugin is not enabled |
| `context7` | The `context7@claude-plugins-official` plugin is not enabled |
| `code-review` | The `code-review@claude-plugins-official` plugin is not enabled |
| `exa` | The Exa MCP server is not configured |
| `firefox-devtools` | The Firefox MCP server is not configured |
| `gh-cli` | The `gh` CLI is not on `PATH` |

## What you cannot suppress

`BYTEWYRD_SKIP_WARN` only silences warnings — it cannot bypass hard failures. The hook exits with a blocking error in two cases, neither of which is suppressible:

- The project's `.claude/settings.json` references a `claude-plugins-official` plugin that is not installed (Claude Code itself would error during a tool call later).
- `git` is not on your `PATH`.

In both cases the error message includes the exact fix command. Run it and the hook proceeds.

## Per-project suppression

`BYTEWYRD_SKIP_WARN` is a shell environment variable, so it applies to every project you open in that shell. If you want different suppression sets per project — e.g., a frontend project that wants `firefox-devtools` checked, and a backend project that does not — set the variable in a project-local `.envrc` (with [direnv](https://direnv.net/)) or a shell wrapper.

## Related

- [Installation](../installation.md) — install scopes and what the hook checks.
- [Architecture](../../ARCHITECTURE.md) — design rationale for the requirement-check hook.
