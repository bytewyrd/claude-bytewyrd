---
name: best-practices-extract
description: Use at the end of a meaningful session to extract non-obvious learnings into the project's docs/BEST_PRACTICES.md. Generalizable entries can optionally be promoted to the global cross-project pool (~/.claude/BEST_PRACTICES.md) via a single bulk-checkbox prompt in the same approval flow — the agent pre-selects defaults from portability triage and the user confirms or adjusts in one step. Project-specific entries stay project-local under ## Project-Specific.
---

# Extract Best Practices

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

## Extraction Pass

Scan the conversation for:
- Design decisions that are non-obvious from reading the code
- Architectural constraints that affect future decisions
- Patterns confirmed as "the right way" for this project
- Pitfalls, anti-patterns, or failed approaches discovered
- Stack/domain-specific gotchas (EVE API, Rust async, Vue reactivity edge cases, etc.)

Collect these as raw candidates. Do not filter, generalize, or rewrite at this step — that happens in Triage and Lift.

## Triage Step (Before Anything Else)

Apply the three portability questions defined in [`TRIAGE-AND-LIFT.md`](./TRIAGE-AND-LIFT.md):

1. Framework portability
2. Project portability
3. Audience portability

For each raw candidate:
- **All three yes** → generalizable; carry it to the Lift Step below.
- **Any one no** → project-specific; carry it to the Project-Specific Routing step below.

Do not present any candidate to the user before triage. Triage decides destination, and the user should see candidates already grouped by destination.

## Project-Specific Routing

For candidates that failed triage:

- The candidate is still valuable to *this* project. Keep it, but in a clearly-labeled section.
- The destination section is `## Project-Specific` in `docs/BEST_PRACTICES.md`. If the section does not exist, create it (with the introductory line described in the Write Format section below).
- Do **not** lift these entries — keep the project-specific names, file paths, and identifiers because that's what makes them useful in the project file. The trade-off is that they don't transfer; that's by design.
- Project-specific entries are skipped by `best-practices-sync` (which only reads global entries) and never reach `~/.claude/BEST_PRACTICES.md` or the bootstrap content.

## Mandatory Filters

After triage, apply these additional skip filters to *generalizable* candidates only (project-specific candidates have their own routing above):

- Already documented in `CLAUDE.md`, `BEST_PRACTICES.md`, or a code comment
- Technology behavior that belongs in library docs, not project conventions (K8s quirks, serde edge cases, API semantics — look these up, don't memorize them here)
- One-off (environment setup, temporary workaround, single-use debugging step)
- Inferrable by reading the code for 5 minutes
- Already covered by an existing entry in `~/.claude/BEST_PRACTICES.md` or the project's `docs/BEST_PRACTICES.md`

If nothing passes triage and filtering, say so — "Nothing new to capture this session." Do not pad.

## Lift Step

Apply the two-pass + verification procedure defined in [`TRIAGE-AND-LIFT.md`](./TRIAGE-AND-LIFT.md):

1. **Pass 1 — Strip the instance**: remove project names, file paths, type names, function names, module names, and version numbers. Replace each with the role it played.
2. **Pass 2 — Name the domain**: prepend the technology, layer, or domain the principle applies to (`Vue:`, `Rust:`, `Architecture:`, `Testing:`, etc.).
3. **Verification — re-read in isolation**: ask "would this entry be useful to someone in two years, with no context?" If no, lift higher; if still no, demote to project-specific.

Each generalizable candidate must complete the lift before being shown to the user. The user sees the lifted version, not the raw extraction — the raw extraction is intermediate work.

## User Confirmation (Always Required)

Present candidates as a numbered list with category and one-line context, grouped by destination so the user sees the routing at a glance:

```
Found 3 candidates (2 generalizable, 1 project-specific):

GENERALIZABLE → docs/BEST_PRACTICES.md (this project) [+ optional: ~/.claude/BEST_PRACTICES.md via Promotion Step]

1. [Architecture] Subsystem boundaries own their domain assembly; configuration layers only
   resolve and forward inputs. Pushing assembly into a config layer creates a god module
   that knows about every subsystem.

2. [Vue] When a wrapper component renders arbitrary slot content and needs to share state
   with it, use `provide` / `inject` — slot content has no prop access to its wrapper.

PROJECT-SPECIFIC → docs/BEST_PRACTICES.md (this project only, ## Project-Specific section)

3. [Project-Specific] The `sync` skill must read from the worktree (cwd-derived
   `git rev-parse --show-toplevel`), never from `git rev-parse --git-common-dir`.

Add any? (1, 2, 3, generalizable, project-specific, all, none)
```

The user can accept by index or by group. Generalizable entries are written to `docs/BEST_PRACTICES.md` under the appropriate thematic section (`## Architecture`, `## Vue`, etc.). Project-specific entries are written to `docs/BEST_PRACTICES.md` under `## Project-Specific`.

Never write to `BEST_PRACTICES.md` without explicit user approval on specific items.

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
2. After the project-file write succeeds, write each promoted entry (same lifted text, same
   canonical category label) to `~/.claude/BEST_PRACTICES.md` in the matching section.

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

## Write Format

Append approved items under the appropriate section in `docs/BEST_PRACTICES.md`:

```markdown
- **[YYYY-MM-DD]** _[Category]_: Concise statement. One or two sentences max.
```

Categories for **generalizable** entries: `Testing`, `Architecture`, `Documentation`, `Security`, `Error Handling`, `Workflow`, `Pitfall`, `Claude Code`, plus language/stack categories (`Rust`, `Go`, `JS/TS`, `Svelte`, `Python`, `Ruby`, `Rails`, `K8s`, `K8s/CUE`, `kapply`, `Terraform`, `Terragrunt`). Match the canonical abbreviated label used in `skills/best-practices-record/SKILL.md` so entries are interchangeable across files.

Categories for **project-specific** entries: use `_Project-Specific_` as the italic label and place under the `## Project-Specific` section.

Create the section header if it doesn't exist yet. The `## Project-Specific` section uses this introductory text the first time it is created:

```markdown
## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see `skills/best-practices-extract/TRIAGE-AND-LIFT.md`.
```

## Post-Write Check

Verify the project's root `CLAUDE.md` references `BEST_PRACTICES.md`. If not, add:

```
For accumulated session learnings, see [BEST_PRACTICES.md](BEST_PRACTICES.md).
```

## When to Run

- **Automatically:** `PreCompact` hook fires before conversation compaction (configured in `.claude/settings.json`)
- **Manually:** Invoke this skill at any time, especially before ending a long design/feature session
- **Branch completion:** Natural checkpoint in the `finishing-a-development-branch` workflow

## Red Flags — Stop and Reconsider

- You're about to write more than 2 generalizable items from one session → you're being too permissive at the triage step. Re-apply the audience-portability question to each.
- A candidate passed triage but the lifted text still mentions a project-specific identifier → Pass 1 missed something. Strip again or demote to project-specific.
- A candidate failed triage but you're about to write it to a thematic section (not `## Project-Specific`) → routing error. Move it to `## Project-Specific` or re-evaluate the triage decision.
- The lifted entry is so abstract it could appear in any project's best practices ("Use proper error handling") → Pass 2 over-lifted. Add the domain back, or skip — over-abstraction is just as bad as under-abstraction.
- Entry is longer than 2 sentences → consolidate or skip.
- You're adding without asking the user → violation.
- You're about to leave every checkbox checked when the agent recommended only some → the global bar is stricter than the project bar. The agent's pre-checked defaults reflect triage confidence; if you find yourself overriding most defaults to "promote everything," your triage was permissive. Default to trusting the agent's recommendation and only flip boxes where your judgement diverges.
