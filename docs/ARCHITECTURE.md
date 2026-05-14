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
**Key interfaces:** Each skill is a directory containing `SKILL.md`. Claude Code's plugin system discovers skills via the `skills` array in `.claude-plugin/plugin.json` and exposes them as `/skill-name` commands.

Skills are organized by noun-first naming convention (e.g., `best-practices-extract`, `rfc-new`). Related skills share a common noun prefix and sort together in any alphabetical listing.

### Agents (`agents/`)

**Purpose:** Specialized subagent definitions that Claude Code can spawn as subtasks. Agents are role-specific — each carries a focused system prompt, a tool allow-list, and a model preference.
**Location:** `agents/`
**Key interfaces:** Each agent is a single `.md` file with YAML frontmatter (`name`, `description`, optional `model`). Claude Code discovers agents in this directory and makes them available as subagent targets.

**Source:** Agent definitions originated from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) (MIT) and are now permanently locally owned. The upstream repository is organized by category (`categories/{category}/{agent-name}.md`); this plugin flattens them into a single `agents/` directory for simpler discovery. Each locally modified file carries an attribution comment. Future upstream improvements are pulled manually, file by file, when a maintainer judges them worth applying.

### Plugin-local skills (`.claude/skills/`)

**Purpose:** Skills that are only meaningful inside this plugin's own checkout — maintenance and meta-operations that consumers would never need.
**Location:** `.claude/skills/`
**Key interfaces:** Same `SKILL.md` discovery as `skills/`, but these are not exported in `plugin.json` and are therefore invisible to consumers.

Current plugin-local skills:
- `best-practices-sync` — promotes entries from the global `~/.claude/BEST_PRACTICES.md` into `skills/sync/SKILL.md`

### Plugin manifest (`.claude-plugin/`)

**Purpose:** Defines the plugin's identity. This is the entrypoint the Claude Code plugin system reads; skills and agents are auto-discovered from their respective root directories.
**Location:** `.claude-plugin/plugin.json`

### Hooks (`hooks/`, `scripts/`)

**Purpose:** Shell-level automation that Claude Code executes in response to session lifecycle events. The plugin currently ships one hook: a `SessionStart` probe that runs once per session in every project where the plugin is enabled.
**Location:** `hooks/hooks.json` (hook declarations) + `scripts/check-requirements.sh` (probe logic)
**Key behavior:** The hook is silent when all requirements are met. It emits a warning bundle for soft-dependency gaps (companion plugins not enabled, MCP servers not configured, optional CLI tools absent, installed plugin older than the version that last ran `/sync` on the project) and exits with status 2 only for hard failures (`git` missing, or a stale `claude-plugins-official` reference that Claude Code would error on later). Individual warnings can be suppressed via `BYTEWYRD_SKIP_WARN=<id>` in the user's shell environment.

## Data Flow

Skills → executed by Claude Code in-session. No persistent side effects unless the skill writes files.

Agents → spawned as subtask processes. Receive a goal and a tool allow-list from the calling skill; return a result message.

`SessionStart` hook → `scripts/check-requirements.sh` → warns or blocks when companion plugins, MCP servers, or required CLI tools are missing.

`best-practices-extract` (skill) → `docs/BEST_PRACTICES.md` (project file); entries the user marks as generalizable → optional Promotion Step → `~/.claude/BEST_PRACTICES.md` (user-global file).

`best-practices-record` (skill) → `~/.claude/BEST_PRACTICES.md` (user-global file).

`~/.claude/BEST_PRACTICES.md` → `best-practices-sync` (plugin-local skill) → `skills/sync/SKILL.md` → future `/sync` runs in consumer projects.

`/sync` (skill) → `$CLAUDE_PLUGIN_ROOT/rfc-process.md` (canonical template) → `docs/rfc-process.md` in consumer project (created or updated with upstream sync markers).

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent source | Permanently local copies in `agents/`, originally from awesome-claude-code-subagents (MIT) | Consumers get agents without a network call at install time; local ownership prevents silent upstream clobber of customizations; upstream improvements pulled manually when desired |
| Skill naming | Noun-first (`rfc-new`, `best-practices-extract`) | Groups related skills alphabetically; matches `rfc-*` family already established |
| Plugin-local vs exported skills | Plugin-local in `.claude/skills/`, exported in `skills/` | Keeps maintenance tools out of consumer installs; plugin.json is the explicit export declaration |
| Best-practices flow | Record → global file → manual sync to `/sync` content | Puts human review between personal capture and distribution; prevents one user's project-specific notes from polluting the sync content of every future project |
| RFC process distribution | Canonical template at plugin root; `/sync` creates/updates `docs/rfc-process.md` with upstream sync markers | Eliminates separate `/rfc-install` step; RFC setup is idempotent and automatic on every `/sync` run |
| Plugin installation scope | User scope only (`~/.claude/settings.json`); `/sync` does not write `enabledPlugins` or `extraKnownMarketplaces` to project settings | See note below |

### Plugin installation scope — extended note

The plugin is installed once per developer at user scope. `/sync` explicitly does not write `bytewyrd@bytewyrd` to `enabledPlugins` or `bytewyrd` to `extraKnownMarketplaces` in the project's `.claude/settings.json`.

**Why not project scope?**

The motivation for user-scope-first is maintenance. If every `/sync`-bootstrapped project carries `enabledPlugins` + `extraKnownMarketplaces` entries, those entries become per-project artifacts that must be updated whenever the plugin's name, marketplace identifier, or GitHub path changes. The entries are also redundant for developers who already have the plugin installed: they get the plugin twice (user + project scope) with no benefit.

**Why not use the `SessionStart` hook to warn collaborators?**

The `check-requirements.sh` hook is a natural place to surface a "plugin not installed" warning for new collaborators who open a project that has been bootstrapped with `/sync`. The problem is circular: the hook is shipped by the plugin and is registered in `hooks/hooks.json`, so it only runs in sessions where the plugin is already loaded. A developer who does not have the plugin installed will see none of the hook's output — the hook simply does not execute for them.

**What covers new collaborators instead?**

`/sync` adds an explicit install hint to the consumer project's `CONTRIBUTING.md` (see the CONTRIBUTING.md rendering section in `skills/sync/SKILL.md`). A developer who clones the repo, reads the contributing guide, and follows the one-line install command gets the plugin and all its session-start validation from that point on.

**Optional project-scope enforcement**

Teams that want Claude Code to auto-install the plugin for any collaborator who opens the repo — bypassing the CONTRIBUTING.md manual step — can add both `enabledPlugins` and `extraKnownMarketplaces` entries to `.claude/settings.json` and commit them. Both entries are required: `enabledPlugins` alone is not enough because Claude Code needs `extraKnownMarketplaces` to resolve the marketplace source before it can prompt the install. Teams that choose this path own the maintenance of those entries. See `docs/guide/installation.md` for the exact JSON.

## Dependencies

| Dependency | Purpose |
|------------|---------|
| [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | Historical source of agent definitions (MIT). Files are now locally owned; no active sync dependency. |
| Claude Code plugin system | Runtime host — discovers skills and agents |
