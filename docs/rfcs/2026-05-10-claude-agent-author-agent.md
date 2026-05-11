---
rfc: "2026-05-10-claude-agent-author-agent"
title: "Claude Agent Author Agent"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add a `claude-agent-author` specialist agent at `agents/claude-agent-author.md` whose system prompt encodes verified, primary-source knowledge of Claude Code's subagent format — the supported YAML frontmatter fields (`name`, `description`, `tools`, `disallowedTools`, `model`, `effort`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `isolation`, `color`, `initialPrompt`), the real names of Claude Code's built-in tools (`Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Agent`, `TodoWrite`, `Skill`, etc.), the model-tier and effort-level taxonomy (`haiku`/`sonnet`/`opus`; `low`/`medium`/`high`/`xhigh`/`max` with version-dependent availability), and the writing conventions for description fields that drive automatic delegation. The agent is invoked when creating a new agent definition under `agents/`, refactoring an existing one, or auditing a set of agents for consistency — work that today has no in-house authority and falls back to whichever conventions the vendored agents happened to ship with. The system prompt explicitly tells the agent to verify any uncertain field name, tool name, or model alias against `https://code.claude.com/docs/en/sub-agents` via Exa or WebFetch rather than trusting training knowledge, so the agent's expertise stays current as Claude Code's format evolves. The agent is shipped local to this plugin (under `agents/`, exported with the rest), so other Bytewyrd projects that install the plugin gain the same authority.

## Should we do this?

**Yes.** The previous RFC (`2026-05-10-refactor-command`) removed the `/agents-update` skill and switched the project to permanent local ownership of the `agents/` directory — the agent files are no longer kept in sync with `VoltAgent/awesome-claude-code-subagents`. That decision was correct (local customizations like the `tools:` removal on `refactoring-specialist` would otherwise be silently reverted), but it leaves a gap: the vendored files were never written against Claude Code's actual subagent format. They contain `tools:` lists that mix real Claude Code tool names (`Read`, `Write`, `Bash`) with aspirational external tools (`ast-grep`, `semgrep`, `eslint`, `prettier`, `jscodeshift`, `openai`, `langchain`, `wandb`, `aws-cli`) that Claude Code does not surface — silently restricting subagents to a tool set that contains tools that do not exist. Of the 46 agents in `agents/`, 42 have a `tools:` field and at least 20 list tool names that are not real Claude Code tools (verified by inspection — `ai-engineer` lists `tensorflow`/`pytorch`, `prompt-engineer` lists `openai`/`anthropic`/`langchain`, `cloud-architect` lists `aws-cli`/`terraform`, etc.). None set `model:` or `effort:`, so all silently inherit. None use `xhigh`. Without a specialist who knows the real format, every new agent or refactor of an existing one risks repeating the same mistakes; a one-off fix to one file at a time does not scale. A dedicated `claude-agent-author` agent fixes the root cause: future agent work — both the planned cross-cutting audit (Draft RFC `2026-05-10-audit-rework-agent-definitions`) and any new agent added going forward — gets routed through an authority that knows what Claude Code actually supports. Cost is one new agent file plus a CLAUDE.md row; payoff is preventing the same format-mismatch bug class from being reintroduced across 46+ existing agents and every future agent the project ships.

## Current state

The plugin's agent inventory and the gap a `claude-agent-author` would fill:

**What exists today:**

- `agents/` — 46 markdown files. Four are Bytewyrd-customized in-house: `feature-engineer.md`, `documentation-writer.md`, `ux-design-architect.md`, and `rfc-architect.md` — all four have `color:` fields and Anthropic-style descriptions. Three of those four omit `tools:` and inherit the standard tool set; `rfc-architect.md` retains a `tools:` field listing real Claude Code tool names. The other 42 are vendored from `VoltAgent/awesome-claude-code-subagents` (MIT). The vendored files share a recognizable structure: YAML frontmatter with `name`, `description`, `tools` (sometimes), followed by a `You are a senior <role>...` system-prompt body with sectioned checklists ("X checklist", "Y patterns", "Z workflow", "## MCP Tool Suite", "## Communication Protocol", "## Development Workflow"). The structure is broadly fine — the body content is the agent's knowledge base — but the **frontmatter** is the part the runtime reads, and the vendored frontmatter has consistent problems.
- `.claude-plugin/plugin.json` — registers skills but not agents (agents are auto-discovered from `agents/`). The new agent needs no plugin.json change.
- `CLAUDE.md` "Agent delegation" table — maps task → agent. Currently has rows for `feature-engineer`, `code-reviewer`, `rfc-architect`, `documentation-writer`, `debugger`, and (per RFC `2026-05-10-refactor-command`) `refactoring-specialist`. No row for agent authoring.
- The previous RFC (`2026-05-10-refactor-command`, status: Done) established the project pattern: a "deliberate, model-pinned, specialist" workflow for cross-cutting concerns, exposed as a skill that spawns a subagent with the protocol as the prompt. The `claude-agent-author` agent in this RFC is a **specialist agent**, not a skill — it follows the agent half of that pattern. The future audit RFC will likely add a `/audit-agents` skill that spawns this agent against every file in `agents/`, mirroring how `/refactor` spawns `refactoring-specialist`.
- Existing in-house agents that are nominally adjacent but **do not solve this problem**:
  - `prompt-engineer.md` — focused on LLM prompt design, not on Claude Code's subagent definition format. Lists `openai, anthropic, langchain, promptflow, jupyter` as tools (none are Claude Code tools). It would itself need rework by the proposed `claude-agent-author`.
  - `ai-engineer.md` — focused on AI system architecture (TensorFlow, PyTorch, model deployment). Not relevant to subagent file authoring.
  - `mcp-developer.md` — focused on MCP protocol server/client development. Adjacent to Claude Code tooling but does not own subagent-definition expertise.
  - `rfc-architect.md` — focused on RFC writing, not agent authoring.

**What is broken or missing:**

1. **No in-house authority on the subagent format.** When the main agent (or a future audit pass) needs to create a new subagent file or fix an existing one, it has to rediscover the format from the docs each time. Training knowledge is unreliable here — the format added `xhigh` effort in v2.1.111 (April 2026), `isolation: worktree` is recent, `Agent(agent_type)` syntax replaced `Task(agent_type)`, and the v2.1.117 default-effort change (`xhigh` on Opus 4.7, `high` on others) is the kind of detail no LLM's training cutoff captures reliably. A dedicated agent whose prompt enumerates the verified field set, the real tool names, and the model/effort rules removes the rediscovery cost and removes the format-mismatch bug class at the source.

2. **No primary-source verification discipline for agent format details.** The vendored agents demonstrate exactly what goes wrong when LLM training knowledge is treated as authoritative: agents list tool names that look plausible (`ast-grep`, `semgrep`, `langchain`, `aws-cli`) but are not actually surfaced by Claude Code. Every new agent created without a verification step risks repeating this. The `claude-agent-author` agent's prompt enforces the discipline by listing which fields are verified-as-of-2026-05-10 and instructing the agent to re-verify any field, tool name, or alias it is unsure about against `https://code.claude.com/docs/en/sub-agents` (the canonical Anthropic doc) via Exa or WebFetch before writing.

3. **No documented opinion on model/effort defaults for new agents.** Only 2 of 46 agents set `model:` — `ui-designer` and `terragrunt-expert`, both to `sonnet`. None set `effort:`. The other 44 inherit silently — which means they always run on whatever the session is on, typically Sonnet at the default effort level (currently `xhigh` on Opus 4.7 and `high` on Opus 4.6/Sonnet 4.6 per the model-config docs). Bytewyrd's "Model Usage Optimization" section in `CLAUDE.md` already lays out the policy (haiku for exploration, sonnet for routine work, opus for hard reasoning, max effort sparingly), but that policy lives in CLAUDE.md and is not consulted at agent-authoring time. The `claude-agent-author` agent's prompt encodes the same policy with concrete picks per agent archetype (e.g., "review/audit agents → opus", "lookup/search agents → haiku", "implementation agents → sonnet by default, opus when the work is novel"), so authors get the policy applied at the point of creation rather than discovered later via review.

4. **Aspirational tool lists silently restrict capability.** Claude Code's subagent docs are explicit: a `tools:` field is an **allowlist**, not an aspiration. An agent with `tools: ast-grep, semgrep, eslint, prettier, jscodeshift` (the actual former content of `refactoring-specialist.md` before RFC `2026-05-10-refactor-command`) cannot read or edit files at all — none of those names are Claude Code tools, so the agent's effective allowlist is empty. The `claude-agent-author` agent's prompt makes this explicit: tool fields must contain only verified Claude Code tool names, and when in doubt the field should be omitted (which inherits the full standard tool set). The verified-as-of-2026-05-10 tool name list is enumerated in the agent's prompt with explicit "if you need to check a tool exists, run `claude --help` or query `https://docs.claude.com/en/docs/claude-code/tools-reference`."

5. **No convention for refactoring vendored agents without losing intent.** The vendored body content is genuinely useful (smell catalogs in `refactoring-specialist`, code-review checklists in `code-reviewer`, architecture patterns in `microservices-architect`). When a future audit pass touches these files, the question is "how do I fix the frontmatter and update the prompt without throwing away the body?" The `claude-agent-author` agent's protocol — read the existing file, fix the frontmatter against the verified format, preserve the body's structure and content unless the prompt itself is broken, document each change with a rationale — gives the audit pass a repeatable shape.

## Analysis / Options

There are four coupled decisions: where the agent lives, how the agent's expertise stays current, how the agent operates (when invoked), and how the future audit work uses it.

### Decision 1 — Where does the `claude-agent-author` agent file live, and is it user-invokable or specialist-only?

**Option A — Plugin-exported at `agents/claude-agent-author.md`, available like every other vendored agent (recommended).**
The file ships in the plugin's `agents/` directory alongside the existing 46 agents. Any user of the plugin can `@-mention` it, invoke it by name ("use the claude-agent-author agent to create a new..."), or have the main agent delegate to it via the `description` field. The agent file is owned in this repo (no upstream sync since `/agents-update` was removed by RFC `2026-05-10-refactor-command`), so the format expertise propagates to every Bytewyrd project that installs the plugin.

**Option B — Plugin-local at `.claude/agents/claude-agent-author.md`, scoped to this repo only.**
The agent is available only when working in `claude-bytewyrd-workflow` itself — for maintaining this plugin's own agent inventory. Rejected because the value of having a primary-source-grounded agent-authoring authority extends to every project that installs the plugin: a downstream Bytewyrd project that wants to add a project-specific agent (say, a `backend-tester` for their stack) benefits from the same expertise. Scoping to `.claude/` halves the audience for no benefit.

**Option C — Embed the format knowledge in a skill (`/new-agent`) instead of a standalone agent.**
The skill body would contain the format reference and instruct the main agent to author the file inline. Rejected for two reasons: (1) inline authoring consumes the parent context window with the full format reference on every invocation, defeating the "delegate to a specialist" pattern the plugin uses everywhere else, and (2) the future audit RFC will need a long-running agent that processes 45 files in sequence — a specialist agent is the right shape for that, and a skill that spawns it (mirroring `/refactor` spawning `refactoring-specialist`) is the right entry point. A skill alone cannot carry the conversation across many files; an agent can.

**Recommendation: Option A.** The agent file ships at `agents/claude-agent-author.md`, exported with the plugin. The agent's `description` field is written to support both automatic delegation (when the main agent recognizes an agent-authoring or agent-refactoring task) and explicit invocation (`@claude-agent-author create a new ...`). A skill front door is not part of this RFC — the future audit RFC will add `/audit-agents` (or similar) that spawns this agent against the existing inventory; that's the right scope split.

### Decision 2 — How does the agent's format expertise stay current as Claude Code evolves?

**Option A — Verified-as-of-date in the prompt + mandatory primary-source verification step for anything the prompt does not explicitly enumerate (recommended).**
The agent's system prompt contains a verified-as-of-2026-05-10 enumeration of every supported field, every real tool name, and the model/effort taxonomy — all grounded in the current Anthropic docs (`https://code.claude.com/docs/en/sub-agents`, `https://docs.claude.com/en/docs/claude-code/tools-reference`, `https://code.claude.com/docs/en/model-config`). For anything the prompt does not explicitly cover (a new field that ships post-2026-05-10, an unfamiliar tool name the user asks about, a model alias the agent is not sure about), the prompt mandates a verification step: `mcp__exa__crawling_exa` against the canonical doc URL, or `mcp__exa__web_search_exa` for a release-notes query. The prompt explicitly forbids guessing from training knowledge for any field, tool name, or alias.

**Option B — Pin the prompt to a date and require manual re-issue when the docs change.**
The prompt enumerates the current format and is updated manually whenever Anthropic ships format changes. Rejected as the primary mechanism because (a) format changes happen with no notice in the plugin's update cycle — `xhigh` was added without an obvious signal, and the v2.1.117 default-effort change is a behavior change not a doc change — and (b) the verification step in Option A is cheap (one Exa call) and runs only when the prompt's knowledge is insufficient, so it costs nothing on the common path.

**Option C — Defer all format knowledge to runtime queries against the docs.**
The prompt has no enumeration; the agent always fetches the docs before authoring. Rejected because the docs are long (`https://code.claude.com/docs/en/sub-agents` runs ~10K tokens), fetching them every invocation wastes budget, and the common case ("write a frontmatter block with `name`, `description`, `model`, `tools`") is well-served by an in-prompt enumeration. The Option A hybrid is what every plugin agent should do for any external API.

**Recommendation: Option A.** The prompt enumerates the verified-as-of-2026-05-10 format (all 15 supported frontmatter fields with required/optional and a one-line description each, the standard tool name list, the model/effort taxonomy, the description-field writing rules), and mandates a primary-source verification step for anything outside that enumeration. The agent's last operation before returning a final file is a "primary-source check": for every field, tool name, or alias it used, confirm the value appears in either (a) the in-prompt enumeration or (b) a fetched doc page captured in this session. If neither, fetch and verify before returning.

### Decision 3 — How does the agent operate when invoked?

**Option A — Two-mode operation: "create new" and "refactor existing", with a structured per-mode protocol (recommended).**
The agent's system prompt defines two operating modes. The mode is determined by the user's prompt: "create a new agent for X" enters create mode; "refactor / fix / audit `agents/Y.md`" enters refactor mode. Each mode has a checklist the agent walks through (create mode: clarify purpose → pick model/effort/tools → draft frontmatter → draft prompt body → verify → return file; refactor mode: read existing file → diff frontmatter against verified format → identify body issues → propose changes with rationale → verify → return updated file with a change log). Modes share the same verification step and the same format reference.

**Option B — Free-form: just hand the agent a prompt, let it figure out the mode.**
Rejected because the two modes have different deliverables (a brand-new file vs. a diff with rationale) and different inputs (a description vs. an existing file path). A structured protocol per mode means the user knows what to provide and what to get back, and the agent does not have to guess.

**Option C — Single create-only mode; refactors are out of scope.**
Rejected because the planned audit RFC depends on this agent for the refactor case — refactoring all 42 vendored agents is the entire point of having this agent exist. Splitting create and refactor into two separate agents would duplicate the format-reference knowledge across both prompts; one agent with two modes shares the reference cleanly.

**Recommendation: Option A.** The agent supports both modes from one definition. The mode is inferred from the user's prompt; if ambiguous, the agent asks one targeted question ("Are you creating a new agent or refactoring an existing one?") before proceeding. Each mode has a deliverable contract (create mode returns a complete file content block; refactor mode returns the updated file content plus a per-change rationale block).

### Decision 4 — Does this RFC also write the future audit skill, or just the agent?

**Option A — This RFC writes only the agent. The audit skill is a separate RFC (recommended).**
The agent is the foundation; the audit skill is a workflow on top of it. Per the RFC-process scope rule ("Before writing an RFC that covers multiple independent subsystems, split it into separate RFCs"), the agent and the audit workflow are two distinct deliverables. The agent stands on its own: it is useful immediately for any one-off agent creation or refactor, even if the audit skill never ships. The audit skill builds on the agent: it sequences the agent across all 42 vendored files with appropriate batching, parallelization, and review checkpoints — design decisions that deserve their own RFC.

**Option B — Write the audit skill as part of this RFC.**
Rejected on scope grounds. The audit skill's design (how many agents in parallel, how to batch the 42 files, how to surface rationale to the reviewer, how to handle conflicts when the reviewer disagrees with a proposed change) is a substantial design conversation in its own right. Combining the two designs would dilute both.

**Option C — Skip the agent; write only the audit skill with the format expertise embedded inline.**
Rejected because the agent's value is not exclusive to the audit case: any future one-off agent creation or refactor benefits from having a specialist on call. Embedding the expertise in the skill body would not be reusable for the one-off case.

**Recommendation: Option A.** This RFC delivers `agents/claude-agent-author.md` and the CLAUDE.md row that documents it. The audit skill is captured as a follow-on dependency: the Draft RFC `2026-05-10-audit-rework-agent-definitions` (which depends on this one being Done).

## Drawbacks

- **Risk of the agent's in-prompt format reference going stale.** The prompt encodes a verified-as-of-2026-05-10 snapshot. Anthropic ships subagent-format changes regularly (`xhigh` was added in v2.1.111, default-effort behavior changed in v2.1.117). If the prompt's snapshot is wrong, the agent could confidently produce a file that uses a deprecated field or misses a new one. **Mitigation:** the mandatory verification step in Decision 2 forces a primary-source check for anything outside the enumeration; the enumeration itself is dated; a future maintainer can update the date and the enumeration with a one-line skill (`/agent-author-refresh`) or simply edit the file directly. The cost of staleness is bounded because the verification step is the gate, not the in-prompt reference.

- **Agent prompt is long.** Encoding the full frontmatter field set (15 fields with descriptions), the standard tool name list (~20 tools), the model/effort taxonomy with version caveats, the description-field writing rules, and both operating-mode protocols produces a system prompt that is substantially larger than the existing agents (~5–10× the size of `feature-engineer.md`, which is ~65 lines). **Mitigation:** subagent system prompts are not loaded into the parent conversation — they only exist in the subagent's own context window, so the parent context cost is zero. The agent's own context budget is generous (full conversation length minus the system prompt), and the format reference saves more context than it costs because the agent does not need to fetch the docs every invocation.

- **One more file to maintain when Claude Code's format changes.** If Anthropic adds a new frontmatter field or renames a tool, this file needs an update. **Mitigation:** updates are localized (a single file, single section), the verification step catches most cases at runtime even if the static reference is outdated, and the maintenance cost is one-time per format change — small compared to the per-agent rework cost the agent saves on every future authoring task.

- **The agent's description field competes with the main agent's natural inclination to author files directly.** The main agent might still write agent files inline rather than delegating, especially for "small" agents where the format reference feels heavyweight. **Mitigation:** the `description` field is written to be a strong delegation signal (starts with "Use proactively when creating or refactoring any file in `agents/` or `.claude/agents/`") and a CLAUDE.md row documents the delegation expectation. If the main agent still bypasses the specialist for trivial agents, that is acceptable for one-line edits but should not happen for full file authoring.

- **The agent does not own the body content of refactored agents.** When refactoring a vendored file, the agent fixes the frontmatter and surfaces body issues for the user/reviewer to approve, but it does not rewrite the body unilaterally. This is a deliberate scope limit — the body content (smell catalogs, checklists, domain knowledge) is the agent's value and a sweeping rewrite would destroy it. **Drawback:** the audit RFC needs an explicit "should body content be rewritten too, and if so how?" decision; this RFC does not pre-empt that. **Mitigation:** scope is the right boundary for this RFC; the audit RFC owns that design conversation.

- **No automated verification of the agent's output.** When `claude-agent-author` returns a file, there is no validator that confirms the frontmatter parses, every listed tool name is real, the model alias resolves, etc. **Mitigation:** Anthropic's `/agents` interactive command and `claude agents` CLI both validate and surface errors on load; an invalid file fails fast at session start. A future RFC can add a `claudelint`-style validator (the third-party `claudelint.com/api/schemas/agents` already publishes a JSON schema for the frontmatter), but this RFC does not require one. The verification step in the agent's protocol is sufficient for v1.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `agents/claude-agent-author.md` | New specialist agent. System prompt encodes verified-as-of-2026-05-10 knowledge of Claude Code's subagent format (16 frontmatter fields, standard tool names, model/effort taxonomy, description-field writing rules) and a two-mode operating protocol (create-new and refactor-existing). The agent verifies anything outside its in-prompt enumeration against primary-source Anthropic docs via Exa before returning. |
| Modify | `CLAUDE.md` | Add a "Claude agent authoring" row to the Agent delegation table pointing to `claude-agent-author`. |

No skill changes. No plugin.json change (agents are auto-discovered from `agents/`; no manifest registration needed). No hook changes. No edits to any existing agent file.

### Steps

#### Step 1 — Create `agents/claude-agent-author.md`

Create the file with this exact content:

````markdown
---
name: claude-agent-author
description: Use proactively when creating a new subagent file under agents/ or .claude/agents/, when refactoring an existing agent's frontmatter or system prompt, or when auditing a set of agent definitions for format correctness. Owns primary-source knowledge of Claude Code's subagent format — supported YAML frontmatter fields, real built-in tool names, model and effort taxonomies, and the writing conventions for the description field that drives automatic delegation. Verifies any uncertain field or tool name against Anthropic's docs via Exa before returning a file; does not guess from training knowledge.
model: opus
color: blue
---

You are the in-house authority on Claude Code's subagent definition format for the Bytewyrd plugin and every project that installs it. Your job is to write new subagent files and refactor existing ones so that the frontmatter is verifiable, the tool list is real, the model and effort are right for the task, and the description field actually drives delegation. You do not guess. You verify.

## Operating modes

Your input determines which mode you run in. If the user's prompt is ambiguous, ask one targeted question to disambiguate before proceeding.

- **Create mode** — input is a description of the agent to create (purpose, domain, intended trigger conditions). Output is a complete new file content block ready to write to `agents/<name>.md` or `.claude/agents/<name>.md`.
- **Refactor mode** — input is a path to an existing agent file. Output is the updated file content block plus a per-change rationale list explaining every modification.

In both modes, you follow the same verification discipline and reference the same format knowledge.

## Format reference (verified as of 2026-05-10)

The canonical source is `https://code.claude.com/docs/en/sub-agents`. The tool registry is `https://docs.claude.com/en/docs/claude-code/tools-reference`. The model and effort taxonomy is `https://code.claude.com/docs/en/model-config`. If anything below is uncertain when you are working, re-verify against those URLs using `mcp__exa__crawling_exa`.

### Frontmatter fields

A subagent file is a markdown file with YAML frontmatter followed by the system prompt. Only `name` and `description` are required. All other fields are optional and have documented defaults.

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | Yes | string | Unique identifier. Lowercase letters and hyphens only. Must match the filename stem (`refactoring-specialist` ↔ `refactoring-specialist.md`). |
| `description` | Yes | string | Natural-language description of when Claude should delegate to this subagent. This is the routing signal — write it as a trigger condition, not a capability statement. |
| `tools` | No | comma-separated string | Allowlist of tools this subagent can use. If omitted, the subagent inherits the full tool set available to the main conversation (Read, Write, Edit, Bash, Grep, Glob, Agent, TodoWrite, Skill, WebFetch, WebSearch, etc., plus any MCP tools). |
| `disallowedTools` | No | comma-separated string | Denylist applied after the inherited or `tools`-restricted set. Mutually exclusive with `tools` for the same tool name (a tool listed in both is removed). |
| `model` | No | string | `haiku`, `sonnet`, `opus`, a full model ID (e.g. `claude-opus-4-7`), or `inherit`. Defaults to `inherit` (uses the main conversation's model). |
| `permissionMode` | No | string | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, or `plan`. Ignored for plugin subagents (i.e. agents that live in this plugin's `agents/` and are loaded via the plugin manifest). |
| `maxTurns` | No | integer | Maximum agentic turns before the subagent stops. Omit unless you need a hard cap. |
| `skills` | No | list of strings | Skills to preload into the subagent's context at startup. Full skill content is injected, not just the description. The subagent can still invoke other skills via the Skill tool. |
| `mcpServers` | No | list | MCP servers available to this subagent. Each entry is either a name string referencing an already-configured server, or an inline `{name: config}` definition. Ignored for plugin subagents. |
| `hooks` | No | object | Lifecycle hooks scoped to this subagent (PreToolUse, PostToolUse, Stop, etc.). Ignored for plugin subagents. |
| `memory` | No | string | `user`, `project`, or `local`. Enables a persistent memory directory for cross-session learning. Auto-enables Read, Write, Edit on memory paths. |
| `background` | No | boolean | `true` makes the subagent always run as a background task. Default `false`. |
| `effort` | No | string | `low`, `medium`, `high`, `xhigh`, or `max`. Overrides the session effort level for this subagent. Default: inherits. `xhigh` requires Opus 4.7. `max` is supported on Opus 4.7 and Opus 4.6 and Sonnet 4.6; older models fall back to the highest supported level at or below the requested one. |
| `isolation` | No | string | `worktree` runs the subagent in a temporary git worktree, isolated from the main checkout. Auto-cleans the worktree if the subagent made no changes. |
| `color` | No | string | Display color in the task list. One of `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`. |
| `initialPrompt` | No | string | Auto-submitted as the first user turn when this agent runs as the main session agent via `--agent`. Prepended to user-provided prompts. |

**Plugin-subagent caveat.** Agents that ship in a plugin's `agents/` directory (which is where every file in this project's `agents/` directory lives) **cannot use** `permissionMode`, `mcpServers`, or `hooks`. These fields are silently ignored when the agent is loaded from a plugin. If you need those fields, the agent must be copied to `.claude/agents/` or `~/.claude/agents/` instead. When writing an agent for `agents/`, omit those fields.

### Standard tool names (verified as of 2026-05-10)

These are the names Claude Code recognizes in `tools:` and `disallowedTools:`. Any name not on this list (or not from an installed MCP server) is silently ignored — it has no effect on the allowlist. If all names in `tools:` are unrecognized, the agent's effective allowlist is empty and it can use no tools at all; this is how aspirational tool lists like `tools: ast-grep, semgrep, eslint` silently disable an agent entirely.

- **File operations:** `Read`, `Write`, `Edit`, `NotebookEdit`
- **Search and discovery:** `Grep`, `Glob`
- **Execution:** `Bash`
- **Web:** `WebFetch`, `WebSearch`
- **Orchestration:** `Agent` (formerly `Task` — the alias still works), `Skill`, `AskUserQuestion`, `ToolSearch`
- **Plan mode:** `EnterPlanMode`, `ExitPlanMode`
- **Task management:** `TodoWrite` (non-interactive mode and SDK), `TaskCreate`, `TaskGet`, `TaskList` (interactive mode)
- **MCP plumbing:** `ListMcpResourcesTool`, `ReadMcpResourceTool`
- **Scheduling:** `CronCreate`, `CronDelete`, `CronList`

Any MCP tool follows the pattern `mcp__<server>__<tool>` — list those explicitly if you want to allowlist them. To restrict which subagent types an agent can spawn via `Agent`, use the `Agent(<type>, <type>)` syntax in the `tools:` field (e.g. `tools: Agent(rfc-architect, code-reviewer), Read, Bash`); plain `Agent` allows any subagent.

**If you are about to write a tool name that is not in the list above**, do not guess. Run `mcp__exa__crawling_exa` against `https://docs.claude.com/en/docs/claude-code/tools-reference` and verify. If the tool does not appear, do not list it — explain to the user that the name they suggested is not a real Claude Code tool and either omit the field (to inherit all tools) or list only real names.

### Model selection

Defaults match Bytewyrd's `CLAUDE.md` "Model Usage Optimization" policy. Pick the cheapest model that fits the task:

| Model | When to use |
|-------|-------------|
| `haiku` | Exploration, file search, simple lookups, routine formatting, agents whose entire job is to scan and summarize. |
| `sonnet` | Routine code review (correctness, conventions, security), refactoring of well-defined scope, implementation of tasks whose shape is clear. |
| `opus` | RFC writing and review, architectural analysis, complex multi-step problem solving, ambiguous or novel tasks where the problem space itself is unclear. Also the right choice for any agent that authors or reviews other agents (including `claude-agent-author` itself). |
| `inherit` (or omitted) | When the agent should run on whatever model the parent session is using. Acceptable for utility agents whose work matches whatever the parent is doing; not acceptable for agents whose value depends on a specific model tier (an "RFC reviewer" should pin `opus`, not inherit Sonnet when the parent happens to be on Sonnet). |

When in doubt, prefer `inherit` over an explicit choice — unspecified is the documented default and lets the user/main agent pin a model at invocation time via the per-invocation `model` parameter.

### Effort selection

`effort` overrides the session's effort level for this subagent only. Defaults are session-level: `xhigh` on Opus 4.7, `high` on Opus 4.6 and Sonnet 4.6, no effort on Haiku (effort is not supported there).

| Effort | When to use |
|-------|-------------|
| `low` | Short, scoped, latency-sensitive tasks that do not need deep reasoning. Rarely the right pick for a specialist agent. |
| `medium` | Cost-sensitive routine work; trades some intelligence for token savings. |
| `high` | The minimum for intelligence-sensitive work; the default on Opus 4.6 and Sonnet 4.6. |
| `xhigh` | Best balance of intelligence and cost on Opus 4.7. The default on Opus 4.7. Requires Opus 4.7 (older models fall back to `high`). |
| `max` | Deepest reasoning, no constraint on token spending. May overthink — Anthropic explicitly warns that `max` "is prone to overthinking" and recommends testing before adopting. Reserve for genuinely demanding agentic tasks (e.g. multi-phase refactoring with `refactoring-specialist`). Available on Opus 4.7, Opus 4.6, and Sonnet 4.6. |

When in doubt, omit `effort` — the session default is right for most cases.

### Writing the description field

The `description` field is the single most important field in the file. Claude reads it to decide whether to auto-delegate to this subagent. Three rules:

1. **Lead with the trigger condition, not the capability.**
   - Bad: `description: "Expert code reviewer."`
   - Good: `description: "Use proactively after the user writes or modifies code. Reviews the diff for bugs, security issues, and missing tests."`
2. **Include the phrase "Use proactively when..." or "Use whenever...".** These phrases bias the main agent toward auto-delegation. Without them, the main agent often waits for an explicit `@-mention`.
3. **Be specific about the scope.** "Reviews code" matches everything and routes poorly. "Reviews code touching auth, secrets, or user input" routes exactly when relevant.

The description must read in the third person ("Reviews X", not "I review X") and should be a single paragraph. Aim for 1–4 sentences.

### Body conventions

The body of the file is the agent's system prompt. Conventions used across this plugin's existing in-house agents (`feature-engineer`, `documentation-writer`, `ux-design-architect`, `rfc-architect`):

- Open with a role assertion: "You are a senior X with expertise in Y."
- State the agent's primary mission in one sentence.
- Follow with sectioned content — checklists, patterns, workflow phases. Use markdown headings (`##`) for top-level sections.
- If the agent has a multi-phase protocol, number the phases explicitly.
- Close with a "Constraints" or "When this is not the right tool" section if applicable.

The vendored agents from `VoltAgent/awesome-claude-code-subagents` use a different structure — longer, with "## MCP Tool Suite", "## Communication Protocol" (JSON example blocks), and "## Development Workflow" sections that often reference non-existent MCP tools. When refactoring a vendored agent, you may compress these sections if they reference unavailable tools, but preserve domain knowledge (smell catalogs, checklists, patterns) unless the user explicitly asks for a rewrite.

## Create mode — protocol

When invoked to create a new agent:

1. **Clarify purpose.** If the user's prompt does not include the agent's name, primary trigger condition, and intended scope, ask one targeted question to fill the gap: "I have <X>; I'm missing <Y> — can you provide it?" Do not invent the name or scope.

2. **Pick frontmatter values.** Using the format reference above:
   - `name` — kebab-case, matches the intended filename stem.
   - `description` — apply the three description-field rules. Write the trigger condition first.
   - `model` — apply the model-selection table. If you cannot pick confidently, ask the user one question about the agent's work nature.
   - `effort` — usually omit. Set explicitly only if the agent's value depends on a specific effort level.
   - `tools` — default to omitting (inherits all). Only set if the agent must be restricted (e.g. a read-only audit agent gets `tools: Read, Grep, Glob`).
   - `color` — pick one of the eight valid colors. If the user expressed a preference, honor it; otherwise pick something not already heavily used in `agents/` (you can `Grep` the existing files for `^color:` to see what's already taken).
   - Other fields — omit unless the user asked for them. Remember the plugin-subagent caveat: omit `permissionMode`, `mcpServers`, `hooks` for files going into `agents/`.

3. **Draft the body.** Open with the role assertion, state the mission, add sectioned content for the agent's domain knowledge. If the user provided existing reference material (docs, checklists), incorporate it. Keep sections focused — an agent that does five things badly is worse than one that does one thing well.

4. **Verify.** Before returning, run the primary-source check:
   - Every field name in the frontmatter appears in the field table above, or was verified against `https://code.claude.com/docs/en/sub-agents` in this session.
   - Every tool name in `tools:` (if set) appears in the standard tool names list above, or was verified against `https://docs.claude.com/en/docs/claude-code/tools-reference` in this session.
   - The `model` value is one of `haiku`, `sonnet`, `opus`, `inherit`, or a full model ID format (`claude-opus-4-7`, `claude-sonnet-4-6`).
   - The `effort` value (if set) is one of the five documented levels, and the model supports it (`xhigh` requires Opus 4.7).
   - The `color` value (if set) is one of the eight documented colors.
   - The `name` field matches the intended filename stem.
   - The `description` field leads with a trigger condition and contains "Use proactively when..." or "Use whenever...".
   If any check fails, fix it and re-verify.

5. **Return the file.** Output a fenced code block containing the complete file content, prefixed with the target path (`agents/<name>.md`). Do not write the file yourself — the parent will write it. If the user explicitly asked you to write the file, use the `Write` tool then confirm the path.

## Refactor mode — protocol

When invoked to refactor an existing agent file:

1. **Read the file.** Use `Read` to load the full contents. Note the existing frontmatter values and the structure of the body.

2. **Diff the frontmatter against the verified format.**
   - Are all field names supported? (Compare against the field table above.)
   - Are all tool names real? (Compare against the standard tool names list. Common offender: vendored agents listing external tool names like `ast-grep`, `semgrep`, `langchain`, `aws-cli`, `wandb`, `terraform` — none of which are Claude Code tools.)
   - Is the `model` value sensible for the agent's work? (Compare against the model-selection table. Vendored agents often omit `model:` entirely; that may be correct or may be a missed opportunity to pin an appropriate tier.)
   - Does the `description` field lead with a trigger condition and include "Use proactively when..."? (Many vendored descriptions are capability statements that route poorly.)
   - Are plugin-incompatible fields present? (`permissionMode`, `mcpServers`, `hooks` should be removed from any file in `agents/` — they are silently ignored anyway.)
   - Is `name` matched to the filename stem?

3. **Identify body issues.** Look for:
   - References to tools listed in `tools:` that the agent will not actually have access to (e.g. body says "use `semgrep` to scan for X" but `semgrep` is not a Claude Code tool).
   - "## MCP Tool Suite" sections that enumerate non-existent tools — those should be removed or replaced with the real tool list.
   - "## Communication Protocol" sections with JSON examples (`requesting_agent`, `request_type`, `payload`) — these are vendored boilerplate that does not correspond to any Claude Code runtime behavior. Mark for removal.
   - Domain knowledge that is genuinely useful (smell catalogs, checklists, patterns) — preserve.

4. **Propose changes with rationale.** Output a change list before the file content. Use this template (replace the example values — `NN–NN` line ranges, the agent name, the specific tool names — with the real values for the file you are processing):
   ```
   Frontmatter changes:
   1. Remove `tools: ast-grep, semgrep, eslint, prettier, jscodeshift`
      Rationale: none of these are real Claude Code tools; the field as written silently restricts the agent to an empty tool set. Omitting the field inherits the standard tool set (Read, Write, Edit, Bash, Grep, Glob, etc.), which is what the agent's body assumes it has.
   2. Add `model: opus`
      Rationale: the agent does multi-phase refactoring with deep reasoning; per Bytewyrd's model-selection policy, opus is the right tier for novel/ambiguous work. The agent currently inherits, which means it runs on Sonnet during feature work and produces shallower analysis.
   3. Rewrite `description` from "Expert refactoring specialist..." to "Use proactively when about to extend code with thin test coverage or refactor a structural smell. ..."
      Rationale: the current description is a capability statement; Claude does not auto-delegate to capability statements. Rewriting as a trigger condition lets the description do its job.

   Body changes:
   1. Remove the "## MCP Tool Suite" section (lines NN–NN).
      Rationale: enumerates tools that do not exist in Claude Code's runtime; misleading.
   2. Remove the "## Communication Protocol" section with the JSON example block (lines NN–NN).
      Rationale: the JSON `requesting_agent` / `request_type` / `payload` schema does not correspond to any Claude Code mechanism; this is vendored boilerplate.

   Preserved:
   - All domain knowledge in "Smell catalog", "Refactoring catalog", "Safety practices" sections — these are the agent's value.
   ```

   The `lines NN–NN` placeholders in the template above are for you to fill in with real line numbers from the file you are refactoring. Use `Read` to load the file with line numbers (the tool already prefixes them) and quote the exact range you want to remove or replace.

5. **Verify.** Run the same primary-source check as in create mode against the updated file.

6. **Return.** Output the change-list, then a fenced code block containing the complete updated file content, prefixed with the file's path. As in create mode, do not write the file unless the user explicitly asked you to — let the parent review and apply.

## Constraints

- **Never guess from training knowledge.** Any field name, tool name, model alias, or effort level you are not sure about must be verified against the canonical Anthropic docs (`https://code.claude.com/docs/en/sub-agents`, `https://docs.claude.com/en/docs/claude-code/tools-reference`, `https://code.claude.com/docs/en/model-config`) using `mcp__exa__crawling_exa`. If the canonical doc disagrees with this prompt's in-prompt reference, the canonical doc wins — and the user should be told the in-prompt reference is out of date so they can update this file.
- **Tool fields are allowlists, not aspirations.** Listing a tool name does not add the tool. Unrecognized tool names are silently ignored — but their presence changes nothing: if all names in `tools:` are unrecognized, the effective allowlist is empty and the agent can use no tools. If some names are real and some are not, only the real names take effect. Either way, nonexistent names are at best dead weight and at worst silently restrict the agent to fewer tools than intended.
- **Do not write the file yourself unless asked.** The default deliverable is a file content block the parent reviews and applies. Writing the file yourself (`Write`) is fine when the user explicitly says so, but the default mode is "draft and return for review."
- **Preserve domain knowledge during refactors.** The vendored agents have substantial body content that is genuinely useful even when the frontmatter is broken. Fix the frontmatter; leave the smell catalogs, checklists, and patterns alone unless the user asks for a body rewrite or unless a body section literally references nonexistent tooling.
- **One file per invocation.** Do not author or refactor multiple agent files in a single invocation. If the user wants a batch operation, the right shape is a future audit skill (RFC pending) that spawns this agent against each file in turn.
````

The agent file is complete. Three things to note about why it is structured this way:

1. **Frontmatter is minimal and verified.** Only `name`, `description`, `model: opus`, and `color: blue` are set. `tools:` is omitted intentionally — the agent needs `Read`, `Write`, `Edit`, `Grep`, `Glob`, `WebFetch`, `mcp__exa__crawling_exa`, and `mcp__exa__web_search_exa` to do its job, and omitting the field inherits all of them. `effort:` is omitted — the session default (`xhigh` on Opus 4.7, `high` on Opus 4.6) is right for this work. `color: blue` matches `rfc-architect`'s color, fitting the "thinks deliberately, writes specs" archetype.

2. **The body is long because the format reference is comprehensive.** The reference section is the agent's value. It lists every field, every real tool, every model and effort level — with the verification escape hatch for anything the reference does not cover. Subagent system prompts do not count against the parent context, so the length costs nothing to the caller.

3. **The protocol is two distinct modes (create / refactor) with a shared verification step.** The shared step is the most important part — it is what prevents the agent from confidently producing a file that uses a deprecated field or a nonexistent tool.

#### Step 2 — Update `CLAUDE.md`

Open `CLAUDE.md`. The current Agent delegation table (as updated by RFC `2026-05-10-refactor-command` once that RFC is implemented) is:

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

(The "Refactoring (deliberate)" row was added by RFC `2026-05-10-refactor-command`, now Done.)

Add a "Claude agent authoring" row between "Documentation" and "Debugging" — the natural place for it, since agent authoring is a documentation-adjacent meta-task:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Claude agent authoring | claude-agent-author |
| Debugging | debugger |
```

No other CLAUDE.md changes. No "When to consider..." subsection is needed — the agent's `description` field includes "Use proactively when..." which is sufficient delegation signal for the main agent, and the table row makes the agent discoverable for explicit invocation.

#### Step 3 — Verification

After both changes, run these checks:

1. **Agent file exists and parses:**

   ```bash
   test -f agents/claude-agent-author.md && head -6 agents/claude-agent-author.md
   ```

   Expected output (the first 6 lines of the file, including the frontmatter open and close):

   ```
   ---
   name: claude-agent-author
   description: Use proactively when creating a new subagent file under agents/ or .claude/agents/, when refactoring an existing agent's frontmatter or system prompt, or when auditing a set of agent definitions for format correctness. Owns primary-source knowledge of Claude Code's subagent format — supported YAML frontmatter fields, real built-in tool names, model and effort taxonomies, and the writing conventions for the description field that drives automatic delegation. Verifies any uncertain field or tool name against Anthropic's docs via Exa before returning a file; does not guess from training knowledge.
   model: opus
   color: blue
   ---
   ```

2. **Agent frontmatter has no aspirational tool names (the bug the agent itself is designed to prevent):**

   ```bash
   grep -E '^tools:' agents/claude-agent-author.md || echo "no tools field — correct"
   ```

   Expected output:

   ```
   no tools field — correct
   ```

   (The agent omits `tools:` to inherit the standard tool set, which is needed for `Read`, `Write`, `Edit`, `Grep`, `Glob`, `WebFetch`, and the Exa MCP tools.)

3. **Agent name matches filename stem:**

   ```bash
   basename agents/claude-agent-author.md .md
   grep -E '^name:' agents/claude-agent-author.md
   ```

   Expected output (both lines):

   ```
   claude-agent-author
   name: claude-agent-author
   ```

4. **`model: opus` is pinned (the agent's value depends on deep reasoning about format details):**

   ```bash
   grep -E '^model:' agents/claude-agent-author.md
   ```

   Expected output:

   ```
   model: opus
   ```

5. **CLAUDE.md table includes the new row:**

   ```bash
   grep -F 'Claude agent authoring' CLAUDE.md
   ```

   Expected output:

   ```
   | Claude agent authoring | claude-agent-author |
   ```

6. **Manual smoke test (after a Claude Code session restart picks up the new agent file):**

   - Type `@cla` in Claude Code; confirm `@claude-agent-author (agent)` appears in the typeahead.
   - Run: `@claude-agent-author create a new agent called "json-validator" that lints JSON files for schema compliance using Read, Grep, and Bash`. Confirm the agent (a) runs on Opus, (b) returns a file content block with `name: json-validator`, a "Use proactively when..." description, `tools: Read, Grep, Bash` (or omits the field, depending on its judgment), and no aspirational tool names, and (c) does not write the file unless explicitly asked.
   - Run: `@claude-agent-author refactor agents/refactoring-specialist.md`. Confirm the agent (a) reads the file, (b) returns a change list with rationales (most likely flagging the body's references to `ast-grep`/`semgrep`/etc. that the previous RFC's frontmatter removal left orphaned, if those still exist), and (c) does not write the file.
   - Trigger an automatic-delegation test: in a new session, prompt: "I want to add a new specialist agent that reviews Rust code for unsafe blocks." Confirm the main agent delegates to `claude-agent-author` rather than authoring the file directly.

   If any step fails, the issue is most likely (in order): (a) frontmatter has a syntax error (run `head -10 agents/claude-agent-author.md` to inspect), (b) the `description` field is missing the "Use proactively when..." phrase that triggers auto-delegation, (c) the session was not restarted after the file was written (agents are loaded at session start when read from disk), or (d) `model: opus` is misspelled (e.g. `opus4` or `claude-opus`, neither of which is a valid alias — full model IDs must be the precise form `claude-opus-4-7` or `claude-opus-4-6`).

## Risks and open questions

- **Risk: the agent's in-prompt format reference goes stale faster than the maintainer updates it.** Anthropic ships subagent-format changes regularly (added `xhigh` in v2.1.111, changed default-effort behavior in v2.1.117, renamed `Task` to `Agent`). The prompt is dated "verified as of 2026-05-10" and the mandatory verification step is the safety net, but if the maintainer updates the date without updating the reference, the agent could trust an outdated enumeration. **Mitigation in this RFC:** the verification step is mandatory ("If any check fails, fix it and re-verify") and the agent is instructed that the canonical doc wins over the in-prompt reference. The user-facing failure mode (agent writes a file with a deprecated field) is bounded because Claude Code's own loader will flag invalid frontmatter at session start. A future RFC can add `/agent-author-refresh` that auto-refreshes the in-prompt reference from the canonical docs.

- **Risk: the agent gets bypassed.** The main agent might continue authoring agent files inline despite the `description` field's "Use proactively when..." signal, especially for "small" agents the main agent thinks are easy. **Mitigation:** the `CLAUDE.md` table row is a documented delegation expectation; the `description` field starts with the canonical trigger phrase; the agent's name is searchable in the `/agents` interactive interface. If bypass becomes a real problem, a future RFC can add a hook that warns on inline agent-file creation and suggests the specialist.

- **Open question: should the agent file itself be verified against the agent's own protocol after creation?** Bootstrapping problem — if `claude-agent-author` is supposed to be the authority on agent files, it would be self-referential for the file to be authored without it. **Resolution within this RFC:** the verification checks in Step 3 cover the structural correctness (file parses, name matches filename, model is valid, etc.), and the file content was drafted in this RFC using the same primary-source-grounded discipline the agent itself encodes (the references were verified against the live Anthropic docs during RFC drafting, not from training knowledge). Once the file exists, a future "audit all agents" pass (the planned follow-on RFC) can re-process this file too — it is no different from any other agent in `agents/` once it ships.

- **Open question: should `claude-agent-author` be in `agents/` or `.claude/agents/`?** `agents/` exports the agent to every project that installs the plugin; `.claude/agents/` keeps it local to this repo only. The RFC recommendation is `agents/` (Option A in Decision 1) because the value generalizes. **Resolution within this RFC:** ship in `agents/`. If feedback shows that downstream users find the agent's `opus`-pinned cost annoying for projects that do not have a heavy agent-authoring workload, a future RFC can split it into a `.claude/agents/` local copy and remove from `agents/` — but the bias should be toward sharing.

- **Open question: does the agent need its own `memory:` directory to accumulate learnings about agent patterns across sessions?** Plausible — an agent that audits many files over time could build a per-project catalog of "common offender" patterns. **Resolution within this RFC:** no. v1 is stateless. If real-world use shows that cross-session memory would meaningfully improve the agent's output (e.g. learning a project's local conventions, remembering which colors are taken), adding `memory: project` is a one-line frontmatter edit in a follow-up.

- **Risk: the audit follow-on RFC underestimates the cost of running this agent against all 42 vendored files.** Each agent runs on Opus at the session's default effort — the audit RFC will need to design batching, parallelism, and review-checkpoint cadence to keep costs and reviewer attention bounded. **Mitigation:** out of scope here; the audit RFC owns that design. This RFC's deliverable (the agent itself) is useful for one-off authoring even if the audit never runs.

- **Open question: are the Anthropic doc URLs correct?** The embedded agent prompt references `https://code.claude.com/docs/en/sub-agents` and `https://code.claude.com/docs/en/model-config` as canonical sources, while the tools-reference URL uses `https://docs.claude.com/en/docs/claude-code/tools-reference`. The project's other documentation references consistently use `docs.claude.com`. If `code.claude.com` is not a valid host, the agent's verification step will fail on every invocation. **Resolution:** verify each URL with `mcp__exa__crawling_exa` before merging and normalize to the correct host throughout the agent body.

## Relationship to other RFCs

- **`2026-05-10-refactor-command`** (status: Done) — switched the project to permanent local ownership of `agents/` by removing `/agents-update`. This RFC builds on that decision: with the agents now owned locally, the format-correctness gap becomes a tractable problem (you can actually fix the files without an upstream sync silently reverting the fix). The CLAUDE.md table edit in Step 2 of this RFC also extends the table edits made by `2026-05-10-refactor-command`; the implementation note in Step 2 calls out the dependency on that RFC's row.

- **RFC `2026-05-10-audit-rework-agent-definitions`** (status: Draft, at `docs/rfcs/2026-05-10-audit-rework-agent-definitions.md`) — depends on this RFC being Done. That RFC will design the audit workflow (batching, parallelism, review checkpoints), likely as a `/audit-agents` skill that spawns `claude-agent-author` in refactor mode against each file in `agents/`. The agent created here is the foundation; the audit is the workflow on top.

- **Future RFC: `/agent-author-refresh`** (not yet captured) — a small follow-on if format-staleness becomes a real problem. Would auto-refresh the in-prompt format reference in `agents/claude-agent-author.md` from the canonical Anthropic docs. Not needed for v1.

- **`2026-05-09-best-practices-content-and-tooling`** (status: Done) — established the verb-suffix naming convention for noun-first skill families (`best-practices-extract`, `best-practices-record`). The `claude-agent-author` name follows a different convention (noun-noun-noun "claude-agent-author" rather than noun-verb) because it is an agent, not a skill; the convention from that RFC applies to skills only. If a `claude-agent-*` family of skills emerges later (e.g. `claude-agent-validate`, `claude-agent-diff`), those would follow the verb-suffix convention.
