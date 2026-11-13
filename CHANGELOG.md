# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

**Versioning.** Releases up to 0.2.0 used [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Since then the plugin has no version number: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` deliberately omit `version`, and users track commits on `main`. Claude Code takes the version from the manifest first, and a pinned value kept every install on its cached copy until the string changed, however many commits landed. Without it, Claude Code identifies each install by commit, so every new commit on `main` is an update. Notable changes are recorded under [Unreleased].

---

## [Unreleased]

Everything merged after the 0.2.0 release notes were written: #94, #96, #110, #111, #112, and #113 (the release-hygiene PR that introduced this section).

### Changed

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

### Added

- **CI that gates merges.** Three jobs replace the stub workflow:
  - `lint`: JSON manifests parse, `bootstrap-manifest.json` is current, agent and skill frontmatter is strict YAML, relative Markdown links resolve, and the shell scripts pass shellcheck (warning level) and shfmt.
  - `validate`: `claude plugin validate` with a pinned CLI.
  - `test`: the bats suite.

  Actions are pinned to commit SHAs, shellcheck and shfmt are pinned releases verified by sha256, jobs run on `ubuntu-26.04` instead of `ubuntu-latest`, and the token is read-only. See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md#quality-gate) to run the same checks locally.
- **Shell style.** `.editorconfig` records the shfmt style (2-space indent, indented case items, binary operators may start a line). The scripts were reformatted once, with no behavior change: their syntax trees are identical before and after.

### Fixed

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

Existing installs are pinned to the cached 0.2.0 copy. Refresh the marketplace and update once:

```bash
claude plugin marketplace update bytewyrd
claude plugin update bytewyrd@bytewyrd
```

Restart Claude Code afterwards. From then on, each `claude plugin update` (or marketplace auto-update, if you turn it on) picks up the latest commit on `main`.

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
