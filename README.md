<div align="center">
  <img src="docs/icon.svg" alt="" width="96" height="96"/>
  <h1>claude-bytewyrd</h1>
  <p>Opinionated Claude Code workflow for Bytewyrd projects and teams</p>
  <code>claude plugin marketplace add bytewyrd/claude-bytewyrd --scope project</code>
</div>

---

A Claude Code plugin that wires up the full Bytewyrd development workflow — slash-command skills, 50+ specialist agents, an RFC-driven design process, and cross-session best-practices tracking — into any project with a single command.

Install once. Run `/sync`. Everything else follows.

## What you get

**13 slash-command skills** covering the full development lifecycle — from project bootstrap to design review to deliberate refactoring.

**50+ specialist agents** — each with a focused role, curated tool list, and right-sized model. Backend, frontend, DevOps, database, security, and architecture. Claude delegates to the right one automatically.

**RFC-driven design.** `/rfc-new` researches and drafts. `/rfc-consensus-review` runs independent critic agents. `/rfc-approve` locks the design. `/rfc-implement` builds it. Architecture decisions leave a paper trail.

**Best-practices capture.** `/best-practices-record` saves a session learning. `/best-practices-extract` surfaces everything non-obvious from a session. Learnings flow from one project to future projects through `/sync`.

**Evidence-based operating rules** baked into every agent: gather symptoms before diagnosing, distinguish hypothesis from conclusion, look up external APIs before asserting behavior.

## Workflow

```
 Bootstrap             Design                        Ship
 ─────────────         ────────────────────────      ────────────────────
 /sync                 /rfc-new <idea>               /rfc-implement
                       /rfc-braindump <quick idea>
 Sets up:              /rfc-read-feedback            Spawns a
  · RFC docs           /rfc-consensus-review         feature-engineer
  · agent table        /rfc-approve                  with the RFC
  · CI checks                                        as its spec.
  · best-practices
    infrastructure

 Between sessions                   Maintenance
 ────────────────────────────────   ───────────────────────────────
 /best-practices-record <note>      /refactor <scope>
 /best-practices-extract            /git-branch-cleanup
```

## Why

**Consistency.** Every project that runs `/sync` gets the same RFC process, agent delegation table, CI gates, and best-practices infrastructure. No copy-paste, no configuration drift.

**Design before build.** RFCs are authored by `rfc-architect` (Opus), reviewed by independent critic agents, and approved by a human before any implementation starts. Architectural decisions are explicit, documented, and auditable.

**Learning compounds.** Best practices captured in one project flow to future ones via the next `/sync`. The workflow gets smarter over time without manual curation.

**Right model for each task.** Agent definitions specify the cheapest model that fits the task — `haiku` for lookups, `sonnet` for implementation, `opus` for architecture. Cost is a first-class concern.

**Promote-through-production.** This repository is a live instance of its own workflow. Changes are validated here before being distributed to other projects. You get patterns that have run in anger, not designed in theory.

## Getting started

```bash
# Recommended: scoped to the project so teammates get prompted to install automatically
claude plugin marketplace add bytewyrd/claude-bytewyrd --scope project

# Or: install for your user globally across all projects
claude plugin marketplace add bytewyrd/claude-bytewyrd --scope user
```

Then in any Claude Code session:

```
/bytewyrd:sync
```

RFC docs, best-practices file, agent delegation table, and CI are set up in one run.

## Skills

| Skill | What it does |
|-------|-------------|
| `/sync` | Bootstrap or refresh a project with the full Bytewyrd setup |
| `/rfc-new` | Research, draft, and multi-agent-review a new RFC |
| `/rfc-braindump` | Capture a quick RFC candidate without full authoring |
| `/rfc-approve` | Mark an RFC Approved and commit |
| `/rfc-implement` | Implement an Approved RFC via a `feature-engineer` agent |
| `/rfc-update` | Update a Draft RFC with new findings |
| `/rfc-read-feedback` | Incorporate inline `FEEDBACK:` comments from reviewers |
| `/rfc-consensus-review` | Run independent critic agents, surface gaps |
| `/rfc-drop` | Drop an RFC and record the reason |
| `/best-practices-record` | Capture a session learning |
| `/best-practices-extract` | Extract all non-obvious learnings from a session |
| `/refactor` | Deliberate phased refactor (Opus, with approval gate) |
| `/git-branch-cleanup` | Prune stale branches and associated worktrees |

## Agents

50+ specialist agents across every engineering domain. Claude picks the right one automatically based on the task; you can also request one by name.

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
| + 25 more | See [`agents/`](agents/) |

</details>

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — how the plugin is built and key design decisions
- [Contributing](docs/CONTRIBUTING.md) — development workflow and conventions
- [RFC Process](docs/rfc-process.md) — the design-first workflow (installed by `/sync`)
- [Best Practices](docs/BEST_PRACTICES.md) — accumulated session learnings

---

<div align="center">
  <code>claude plugin marketplace add bytewyrd/claude-bytewyrd --scope project</code>
</div>

<!--
README audience: users — people who want to use or run this project.
Update this file when:
  - A real install method is available (replace the marketplace command if it changes)
  - The product's value proposition or top-level workflow changes
  - Skills are added or removed
  - A new section is added to the Documentation list

Do NOT expand this into full documentation.
Detailed user docs go in docs/guide/.
Dev docs (workflow, architecture, learnings) go in docs/.
Build/test commands belong in CONTRIBUTING.md, not here.
-->
