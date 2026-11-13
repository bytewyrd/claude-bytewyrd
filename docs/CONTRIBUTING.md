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

Most agent definitions in `agents/` originated from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) (MIT) and are now permanently locally owned. Attribution lives in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), which carries the upstream license text and lists the agents that still contain substantial upstream text. The agent files themselves generally carry no attribution comment.

To pull in upstream improvements manually:

1. Find the file in the upstream repo at `categories/{category}/{agent-name}.md`.
2. Diff it against the local copy.
3. Apply changes you want to keep; skip changes that conflict with local customizations.
4. Make sure the agent has a row in the table in `THIRD_PARTY_NOTICES.md`.
5. Commit with a message like `chore(agents): pull upstream improvements to {agent-name}`.

Never overwrite a local file wholesale — the upstream file won't have any local customizations. Pull selectively.

To add a new agent not yet in the plugin, copy it from upstream into `agents/`, add a row for it to the table in `THIRD_PARTY_NOTICES.md`, and commit.

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

CI (`.github/workflows/ci.yml`) runs three jobs on every pull request to `main`. Their names are the checks the branch ruleset requires:

- **`lint`**:
  - The JSON manifests parse, and `bootstrap-manifest.json` is current.
  - Agent and skill frontmatter is strict YAML.
  - Relative Markdown links resolve.
  - The shell scripts have no shellcheck warnings and match the shfmt style in `.editorconfig`.
- **`validate`**: `claude plugin validate .` with the pinned Claude Code CLI.
- **`test`**: the bats suite.

To run the same checks locally before pushing (shellcheck, shfmt, and PyYAML must be installed):

```bash
git submodule update --init --recursive   # once: the bats libraries
tests/run.sh
scripts/build-manifest.sh --check
python3 .github/scripts/lint-frontmatter.py agents/*.md skills/*/SKILL.md .claude/skills/*/SKILL.md
python3 .github/scripts/check-links.py
SHELL_FILES=$(git ls-files -- 'scripts/*.sh' 'scripts/_lib/*.bash' 'hooks/pre-commit/*.sh' tests/run.sh tests/scripts/helpers.bash)
shellcheck -x --source-path=SCRIPTDIR --severity=warning $SHELL_FILES
shfmt -d $SHELL_FILES   # shfmt -w applies the fixes
claude plugin validate .
```

## Pull Request Process

1. Open a PR against `main`
2. CI must pass
3. One approval required for merge
4. Merge with a merge commit; never squash (see the Git section of `CLAUDE.md`)

## RFC Process

Significant changes (new features, architectural changes, breaking changes) go through the RFC process. See [docs/rfc-process.md](rfc-process.md).
