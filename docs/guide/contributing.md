# Contributing to claude-bytewyrd

This page is the extended on-ramp for people who want to *contribute to the plugin itself* — adding skills, modifying agents, evolving the RFC workflow, or proposing a new convention to bundle with `/sync`.

For the narrow dev ops (clone, install locally, run the quality gate, commit conventions, PR process), see [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md). This page cross-links to it rather than duplicating.

## Plugin anatomy

```
claude-bytewyrd/
├── .claude-plugin/
│   ├── plugin.json              — plugin identity (name, version, description)
│   └── marketplace.json         — local marketplace entry for self-install
├── agents/                      — 48 specialist subagent definitions (.md files)
├── skills/                      — exported slash-command skills (auto-discovered)
├── .claude/skills/              — plugin-local maintenance skills (not exported)
├── hooks/
│   └── hooks.json               — SessionStart + SubagentStop hooks
├── scripts/                     — helper shell scripts called by skills and hooks
├── docs/
│   ├── ARCHITECTURE.md          — internal design reference
│   ├── BEST_PRACTICES.md        — accumulated session learnings
│   ├── CONTRIBUTING.md          — dev workflow ops
│   ├── agent-audit-criteria.md  — what every agent file must satisfy
│   ├── project-brief.md         — what/why/who
│   ├── rfc-process.md           — full RFC workflow (template for /sync)
│   ├── rfcs/                    — RFC proposals
│   └── guide/                   — user-facing documentation (this directory)
├── CLAUDE.md                    — operating rules for Claude in this repo
└── README.md                    — landing page for consumers
```

Two directories are easy to confuse:

- **`skills/`** is the **exported** skill set. Every directory here becomes a `/skill-name` for consumers.
- **`.claude/skills/`** is **plugin-local**. These skills only exist inside the plugin's own checkout — maintenance and meta-operations consumers would never invoke. The current local-only skill is `best-practices-sync`.

## What to read first

1. [`docs/project-brief.md`](../project-brief.md) — the plugin's identity, target audience, and naming conventions. Read this before proposing anything that changes the project's positioning.
2. [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — design decisions and component boundaries. The "Design Decisions" table is the place to look before you ask "why is it built this way?"
3. [`docs/agent-audit-criteria.md`](../agent-audit-criteria.md) — the contract every agent file in `agents/` must satisfy.
4. `CLAUDE.md` — operating rules for Claude when working in this repo. It encodes the same workflow consumers see, applied to the plugin itself.

## The promote-through-production model

This repository is both the definition of the bytewyrd workflow and a live instance of it. Changes follow a promote-through-production model:

1. Make the change to the plugin's own `.claude/` configuration first.
2. Validate through real usage in this repo (run the affected skills, spawn the affected agents).
3. Promote to the exported plugin artifacts (`skills/`, `agents/`, `.claude-plugin/`) only after the change behaves the way you want.

Never edit exported artifacts directly without first validating the change in the live `.claude/` context. This is enforced socially, not by tooling, but it's a hard rule — the export should always represent a tested baseline.

## Adding a skill or agent

Two task-oriented guides cover the common contribution paths:

- [Add a new skill to the plugin](how-to/add-a-skill.md) — full lifecycle: shape selection, naming, frontmatter, local testing, README and CLAUDE.md updates.
- [Add a new agent to the plugin](how-to/add-an-agent.md) — including the audit checklist every agent must pass.

Both link back into the architecture and conventions captured here.

## RFC-first for significant changes

The plugin uses its own RFC workflow for any change that involves design decisions, breaking changes, or new conventions that consumers will inherit. The shortlist:

- New skills with non-trivial behavior.
- Changes to the agent delegation table that shift defaults.
- Changes to `scripts/check-requirements.sh` (the session-start probe) — every consumer feels these.
- Changes to `docs/rfc-process.md`, which is the template `/sync` writes into every project.
- New best-practice entries that will ship via `/sync`.

The shortlist of things that are *not* RFC-worthy: typo fixes, dependency bumps, additions to `docs/BEST_PRACTICES.md` from `/best-practices-extract`, agent upstream-improvement pulls.

Use `/rfc-new <description>` to start. The skill walks the full Draft → Approved → Done lifecycle. See [`docs/rfc-process.md`](../rfc-process.md) for the canonical process.

## Plugin packaging

`.claude-plugin/plugin.json` declares the plugin's identity to Claude Code:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.2.0"
}
```

Skills under `skills/` and agents under `agents/` are auto-discovered — no array of paths is required in `plugin.json`. The plugin manifest is intentionally minimal: identity only, no behavior. Discovery does the rest.

`.claude-plugin/marketplace.json` declares the plugin within its own local marketplace, used by the project-local install pattern in `docs/CONTRIBUTING.md`. Both files are short and rarely change.

## Where to put best-practice learnings

After a session where you learned something non-obvious about working on the plugin, capture it:

- **`/best-practices-record <one-line lesson>`** — writes to `~/.claude/BEST_PRACTICES.md` (global, cross-project). Use for portable patterns like "always run the quality gate before opening a PR."
- **`/best-practices-extract`** at session end — surfaces session learnings to this repo's `docs/BEST_PRACTICES.md`. Use for plugin-specific patterns like "the `tools:` frontmatter field is silently ignored by Claude Code, so don't bother adding it."

The global pool flows into future projects via `/sync` after promotion through the plugin-local `best-practices-sync` skill.

## Related

- [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md) — narrow dev workflow ops.
- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) — system design and decisions.
- [`docs/rfc-process.md`](../rfc-process.md) — full RFC workflow.
- [Add a new skill](how-to/add-a-skill.md), [Add a new agent](how-to/add-an-agent.md) — task-oriented recipes.
