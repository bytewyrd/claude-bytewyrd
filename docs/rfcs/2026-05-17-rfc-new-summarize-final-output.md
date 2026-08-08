---
rfc: "2026-05-17-rfc-new-summarize-final-output"
title: "Summarize RFC in /rfc-new final output"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

When `/rfc-new` finishes today, Step 9 tells the human the RFC file path and lists any auto-fixed bugs — but says nothing about what the RFC proposes. The reviewer must open the file to learn even the rough direction. This RFC extends Step 9 to include a short inline summary derived from the RFC the architect just wrote: problem, proposed change, key constraints, and notable design decisions (a few sentences or short bulleted sections). The path and bug changelog are preserved beneath the summary unchanged.

## Should we do this?

**Yes.** The final-output step is the handoff from the automated pipeline to the human reviewer. Today that handoff omits the most important information: what the RFC is about. A reviewer who cannot sanity-check the direction inline may approve a mistaken RFC without reading it, or must open the file before they can decide whether the direction even warrants reading. The summary closes that gap with minimal cost — the architect already has the RFC content in memory; no re-analysis is needed, and the change is a one-sentence instruction addition to a single skill step.

## Current state

Step 9 of `skills/rfc-new/SKILL.md` (verified: `skills/rfc-new/SKILL.md:L140`) currently reads:

```
### 9. Present to human

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
```

The five bullets are entirely procedural: where the file is, what was auto-fixed, and what to run next. Nothing tells the reviewer what the RFC proposes. The `## Summary` section of the RFC itself contains this information (verified: every RFC template and every existing RFC includes this section), but the human must open the file to read it.

The `rfc-consensus-review` skill already emits a final report that names the number of bugs fixed and design opinions addressed (verified: `skills/rfc-consensus-review/SKILL.md:L139-L151`). That report is about the review process, not the RFC content — it does not substitute for a content summary.

## Analysis / Options

### Option A — Derive summary from the RFC's `## Summary` section (recommended)

Instruct the architect in Step 9 to quote or paraphrase the RFC's `## Summary` section verbatim, followed by a short bulleted section listing key constraints and notable design decisions drawn from the rest of the RFC. This is derivation, not re-analysis: the architect already holds the complete RFC text. The output is bounded — "a few sentences or short bulleted sections" — so it does not become a second full RFC synopsis.

**Why this is the right scope:** The `## Summary` section is required by the RFC template and is always ≤5 sentences describing what is being proposed and why. Surfacing it inline costs one read of a section the architect has already written. The additional "key constraints and notable design decisions" bullet is the value-add: it gives the reviewer a signal on what is non-obvious or contentious, which is exactly what they need to decide whether to push back before reading the whole file.

**What "key constraints and notable design decisions" means:** constraints are things that ruled out alternatives (e.g., "must not break existing /rfc-approve callers", "no new file created"); notable design decisions are choices that could have gone differently and that a reviewer might want to question (e.g., "derives from RFC content already in memory, not a re-run", "summary is prose-first, not a structured key/value block"). Limit to 2-4 bullets; if none are notable, omit the bullet section.

### Option B — Regenerate a fresh summary with a separate agent call

Spawn a lightweight agent after the consensus review to read the RFC and produce a summary. This would allow a summary style independent of the architect's `## Summary` prose.

Rejected: a separate agent call adds latency and cost for information the architect already has. The RFC `## Summary` section is the canonical synopsis — a separate agent re-generating it is redundant at best and divergent at worst. If the `## Summary` is poor, the fix is to improve the architect's drafting, not to add a second agent that contradicts it.

### Option C — Display the full RFC content inline

Print the entire RFC file contents in the Step 9 output so the reviewer can read it without opening the file.

Rejected: a full RFC is typically hundreds of lines. Pasting it inline makes the Step 9 output unwieldy, buries the actionable instructions (path, changelog, next steps), and defeats the purpose of having a file. The goal is a quick sanity-check signal, not a replacement for reading the RFC.

## Drawbacks

1. **Summary quality depends on architect quality.** If the architect wrote a weak `## Summary`, the inline summary will reflect that. This RFC does not change the quality bar for the Summary section — it only surfaces whatever was already written. A poor inline summary is a signal to the reviewer that the RFC itself needs work, which is arguably useful feedback.

2. **Step 9 output grows longer.** Reviewers who are comfortable opening the file will see extra prose they did not need. The instruction keeps the summary tight ("a few sentences or short bulleted sections"), and the actionable instructions (path, changelog, next steps) are preserved at the bottom where they are easy to find.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/rfc-new/SKILL.md` | Extend Step 9 to include an inline RFC summary before the path and changelog bullets |

### Steps

#### Step 1 — Update Step 9 of `skills/rfc-new/SKILL.md`

Open `skills/rfc-new/SKILL.md`. Replace the current Step 9 block (lines 140-149, verified: `skills/rfc-new/SKILL.md:L140`) with the following:

Current text:
```
### 9. Present to human

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
```

Replacement text:
```
### 9. Present to human

Present the RFC to the human. The RFC stays `status: Draft`.

Open with an inline RFC summary derived from the RFC content the architect just wrote — do not re-analyze or spawn a new agent. The summary has two parts:

1. **What was proposed.** Present the RFC's `## Summary` section content verbatim or closely paraphrased. Do not restate the section heading; present the prose directly. If the `## Summary` section is absent or empty, synthesize a one-sentence description of what the RFC proposes based on the file content.

2. **Key constraints and notable design decisions.** A short bulleted list (2-4 bullets) of choices that shaped the design and that a reviewer might want to question before reading the full file. Examples: what alternatives were ruled out and why, what backward-compatibility constraints apply, what the most contentious design choice was. If nothing is notable beyond what the summary already captures, omit this section rather than padding with obvious points.

After the summary, tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
```

Verification:

```bash
grep -c "What was proposed\|Key constraints and notable design decisions" skills/rfc-new/SKILL.md
```

Expected output: `2` (both new instruction headings are present in the step body).

```bash
grep -c "Path to the RFC file\|rfc-read-feedback\|rfc-approve" skills/rfc-new/SKILL.md
```

Expected output: `3` (the three preserved action bullets are still present).

```bash
grep -n "^### 9\." skills/rfc-new/SKILL.md
```

Expected output: a single line — `140:### 9. Present to human` (the heading stays at the same line; the block is longer but starts at the same place).

## Risks and open questions

1. **Summary accuracy depends on what the architect surfaces.** The instruction says "derived from the RFC content the architect just wrote" to prevent re-analysis, but it does not define what counts as a "notable design decision". An architect that lists every decision makes the output noisy; one that lists nothing omits value. The instruction bounds the output at 2-4 bullets and includes a concrete "if nothing is notable, omit" escape hatch, which should keep it calibrated in most cases. If the output is consistently too sparse or too verbose in practice, the instruction wording can be tuned without a new RFC.

2. **The summary may reference information the human sees before reading the RFC, creating anchoring bias.** A reviewer who reads the inline summary first may anchor on the architect's framing rather than evaluating the RFC independently. This is an inherent trade-off: summary always anchors; the question is whether the sanity-check value outweighs the anchoring cost. For this skill the answer is yes — `/rfc-new` is the creation flow, not the approval flow; the goal is to catch gross direction errors early, not to preserve reviewer neutrality.

3. **Step 9 instruction length grew but is still unambiguous.** The replacement text is longer than the original. The added length is instruction prose, not implementation code, so there is no parsing ambiguity. The architect is told exactly what to do (derive from the `## Summary` section and add 2-4 notable-decision bullets) and what not to do (no new agent, no re-analysis).

## Relationship to other RFCs

- **`docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md`** (`Approved`) renames `/rfc-read-feedback` to `/rfc-read-reviews` and replaces the `FEEDBACK:` marker with `REVIEW:`. The current text of `skills/rfc-new/SKILL.md` Step 9 still references `/rfc-read-feedback` and `FEEDBACK:` (verified: `skills/rfc-new/SKILL.md:L146`). This RFC's replacement text preserves those references unchanged, so whichever RFC lands first, the other's update to that bullet is still a clean substitution. If the unify RFC is implemented before this one, the implementer of this RFC should use the post-rename text (`/rfc-read-reviews` and `REVIEW:`) in the replacement block above rather than the current text. If this RFC is implemented first, the unify RFC's Step 4 targets the `/rfc-read-feedback` bullet "at line 145" — but after this RFC's edit inserts new lines above that bullet, the bullet moves to a later line number. The implementer of the unify RFC should locate the bullet by content (the literal text `Run \`/rfc-read-feedback\``) rather than by line number when applying the substitution.

- No other in-flight RFC touches `skills/rfc-new/SKILL.md` Step 9.
