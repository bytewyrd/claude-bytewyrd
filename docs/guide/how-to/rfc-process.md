# Use the RFC process

An RFC (Request for Comments) is a short design document written *before* implementation. The plugin's RFC process is built around a skill cluster that handles authoring, agent review, approval, and implementation. This guide explains the process from your perspective — when to write an RFC, how to write a good one, and what happens at each stage.

For the skill command reference (syntax for each `/rfc-*` skill), see [RFC workflow](rfc-workflow.md).

---

## When to write an RFC — and when to skip it

**Write an RFC for:**

- New features or capabilities that require design decisions
- Architectural changes (module structure, data flow, infrastructure topology)
- Migrations (tooling changes, protocol upgrades, schema changes)
- Any work expected to take more than one focused session
- Anything where getting it wrong would be expensive to undo

**Skip the RFC for:**

- Bug fixes with an obvious, localized solution
- Documentation-only changes
- Minor config tweaks with no design trade-offs
- Work that is directly implementing a step described in an already-approved RFC

When in doubt, write one. A short RFC is always better than no RFC — it forces the reasoning to be explicit, and it is much cheaper to reject a design on paper than to rewrite it after implementation.

**Scope check before writing:** if your idea covers multiple independent subsystems, split it into separate RFCs. Each RFC should describe work that can be implemented and tested independently. If the subsystems must be designed together because they are tightly coupled, one RFC is fine.

---

## The braindump-to-RFC lifecycle

An idea does not have to be fully formed to capture it. The lifecycle has two entry points:

### Quick capture: `/rfc-braindump`

Use `/rfc-braindump <idea>` to park a rough thought in `docs/rfc-braindump.md`. No design needed — just enough to remember the idea and its motivation. An Opus agent distills your raw idea into a tight paragraph entry.

When you are ready to promote a braindump entry to a full RFC, run `/rfc-new` — it lists existing braindump entries and lets you pick one.

### Full RFC: `/rfc-new`

Run `/rfc-new <description>` when you are ready to design. The skill handles the entire authoring and review flow and presents you a finished Draft.

---

## How to write a good RFC

The `rfc-architect` agent writes the RFC from your description. Your job is to give it a clear description and review the output critically. Here is what makes each section strong.

### A strong problem statement (the Summary section)

One paragraph. Answer: what is being proposed, and why. Prefer concrete statements over vague ones.

Weak: "Improve the sync skill to handle more cases."

Strong: "Extend `/sync` with a `--dry-run` flag that prints every file it would create or update without writing to disk. Teams with large projects need to preview sync output before committing, especially during plugin upgrades."

### A clear "Should we do this?"

An explicit yes/no with brief rationale. This is the most skipped section and the most valuable — it forces the author to make the decision visible upfront rather than burying it in the implementation. If the answer is "no," the RFC should not exist.

### A grounded Analysis / Options section

Present the trade-offs between approaches and recommend one. Every claim about what a tool "can" or "cannot" do must be grounded in documentation or source evidence — the `rfc-architect` agent uses Context7 and Exa to verify claims before asserting them. If you see `[UNVERIFIED]` in a Draft RFC, it is a signal that a claim needs verification before the RFC can be approved.

When two options are operationally identical, do not list them separately — present the shared option once and note the distinguishing variant. Duplicate options add noise.

### A no-placeholders implementation spec

The implementation spec is what the `feature-engineer` agent follows. Every step must contain what an implementer actually needs:

- Exact file paths and actions (create vs. modify)
- Concrete code blocks with actual commands and expected output
- No "TBD", "TODO", "implement later", or "add appropriate error handling" without specifics

**File structure table first.** Before listing steps, map every file that will be created or modified:

```markdown
| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/dry-run.sh` | Print planned changes without writing |
| Modify | `skills/sync/SKILL.md` | Add --dry-run flag handling to Step 3 |
```

This is where decomposition is decided. Doing it explicitly in the spec prevents the implementation agent from guessing.

---

## The Draft review cycle

After `/rfc-new` creates the initial Draft, it immediately runs the review loop:

1. The `rfc-architect` agent fills in the RFC template and dispatches domain-specific review agents in parallel (general correctness, plus security/frontend/infrastructure/database agents based on what the RFC touches).
2. `rfc-architect` incorporates feedback and runs a self-review checklist (coverage, placeholder scan, consistency, evidence audit).
3. `/rfc-consensus-review` runs five independent reviewer agents, synthesizes findings by consensus, auto-fixes verified bugs, and walks you through design opinions interactively.

You see the post-review, post-consensus version — never a raw first draft.

### What the human reviews vs. what agents handle

**Agents handle:**

- Verifying factual claims about external tools, libraries, and services
- Catching placeholder language, missing spec steps, and type inconsistencies
- Identifying design quality issues (consensus-based, tiered by agreement level)
- Auto-fixing verified bugs without asking

**You review:**

- Whether the problem statement accurately captures what you want to solve
- Design opinions surfaced by `/rfc-consensus-review` (presented one at a time, with RFC context)
- Whether the implementation spec is complete enough for implementation to begin
- The final decision to approve

If you want to add feedback after reviewing the Draft, edit the RFC file directly and add `FEEDBACK:` comment lines where you want changes. Then run `/rfc-read-feedback` to have `rfc-architect` address each one.

---

## Approval as the human gate

`/rfc-approve` is the only action that moves an RFC from `Draft` to `Approved`. Only humans invoke it — agents write and review, humans approve. The skill shows you the RFC summary and waits for explicit confirmation before committing the status change.

**What approval means:** you are satisfied that the problem statement is accurate, the implementation spec is unambiguous, and the trade-offs have been considered. The `feature-engineer` agent will follow the spec as written.

**What to check before approving:**

- No `FEEDBACK:` markers remain (run `/rfc-read-feedback` if there are)
- No `[UNVERIFIED]` markers remain (the agent could not verify a factual claim; verify it before approving)
- The file structure table is complete
- The implementation steps contain no placeholder language

---

## Implementation and done/dropped states

After approval, `/rfc-implement` spawns the `feature-engineer` agent with the RFC as its spec. The agent follows the implementation spec exactly — it does not redesign or extend scope. If it hits an ambiguity, it surfaces the gap rather than guessing.

When the PR is merged, the RFC is marked `Done` and committed.

If you decide not to implement an RFC (superseded by a better approach, requirements changed, the problem went away), use `/rfc-drop <RFC> <reason>`. Dropped RFCs are permanent historical record — files are never deleted. The recorded reason is the audit trail for why the work was not done.

---

## RFC statuses at a glance

| Status | Meaning |
|--------|---------|
| `Draft` | Being written or under agent review; not yet human-approved |
| `Approved` | Human-approved; implementation may begin via `/rfc-implement` |
| `Done` | Implementation complete and merged |
| `Dropped` | Will not be implemented; reason recorded |

Use `/rfc-summary` at any time to see all in-flight RFCs (Draft and Approved) grouped by status.

---

## Related

- [RFC workflow](rfc-workflow.md) — the skill command reference (syntax and behavior for each `/rfc-*` skill).
- [Concepts: the RFC process](../concepts.md#the-rfc-process-as-the-backbone-of-structured-work) — the mental model behind RFC-first design.
