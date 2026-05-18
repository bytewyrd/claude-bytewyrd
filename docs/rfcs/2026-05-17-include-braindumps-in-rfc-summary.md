---
rfc: "2026-05-17-include-braindumps-in-rfc-summary"
title: "Include braindumps in /rfc-summary output"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Extend the `/rfc-summary` skill to surface entries from `docs/rfc-braindump.md` alongside the existing `Approved` and `Draft` RFC groupings. Today the standup-style snapshot the skill produces covers only promoted proposals — parked ideas in the braindump are invisible and can accumulate unnoticed until the file grows large enough to feel unmaintainable. Adding a `### Braindumps (parked ideas)` section after the `Draft` table completes the in-flight picture: the skill will show `Approved`, `Draft`, and the braindump entry count in a single view, with each braindump entry truncated to its bold title for quick scanning, capped at 10 entries with a count of the remainder if the list is longer.

## Should we do this?

**Yes.** The braindump file is the first stage of the RFC lifecycle, and the skill already positions itself as a "standup-style snapshot of in-flight work" (verified: `skills/rfc-summary/SKILL.md:L8`). Leaving it silent about the braindump creates a gap: a user who asks "what RFC work is in flight?" gets Draft and Approved, but not the queue of ideas waiting to be promoted. Given the current braindump file has 9 entries (verified by `grep -c '^\* ' docs/rfc-braindump.md`), this is already a meaningful amount of parked material.

The implementation is minimal: the braindump data is already available via `scripts/rfc-braindump-list.sh` (verified: `scripts/rfc-braindump-list.sh:L1-L53`), so the only change is extending the skill's step 3 (filter and group) and step 4 (render output) to consume and display it. No new scripts, no agent spawn, no schema changes.

The constraint that the braindump list can grow large is addressed by the 10-entry cap — the output stays concise whether the file has 2 entries or 50.

## Current state

**What the skill does today:**

`skills/rfc-summary/SKILL.md` (verified: `skills/rfc-summary/SKILL.md:L1-L98`) executes a five-step inline flow:

1. Verify `docs/rfcs/` exists.
2. Run `bash scripts/rfc-summary.sh` to get a JSON array of RFC frontmatter objects, sorted by `created` then `rfc`.
3. Filter and group the rows into `Approved`, `Draft`, and `Other` (Done/Dropped, counted only).
4. Render two Markdown tables — `### Approved (ready to implement)` and `### Draft (needs review or approval)` — with a trailing counts line and a `(also: <X> Done, <Y> Dropped)` footnote.
5. Print a hand-off hint listing the next-action skills.

**What it does not cover:**

The skill makes no reference to `docs/rfc-braindump.md` or `scripts/rfc-braindump-list.sh` (verified: `skills/rfc-summary/SKILL.md:L1-L98`). Braindump entries are entirely absent from the output.

**The braindump data source:**

`scripts/rfc-braindump-list.sh` (verified: `scripts/rfc-braindump-list.sh:L1-L53`) emits:

```json
{"entries": [{"n": 1, "body": "**Title.** Full paragraph text."}, ...]}
```

Each `body` is a complete bullet entry prefixed with a bold `**Title.**` phrase followed by a descriptive paragraph. The script exits 0 always — an absent `docs/rfc-braindump.md` produces `{"entries": []}` rather than an error. The body is a single raw string; there is no separate `title` field.

## Analysis / Options

Three coupled decisions: which data to show, how to truncate long entries, and where to render the section.

### Decision 1 — What information to display per braindump entry

**Option A — Bold title only, extracted from the `body` field (recommended).**

Every braindump entry written by the `/rfc-braindump` skill follows the format `**Title.** Paragraph.` (verified: `skills/rfc-braindump/SKILL.md:L28`). The bold title can be extracted from `body` with a simple pattern match: the text between the first `**` pair. The trailing period (`.`) is part of the source-formatting convention — a sentence-ending mark that closes the bold title clause — not part of the title itself, so the extraction strips a trailing `.` before display (`**Auto-prompt PR.**` → `Auto-prompt PR`, not `Auto-prompt PR.`). This gives a clean, short label that fits a table row or a bulleted list without wrapping. The full paragraph is available in the file for anyone who needs it.

**Option B — Full body text.**

Displaying the full paragraph for each entry produces a readable single-column list but quickly becomes verbose — entries average 50–100 words. With 9 current entries, the output would be several hundred words of dense prose, defeating the "standup snapshot" goal. Rejected on length grounds.

**Option C — First sentence of the body.**

More granular than Option A but less predictable: sentences vary in length and structure, and some entries front-load context that only resolves mid-sentence. The `**Title.**` bold pattern is more reliable and consistently short. Rejected in favor of Option A.

**Recommendation: Option A.** Extract the bold-title substring from `body`, strip the trailing `.`. This is a well-defined, machine-readable convention enforced by the `/rfc-braindump` skill's Opus distillation step.

### Decision 2 — Entry cap

The braindump file can grow large. Showing every entry unconditionally could produce a long tail that buries the RFC tables.

**Option A — Cap at 10 entries, show a remainder count (recommended).**

Show the first 10 entries (in file order — file order reflects insertion order, oldest first). If there are more, append: `_(and <N> more — see docs/rfc-braindump.md)_`. The choice of 10 is grounded in the current 9-entry file fitting in one screen already; 10 provides one entry of headroom before the cap triggers, and the remainder-count line keeps the total length bounded without hiding the existence of additional entries.

**Option B — No cap, show all entries.**

Simple to implement but produces unbounded output as the file grows. The braindump is designed to accumulate; a cap is necessary for the snapshot framing. Rejected.

**Option C — Show only the first 5 entries.**

More aggressive; 5 would already cap today's 9-entry file. Setting the cap at 5 forces the remainder-count line to appear in almost every real invocation, which reduces the signal-to-noise ratio of the entry list. 10 is a better default — it matches the scale of the current file and gives room to grow before the cap fires. Rejected.

**Recommendation: Option A.** Cap at 10, show a remainder line when the list is longer.

### Decision 3 — Placement and format of the braindumps section

**Option A — `### Braindumps (parked ideas)` section after the Draft table, bulleted list (recommended).**

The natural reading order for the standup snapshot is: "what's ready to implement?" (`Approved`) → "what needs review?" (`Draft`) → "what's in the parking lot?" (`Braindumps`). Placing the braindump section last keeps the actionable items prominent. A bulleted list (not a table) fits the data: braindump entries have no structured fields (`status`, `author`, `created`) to tabulate — only the extracted title. A table with one column of titles would be noisier than a plain list.

If `docs/rfc-braindump.md` is absent or has zero entries, the section is omitted entirely — no "No Braindumps." placeholder, because an empty parking lot is not noteworthy in the way that an empty `Approved` or `Draft` group is (where the explicit "No X RFCs." avoids the user wondering if the skill looked at that group at all).

**Option B — Braindumps section before the RFC tables.**

Front-loading the parking lot would obscure the actionable items. The RFC tables answer "what requires a decision or implementation?" — the more urgent question. Rejected.

**Option C — Inline braindump count at the bottom, no entry list.**

A single trailing line like `(also: 9 braindump entries — run /rfc-braindump or /rfc-new)` would be minimal but not useful for discovery. The point of surfacing braindump entries is to make forgotten ideas visible by name, not just by count. Rejected.

**Recommendation: Option A.** `### Braindumps (parked ideas)` after Draft, bulleted list, capped at 10, with a remainder line if needed, section omitted when empty.

## Drawbacks

- **Longer output.** The skill output grows by up to 12 lines (10 bullet entries + a header + a remainder line) when braindump entries exist. For a project with a full braindump file, the snapshot can become less "standup-style" and more report-like. Mitigation: the 10-entry cap keeps the maximum addition bounded. The braindumps section is also clearly separated by its `###` header and appears after the actionable RFC tables, so users who care only about `Approved`/`Draft` can stop reading at the familiar boundary.

- **Braindump entries have no metadata.** Unlike RFC rows (which have `author` and `created`), braindump entries expose only their title. A user cannot tell from the summary who parked an idea or when. Mitigation: this is an intentional constraint — the braindump file does not store per-entry metadata, and adding metadata would require changing the braindump schema (a different RFC's scope). The section header links readers to `docs/rfc-braindump.md` in the remainder-count line for entries beyond the cap.

- **Title extraction is a pattern match, not a structured parse.** If a braindump entry does not begin with `**Title.**`, the extraction falls back to the first 80 characters of `body`. Entries written by hand (not via `/rfc-braindump`) may not follow the bold-title convention. Mitigation: the fallback produces something readable, not an error. The `/rfc-braindump` skill enforces the convention via its Opus distillation step (verified: `skills/rfc-braindump/SKILL.md:L28`), so manually authored entries are the edge case, not the norm.
  - **Malformed `**` edge case.** If a `body` contains an opening `**` with no matching closing `**` (e.g., `**Title without closing bold`), the pattern match yields no closing-bold capture. The fallback (first 80 characters of `body`) applies in this case, same as the no-bold-title case. Do not error or abort. This is enforced in the jq expression by guarding the bold-title branch with a second-`**` presence check before splitting.

- **File-order display may surface stale entries first.** `rfc-braindump-list.sh` returns entries in file order, which is insertion order (verified: `scripts/rfc-braindump-list.sh:L31-L39`). Old, never-promoted ideas appear at the top. This is actually the desired behavior for a parking lot — older entries are more likely to need attention or explicit dropping — but it can look odd if the first entry is a long-obsolete idea. Mitigation: out of scope for this RFC; the braindump file's curation is the user's responsibility.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/rfc-summary/SKILL.md` | Extend Steps 2–4 to fetch, truncate, and render braindump entries in a new `### Braindumps (parked ideas)` section after the Draft table |
| Modify | `docs/rfc-process.md` | Update the one-line `/rfc-summary` description in the Skills table so the project-level RFC process doc reflects the expanded scope (Draft, Approved, and braindumps) |

No new scripts. No agent files changed. No plugin.json change.

### Steps

#### Step 1 — Modify `skills/rfc-summary/SKILL.md`

Replace the existing file content with the content below. The diff relative to the current file (verified: `skills/rfc-summary/SKILL.md:L1-L98`) is:

- Step 2: rename "Enumerate, parse, and sort" to reflect that braindump data is now also fetched; add a second `bash` invocation to fetch braindump entries.
- Step 3: add braindump extraction logic after the RFC grouping.
- Step 4: add the `### Braindumps (parked ideas)` section to the rendered output.
- Step 5: update the hand-off hint to mention `/rfc-braindump` and `/rfc-new`.
- Description frontmatter: update to mention braindumps.

**Before** (current `skills/rfc-summary/SKILL.md` description line, verified: `skills/rfc-summary/SKILL.md:L3`):

```
description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
```

**After:**

```
description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date, plus parked braindump ideas. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
```

**Full replacement file content for `skills/rfc-summary/SKILL.md`:**

````markdown
---
name: rfc-summary
description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date, plus parked braindump ideas. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
---

# RFC Summary

Lists every RFC currently in `Draft` or `Approved` status, grouped by status, oldest first within each group, followed by a `### Braindumps (parked ideas)` section showing parked ideas from `docs/rfc-braindump.md`. Output is a quick standup-style snapshot — not a full report. Read-only, no commits.

## Steps

### 1. Verify the project has an RFC directory

Run:

```bash
test -d docs/rfcs
```

If the directory does not exist, tell the user:

> "This project has no `docs/rfcs/` directory. Run `/sync` to set up the RFC process, or `/rfc-new` to create the first RFC."

Stop.

### 2. Enumerate, parse, and sort

```bash
result="$(bash scripts/rfc-summary.sh)"
```

`$result` is a JSON object `{"rfcs": [...], "warnings": [...]}`. Extract:

```bash
rfcs="$(printf '%s' "$result" | jq -c '.rfcs')"
warnings="$(printf '%s' "$result" | jq -r '.warnings[]?')"
```

`$rfcs` is a JSON array sorted ascending by `created` then by `rfc` identifier. Iterate it with `printf '%s' "$rfcs" | jq -c '.[]'` to grab each row as an object for step 3's grouping. Print any per-file `$warnings` (incomplete frontmatter, unrecognized status) so the user sees them before the rendered summary. Exit code 2 only if `docs/rfcs/` does not exist — in that case `$result` contains `{"error":"..."}` (extract via `jq -r .error`) and step 1's "no RFC directory" message is shown.

Then fetch braindump entries:

```bash
braindump_result="$(bash scripts/rfc-braindump-list.sh)"
braindump_entries="$(printf '%s' "$braindump_result" | jq -c '.entries')"
```

`$braindump_entries` is a JSON array of `{"n": <int>, "body": "<string>"}` objects in file order. The script always exits 0; an absent `docs/rfc-braindump.md` produces `{"entries": []}`.

### 3. Filter, group, and extract braindump titles

Group the sorted RFC rows by status. Build three lists:

- **Approved** — rows whose `status` is `Approved`
- **Draft** — rows whose `status` is `Draft`
- **Other** — rows whose `status` is `Done` or `Dropped`; not displayed by row, only counted

From `$braindump_entries`, extract a display title for each entry. Each `body` follows the format `**Title.** Paragraph.` (the bold-title convention enforced by `/rfc-braindump`). Extract the title by matching the text between the first `**` pair, then strip a trailing `.` (the period is part of the source-formatting convention, not the title):

```bash
# For each entry in $braindump_entries, extract the title.
# jq expression:
#   - if body starts with ** AND has a closing ** somewhere after, take the
#     text between the first ** pair and strip a trailing period.
#   - otherwise (no opening **, OR opening ** with no matching close), fall
#     back to the first 80 characters of body. Do not error or abort.
braindump_titles="$(printf '%s' "$braindump_entries" | jq -r '
  .[] | .body |
  if startswith("**") and (.[2:] | contains("**")) then
    ltrimstr("**") | split("**")[0] | rtrimstr(".")
  else
    .[0:80]
  end
')"
```

`$braindump_titles` is a newline-separated list of display titles, one per entry, in file order. The `and (.[2:] | contains("**"))` guard handles the malformed case where an opening `**` has no matching closing `**` (e.g., `**Title without closing bold`) — without it, `split("**")[0]` would return the entire remainder of the string. With it, such entries cleanly fall through to the 80-character fallback.

Count total braindump entries:

```bash
braindump_total="$(printf '%s' "$braindump_entries" | jq 'length')"
```

### 4. Render the output

Output is plain Markdown so it renders cleanly in the conversation.

If both `Approved` and `Draft` are empty (no in-flight RFCs):

```markdown
No active RFCs. All RFCs in `docs/rfcs/` are Done or Dropped.

(also: <D> Done, <X> Dropped)
```

If there are braindump entries, append the braindumps section (see below) after this message.

Otherwise, render two tables. Always include both headers — if a group is empty, show "No Approved RFCs." or "No Draft RFCs." under the heading instead of an empty table:

```markdown
## Active RFCs

### Approved (ready to implement)

| RFC | Title | Author | Created |
|-----|-------|--------|---------|
| `2026-05-10-foo` | Foo Title | Rodrigo Kochenburger | 2026-05-10 |

### Draft (needs review or approval)

| RFC | Title | Author | Created |
|-----|-------|--------|---------|
| `2026-05-12-bar` | Bar Title | Rodrigo Kochenburger | 2026-05-12 |

**<A> Approved · <D> Draft · <T> in flight**

(also: <X> Done, <Y> Dropped)
```

Where `<A>`, `<D>` are the per-group counts, `<T> = A + D` is the total in-flight count, and `<X>`, `<Y>` are the Done and Dropped counts. The `rfc:` identifier is rendered in inline code (backticks) so it visually distinguishes from the title prose.

**Braindumps section:**

If `$braindump_total` is 0, omit the section entirely. Otherwise, append after the RFC counts line (or after the "No active RFCs" line if applicable).

To build the bullets, take the first 10 lines of `$braindump_titles`:

```bash
display_titles="$(printf '%s\n' "$braindump_titles" | head -10)"
```

Then render the section:

```markdown
### Braindumps (parked ideas)

* <title-1>
* <title-2>
* ...
```

Where each `<title-N>` is one line from `$display_titles`. If `$braindump_total` is greater than 10, append this line after the last bullet:

```markdown
_(and <R> more — see docs/rfc-braindump.md)_
```

Where `<R>` is `$braindump_total - 10`.

### 5. Hand off

Tell the user:

> "Run `/rfc-approve <rfc>` to approve a Draft, `/rfc-implement <rfc>` to begin an Approved RFC, `/rfc-read-feedback <rfc>` to address inline `FEEDBACK:` comments, `/rfc-braindump <idea>` to add a new idea, or `/rfc-new` to promote a braindump to a full RFC."

This is one line; it provides the next-step hint without bloating the output. Do not commit. Do not modify any file.

## Constraints

- **Read-only.** This skill does not write, edit, or commit. If asked to "fix" something it surfaces, decline and point at the appropriate mutation skill (`/rfc-approve`, `/rfc-drop`, `/rfc-implement`, `/rfc-braindump`).
- **No agent spawn.** The skill runs in the main conversation. Listing RFC frontmatter and braindump entries is mechanical; there is no domain reasoning to delegate.
- **Frontmatter contract.** This skill assumes every `docs/rfcs/*.md` file has the frontmatter shape defined in `docs/rfc-process.md` §"Required YAML frontmatter". If parsing yields an empty `rfc` or `status` for a file, print `Warning: <filename> — frontmatter incomplete; skipping.` and continue. Do not abort the whole listing on one malformed file.
- **Braindump section is omitted when empty.** If `docs/rfc-braindump.md` is absent or contains no bullet entries, do not render the `### Braindumps (parked ideas)` header.
````

#### Step 2 — Update `docs/rfc-process.md`

The project-level RFC process doc lists each RFC skill with a one-line description in a Skills table. Update the `/rfc-summary` row to reflect the expanded scope (it now also surfaces braindump entries). This keeps the doc consistent with the skill's `description` frontmatter line updated in Step 1.

**Target line** (verified: `docs/rfc-process.md:L212`):

```
| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
```

**Replace with:**

```
| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status, plus parked braindump ideas, for a quick standup snapshot |
```

Exact Edit-tool call (preferred — Markdown table rows contain pipe characters, so `sed` is brittle here):

- `old_string` (literal, single line):

  ```
  | `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
  ```

- `new_string` (literal, single line):

  ```
  | `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status, plus parked braindump ideas, for a quick standup snapshot |
  ```

The `<!-- END_UPSTREAM_CONTENT -->` marker at line 226 is below the Skills table, so this change falls within the upstream-synced section. That is expected — the upstream `rfc-process.md` source (in this plugin) ships the same one-line description, and updating only the local copy without updating the upstream would create drift on the next `/sync`. **The same edit must be applied to the upstream copy of `rfc-process.md` in this plugin's repository.** Implementers in the plugin repo: the file is `docs/rfc-process.md` (the canonical source); consumers running `/sync` against an updated plugin will receive the new line automatically.

#### Step 3 — Verification

After editing the file, run these checks:

1. **Description line updated:**

   ```bash
   grep -F 'plus parked braindump ideas' skills/rfc-summary/SKILL.md
   ```

   Expected output:

   ```
   description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date, plus parked braindump ideas. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
   ```

2. **Braindump fetch step is present:**

   ```bash
   grep -F 'rfc-braindump-list.sh' skills/rfc-summary/SKILL.md
   ```

   Expected output:

   ```
   braindump_result="$(bash scripts/rfc-braindump-list.sh)"
   ```

3. **Braindumps section header is present:**

   ```bash
   grep -F 'Braindumps (parked ideas)' skills/rfc-summary/SKILL.md
   ```

   Expected output (two lines — one for the step heading, one for the rendered output example):

   ```
   ### Braindumps (parked ideas)
   ### Braindumps (parked ideas)
   ```

4. **Braindump script smoke test — confirm it returns entries:**

   ```bash
   bash scripts/rfc-braindump-list.sh | jq '.entries | length'
   ```

   Expected output: a non-negative integer (currently `9`). Zero is valid if `docs/rfc-braindump.md` is empty. Any parse error indicates a problem with the script, not with this RFC's changes (the script is pre-existing).

5. **Title extraction smoke test — confirm the jq expression works against current data:**

   ```bash
   bash scripts/rfc-braindump-list.sh | jq -r '
     .entries[] | .body |
     if startswith("**") and (.[2:] | contains("**")) then
       ltrimstr("**") | split("**")[0] | rtrimstr(".")
     else
       .[0:80]
     end
   '
   ```

   Expected output: one line per braindump entry, each showing only the bold-title text (e.g., `Modular Plugin Feature Toggles`, `Auto-prompt PR creation in /rfc-new and parallelize /rfc-new-braindumps`, etc.), without the `**` markers, without the trailing `.`, and without the paragraph body.

6. **Manual smoke test (after plugin reload):**

   - Type `/rfc-summary` in Claude Code and confirm:
     - The `## Active RFCs` section renders with `Approved` and `Draft` tables as before.
     - A `### Braindumps (parked ideas)` section appears after the Draft table with a bulleted list of entry titles (up to 10).
     - If there are more than 10 entries, a `_(and <R> more — see docs/rfc-braindump.md)_` line appears after the 10th bullet.
     - If `docs/rfc-braindump.md` has no entries, the `### Braindumps (parked ideas)` section is absent.
   - Confirm no commits were made (`git status` shows a clean working tree, assuming it was clean before invocation).

## Risks and open questions

- **Risk: the bold-title jq pattern fails for entries that begin with a backtick or other non-`**` opener.** Entries written by hand rather than via `/rfc-braindump` may not follow the `**Title.**` convention. The fallback (first 80 characters of `body`) produces something readable rather than an error, but may look truncated mid-sentence. **Mitigation:** this is an inherent limitation of parsing a free-form text field; the mitigation is to note in the Constraints section that the braindump section title extraction assumes the `/rfc-braindump`-enforced format. Users who add entries by hand and see a truncated display can reformulate the entry or add `**Title.**` prefix manually.

- **Risk: performance regression if `docs/rfc-braindump.md` is very large.** The `rfc-braindump-list.sh` script reads the file line by line in a Bash loop (verified: `scripts/rfc-braindump-list.sh:L31-L39`); for a very large file (hundreds of entries) this could be slower than the RFC enumeration. **Mitigation:** the 10-entry display cap does not affect parse time — the script always parses all entries. In practice, a braindump file with hundreds of entries indicates a maintenance issue (the file should be culled periodically), not a performance issue with this skill. The skill's display behavior does not change if the file is large; only the `_(and <R> more)_` count grows.

- **Risk: the `### Braindumps` section may confuse users who expect `/rfc-summary` to show only RFC files.** The section is clearly labeled "parked ideas" and is visually separated from the RFC tables by the `###` header, but it changes the skill's scope from "RFC files only" to "full RFC workflow including pre-RFC stage." **Mitigation:** the skill description is updated to say "plus parked braindump ideas" so users who read the description see the expanded scope before invoking.

- **Open question: should `/rfc-summary` include braindump entries even when `docs/rfc-braindump.md` does not exist?** The current resolution is: no — the section is silently omitted. This matches the design decision to only surface the section when there is something to show. No change needed.

## Relationship to other RFCs

- **`2026-05-12-rfc-summary-command`** (status: Done, verified: `docs/rfcs/2026-05-12-rfc-summary-command.md:L7`) — the RFC that created `/rfc-summary`. This RFC extends the skill it established; the output format and step numbering here follow the same conventions that RFC introduced.

- All other RFCs in `docs/rfcs/` are unaffected. No skill, agent, or script other than `skills/rfc-summary/SKILL.md` is changed.
