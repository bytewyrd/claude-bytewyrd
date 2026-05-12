---
name: best-practices-extract
description: Use when a session contained design decisions, architectural choices, discovered pitfalls, or established patterns worth preserving — triggered automatically before compaction, manually at any time, or at the end of a development branch.
---

# Extract Best Practices

## Overview

Selectively extract non-obvious learnings from a session and append them to the project's
`BEST_PRACTICES.md`. Quality over quantity — the value is in the filter, not the writing.

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

GENERALIZABLE → ~/.claude/BEST_PRACTICES.md (eligible) and docs/BEST_PRACTICES.md (this project)

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

To promote a generalizable entry to the *global* file (`~/.claude/BEST_PRACTICES.md`), the user invokes `/best-practices-record` separately — `best-practices-extract` writes only to the project file. This separation is intentional: extraction is high-velocity and per-session; recording into the global pool is a deliberate cross-project decision.

## Write Format

Append approved items under the appropriate section in `docs/BEST_PRACTICES.md`:

```markdown
- _[Category]_: Concise statement. One or two sentences max.
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

## Mark Extraction Done (Required — Last Step)

After every invocation of this skill, regardless of whether any entries were added, run:

```bash
mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done
```

This writes the sentinel file the `PreCompact` hook uses as its release condition. The sentinel signals "extraction has run in this session" — the next compaction trigger will be allowed through without re-blocking.

The sentinel-write runs on **every normally-completing exit path**:

- After approved entries are written to `docs/BEST_PRACTICES.md`.
- After the user declined all candidates (`none`).
- After the skill exited with "Nothing new to capture this session" because nothing passed triage and filtering.
- After any partial-success path (e.g., one entry approved, one declined).

The only cases where the sentinel is **not** written are: a hard failure of the skill itself (e.g., the disk is full when writing `docs/BEST_PRACTICES.md`), or session termination mid-execution before the final step is reached. In either case, the next compaction will re-block, which is the correct behavior — the user re-runs the skill.

Do not skip this step "because nothing was written." The skill ran; the gate is satisfied; the sentinel records that. Skipping the sentinel leaves the `PreCompact` hook in an unresolved-block state and the user has to bypass manually.

## When to Run

- **Automatically and enforced:** The `PreCompact` hook in `.claude/settings.json` blocks compaction until this skill runs. On the first compaction trigger of a session, the hook returns `{"decision": "block"}` and injects a system reminder instructing the agent to invoke `/best-practices-extract`. The skill then runs, the user approves or declines per-candidate, the skill writes the sentinel file at `.bytewyrd/precompact-extraction-done`, and the next compaction trigger is allowed through. The block-and-release pattern makes extraction a true gate rather than a suggestion.
- **Manually:** Invoke this skill at any time, especially before ending a long design/feature session — running it manually also writes the sentinel, so the next automatic compaction passes through cleanly.
- **Branch completion:** Natural checkpoint in the `finishing-a-development-branch` workflow.
- **Bypass:** To compact without extraction (e.g., the session has no learnings worth capturing and the user wants to skip the gate), run `touch .bytewyrd/precompact-extraction-done` then `/compact`. The bypass is documented in the hook's `reason` field, surfaced to the user at the moment the block is encountered.

## Red Flags — Stop and Reconsider

- You're about to write more than 2 generalizable items from one session → you're being too permissive at the triage step. Re-apply the audience-portability question to each.
- A candidate passed triage but the lifted text still mentions a project-specific identifier → Pass 1 missed something. Strip again or demote to project-specific.
- A candidate failed triage but you're about to write it to a thematic section (not `## Project-Specific`) → routing error. Move it to `## Project-Specific` or re-evaluate the triage decision.
- The lifted entry is so abstract it could appear in any project's best practices ("Use proper error handling") → Pass 2 over-lifted. Add the domain back, or skip — over-abstraction is just as bad as under-abstraction.
- Entry is longer than 2 sentences → consolidate or skip.
- You're adding without asking the user → violation.
