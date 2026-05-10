# Claude Bytewyrd Workflow

> Opinionated Claude Code plugin for Bytewyrd projects — skills, agents, hooks, and RFC-driven workflow

## Why Claude Bytewyrd Workflow

Setting up Claude Code consistently across projects takes significant manual effort — configuring skills, agent delegation patterns, hooks, MCP servers, and quality gates from scratch each time. Claude Bytewyrd Workflow packages all of that into a single installable plugin with proven defaults, so any project can get the full setup instantly via `/sync`.

## How It Works

The plugin provides a curated collection of Claude Code skills (like `/sync`, `/rfc-new`, `/rfc-implement`), opinionated agent delegation tables, pre-push quality gate hooks, and MCP server permissions. Install it once, then run `/sync` in any project to get a fully-configured Claude Code environment — RFC process, best-practices tracking, CI, and all.

## Getting Started

Add the Bytewyrd marketplace to your Claude Code settings (`~/.claude/settings.json` for all projects, or `.claude/settings.json` for a single project):

```json
{
  "extraKnownMarketplaces": {
    "bytewyrd": {
      "source": { "source": "github", "repo": "bytewyrd/claude-bytewyrd" }
    }
  }
}
```

Then install and restart Claude Code:

```bash
claude plugin install bytewyrd
```

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
