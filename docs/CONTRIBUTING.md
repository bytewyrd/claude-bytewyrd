<!--
CONTRIBUTING scope: everything a developer needs to work on this project.
  - Prerequisites or tool versions change
  - Setup steps change
  - Dev workflow or branching conventions change
  - Quality gate commands change
  - PR or RFC process changes

Not here: what the project does or its architecture → README.md / docs/ARCHITECTURE.md
-->

# Contributing

## Prerequisites

- [git](https://git-scm.com/)

## Development Setup

```bash
git clone <repo-url>
cd claude-bytewyrd-workflow
```

## Plugin Setup (one-time)

This project is both the definition of the Bytewyrd workflow and a live instance of it. To test changes as you make them, install the plugin from your local checkout rather than from GitHub. This way you experience exactly what a consumer gets, with no separate test repo needed.

```bash
claude plugin marketplace add ./ --scope local
claude plugin install bytewyrd-workflow --scope local
```

Then restart Claude Code. The plugin is now active in all your sessions from this directory.

You can also clean up the stale `.claude/skills/` directory left over from initial setup:

```bash
rm -rf .claude/skills/
```

**Why local install over other approaches:**
Skills in `skills/` are not auto-loaded as slash commands by Claude Code — only `.claude/skills/` and installed plugins are loaded. Options considered: keeping a manual copy in `.claude/skills/` (friction, two copies to sync), symlinking (sandbox may not follow symlinks), or a sync script (must remember to run it). Local install is the only option that tests the exact consumer experience with no duplication.

**Edit cycle:** change anything in `skills/`, `agents/`, `.claude-plugin/`, or `rfc-process.md` → then restart Claude Code. The plugin reads directly from the local checkout, so no separate update command is needed. (`claude plugin update` only works for remote-hosted plugins — it will fail with "not found" for local installs.)

## Agents

Agent definitions in `agents/` are vendored from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents). The upstream repository organizes agents by category; this plugin flattens them into a single directory.

To pull upstream updates (new agents, changed definitions):

```bash
# inside the plugin checkout, invoke the skill:
/agents-update
```

The skill fetches the upstream file tree, shows what changed, and lets you approve updates before writing. It never commits — review the diff and commit manually. Run this periodically (e.g., when the upstream repo has new releases) to keep bundled agents current.

## Sync

Run `/sync` in any project to set up or refresh the Claude Code environment — CLAUDE.md, BEST_PRACTICES.md, CI, RFC process, and all. The skill is idempotent: existing files are skipped, missing files are created, name/description are kept in sync. Re-run after the plugin updates to pick up new best-practice entries.

To add a custom agent that is not in the upstream repo, create `agents/{name}.md` directly and commit it. Custom agents are not affected by `/agents-update` as long as their filename doesn't collide with an upstream agent.

## Development Workflow

All work happens on feature branches. Use the [git worktree](https://git-scm.com/docs/git-worktree) workflow for parallel tasks:

```bash
git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
# work here
```

See `CLAUDE.md` for agent delegation guidance.

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/) with a scope:

```
feat(scope): add new capability
fix(scope): correct wrong behavior
refactor(scope): restructure without changing behavior
docs(scope): update documentation
chore(scope): tooling, deps, config
```

## Quality Gate

No automated quality gate configured yet. Review changes manually before pushing.

## Pull Request Process

1. Open a PR against `main`
2. CI must pass
3. One approval required for merge
4. Squash merge to keep history clean

## RFC Process

Significant changes (new features, architectural changes, breaking changes) go through the RFC process. See [docs/rfc-process.md](docs/rfc-process.md).
