<div align="center">
  <h1>
    <img src="docs/icon.svg" alt="" width="56" height="56" align="absmiddle"/>
    &nbsp;claude-bytewyrd
  </h1>
  <p>Opinionated Claude Code workflow — RFC-driven development, specialist agents, and best-practices capture, ready to install in any project</p>
  <code>
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official
/bytewyrd:scaffold
  </code>
</div>

---

A Claude Code plugin that wires up a complete, opinionated development workflow — slash-command skills, 48 specialist agents, an RFC-driven design process, and cross-session best-practices tracking — into any project with a single command. Built by Bytewyrd for its own projects; the conventions are generic enough that any team can adopt them.

Install once. Run `/bytewyrd:scaffold`. Everything else follows.

## What you get

**17 skills** covering the full development lifecycle — from project setup to design review to deliberate refactoring. Fifteen are commands you run; `rfc-process` and `best-practices` are reference skills that Claude reads from the plugin when it needs them.

**48 specialist agents** — each with a focused role, curated tool list, and right-sized model. Backend, frontend, DevOps, database, security, and architecture. Claude delegates to the right one automatically.

**RFC-driven design.** `/rfc-new` researches and drafts. `/rfc-consensus-review` runs independent critic agents. `/rfc-approve` locks the design. `/rfc-implement` builds it. Architecture decisions leave a paper trail.

**Best-practices capture.** `/best-practices-record` saves a session learning. `/best-practices-extract` surfaces everything non-obvious from a session. Vetted learnings are promoted into the plugin's `best-practices` skill, which every project reads.

**Always-on rules.** A session-start hook adds five short workflow conventions to every session: evidence before assertions, the user makes the decisions, RFCs for design, Conventional Commits with merge-only integration, and the user starts long-running processes.

## Workflow

```
 Bootstrap             Design                        Ship
 ─────────────         ────────────────────────      ────────────────────
 /bytewyrd:scaffold    /rfc-new <idea>               /rfc-implement
 /bytewyrd:drift       /rfc-braindump <quick idea>
                       /rfc-read-feedback            Spawns a
 Seeds, once:          /rfc-consensus-review         feature-engineer
  · AGENTS.md          /rfc-approve                  with the RFC
  · CLAUDE.md                                        as its spec.
  · PR template
  · CI workflow

 Between sessions                   Maintenance
 ────────────────────────────────   ───────────────────────────────
 /best-practices-record <note>      /refactor <scope>
 /best-practices-extract            /git-branch-cleanup
```

## Why

**Consistency.** Every project that runs `/bytewyrd:scaffold` gets the same `AGENTS.md`, `CLAUDE.md`, PR template, and CI workflow, and every project reads the same RFC process and best practices from the plugin's skills. `/bytewyrd:drift` reports when a seeded file falls behind the plugin's templates. No copy-paste, no configuration drift.

**Design before build.** RFCs are authored by `rfc-architect` (Opus), reviewed by independent critic agents, and approved by a human before any implementation starts. Architectural decisions are explicit, documented, and auditable.

**Learning compounds.** Best practices captured in one project flow to future ones through the plugin's `best-practices` skill. The workflow gets smarter over time without manual curation.

**Right model for each task.** Agent definitions specify the cheapest model that fits the task — `haiku` for lookups, `sonnet` for implementation, `opus` for architecture. Cost is a first-class concern.

**Promote-through-production.** This repository is a live instance of its own workflow. Changes are validated here before being distributed to other projects. You get patterns that have run in anger, not designed in theory.

## Getting started

```bash
# Add the official marketplace first (the claude plugin commands never register it),
# then bytewyrd's, then install the plugin and its three dependencies (user scope by default)
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official

# Or: project scope. This records the plugin in the repository's .claude/settings.json,
# but each collaborator still runs the command once per clone
claude plugin install bytewyrd@bytewyrd --scope project
```

The plugin's commands and hooks need Python 3.11 or newer, on your `PATH` or in `BYTEWYRD_PYTHON`. They no longer need bash. See [docs/guide/installation.md](docs/guide/installation.md) for the requirements and for upgrading from 0.2.x, and its [team-wide enforcement](docs/guide/installation.md#team-wide-enforcement-optional) section for setting up a repository for a team.

Then in any Claude Code session:

```
/bytewyrd:scaffold           # a dry run: lists what it would create
/bytewyrd:scaffold --apply   # writes it
```

`AGENTS.md`, a `CLAUDE.md` that imports it, a PR template, and a CI workflow are created, each only if missing. `/bytewyrd:drift` later checks them against the plugin's current templates.

## Skills

| Skill | What it does |
|-------|-------------|
| `/scaffold` | Seed a repository with `AGENTS.md`, `CLAUDE.md`, a PR template, and a CI workflow, each only if missing (dry run unless `--apply`) |
| `/drift` | Read-only check of the seeded files against the plugin's current templates, plus leftover 0.2.x artifacts, with one-line fixes |
| `/rfc-new` | Research, draft, and multi-agent-review a new RFC |
| `/rfc-braindump` | Capture a quick RFC candidate without full authoring |
| `/rfc-approve` | Mark an RFC Approved and commit |
| `/rfc-implement` | Implement an Approved RFC via a `feature-engineer` agent |
| `/rfc-read-feedback` | Incorporate inline `FEEDBACK:` comments from reviewers |
| `/rfc-consensus-review` | Run independent critic agents, surface gaps |
| `/rfc-summary` | List active RFCs (Draft and Approved) at a glance |
| `/rfc-drop` | Drop an RFC and record the reason |
| `/rfc-process` | The RFC process itself, read by Claude from the plugin; a `docs/rfcs/` directory opts a repository in |
| `/best-practices` | Curated practices per stack, read by Claude from the plugin when it designs, writes, or reviews code |
| `/best-practices-record` | Capture a session learning |
| `/best-practices-extract` | Extract all non-obvious learnings from a session |
| `/docs-review` | Audit `docs/guide/**` and `README.md` for drift |
| `/refactor` | Deliberate phased refactor (Opus, with approval gate) |
| `/git-branch-cleanup` | Prune stale branches and associated worktrees |

## Agents

48 specialist agents across every engineering domain. Claude picks the right one automatically based on the task; you can also request one by name.

<details>
<summary>Full agent list</summary>

| Agent | Role |
|-------|------|
| `rfc-architect` | RFC authoring, research, design review |
| `feature-engineer` | RFC-driven feature implementation, TDD |
| `code-reviewer` | Security, correctness, conventions |
| `refactoring-specialist` | Safe phased refactoring with characterization tests |
| `debugger` | Root cause analysis, systematic diagnosis |
| `backend-developer` | APIs, microservices, server-side logic |
| `frontend-developer` | React, UI components, accessibility |
| `fullstack-developer` | End-to-end feature ownership |
| `devops-engineer` | CI/CD, containers, infrastructure automation |
| `cloud-architect` | Multi-cloud strategy, scalable systems |
| `kubernetes-specialist` | Cluster management, production deployments |
| `database-administrator` | PostgreSQL, MySQL, MongoDB, Redis — operations |
| `database-optimizer` | Query tuning, index strategy, execution plans |
| `security-engineer` | DevSecOps, vulnerability management |
| `performance-engineer` | Profiling, load testing, bottleneck analysis |
| `sre-engineer` | SLOs, reliability engineering, toil reduction |
| `documentation-writer` | Developer docs, API references, guides |
| `typescript-pro` | Advanced type system, full-stack TS |
| `python-pro` | Modern Python 3.11+, async, type safety |
| `rust-engineer` | Systems programming, memory safety |
| `golang-pro` | Idiomatic Go, high-performance services |
| `rails-expert` | Rails 7+, Hotwire, convention-over-configuration |
| `nextjs-developer` | Next.js 14+, App Router, server components |
| `react-specialist` | React 18+, advanced hooks, performance |
| `llm-architect` | LLM system design, fine-tuning, serving |
| `mcp-developer` | Model Context Protocol servers and clients |
| `prompt-engineer` | Prompt architecture, evaluation, optimization |
| + 21 more | See [`agents/`](agents/) |

</details>

## Documentation

- [User Guide](docs/guide/index.md) — tutorials, how-to guides, reference, and contributor docs
- [Installation](docs/guide/installation.md) — how to install and configure the plugin
- [Architecture](docs/ARCHITECTURE.md) — how the plugin is built and key design decisions
- [Contributing](docs/CONTRIBUTING.md) — development workflow and conventions
- [RFC Process](skills/rfc-process/references/rfc-process.md) — the design-first workflow (the `rfc-process` skill)
- [Best Practices](docs/BEST_PRACTICES.md) — accumulated session learnings

## License

This plugin is licensed under the [Apache License 2.0](LICENSE). Material derived from third-party projects keeps its own license; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

<!--
README audience: users — people who want to use or run this project.
Update this file when:
  - The install command changes (it is currently `claude plugin install`)
  - The product's value proposition or top-level workflow changes
  - Skills are added or removed
  - A new section is added to the Documentation list

Do NOT expand this into full documentation.
Detailed user docs go in docs/guide/.
Dev docs (workflow, architecture, learnings) go in docs/.
Build/test commands belong in CONTRIBUTING.md, not here.
-->
