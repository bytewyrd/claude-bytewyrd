# Architecture

<!--
ARCHITECTURE scope: system design reference — the "how and why it's built this way."
  - A component is added, renamed, or removed
  - A significant design decision is made or reversed (update the Decisions table)
  - Data flow between components changes
  - A new external dependency or service is introduced

Not here: setup/quickstart                   → README.md
          dev workflow, commit conventions   → docs/CONTRIBUTING.md
          non-obvious session learnings      → docs/BEST_PRACTICES.md
-->

## Overview

Bytewyrd's Claude Plugin bundles skills and agents for Bytewyrd projects. It is both a plugin (distributed via the Claude Code plugin system) and a live dogfood of itself — the plugin's own checkout uses the plugin's skills and conventions. Consumers install it via `claude plugin install bytewyrd` and get the full skill and agent set immediately; no per-project configuration is required beyond the install.

## Components

### Skills (`skills/`)

**Purpose:** Slash-command skills invokable in any Claude Code session by users of this plugin.
**Location:** `skills/`
**Key interfaces:** Each skill is a directory containing `SKILL.md`. Claude Code's plugin system discovers skills in the plugin's `skills/` directory, which `.claude-plugin/plugin.json` doesn't list, and exposes them as `/skill-name` commands.

Skills are organized by noun-first naming convention (e.g., `best-practices-extract`, `rfc-new`). Related skills share a common noun prefix and sort together in any alphabetical listing.

Two skills hold reference content in a `references/` directory, read at runtime so that repositories keep no copies: `rfc-process` (the RFC process) and `best-practices` (curated practices per stack). `scaffold` and `drift` are thin wrappers that run `scripts/bw`.

### Agents (`agents/`)

**Purpose:** Specialized subagent definitions that Claude Code can spawn as subtasks. Agents are role-specific — each carries a focused system prompt, a tool allow-list, and a model preference.
**Location:** `agents/`
**Key interfaces:** Each agent is a single `.md` file with YAML frontmatter (`name`, `description`, optional `model`). Claude Code discovers agents in this directory and makes them available as subagent targets.

**Source:** Agent definitions originated from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) (MIT) and are now permanently locally owned. The upstream repository is organized by category (`categories/{category}/{agent-name}.md`); this plugin flattens them into a single `agents/` directory for simpler discovery. Attribution lives in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), which carries the upstream MIT license text and lists the agents that still contain substantial upstream text; the agent files themselves generally carry no attribution comment. Future upstream improvements are pulled manually, file by file, when a maintainer judges them worth applying.

### Plugin-local skills (`.claude/skills/`)

**Purpose:** Skills that are only meaningful inside this plugin's own checkout — maintenance and meta-operations that consumers would never need.
**Location:** `.claude/skills/`
**Key interfaces:** The same `SKILL.md` format as `skills/`. The plugin system loads skills only from the plugin's `skills/` directory, so consumers never see these; Claude Code loads them as project skills when it runs in this repository.

Current plugin-local skills:
- `best-practices-sync` — promotes entries from the global `~/.claude/BEST_PRACTICES.md` into `skills/best-practices/references/<stack>.md`

### Plugin manifest (`.claude-plugin/`)

**Purpose:** Defines the plugin's identity. This is the entrypoint the Claude Code plugin system reads; skills and agents are auto-discovered from their respective root directories.
**Location:** `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json` for the marketplace that lists the plugin.
**Key behavior:** `plugin.json` declares `github`, `context7` and `code-review` from `claude-plugins-official` as `dependencies` (`code-review` at `^1.0.1`, the only one that publishes a version), and `marketplace.json` allows that marketplace with `allowCrossMarketplaceDependenciesOn`. Installing bytewyrd installs them, and Claude Code doesn't load bytewyrd while one is missing or disabled.

### Hooks (`hooks/`)

**Purpose:** Automation that Claude Code runs on session lifecycle events, in every project where the plugin is enabled: the always-on rules at session start, and the `/docs-review` reminders after a `feature-engineer` subagent finishes.
**Location:** `hooks/hooks.json` (hook declarations) and `hooks/always-on-rules.json` (the rules). The two hooks that need Python run `scripts/bw`.
**Key behavior:**
- `SessionStart` with matcher `startup|clear|compact` runs `cat` on `hooks/always-on-rules.json`, whose `hookSpecificOutput.additionalContext` adds five workflow conventions to Claude's context. They are written as factual statements, and CI caps them at 2,000 characters.
- `SubagentStop` for `feature-engineer` echoes a reminder to ask the user to run `/docs-review`, and runs `bw state-touch last-feature-engineer-stop`. `SessionStart` with matcher `compact` runs `bw compact-reminder`, which repeats the reminder while that sentinel is under a day old.
- Every hook exits 0: the `bw` commands end in `|| true`, so without Python 3.11 or newer they print one stderr line and fail nothing. Hooks run outside the sandbox, so `state-touch`, the only writer into `.bytewyrd/`, refuses symlinks.

### Commands (`scripts/bw`, `scripts/bytewyrd/`, `scripts/_vendor/`, `templates/scaffold/`)

**Purpose:** The plugin's deterministic commands. `scaffold` seeds a repository, `drift` checks it, `state-touch` is the only writer into `.bytewyrd/`, and `compact-reminder` backs the compact hook. The nine JSON helpers, `rfc-*` and `tool-probe`, do the scripted steps of the RFC skills and `/best-practices-extract`. Skills, hooks, tests and CI run each one as `sh scripts/bw NAME`.
**Location:** `scripts/bw`, a POSIX-sh launcher; `scripts/bytewyrd/`, the Python package behind it (layout below); `scripts/_vendor/yaml/`, an unmodified copy of the PyYAML release that `uv.lock` pins; `templates/scaffold/*.tpl`, the seed templates. `tests/py/` pins the command-line contracts, running `scripts/bw` and the hook commands as child processes, and covers the modules and the vendored copy. `tests/e2e/test_consumer_sim.py` runs scaffold and drift end to end, as a consumer repository sees them.
**Key behavior:**
- The launcher runs Python 3.11 or newer: `$BYTEWYRD_PYTHON` when it reports 3.11 or newer, else the first of `python3.15` … `python3.11` on `PATH`, else `python3` when it reports 3.11 or newer. It starts it with `-I -S -B`, so `PYTHON*` variables, a virtualenv's `.pth` files and bytecode stay out. Without such an interpreter, `scaffold`, `drift` and the hook commands exit 1 and the JSON helpers exit 2, except that `state-touch precompact-extraction-done` still writes its sentinel in plain sh.
- The plugin root is the parent of `scripts/`, found from `__file__`. No command reads `CLAUDE_PLUGIN_ROOT`, which commands run through the Bash tool don't get.
- `scaffold` writes at most four files, at the top of the work tree and only where none exists, each stamped on line 1 with its template's hash and the plugin commit. It is a dry run unless `--apply`. `drift` never writes, and exits 0 when clean, 2 on drift and 1 when it can't run.
- Each JSON helper prints one JSON object on stdout, which the skills read with jq, and exits 0, or 2 on an error. Exit 1 means no RFC found for `rfc-resolve`, no matching entry for `rfc-braindump-remove`, and a missing or logged-out tool for `tool-probe`.
- Only `load_frontmatter()` in `frontmatter.py` parses YAML, the frontmatter of an RFC, with the vendored PyYAML and a loader that keeps every plain scalar a string and refuses aliases.

**Package layout.** `scripts/bytewyrd/` holds the bootstrap, seven shared modules, and one module per command in `commands/`. Every module but the bootstrap is typed and checked with `mypy --strict`. The shared modules never exit the process: each command's `main(argv)` returns its exit code.

| Module | Role |
|---|---|
| `__main__.py` | The bootstrap that the launcher runs. It checks the interpreter, then imports `bytewyrd.commands.<name>` and exits with its `main(argv)`. It has no annotations or newer syntax, so an older Python that runs it still reaches the version check |
| `cli` | `BwError`, the failure a command reports as one line; the argument parser, whose usage errors exit 1; and `quote()` and `describe()`, which make repo-derived strings and exceptions safe to print |
| `git` | The work tree and its index: the top level, the project name, the index entries, a blob's bytes, and whether the tree is dirty |
| `fs` | Work-tree files: whether a seed target exists, a symlinked directory on its path, creating it without following a symlink, and reading a file as drift does; plus the JSON helpers' line-splitting and working-directory helpers |
| `detect` | Detection, for scaffold and drift: a component for each tracked (language, directory) that gets a CI job, and a reason and a fix line for each manifest that gets none |
| `seed` | The seed targets and their templates, `render()`, the stamps and their hashes, the plugin commit, and the checks for an existing PR template, workflow or `@AGENTS.md` line |
| `frontmatter` | `load_frontmatter()` and its loader. It is the only module that imports `yaml`, at module level, so a command that parses no frontmatter never loads it |
| `jsonout` | The JSON helpers' jq-compatible output, their `json_main()`, and the emitters for errors and tool probes |
| `commands/<name>.py` | One module per command: `scaffold`, `drift`, `state_touch`, `compact_reminder` and the nine JSON helpers |

### CI (`.github/workflows/ci.yml`, `.github/scripts/`)

**Purpose:** Gates merges to `main`. Three of its jobs, `lint`, `validate`, and `test`, are the checks the branch ruleset is meant to require.
**Location:** `.github/workflows/ci.yml`. The Python lint helpers `lint-frontmatter.py` and `check-links.py` live in `.github/scripts/` and are tested by `tests/py/test_ci_lint.py`; `vendor-pyyaml.py`, next to them, is tested by `tests/py/test_vendor.py`. `.github/workflows/lang-ci-<id>.yml` (go, js, python, ruby, rust) are reusable workflows, one per language, which consumer repositories' CI calls by commit SHA (RFC `2026-11-09-scaffold-and-drift`). `.github/actionlint.yaml` configures actionlint.
**Key behavior:**
- `lint` installs the dev tools from `uv.lock`, then checks the JSON manifests, strict-YAML agent and skill frontmatter, the `lang-ci-<id>.yml` workflows' pins, permissions and fixtures, the vendored PyYAML against the sdist that `uv.lock` pins, that nothing but `load_frontmatter()` loads YAML, the lint tools' and uv's versions against `mise.toml`, ruff's lint and format checks, `mypy --strict` on the package, shellcheck warnings, shfmt formatting (style in `.editorconfig`), actionlint on every workflow, and, last, relative Markdown links.
- `validate` runs `claude plugin validate .` with a pinned Claude Code CLI.
- `test` runs pytest over `tests/py` and `tests/e2e`, with the dev tools from `uv.lock`.
- `lang-ci-fixture-<id>` runs each `lang-ci-<id>.yml` on its fixture in `tests/fixtures/lang-ci/<id>/`.
- `compat` runs pytest on Python 3.11 under Linux and on the latest 3.x under macOS.
- `history` runs pytest over `tests/py` at every commit of a pull request, and checks that the scaffold caller template pins a `main` commit that has every `lang-ci-<id>.yml`.
- `install-check` installs the plugin into a temporary HOME from the checkout, and updates an install of `main` to the pull request's branch, failing on any load error that `claude plugin list --json` reports.

Actions are pinned to commit SHAs. shellcheck, shfmt and actionlint are pinned releases verified by sha256, and `mise.toml` and `mise.lock` pin the same versions for local runs. `astral-sh/setup-uv` installs uv at `UV_VERSION`, which `lint` checks against `mise.toml`. Jobs run on `ubuntu-26.04` instead of `ubuntu-latest`; GitHub still updates that image weekly. The `lang-ci-<id>.yml` jobs run on `ubuntu-latest`, as they do for the repositories that call them.

### Development tools (`pyproject.toml`, `uv.lock`, `mise.toml`)

**Purpose:** The tools that test, lint and type-check the plugin, for contributors and CI only. Users need none of them: the plugin runs on Python 3.11 or newer with the standard library and `scripts/_vendor/`, and installs nothing.
**Location:** `pyproject.toml` and `uv.lock` for the Python tools; `mise.toml` and `mise.lock` for uv, shellcheck, shfmt and actionlint.
**Key behavior:**
- `pyproject.toml` has a `[project]` table, so that `uv lock` records `requires-python = ">=3.11"`, and sets `package = false`, so that uv never builds or installs the project. Its one `dev` group pins pytest, PyYAML, ruff, mypy and types-PyYAML, and it holds the pytest, ruff and mypy settings. The `[project]` table also makes detection find a root `python` component in this repository.
- `uv.lock` pins every tool by hash, and only `uv lock` writes it. Contributors and CI run `uv sync --locked`, which fails on a stale lock, then each tool with `uv run --no-sync`.
- mise pins uv 0.13.4 next to the lint tools, and CI checks its own uv version against that pin.
- ruff lints and formats the repository's Python, but not `scripts/_vendor/` or Markdown. mypy runs `--strict` on `scripts/bytewyrd/`.
- `uv.lock` is also the source of truth for the vendored PyYAML. `.github/scripts/vendor-pyyaml.py`, standard library only, rebuilds `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` from the sdist that `uv.lock` records, after checking its size and sha256, and `lint` runs its `--check`.

## Data Flow

Skills → executed by Claude Code in-session. No persistent side effects unless the skill writes files.

Agents → spawned as subtask processes. Receive a goal and a tool allow-list from the calling skill; return a result message.

`SessionStart` hook (`startup|clear|compact`) → `hooks/always-on-rules.json` → the five conventions, as `additionalContext`.

`SubagentStop` hook (`feature-engineer`) → `bw state-touch` → `.bytewyrd/last-feature-engineer-stop` → `SessionStart` hook (`compact`) → `bw compact-reminder` → the `/docs-review` reminder. `/docs-review` removes the sentinel with `bw state-touch --rm`.

`/bytewyrd:scaffold` (skill) → `bw scaffold` → `templates/scaffold/*.tpl` → `AGENTS.md`, `CLAUDE.md`, `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` in the consumer repository, each only if missing.

`/bytewyrd:drift` (skill) → `bw drift` → a read-only report comparing those files with the current templates, plus the 0.2.x leftovers, each with a one-line fix.

`rfc-process` and `best-practices` (skills) → read from the plugin at runtime. A scaffolded `AGENTS.md` links to the RFC process and the always-on rules for contributors without the plugin.

`best-practices-extract` (skill) → `docs/BEST_PRACTICES.md` (project file); entries the user marks as generalizable → optional Promotion Step → `~/.claude/BEST_PRACTICES.md` (user-global file).

`best-practices-record` (skill) → `~/.claude/BEST_PRACTICES.md` (user-global file).

`~/.claude/BEST_PRACTICES.md` → `best-practices-sync` (plugin-local skill) → `skills/best-practices/references/<stack>.md` → the `best-practices` skill in consumer projects, read at runtime.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent source | Permanently local copies in `agents/`, originally from awesome-claude-code-subagents (MIT) | Consumers get agents without a network call at install time; local ownership prevents silent upstream clobber of customizations; upstream improvements pulled manually when desired |
| Skill naming | Noun-first (`rfc-new`, `best-practices-extract`) | Groups related skills alphabetically; matches `rfc-*` family already established |
| Plugin-local vs exported skills | Plugin-local in `.claude/skills/`, exported in `skills/` | Keeps maintenance tools out of consumer installs: the plugin system loads skills only from `skills/` |
| Best-practices flow | Record → global file → manual sync into the `best-practices` skill's references | Puts human review between personal capture and distribution; prevents one user's project-specific notes from polluting the practices that every project reads |
| RFC process distribution | The `rfc-process` skill, read from the plugin at runtime; a `docs/rfcs/` directory opts a repository in | No install or update step: repositories keep no copy, since per-repository copies drift from the plugin's (RFC `2026-11-09-scaffold-and-drift`, Options) |
| Script language | Python 3.11 or newer with the standard library and a vendored pure-Python PyYAML 6.0.3, behind the POSIX-sh launcher `scripts/bw`; nothing installs at run time | The 0.2.x sync scripts already needed Python 3.11 for `tomllib`, while the bash scripts needed bash 4, jq and GNU/BSD workarounds, and Claude Code installs only npm and Bun packages for a plugin (RFC `2026-11-09-scaffold-and-drift`, Language policy) |
| Repository seeding | `scaffold` seeds at most four stamped files once; `drift` checks them, read-only, with CI exit codes | Merging plugin content into consumer files on every run caused the 0.2.x defects; a seeded file belongs to the project, and drift reports what changed instead of rewriting it |
| Always-on conventions | Five factual statements in `hooks/always-on-rules.json`, emitted as SessionStart `additionalContext` and capped at 2,000 characters in CI | A small always-on context serves better than a large one, and skills alone often go uninvoked, so the rules name the skills that hold the detail |
| Companion plugins | `github`, `context7` and `code-review` are hard `dependencies` | Installing bytewyrd installs them; the cost is that bytewyrd doesn't load while one is missing or disabled |
| Plugin installation scope | User scope only (`~/.claude/settings.json`); `/bytewyrd:scaffold` does not write `enabledPlugins` or `extraKnownMarketplaces` to project settings | See note below |

### Plugin installation scope — extended note

The plugin is installed once per developer at user scope. `/bytewyrd:scaffold` explicitly does not write `bytewyrd@bytewyrd` to `enabledPlugins` or `bytewyrd` to `extraKnownMarketplaces` in the project's `.claude/settings.json`.

**Why not project scope?**

The motivation for user-scope-first is maintenance. If every `/bytewyrd:scaffold`-seeded project carries `enabledPlugins` + `extraKnownMarketplaces` entries, those entries become per-project artifacts that must be updated whenever the plugin's name, marketplace identifier, or GitHub path changes. The entries are also redundant for developers who already have the plugin installed: they get the plugin twice (user + project scope) with no benefit.

**Why not use the `SessionStart` hook to warn collaborators?**

A `SessionStart` hook is a natural place to surface a "plugin not installed" warning for new collaborators who open a project that has been seeded with `/bytewyrd:scaffold`. The problem is circular: the hook is shipped by the plugin and is registered in `hooks/hooks.json`, so it only runs in sessions where the plugin is already loaded. A developer who does not have the plugin installed will see none of the hook's output — the hook simply does not execute for them.

**What covers new collaborators instead?**

`/bytewyrd:scaffold` seeds the consumer project's `CLAUDE.md` with the install commands. A developer who clones the repo and runs them gets the plugin and its session-start hooks from that point on.

**Optional project-scope enforcement**

Teams that want Claude Code to register the marketplace and turn the plugin on for every collaborator can add both `enabledPlugins` and `extraKnownMarketplaces` entries to `.claude/settings.json` and commit them. `extraKnownMarketplaces` registers the marketplace once a collaborator trusts the folder, and `enabledPlugins` turns the plugin on. Neither installs it: each collaborator still runs `claude plugin install bytewyrd@bytewyrd --scope project` once per clone ([Claude Code docs](https://code.claude.com/docs/en/plugins/org#require-plugins-per-repository)). Teams that choose this path own the maintenance of those entries. See `docs/guide/installation.md` for the exact JSON.

## Dependencies

| Dependency | Purpose |
|------------|---------|
| [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | Historical source of agent definitions (MIT). Files are now locally owned; no active sync dependency. |
| Claude Code plugin system | Runtime host — discovers skills and agents |
| Python 3.11 or newer | Runs the commands and JSON helpers behind `scripts/bw` and the hooks that use them, with the standard library and the vendored PyYAML in `scripts/_vendor/` |
| jq | The skills read the JSON helpers' output with it |
| uv 0.13.4, with pytest, PyYAML, ruff, mypy and types-PyYAML from `uv.lock` | Development and CI only: the tests, lint and type checks. Users need none of them |
| `github`, `context7` and `code-review` from `claude-plugins-official` | Hard plugin dependencies: the GitHub MCP server, library documentation lookup and the `/review` pre-pass |
