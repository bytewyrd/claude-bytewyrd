# Hooks reference

The plugin ships hooks that fire automatically during Claude Code sessions. Plugin-distributed hooks (applied to every consumer project via `/sync`) are defined in `hooks/hooks.json`. Additional hooks in `.claude/settings.json` are project-local — they apply only in the plugin's own checkout and are not distributed to consumers. All hooks execute shell commands — no network calls, no Claude invocations.

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
| `plugin-version` | The installed plugin version is older than the version that last ran `/sync` on this project | Run `/sync` to update the project, or upgrade the plugin |

### Suppressing warnings

Set `BYTEWYRD_SKIP_WARN` in your shell environment with a comma-separated list of suppressible IDs:

```bash
# Example: suppress Firefox MCP and gh-cli nudges on a backend-only machine
export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli
```

Add the export to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.) to make it permanent. The check is per-session; the variable is read fresh each time.

**Silent path:** when all checks pass, the script exits without output.

---

## Project-local hooks (.claude/settings.json)

The following hooks are defined in `.claude/settings.json` in the plugin's own checkout. They are **not** distributed to consumer projects via `/sync` — they apply only when working inside the plugin repository itself.

---

## SessionStart — bootstrap version check

**Trigger:** fires at the start of every Claude Code session (unconditional matcher).

**Behavior:** compares the `bootstrap-content-version` tag in `docs/BEST_PRACTICES.md` against the version recorded in `skills/sync/SKILL.md`. If the plugin's sync content has a newer version than what is currently in the project's `BEST_PRACTICES.md`, prints a notice:

> SessionStart: bootstrap content has new entries (project=X, plugin=Y). Consider running /sync to refresh docs/BEST_PRACTICES.md.

**User-visible effect:** you see a notice at session start when your `docs/BEST_PRACTICES.md` is behind the plugin's current sync content. Run `/sync` to pick up the new entries.

**Why it exists:** when the plugin ships new best-practice bootstrap content, existing projects would not know about it without a version check. This hook surfaces the gap automatically.

---

## SessionStart — precompact sentinel reset

**Trigger:** fires at the start of every Claude Code session (unconditional matcher).

**Behavior:** removes `.bytewyrd/precompact-extraction-done` if it exists. This re-arms the `PreCompact` gate for the new session.

**User-visible effect:** invisible under normal operation. Without this reset, a sentinel left over from a previous session would allow the first compaction of a new session to bypass the extraction check.

---

## PreCompact — compaction gate

**Trigger:** fires whenever Claude Code is about to compact the conversation context.

**Behavior:**

- If `.bytewyrd/precompact-extraction-done` exists: removes the sentinel file and continues (returns `{"continue": true}`).
- If the sentinel does not exist: blocks compaction with a `block` decision and prints:

  > Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.

**User-visible effect:** if you try to compact without first running `/best-practices-extract`, Claude Code pauses and tells you why. After extraction completes (the skill creates the sentinel), the next compaction attempt proceeds normally.

**Bypass:** if you want to compact without extraction:

```bash
touch .bytewyrd/precompact-extraction-done
```

Then re-run `/compact`.

---

## Stop — session-end checklist

**Trigger:** fires when Claude Code stops at the end of a session.

**Behavior (two commands run in sequence):**

1. Prints a cleanup checklist:
   > Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.

2. If the current checkout is the plugin itself (detected via `.claude-plugin/plugin.json`) and `~/.claude/BEST_PRACTICES.md` has content: prints an additional reminder to run `/best-practices-sync` to promote pending global entries into the plugin's sync content.

**User-visible effect:** after Claude Code stops, you see the checklist above. On plugin-checkout sessions, you also see the sync-promotion reminder when there are pending global entries.

---

## PostToolUse — post-commit documentation reminder

**Trigger:** fires after any of these tool calls:

- `Bash(git commit*)` — any `git commit` shell command
- `mcp__plugin_github_github__push_files` — GitHub MCP file push
- `mcp__plugin_github_github__create_or_update_file` — GitHub MCP file create/update

**Behavior:** prints a documentation reminder:

> Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.

**User-visible effect:** after each commit or GitHub file operation, you see the reminder above. It is a prompt, not a block — work continues regardless.

**Why it exists:** documentation updates are easy to defer and forget once a commit is made. The hook surfaces the question while the change is fresh.
