# Claude Bytewyrd Workflow

Claude plugin containing a set of skills, agents, hooks and MCP servers for working on bytewyrd projects, or projects wanting to follow the same workflow.

## Toolchain

No language-specific toolchain detected. Add source code and re-run `/bootstrap` to pick up language tooling.

## File structure

```
claude-bytewyrd-workflow/
├── CLAUDE.md          — this file
├── docs/
│   ├── ARCHITECTURE.md        — system design (devs/agents)
│   ├── BEST_PRACTICES.md      — session learnings (devs/agents)
│   ├── CONTRIBUTING.md        — dev workflow (devs/agents)
│   ├── project-brief.md       — what/why/who (optional)
│   ├── guide/                 — expanded user documentation
│   └── rfcs/                  — RFC proposals
└── src/               — source code
```

## Agent delegation

| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Debugging | debugger |

## Tool Usage

### Exa — web search

Use `mcp__exa__web_search_exa` for any web lookup — error messages, release notes, package info, community discussions. It is the default, not a fallback. Use `mcp__exa__crawling_exa` to fetch a specific URL's content. Never say "I don't have access to current information" without trying Exa first.

### Context7 — library documentation

Mandatory before writing code that uses an external library, framework, or CLI tool. Use `mcp__plugin_context7_context7__resolve-library-id` then `mcp__plugin_context7_context7__query-docs`. Fall back to Exa if Context7 has no entry.

### Firefox MCP — visual verification

Required before reporting any UI or frontend change done. The dev server must already be running (never start long-running processes yourself — ask the user). Standard flow: `list_pages` → `screenshot_page` → interact with the feature → `list_console_messages` → `screenshot_page` to confirm result. Use `take_snapshot` for accessibility tree inspection.

## Conventions

Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
