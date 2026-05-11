---
rfc: "2026-05-10-claude-plugin-author-agent"
title: "Claude Plugin Author Agent"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add a `claude-plugin-author` subagent at `agents/claude-plugin-author.md` that owns deep, current knowledge of the Claude Code plugin format — `.claude-plugin/plugin.json` manifest schema, skill `SKILL.md` frontmatter fields (`name`, `description`, `model`, `effort`, `context`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `argument-hint`, `arguments`, `paths`, `hooks`, `agent`, `shell`), the available string substitutions (`$ARGUMENTS`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, etc.), subagent frontmatter fields (`tools`, `disallowedTools`, `model`, `effort`, `maxTurns`, `skills`, `memory`, `isolation`, `color`), the `hooks/hooks.json` event-and-matcher structure, and this plugin's promote-through-production convention (changes start in `.claude/skills/` for local validation, then move to `skills/` and get registered via `.claude-plugin/plugin.json` when they are ready to export to consumers). The agent's system prompt is built from the upstream Claude Code documentation pages — quoted with citations rather than paraphrased from training knowledge — so when format details shift between releases, refreshing the agent is a re-fetch of the same pages, not a guessing exercise. Routing is via the existing pattern in `CLAUDE.md` ("Agent delegation" table): adding a new row maps plugin-authoring work to this agent so the main agent reaches for it instead of rediscovering conventions from the codebase each time.

## Should we do this?

**Yes.** Every plugin-authoring task in this repository today — creating a new skill, debugging why a skill doesn't appear, adding a new agent, wiring up a hook, deciding whether something belongs in `.claude/skills/` (internal) or `skills/` (exported) — currently runs through the main agent re-reading existing skills as exemplars and inferring conventions from neighboring files. That works, but it is lossy: subtle frontmatter fields (`user-invocable`, `disable-model-invocation`, the difference between `allowed-tools` granting permission vs `tools` restricting access on subagents) only get applied when the main agent happens to notice them in the neighbor it picks as a template. New fields shipped by Claude Code in recent versions (`arguments` for positional substitution, `paths` for glob-scoped activation, `${CLAUDE_SKILL_DIR}` for path resolution) are invisible to a main agent that templates off skills written before those fields existed. The promote-through-production workflow (`.claude/skills/` first, then `skills/` and `plugin.json` registration) is project-specific and not in any external documentation; today it lives only as tacit knowledge in `CLAUDE.md` and in observed patterns. A specialized agent that knows the format from primary sources and knows this project's promotion convention turns plugin authoring from "rediscover conventions from neighbors each time" into "delegate to the specialist that already knows them." The cost is one new agent file, a small `CLAUDE.md` edit (table row + workflow subsection), a mirror of the workflow subsection in `.claude-plugin/CLAUDE.md` for plugin-developer context, and a one-line update to `skills/sync/SKILL.md` so consuming projects pick up the routing on their next `/sync`; the payoff is consistency across every future skill, agent, and hook this plugin ships, and a single chokepoint where Claude Code format updates can be absorbed.

## Current state

The plugin currently ships 46 subagents in `agents/` (vendored from VoltAgent/awesome-claude-code-subagents under MIT, now owned locally per RFC 2026-05-10-refactor-command) and 13 exported skills in `skills/` (registered in `.claude-plugin/plugin.json`), plus 1 plugin-local internal skill in `.claude/skills/` (`best-practices-sync`). None of those agents specialize in Claude Code plugin authoring itself.

**What exists today:**

- **No plugin-authoring specialist.** The closest agents are `documentation-writer` (general docs, not Claude Code format), `feature-engineer` (general implementation, no plugin-format expertise), and `mcp-developer` (Model Context Protocol servers — a *different* protocol with overlapping vocabulary that has caused confusion in past sessions). None of these own the Claude Code plugin format.
- **Conventions live as tacit knowledge.** The `promote-through-production` convention (start changes in `.claude/skills/`, validate, then move to `skills/` and register in `.claude-plugin/plugin.json`) is documented only as an implicit pattern in this project. The `~/.claude/projects/<project-slug>/memory/MEMORY.md` file has one note about it, but no in-repo doc spells out the workflow. When the main agent needs to add a new skill, it reads three or four existing skills and infers structure from the diff between them — slow, and prone to copying outdated patterns from the oldest neighbor.
- **Frontmatter field coverage is uneven across existing skills.** Across the 13 exported skills currently in `skills/`, none use `argument-hint` (the `refactor` skill (from RFC 2026-05-10-refactor-command, now Done) introduced the first usage); none use `paths` or `arguments`; `model` is set indirectly via spawn instructions in skill bodies rather than via the skill's own frontmatter; none use `disable-model-invocation`. This is not necessarily wrong — many of these skills are interactive workflows that *should* be model-invocable — but the unevenness is a sign that field selection happens by template-copying, not by deliberate matching to skill purpose.
- **The Claude Code plugin format is moving.** Recent upstream changes (skills' `arguments` for named positional substitution, `paths` for glob-scoped automatic activation, `${CLAUDE_SKILL_DIR}` for bundled-script path resolution, the `experimental.monitors` block, `userConfig` for plugin-prompted values) have landed in versions newer than when several of the existing skills in `skills/` were authored. A main agent without an explicit "look up the current spec" rule will template off older skills and miss these.
- **Existing agents include some that ship with frontmatter aspirations the environment does not honor.** Several local agents (e.g., `ai-engineer` lists `tools: python, jupyter, tensorflow, pytorch, huggingface, wandb`; `mcp-developer` lists `tools: Read, Write, MultiEdit, Bash, typescript, nodejs, python, json-rpc, zod, pydantic, mcp-sdk`) include `tools:` entries that are not Claude Code tool identifiers. Per the subagent docs ("Tools the subagent can use. Inherits all tools if omitted."), listing names that the runtime does not recognize as real tool identifiers narrows the agent's effective tool set to whatever subset matches real Claude Code tools — leaving the rest of the listed items dead. RFC 2026-05-10-refactor-command already addresses this for `refactoring-specialist` by removing the field entirely. A plugin-author agent — used when creating new agents — would have caught these mistakes at write time.
- **No agent is the canonical reference for "is this the right frontmatter for what this skill does?"** Subjective decisions like "should this skill use `context: fork`?" (run in an isolated subagent), "should it have `disable-model-invocation: true`?" (manual-only), "should `model` be pinned?" require knowing both the format and the project's opinion. Today both live in scattered places.

**What is broken or missing:**

1. **Discovery friction.** The main agent re-reads neighboring skills and the upstream docs every time it adds something to the plugin. The total time spent rediscovering format is non-trivial across the dozen-plus plugin-edit sessions this repo has had in the past two weeks.
2. **Field-coverage drift.** Without an opinionated authority on "use this field when X," new skills inherit the field-selection biases of whatever older skill the main agent picked as template, and the codebase converges away from the format's full capability rather than toward it.
3. **No primary-source citation discipline.** When the main agent inlines plugin-format guidance, the guidance is not annotated with which doc page it came from, so when the format changes there is no anchor to update from. A subagent whose system prompt is *built from* the doc URLs makes this explicit.
4. **Promote-through-production is a convention nobody writes down.** New contributors (human or agent) reading `CLAUDE.md` see the directory layout but not the workflow: validate in `.claude/skills/` first, then promote to `skills/` and register. The result is occasional skills that get written directly to `skills/` and shipped to consumers before they've been used locally.

The plugin's existing agent-delegation pattern (`CLAUDE.md` "Agent delegation" table) is the mechanism this RFC uses to surface the new agent to the main agent. The new agent slots in alongside the existing rows — same routing concept, new specialty.

## Analysis / Options

The design has four coupled decisions: scope of the agent's responsibility, source-of-truth strategy for its knowledge, how it's surfaced to the main agent, and what (if anything) ships as a companion skill.

### Decision 1 — What is the agent's scope?

**Option A — Plugin authoring + maintenance (skills, agents, hooks, manifest, this plugin's promote-through-production workflow). Recommended.**
The agent owns the full lifecycle: scaffolding a new skill, deciding placement (`.claude/skills/` vs `skills/`), choosing frontmatter values, drafting the body, registering in `plugin.json`, adding agent definitions, wiring hooks, and explaining why a skill doesn't resolve when debugging. Scope is bounded to the *plugin format itself* — not general implementation, not test design, not refactoring. When the main agent needs to do plugin-authoring work, this is the delegate. Other agents remain authoritative in their own domains (`feature-engineer` for general implementation, `refactoring-specialist` for refactoring passes, `rfc-architect` for design work).

**Option B — Skills-only specialist.**
Narrower: only skill-creation and skill-debugging. Hooks and agent-definition authoring stay with the main agent or get separate specialists later. Rejected because skills, agents, and hooks share the same plugin format, the same `${CLAUDE_PLUGIN_ROOT}` substitution conventions, the same `plugin.json` registration semantics, and frequently appear together (a new skill often needs a companion hook). Splitting these into separate agents would force the main agent to coordinate between two specialists for one task, which is exactly the friction the agent is meant to eliminate.

**Option C — Plugin authoring + Claude Code SDK / Anthropic API knowledge.**
Broader: also covers Anthropic SDK usage, model-tier selection generally, MCP server construction, plugin-marketplace authoring. Rejected because the surface area is huge and the user already has dedicated specialists for those (`ai-engineer`, `mcp-developer`, plus the bundled `claude-api` skill). An agent that knows everything about the Claude ecosystem is an agent that knows nothing well. The bounded scope of "the Claude Code plugin format and this project's promotion convention" is the sweet spot — small enough to keep current, big enough to eliminate the rediscovery friction.

**Recommendation: Option A.** The plugin format is the natural unit. Skills, agents, hooks, and `plugin.json` are tightly coupled; an agent that knows one needs to know the rest. Out-of-scope topics (general implementation, the Anthropic SDK, MCP-protocol server construction, plugin-marketplace publishing) have other specialists and the boundary keeps the agent's system prompt small enough to maintain.

### Decision 2 — How is the agent's knowledge sourced and kept current?

**Option A — System prompt is built from primary-source URLs, quoted with citations, not paraphrased. Recommended.**
The agent's body explicitly lists the upstream Claude Code documentation pages it is built from — `https://code.claude.com/docs/en/plugins-reference`, `https://code.claude.com/docs/en/skills`, `https://code.claude.com/docs/en/sub-agents`, `https://code.claude.com/docs/en/hooks` — and quotes the field tables, frontmatter examples, and event lists directly from those pages. The body also includes a "How this agent stays current" section telling future maintainers: refresh by re-fetching the same URLs (the agent body shows the `mcp__exa__crawling_exa` invocation, or `WebFetch` as a fallback), diff against the agent body, and update. When Claude Code ships a new field or changes an existing one, the refresh path is mechanical, not a translation exercise.

**Option B — System prompt is paraphrased from training knowledge.**
Rely on the model's existing knowledge of plugin formats. Rejected because the format is moving (`arguments`, `paths`, `experimental.monitors`, `${CLAUDE_SKILL_DIR}` are all post-training-data additions for many model versions); paraphrased guidance ages silently and there is no signal to update it.

**Option C — System prompt links to URLs but doesn't quote them.**
The agent's body cites the doc URLs but does not embed the field tables. At runtime the agent fetches them via WebFetch. Rejected because every invocation pays the fetch cost, the agent depends on network availability per turn, and the URLs become a single point of failure for a hot-path workflow. Quoting the content into the system prompt — with a refresh procedure documented — gives a better latency/reliability profile, at the cost of refresh discipline (which Option A makes explicit).

**Recommendation: Option A.** This is the "primary sources, cited, refresh path documented" hint from the braindump for the `claude-agent-author` idea, applied here. It is the only option that survives format churn.

### Decision 3 — How is the agent surfaced to the main agent?

**Option A — Add a row to `CLAUDE.md`'s "Agent delegation" table + write a clear `description` so Claude can auto-delegate. Recommended.**
The plugin's existing `CLAUDE.md` already routes by table: "Task → Agent" rows like `New features → feature-engineer`, `Code reviews → code-reviewer`. Add `Plugin authoring (skills, agents, hooks, plugin.json) → claude-plugin-author`. The agent's `description` frontmatter field includes trigger phrases (per Claude Code's skill/agent description guidance) so Claude can also auto-delegate when it sees the task without the main agent needing to consult the table explicitly.

**Option B — Companion skill (`/plugin-new-skill`, `/plugin-debug-skill`, etc.) as the primary entry point.**
Several slash commands that each spawn the agent for a specific sub-task. Rejected as the *primary* surface because plugin-authoring tasks vary too much in shape to enumerate cleanly (some are "create a new skill", some are "debug why this skill doesn't resolve", some are "add a hook that fires on X", some are "is this the right field for what I want") — the slash-command-per-task approach proliferates skills without adding value. The agent itself, surfaced via `CLAUDE.md` routing and auto-delegation, is the right entry point. A single companion skill *is* worth adding later if a specific sub-task proves to recur — covered as a future RFC, not this one.

**Option C — Auto-invocation only, no `CLAUDE.md` row.**
Trust the agent's `description` to do all the routing work. Rejected because the existing `CLAUDE.md` table is the documented contract for delegation; agents that are not in the table are easy for the main agent to forget about (the table is in the prompt; the agent descriptions are not). The table row is cheap and the auto-invocation is a second-line trigger, not the only trigger.

**Recommendation: Option A.** Use both the explicit `CLAUDE.md` row (primary) and the well-written `description` (secondary fallback for auto-delegation).

### Decision 4 — Companion skill?

**Option A — No companion skill in this RFC. Recommended.**
Ship the agent on its own. The main agent invokes it via the Agent tool whenever the `CLAUDE.md` row matches or the description matches. This follows the same shape as `documentation-writer` and `debugger` — agents listed in the delegation table without their own slash command.

**Option B — Ship one companion skill (`/plugin-new-skill <name>`) that spawns the agent with a structured scaffolding prompt.**
A specific, recurring task gets a dedicated entry point. Rejected for this RFC because (a) no single sub-task has yet proved frequent enough to justify its own skill, and (b) shipping the agent alone first will surface which sub-tasks recur. A future RFC can add a companion skill once the pattern is clear, following the model of `/refactor` + `refactoring-specialist`.

**Option C — Ship multiple companion skills.**
`/plugin-new-skill`, `/plugin-debug-skill`, `/plugin-new-hook`, `/plugin-validate`. Rejected as premature; see Option B's rationale.

**Recommendation: Option A.** Ship the agent first. Defer companion skills until usage shows specific sub-tasks recur often enough to deserve their own surface.

## Drawbacks

- **The system prompt is moderately large.** Quoting the field tables for `plugin.json`, `SKILL.md`, subagent definitions, and the hook event list, plus the project-conventions section and the refresh procedure, makes the agent file roughly 330–350 lines of markdown (comfortably under the 500-line ceiling that the upstream docs recommend for *skill* bodies, though that ceiling does not apply to agent system prompts — agents are loaded once per invocation, not per turn). Every invocation pays that as one-time prompt cost, plus the agent must be on `model: "opus"` for the format-reasoning work to be reliable. **Mitigation:** the agent's content stays in the *subagent's* context, not the parent's, so the parent's window is not affected. The cost is per-invocation, not per-turn-in-parent. If real-world use shows the agent is over-invoked for trivial questions, the `description` can be tightened to discourage low-value triggers. The token cost is also far smaller than the alternative — the main agent re-reading the docs and three or four neighboring skills before every plugin edit — which is what the agent eliminates.

- **The agent goes stale when Claude Code changes the plugin format.** Quoted field tables and event lists rot when upstream adds, renames, or removes fields. **Mitigation:** the agent body includes a "How this agent stays current" section with a documented refresh procedure (re-fetch the four documented URLs with `mcp__exa__crawling_exa` or `WebFetch`, diff against the agent body, update, commit). The refresh is mechanical; the same procedure is run periodically (recommended: when Claude Code releases a notable update) or reactively (when the main agent notices the agent's guidance no longer matches observed behavior). A future RFC can wrap this into a `/plugin-author-refresh` skill if the refresh proves frequent enough; out of scope here.

- **Overlap risk with the proposed `claude-agent-author` Draft RFC.** A separate Draft RFC calls for a `claude-agent-author` agent that specializes in the *subagent* format specifically. This RFC's `claude-plugin-author` agent covers the subagent format as part of its scope (because agents are a plugin component). **Mitigation:** explicit boundary statement in the agent body — "Agent definitions in `agents/` are covered here as a plugin component; for deep agent-authoring topics (prompt construction patterns, model-tier rationales beyond what the Claude Code docs prescribe, system-prompt-engineering technique), defer to `claude-agent-author` once that agent exists." When the `claude-agent-author` RFC ships, this agent's section on agent definitions becomes the format-only layer; the deeper craft layer routes to the new specialist. The two agents compose cleanly because the boundary is "format conventions" vs "prompt-construction craft." If `claude-agent-author` never ships, this agent remains the authority for both layers — no orphaned coupling.

- **Risk of confusion with `mcp-developer`.** The names are similar enough that the main agent could pick the wrong one (`mcp-developer` deals with the Model Context Protocol — a *different* protocol from Claude Code's plugin format, despite both being part of the broader "extensions for Claude" ecosystem). **Mitigation:** both agents' `description` fields are written to disambiguate explicitly. `claude-plugin-author`'s description says "Claude Code plugin format (plugin.json, skills, agents, hooks) — NOT for Model Context Protocol server development; use `mcp-developer` for MCP servers." `mcp-developer`'s description is left as-is (it does not mention Claude Code plugins, so the confusion is asymmetric — the new agent disambiguates against the existing one, not the other way around).

- **The agent gives advice but does not execute changes itself when invoked through delegation.** The main agent (or another spawning context) reads the agent's output and applies changes. This is intentional — the agent's job is to be the source of truth for "what should the frontmatter say," not to perform every edit — but it means a single plugin-authoring task often involves two turns (consult the agent, then apply the recommendation in the parent context). **Mitigation:** for tasks where the agent's output is large enough that round-tripping is wasteful (e.g., "scaffold a complete new skill from scratch"), the agent is given the `Edit` and `Write` tools (inherited via no `tools:` field) and can perform the writes itself when the spawning context asks it to. The two-turn pattern is the default; one-turn write-through is available when the parent prompts for it explicitly.

- **No automated validation that the agent's quoted content matches current upstream.** The refresh procedure is documented but not enforced; the agent could drift silently if maintenance lapses. **Mitigation:** the validation gap is real and accepted for this RFC. A future RFC can add a CI step or scheduled `/loop` job that fetches the upstream URLs and diffs against the agent body — that is a separate piece of automation worth its own RFC, not a blocker for shipping this one.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `agents/claude-plugin-author.md` | New subagent definition: `claude-plugin-author`. Frontmatter declares `name`, `description` (disambiguating against `mcp-developer`), `model: opus`, `color: green` (distinct from `rfc-architect`'s `color: blue` and `feature-engineer`'s `color: cyan` so the agent is visually distinguishable in the transcript). Body is a primary-source-cited reference for the Claude Code plugin format covering `.claude-plugin/plugin.json`, `SKILL.md` frontmatter, subagent frontmatter, the hook event-and-matcher schema, the available string substitutions, and this plugin's `.claude/skills/` → `skills/` promote-through-production workflow, plus a "How this agent stays current" refresh procedure |
| Modify | `CLAUDE.md` (plugin root) | (1) Add `Plugin authoring (skills, agents, hooks, plugin.json) → claude-plugin-author` row to the "Agent delegation" table. (2) Add a one-paragraph "Plugin authoring" subsection in the workflow guidance pointing to the agent and to the canonical authoring entry points |
| Modify | `.claude-plugin/CLAUDE.md` | Mirror the workflow subsection from Change 2b (plugin-developer guidance that loads when working in this checkout). This file is loaded into context when developing in the plugin's own repo. The Agent delegation row (Change 2a) is NOT added here because this file does not currently contain a delegation table — adding one would create drift between the two `CLAUDE.md` files. The plugin root's `CLAUDE.md` remains the canonical delegation source |
| Modify | `skills/sync/SKILL.md` | Update the seed `CLAUDE.md` template (the runtime-built `## Agent delegation` section) and the "Shared agents always added (once)" line so `claude-plugin-author` is included in every project that runs `/sync` after this RFC lands |

No changes to `.claude-plugin/plugin.json` (agent files are auto-discovered from `agents/`; no registration is required per the Claude Code plugin docs). No companion skill in this RFC (deferred to a future RFC if specific sub-tasks recur). No hook changes. No edits to existing skills other than `sync`.

### Steps

#### Step 1 — Create `agents/claude-plugin-author.md`

Create the file with this exact content:

````markdown
---
name: claude-plugin-author
description: Expert authority on the Claude Code plugin format — .claude-plugin/plugin.json manifest, SKILL.md frontmatter (including model, effort, context, disable-model-invocation, user-invocable, allowed-tools, argument-hint, arguments, paths, hooks, agent, shell), subagent frontmatter (model, effort, tools, disallowedTools, skills, memory, isolation, color), the hooks/hooks.json event-and-matcher schema, the ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_SKILL_DIR} / ${CLAUDE_PLUGIN_DATA} substitutions, and this plugin's `.claude/skills/` → `skills/` promote-through-production workflow. Use when creating a new skill from scratch, adding a new agent, wiring up a hook, debugging why a skill isn't resolving, deciding whether a skill belongs in `.claude/skills/` (internal) vs `skills/` (exported), or validating any plugin-format frontmatter against the current spec. NOT for Model Context Protocol server development — use `mcp-developer` for MCP servers (a different protocol, despite the similar name). This agent does cover the `mcpServers` and `.mcp.json` *manifest* config (how plugins register MCP servers), but not the construction of the servers themselves.
model: opus
color: green
---

You are the `claude-plugin-author` subagent. You are the project's authority on the Claude Code plugin format and on this plugin's authoring conventions. When you are invoked, the parent context wants help creating, modifying, debugging, or validating a plugin component (skill, agent, hook, or `plugin.json`).

## How to operate

1. **Identify the task.** The parent's prompt tells you what they want. Common shapes: "scaffold a new skill called X that does Y", "this skill isn't appearing in the `/` menu — why?", "what frontmatter should I use for a skill that auto-fires on file edits in `src/`?", "add a hook that runs after every Bash tool call", "is this `plugin.json` valid?". If the prompt is ambiguous, ask exactly one clarifying question, then proceed.

2. **Cite the format from primary sources.** This system prompt embeds the relevant sections of the Claude Code documentation, quoted directly from the upstream pages (see "How this agent stays current" at the end). When you answer a format question, point to the relevant table or section in this prompt — do not paraphrase from your training knowledge, and do not invent fields. If a question is about a field you cannot find in the embedded content, say so explicitly ("I don't have authoritative content for that field in my reference") and offer to fetch the upstream docs.

3. **Apply this plugin's conventions.** Embedded content covers the upstream format; the "This plugin's conventions" section at the end covers the project-specific overlay (`.claude/skills/` for internal/local-validation, `skills/` for exported, `plugin.json` registration order, MIT-attribution comment for vendored agent files, etc.). When the format permits multiple valid choices, the project conventions are the tiebreaker.

4. **Default to advice; write only on request.** Your default mode is to return structured recommendations — frontmatter blocks, file layouts, registration steps, diagnostic findings — to the parent, who applies them. When the parent explicitly asks you to perform the writes (e.g., "go ahead and create the skill file"), you have access to Read, Write, and Edit and can do so directly.

5. **Validate before you finish.** When you scaffold or modify a file, run a self-check: does the frontmatter have the required fields? Do field values match the upstream spec? Does the placement (`.claude/skills/` vs `skills/`) match the intended audience? Does `plugin.json` need a corresponding registration edit?

## Embedded reference — the Claude Code plugin format

This section quotes the relevant content from the upstream docs. **Do not paraphrase from training knowledge.** If a user question is not answered by this content, say so explicitly and offer to fetch the latest docs.

### `.claude-plugin/plugin.json` manifest

Source: `https://code.claude.com/docs/en/plugins-reference#plugin-manifest-schema`

The manifest is optional. If omitted, Claude Code auto-discovers components in default locations and derives the plugin name from the directory name. Use a manifest when you need to provide metadata or custom component paths.

**Required field:** only `name` (kebab-case, no spaces).

**Metadata fields:** `$schema`, `version`, `description`, `author` (object: `name`, `email`, `url`), `homepage`, `repository`, `license`, `keywords`.

**Component path fields** (all paths must be relative and start with `./`):

| Field | Type | Default-behavior | Description |
|-------|------|------------------|-------------|
| `skills` | string \| array | Adds to default `skills/` | Custom skill directories containing `<name>/SKILL.md` |
| `commands` | string \| array | Replaces default `commands/` | Flat `.md` skill files or directories |
| `agents` | string \| array | Replaces default `agents/` | Custom agent files |
| `hooks` | string \| array \| object | Own merge rules | Hook config paths or inline config |
| `mcpServers` | string \| array \| object | Own merge rules | MCP config paths or inline config |
| `outputStyles` | string \| array | Replaces default `output-styles/` | Output-style files/directories |
| `lspServers` | string \| array \| object | Own merge rules | LSP server configs |
| `experimental.themes` | string \| array | Replaces default `themes/` | Color theme files |
| `experimental.monitors` | string \| array | Replaces default `monitors/monitors.json` | Background monitor configs |
| `userConfig` | object | — | Values prompted at enable time. Substitute as `${user_config.KEY}` |
| `channels` | array | — | Channel declarations for message injection |
| `dependencies` | array | — | Other plugins this plugin requires (semver constraints supported) |

**Version semantics:**

| Approach | How | Update behavior |
|----------|-----|----------------|
| Explicit version | Set `"version": "2.1.0"` in `plugin.json` | Users get updates only when the field bumps |
| Commit-SHA | Omit `version` from both `plugin.json` and the marketplace entry | Users get updates on every new commit to the git source |

**Environment variables for substitution in skill content, agent content, hooks, monitors, MCP/LSP configs:**

- `${CLAUDE_PLUGIN_ROOT}` — absolute path to the plugin's installation directory. Changes on update; treat as ephemeral.
- `${CLAUDE_PLUGIN_DATA}` — persistent directory for plugin state that survives updates. Used for caches, installed dependencies, generated code. Resolves to `~/.claude/plugins/data/{plugin-id}/`.

**Path traversal limitation:** installed plugins cannot reference files outside their directory (`../shared-utils` will not work). Use symlinks if you need to reach external files.

### `SKILL.md` frontmatter

Source: `https://code.claude.com/docs/en/skills#frontmatter-reference`

All fields are optional; only `description` is recommended (so Claude knows when to use the skill).

| Field | Required | Description |
|-------|----------|-------------|
| `name` | No | Display name for the skill. If omitted, uses the directory name. Lowercase letters, numbers, and hyphens only (max 64 characters). |
| `description` | Recommended | What the skill does and when to use it. Combined `description` + `when_to_use` truncated at 1,536 chars in the skill listing. Put the key use case first. |
| `when_to_use` | No | Additional trigger context. Appended to `description` in the skill listing; counts toward the 1,536-char cap. |
| `argument-hint` | No | Hint shown during autocomplete. Example: `[issue-number]` or `[filename] [format]`. |
| `arguments` | No | Named positional arguments for `$name` substitution. Accepts a space-separated string or a YAML list. Names map to positions in order. |
| `disable-model-invocation` | No | Default `false`. Set `true` to prevent Claude from automatically loading this skill. Use for workflows with side effects or that you want to trigger manually with `/name`. Also prevents preload into subagents. |
| `user-invocable` | No | Default `true`. Set `false` to hide from the `/` menu. Use for background knowledge users shouldn't invoke directly. |
| `allowed-tools` | No | Tools Claude can use without asking permission when this skill is active. Does NOT restrict; permission settings still govern unlisted tools. Space-separated string or YAML list. |
| `model` | No | Model override for the rest of the current turn. Accepts the same values as `/model` or `inherit`. Not saved to settings; session model resumes on the next prompt. |
| `effort` | No | Effort level when this skill is active. Overrides session effort. Options: `low`, `medium`, `high`, `xhigh`, `max`. Defaults to inherits from session. |
| `context` | No | Set to `fork` to run in a forked subagent context. Only meaningful for task-style skills, not reference content. |
| `agent` | No | When `context: fork` is set, picks which subagent type to use (built-ins: `Explore`, `Plan`, `general-purpose`; or any custom subagent from `.claude/agents/`). Defaults to `general-purpose`. |
| `hooks` | No | Hooks scoped to this skill's lifecycle. |
| `paths` | No | Glob patterns that limit when this skill is activated. Same format as path-specific rules. |
| `shell` | No | Shell to use for `` !`command` `` and ` ```! ` blocks. `bash` (default) or `powershell`. PowerShell requires `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`. |

**Invocation-control matrix:**

| Frontmatter | You can invoke | Claude can invoke | Description loaded |
|-------------|----------------|-------------------|-------------------|
| (default) | Yes | Yes | Always, full skill loads when invoked |
| `disable-model-invocation: true` | Yes | No | Not loaded; full skill loads when you invoke |
| `user-invocable: false` | No | Yes | Always, full skill loads when Claude invokes |

**String substitutions** available in skill content:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | All arguments passed when invoking the skill. If not present in the content, arguments are appended as `ARGUMENTS: <value>`. |
| `$ARGUMENTS[N]` | Access a specific argument by 0-based index (e.g., `$ARGUMENTS[0]`). |
| `$N` | Shorthand for `$ARGUMENTS[N]` (e.g., `$0`). |
| `$name` | Named argument declared in the `arguments` frontmatter list. |
| `${CLAUDE_SESSION_ID}` | Current session ID. |
| `${CLAUDE_EFFORT}` | Current effort level. |
| `${CLAUDE_SKILL_DIR}` | Directory containing the skill's `SKILL.md`. For plugin skills, this is the skill's subdirectory, not the plugin root. Use this in bash injection commands. |

**Dynamic context injection:** `` !`<command>` `` runs a shell command before the skill content is sent to Claude; the output replaces the placeholder. Multi-line: open with ` ```! ` instead of inline.

**Skill content lifecycle:** when invoked, rendered `SKILL.md` enters the conversation as a single message and stays for the rest of the session. Claude does not re-read the file on later turns. Write standing instructions, not one-time steps.

**SKILL.md size guidance:** keep under 500 lines. Move detailed reference material to separate files in the skill directory and reference them from `SKILL.md` so Claude knows what they contain and when to load them.

**Skill discovery scopes** (highest precedence first; plugin skills are namespaced separately and cannot conflict):

| Location | Path | Applies to |
|----------|------|-----------|
| Enterprise | Managed settings | All users in your organization |
| Personal | `~/.claude/skills/<name>/SKILL.md` | All your projects |
| Project | `.claude/skills/<name>/SKILL.md` | This project only |
| Plugin | `<plugin>/skills/<name>/SKILL.md` (registered via `plugin.json` or auto-discovered) | Where plugin is enabled (namespaced `plugin-name:skill-name`) |

### Subagent frontmatter (`agents/<name>.md`)

Source: `https://code.claude.com/docs/en/sub-agents#frontmatter-reference`

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier using lowercase letters and hyphens. |
| `description` | Yes | When Claude should delegate to this subagent. Auto-delegation matches on this. |
| `tools` | No | Tools the subagent can use. **Inherits all tools if omitted.** To preload Skills into context, use the `skills` field rather than listing `Skill` here. |
| `disallowedTools` | No | Tools to deny, removed from inherited or specified list. |
| `model` | No | `sonnet`, `opus`, `haiku`, a full model ID (e.g., `claude-opus-4-7`), or `inherit`. Defaults to `inherit`. |
| `permissionMode` | No | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, or `plan`. **Ignored for plugin subagents** (security). |
| `maxTurns` | No | Maximum agentic turns before the subagent stops. |
| `skills` | No | Skills to preload into the subagent's context at startup. Full skill content is injected, not just the description. The subagent can still invoke unlisted skills via the Skill tool. |
| `mcpServers` | No | MCP servers available to this subagent. **Ignored for plugin subagents** (security). |
| `hooks` | No | Lifecycle hooks scoped to this subagent. **Ignored for plugin subagents** (security). |
| `memory` | No | `user`, `project`, or `local`. Enables cross-session learning. |
| `background` | No | Default `false`. Set `true` to always run as a background task. |
| `effort` | No | `low`, `medium`, `high`, `xhigh`, `max`. Overrides session effort. |
| `isolation` | No | Set to `worktree` to run in a temporary git worktree (auto-cleaned if no changes). |
| `color` | No | Display color: `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`. |
| `initialPrompt` | No | Auto-submitted as the first user turn when this agent runs as the main session agent (via `--agent` or the `agent` setting). |

**Critical for plugin agents:** `hooks`, `mcpServers`, and `permissionMode` are ignored on plugin-shipped agents for security reasons. Do not include them in agents under `agents/` in a published plugin.

**Tool inheritance:** the upstream docs say `tools` "Inherits all tools if omitted." If you include a `tools:` line that lists names Claude Code does not recognize as real tool identifiers, the subagent silently runs with the *intersection* of "real Claude Code tools" and "your list" — typically the empty set, which prevents the subagent from doing useful work. **Default to omitting the field** so the subagent inherits the standard tool set (Read, Write, Edit, Bash, Grep, Glob, TodoWrite, etc.). Only include `tools:` when you genuinely want a restricted subset and you can name each entry as a real Claude Code tool.

**Plugin agent namespacing:** plugin agents are referenced as `plugin-name:agent-name` (e.g., `bytewyrd:rfc-architect`). When spawning a plugin agent from a skill or another agent, use the namespaced form.

**Agent discovery scopes** (highest precedence first):

| Location | Applies to | Precedence |
|----------|-----------|------------|
| `--agents` CLI flag | Current session | 2 (highest) |
| `.claude/agents/` | Current project | 3 |
| `~/.claude/agents/` | All your projects | 4 |
| Plugin's `agents/` directory | Where plugin is enabled | 5 (lowest) |

### `hooks/hooks.json` schema

Source: `https://code.claude.com/docs/en/plugins-reference#hooks` and `https://code.claude.com/docs/en/hooks`

**Location:** `hooks/hooks.json` in the plugin root, or inline in `plugin.json` via the `hooks` field.

**Structure:**

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<pattern>",
        "hooks": [
          {
            "type": "<hook-type>",
            "command": "<command-or-config>"
          }
        ]
      }
    ]
  }
}
```

The outer array under each event name holds matcher groups. Each matcher group has a `matcher` string (event-specific — typically a tool-name regex like `"Write|Edit"`, or omitted for events that don't have a matcher) and a `hooks` array of one or more hook invocations.

**Hook types:**

- `command`: execute shell commands or scripts (use `${CLAUDE_PLUGIN_ROOT}` for paths to bundled scripts).
- `http`: send the event JSON as a POST request to a URL.
- `mcp_tool`: call a tool on a configured MCP server.
- `prompt`: evaluate a prompt with an LLM (uses `$ARGUMENTS` for context).
- `agent`: run an agentic verifier with tools for complex verification tasks.

**Event names** (complete list, from upstream):

`SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`.

Event names are case-sensitive (`PostToolUse`, not `postToolUse`).

**Hook script requirements (command type):**

- Script must be executable: `chmod +x ./scripts/your-script.sh`.
- Shebang line on the first line: `#!/bin/bash` or `#!/usr/bin/env bash`.
- Path uses `${CLAUDE_PLUGIN_ROOT}` for bundled-script references.

### Plugin directory structure

Source: `https://code.claude.com/docs/en/plugins-reference#plugin-directory-structure`

```
plugin-root/
├── .claude-plugin/
│   └── plugin.json              # manifest (ONLY this file in .claude-plugin/)
├── skills/                      # skills, each in own subdir with SKILL.md
├── commands/                    # flat .md skills (legacy)
├── agents/                      # subagent .md files
├── output-styles/               # output style definitions
├── themes/                      # color themes
├── monitors/                    # background monitors
├── hooks/hooks.json             # hook configurations
├── bin/                         # executables added to Bash tool PATH
├── settings.json                # default settings
├── .mcp.json                    # MCP server definitions
├── .lsp.json                    # LSP server configurations
└── scripts/                     # hook and utility scripts
```

**Critical:** components must be at the plugin root, not inside `.claude-plugin/`. Only `plugin.json` belongs in `.claude-plugin/`. A `CLAUDE.md` at the plugin root is NOT loaded as project context — contribute context through skills, agents, and hooks instead.

### Common loading issues (diagnostic catalog)

Source: `https://code.claude.com/docs/en/plugins-reference#debugging-and-development-tools`

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Plugin not loading | Invalid `plugin.json` | Run `claude plugin validate` or `/plugin validate` |
| Skills not appearing | Wrong directory structure | Ensure `skills/` is at the plugin root, not in `.claude-plugin/` |
| Hooks not firing | Script not executable | `chmod +x script.sh` |
| MCP server fails | Missing `${CLAUDE_PLUGIN_ROOT}` | Use the variable for all plugin paths |
| Path errors | Absolute paths used | All paths must be relative and start with `./` |
| LSP `Executable not found in $PATH` | Language server not installed | Install the binary (e.g., `npm install -g typescript-language-server`) |

**Debug command:** `claude --debug` shows which plugins load, errors in manifests, skill/agent/hook registration, MCP initialization.

## This plugin's conventions (project-specific overlay)

These conventions are this plugin's house style. They sit on top of the upstream format; when the format permits a choice, these are the tiebreakers.

### Promote-through-production workflow

Changes to skills follow a two-stage path:

1. **Internal validation in `.claude/skills/<name>/SKILL.md`.** New skills, or significant changes to existing skills, start here. `.claude/skills/` is the project-scope directory — the skill is available to anyone working in this plugin's repo but is NOT exported to consumers of the plugin. Validate the skill works as intended; iterate.
2. **Promote to `skills/<name>/SKILL.md` and register in `.claude-plugin/plugin.json`.** When the skill is ready to ship to consumers, move it to `skills/` (the plugin's exported skills directory) and add an entry to the `skills` array in `.claude-plugin/plugin.json` (alphabetical position is preferred for readability; see existing entries for the convention).

The two-stage path exists because plugin updates ripple to every consumer; shipping a broken or incomplete skill is high-cost to undo. Skills with no external audience yet (e.g., `agents-update`, `best-practices-sync`) live permanently in `.claude/skills/`.

### Agent file conventions

- **Vendored origin:** all files in `agents/` originated from `VoltAgent/awesome-claude-code-subagents` (MIT). Per RFC 2026-05-10-refactor-command, the project owns these files locally now. Newly added agents that originate locally do not need the attribution comment; agents that were originally vendored should have a header comment near the top:

  ```
  <!-- Originally from VoltAgent/awesome-claude-code-subagents (MIT). Customized for this project. -->
  ```

- **No `tools:` field unless you can name every tool as a real Claude Code tool.** Aspirational lists (e.g., `tools: ast-grep, semgrep, eslint, prettier, jscodeshift`) silently restrict the agent to a non-existent toolset. Default: omit the field; inherit the standard tool set.
- **Default model is `sonnet`; upgrade to `opus` for reasoning-heavy work (architecture, RFCs, deep refactors, ambiguous problem spaces); downgrade to `haiku` for exploration, file search, simple lookups, and formatting tasks.** Start at `sonnet` and adjust based on the agent's purpose.

### Skill registration in `plugin.json`

`.claude-plugin/plugin.json` lists exported skills under the `skills` array. Add new entries in roughly alphabetical position. Internal skills under `.claude/skills/` are NOT registered there — they are discovered as project-scope skills, not plugin-scope skills.

### Where CLAUDE.md lives

This plugin maintains two `CLAUDE.md` files:

- `CLAUDE.md` (plugin root) — instructions for working in *this plugin's repo* (developing the plugin itself).
- `.claude-plugin/CLAUDE.md` — the seed `CLAUDE.md` that `/sync` writes to consuming projects.

When a convention should apply both inside the plugin's own repo AND in projects that consume the plugin, update both. When a convention is local to plugin development, update only the root `CLAUDE.md`. Per the upstream plugin docs, `CLAUDE.md` at the plugin root is NOT auto-loaded as plugin context for consumers; instructions for consumers must be shipped via the seed file (handled by `/sync`).

### Agent delegation pattern

The plugin's `CLAUDE.md` has an "Agent delegation" table mapping `Task → Agent`. The main agent consults this table when deciding whom to delegate to. When you add a new agent, also add a row to that table so the routing is documented.

### RFC-first for non-trivial changes

Per `docs/rfc-process.md`, anything beyond a localized bug fix should go through `/rfc-new`. New skills, new agents, hook changes, and `plugin.json` structural edits all qualify.

## How this agent stays current

This system prompt embeds quoted content from four upstream Claude Code documentation pages. Claude Code's plugin format evolves; the embedded content can go stale. The upstream docs are continuously updated and not versioned; the only signal that this agent has drifted is content divergence between the embedded reference and a current fetch.

**Refresh procedure** (run when Claude Code releases a notable update, or when this agent's guidance no longer matches observed behavior):

1. Fetch each of the following URLs (prefer `mcp__exa__crawling_exa`; fall back to `WebFetch` if Exa is unavailable):

   - `https://code.claude.com/docs/en/plugins-reference`
   - `https://code.claude.com/docs/en/skills`
   - `https://code.claude.com/docs/en/sub-agents`
   - `https://code.claude.com/docs/en/hooks`

2. Diff the fetched content against the corresponding sections of this agent body:

   - "`.claude-plugin/plugin.json` manifest" ← plugins-reference (sections: "Plugin manifest schema", "Required fields", "Metadata fields", "Component path fields", "Environment variables")
   - "`SKILL.md` frontmatter" ← skills (sections: "Frontmatter reference", "Available string substitutions", "Skill content lifecycle", "Control who invokes a skill")
   - "Subagent frontmatter" ← sub-agents (section: "Frontmatter reference"; the field table that begins with `name`, `description`, `tools`, ...)
   - "`hooks/hooks.json` schema" ← plugins-reference ("Hooks" subsection) + hooks (event-list and matcher details)
   - "Plugin directory structure" ← plugins-reference ("Plugin directory structure" section)
   - "Common loading issues" ← plugins-reference ("Common issues" subsection)

3. Update the embedded content to match the upstream — quote the field tables and examples verbatim; do not paraphrase. When a field is renamed, removed, or added, update the agent body and bump the date in the next step.

4. Update the `<!-- LAST_REFRESHED: YYYY-MM-DD -->` comment at the very bottom of this agent file to today's date.

5. Commit with a Conventional Commits message: `docs(agent): refresh claude-plugin-author against upstream docs`.

The refresh is mechanical, not interpretive. If a field has changed meaning subtly (e.g., a default value flipped, or two fields' semantics merged), call that out in the commit message and consider whether the project's existing skills or agents need adjustment.

## When this agent is NOT the right tool

- **Model Context Protocol (MCP) server development.** That is a different protocol (despite the similar name). Use `mcp-developer` for MCP server/client implementations, JSON-RPC 2.0 protocol compliance, MCP tool/resource/prompt design, transport configuration. The boundary: this agent owns the `mcpServers` field in `plugin.json` and the `.mcp.json` file layout (the *manifest config* by which a plugin declares its MCP servers); it does not own the server implementations themselves.
- **General implementation tasks unrelated to plugin format** (writing application code, refactoring business logic, building features). Use `feature-engineer` or `refactoring-specialist`.
- **Design and architecture decisions about WHAT to build in the plugin.** Use `rfc-architect` to write an RFC first; this agent comes in once the RFC is approved and implementation begins.
- **Deep prompt-engineering craft for subagents** (system prompt structure, model-tier rationales beyond what the docs prescribe). Defer to `claude-agent-author` if/when that specialist exists. Until then, this agent covers agent definitions as a plugin component but is not the authority on prompt-construction technique.

<!-- LAST_REFRESHED: 2026-05-10 -->
````

This is the complete agent body. The file is the agent — no companion script or supporting files.

#### Step 2 — Update `CLAUDE.md` (plugin root)

Two changes to `/home/divoxx/code/bytewyrd/claude-bytewyrd-workflow/CLAUDE.md`.

**Change 2a — Agent delegation table.**

The current table reads:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Debugging | debugger |
```

Add a row for plugin authoring directly after `Code reviews`, so the table becomes:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Plugin authoring (skills, agents, hooks, plugin.json) | claude-plugin-author |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Debugging | debugger |
```

The `Plugin authoring` row is placed directly after `Code reviews` and before `Refactoring (deliberate)`. The ordering is: build → review → plugin-authoring → refactor → architect → docs → debug.

**Change 2b — Workflow subsection.**

Insert a new subsection in the "Workflow" block immediately after `### Considering /refactor` and before `### Session end`:

```markdown
### Authoring plugin components

When creating a new skill, adding a new agent, wiring up a hook, modifying `.claude-plugin/plugin.json`, or debugging why a plugin component isn't resolving, delegate to the `claude-plugin-author` agent. It owns deep knowledge of the Claude Code plugin format (skill and subagent frontmatter, hook event/matcher schema, `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_SKILL_DIR}` substitutions, manifest schema) and this plugin's promote-through-production convention (start new skills in `.claude/skills/` for internal validation, then promote to `skills/` and register in `plugin.json` when ready to ship to consumers).

The agent's reference content is built from the upstream Claude Code documentation, quoted verbatim with refresh-procedure instructions in the agent body. When the format changes, refresh the agent rather than re-deriving conventions from neighboring files.
```

**Where to insert this subsection precisely:** in the current `## Workflow` section, the order is `### Session start`, `### During work`, `### Considering /refactor`, `### Session end`. Place "Authoring plugin components" between `### Considering /refactor` and `### Session end`. Both `### Considering /refactor` and `### Authoring plugin components` are about "things to consider mid-session"; they are siblings.

#### Step 3 — Update `.claude-plugin/CLAUDE.md`

`.claude-plugin/CLAUDE.md` is the plugin-developer guidance file that loads when working inside this plugin's own checkout. It is NOT the seed `CLAUDE.md` shipped to consumers (that template lives inside `skills/sync/SKILL.md` — see Step 4). Only the workflow subsection from Change 2b is mirrored here, because this file does not currently contain an Agent delegation table.

**Insert the workflow subsection from Change 2b** into `.claude-plugin/CLAUDE.md`'s "Development Workflow" section. The current section structure has subsections like `### Step 1 — Session start: new work or continuation?` and `### Step 2 — Starting new work`. Add a new `### Authoring plugin components` subsection at the end of the "Development Workflow" section (after `### Step 2 — Starting new work`), with the exact content from Change 2b above.

Do NOT add an Agent delegation table to `.claude-plugin/CLAUDE.md`; the plugin root's `CLAUDE.md` (updated in Step 2) remains the canonical location for that table. Adding a table here would create two sources of truth and risk drift.

#### Step 4 — Update `skills/sync/SKILL.md`

`skills/sync/SKILL.md` contains the seed `CLAUDE.md` template that `/sync` writes to every consuming project. The seed includes an `## Agent delegation` section that is populated at runtime from a "Shared agents always added (once)" line further down in the skill body. This step adds `claude-plugin-author` to that list so every project that runs `/sync` after this RFC lands gets the new delegation row in its `CLAUDE.md`.

**Locate the "Shared agents always added (once)" line.** In the current `skills/sync/SKILL.md`, search for the line beginning `Shared agents always added (once):` (around line 456 at the time of writing; line numbers may shift). The current line reads:

```
Shared agents always added (once): feature-engineer (new features), code-reviewer (code reviews), rfc-architect (architecture/RFCs), documentation-writer (docs), debugger (debugging).
```

**Replace with:**

```
Shared agents always added (once): feature-engineer (new features), code-reviewer (code reviews), claude-plugin-author (plugin authoring — skills, agents, hooks, plugin.json), rfc-architect (architecture/RFCs), documentation-writer (docs), debugger (debugging).
```

The added row appears between `code-reviewer` and `rfc-architect`, matching the ordering decision in Change 2a (Step 2). Per `skills/sync/SKILL.md`'s description, this list is merged with language-specific rows when sync renders the table.

No changes are needed to the static `## Agent delegation` template block in `skills/sync/SKILL.md` (the `<AGENT_TABLE_ROWS>` placeholder is what gets substituted; the substitution data is what we changed above).

**Important:** `skills/sync/SKILL.md` also contains a prose paragraph around line 446 that enumerates the shared agents by name. This prose list must also be updated to include `claude-plugin-author (plugin authoring — skills, agents, hooks, plugin.json)` between `code-reviewer` and `rfc-architect`, consistent with the data-line update above.

#### Step 5 — Verification

After all changes, run these checks:

1. **Agent file exists and parses (first 5 lines = frontmatter):**

   ```bash
   test -f agents/claude-plugin-author.md && head -5 agents/claude-plugin-author.md
   ```

   Expected output: exactly 5 lines beginning with `---`, then `name: claude-plugin-author`, then a single (very long) `description:` line, then `model: opus`, then `color: green`. The `description:` line is too long to reproduce here verbatim; the structure is what matters. Use this stricter follow-up check to confirm key invariants:

   ```bash
   grep -c '^name: claude-plugin-author$' agents/claude-plugin-author.md
   grep -c '^model: opus$' agents/claude-plugin-author.md
   grep -c '^color: green$' agents/claude-plugin-author.md
   ```

   Expected output: each grep returns `1`.

2. **Agent has no `tools:` field** (so it inherits the standard tool set):

   ```bash
   grep -c '^tools:' agents/claude-plugin-author.md
   ```

   Expected output: `0`

3. **Agent body includes the refresh procedure marker:**

   ```bash
   grep -F 'LAST_REFRESHED:' agents/claude-plugin-author.md
   ```

   Expected output:

   ```
   <!-- LAST_REFRESHED: 2026-05-10 -->
   ```

4. **Agent body cites all four primary-source URLs at least once each:**

   ```bash
   for url in \
     'https://code.claude.com/docs/en/plugins-reference' \
     'https://code.claude.com/docs/en/skills' \
     'https://code.claude.com/docs/en/sub-agents' \
     'https://code.claude.com/docs/en/hooks'; do
     count=$(grep -cF "$url" agents/claude-plugin-author.md)
     echo "$count  $url"
   done
   ```

   Expected: each line has a count `>= 1`. Total across all four URLs should be `>= 6` (some URLs appear in multiple sections — e.g., plugins-reference appears in the manifest, hooks, directory-structure, and diagnostics sections).

5. **Plugin-root CLAUDE.md table includes the new row:**

   ```bash
   grep -F 'Plugin authoring (skills, agents, hooks, plugin.json)' CLAUDE.md
   ```

   Expected output:

   ```
   | Plugin authoring (skills, agents, hooks, plugin.json) | claude-plugin-author |
   ```

6. **Plugin-root CLAUDE.md workflow includes the new subsection:**

   ```bash
   grep -F '### Authoring plugin components' CLAUDE.md
   ```

   Expected output:

   ```
   ### Authoring plugin components
   ```

7. **Plugin-developer CLAUDE.md (`.claude-plugin/CLAUDE.md`) includes the workflow subsection:**

   ```bash
   grep -F '### Authoring plugin components' .claude-plugin/CLAUDE.md
   ```

   Expected output:

   ```
   ### Authoring plugin components
   ```

8. **`skills/sync/SKILL.md` includes `claude-plugin-author` in the shared-agents list:**

   ```bash
   grep -F 'claude-plugin-author (plugin authoring' skills/sync/SKILL.md
   ```

   Expected output: the line containing `claude-plugin-author (plugin authoring — skills, agents, hooks, plugin.json)`.

9. **No `plugin.json` change is needed** (agents are auto-discovered from `agents/`):

   ```bash
   grep -F 'claude-plugin-author' .claude-plugin/plugin.json
   ```

   Expected output: empty (no registration required; this verifies we did NOT incorrectly add the agent to plugin.json).

10. **Manual smoke test.** Plugin agents in this repo's own `agents/` directory are picked up the next time Claude Code loads the plugin. If you are running Claude Code in this plugin's own checkout, restart Claude Code to pick up the new agent (live-change detection is documented for skill directories but is not documented for agent directories; restart is the safe default). If the plugin is consumed from elsewhere via the marketplace, run `claude plugin update bytewyrd` and restart Claude Code.

    - Type `/agents` in Claude Code; confirm `bytewyrd:claude-plugin-author` appears in the agent list with the disambiguating description (mentioning NOT MCP).
    - Ask the main agent: "Add a new skill called `hello` that prints hello world." Confirm the main agent invokes `bytewyrd:claude-plugin-author` (visible in the status line / transcript) rather than directly authoring the file from scratch.
    - Ask the main agent: "Why might a skill at `skills/foo/SKILL.md` not appear in the `/` menu?" Confirm the agent (if invoked) cites authoritative reasons from its embedded reference (directory placement, frontmatter `user-invocable: false`, `disable-model-invocation: true`, namespacing collision) rather than guessing.
    - Ask the main agent: "Build an MCP server that connects to PagerDuty." Confirm the main agent invokes `mcp-developer`, NOT `claude-plugin-author` — the disambiguation in the description should be load-bearing here.

    If any of these steps fail, the most likely causes (in order) are: (a) the `description` was not specific enough for auto-delegation — tighten the trigger phrases in the description; (b) the `CLAUDE.md` table row was not added or was placed inconsistently; (c) the agent file's frontmatter has a syntax error preventing discovery (run `claude --debug` and check for plugin-loading errors); (d) the disambiguation against `mcp-developer` was too weak — strengthen the "NOT for MCP" language in the description.

## Risks and open questions

- **Risk: agent over-invocation on trivial questions.** A well-written `description` invites Claude to delegate; if the description is too inclusive, the agent gets called for trivial questions ("what does `description` do in skill frontmatter?") where the round-trip cost exceeds the value. **Mitigation:** the description leads with "Use when creating a new skill from scratch, adding a new agent, wiring up a hook, debugging why a skill isn't resolving..." — verb-led, concrete tasks. Trivial reference questions ("what does field X do?") can still be answered from the main agent's general knowledge or by reading an existing skill. If over-invocation shows up in real use, tighten the description to require a stated authoring or debugging intent.

- **Risk: agent goes stale.** Documented and accepted; mitigation is the refresh procedure in the agent body (see Drawbacks).

- **Risk: maintainer skips the refresh procedure.** The agent will then guide future contributors based on stale field semantics. **Mitigation:** the `LAST_REFRESHED:` comment at the bottom of the agent body is visible in any diff or read. A future RFC can add a hook or CI check that warns when the date is more than N months old, but that automation is out of scope for this RFC. **Resolution:** mitigation accepted as-is; the visible date and the procedure documentation are the human-readable signal.

- **Risk: confusion with the proposed `claude-agent-author` Draft RFC.** This is named `claude-plugin-author` deliberately so future `claude-agent-author` (focused on the subagent format and prompt-engineering craft specifically) has a non-overlapping name. The boundary, also stated in the agent body: this agent covers agent definitions as a *plugin component*; the future `claude-agent-author` covers agent-authoring *craft*. **Mitigation:** the agent's "When this agent is NOT the right tool" section makes the deferral explicit. When the future RFC lands, it should land with an edit to this agent's "When NOT to use" section to make the routing tighter.

- **Open question: should the agent also write to `docs/`?** The plugin has `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md` — when a new skill ships, should those docs auto-update? **Resolution:** out of scope here. `documentation-writer` exists for doc work; if a plugin change requires a doc update, the main agent's existing "after-commit" hooks (see `.claude/settings.json`) already prompt for it. This agent does not own `docs/`.

- **Open question: should the agent have memory enabled (`memory: project`)?** With memory enabled the agent could accumulate project-specific patterns (e.g., "this project's CLAUDE.md uses `###` for workflow subsections, not `##`") across sessions. **Resolution within this RFC:** no — start without memory. Memory adds state that needs management; the agent's embedded reference plus the `CLAUDE.md` table is sufficient for the use cases this RFC scopes. A future RFC can enable memory if real-world use shows accumulated patterns would help.

- **Open question: should the agent's `description` field include `${CLAUDE_SKILL_DIR}` or other substitution placeholders?** The skills documentation says substitutions are processed in skill content; subagent descriptions are not skill content. **Resolution:** no substitutions in the agent file's frontmatter; the agent body uses real values (e.g., literal `${CLAUDE_PLUGIN_ROOT}` text that the agent references when answering format questions, not substitution). This is consistent with how the existing agents in `agents/` are written.

- **Open question: what triggers a refresh in practice?** Without automation, refreshes depend on a human noticing that the docs have changed. **Resolution:** the agent body documents the refresh procedure; the cadence is "when Claude Code releases a notable update, or when this agent's guidance no longer matches observed behavior." A `/loop`-driven scheduled refresh is plausible but out of scope (and would require a separate RFC because it changes the project's automation surface).

- **Risk: the agent gives advice that disagrees with what an existing skill or agent in the repo actually does.** Example: an older skill uses `disable-model-invocation` in a way the agent would recommend against. The agent should not silently "fix" existing files; it should surface the divergence. **Mitigation:** the operating instructions in the agent body include "Default to advice; write only on request" (step 4 in "How to operate"). When the agent encounters a divergence between its own guidance and an existing file, it reports the divergence to the parent rather than performing an edit.

## Relationship to other RFCs

This RFC depends on, complements, and defers to several other RFCs:

- **2026-05-10-refactor-command** (status: Done) — established the local-ownership posture for `agents/` files (vendored from VoltAgent/awesome-claude-code-subagents under MIT, now permanent local copies with attribution comments) and removed the `/agents-update` skill. This RFC continues that posture: `claude-plugin-author` is a newly-authored local agent (not vendored), so it does NOT need the MIT-attribution comment, and there is no upstream-sync risk because no auto-update mechanism exists. The convention from 2026-05-10-refactor-command is encoded in the agent body's "Agent file conventions" section so the agent can apply it consistently when it scaffolds future agents.

- **Future RFC — `claude-agent-author` (Draft RFC).** The Draft RFC calls for a specialist on the subagent format and agent-authoring craft. `claude-plugin-author` covers agent definitions as a plugin component (the frontmatter, file location, registration); `claude-agent-author` (when it ships) will cover the deeper craft (prompt structure, model-tier rationales, tool-selection patterns informed by primary-source research). The boundary is stated in this agent's "When this agent is NOT the right tool" section so the routing tightens when the new agent arrives.

- **Future RFC — audit all agent definitions with `claude-agent-author` (Draft RFC).** That RFC depends on the `claude-agent-author` agent existing first and is not blocked by this RFC. When it runs, `claude-plugin-author` will be one of the agents it audits — the format-only layer this agent owns will not change; only the deeper craft layer will get a separate authority.

- **`/sync` skill.** The seed `CLAUDE.md` written to consuming projects by `/sync` is built from a template that lives inside `skills/sync/SKILL.md`. Step 4 of this RFC updates the "Shared agents always added (once)" line in that template so consuming projects pick up the `claude-plugin-author` delegation row on their next `/sync` invocation. Projects that have already run `/sync` will only pick up the change when they re-run `/sync`; the existing bootstrap-content-version mechanism (`SessionStart` hook in `.claude/settings.json`) will warn them to do so. No backfill mechanism is needed; the change is forward-only.

- **`/rfc-implement` skill.** This RFC, once approved, is implemented by `/rfc-implement` (which spawns `feature-engineer` per the RFC process). The implementation is mechanical given the file-structure table and steps. `feature-engineer` does not need to consult `claude-plugin-author` while implementing this RFC, because the RFC content is what the agent will *become* — bootstrapping the agent does not require the agent.
