---
name: best-practices-sync
description: Use inside the bytewyrd-workflow plugin's checkout to promote vetted global best-practice entries into the plugin's sync content. Run after accumulating a few entries via /best-practices-record. For each candidate it detects whether a conceptually similar entry already exists in the sync file — if so, it shows both versions plus an Opus-generated combined version and asks the user to pick one. Approved entries are appended to skills/sync/SKILL.md and removed from ~/.claude/BEST_PRACTICES.md.
---

# Sync Best Practices Into Plugin

## Overview

Promote entries from the user's global pool (`~/.claude/BEST_PRACTICES.md`) into this plugin's distributed sync content (`skills/sync/SKILL.md`), and then remove the promoted entries from the global pool. This is the *only* path for a global entry to reach a freshly-synced project — the global file is private to the user; the plugin file is what consumers receive.

This skill is plugin-local: it lives at `.claude/skills/best-practices-sync/` inside the plugin checkout and is not exported via `.claude-plugin/plugin.json`. It is only invokable from within the bytewyrd-workflow plugin checkout. If the cwd does not contain `skills/sync/SKILL.md` and `.claude-plugin/plugin.json`, stop with: "best-practices-sync only runs inside the bytewyrd-workflow plugin checkout. cd into the plugin repo and try again."

## Step 1 — Read both files

Read `~/.claude/BEST_PRACTICES.md` (the source). If absent or empty, stop with: "No global entries found at ~/.claude/BEST_PRACTICES.md — nothing to sync."

Read `skills/sync/SKILL.md` (the destination). Locate the language-and-section blocks that get appended to the synced `docs/BEST_PRACTICES.md`. Each block is identified by its section header (e.g., `## Testing`, `## Architecture`, `## Rust`, `## Kubernetes / CUE / kapply`).

## Step 2 — Classify each global entry

For every entry in the global file, normalize it and compare against the matching section in the sync file.

**Normalization rule:** strip from the start of each line, in order:
1. Any `**[...]**` token matching the regex `\*\*\[.*?\]\*\*` followed by surrounding whitespace. This handles both forms:
   - `**[2026-05-09]**` — concrete-date form, used in `~/.claude/BEST_PRACTICES.md`
   - `**[<TODAY>]**` — placeholder form, used in `skills/sync/SKILL.md` (rendered at sync time)
   A regex limited to `\[\d{4}-\d{2}-\d{2}\]` would leave `[<TODAY>]` in place and make every sync entry look unique — always strip the broader pattern.
2. The italic-category prefix matching `_[^_]+_:` followed by surrounding whitespace. This collapses entries that differ only in label form (e.g., `_JS/TS_: Use bun install...` vs `_JavaScript / TypeScript_: Use bun install...`) into the same statement body for dedup purposes.

**Classification after normalization:**

- **EXACT_DUPLICATE** — normalized statement body is text-equal to an existing entry in the sync file's same section. Skip silently; no user action needed.
- **CONFLICT** — normalized statement body is *not* text-equal to any sync entry, but you (as Claude) judge that an existing entry in the same section covers the same concept or overlaps significantly in meaning. Record which existing sync entry it conflicts with.
- **NEW** — no conceptually related entry exists in the section, OR the section does not yet exist in `sync/SKILL.md`. Candidate for direct promotion; missing sections are created automatically in Step 5.

Use judgment to distinguish CONFLICT from NEW: if the global entry and an existing sync entry give the same advice to a developer (even with different wording, emphasis, or examples), it is a CONFLICT. If the global entry adds genuinely new guidance that the section does not cover, it is NEW.

## Step 3 — Resolve conflicts

For each CONFLICT entry, resolve it before moving on to Step 4.

**Resolution process:**

1. Spawn an Opus subagent with the following task:

   > "You are helping merge two best-practice entries into one. Both cover the same concept but are worded differently. Write a single combined entry (≤ 2 sentences) that preserves the most useful insight from each. Output only the merged sentence(s), no preamble.
   >
   > Global version: <global entry text, normalized>
   > Plugin version: <existing sync entry text, normalized>"

2. **Dedup check before asking.** Compare the three versions (normalized, whitespace-collapsed). If any two are identical, auto-resolve without asking:
   - Global == Combined: use Global (Opus validated it), record as auto-resolved.
   - Plugin == Combined: keep Plugin (Opus validated it), record as auto-resolved.
   - Global == Plugin: they are effectively identical despite passing text-equality earlier — skip, record as auto-resolved.
   - All three equal: skip, record as auto-resolved.
   Only present the dialog when all three versions are genuinely distinct.

3. Present the three versions to the user with AskUserQuestion (single-select):
   - **Option 1 — Global**: `<global entry text>` *(from ~/.claude/BEST_PRACTICES.md)*
   - **Option 2 — Plugin**: `<existing sync entry text>` *(currently in skills/sync/SKILL.md)*
   - **Option 3 — Combined (Opus)**: `<Opus output>`

4. Act on the user's choice (or auto-resolved outcome):
   - **Global**: the global entry replaces the existing sync entry. Record: promote global text, delete existing sync entry, delete global line.
   - **Plugin**: keep the existing sync entry as-is. Record: delete global line (it's been reviewed and the plugin version wins), no change to sync file.
   - **Combined**: the Opus-generated text replaces the existing sync entry. Record: write Opus text, delete existing sync entry, delete global line.

If there are multiple CONFLICT entries, resolve them one at a time (sequential AskUserQuestion calls — do not batch conflicts into a multi-select).

## Step 4 — Present NEW candidates for batch approval

After all conflicts are resolved, collect the remaining NEW candidates. If none, skip to Step 5.

Group NEW candidates by section. Show them as a numbered list, with the destination section in brackets:

```
Found N new candidates to add:

[Testing]
1. Use property-based tests for parsers, encoders, and any function with a clear algebraic invariant. Hand-written cases miss adversarial inputs that quickcheck-style generation surfaces in seconds.

[Rust]
2. Prefer `Result<T, E>` over panic for any error a caller might reasonably handle. Panic is for programmer error (broken invariants); Result is for runtime conditions.

Promote which? (numbers, "all", "none")
```

## Step 5 — Write changes to the sync file

Apply the outcomes from Steps 3 and 4 to `skills/sync/SKILL.md`:

**For conflict resolutions where the sync entry must change (Global or Combined choice):**
- Find the existing entry line in the sync file and replace it with the new text (using the `**[<TODAY>]**` placeholder and the canonical abbreviated category label).

**For new entries being added:**
- Append to the matching section. Insert the new line before the closing ` ``` ` of the section's code fence, after the last existing entry.
- Use the `**[<TODAY>]**` date placeholder (not the concrete date from the global file).
- Use the canonical abbreviated category label (e.g., `_JS/TS_`, not `_JavaScript / TypeScript_`).

**Fence structure for reference:**
```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: ...
- **[<TODAY>]** _<SectionName>_: ...   ← insert before the closing ``` fence
```

**If the target section does not exist — create it automatically:**

`skills/sync/SKILL.md` contains multiple labeled addition blocks (each a fenced markdown block). New general sections go into the **base content block** — the first fenced block in the file, which currently ends with the `## Claude Code` entries. Do not create a new labeled addition block; just append the new section inside the existing base content fence.

Insert the new section immediately before the closing ` ``` ` of the base content block, in this form:

```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: <entry text>
```

After creating the section, insert the entry as normal. Note in the Step 8 report which sections were auto-created.

## Step 6 — Remove processed entries from the global file

For every entry that was:
- An EXACT_DUPLICATE
- A CONFLICT (regardless of which version the user chose — all three choices mean the global entry has been reviewed and resolved)
- A NEW candidate that the user approved

Delete the corresponding line from `~/.claude/BEST_PRACTICES.md`. Use a literal-line match against the original (un-normalized) line. If a section becomes empty, leave the section header in place.

Entries that remain untouched in the global file:
- NEW candidates the user declined

Rewrite `~/.claude/BEST_PRACTICES.md` with the deletions applied.

## Step 7 — Bump the sync content version

`skills/sync/SKILL.md` carries a content-version marker near the top: `<!-- bootstrap-content-version: <YYYY-MM-DD>-<short-hash> -->`. After all writes in Step 5, recompute the marker: `<YYYY-MM-DD>` is today's date, `<short-hash>` is a 7-character hex digest of the concatenated content of every fenced markdown block in the file. Update the marker line in place. The `SessionStart` hook compares this marker against the value cached in the project's `docs/BEST_PRACTICES.md` to remind users to re-run `/sync`.

Only update the version if the sync file actually changed (i.e., at least one entry was written or replaced in Step 5).

## Step 8 — Report

Print a summary:

```
Resolved conflicts: N
  - [Architecture] kept Combined (Opus) version
  - [Workflow] kept Plugin version

Promoted N new entries to skills/sync/SKILL.md:
  - [Testing] 2
  - [Code Design] 2  ← new section created
  - [Code Style] 1   ← new section created

Skipped N exact duplicates (already in sync).

Removed N entries from ~/.claude/BEST_PRACTICES.md.

Sync content version: <new-version-marker>

Run `git diff skills/sync/SKILL.md` to review.
```

The skill never commits. Review and commit are the user's call.

## Red Flags — Stop and Reconsider

- A candidate is project-specific (mentions a project name, internal service, or repo path) → skip it; explain why ("this looks project-specific; sync content must be cross-project"). Remove from global file only if user confirms.
- A candidate is > 2 sentences → note this in the presentation ("Note: this entry is N sentences — sync entries are typically ≤ 2. Consider using the Combined option to get a tighter version.") but do NOT skip it; let the user decide. If it goes in via conflict resolution, the Opus combined version will naturally be more concise.
- The destination section already has > 12 entries → warn the user that the section is getting long and may need a split, but proceed unless the user says to stop.
