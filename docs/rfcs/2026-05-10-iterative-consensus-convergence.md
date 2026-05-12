---
rfc: "2026-05-10-iterative-consensus-convergence"
title: "Iterative Consensus Convergence in /rfc-consensus-review"
author: "Rodrigo Kochenburger"
status: "Approved"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Rework `/rfc-consensus-review` so the consensus pass loops until the RFC reaches **bug convergence** — no verified bugs are produced by an additional pass — and **only then** surfaces design opinions to the user. Each iteration spawns three fresh `bytewyrd:code-reviewer` instances (no shared conversation history; prior-round context reaches them only through an explicit "previously-addressed" block in the prompt), auto-fixes verified bugs via `bytewyrd:rfc-architect`, and the next iteration's reviewers evaluate the post-fix RFC. The reviewer count drops from the prior single-shot skill's 5 to 3 because the convergence loop provides redundancy through *sequential* re-review across iterations, not just parallel diversity within an iteration — three parallel Opus reviewers per pass with a quorum-based consensus rule preserves the signal while cutting per-iteration cost by 40%. Design opinions are collected during the convergence loop but held until after convergence; presenting them earlier is noise because an auto-fix in iteration N can invalidate a design question raised in the same iteration. After the human resolves design opinions one-by-one, the skill runs **one final single-shot validation pass** to confirm the design-opinion incorporations did not introduce new bugs. A hard cap (`max_iterations = 5`) guards against runaway loops; if convergence is not reached, the loop terminates and the remaining un-validated fixes are surfaced explicitly to the human alongside the iteration history.

## Should we do this?

**Yes.** The current single-shot skill has a structural defect: it auto-fixes verified bugs **once** and never re-reviews the fixes. A fix that introduces a new bug — or that is itself buggy — ships to the human unchallenged with no mechanism that could catch it. The braindump that motivates this RFC captures the same observation: "a fix in one pass can introduce new issues." The single-shot design also presents design opinions on an unstable RFC: the user is asked "should we change X to Y?" while X is about to be rewritten by the auto-fix layer in a way that may obviate or reshape the question. This wastes user attention on stale framing and creates re-work when the post-fix RFC raises a different question about the same area.

The convergence loop solves both problems with one mechanism: keep iterating the bug-fix pass until reviewers stop finding new bugs (convergence), then — and only then — engage the human on design opinions. A separate final validation pass after design-opinion incorporation closes the same hole on the design side. The cost is bounded — each iteration is a parallel 3-reviewer spawn (one main-context turn of latency, three concurrent agent calls), and the hard cap of 5 iterations bounds the worst case. The payoff is that the RFC the human reads has been verified stable by the consensus mechanism: every bug the loop's reviewers could find has been fixed and re-reviewed.

## Current state

`/rfc-consensus-review` is a single-shot skill: spawn five reviewers in parallel, synthesize findings by consensus, auto-fix verified bugs in **one** pass via `bytewyrd:rfc-architect`, walk the human through design opinions, report. There is no loop, no re-review of fixes, and no separation between bug stabilization and design discussion.

**What exists today (verbatim summary of the skill's behavior, sourced from `skills/rfc-consensus-review/SKILL.md`):**

1. **Step 1 — Identify the RFC.** Argument or staged-file detection picks one RFC file.
2. **Step 2 — Build previously-addressed context.** If the caller (typically `/rfc-new`) provides a "topics already fixed in prior rounds" list, prepend it to the reviewer prompt as a "do not re-raise" instruction. This is the only existing mechanism for memory across invocations, and it is **caller-provided** — the skill itself does not maintain iteration state.
3. **Step 3 — Spawn 5 parallel reviewer agents.** Five `bytewyrd:code-reviewer` agents (`model: "opus"`) spawn in a single message. Each gets the full RFC text and a structured prompt requesting Category / Severity / Confidence / Type / Location / Issue / Fix per finding.
4. **Step 4 — Main-agent synthesis and verification.** Group findings by underlying issue (4a). Verify each group's factual claims against code or docs (4b). Complete any `needs-research` items (4c). Classify each group as `bug` (verified wrong), `design` (defensible preference), `nit` (style), or `false-positive`.
5. **Step 5 — Apply consensus tiers.** Map each group's `(count, type)` pair to an action: `bug` (any tier) → auto-fix; `design` (Critical/Moderate) → walk through; everything else → skip or offer.
6. **Step 6 — Auto-fix all verified bugs.** Spawn one `bytewyrd:rfc-architect` (`model: "opus"`) with the full bug list grouped by tier. The agent fixes every bug in one pass, runs the self-review checklist, does not change status, does not commit. Print a changelog of fixes.
7. **Step 7 — Walk through design opinions interactively.** Present each design finding to the human one at a time (highest consensus first); apply approved fixes immediately.
8. **Step 8 — Final report.** Summary of bugs fixed, design opinions addressed, nits available on request, false-positives closed.
9. **Step 9 — Caller protocol.** Behavior is the same whether invoked standalone or from `/rfc-new`. The walk-through always happens in the main conversation.

**How `/rfc-new` calls it today (sourced from `skills/rfc-new/SKILL.md` Step 8):**

> After `bytewyrd:rfc-architect` completes step 7, invoke the `/rfc-consensus-review` skill on the new RFC. The consensus review skill runs to completion: it auto-fixes all verified bugs, walks through any design opinions interactively with the human, and reports. Wait for it to finish — including the interactive walk-through — before proceeding to step 9.
>
> **If verified bugs were found and fixed:**
> 1. Invoke `/rfc-consensus-review` a second time on the updated RFC.
> 2. If verified bugs still remain after the second pass, do **not** loop further — surface them to the human in step 9.

So `/rfc-new` already attempts a hand-rolled two-pass loop: if the first consensus call fixes bugs, invoke again; if the second call still finds bugs, give up and surface them. This is the seed of the convergence idea, but the implementation has four structural defects:

**Defect 1 — Loop is caller-side, two-pass, and hand-rolled.** Only `/rfc-new` does it. A user who invokes `/rfc-consensus-review` standalone gets exactly one pass — no re-review of fixes at all. The standalone-invocation case is precisely when the user is most likely to want the strongest convergence guarantee, because they are explicitly asking for review.

**Defect 2 — Two passes is not convergence.** Even from `/rfc-new`, the loop terminates after the second pass regardless of whether new bugs were introduced. If pass 2's auto-fix is itself buggy, the user gets a still-broken RFC with no signal that pass 3 would have caught it. The braindump's word for this is "single-shot" — and "two-shot" has the same shape, just one degree less so.

**Defect 3 — Design opinions are presented on an unstable RFC.** Both passes walk the human through design opinions in the same Step 7 that runs the auto-fix. So in `/rfc-new`'s two-pass loop, the human is potentially asked about the same area twice — once during pass 1's walk-through, then again during pass 2's after the fix has rewritten the surrounding text. Design questions raised on text that is about to be rewritten are noise; the human's "yes / no / skip" answers from pass 1 may not even apply to the post-fix text.

**Defect 4 — Previously-addressed context is opaque and lossy.** The "previously-addressed topics" block (Step 2) is a free-text comma-separated list that the caller (`/rfc-new`) constructs. There is no schema, no automatic carry-forward of the prior round's verified-bug list, no way for the reviewers to look at "here is the verbatim fix that was applied to address concern X" — just a list of bare topic names. Reviewers are told "do not re-raise these," but they have no way to verify the fix was correct, so a buggy fix that touches the previously-addressed area can be silently accepted because reviewers are instructed to defer to it.

**Other surfaces that reference the current behavior:**

- `docs/rfc-process.md` § *Writing a new RFC*, step 5: "`/rfc-consensus-review` runs: five independent reviewers in parallel, findings synthesized by consensus. Critical findings (4–5/5 reviewers) are fixed by `rfc-architect` in a second pass; consensus runs once more to verify. If critical findings remain after two passes, they are surfaced to the human alongside the RFC." This documents the two-pass behavior as the canonical process. This RFC updates that paragraph to describe the convergence loop.
- The `bytewyrd:` skill prefix is set in `.claude-plugin/plugin.json` (`"name": "bytewyrd"`). All spawned agents in this skill use the fully-qualified `bytewyrd:` form already (`bytewyrd:code-reviewer`, `bytewyrd:rfc-architect`); this RFC does not change that.
- No other skill in the plugin invokes `/rfc-consensus-review`. The only callers are `/rfc-new` (above) and direct human invocation.

## Analysis / Options

There are six coupled decisions: what convergence means, how the loop is structured, where the loop lives, when design opinions surface, how iteration state crosses pass boundaries, and how many reviewers run per iteration.

### Decision 1 — What does "convergence" mean?

**Option A — Zero new verified bugs in the latest pass (recommended).**
A pass converges when its verified-bug count is **zero** — no group of findings, when verified against code and docs, classifies as `bug`. `false-positive`, `design`, and `nit` findings are not blockers; only verified bugs gate convergence. This matches the existing skill's classification taxonomy (currently in Step 4b of the single-shot skill, becoming Step 2d in the new skill): the convergence check piggybacks on a classification the skill already performs.

**Option B — No new findings of any type in the latest pass.**
A pass converges only when reviewers produce **no findings at all** (no bugs, no design opinions, no nits). Rejected because design opinions and nits are by construction subjective and reviewer-dependent; three fresh opus reviewers will almost always produce at least one design opinion on any non-trivial RFC, even a perfectly-stable one. The loop would never terminate under normal operating conditions, and the hard cap would always be the actual terminator — which is exactly what convergence is supposed to avoid.

**Option C — Bug count strictly decreasing pass-over-pass.**
A pass converges when its verified-bug count is **strictly less than** the prior pass's. Rejected because a pass that fixes 3 bugs and introduces 1 (net: 2 down from 3) would converge after one iteration, even though the introduced bug is real. The current loop's pathology is precisely this — it cannot see introduced bugs because it does not re-review the fixes. "Strictly decreasing" papers over the same pathology in a different way.

**Recommendation: Option A.** Bug count zero is unambiguous, matches the existing classification, and is the right correctness gate. Design opinions and nits being present at convergence is expected and intended — they are surfaced to the human after convergence (Decision 4), not as a blocker.

### Decision 2 — How is the loop structured?

**Option A — While-loop with hard cap on iterations (recommended).**
Structure: `for iteration in 1..=max_iterations: spawn reviewers, synthesize, verify, classify. If verified_bugs.is_empty(): break (converged). Else: auto-fix bugs via rfc-architect, record this iteration's topics in state, continue.` Termination: convergence (bug count = 0) or iteration count = `max_iterations`. The hard cap is the safety net for the pathological case where every pass introduces a new bug; without it, a buggy `rfc-architect` could trap the loop indefinitely.

**Option B — Until-loop with no cap, trust convergence.**
Same shape but no cap; rely on the loop to terminate naturally. Rejected — a runaway loop on an Opus-driven parallel reviewer spawn is expensive enough that even a 0.1% chance of hitting the pathology is too much risk to take. The cap is cheap; the absence of a cap is occasionally catastrophic.

**Option C — Fixed iteration count, no convergence check.**
Just run N passes (e.g., 3) regardless of bug-count signal. Rejected because mandating a fixed N pays the cost of additional passes even when the RFC is already stable after one pass — pure waste in the common-good-RFC case. The convergence check is what makes the design self-tuning to the actual state of the RFC.

**Option D — Adaptive cap (max_iterations grows with RFC size or initial bug count).**
Reasonable in theory but adds complexity (heuristic to pick the cap; explanation surface for "why did your skill spend more iterations on my RFC than on someone else's"). Rejected for v1 in favor of the fixed cap; if the fixed cap turns out to be too low in real use, a follow-up RFC can introduce adaptivity with the data to inform the heuristic.

**Recommendation: Option A.** The fixed cap (`max_iterations = 5`) is a conservative starting value: it is high enough that several iterations of "fix introduces a new bug" can still converge before the cap fires, and low enough that the pathological case (every pass introduces a new bug) is bounded to roughly 5× the cost of a single-shot pass. The right value is data-dependent and the constant is centralized in one place (the skill's `## Configuration` table) so adjusting it after real-world use is a one-line edit.

### Decision 3 — Where does the loop live?

**Option A — In the `/rfc-consensus-review` skill body itself (recommended).**
The skill becomes the canonical "review until stable" surface. Standalone invocation gets the same convergence guarantee as invocation from `/rfc-new`. `/rfc-new`'s Step 8 simplifies from "invoke, check, invoke again" to "invoke and wait" because the loop is now internal to the skill it invokes. The skill's behavior matches its name better — "consensus review" with convergence baked in.

**Option B — In `/rfc-new` (and any future caller), keep `/rfc-consensus-review` single-shot.**
Today's pattern, but extended to "loop until convergence" instead of fixed two passes. Rejected because every caller now has to implement the same loop, and a standalone-invocation user never gets convergence at all. The convergence logic is the right kind of behavior to encapsulate in the skill it belongs to.

**Option C — Split into two skills: `/rfc-review-pass` (single-shot) and `/rfc-consensus-review` (loops the first one).**
Surface area doubles for a single user-visible feature. Rejected on cost — the convergence loop is the natural behavior of "review for consensus," not a separate concept.

**Recommendation: Option A.** The skill owns the loop. Callers invoke once and get a converged RFC back.

### Decision 4 — When are design opinions surfaced?

**Option A — Only after bug convergence, then run one final validation pass (recommended).**
Iterations 1..N (convergence loop) collect design opinions but do not present them. Once convergence is reached, the accumulated design opinions are deduplicated (a design opinion raised in three different iterations on the same area is one opinion, not three), then walked through interactively with the human one at a time. After the human resolves the design opinions, a **single final validation pass** runs to verify the design-opinion incorporations did not introduce new bugs. If that final pass finds verified bugs, they are surfaced to the human along with the iteration history — the human chooses to re-enter the loop, accept the bugs, or stop.

**Option B — Surface design opinions in every iteration, as today.**
Rejected — this is the braindump's diagnosed defect. Design questions on an unstable RFC are noise.

**Option C — Surface design opinions only at the very end, no final validation pass.**
Cheaper but loses the symmetric guarantee on the design side: the human resolves design opinions, the RFC is mutated as a result, and the human ships the mutated RFC without anyone having re-reviewed those mutations. The bug convergence loop carefully eliminates exactly this hole on the bug side; not closing it on the design side after introducing the mechanism would be inconsistent and would partially defeat the purpose of the change.

**Recommendation: Option A.** Bug convergence first; then design walk-through; then one final validation pass. The final pass is single-shot, not looped — it is a sanity check, not a second convergence round. If it finds bugs, the human decides what to do (loop again or accept).

### Decision 5 — How does iteration state cross pass boundaries?

**Option A — Structured iteration ledger maintained by the skill itself (recommended).**
The skill keeps an in-memory ledger across iterations of:
- Iteration number
- Verified bugs found this iteration (group descriptions + the verbatim fix that `rfc-architect` applied, recovered from the changelog string `rfc-architect` returns in Step 6)
- Design opinions collected this iteration (group description, count, location)
- Reviewer count and identity (always 3 `bytewyrd:code-reviewer` `model: "opus"` — recorded for the iteration history)

This ledger drives:
- The "previously-addressed topics" prompt prepended to the next iteration's reviewers (replaces the lossy caller-provided list in current Step 2)
- The design-opinion deduplication after convergence (group design opinions by `(location, issue)` similarity across iterations; same opinion raised in multiple iterations counts as one)
- The iteration history surfaced to the human in the final report

**Option B — No state across iterations; each pass is fully fresh.**
Reviewers re-discover and re-raise the same bugs each pass (cheaper to implement but a tax on every iteration's reviewers). Design opinions are never deduplicated; the user sees the same opinion N times. Rejected on quality grounds — the previously-addressed mechanism in the current skill exists for exactly this reason and removing it would be a regression.

**Option C — Persist iteration state to disk (e.g., `.rfc-consensus-state.json` next to the RFC).**
Survives across main-agent context resets (e.g., a `/compact`). Adds a file-management dimension (when to clean up, what if the file is stale, how to handle multiple in-flight reviews). Rejected for v1 — the loop runs in a single main-agent turn from invocation to completion; a context reset mid-loop is rare and recovers cleanly by re-invoking the skill (the new run starts fresh; nothing is lost that was not already lost when the context reset).

**Recommendation: Option A.** In-memory ledger, structured, drives previously-addressed prompts, design deduplication, and the iteration history report.

### Decision 6 — How many reviewers run per iteration?

The prior single-shot skill spawned five reviewers per pass because that was the only pass — parallel diversity was the *only* source of redundancy. The convergence loop changes that calculus fundamentally: each iteration is itself a re-review of the prior iteration's fixes. Redundancy now stacks across iterations *sequentially*, not just within a single pass *in parallel*. The question is how to distribute the reviewer budget between parallel breadth (more reviewers per pass) and sequential depth (more iterations).

**Option A — 3 reviewers per iteration with quorum-based consensus tiers (recommended).**
Three parallel `bytewyrd:code-reviewer` agents per iteration. Consensus tiers shift accordingly: `3/3` = unanimous (strongest signal), `2/3` = quorum / majority, `1/3` = single voice. Per-iteration reviewer cost drops by 40% relative to the 5-reviewer baseline. Across a worst-case run (5 iterations + 1 final validation pass = 6 reviewer-passes), this saves 12 Opus reviewer calls (30 → 18). The convergence loop provides the redundancy that the dropped fourth and fifth reviewers would have provided: a bug that one iteration's reviewers miss is likely to be caught either by the next iteration's reviewers (post-fix re-review) or by the final validation pass.

**Option B — 5 reviewers per iteration (status quo from the single-shot skill).**
Preserves the existing tier mapping (`4-5/5` Critical, `3/5` Moderate, `1-2/5` Minor) verbatim, no recalibration needed. Rejected on cost: the convergence loop changes the meaning of "5 reviewers per pass" by multiplying it across iterations. The marginal value of reviewer 4 and 5 in a single pass is lower than the marginal value of running an additional iteration with 3 reviewers; the iteration captures a class of bugs (introduced by the fix layer) that no number of parallel reviewers within a single pass can capture, because the bug does not exist until after the fix runs.

**Option C — 5 reviewers in iteration 1, 3 reviewers in subsequent iterations.**
Front-load parallel diversity on the initial pass (where the RFC has not been pre-stabilized) and trim for later iterations (where the RFC has already been partially fixed). Rejected because the asymmetry adds complexity (two tier scales — `4-5/5, 3/5, 1-2/5` for iteration 1 vs `3/3, 2/3, 1/3` for later iterations) and the deduplication / previously-addressed logic has to bridge the two regimes. The clarity cost of two scales outweighs the small additional signal in iteration 1; iteration 1 is also the iteration most likely to find genuine pre-existing bugs that any reasonable reviewer would catch, so the marginal value of reviewer 4 and 5 there is smaller than it would be on a noise-heavy later iteration.

**Option D — 7 reviewers per iteration (strictly more parallel diversity).**
Rejected outright on cost; the convergence loop already pays a multiplier on per-iteration cost, and pushing per-iteration reviewer count up compounds that multiplier. Even if 7 reviewers caught slightly more bugs per iteration, the additional cost across a 5-iteration worst case (35 → 42 reviewer calls plus the final validation pass) is not justified.

**Why 3 is the floor:** with 3 reviewers, the consensus tiers have clean meanings — unanimous (3/3), quorum/majority (2/3), single voice (1/3). With 2 reviewers, ties are ambiguous; with 1 reviewer there is no consensus at all. Three is the minimum where quorum-based aggregation still has a meaningful majority tier distinct from a unanimous tier, which preserves the existing skill's signal structure (the human sees Critical / Moderate / Minor analogues, just remapped).

**Why this is safe under the convergence loop:** the convergence loop's promise is that the loop continues until reviewers stop finding bugs. If 3 reviewers in iteration N miss a bug that 5 would have caught, the more likely outcome is not "ship the bug" but rather "iteration N+1's reviewers catch it after the auto-fix runs," or "the final validation pass catches it." The 5-reviewer baseline in the single-shot world had no recovery path; the 3-reviewer baseline in the converged world has up to 4 additional reviewer-passes (iterations 2-5) plus the final validation pass to recover.

**Recommendation: Option A.** 3 reviewers per iteration, quorum-based consensus tiers, 40% per-iteration cost reduction. The convergence loop provides the redundancy budget that lets us trim parallel breadth without sacrificing overall correctness signal.

## Drawbacks

- **Cost in tokens and wall-clock time.** Each iteration is three parallel Opus reviewers plus one `rfc-architect` auto-fix pass plus one main-agent synthesis turn. A 3-iteration convergence costs roughly 3× a single-iteration pass; the worst case (5 iterations + 1 final validation pass) is bounded by `(max_iterations + 1)` reviewer-passes. **Mitigation:** the reviewer count was set to 3 (down from the prior single-shot skill's 5) specifically to absorb the cost multiplier introduced by iteration — the per-iteration cost drops 40% relative to the prior baseline, so a 3-iteration converged run (3 reviewer-passes × 3 reviewers = 9 Opus reviewer calls) costs slightly more than a single-shot 5-reviewer pass (5 calls) but substantially less than the naïve 3-iteration × 5-reviewer alternative (15 calls). The worst-case 6-pass run with 3 reviewers (18 Opus calls) is comparable to a 4-iteration × 5-reviewer alternative (20 calls) but with a wider iteration budget for catching introduced bugs. The hard cap bounds the absolute worst case. The current `/rfc-new` hand-rolled two-pass loop already pays 2 × 5 = 10 Opus reviewer calls for a weaker guarantee; the new design's typical good case (1–2 iterations + 1 final validation pass = 6–9 Opus calls) is comparable cost for a substantially stronger correctness guarantee.

- **Reviewer fatigue / convergence on subjective text.** If reviewers keep raising the same low-confidence finding each iteration (Confidence: medium or low, Type ambiguous), the skill could classify it as `bug` repeatedly and trigger fixes that other reviewers immediately reverse. **Mitigation:** Step 2d's verification step (carried over unchanged from the current skill's Step 4b) — every finding gets verified against code/docs before classification. Low-confidence findings on subjective text classify as `design` or `nit`, not `bug`, so they do not gate convergence. A bug that flips between "fixed" and "broken" across iterations is a real bug whose fix is wrong; the iteration ledger's verbatim-fix tracking surfaces it as an oscillation pattern in the iteration history, and the human sees the pattern in the final report.

- **Three reviewers means narrower parallel breadth per iteration.** With 3 reviewers instead of 5, an individual iteration has 40% less parallel coverage of the RFC. A bug that only one out of five reviewers would have caught (a 1/5 = 20% finding) might now be missed by all three if the responsible reviewer is one of the two that were dropped. **Mitigation:** the convergence loop converts the missed-bug scenario into a delayed-catch scenario rather than a missed-forever scenario. If iteration N's three reviewers miss a bug, iteration N+1 spawns three fresh reviewers on the post-fix RFC; the missed bug (if it is a real bug) is likely to surface there or in the final validation pass. The 5-reviewer single-shot world had no recovery path because there was no iteration N+1. Single-reviewer (1/5) findings were historically treated as Minor and skipped anyway under the prior tier rules, so the bugs most at risk from the reviewer-count reduction are precisely the bugs that the prior skill was also not auto-fixing. The mitigation has limits: a bug consistently missed by all three reviewers across all iterations is genuinely missed by this skill, just as it would have been by a 5-reviewer skill in the case where all five reviewers missed it. The fundamental statistical limit (you cannot catch bugs no reviewer notices) is unchanged.

- **Design-opinion deduplication is heuristic.** Two reviewers raising "the same" design opinion in different iterations may phrase it differently enough that the dedup step keeps them as separate items. **Mitigation:** the dedup is `(location, issue)` similarity — designed conservatively so the failure mode is "occasionally show the human two near-duplicate opinions" rather than "drop a real opinion." Showing two near-duplicates is small noise; dropping a real opinion would be a regression. The conservative threshold accepts the small noise to avoid the regression.

- **Hard cap can hide a real problem.** If the loop hits `max_iterations = 5` without converging, the iteration-`max_iterations` auto-fix ran but was never re-reviewed by another iteration. The fixes may be correct, may be incomplete, or may have introduced new bugs — the skill cannot tell without one more pass that did not happen. **Mitigation:** the final report's "did not converge" case uses a distinct, prominent heading (`### Convergence NOT reached`), lists the un-validated iteration-`max_iterations` fixes with their `fix_applied` strings, and explicitly tells the human to either accept-and-re-run (which validates them as a fresh pass) or revert-and-edit-manually. The "converged" case uses the neutral `### Convergence reached after N iterations` heading. The visual difference is intentional and load-bearing — a human skimming should see the "NOT reached" header at a glance.

- **Loss of incremental human signal.** Today, the user sees design opinions mid-loop and can stop / redirect the process early. Under the convergence-first design, the user does not see design opinions until after bug convergence, which can take several iterations of agent work. **Mitigation:** the skill prints a one-line status after each iteration (`Iteration N: 3 bugs found, 2 design opinions deferred. Auto-fixing bugs.`) so the user has visibility into progress. The user can interrupt at any point. The deferred design opinions are still presented at the end; nothing is dropped, only re-ordered.

- **Final validation pass adds a guaranteed extra cost even when nothing breaks.** Even on an RFC where the design-opinion incorporations are uncontroversial, the final pass spends another 3-reviewer + verification turn to confirm nothing broke. **Mitigation:** acceptable — the final pass is what closes the symmetric hole on the design side. Its cost is bounded (single-shot, not looped) and the alternative ("trust the design fixes were safe") is exactly the kind of single-shot assumption the convergence loop exists to eliminate.

- **Reviewer anchoring bias from the previously-addressed block.** Telling reviewers "this was already fixed" creates a known anchoring effect: the reviewer is biased against re-flagging the area, even when the fix was wrong. The current single-shot skill has the same problem at smaller scale (one round of "already fixed" context); the convergence loop makes it cumulative across iterations. **Mitigation:** the previously-addressed block's wording (Step 2b) is explicit that the reviewer's judgment is not being overridden — they are expected to engage with the fix and flag residual problems if the fix is wrong, and the verbatim `fix_applied` text is included so the reviewer can read what was changed rather than only seeing "this topic was addressed." If real-world use shows reviewers consistently defer to bad fixes, a follow-up could spawn one of the three reviewers per iteration *without* the previously-addressed block (a "naïve reviewer" control); out of scope for v1 but the mechanism is straightforward to add later.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create or Modify | `.claude/skills/rfc-consensus-review/SKILL.md` | Internal copy (create if missing): rewrite the skill body to implement the convergence loop (the existing 9-step single-shot structure is reorganized into 7 steps: identify → convergence loop (Step 2 with sub-steps 2a–2g) → deduplicate deferred design opinions → walk through design opinions → final validation pass → final report → caller protocol). Adds the iteration ledger structure, the convergence termination condition, the `max_iterations = 5` guard, the new 3-reviewer quorum-based consensus tiers, and the design-opinion deferral / deduplication / post-convergence walk-through |
| Modify | `skills/rfc-consensus-review/SKILL.md` | Exported skill: identical content to the internal copy, promoted after the internal copy is validated per the project's promote-through-production workflow |
| Modify | `skills/rfc-new/SKILL.md` | Simplify Step 8 from the hand-rolled "invoke, check, invoke again" to "invoke and wait for convergence." Update Step 9's bullets to forward the new convergence-report structure. The skill becomes thinner because the convergence guarantee moves into `/rfc-consensus-review` |
| Modify | `docs/rfc-process.md` | Update the "Writing a new RFC" section's step 5 paragraph (line 153) from the two-pass-then-give-up description to the convergence-loop description, including the new 3-reviewer quorum-based tier nomenclature. The change is one paragraph; no other section of `docs/rfc-process.md` references the consensus skill's reviewer count or pass count |

No new files. No new agent definitions. No changes to `bytewyrd:code-reviewer` or `bytewyrd:rfc-architect` agent definitions.

### Steps

#### Step 1 — Rewrite `.claude/skills/rfc-consensus-review/SKILL.md` (internal copy first)

Per the project's promote-through-production workflow (see `MEMORY.md`: "changes start in `.claude/` first, validated, then promoted to plugin export artifacts"), the internal copy at `.claude/skills/rfc-consensus-review/SKILL.md` is rewritten first. The exported copy at `skills/rfc-consensus-review/SKILL.md` is updated in Step 2 with the identical content.

**Note:** the existing `skills/rfc-consensus-review/SKILL.md` does not currently have an internal twin in `.claude/skills/rfc-consensus-review/` (verify with `ls .claude/skills/`). If absent, **create** the directory and file as the first action of this step:

```bash
mkdir -p .claude/skills/rfc-consensus-review
```

Then write the file at `.claude/skills/rfc-consensus-review/SKILL.md` with this exact content:

````markdown
---
name: rfc-consensus-review
description: Spawns 3 parallel independent reviewer agents on an RFC in an iterative convergence loop — each iteration auto-fixes verified bugs, then re-reviews until no new bugs appear (convergence). Design opinions are collected during the loop and walked through with the human only after convergence is reached. A final validation pass confirms design-opinion incorporations did not introduce new bugs. Critical = 3/3 reviewers (unanimous); Moderate = 2/3 reviewers (quorum); Minor = 1/3 reviewers (single voice). Triggered by "/rfc-consensus-review [RFC number or filename]".
---

# RFC Consensus Review

Spawns three independent reviewer agents in an iterative loop. Each iteration auto-fixes verified bugs and re-runs the reviewers on the post-fix RFC. The loop terminates when reviewers produce zero verified bugs (convergence) or when iteration count hits `max_iterations`. Design opinions surface only after convergence — presenting them on an unstable RFC is noise. A final single-shot validation pass after design-opinion incorporation confirms nothing new broke.

The reviewer count is 3 (rather than 5 as in the prior single-shot version of this skill) because the convergence loop provides redundancy through sequential re-review across iterations, not just parallel diversity within a single pass. Three parallel reviewers with a quorum-based consensus tier (unanimous / quorum / single-voice) is sufficient signal per iteration when the loop itself provides up to 4 additional iterations of re-review plus a final validation pass.

## Configuration

| Constant | Value | Purpose |
|----------|-------|---------|
| `max_iterations` | `5` | Hard cap on convergence-loop iterations. Bounds the cost of a pathological loop where each pass introduces a new bug |
| `reviewer_count` | `3` | Number of parallel reviewers per iteration. Reduced from the prior single-shot skill's 5 because the convergence loop provides redundancy through iteration |
| `reviewer_agent` | `bytewyrd:code-reviewer` | Agent type for reviewers. Each spawn is a fresh agent instance (no Claude conversation history); prior-round context reaches the reviewers only via the explicit previously-addressed block built in Step 2b |
| `reviewer_model` | `"opus"` | Model for reviewers. Unchanged from prior behavior |
| `fix_agent` | `bytewyrd:rfc-architect` | Agent type for the per-iteration auto-fix pass |
| `fix_model` | `"opus"` | Model for the fix agent. Unchanged from prior behavior |

## Consensus tiers

| Consensus | Label | Meaning |
|-----------|-------|---------|
| 3 reviewers (unanimous) | **Critical** | All three reviewers independently raised this — strongest signal |
| 2 reviewers (quorum/majority) | **Moderate** | A clear majority — confident but not unanimous |
| 1 reviewer (single voice) | **Minor** | One reviewer raised it — lowest confidence |

## Finding types

| Type | Meaning | Default action |
|------|---------|----------------|
| `bug` | Verified wrong — confirmed against code/docs | Auto-fix in this iteration (no confirmation needed); gates convergence |
| `needs-research` | Factual claim not yet verified | Research first, then re-classify |
| `design` | Correct but debatable design preference | Defer to post-convergence walk-through |
| `nit` | Style/clarity only, no correctness impact | Skip unless human requests |

## Iteration ledger

The skill maintains an in-memory ledger across iterations:

| Field | Type | Populated when | Purpose |
|-------|------|----------------|---------|
| `iteration_number` | integer (1..=`max_iterations`) | Start of each iteration (Step 2a) | Iteration history; previously-addressed prompt |
| `verified_bugs_this_iteration` | list of `{location, issue, fix_applied}` | After Step 2f (auto-fix completes; `fix_applied` populated from `rfc-architect`'s returned changelog) | Previously-addressed prompt for next iteration; final report |
| `design_opinions_this_iteration` | list of `{location, issue, suggested_fix, count}` | After Step 2d (classification) and recorded in Step 2e | Deferred until post-convergence walk-through; deduped at convergence |
| `false_positives_this_iteration` | list of `{location, issue, evidence}` | After Step 2d (verification closes as `false-positive`) and recorded in Step 2e | Previously-addressed prompt for next iteration |
| `converged` | boolean | End of each iteration (Step 2g) | Loop termination signal |
| `converged_at_iteration` | integer or null | When convergence is first reached (Step 2g) | Final report; "converged after N iterations" |

The ledger is in-memory only — it does not persist across separate skill invocations. A context reset mid-loop recovers by re-invoking the skill; the new invocation starts fresh.

## Steps

### 1. Identify the RFC

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: `docs/rfcs/<filename>`]" — accept a blank response as confirmation of the default.

Read the matching `docs/rfcs/*.md` file in full. Initialize the iteration ledger with `iteration_number = 0`, all lists empty, `converged = false`, `converged_at_iteration = null`.

### 2. Convergence loop

Repeat Steps 2a–2g for `iteration_number` in `1..=max_iterations`. After each iteration, check the convergence condition (Step 2g) and either break or continue.

#### 2a. Increment iteration counter

Set `iteration_number = iteration_number + 1`. Print to the user:

```
Iteration <N> of up to <max_iterations>: spawning 3 reviewers…
```

#### 2b. Build previously-addressed context

If `iteration_number > 1`, construct a previously-addressed block from the ledger entries of all prior iterations. The block has three sub-sections:

```
**Context from prior iterations of this review.** The items below were addressed earlier in this iterative review. The point of showing them to you is *not* to suppress your judgment — review the RFC as you normally would. The point is so you can recognize when a current concern overlaps with prior work and respond appropriately:

- If you see a problem that overlaps with a Fixed bug below, evaluate whether the fix actually resolved it. If the fix is wrong or incomplete, flag the residual problem explicitly: "The iteration-N fix to <location> applied <fix_applied>, but the underlying problem persists because <reason>." A bare repeat of the original concern (without engaging with the fix) is not actionable; engage with the fix.
- If you see a problem that overlaps with a Deferred design opinion below, the human will resolve that opinion after the bug-fix loop converges. Do not re-raise it as a bug just because it has not been addressed yet — that's by design.
- If you see a problem that overlaps with a Closed-as-false-positive item below, you are free to disagree with the prior verification, but explain what evidence the prior pass missed.

Fixed bugs (auto-applied by the rfc-architect agent in prior iterations):
- [Iteration 1] <location>: <issue> → <fix_applied>
- [Iteration 2] <location>: <issue> → <fix_applied>
- …

Deferred design opinions (will be walked through with the human after convergence):
- [Iteration 1] <location>: <issue>
- …

Closed as false-positive (with verifying evidence):
- [Iteration 1] <location>: <issue> (evidence: <evidence>)
- …
```

If `iteration_number == 1`, omit the previously-addressed block entirely (no prior iterations exist).

#### 2c. Spawn 3 parallel reviewer agents

Spawn three `bytewyrd:code-reviewer` agents (`model: "opus"`) in a **single message**. Do not ask for human confirmation first.

Each agent receives the full RFC text and this prompt:

> [Insert previously-addressed block from Step 2b, if any]
>
> Review this RFC for correctness, completeness, and design quality. For each finding provide:
> - **Category**: `correctness` | `completeness` | `design` | `clarity`
> - **Severity**: `critical` | `moderate` | `minor`
> - **Confidence**: `high` (you verified against code or docs) | `medium` (strong inference) | `low` (speculation)
> - **Type**: `bug` (definitively wrong or broken) | `opinion` (defensible but you'd do it differently) | `nit` (style/naming only)
> - **Location**: section name, or "general"
> - **Issue**: what is wrong or missing (1–3 sentences)
> - **Fix**: the specific change needed (1–3 sentences)
>
> Only flag things you are reasonably confident about. Include `low`-confidence findings only when the potential impact is high (e.g. a silent failure in production). Skip pure style preferences unless they cause genuine confusion. Do not summarize or praise the RFC. If you find no problems, say "No findings."

#### 2d. Group and classify findings

Once all three agents return:

**Group findings.** Group findings that describe the same underlying issue — same root problem in the same part of the RFC, even if worded differently. For each group record:
- Count (N/3)
- Clearest issue description from any reviewer
- Best-described fix from any reviewer
- Highest severity assigned
- Confidence spread across reviewers (e.g. "2 high, 1 medium")

**Verify and classify.** For each group, independently determine its type — do not rely solely on what reviewers labeled it.

- Read the relevant RFC section.
- For any finding that makes a factual claim about external behavior, library behavior, or code execution: verify it. Fetch the relevant doc page, grep the code, or read the file. This is mandatory when reviewer confidence is mixed or low, or when the claim is the sole basis for a Critical/Moderate classification.
- Classify as `bug` (verified wrong), `needs-research` (plausible but unconfirmed after reading the RFC), `design` (RFC is defensible; this is a preference), or `nit` (clarity only).
- If verification shows the RFC is already correct, close as `false-positive`. Note the evidence so it can be added to the ledger and to the next iteration's previously-addressed prompt.

**Complete any remaining research.** For each `needs-research` finding: fetch docs or read code now. Re-classify as `bug`, `false-positive`, or `design`.

#### 2e. Update the iteration ledger

For this iteration, record into the ledger:

- `verified_bugs_this_iteration`: every group classified as `bug` (will be auto-fixed in Step 2f; the `fix_applied` field is populated after Step 2f returns)
- `design_opinions_this_iteration`: every group classified as `design`
- `false_positives_this_iteration`: every group closed as `false-positive`, with the verifying evidence

Nits are recorded only as a count; their detail is not retained across iterations (nits are not subject to deduplication or convergence gating).

#### 2f. Auto-fix all verified bugs in this iteration

If `verified_bugs_this_iteration` is empty, skip to Step 2g (the iteration converged with no bugs to fix).

Otherwise, without asking for confirmation, spawn one `bytewyrd:rfc-architect` agent (`model: "opus"`) with:
- The RFC content
- The complete list of verified bugs grouped by tier (Critical → Moderate → Minor)
- Instruction: fix every bug in the list, return a structured changelog of `{location, issue, fix_applied}` triples (one per bug), run the self-review checklist after, do not change status, do not commit

Parse the returned changelog and populate `fix_applied` for each bug in `verified_bugs_this_iteration`. The `fix_applied` string is the verbatim text the `rfc-architect` returned — it is used as-is in the next iteration's previously-addressed prompt so reviewers can see what was changed.

Run the reflow script after prose changes (see memory for the script).

Print a brief iteration changelog:

```
Iteration <N> auto-fixed <count> verified bugs:
• [Critical 3/3] <location> — <fix_applied>
• [Moderate 2/3] <location> — <fix_applied>
• …
```

#### 2g. Check convergence

Decide whether to break out of the loop or continue to the next iteration.

- **True convergence:** `verified_bugs_this_iteration` is empty. The most recent reviewer pass found zero bugs, which means the prior iteration's fixes (or the RFC's initial state, on iteration 1) have been validated by an independent review. Set `converged_at_iteration = iteration_number`, `converged = true`, and **break** out of the loop.
- **Hard-cap termination:** `iteration_number == max_iterations` AND `verified_bugs_this_iteration` is not empty. The cap has fired before reviewers stopped finding bugs. The iteration's auto-fix (Step 2f) did run, so the bugs detected in this iteration *were* fixed — but those fixes were never independently re-reviewed because no further iteration will run. Leave `converged_at_iteration = null`, set `converged = false`, and **break** out of the loop. The final report (Step 6) will surface this case prominently as "convergence not reached" with the un-validated fixes from this iteration listed under "fixes applied in iteration `<max_iterations>` but not validated by a subsequent review pass."
- **Continue:** otherwise (`iteration_number < max_iterations` AND `verified_bugs_this_iteration` is not empty), the iteration's auto-fix ran and the loop continues to iteration `iteration_number + 1` for re-review.

Note that on iteration 1 with zero bugs found, the convergence is real (a clean initial RFC); on iteration N > 1 with zero bugs found, the convergence validates the auto-fixes from iteration N-1. Both cases are equally valid and counted as "converged at iteration N."

### 3. Deduplicate deferred design opinions

After the convergence loop exits, walk the ledger's `design_opinions_this_iteration` lists across all iterations. Deduplicate by `(location, issue)` similarity:

- Two design opinions match if they target the same section (or both target "general") AND their `issue` strings are paraphrases of each other (judged by the synthesizing main agent — when uncertain, treat them as distinct, since the failure mode of false-distinct is mild noise while the failure mode of false-merge is dropping a real opinion).
- For matched groups, take the highest consensus count any iteration assigned to the opinion (`count = max(counts)`), the clearest issue description, and the best-described suggested fix.

The output is a deduplicated list of design opinions, each with a `count` (highest tier observed) and the iteration numbers in which it was raised (so the human can see "this was raised in iterations 1 and 3").

### 4. Walk through deferred design opinions interactively

Filter the deduplicated list down to actionable opinions using the consensus-tier rules:

| Consensus | Action |
|-----------|--------|
| Critical (3/3) | Walk through interactively |
| Moderate (2/3) | Walk through interactively |
| Minor (1/3) | Skip (offer to walk through if human wants) |

For each actionable design opinion (highest consensus first), present it one at a time:

```
Design opinion (<N>/3 reviewers, raised in iteration(s) <i1, i2, …>) — <location>

RFC currently says:
  <relevant excerpt, 3-8 lines>

Concern: <issue in 1-2 sentences>
Suggested change: <fix in 1-2 sentences>

Address this? (yes / no / skip all remaining)
```

Wait for a response before presenting the next item. Apply confirmed fixes immediately (via direct edit or a targeted `bytewyrd:rfc-architect` call if the change is non-trivial). On each response, record into a `design_changes_applied` list one entry of the form `{opinion, action: "addressed" | "skipped", fix_applied}` (where `fix_applied` is the verbatim change made for `addressed` entries, or `"skipped"` for `skipped` entries). If the human says "skip all remaining", record every remaining un-presented opinion as `{opinion, action: "skipped", fix_applied: "skipped (skip all remaining)"}` so the ledger is complete, then stop the loop.

After the walk-through completes, if no design opinions were addressed (the `design_changes_applied` list has zero entries with `action: "addressed"`, either because the human skipped them all or because there were none to walk through), **skip Step 5** entirely — there is nothing to validate. Proceed directly to Step 6 and report.

### 5. Final validation pass

If at least one design opinion was addressed in Step 4 (i.e., `design_changes_applied` contains entries with `action: "addressed"`), run one single-shot validation pass:

#### 5a. Spawn 3 fresh reviewers on the post-design-walkthrough RFC

Spawn three `bytewyrd:code-reviewer` agents (`model: "opus"`) in parallel, with the same prompt structure as Step 2c. Build a previously-addressed block from:
- All verified bugs from all convergence-loop iterations (with their `fix_applied`)
- All deferred design opinions (with the action taken: `addressed` with the fix applied, or `skipped`)
- All false-positives from all convergence-loop iterations

#### 5b. Group, classify, and verify

Run Step 2d's grouping, classification, and verification logic on the new findings. The classification taxonomy is unchanged: `bug` (verified wrong), `needs-research`, `design`, `nit`, `false-positive`.

#### 5c. Handle final-pass findings

- If the final pass classifies any group as `bug`, **do not auto-fix in this pass**. Surface the bugs to the human in the final report (Step 6) under a distinct `### Post-design-walkthrough bugs introduced` heading and ask: "These bugs were introduced by the design-opinion incorporations. Re-enter the convergence loop, accept them as-is, or stop?" Wait for the human to choose.
  - **Re-enter the loop:** restart from Step 2 with `iteration_number` reset to `0`. The post-design-walkthrough RFC is the new starting point. Carry the existing ledger over so the previously-addressed block in the re-entered loop's iteration 1 includes everything from the prior loop (verified bugs with their fixes, deferred design opinions with their resolution actions, false-positives with evidence) — reviewers in the re-entered loop should see the full history, not start blind. The hard cap of `max_iterations = 5` applies independently to the re-entered loop (i.e., the cap is per loop entry, not cumulative across re-entries). After re-entry, the loop runs through Step 2 → Step 3 → Step 4 → Step 5 again, with one important constraint: **Step 5 will not re-trigger a third loop entry.** If the second final validation pass also finds bugs, surface them in the final report and stop (the recursion depth is capped at 2 to prevent unbounded re-entry).
  - **Accept as-is:** record the bugs as known-unfixed in the final report (under the `### Post-design-walkthrough bugs introduced` heading with `User decision: accepted as-is`) and proceed to Step 6.
  - **Stop:** abort the skill; report what was done so far and what remains, then exit.
- If the final pass classifies findings as `design` (new design opinions raised on the post-walkthrough RFC), treat them as net-new design opinions and walk through them via Step 4 once more, on these new opinions only — **do not re-trigger Step 5 after this second walk-through.** That would be infinite regress, and the human's design choices on a converged RFC are the boundary. The skill proceeds directly to Step 6 after the second walk-through.
- If the final pass produces zero `bug` findings AND zero new `design` findings, the validation pass passes cleanly and the skill proceeds to Step 6.

### 6. Final report

After the convergence loop, design walk-through, and (if applicable) final validation pass complete, return a structured report to the human:

If `converged_at_iteration` is set (true convergence):

```
### Convergence reached after <converged_at_iteration> iteration(s)

Iteration history:
- Iteration 1: <count> bugs fixed, <count> design opinions deferred, <count> false-positives
- Iteration 2: <count> bugs fixed, <count> design opinions deferred, <count> false-positives
- …
- Iteration <converged_at_iteration>: 0 bugs found (converged)

Design opinions addressed: <count> (of <total_deduped> deduplicated opinions; <skipped> skipped)
Final validation pass: <pass | bugs introduced — see below>
Nits available on request: <count>

RFC is ready. Run /rfc-approve when satisfied.
```

If `converged_at_iteration` is null (hard-cap termination):

```
### Convergence NOT reached after <max_iterations> iteration(s)

The convergence loop hit the iteration cap (<max_iterations>) before reviewers stopped finding verified bugs. The iteration-<max_iterations> auto-fix did run, but those fixes were never independently re-reviewed — the cap fired before a validating pass could be spawned.

Bugs fixed in iteration <max_iterations> (un-validated by a subsequent review pass):
- [Critical 3/3] <location>: <issue>
  Fix applied: <fix_applied>
- …

Per-iteration history (for context — earlier fixes were validated by the next iteration's reviewers):
- Iteration 1: <count> bugs fixed (validated by iteration 2 reviewers), <count> design opinions deferred
- Iteration 2: <count> bugs fixed (validated by iteration 3 reviewers), <count> design opinions deferred
- …
- Iteration <max_iterations>: <count> bugs fixed (NOT validated — cap reached)

Design opinions were NOT walked through (the loop did not converge). The most likely cause is either (a) the auto-fix layer is producing fixes that introduce new bugs each iteration, or (b) the RFC has a structural issue the auto-fix cannot resolve. Read the iteration-<max_iterations> fixes above, decide whether they look correct, then either accept them and re-run /rfc-consensus-review (which validates them as a fresh pass) or revert them and edit the RFC manually.
```

If a final validation pass was run and surfaced post-walkthrough bugs (regardless of convergence-loop status):

```
### Post-design-walkthrough bugs introduced

The final validation pass found the following bugs that appear to have been introduced by the design-opinion incorporations:

- [Critical 3/3] <location>: <issue>
  Suggested fix: <fix>
- …

User decision: <re-entered loop | accepted as-is | stopped>
```

Do **not** change `status`. Do **not** commit automatically.

### 7. Caller protocol

Behavior is the same whether invoked standalone or from `/rfc-new`: run the convergence loop to completion (Step 2), walk through deferred design opinions (Step 4), run final validation if needed (Step 5), then report (Step 6). There is no "return findings to caller" mode — the walk-through and validation always happen here, in the main conversation, so the human never needs to re-invoke the skill to see design opinions.

A caller (typically `/rfc-new`) waits for this skill to return and then proceeds. The caller does not need to detect "bugs were fixed, invoke again" — convergence is already guaranteed by the loop in Step 2.
````

The skill's logical structure changes from 9 steps (single-pass with caller-side hand-rolled looping) to 7 steps (loop is internal; Step 2 is the entire convergence loop; Steps 3–5 are the post-convergence design-and-validation phase; Steps 6–7 are reporting and caller protocol).

#### Step 2 — Promote the rewritten skill to `skills/rfc-consensus-review/SKILL.md`

After Step 1 lands and is validated in the internal copy, promote it to the exported copy at `skills/rfc-consensus-review/SKILL.md`. The exported file gets the **identical** content from Step 1.

Procedure:

```bash
cp .claude/skills/rfc-consensus-review/SKILL.md skills/rfc-consensus-review/SKILL.md
```

Then verify the two files are identical:

```bash
diff .claude/skills/rfc-consensus-review/SKILL.md skills/rfc-consensus-review/SKILL.md
```

Expected output: (empty — no differences)

Per the project's MEMORY.md note "Write/Edit tools bypass sandbox restrictions": if `cp` fails due to sandbox restrictions, fall back to reading the internal copy with the `Read` tool and writing the exported copy with the `Write` tool.

#### Step 3 — Simplify `skills/rfc-new/SKILL.md` Step 8

Replace the entirety of Step 8 in `skills/rfc-new/SKILL.md` (the section currently titled `### 8. Consensus review and fix loop`) with the simplified version below.

Current Step 8 text (verbatim from lines 126–137 of the file as of this RFC's drafting):

```markdown
### 8. Consensus review and fix loop

After `bytewyrd:rfc-architect` completes step 7, invoke the `/rfc-consensus-review` skill on the new RFC.

The consensus review skill runs to completion: it auto-fixes all verified bugs, walks through any design opinions interactively with the human, and reports. Wait for it to finish — including the interactive walk-through — before proceeding to step 9.

**If verified bugs were found and fixed:**

1. Invoke `/rfc-consensus-review` a second time on the updated RFC.
2. If verified bugs still remain after the second pass, do **not** loop further — surface them to the human in step 9.

**If no verified bugs remain:** proceed directly to step 9.
```

Replace with:

```markdown
### 8. Consensus review

After `bytewyrd:rfc-architect` completes step 7, invoke the `/rfc-consensus-review` skill on the new RFC.

The consensus review skill runs to completion: it loops the 3-reviewer pass until reviewers stop finding verified bugs (convergence), walks through any deferred design opinions interactively with the human, and (if any design opinions were addressed) runs one final validation pass. Wait for it to finish — including the interactive walk-through and any validation pass — before proceeding to step 9.

The convergence loop is internal to `/rfc-consensus-review`. Do not invoke the skill more than once from this step; the skill itself guarantees convergence (or surfaces an explicit "convergence not reached after N iterations" report that step 9 forwards to the human verbatim).
```

The replacement removes the hand-rolled "invoke, check, invoke again" logic because `/rfc-consensus-review` now owns the loop. The replacement also drops the "if verified bugs remain after the second pass" branch because convergence is the skill's guarantee (or the explicit non-convergence report is, in the pathological case).

#### Step 4 — Update Step 9 of `skills/rfc-new/SKILL.md` to forward the convergence report

Step 9 of `skills/rfc-new/SKILL.md` currently includes the bullet `Summary of bugs auto-fixed across review passes` and a note about surfacing remaining bugs. Update the bullet list to reflect the convergence report's structure.

Current Step 9 bullet block (verbatim from lines 142–146):

```markdown
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve
```

Replace with:

```markdown
- Path to the RFC file
- The convergence-loop summary as returned by `/rfc-consensus-review` (number of iterations, bugs fixed per iteration, design opinions addressed, validation pass result)
- If `/rfc-consensus-review` reported "convergence NOT reached" (hard-cap termination with persistent bugs), forward the report verbatim — the persistent bugs need human attention before `/rfc-approve`
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve
```

The change tracks the new report structure from the rewritten `/rfc-consensus-review`. The "hard-cap reached" case is forwarded verbatim because it is unambiguous and human-actionable; the user does not need `/rfc-new` to re-summarize it.

#### Step 5 — Update `docs/rfc-process.md` step 5 paragraph

In `docs/rfc-process.md`, the "Writing a new RFC" subsection has a numbered list (currently lines 144–155). Step 5 of that list currently reads:

```markdown
5. `/rfc-consensus-review` runs: five independent reviewers in parallel, findings synthesized by consensus. Critical findings (4–5/5 reviewers) are fixed by `rfc-architect` in a second pass; consensus runs once more to verify. If critical findings remain after two passes, they are surfaced to the human alongside the RFC.
```

Replace with:

```markdown
5. `/rfc-consensus-review` runs: three independent reviewers in parallel, findings synthesized by consensus (Critical = 3/3 unanimous, Moderate = 2/3 quorum, Minor = 1/3 single voice), the bug-fix pass iterates until reviewers produce zero verified bugs (convergence) or until the hard cap of 5 iterations is reached. Design opinions are deferred until after convergence and then walked through with the human one at a time; a final validation pass confirms the design-opinion incorporations did not introduce new bugs. If convergence is not reached within the hard cap, the persistent bugs are surfaced to the human verbatim alongside the RFC.
```

The replacement updates the canonical process description so contributors reading `docs/rfc-process.md` see the convergence-loop behavior with the new 3-reviewer quorum tiers, not the prior two-pass 5-reviewer behavior. No other paragraph in `docs/rfc-process.md` references the consensus skill's reviewer count or pass count.

#### Step 6 — Verification

After all changes, run these checks:

1. **Internal skill exists with the new convergence-loop description:**

   ```bash
   test -f .claude/skills/rfc-consensus-review/SKILL.md && grep -c 'Convergence loop' .claude/skills/rfc-consensus-review/SKILL.md
   ```

   Expected output: `1` (the `## Steps` → `### 2. Convergence loop` heading is present exactly once)

2. **Exported skill is identical to internal skill:**

   ```bash
   diff .claude/skills/rfc-consensus-review/SKILL.md skills/rfc-consensus-review/SKILL.md
   ```

   Expected output: (empty — no differences)

3. **`max_iterations = 5` is set in the skill:**

   ```bash
   grep -F 'max_iterations' skills/rfc-consensus-review/SKILL.md | head -1
   ```

   Expected output: a line containing `` `max_iterations` `` and `` `5` `` in the configuration table

4. **`reviewer_count = 3` is set in the skill:**

   ```bash
   grep -F 'reviewer_count' skills/rfc-consensus-review/SKILL.md | head -1
   ```

   Expected output: a line containing `` `reviewer_count` `` and `` `3` `` in the configuration table

5. **`/rfc-new` step 8 no longer mentions the second-pass branch:**

   ```bash
   grep -c 'second pass' skills/rfc-new/SKILL.md
   ```

   Expected output: `0`

6. **`/rfc-new` step 8 invokes the convergence loop description:**

   ```bash
   grep -c 'convergence' skills/rfc-new/SKILL.md
   ```

   Expected output: at least `3` (the rewritten Step 8 mentions "convergence" in: `(convergence)`, `convergence loop is internal`, `guarantees convergence`, and `"convergence not reached"`; Step 9 forwards the convergence report).

7. **`docs/rfc-process.md` step 5 mentions convergence with the new tier nomenclature:**

   ```bash
   grep -F 'three independent reviewers in parallel' docs/rfc-process.md
   ```

   Expected output:

   ```
   5. `/rfc-consensus-review` runs: three independent reviewers in parallel, findings synthesized by consensus (Critical = 3/3 unanimous, Moderate = 2/3 quorum, Minor = 1/3 single voice), the bug-fix pass iterates until reviewers produce zero verified bugs (convergence) or until the hard cap of 5 iterations is reached. Design opinions are deferred until after convergence and then walked through with the human one at a time; a final validation pass confirms the design-opinion incorporations did not introduce new bugs. If convergence is not reached within the hard cap, the persistent bugs are surfaced to the human verbatim alongside the RFC.
   ```

8. **`docs/rfc-process.md` step 5 no longer mentions the prior "two passes" or "five independent reviewers" language:**

   ```bash
   grep -c 'after two passes' docs/rfc-process.md
   ```

   Expected output: `0`

   ```bash
   grep -c 'five independent reviewers' docs/rfc-process.md
   ```

   Expected output: `0`

9. **Manual smoke test (after `claude plugin update bytewyrd` and Claude Code restart):**

   - Run `/rfc-consensus-review` against an RFC known to have a recent reviewer-found bug (any RFC in `docs/rfcs/` from the last week is a good candidate). Confirm the iteration counter prints (`Iteration 1 of up to 5: spawning 3 reviewers…`).
   - After the auto-fix in iteration 1, confirm the skill spawns iteration 2 automatically — without any caller-side loop or human prompt — and prints the previously-addressed block to the new reviewers (visible via the agent invocation prompt).
   - Confirm convergence reporting on a clean RFC: the loop terminates on iteration 1 (no bugs found), then proceeds directly to the design walk-through (no Step 5 final validation needed if no design opinions were addressed).
   - Confirm the hard-cap path by manually limiting `max_iterations` to 2 temporarily and running against an adversarial test RFC; the report should show the `### Convergence NOT reached` heading.

   If any of these steps fail, the issue is most likely (in order): (a) the loop in Step 2 has an off-by-one error in the iteration counter, (b) the previously-addressed block is not being prepended to the reviewer prompt in Step 2c, (c) the convergence check in Step 2g misclassifies hard-cap termination as true convergence, or (d) the deduplication in Step 3 over-merges distinct design opinions.

## Risks and open questions

- **Risk: the `fix_applied` string extraction from `rfc-architect` is fragile.** Step 2f expects the auto-fix agent to return a structured changelog of `{location, issue, fix_applied}` triples, which the skill parses and stores in the ledger. If `rfc-architect` returns a free-text changelog or omits the `fix_applied` text, the next iteration's previously-addressed prompt will have empty `fix_applied` strings, weakening reviewer signal. **Mitigation:** the spawn instruction to `rfc-architect` (Step 2f) explicitly requires the structured format; if `rfc-architect` returns a free-text changelog, the skill falls back to including the changelog verbatim in the previously-addressed block (lossy but not broken). A future improvement could pin a JSON-formatted return contract on `rfc-architect`; out of scope for this RFC.

- **Risk: design-opinion deduplication is heuristic and can over-merge.** Two distinct design opinions about the same RFC section can phrase their concerns similarly enough that the `(location, issue)` similarity check merges them, dropping one. **Mitigation:** the dedup rule in Step 3 says "when uncertain, treat them as distinct, since the failure mode of false-distinct is mild noise while the failure mode of false-merge is dropping a real opinion." The conservative threshold biases toward small noise over silent loss.

- **Risk: 3 reviewers per iteration may miss bugs a 5-reviewer pass would have caught.** The reviewer-count reduction trades parallel breadth for sequential depth (more iterations). On any single iteration, 40% less parallel coverage means a non-zero chance that a real bug visible only to "the fourth or fifth reviewer's perspective" is missed. **Mitigation:** the convergence loop converts a single-iteration miss into a delayed catch — the next iteration spawns three *fresh* reviewers on the post-fix RFC, and the cumulative coverage across iterations 1-5 plus the final validation pass is substantially higher than 5 reviewers in a single pass. If real-world use shows the 3-reviewer floor is producing measurable misses (bugs surfacing only post-merge), a follow-up RFC can raise `reviewer_count` to 5 — the constant is centralized in one place so the change is a one-line edit. The choice of 3 is the recommendation for v1, not a permanent commitment.

- **Open question: should `max_iterations` be configurable per invocation (e.g., `/rfc-consensus-review docs/rfcs/foo.md --max-iter=10`)?** A user reviewing a very large RFC may want a higher cap. **Resolution within this RFC:** not for v1. The fixed cap of 5 is a conservative starting value; a configurable cap adds argument-parsing surface and a "what does my user expect" question for the skill's default. If real-world use shows 5 is too low, a follow-up RFC can introduce configurability with data to inform the right default. The constant is centralized in the skill's `## Configuration` table so changing it is a one-line edit.

- **Open question: should `reviewer_count` be configurable per invocation?** Similar to `max_iterations`: a user reviewing a particularly sensitive RFC may want 5 reviewers for stronger per-iteration signal. **Resolution within this RFC:** not for v1, same reasoning. Both `reviewer_count` and `max_iterations` are centralized in the `## Configuration` table; if a follow-up RFC introduces configurability for one, it will likely make sense to introduce it for both at the same time.

- **Open question: should the final validation pass (Step 5) also loop until convergence?** Currently it is a single-shot sanity check that, if it finds bugs, asks the human to choose (re-enter the loop, accept, or stop). **Resolution within this RFC:** keep it single-shot. The convergence loop's purpose is to stabilize the RFC against the auto-fix layer's own potential for introduced bugs; once the human has made design choices, those choices are the boundary — the skill's job is to surface any unexpected interactions, not to keep iterating on the human's choices. If the final pass finds bugs, the human re-enters the loop explicitly, which restarts the convergence guarantee from Step 2.

- **Open question: how does the convergence loop interact with the `/rfc-read-feedback` skill?** `/rfc-read-feedback` addresses inline `FEEDBACK:` comments via `rfc-architect`; if a human leaves feedback comments after this skill returns, the feedback addressing is a separate pass that does not re-run the convergence loop automatically. **Resolution within this RFC:** out of scope; `/rfc-read-feedback` is unchanged. If a human leaves feedback and wants convergence guarantees on the feedback-addressed RFC, they re-invoke `/rfc-consensus-review` after `/rfc-read-feedback` completes — exactly the same flow as today, just with a stronger guarantee from the re-invocation.

- **Open question: how do callers other than `/rfc-new` adapt?** Today the only caller is `/rfc-new`. If a future skill wants to invoke `/rfc-consensus-review`, the skill protocol (Step 7) makes it clear that one invocation now returns a fully-converged RFC plus a structured report. A future caller does not need to re-implement the convergence loop. **Resolution within this RFC:** the skill's `## Steps` → Step 7 "Caller protocol" section documents this contract explicitly. New callers read it and conform.

- **Open question: the in-memory ledger does not persist across a context reset (e.g. `/compact` mid-loop).** A user who runs `/rfc-consensus-review`, has their main agent context reset mid-iteration, and then re-invokes the skill loses all iteration state — the second invocation starts from `iteration_number = 0` with no previously-addressed block. **Resolution within this RFC:** the second invocation simply runs the convergence loop again from scratch. Reviewers may re-raise findings the first run already fixed; the skill verifies them in Step 2d (now reading the post-fix RFC), so any already-fixed item classifies as `false-positive` and is recorded. Lossy but self-correcting. Persisting the ledger to disk is out of scope; a follow-up RFC can add it if real-world use shows context-reset mid-loop is common.

- **Risk: the previously-addressed block can grow large across many iterations and consume reviewer-prompt budget.** A 5-iteration run with 5 bugs per iteration would produce a 25-bug previously-addressed block; if each bug's `fix_applied` is verbose, the block can crowd the reviewer's effective context. **Mitigation:** the expected convergence trajectory is a decreasing bug count per iteration (each iteration's auto-fix removes verified bugs and the next pass should find fewer); the cumulative block size is bounded by the convergence trajectory in practice, not by the cap × max-bugs upper bound. If reviewer-prompt budget becomes a measured problem in real use, a follow-up can truncate older `fix_applied` strings or summarize the cumulative block. Out of scope here.

## Relationship to other RFCs

This RFC modifies the canonical RFC pre-review pipeline — every RFC written in the project after this lands flows through the convergence-loop version of `/rfc-consensus-review`. Three adjacencies are worth naming:

- **`/rfc-new` skill (modified by this RFC).** The convergence guarantee moves from a hand-rolled two-pass loop in `/rfc-new` into the skill it invokes. `/rfc-new` becomes thinner; `/rfc-consensus-review` becomes the canonical "review until stable" surface. No behavior is lost from `/rfc-new`'s side — the user-visible outcome (a converged RFC with design opinions resolved) is the same or better.

- **`/rfc-read-feedback` skill (unchanged by this RFC, but adjacent).** When a human leaves inline `FEEDBACK:` comments and runs `/rfc-read-feedback`, the feedback addressing is a separate `rfc-architect` pass that does not invoke this skill's convergence loop. A human who wants convergence after feedback runs `/rfc-consensus-review` explicitly. A future RFC could thread `/rfc-read-feedback` to call this skill automatically after addressing comments; that change is out of scope here, but the contract Step 7 documents in this skill makes it straightforward to add later.

- **`docs/rfc-process.md` step 5 (modified by this RFC).** The canonical process documentation is updated to describe the convergence loop with the new 3-reviewer quorum-based consensus tiers. Contributors reading `docs/rfc-process.md` see the convergence behavior, not the prior two-pass 5-reviewer behavior. The change is one paragraph; the rest of the process document is unaffected.

This RFC does not depend on any other in-flight RFC. Once approved, it can be implemented independently.
