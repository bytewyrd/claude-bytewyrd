# Getting started

This tutorial takes you from a clean machine to a working `claude-bytewyrd` setup with one finished RFC. It should take about 15 minutes.

By the end you will have:

1. The plugin installed at user scope.
2. A project bootstrapped with the bytewyrd conventions (RFC docs, agent table, best-practices file).
3. A Draft RFC drafted by `rfc-architect`, reviewed by independent critic agents.
4. The same RFC approved by you and implemented by `feature-engineer`.

## Prerequisites

- [Claude Code](https://docs.claude.com/claude-code) installed and authenticated.
- [git](https://git-scm.com/) on your `PATH`.
- An empty (or near-empty) project directory where you can experiment.

Optional but recommended — the plugin will warn you at session start if these are missing and you can fix them later:

- The `github`, `context7`, and `code-review` companion plugins from `claude-plugins-official`.
- The Exa MCP server (web search) and Firefox MCP (UI verification).
- The [GitHub CLI](https://cli.github.com/) (`gh`).

## Step 1 — Install the plugin

From any terminal:

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
```

Restart Claude Code if it is already running. The plugin is now available in every project you open.

## Step 2 — Bootstrap your project

Open Claude Code in your project directory. In the session, run:

```
/bytewyrd:sync
```

`/sync` is idempotent — safe to re-run any time the plugin updates. On the first run, it asks for the project name and a one-line description (used in `docs/project-brief.md`), then creates or updates:

- `CLAUDE.md` — operating rules for Claude in this project.
- `README.md` — bootstrap landing page (written once, then project-owned).
- `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md` — internal docs scaffolds.
- `docs/rfc-process.md` — the full RFC workflow, including any project-specific extensions.
- `docs/rfcs/` — directory for future RFCs.
- `.claude/settings.json` — permissions, hooks, and MCP-server allow-lists.
- `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` — PR template and starter CI workflow.
- `.gitignore` and `mise.toml` — sensible defaults; merged additively if you already maintain them.

If anything is missing or out of date, `/sync` shows a categorized summary (additions, fast-forward updates, conflicts) and asks you to approve before writing.

## Step 3 — Author your first RFC

Pick a small, concrete change you actually want to make to your project. RFCs work best for design decisions, not trivial cleanup. Examples that fit:

- "Add a `/release` skill that automates version bumps."
- "Replace direct `fetch` calls in the codebase with a typed client."
- "Adopt a daily-cron job to prune stale branches."

In your session, run:

```
/rfc-new <one-line description of your idea>
```

The skill creates a date-based RFC file in `docs/rfcs/YYYY-MM-DD-<slug>.md`, spawns the `rfc-architect` subagent to flesh out the proposal (Opus, with research via Context7 and Exa), runs independent reviewer agents, runs the consensus-review pass, and applies any verified critical fixes automatically. When it finishes, the RFC is in `Draft` status and `rfc-architect` walks you through any remaining design decisions one at a time.

If you have rough ideas you want to capture without authoring a full RFC, use `/rfc-braindump <idea>` first — entries land in `docs/rfc-braindump.md` and can be promoted later with `/rfc-new`.

## Step 4 — Approve the RFC

Read the Draft. If you spot something to change, add inline `FEEDBACK:` comments and run `/rfc-read-feedback` — `rfc-architect` will revise. If the consensus surfaced design questions you want a second opinion on, run `/rfc-consensus-review`.

When you are happy with the Draft, approve it:

```
/rfc-approve
```

This is the **only** step in the workflow that is human-only. Agents draft and review; humans approve. The RFC's `status` frontmatter flips to `Approved` and the change is committed.

## Step 5 — Implement the RFC

```
/rfc-implement
```

This spawns the `feature-engineer` subagent with the Approved RFC as its primary spec. The agent reads the RFC, builds the change, and opens a pull request. When the PR merges (or when you mark it manually), the RFC moves to `Done`.

If you decide partway through that the design needs revision, stop the implementation and either run `/rfc-read-feedback` to amend the Draft, or `/rfc-drop` to retire it.

## What to do next

You now have the full loop. From here:

- `/best-practices-record <one-line lesson>` after any session where you learned something non-obvious — entries flow into `~/.claude/BEST_PRACTICES.md`.
- `/best-practices-extract` at the end of a meaningful session — surfaces session learnings to `docs/BEST_PRACTICES.md` and offers to promote portable ones globally.
- `/docs-review <scope>` after `/rfc-implement` lands user-visible behavior — checks `docs/guide/**` for drift.
- `/refactor <scope>` before extending code that has thin test coverage — deliberate phased refactor with characterization tests.
- `/rfc-summary` for a quick snapshot of every Draft and Approved RFC.

For task-specific recipes, see the [how-to guides](../how-to). For the full skill and agent surface, see the [reference section](../reference).
