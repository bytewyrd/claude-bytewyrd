---
rfc: "2026-05-10-audit-rework-agent-definitions"
title: "Audit and Rework All Agent Definitions"
author: "Rodrigo Kochenburger"
status: "Done"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Run the `claude-agent-author` agent (introduced by RFC `2026-05-10-claude-agent-author-agent`) systematically across all 46 files in `agents/` to audit and rework each definition against a single set of evaluation criteria, producing a higher-baseline, consistent set of agent definitions that the plugin owns locally. The audit is structured as one PR per agent file (with batched exceptions for agents that share a domain and should be reviewed together), and every change ships with a `Why` section in the PR body and a corresponding entry in the file's own audit footer explaining the rationale — so the human reviewer can evaluate "is this improvement worth the change" rather than "what changed and why" for each diff. The audit is sequenced by criticality (agents the plugin actively delegates to are reworked first; long-tail agents that exist for completeness are reworked last), and the audit's own pass/fail criteria — derived from the `claude-agent-author` agent's documented frontmatter and structural conventions — are checked into the repo at `docs/agent-audit-criteria.md` so future audits (re-audits, new agents) measure against the same bar.

## Should we do this?

**Yes.** The current `agents/` directory is a vendored snapshot of `VoltAgent/awesome-claude-code-subagents` — a high-quality starting point, but written generically for any Claude Code project, not specifically for this plugin's environment. Three concrete pieces of evidence make the case for a systematic rework now:

1. **Aspirational tool fields are pervasive.** 43 of 46 agents (93%) declare `tools:` fields listing external CLIs (`ast-grep`, `semgrep`, `eslint`, `prettier`, `jscodeshift`, `pytest`, `mypy`, `terraform`, `kubectl`, `docker`, `pagerduty`, `wandb`, etc.) that Claude Code does not surface as named tool primitives. Per the Claude Code subagent docs ("Tools the subagent can use. Inherits all tools if omitted"), this silently restricts each subagent to a tool set that does not exist — they cannot Read, Write, Edit, or Bash, which means they cannot do their job. RFC `2026-05-10-refactor-command` already established this for `refactoring-specialist` and removed the field as a one-off fix; doing this 42 more times by hand (without a shared author) is exactly the inconsistency the rework is meant to eliminate.
2. **No documented quality bar for "what a good agent looks like in this plugin".** Four agents have already been locally customized (`feature-engineer`, `documentation-writer`, `ux-design-architect`, `rfc-architect` — the four with `color:` fields and Anthropic-style `description` examples). The customization style differs from the VoltAgent style in concrete ways: structured `<example>` blocks in `description`, project-specific guidance in the body, omission of fake tool lists. These are good improvements, but they were applied agent-by-agent with no shared criteria, so it is not obvious to a future contributor what "Bytewyrd-style" looks like or which of the remaining 42 agents need the same treatment.
3. **`/agents-update` was removed (per RFC `2026-05-10-refactor-command`).** The previous escape hatch — "if the local copy is wrong, pull upstream and start over" — is gone. The plugin now owns these files permanently. That ownership is empty until the files are systematically aligned with the plugin's actual environment and conventions; otherwise the project carries 46 inconsistent files indefinitely.

The audit is bounded work (46 files, criteria-driven, one PR each), produces a permanent reference artifact (`docs/agent-audit-criteria.md`), and unblocks future contributions (anyone adding a new agent now has a documented quality bar to clear). The cost is real — 46 PR reviews and the Opus tokens to run `claude-agent-author` against each file — but the cost is one-time and the resulting baseline is what makes the next 46 audits or new-agent additions cheap.

## Current state

The `agents/` directory contains 46 markdown files, each defining one Claude Code subagent. The files were vendored from `VoltAgent/awesome-claude-code-subagents` (MIT) and were maintained in sync via the (now-removed) `/agents-update` skill. RFC `2026-05-10-refactor-command` switched the project's posture to local ownership and removed the sync mechanism, but did not touch the agent definitions themselves except for the one-off `refactoring-specialist` cleanup.

**Quantitative survey of the current set (as of 2026-05-10):**

- **Total files:** 46
- **Files with `tools:` field:** 43 (the three current exceptions are `feature-engineer`, `documentation-writer`, and `ux-design-architect` — the locally-customized agents that already had their `tools:` fields removed; `refactoring-specialist` will become the fourth exception once RFC `2026-05-10-refactor-command` lands)
- **Files with `color:` field:** 4 (`feature-engineer`, `documentation-writer`, `ux-design-architect`, `rfc-architect` — the locally-customized ones)
- **Files with `model:` field:** 2 (`ui-designer` → `sonnet`, `terragrunt-expert` → `sonnet`)
- **Files with `effort:` field:** 0
- **Body length range:** 39 lines (`ux-design-architect`) → 307 lines (`terragrunt-expert`); median around 280 lines. Total agent-definition content: ~12,000 lines.
- **Body structure:** the upstream style is a uniform "When invoked: 1. … 2. … / `<domain> engineering checklist:` / `<domain> architecture:` / …" template with domain-specific section headings. Locally-customized agents (`rfc-architect`, `feature-engineer`, etc.) abandon this template for a freer-form, Anthropic-style guidance prose with `<example>` blocks in the description.

**Visible patterns of variation:**

1. **Tool fields.** Most upstream agents list a mix of valid Claude Code tools (`Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`) and external CLIs/SDKs (`pytest`, `mypy`, `kubectl`, `wandb`, `langchain`). The external entries are aspirational metadata, not active capability declarations — Claude Code does not interpret them and they silently shrink the inherited tool set.
2. **Description style.** Two distinct styles coexist: (a) a one-paragraph "Expert X specialist mastering …" upstream blurb, and (b) the locally-customized Anthropic style with `<example>Context: … user: '…' assistant: '…' <commentary>…</commentary></example>` blocks. The two styles trigger differently in Claude Code's autoload heuristics and read very differently to humans.
3. **Body structure.** Upstream agents follow a near-identical template (numbered "When invoked" steps, "checklist" sections with numeric thresholds like "Coverage > 95%", multiple subdomain sections). Locally-customized agents use a freer prose structure organized around responsibilities and decision frameworks rather than checklists.
4. **Model and effort pinning.** Two agents pin `model: sonnet` for cost reasons; no agent pins `effort`. The other 44 inherit whatever the parent session is using, which means an Opus-recommended task (RFC architecture, deep refactoring) silently runs on Sonnet if the user is in a Sonnet session.
5. **Agent-tool boundary.** Several agents describe coordination with other agents ("partners with …", "collaborates with …") via prose rather than via Claude Code's actual subagent-invocation mechanism. The prose is aspirational; subagents cannot spawn other subagents in Claude Code's current model. This is harmless but misleading, and an audit pass should either remove the language or rephrase it to reflect what the agent can actually do (recommend the user invoke X next).
6. **Project-specific guidance is missing.** Upstream agents do not know about this plugin's RFC process (`docs/rfc-process.md`), its skills (`/refactor`, `/rfc-implement`, etc.), or its conventions (Conventional Commits, evidence-based development, the four-section docs layout). Where appropriate, agents should know to defer to these — e.g., `feature-engineer` should know to read the linked RFC; `code-reviewer` should know to surface security findings to `security-engineer`.

**What is broken or missing:**

1. **The 43 aspirational `tools:` fields each silently break the agent.** Subagents spawned with `tools: pytest, mypy` cannot Read or Edit any file. This is a latent bug that only surfaces when a user actually invokes the agent and watches it fail to do anything useful.
2. **No quality bar.** Without a documented criteria file, "fix the agent" is an open-ended ask. Two contributors can audit the same agent and produce wildly different rewrites because they are anchored to different implicit standards.
3. **No tracking.** Nobody can answer "which agents have been audited?" without diffing every file against the VoltAgent upstream. An audit footer in each file (with date, author, criteria version) makes that lookup local.
4. **`claude-agent-author` does not exist yet.** This RFC depends on RFC `2026-05-10-claude-agent-author-agent` shipping first. Without that agent, the rework would be done ad-hoc by whichever agent or human happened to be available, reproducing the inconsistency the audit is meant to fix.

## Analysis / Options

There are five coupled decisions: how the audit is sequenced, how rationale is captured, how the work is reviewed by the human, what the evaluation criteria are, and how the audit is gated against partial completion.

### Decision 1 — How is the audit sequenced?

**Option A — By criticality, in three tiers (recommended).**
Tier 1 (highest priority) is the agents the plugin actively delegates to via skill bodies or the `CLAUDE.md` "Agent delegation" table: `feature-engineer`, `code-reviewer`, `rfc-architect`, `documentation-writer`, `debugger`, `refactoring-specialist`, plus the review-agent set referenced in `docs/rfc-process.md` (`security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`), plus `claude-agent-author` itself (self-audit, added to Tier 1 when RFC `2026-05-10-claude-agent-author-agent` ships, per the "Risks and open questions" section). 12 Tier 1 agents total.

Tier 2 (medium priority) is the agents referenced by the RFC review-agent selection table for specific domains: `frontend-developer`, `ux-design-architect`, `react-specialist`, `nextjs-developer`, `terraform-engineer`, `cloud-architect`, `kubernetes-specialist`, `database-administrator`, `postgres-pro`, `api-designer`, `graphql-architect`, `performance-engineer`, `sre-engineer`. 13 agents.

Tier 3 (long tail) is everything else — agents the plugin does not explicitly invoke but ships for completeness so consumer projects can route to them on demand: `backend-developer`, `fullstack-developer`, `python-pro`, `rust-engineer`, `golang-pro`, `typescript-pro`, `sql-pro`, `cli-developer`, `build-engineer`, `deployment-engineer`, `devops-engineer`, `devops-incident-responder`, `platform-engineer`, `microservices-architect`, `websocket-engineer`, `prompt-engineer`, `qa-expert`, `test-automator`, `database-optimizer`, `terragrunt-expert`, `rails-expert`, `ui-designer`. 22 agents.

Tier 1 ships first because those agents are on the hot path — a broken tool field on `code-reviewer` immediately breaks every `/rfc-consensus-review` invocation, while a broken tool field on `terragrunt-expert` lies dormant until someone actually uses it. Tier 2 ships next because those agents are spawned by the RFC review system on demand, so latent breakage there manifests during RFC consensus reviews for relevant-domain RFCs. Tier 3 ships last because the cost of a latent issue is lowest (the agent is not in use), but it still ships — incomplete audits are themselves a quality risk because they leave a maintainer guessing which agents are trustworthy.

**Option B — Alphabetical.**
Simple ordering, no judgment required, but it interleaves critical and long-tail agents in a way that delays the value (you do not get `code-reviewer` fixed until the alphabetically-prior 6 agents are reviewed). Rejected on the basis that the audit is high-effort per file (45 minutes of human review minimum, per the PR-per-agent decision below); spending that effort first on agents that are not actively invoked is the worst possible ordering.

**Option C — By complexity (smallest files first to build momentum).**
A common pattern for migrations, but it has the same issue as alphabetical ordering: the smallest files are mostly Tier 3 agents (`ux-design-architect` at 39 lines is Tier 2; the next smallest are mostly Tier 1, but the ordering is not monotonic). The "build momentum" benefit is also weaker for this audit than for a typical migration because each PR is independent — there is no progressive learning curve where later PRs benefit from earlier ones structurally.

**Recommendation: Option A.** The criticality tiering is the explicit acknowledgment that this is an audit, not a refactor — the value lands when the in-use agents are aligned with the criteria, and tiers 2 and 3 are necessary but lower-value follow-on work. The tiering is also a natural pause-point for re-evaluation: after Tier 1 completes, the human can decide whether to push through to Tier 2 immediately, defer it for a sprint, or amend the criteria based on what was learned.

### Decision 2 — How is rationale captured?

**Option A — Dual-location: PR body and an audit footer in the file itself (recommended).**
Every audit PR includes a structured "Audit rationale" section in the body explaining (a) which criteria the original file failed, (b) the specific edits made to bring it into compliance, and (c) any judgment calls that were not obvious from the criteria. Simultaneously, the agent file gets a footer block appended:

```markdown
<!-- Audit log -->
<!-- 2026-05-10: criteria v1, audited by claude-agent-author; tools field removed (aspirational CLIs unavailable in Claude Code); description retained; body shortened from 296→210 lines (removed duplicate "checklist" sections that did not add information); model: opus pinned because this agent is on the hot path for /rfc-consensus-review. -->
```

The PR body is for the reviewer at merge time; the footer is for the next person who opens the file and wants to know "why does this differ from upstream?". The two channels overlap deliberately because they serve different lookup paths.

**Option B — PR body only.**
Cheaper to maintain (no footer drift), but the rationale becomes invisible once the PR is merged — a contributor reading the file two years later has to dig through git blame to understand why a section was removed. Rejected: the rework is meant to be reviewable in perpetuity, not just at the merge moment.

**Option C — Audit footer only.**
Inverts Option B's failure mode: the rationale lives in the file forever but the reviewer at merge time has to context-switch into the file to read it. Also rejected, because the PR body is the artifact the consensus-review or code-review agent reads to decide whether to approve the change.

**Option D — Separate audit document (one file collecting all rationales).**
A single `docs/agent-audit-2026-05-10.md` tracking the per-file rationale. Cleaner artifact for "the whole audit, all at once" but loses the per-file locality of Option A (the file does not know it was audited; the audit document does not know what the current state of the file is). Rejected.

**Recommendation: Option A.** The duplication is intentional — the marginal cost is one short paragraph per file, and it covers both the "what did this PR change" and "why does the file look like this" lookups.

### Decision 3 — How is the audit work reviewed by the human?

**Option A — One PR per agent (with batched exceptions for cross-cutting changes) (recommended).**
Default to one PR per agent file. The reviewer sees a self-contained diff: one frontmatter change, one body rewrite, one footer addition. This is reviewable in ~10–15 minutes per PR and produces 46 atomic git history entries that can be reverted individually if a regression is found later.

The batched exceptions are:
- The "review agent set" (`security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`) — these 5 agents are invoked together by `/rfc-consensus-review` and their conventions should match exactly. `code-reviewer` ships separately as the calibration PR (#1 in Step 2); it is excluded from this batch so the calibration review is self-contained.
- The "language pro" set (`python-pro`, `rust-engineer`, `golang-pro`, `typescript-pro`, `sql-pro`) — these have a uniform template upstream and should remain uniform after the audit. Batching them keeps the cross-cutting structural decisions (e.g., "do we keep the language version pin?", "do we standardize the section ordering?") in one review thread.

Any agent not in a batch ships as a standalone PR.

**Option B — Tiered mega-PRs (one PR per tier).**
46 files in 3 PRs. Faster to ship but unreviewable in practice — a 13-file PR for Tier 2 forces the reviewer to load 13 agent rewrites into working memory at once. Loses the ability to revert one agent's audit without reverting the whole tier. Rejected.

**Option C — All-in-one PR.**
46 files, one PR, 12,000 lines of diff. Unreviewable. Rejected.

**Option D — Stacked PRs (each agent on a branch off the previous agent's branch).**
The git-tooling pattern works for code that has interdependencies, but the agent files are independent — there is no benefit to stacking them, and the stacking adds rebase overhead every time one PR lands. Rejected.

**Recommendation: Option A.** The PR-per-agent default with two named batched exceptions is the smallest deviation from "one atomic change per PR" that handles the genuinely cross-cutting cases. Reviewer load is bounded at ~10–15 minutes per standalone PR and ~30–45 minutes per batched PR, both of which fit in a single focused session.

### Decision 4 — What are the evaluation criteria?

**Option A — Criteria file checked into the repo, derived from `claude-agent-author`'s documented conventions (recommended).**
Create `docs/agent-audit-criteria.md` at the start of the audit. The file enumerates the pass/fail checks every audited agent must meet, organized into hard requirements (file fails the audit until fixed) and soft recommendations (file gets a noted deviation but ships):

**Hard requirements (the audit cannot complete until met):**
1. **No aspirational `tools:` fields.** Either omit `tools:` entirely (inherits Claude Code's standard tool set) or list only tools Claude Code actually surfaces (`Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Task`, `WebFetch`, `WebSearch`, `TodoWrite`, `NotebookEdit`, etc.). External CLIs in `tools:` are forbidden — they silently restrict the agent.
2. **`description` is autoload-friendly.** The first 200 characters of the description must clearly state what the agent does and when to invoke it (Claude Code's autoload heuristics match on description prefix). Either the upstream "Expert X specialist …" style or the Anthropic `<example>` style is acceptable; the choice must match the criteria file's per-tier guidance.
3. **`model:` is pinned when the agent's recommended tier is non-default.** Per `CLAUDE.md`'s Model Usage Optimization section, default to `haiku` unless the task requires more; the agent's frontmatter must declare `model: sonnet` or `model: opus` explicitly when those tiers are required. Tier 1 agents that participate in `/rfc-consensus-review` must pin `model: opus`.
4. **No prose claims about coordinating with other subagents.** Subagents cannot spawn other subagents; replace any "partners with …" / "delegates to …" language with "if X is needed, recommend the user invoke `<skill or agent name>`".
5. **Audit footer present** in the format described in Decision 2.
6. **Body length proportionate to scope.** The upstream median of ~280 lines is excessive for many agents; the audit removes redundant "checklist" sections that restate the description, collapses near-duplicate subdomain sections, and trims aspirational metrics that are not actionable. Target: ≤ 200 lines unless the domain genuinely warrants more (and the rationale section documents why).

**Soft recommendations (deviation is allowed but must be noted in the rationale):**
1. **Project-specific guidance** — Tier 1 agents that interact with the plugin's RFC process should reference `docs/rfc-process.md` and the relevant skills.
2. **Section ordering convention** — for agents that retain the upstream template, the recommended section order is `When invoked` → `<domain> engineering checklist` → core domain sections → `Communication Protocol` → `Output format`. Agents deviating from this should note why.
3. **`color:` field consistency** — the four locally-customized agents use a `color:` field. The audit recommends adding `color:` to all Tier 1 agents for consistency with the locally-owned style, but does not require it.

**Option B — Implicit criteria, applied by the `claude-agent-author` agent's judgment.**
Trust the agent to apply consistent criteria across all 46 files without a written rubric. Rejected: this is exactly the inconsistency the audit is meant to eliminate. Without a written rubric, the agent's judgment can drift based on context (e.g., what it just read), and a future audit cannot reproduce the criteria.

**Option C — Borrow VoltAgent's contributing guide as the rubric.**
The upstream repo has contribution guidance for new agents; reuse it as-is. Rejected: the upstream guidance is calibrated for the upstream project, which still includes aspirational `tools:` fields and the rigid section template that this audit is partly trying to soften. Borrowing upstream criteria would reproduce the upstream's problems.

**Recommendation: Option A.** The criteria file is the most important durable artifact of this RFC — it is what makes the audit reproducible (someone running the audit again in a year measures against the same bar) and what makes new-agent additions cheap (a contributor adding a new agent reads the criteria file rather than reverse-engineering the existing set). The hard/soft split keeps the criteria honest: hard requirements are bugs being fixed, soft recommendations are preferences whose enforcement would be over-rigid.

### Decision 5 — How is the audit gated against partial completion?

**Option A — Per-tier completion gate; published criteria version (recommended).**
The audit is considered "complete for Tier N" when every agent in that tier has shipped its audit PR and the per-agent footer references the same criteria version. A tracking table in `docs/agent-audit-criteria.md` lists every agent and the criteria version it was last audited against. If the criteria file is updated after a tier is complete (e.g., a new hard requirement is added based on what the audit revealed), agents audited under the older version do not automatically need re-audit — but the tracking table makes the version skew visible so future maintainers can prioritize bringing the older audits forward.

**Option B — All-or-nothing gate (cannot ship Tier 1 until all 46 are audited).**
Rejected: this is the unbounded-WIP failure mode. Tier 1 is 12 agents shipping the highest-value fixes; gating the whole audit on Tier 3 completion (22 agents, lowest value) delays the value for no good reason.

**Option C — No gate; audits land whenever they land and the audit is "done" when the maintainer stops working on it.**
Rejected: this is what we have today (uncoordinated local customizations on four agents and no others). The gate exists precisely to force the question "are we done?".

**Recommendation: Option A.** The tracking table is the minimum bookkeeping that makes the audit's status answerable. The per-tier framing means the value lands as each tier completes, and the criteria-version tracking makes it possible to detect skew without forcing a re-audit cascade every time the criteria evolve.

## Drawbacks

- **High aggregate cost.** 46 PRs at Opus `claude-agent-author` plus ~10–15 minutes of human review per standalone PR (~30–45 for batched) sums to 8–12 hours of focused review time plus the Opus token spend. **Mitigation:** the tiered ordering makes the cost incremental — Tier 1 delivers most of the value (12 agents, all on the hot path) for a quarter of the total cost; Tiers 2 and 3 can be scheduled across multiple sprints or deferred indefinitely without losing the Tier 1 value. The criteria file is written once and amortized across the audit and all future agent work.
- **Criteria-file ossification risk.** Once `docs/agent-audit-criteria.md` exists, it becomes load-bearing — changing the criteria mid-audit creates skew, and changing them after the audit creates a quiet expectation that all 46 agents will be re-audited. **Mitigation:** the criteria file is explicitly versioned (the tracking table records which criteria version each agent was audited against), so version skew is observable rather than silent. Updates to the criteria are themselves RFCs or small focused PRs with rationale; the version increment makes the change traceable. Re-audits are not automatic — the maintainer prioritizes them based on the gap between the agent's audited version and the current criteria version.
- **`claude-agent-author` may have systematic blind spots.** A single agent doing all 46 audits will reproduce its own biases across all 46 files; if the agent over-indexes on one criterion (e.g., aggressively shortens bodies) the audit produces 46 over-shortened files. **Mitigation:** the human review step on every PR is the gate. The first 3–5 audits in Tier 1 (`code-reviewer`, `rfc-architect`, `feature-engineer`) function as the calibration set — if a systematic pattern emerges (every PR removes the same kind of content), the reviewer can adjust the criteria file or the agent's prompt before the rest of Tier 1 ships. Batched PRs (the "review agent set" and the "language pro set") also expose cross-file inconsistencies in one diff.
- **Locally-customized agents may regress.** Four agents (`feature-engineer`, `documentation-writer`, `ux-design-architect`, `rfc-architect`) were customized deliberately; an audit pass that re-applies the criteria could overwrite the bespoke `<example>` blocks or project-specific guidance. **Mitigation:** the criteria file explicitly preserves the Anthropic-style `description` with `<example>` blocks as one of the two acceptable styles, and the audit's analysis phase reads the current file before proposing changes. The PR review is the second gate — if an audit PR removes a deliberately-customized section, the reviewer rejects it and the audit PR is revised. The four customized agents are also concentrated in Tier 1, so they are the early-calibration cases.
- **The audit reveals criteria failures more than it fixes them.** It is possible that on first run, the criteria file will surface that several agents have a category of problem the criteria did not anticipate (e.g., conflicting domain claims, plagiarism from another source, broken cross-references to non-existent agents). **Mitigation:** the criteria file is meant to evolve. When an audit pass surfaces a new category of issue, the criteria file gets a new hard or soft requirement in a follow-up PR, and subsequent audits address it. The tracking-table version skew makes the criteria-evolution visible. Treating the criteria file as a living document is the design intent, not a flaw.
- **No automated re-audit detection.** When the criteria file is updated, nothing automatically flags the agents that were audited under the older version as needing re-review. **Mitigation:** the tracking table's version-skew column is the manual surface for this. A future RFC could add a `/agents-audit-status` skill that prints the skew, but that is out of scope here — the table read by eye is sufficient for the audit's scale (46 entries).

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `docs/agent-audit-criteria.md` | The audit's pass/fail rubric. Hard requirements (frontmatter rules, tool-field constraints, model-pinning rules, no-cross-agent-coordination prose, audit-footer format) and soft recommendations (project-specific guidance, section ordering, color field consistency, body-length guidance (soft)). Includes a per-agent tracking table with columns `Agent | Tier | Last audited (date) | Criteria version | Status`. Versioned `v1`, `v2`, … in a header field |
| Modify | `agents/*.md` (46 files, in tier order) | Per-agent audit: each PR modifies one file (or one batched group of files per Decision 3) to bring it into compliance with the current `docs/agent-audit-criteria.md` version. Each modified file gains an `<!-- Audit log -->` footer documenting the audit date, criteria version, auditor (`claude-agent-author`), and a one-paragraph summary of what changed and why |
| Modify | `docs/agent-audit-criteria.md` tracking table | Update the row for the audited agent after each PR merges: set `Last audited`, `Criteria version`, and `Status: pass` |
| Modify | `CLAUDE.md` (plugin root) | Add a short subsection to the "Agent delegation" area explaining that new agents must follow `docs/agent-audit-criteria.md`, and that existing agents may be re-audited when the criteria file is updated. One paragraph |

No new agents (this RFC depends on `claude-agent-author` from a separate RFC). No new skills. No hook changes. No `plugin.json` edits.

### Steps

This implementation has three phases: (1) create the criteria file and tracking table, (2) run the audit tier by tier with one PR per agent (or per batch), (3) close the audit when all tiers complete.

#### Step 1 — Create `docs/agent-audit-criteria.md`

Create the file with this exact content (the `v1` criteria are the starting point — updates ship as separate PRs that increment the version):

````markdown
# Agent Audit Criteria

This document defines the pass/fail criteria for auditing agent definitions in `agents/`. The criteria are versioned; the current version is recorded in the header field below. Each audited agent's footer references the criteria version it was audited against, and the tracking table at the bottom shows the current audit state for every agent.

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

- **`model: "opus"`** — required for the Tier 1 agents that own design or review responsibility: `rfc-architect`, `code-reviewer`, `feature-engineer` (when implementing an RFC; pinned via the agent file, since `/rfc-implement`'s skill body invokes it on opus regardless), `refactoring-specialist` — the `/refactor` skill body pins `model: "opus"` at spawn time, which overrides the agent frontmatter. The agent file should also set `model: opus` in the frontmatter so standalone (non-skill) invocations default correctly. Plus the rest of the Tier 1 set (`debugger`, `documentation-writer`, `security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`). The review-agent subset (`code-reviewer`, `security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer`) are additionally pinned to opus because they participate in `/rfc-consensus-review` per `docs/rfc-process.md`. The remaining Tier 1 agents (`documentation-writer`, `debugger`) pin opus because they are on the plugin's active-delegation hot path (listed in `CLAUDE.md`'s "Agent delegation" table) and operate at design-output quality, not exploration quality.
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
- `debugger` — `red`
- `refactoring-specialist` — `purple`
- `security-engineer` — `red` (deliberate overlap with debugger; both surface urgent work)
- `penetration-tester` — `red`
- `ai-engineer` — `cyan`
- `llm-architect` — `cyan`
- `mcp-developer` — `cyan`

Tier 2 and Tier 3 agents may add `color:` if the auditor judges it useful (e.g., `ux-design-architect`'s yellow is preserved by the audit), but it is not required.

### S3 — Conventional Commits scope alignment

The agent file's `name:` field is the natural Conventional Commits scope for changes to that agent. Audit PR commit messages should use the format `chore(agents/<agent-name>): audit pass under criteria v<version>`.

### S4 — Body length proportionate to scope (soft recommendation)

The upstream median of ~280 lines includes redundant content (numeric-threshold checklists that restate the description; near-duplicate subdomain sections). Prefer tighter bodies — target ≤ 250 lines — but preserve domain knowledge (smell catalogs, checklists, patterns, worked examples) that the agent genuinely needs to do its job. Trim tautologies and aspirational metrics; keep content that is actionable.

If the audited file retains more than 250 lines, the audit footer notes why (e.g., "kept at 290 lines because the domain spans three sub-disciplines with distinct decision frameworks that cannot be collapsed without losing precision").

There is no hard cap; the criterion is "remove what adds no value", not "enforce a line count."

## Tracking table

| Agent | Tier | Last audited | Criteria version | Status |
|-------|------|--------------|------------------|--------|
| ai-engineer | 1 | — | — | pending |
| api-designer | 2 | — | — | pending |
| backend-developer | 3 | — | — | pending |
| build-engineer | 3 | — | — | pending |
| claude-agent-author | 1 | — | — | pending (added after RFC 2026-05-10-claude-agent-author-agent merges) |
| cli-developer | 3 | — | — | pending |
| cloud-architect | 2 | — | — | pending |
| code-reviewer | 1 | — | — | pending |
| database-administrator | 2 | — | — | pending |
| database-optimizer | 3 | — | — | pending |
| debugger | 1 | — | — | pending |
| deployment-engineer | 3 | — | — | pending |
| devops-engineer | 3 | — | — | pending |
| devops-incident-responder | 3 | — | — | pending |
| documentation-writer | 1 | — | — | pending |
| feature-engineer | 1 | — | — | pending |
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
| rfc-architect | 1 | — | — | pending |
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
````

This file is the durable artifact. The criteria version is updated only by deliberate criteria-evolution PRs.

#### Step 2 — Audit Tier 1 (12 agents)

Tier 1 agents, in the order they should be audited:

1. `code-reviewer` (single PR — the calibration case for the audit)
2. `rfc-architect` (single PR — already locally-customized; the audit verifies criteria fit rather than restructuring)
3. `feature-engineer` (single PR — already locally-customized; same calibration role)
4. `refactoring-specialist` (single PR — already had its `tools:` field removed in RFC `2026-05-10-refactor-command`; audit verifies remaining criteria)
5. `debugger` (single PR)
6. `documentation-writer` (single PR — already locally-customized)
7. **Batched PR** — the "review agent set": `security-engineer`, `penetration-tester`, `ai-engineer`, `llm-architect`, `mcp-developer` (5 files, one PR per Decision 3)
8. `claude-agent-author` (single PR — the self-audit case; ships last in Tier 1 after all other Tier 1 agents are done, so that the agent has audit experience before auditing itself)

For each PR:

1. The maintainer creates a worktree off `main`: `git worktree add .worktrees/audit-<agent-name> -b audit/<agent-name>` (the maintainer owns worktree creation per the project's CLAUDE.md rule that agents do not create worktrees autonomously).
2. The maintainer or the orchestrating agent reads `docs/agent-audit-criteria.md` (current version) and the target agent file.
3. Invoke `claude-agent-author` (via direct subagent spawn from the user's session, with `model: "opus"` per the RFC process's requirement that all agent-quality and design work runs on opus) with this prompt template:

   ```
   Audit the agent definition at `agents/<agent-name>.md` against `docs/agent-audit-criteria.md` (version <current>).

   Read both files. Produce:
   1. An analysis: which hard requirements does the current file fail? Which soft recommendations does it deviate from?
   2. A proposed rewrite of the file that brings it into compliance with all hard requirements, applies soft recommendations where appropriate, and preserves the agent's core intent.
   3. A rationale section formatted for the PR body, with sub-sections "Hard requirements addressed", "Soft recommendations applied", and "Judgment calls" (any decisions not directly covered by the criteria).
   4. The audit footer line to append to the file, in the exact format specified by H5.

   Do not commit. Return the proposed file contents and the PR-body rationale; the human will review and apply.
   ```

4. Review the agent's proposal. If acceptable, write the modified file and append the footer. If the proposal removes deliberately-customized content (especially for `feature-engineer`, `documentation-writer`, `rfc-architect`, `ux-design-architect`), revise the proposal or push back to the agent with corrective instructions.
5. Commit with the message format from S3: `chore(agents/<agent-name>): audit pass under criteria v<version>`. The commit body includes the rationale section verbatim.
6. Open the PR. The PR description is the rationale section. Title format: `chore(agents): audit <agent-name> under criteria v<version>` (or `audit <batch-name> set` for batched PRs).
7. Include the tracking table update for the audited agent(s) in the audit PR itself — update `docs/agent-audit-criteria.md`'s row for the agent as a second commit (or as part of the same commit) before opening the PR. Each audit PR touches a different agent's row (a different line of the table), so concurrent audit PRs do not conflict. If two PRs happen to modify adjacent rows and git flags a conflict, a rebase resolves it trivially — the rows are independent. Keeping the table update in the PR ensures the table is never stale and avoids "chore: update tracking table" noise commits on `main`.

If the audit reveals a category of issue that the criteria did not anticipate (e.g., the first PR exposes that several agents have plagiarized content from another non-MIT source), pause the audit, write a follow-up PR that updates the criteria file to v2 with the new requirement, and resume the audit under v2. The version skew is documented in the tracking table.

Tier 1 is complete when all 12 agents have shipped audit PRs and their tracking table rows show `Status: pass` (or `pass with deviations` with documented deviations).

#### Step 3 — Audit Tier 2 (13 agents)

Tier 2 agents, in any order the auditor finds convenient:

`api-designer`, `cloud-architect`, `database-administrator`, `frontend-developer`, `graphql-architect`, `kubernetes-specialist`, `nextjs-developer`, `performance-engineer`, `postgres-pro`, `react-specialist`, `sre-engineer`, `terraform-engineer`, `ux-design-architect`

Each ships as a standalone PR following the same procedure as Tier 1. The criteria version used must be the current version at the time of the PR; if the criteria evolved between Tier 1 and Tier 2, the Tier 1 agents will show version skew in the tracking table — that is expected and visible.

Tier 2 is complete when all 13 agents have shipped audit PRs and their tracking table rows show `Status: pass` (or `pass with deviations`).

#### Step 4 — Audit Tier 3 (22 agents)

Tier 3 agents:

`backend-developer`, `build-engineer`, `cli-developer`, `database-optimizer`, `deployment-engineer`, `devops-engineer`, `devops-incident-responder`, `fullstack-developer`, `golang-pro`, `microservices-architect`, `platform-engineer`, `prompt-engineer`, `python-pro`, `qa-expert`, `rails-expert`, `rust-engineer`, `sql-pro`, `terragrunt-expert`, `test-automator`, `typescript-pro`, `ui-designer`, `websocket-engineer`

Same procedure as Tiers 1 and 2 with one batching opportunity:

- **Batched PR** — the "language pro set": `python-pro`, `rust-engineer`, `golang-pro`, `typescript-pro`, `sql-pro` (5 files, one PR). These have a uniform template upstream and the batched PR keeps them uniform post-audit.

All other Tier 3 agents ship as standalone PRs.

Tier 3 is complete when all 22 agents have shipped audit PRs and their tracking table rows show `Status: pass`.

#### Step 5 — Close the audit

When all three tiers are complete:

1. Update this RFC's `status:` to `Done` (handled by `/rfc-implement` when it finishes, per the standard RFC lifecycle).
2. Confirm `docs/rfc-braindump.md` has no stale entries referencing this RFC.
3. Confirm `docs/agent-audit-criteria.md`'s tracking table shows every agent at `Status: pass` (or `pass with deviations`) under the same criteria version, or document the version skew explicitly.
4. Update `CLAUDE.md` to add a paragraph in the "Agent delegation" area stating that new agents must follow `docs/agent-audit-criteria.md` and that the criteria file is the source of truth for agent quality.

#### Step 6 — Verification

After every individual PR, the audit's correctness is verified by:

1. **The criteria file's hard requirements are met by the file:**

   ```bash
   # H1: no aspirational tools (allowlist inversion)
   tools_line=$(grep -E '^tools:' agents/<agent-name>.md || true)
   if [ -n "$tools_line" ]; then
     # Extract tokens after 'tools:', strip list syntax, check each against allowed set
     echo "$tools_line" | sed 's/^tools:[[:space:]]*//' | tr ',\[\]' '\n' | tr -d ' "' | grep -v '^$' | \
       grep -Ev '^(Read|Write|Edit|MultiEdit|Bash|Grep|Glob|Agent|Task|Skill|AskUserQuestion|ToolSearch|WebFetch|WebSearch|TodoWrite|NotebookEdit|EnterPlanMode|ExitPlanMode|TaskCreate|TaskGet|TaskList|ListMcpResourcesTool|ReadMcpResourceTool|CronCreate|CronDelete|CronList|mcp__.*)$'
   fi
   ```

   Expected output: empty (no tokens outside the allowed set).

2. **H5: the audit footer is present:**

   ```bash
   grep -F '<!-- Audit log -->' agents/<agent-name>.md
   ```

   Expected output:

   ```
   <!-- Audit log -->
   ```

3. **The tracking table is updated for the audited agent:**

   ```bash
   grep -F "| <agent-name> |" docs/agent-audit-criteria.md
   ```

   Expected output: a row where `Last audited`, `Criteria version`, and `Status` are populated (not `—`). Substitute the literal agent name (e.g., `code-reviewer`) for `<agent-name>` before running.

After the entire audit closes (Step 5), the global verification is:

1. **No file has an aspirational `tools:` field:**

   ```bash
   # H1 global: list any agent with aspirational tools
   for f in agents/*.md; do
     tools_line=$(grep -E '^tools:' "$f" || true)
     if [ -n "$tools_line" ]; then
       offenders=$(echo "$tools_line" | sed 's/^tools:[[:space:]]*//' | tr ',\[\]' '\n' | tr -d ' "' | grep -v '^$' | \
         grep -Ev '^(Read|Write|Edit|MultiEdit|Bash|Grep|Glob|Agent|Task|Skill|AskUserQuestion|ToolSearch|WebFetch|WebSearch|TodoWrite|NotebookEdit|EnterPlanMode|ExitPlanMode|TaskCreate|TaskGet|TaskList|ListMcpResourcesTool|ReadMcpResourceTool|CronCreate|CronDelete|CronList|mcp__.*)$')
       [ -n "$offenders" ] && echo "$f: $offenders"
     fi
   done
   ```

   Expected output: empty.

2. **Every agent file has an audit footer:**

   ```bash
   grep -rL '<!-- Audit log -->' agents/*.md
   ```

   Expected output: empty (every file matches).

3. **The tracking table has no `pending` rows:**

   ```bash
   grep -E '\| pending \|' docs/agent-audit-criteria.md
   ```

   Expected output: empty.

If any check fails, the audit is incomplete; the failing agents are identified and re-audited under the current criteria version.

## Risks and open questions

- **Risk: `claude-agent-author` ships with a flaw that propagates to all 46 audits.** If the agent's initial implementation has a systematic bias (e.g., over-aggressively trimming domain knowledge), the audit will produce 46 over-trimmed files. **Mitigation:** the first 3–5 audits in Tier 1 (especially `code-reviewer` and `rfc-architect`) are the calibration set — if a systematic pattern emerges, the auditor can amend the criteria file or push fixes to `claude-agent-author`'s prompt before continuing. The PR-per-agent review structure means a problematic pattern surfaces within 1–2 PRs rather than after all 46 are merged.

- **Risk: the audit becomes the maintainer's exclusive focus for weeks.** 46 PRs at 10–45 minutes of review each is significant focused time. **Mitigation:** the tiered structure makes the audit pausable between tiers (Tier 1 delivers most of the value); the work does not need to complete in one calendar block. The tracking table makes the "where are we" lookup trivial when picking the audit back up after a pause.

- **Open question: what happens if `claude-agent-author` is itself in `agents/` and needs an audit?** It will be — the agent's definition file lives in `agents/` alongside the others. **Resolution within this RFC:** `claude-agent-author` audits its own file as the last Tier 1 PR (it will be added to the tracking table when RFC `2026-05-10-claude-agent-author-agent` ships; its position in the tracking table is Tier 1 because it is on the hot path for every subsequent audit). Self-audit is reasonable because the criteria are external to the agent — the criteria file says what "good" looks like, and the agent applies the same criteria to its own definition. The human review on the PR catches obvious self-favoring biases.

- **Open question: how are agents that should be removed handled?** The audit may surface that some Tier 3 agents are duplicates or stale (e.g., `devops-engineer` and `devops-incident-responder` may cover overlapping ground; `database-administrator` and `database-optimizer` may collapse to one agent). **Resolution within this RFC:** removal decisions are out of scope for the audit; the audit's job is "bring the existing file into compliance with the criteria", not "decide whether the file should exist". If during an audit the auditor concludes a file should be removed, the audit PR is paused and the maintainer opens a separate RFC (or a focused PR with explicit rationale) to consider the removal. The audit then either resumes (if the file stays) or is skipped (if the file is removed; the tracking table row becomes `Status: removed by <PR-ref>`).

- **Risk: criteria-version skew accumulates.** If the criteria file evolves several times during the audit (v1 → v2 → v3), the tracking table will show a mix of versions per agent. A maintainer reading the table at v3 cannot easily see "which agents are at the latest version" without scanning the column. **Mitigation:** the tracking-table column is sortable by eye for a 46-row table; this is acceptable scale. A future RFC could add tooling to render the skew (e.g., a `/agents-audit-status` skill that prints a summary), but the manual table is sufficient at this scale. The version skew is also bounded by the audit's expected lifespan (weeks, not years) — most criteria evolution happens early as the audit reveals categories of issues, and stabilizes after Tier 1.

- **Open question: should the audit re-derive `description` fields, or preserve them?** The upstream descriptions are generally good ("Expert X specialist mastering …"); rewriting them risks losing autoload precision that the upstream author tuned. **Resolution within this RFC:** the audit preserves the `description` field by default. The criteria file's H2 specifies the autoload-friendliness requirement; if the existing description meets H2, it stays. Only failing descriptions get rewritten, and the audit footer documents why.

- **Risk: re-audit cascades when criteria evolve.** A new hard requirement added to v2 implicitly invalidates all v1 audits. **Mitigation:** the criteria file's update PR explicitly states whether the new requirement is "applies to new audits only" (no cascade — v1 agents stay at v1 and are re-audited only if revisited for other reasons) or "applies retroactively" (cascade — all v1 agents must be re-audited before the criteria update can be considered complete). The default is "applies to new audits only" unless the new requirement reflects a discovered bug that the older audits introduced.

## Relationship to other RFCs

This RFC depends on **RFC `2026-05-10-claude-agent-author-agent`** (status: Draft — see `docs/rfcs/2026-05-10-claude-agent-author-agent.md`) shipping first. Without `claude-agent-author`, the audit driver does not exist and the audit would either be done by an ad-hoc agent (reproducing the inconsistency the audit is meant to fix) or by the human directly (defeating the cost-amortization of an audit). This RFC explicitly assumes `claude-agent-author` is available; if that RFC is rejected or significantly delayed, this RFC should be re-evaluated for whether a different driver (a human-only audit, an alternative agent) is workable.

This RFC builds on **RFC `2026-05-10-refactor-command`** (status: done), which established the local-ownership posture for `agents/` (removed `/agents-update`, added MIT attribution to `refactoring-specialist`). The audit completes the implication of that ownership: now that the project owns the files, the project is responsible for their quality. This RFC also picks up `refactoring-specialist`'s already-completed `tools:` cleanup as the prototype for the same edit across the remaining 42 files.

This RFC informs (but does not block) the future **`/agents-diff`** RFC (status: Draft — see `docs/rfcs/2026-05-10-agents-diff-skill.md`). When `/agents-diff` ships, it will surface upstream changes against the locally-audited files. The audit footer's criteria-version field tells the maintainer "this file is at v2 locally; upstream has its own version line — decide whether the upstream change is worth re-auditing this file under v3."

This RFC does not modify any skill or hook. It does not change `plugin.json`. It does not introduce new agents. It is purely a content-quality migration over the existing `agents/` directory, anchored by one new documentation file (`docs/agent-audit-criteria.md`).
