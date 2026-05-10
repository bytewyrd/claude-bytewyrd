# Bytewyrd's Claude Plugin

> Opinionated Claude Code plugin for Bytewyrd projects — skills, agents, and RFC-driven workflow

## Why Bytewyrd's Claude Plugin

Setting up Claude Code consistently across projects takes significant manual effort — configuring skills, agent delegation patterns, MCP servers, and quality gates from scratch each time. Bytewyrd's Claude Plugin packages all of that into a single installable plugin with proven defaults, so any project can get the full setup instantly via `/sync`.

## How It Works

The plugin provides a curated collection of Claude Code skills (like `/sync`, `/rfc-new`, `/rfc-implement`), opinionated agent delegation tables, and MCP server permissions. Install it once, then run `/sync` in any project to get a fully-configured Claude Code environment — RFC process, best-practices tracking, CI, and all.

## Getting Started

Install the plugin and restart Claude Code:

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd --scope project
```

`--scope project` is recommended: it stores the marketplace registration in the project's `.claude/settings.json`, so anyone who checks out the repo will be prompted to install the plugin automatically — no per-machine setup needed.

If you want the plugin available across all your projects, use `--scope user`. Just be aware that the marketplace registration only exists on that machine: teammates or other machines won't be prompted to install, even if the plugin is listed in the project's `.claude/settings.json`.

Once installed, run `/bytewyrd:sync` in any project to bootstrap it with the full Claude Code setup — RFC process, best-practices tracking, CI, agent delegation, and all.

## Documentation

- [Contributing](docs/CONTRIBUTING.md) — dev setup, workflow, and conventions
- [Architecture](docs/ARCHITECTURE.md) — system design and key decisions
- [User Guide](docs/guide/) — detailed usage guides
- [RFC Process](docs/rfc-process.md) — how we propose and review changes

<!--
README audience: users — people who want to use or run this project.
Update this file when:
  - A real install method is available (replace the build-from-source notice)
  - The product's value proposition or top-level workflow changes
  - A new section is added to the Documentation list

Do NOT expand this into full documentation.
Detailed user docs go in docs/guide/.
Dev docs (workflow, architecture, learnings) go in docs/.
Build/test commands belong in CONTRIBUTING.md, not here.
-->
