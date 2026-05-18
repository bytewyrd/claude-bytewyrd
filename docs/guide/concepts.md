# Understanding the plugin

This page explains the mental model behind the plugin — what skills and agents are, how the hook system works, why the RFC process is the default for design work, and how learnings accumulate across projects. It is reading, not steps. For task recipes, see the [how-to guides](index.md#how-to-guides--recipes-for-specific-tasks).

---

## Skills and agents — the distinction that matters

**Skills** are slash commands you invoke in a Claude Code session. `/rfc-new`, `/refactor`, `/docs-review` — each skill has a single, well-defined job. Skills are discovered by Claude Code from the plugin's `skills/` directory and run in the main conversation context.

**Agents** are specialist subagents that skills spawn for complex, domain-specific work. When you run `/rfc-new`, the skill itself handles the orchestration (prompting for a description, creating the file, running the review loop) while the `rfc-architect` agent — operating on Opus with the full RFC process as its context — does the actual design work. You interact with the skill; the skill delegates to the agent.

The distinction matters because it determines where the work happens. Skills run in the main conversation thread; they can ask you questions and relay agent output back to you. Agents run as subtasks; they have focused tool access and a domain-specific system prompt that makes them better at their specialty than the generalist main agent.

You generally do not need to invoke agents directly. The skills know which agents to use and when.

### Why use specialists rather than the main agent?

Each agent carries a focused system prompt — the `rfc-architect` knows RFC structure and review protocols; the `refactoring-specialist` knows code smell catalogs, characterization test patterns, and Fowler's refactoring catalog. A specialist produces higher-quality output than the main agent would inline, and the model budget is used more efficiently (specialists default to the cheapest model that fits the task).

The [agent delegation table in CLAUDE.md](../CLAUDE.md) maps task types to agents.

---

## The hook system

The plugin ships hooks that fire automatically during Claude Code's session lifecycle. Hooks run outside Claude's context — they are shell scripts, not agent tasks.

**`SessionStart` — requirement check**

Fires at the start of every Claude Code session. Runs `scripts/check-requirements.sh`, which probes for:

- Companion plugins (GitHub, Context7, code-review)
- MCP servers (Exa, Firefox DevTools)
- CLI tools (`git`, `gh`)
- Plugin version — whether the installed plugin is older than the version that last ran `/sync` on this project

If all checks pass, the hook is silent. When something soft is missing, it emits a warning bundle but lets the session continue. Hard failures (`git` missing, a stale plugin reference in settings) block the session with a remediation command.

Individual soft warnings can be silenced with `BYTEWYRD_SKIP_WARN`. See [Suppress session-start warnings](how-to/suppress-session-warnings.md).

**`SessionStart` — compact reminder**

A second `SessionStart` hook checks whether a `feature-engineer` agent finished in the last 24 hours without a subsequent `/docs-review` run. If so, it re-surfaces the reminder to check whether `docs/guide/**` needs updating. This reminder survives context compaction (where the original terminal output would be lost).

**`SubagentStop` — feature-engineer reminder**

Fires whenever a `bytewyrd:feature-engineer` subagent finishes. Prints a reminder to run `/docs-review` if the implemented feature affects user-visible behavior. Also creates a sentinel file (`.bytewyrd/last-feature-engineer-stop`) that the compact `SessionStart` hook reads.

For full hook details, see [Hooks reference](reference/hooks.md).

---

## The RFC process as the backbone of structured work

For any work that involves design decisions — new features, architectural changes, tool migrations, anything expected to take more than one focused session — the plugin defaults to writing an RFC before touching code.

**Why RFC-first?**

1. Explicit trade-offs. Writing down the options before you commit to one forces the reasoning to be visible. It is much cheaper to reject a design on paper than to rewrite it after implementation.
2. Audit trail. `docs/rfcs/` is a searchable record of why decisions were made, not just what was built. When you come back to a system six months later, the RFC tells you what was considered and why the current approach was chosen.
3. Agent alignment. The `feature-engineer` agent follows the RFC's implementation spec exactly. An unambiguous spec produces a predictable implementation; a vague spec produces guesses.

**What the lifecycle looks like from your perspective:**

A quick idea goes into `docs/rfc-braindump.md` via `/rfc-braindump`. When you are ready to design it, `/rfc-new` handles the full authoring and review loop — `rfc-architect` writes the RFC, domain-specific agents review it, `/rfc-consensus-review` synthesizes findings and walks you through design opinions. When you are satisfied, `/rfc-approve` locks the design. Then `/rfc-implement` builds it.

You spend your time reviewing and approving, not writing boilerplate or managing review logistics.

For the full user-facing guide, see [How to use the RFC process](how-to/rfc-process.md). For the skill command reference, see [RFC workflow](how-to/rfc-workflow.md).

---

## The best-practices lifecycle

Engineering learnings accumulate in three files, at increasing scope:

| File | Scope | How entries arrive |
|------|-------|-------------------|
| `docs/BEST_PRACTICES.md` | This project | `/best-practices-extract` at session end |
| `~/.claude/BEST_PRACTICES.md` | All your projects | Promotion step in `/best-practices-extract`, or `/best-practices-record` |
| `skills/sync/SKILL.md` (plugin bootstrap content) | All future projects | Plugin maintainer runs `/best-practices-sync` |

The key design principle is that promotion requires human review at each step. `/best-practices-extract` extracts from the session and offers entries for promotion to the global pool — you confirm the bulk checkbox. `/best-practices-sync` (a plugin-local maintenance skill) promotes from the global pool into the plugin's sync content — a maintainer reviews each entry before it ships to future projects.

This staged flow prevents one project's specific workaround from landing in every future project's `BEST_PRACTICES.md`. The global bar is higher than the project bar by design.

The compaction gate (a `PreCompact` hook) ensures extraction happens before context is compressed. The first compaction trigger of a session blocks until `/best-practices-extract` runs, then the gate releases. See [How to capture and propagate best practices](how-to/best-practices.md).

---

## Why `/sync` is the entry point

`/sync` is idempotent and safe to re-run. It sets up or refreshes:

- `docs/rfc-process.md` — a self-contained copy of the RFC process, updated with upstream sync markers so future `/sync` runs can detect and apply plugin updates
- `docs/BEST_PRACTICES.md` — seeded with entries promoted into the plugin's sync content
- `CLAUDE.md` — agent delegation table, evidence-based development rules, model usage guidelines
- `docs/CONTRIBUTING.md` — developer workflow, including the plugin install hint for new collaborators
- `.claude/settings.json` — hooks, permissions

Running `/sync` when the plugin updates picks up any new conventions or quality gates. You do not need to manage individual files — `/sync` handles the idempotent merge.

---

## Promote-through-production

This repository is a live instance of its own workflow. Every RFC, every skill, every convention was designed and tested here before being distributed to other projects. The pattern you see in the guide pages is not aspirational — it is the workflow the plugin itself runs on.

This matters because it prevents "designed in theory" from shipping as a convention. The RFC process is documented the way it is because it has been used to design and ship the plugin's own features. The agent delegation table reflects the actual agents used for the plugin's development. Best practices in `docs/BEST_PRACTICES.md` were extracted from real sessions.
