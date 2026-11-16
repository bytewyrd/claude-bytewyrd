# Getting started

This tutorial takes you from a clean machine to a working `claude-bytewyrd` setup with one finished RFC. It should take about 15 minutes.

By the end you will have:

1. The plugin installed at user scope.
2. A project seeded with the bytewyrd files: `AGENTS.md`, a `CLAUDE.md` that imports it, a PR template, and a CI workflow.
3. A Draft RFC drafted by `rfc-architect`, reviewed by independent critic agents.
4. The same RFC approved by you and implemented by `feature-engineer`.

## Prerequisites

- [Claude Code](https://docs.claude.com/claude-code) installed and authenticated.
- [git](https://git-scm.com/) on your `PATH`.
- [Python](https://www.python.org/) 3.11 or newer, on your `PATH` or named in `BYTEWYRD_PYTHON`. The plugin's commands and hooks run on it; check yours with `python3 --version`.
- [jq](https://jqlang.org/), which the RFC and best-practices skills use to read their helper scripts' output. See [Requirements](../installation.md#requirements).
- An empty (or near-empty) project directory where you can experiment. Make it a git repository (`git init`) and commit what is in it: `/bytewyrd:scaffold --apply` refuses a dirty working tree.

Optional — nothing checks for these at session start:

- The Exa MCP server (web search) and Firefox MCP (UI verification).
- The [GitHub CLI](https://cli.github.com/) (`gh`).

## Step 1 — Install the plugin

From any terminal:

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official
```

The `claude plugin` commands never register the official marketplace on their own, so that command comes first. bytewyrd depends on `github`, `context7` and `code-review` from it, and Claude Code doesn't load bytewyrd unless all three are installed and enabled. The last three commands install them explicitly, so that updates keep them resolved.

Restart Claude Code if it is already running. The plugin is now available in every project you open. See [Installation](../installation.md) for project scope, following a branch or tag, and upgrading from 0.2.x.

## Step 2 — Seed your project

Open Claude Code in your project directory. In the session, run:

```
/bytewyrd:scaffold
```

This is a dry run: it lists what it would create and writes nothing. It asks you no questions, and the project name comes from your repository. It prints something like:

```
bytewyrd scaffold: /path/to/myapp
would create  AGENTS.md
would create  CLAUDE.md
would create  .github/PULL_REQUEST_TEMPLATE.md
would create  .github/workflows/ci.yml
dry run: 4 to create, 0 skipped; re-run with --apply to write
```

When the list looks right, write the files:

```
/bytewyrd:scaffold --apply
```

`--apply` refuses to run on a dirty working tree (it exits with code 3), so commit or stash your work first, or add `--allow-dirty`. It creates only the files that are missing and skips any that exist:

- `AGENTS.md` — guidance for people and coding agents: the project name, the languages scaffold found with their build and test commands, and links to the RFC process and the plugin's always-on rules.
- `CLAUDE.md` — imports `@AGENTS.md` and adds Claude Code specifics, including the plugin install commands for new collaborators.
- `.github/PULL_REQUEST_TEMPLATE.md` — a pull request template.
- `.github/workflows/ci.yml` — one job per language it found, each calling the plugin's reusable workflow at a pinned commit, or a no-op job when it found none.

Each file starts with a stamp line that names its template and the plugin commit. Review and commit them: from then on they belong to your project, and the plugin never edits them. After a plugin update, `/bytewyrd:drift` shows which of them differ from the new templates. It only reports; you decide what to change.

Nothing else is seeded. The RFC process and the best-practices library stay in the plugin as the `rfc-process` and `best-practices` skills, which Claude reads at runtime, so your project keeps no copy of them.

## Step 3 — Author your first RFC

RFCs live in `docs/rfcs/`, and a repository opts in to the RFC process by having that directory. Create it before your first RFC: `mkdir -p docs/rfcs`.

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

## Step 4 — Revise and approve the RFC

Read the Draft. You have three ways to push back before approving.

**Targeted feedback — `/rfc-read-feedback`**

Open the RFC file and add `FEEDBACK:` comments directly in the markdown wherever you want something changed:

```markdown
## Implementation spec

<!-- FEEDBACK: This approach couples two concerns — split the helper into its own module. -->
The skill will write directly to the main skill file.
```

Then run:

```
/rfc-read-feedback
```

`rfc-architect` reads every `FEEDBACK:` marker, revises the RFC to incorporate each comment, removes the markers, and runs the self-review checklist. Repeat this cycle as many times as you need.

**Broader review — `/rfc-consensus-review`**

If you want an independent second opinion on the whole RFC rather than targeted comments, run:

```
/rfc-consensus-review
```

This spawns five parallel reviewer agents and synthesizes their findings by consensus. Critical findings (4–5/5 reviewers agree) are auto-fixed; moderate and minor findings are presented to you as design decisions to resolve one at a time.

**Approve — `/rfc-approve`**

When you are satisfied with the Draft:

```
/rfc-approve
```

This is the **only** step in the workflow that is human-only. Agents draft and review; humans approve. The RFC's `status` frontmatter flips to `Approved` and the change is committed.

## Step 5 — Implement the RFC

```
/rfc-implement
```

This spawns the `feature-engineer` subagent with the Approved RFC as its primary spec. The agent reads the RFC, builds the change, and opens a pull request. When the PR merges (or when you mark it manually), the RFC moves to `Done`.

If you decide partway through that the design needs revision, stop the implementation and run `/rfc-read-feedback` to amend the RFC and re-enter the approval cycle. To retire it entirely, run:

```
/rfc-drop <reason>
```

## What to do next

You now have the full loop. Here is the rest of the skill surface, organized by when you'll reach for each one.

**Capture ideas early**

- `/rfc-braindump <idea>` — log a rough idea to `docs/rfc-braindump.md` without authoring a full RFC. Useful when you're not ready to commit to a design.

**Track in-flight work**

- `/rfc-summary` — list every Draft and Approved RFC at a glance (identifier, title, author, date). Read-only, runs inline.

**Maintain code quality**

- `/refactor <scope>` — deliberate phased refactor with characterization tests, approval gate, and one commit per step. Run this before extending code that has thin test coverage so the upcoming feature has a clean place to land.

**Keep docs in sync**

- `/docs-review <scope>` — after `/rfc-implement` lands user-visible behavior, audit `docs/guide/**` for drift (broken examples, stale references, workflow changes). The scope can be an RFC identifier, a path, or `all`.

**Capture learnings**

- `/best-practices-record <one-line lesson>` — capture a single cross-project lesson immediately into `~/.claude/BEST_PRACTICES.md`.
- `/best-practices-extract` — at the end of a meaningful session, surface non-obvious learnings to `docs/BEST_PRACTICES.md` and optionally promote portable ones globally.

**Housekeeping**

- `/git-branch-cleanup` — prune stale local branches (no remote, merged PRs, abandoned remotes) and clean up orphaned worktrees.
- `/bytewyrd:drift` — run it after the plugin updates. It is read-only: it compares the files `/bytewyrd:scaffold` seeded with the plugin's current templates and lists anything out of date, plus anything 0.2.x left behind, each with a one-line fix for you to review and run.

For task-specific recipes, see the [how-to guides](../how-to). For the full skill and agent surface, see the [reference section](../reference).
