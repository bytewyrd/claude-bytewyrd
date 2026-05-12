---
name: best-practices-record
description: Use when the user wants to capture a single best practice into the global cross-project pool at ~/.claude/BEST_PRACTICES.md — typically after seeing a pattern repeat across projects, or learning a stack-level lesson that future projects should ship with from day one.
---

# Record Best Practice

## Overview

Append a single, user-confirmed best-practice entry to the **global** `~/.claude/BEST_PRACTICES.md`. This file is the cross-project pool — it accumulates lessons that future projects should ship with from day one. Entries from here are reviewed and pulled into the plugin's `sync/SKILL.md` via `/best-practices-sync`; once promoted, they are removed from the global file by the sync skill.

**When to use this skill vs. `/best-practices-extract`:**

- **Mid-session, surfaced from work just done** → use `/best-practices-extract`. Its approval flow includes a bulk-checkbox Promotion Step that presents every generalizable entry with an agent-recommended default (checked for broadly generalizable, unchecked for narrowly generalizable). Confirming the batch writes the checked entries to both `docs/BEST_PRACTICES.md` and `~/.claude/BEST_PRACTICES.md` in one pass.
- **Stated from scratch, not anchored to a session** → use this skill. Pattern recognized after the fact ("I keep seeing the same testing mistake across projects"), a stack-level lesson you want to record without a project session as its anchor, or a recovery path for an entry the bulk checkbox in `/best-practices-extract` missed or failed to write.

Both skills run the same triage-and-lift procedure (see `../best-practices-extract/TRIAGE-AND-LIFT.md`), so the resulting entry has the same quality bar regardless of which path produced it. The confirmation UX is also aligned: in `record` the user confirms a one-row checkbox; in `extract` the user confirms a multi-row checkbox. Both surface the agent's recommendation (checked vs. unchecked) based on the triage result.

## Inputs

The user invokes this skill with a single sentence or short paragraph stating the practice. If the invocation lacks the practice text, ask: "What is the best practice to record?" — wait for the answer before proceeding.

## Triage Step (Before Categorization)

Apply the three portability questions defined in [`../best-practices-extract/TRIAGE-AND-LIFT.md`](../best-practices-extract/TRIAGE-AND-LIFT.md):

1. Framework portability
2. Project portability
3. Audience portability

`/best-practices-record` writes only to the global pool (`~/.claude/BEST_PRACTICES.md`). The global pool is for *generalizable* entries only — there is no global "project-specific" section, by design.

- **All three yes** → generalizable; continue to the Lift Step below.
- **Any one no** → refuse, with this exact message:

  ```
  This statement looks project-specific (failed: <which question>). Project-specific
  learnings belong in the project's docs/BEST_PRACTICES.md under the
  ## Project-Specific section, not in the global pool.

  Use /best-practices-extract instead, which routes project-specific entries
  to the project file. If you believe the underlying principle is generalizable
  but you've stated it instance-by-instance, re-state the principle and re-invoke
  /best-practices-record.
  ```

  Stop. Do not proceed to categorization or write anything.

## Lift Step

Apply the two-pass + verification procedure defined in [`../best-practices-extract/TRIAGE-AND-LIFT.md`](../best-practices-extract/TRIAGE-AND-LIFT.md):

1. **Pass 1 — Strip the instance**: rewrite the user's statement with project-specific identifiers replaced by their role.
2. **Pass 2 — Name the domain**: prepend the canonical domain prefix that matches the destination section.
3. **Verification — re-read in isolation**: confirm the lifted statement survives the two-years-later test.

Show the user the lifted version alongside their original. The user picks which one is recorded — the lifted version is the recommendation, but the user can override.

```
You said:
  <user's original statement>

Lifted to principle:
  <Pass 2 output>

Which version do you want to record?
- Option 1: Lifted (recommended) — generalizable, ready for the global pool
- Option 2: Original — record as-is (only do this if Lifted lost important meaning)
- Option 3: Edit — type a corrected version
```

If the user picks Original *and* the Original still contains project-specific identifiers, refuse with: "The original contains project-specific identifiers (`<identifier>`). Either pick the Lifted version or use `/best-practices-extract` instead." This is a hard gate — `/best-practices-record` writes only to the global pool, and the global pool admits no project-specific entries.

## Categorization Step

Determine the section the entry belongs in. The global file uses the same section headers as `sync/SKILL.md`. The categorization also decides whether the entry will eventually land in a *general* (always-emitted) sync section, or a *stack-specific* (detection-gated) section — this matters for promotion: stack-specific entries only ship to projects that use the matching tooling.

| Header | Kind | Use for |
|---|---|---|
| `Testing` | General | TDD, testing pyramids, what to mock, integration vs unit boundaries |
| `Architecture` | General | SOLID, dependency direction, hexagonal/onion layering, module boundaries, public-API discipline, cross-cutting structural patterns (tracing, config, lifecycle) |
| `Documentation` | General | Docs-first practices, README/CONTRIBUTING/ARCHITECTURE scope, comment discipline |
| `Security` | General | Secret handling, input validation, dependency hygiene, privilege boundaries |
| `Error Handling` | General | Error types, panics vs returned errors, retry policy, failure observability |
| `Workflow` | General | Cross-project dev practices (commits, PRs, branches, CI gates) |
| `Pitfall` | General | Cross-project gotchas (tooling, sandbox, environment) |
| `Claude Code` | General | Working with the Claude Code agent across projects |
| `<Language>` | Stack-specific | Language-specific rules: `Rust`, `Go`, `JavaScript / TypeScript`, `Svelte`, `Python`, `Ruby`, `Rails` |
| `<Stack>` | Stack-specific | Stack-specific rules: `Kubernetes / CUE / kapply`, `Terraform / Terragrunt` |

If you cannot map the user's statement to one of the above, propose a new header — but only when nothing existing fits. Adding sections inflates the table of contents; reuse over invent.

When the entry would have gone under a hypothetical `Design` or `Boundaries` header, route it to `Architecture` instead — both are architectural concerns and bootstrap consolidates them under one header. Tracing, config, and lifecycle entries also live under `Architecture`.

## Confirmation Step (Always Required)

The agent runs the three portability questions against the lifted entry (see Triage Step), then
computes a *default* from the triage confidence:

- All three portability questions answered with high confidence "yes" → default the checkbox to
  **checked** with tag `[recommended: record to global pool]`.
- At least one portability question landed with lower confidence → default the checkbox to
  **unchecked** with tag `[recommended: reconsider — entry may not transfer cleanly]`.

Issue one `AskUserQuestion` with `multiSelect: true` and a single row showing the entry and its
recommendation tag. The user either accepts the recommendation (single confirm) or flips the box.

- If the user confirms the box **checked** → write to `~/.claude/BEST_PRACTICES.md` as described
  in Write Format below.
- If the user confirms the box **unchecked** → abort the write and report: "Entry not recorded.
  If this is a project-specific learning, consider using `/best-practices-extract` instead to
  route it to the project's `docs/BEST_PRACTICES.md`."

## Write Format

Format matches `best-practices-extract`:

```markdown
- _<Category>_: One or two sentences max.
```

The italic category label uses a canonical abbreviated form for each section header — never the verbatim header text. Use this table:

| Section header | Italic label to use |
|---|---|
| `## Testing` | `_Testing_` |
| `## Architecture` | `_Architecture_` |
| `## Documentation` | `_Documentation_` |
| `## Security` | `_Security_` |
| `## Error Handling` | `_Error Handling_` |
| `## Workflow` | `_Workflow_` |
| `## Pitfall` | `_Pitfall_` |
| `## Claude Code` | `_Claude Code_` |
| `## Rust` | `_Rust_` |
| `## Go` | `_Go_` |
| `## JavaScript / TypeScript` | `_JS/TS_` |
| `## Svelte` | `_Svelte_` |
| `## Python` | `_Python_` |
| `## Ruby` | `_Ruby_` |
| `## Rails` | `_Rails_` |
| `## Kubernetes / CUE / kapply` | `_K8s_`, `_K8s/CUE_`, or `_kapply_` (use `_K8s_` for general Kubernetes best-practices — scheduling, security, probes, namespaces; use `_K8s/CUE_` for CUE-schema and manifest-rendering topics; use `_kapply_` for kapply-tool-specific behavior) |
| `## Terraform / Terragrunt` | `_Terraform_` or `_Terragrunt_` (use the specific tool the entry applies to) |

Using the verbatim header (e.g., `_JavaScript / TypeScript_`) instead of the canonical abbreviation (`_JS/TS_`) breaks the dedup logic in `best-practices-sync` — the existing sync entries use the abbreviated forms.

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

Format matches `best-practices-extract`:

```markdown
- _<Category>_: One or two sentences max.
```

If the target section header (`## <Category>`) does not exist, append it (with a blank line before) before writing the entry.

**Header backfill for existing global files.** If the file exists but its top-of-file lacks the
"## Where do entries live, and why?" header (any global file created before this RFC), insert the
rationale block (everything from `## Where do entries live, and why?` through the line ending
`Format: _Category_: Concise statement...`) immediately after the existing H1 (`# Global Best
Practices` or whatever H1 the file already has) and before the first H2. Do not modify any
existing entries. Run the backfill check on every invocation — it is idempotent (the block is
either present or absent; presence skips the backfill).

## Red Flags — Stop and Reconsider

- The statement is more than 2 sentences → ask the user to compress it before recording.
- The statement is project-specific ("our deploy script does X") → handled by the Triage Step refusal above, but if it slips through Triage, refuse here too.
- The statement is a library quirk ("the K8s HPA controller does X") → that's library documentation; suggest looking it up via Context7 / Exa instead of recording.
- The lifted version differs from the original only in cosmetic ways (whitespace, capitalization) → the lift didn't actually change anything; either the original was already lifted, or Pass 1 missed identifiers. Re-check.
- A near-duplicate already exists under the target section → present the existing entry and ask whether to replace, append, or skip.
