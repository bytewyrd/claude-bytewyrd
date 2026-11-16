<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:5b6487db202b plugin=f46d66f6c5c8 -->
# claude-bytewyrd

Opinionated Claude Code plugin for Bytewyrd projects — skills, agents, and RFC-driven workflow

Guidance for people and coding agents working in this repository. Keep it under 100 lines; put detail in docs/.

## Project facts

- Tests: `uv run --no-sync tests/run.sh` (bats) and `uv run --no-sync pytest -q tests/py tests/e2e`, after `uv sync --locked`; both need Python 3.11 or newer.
- Lint: the checks and pinned tools are in [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#quality-gate).

## Workflow

This repository follows the bytewyrd workflow: https://github.com/bytewyrd/claude-bytewyrd
- Changes that need design start as an RFC in `docs/rfcs/`. Process: https://github.com/bytewyrd/claude-bytewyrd/blob/main/skills/rfc-process/references/rfc-process.md
- Working conventions: https://github.com/bytewyrd/claude-bytewyrd/blob/main/hooks/always-on-rules.json
- Project-specific learnings go in `docs/BEST_PRACTICES.md`.

## File structure

```
claude-bytewyrd/
├── AGENTS.md                    — this file
├── CLAUDE.md                    — Claude Code additions; imports AGENTS.md
├── LICENSE                      — Apache-2.0
├── THIRD_PARTY_NOTICES.md       — upstream MIT notices: agents derived from VoltAgent/awesome-claude-code-subagents, and the vendored PyYAML
├── pyproject.toml               — development only: the dev tools (pytest, PyYAML, ruff, mypy) and their settings
├── uv.lock                      — pins the dev tools, and the PyYAML sdist that scripts/_vendor/ is built from
├── agents/                      — subagent definitions (many originally from VoltAgent/awesome-claude-code-subagents, MIT; now locally owned)
├── skills/                      — exported plugin skills (auto-discovered by Claude Code), including
│   ├── scaffold/                — seeds AGENTS.md, CLAUDE.md, a PR template and CI, each only if missing
│   ├── drift/                   — read-only check of the seeded files against the templates, and of 0.2.x leftovers
│   ├── rfc-process/             — the RFC process, in references/
│   └── best-practices/          — curated practices per stack, in references/
├── hooks/                       — hooks.json, and always-on-rules.json, the conventions added to each session
├── scripts/
│   ├── bw                       — POSIX-sh launcher that runs every command
│   ├── bytewyrd/                — the Python package behind the commands, typed and checked with mypy --strict
│   └── _vendor/                 — PyYAML, vendored unmodified from the sdist that uv.lock pins
├── templates/scaffold/          — the seed templates scaffold renders and drift compares against
├── tests/                       — bats (scripts/), pytest (py/, e2e/) and fixtures/
├── .claude-plugin/
│   └── plugin.json              — plugin identity and metadata
├── .claude/skills/              — plugin-local maintenance skills (not exported to consumers)
├── .github/workflows/           — CI, the reusable lang-ci-<id>.yml workflows and the scaffold no-op fixture
├── docs/
│   ├── ARCHITECTURE.md          — system design (devs/agents)
│   ├── BEST_PRACTICES.md        — session learnings (devs/agents)
│   ├── CONTRIBUTING.md          — dev workflow (devs/agents)
│   ├── project-brief.md         — what/why/who (optional)
│   ├── guide/                   — expanded user documentation
│   └── rfcs/                    — RFC proposals
└── README.md
```
