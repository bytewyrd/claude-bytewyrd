---
rfc: "2026-05-12-unify-best-practices-destinations"
title: "Unify Destination of /best-practices-record and /best-practices-extract"
author: "Rodrigo Kochenburger"
status: "Done"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Keep the two-destination model — project-local `docs/BEST_PRACTICES.md` for everything that comes out of a live session, global `~/.claude/BEST_PRACTICES.md` for cross-project lessons the user records deliberately — but make the rationale **explicit** at every touch point, and close the one gap that makes the split feel arbitrary: a generalizable insight surfaced by `/best-practices-extract` mid-session cannot reach the global pool without the user reciting it again to `/best-practices-record`. Three concrete changes resolve this. First, `/best-practices-extract` gains a bulk-checkbox Promotion Step: every generalizable entry the user approved becomes one row in a single `AskUserQuestion` checkbox prompt, with each row's default pre-selected by the agent from the portability triage (broadly generalizable → checked; narrowly generalizable → unchecked). The user audits the recommendations, flips any boxes they disagree with, and confirms once — no per-entry round-trips, no second skill invocation. Second, a short "Where do entries live, and why?" header is added to `docs/BEST_PRACTICES.md`, `~/.claude/BEST_PRACTICES.md`, and the three skill files so the model is documented in the files themselves, not just in this RFC. Third, `/best-practices-record`'s Confirmation Step is aligned with the same UI primitive (one-row checkbox with the same triage-determined default) so the two entry paths into the global pool feel like the same dialog. `/best-practices-sync` is unchanged. The result: each destination has a clearly justified scope, the promotion path is a single batched confirmation instead of a separate skill invocation, and the conceptual model is visible to any reader of any of the three best-practices files.

## Should we do this?

**Yes, and the scope is small.** The braindump frames the current split as "an inconsistency that splits the same conceptual data across two destinations with no clear rationale." The rationale exists — extract is per-session and high-velocity (project file), record is deliberate and cross-project (global file), sync is curated and bootstrap-ready (plugin file) — but it is encoded only in the implementation-spec sections of the prior RFC (`2026-05-09-best-practices-content-and-tooling`) and the triage-and-lift RFC (`2026-05-10-best-practice-extraction-principles`). A user looking at the two files side by side has no on-page reason to expect the asymmetry. That is the actual defect the braindump names — not the destinations themselves but the missing documentation and the missing in-flow promotion path.

Unifying to a single file (the alternative model) would either lose the cross-project pool's distinct quality bar (every project-local entry contaminates the global pool) or lose the project-local pool's value (project-specific entries never reach project files at all). Both regressions are worse than the current split. The fix is to make the split intentional and frictionless, not to flatten it.

The change touches three skill files and two best-practices files. No new skills are created; no skills are renamed; no plugin manifest entries change. The implementation is small enough to land in one focused session.

## Current state

Three skills handle best-practice capture today (post-RFC `2026-05-10-best-practice-extraction-principles`):

| Skill | Scope | Source | Target | Path of skill file |
|---|---|---|---|---|
| `/best-practices-extract` | Per-session | Conversation history | `docs/BEST_PRACTICES.md` (project) | `skills/best-practices-extract/SKILL.md` |
| `/best-practices-record` | Cross-project | User-supplied sentence | `~/.claude/BEST_PRACTICES.md` (global) | `skills/best-practices-record/SKILL.md` |
| `/best-practices-sync` | Plugin maintenance | `~/.claude/BEST_PRACTICES.md` | `skills/sync/SKILL.md` (bootstrap content) | `.claude/skills/best-practices-sync/SKILL.md` (plugin-local, not exported) |

A shared procedure file (`skills/best-practices-extract/TRIAGE-AND-LIFT.md`) defines the three portability questions and the two-pass + verification lift that all three skills apply before writing.

The destinations have distinct, justified scopes:

- `docs/BEST_PRACTICES.md` — per-project accumulator. Thematic sections (`## Testing`, `## Architecture`, `## Documentation`, `## Security`, `## Error Handling`, `## Workflow`, `## Pitfall`, `## Claude Code`, language/stack sections) hold generalizable entries extracted from this project's sessions. `## Project-Specific` holds the non-portable entries that survive in this file alone — they are not promoted, by design.
- `~/.claude/BEST_PRACTICES.md` — global cross-project pool. Holds only generalizable entries the user has deliberately recorded as candidates for shipping in bootstrap content. Same section structure as the project file, minus `## Project-Specific` (which has no global meaning).
- `skills/sync/SKILL.md` — distributed bootstrap content. What freshly-bootstrapped projects receive in their starter `docs/BEST_PRACTICES.md`. Entries arrive here from the global pool via `/best-practices-sync`, which lifts and dedupes once more.

The flow is:

```
session → extract → docs/BEST_PRACTICES.md (project, thematic OR ## Project-Specific)
                                ↓
                            (no automated path — user must re-state via record)
                                ↓
user statement → record → ~/.claude/BEST_PRACTICES.md (global)
                                ↓
                            sync (manual, inside plugin checkout)
                                ↓
                        skills/sync/SKILL.md (bootstrap content)
                                ↓
                            new project /sync → docs/BEST_PRACTICES.md (project, pre-populated)
```

The asymmetry the braindump flags is real and lives in two places:

**Defect 1 — silent promotion path.** When `/best-practices-extract` surfaces a generalizable entry (one that passed the three portability questions and was lifted), the entry is written *only* to the project file. To get the same insight into the global pool, the user has to switch contexts, invoke `/best-practices-record`, retype or paste the entry, walk through triage and lift again (even though `extract` already did exactly that), and approve. The duplication is not preserved-on-purpose — it is friction that loses entries. In practice the user either does not promote (the entry stays project-local and dies with the project) or promotes inconsistently (some entries make the jump, others do not, based on whether the user remembered).

**Defect 2 — invisible rationale.** A reader opening `docs/BEST_PRACTICES.md` and `~/.claude/BEST_PRACTICES.md` side by side sees two files with overlapping section names, similar entry formats, and no on-page explanation of which is which or how an entry moves between them. The model only exists in the RFCs and the skill-file descriptions. The bootstrapped intro line is "Use `/best-practices-extract` at the end of a session to add new entries." — it does not explain what the file is for or how it relates to the global file. The global file's header reads "Cross-project accumulator. Entries here are candidates for promotion into the bytewyrd plugin's sync content via `/best-practices-sync`." — it explains the path out, not the path in or its relationship to the project file.

What is *not* a defect:

- `/best-practices-extract` writes to the project file only. This is correct — extraction is per-session, often produces project-specific entries that have no global meaning, and the global pool's quality bar is explicitly stricter than the project pool's. Letting extract write to the global pool directly would either dilute the global pool or require every extracted entry to go through the same "is this really cross-project?" gate twice (once at extract time, once at promote time) — Defect 1's promotion prompt is the right place for that decision.
- `/best-practices-record` exists as a separate skill. It serves a different use case: the user has a fully-formed principle in mind and wants to write it directly to the global pool, without it being attached to a session. Removing it would force every cross-project recording to go through a fake "session" first.
- The `## Project-Specific` section exists in the project file but not the global file. This is correct — `Project-Specific` is the destination for entries that failed triage; no triage-failed entry has any business in the global pool, so the section has no global equivalent.

## Analysis / Options

The braindump asks the central question directly: "what belongs project-local vs. cross-project, how does an entry get promoted, and does `/best-practices-extract` need a global-write variant for stack-level lessons surfaced mid-session." Three coherent models answer it.

### Decision 1 — Unify vs. preserve the split

**Option A — Preserve the two-file split, document the rationale on-page, and add a bulk-checkbox promotion step to `extract` (recommended).**
The split is justified by distinct quality bars (project-local accepts project-specific entries; global rejects them) and distinct sources (extract reads sessions; record reads user statements). The defect is friction in the cross-file move and lack of on-page rationale. Fixing those preserves the model's benefits and removes its costs. Implementation cost: small (three skill files, two best-practices files; no new skills, no manifest changes).

**Option B — Unify to a single file with intra-file scoping markers.**
Drop `~/.claude/BEST_PRACTICES.md`; keep only the project files and one designated "global" project file under `~/.claude/`. Within that file, use section headers or inline markers to distinguish global-eligible from project-only entries. This actually keeps two scopes — it just hides them in one file. The pull-in convenience (one file to grep) is real but small; the regression is that the scope distinction becomes a convention humans must enforce, instead of an enforcement boundary the file system makes explicit. `/best-practices-sync` (which today reads `~/.claude/BEST_PRACTICES.md` and writes `skills/sync/SKILL.md`) would need to learn to parse the markers, and re-triage at promotion time has more leakage paths.

**Option C — Unify to the global file alone; eliminate the project file entirely.**
Every extracted learning goes to the global pool. Project-specific entries either lose their project context (the lift step rewrites them to portable form, and project-specific reality is lost) or pollute the global pool with project names. This is the model the triage-and-lift RFC explicitly rejected by creating the `## Project-Specific` section. Repeating that rejection here.

**Recommendation: Option A.** The model is sound; the defects are documentation and friction, both of which Option A addresses without restructuring the storage layer. Option B trades file-level enforcement for a documentation convention and gains very little. Option C is regression on the triage-and-lift RFC.

### Decision 2 — How `/best-practices-extract` promotes to the global pool

**Option A — Bulk checkbox list with agent-determined per-entry defaults (recommended).**
After the user approves the set of entries that will be written to the project file, the skill presents a single bulk-prompt step (one `AskUserQuestion` with `multiSelect: true`) listing every *generalizable* entry as a checkbox row. Each checkbox carries a pre-applied default determined by the agent from the same triage data that surfaced the entry — the agent re-runs the three portability questions (framework / project / audience) against the lifted entry and uses the confidence of the answers to set the default:

- **Broadly generalizable** (passes all three portability questions with high confidence, would fit any tech stack the user touches) → checkbox defaulted to **checked** ("recommend global").
- **Narrowly generalizable** (passes triage but is bound to a specific stack, language, or workflow the user uses only sometimes) → checkbox defaulted to **unchecked** ("recommend project-local").

Entries triaged as `## Project-Specific` are not shown in the checkbox list at all (they are not eligible for promotion). The user reviews the pre-checked set, flips any boxes they disagree with, and confirms once for the entire batch. The result is per-entry granularity (every checkbox is independent) plus single-step UX (one confirmation, not N prompts). The defaults are recommendations, not enforcement — the user has the final say on each box.

The prompt happens **after** the User Confirmation step but **before** any file writes. File writes proceed project-first, then global-second for the boxes the user left or marked checked. The two writes are independent — if the global write fails, the project-file write stands and the user is told to re-run `/best-practices-record` for the affected entries.

**Option B — In-line per-entry sequential promotion prompt (one `AskUserQuestion` per entry).**
Same per-entry granularity as Option A but presented as a sequence of N prompts ("Promote entry 1? (y/N)" → "Promote entry 2? (y/N)" → ...) rather than a single bulk checkbox list. Loses the "review at a glance" UX of the checkbox grid and adds N round-trips for a session producing N generalizable entries. The agent could still set per-prompt defaults from triage, but with no bulk view the user cannot see the recommendation pattern across entries (e.g., "the agent recommends checking 3 of 4 — that matches my intuition").

**Option C — Bulk yes/no for the batch (single `AskUserQuestion` with no per-entry granularity).**
Simpler prompt (single yes/no for the whole batch) but the user can only accept-all or reject-all. Users who want 2 of 3 generalizable entries promoted have to accept all 3 and live with one over-promoted entry, or reject all 3 and re-run `/best-practices-record` for the 2 they wanted. Loses per-entry granularity. This option is superseded by Option A, which gives both bulk UX *and* per-entry granularity.

**Option D — Auto-promote every generalizable entry without asking.**
Removes the cross-project quality gate. Any entry that passes the three portability questions for the project file is by definition portable in principle, but "portable" and "should ship to every future project" are different bars — the global file's role is exactly to be the curation queue between them. Auto-promoting collapses that gap.

**Option E — Keep promotion strictly manual via `/best-practices-record`.**
Status quo. Defect 1 (silent promotion path) persists; users either over-promote (paste every entry) or under-promote (never paste anything).

**Recommendation: Option A.** Bulk checkbox with agent-determined defaults is the strict improvement over Option B's sequential prompts: it preserves per-entry granularity (each checkbox is independent), adds a "review at a glance" view of the whole batch, and reduces N user interactions to 1. The agent-set defaults turn the user's job from "answer N yes/no questions from scratch" into "audit and adjust a recommendation" — cheaper cognitively and more accurate (the triage that already happened informs the default; the user only intervenes when their judgement diverges from the agent's). Options C, D, and E are rejected for the same reasons they were before: C loses granularity, D removes the bar, E is the status quo defect.

### Decision 3 — How the rationale is documented on-page

**Option A — A short "Where do entries live, and why?" header in both BP files plus a one-line scope reminder in each skill description (recommended).**
The project file gains a 4-to-6-line header explaining: this file is per-project; cross-project lessons go to `~/.claude/BEST_PRACTICES.md` via the promotion prompt in `/best-practices-extract` or directly via `/best-practices-record`; `## Project-Specific` is the destination for entries that failed the portability triage. The global file gains a mirror header explaining: this file is the cross-project pool; entries arrive via either path; they leave via `/best-practices-sync` (which promotes the vetted subset into the plugin's bootstrap content). The skill files' `description:` frontmatter is tweaked so a user calling `/help` sees the destination in the first sentence.

**Option B — A single shared `docs/best-practices-model.md` referenced from both files.**
Indirection. A reader of `BEST_PRACTICES.md` has to follow a link to learn what the file is. The header in Option A is short enough to live in the file itself.

**Option C — No on-page documentation; rely on skill descriptions and RFC history.**
Status quo for the BP files. Defect 2 persists.

**Recommendation: Option A.** Short, on-page, mirrored across both files. The header costs less than 200 bytes per file and self-documents the model for any reader who happens to open the file. Option B's indirection adds friction for no gain — the header is short enough that no separate document is needed.

### Decision 4 — Should there be a "global-write" variant of `/best-practices-extract`?

The braindump asks this directly. The answer is no — Option A in Decision 2 (bulk-checkbox promotion with agent-determined defaults) covers the stack-level-lesson-surfaced-mid-session case exactly. A "global-write variant" would either be a duplicate of `extract` with one bit flipped (high duplication for low value) or a parameter on `extract` (e.g., `/best-practices-extract --global`) that bypasses the project file. The latter is wrong: stack-level lessons surfaced mid-session are still per-session artifacts, and the project file is the right local record of "here is what this session noticed about Rust async cancellation safety" — promotion to the global pool is an additional cross-project assertion, not a replacement for the project-local record.

The bulk-checkbox Promotion Step achieves the same end without forking the skill: the entry is recorded in the project file (where it documents what this session learned) *and* in the global file (where it joins the queue for future bootstrap shipping). Both files have the entry; both files have a reason to.

## Drawbacks

- **The promotion prompt adds one batch interaction per session that produces generalizable entries.** For a session that produces five generalizable extracts, that is one bulk-checkbox step containing five rows. Mitigation, part 1: the prompt is a single `AskUserQuestion` with all generalizable entries shown together — the user reviews and confirms once, not five times. Mitigation, part 2: the agent pre-applies per-row defaults from the same triage signals that surfaced each entry (broadly generalizable → checked; narrowly generalizable → unchecked), so the user's job is "audit and adjust the recommendation" rather than "answer N questions from scratch." Mitigation, part 3: in practice the number of generalizable entries per session is bounded by `best-practices-extract`'s own red flag ("You're about to write more than 2 generalizable items from one session → you're being too permissive at the triage step"). The expected cost is one short bulk prompt per session.

- **Promotion still requires a user confirmation and could be skipped.** A user who unchecks every box (or accepts a batch of all-unchecked defaults) loses the same entries today's manual flow loses. Mitigation: this is the right behaviour. The cross-project bar should be a deliberate choice, not an automatic write — Option D in Decision 2 was rejected for exactly this reason. The defect being fixed is *friction* (forcing a separate skill invocation), not *the existence of a choice*. A user who consistently unchecks every box is making a consistent choice; that is observable in their global file's empty state and can be corrected by changing the choice on the next session, not by removing the confirmation.

- **The "Where do entries live, and why?" header adds boilerplate to both BP files.** Boilerplate at the top of a file is, by default, noise readers skim past. Mitigation, part 1: the header is short (4-6 lines) and answers a question the reader actively has the first time they encounter the file. Mitigation, part 2: the header is only added once, not per-entry — it is a one-time cost amortized across every future read of the file. Mitigation, part 3: the header is placed *after* the H1 and *before* the first section heading, where existing intro text already lives (the project file currently has "Accumulated non-obvious learnings from development sessions." in that slot, which the new header replaces and expands).

- **The promotion path inside `extract` reuses the triage signals to recommend defaults — it does not skip triage.** A reader of the previous draft might have worried that the in-line promotion prompt bypasses the triage-and-lift dialog that `/best-practices-record` runs. It does not. The agent re-runs the three portability questions (framework / project / audience) against each generalizable entry at promotion time and uses the confidence of the answers to set the checkbox default: broadly generalizable entries (high confidence on all three questions) default to **checked**; narrowly generalizable entries (passed triage but bound to a stack the user touches only sometimes) default to **unchecked**. The user retains final say on every box, but the triage informs the recommendation. Same triage, two roles: at extraction time it decides the destination section (`## Architecture` vs. `## Project-Specific`); at promotion time it decides the recommended default. The defense-in-depth path (`/best-practices-sync`'s Step 2a re-triage) is unchanged and remains the final filter before bootstrap shipping.

- **Triage-and-confirmation UX is consistent across `extract` and `record`.** The same "triage recommends, user confirms" pattern applies to `/best-practices-record` after this RFC. When a user records a single entry from scratch, the skill runs the three portability questions to determine whether the entry belongs in the global pool (the existing triage behavior is unchanged), but the confirmation step now mirrors the bulk-checkbox UX used in `extract` — a one-row checkbox showing the entry with the agent's recommended default (checked for broadly generalizable, unchecked for narrowly generalizable). The user confirms once. This keeps the two entry paths into the global pool feeling like the same dialog, just one row vs. many. Implementation detail in Step 2 below.

- **Two atomic writes (project file, then global file) can fail independently.** If the project write succeeds and the global write fails (disk full, permission error, race), the session ends with a partial result. Mitigation: the order is project-first, global-second, and the user is told explicitly when the global write fails ("Failed to write to ~/.claude/BEST_PRACTICES.md: <error>. The project-file write succeeded. Re-run `/best-practices-record` for the affected entries: <list>."). The reverse ordering (global-first, project-second) is wrong — a successful global write with a failed project write would leave the entry promoted but unrecorded in its source project, which is worse than the converse.

- **The on-page header could drift from the implementation if the model changes.** A future RFC that adds a fourth file (say, a team-scoped pool) needs to update three places: the project header, the global header, and the skill descriptions. Mitigation: this is true of any on-page documentation. The header is short enough that a future RFC's "update the headers" step is one line in the implementation spec. The cost of mild drift risk is far smaller than the cost of permanent invisible rationale (the status quo).

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/best-practices-extract/SKILL.md` | Add a "Promotion Step" between "User Confirmation" and "Write Format" that presents every generalizable entry in one bulk-checkbox `AskUserQuestion` with agent-determined per-row defaults (checked for broadly generalizable, unchecked for narrowly generalizable). Update the description: frontmatter to reflect the destination(s). Add a one-line scope reminder to the Overview. |
| Modify | `skills/best-practices-record/SKILL.md` | Add a one-line note in the Overview that clarifies when to use this skill vs. the bulk-checkbox promotion in `/best-practices-extract`. Replace the Confirmation Step's free-form prompt with a one-row `AskUserQuestion` checkbox that mirrors `extract`'s Promotion Step UX (same `AskUserQuestion` primitive, same triage-determined default). Description frontmatter unchanged. |
| Modify | `.claude/skills/best-practices-sync/SKILL.md` | No behavior change. Add a one-line reference in the Overview to the rationale header in `~/.claude/BEST_PRACTICES.md`. |
| Modify | `skills/sync/SKILL.md` | Update the starter `docs/BEST_PRACTICES.md` template so newly-bootstrapped projects ship with the rationale header at the top of the file. Bump the bootstrap content version marker. |
| Modify | `docs/BEST_PRACTICES.md` (this repo's own file) | Replace the existing 3-line intro with the new rationale header. No retroactive changes to existing entries. |

There is no global `~/.claude/BEST_PRACTICES.md` write step in this RFC's implementation — the file is private to each user, and any user's existing file is updated the next time they invoke `/best-practices-record` (which, per Step 3 below, learns to write the rationale header into the file's bootstrap block when the file is created or when the header is missing).

### Steps

#### Step 1 — Update `skills/best-practices-extract/SKILL.md`

Two changes: insert a new "Promotion Step" section, update the Overview, update the description frontmatter.

**Update the frontmatter description (line 3) from:**

```markdown
description: Use when a session contained design decisions, architectural choices, discovered pitfalls, or established patterns worth preserving — triggered automatically before compaction, manually at any time, or at the end of a development branch.
```

**to:**

```markdown
description: Use at the end of a meaningful session to extract non-obvious learnings into the project's docs/BEST_PRACTICES.md. Generalizable entries can optionally be promoted to the global cross-project pool (~/.claude/BEST_PRACTICES.md) via a single bulk-checkbox prompt in the same approval flow — the agent pre-selects defaults from portability triage and the user confirms or adjusts in one step. Project-specific entries stay project-local under ## Project-Specific.
```

**Update the Overview section (currently lines 9–11) from:**

```markdown
## Overview

Selectively extract non-obvious learnings from a session and append them to the project's
`BEST_PRACTICES.md`. Quality over quantity — the value is in the filter, not the writing.
```

**to:**

```markdown
## Overview

Selectively extract non-obvious learnings from a session and append them to the project's
`docs/BEST_PRACTICES.md`. Quality over quantity — the value is in the filter, not the writing.

**Two destinations, one flow.** Generalizable entries land in a thematic section of the project file
(`## Architecture`, `## Testing`, etc.) and — for every entry the user leaves checked in the bulk
Promotion Step — are also written to the cross-project pool at `~/.claude/BEST_PRACTICES.md`. The
agent pre-selects each checkbox based on portability triage (broadly generalizable → checked;
narrowly generalizable → unchecked); the user audits and confirms once for the whole batch.
Project-specific entries land in the project file's `## Project-Specific` section, are not shown
in the checkbox list, and never reach the global pool. See the "Where do entries live, and why?"
header at the top of either `BEST_PRACTICES.md` file for the full model.
```

**Insert a new "Promotion Step" section immediately after "User Confirmation (Always Required)" (which currently ends with the paragraph "To promote a generalizable entry to the *global* file (`~/.claude/BEST_PRACTICES.md`), the user invokes `/best-practices-record` separately — `best-practices-extract` writes only to the project file. This separation is intentional: extraction is high-velocity and per-session; recording into the global pool is a deliberate cross-project decision."):**

Replace that closing paragraph (the one that says "the user invokes `/best-practices-record` separately") with this new section:

````markdown
## Promotion Step (Generalizable Entries Only)

After the User Confirmation step, before any file writes, present **one** bulk-checkbox prompt
that lists every entry the user approved that was *also* triaged as **generalizable** (not
`## Project-Specific`). The user reviews the entire batch in a single view, flips any checkbox
they disagree with, and confirms once. File writes then proceed project-first, global-second
for every entry that ends up checked.

### Determining the per-entry default (agent does this before showing the prompt)

For each generalizable entry, re-run the three portability questions defined in
`TRIAGE-AND-LIFT.md` against the *lifted* text (the same text that will be written to the
project file):

1. **Framework portability** — does this principle apply across language/framework choices, or
   only inside one specific ecosystem?
2. **Project portability** — does this principle apply to any project, or only to projects of a
   specific type, scale, or domain?
3. **Audience portability** — does this principle apply to any engineer reading it, or only to
   engineers with project-specific context?

Translate the answers into a confidence score and a default:

- **All three questions answered "yes" with high confidence** → the entry is *broadly
  generalizable* (would fit any tech stack the user is likely to touch) → default the checkbox
  to **checked** with the recommendation tag `[recommended: global]`.
- **Triage passed (the entry is in the generalizable bucket) but at least one portability
  question landed with lower confidence — e.g., the entry is bound to a specific stack, language,
  or workflow the user uses only sometimes** → the entry is *narrowly generalizable* → default
  the checkbox to **unchecked** with the recommendation tag `[recommended: project-local]`.

The defaults are recommendations, not enforcement. The user retains final say on every box.

### Presenting the bulk checkbox prompt

Issue a single `AskUserQuestion` call with `multiSelect: true`. Each row is one generalizable
entry; the row's pre-selected state reflects the default the agent computed above. Example shape
of the rendered prompt (the literal wording is illustrative — what matters is the structure):

```
Promote which entries to the global pool (~/.claude/BEST_PRACTICES.md)?

The agent has pre-checked entries it recommends for the global pool based on portability triage.
Adjust as needed; you can leave the defaults as-is or change individual boxes.

[x] [Architecture] Subsystem boundaries own their domain assembly; configuration layers only
    resolve and forward inputs.  [recommended: global]

[x] [Testing] Treat flaky tests as production bugs — investigate root cause before retrying.
    [recommended: global]

[ ] [Workflow] Prefer one-tab terminals for SvelteKit dev so HMR reloads cleanly.
    [recommended: project-local]
```

If there is exactly one generalizable entry to promote, the prompt is still issued (one-row
checkbox); the bulk format collapses gracefully to a single row.

If there are zero generalizable entries to promote (the entire approved set is `## Project-
Specific`), skip the Promotion Step entirely.

### Writing the entries

For every row the user confirmed checked, write the entry to *both* the project file (the
already-planned write) and `~/.claude/BEST_PRACTICES.md`. Write order is project-first,
global-second across the whole batch:

1. Write all approved entries (regardless of promotion state) to `docs/BEST_PRACTICES.md` in
   their respective destination sections.
2. After the project-file write succeeds, write each promoted entry (same date, same lifted
   text, same canonical category label) to `~/.claude/BEST_PRACTICES.md` in the matching section.

If the global write fails, report the error to the user with this exact message:

```
Wrote N entries to docs/BEST_PRACTICES.md (succeeded).
Failed to write M entries to ~/.claude/BEST_PRACTICES.md: <error>.

The project file is up to date. Re-run /best-practices-record for the affected entries:
  - <entry 1>
  - <entry 2>
  ...
```

The reverse ordering (global-first, project-second) is wrong — a successful global write paired
with a failed project write would leave the entry promoted but unrecorded in its source project.

### Project-specific entries

Entries triaged as `## Project-Specific` do not appear in the checkbox list. They are not
eligible for promotion (the global pool admits only generalizable entries — see
`TRIAGE-AND-LIFT.md`).

### Global file bootstrap

If `~/.claude/BEST_PRACTICES.md` does not exist, create it with the header block defined in
`skills/best-practices-record/SKILL.md`'s "File Bootstrap" section. If the file exists but
lacks the "Where do entries live, and why?" rationale block (a one-time backfill for users
whose global file was created before this RFC), prepend the rationale block after the existing
H1 and before the first section header. Do not modify any existing entries.

### Non-interactive invocations (e.g., auto-triggered by a PreCompact hook)

If no interactive user is present when the skill runs, skip the bulk checkbox prompt entirely
and treat every row as unchecked. The project-file write proceeds normally; no entry is
promoted to the global pool. This ensures auto-extraction never blocks on user input. The user
can manually promote any auto-extracted entry in a later interactive session via the promotion
prompt (on the next manual `/best-practices-extract` run) or directly via
`/best-practices-record`.

### After the fact

To promote a generalizable entry to the global pool after the fact (e.g., the user unchecked the
box during this flow and changed their mind later), invoke `/best-practices-record` separately —
that skill remains the canonical path for any standalone "I want to write a cross-project entry
from scratch" use case, and it is also the recovery path for entries the bulk checkbox missed
or that failed the global write.
````

**Update the User Confirmation display header.** The current User Confirmation section labels
GENERALIZABLE entries as `GENERALIZABLE → ~/.claude/BEST_PRACTICES.md (eligible) and docs/BEST_PRACTICES.md (this project)`.
After this RFC the global file is opt-in (selected per-row in the bulk checkbox prompt), not automatic, and the listing order should reflect
project-first. Replace that label line with:

```
GENERALIZABLE → docs/BEST_PRACTICES.md (this project) [+ optional: ~/.claude/BEST_PRACTICES.md via Promotion Step]
```

This update happens inside the User Confirmation section's display example block (the line
currently reading `GENERALIZABLE → ~/.claude/BEST_PRACTICES.md (eligible) and docs/...`).

The remainder of the SKILL.md (Write Format, Post-Write Check, When to Run, Red Flags) is unchanged.

**Add one Red Flag to the existing "Red Flags — Stop and Reconsider" section** (currently the last section of the file). Append this bullet to the existing list:

```markdown
- You're about to leave every checkbox checked when the agent recommended only some → the global bar is stricter than the project bar. The agent's pre-checked defaults reflect triage confidence; if you find yourself overriding most defaults to "promote everything," your triage was permissive. Default to trusting the agent's recommendation and only flip boxes where your judgement diverges.
```

#### Step 2 — Update `skills/best-practices-record/SKILL.md`

Two changes: clarify in the Overview when to use `/best-practices-record` vs. the new in-line promotion in `/best-practices-extract`, and align the Confirmation Step UX with the bulk-checkbox pattern used in `extract`.

**Replace the Overview section (currently lines 8–19, which includes the intro paragraph, the
comparison table, and the guide sentence) — which reads:**

```markdown
## Overview

Append a single, user-confirmed best-practice entry to the **global** `~/.claude/BEST_PRACTICES.md`. This file is the cross-project pool — it accumulates lessons that future projects should ship with from day one. Entries from here are reviewed and pulled into the plugin's `sync/SKILL.md` via `/best-practices-sync`; once promoted, they are removed from the global file by the sync skill.

This is the counterpart to `/best-practices-extract`:

| Skill | Scope | Source | Target |
|---|---|---|---|
| `/best-practices-extract` | Project-specific | Current session | `docs/BEST_PRACTICES.md` (in the project) |
| `/best-practices-record` | Cross-project | User-supplied statement | `~/.claude/BEST_PRACTICES.md` (global) |

If the rule describes how a single project is built, prefer `/best-practices-extract`. If the rule describes how a *technology, stack, or engineering practice* should be applied — and would be true for any future project using that stack — use this skill.
```

The new "When to use this skill" block below supersedes the role of the existing comparison table
and guide sentence above, so the entire Overview section is replaced — not just the first paragraph.

**with:**

```markdown
## Overview

Append a single, user-confirmed best-practice entry to the **global** `~/.claude/BEST_PRACTICES.md`. This file is the cross-project pool — it accumulates lessons that future projects should ship with from day one. Entries from here are reviewed and pulled into the plugin's `sync/SKILL.md` via `/best-practices-sync`; once promoted, they are removed from the global file by the sync skill.

**When to use this skill vs. `/best-practices-extract`:**

- **Mid-session, surfaced from work just done** → use `/best-practices-extract`. Its approval flow includes a bulk-checkbox Promotion Step that presents every generalizable entry with an agent-recommended default (checked for broadly generalizable, unchecked for narrowly generalizable). Confirming the batch writes the checked entries to both `docs/BEST_PRACTICES.md` and `~/.claude/BEST_PRACTICES.md` in one pass.
- **Stated from scratch, not anchored to a session** → use this skill. Pattern recognized after the fact ("I keep seeing the same testing mistake across projects"), a stack-level lesson you want to record without a project session as its anchor, or a recovery path for an entry the bulk checkbox in `/best-practices-extract` missed or failed to write.

Both skills run the same triage-and-lift procedure (see `../best-practices-extract/TRIAGE-AND-LIFT.md`), so the resulting entry has the same quality bar regardless of which path produced it. The confirmation UX is also aligned: in `record` the user confirms a one-row checkbox; in `extract` the user confirms a multi-row checkbox. Both surface the agent's recommendation (checked vs. unchecked) based on the triage result.
```

**Align the Confirmation Step with the bulk-checkbox UX used in `extract`.** The existing
Confirmation Step in `best-practices-record/SKILL.md` walks the user through a free-form
confirmation of the lifted entry. After this RFC the confirmation is issued via the same
`AskUserQuestion` pattern as the Promotion Step in `extract`, but with a single row (since
`record` operates on one entry at a time). The structure:

- The agent runs the three portability questions against the lifted entry (existing Triage Step
  behavior — unchanged).
- The agent computes a *default* from the triage confidence:
  - All three portability questions high-confidence "yes" → default the checkbox to **checked**
    with tag `[recommended: record to global pool]`.
  - At least one portability question lower-confidence → default the checkbox to **unchecked**
    with tag `[recommended: reconsider — entry may not transfer cleanly]`.
- The agent issues one `AskUserQuestion` with `multiSelect: true` and a single row showing the
  entry and its recommendation tag. The user either accepts the recommendation (single confirm)
  or flips the box.
- If the user confirms the box checked, write to `~/.claude/BEST_PRACTICES.md` as today.
- If the user confirms the box unchecked, abort the write and report the entry was not recorded
  (with a one-line hint suggesting the entry may belong in a project's `docs/BEST_PRACTICES.md`
  via `/best-practices-extract` instead).

This mirrors `extract`'s Promotion Step exactly — same UI primitive (`AskUserQuestion` with
`multiSelect: true`), same default-from-triage logic, same "user has final say" stance. The
only difference is row count: `record` is always one row; `extract` is N rows.

The remainder of the SKILL.md (Inputs, Triage Step, Lift Step, Categorization Step, Write
Format, File Bootstrap, Red Flags) is unchanged. The Confirmation Step's *placement* in the
flow (after Categorization, before Write) is unchanged; only its UI primitive and the
agent-recommendation tag are new.

**Update the "File Bootstrap" section** to include the new rationale header. The existing section currently reads:

````markdown
## File Bootstrap

If `~/.claude/BEST_PRACTICES.md` does not exist, create it with this header before appending:

```markdown
# Global Best Practices

Cross-project accumulator. Entries here are candidates for promotion into the bytewyrd plugin's sync content via `/best-practices-sync`. Once promoted, sync removes them from this file.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```

If the target section header (`## <Category>`) does not exist, append it (with a blank line before) before writing the entry.
````

**Replace the fenced header block** with the new rationale-bearing version:

````markdown
## File Bootstrap

If `~/.claude/BEST_PRACTICES.md` does not exist, create it with this header before appending:

```markdown
# Global Best Practices

## Where do entries live, and why?

This file is the **global cross-project pool**. It accumulates engineering principles that should
ship with every future project — captured deliberately (via `/best-practices-record`) or promoted
from a project's `docs/BEST_PRACTICES.md` (via the per-entry promotion prompt in
`/best-practices-extract`). The quality bar here is intentionally higher than any project file's:
every entry must have passed the three portability questions (framework / project / audience)
defined in the shared `TRIAGE-AND-LIFT.md` procedure.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `~/.claude/BEST_PRACTICES.md` (this file) | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into `skills/sync/SKILL.md` |
| `<project>/docs/BEST_PRACTICES.md` | Per-project | Session extraction | Generalizable entries may be promoted here via `/best-practices-extract`'s prompt |
| `skills/sync/SKILL.md` (bootstrap content) | Distributed | `/best-practices-sync` from this file | Renders into every new project's starter `docs/BEST_PRACTICES.md` at `/sync` time |

Project-specific entries (those that fail any portability question) never reach this file by
design — they live only in the source project's `## Project-Specific` section.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```

If the target section header (`## <Category>`) does not exist, append it (with a blank line before) before writing the entry.

**Header backfill for existing global files.** If the file exists but its top-of-file lacks the
"## Where do entries live, and why?" header (any global file created before this RFC), insert the
rationale block (everything from `## Where do entries live, and why?` through the line ending
`Format: **[YYYY-MM-DD]** _Category_...`) immediately after the existing H1 (`# Global Best
Practices` or whatever H1 the file already has) and before the first H2. Do not modify any
existing entries. Run the backfill check on every invocation — it is idempotent (the block is
either present or absent; presence skips the backfill).
````

#### Step 3 — Update `.claude/skills/best-practices-sync/SKILL.md`

No behavior change. One addition: a one-line pointer in the Overview to the rationale header that now lives in both BP files.

**Insert the following paragraph immediately after the existing first paragraph of the "## Overview" section** (the paragraph that reads "Promote entries from the user's global pool...the global file is private to the user; the plugin file is what consumers receive."). Do not remove or replace any existing text — this is a pure insertion:

```markdown
Promote entries from the user's global pool (`~/.claude/BEST_PRACTICES.md`) into this plugin's distributed sync content (`skills/sync/SKILL.md`), and then remove the promoted entries from the global pool. This is the *only* path for a global entry to reach a freshly-synced project — the global file is private to the user; the plugin file is what consumers receive.

For the full model of which file holds what and how entries move between files, see the "Where do entries live, and why?" header at the top of `~/.claude/BEST_PRACTICES.md` (or any project's `docs/BEST_PRACTICES.md` — both files carry the same rationale block).
```

All other content in this SKILL is unchanged — Step 1, Step 2, Step 2a, Step 3 (with conflict resolution), Step 4 (NEW candidates), Step 5 (write to sync file), Step 6 (remove from global), Step 7 (bump version), Step 8 (report), and Red Flags. The flow is preserved exactly.

#### Step 4 — Update `skills/sync/SKILL.md`'s starter `docs/BEST_PRACTICES.md` template

`skills/sync/SKILL.md` writes the starter `docs/BEST_PRACTICES.md` content when a project runs `/sync`. The template currently begins with this intro (around line 515 of `skills/sync/SKILL.md`):

```markdown
Use `/best-practices-extract` at the end of a session to add new entries.
```

Replace the project file template's H1-through-first-section-header block with the new rationale-bearing version. The exact content to render at the top of every newly-bootstrapped `docs/BEST_PRACTICES.md`:

````markdown
# Best Practices

<!-- bootstrap-content-version: <TODAY>-<HASH> -->

## Where do entries live, and why?

This file is the **per-project accumulator**. It holds non-obvious learnings extracted from this
project's sessions (via `/best-practices-extract`). Both *generalizable* and *project-specific*
entries live here, separated by section:

- **Thematic sections** (`## Testing`, `## Architecture`, `## Documentation`, etc.) hold
  generalizable entries — they passed the three portability questions in `TRIAGE-AND-LIFT.md`
  and could theoretically ship to any project that uses the matching stack. They are *eligible*
  for promotion to the global pool.
- **`## Project-Specific`** holds entries that failed any portability question. They are
  valuable to this project (gotchas, internal conventions, project-name-specific quirks) but
  do not transfer. They are never promoted.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `docs/BEST_PRACTICES.md` (this file) | Per-project | Session extraction | Generalizable entries may be promoted to `~/.claude/BEST_PRACTICES.md` via `/best-practices-extract`'s per-entry prompt |
| `~/.claude/BEST_PRACTICES.md` | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into bootstrap content (plugin-author only) |
| `skills/sync/SKILL.md` (bootstrap content, plugin-internal) | Distributed | `/best-practices-sync` from global pool | Renders here, in every new project's starter `docs/BEST_PRACTICES.md`, at `/sync` time |

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries. Generalizable entries
can be opted into the global pool via the per-entry prompt in that same flow.
````

The template's existing thematic sections (`## Pitfall`, `## Workflow`, `## Claude Code`, `## Architecture`, `## Testing`, `## Documentation`, `## Security`, `## Error Handling`, the conditional language and stack sections, and `## Project-Specific`) follow exactly as today — no changes to entry content.

Bump the bootstrap content version marker in `skills/sync/SKILL.md` (the `<!-- bootstrap-content-version: <YYYY-MM-DD>-<short-hash> -->` line near the top of `sync/SKILL.md` itself) so the `SessionStart` hook surfaces the new rationale block to projects whose `docs/BEST_PRACTICES.md` is on the prior version. Use today's date (`2026-05-12`) and compute the short hash from the fenced markdown blocks of the updated file.

#### Step 5 — Update this repo's own `docs/BEST_PRACTICES.md`

Replace the existing 3-line intro (currently lines 1–9 of `/home/divoxx/code/bytewyrd/claude-bytewyrd/docs/BEST_PRACTICES.md`, which read):

```markdown
# Best Practices

<!-- bootstrap-content-version: 2026-05-10-8e478c1 -->

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries.
```

with the rationale-bearing version (same content as the template in Step 4, with the version marker bumped to today's value):

````markdown
# Best Practices

<!-- bootstrap-content-version: 2026-05-12-<SHORT_HASH> -->

## Where do entries live, and why?

This file is the **per-project accumulator**. It holds non-obvious learnings extracted from this
project's sessions (via `/best-practices-extract`). Both *generalizable* and *project-specific*
entries live here, separated by section:

- **Thematic sections** (`## Testing`, `## Architecture`, `## Documentation`, etc.) hold
  generalizable entries — they passed the three portability questions in `TRIAGE-AND-LIFT.md`
  and could theoretically ship to any project that uses the matching stack. They are *eligible*
  for promotion to the global pool.
- **`## Project-Specific`** holds entries that failed any portability question. They are
  valuable to this project (gotchas, internal conventions, project-name-specific quirks) but
  do not transfer. They are never promoted.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `docs/BEST_PRACTICES.md` (this file) | Per-project | Session extraction | Generalizable entries may be promoted to `~/.claude/BEST_PRACTICES.md` via `/best-practices-extract`'s per-entry prompt |
| `~/.claude/BEST_PRACTICES.md` | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into bootstrap content (plugin-author only) |
| `skills/sync/SKILL.md` (bootstrap content, plugin-internal) | Distributed | `/best-practices-sync` from global pool | Renders here, in every new project's starter `docs/BEST_PRACTICES.md`, at `/sync` time |

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries. Generalizable entries
can be opted into the global pool via the per-entry prompt in that same flow.
````

Compute `<SHORT_HASH>` as the first 7 hex characters of the SHA-1 (or the same algorithm `sync` already uses) of the existing entry blocks (everything from `## Pitfall` onward, unchanged by this RFC). This keeps the marker meaningful for the `SessionStart` hook even though no entries themselves changed.

**Do not retroactively re-section** any existing entries. The current file has `## Refactoring`, `## Code Design`, and `## Code Style` sections that pre-date the canonical thematic list; they remain as-is. The `## Project-Specific` section (lines 98–103 today) is unchanged.

#### Step 6 — Verification

After all changes, run these checks. Expected output is the literal text shown.

1. **Promotion Step is present in `best-practices-extract`:**
   ```bash
   grep -n '^## Promotion Step' skills/best-practices-extract/SKILL.md
   ```
   Expected output: one match line.

2. **Promotion Step references project-first / global-second ordering and the recovery message:**
   ```bash
   grep -E "project-first, global-second|Failed to write M entries" skills/best-practices-extract/SKILL.md
   ```
   Expected output: two matches (one per phrase).

2b. **Promotion Step uses the bulk-checkbox `AskUserQuestion` primitive with agent-determined defaults:**
   ```bash
   grep -E "AskUserQuestion|multiSelect: true|recommended: global|recommended: project-local" skills/best-practices-extract/SKILL.md
   ```
   Expected output: at least four matches (the four phrases appear in the Promotion Step body).

3. **`/best-practices-record` Overview names both paths:**
   ```bash
   grep -E "Mid-session, surfaced from work just done|Stated from scratch, not anchored to a session" skills/best-practices-record/SKILL.md
   ```
   Expected output: two matches.

3b. **`/best-practices-record` Confirmation Step uses the same bulk-checkbox primitive (one-row form):**
   ```bash
   grep -E "AskUserQuestion|multiSelect: true|recommended: record to global pool" skills/best-practices-record/SKILL.md
   ```
   Expected output: at least three matches (the phrases appear in the aligned Confirmation Step body).

4. **Both BP files share the rationale header block:**
   ```bash
   grep -c '^## Where do entries live, and why?' docs/BEST_PRACTICES.md skills/sync/SKILL.md
   ```
   Expected output:
   ```
   docs/BEST_PRACTICES.md:1
   skills/sync/SKILL.md:1
   ```
   (One match per file — the rationale header is exactly once in each. Note: the match in
   `skills/sync/SKILL.md` is inside a template fenced block, not a top-level section of the
   sync file itself — this is correct and expected.)

4b. **Global file bootstrap block in `best-practices-record` carries the rationale header:**
   ```bash
   grep -c 'Where do entries live, and why?' skills/best-practices-record/SKILL.md
   ```
   Expected output:
   ```
   skills/best-practices-record/SKILL.md:1
   ```
   (The rationale block is present in the File Bootstrap section — this is the template for
   `~/.claude/BEST_PRACTICES.md` when created or backfilled.)

5. **Bootstrap content version marker bumped:**
   ```bash
   grep -m1 'bootstrap-content-version:' skills/sync/SKILL.md docs/BEST_PRACTICES.md
   ```
   Expected output: both markers carry today's date (`2026-05-12-...`). The hashes will differ between the two files (they are computed from each file's own content).

6. **The existing flow remains intact** — `/best-practices-record` is still invokable, still writes only to the global pool, and still applies triage and lift. The promotion prompt in `/best-practices-extract` is an *additional* path, not a replacement.
   ```bash
   grep -n '^name: best-practices-record' skills/best-practices-record/SKILL.md
   grep -n '~/.claude/BEST_PRACTICES.md' skills/best-practices-record/SKILL.md | head -3
   ```
   Expected output: skill name on a single line; at least one reference to the global file path in the body.

7. **Manual: run `/best-practices-extract` in a project session with one or more generalizable candidates.** Confirm:
   - A single bulk-checkbox Promotion Step appears after the User Confirmation step, listing every generalizable candidate as a row.
   - Each row carries an agent-determined default (checked for broadly generalizable, unchecked for narrowly generalizable) plus a visible recommendation tag.
   - Leaving a row checked at confirm time causes the entry to appear in both `docs/BEST_PRACTICES.md` and `~/.claude/BEST_PRACTICES.md`, in the same thematic section, with the same date and lifted text.
   - Unchecking a row before confirm causes that entry to appear only in `docs/BEST_PRACTICES.md`.
   - Project-specific candidates do not appear in the Promotion Step at all.
   - If the entire approved set is project-specific, the Promotion Step is skipped.

8. **Manual: run `/best-practices-extract` in a fresh shell where `~/.claude/BEST_PRACTICES.md` does not yet exist.** Confirm that leaving any row checked at the Promotion Step confirm creates the global file with the full rationale header (as defined in `skills/best-practices-record/SKILL.md`'s File Bootstrap section) and then appends the entry.

9. **Manual: run `/best-practices-extract` against a pre-existing `~/.claude/BEST_PRACTICES.md` that was created before this RFC (i.e., does not yet have the "## Where do entries live, and why?" block).** Confirm that the rationale block is back-filled into the file (inserted between the H1 and the first H2) before the entry append. Confirm existing entries are not touched.

10. **Manual: simulate a global-write failure** (e.g., make `~/.claude/BEST_PRACTICES.md` temporarily unwritable). Confirm the project-file write still succeeds and the user sees the recovery message naming the affected entries.

## Risks and open questions

- **Risk: the user accepts the agent's pre-checked defaults reflexively.** A user habituated to approving prompts may simply confirm the batch without auditing the checkboxes, ratifying every pre-checked recommendation. Mitigation, part 1: the agent's defaults are themselves derived from the triage signal — broadly generalizable entries default checked, narrowly generalizable entries default unchecked — so reflexive confirmation still respects the triage bar (it is not "accept everything," it is "accept the agent's judgement"). Mitigation, part 2: per-row recommendation tags (`[recommended: global]` vs. `[recommended: project-local]`) surface the agent's reasoning in the checkbox view, encouraging a quick review rather than blind acceptance. Mitigation, part 3: the red flag added to `best-practices-extract` ("If you find yourself overriding most defaults to 'promote everything,' your triage was permissive") surfaces the concern in the skill's own self-check. Mitigation, part 4: `/best-practices-sync`'s Step 2a re-triage remains a defense-in-depth gate before any entry leaves the global pool for bootstrap shipping.

- **Risk: the rationale header drifts between project files and the global file.** Because the header is duplicated (once in `skills/sync/SKILL.md`'s template, once in any individual `docs/BEST_PRACTICES.md`, once in `~/.claude/BEST_PRACTICES.md` via the bootstrap block in `best-practices-record/SKILL.md`), a future RFC that changes the rationale must update all three sources. Mitigation, part 1: the three sources are intentionally redundant — each file should self-document for any reader who opens it standalone. Mitigation, part 2: the `bootstrap-content-version` marker on the project file means projects falling behind get a `SessionStart` reminder to re-sync, which would refresh the header on the next bootstrap. Mitigation, part 3: a future RFC could extract the rationale block into a single source-of-truth file (analogous to `TRIAGE-AND-LIFT.md`) and have all three files reference it; out of scope here because the rationale is short enough that inline duplication is cheaper than a fourth file.

- **Risk: the project-file write and global-file write are two operations, not one transaction.** A truly atomic write would require either filesystem-level transactions (not available across users' home directories) or a temp-file + rename pattern that risks leaving inconsistent state on crash. Mitigation: the project-first ordering bounds the failure mode — the worst case is "entry in project file, not in global file," which the recovery message addresses and `/best-practices-record` can backfill. The opposite ordering would leave the entry promoted but not recorded in its source project, which is harder to recover from.

- **Open question: should `/best-practices-record` also offer a "promote *down* to a specific project" path?** A user with a fresh global entry might want it to also land in the current project's `docs/BEST_PRACTICES.md`. **Resolution within this RFC:** out of scope. The current `/best-practices-record` writes only to the global pool, by design — its quality bar is cross-project, and writing to a specific project file would re-introduce the symmetry-breaking the braindump complained about (asymmetric writes from different entry points). If demand emerges, a follow-up RFC can add a `--also-here` flag or equivalent; for now, the user can copy the entry manually after recording.

- **Open question: should the bulk-checkbox prompt offer keyboard shortcuts ("check all" / "uncheck all") for power users?** The bulk checkbox already collapses N sequential prompts into one batch confirmation, so the typical-user UX is already efficient. A "check all" shortcut would let a user who is confident every generalizable entry should be promoted skip even the audit step. **Resolution within this RFC:** out of scope. The checkbox primitive already supports per-row toggles, and the agent's default-setting reduces the audit cost to "glance and confirm" in the common case. A shortcut is a usability optimization that should be added only when demand is observed; defer until then.

- **Open question: how does this interact with `2026-05-12-auto-extract-best-practices-on-precompact`?** That RFC (Draft) explores firing `/best-practices-extract` automatically before context compaction. If extraction runs automatically, the bulk-checkbox Promotion Step would need to happen at the same time, with the user actively present at the keyboard. **Resolution within this RFC:** the Promotion Step is interactive and requires user input by design — an auto-extracted entry that has no user to confirm the bulk checkbox simply gets the unchecked default for every row, staying project-local. The auto-extract RFC may need to revisit whether promotion should be deferred to a later interactive session; that decision belongs in that RFC, not this one.

- **Note: the existing `/best-practices-sync` Step 2a re-triage handles the legacy entries case.** Any entries in `~/.claude/BEST_PRACTICES.md` written before this RFC (via the manual-only `/best-practices-record` path) are still re-triaged at sync time by Step 2a. This RFC does not change that behavior — the bulk-checkbox Promotion Step in `extract` and the aligned one-row checkbox confirmation in `record` are *additive* entry points into the global pool, with the same downstream gates as the prior manual path.

## Relationship to other RFCs

- **Builds on `2026-05-09-best-practices-content-and-tooling`** (Done). That RFC established the three-skill pipeline (`best-practices-extract`, `best-practices-record`, `best-practices-sync`), the canonical category list, the global file at `~/.claude/BEST_PRACTICES.md`, and the bootstrap content at `skills/sync/SKILL.md`. This RFC adds an in-line promotion path within `best-practices-extract` and documents the rationale on-page. The category list, file paths, and bootstrap-content-version marker are reused unchanged.

- **Builds on `2026-05-10-best-practice-extraction-principles`** (Done). That RFC introduced the shared triage-and-lift procedure (`skills/best-practices-extract/TRIAGE-AND-LIFT.md`) applied by all three skills, and added the `## Project-Specific` section to the project file. This RFC does not modify the triage-and-lift procedure or the `## Project-Specific` mechanism — generalizable entries (those that passed all three portability questions) are exactly the entries eligible for the new promotion prompt; project-specific entries are explicitly excluded.

- **Touches `2026-05-12-auto-extract-best-practices-on-precompact`** (Draft). See the open question above: if auto-extraction lands, the auto path defaults to `No` on the promotion prompt because no interactive user is present. No coordination changes are required in either RFC, but the auto-extract RFC should mention the interaction for completeness.

- **Touches `2026-05-12-drop-dates-from-best-practices`** (Draft). That RFC removes date stamps from BP entries. If it lands first, the entry format becomes `_Category_: <statement>` instead of `**[YYYY-MM-DD]** _Category_: <statement>`. The promotion path here writes the *same* format to both files, whatever that format is — the RFC ordering is commutative. If date-drop lands after this RFC, the affected lines in the new Promotion Step (and the bootstrap headers) are mechanically updated by the date-drop implementation.

- **No conflicts with open or completed RFCs.** All other RFCs in `docs/rfcs/` touch unrelated subsystems (sync interactive diff, refactor command, GitHub branch auto-delete, etc.).
