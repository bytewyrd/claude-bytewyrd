# Contributing to claude-bytewyrd

This page is the extended on-ramp for people who want to *contribute to the plugin itself* — adding skills, modifying agents, evolving the RFC workflow, or proposing a new always-on rule, seed template or best practice.

For the narrow dev ops (clone, install locally, run the quality gate, commit conventions, PR process), see [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md). This page cross-links to it rather than duplicating.

## Plugin anatomy

```
claude-bytewyrd/
├── .claude-plugin/
│   ├── plugin.json              — plugin identity and hard dependencies (name, description, author, license, dependencies; deliberately no version)
│   └── marketplace.json         — marketplace entry for self-install, and the allowance for the dependencies' marketplace
├── agents/                      — 48 specialist subagent definitions (.md files)
├── skills/                      — exported skills (auto-discovered)
├── .claude/skills/              — plugin-local maintenance skills (not exported)
├── hooks/
│   ├── hooks.json               — SessionStart and SubagentStop hooks
│   └── always-on-rules.json     — the five conventions the SessionStart hook adds to every session
├── scripts/
│   ├── bw                       — POSIX-sh launcher that runs every command under Python 3.11 or newer
│   ├── bytewyrd/                — the Python package behind the commands
│   └── _vendor/                 — vendored PyYAML
├── templates/scaffold/          — the seed templates that scaffold renders and drift compares against
├── tests/                       — bats and pytest suites, and fixtures
├── docs/
│   ├── ARCHITECTURE.md          — internal design reference
│   ├── BEST_PRACTICES.md        — accumulated session learnings
│   ├── CONTRIBUTING.md          — dev workflow ops
│   ├── agent-audit-criteria.md  — what every agent file must satisfy
│   ├── project-brief.md         — what/why/who
│   ├── rfcs/                    — RFC proposals
│   └── guide/                   — user-facing documentation (this directory)
├── AGENTS.md                    — guidance for people and coding agents in this repo
├── CLAUDE.md                    — Claude Code additions; imports AGENTS.md
└── README.md                    — landing page for consumers
```

Two directories are easy to confuse:

- **`skills/`** is the **exported** skill set. Every directory here becomes a `/skill-name` for consumers.
- **`.claude/skills/`** is **plugin-local**. These skills only exist inside the plugin's own checkout — maintenance and meta-operations consumers would never invoke. The current local-only skill is `best-practices-sync`.

Two exported skills hold reference content that Claude reads at runtime, so consumers keep no copy of it: `rfc-process` (the RFC process, in `references/`) and `best-practices` (curated practices per stack, one file each). `scaffold` and `drift` are thin wrappers that run `scripts/bw`.

## What to read first

1. [`docs/project-brief.md`](../project-brief.md) — the plugin's identity, target audience, and naming conventions. Read this before proposing anything that changes the project's positioning.
2. [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — design decisions and component boundaries. The "Design Decisions" table is the place to look before you ask "why is it built this way?"
3. [`docs/agent-audit-criteria.md`](../agent-audit-criteria.md) — the contract every agent file in `agents/` must satisfy.
4. [`AGENTS.md`](../../AGENTS.md) and [`CLAUDE.md`](../../CLAUDE.md) — guidance for people and coding agents working in this repo. `CLAUDE.md` imports `AGENTS.md` and adds the Claude Code specifics; between them they apply the same workflow consumers see to the plugin itself.

## The promote-through-production model

This repository is both the definition of the bytewyrd workflow and a live instance of it. Changes follow a promote-through-production model:

1. Make the change to the plugin's own `.claude/` configuration first.
2. Validate through real usage in this repo (run the affected skills, spawn the affected agents).
3. Promote to the exported plugin artifacts (`skills/`, `agents/`, `.claude-plugin/`) only after the change behaves the way you want.

Never edit exported artifacts directly without first validating the change in the live `.claude/` context. This is enforced socially, not by tooling, but it's a hard rule — the export should always represent a tested baseline.

## Adding a skill or agent

Two task-oriented guides cover the common contribution paths:

- [Add a new skill to the plugin](contributing/add-a-skill.md) — full lifecycle: shape selection, naming, frontmatter, local testing, and the README update.
- [Add a new agent to the plugin](contributing/add-an-agent.md) — including the audit checklist every agent must pass.

Both link back into the architecture and conventions captured here.

## RFC-first for significant changes

The plugin uses its own RFC workflow for any change that involves design decisions, breaking changes, or new conventions that consumers will inherit. The shortlist:

- New skills with non-trivial behavior.
- Changes to which agent a skill spawns, or to an agent's default model, that shift defaults.
- Changes to `hooks/always-on-rules.json` or `hooks/hooks.json` — every consumer feels these.
- Changes to the process in the `rfc-process` skill (`skills/rfc-process/references/rfc-process.md`), which every project reads at runtime.
- New best-practice entries that will ship in the `best-practices` skill.

The shortlist of things that are *not* RFC-worthy: typo fixes, dependency bumps, additions to `docs/BEST_PRACTICES.md` from `/best-practices-extract`, agent upstream-improvement pulls.

Use `/rfc-new <description>` to start. The skill walks the full Draft → Approved → Done lifecycle. See the [`rfc-process` skill](../../skills/rfc-process/references/rfc-process.md) for the canonical process.

## Plugin packaging

`.claude-plugin/plugin.json` declares the plugin's identity and its dependencies to Claude Code (abridged here):

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "author": { "name": "Bytewyrd" },
  "license": "Apache-2.0",
  "dependencies": [
    "github@claude-plugins-official",
    "context7@claude-plugins-official",
    { "name": "code-review", "marketplace": "claude-plugins-official", "version": "^1.0.1" }
  ]
}
```

The manifest deliberately has no `version`. Claude Code reads the manifest's `version` first, and a pinned value keeps every install on its cached copy until the string changes. Without one, each commit on `main` is a new version, so users track commits. Don't add `version` back. See the versioning note at the top of [`CHANGELOG.md`](../../CHANGELOG.md).

The `dependencies` make `github`, `context7` and `code-review` from the official marketplace hard requirements: installing bytewyrd installs them, and Claude Code doesn't load bytewyrd while one is missing or disabled. Only `code-review` carries a version range, since it is the only one of the three that publishes a version. `marketplace.json` lists `claude-plugins-official` under `allowCrossMarketplaceDependenciesOn`, which allows the dependencies to come from that marketplace.

Skills under `skills/` and agents under `agents/` are auto-discovered — no array of paths is required in `plugin.json`. The plugin manifest is intentionally minimal: identity and dependencies, no behavior. Discovery does the rest.

`.claude-plugin/marketplace.json` declares the plugin within its own local marketplace, used by the project-local install pattern in `docs/CONTRIBUTING.md`. Both files are short and rarely change.

Skills and hooks that need deterministic work run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" <command>`. `bw` is a POSIX-sh launcher: it picks Python 3.11 or newer and runs `scripts/bytewyrd/commands/<command>.py`. The package uses the standard library and the PyYAML copy in `scripts/_vendor/`, so nothing installs at run time. Setup, tests and lint (uv, bats, pytest, ruff, mypy) are in [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md#development-setup).

## Where to put best-practice learnings

After a session where you learned something non-obvious about working on the plugin, capture it:

- **`/best-practices-record <one-line lesson>`** — writes to `~/.claude/BEST_PRACTICES.md` (global, cross-project). Use for portable patterns like "always run the quality gate before opening a PR."
- **`/best-practices-extract`** at session end — surfaces session learnings to this repo's `docs/BEST_PRACTICES.md`. Use for plugin-specific patterns like "the `tools:` frontmatter field is silently ignored by Claude Code, so don't bother adding it."

The global pool flows into every project through the `best-practices` skill, after a maintainer promotes entries with the plugin-local `best-practices-sync` skill.

## Hooks in the plugin checkout

The plugin's own checkout defines additional hooks in `.claude/settings.json` that run only in sessions inside this repository. They are not distributed to consumer projects via `/sync`.

**SessionStart — bootstrap version check**

Compares the `bootstrap-content-version` tag in `docs/BEST_PRACTICES.md` against the version recorded in `skills/sync/SKILL.md`. If the plugin's sync content is newer, prints a notice at session start suggesting you run `/sync` to refresh `docs/BEST_PRACTICES.md`. This is how existing projects learn that the plugin shipped new best-practice bootstrap content.

**SessionStart — precompact sentinel reset**

Removes `.bytewyrd/precompact-extraction-done` if it exists, re-arming the `PreCompact` gate for the new session. Invisible under normal operation — without this reset, a sentinel left over from a previous session would allow the first compaction of a new session to bypass the extraction check.

**PreCompact — compaction gate**

Blocks context compaction until `/best-practices-extract` runs this session. If the sentinel `.bytewyrd/precompact-extraction-done` is absent when compaction is triggered, the hook blocks and prints a message directing you to run `/best-practices-extract` first. Once extraction completes (the skill creates the sentinel), the next compaction attempt proceeds. To bypass: `touch .bytewyrd/precompact-extraction-done`, then re-run `/compact`.

**Stop — session-end checklist**

Fires when Claude Code stops. Prints a cleanup checklist covering `docs/BEST_PRACTICES.md` extraction, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `README.md`, and `docs/project-brief.md`. On plugin-checkout sessions where `~/.claude/BEST_PRACTICES.md` has content, also prints a reminder to run `/best-practices-sync` to promote pending global entries into the plugin's sync content.

**PostToolUse — post-commit documentation reminder**

Fires after any `git commit` shell command or GitHub MCP file-push operation. Prints a prompt asking whether the commit touches component structure, dev workflow, user-facing behavior, or product scope — and which documentation file should be updated if so. It is a prompt, not a block; work continues regardless.

---

## Related

- [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md) — narrow dev workflow ops.
- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — system design and decisions.
- [`rfc-process` skill](../../skills/rfc-process/references/rfc-process.md) — full RFC workflow.
- [Add a new skill](contributing/add-a-skill.md), [Add a new agent](contributing/add-an-agent.md) — task-oriented recipes.
