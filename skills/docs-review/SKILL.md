---
name: docs-review
description: Run a scoped documentation review against the codebase. The skill instructs the main agent to spawn the docs-agent subagent on Sonnet, with a seven-phase protocol that audits docs/guide/** and README.md for drift (broken examples, stale references, workflow drift) and coverage gaps against the current code. Respects strict ownership — never touches ARCHITECTURE.md, CONTRIBUTING.md, BEST_PRACTICES.md, project-brief.md, or rfcs/. Use after a feature lands, when /sync reports the docs-agent has improved, or any time the user-facing docs may be out of step with the code. Triggered by "/docs-review [scope-hint]".
argument-hint: "[scope-hint]"
---

# /docs-review — Scoped Documentation Review

This skill runs in the main conversation. Its job is to spawn a `bytewyrd:docs-agent` subagent with the seven-phase documentation-review protocol below as the prompt, then relay the subagent's questions, plan, and final report back to the user.

## Step 1 — Capture scope

The invocation passed this scope hint:

```
$ARGUMENTS
```

If the scope hint is empty, ask the parent (the user or the agent that invoked this skill) one targeted question: "What scope should this documentation review cover? Options: (a) a recently-implemented RFC by identifier (e.g., `2026-05-10-foo`); (b) a path or area (`docs/guide/tutorials/`, `the auth module`); (c) `all` to audit the full `docs/guide/**` against the current codebase." Do not spawn the subagent without a scope.

The scope hint must also carry any non-obvious context the review needs (e.g., "this feature deprecated the `--legacy-flag`, so any doc still referencing it is correctly drifting — flag for removal, not update"). The subagent does not see the parent's history; if the parent expects the subagent to know something they discussed earlier, they must include it in the hint.

## Step 2 — Spawn the docs-agent subagent

Use the Agent tool to spawn a `bytewyrd:docs-agent` agent with:

- `model: "sonnet"`
- Prompt: the entire **Documentation review protocol** section below, with the scope hint substituted into the Scope block

The protocol is the agent's prompt. The agent definition supplies the ownership boundary, the Diátaxis vocabulary, and the constraints. The protocol below tells the agent how to apply that knowledge for this specific invocation.

The skill itself does not run the protocol — the spawned subagent does. While the subagent runs, the main agent's job is to relay any questions the subagent surfaces back to the user (especially during the Phase 5 approval gate) and to deliver the final Phase 7 report.

## Step 3 — Wait for the subagent's plan, get user approval, deliver to the subagent

The subagent will return a plan (Phase 4) and stop. Present the plan to the user verbatim and ask for one of:

- `apply all`
- `apply 1, 3, 5` (or any subset; grouped findings like `1a, 1b` apply together)
- `cancel`

Pass the user's response back to the subagent (resume the agent task with the response as input). The subagent will then apply the approved findings (Phase 6) and return the final report (Phase 7).

If the user requests changes to the plan ("merge findings 2 and 3", "skip finding 4", "add a check that does X"), pass the request to the subagent — the subagent revises and re-presents the plan, and the approval cycle repeats.

## Step 4 — Deliver the final report

When the subagent finishes (Phase 7), present the structured report to the user verbatim. The report includes the scope, files audited, findings by severity, applied edits with commit SHAs, deferred findings, and recommended follow-ups. The user decides what to do with the recommended follow-ups.

After presenting the report (whether the review ran successfully or the user cancelled), delete the sentinel file if it exists:

```bash
rm -f .bytewyrd/last-feature-engineer-stop
```

This prevents the `SessionStart compact` hook from re-echoing the reminder after the review has been completed or explicitly skipped. If the user wants to dismiss the reminder manually (without running `/docs-review`), they can run `rm -f .bytewyrd/last-feature-engineer-stop` directly.

---

# Documentation review protocol (passed as the subagent's prompt)

You are the `docs-agent` for a scoped documentation review. Your system prompt (the agent definition) gives you the ownership boundary, the Diátaxis vocabulary, and the constraints. This protocol is what you follow for this specific invocation.

## Scope

```
<SCOPE HINT FROM $ARGUMENTS>
```

The scope hint includes any non-obvious context from the parent conversation. You do not see the parent's history; treat the scope hint as the complete brief.

## Protocol — seven phases

### Phase 1 — Resolve scope

Map the scope hint to a concrete file list. The hint may reference:

- **An RFC identifier** (`2026-05-10-foo`): read `docs/rfcs/2026-05-10-foo.md`, extract the file structure table from its Implementation spec, and treat those files as the *codebase* scope (the source-of-truth surface to compare docs against). The *docs* scope is `docs/guide/**` files that mention any of the codebase scope's symbols, skills, agents, paths, or concepts (use Grep across `docs/guide/`).
- **A path or area** (`docs/guide/tutorials/`, `src/auth/`): if the path is under `docs/guide/`, that is the docs scope; the codebase scope is whatever those docs reference (resolved by reading each doc file and noting referenced symbols/skills/agents/paths). If the path is under source code, the codebase scope is that path; the docs scope is `docs/guide/**` files that mention any of the path's symbols.
- **A free-text description** (`the auth module`, `everything related to /refactor`): use Grep to locate matching files in both `docs/guide/` and the codebase; list both sets explicitly before proceeding.
- **`all`**: codebase scope is the whole project tree (excluding `docs/`, `.git/`, and `.worktrees/`); docs scope is the whole of `docs/guide/**`.

Print the resolved scope (both code and docs lists) before phase 2. If the lists are empty (docs scope has no files yet — likely on the first invocation against a fresh `docs/guide/` directory), proceed to phase 2 anyway; the coverage audit will identify which files *should* exist.

### Phase 2 — Coverage audit

For the codebase scope, determine what user-facing documentation *should* exist under `docs/guide/**`:

- **Tutorials:** if the scope includes a consumer-facing feature with a clear "first-time use" workflow, a tutorial should exist (`docs/guide/tutorials/<feature-or-skill>.md`).
- **How-to guides:** for each user-facing task the scope enables (e.g., "add a custom skill", "configure hooks for my project", "drop an unwanted RFC"), a how-to guide should exist (`docs/guide/how-to/<task>.md`).
- **Reference:** for each shipped skill (file under `skills/<name>/SKILL.md`), a reference page should exist (`docs/guide/reference/skills.md` or one file per skill — the agent picks the granularity based on the project's existing convention; default to a single `skills.md` for small skill counts, one-file-per-skill when count exceeds 15). Same for agents (`docs/guide/reference/agents.md`) and hooks (`docs/guide/reference/hooks.md`).
- **Contributor section:** `docs/guide/contributing.md` should exist and cover plugin anatomy, "how to add a skill," "how to add an agent," "how plugin packaging works." This file is created or extended by every review whose scope touches a new skill or agent.
- **Index:** `docs/guide/index.md` exists and links to the four sub-areas (tutorials, how-to, reference, contributing.md). Updated whenever a new file is added under `docs/guide/**`.

Compare the *should-exist* list against the *does-exist* list (using `ls docs/guide/**/*.md`). Coverage gaps are entries from the should-exist list that have no corresponding file. Tag each gap with `coverage-gap` severity.

### Phase 3 — Drift detection

For each file in the docs scope (the *does-exist* set under `docs/guide/`), run these checks:

- **Symbol references:** scan the file for fenced code blocks and inline code spans. For each named symbol (function names, class names, CLI flags, environment variables), Grep the codebase for the symbol's definition. Missing symbols are tagged as `broken-example` severity.
- **Skill references:** for each `/skill-name` mentioned in prose or code, check that `skills/<name>/SKILL.md` exists (or `.claude/skills/<name>/SKILL.md` for plugin-local skills). Missing skills are tagged as `stale-reference` severity.
- **Agent references:** for each `agent-name` mentioned in prose or code, check that `agents/<name>.md` exists. Missing agents are tagged as `stale-reference` severity.
- **File-path references:** for each relative path mentioned (e.g., `docs/CONTRIBUTING.md`, `.claude/settings.json`, `agents/foo.md`), check that the file exists at that path. Missing paths are tagged as `stale-reference` severity.
- **Workflow drift:** read the doc's described workflow (typically the first numbered list or `## Quick start` section) and compare it to the actual current workflow inferred from the matching skill's `SKILL.md`. If the doc says "run X then Y" and the current skill says "run X, answer prompt, then Y," tag as `workflow-drift` severity.

Each finding records: file, line range (if specific), severity, what is wrong, and what the fix would be (one line).

### Phase 4 — Plan

Produce a refactoring-style plan as a numbered list. Each item is one finding:

```
Documentation review plan for <scope>:

1. <severity>: <one-line description>
   File: <path> (line <range> if applicable)
   Current: <what the doc says>
   Should be: <what the doc should say given the codebase>
   Risk: <low | medium | high> — <why; usually low for docs work>

2. <severity>: <one-line description>
   ...
```

Group related findings when they cannot be cleanly separated (e.g., "two broken examples in the same tutorial fixed by updating one shared variable name"). Number bundled findings as `1a, 1b, 1c` so the parent can approve or skip the group as a unit.

Order findings by severity (`broken-example` first, then `stale-reference`, then `workflow-drift`, then `coverage-gap`). Within a severity, order by file path alphabetically for predictable review.

If a finding is ambiguous ("the doc says `--foo`, the codebase has both `--foo` and `--foo-bar`; unclear which the doc means"), include both interpretations in the finding's `Should be:` line and let the parent decide.

### Phase 5 — Approval gate (mandatory)

Return the plan to the parent and stop. The parent (the main agent or the user) reviews the plan and decides which findings to apply. Do not proceed to phase 6 until the parent responds with one of:

- `apply all` — proceed with every finding in order
- `apply 1, 3, 5` — proceed with the listed finding numbers in order (grouped findings like `1a, 1b` apply together when the group number is listed)
- `cancel` — stop; proceed to phase 7 to report findings without applying any

If the parent asks clarifying questions, answer them. If the parent requests changes to the plan ("merge findings 2 and 3", "skip finding 4", "the broken example in finding 1 is correct — the symbol is being deprecated"), revise the numbered list and re-present, then wait for a new approval response.

This gate is non-negotiable. The agent does not auto-apply documentation changes even when the changes look mechanical.

### Phase 6 — Apply

For each approved finding, in the order the parent listed them:

1. Apply the smallest possible documentation edit that resolves the finding. Do not "while I'm here" rewrite surrounding content.
2. If the finding is a coverage gap (a file that should exist but does not), create the file with content appropriate to its Diátaxis quadrant (tutorial / how-to / reference / contributing).
3. Verify the edit by re-running the relevant check from phase 3 against the updated file. The check should now pass.
4. Commit the finding. Use a Conventional Commits message: `docs(guide): <one-line description from the plan>` — one commit per approved finding (or per approved group when findings were bundled as `1a, 1b, 1c`).
5. If `docs/guide/.gitkeep` exists and this is the first real file being committed to `docs/guide/`, include its deletion in the same commit as the first file (not a separate commit).
6. Move to the next approved finding.

If a finding turns out to be larger or riskier than the plan estimated (e.g., fixing one stale reference requires restructuring the surrounding section to maintain coherence), stop and re-present the revised finding to the parent before continuing.

### Phase 7 — Report

After all approved findings are applied (or after `cancel` was received), return a structured report:

```
Documentation review complete.

Scope (code): <files in code scope>
Scope (docs): <files in docs scope>
Files audited: <count>
Findings by severity:
  broken-example: <count> (<one-line summary>)
  stale-reference: <count> (<one-line summary>)
  workflow-drift: <count> (<one-line summary>)
  coverage-gap: <count> (<one-line summary>)
Findings applied: <numbered list with commit SHAs>
Findings deferred: <list with reason>
Recommended follow-up: <one or two sentences, or "none">
```

Do not edit the report after returning it. The parent decides what to do with the recommended follow-ups.

## Constraints (inherited from the agent definition; restated here for clarity)

- **Ownership boundary first.** Never edit `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, `docs/rfcs/**`, `docs/rfc-process.md`, or `docs/rfc-braindump.md`. `README.md` **is** in scope — it is bootstrap-once (written by `/sync` at project creation, then project-owned) and may drift as the plugin evolves. If a finding seems to require editing one of the off-limits files, surface the boundary violation in the plan with a suggested split.
- **Trust the codebase.** When code and docs disagree, the code is the spec; the doc gets updated. Never edit code from this skill.
- **One commit per finding.** Bundling unrelated findings into one commit destroys reviewability.
- **Respect the scope.** Do not audit files outside the resolved scope. Mention adjacent-scope drift in recommended follow-ups.
- **Do not start long-running processes.** Doc-site previews, watchers — ask the parent to run them in a separate terminal if needed.

## When this skill is *not* the right tool

- Updating `docs/ARCHITECTURE.md` — that file is owned by changes to component structure. The agent that made the structural change updates it.
- Updating `docs/CONTRIBUTING.md` — owned by changes to dev workflow or quality gates. The agent that made the workflow change updates it.
- Capturing a session learning — use `/best-practices-extract` (writes to `docs/BEST_PRACTICES.md`).
- Creating or updating an RFC — use `/rfc-new`, `/rfc-read-feedback`, `/rfc-implement`.
- Updating project identity (name, description, problem) — use `/sync` Step 2.
- General-purpose docs writing outside `docs/guide/**` and `README.md` — use the `documentation-writer` agent directly.
