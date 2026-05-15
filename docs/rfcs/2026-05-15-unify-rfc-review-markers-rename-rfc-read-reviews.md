---
rfc: "2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews"
title: "Unify RFC review markers under REVIEW: and rename rfc-read-feedback to rfc-read-reviews"
author: "Rodrigo Kochenburger"
status: "Approved"
created: "2026-05-15"
drop_reason: ~
---

## Summary

The RFC workflow currently uses two distinct inline-marker conventions: `FEEDBACK:` (scanned by `/rfc-read-feedback`, the human-comment intake skill) and `REVIEW:` (scanned by `/rfc-implement` Step 3 as a "spec has unresolved items" gate, verified: `skills/rfc-implement/SKILL.md:L44`). The two-marker split is an inconsistency users routinely hit — a human pastes a `REVIEW:` comment and `/rfc-read-feedback` cannot find it, or vice versa. This RFC unifies the convention under a single `REVIEW:` marker, renames the skill from `/rfc-read-feedback` to `/rfc-read-reviews` (and the skill directory from `skills/rfc-read-feedback/` to `skills/rfc-read-reviews/`), and updates every dependent file (skill bodies, agent definitions, docs, README, CHANGELOG, the upstream `rfc-process.md`, the project copy `docs/rfc-process.md`, and the Draft RFC `2026-05-14-skill-helper-scripts.md`) so prose, examples, grep patterns, and skill names all reference the unified `REVIEW:` / `/rfc-read-reviews` convention.

## Should we do this?

**Yes.** Two marker conventions for the same conceptual operation ("annotate the RFC inline; come back and address the annotations") is a footgun that has already shipped: `skills/rfc-implement/SKILL.md` lines 45 and 53 reference a `/rfc-reviews` skill that does not exist (verified: `skills/rfc-implement/SKILL.md:L45`, `skills/rfc-implement/SKILL.md:L53`) — a latent broken pointer that this RFC also fixes by making it `/rfc-read-reviews`. The Approved RFC `2026-05-12-post-approval-discretionary-revisions` proposes to keep `REVIEW:` as the ambiguity-scanner's marker but rewrite the error message to say `/rfc-read-feedback` (verified: `docs/rfcs/2026-05-12-post-approval-discretionary-revisions.md:L337`) — bookkeeping that still leaves the two-marker split intact. Unifying now, before that RFC's helper-scripts cousin (`2026-05-14-skill-helper-scripts`, still `Draft`, verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5`) hardens the `FEEDBACK:` grep pattern into a versioned `scripts/rfc-feedback-list.sh`, is materially cheaper than unifying after.

## Current state

Two markers, two scanners, fragmented prose:

1. **`FEEDBACK:` is the human-comment intake marker.** `skills/rfc-read-feedback/SKILL.md` describes the workflow: humans add lines like `FEEDBACK: <comment>` directly inside the RFC body; the skill greps for them with `grep -n "^FEEDBACK:" docs/rfcs/<filename>` (verified: `skills/rfc-read-feedback/SKILL.md:L37`), lists each marker with line numbers for confirmation, dispatches `rfc-architect` to address each one, and removes the marker line.

2. **`REVIEW:` is the implementation-gate marker.** `skills/rfc-implement/SKILL.md` Step 3 scans the implementation spec for any remaining `REVIEW:` markers or placeholder language and refuses to proceed if any are found (verified: `skills/rfc-implement/SKILL.md:L44`). The error message in the same step tells the user to "Run `/rfc-reviews` or update the RFC" (verified: `skills/rfc-implement/SKILL.md:L45`, `skills/rfc-implement/SKILL.md:L53`) — a skill that does not exist. This dangling `/rfc-reviews` reference appears to be a pre-emptive but never-completed rename attempt.

3. **The two markers are used for the same conceptual operation.** A user who wants to leave an inline note on a Draft RFC has no reason to think there are two markers. A user who reads `/rfc-implement`'s "the implementation spec has unresolved items" message and tries to run `/rfc-reviews` gets nothing. A user who reads `/rfc-read-feedback`'s name and grep pattern uses `FEEDBACK:` — but the `/rfc-implement` gate will not flag `FEEDBACK:` lines.

4. **The split has spread across the documentation surface.** References to `/rfc-read-feedback` and `FEEDBACK:` appear in 16 distinct files (verified by grep): the two `rfc-process.md` files (root and `docs/`), both `CLAUDE.md` files (root and `.claude-plugin/`), `README.md`, `CHANGELOG.md`, `docs/agent-audit-criteria.md`, four agent definitions (`agents/rfc-architect.md`, `agents/feature-engineer.md`, `agents/docs-agent.md`, `agents/documentation-writer.md`), four sibling skill bodies (`skills/rfc-new/SKILL.md`, `skills/rfc-summary/SKILL.md`, `skills/docs-review/SKILL.md`, `skills/rfc-read-feedback/SKILL.md` itself), and one Draft RFC (`docs/rfcs/2026-05-14-skill-helper-scripts.md`) that contains a planned `scripts/rfc-feedback-list.sh` with embedded `FEEDBACK:` grep patterns.

5. **Existing RFC files do not contain active `FEEDBACK:` markers.** A `grep -rn "^FEEDBACK:" docs/rfcs/` returns no matches (only quoted/prose references inside historical RFC bodies, none of which are live annotations). This means the migration does not need to rewrite live human-authored markers in any RFC file — only documentation prose, skill bodies, and one Draft RFC.

## Analysis / Options

### Option A — Unify on `REVIEW:`, rename to `/rfc-read-reviews` (recommended)

Adopt `REVIEW:` as the single marker. Rename the skill from `/rfc-read-feedback` to `/rfc-read-reviews` (and move the directory from `skills/rfc-read-feedback/` to `skills/rfc-read-reviews/`). Update every prose reference, grep pattern, example, and skill name. The `/rfc-implement` ambiguity-gate keeps its existing scanner intact (it already targets `REVIEW:`) and only changes the next-step hint it emits ("Run `/rfc-read-reviews` ...").

**Why `REVIEW:` over `FEEDBACK:`:**

- It is already the implementation-gate marker. Changing the gate to scan `FEEDBACK:` would require updating two files (`skills/rfc-implement/SKILL.md` plus the Approved `2026-05-12-post-approval-discretionary-revisions` RFC's Step 3 replacement text, which itself rewrites the same lines). Keeping `REVIEW:` means the gate scanner is unchanged.
- It is the broader word: "review" covers "request changes", "ask a question inline", "note something the implementer should check", and "post-approval discretionary revision" — all valid use cases for an inline marker. "Feedback" is narrower and biases readers toward "human telling the author something is wrong".
- The skill name `/rfc-read-reviews` reads cleanly: "read the inline review notes on this RFC and address them". The plural "reviews" matches what the skill iterates over (a set of marker lines), and the verb "read" matches the skill's first action (`grep -n` to find and list them).
- No live `FEEDBACK:` markers exist in any current RFC body — switching the marker convention does not require rewriting in-flight annotations on any RFC. The migration is documentation-only plus a directory rename.
- Under the unified marker, the `/rfc-implement` Step-3 gate scanner doubles as a late-annotation catcher: a human who pastes a `REVIEW:` into an Approved RFC's `## Implementation spec` after `/rfc-implement` has started will cause the next invocation to halt at the gate. Under the split `FEEDBACK:` marker, late annotations would be silently invisible to that gate.

**Why rename the skill, not just unify the marker:**

- A skill called `/rfc-read-feedback` that scans for `REVIEW:` markers is internally contradictory. Either the name or the marker has to change; renaming the skill keeps the marker stable across both scanners (the implementation gate already uses `REVIEW:`).
- The dangling `/rfc-reviews` references in `skills/rfc-implement/SKILL.md` lines 45 and 53 indicate the rename was already half-attempted by a prior author. Completing it to `/rfc-read-reviews` (preserving the `read-` prefix that signals "read existing annotations" rather than "create new reviews") resolves the dangling references and aligns naming.

### Option B — Unify on `FEEDBACK:`, keep `/rfc-read-feedback`

Adopt `FEEDBACK:` as the single marker and update `/rfc-implement` Step 3 to scan `FEEDBACK:` instead of `REVIEW:`. The skill name stays `/rfc-read-feedback`.

This avoids the directory rename but is more invasive across the codebase: the `/rfc-implement` gate scanner needs to change, the Approved RFC `2026-05-12-post-approval-discretionary-revisions` needs its Step 3 replacement text updated to scan `FEEDBACK:` instead of `REVIEW:` (currently approved text scans `REVIEW:`, verified: `docs/rfcs/2026-05-12-post-approval-discretionary-revisions.md:L335`), and the dangling `/rfc-reviews` references still need correcting to `/rfc-read-feedback`. The total churn is comparable but the directional change ("change the scanner, leave the skill name") is harder to reason about than Option A's "leave the scanner, rename the skill".

Rejected: more churn to the existing `REVIEW:` scanner and the in-flight Approved RFC; no offsetting benefit. The marker-word choice favors `REVIEW:` for the reasons in Option A.

### Option C — Keep both markers, document the distinction

Leave `FEEDBACK:` for human inline comments and `REVIEW:` for spec-incompleteness markers, and add prose to `docs/rfc-process.md` explaining when to use each.

Rejected: this codifies the current confusion as a feature. Users who paste a `REVIEW:` marker expecting `/rfc-read-feedback` to find it will still be surprised; users who paste a `FEEDBACK:` marker expecting `/rfc-implement` to gate on it will still be surprised. The two markers serve the same conceptual operation (an annotation that the implementer/author must come back to) — there is no operational reason to maintain two separate scanners.

## Drawbacks

1. **Renaming a published skill is a breaking change for users.** The plugin has been released; teams may have shell aliases, internal docs, or local scripts that invoke `/rfc-read-feedback`. The CHANGELOG entry must call this out prominently, and the README/skill list must reflect the new name. No backward-compatibility alias is provided — the skill name is canonical, and shipping a renamed-skill-with-alias would mean carrying two skill registrations forever to avoid one explicit migration step.

2. **Existing audit-log footers in agent files reference `/rfc-read-feedback`.** The audit log in `agents/rfc-architect.md` line 194 (verified: `agents/rfc-architect.md:L194`) names `/rfc-read-feedback` in the historical justification for that audit pass. Rewriting an audit log silently rewrites history; instead, audit-log entries that name the old skill are left unchanged (they describe what was true on the date stamped at the entry's start), and a new audit-log entry is appended documenting this RFC's pass.

3. **The Draft helper-scripts RFC (`2026-05-14-skill-helper-scripts`) plans a `scripts/rfc-feedback-list.sh` keyed off `FEEDBACK:`.** Updating that Draft RFC to align with the new convention is part of this RFC's scope; once the helper-scripts RFC is implemented, it will create `scripts/rfc-review-list.sh` instead. If the helper-scripts RFC is implemented before this one (it is currently `Draft`, so the order is not yet fixed), the rename would need to happen during this RFC's implementation as a script-file rename plus a content patch — straightforward but worth noting.

4. **The `/rfc-implement` Step 3 message currently mentions `/rfc-reviews` (a non-existent skill).** This RFC corrects that to `/rfc-read-reviews`. The Approved `2026-05-12-post-approval-discretionary-revisions` RFC also rewrites those same Step 3 lines (changing `/rfc-reviews` to `/rfc-read-feedback`, verified: `docs/rfcs/2026-05-12-post-approval-discretionary-revisions.md:L337`). If that RFC lands first, this RFC's patch must be re-rebased onto the new file content. The "Risks and open questions" section captures the merge-order handling explicitly.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Move | `skills/rfc-read-feedback/SKILL.md` → `skills/rfc-read-reviews/SKILL.md` | Rename the skill directory and update the file's contents (`name:` field, `description:` triggers, body prose, examples, grep pattern) to use `REVIEW:` and the new skill name. |
| Modify | `skills/rfc-approve/SKILL.md` | Add a pre-approval gate that scans the `## Implementation spec` section for `REVIEW:` markers and refuses to approve if any are found, instructing the user to run `/rfc-read-reviews` first. |
| Modify | `skills/rfc-implement/SKILL.md` | Fix the two dangling `/rfc-reviews` references on lines 45 and 53 to `/rfc-read-reviews`. |
| Modify | `skills/rfc-new/SKILL.md` | Update the "Present to human" closing-tip line (line 145) to mention `/rfc-read-reviews` and `REVIEW:` instead of `/rfc-read-feedback` and `FEEDBACK:`. |
| Modify | `skills/rfc-summary/SKILL.md` | Update the closing hand-off line (line 106) to mention `/rfc-read-reviews` and `REVIEW:`. |
| Modify | `skills/docs-review/SKILL.md` | Update the "When this skill is *not* the right tool" list (line 192) to mention `/rfc-read-reviews`. |
| Modify | `agents/rfc-architect.md` | Update line 16 (skill list in "Project context") to reference `/rfc-read-reviews` and `REVIEW:` markers. Append a new audit-log entry documenting this RFC's update. Existing audit-log entries are unchanged. |
| Modify | `agents/feature-engineer.md` | Update line 70 to reference `/rfc-read-reviews` instead of `/rfc-read-feedback`. |
| Modify | `agents/docs-agent.md` | Update lines 77 and 86 to reference `/rfc-read-reviews`. |
| Modify | `agents/documentation-writer.md` | Update line 60 to reference `/rfc-read-reviews`. |
| Modify | `rfc-process.md` (repo root, the upstream copy used by `/rfc-update`) | Update lines 160, 191, 206 to reference `/rfc-read-reviews` and `REVIEW:`. |
| Modify | `docs/rfc-process.md` (project copy) | Update the corresponding lines (165, 196, 211 in the current file) to mirror the upstream changes, and update the `<!-- LAST_SYNCED: ... -->` header date. |
| Modify | `CLAUDE.md` (repo root) | Update line 65 (skills list under "RFC Process") to list `/rfc-read-reviews`. |
| Modify | `.claude-plugin/CLAUDE.md` | Update line 161 to list `/rfc-read-reviews`. |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | Update line 41 (the `Skills:` list in the "RFC Process" section) to replace `/rfc-read-feedback` with `/rfc-read-reviews`. |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Regenerated by `build-manifest.sh` after editing the template. |
| Modify | `README.md` | Update lines 38 (workflow diagram) and 91 (skills table) to use `/rfc-read-reviews` and `REVIEW:`. |
| Modify | `CHANGELOG.md` | Append a new unreleased entry documenting the breaking rename. The historical `0.1.0` entry on line 64 is left unchanged (it describes the state at release). |
| Modify | `docs/agent-audit-criteria.md` | Update line 95 to reference `/rfc-read-reviews`. |
| Modify | `docs/rfcs/2026-05-14-skill-helper-scripts.md` (Draft) | Rewrite every `FEEDBACK:` and `rfc-feedback-list` reference to `REVIEW:` and `rfc-review-list`, including the inline scripts, file-structure tables, test descriptions, and verification examples. This is a Draft RFC so the change is in-place. |

### Steps

The steps are ordered so that each step leaves the repository in a coherent state — every intermediate commit can be reviewed independently and no step assumes a later step has run. The directory rename happens first so subsequent edits target the final path.

#### Step 1 — Rename the skill directory and rewrite its contents

Move the skill directory:

```bash
git mv skills/rfc-read-feedback skills/rfc-read-reviews
```

Then rewrite the contents of `skills/rfc-read-reviews/SKILL.md` to use the new name and marker. The full target content (rendered with four-backtick outer fences here so the embedded three-backtick examples inside the file are preserved verbatim — the actual SKILL.md uses three-backtick fences, not four):

````markdown
---
name: rfc-read-reviews
description: Use to address inline REVIEW: comments that humans have added to an RFC file. Spawns rfc-architect to incorporate each comment, removes the markers, and runs the self-review checklist. Triggered by "/rfc-read-reviews [RFC number or filename]".
---

# RFC Read Reviews

Reads all `REVIEW:` markers in an RFC, dispatches `rfc-architect` to address them, removes the markers, and runs the self-review checklist.

## REVIEW: marker format

Humans add review notes directly in the RFC file as lines starting with `REVIEW:`:

```
REVIEW: The implementation spec doesn't cover the authentication failure case. Please add a step for it.
```

A marker applies to the content immediately above it in the same section. Markers may appear anywhere in the document body (not in frontmatter).

## Lifecycle invariant

`REVIEW:` markers are valid annotations at any point in an RFC's lifecycle:

- **On a Draft RFC**: they signal discussion notes or questions for the author to address before approval. Use `/rfc-read-reviews` to process them.
- **On an Approved RFC's `## Implementation spec` section**: they signal a spec gap that must be resolved before implementation begins. `/rfc-implement` Step 3 treats any remaining `REVIEW:` marker in the spec as a blocking error.
- **On an Approved RFC's non-spec sections** (Summary, Analysis, Risks, etc.): they are informational notes left for the implementer; `/rfc-implement` does not block on them.

`/rfc-approve` enforces this by refusing to approve any RFC that contains a `REVIEW:` marker inside its `## Implementation spec` section.

## Steps

### 1. Identify the RFC

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: RFC-NNN — `docs/rfcs/NNN-title.md`]" — accept a blank response as confirmation of the default.

Read the matching `docs/rfcs/NNN-*.md` file.

### 2. Find all REVIEW: markers

Search for lines starting with `REVIEW:`:

```bash
grep -n "^REVIEW:" docs/rfcs/<filename>
```

If none found: report **"No REVIEW: markers found in <filename>."** and stop.

### 3. Display for human confirmation

List the found comments with their line numbers:

```
Found N REVIEW: comment(s) in <filename>:

Line 42: REVIEW: The implementation spec doesn't cover authentication failures.
Line 67: REVIEW: Option B should be dropped — it's identical to Option A except for naming.

Address these? (yes/no)
```

Wait for confirmation before proceeding.

### 4. Spawn bytewyrd:rfc-architect to address the comments

Spawn a `bytewyrd:rfc-architect` agent (`model: "opus"`) with:
- The full RFC content
- The list of `REVIEW:` comments and their line numbers
- Instruction: address each comment by updating the relevant section, then remove the `REVIEW:` line; do not add new `REVIEW:` lines; follow the no-placeholders rule

After incorporating feedback, the agent runs the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present?
3. **Consistency** — type names, signatures, paths match across sections?

### 5. Write and report

Write the updated RFC. Report a brief summary per comment:

```
Addressed 2 REVIEW: comments:
- Line 42: Added "Error handling" step to the implementation spec covering auth failures (401 response, token invalidation).
- Line 67: Removed Option B; folded the naming note into Option A as a variant.
```

Do **not** change `status`. Do **not** commit automatically.
````

Verification:

```bash
test -f skills/rfc-read-reviews/SKILL.md && ! test -e skills/rfc-read-feedback
```

Expected output: exit code `0` (the new file exists; the old directory does not).

```bash
grep -c '^REVIEW:' skills/rfc-read-reviews/SKILL.md
```

Expected output: a single integer (the count of literal `REVIEW:` line-starts inside the example blocks) — not zero.

```bash
grep -c 'FEEDBACK' skills/rfc-read-reviews/SKILL.md
```

Expected output: `0`.

#### Step 2 — Add REVIEW: gate to `skills/rfc-approve/SKILL.md`

Open `skills/rfc-approve/SKILL.md`. The current skill body (after the frontmatter) runs five numbered steps under `## Steps`: (1) Identify the RFC, (2) Verify status, (3) Display summary for confirmation, (4) Update status, (5) Commit. The new gate runs after the RFC has been read and validated as `Draft` but before the human confirmation prompt — between the current Step 2 ("Verify status") and the current Step 3 ("Display summary for confirmation"). Placing it there means the human is not shown an approval prompt for an RFC that the gate would reject.

Insert the new step content as a new `### 3. Check for unresolved REVIEW: markers in the implementation spec` block, and renumber the existing Step 3 ("Display summary for confirmation") to Step 4, Step 4 ("Update status") to Step 5, and Step 5 ("Commit") to Step 6. The new block is inserted between line 30 (the blank line after the `Stop in any of these cases.` paragraph at the end of the current Step 2 body) and line 31 (the `### 3. Display summary for confirmation` heading).

The new block's exact prose:

```markdown
### 3. Check for unresolved REVIEW: markers in the implementation spec

`REVIEW:` markers inside the `## Implementation spec` section signal a spec gap that `/rfc-implement` will refuse to act on. Catch those at the approval boundary rather than letting them surface mid-implementation.

Scan the RFC's `## Implementation spec` section (only that section — `REVIEW:` markers in other sections such as `## Summary`, `## Analysis / Options`, and `## Risks and open questions` are informational annotations and do not block approval):

​```bash
awk '/^## Implementation spec/{found=1} found && /^## /{if(!/^## Implementation spec/)found=0} found && /^REVIEW:/{print NR": "$0}' docs/rfcs/<filename>
​```

If the `awk` command produces any output, refuse approval and report:

> "Cannot approve: the `## Implementation spec` section contains N unresolved `REVIEW:` marker(s). Run `/rfc-read-reviews` to address them before approving."

Show the matching lines (the `awk` output already includes line numbers and the marker text) so the human can see exactly what needs resolving. Stop.

If the `awk` command produces no output, proceed to the next step.
```

Note: the inner four-space-indented code block uses zero-width-space-prefixed (`​`) backticks here so the surrounding RFC markdown does not nest fences. When applying this edit to `skills/rfc-approve/SKILL.md`, write the standard three-backtick fences (without the zero-width space) — the SKILL.md file does not need the prefix because it does not nest the snippet inside another fence.

Verification:

```bash
grep -c 'REVIEW:' skills/rfc-approve/SKILL.md
```

Expected output: at least `1` (the new gate references the marker in prose and in the `awk` pattern).

```bash
grep -n '^### ' skills/rfc-approve/SKILL.md
```

Expected output: six lines — `### 1. Identify the RFC`, `### 2. Verify status`, `### 3. Check for unresolved REVIEW: markers in the implementation spec`, `### 4. Display summary for confirmation`, `### 5. Update status`, `### 6. Commit`.

#### Step 3 — Fix the dangling `/rfc-reviews` references in `skills/rfc-implement/SKILL.md`

Open `skills/rfc-implement/SKILL.md`. Two lines need updating.

Line 45 currently reads:
```
> "The implementation spec has unresolved items. Run `/rfc-reviews` or update the RFC before implementing."
```

Replace with:
```
> "The implementation spec has unresolved items. Run `/rfc-read-reviews` or update the RFC before implementing."
```

Line 53 currently reads:
```
- If the spec is ambiguous on any point: stop, update the RFC via `bytewyrd:rfc-architect` + `/rfc-reviews`, get it re-approved, then resume
```

Replace with:
```
- If the spec is ambiguous on any point: stop, update the RFC via `bytewyrd:rfc-architect` + `/rfc-read-reviews`, get it re-approved, then resume
```

The `REVIEW:` marker reference on line 44 is unchanged — the scanner already targets `REVIEW:`.

Verification:

```bash
grep -n 'rfc-reviews\b\|rfc-read-reviews' skills/rfc-implement/SKILL.md
```

Expected output: two lines, both mentioning `rfc-read-reviews` (and no bare `rfc-reviews`).

```bash
grep -c 'REVIEW:' skills/rfc-implement/SKILL.md
```

Expected output: `1` (the original line 44 scanner reference, unchanged).

#### Step 4 — Update `skills/rfc-new/SKILL.md`

Open `skills/rfc-new/SKILL.md`. The "Present to human" step (Step 9) lists hints to print after the RFC is finished. Line 145 currently reads:

```
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
```

Replace with:

```
- Run `/rfc-read-reviews` to address any inline `REVIEW:` comments
```

Verification:

```bash
grep -n 'rfc-read-feedback\|FEEDBACK' skills/rfc-new/SKILL.md
```

Expected output: no matches (exit code `1` from grep).

```bash
grep -c 'rfc-read-reviews\|REVIEW:' skills/rfc-new/SKILL.md
```

Expected output: at least `1` (the updated hint line).

#### Step 5 — Update `skills/rfc-summary/SKILL.md`

Open `skills/rfc-summary/SKILL.md`. Line 106 currently reads:

```
> "Run `/rfc-approve <rfc>` to approve a Draft, `/rfc-implement <rfc>` to begin an Approved RFC, or `/rfc-read-feedback <rfc>` to address inline `FEEDBACK:` comments."
```

Replace with:

```
> "Run `/rfc-approve <rfc>` to approve a Draft, `/rfc-implement <rfc>` to begin an Approved RFC, or `/rfc-read-reviews <rfc>` to address inline `REVIEW:` comments."
```

Verification:

```bash
grep -n 'rfc-read-feedback\|FEEDBACK' skills/rfc-summary/SKILL.md
```

Expected output: no matches (exit code `1`).

#### Step 6 — Update `skills/docs-review/SKILL.md`

Open `skills/docs-review/SKILL.md`. Line 192 currently reads:

```
- Creating or updating an RFC — use `/rfc-new`, `/rfc-read-feedback`, `/rfc-implement`.
```

Replace with:

```
- Creating or updating an RFC — use `/rfc-new`, `/rfc-read-reviews`, `/rfc-implement`.
```

Verification:

```bash
grep -n 'rfc-read-feedback' skills/docs-review/SKILL.md
```

Expected output: no matches (exit code `1`).

#### Step 7 — Update `agents/rfc-architect.md`

Open `agents/rfc-architect.md`. Line 16 currently reads:

```
- **`/rfc-read-feedback`** — dispatches you to address inline `FEEDBACK:` markers humans have added to an RFC file, remove the markers, and re-run the self-review checklist.
```

Replace with:

```
- **`/rfc-read-reviews`** — dispatches you to address inline `REVIEW:` markers humans have added to an RFC file, remove the markers, and re-run the self-review checklist.
```

The existing audit-log footer on line 194 is **not modified** — that entry describes what was audited on the original audit date and naming the old skill there is historically correct. Append a new audit-log entry immediately after the existing one. The new entry's text is exactly:

```html
<!-- 2026-05-15: marker-unification pass per RFC 2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews; updated the "Project context" skill list to reference /rfc-read-reviews (renamed from /rfc-read-feedback) and `REVIEW:` markers (unified from `FEEDBACK:`); no other content changes; criteria version unchanged. -->
```

Verification:

```bash
grep -c 'rfc-read-feedback\|FEEDBACK' agents/rfc-architect.md
```

Expected output: `3` (the preserved 2026-05-12 audit-log entry on line 194 naming `/rfc-read-feedback`, plus the two references in the new 2026-05-15 audit-log entry's historical-rename description `renamed from /rfc-read-feedback` and `unified from FEEDBACK:`). The three remaining matches are all inside audit-log footers (one in the 2026-05-12 entry, two in the new 2026-05-15 entry) — they are intentional historical record and are not removed.

```bash
grep -c 'rfc-read-reviews' agents/rfc-architect.md
```

Expected output: `2` (line 16 plus the new audit-log footer).

#### Step 8 — Update `agents/feature-engineer.md`

Open `agents/feature-engineer.md`. Line 70 currently reads:

```
2. **If implementing an Approved RFC**, the entry point is the `/rfc-implement` skill. Treat the RFC as the source of truth for the implementation spec: do not redesign and do not extend scope. If any part of the spec is ambiguous, stop and recommend the user run `/rfc-read-feedback` or revise the RFC via the `rfc-architect` agent before resuming.
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews` in that sentence. The rest of the line is unchanged.

Verification:

```bash
grep -n 'rfc-read-feedback' agents/feature-engineer.md
```

Expected output: no matches (exit code `1`).

#### Step 9 — Update `agents/docs-agent.md`

Open `agents/docs-agent.md`. Two lines need updating.

Line 77 currently reads:

```
- RFC creation or updates — use `/rfc-new`, `/rfc-read-feedback`, `/rfc-implement`.
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Line 86 currently reads (within a longer paragraph):

```
... and are mutated only by `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, and `/rfc-read-feedback`. ...
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`. The surrounding paragraph is unchanged.

Verification:

```bash
grep -n 'rfc-read-feedback' agents/docs-agent.md
```

Expected output: no matches (exit code `1`).

#### Step 10 — Update `agents/documentation-writer.md`

Open `agents/documentation-writer.md`. Line 60 currently reads (within a longer paragraph):

```
- **RFC files (do not modify):** `docs/rfcs/**` and `docs/rfc-process.md` are owned by the `rfc-architect` agent and the RFC skills (`/rfc-new`, `/rfc-read-feedback`). If a documentation update implies an RFC change, recommend the user open one with `/rfc-new` rather than editing RFC files directly.
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Verification:

```bash
grep -n 'rfc-read-feedback' agents/documentation-writer.md
```

Expected output: no matches (exit code `1`).

#### Step 11 — Update the upstream `rfc-process.md` (repo root)

Open `rfc-process.md` (at the repo root — this is the source-of-truth copy that `/rfc-update` syncs into project `docs/rfc-process.md` files). Three locations need updating.

Line 160 currently reads:

```
Use `/rfc-read-feedback`. Humans annotate the RFC file directly with `FEEDBACK:` markers; the skill dispatches `rfc-architect` to address each comment, remove the markers, and run the self-review checklist.
```

Replace with:

```
Use `/rfc-read-reviews`. Humans annotate the RFC file directly with `REVIEW:` markers; the skill dispatches `rfc-architect` to address each comment, remove the markers, and run the self-review checklist.
```

Line 191 currently reads (within a longer paragraph):

```
... If the spec is ambiguous, update the RFC first (via `rfc-architect` + `/rfc-read-feedback`) rather than having the implementation agent guess. ...
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Line 206 currently reads (inside the Skills table):

```
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments left by humans in an RFC |
```

Replace with:

```
| `/rfc-read-reviews` | Address inline `REVIEW:` comments left by humans in an RFC |
```

Verification:

```bash
grep -c 'rfc-read-feedback\|FEEDBACK:' rfc-process.md
```

Expected output: `0`.

```bash
grep -c 'rfc-read-reviews\|REVIEW:' rfc-process.md
```

Expected output: at least `3` (three updated locations).

#### Step 12 — Update the project copy `docs/rfc-process.md`

Open `docs/rfc-process.md`. This is the synced copy in the project's docs directory. The three locations to update are at lines 165, 196, and 211 of the current file (the offset versus the upstream is because the project copy has the four header lines `<!-- UPSTREAM: ... -->`, `<!-- LAST_SYNCED: ... -->`, `<!-- /rfc-update or /sync ... -->`, and a blank line prepended, plus one extra body line inserted on line 153 that does not appear in the upstream).

Line 165 currently reads:

```
Use `/rfc-read-feedback`. Humans annotate the RFC file directly with `FEEDBACK:` markers; the skill dispatches `rfc-architect` to address each comment, remove the markers, and run the self-review checklist.
```

Replace identically to Step 11's line 160 change (use `/rfc-read-reviews` and `REVIEW:`).

Line 196 currently reads (within a longer paragraph):

```
... If the spec is ambiguous, update the RFC first (via `rfc-architect` + `/rfc-read-feedback`) rather than having the implementation agent guess. ...
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Line 211 currently reads:

```
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments left by humans in an RFC |
```

Replace with:

```
| `/rfc-read-reviews` | Address inline `REVIEW:` comments left by humans in an RFC |
```

Then update the `<!-- LAST_SYNCED: ... -->` header on line 2 from `<!-- LAST_SYNCED: 2026-05-12 -->` to `<!-- LAST_SYNCED: 2026-05-15 -->`. This signals that the project copy is now in sync with the post-rename upstream.

Verification:

```bash
grep -c 'rfc-read-feedback\|FEEDBACK:' docs/rfc-process.md
```

Expected output: `0`.

```bash
grep -n 'LAST_SYNCED' docs/rfc-process.md
```

Expected output: a single line — `2:<!-- LAST_SYNCED: 2026-05-15 -->`.

#### Step 13 — Update `CLAUDE.md` (repo root)

Open `CLAUDE.md`. Line 65 currently reads (the trailing skill list under "RFC Process"):

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews` in the skills list. The rest of the line is unchanged.

Verification:

```bash
grep -n 'rfc-read-feedback' CLAUDE.md
```

Expected output: no matches (exit code `1`).

#### Step 14 — Update `.claude-plugin/CLAUDE.md`

Open `.claude-plugin/CLAUDE.md`. Line 161 currently reads:

```
- Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Verification:

```bash
grep -n 'rfc-read-feedback' .claude-plugin/CLAUDE.md
```

Expected output: no matches (exit code `1`).

#### Step 15 — Update `.claude-plugin/scripts/templates/CLAUDE.md.tpl`

Open `.claude-plugin/scripts/templates/CLAUDE.md.tpl`. This template is the source that `/sync` seeds into every consumer project's `CLAUDE.md`; leaving it unmodified would mean every post-rename `/sync` restores the old skill name.

Line 41 currently reads:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews` in the skills list. The rest of the line is unchanged.

Verification:

```bash
grep -n 'rfc-read-feedback' .claude-plugin/scripts/templates/CLAUDE.md.tpl
```

Expected output: no matches (exit code `1`).

#### Step 16 — Regenerate `.claude-plugin/bootstrap-manifest.json`

The pre-commit hook (`.claude-plugin/hooks/pre-commit/manifest-check.sh`) fails commits when the manifest is stale. Two manifest-tracked source files are modified by this RFC: `rfc-process.md` (Step 11) and `.claude-plugin/scripts/templates/CLAUDE.md.tpl` (Step 15). Without regenerating, any commit that includes those edits will be rejected.

After editing `.claude-plugin/scripts/templates/CLAUDE.md.tpl` (Step 15) and `rfc-process.md` (Step 11), run:

```bash
bash .claude-plugin/scripts/build-manifest.sh
```

Expected output: the manifest is regenerated silently (no errors). Then check that the file changed:

```bash
git diff --name-only .claude-plugin/bootstrap-manifest.json
```

Expected output: `.claude-plugin/bootstrap-manifest.json` is listed as modified.

Stage and commit the regenerated manifest alongside the template edit:

```bash
git add .claude-plugin/bootstrap-manifest.json .claude-plugin/scripts/templates/CLAUDE.md.tpl
```

Then commit (together with the `rfc-process.md` edit from Step 11 if that has not been committed yet, or as its own commit if Step 11 was already committed — either ordering is fine as long as no intermediate commit leaves the manifest stale relative to its sources).

Verification:

```bash
bash .claude-plugin/scripts/build-manifest.sh --check
```

Expected output: exit code `0` (the manifest is up-to-date).

#### Step 17 — Update `README.md`

Open `README.md`. Two lines need updating.

Line 38 (inside the workflow diagram, which is rendered as plain ASCII inside a Markdown code block):

```
 Sets up:              /rfc-read-feedback            Spawns a
```

Replace with:

```
 Sets up:              /rfc-read-reviews             Spawns a
```

Note: the alignment of the diagram requires careful column-count preservation. `/rfc-read-feedback` is 18 characters wide. `/rfc-read-reviews` is 17 characters wide. To preserve the diagram's column boundary (the `Spawns a` text is column-anchored relative to surrounding diagram rows), pad the replacement with one trailing space — i.e., `/rfc-read-reviews ` (with one extra space before the run of spaces leading to `Spawns a`). The total whitespace between the new skill name and `Spawns a` must equal the total whitespace in the original (12 spaces between `/rfc-read-feedback` and `Spawns a` in the original → 13 spaces after `/rfc-read-reviews` in the replacement).

Line 91 (inside the Skills table):

```
| `/rfc-read-feedback` | Incorporate inline `FEEDBACK:` comments from reviewers |
```

Replace with:

```
| `/rfc-read-reviews` | Incorporate inline `REVIEW:` comments from reviewers |
```

Verification:

```bash
grep -n 'rfc-read-feedback\|FEEDBACK:' README.md
```

Expected output: no matches (exit code `1`).

Render check: open `README.md` in a Markdown previewer (or `glow README.md`) and visually confirm the workflow diagram on line 38 is still column-aligned with surrounding rows. The diagram is decorative; a one-space drift is acceptable, but the diagram must remain readable.

#### Step 18 — Append a CHANGELOG entry

Open `CHANGELOG.md`. Do **not** modify the existing `0.1.0` entry on line 64 — that entry describes the state shipped on 2026-05-09 and rewriting it would be revisionist. Insert a new entry at the top of the file (after the title and any "Unreleased" header if one exists; otherwise add an `## [Unreleased]` heading).

The new entry's body, in Keep-a-Changelog format under `### Changed` and `### Breaking`:

```markdown
## [Unreleased]

### Breaking

- Renamed the `/rfc-read-feedback` skill to `/rfc-read-reviews`. The inline-marker convention is unified under `REVIEW:` (previously a split between `FEEDBACK:` for the read-feedback skill and `REVIEW:` for the implementation-gate scanner). The new skill scans the same RFC files for `REVIEW:` markers, lists them with line numbers, and dispatches `rfc-architect` to address each one. Users with shell aliases or internal docs referencing `/rfc-read-feedback` must update them to `/rfc-read-reviews`. No live `FEEDBACK:` markers existed in any RFC file at the time of the rename, so no in-flight RFC annotations were lost.

### Changed

- `/rfc-implement` Step 3 now reports "Run `/rfc-read-reviews` or update the RFC" when the implementation spec contains unresolved `REVIEW:` markers or placeholder language. The previous text mentioned `/rfc-reviews`, a skill that did not exist.
```

Verification:

```bash
grep -c '/rfc-read-reviews' CHANGELOG.md
```

Expected output: at least `2` (the breaking-change line and the changed line of the new entry).

```bash
grep -c '0\\.1\\.0' CHANGELOG.md
```

Expected output: `1` (the original `0.1.0` heading is preserved, unchanged).

#### Step 19 — Update `docs/agent-audit-criteria.md`

Open `docs/agent-audit-criteria.md`. Line 95 currently reads:

```
- `rfc-architect` — references `docs/rfc-process.md` (which it already does in the locally-customized version) and the skill flow it participates in (`/rfc-new`, `/rfc-consensus-review`, `/rfc-read-feedback`).
```

Replace `/rfc-read-feedback` with `/rfc-read-reviews`.

Verification:

```bash
grep -n 'rfc-read-feedback' docs/agent-audit-criteria.md
```

Expected output: no matches (exit code `1`).

#### Step 20 — Update the in-flight Draft RFC `docs/rfcs/2026-05-14-skill-helper-scripts.md`

This Draft RFC contains a planned `scripts/rfc-feedback-list.sh` keyed off `FEEDBACK:`. Since the RFC is `Draft` and the script does not yet exist on disk (`scripts/` currently contains only `check-requirements.sh`), the change is in-place inside the RFC body — no script rename on disk is needed in this RFC. The implementer of `2026-05-14-skill-helper-scripts` will create the renamed script `scripts/rfc-review-list.sh` when they execute that RFC's spec.

The replacements inside `docs/rfcs/2026-05-14-skill-helper-scripts.md` are listed by line number as observed at this RFC's draft time. If the helper-scripts RFC has been edited between draft time and implementation time, the implementer should locate each replacement by content (the literal `FEEDBACK:` / `rfc-feedback-list` / `rfc-read-feedback` strings) rather than by line number. The set of substitutions is:

1. **Pattern label.** Line 42 currently reads:
   ```
   **P7 — FEEDBACK: comment extraction.** Extracting and counting `FEEDBACK:` markers is described at `skills/rfc-read-feedback/SKILL.md:36-40` (verified: `skills/rfc-read-feedback/SKILL.md:L36`). The current grep is one line, but the surrounding "if none found, report" / "count + list with line numbers" logic is repeated in prose. The script matches `FEEDBACK:` at any indentation level, including inside bullet lists and blockquotes — humans frequently anchor feedback to a specific list item or nested bullet, and a column-0-only matcher would silently drop those markers.
   ```
   Replace with:
   ```
   **P7 — REVIEW: comment extraction.** Extracting and counting `REVIEW:` markers is described at `skills/rfc-read-reviews/SKILL.md:36-40` (verified: `skills/rfc-read-reviews/SKILL.md:L36`). The current grep is one line, but the surrounding "if none found, report" / "count + list with line numbers" logic is repeated in prose. The script matches `REVIEW:` at any indentation level, including inside bullet lists and blockquotes — humans frequently anchor review notes to a specific list item or nested bullet, and a column-0-only matcher would silently drop those markers.
   ```
   The line-number range `36-40` and the verified-citation suffix `:L36` are preserved unchanged because they refer to the new file `skills/rfc-read-reviews/SKILL.md`, which has the same internal structure as the old `skills/rfc-read-feedback/SKILL.md` (Step 1 of this RFC keeps the step ordering identical; only the literal `FEEDBACK:` → `REVIEW:` substitutions move text by zero lines).

2. **File-structure table entries.**
   - Line 109 changes `scripts/rfc-feedback-list.sh` to `scripts/rfc-review-list.sh`, and `Pattern P7. Reads the given file and emits a JSON object on stdout with markers (array of {line, text} objects). Exits 0 on zero or more findings — finding-count is signaled by the array length, not the exit code.` is preserved verbatim except the script-name token.
   - Line 123 changes `tests/scripts/rfc-feedback-list.bats` to `tests/scripts/rfc-review-list.bats`.
   - Line 130 changes `skills/rfc-read-feedback/SKILL.md` to `skills/rfc-read-reviews/SKILL.md`.

3. **"Used by:" comment lines inside the inline scripts in the RFC body.**
   - Line 169 changes `rfc-read-feedback` to `rfc-read-reviews`.
   - Line 324 changes `rfc-read-feedback` to `rfc-read-reviews`.
   - Line 808 changes `Used by: rfc-read-feedback.` to `Used by: rfc-read-reviews.`.

4. **The `scripts/rfc-feedback-list.sh` script block** (lines 799-901 of the RFC body) is renamed throughout to `scripts/rfc-review-list.sh`. Every occurrence of `FEEDBACK:` inside the script's matching pattern, comments, error messages, and verification examples is changed to `REVIEW:`. The grep pattern `^\s*[-*>]*\s*FEEDBACK:` becomes `^\s*[-*>]*\s*REVIEW:`. The example markers in the verification output (`{"line": 3, "text": "FEEDBACK: Add a step for X."}` etc.) become `{"line": 3, "text": "REVIEW: Add a step for X."}` etc. The output JSON example block's textual content changes correspondingly.

5. **Test descriptions and the test-case table.**
   - Line 1740 changes `zero FEEDBACK markers` to `zero REVIEW markers`.
   - Line 1753 — the row labeled `rfc-feedback-list.sh` becomes `rfc-review-list.sh`, and the test descriptions inside that cell change `FEEDBACK:` to `REVIEW:` and `non-FEEDBACK:` to `non-REVIEW:`.

6. **Step 15 of the RFC body (lines 1440-1460), which describes updating `skills/rfc-read-feedback/SKILL.md`** is rewritten to describe updating `skills/rfc-read-reviews/SKILL.md`. Every embedded snippet inside that Step 15 — including the example shell invocation, the example heading `### 2. Find all FEEDBACK: markers`, and the example report-line text — changes `FEEDBACK:` to `REVIEW:`.

7. **The Risk section's Exa-cited entry on line 1800** referencing `rfc-feedback-list.sh` (as the clear example of a script that deliberately omits `set -e`) is updated to `rfc-review-list.sh`. The substantive content of the risk (the bash strict-mode behavior, the Exa citation URL, and the mitigation reasoning) is preserved verbatim — only the script-name token changes.

The enumerated items 1–7 above describe *what* is being changed and *why* — they orient the implementer to the structurally distinct locations (pattern label, file-structure table, "Used by:" comments, script block, test descriptions, embedded SKILL.md update, Risks entry). At draft time `grep -c 'FEEDBACK:\|rfc-feedback-list\|rfc-read-feedback' docs/rfcs/2026-05-14-skill-helper-scripts.md` returns `38`, and many of those 38 occurrences cluster inside the script block (item 4) and the embedded SKILL.md update (item 6) rather than mapping one-to-one onto separate enumerated bullets. Rather than trying to enumerate every match by line number, after applying the enumerated substitutions above run a final sweep to catch any missed occurrences:

```bash
grep -n 'FEEDBACK:\|rfc-feedback-list\|rfc-read-feedback' docs/rfcs/2026-05-14-skill-helper-scripts.md
```

For each remaining match, apply the same literal substitution: `FEEDBACK:` → `REVIEW:`, `rfc-feedback-list` → `rfc-review-list`, `rfc-read-feedback` → `rfc-read-reviews`. Re-run until the command exits with no output. The Step 20 verification grep below already expects `0` matches — this sweep is the path to that state.

Verification (run from the project root after the edits):

```bash
grep -c 'FEEDBACK:\|rfc-feedback-list\|rfc-read-feedback' docs/rfcs/2026-05-14-skill-helper-scripts.md
```

Expected output: `0`.

```bash
grep -c 'rfc-review-list\|rfc-read-reviews' docs/rfcs/2026-05-14-skill-helper-scripts.md
```

Expected output: at least `10` (multiple replaced references throughout the RFC body).

```bash
grep -n '^status:' docs/rfcs/2026-05-14-skill-helper-scripts.md
```

Expected output: `5:status: "Draft"` — the RFC stays `Draft` (this is in-place editing of a Draft document, not a status change).

#### Step 21 — Final cross-repository verification

After all 19 prior steps are committed (each step can be a separate commit per the project's commit-discipline conventions, or batched as makes sense for review), run the following final checks from the project root.

```bash
grep -rn 'FEEDBACK:' --include='*.md' --include='*.sh' --include='*.json' --include='*.tpl' --exclude-dir='.git' . 2>/dev/null
```

Expected output: only matches inside historical/audit content. Specifically, only matches inside `agents/rfc-architect.md` line 194 (the preserved 2026-05-12 audit-log entry that names `/rfc-read-feedback` for historical record), inside this RFC's own body under `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md` (which intentionally documents the old marker in prose), and inside historical RFC bodies under `docs/rfcs/` from before this RFC's date that describe the old marker as a feature (verified at draft time: `docs/rfcs/2026-05-10-iterative-consensus-convergence.md` and `docs/rfcs/2026-05-12-rfc-summary-command.md` contain prose references). These historical RFC files are not modified — they describe the state at their creation date, and rewriting them would be revisionist. The `--include='*.tpl'` flag catches `.claude-plugin/scripts/templates/CLAUDE.md.tpl` (Step 15) so future modifications cannot silently re-introduce the old marker via that template.

```bash
grep -rn 'rfc-read-feedback' --include='*.md' --include='*.sh' --include='*.json' --include='*.tpl' --exclude-dir='.git' . 2>/dev/null
```

Expected output: only matches inside the same historical/audit content as above (including this RFC's own body). No matches inside any active skill, agent, README, CHANGELOG, CLAUDE.md, rfc-process.md, agent-audit-criteria.md, or `.tpl` template file.

```bash
grep -rn 'rfc-reviews\b' --include='*.md' --include='*.sh' --include='*.json' --include='*.tpl' --exclude-dir='.git' . 2>/dev/null
```

Expected output: only matches inside this RFC's own body (`docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md`), where the historical `/rfc-reviews` token is intentionally preserved in prose because the RFC documents the rename. No matches inside any active skill, agent, README, CHANGELOG, CLAUDE.md, rfc-process.md, agent-audit-criteria.md, or `.tpl` template file. The dangling `/rfc-reviews` references in `skills/rfc-implement/SKILL.md` lines 45 and 53 are fixed; the bare token `rfc-reviews` (without the `read-` prefix) does not appear anywhere else except as a substring inside `rfc-read-reviews` — which the `\b` word boundary in the grep excludes.

```bash
ls skills/rfc-read-reviews/SKILL.md && ! ls skills/rfc-read-feedback 2>/dev/null
```

Expected output: the new path is listed; the old directory is absent (the second `ls` exits non-zero, which the `!` inverts to success).

```bash
bash .claude-plugin/scripts/build-manifest.sh --check
```

Expected output: exit code `0` (the bootstrap manifest is up-to-date relative to its sources). The `--check` flag is documented in the script header (`build-manifest.sh --check    — exit non-zero if regenerated differs from committed`, verified: `.claude-plugin/scripts/build-manifest.sh:L4`). If this check fails, run `bash .claude-plugin/scripts/build-manifest.sh` (without `--check`) to regenerate, stage the resulting `.claude-plugin/bootstrap-manifest.json`, and commit before re-running the verification.

```bash
bash scripts/check-requirements.sh
```

Expected output: same as before this RFC (the requirement-check script does not reference either marker or skill name; verified by reading `scripts/check-requirements.sh` end-to-end).

```bash
git status --short
```

Expected output: empty (all changes committed) by the end of the implementation work.

## Risks and open questions

1. **Merge-order risk with the Approved RFC `2026-05-12-post-approval-discretionary-revisions`.** That RFC's Step 3 (in `skills/rfc-implement/SKILL.md`) rewrites lines 44-46 to mention `/rfc-read-feedback`. If `2026-05-12-post-approval-discretionary-revisions` is implemented first, then this RFC's Step 3 patch must be applied against the post-rewrite content rather than the current content — substantively it still becomes "replace `/rfc-read-feedback` (or `/rfc-reviews`) with `/rfc-read-reviews`", but the literal line being matched will differ. **Mitigation:** before applying Step 3, `grep -n 'rfc-read-feedback\|rfc-reviews\|rfc-read-reviews' skills/rfc-implement/SKILL.md` and update whichever skill-name token appears on the unresolved-items message line, regardless of which prior RFC has landed.

2. **Merge-order risk with the Draft RFC `2026-05-14-skill-helper-scripts`.** If that RFC is approved and implemented before this RFC, then by the time this RFC runs the on-disk `scripts/rfc-feedback-list.sh` will already exist and `skills/rfc-read-feedback/SKILL.md` will already have been refactored to delegate to it. This RFC's Step 20 currently assumes the script file does not yet exist (Step 20 only edits the Draft RFC's body, not the script). **Mitigation:** at implementation time, re-check `ls scripts/` and `ls skills/rfc-read-feedback/`. If the script exists, add an extra step that performs `git mv scripts/rfc-feedback-list.sh scripts/rfc-review-list.sh`, rewrites the script's internal `FEEDBACK:` patterns and comments to `REVIEW:`, runs the script's `bats` tests, and renames `tests/scripts/rfc-feedback-list.bats` to `tests/scripts/rfc-review-list.bats` with the same internal content substitution. The renamed script must remain functionally equivalent; only the marker word and skill-name references change.

3. **Audit-log preservation.** The audit-log entry inside `agents/rfc-architect.md` line 194 mentions the old skill name. Step 7 explicitly leaves that entry intact and appends a new entry. The new entry documents this RFC's update. This is the standard pattern documented in `docs/agent-audit-criteria.md` ("Future re-audits append additional footer entries (one per audit pass) rather than replacing the existing entries.", verified: `docs/agent-audit-criteria.md:L89`).

4. **Historical RFC bodies are not rewritten.** RFCs created before this RFC's date that reference `FEEDBACK:` or `/rfc-read-feedback` in their prose (notably `2026-05-10-iterative-consensus-convergence.md`, `2026-05-12-rfc-summary-command.md`, and any other prior RFC) are not modified. They describe the workflow as it existed at their creation date. Rewriting them would be revisionist history and is explicitly out of scope. The Step 21 verification grep tolerates these historical references by exclusion (the grep is reported but the matches are expected).

5. **The Draft helper-scripts RFC stays `Draft` after Step 20's edits.** This RFC modifies the body of a Draft RFC owned by the same author. The change is in-place because the helper-scripts RFC is not yet Approved. If a reviewer of this RFC believes mutating another RFC's body (even a Draft one) is inappropriate, the alternative is to leave `2026-05-14-skill-helper-scripts.md` unchanged here and require its author to update it as a follow-up before approval. **Resolution within this RFC:** prefer the in-place edit because the alternative leaves a Draft RFC in the tree with planned scripts that reference the deprecated marker — an inconsistency reviewers would catch and bounce. The author of `2026-05-14-skill-helper-scripts` (the same person authoring this RFC) consents to the in-place edit.

6. **No active human `FEEDBACK:` markers exist at draft time.** Step 21's first verification grep is built on this assumption (verified at draft time: `grep -rn '^FEEDBACK:' docs/rfcs/` returned zero matches). If, between draft time and implementation time, a human pastes a live `FEEDBACK:` marker into an RFC file, the rename would silently leave that marker unreadable by the new `/rfc-read-reviews` skill. **Mitigation:** the implementer runs `grep -rn '^FEEDBACK:' docs/rfcs/` as a first-step pre-check. If any matches surface, convert each `FEEDBACK:` line to `REVIEW:` in-place via `sed -i 's/^FEEDBACK:/REVIEW:/' <files>` and commit that as a separate "rfc(content): migrate live FEEDBACK markers to REVIEW" commit before proceeding.

7. **The README workflow diagram's column alignment is fragile.** Step 17 includes explicit guidance on preserving the column count (replace 18-char `/rfc-read-feedback` with 17-char `/rfc-read-reviews` plus one extra trailing space). A diff-mode review may flag the trailing space; the implementer should leave it because the diagram is decorative and its readability depends on alignment.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-12-post-approval-discretionary-revisions.md`** (`Approved`, not yet implemented) — overlaps with this RFC at `skills/rfc-implement/SKILL.md` Step 3 ("Check for ambiguity") at lines 44-46. The Approved RFC rewrites the same lines to scope the scanner to the `## Implementation spec` section only and to update the unresolved-items message text. This RFC's Step 3 changes the skill name referenced in that message from `/rfc-reviews` to `/rfc-read-reviews`. Either RFC can land first; the merge resolution is described in Risks point 1. The two RFCs are conceptually independent — one is about *what to scan*, this one is about *what skill to point users at after a failed scan and what to call the human-comment skill*.

- **`docs/rfcs/2026-05-14-skill-helper-scripts.md`** (`Draft`) — overlaps with this RFC at `scripts/rfc-feedback-list.sh` (which the helper-scripts RFC introduces) and at `skills/rfc-read-feedback/SKILL.md` (which the helper-scripts RFC modifies to delegate to the script). This RFC handles the helper-scripts RFC's marker and skill-name references in-place inside the Draft RFC's body (Step 20). The merge resolution if the helper-scripts RFC is implemented before this RFC is described in Risks point 2.

- **No other RFC dependencies.** The remaining files this RFC modifies (the two `rfc-process.md` files, the two `CLAUDE.md` files, the README, the CHANGELOG, the four agent files, the four other skill bodies, and `docs/agent-audit-criteria.md`) are not the subject of any in-flight RFC.
