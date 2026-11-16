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
- Python 3.11 or newer, which runs the plugin's commands, the JSON helpers behind its skills, and its hooks through `scripts/bw`. It takes `$BYTEWYRD_PYTHON` when that is 3.11 or newer, else the first of `python3.15` … `python3.11` on `PATH`, else `python3` when it is 3.11 or newer.
- [jq](https://jqlang.org/), which the skills use to read the JSON helpers' output, and which one pytest case checks that output against.
- For development only, [mise](https://mise.jdx.dev/) 2026.11.1 or newer, which installs the pinned shellcheck, shfmt, actionlint and [uv](https://docs.astral.sh/uv/) 0.13.4. uv installs the Python dev tools. The plugin itself needs neither.

## Development Setup

```bash
git clone <repo-url>
cd claude-bytewyrd
mise install --locked                     # mise.lock covers linux-x64 and macos-arm64; elsewhere, run mise lock --platform <yours> first
uv sync --locked                          # the dev group, as uv.lock pins it, into .venv
```

`mise activate` puts the mise tools first on `PATH`. `pyproject.toml` and `uv.lock` are for development and CI only. The `dev` group pins pytest, PyYAML, ruff, mypy and types-PyYAML; only `uv lock` writes `uv.lock`, and `uv sync --locked` fails while the lock is stale. `uv run --no-sync <command>` runs a tool from `.venv` without syncing it first.

## Plugin Setup (one-time)

This project is both the definition of the Bytewyrd workflow and a live instance of it. To test changes as you make them, install the plugin from your local checkout rather than from GitHub. This way you experience exactly what a consumer gets, with no separate test repo needed.

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add ./ --scope local
claude plugin install bytewyrd --scope local
```

The first line registers the official marketplace, which the `claude plugin` commands never do on their own. The plugin's three dependencies, `github`, `context7` and `code-review`, install from there, and without them the plugin doesn't load.

Then restart Claude Code. The plugin is now active in all your sessions from this directory.

**Why local install over other approaches:**
Skills in `skills/` are not auto-loaded as slash commands by Claude Code — only `.claude/skills/` and installed plugins are loaded. Options considered: keeping a manual copy in `.claude/skills/` (friction, two copies to sync), symlinking (sandbox may not follow symlinks), or a sync script (must remember to run it). Local install is the only option that tests the exact consumer experience with no duplication.

**Edit cycle:** change anything in `skills/`, `agents/`, or `.claude-plugin/` → then restart Claude Code. The plugin reads directly from the local checkout, so no separate update command is needed. (`claude plugin update` only works for remote-hosted plugins — it will fail with "not found" for local installs.)

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

## Scaffold and drift

Run `/bytewyrd:scaffold` in any project to set up the Claude Code environment: `AGENTS.md`, a `CLAUDE.md` that imports it, a PR template and CI. Existing files are skipped and missing files are created, and nothing is written without `--apply`. After the plugin updates, run `/bytewyrd:drift` to check those files against the new templates; it never edits files.


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

CI (`.github/workflows/ci.yml`) runs eleven jobs on every pull request to `main`. Three of them are the checks the branch ruleset is meant to require:

- **`lint`**, with the dev tools from `uv.lock`:
  - The JSON manifests parse.
  - Agent and skill frontmatter is strict YAML.
  - The `lang-ci-<id>.yml` workflows pass their checks, each named by a comment in the step: one job per file, named by its language, each with a `lang-ci-fixture-<id>` job, SHA-pinned actions, only `contents: read`, and no secrets.
  - `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` match the sdist that `uv.lock` pins (`vendor-pyyaml.py --check`), and nothing but `load_frontmatter()` in `scripts/bytewyrd/frontmatter.py` loads YAML.
  - CI's shellcheck, shfmt, actionlint and uv versions match the pins in `mise.toml`.
  - The Python code passes `ruff check` and `ruff format --check`, and the `scripts/bytewyrd/` package passes `mypy --strict`, as `pyproject.toml` configures them. ruff's rules are its classic default set (`E4`, `E7`, `E9` and `F`) plus `I`, import sorting, and it skips Markdown and `scripts/_vendor/`. mypy asks for no annotations in the bootstrap, `scripts/bytewyrd/__main__.py`, which older Pythons must be able to parse.
  - The shell scripts have no shellcheck warnings and match the shfmt style in `.editorconfig`.
  - The workflows pass actionlint, which also runs shellcheck on their `run:` blocks.
  - Relative Markdown links resolve. This check runs last, so a broken link doesn't skip the others.
- **`validate`**: `claude plugin validate .` with the pinned Claude Code CLI.
- **`test`**: pytest over `tests/py` and `tests/e2e`, through `uv run --no-sync`. pytest also checks that the language ids, the `lang-ci-<id>.yml` files, their fixture jobs and the AGENTS.md template's tags agree.

The other eight are not required:

- **`lang-ci-fixture-<id>`**, five jobs, run each `lang-ci-<id>.yml` on its fixture in `tests/fixtures/lang-ci/<id>/`.
- **`compat`** runs pytest on Python 3.11 under Linux and on the latest 3.x under macOS.
- **`history`** runs pytest over `tests/py` at every commit of the pull request, and checks that `templates/scaffold/ci-caller.yml.tpl` pins a `main` commit that has every `lang-ci-<id>.yml`. Keep `tests/py` passing at every commit; `tests/e2e` runs only on the pull request's head, in `test` and `compat`.
- **`install-check`** installs the plugin into a temporary HOME from the checkout, and updates an install of `main` to the pull request's branch; any load error that `claude plugin list --json` reports fails it.

To run the same checks locally before pushing, after the [setup](#development-setup) above (`python3` must be 3.11 or newer, and `BYTEWYRD_PYTHON` can point `scripts/bw` at another interpreter):

```bash
uv run --no-sync pytest -q tests/py tests/e2e
uv run --no-sync ruff check
uv run --no-sync ruff format --check               # ruff format applies the fixes
uv run --no-sync mypy
python3 .github/scripts/vendor-pyyaml.py --check   # downloads the sdist that uv.lock pins
uv run --no-sync python .github/scripts/lint-frontmatter.py agents/*.md skills/*/SKILL.md .claude/skills/*/SKILL.md
python3 .github/scripts/check-links.py
SHELL_FILES=$(git ls-files -- scripts/bw)
shellcheck -x --source-path=SCRIPTDIR --severity=warning $SHELL_FILES
shfmt -d $SHELL_FILES   # shfmt -w applies the fixes
actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml
claude plugin validate .
```

## Updating the vendored PyYAML

`uv.lock` pins the PyYAML that `scripts/_vendor/yaml/` holds: its version, and its sdist's URL, sha256 and size. To move to another release, make these changes in one commit:

1. Edit the `pyyaml==` pin in the `dev` group of `pyproject.toml`.
2. Run `uv lock`.
3. Run `python3 .github/scripts/vendor-pyyaml.py`. It downloads the sdist that `uv.lock` now pins, checks its size and sha256, and rebuilds `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` from it.
4. Update the version in the PyYAML section of `THIRD_PARTY_NOTICES.md`.

`lint` runs `vendor-pyyaml.py --check`, which fails while the vendored copy differs from that sdist.

## Pull Request Process

1. Open a PR against `main`
2. CI must pass
3. The `main` ruleset requires no approval
4. Merge with a merge commit; never squash (rule 4 of the always-on rules in `hooks/always-on-rules.json`)

## RFC Process

Significant changes (new features, architectural changes, breaking changes) go through the RFC process. See the [`rfc-process` skill](../skills/rfc-process/references/rfc-process.md).
