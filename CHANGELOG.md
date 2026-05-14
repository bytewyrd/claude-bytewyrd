# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — 2026-05-14

A substantial step up from 0.1.0. The two headline changes are a complete audit of all 48 specialist agents and a series of RFC-driven improvements to the skill set — but there are significant additions throughout.

### Agent overhaul

All 48 agents were audited and reworked against a versioned quality rubric ([`docs/agent-audit-criteria.md`](docs/agent-audit-criteria.md)), replacing the original vendored definitions from `VoltAgent/awesome-claude-code-subagents` with locally-owned, Bytewyrd-style definitions. Each agent now has:

- A correct `tools:` list (the original set listed CLIs that Claude Code does not surface as named primitives, silently preventing agents from using Read/Write/Edit/Bash)
- An explicit model assignment (`haiku`, `sonnet`, or `opus`) sized to the task
- Structured `<example>` blocks in the `description` field for reliable dispatch
- Evidence-based operating guidance in the body

Two new specialist agents ship with this release: `claude-agent-author` (authors and audits agent definitions) and `docs-agent` (reviews and repairs `docs/guide/**`).

### New skills

| Skill | What it adds |
|-------|-------------|
| `/refactor` | Deliberate six-phase refactoring pass: pre-flight → analyze → characterization tests → plan → **approval gate** → apply → report. Spawns `refactoring-specialist` on Opus. |
| `/rfc-summary` | Active RFC overview — statuses, authors, ages at a glance. |
| `/docs-review` | Spawns `docs-agent` to audit and repair `docs/guide/**` for accuracy, coverage, and drift. |

### Skill improvements

- **`/sync`** — renamed from `/bootstrap`; RFC setup integrated (dropped separate `/rfc-install`); rewrote artifact application as a 3-way diff + interactive confirmation instead of skip-if-exists; `project-brief.md` now the single source of truth for project identity; Security and Workflow sections added to the installed CLAUDE.md template; fixed a bug where writes went to the main repo root instead of the active worktree
- **`/best-practices-extract`** — now auto-triggers on the `PreCompact` hook so learnings are captured before context windows compact; full triage-and-lift discipline applied (non-obvious, cross-project guidance only)
- **`/best-practices-record`** and **`/best-practices-extract`** — unified destination: both write to the same global pool; rationale headers added
- **`/best-practices-sync`** — Opus-powered conflict resolution when a candidate entry overlaps an existing one; auto-creates missing sections rather than failing
- **`/rfc-new`** — automatically removes the source braindump entry after promoting it to a full RFC
- All RFC skills — switched to fully-qualified `bytewyrd:` agent names for unambiguous dispatch

### Infrastructure

- **SessionStart hook** — per-session requirements check probing companion plugin state, MCP server config, and `git`/`gh` CLI availability; soft warnings for missing optional dependencies, hard exit on critical gaps only
- **PreCompact hook** — gates session end on best-practices extraction so learnings aren't lost to context compaction
- **bootstrap-manifest.json** — SHA-256 index of every artifact source managed by `/sync`; `build-manifest.sh` regenerates it after source edits
- **Pre-commit manifest-check hook** — fails commits when the manifest is stale; prevents phantom fast-forward updates for plugin consumers

### rfc-architect discipline

`rfc-architect` now enforces evidence-based research: it must fetch authoritative sources for every external claim before writing them into an RFC. Training knowledge is treated as a search query, not a source of truth.

### Plugin housekeeping

- Renamed plugin `bytewyrd-workflow` → `bytewyrd`; repository renamed to `claude-bytewyrd`
- Plugin directory structure aligned to the standard Claude Code plugin layout
- README redesigned with icon, cleaner install instructions, and generic-audience messaging
- Model selection guidance, evidence-based development principles, and sandbox container compatibility notes baked into the plugin `CLAUDE.md`

---

## [0.1.0] — 2026-05-09

Initial release. Core plugin scaffold: RFC workflow skills (`/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-consensus-review`, `/rfc-read-feedback`, `/rfc-update`), best-practices capture (`/best-practices-record`, `/best-practices-extract`, `/best-practices-sync`), `/git-branch-cleanup`, 46-agent set, and SessionStart hooks wiring.
