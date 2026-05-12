---
rfc: "2026-05-12-drop-dates-from-best-practices"
title: "Drop Dates from BEST_PRACTICES Entries"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Remove the `**[YYYY-MM-DD]**` date prefix from every entry in `~/.claude/BEST_PRACTICES.md`, `docs/BEST_PRACTICES.md`, and the bootstrap content emitted by `skills/sync/SKILL.md`, and update the writer skills (`best-practices-extract`, `best-practices-record`) and the promoter skill (`best-practices-sync`) to stop emitting dates. A practice's value is its content; the date it was first captured adds no signal a future reader can act on. Stale dates create a perception of staleness even when the lesson is still correct, and they leak temporal coupling into a file whose contract is *timeless engineering advice*. The new entry shape is `- _Category_: One or two sentences max.`

## Should we do this?

**Yes.** Three reasons:

1. **Signal-to-noise.** The date field carries no decision-relevant information. A reader does not ask "is this still true?" of a best-practice entry; they ask "is this advice good?". When the answer turns on the entry's age, the entry is project-specific tooling lore, not best practice, and belongs elsewhere — the triage step in `best-practices-extract` already rejects such entries.
2. **Perception of staleness.** Dates that drift backward make a reader discount the entry. A 2024 entry next to a 2026 entry reads as "the 2024 one might be outdated", even when the advice (e.g., "validate input at the boundary") is timeless. The fix is to not seed that question in the reader's mind.
3. **Cost is one-shot.** The change is mechanical: one sed pass per file plus three skill edits. The benefit compounds — every future entry is shorter, every future reader is unbothered by dates.

The work is small enough that a separate RFC is borderline, but the writer/promoter skills span three files with interlocked formats (the sync skill's normalization regex depends on the writer skills' output shape), so writing it down once is cheaper than coordinating three independent edits.

## Current state

### Format today

Every entry across the three best-practices files uses this shape:

```markdown
- **[YYYY-MM-DD]** _Category_: One or two sentences max.
```

The italic `_Category_` is the canonical abbreviated label (`_Rust_`, `_JS/TS_`, `_K8s/CUE_`, etc.). The date is the day the entry was first written.

**`~/.claude/BEST_PRACTICES.md`** — 3 dated entries today (file header also documents the format with `**[YYYY-MM-DD]**`).

**`docs/BEST_PRACTICES.md`** (this repo) — 56 dated entries today across 12 sections; file header documents the format.

**`skills/sync/SKILL.md`** — 133 lines containing `**[<TODAY>]**`. This is the bootstrap content that the `/sync` skill emits into a freshly-synced project's `docs/BEST_PRACTICES.md` after substituting `<TODAY>` with the current date.

### Where dates are emitted and substituted

| File | Date appears as | Substituted by |
|------|-----------------|----------------|
| `~/.claude/BEST_PRACTICES.md` | concrete `**[2026-05-09]**` | written at record time by `/best-practices-record` |
| `docs/BEST_PRACTICES.md` | concrete `**[2026-05-09]**` | written at extract time by `/best-practices-extract`, or rendered at sync time (`<TODAY>` → current date) by `/sync` |
| `skills/sync/SKILL.md` | placeholder `**[<TODAY>]**` | substituted at sync time by `/sync` (see Step 4.5 of that skill, line 485) |

### Where the skills emit date format

- `skills/best-practices-record/SKILL.md`:
  - Line 104: Confirmation Step shows `- **[YYYY-MM-DD]** _<header>_: <text>` to the user
  - Line 116: Write Format documents `- **[YYYY-MM-DD]** _<Category>_: One or two sentences max.`
  - Line 119: "`YYYY-MM-DD` is today's date." prose
  - Line 152: bootstrap header for a new global file documents `Format: **[YYYY-MM-DD]** _Category_: ...`
- `skills/best-practices-extract/SKILL.md`:
  - Line 104: Write Format documents `- **[YYYY-MM-DD]** _[Category]_: Concise statement. One or two sentences max.`
- `.claude/skills/best-practices-sync/SKILL.md`:
  - Lines 25–28: Normalization rule for Step 2 strips a leading `**[...]**` token before comparing entries for classification — handles both concrete-date and `<TODAY>` forms
  - Line 152: "Use the `**[<TODAY>]**` placeholder" for replaced entries (Step 5)
  - Line 156: "Use the `**[<TODAY>]**` date placeholder (not the concrete date from the global file)" for new entries (Step 5)
  - Lines 163–164: fence-structure example shows `- **[<TODAY>]** _<SectionName>_: ...`
  - Line 176: auto-created section template shows `- **[<TODAY>]** _<SectionName>_: <entry text>`
- `skills/sync/SKILL.md`:
  - Line 485: substitution rule "substituting `<TODAY>` with today's date in `YYYY-MM-DD` format"
  - Line 513: bootstrap-output header documents `Format: **[YYYY-MM-DD]** _Category_: ...`
  - Lines 519+: 134 `**[<TODAY>]**` entries in the embedded fenced markdown blocks

### What is *not* a per-entry date

`skills/sync/SKILL.md`, `docs/BEST_PRACTICES.md`, and the bootstrapped output all carry an `<!-- bootstrap-content-version: YYYY-MM-DD-<short-hash> -->` HTML comment near the top. This marker tracks the *content version* of the sync bundle (the plugin author bumps it when promoting new entries), and the `SessionStart` hook compares it across the project's file and the installed plugin's file to prompt re-sync. **This is not a per-entry timestamp** and is out of scope for this RFC. It stays.

### How `best-practices-sync` uses dates today

The sync skill normalizes entries before classifying them as `EXACT_DUPLICATE`, `CONFLICT`, or `NEW` (Step 2, lines 22–37). The first normalization step strips a leading `**[...]**` token so that `**[2026-05-09]** _Rust_: foo` and `**[<TODAY>]** _Rust_: foo` are compared by body alone. The normalization explicitly does *not* use the date for ordering or deduplication — it strips the date before comparison so that the date has no influence on outcome. Once dates are removed from both the global file and the sync file, the normalization rule simplifies to "strip leading italic-category prefix only". No ordering logic uses dates. No dedup logic uses dates after normalization. **Confirmed: the sync skill does not rely on dates for ordering or deduplication.**

## Analysis / Options

### Decision 1 — Remove dates entirely vs. keep them only in `~/.claude/BEST_PRACTICES.md`

**Option A — Remove dates from every BEST_PRACTICES file (recommended).**
The global file, the project file, and the sync-bundled content all use the same shape: `- _Category_: text`. One format, one writer template, one normalization rule in the sync skill.

**Option B — Keep dates in the global pool only.**
The argument would be that the global file is a working buffer pending promotion (entries leave it via sync), so a "captured-at" date could help when reviewing what's been sitting unpromoted. In practice, the sync skill runs whenever the plugin author touches this repo (Stop hook reminder fires); the global file empties out within days of each capture. The date adds nothing to the review.

**Option C — Drop the format but preserve historical entries.**
Treat the date as immutable historical record on existing entries, only stop emitting it on new ones. Produces a mixed format that confuses both readers and the sync skill's normalization regex. Worse than either consistent option.

**Recommendation: Option A.** Universal removal. One format everywhere is the simplest contract for readers and the cheapest contract for the three skills.

### Decision 2 — How to strip dates from existing entries

**Option A — One sed expression per file (recommended).**
A single regex captures the entry shape `**[<anything>]** ` and removes it, leaving the leading `_Category_:` intact. Idempotent (running twice has no effect after the first pass).

**Option B — Per-section walk in a script.**
Read each section, regenerate without dates, write back. More structure than the change warrants — sed handles the one-pattern replacement cleanly.

**Option C — Manual edit through the writer skills.**
The skills already write entries; ask them to rewrite the files. Slow, error-prone, and unnecessary when the regex is unambiguous.

**Recommendation: Option A.** Sed is the right scope.

### Decision 3 — How to update the writer/promoter skill templates

**Option A — Strip `**[YYYY-MM-DD]**` and `**[<TODAY>]**` from skill templates (recommended).**
Drop the date token from every documented format and every example in `best-practices-record`, `best-practices-extract`, `best-practices-sync`, and `sync` skill. Simplify the sync skill's normalization regex to strip only the italic-category prefix.

**Option B — Leave the templates with a date placeholder and let the writer skill choose to omit it.**
Branches the writer skill: "if user asks for a date, write one; otherwise omit". Adds optionality nobody asked for and contradicts Option A's premise that one format is the win.

**Recommendation: Option A.** Templates become shorter; the normalization regex becomes simpler; one less variable for the writer skills to reason about.

## Drawbacks

- **Loss of any chronological signal for forensic review.** If a future reader wants to know "when did we adopt this practice?", the answer is now "see git history of `docs/BEST_PRACTICES.md`" rather than reading the line itself. Mitigation: git history is the right source for that question — it includes the commit, the author, and the surrounding context. The line-level date was always lossy (no commit, no author, no diff context).
- **One-time migration cost on the existing global pool.** Any user who has an `~/.claude/BEST_PRACTICES.md` with dated entries gets a (small) sed pass applied. Mitigation: the sed pattern is unambiguous; the file is < 100 lines on real installations.
- **Existing dropped/done RFCs and other historical documents may continue to reference the dated format.** That's fine — they're historical record, not active contracts. The change applies to active writer skills and the live files they write into. Mitigation: this RFC does not retroactively edit RFC files; only the three best-practices files and the four skills.
- **The sync skill's normalization rule becomes simpler enough that the rule itself may not need to be in writing.** That is *not* a drawback; it is a benefit — but worth naming so the implementer doesn't accidentally re-add complexity. Mitigation: Step 5 of the implementation spec deletes the date-stripping prose entirely; the regex left in place is documented inline with a single example.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `~/.claude/BEST_PRACTICES.md` | Strip `**[YYYY-MM-DD]** ` from every entry line; update the file's header format documentation to remove the `**[YYYY-MM-DD]**` token |
| Modify | `docs/BEST_PRACTICES.md` | Strip `**[YYYY-MM-DD]** ` from every entry line (56 entries); update the file's header format documentation |
| Modify | `skills/best-practices-record/SKILL.md` | Remove the date token from the Confirmation Step example, Write Format documentation, the "`YYYY-MM-DD` is today's date" prose, and the bootstrap-file header template |
| Modify | `skills/best-practices-extract/SKILL.md` | Remove the date token from the Write Format documentation |
| Modify | `.claude/skills/best-practices-sync/SKILL.md` | Simplify the Step 2 normalization rule (drop the `**[...]**` strip step); remove `**[<TODAY>]**` from the Step 5 write instructions, the fence-structure example, and the auto-section-create template |
| Modify | `skills/sync/SKILL.md` | Remove the `<TODAY>` substitution rule (line 485); strip `**[<TODAY>]** ` from the 134 embedded entries; update the bootstrap-output header format documentation; bump `bootstrap-content-version` marker |

### Steps

#### Step 1 — Strip dates from `~/.claude/BEST_PRACTICES.md`

Run this in-place sed (GNU sed; macOS users substitute `sed -i ''`):

```bash
sed -i -E 's/^(- )\*\*\[[^]]+\]\*\* /\1/' ~/.claude/BEST_PRACTICES.md
```

**What this matches:** a line beginning with `- `, followed by `**[`, any characters that are not `]`, `]**`, and a trailing space. The capture group `(- )` is preserved; the date token is removed. Anything that didn't start with `- **[...]**` is untouched.

**Idempotency:** running it twice produces the same output — the second pass finds no `- **[...]**` prefix because the first pass removed it.

**Header update.** The file header still documents the old format. Edit `~/.claude/BEST_PRACTICES.md` to change this line:

Before:
```
Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```
After:
```
Format: _Category_: Concise statement (1–2 sentences max).
```

**Verification:**
```bash
grep -c '^\- \*\*\[' ~/.claude/BEST_PRACTICES.md
```
Expected output: `0` (no lines start with `- **[`).

```bash
grep -c '^\- _' ~/.claude/BEST_PRACTICES.md
```
Expected output: the same count as the dated-entry count before the change (3 today; will match whatever the file had).

#### Step 2 — Strip dates from `docs/BEST_PRACTICES.md`

Same sed pattern on the project file:

```bash
sed -i -E 's/^(- )\*\*\[[^]]+\]\*\* /\1/' docs/BEST_PRACTICES.md
```

Also update the header format documentation:

Before:
```
Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```
After:
```
Format: _Category_: Concise statement (1–2 sentences max).
```

**Verification:**
```bash
grep -c '^\- \*\*\[' docs/BEST_PRACTICES.md
```
Expected output: `0`.

```bash
grep -c '^\- _' docs/BEST_PRACTICES.md
```
Expected output: 56 (the current count of dated entries in the file).

#### Step 3 — Update `skills/best-practices-record/SKILL.md`

Apply three textual edits.

**Edit 1.** Lines 102–104 (Confirmation Step example):

Before:
```
About to append to ~/.claude/BEST_PRACTICES.md under "## <header>":

- **[YYYY-MM-DD]** _<header>_: <user's statement, lightly edited for the standard format>.

Proceed? (yes / edit / cancel)
```
After:
```
About to append to ~/.claude/BEST_PRACTICES.md under "## <header>":

- _<header>_: <user's statement, lightly edited for the standard format>.

Proceed? (yes / edit / cancel)
```

**Edit 2.** Lines 113–119 (Write Format section):

Before:
````
## Write Format

Format matches `best-practices-extract`:

```markdown
- **[YYYY-MM-DD]** _<Category>_: One or two sentences max.
```

`YYYY-MM-DD` is today's date. The italic category label uses a canonical abbreviated form for each section header — never the verbatim header text. Use this table:
````
After:
````
## Write Format

Format matches `best-practices-extract`:

```markdown
- _<Category>_: One or two sentences max.
```

The italic category label uses a canonical abbreviated form for each section header — never the verbatim header text. Use this table:
````

**Edit 3.** Line 152 (bootstrap-file header template inside the File Bootstrap section):

Before:
```
Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```
After:
```
Format: _Category_: Concise statement (1–2 sentences max).
```

No other changes. The triage step, lift step, categorization step, file-bootstrap logic, and red-flags list are unchanged.

**Verification:**
```bash
grep -nE 'YYYY-MM-DD|\*\*\[' skills/best-practices-record/SKILL.md
```
Expected output: `(empty)`.

#### Step 4 — Update `skills/best-practices-extract/SKILL.md`

Single edit at lines 99–105 (Write Format section):

Before:
````
## Write Format

Append approved items under the appropriate section in `docs/BEST_PRACTICES.md`:

```markdown
- **[YYYY-MM-DD]** _[Category]_: Concise statement. One or two sentences max.
```
````
After:
````
## Write Format

Append approved items under the appropriate section in `docs/BEST_PRACTICES.md`:

```markdown
- _[Category]_: Concise statement. One or two sentences max.
```
````

No other changes.

**Verification:**
```bash
grep -nE 'YYYY-MM-DD|\*\*\[' skills/best-practices-extract/SKILL.md
```
Expected output: `(empty)`.

#### Step 5 — Update `.claude/skills/best-practices-sync/SKILL.md`

This skill needs five edits — Step 2's normalization rule, two Step 5 prose lines, the fence-structure example, and the auto-create-section template.

**Edit 1.** Lines 22–37 (Step 2 — Classify each global entry). Replace the multi-step normalization with a single-step rule.

Before:
````
## Step 2 — Classify each global entry

For every entry in the global file, normalize it and compare against the matching section in the sync file.

**Normalization rule:** strip from the start of each line, in order:
1. Any `**[...]**` token matching the regex `\*\*\[.*?\]\*\*` followed by surrounding whitespace. This handles both forms:
   - `**[2026-05-09]**` — concrete-date form, used in `~/.claude/BEST_PRACTICES.md`
   - `**[<TODAY>]**` — placeholder form, used in `skills/sync/SKILL.md` (rendered at sync time)
   A regex limited to `\[\d{4}-\d{2}-\d{2}\]` would leave `[<TODAY>]` in place and make every sync entry look unique — always strip the broader pattern.
2. The italic-category prefix matching `_[^_]+_:` followed by surrounding whitespace. This collapses entries that differ only in label form (e.g., `_JS/TS_: Use bun install...` vs `_JavaScript / TypeScript_: Use bun install...`) into the same statement body for dedup purposes.

**Classification after normalization:**
````
After:
````
## Step 2 — Classify each global entry

For every entry in the global file, normalize it and compare against the matching section in the sync file.

**Normalization rule:** strip the italic-category prefix matching `_[^_]+_:` followed by surrounding whitespace from the start of each line. This collapses entries that differ only in label form (e.g., `_JS/TS_: Use bun install...` vs `_JavaScript / TypeScript_: Use bun install...`) into the same statement body for dedup purposes.

Entries no longer carry a date prefix as of RFC 2026-05-12-drop-dates-from-best-practices. If a legacy entry is encountered with a residual `**[...]**` prefix (e.g., a `~/.claude/BEST_PRACTICES.md` not yet migrated), apply an additional one-shot strip of `\*\*\[.*?\]\*\* ` before the italic-category strip; this only matters for unmigrated files and is removable once all instances have been migrated.

**Classification after normalization:**
````

**Edit 2.** Line 152 (Step 5, first bullet under "For conflict resolutions where the sync entry must change"):

Before:
```
- Find the existing entry line in the sync file and replace it with the new text (using the `**[<TODAY>]**` placeholder and the canonical abbreviated category label).
```
After:
```
- Find the existing entry line in the sync file and replace it with the new text (using the canonical abbreviated category label, no date prefix).
```

**Edit 3.** Lines 154–157 (Step 5, "For new entries being added" bullet block):

Before:
```
**For new entries being added:**
- Append to the matching section. Insert the new line before the closing ` ``` ` of the section's code fence, after the last existing entry.
- Use the `**[<TODAY>]**` date placeholder (not the concrete date from the global file).
- Use the canonical abbreviated category label (e.g., `_JS/TS_`, not `_JavaScript / TypeScript_`).
```
After:
```
**For new entries being added:**
- Append to the matching section. Insert the new line before the closing ` ``` ` of the section's code fence, after the last existing entry.
- Use the canonical abbreviated category label (e.g., `_JS/TS_`, not `_JavaScript / TypeScript_`). Do not include any date prefix.
```

**Edit 4.** Lines 159–165 (Fence structure for reference block):

Before:
````
**Fence structure for reference:**
```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: ...
- **[<TODAY>]** _<SectionName>_: ...   ← insert before the closing ``` fence
```
````
After:
````
**Fence structure for reference:**
```
## <SectionName>

- _<SectionName>_: ...
- _<SectionName>_: ...   ← insert before the closing ``` fence
```
````

**Edit 5.** Lines 171–177 (auto-create-section template in Step 5):

Before:
````
Insert the new section immediately before the closing ` ``` ` of the base content block, in this form:

```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: <entry text>
```
````
After:
````
Insert the new section immediately before the closing ` ``` ` of the base content block, in this form:

```
## <SectionName>

- _<SectionName>_: <entry text>
```
````

No other changes. Step 2a (re-triage), Step 3 (conflict resolution), Step 4 (NEW candidate batch approval), Step 6 (removal from global file), Step 7 (content-version bump), and Step 8 (report) are unchanged. The `bootstrap-content-version: <YYYY-MM-DD>-<short-hash>` marker mentioned in Step 7 is the content-version marker described in *Current state*; it is out of scope for this RFC and stays.

**Verification:**
```bash
grep -nE '<TODAY>|\*\*\[YYYY' .claude/skills/best-practices-sync/SKILL.md
```
Expected output: `(empty)`.

```bash
grep -nE '\*\*\[' .claude/skills/best-practices-sync/SKILL.md
```
Expected output: `(empty)`. The legacy-strip regex documentation in Edit 1 uses escaped backslashes (`\*\*\[.*?\]\*\*`) inside a backtick span, so its raw bytes are `\*\*\[` (backslash-asterisk-asterisk-backslash-bracket) — the grep pattern `\*\*\[` (which matches literal `**[`) does not match escaped forms. All `**[` occurrences from the pre-RFC file are gone.

#### Step 6 — Update `skills/sync/SKILL.md`

This skill's body documents the bootstrap output and embeds the dated entry templates inside fenced markdown blocks. Two-part edit.

**Part A — Remove the `<TODAY>` substitution rule.** Line 485 currently reads:

Before:
```
Create with the base content below, substituting `<TODAY>` with today's date in `YYYY-MM-DD` format. Then append every applicable section.
```
After:
```
Create with the base content below. Then append every applicable section.
```

**Part B — Update the bootstrap-output header format documentation.** Line 513 currently reads:

Before:
```
Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```
After:
```
Format: _Category_: Concise statement (1–2 sentences max).
```

**Part C — Strip `**[<TODAY>]** ` from every entry line inside the embedded fenced markdown blocks.** Use a sed pattern anchored to `**[<TODAY>]**` specifically (the placeholder form):

```bash
sed -i -E 's/^(- )\*\*\[<TODAY>\]\*\* /\1/' skills/sync/SKILL.md
```

This handles all 134 occurrences in one pass. The `<` and `>` inside `[<TODAY>]` are matched literally; the explicit pattern is more readable and safer than the general `[^]]+` form used in Steps 1–2 (no risk of accidentally stripping a non-date `**[...]**` token if one is added to the file later).

**Part D — Bump the `bootstrap-content-version` marker.** Both occurrences (line 6 file header and line 509 inside the embedded base-content fence) currently read `<!-- bootstrap-content-version: 2026-05-10-a81e517 -->`. Update both to a new value reflecting this content change. Use the date `2026-05-12` and a fresh 7-character hex digest. The implementer computes the digest as documented in `.claude/skills/best-practices-sync/SKILL.md` Step 7 (concatenated content of every fenced markdown block, 7-char hex digest). For this RFC, the marker after the edit must satisfy:

```bash
grep -c '^<!-- bootstrap-content-version: 2026-05-12-[0-9a-f]\{7\} -->$' skills/sync/SKILL.md
```
Expected output: `2` (header + embedded base-content fence).

**Verification (Step 6 as a whole):**
```bash
grep -cE '\*\*\[<TODAY>\]\*\*' skills/sync/SKILL.md
```
Expected output: `0`.

```bash
grep -nE 'substituting `<TODAY>`' skills/sync/SKILL.md
```
Expected output: `(empty)`.

```bash
grep -nE 'Format: \*\*\[' skills/sync/SKILL.md
```
Expected output: `(empty)`.

#### Step 7 — End-to-end verification

After all six file edits, run the consolidated check:

```bash
# (1) No per-entry date prefixes remain in any of the four content files
grep -cE '^- \*\*\[' \
  ~/.claude/BEST_PRACTICES.md \
  docs/BEST_PRACTICES.md \
  skills/sync/SKILL.md
```
Expected output: each path reports `0`.

```bash
# (2) No date placeholder text remains in any of the writer/promoter skill bodies
#     (the legacy-fallback regex documentation in the sync skill's Edit 1 is allowed)
grep -lnE '\*\*\[YYYY-MM-DD\]\*\*|\*\*\[<TODAY>\]\*\*' \
  skills/best-practices-record/SKILL.md \
  skills/best-practices-extract/SKILL.md \
  .claude/skills/best-practices-sync/SKILL.md \
  skills/sync/SKILL.md
```
Expected output: `(empty)` — no file matches.

```bash
# (3) Header format documentation is updated everywhere it appears
grep -nE 'Format: _Category_' \
  ~/.claude/BEST_PRACTICES.md \
  docs/BEST_PRACTICES.md \
  skills/best-practices-record/SKILL.md \
  skills/sync/SKILL.md
```
Expected output: each path has at least one match. (`skills/best-practices-record/SKILL.md` reports the file-bootstrap template; `skills/sync/SKILL.md` reports the embedded bootstrap-output header.)

```bash
# (4) Entry shape is correct after the strip — entries should now start with "- _"
grep -cE '^- _' \
  ~/.claude/BEST_PRACTICES.md \
  docs/BEST_PRACTICES.md
```
Expected output: matches the pre-change entry count for each file (3 and 56 today; verify against your local files).

```bash
# (5) bootstrap-content-version marker bumped in sync skill
grep -c '^<!-- bootstrap-content-version: 2026-05-12-' skills/sync/SKILL.md
```
Expected output: `2`.

```bash
# (6) Manual functional check — invoke /best-practices-record with a throwaway entry and
#     confirm the confirmation dialog shows "- _Category_: text" (no date prefix). Cancel
#     before write. If the user accidentally proceeds, the resulting line in
#     ~/.claude/BEST_PRACTICES.md must also lack the date prefix.
```
Expected: the dialog text matches the new Write Format.

If any check fails, the implementer re-applies the corresponding step. The sed passes are idempotent; the textual edits are reviewable via `git diff`.

## Risks and open questions

- **Risk: an in-flight `/best-practices-sync` run started before this RFC merges sees a mixed format mid-flight.** The user's global file may have been migrated (Step 1) but the sync skill (Step 5) not yet — or vice versa. Mitigation: the migration is a single PR landed together; partial application requires a deliberate split that should not happen. The updated normalization rule in Step 5 Edit 1 documents the legacy-strip fallback explicitly so that even a mid-flight mixed state classifies correctly.
- **Risk: an external user's `~/.claude/BEST_PRACTICES.md` may have hand-written entries that don't match the `- **[YYYY-MM-DD]** _Category_: ` pattern.** The sed regex is anchored to that exact prefix; non-matching lines are left untouched. Mitigation: the regex's specificity is the safety net. If a hand-written entry was written as `- **[note]** _Category_: foo` instead of a date, it would also be stripped — acceptable, since the entry then matches the new format anyway.
- **Risk: an entry's leading bullet is indented (`  - **[...]** _Cat_: text`) — the regex's `^- ` anchor misses it.** Mitigation: scan `~/.claude/BEST_PRACTICES.md` and `docs/BEST_PRACTICES.md` for indented entries before running the sed (`grep -nE '^  *- \*\*\['`). If any are found, broaden the regex to `^( *- )\*\*\[[^]]+\]\*\* /\1/`. Current files have no indented entries; the simpler anchor is preferred for readability.
- **Open question: should the sync skill keep the legacy-strip fallback indefinitely?** Step 5 Edit 1 leaves it in place as documentation of a one-shot path for unmigrated files. Once the user's `~/.claude/BEST_PRACTICES.md` is confirmed migrated (e.g., via a follow-up session a week after this RFC lands), a tiny cleanup PR can remove the fallback paragraph. Out of scope for this RFC.
- **Open question: when this RFC lands, should existing dropped/done RFCs that reference the dated format be updated?** No. Those RFCs are historical record. The format described in them was correct at the time of writing. Future RFCs that touch best-practices content reference the new format.
- **Risk: the `bootstrap-content-version` marker uses `YYYY-MM-DD` and could be confused with a per-entry date by a careless reader.** The marker is a HTML comment, not a list item, and is clearly labeled. No mitigation needed beyond keeping the distinction in mind during code review.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-09-best-practices-content-and-tooling.md` (Done).** Established the dated `**[YYYY-MM-DD]**` entry format across the three best-practices files and three skills. This RFC supersedes the format choice; the rest of the 2026-05-09 RFC (skill naming, sections, content) stays in force.
- **`docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md` (Draft, empty).** That RFC, when filled in, will likely add a hook that invokes `/best-practices-extract`. The writer skill's output format is already updated by this RFC; the auto-extract RFC inherits the dateless format without needing to coordinate.
- **`docs/rfcs/2026-05-12-unify-best-practices-destinations.md` (Draft, empty).** That RFC, when filled in, may collapse the global pool and project file into a single destination. Whatever shape it lands on, the entry format is now `- _Category_: text` and applies to both.
- **`docs/rfcs/2026-05-10-best-practice-extraction-principles.md`.** The triage + lift procedure shared by `best-practices-extract`, `best-practices-record`, and `best-practices-sync` references entry format in passing. No change required — the procedure operates on the *body* of an entry, never on the date prefix.

No conflicts. No prerequisites. This RFC can be implemented standalone.
