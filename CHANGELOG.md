# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

**Versioning.** Releases up to 0.2.0 used [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Since then the plugin has no version number: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` deliberately omit `version`, and users track commits on `main`. Claude Code takes the version from the manifest first, and a pinned value kept every install on its cached copy until the string changed, however many commits landed. Without it, Claude Code identifies each install by commit, so every new commit on `main` is an update. Notable changes are recorded under [Unreleased].

---

## [Unreleased]

Everything merged after the 0.2.0 release notes were written: #94, #96, #110, #111, #112, #113 (the release-hygiene PR that introduced this section), #115, #116, #117, and #120.

### Changed

- **Python 3.11 or newer runs the new commands and hooks** (RFC `2026-11-09-scaffold-and-drift`). `scripts/bw`, a POSIX-sh launcher, runs `scaffold`, `drift`, `state-touch` and `compact-reminder` under `$BYTEWYRD_PYTHON` when it is 3.11 or newer, else the first of `python3.15` … `python3.11` on `PATH`, else `python3` when it is 3.11 or newer. It passes `-I -S -B`, so `PYTHON*` variables, a virtualenv's `.pth` files and bytecode stay out. Without such an interpreter the commands exit 1, the hooks still exit 0, and the PreCompact sentinel is still written.
- **The nine JSON helpers behind the skills are Python too, so the plugin's scripts no longer need bash** (RFC `2026-11-09-scaffold-and-drift`). This supersedes the "bash 4 or newer is required" entry below. `rfc-braindump-append`, `rfc-braindump-list`, `rfc-braindump-remove`, `rfc-feedback-list`, `rfc-frontmatter`, `rfc-resolve`, `rfc-set-status`, `rfc-summary` and `tool-probe` run through `scripts/bw`, and the skills call them as `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" <name>`. They keep their arguments, JSON output and exit codes apart from the changes below, and the skills still read the output with jq. Without Python 3.11 or newer they exit 2 with a JSON error on stderr. RFC frontmatter is read with a vendored, pure-Python PyYAML 6.0.3, and usage errors name `bw <name>`. Deliberate changes:
  - **Stricter frontmatter.** An unclosed block, an explicit tag that makes a field anything but a string, a list or mapping in a field, an alias, a block over 64 KiB and invalid YAML are errors (exit 2). Values read as YAML reads them: a quoted value is unquoted and unescaped, a plain one keeps any `"`, a trailing `# comment` is dropped, and `~` and `null` are empty in every field. `rfc-set-status` reads the old status the same way.
  - **Failed writes.** `rfc-braindump-append`, `rfc-braindump-remove` and `rfc-set-status` report a failed write as a JSON error with exit 2, where they reported success.
  - **Unreadable files.** `rfc-feedback-list` and `rfc-braindump-remove` exit 2 on a file they can't read, where they found no markers or no match.
  - `rfc-braindump-remove` compares the body exactly, so a body holding a backslash now matches its line.
  - `rfc-resolve` falls back to the last regular file in `docs/rfcs/`, so a directory named `*.md` that sorts last no longer gives "no RFC files".
  - `tool-probe` needs the execute bit, and `tool-probe jq` without jq reports it missing with exit 1, where it failed with exit 2.
  - Input that isn't UTF-8 becomes U+FFFD in the JSON.
- **The Python behind `scripts/bw` is one typed package, `scripts/bytewyrd/`** (RFC `2026-11-09-scaffold-and-drift`). `scripts/bw NAME` is unchanged: the launcher runs the bootstrap, `scripts/bytewyrd/__main__.py`, which dispatches NAME to `scripts/bytewyrd/commands/<name>.py`, and every command keeps its arguments, output and exit codes. Seven shared modules, `cli`, `git`, `fs`, `detect`, `seed`, `frontmatter` and `jsonout`, hold what the commands share, and only `frontmatter` imports the vendored PyYAML. Every module but the bootstrap is typed and checked with `mypy --strict`.
- **Seeded files say nothing when no language is found** (RFC `2026-11-09-scaffold-and-drift`). The `AGENTS.md` template has a Project facts section only when scaffold finds a language, and its languages line no longer says that scaffold found them. With no languages, the seeded `ci.yml` is a neutral no-op, whose one step is `run: exit 0`. Repositories seeded before this change see `template-changed` until they apply drift's diff and the stamp that its fix line prints.
- **`github`, `context7` and `code-review` are hard dependencies.** `plugin.json` declares them from `claude-plugins-official`, `code-review` at `^1.0.1` since it is the only one that publishes a version, and `marketplace.json` allows that marketplace, so installing bytewyrd installs them. Claude Code doesn't load bytewyrd while one is missing or disabled. The `claude plugin` commands never register the official marketplace on their own; see Upgrading.
- **The SessionStart requirement check is removed**, with `scripts/check-requirements.sh` and `BYTEWYRD_SKIP_WARN`. The companion plugins are dependencies now, Exa and Firefox are MCP servers whose tools degrade where they are used, and scaffold and drift exit 1 without git.
- **`.bytewyrd/` sentinels go through `bw state-touch`.** `/best-practices-extract` writes its PreCompact sentinel, and `/docs-review` removes the SubagentStop one, through a no-follow directory descriptor that refuses symlinks.
- **Agents and skills cite the `rfc-process` skill** instead of `docs/rfc-process.md`, and `feature-engineer` takes a `docs/rfcs/` directory at the repository root as the RFC opt-in. Agents and skills name MCP tools in prose instead of by `mcp__` ID, and the nine skills that need Claude Code declare `compatibility:`.
- **pytest replaces bats** (#120). Each of the 121 bats tests in `tests/scripts/` maps to pytest coverage in `tests/py/`. Most of the JSON helpers' cases were already covered, and the rest were ported as black-box tests that run `scripts/bw`, the hook commands, the skills' Step 2 snippet and the CI lint helpers as child processes. bats, `tests/run.sh` and the four `tests/bats-*` submodules are gone, so a clone or worktree no longer needs `git submodule update --init`. `test` and `compat` run only pytest. `history` runs pytest over `tests/py` at every commit of a pull request instead of bats, without the check that port commits leave `tests/scripts/` alone, and `tests/e2e` runs only on the head. This supersedes the bats parts of the "Skill helper scripts", "More CI" and "CI that gates merges" entries below. In a checkout made before this change, `git pull` leaves the four `tests/bats-*` directories in place, untracked. `ruff check` and `ruff format --check` then fail on the Python files in them, so remove them with `rm -rf tests/bats-*`.

- **No version number; users track commits.** `version` is removed from `plugin.json` and `metadata.version` from `marketplace.json`. Side effects:
  - The `plugin-version` SessionStart warning (installed plugin older than the one that last ran `/sync`) no longer fires.
  - `/sync` no longer writes `.bytewyrd/plugin-version`.
  - `claude plugin validate` reports an expected "No version specified" warning.
- **bash 4 or newer is required**, and the requirement is now explicit. The helper scripts already used `mapfile` and associative arrays, which macOS's stock `/bin/bash` 3.2 lacks. On older bash, `/sync` preflight and the scripts behind `/rfc-approve`, `/rfc-drop` and `/rfc-summary` now stop with a message pointing to `brew install bash`, instead of failing partway with `mapfile: command not found`. Requirements are listed in [`docs/guide/installation.md`](docs/guide/installation.md#requirements).
- **License:** the plugin is licensed under Apache-2.0 (`LICENSE`, plus `"license"` in `plugin.json`). [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) carries the MIT notice of VoltAgent/awesome-claude-code-subagents and lists the agents that still contain substantial upstream text.
- **Per-file `/sync` extension strategies** (#96):
  - Five new strategies (`additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, `owned-regions`) join the existing `structured` one, and each plugin-managed file now uses the strategy that matches how the plugin relates to it. That ends the `conflict_legacy` prompts on every run.
  - Plugin infrastructure moved out of `.claude-plugin/` to the repository root (`scripts/`, `templates/`, `hooks/pre-commit/`, `bootstrap-manifest.json`).
  - `/rfc-update` is removed now that `docs/rfc-process.md` is plugin-authoritative.
  - `/docs-review` now covers `README.md`.
- **Skill helper scripts** (#94): ten scripts under `scripts/`, each with a JSON stdout contract and bats tests, replace the inline bash/awk in eleven skills. bats-core and its libraries are vendored as submodules under `tests/`.
- **RFC model tier** (#112): `rfc-process.md` documents Opus as the default rather than the highest available model, and `/rfc-new` can draft with Claude Fable 5 on opt-in.
- **User-only skills** (#116): `/sync`, `/git-branch-cleanup`, `/rfc-approve`, `/rfc-drop`, `/rfc-implement`, `/refactor` and `/docs-review` carry `disable-model-invocation: true`, so Claude cannot start them on its own and you run them yourself. Claude Code versions around 2.1.138 are reported to ignore the flag for plugin skills ([anthropics/claude-code#22345](https://github.com/anthropics/claude-code/issues/22345)). `/sync` now also asks you to confirm before it does anything, because it is being replaced by scaffold + drift (RFC `2026-11-09-scaffold-and-drift`) and has known defects. `code-reviewer` and `security-engineer` no longer have the `Write`, `Edit` and `NotebookEdit` tools.
- **The consumer settings template no longer ships the PreCompact gate** (#116). A blocked compaction can make a request fail when Claude Code was compacting to recover from a context-limit error. Repos that already have the gate lose it, along with any hooks they added under `hooks`, the next time `/sync` runs.

### Added

- **`/bytewyrd:scaffold` and `/bytewyrd:drift`** (RFC `2026-11-09-scaffold-and-drift`).
  - scaffold seeds `AGENTS.md`, a `CLAUDE.md` that imports it, a PR template and `.github/workflows/ci.yml`, each only if missing and stamped on line 1. It is a dry run unless `--apply`, writes only at the top of the work tree and never under `.claude/`, never overwrites or writes through a symlink, and refuses a dirty tree unless `--allow-dirty`.
  - The seeded CI is a no-op job, or one job per tracked (language, directory) that calls this repository's `lang-ci-<id>.yml` reusable workflows (#115) at a pinned commit SHA.
  - drift is read-only. It compares the seeded files with the current templates, checks the CI pins, and lists leftover 0.2.x `/sync` artifacts, each with a one-line fix. It exits 0 when clean, 2 on drift (with `--strict`, also on warnings) and 1 when it cannot run.
- **Always-on rules.** A SessionStart hook on `startup|clear|compact` adds five workflow conventions, from `hooks/always-on-rules.json`, as `additionalContext`. CI caps them at 2,000 characters.
- **`rfc-process` and `best-practices` skills.** The RFC process and the curated best practices per stack (general, go, js-ts, python, rust, svelte, ruby, rails, k8s-cue, terraform) ship in the plugin and are read at runtime, so repositories don't need copies.
- **More CI.** `test` also runs pytest over `tests/py` and `tests/e2e`. New jobs, not required: `compat` runs bats and pytest on Python 3.11 under Linux and on the latest 3.x under macOS; `history` runs bats at every commit of a pull request and checks the scaffold caller's pin; `install-check` installs the plugin into a temporary HOME and updates an install of `main`.
- **A uv development environment** (RFC `2026-11-09-scaffold-and-drift`). `pyproject.toml` and `uv.lock` pin the development tools, pytest, PyYAML, ruff, mypy and types-PyYAML, and `mise.toml` pins uv 0.13.4. Contributors and every CI job install them with `uv sync --locked` and run them with `uv run --no-sync`, in place of CI's pip installs. The plugin itself installs nothing and needs no uv.
- **ruff and `mypy --strict` in CI.** `lint` runs `ruff check`, `ruff format --check` and `mypy` as `pyproject.toml` configures them: ruff's classic rule set plus import sorting, on the repository's Python but not `scripts/_vendor/` or Markdown, and `--strict` on `scripts/bytewyrd/`.
- **The vendored PyYAML is checked against `uv.lock`.** `.github/scripts/vendor-pyyaml.py`, standard library only, rebuilds `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` from the sdist that `uv.lock` pins, after checking its size and sha256, and `lint` runs it with `--check`, which compares the files both ways. `scripts/_vendor/PyYAML-6.0.3.sha256` is gone, since `uv.lock` records the same hash. [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md#updating-the-vendored-pyyaml) has the steps to update PyYAML.

- **CI that gates merges.** Three jobs replace the stub workflow:
  - `lint`: JSON manifests parse, `bootstrap-manifest.json` is current, agent and skill frontmatter is strict YAML, relative Markdown links resolve, and the shell scripts pass shellcheck (warning level) and shfmt.
  - `validate`: `claude plugin validate` with a pinned CLI.
  - `test`: the bats suite.

  Actions are pinned to commit SHAs, shellcheck and shfmt are pinned releases verified by sha256, jobs run on `ubuntu-26.04` instead of `ubuntu-latest`, and the token is read-only. See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md#quality-gate) to run the same checks locally.
- **Shell style.** `.editorconfig` records the shfmt style (2-space indent, indented case items, binary operators may start a line). The scripts were reformatted once, with no behavior change: their syntax trees are identical before and after.
- **License section in the README** (#116).

### Removed

- **`/sync`** (RFC `2026-11-09-scaffold-and-drift`), with its 18 `scripts/sync-*.sh` helpers, the sync-only libraries `scripts/_lib/{chunks,detect-languages,plugin}.bash` and their bats tests. Run `/bytewyrd:scaffold` to seed a repository instead, and `/bytewyrd:drift` to check it: drift prints each 0.2.x leftover with its fix.
- **The bootstrap manifest:** `bootstrap-manifest.json`, `scripts/build-manifest.sh`, the `hooks/pre-commit/manifest-check.sh` pre-commit hook and CI's manifest check. If a plugin clone's `.git/hooks/pre-commit` links to that hook, remove it with `rm .git/hooks/pre-commit`.
- **The 0.2.x templates** in `templates/`, and the root `rfc-process.md`. scaffold's seed templates are in `templates/scaffold/`, and the RFC process and the curated practices are in the `rfc-process` and `best-practices` skills, read from the plugin at runtime.
- **`scripts/rfc-legacy-detect.sh`**, which nothing called, and its tests.
- **The companion-plugin probes** `github-mcp`, `context7-mcp` and `code-review-mcp` in `scripts/tool-probe.sh`. The three plugins are hard dependencies, so they can't be missing while bytewyrd loads. `/rfc-implement` opens its pull request with the GitHub MCP server's `create_pull_request` tool, without the `gh` fallback, and `/refactor` always runs the `/review` pre-pass.

### Fixed

- **The `/docs-review` reminder after a `feature-engineer` run is back** (#116 removed it; see below). The SubagentStop hook now writes its sentinel through `bw state-touch`, which refuses a symlinked `.bytewyrd` or sentinel. Its reminder and the post-compact one ask you to run `/docs-review`, which is user-only, and the post-compact reminder no longer needs GNU or BSD `stat`.

- **Security: a committed symlink could redirect a hook's write outside the repository** (#116). The `SubagentStop` hook for `feature-engineer` ran `mkdir -p .bytewyrd && : > .bytewyrd/last-feature-engineer-stop` in the project root, and plugin hooks run outside the sandbox. A repository that committed `.bytewyrd` (or the sentinel inside it) as a symlink therefore made the hook create or truncate a file elsewhere. The hook is removed, so the `/docs-review` reminder after a `feature-engineer` run is gone until RFC `2026-11-09-scaffold-and-drift` re-adds it through a writer that refuses symlinks. Update the plugin to pick up the fix.
- Five agents (`deployment-engineer`, `microservices-architect`, `rust-engineer`, `sql-pro`, `websocket-engineer`) listed `MultiEdit`, which is not a Claude Code tool, so they had no `Edit`. They now list `Edit` (#116).
- `/git-branch-cleanup` could delete work that git would have kept (#116). It now fetches before reading state, looks up each branch's PR on its own instead of from a list capped at 30, tries `git branch -d` and a plain `git worktree remove` before the forced forms, and asks per branch or worktree before deleting anything that can lose work: unmerged commits, ignored files in a worktree, or a remote branch with commits missing from main.
- `rfc-set-status.sh` wrote a drop reason containing a double quote or a backslash as invalid YAML, and `rfc-frontmatter.sh` could not read the escaped form back. Both now handle `\"` and `\\` (#116).
- `/rfc-consensus-review` told the model to run a "reflow script" that does not exist, and carried examples from another project (#116).
- Skills invoked bundled scripts by relative path, which failed in consuming projects; they now use `${CLAUDE_PLUGIN_ROOT}/scripts/…` (#110).
- `/sync` (#111):
  - The project slug is now derived correctly when `/sync` runs from a worktree.
  - `enabledPlugins` is limited to the three companion plugins.
  - `PULL_REQUEST_TEMPLATE.md` and `ci.yml` get real drift detection.
  - `## Auto Mode` and `## Git` now propagate to consumers' `CLAUDE.md`.
  - `mise.toml` `[tools]` canonicalization and apply now work.
- `/sync` resolves its plugin root to the cached copy that is running and skips cache directories Claude Code marked `.orphaned_at`. With commit-SHA cache directories, a version sort could otherwise pick a stale copy for up to two weeks after an update.
- `/sync` renders a valid `ci.yml` when no language is detected: a single no-op `ci` job instead of an empty `jobs:` that GitHub rejects.
- Fourteen agents and `rfc-read-feedback` had frontmatter that only Claude Code's lenient fallback could parse; they are now strict YAML, with the text unchanged. The `best-practices-extract` description is no longer cut off at "## Project-Specific".
- Broken relative links in `docs/CONTRIBUTING.md` (and the template it is rendered from) and in the `best-practices-sync` skill.
- The manifest pre-commit hook is committed executable, and its setup command now works from git worktrees.

### Upgrading

Existing installs are pinned to the cached 0.2.0 copy, and bytewyrd now loads only once its three dependencies are installed. Add the official marketplace, install the dependencies explicitly so that updates keep them resolved, then refresh the marketplace and update once:

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official
claude plugin marketplace update bytewyrd
claude plugin update bytewyrd@bytewyrd
```

The first four commands succeed without changing anything when the marketplace or plugin is already there. Restart Claude Code afterwards. From then on, each `claude plugin update` (or marketplace auto-update, if you turn it on) picks up the latest commit on `main`. The hooks and scaffold and drift need Python 3.11 or newer on `PATH`, or in `BYTEWYRD_PYTHON`.

---

## [0.2.0] — 2026-05-14

A substantial step up from 0.1.0. The two headline changes are a complete audit of all 48 specialist agents and a series of RFC-driven improvements to the skill set — but there are significant additions throughout.

### Agent overhaul

All 48 agents were audited and reworked against a versioned quality rubric ([`docs/agent-audit-criteria.md`](docs/agent-audit-criteria.md)), replacing the original vendored definitions from `VoltAgent/awesome-claude-code-subagents` with locally-owned, Bytewyrd-style definitions. Each agent now has:

- A correct `tools:` list (the original set listed CLIs that Claude Code does not surface as named primitives, silently preventing agents from using Read/Write/Edit/Bash)
- An explicit model assignment (`haiku`, `sonnet`, or `opus`) sized to the task
- Structured `<example>` blocks in the `description` field for reliable dispatch
- Evidence-based operating guidance in the body

Two new specialist agents ship with this release: `claude-agent-author` (authors and audits agent definitions) and `docs-agent` (reviews and repairs `docs/guide/**`).

### New skills

| Skill | What it adds |
|-------|-------------|
| `/refactor` | Deliberate six-phase refactoring pass: pre-flight → analyze → characterization tests → plan → **approval gate** → apply → report. Spawns `refactoring-specialist` on Opus. |
| `/rfc-summary` | Active RFC overview — statuses, authors, ages at a glance. |
| `/docs-review` | Spawns `docs-agent` to audit and repair `docs/guide/**` for accuracy, coverage, and drift. |

### Skill improvements

- **`/sync`** — renamed from `/bootstrap`; RFC setup integrated (dropped separate `/rfc-install`); rewrote artifact application as a 3-way diff + interactive confirmation instead of skip-if-exists; `project-brief.md` now the single source of truth for project identity; Security and Workflow sections added to the installed CLAUDE.md template; fixed a bug where writes went to the main repo root instead of the active worktree; now strips legacy `bytewyrd@bytewyrd` entries from `enabledPlugins` (and `bytewyrd` from `extraKnownMarketplaces`) on each run — 0.1.x projects had these entries; current projects rely on user-scope install instead
- **`/best-practices-extract`** — now auto-triggers on the `PreCompact` hook so learnings are captured before context windows compact; full triage-and-lift discipline applied (non-obvious, cross-project guidance only)
- **`/best-practices-record`** and **`/best-practices-extract`** — unified destination: both write to the same global pool; rationale headers added
- **`/best-practices-sync`** — Opus-powered conflict resolution when a candidate entry overlaps an existing one; auto-creates missing sections rather than failing
- **`/rfc-new`** — automatically removes the source braindump entry after promoting it to a full RFC
- All RFC skills — switched to fully-qualified `bytewyrd:` agent names for unambiguous dispatch

### Infrastructure

- **SessionStart hook** — per-session requirements check probing companion plugin state, MCP server config, and `git`/`gh` CLI availability; soft warnings for missing optional dependencies, hard exit on critical gaps only
- **PreCompact hook** — gates session end on best-practices extraction so learnings aren't lost to context compaction
- **bootstrap-manifest.json** — SHA-256 index of every artifact source managed by `/sync`; `build-manifest.sh` regenerates it after source edits
- **Pre-commit manifest-check hook** — fails commits when the manifest is stale; prevents phantom fast-forward updates for plugin consumers

### rfc-architect discipline

`rfc-architect` now enforces evidence-based research: it must fetch authoritative sources for every external claim before writing them into an RFC. Training knowledge is treated as a search query, not a source of truth.

### Plugin housekeeping

- Renamed plugin `bytewyrd-workflow` → `bytewyrd`; repository renamed to `claude-bytewyrd`
- Plugin directory structure aligned to the standard Claude Code plugin layout
- README redesigned with icon, cleaner install instructions, and generic-audience messaging
- Model selection guidance, evidence-based development principles, and sandbox container compatibility notes baked into the plugin `CLAUDE.md`

### Upgrading from 0.1.0

The plugin was renamed from `bytewyrd-workflow` to `bytewyrd`, and the recommended install scope changed from project to user. The steps depend on how you installed 0.1.0.

**If you followed the 0.1.0 recommendation (project scope):**

The old plugin is registered separately in each project's `.claude/settings.json`. Uninstall it once per project, then install the new name once globally.

```bash
# Run inside each project where you installed 0.1.0
cd /path/to/your/project
claude plugin uninstall bytewyrd-workflow --scope project

# Run once from anywhere — installs at user scope (the new default)
claude plugin install bytewyrd/claude-bytewyrd
```

**If you installed at user scope (`--scope user`):**

The old plugin is registered once in `~/.claude/settings.json`. One uninstall, one install — both from anywhere.

```bash
claude plugin uninstall bytewyrd-workflow --scope user
claude plugin install bytewyrd/claude-bytewyrd
```

If your team wants to *require* the plugin in a specific repo (so collaborators are prompted on first open), see [docs/guide/installation.md](docs/guide/installation.md#team-wide-enforcement-optional).

**`/bootstrap` → `/sync`.** The bootstrap skill was renamed to `/sync`. Update any notes or scripts that reference `/bootstrap` (or `/bytewyrd:bootstrap`).

**Re-run `/sync` in each project.** The installed CLAUDE.md template, RFC process file, and BEST_PRACTICES.md all gained new sections in 0.2.0. Run `/sync` in each project to pick up the updated content.

**SessionStart warnings are expected on first run.** After installing, the new requirement-check hook will warn about any missing companion plugins or MCP servers. Follow the fix commands shown — or suppress individual warnings with `export BYTEWYRD_SKIP_WARN=<id>` if a dependency doesn't apply to your setup.

---

## [0.1.0] — 2026-05-09

Initial release. Core plugin scaffold: RFC workflow skills (`/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-consensus-review`, `/rfc-read-feedback`, `/rfc-update`), best-practices capture (`/best-practices-record`, `/best-practices-extract`, `/best-practices-sync`), `/git-branch-cleanup`, 46-agent set, and SessionStart hooks wiring.
