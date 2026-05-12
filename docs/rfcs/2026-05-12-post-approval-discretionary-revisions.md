---
rfc: "2026-05-12-post-approval-discretionary-revisions"
title: "Post-Approval Discretionary Revisions Section in RFC Template"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Add a `## Post-approval discretionary revisions` section to the RFC template emitted by `/rfc-new`, plus a matching subsection in `docs/rfc-process.md`, so implementers have a single, well-defined place to log small clarifications, typo fixes, non-breaking adjustments, and code-review-driven implementation changes (including structural ones) that the implementer and their implementation peers have approved during implementation of an `Approved` RFC — without re-running the full review-and-approval cycle for changes that do not warrant it. The section is a dated, append-only changelog with a rule set that draws its line at *RFC design decisions* rather than at *implementation decisions*: revisions must not alter the design decisions captured in `## Analysis / Options`, must not change the deliverables listed in `## Implementation spec`'s file structure table, and must not change public contracts that the RFC itself specified (frontmatter field names, agent prompts, CLI argument shapes). Code-level decisions about *how* a spec step is implemented — internal class hierarchy, module organization, interface design at code level, refactors and structural improvements that emerge from code review — are explicitly in scope, because the implementer and their peers are the final authority on code quality and architectural decisions during the implementation phase. Anything substantive at the RFC-design level — a changed file path that no longer matches the spec table, a flipped option in `Analysis`, a new option added, a changed public contract specified in the RFC — is out of scope and must go back through `bytewyrd:rfc-architect` and (where appropriate) `/rfc-consensus-review`. The section makes the diff between `Approved` and `Done` auditable in one place: a reviewer can read the original `Approved` RFC plus the discretionary-revisions log and see exactly what was clarified, refactored, or restructured mid-flight.

## Should we do this?

**Yes.** Today the `Approved → Done` interval is the least-documented part of the RFC lifecycle. The RFC template has no section for implementer-side annotations, and `docs/rfc-process.md` is silent on what to do with a mid-implementation clarification. The result is one of three failure modes, all observed in this repository's recent RFC history (e.g., `2026-05-10-iterative-consensus-convergence.md` shipped with implementation-discovered specifics — exact wording of `fix_applied` extraction, ledger field names — that should have been logged as discretionary clarifications but ended up either re-edited into the original sections or scattered across commit messages):

1. **Commit-message bloat.** The implementer captures the clarification in the implementation commit (`feat(rfc-consensus): widen previously-addressed block to also include false-positives — RFC said "verified bugs," but the false-positive list serves the same purpose`). The clarification is correct, but it lives in a commit message a future reviewer must `git log -p docs/rfcs/<file>.md` to find — invisible in the RFC itself.
2. **Lost annotations.** The implementer notices a typo or stale path, fixes it in-place in the existing sections of the `Approved` RFC, and commits the RFC edit with the implementation. The RFC's frontmatter still says `status: Approved` (and later `Done`), but the body silently differs from what the human originally approved. Anyone reading the RFC after the fact has no way to know which sentences were post-approval edits.
3. **Unnecessary re-review.** The implementer pessimistically routes every mid-flight clarification — including a typo, a path correction, a stylistic edit to the spec, and (most importantly) code-review-driven structural changes that emerge naturally during implementation — through `bytewyrd:rfc-architect` and `/rfc-consensus-review` to be safe. This is a five-reviewer Opus spawn (per the convergence-loop policy in RFC 2026-05-10) for a one-line clarification or for an internal refactor that the implementer and their peers already vetted in code review. The cost is real and the benefit is negligible. This failure mode is especially acute for code-review-driven structural changes (internal refactors, class hierarchy adjustments, module splits, interface redesigns at code level): those changes were previously unclear territory — implementers either re-edited the spec in place, scattered the rationale into commit messages, or routed them through `rfc-architect` defensively. This RFC explicitly resolves that ambiguity by putting code-review-driven structural changes in scope for discretionary revisions when the implementer and their peers agree.

Adding a dedicated, dated, append-only section closes all three. Failure mode 1 moves the annotation into the RFC; failure mode 2 makes the post-approval edits explicit and bounded; failure mode 3 gets a clear "this qualifies as discretionary, no re-review needed" rule that explicitly covers code-review-driven structural changes. The cost is one new section in the template, one new subsection in `docs/rfc-process.md`, and a small rule-set definition. The marginal cost on a per-RFC basis is near-zero — the section starts empty and stays empty for RFCs with no mid-flight revisions, and is added to in-place when needed.

The alternative — leaving the gap unfilled — keeps the audit story incoherent for every future RFC, and the cost of incoherent audit history compounds over time as the RFC corpus grows.

## Current state

The RFC template (defined in `skills/rfc-new/SKILL.md` lines 56–100) currently emits these sections in order:

1. `## Summary`
2. `## Should we do this?`
3. `## Current state`
4. `## Analysis / Options`
5. `## Implementation spec` (with `### File structure` and `### Steps`)
6. `## Risks and open questions`
7. `## Relationship to other RFCs`

There is no section that addresses what happens *after* `status: Approved` is set. The lifecycle defined in `docs/rfc-process.md` (lines 50–64) is:

```
Draft → Approved → Done
                 ↘ Dropped
```

`Approved` is set by `/rfc-approve` (the human-invoked skill). `Done` is set by `/rfc-implement` after the implementation PR merges, via Step 5 of `skills/rfc-implement/SKILL.md` (which simply flips `status: "Approved"` to `status: "Done"` and commits with `rfc: mark RFC-NNN done — <title>`). Nothing in either skill, in the RFC template, or in `docs/rfc-process.md` addresses the time between those two state transitions.

`docs/rfc-process.md` does mention one related concept: Step 4 of "Implementing an approved RFC" (line 195) says **"If the spec is ambiguous, update the RFC first (via `rfc-architect` + `/rfc-read-feedback`) rather than having the implementation agent guess."** This rule is correct for genuine ambiguity (a missing step, an undefined type, a contradiction between sections) but is overkill for the typo / typo-adjacent / clarification case. It is also the only existing rule on the `Approved → Done` interval, and it has been silently re-interpreted in practice as "anything I notice during implementation needs an `rfc-architect` round-trip," which is one of the failure modes this RFC closes.

**The `rfc-implement` skill checks for `REVIEW:` and TBD-style markers in its Step 3 (lines 31–35):**

```markdown
### 3. Check for ambiguity

Scan the implementation spec for any remaining `REVIEW:` markers or placeholder language ("TBD", "TODO", etc.). If found:
> "The implementation spec has unresolved items. Run `/rfc-reviews` or update the RFC before implementing."
Stop.
```

A post-approval revision section, if added naively, could trip this check (e.g., an implementer writes "TODO: backfill the test names" inside a discretionary revision entry and the next `/rfc-implement` call refuses to proceed). The design below avoids this by (a) defining the section's content shape as completed-action entries — not work items — and (b) scoping the ambiguity-marker scan to `## Implementation spec` only, which is where it already operates by intent.

**`rfc-approve` does not look at any section other than `status` and the Summary (lines 17–42 of `skills/rfc-approve/SKILL.md`).** The approval gate cares about the design and spec as approved; the post-approval-revisions section is irrelevant to it (it should be empty at the time of approval anyway).

**`rfc-drop` and `rfc-update` are unaffected.** Dropped RFCs do not enter the `Approved → Done` interval. `rfc-update` syncs `docs/rfc-process.md` from the upstream copy in the plugin root; the RFC template content does not flow through `rfc-update` (it lives in `skills/rfc-new/SKILL.md`).

**Other RFCs in this repository have shipped with implementation-discovered specifics** that, in retrospect, would have been clearer as discretionary-revision entries than as in-place edits to the original sections. The pattern is consistent enough that the gap is structural, not a one-off oversight.

## Analysis / Options

There are four coupled decisions: where the section goes, what shape its entries take, what qualifies as "discretionary" vs. requires re-approval, and how the section interacts with the existing `rfc-implement` ambiguity scan.

### Decision 1 — Where does the section live in the template?

**Option A — A new top-level `## Post-approval discretionary revisions` section, appended at the end of the template after `## Relationship to other RFCs` (recommended).**
The section is empty at `Draft` and `Approved` time and stays empty for RFCs with no mid-flight revisions. It is positioned at the end intentionally — readers scanning a fresh RFC encounter design content first; readers auditing a `Done` RFC scroll past design content to the changelog. Including it as a top-level `##` heading matches the precedent of every other section in the template and makes it grep-able (`grep -l 'Post-approval discretionary revisions' docs/rfcs/*.md` lists every RFC that has discretionary entries simply because non-empty sections include their content directly; the empty-template instance has the heading but no entries).

**Option B — A subsection nested under `## Implementation spec` (e.g., `### Discretionary revisions`).**
Conceptually attractive because the revisions are about the spec, but rejected for two structural reasons: (a) entries can also clarify the `## Analysis / Options` text (e.g., "Decision 2 Option C's footnote referenced the old field name `verified_bug_count`; the actual ledger field is `verified_bugs_this_iteration`") or `## Current state` (a stale path that was true at Draft time but changed before approval merged), so nesting under `## Implementation spec` would be misleading. (b) The implementation-spec section is dense and code-heavy; appending a changelog inside it harms readability of the spec proper.

**Option C — A separate file alongside the RFC, e.g., `docs/rfcs/<rfc-id>.revisions.md`.**
Rejected because it doubles the per-RFC file count and breaks the "one RFC = one file" invariant the rest of the tooling relies on (`/rfc-implement`, `/rfc-approve`, `/rfc-drop`, `/rfc-update`, the `rfc:` filename-stem equality rule in the frontmatter, the consensus-review skill's RFC identification step). The current single-file model is well-served; adding a second file per RFC would force changes to every skill that touches an RFC. The benefits of separation (cleaner diff per revision, easier filtering) are real but small, and the cost of breaking the single-file invariant is large.

**Recommendation: Option A.** Top-level `##` section, appended to the end of the template. The heading is always present (even when empty), so an implementer adding the first entry does not have to know whether to create the section — they just add a bullet.

### Decision 2 — What shape do entries take?

**Option A — Dated bullet entries with a short justification, ordered chronologically newest-first (recommended).**
Format: `- **YYYY-MM-DD** — <one-line description of the change>. _Why:_ <one-sentence justification why this qualifies as discretionary and not substantive_._`. Entries reference a specific RFC section by heading or line range when the change is localized. The "Why" clause is mandatory because it forces the implementer to think about the discretionary rule (Decision 3) before committing the entry, and gives auditors a one-line explanation rather than requiring them to reconstruct intent from the diff. Newest-first ordering matches commit-log convention and makes the "most recent change" the first thing a reader sees.

**Option B — Free-form prose paragraphs per revision.**
Rejected — free-form prose invites long-form explanations of fixes that should be one-liners. The structure of a bullet list with a date prefix makes drift toward verbose entries visible immediately ("why is this entry five paragraphs?") and keeps the section scannable. Prose paragraphs also lose the chronological ordering signal because dates float inside prose rather than anchoring the entry.

**Option C — A structured table with columns (`Date`, `Section`, `Change`, `Justification`).**
Rejected — Markdown tables wrap badly for entries with longer change descriptions, and the column structure adds friction without adding information that the bullet format does not already convey via the explicit "Why:" clause and the "section: X" reference convention.

**Recommendation: Option A.** Dated bullet entries with "Why:" clauses, newest-first. The format is regular enough for tooling to grep over (`grep -E '^- \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\* —' docs/rfcs/*.md`) but loose enough that no schema validation is needed.

### Decision 3 — What qualifies as "discretionary"?

This is the load-bearing decision. The rule must draw its line at *RFC design decisions* (what to build, which option to take, which files to create or modify, which public contracts the RFC commits to) versus *implementation decisions* (how to build it, internal code structure, interface design at code level, refactors discovered in code review). The implementer and their implementation peers are the final authority on implementation decisions; RFC reviewers are the final authority on design decisions. The rule below is tight enough that "discretionary" cannot become a euphemism for "redesigned in-flight" at the RFC-design level, and loose enough that genuine implementation-level decisions — including structural ones — can land without a re-approval cycle when the implementer and their peers agree.

**Option A — Defined by an explicit allow-list + an explicit reject-list (recommended).**

**Allowed (discretionary, log and proceed):**
- Typo corrections, grammar fixes, punctuation
- Stale absolute path / URL corrections (the path / URL was correct when the RFC was drafted but moved before implementation began — e.g., a file renamed in an unrelated PR that landed between Draft and Approved)
- Internal cross-reference fixes (a "see Decision 2" reference that should be "see Decision 3" because Decision 1 was dropped between Draft and the review pass)
- Clarification of a step that is operationally equivalent to what was approved but ambiguous on a minor detail (e.g., "Step 5 says 'commit the change' — commit message is `<exact verbatim string>`" when the original step omitted the exact string but the broader commit format is established convention)
- Adding an expected-output line to a verification command where the command itself was specified but the expected output was not (e.g., `grep -c 'X' file.md` was specified, and "Expected output: `2`" is being added)
- Filling in a previously-omitted-but-now-known concrete value where the omission was an oversight, not a design deferral (e.g., a constant was named in one section and a concrete value was named in another; the entry reconciles them by adopting the concrete value). If filling in the omitted value requires new research, design judgment, or changes the meaning of the step — it is a design deferral, not an oversight.
- Renaming a private internal variable, function, or struct field used only inside the spec's code blocks, where the name change is purely cosmetic and the type/contract is unchanged
- Adding examples or expected-output strings that illustrate but do not change behavior
- **Code-review-driven changes to *how* a spec step is implemented, including structural changes** — refactors, class hierarchy adjustments, module splits or merges, interface redesigns at code level, naming changes at code level, added or removed internal abstractions — when the implementer and their implementation peers have agreed on the change in code review. The change must stay within the scope of what the spec step requires (the deliverables, behaviors, and public contracts the RFC specified). It must not add or remove deliverables the spec does not call for, and it must not alter public contracts the RFC itself specified. The rationale: the implementer and their peers are the final authority on code quality and architectural decisions during the implementation phase; RFC reviewers are not the appropriate audience for "should this be one module or two" or "should this be a struct method or a free function" decisions at code level.

**Not allowed (substantive at the RFC-design level, requires re-approval via `rfc-architect` + `/rfc-consensus-review`):**

The distinction below is between *RFC-design-level decisions* (which require re-approval if changed) and *implementation-level decisions* (which are now explicitly in scope for discretionary revisions per the allow-list above). When in doubt, the question to ask is: "did the RFC make this decision, or did the RFC leave this to the implementer?" — if the RFC made it, changing it is substantive; if the RFC left it to the implementer, the implementer and their peers can change it discretionarily.

- Any change to the `## Analysis / Options` recommendations or the rationale for them (these are RFC-level design decisions, not implementation decisions)
- Any change to the file structure table — adding or removing rows, changing the action (`Create` vs `Modify`), changing the path. The file structure table specifies *what files are created or modified*, which is an RFC-design-level decision. **Note:** the internal structure *within* a file (how a SKILL.md is organized internally, what helper functions a Go file has, how a TypeScript module groups its exports) is an implementation-level decision and is covered by the allow-list above.
- Any change to a public-facing contract *as defined in the RFC spec*: frontmatter field names, agent prompts whose wording is load-bearing for downstream agents, CLI argument shapes, function signatures the RFC itself committed to. **Note:** a code-level interface that the RFC did not specify — e.g., an internal Go interface, a TypeScript type added during implementation, a private method signature — is implementation-level and is covered by the allow-list above. The test is whether the RFC's spec text named the contract; if not, the implementer and their peers decide its shape.
- Any change that affects a deliverable in `## Implementation spec` that has not yet been implemented. **Note:** this applies to the *spec's deliverables* — what files are produced, what behaviors they implement, what public contracts they expose — not to the *implementation approach* used to produce them. An unimplemented step's deliverable list (e.g., "modify file X to add behavior Y") is fixed; the code-level approach to producing that deliverable is the implementer's call.
- Any change to the convergence / approval rules embedded in a skill body that the RFC committed to (e.g., a `max_iterations` constant, a tier threshold, a "skip unless human requests" rule). If the RFC named the constant or rule, changing it is substantive.
- Any change to the Risks and open questions section's resolutions where the resolution was used as a rationale in `Analysis / Options`
- Any addition of a new option, drawback, risk, or constraint that did not exist in the `Approved` RFC

When an allow-list item and a reject-list item conflict, the allow-list takes precedence for corrections that are purely filling in an omitted detail or are purely implementation-level — but only if the correction does not change a deliverable or public contract the RFC specified. The rule for the boundary case: "did the RFC decide this? — if yes, re-approval; if no, the implementer and their peers decide."

**Recommendation: Option A.** The explicit allow-and-reject lists are the right shape for a rule that needs to bind future readers (including LLM implementers) without ambiguity. A general principle ("non-breaking changes") would be too weak; LLMs in particular treat "non-breaking" as a permissive label and would log substantive changes under it. The lists are concrete; the underlying principle — *implementation peers are the authority on implementation decisions; RFC reviewers are the authority on design decisions* — gives reviewers and implementers a clear way to evaluate cases the lists do not name explicitly. Ambiguous cases default to the reject list (when in doubt, route through `rfc-architect`).

**Option B — Defined by a general principle ("non-breaking, does not alter core design decisions").**
Rejected — too weak. LLM implementers (the primary audience here, per the plugin's "all RFC-related agent tasks must use `model: opus`" rule in `docs/rfc-process.md`) need the rule to be operationally specific, not aspirational. The expanded scope (code-review-driven structural changes are explicitly in scope when implementer and peers agree) is even harder to convey with a general principle alone — the bounded form of the principle is "implementation peers are the authority on implementation decisions; RFC reviewers are the authority on design decisions," and that boundary is most clearly expressed by Option A's paired allow/reject lists. A general principle would either be too restrictive (collapses the implementation-decision space back into the reject list) or too permissive (lets RFC-design-level changes through under "non-breaking" framing). The lists are the operationally specific form of the principle.

**Option C — Defined by examples only (no rule).**
Rejected — examples alone do not generalize. A new case the implementer faces ("can I rename this struct?", "can I split this module in two during code review?") needs to be answerable from the rule, not by analogy to whatever case happens to be in the examples list.

### Decision 4 — How does the section interact with `/rfc-implement`'s ambiguity scan?

**Option A — Scope the existing ambiguity scan to `## Implementation spec` only; the post-approval-revisions section is exempt (recommended).**
The current `/rfc-implement` Step 3 scans for "REVIEW:" markers and "TBD"/"TODO" placeholder language. After this RFC lands, the scan continues to operate but is narrowed to look only inside the `## Implementation spec` section (and its sub-sections `### File structure` and `### Steps`). Discretionary-revision entries — by Decision 2's shape — are completed-action entries, not work items, so they will not contain "TBD" or "TODO" in normal use, but the scan-scoping protects against a stray instance ending up in a revision entry (e.g., "fixed a TODO comment in the source file that the spec did not flag" — the word "TODO" appears in the description but not as a placeholder in the RFC).

**Option B — Leave the ambiguity scan unscoped; rely on revision-entry authors to avoid placeholder language.**
Rejected — this is exactly the kind of "rely on people to remember" rule that fails the moment someone forgets. Scoping the scan is one-line change to `skills/rfc-implement/SKILL.md` and removes the failure mode entirely.

**Option C — Add the revisions section's heading to a hardcoded exclude-list inside the scan, leaving it otherwise unscoped.**
Rejected — same outcome as Option A but expressed as a denylist rather than a positive scope, which is harder to reason about and harder to extend if other sections later need similar treatment.

**Recommendation: Option A.** Scope the existing scan to `## Implementation spec` only. The scope change is small, the scan's intent is preserved, and the revisions section is structurally protected from tripping the gate it does not target.

## Drawbacks

- **Auditors must now read two parts to understand a `Done` RFC's final state.** Before this change, the `Done` RFC was a single linear document; after, the linear document captures the `Approved` design and the appended revisions section captures the deltas. **Mitigation:** the revisions section is at the end and is explicitly labeled as the changelog. Anyone reading top-to-bottom encounters the original design first; anyone wanting "what shipped" reads the design plus the revisions in order. A future tooling option (out of scope here) could render a "consolidated view" by walking the revisions and applying them, but the read-both-parts model is well-precedented in software engineering practice (CHANGELOG.md alongside README, ADRs alongside the codebase) and is not novel friction.

- **The discretionary/substantive line is a judgment call in edge cases.** Decision 3's allow-and-reject lists cover the common cases explicitly, but the boundary case ("I'm renaming an internal struct field that *is* referenced by the spec's code block, but the rename is purely cosmetic — does that count as a public contract change?", "this refactor splits one module into two — is that adding deliverables the spec did not call for, or is it an implementation-level structural change?") still requires judgment. **Mitigation:** the rule's underlying principle — *implementation peers are the authority on implementation decisions; RFC reviewers are the authority on design decisions* — answers the boundary case. The question to ask is "did the RFC decide this?". If yes, re-approval; if no, the implementer and their peers decide. The "when in doubt, route through `rfc-architect`" fallback remains for genuinely ambiguous cases. The cost of an unnecessary `rfc-architect` round-trip is bounded (one agent call, no consensus review unless the architect deems it substantive), and the cost of a wrongly-logged substantive change is unbounded (it ships unreviewed). The asymmetry justifies the conservative default for genuine ambiguity, but the principle resolves most boundary cases without escalation.

- **An implementer can game the rule by routing substantive changes through the revisions section.** A motivated bad actor (human or agent) can describe a substantive change with discretionary-shaped language and slip it past auditors. This concern applies especially to the expanded scope (code-review-driven structural changes): a bad actor could frame an RFC-design-level change as "code-review-driven structural change" to bypass re-approval. **Mitigation:** the enforcement boundary for the expanded scope is *code review itself* — the rationale for putting code-review-driven structural changes in scope is that the implementer and their implementation peers have already vetted the change in PR review. The revisions log entry is committed alongside the code that motivates it; reviewers of the implementation PR see every revision-section entry alongside the diff. Mismatch between the entry's framing ("structural refactor agreed in code review") and the actual change ("redesigned the file structure table out from under the spec") is visible in PR review, which is where the enforcement happens. The mitigation is process-level (peer review is the enforcer, not tooling), but the same is true of every code-review-based rule in the project (e.g., "tests must accompany behavior changes" is enforced by reviewers, not by tooling). The expanded scope does not weaken the mitigation; it makes the enforcement boundary explicit — code-review-driven changes are in scope precisely because code review is the gate, and the revisions entry is a record of what code review approved.

- **Empty-section noise in newly-created RFCs.** Every `Draft` RFC will carry a `## Post-approval discretionary revisions` heading with no body. For RFCs that never enter the `Approved → Done` interval (i.e., `Dropped` RFCs) the section is dead weight. **Mitigation:** the heading is one line and is at the end of the template; it does not interfere with the design content above it. The "always present, sometimes empty" pattern matches `## Relationship to other RFCs`, which is also often "None." for self-contained RFCs.

- **Tooling assumes the entries are append-only but does not enforce it.** An implementer can in principle edit or delete an entry retroactively. **Mitigation:** the same git history that makes the existing RFC content auditable also makes the revisions log auditable — `git log -p docs/rfcs/<rfc>.md` shows every edit to every section, including this one. Append-only is the convention, not the enforcement; the enforcement is git history.

- **The section adds load on `rfc-architect` and other agents reading RFCs after this lands.** Every agent that reads an `Approved` or `Done` RFC will also read the revisions section, even when it is empty. **Mitigation:** an empty section is ~30 bytes; the marginal context cost is negligible. For RFCs with substantial revisions, the section *is* part of the RFC's truth, so reading it is correct, not overhead.

- **The "Why" clause is short and can degrade into a rubber-stamp pattern.** A lazy implementer can write "_Why:_ typo fix" for every entry, even when the change is more nuanced. **Mitigation:** the entry's diff (visible in the commit and in the PR) is the ground truth; the "Why" clause is documentation of intent, not authorization. A reviewer who sees "_Why:_ typo fix" attached to a 50-line diff will ask the right question. The clause is a forcing function for the author to think about the rule, not an irrevocable certification.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/rfc-new/SKILL.md` | Add the `## Post-approval discretionary revisions` section to the template block in Step 5 (currently lines 56–100 of the file). Updated template includes the new heading at the end with an explanatory comment that gets removed by `rfc-architect` when the RFC is filled in (the heading itself stays). |
| Modify | `docs/rfc-process.md` | Add a new subsection `### Post-approval discretionary revisions` under `## RFC structure` (currently lines 95–113 of the file) that documents the section's purpose, format, allow/reject rules, and interaction with `/rfc-implement`. The subsection sits inside the `<!-- END_UPSTREAM_CONTENT -->` marker (i.e., it is part of the upstream content, not a project extension) so future `/rfc-update` invocations propagate the change to consumer projects. |
| Modify | `skills/rfc-implement/SKILL.md` | Narrow the ambiguity scan in Step 3 (currently lines 31–35 of the file) so it operates on the `## Implementation spec` section only, not the full RFC. This prevents the new revisions section from accidentally tripping the gate. |

No new files are created. No agents are modified. No `.claude-plugin/plugin.json` changes — the new section is template content, not a new skill or agent.

### Steps

#### Step 1 — Add the section to the RFC template in `skills/rfc-new/SKILL.md`

Open `skills/rfc-new/SKILL.md` and locate Step 5 ("Write the template file"), specifically the Markdown template block beginning at line 56 and ending at line 100. The template currently ends with this block (lines 95–100):

```markdown
## Risks and open questions
<!-- What could go wrong. Unresolved decisions that need answers before or during implementation. -->

## Relationship to other RFCs
<!-- Dependencies, conflicts, or "None." -->
```

Replace those six lines with these fourteen lines (i.e., append the new section after `## Relationship to other RFCs`):

```markdown
## Risks and open questions
<!-- What could go wrong. Unresolved decisions that need answers before or during implementation. -->

## Relationship to other RFCs
<!-- Dependencies, conflicts, or "None." -->

## Post-approval discretionary revisions
<!-- DO NOT REMOVE this heading. Leave empty (no entries) until after the RFC is Approved.
     Implementers append dated entries here for typos, stale paths, clarifications, non-breaking
     adjustments, AND code-review-driven structural changes (refactors, internal interface
     redesigns, module reorganizations, etc.) that the implementer and their peers have agreed
     on during code review. Format per entry:

       - **YYYY-MM-DD** — <one-line description of the change>. _Why:_ <one-sentence justification why this qualifies as discretionary (typo / stale path / clarification / code-review-driven structural change / etc.)>.

     Order newest-first. Substantive changes at the RFC-design level (anything that alters the
     file structure table, public contracts specified in the RFC, Analysis recommendations,
     unimplemented spec deliverables, or risk resolutions used as Analysis rationale) must NOT
     go here — route them through bytewyrd:rfc-architect and /rfc-consensus-review for
     re-approval. The principle: implementation peers are the authority on implementation
     decisions; RFC reviewers are the authority on design decisions.
     See docs/rfc-process.md § "Post-approval discretionary revisions" for the full rule set. -->
```

Note: the existing convention in `skills/rfc-new/SKILL.md` is that `bytewyrd:rfc-architect` removes `<!-- ... -->` guidance comments when it fills in the template (per Step 7's instruction: "remove all `<!-- ... -->` guidance comments"). The comment inside `## Post-approval discretionary revisions` is special — it must **not** be removed when the RFC is filled in at `Draft` time, because the comment is also instructions for the implementer who reaches the post-`Approved` phase. Update Step 7 of `skills/rfc-new/SKILL.md` to reflect this exception.

Step 7 of `skills/rfc-new/SKILL.md` currently reads (lines 113–125):

```markdown
### 7. Spawn bytewyrd:rfc-architect to fill in the RFC

Spawn a `bytewyrd:rfc-architect` agent (`model: "opus"`) with:
- The user's description
- The path to the created RFC file
- The full project context (relevant code, existing RFCs, docs)
- Instruction: fill in the template completely, remove all `<!-- ... -->` guidance comments, follow the RFC process in `docs/rfc-process.md`, especially the no-placeholders rule and file structure mapping requirement

The `bytewyrd:rfc-architect` agent must **immediately** after writing dispatch the appropriate review agents in parallel (per the review agent selection table in `docs/rfc-process.md`), incorporate their feedback, then run the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present?
3. **Consistency** — type names, signatures, paths match across sections?
```

Replace with:

```markdown
### 7. Spawn bytewyrd:rfc-architect to fill in the RFC

Spawn a `bytewyrd:rfc-architect` agent (`model: "opus"`) with:
- The user's description
- The path to the created RFC file
- The full project context (relevant code, existing RFCs, docs)
- Instruction: fill in the template completely, remove all `<!-- ... -->` guidance comments **except** the comment block inside the `## Post-approval discretionary revisions` section (which is implementer-facing instructions, not Draft-time guidance, and must be preserved verbatim — including the section heading itself, which stays empty of entries at Draft time), follow the RFC process in `docs/rfc-process.md`, especially the no-placeholders rule and file structure mapping requirement

The `bytewyrd:rfc-architect` agent must **immediately** after writing dispatch the appropriate review agents in parallel (per the review agent selection table in `docs/rfc-process.md`), incorporate their feedback, then run the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present? (Scan the `## Implementation spec` section only; the `## Post-approval discretionary revisions` section is exempt because it is empty at Draft time and its guidance comment is intentional.)
3. **Consistency** — type names, signatures, paths match across sections?
```

The two changes — exempting the new section's comment from removal, and scoping the placeholder scan to `## Implementation spec` — match the parallel scoping change in Step 3 of `skills/rfc-implement/SKILL.md` (see Step 3 below).

#### Step 2 — Add the subsection to `docs/rfc-process.md`

Open `docs/rfc-process.md` and locate the `## RFC structure` section (line 95). The section currently lists numbered items 1–8 (line 99–106), then describes scaling and security considerations (lines 108–112), then has a `### Implementation spec requirements` subsection (line 114).

Insert a new subsection **after** the existing `### Implementation spec requirements` subsection (which ends at line 132 with the "When the spec includes commands…" paragraph) and **before** the `---` horizontal rule that begins `## Agent rules` (line 134). The new content goes before the `---` on line 134.

Read the file before editing to confirm the exact line numbers (they may have shifted since this RFC was written; the structural anchors — `### Implementation spec requirements` heading and the `---` before `## Agent rules` — are stable).

Insert the following text (after the line "When the spec includes commands, include the exact command string and the expected output." and before the next `---`):

~~~markdown

### Post-approval discretionary revisions

Every RFC has a `## Post-approval discretionary revisions` section appended after `## Relationship to other RFCs`. The section is empty at `Draft` and `Approved` time. Implementers add entries during the `Approved → Done` interval to log small clarifications, typo fixes, non-breaking adjustments, and code-review-driven implementation changes (including structural ones) that emerge during implementation, without requiring a full re-approval cycle.

**Underlying principle.** The rule draws its line at *RFC design decisions* versus *implementation decisions*. The implementer and their implementation peers are the final authority on implementation decisions — how a spec step is built, how the code is structured internally, what internal interfaces and abstractions are used, what refactors emerge from code review. RFC reviewers are the final authority on design decisions — what to build, which option to take, which files to create or modify, which public contracts the RFC commits to. Discretionary revisions are for implementation-level changes; substantive re-approval is for design-level changes.

**Format.** Each entry is a dated bullet, ordered newest-first:

```markdown
- **YYYY-MM-DD** — <one-line description of the change>. _Why:_ <one-sentence justification>.
```

The "Why:" clause is mandatory — it forces the author to think about whether the change qualifies as discretionary before logging it, and gives auditors a one-line explanation without requiring them to reconstruct intent from the diff.

**What qualifies as discretionary (log here, no re-approval needed):**

- Typo corrections, grammar fixes, punctuation
- Stale absolute path / URL corrections (path or URL was correct at Draft time but moved before implementation began)
- Internal cross-reference fixes (e.g. a "see Decision 2" reference that should be "see Decision 3" after Decision 1 was dropped)
- Clarification of a step that is operationally equivalent to what was approved but ambiguous on a minor detail
- Adding an expected-output line to a verification command where the command itself was specified but the expected output was not
- Filling in a previously-omitted-but-now-known concrete value where the omission was an oversight, not a design deferral
- Renaming a private internal variable, function, or struct field that appears only inside the spec's code blocks, where the name change is purely cosmetic and the type/contract is unchanged
- Adding examples or expected-output strings that illustrate but do not change behavior
- **Code-review-driven changes to *how* a spec step is implemented, including structural changes** — refactors, class hierarchy adjustments, module splits or merges, interface redesigns at code level, naming changes at code level, added or removed internal abstractions — when the implementer and their implementation peers have agreed on the change in code review. The change must stay within the scope of what the spec step requires (the deliverables, behaviors, and public contracts the RFC specified). It must not add or remove deliverables the spec does not call for, and it must not alter public contracts the RFC itself specified.

**What is NOT discretionary (RFC-design-level changes; require re-approval via `bytewyrd:rfc-architect` and `/rfc-consensus-review`):**

The distinction below is between *RFC-design-level decisions* (which require re-approval if changed) and *implementation-level decisions* (which are covered by the allow-list above). The test: "did the RFC make this decision, or did the RFC leave this to the implementer?" If the RFC made it, changing it is substantive; if the RFC left it to the implementer, the implementer and their peers decide.

- Any change to the `## Analysis / Options` recommendations or their rationale (these are RFC-level design decisions, not implementation decisions)
- Any change to the file structure table in `## Implementation spec` — adding or removing rows, changing the action (`Create` vs `Modify`), changing the path. The table specifies *what files are created or modified*, which is an RFC-design-level decision. **Note:** the internal structure *within* a file (how a SKILL.md is organized internally, what helper functions a Go file has, how a TypeScript module groups its exports) is implementation-level and is covered by the allow-list.
- Any change to a public-facing contract *as defined in the RFC spec*: frontmatter field names, agent prompts whose wording is load-bearing for downstream agents, CLI argument shapes, function signatures the RFC itself committed to. **Note:** a code-level interface that the RFC did not specify — an internal Go interface, a TypeScript type added during implementation, a private method signature — is implementation-level and is covered by the allow-list.
- Any change that affects a deliverable in `## Implementation spec` that has not yet been implemented (the spec's deliverable list — what files are produced, what behaviors they implement, what public contracts they expose — is fixed). **Note:** this applies to the *spec's deliverables*, not to the *implementation approach* used to produce them. The code-level approach inside the deliverable is the implementer's call.
- Any change to convergence, approval, or threshold rules embedded in skill bodies that the RFC committed to (e.g. a `max_iterations` constant, a tier threshold, a "skip unless human requests" rule). If the RFC named the constant or rule, changing it is substantive.
- Any change to a `## Risks and open questions` resolution where the resolution was used as a rationale in `## Analysis / Options`
- Any addition of a new option, drawback, risk, or constraint that did not exist in the `Approved` RFC

**When in doubt: route through `bytewyrd:rfc-architect`.** The cost of an unnecessary `rfc-architect` round-trip is small; the cost of a wrongly-logged substantive change is unbounded. The asymmetry justifies the conservative default for genuine ambiguity. For most boundary cases the underlying principle ("did the RFC decide this?") resolves the question without escalation.

**Enforcement is peer review.** The rule is enforced by the same code-review process that gates every other change in the project. Revision-log entries are committed alongside the code that motivates them; reviewers of the implementation PR see each revision entry alongside the diff. Mismatch between an entry's framing and the actual change is visible in PR review. There is no tooling enforcement — peer review is the gate, and the revisions log is the record of what peer review approved.

**Append-only by convention.** The section is append-only — entries are added at the top (newest-first), never edited or deleted retroactively. Enforcement is via git history (every edit to the file is auditable via `git log -p`), not via tooling.

**Interaction with `/rfc-implement`.** The ambiguity scan in `/rfc-implement` Step 3 (which checks for `REVIEW:`, TBD, TODO placeholders) is scoped to the `## Implementation spec` section only. The `## Post-approval discretionary revisions` section is exempt — entries here describe completed actions, not pending work, and any placeholder-shaped strings in entry descriptions are intentional content, not unresolved RFC text.

~~~

The tilde-fenced block above (the `### Post-approval discretionary revisions` subsection) is the literal text to insert into `docs/rfc-process.md`. The outer `~~~` fences are used here solely to avoid a fence-nesting collision with the inner ` ```markdown ` fence that is part of the inserted content. The implementer copies everything between the `~~~` lines verbatim.

#### Step 3 — Scope the ambiguity scan in `skills/rfc-implement/SKILL.md`

Open `skills/rfc-implement/SKILL.md` and locate Step 3 (lines 31–35 of the current file):

```markdown
### 3. Check for ambiguity

Scan the implementation spec for any remaining `REVIEW:` markers or placeholder language ("TBD", "TODO", etc.). If found:
> "The implementation spec has unresolved items. Run `/rfc-reviews` or update the RFC before implementing."
Stop.
```

Replace with:

```markdown
### 3. Check for ambiguity

Scan the `## Implementation spec` section (from the `## Implementation spec` heading through the next `##`-level heading) of the RFC for any remaining `REVIEW:` markers or placeholder language ("TBD", "TODO", etc.). The scan is scoped to that section only — the `## Post-approval discretionary revisions` section, which appears at the end of every RFC, is exempt because its entries describe completed actions (not pending work) and may contain placeholder-shaped strings as intentional content. If unresolved items are found within `## Implementation spec`:

> "The implementation spec has unresolved items. Run `/rfc-read-feedback` or update the RFC before implementing."

Stop.
```

The change adds a sentence explaining the scope and adds a blank line before the blockquote (a minor formatting fix that aligns with surrounding step formatting in the same file). The behavior change is: the scan now examines text only between the `## Implementation spec` heading and the next `## ` heading (which by template ordering is `## Risks and open questions`).

#### Step 4 — Apply the new template to an existing in-flight RFC (smoke test)

After Steps 1–3 land, run a smoke test on the next RFC that enters the `Approved → Done` interval. Pick any `Draft` RFC currently in `docs/rfcs/` that does not yet have the new section, manually append the new section per the template (just the heading and its guidance comment — no entries yet), and verify:

```bash
grep -c '## Post-approval discretionary revisions' docs/rfcs/<chosen-rfc>.md
```

Expected output: `1`

```bash
grep -A 1 '## Post-approval discretionary revisions' docs/rfcs/<chosen-rfc>.md | head -3
```

Expected output:

```
## Post-approval discretionary revisions
<!-- DO NOT REMOVE this heading. Leave empty (no entries) until after the RFC is Approved.
```

(or whatever the first two lines of the inserted template comment are).

This smoke test is one-shot — once verified, the in-flight RFCs do not need backfilling. They keep their current structure and will simply not have the new section; their `Approved → Done` interval predates the rule. Future RFCs created via `/rfc-new` get the section automatically.

#### Step 5 — Verification

After all changes land, run these checks. Each command is run from the project root.

1. **The new section is present in the `/rfc-new` template:**

   ```bash
   grep -c '## Post-approval discretionary revisions' skills/rfc-new/SKILL.md
   ```

   Expected output: `1`

2. **The guidance comment is present in the template:**

   ```bash
   grep -c 'DO NOT REMOVE this heading' skills/rfc-new/SKILL.md
   ```

   Expected output: `1`

3. **Step 7 of `skills/rfc-new/SKILL.md` exempts the new section's comment from removal:**

   ```bash
   grep -F 'except the comment block inside the `## Post-approval discretionary revisions` section' skills/rfc-new/SKILL.md
   ```

   Expected output: a line containing the literal phrase. (Exit code 0.)

4. **The subsection is present in `docs/rfc-process.md` and falls before the `---` that precedes `## Agent rules`:**

   ```bash
   grep -n '### Post-approval discretionary revisions' docs/rfc-process.md
   ```

   Expected output: a line of the form `<N>:### Post-approval discretionary revisions` where `<N>` is the line number in the project's file (will be in the 130–160 range depending on prior edits to the file; not asserted exactly).

   And:

   ```bash
   awk '/### Post-approval discretionary revisions/{found=1} /^## Agent rules/{if(found) print "OK"; exit}' docs/rfc-process.md
   ```

   Expected output: `OK` (the subsection appears before `## Agent rules`).

5. **`/rfc-implement` Step 3 mentions the scoping rule:**

   ```bash
   grep -F 'scoped to that section only' skills/rfc-implement/SKILL.md
   ```

   Expected output: a line containing the literal phrase.

6. **The discretionary/substantive rule lists are both present in `docs/rfc-process.md`:**

   ```bash
   grep -c 'What qualifies as discretionary' docs/rfc-process.md
   ```

   Expected output: `1`

   ```bash
   grep -c 'What is NOT discretionary' docs/rfc-process.md
   ```

   Expected output: `1`

7. **The expanded scope (code-review-driven structural changes) is named in both `docs/rfc-process.md` and the template comment in `skills/rfc-new/SKILL.md`:**

   ```bash
   grep -F 'Code-review-driven changes' docs/rfc-process.md
   ```

   Expected output: a line containing the literal phrase. (Exit code 0.)

   ```bash
   grep -F 'code-review-driven structural changes' skills/rfc-new/SKILL.md
   ```

   Expected output: a line containing the literal phrase. (Exit code 0.)

8. **Manual smoke test of the rule's wording.** Read `docs/rfc-process.md` § "Post-approval discretionary revisions" top-to-bottom. The reader (human or LLM) should be able to answer the following questions from the subsection alone, without external context:

   - "I noticed the spec says to commit with message X but it should be message Y — is that discretionary?" — Answer: Yes (typo correction / clarification of a specified-but-ambiguous detail). Verify the subsection's allow-list makes this answer reachable.
   - "I want to rename a struct from `FooConfig` to `BarConfig` in the spec's code blocks — is that discretionary?" — Answer: Discretionary if the struct is private to the spec's code and the type/contract is unchanged; substantive if the struct is a public contract the RFC itself specified. Verify the subsection makes both branches reachable.
   - "In code review my peer suggested splitting `helpers.go` into `validation.go` and `parsing.go` — neither file is named in the file structure table; both are internal helpers of the single deliverable named in the table. Is that discretionary?" — Answer: Yes, discretionary (code-review-driven structural change; the spec's deliverable is the single behavior the helpers implement; how the helpers are organized internally is an implementation decision). Verify the subsection's allow-list makes this answer reachable via the "code-review-driven changes to *how* a spec step is implemented" item.
   - "I want to add a new column to the file structure table — is that discretionary?" — Answer: No, substantive (any change to the file structure table is in the reject list — it specifies what files are created or modified, an RFC-design-level decision). Verify the reject-list explicitly names file structure table changes.
   - "I want to bump `max_iterations` from 5 to 10 because real-world use showed 5 was too low — is that discretionary?" — Answer: No, substantive (changes to convergence / threshold rules the RFC committed to are in the reject list). Verify the reject-list explicitly names threshold rule changes.

   If any answer is not reachable from the subsection text, the rule wording is incomplete — revise before merging.

9. **Manual smoke test of the in-flight RFC compatibility.** Pick one RFC from `docs/rfcs/` that is currently in `Approved` status (use `grep -l 'status: "Approved"' docs/rfcs/*.md`). Confirm it does **not** currently have the `## Post-approval discretionary revisions` section (the new rule applies forward; backfilling is not part of this RFC). Run `/rfc-implement <that RFC>` and confirm Step 3 of `/rfc-implement` does not falsely flag the RFC as having unresolved items.

   Expected output: `/rfc-implement` proceeds past Step 3 to Step 4 (spawning `feature-engineer`). If it stops at Step 3, the scoping change in Step 3 of this RFC's spec is broken; investigate.

If any verification step fails, the issue is most likely (in order): (a) Step 1's edit to `skills/rfc-new/SKILL.md` missed the trailing line of the prior template block when extending it, (b) Step 2's insertion point in `docs/rfc-process.md` was wrong (e.g., inserted after `## Agent rules` instead of before), (c) Step 3's scope phrase was not matched exactly by Step 5's verification check.

## Risks and open questions

- **Risk: Decision 3's allow/reject lists drift out of date as the RFC corpus evolves.** New kinds of mid-flight changes will appear over time; the explicit lists will not anticipate them. **Mitigation:** the lists are illustrative-but-explicit, not exhaustive, and the underlying principle ("implementation peers are the authority on implementation decisions; RFC reviewers are the authority on design decisions") generalizes to unanticipated cases. The "when in doubt, route through `rfc-architect`" rule is the always-correct fallback for genuine ambiguity. If a category of legitimate discretionary changes appears repeatedly and is being unnecessarily routed through `rfc-architect`, a follow-up RFC extends the allow-list; the cost of that follow-up is small (one section update) and the data informing it is concrete (the bouncing of similar changes through `rfc-architect`).

- **Risk: agents and humans implementing `Approved` RFCs may not read `docs/rfc-process.md` before logging a revision.** The rule could be ignored simply by not knowing it exists. **Mitigation:** the guidance comment inside the `## Post-approval discretionary revisions` section itself (added in Step 1) names the rule's location: "See `docs/rfc-process.md` § 'Post-approval discretionary revisions' for the full rule set." An implementer who is about to add the first entry to the section will read the comment immediately above the insertion point; they cannot miss it without ignoring inline documentation directly attached to the action they are about to take. The comment also names the underlying principle inline ("implementation peers are the authority on implementation decisions; RFC reviewers are the authority on design decisions") so the most common case can be evaluated without leaving the file.

- **Risk: the `_Why:_` clause is short and vulnerable to copy-paste laziness.** As noted in Drawbacks, an implementer can write "_Why:_ typo fix" mechanically. **Mitigation:** PR review surfaces the diff alongside the revision entry; mismatches are obvious. Long-term, if the laziness pattern becomes systemic, a lightweight linting step (out of scope here) could compare the diff size to the "Why" clause's complexity and flag obvious mismatches.

- **Risk: the expanded scope (code-review-driven structural changes) is misused to redesign RFCs from inside implementation.** A bad-faith implementer could frame an RFC-design-level change as "code-review-driven structural change" and slip it through. **Mitigation:** the enforcement boundary is explicit — code-review-driven changes are in scope precisely because code review is the gate. The revisions log entry is committed alongside the code that motivates it, and the reviewers of the implementation PR are the same audience that approved the code change. A claim of "agreed in code review" is verifiable from the PR itself. The principle ("did the RFC decide this?") is the test reviewers apply when evaluating the framing; if the change touches a decision the RFC made, the entry is mis-classified and re-approval is required. The mitigation is process-level, not tooling-level, but the same is true of every code-review-based rule in the project.

- **Open question: should the section be present in `Dropped` RFCs?** `Dropped` RFCs do not enter the `Approved → Done` interval, so the section is never populated for them. **Resolution within this RFC:** the section is still added to the template (because `/rfc-new` produces every RFC from one template, and forking the template based on a hypothetical future drop state is more complexity than the empty heading is worth). The empty heading in a Dropped RFC is harmless — one line at the end of the file.

- **Open question: should `rfc-implement` automatically add an entry when it marks the RFC `Done`?** A natural extension would be for Step 5 of `/rfc-implement` (the "Mark Done after merge" step) to append a final dated entry along the lines of "_Implementation complete; merged in commit `<sha>`._" **Resolution within this RFC:** out of scope. The `## Post-approval discretionary revisions` section is for *deltas from the approved design*, not for lifecycle bookkeeping. Adding a generic "implementation complete" entry would dilute the section's purpose by mixing it with content that belongs in commit messages and git history. A future RFC can revisit this if the use case proves valuable.

- **Open question: should a maximum number of entries trigger a forced re-approval?** A pathological RFC could accumulate dozens of discretionary entries while never triggering re-review — at which point the cumulative changes might collectively constitute a redesign. **Resolution within this RFC:** the rule is per-entry, not cumulative. Decision 3's allow/reject lists evaluate each entry on its own merits; a redesign expressed as fifty individually-discretionary entries is still fifty individually-discretionary entries, and each one passed the rule at the time it was logged. If the pattern surfaces in practice, a follow-up RFC can introduce a cumulative threshold; for v1, the simplicity of per-entry evaluation outweighs the theoretical concern.

- **Open question: how does the section interact with `/rfc-read-feedback`?** `/rfc-read-feedback` addresses inline `FEEDBACK:` markers in an RFC and is used today for both Draft-state and (in principle) post-Approved feedback. **Resolution within this RFC:** `/rfc-read-feedback` is unchanged. If a human leaves a `FEEDBACK:` comment on an `Approved` RFC and the comment requests a discretionary change, `bytewyrd:rfc-architect` (the agent that `/rfc-read-feedback` dispatches) should apply the change and append a revision-section entry recording it. The rule wording does not need to call this out separately — an `rfc-architect` reading `docs/rfc-process.md` understands that a discretionary change made via `/rfc-read-feedback` still goes through the revision log. If the requested change is substantive, `rfc-architect` should escalate per the existing pattern (update the RFC and re-route through `/rfc-consensus-review`).

- **Open question: do projects that consume this plugin via `/sync` automatically inherit the section?** The plugin's `/rfc-update` skill syncs `docs/rfc-process.md` from the upstream copy. Because the new subsection in Step 2 is inserted *inside* the `<!-- END_UPSTREAM_CONTENT -->` marker (i.e., it is part of the upstream content, not a project extension), it propagates automatically on the next `/rfc-update` invocation. **Resolution:** confirmed — no additional steps needed for downstream projects beyond the standard sync cadence.

## Relationship to other RFCs

This RFC modifies the RFC template and the canonical process documentation — every RFC created in the project after this lands carries the new `## Post-approval discretionary revisions` section. The change is forward-only (existing RFCs are not backfilled per Decision 4's smoke test) and is scoped tightly enough to not interact with the design content of any other RFC. Three adjacencies are worth naming:

- **`/rfc-new` skill (modified by this RFC).** The template emitted by Step 5 of `skills/rfc-new/SKILL.md` gains a new section heading. Step 7's instruction to `rfc-architect` is updated to preserve the new section's guidance comment when filling in the template. No behavioral change to the rest of the skill.

- **`/rfc-implement` skill (modified by this RFC).** Step 3's ambiguity scan is scoped to `## Implementation spec` only, so the new section's content (now or in the future) does not trip the gate. No other step changes; the agent dispatch in Step 4 and the `Done`-marking in Step 5 are untouched.

- **`docs/rfc-process.md` (modified by this RFC).** A new `### Post-approval discretionary revisions` subsection is added under `## RFC structure`. The subsection sits inside the upstream-content region (before `<!-- END_UPSTREAM_CONTENT -->`) so it propagates to consumer projects via the normal `/rfc-update` / `/sync` flow. No other section of `docs/rfc-process.md` is modified.

This RFC does not depend on any other in-flight RFC. It can be implemented independently. It does interact conceptually with RFC `2026-05-10-iterative-consensus-convergence.md` (which defines the `/rfc-consensus-review` convergence loop that this RFC's reject-list cites as the re-approval mechanism for substantive changes) — but the dependency is one-way and content-level only: this RFC references `/rfc-consensus-review` as it exists today, not as it might be modified by a future RFC. If `/rfc-consensus-review` changes shape later, this RFC's reject-list wording stays accurate as long as the skill remains the canonical "review until stable" surface, which is its design intent per the convergence RFC.

## Post-approval discretionary revisions

<!-- DO NOT REMOVE this heading. Leave empty (no entries) until after the RFC is Approved.
     Implementers append dated entries here for typos, stale paths, clarifications, non-breaking
     adjustments, AND code-review-driven structural changes (refactors, internal interface
     redesigns, module reorganizations, etc.) that the implementer and their peers have agreed
     on during code review. Format per entry:

       - **YYYY-MM-DD** — <one-line description of the change>. _Why:_ <one-sentence justification why this qualifies as discretionary (typo / stale path / clarification / code-review-driven structural change / etc.)>.

     Order newest-first. Substantive changes at the RFC-design level (anything that alters the
     file structure table, public contracts specified in the RFC, Analysis recommendations,
     unimplemented spec deliverables, or risk resolutions used as Analysis rationale) must NOT
     go here — route them through bytewyrd:rfc-architect and /rfc-consensus-review for
     re-approval. The principle: implementation peers are the authority on implementation
     decisions; RFC reviewers are the authority on design decisions.
     See docs/rfc-process.md § "Post-approval discretionary revisions" for the full rule set. -->
