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

## Data Flow

Skills → executed by Claude Code in-session. No persistent side effects unless the skill writes files.

Agents → spawned as subtask processes. Receive a goal and a tool allow-list from the calling skill; return a result message.

`best-practices-record` (skill) → `~/.claude/BEST_PRACTICES.md` (user-global file) → `best-practices-sync` (plugin-local skill) → `skills/sync/SKILL.md` → future `/sync` runs in consumer projects.

`/sync` (skill) → `$CLAUDE_PLUGIN_ROOT/rfc-process.md` (canonical template) → `docs/rfc-process.md` in consumer project (created or updated with upstream sync markers).

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent source | Permanently local copies in `agents/`, originally from awesome-claude-code-subagents (MIT) | Consumers get agents without a network call at install time; local ownership prevents silent upstream clobber of customizations; upstream improvements pulled manually when desired |
| Skill naming | Noun-first (`rfc-new`, `best-practices-extract`) | Groups related skills alphabetically; matches `rfc-*` family already established |
| Plugin-local vs exported skills | Plugin-local in `.claude/skills/`, exported in `skills/` | Keeps maintenance tools out of consumer installs; plugin.json is the explicit export declaration |
| Best-practices flow | Record → global file → manual sync to `/sync` content | Puts human review between personal capture and distribution; prevents one user's project-specific notes from polluting the sync content of every future project |
| RFC process distribution | Canonical template at plugin root; `/sync` creates/updates `docs/rfc-process.md` with upstream sync markers | Eliminates separate `/rfc-install` step; RFC setup is idempotent and automatic on every `/sync` run |

## Dependencies

| Dependency | Purpose |
|------------|---------|
| [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | Historical source of agent definitions (MIT). Files are now locally owned; no active sync dependency. |
| Claude Code plugin system | Runtime host — discovers skills and agents |
