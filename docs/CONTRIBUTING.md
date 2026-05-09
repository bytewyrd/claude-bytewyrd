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
