---
version: v1
last_updated: 2026-05-12
---

# Agent Audit Criteria

This document defines the pass/fail criteria for auditing agent definitions in `agents/`. The criteria are versioned; the current version is recorded in the header field above. Each audited agent's footer references the criteria version it was audited against, and the tracking table at the bottom shows the current audit state for every agent.

**Current version:** v1
**Audit driver:** `claude-agent-author` agent (introduced by RFC `2026-05-10-claude-agent-author-agent`)
**Audit framework:** RFC `2026-05-10-audit-rework-agent-definitions`

## Hard requirements

The audit cannot pass an agent file until every hard requirement is met. A PR that does not bring the file into compliance is revised before merge.

### H1 — No aspirational `tools:` fields

The `tools:` frontmatter field must either be omitted (which inherits Claude Code's standard tool set per the Claude Code subagent docs: "Tools the subagent can use. Inherits all tools if omitted") or list only tools Claude Code surfaces as named primitives.

The complete set of Claude Code's surfaced tools is documented in the companion RFC `2026-05-10-claude-agent-author-agent`'s "Standard tool names" section, which is the single source of truth for H1 validation. The `claude-agent-author` agent inherits that list.

As a quick reference, the v1 surfaced set includes: `Read`, `Write`, `Edit`, `MultiEdit`, `Bash`, `Grep`, `Glob`, `Agent` (`Task` is a legacy alias), `Skill`, `AskUserQuestion`, `ToolSearch`, `WebFetch`, `WebSearch`, `TodoWrite`, `NotebookEdit`, `EnterPlanMode`, `ExitPlanMode`, `TaskCreate`, `TaskGet`, `TaskList`, `ListMcpResourcesTool`, `ReadMcpResourceTool`, `CronCreate`, `CronDelete`, `CronList`, plus `mcp__*` prefixes for installed MCP servers.

External CLIs, SDKs, or libraries (`pytest`, `mypy`, `kubectl`, `terraform`, `wandb`, `langchain`, etc.) are **forbidden** in `tools:`. They silently restrict the subagent to a tool set that does not exist, which prevents the subagent from doing any work.

Default: omit the field unless the agent genuinely needs a restricted set (e.g., a read-only investigation agent that should not Write or Bash).

### H2 — `description` field is autoload-friendly

The first 200 characters of the `description` field must clearly state what the agent does and when to invoke it. Claude Code's autoload heuristic matches on the description prefix, so the leading sentence must be a self-contained "this agent does X for Y" statement.

Two acceptable styles:
- **Upstream style:** `"Expert <domain> specialist mastering <skills>. <Differentiator>. <Focus>."` — concise, prose-only, one paragraph.
- **Anthropic style:** `"Use this agent when you need to <task>. Examples: <example>Context: … user: '…' assistant: '…' <commentary>…</commentary></example>"` — explicit trigger conditions with worked examples.

Choose the style per agent based on autoload-trigger needs:
- Agents the plugin actively delegates to via skill bodies (Tier 1) should use the Anthropic style — the examples disambiguate when the autoload should fire vs. when the user should invoke explicitly.
- Tier 2 and Tier 3 agents may use either style. Default to upstream style for consistency with the rest of the set; switch to Anthropic style when the agent's trigger conditions are ambiguous without examples.

### H3 — `model:` is pinned when non-default

Per the plugin's `CLAUDE.md` Model Usage Optimization section, default is `haiku` unless the task requires more. The agent's frontmatter must explicitly pin `model: sonnet` or `model: opus` when those tiers are required:

- **`model: "opus"`** — required for the Tier 1 agents that own design or review responsibility: `rfc-architect`, `code-reviewer`, `feature-engineer` (when implementing an RFC; pinned via the agent file, since `/rfc-implement`'s skill body invokes it on opus regardless), `refactoring-specialist` — the `/refactor` skill body pins `model: "opus"` at spawn time, which overrides the agent frontmatter. The agent file should also set `model: opus` in the frontmatter so standalone (non-skill) invocations default correctly. Plus the rest of the Tier 1 set (`debugger`, `documentation-writer`, `docs-agent`, `security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`, `claude-agent-author`). The review-agent subset (`code-reviewer`, `security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`) are additionally pinned to opus because they participate in `/rfc-consensus-review` per `docs/rfc-process.md`. The remaining Tier 1 agents (`documentation-writer`, `docs-agent`, `debugger`, `claude-agent-author`) pin opus because they are on the plugin's active-delegation hot path (listed in `CLAUDE.md`'s "Agent delegation" table) and operate at design-output quality, not exploration quality.
- **`model: "sonnet"`** — required for the Tier 2 agents that participate in `/rfc-consensus-review` for their specific domain (per the review-agent table in `docs/rfc-process.md`: `frontend-developer`, `ux-design-architect`, `react-specialist`, `nextjs-developer`, `terraform-engineer`, `cloud-architect`, `kubernetes-specialist`, `database-administrator`, `postgres-pro`, `api-designer`, `graphql-architect`, `performance-engineer`, `sre-engineer`). These agents may be upgraded to opus if a specific domain's reasoning needs justify it; the audit footer documents the choice. Tier 2 agents not invoked by the RFC review system default to sonnet; Tier 3 agents that write production code (`python-pro`, `rust-engineer`, `golang-pro`, `typescript-pro`, `sql-pro`, `terragrunt-expert`) also default to sonnet.
- **`model: "haiku"`** — recommended for exploration-only or formatting-only agents (no current agent qualifies; this tier is named for completeness in case future agents are added).

When unsure, prefer the cheaper tier and pin it explicitly; under-pinning is a one-line edit to fix. Note that `docs/rfc-process.md` requires `model: opus` for *all* RFC-related agent tasks regardless of the agent's frontmatter — the skill body's spawn instruction takes precedence over the agent's default. The frontmatter `model:` is the default for non-RFC invocations.

Note: when a skill body explicitly sets `model:` in its spawn instruction, that overrides the agent frontmatter. The frontmatter `model:` governs standalone invocations (user invokes the agent directly without going through a skill). Both should agree; if they differ, document why in the audit footer.

### H4 — No prose claims about coordinating with other subagents

Subagents cannot spawn other subagents in Claude Code. Replace prose like "partners with `security-engineer` on auth changes", "delegates database work to `postgres-pro`", or "collaborates with `ux-design-architect`" with one of:

- **Recommendation phrasing:** "If the work touches auth, recommend the user invoke `security-engineer` next."
- **Skill reference:** "For consensus review, recommend the user invoke `/rfc-consensus-review`."
- **Removal:** if the cross-agent claim was decorative (the agent does not actually need the other agent's output), delete the sentence.

### H4a — No prose claims about non-existent infrastructure

The upstream `VoltAgent/awesome-claude-code-subagents` template includes prose like "Query context manager for X" or "MCP communication for Y" that references infrastructure (a "context manager" subsystem, agent-side MCP communication patterns) that does not exist in Claude Code's actual subagent execution model. These references confuse the agent's first-turn behavior — the agent attempts to follow the instruction and surfaces an error or a no-op.

Remove or replace such references. The standard substitution is:

- **"Query context manager for X" → "Read the relevant files in the codebase to understand X"** (using Read/Grep tools).
- **"MCP communication with the team" → delete the sentence** (it is decorative; the agent communicates by returning text to its caller).
- **"Coordinate via context manager" → delete or rephrase as a recommendation** (per H4).

The audit footer notes which substitutions were applied.

### H5 — Audit footer present

Every audited agent file gains a footer in this exact format, appended as the last lines of the file:

```markdown
<!-- Audit log -->
<!-- YYYY-MM-DD: criteria <version>, audited by <auditor>; <one-paragraph summary of what changed and why>. -->
```

Where:
- `YYYY-MM-DD` is the audit PR's merge date.
- `<version>` is the current criteria version (e.g., `v1`).
- `<auditor>` is `claude-agent-author` for automated audits or the human's name for manual ones.
- The summary is a single paragraph (no headings, no lists) describing the audit's findings in concrete terms (e.g., "removed aspirational `tools:` list; condensed body from 290→195 lines by collapsing redundant 'checklist' sections; pinned `model: opus` because this agent is on the `/rfc-consensus-review` hot path").

Future re-audits append additional footer entries (one per audit pass) rather than replacing the existing entries.

### H7 — Project-specific guidance for Tier 1 agents

Tier 1 agents that interact with the plugin's RFC process must reference `docs/rfc-process.md` and the relevant skills:

- `rfc-architect` — references `docs/rfc-process.md` (which it already does in the locally-customized version) and the skill flow it participates in (`/rfc-new`, `/rfc-consensus-review`, `/rfc-read-feedback`).
- `feature-engineer` — references `docs/rfc-process.md` as the source of truth when implementing an approved RFC, and `/rfc-implement` as the entry point.
- `code-reviewer` — references the `/rfc-consensus-review` skill and the Anthropic security-review skill.
- `refactoring-specialist` — references `/refactor` and the protocol from RFC `2026-05-10-refactor-command`.
- `debugger` — references evidence-based development guidance from `CLAUDE.md`.

Tier 2 and Tier 3 agents do not have this requirement; they remain general-purpose.

## Soft recommendations

Deviation is allowed but must be noted in the rationale section of the audit PR (and reflected in the footer's summary).

### S1 — Section ordering convention

For agents that retain the upstream prose-template style, the recommended section order is:

1. Opening paragraph (`You are a senior <role> with expertise in …`)
2. `When invoked:` (numbered, 3–5 steps)
3. `<Domain> engineering checklist:` (no numeric thresholds without benchmarks)
4. Core domain sections (problem-specific knowledge)
5. `Communication Protocol` (how the agent surfaces questions, partial results, blockers)
6. `Output format` (what the agent returns at completion)

Agents using the Anthropic style (Tier 1 customized agents) follow a freer responsibility-based structure and are not held to this ordering.

### S2 — `color:` field for Tier 1 agents

Three of the four locally-customized agents use `color:` (`feature-engineer` cyan, `documentation-writer` orange, `rfc-architect` blue) and one Tier 2 agent does as well (`ux-design-architect` yellow). For visual consistency in the Claude Code UI, recommend adding `color:` to all Tier 1 agents during their audit pass. Suggested color assignments (the auditor may pick alternatives if they conflict with future additions):

- `code-reviewer` — `green`
- `feature-engineer` — `cyan` (already set)
- `rfc-architect` — `blue` (already set)
- `documentation-writer` — `orange` (already set)
- `docs-agent` — `orange`
- `debugger` — `red`
- `refactoring-specialist` — `purple`
- `security-engineer` — `red` (deliberate overlap with debugger; both surface urgent work)
- `penetration-tester` — `red`
- `ai-engineer` — `cyan`
- `llm-architect` — `cyan`
- `mcp-developer` — `cyan`
- `claude-agent-author` — `purple`

Tier 2 and Tier 3 agents may add `color:` if the auditor judges it useful (e.g., `ux-design-architect`'s yellow is preserved by the audit), but it is not required.

### S3 — Conventional Commits scope alignment

The agent file's `name:` field is the natural Conventional Commits scope for changes to that agent. Audit PR commit messages should use the format `chore(agents/<agent-name>): audit pass under criteria v<version>`.

### S4 — Body length proportionate to scope (soft recommendation)

The upstream median of ~280 lines includes redundant content (numeric-threshold checklists that restate the description; near-duplicate subdomain sections). Prefer tighter bodies — target ≤ 250 lines — but preserve domain knowledge (smell catalogs, checklists, patterns, worked examples) that the agent genuinely needs to do its job. Trim tautologies and aspirational metrics; keep content that is actionable.

If the audited file retains more than 250 lines, the audit footer notes why (e.g., "kept at 290 lines because the domain spans three sub-disciplines with distinct decision frameworks that cannot be collapsed without losing precision").

There is no hard cap; the criterion is "remove what adds no value", not "enforce a line count."

### S5 — No numeric thresholds without benchmarks

Upstream checklists frequently include items like "Coverage > 95%", "Response time < 200ms", or "Cyclomatic complexity ≤ 10" without grounding in project-specific measurements or rationale. These are aspirational metrics that the agent cannot verify or enforce. Remove numeric thresholds that are not derived from the project's actual constraints; replace with qualitative guidance (e.g., "test coverage is sufficient for the risk level of the change") or omit the checklist item entirely if it is not actionable.

## Tracking table

| Agent | Tier | Last audited | Criteria version | Status |
|-------|------|--------------|------------------|--------|
| ai-engineer | 1 | — | — | pending |
| api-designer | 2 | — | — | pending |
| backend-developer | 3 | — | — | pending |
| build-engineer | 3 | — | — | pending |
| claude-agent-author | 1 | — | — | pending |
| cli-developer | 3 | — | — | pending |
| cloud-architect | 2 | — | — | pending |
| code-reviewer | 1 | 2026-05-12 | v1 | pass |
| database-administrator | 2 | — | — | pending |
| database-optimizer | 3 | — | — | pending |
| debugger | 1 | — | — | pending |
| deployment-engineer | 3 | — | — | pending |
| devops-engineer | 3 | — | — | pending |
| devops-incident-responder | 3 | — | — | pending |
| docs-agent | 1 | — | — | pending |
| documentation-writer | 1 | 2026-05-12 | v1 | pass |
| feature-engineer | 1 | 2026-05-12 | v1 | pass |
| frontend-developer | 2 | — | — | pending |
| fullstack-developer | 3 | — | — | pending |
| golang-pro | 3 | — | — | pending |
| graphql-architect | 2 | — | — | pending |
| kubernetes-specialist | 2 | — | — | pending |
| llm-architect | 1 | — | — | pending |
| mcp-developer | 1 | — | — | pending |
| microservices-architect | 3 | — | — | pending |
| nextjs-developer | 2 | — | — | pending |
| penetration-tester | 1 | — | — | pending |
| performance-engineer | 2 | — | — | pending |
| platform-engineer | 3 | — | — | pending |
| postgres-pro | 2 | — | — | pending |
| prompt-engineer | 3 | — | — | pending |
| python-pro | 3 | — | — | pending |
| qa-expert | 3 | — | — | pending |
| rails-expert | 3 | — | — | pending |
| react-specialist | 2 | — | — | pending |
| refactoring-specialist | 1 | — | — | pending |
| rfc-architect | 1 | 2026-05-12 | v1 | pass |
| rust-engineer | 3 | — | — | pending |
| security-engineer | 1 | — | — | pending |
| sql-pro | 3 | — | — | pending |
| sre-engineer | 2 | — | — | pending |
| terraform-engineer | 2 | — | — | pending |
| terragrunt-expert | 3 | — | — | pending |
| test-automator | 3 | — | — | pending |
| typescript-pro | 3 | — | — | pending |
| ui-designer | 3 | — | — | pending |
| ux-design-architect | 2 | — | — | pending |
| websocket-engineer | 3 | — | — | pending |

After each PR merges, update the row: set `Last audited` to the merge date, `Criteria version` to the version the audit ran under, and `Status` to `pass` (or `pass with deviations` if soft recommendations were not followed; the deviations are documented in the file's footer).
