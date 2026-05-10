---
rfc: "2026-05-10-project-brief-sync-source-of-truth"
title: "Project Brief as Single Source of Truth in /sync"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Make `docs/project-brief.md` the canonical source of project identity for the `/sync` skill. On first run, `/sync` interactively builds the brief — name, description, problem, goals, non-goals, constraints — through a single conversational pass; on every subsequent run, it reads the brief and uses it to populate every artifact that needs project identity (`CLAUDE.md` heading and description, `README.md` heading and blockquote, GitHub repository description) without re-asking. The standalone Step 2b "name and description" prompt is removed; name and description become structured front-matter fields on the brief, parsed deterministically rather than scraped from a free-text first-paragraph heuristic.

## Should we do this?

**Yes.** The current `/sync` flow has three coupled problems that this RFC fixes together: (1) the user is asked for project name and description even when an existing `docs/project-brief.md` already encodes them, requiring redundant click-through; (2) the extraction heuristic for the brief's name and description (first H1 line; first non-heading paragraph) is brittle and produces silent mismatches when the brief author wrote a generic intro paragraph or omitted the H1; (3) the same identity values are currently produced by two routes — direct user prompt and brief extraction — with no guarantee they stay aligned across re-runs. Consolidating on the brief as the structured source eliminates duplicate data entry, makes "what is this project?" a single-file edit, and removes a class of drift bugs where `CLAUDE.md` and `README.md` disagree because one was edited by hand and the other by `/sync`.

## Current state

`/sync` collects project identity in **Step 2** of `skills/sync/SKILL.md` through two sequential `AskUserQuestion` calls:

**Step 2a — project brief.** If `docs/project-brief.md` exists, sync auto-sets `brief_mode = "added"` and extracts:
- `brief_name` — first `# Heading` line, stripping `# `.
- `brief_description` — first non-heading, non-blank, non-HTML-comment sentence or paragraph.

Otherwise sync asks `"Do you have a project brief?"` with three options: *help me create one* (deferred 4-question pass after setup), *I've added the file* (read it now), or *Other* (skip entirely → `brief_mode = null`).

**Step 2b — name and description.** Always invoked, regardless of `brief_mode`:
- Question 1: `"What is the project name?"` — default is `brief_name` (if extracted) or `Title Case(project_slug)`; `Other` lets the user type a replacement.
- Question 2: `"One-sentence description?"` — default is `brief_description` (if extracted) or `github_description` (from `gh repo view`) or a `Skip` option.

Stored values: `project_name`, `description`, `project_slug` (always derived from `basename` in Step 1, never asked), `has_github`, `brief_mode`.

These values then feed:
- `CLAUDE.md` line 1 heading and the description paragraph immediately below it (Step 5, "Name and description sync" — applied even on existing files).
- `README.md` line 1 heading and the line-3 blockquote.
- The Step 6 `gh repo edit --description` call when a GitHub remote is configured *and* description is non-empty.
- The "Why" and "How It Works" seeds in the README (extracted from the brief if present).

The current brief template (`skills/sync/SKILL.md` Step 5) has four sections — Problem, Goals, Non-Goals, Constraints — and no dedicated name or description field. The "name" extracted from the brief is whatever the user happened to use as the H1 heading, and the "description" is whatever the user happened to write as the first paragraph. There is no schema enforcement and no place where the brief author is told "these two values are load-bearing for every other doc."

The "help me create one" path asks four AskUserQuestion items (Problem / Goals / Non-Goals / Constraints) with a pre-generated suggestion plus an `Other` text input. It runs *after* Step 2b — meaning the user has already committed to a name and description before the brief is filled in, so the brief's name (H1) and the description (first paragraph) are derived from the Step 2b answers and re-rendered into the brief, not the other way around.

This design carries three latent issues:

1. **Redundant prompt.** Even when `brief_mode = "added"` and both `brief_name` and `brief_description` were extracted cleanly, Step 2b still fires — the user clicks the default twice. On a re-run of `/sync` (idempotent refresh, the documented use case), the user is asked the same two questions every time.
2. **Brittle extraction.** The `brief_description` heuristic ("first non-heading, non-blank, non-HTML-comment sentence or paragraph") silently picks up whatever happens to lead the brief. If the author wrote `"This document captures..."` as a meta-introduction, that becomes the project description on every downstream artifact.
3. **No guaranteed consistency on re-run.** A user who edits the H1 of `docs/project-brief.md` to change the project name does not change `CLAUDE.md` or `README.md` until they re-run `/sync` — and even then, the Step 2b prompt asks again, which is friction that discourages re-running. The brief and the docs can drift indefinitely.

## Analysis / Options

### Option A — Brief as the only source; structured front matter; no Step 2b (recommended)

Promote `docs/project-brief.md` to the canonical source of identity. Add a small YAML front matter block at the top of the brief carrying `name` and `description` as structured fields. `/sync` parses the front matter and uses both values directly — no re-prompt on subsequent runs. On first run (no brief exists), `/sync` runs a single `AskUserQuestion` pass that collects name, description, and the four narrative sections (Problem / Goals / Non-Goals / Constraints) in one conversational flow, then writes the brief. Step 2b is removed entirely.

**Why front matter rather than scraping headings.** Front matter is parseable, schema-able, and unambiguous. The current heading-and-first-paragraph heuristic depends on conventions the brief author has no incentive to follow. With front matter, `/sync` reads exactly two well-known keys; if either is missing, it falls back to a deterministic, documented rule (Title-Case of `project_slug` for name; empty string for description) and notes the omission in the Step 8 report.

**Door stays open for additional structured fields.** A later RFC may add `goals`, `audience`, `keywords`, etc. as additional front matter keys without re-engineering the parsing. The schema is a forward-compatible JSON-like dictionary; consumers ignore unknown keys.

### Option B — Keep Step 2b but skip it when both fields are extractable from brief

Leave the Step 2b prompt structure in place, but skip it entirely when `brief_mode = "added"` and both extraction heuristics returned non-empty values. Continue scraping name and description from the body of the brief (H1 + first paragraph), as today.

**Why this is rejected.** It addresses symptom #1 (redundant prompt) but leaves symptoms #2 (brittle extraction) and #3 (drift between brief and downstream files) unfixed. Heuristic-based scraping is the root cause of most identity drift: a brief author updates the project's narrative paragraph, and `/sync` silently changes `CLAUDE.md` line 2 on the next run because the heuristic's "first paragraph" output is now different. The point of this RFC is to make the brief authoritative *and* unambiguous, not just to mute the prompt.

### Option C — Detect-and-prompt with merge UI

When the brief and downstream docs (`CLAUDE.md` line 1, `README.md` line 1) differ, show a side-by-side comparison and ask the user to pick. This is what most identity-merge tools do (e.g., `git merge --tool`).

**Why this is rejected.** This RFC's goal is *fewer prompts*, not better prompts. Building a merge UI compounds the problem. It also introduces a new failure mode: agentic re-runs of `/sync` (e.g., from a parent agent automating project setup) cannot answer interactive merge prompts, breaking the documented "idempotent, safe to re-run" property.

### Recommendation

Option A. The front matter is small, the parser is trivial, the failure mode (missing keys) is deterministic and noted, and removing Step 2b reclaims an interactive step that delivered no value when the brief already had the data.

## Drawbacks

- **Bootstrap migration cost for existing projects.** Projects that already ran `/sync` before this RFC have a brief without the front matter block. The migration path (folded into Change 3 of the implementation spec) writes the front matter into the existing brief on first run after the upgrade, drawing the values from the existing H1 and first paragraph (the same heuristics in use today). This preserves current behavior for one re-run; subsequent runs are fully driven by the front matter. Mitigation: the migration is idempotent — if the front matter already exists and parses cleanly, leave it untouched; if not, derive it once and write it.

- **Front matter is YAML; brief authors may break it.** A bad indentation or stray colon makes the entire front matter unparseable. Mitigation: the parser is fault-tolerant — if YAML parsing fails, treat the front matter as absent (apply the missing-keys fallback rules), note the parse failure in the Step 8 report so the user sees the message, and continue. The brief content below the front matter is unaffected.

- **Brief becomes the "must-edit" file for renames.** Today, a user can rename a project by editing `CLAUDE.md` line 1 and `README.md` line 1 directly, then re-running `/sync` (which currently respects those edits because Step 2b's default would be the *current* extracted brief value). Under this RFC, edits to `CLAUDE.md` line 1 are overwritten on the next `/sync` run by whatever is in `docs/project-brief.md` front matter. Mitigation: this is the *intended* outcome — single source of truth means downstream artifacts cannot be the rename point. The Step 8 report and the brief template both call this out explicitly. Renaming a project is now: edit `docs/project-brief.md` front matter, re-run `/sync`, done.

- **First-run UX is one larger prompt instead of two smaller ones.** The single AskUserQuestion that collects name, description, and the four narrative fields is more questions in one screen. Mitigation: AskUserQuestion already supports multiple questions in a single call; the current Step 5 "help me create one" path uses a 4-question single call, and we are extending it to 6. The total number of human-input touch points on first run drops from "Step 2a question + Step 2b two questions + Step 5 four questions = 3 separate prompts" to "1 unified prompt".

- **GitHub-derived defaults become a one-time seed, not an interactive default.** Today, when `gh repo view --description` returns a non-empty value, the user sees it as a click-to-accept option in Step 2b. Under this RFC, `github_description` is used only as the pre-fill suggestion in the first-run unified prompt, and on subsequent runs it is ignored entirely (the brief wins). Mitigation: this is correct — once the project has a brief, the brief's description is the project's description, regardless of what someone typed into the GitHub UI six months ago. If the user wants to align them, they edit the brief and `/sync` propagates to GitHub via `gh repo edit` (which already happens in Step 6).

## Implementation spec

### Naming convention for this section

The implementation spec describes a series of **Changes** (Change 1, Change 2, …) to apply to the existing `skills/sync/SKILL.md`. The word "Step" in this section *always* refers to a step inside `skills/sync/SKILL.md` itself (e.g., "Step 2 — Gather project info"). Using "Change N" for the implementation actions avoids the ambiguity of "Step N of the spec" colliding with "Step N of the skill file."

**Note on nested code fences.** Several Changes below show the new content for a region of `skills/sync/SKILL.md` inside a code fence. In some cases the content itself contains triple-backtick fences (e.g., a new template inside the new step body). The implementer should use the *innermost* fence content as the literal text to insert into `skills/sync/SKILL.md`, which already uses single triple-backticks throughout — do not propagate the outer fence used here for presentation. Where this RFC needs to nest fences for readability, the outer fence is shown as a quadruple-backtick (` ```` `) wrapper.

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/sync/SKILL.md` | All behavioral changes: replace Step 2 (entire two-AskUserQuestion flow), update the Interaction-model preamble, fold the brief-migration logic into Step 5's `### docs/project-brief.md` block, update Step 5's "Name and description sync" rule, add a clarifying sentence to Step 6, update Step 8's report table, bump the bootstrap content version marker on line 6 (and any duplicate marker in templated content). |
| Create | (none — no new files) | All changes are scoped to the existing `skills/sync/SKILL.md`. |

The change is intentionally scoped to a single file. The brief's *content* lives in user repositories (created or migrated by `/sync`) and is migrated lazily by Change 3; no existing file in this plugin's source tree carries content that needs editing beyond `skills/sync/SKILL.md`.

### Brief front matter schema

Every `docs/project-brief.md` written or migrated by `/sync` begins with this YAML block:

```yaml
---
name: "<human-readable display name>"
description: "<one-sentence description, may be the empty string>"
---
```

Both keys are strings. `name` must be present and non-empty. `description` must be present; its value may be the empty string (signalling "the user explicitly skipped"). To represent "explicitly empty" the value must be written as `""` (quoted empty string) — an unquoted bare `description:` is interpreted as "absent" and triggers the gap-fill prompt on the next `/sync` run.

Additional keys are reserved for future RFCs and ignored by the current parser.

The closing `---` is followed by a blank line, then the Markdown body (`# <name>`, the four narrative sections, etc.).

### Parser rules

In every step that consumes the brief, parse it as follows:

1. Read `docs/project-brief.md`. If the file is absent, 0 bytes, or contains only whitespace, return `(brief_name=None, brief_description=None, legacy_name=None, legacy_description=None, parse_error=None)`.
2. If the file's first non-blank line is exactly `---`, locate the closing `---` (search line by line *after* the opening `---` until a line equal to `---` is found). Treat the lines between as YAML; parse with the minimal grammar described below.
3. If the file's first non-blank line is not `---`, treat front matter as absent — leave `brief_name` and `brief_description` as `None`. Run the legacy heuristic on the entire file content: `legacy_name` = the first `# Heading` line stripped of `# `; `legacy_description` = the first non-heading, non-blank, non-HTML-comment sentence or paragraph.
4. If the front matter delimiters are present but parsing fails (e.g., unterminated front matter, unparseable line), set `parse_error` to a one-line description (e.g., `"unterminated front matter — no closing --- found"`). Treat front matter as absent for value resolution: leave `brief_name` and `brief_description` as `None` and run the legacy heuristic on the entire file content (including the failed front matter region). Record the parse error for the Step 8 report.

The minimal YAML parser handles exactly this grammar:
- Each non-blank line is `<key>: <value>` where `<key>` matches `^[a-z_][a-z0-9_]*$`.
- `<value>` resolution:
  - A double-quoted string (`"..."` with no embedded escapes) — value is the contents between the quotes (which may be empty: `""` produces `""`).
  - An unquoted string (no surrounding quotes) with at least one non-whitespace character — value is the text after stripping leading/trailing whitespace.
  - **Empty after the colon** (`description:` with nothing or only whitespace following) — treat as "key absent" (do not set the corresponding `brief_*` variable; leave it `None`). This rule is the meaning-distinguishing rule: explicit-empty is `description: ""`; not-yet-filled-in is `description:` (or `description: `).
- Leading/trailing whitespace around the colon is allowed.
- Lines starting with `#` (after optional indentation) are comments and ignored.
- Blank lines are ignored.
- Any line not matching this grammar triggers `parse_error` (e.g., a key with no colon, a key starting with an uppercase letter, a value with mismatched quotes).

After parsing, set `brief_name` and `brief_description` from the parsed values: present with a value (including quoted-empty `""`) → set the variable; absent or unquoted-empty → leave it as `None`.

The minimal parser explicitly does **not** support: nested mappings, lists, multi-line strings, anchors, references, or any YAML feature beyond flat string-valued keys. Briefs needing a richer schema fall outside this RFC's scope.

### Changes

#### Change 1 — Replace Step 2 of `skills/sync/SKILL.md`

Delete the entire existing Step 2 (the heading "Step 2 — Gather project info" through the line ending `**Languages are not asked** ...`, lines 73–125 inclusive in the pre-RFC file). Replace with the following content. The content uses single triple-backticks for any embedded fences, matching the existing file convention.

````markdown
## Step 2 — Gather project identity from the brief

Project identity (`project_name` and `description`) is sourced from `docs/project-brief.md`. The brief is the single source of truth — `/sync` does not maintain identity values independently of it.

`"Other"` is a special label in the Claude Code UI — it renders as a text input field rather than a plain button. Do not add any label like "Type below" or "Enter custom"; the text field is self-explanatory.

### 2a — Read existing brief, if any

If `docs/project-brief.md` exists, parse it (front matter schema and parser rules are documented in the RFC `2026-05-10-project-brief-sync-source-of-truth`). The parse yields these outputs:

- `brief_name` — string from front matter, or `None` if the key is absent or unquoted-empty
- `brief_description` — string from front matter, or `None` if the key is absent or unquoted-empty
- `legacy_name` — string from the H1 heuristic, or `None` if no H1 found
- `legacy_description` — string from the first-paragraph heuristic, or `None` if nothing matches
- `parse_error` — string describing front matter parse failure, or `None`

Resolve `project_name`:
1. If `brief_name` is non-`None` and non-empty → `project_name = brief_name`.
2. Else if `legacy_name` is non-`None` and non-empty AND not equal to `"Project Brief"` (case-insensitive) → `project_name = legacy_name` and set `needs_migration = true`.
3. Else if `legacy_name` is `"Project Brief"` (case-insensitive — the literal placeholder from older brief templates) → `project_name = Title Case(project_slug)` and set `needs_migration = true`.
4. Else → set `project_name_missing = true` (will be filled by the gap-fill prompt below).

Resolve `description`:
1. If `brief_description` is not `None` (a quoted-empty `""` from front matter is a valid explicit "skip" and produces `brief_description = ""`) → `description = brief_description`.
2. Else if `legacy_description` is non-`None` and non-empty → `description = legacy_description` and set `needs_migration = true`.
3. Else → set `description_missing = true` (will be filled by the gap-fill prompt below).

If neither `project_name_missing` nor `description_missing` is set, no further user input is needed for identity; proceed to Step 3.

If `project_name_missing` is set OR `description_missing` is set, ask one AskUserQuestion to fill the gaps:

- If only `project_name_missing`: include question 1 only.
- If only `description_missing`: include question 2 only.
- If both: include both questions in one call.

**Question 1 — "Project name (display)?"**: suggestion is `Title Case(project_slug)`; the auto-rendered `Other` is a free-text input. Falls back to the suggestion if `Other` is empty.

**Question 2 — "One-sentence description (or skip)?"**: the first suggestion is `(skip — leave empty)` (which stores `""`); `Other` is a free-text input. If `github_description` from Step 1 is non-empty, it appears as an additional suggestion option ahead of the skip option. Empty `Other` is treated as "skip" (stores `""`).

**Sentinel detection rule:** the AskUserQuestion response indicates which option the user selected (the suggestion option vs the `Other` text input). Treat description as "skipped" only when the user selected the `(skip — leave empty)` *suggestion option*, not when the user typed the literal text `(skip — leave empty)` into `Other` (an unlikely but possible collision). The implementation tests `response.option_index` (or equivalent), not `response.value`.

After answering, set `project_name` and `description` from the answers. The collected values are folded into `docs/project-brief.md`'s front matter by Change 3's migration sub-rule. Always set `needs_migration = true` when the gap-fill prompt fires (so the front matter gets written, even if the legacy heuristic also yielded values for the other field).

### 2b — If brief is absent, decide whether to create one

If `docs/project-brief.md` does not exist, ask one AskUserQuestion:

**"Do you want to create a project brief now?"** The brief is the canonical source of project identity (name, description) and scope (problem, goals, non-goals, constraints). Without it, `/sync` will use derived defaults (Title-Case of the directory name for the project name; an empty description) and will re-ask on every run.

- Option 1: `Yes — let's set it up now (single prompt, 6 questions)` — sets `create_brief = true`
- Option 2: `Skip — I'll create it later by re-running /sync` — sets `create_brief = false`

If `create_brief = false`, set `project_name = Title Case(project_slug)` and `description = ""`, then proceed directly to Step 3. The brief is not created; subsequent `/sync` runs will re-ask this question.

If `create_brief = true`, proceed to Step 2c.

### 2c — First-run unified prompt (only when brief is being created)

This step runs only when `create_brief = true`. It is a single AskUserQuestion containing six questions in one call.

Each question gets one suggestion option plus an auto-rendered `Other` free-text input. The user can either accept the pre-fill or type a custom answer:

1. **"Project name (display)?"** — suggestion: `Title Case(project_slug)` (e.g. `tinywyrd` → `Tinywyrd`)
2. **"One-sentence description?"** — suggestions: if `github_description` from Step 1 is non-empty, that string is the first suggestion; otherwise the only suggestion is `(skip — leave empty)` which, if selected, stores `""`
3. **"Problem — what does this solve, and who is it for?"** — suggestion inferred from the project slug and any detected language (e.g. for a Rust binary the suggestion might be `"<project_slug> — utility for <inferred-context>; for <inferred-audience>."`)
4. **"Goals — what does success look like?"** — suggestion: a generic `"<project_slug> ships a <one-line-outcome> that <verb> for its users."` template adapted from the slug
5. **"Non-goals — what is explicitly out of scope?"** — suggestion: a generic `"Not a general-purpose <category> for arbitrary use; opinionated toward <inferred-stack>."` template adapted from the slug
6. **"Constraints — technical, operational, or philosophical?"** — suggestion: a generic `"Must work within the user's standard <inferred-runtime> environment."` template adapted from the slug

**Sentinel detection rule** (same as Step 2a): treat description as "skipped" only when the user selected the `(skip — leave empty)` *suggestion option*, not when the user typed that literal text into `Other`. Test `response.option_index`, not `response.value`.

For non-description questions (1, 3, 4, 5, 6): if the user submits an empty `Other` value, fall back to the suggestion. None of these five can be skipped to empty.

Store the answers as `answer_name`, `answer_description`, `answer_problem`, `answer_goals`, `answer_nongoals`, `answer_constraints`. Then:

- `project_name = answer_name`
- `description = answer_description` (which may be `""` if the description was skipped)
- `brief_problem = answer_problem`, `brief_goals = answer_goals`, `brief_nongoals = answer_nongoals`, `brief_constraints = answer_constraints`

The brief file is written in Step 5 — not here — so that `/sync` writes all files in one block.

`has_github` is derived from Step 1 (`true` if a `github.com` remote was detected) and never asked.

`project_slug` is derived from Step 1 (`basename $(git rev-parse --show-toplevel)`) and never asked.

**Languages are not asked** — they are detected automatically in Step 3.
````

The literal `brief_mode` variable is no longer set anywhere — every reference to it elsewhere in `skills/sync/SKILL.md` must be removed (see Change 3).

#### Change 2 — Update the "Interaction model" preamble

The existing preamble (lines 13–19 of `skills/sync/SKILL.md`) reads:

````markdown
## Interaction model

Sync runs almost entirely autonomously. There are exactly **two points** where user input is collected:

1. **Step 2** — Two AskUserQuestion calls: project brief preference, then display name and description.
2. **Step 5** (only if `brief_mode = "help"`) — One AskUserQuestion call with 4 project-brief questions.

Everything else — environment detection, file creation, GitHub metadata update, RFC install, and the final report — happens without asking the user.
````

Replace with:

````markdown
## Interaction model

Sync runs almost entirely autonomously. User input is collected only when project identity cannot be sourced from `docs/project-brief.md`:

1. **Step 2a (gap-fill)** — One AskUserQuestion with 1 or 2 questions, asked only when the existing brief lacks a usable name and/or description.
2. **Step 2b** — One AskUserQuestion: "Do you want to create a project brief now?". Asked only when `docs/project-brief.md` does not exist.
3. **Step 2c** — One AskUserQuestion with 6 questions (name, description, problem, goals, non-goals, constraints). Asked only when 2b answered "Yes".

When `docs/project-brief.md` already exists *and* its front matter (or legacy heuristic fallback) yields both name and description, all three prompts are skipped — `/sync` reads identity from the brief and proceeds. Everything else — environment detection, file creation, GitHub metadata update, RFC install, and the final report — happens without asking the user.
````

#### Change 3 — Update Step 5's `docs/project-brief.md` block (with migration sub-rule)

In the existing Step 5 of `skills/sync/SKILL.md`, locate the `### docs/project-brief.md` block (currently lines 210–244, anchored by the heading and ending before `### .gitignore`). Replace its entire body with:

````markdown
### `docs/project-brief.md`

The brief is the single source of truth for project identity. The exact action depends on what was determined in Step 2:

**If the brief already exists with valid front matter** (Step 2a found `brief_name` and `brief_description` from the front matter parser and `needs_migration` is unset) — skip the file. Track in the Step 8 report as `exists — front matter present`.

**If the brief exists but `needs_migration = true`** (no front matter, or front matter present but missing keys, with the legacy heuristic or Step 2a's gap-fill yielding the values) — prepend (or replace) the front matter block. Read the existing file content, then proceed by case:

- *Case A — file does not start with `---`*: prepend a new front matter block. Construct:

  ```
  ---
  name: "<resolved project_name>"
  description: "<resolved description>"
  ---
  
  <existing file content, byte-for-byte>
  ```

- *Case B — file starts with `---` but the parser rejected it (parse error) or some keys were absent or unquoted-empty*: locate the closing `---` (or the end of the file if there is no closing fence within the first 50 lines). Replace the entire region from the opening `---` through the closing `---` (inclusive) with a freshly-written front matter block:

  ```
  ---
  name: "<resolved project_name>"
  description: "<resolved description>"
  ---
  ```

  The body following the front matter region is preserved byte-for-byte. If no closing `---` was found within the first 50 lines, treat the entire first 50 lines as a malformed front matter region and replace them with the new block, then preserve everything from line 51 onward — this is a worst-case fallback for an unbounded malformed front matter; the value 50 is large enough to absorb any reasonable hand-edited block.

`<resolved project_name>` is the value computed in Step 2a (which has already accounted for the `"Project Brief"` literal-placeholder rule and the gap-fill prompt). `<resolved description>` is the value computed in Step 2a (which may be `""`). Both values are written double-quoted in the output (`name: "Foo"`, `description: ""` for the explicit-skip case).

The body below the new/replaced front matter is preserved exactly — no re-flowing, no heading rewrites, no sentence-level edits.

Track in the Step 8 report as `migrated (front matter added)`.

**If `create_brief = true`** (Step 2c was run) — write a new brief now using the answers collected in Step 2c. The full file content:

```
---
name: "<answer_name>"
description: "<answer_description>"
---

# <answer_name>

> <answer_description>

## Problem

<answer_problem>

## Goals

<answer_goals>

## Non-Goals

<answer_nongoals>

## Constraints

<answer_constraints>
```

Front matter values must be double-quoted. If `answer_description` is the empty string (sentinel selected in Step 2c), write `description: ""` for the front matter and write a single blank line in place of the `> <description>` blockquote.

Track in the Step 8 report as `created (front matter + body)`.

**If `create_brief = false` and the brief is absent** — skip entirely. Track in the Step 8 report as `skipped (user opted not to create)`.
````

This block consolidates what was previously a four-section creation policy (`brief_mode = "added"`, `brief_mode = "help"`, `brief_mode = null`) into four deterministic outcomes driven by the resolution in Step 2 (already exists with valid front matter / needs migration / create new / skip). The four-question deferred prompt that previously ran here under `brief_mode = "help"` is removed — Step 2c covers it before any file write happens.

In the same Change 3, sweep `skills/sync/SKILL.md` for any remaining mention of `brief_mode` (the existing file contains references on lines 17, 92, 97, 122, 212, 214, 244 per pre-RFC line numbers). Remove every reference; their semantics are now subsumed by `create_brief`, `needs_migration`, and the front-matter-vs-legacy-vs-missing distinction in the Step 2 resolution.

#### Change 4 — Update Step 5's "Name and description sync" rule

The current Step 5 file-creation policy (lines 195–202 of `skills/sync/SKILL.md`) includes this paragraph:

````markdown
- **Name and description sync** — always apply, even to existing files:
  - In `CLAUDE.md`: update the `# <heading>` on line 1 if it differs from `project_name`; update the description paragraph directly after the heading if it differs from `description` (skip if description is empty)
  - In `README.md`: update the `# <heading>` on line 1 if it differs; update the `> <blockquote>` description on line 3 if it differs (skip if description is empty)
````

Replace with:

````markdown
- **Name and description sync** — always apply, even to existing files. Both values come from `project_name` and `description` resolved in Step 2 (which sourced them from `docs/project-brief.md` front matter, or from the documented legacy/gap-fill fallbacks):
  - In `CLAUDE.md`: update the `# <heading>` on line 1 if it differs from `project_name`; update the description paragraph directly after the heading if it differs from `description` (skip the description update if `description` is empty).
  - In `README.md`: update the `# <heading>` on line 1 if it differs from `project_name`; update the `> <blockquote>` description on line 3 if it differs from `description` (skip the description update if `description` is empty).
  - **Direction is one-way: brief → docs.** Edits made directly to `CLAUDE.md` line 1 or `README.md` line 1 are overwritten on the next `/sync` run. To rename the project, edit the `name` field in `docs/project-brief.md` front matter and re-run `/sync`.
````

#### Change 5 — Add a clarifying sentence to Step 6's GitHub metadata block

The current Step 6 GitHub metadata block (lines 1083–1098 of `skills/sync/SKILL.md`) reads `description` and runs `gh repo edit --description "<description>"` *only if description is non-empty* (the existing `# Update description (only if description is non-empty)` comment on line 1093). No code or guard logic changes here — the variable `description` now sources from the brief, the empty-guard is preserved, and the `gh` invocation is unchanged.

Append this clarifying paragraph to the end of the GitHub repository metadata block, immediately before the next subsection (`### .github/workflows/ci.yml`):

````markdown
The `description` value passed to `gh repo edit` is the same value written into `CLAUDE.md` and `README.md` — all three are sourced from `docs/project-brief.md` front matter, ensuring local and remote stay aligned. The empty-guard is preserved: when `description` is `""` (the user explicitly skipped), no `gh repo edit --description` call is made, and any pre-existing GitHub description is left untouched.
````

#### Change 6 — Update the Step 8 report table

In the existing Step 8 report table (lines 1322–1346 of `skills/sync/SKILL.md`), replace the row:

````markdown
| `docs/project-brief.md` | created (template) / exists — used for name/description / **skipped** (not requested) |
````

with two rows:

````markdown
| `docs/project-brief.md` | created (front matter + body) / exists — front matter present / migrated (front matter added) / skipped (user opted not to create) |
| Brief parse status      | front matter parsed OK / legacy heuristic used (consider re-running with migration) / parse error: `<message>` |
````

The "Brief parse status" row reports the outcome of Step 2a's parse (and Change 3's migration sub-rule); it is informational only — `/sync` never aborts on parse failure.

#### Change 7 — Bump the bootstrap content version marker

`skills/sync/SKILL.md` line 6 carries:

```
<!-- bootstrap-content-version: 2026-05-10-8e478c1 -->
```

Update the value to a new marker reflecting this change. The marker format is `<YYYY-MM-DD>-<7-char-hash>`. Use today's date (`2026-05-10`) and a fresh 7-character lowercase-hex suffix derived from the SHA-1 of the file's full new content (`sha1sum skills/sync/SKILL.md | cut -c1-7`). The marker is consumed by the `SessionStart` hook in `.claude-plugin/hooks/hooks.json` and `.claude/settings.json` to remind users to re-run `/sync` when the plugin's bootstrap content changes; updating the marker on this RFC's commit ensures users running an older cached `/sync` see the prompt.

The same marker also appears once inside Step 5's templated `docs/BEST_PRACTICES.md` content (the line `<!-- bootstrap-content-version: 2026-05-10-8e478c1 -->` near line 438 of `skills/sync/SKILL.md`). Update that occurrence to the same new value, so freshly-bootstrapped projects record the new marker in their `docs/BEST_PRACTICES.md`.

#### Change 8 — Verification

After applying Changes 1 through 7, run these checks from the repo root:

1. **No references to the removed `brief_mode` variable**:

   ```bash
   grep -n "brief_mode" skills/sync/SKILL.md
   ```

   Expected output: empty.

2. **Step 2 contains exactly the new sub-headings**:

   ```bash
   grep -nE "^### 2[abc]" skills/sync/SKILL.md
   ```

   Expected output (in order, line numbers will vary):

   ```
   ### 2a — Read existing brief, if any
   ### 2b — If brief is absent, decide whether to create one
   ### 2c — First-run unified prompt (only when brief is being created)
   ```

3. **The Interaction model preamble lists Step 2a / 2b / 2c**:

   ```bash
   sed -n '/^## Interaction model/,/^## Step 1/p' skills/sync/SKILL.md | grep -E "Step 2[abc]"
   ```

   Expected: at least three matches (one each for 2a, 2b, 2c) within the Interaction model section.

4. **The brief block in Step 5 contains the front-matter template**:

   ```bash
   sed -n '/^### `docs\/project-brief\.md`/,/^### /p' skills/sync/SKILL.md | grep -c '^---$'
   ```

   Expected: at least 6 (two `---` for the migration "Case A" template, two `---` for the migration "Case B" template, two `---` for the create template).

5. **The Step 8 report table includes the new "Brief parse status" row**:

   ```bash
   grep "Brief parse status" skills/sync/SKILL.md
   ```

   Expected: one match.

6. **Bootstrap content version marker is updated**:

   ```bash
   grep -n "bootstrap-content-version:" skills/sync/SKILL.md
   ```

   Expected: two matching lines (the file-level marker on line 6, and the templated-content marker inside Step 5's `BEST_PRACTICES.md` block). Both must show the new value, neither still shows `2026-05-10-8e478c1`.

7. **No unmodified verbiage from the old Step 2**:

   ```bash
   grep -n "two sequential AskUserQuestion calls" skills/sync/SKILL.md
   ```

   Expected output: empty (this string was Step 2's old preamble line; if it remains, Change 1 was incomplete).

8. **Manual end-to-end check** in a scratch repo:
   - `mkdir /tmp/sync-test && cd /tmp/sync-test && git init && git config user.name 'Test User' && git config user.email 'test@example.com'`.
   - **First run.** Run `/sync`. Verify Step 2b is asked (one question), then Step 2c is asked (one prompt, six questions).
   - Inspect `docs/project-brief.md` — verify front matter is present at the top with `name:` and `description:` keys, both double-quoted.
   - Inspect `CLAUDE.md` line 1 and `README.md` line 1 — verify both match the front matter `name`.
   - **Re-run, brief renamed.** Edit `docs/project-brief.md` front matter to change the `name` value. Re-run `/sync`. Verify no AskUserQuestion is asked at all (brief exists with valid front matter), and verify `CLAUDE.md` line 1 and `README.md` line 1 update to the new name.
   - **Re-run, front matter manually deleted.** Manually delete the front matter block from `docs/project-brief.md` (leave the H1 and body intact). Re-run `/sync`. Verify no AskUserQuestion is asked (`brief_name`/`brief_description` come from the legacy heuristic), the file gets the front matter prepended (Change 3 migration sub-rule fires, Case A), and the Step 8 report shows `migrated (front matter added)`.
   - **Re-run, H1 = "# Project Brief".** Replace the H1 in `docs/project-brief.md` with the literal `# Project Brief`, delete the front matter again. Re-run `/sync`. Verify `project_name` resolves to `Title Case(project_slug)` (i.e., `Sync-Test`), not to `Project Brief`, and the migrated front matter writes `name: "Sync-Test"`.
   - **Re-run, front matter present but values empty.** Manually set `docs/project-brief.md` to start with `---\nname:\ndescription:\n---\n\n# Foo\n\nBody.\n` (front matter present, both values unquoted-empty). Re-run `/sync`. Verify the gap-fill prompt fires (Step 2a end), asking for both name and description. Accept the suggestion for name and select the skip sentinel for description. Verify the file is rewritten with `name: "Sync-Test"` and `description: ""` (quoted-empty) in the front matter, and the report shows `migrated (front matter added)`.
   - **Re-run, front matter with `description: ""`.** Edit the brief's front matter to `description: ""` (quoted-empty). Re-run `/sync`. Verify no prompt fires (quoted-empty is "explicit skip"), `description` resolves to `""`, and `CLAUDE.md` / `README.md` line 1 still update to `name` while their description lines remain untouched.

## Risks and open questions

- **Risk: minimal YAML parser is too restrictive.** The grammar accepts only flat string-valued keys with double-quoted or unquoted values. A user who tries to add a list (`tags: [a, b]`), a multi-line string (`description: |\n ...`), or any nested mapping triggers `parse_error` and falls back to the legacy heuristic. Mitigation: the schema documented in this RFC explicitly contains only `name` and `description`, both string-valued; the Step 8 "Brief parse status" line surfaces parse failures so the user sees what went wrong; future RFCs that add structured fields will need to upgrade the parser, and that scope is delegated.

- **Risk: existing pre-RFC briefs in user repos may have an H1 of `# Project Brief`.** The current brief template (current Step 5 of `skills/sync/SKILL.md`) literally starts with `# Project Brief` as the H1. The migration step's special-case rule (Change 1, Step 2a, resolution rule #3) catches this — `legacy_name == "Project Brief"` (case-insensitive) is overridden with `Title Case(project_slug)`. Any other H1 string (including a project's actual display name) is taken at face value.

- **Risk: a user who relies on `gh repo view --description` to seed the description loses that auto-fill on subsequent runs.** Today, sync re-checks GitHub on every run and uses the GitHub description as a fallback default for Step 2b. Under this RFC, `github_description` is consulted only as a *suggestion in Step 2c (or in Step 2a's gap-fill)* on first run; afterward the brief wins. If the user later updates the GitHub description manually (via the GitHub UI), it is *not* pulled back into the brief. Mitigation: this is correct behavior — the brief is the source of truth. The Change 5 paragraph documents that the brief→GitHub direction is the synced one; the reverse is intentional drift.

- **Risk: Step 2c's six-questions-in-one-prompt may be cognitively heavy.** The current Step 5 four-question prompt already exists; this RFC extends it to six. Mitigation: the AskUserQuestion UI presents each question with a single pre-fill suggestion plus an `Other` text input — the user can accept all defaults with six clicks. The "Why" of consolidating six into one prompt is to make first-run setup feel like a single decision point rather than three separate gates.

- **Risk: Change 1's bullet-list manipulation may diverge from the rest of `skills/sync/SKILL.md`'s style on a careful read.** Mitigation: Change 8's verification step #7 (`grep "two sequential AskUserQuestion calls"`) is the canary for an incomplete Change 1; if any of the old Step 2 phrasing persists, the implementer is told to re-do Change 1.

- **Risk: the gap-fill AskUserQuestion (Change 1's Step 2a end) writes its answers into the brief via the migration sub-rule of Change 3, but the order of operations is `Step 2a (gap-fill) → ... → Step 5 (write brief)` with several steps in between.** If `/sync` aborts mid-flow (network error during `gh repo view`, file write failure, etc.), the gap-fill answers are lost and the brief still lacks valid identity. Mitigation: the gap-fill prompt is small (1-2 questions) and the answers are deterministic from `project_slug` and user input; on the next `/sync` run, the same prompt re-fires with the same suggestions. No data is lost in any user-meaningful way; the user re-clicks defaults.

- **Risk: distinction between unquoted-empty and quoted-empty front-matter values is subtle.** A user reading their brief might not notice the difference between `description:` (re-prompts on next run) and `description: ""` (explicit skip, no re-prompt). Mitigation: Change 3's create template always writes `description: ""` when the user skipped (so the next run sees the explicit skip); the migration "Case B" path also writes `description: ""` when the user selects skip during gap-fill. The only path to unquoted-empty in the brief is hand-editing — which is precisely the user-intent we want to interpret as "I'm not done yet, please re-prompt." The Step 8 "Brief parse status" report makes the distinction visible.

- **Open question: should the front matter support `aliases` for the project name?** Some projects have a long display name and a short slug (e.g. `Bytewyrd Workflow Plugin` vs `bytewyrd`). Today, `project_slug` is used in CLI examples and `project_name` in headings. Both are derived in Step 1 (slug) and Step 2 (name) respectively. Whether to expose explicit aliases (e.g. `name: ...`, `short_name: ...`) is deferred to a follow-up RFC. This RFC keeps the schema minimal — `name`, `description`, plus reserved unused keys for the future.

- **Open question: should the Step 2b "do you want to create a brief?" prompt have a third option to import from a URL or template?** A future RFC may add `--brief-from <url-or-path>` invocation that pre-populates the unified prompt's defaults from a remote source. Out of scope for this RFC.

- **Open question: how should the gap-fill answers persist into the brief when the brief already has body content?** Today the gap-fill answers are written into the front matter (Change 3 migration sub-rule). The brief's body (Problem / Goals / Non-Goals / Constraints sections) is untouched. If a user wants those sections filled in too, they must edit the brief directly or delete it and re-run `/sync` to invoke Step 2c. A future RFC may add a "fill in the body sections too" prompt; out of scope here.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-09-best-practices-content-and-tooling.md` (Done).** That RFC introduced the `bootstrap-content-version` marker on the bootstrap skill (since renamed to `skills/sync/SKILL.md`) and the `SessionStart` hook that compares it against the project's local copy. This RFC bumps that marker as part of Change 7 — the mechanism is reused unchanged. No conflict.

- No other open or in-progress RFCs touch `skills/sync/SKILL.md` or `docs/project-brief.md`. The braindump entries `Best-practice extraction generalization` and `/refactor command` are independent of this work.
