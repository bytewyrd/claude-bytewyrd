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
cd claude-bytewyrd
```

## Plugin Setup (one-time)

This project is both the definition of the Bytewyrd workflow and a live instance of it. To test changes as you make them, install the plugin from your local checkout rather than from GitHub. This way you experience exactly what a consumer gets, with no separate test repo needed.

```bash
claude plugin marketplace add ./ --scope local
claude plugin install bytewyrd --scope local
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

Agent definitions in `agents/` originated from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) (MIT) and are now permanently locally owned. Each customized file carries an attribution comment near the top.

To pull in upstream improvements manually:

1. Find the file in the upstream repo at `categories/{category}/{agent-name}.md`.
2. Diff it against the local copy.
3. Apply changes you want to keep; skip changes that conflict with local customizations.
4. Commit with a message like `chore(agents): pull upstream improvements to {agent-name}`.

Never overwrite a local file wholesale — the upstream file won't have the attribution comment or any local customizations. Pull selectively.

To add a new agent not yet in the plugin, copy it from upstream into `agents/`, add the attribution comment after the frontmatter closing `---`, and commit.

## Sync

Run `/sync` in any project to set up or refresh the Claude Code environment — CLAUDE.md, BEST_PRACTICES.md, CI, RFC process, and all. The skill is idempotent: existing files are skipped, missing files are created, name/description are kept in sync. Re-run after the plugin updates to pick up new best-practice entries.


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
