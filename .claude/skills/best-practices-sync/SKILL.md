---
name: best-practices-sync
description: Use inside the bytewyrd-workflow plugin's checkout to promote vetted global best-practice entries into the plugin's sync content. Run after accumulating a few entries via /best-practices-record. Surfaces a diff for the user to approve, appends approved entries to the matching section of skills/sync/SKILL.md so they ship with every freshly synced project, then removes the promoted entries from ~/.claude/BEST_PRACTICES.md.
---

# Sync Best Practices Into Plugin

## Overview

Promote entries from the user's global pool (`~/.claude/BEST_PRACTICES.md`) into this plugin's distributed sync content (`skills/sync/SKILL.md`), and then remove the promoted entries from the global pool. This is the *only* path for a global entry to reach a freshly-synced project — the global file is private to the user; the plugin file is what consumers receive.

This skill is plugin-local: it lives at `.claude/skills/best-practices-sync/` inside the plugin checkout and is not exported via `.claude-plugin/plugin.json`. It is only invokable from within the bytewyrd-workflow plugin checkout. If the cwd does not contain `skills/sync/SKILL.md` and `.claude-plugin/plugin.json`, stop with: "best-practices-sync only runs inside the bytewyrd-workflow plugin checkout. cd into the plugin repo and try again."

## Step 1 — Read both files

Read `~/.claude/BEST_PRACTICES.md` (the source). If absent or empty, stop with: "No global entries found at ~/.claude/BEST_PRACTICES.md — nothing to sync."

Read `skills/sync/SKILL.md` (the destination). Locate the language-and-section blocks that get appended to the synced `docs/BEST_PRACTICES.md`. Each block is identified by its section header (e.g., `## Testing`, `## Architecture`, `## Rust`, `## Kubernetes / CUE / kapply`).

## Step 2 — Compute the candidate set

For every entry in the global file, normalize and dedup against the sync file's same section.

**Normalization rule:** strip from the start of each line, in order:
1. Any `**[...]**` token matching the regex `\*\*\[.*?\]\*\*` followed by surrounding whitespace. This handles both forms:
   - `**[2026-05-09]**` — concrete-date form, used in `~/.claude/BEST_PRACTICES.md`
   - `**[<TODAY>]**` — placeholder form, used in `skills/sync/SKILL.md` (rendered at sync time)
   A regex limited to `\[\d{4}-\d{2}-\d{2}\]` would leave `[<TODAY>]` in place and make every sync entry look unique — always strip the broader pattern.
2. The italic-category prefix matching `_[^_]+_:` followed by surrounding whitespace. This collapses entries that differ only in label form (e.g., `_JS/TS_: Use bun install...` vs `_JavaScript / TypeScript_: Use bun install...`) into the same statement body for dedup purposes.

After both strips, compare statement bodies with text-equality (case-sensitive, internal whitespace preserved).

- If the normalized statement already appears in the sync file's same section → skip (already promoted).
- Otherwise → candidate.

## Step 3 — Present candidates

Group candidates by section. Show them as a numbered list, with the destination section in brackets:

```
Found 5 candidates to sync:

[Testing]
1. Use property-based tests for parsers, encoders, and any function with a clear algebraic invariant. Hand-written cases miss adversarial inputs that quickcheck-style generation surfaces in seconds.

[Architecture]
2. Favor composition over inheritance even in OO languages. Inheritance ties two types together at compile time; composition lets you swap collaborators in tests and at runtime.

[Rust]
3. Prefer `Result<T, E>` over panic for any error a caller might reasonably handle. Panic is for programmer error (broken invariants); Result is for runtime conditions.

[Kubernetes / CUE / kapply]
4. Render manifests with CUE and apply with kapply (`cue export --out yaml -e resources ./k8s/clusters/<env> | kapply -n <env> -`). The CUE side enforces shape; the kapply side enforces inventory and prune semantics.

[Terraform / Terragrunt]
5. Pin provider versions in every module. An unpinned provider can change resource schema between plan and apply, producing destructive diffs nobody asked for.

Promote which? (numbers, "all", "none")
```

## Step 4 — Append approved entries to the sync file

For each approved entry, append the line to the matching section of `skills/sync/SKILL.md`.

**Date placeholder:** when inserting into `sync/SKILL.md`, write the entry with the `**[<TODAY>]**` placeholder (not the concrete `**[YYYY-MM-DD]**` date from the global file). Sync entries are rendered at sync time; the placeholder is what gets substituted with the actual date when a user runs `/sync`.

**Italic category label:** use the canonical abbreviated form for the destination section (see the table in `best-practices-record`'s Write Format) — `_JS/TS_`, not `_JavaScript / TypeScript_`. This keeps sync entries consistent with one another and consistent with future global-file entries written by `best-practices-record` (which also uses the abbreviated forms).

**Insertion target.** Each section block in `sync/SKILL.md` uses a single Markdown code fence (` ``` `). The label line (e.g., `**Rust addition** (append after the Universal block):`) sits immediately above the opening fence. Insert the new entry before the closing ` ``` ` of the section's code fence.

The grep-anchor pattern is the section header inside the fenced block:

```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: ...
- **[<TODAY>]** _<SectionName>_: ...   ← insert before the closing ``` fence
```

Insertion point: immediately after the last existing entry in that section, before any blank line that precedes the closing fence.

If the section does not yet exist in `sync/SKILL.md`, **stop and tell the user**:

```
Cannot promote entry to "## <SectionName>" — that section does not exist in skills/sync/SKILL.md.

Adding a new section is a structural change. Edit sync/SKILL.md by hand to introduce the section (matching the existing pattern: append-after-X table row, fenced block, etc.), then re-run /best-practices-sync.
```

## Step 5 — Remove promoted entries from the global file

After Step 4 succeeds for an entry, delete the corresponding line (and only that line) from `~/.claude/BEST_PRACTICES.md`. Use a literal-line match against the original (un-normalized) line as it appeared in the global file. If the global section becomes empty after the deletions, leave the section header in place — the user may still add entries to it later.

Skipped candidates (Step 4's missing-section bail-out, or candidates the user did not approve) remain in the global file untouched.

Rewrite `~/.claude/BEST_PRACTICES.md` with the lines removed. The file's introductory header and any unmatched sections stay exactly as they were.

## Step 6 — Bump the sync content version

`skills/sync/SKILL.md` carries a content-version marker (a comment line near the top of the file: `<!-- bootstrap-content-version: <YYYY-MM-DD>-<short-hash> -->`). After appending entries in Step 4, recompute the marker: `<YYYY-MM-DD>` is today's date, `<short-hash>` is a 7-character hex digest of the concatenated content of every fenced markdown block in the file. Update the marker line in place. The `SessionStart` hook compares this marker against the value cached in the project's `docs/BEST_PRACTICES.md` to decide whether to remind the user to re-run `/sync`.

## Step 7 — Report

Print:

```
Promoted N entries to skills/sync/SKILL.md:
  - [Testing] 2
  - [Rust] 1
  - [Kubernetes / CUE / kapply] 1

Removed N entries from ~/.claude/BEST_PRACTICES.md.

Skipped M entries (section missing):
  - [<section>] <count>

Sync content version: <new-version-marker>

Run `git diff skills/sync/SKILL.md ~/.claude/BEST_PRACTICES.md` to review.
```

The skill never commits. Review and commit are the user's call.

## Red Flags — Stop and Reconsider

- A candidate's text is more than 2 sentences → tell the user the entry is too long for sync content and skip it (the global file may keep entries that are too rich for the sync; promotion is the discipline gate).
- A candidate is project-specific (mentions a project name, internal service, or repo path) → skip it; explain why ("this looks project-specific; sync content must be cross-project").
- The destination section already has > 12 entries → warn the user that the section is getting long and may need a split before appending more.
