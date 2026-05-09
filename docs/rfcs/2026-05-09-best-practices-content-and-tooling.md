---
rfc: "2026-05-09-best-practices-content-and-tooling"
title: "Best Practices: Content Library and Tooling Improvements"
author: "Rodrigo Kochenburger"
status: "Done"
created: "2026-05-09"
drop_reason: ~
---

## Summary

Replace the thin starter content in `bootstrap/SKILL.md` with an opinionated, prescriptive best-practices library — one universal section that applies to every project (TDD, software architecture and boundaries, documentation as a first-class citizen, observability, error handling, security hygiene), plus expanded language and stack sections (Go, Rust, TS/JS, Svelte, Ruby, Rails, k8s + CUE + `kapply`, Terraform + Terragrunt). At the same time, rename the existing `extract-best-practices` skill to `best-practices-extract`, add a new `best-practices-record` skill that writes individual learnings to a global `~/.claude/BEST_PRACTICES.md`, and add a plugin-local `best-practices-sync` skill (kept inside `.claude/skills/`, not exported) that pulls vetted global entries back into this plugin's `bootstrap/SKILL.md` so they propagate to every freshly bootstrapped project. The content and tooling are co-designed because the new skills need a target naming convention and storage layout that the bootstrap content references, and the bootstrap content needs section headers that the extract/record/sync skills know how to find and append into.

## Should we do this?

**Yes.** The current `bootstrap/SKILL.md` seeds two or three entries per language and almost nothing universal — it leaves new projects without the engineering discipline that should be the baseline. The naming inversion (`extract-best-practices` vs the planned `best-practices-record` / `best-practices-sync`) is also worth fixing now, before the verb-prefix convention spreads to more skills. Doing both in one RFC keeps the migration coherent: hook messages, plugin manifest entries, and starter content all land in the same change.

## Current state

`skills/bootstrap/SKILL.md` writes a starter `docs/BEST_PRACTICES.md` with these sections:

- **Pitfall** (2 entries — sandbox `git add` and `mkdir`/`cp` quirks)
- **Workflow** (6 entries — long-running processes, `git fetch`, quality gate, small PRs, commit-message rationale, README scope)
- **Claude Code** (3 entries — evidence-based diagnosis, verifying subagent output, prefer specialized agents)
- **Architecture** (1 entry — structured tracing via `tracing` / OpenTelemetry)
- **Rust** (3 entries — toolchain via rustup, `thiserror`/`anyhow`, `cargo check`)
- **JS/TS** (2 entries — `--frozen-lockfile`, `strict: true`)
- **Python** (2 entries — type annotations as you write, `uv`)
- **Go** (2 entries — error handling, `go vet` + `golangci-lint`)

The content reflects the plugin author's accumulated Claude Code experience but is silent on the engineering discipline a new project should ship with. There are no entries for testing methodology, design principles, software boundaries, security hygiene, or documentation discipline. There are no entries for Svelte, Ruby, Rails, infrastructure (Terraform / Terragrunt), or Kubernetes (CUE + `kapply`).

`skills/extract-best-practices/SKILL.md` extracts non-obvious project-specific learnings from a session and appends them to the project's `docs/BEST_PRACTICES.md` after explicit user confirmation. Its quality filter is: "would a developer joining this project specifically benefit from reading this — not a developer joining any project of this language or stack?" That filter is the whole point of the skill — it defines what belongs in a project-local file.

The current name `extract-best-practices` puts the verb first. Two adjacent skills are planned:
- One that records a best practice into a global file (cross-project).
- One that pulls vetted global entries back into this plugin's bootstrap content for redistribution.

Verb-first naming makes related skills sort apart in any alphabetical listing (`bootstrap`, `extract-best-practices`, `git-branch-cleanup`, `record-best-practice`, ...). Noun-first naming groups them naturally (`best-practices-extract`, `best-practices-record`, `best-practices-sync`).

References to `extract-best-practices` exist in:
- `.claude-plugin/plugin.json` (line 12) — registers the skill
- `.claude-plugin/hooks/hooks.json` (lines 8, 30) — `PreCompact` and `Stop` hook messages
- `.claude/settings.json` (lines 13, 53) — same hooks for the plugin's own checkout
- `skills/bootstrap/SKILL.md` (lines 339, 631, 671, 1043) — the starter `BEST_PRACTICES.md`, hook content, and Step 8 follow-up reminders
- `skills/extract-best-practices/SKILL.md` (line 2) — the skill's own name field
- `docs/BEST_PRACTICES.md` (line 7) — this plugin's own best-practices file

There is no global `BEST_PRACTICES.md` today and no mechanism for a learning captured in one project to influence the bootstrap content of the next.

## Analysis / Options

There are two coupled decisions: how to *grow* the bootstrap content over time, and how to *name* the skills that interact with best-practices files.

### Decision 1 — Where do new best practices live, and how do they reach future projects?

**Option A — Global file + explicit sync (recommended).**
A single `~/.claude/BEST_PRACTICES.md` is the user's personal accumulator across every project. `best-practices-record` appends to it directly. A separate `best-practices-sync` skill, run only inside this plugin's checkout, reads the global file and proposes additions to `bootstrap/SKILL.md` for the user to approve and commit. This keeps the plugin's distributed content under explicit human review while letting the global file accumulate freely.

**Option B — Per-project extraction only, no global pool.**
Keep the world flat: every project has its own `docs/BEST_PRACTICES.md` and learnings die with the project unless the user remembers to copy them. This is the status quo. It loses high-quality learnings and produces no compounding effect across projects.

**Option C — Auto-merge global file into bootstrap on each plugin build.**
Hook the merge into a release script. Avoids manual sync but distributes whatever is in the global file unfiltered, including project-specific notes that slipped past the record-time filter. Risks polluting bootstrap content for every consumer with one user's local quirks.

**Recommendation: Option A.** The global file is high-velocity (record while still in flow), the plugin file is high-curation (review before distribution), and the sync skill makes the curation step explicit — a `git diff` the human approves. Option C trades quality for one less command. Option B is the status quo and is what this RFC exists to change.

Because `best-practices-sync` is only meaningful inside this plugin's own checkout (its job is to mutate `skills/bootstrap/SKILL.md`), it is not exported to consumers of the plugin. It lives at `.claude/skills/best-practices-sync/SKILL.md` — alongside the plugin's own dogfooded settings — and is omitted from the `skills` array in `.claude-plugin/plugin.json`. Only `best-practices-extract` and `best-practices-record` are useful in any project and therefore distributed via the plugin manifest.

### Decision 2 — Skill naming convention.

**Option A — Verb-first (status quo): `extract-best-practices`, `record-best-practice`, `sync-best-practices`.**
Matches the `rfc-*` family already in this plugin (e.g. `rfc-new`, `rfc-approve`) inverted — `rfc-*` is noun-first. Adding `extract-best-practices` already broke the family pattern; adding two more verb-first skills compounds the inconsistency.

**Option B — Noun-first (recommended): `best-practices-extract`, `best-practices-record`, `best-practices-sync`.**
Sorts together in any alphabetical listing. Matches the `rfc-*` convention (noun-first, verb-suffix). Reads as "best-practices, then the verb" which is how a user thinks about the action.

**Recommendation: Option B.** The cost is a one-time rename of one existing skill (and four reference sites). The value compounds — every future best-practices skill stays in the family.

### Decision 3 — Form of the universal section in `bootstrap/SKILL.md`.

**Option A — Append a small set of universal sections after the existing base content; expand the existing Architecture block to absorb design/boundaries entries (recommended).**
Universal entries become a focused group of *non-overlapping* sections: `Testing`, `Architecture`, `Documentation`, `Security`, `Error Handling`. Module/package boundaries, dependency direction, hexagonal/onion layering, SOLID — these are all forms of *architecture* and live under the existing `## Architecture` header (which today carries the single tracing entry). New top-level sections are added only for `Testing`, `Documentation`, `Security`, and `Error Handling`. Language sections (`Rust`, `JS/TS`, etc.) continue to be appended below these for the languages bootstrap detects.

**Option B — Inline universal entries into the existing Workflow / Architecture sections.**
Less new structure but conflates universal engineering principles ("write tests before the code under test") with project-mechanics workflow ("run `git fetch --all` at session start"). Loses the ability to point a developer at "the design principles entries" as a unit.

**Option C — One section per concept (Testing, Design, Boundaries, Documentation, Security, Error Handling, Architecture).**
Maximally granular, but introduces overlap: `Design` and `Boundaries` are both architectural concerns, and a reader has to guess which header a "dependency direction" rule went into. Adds two extra TOC entries that earn their keep only on a much larger entry set than this RFC delivers.

**Recommendation: Option A.** Five tightly-scoped sections is the right cardinality at this stage. Each header has a clear, non-overlapping scope: `Testing` is about how tests are written and what level they target; `Architecture` is about structure (SOLID, boundaries, dependency direction, layering, observability hooks); `Documentation` is about the artifacts and their audiences; `Security` is about secret/privilege/dep hygiene; `Error Handling` is about error propagation, observability, and idempotency. If `Architecture` later grows past ~12 entries, splitting it then is cheap; pre-splitting it now is premature.

## Drawbacks

- **Bootstrap output gets longer.** The pre-populated `docs/BEST_PRACTICES.md` grows from roughly 30 entries to roughly 100. Some projects will skim it; some will treat the entries as gospel. Mitigation: every entry stays one-to-two sentences (already the format rule) and the file's introduction makes clear the entries are *defaults to question*, not commandments. Mitigation, part 2 — bootstrap is stack-aware: language and stack sections (Rust, Svelte, Ruby, Rails, K8s, Terraform, …) are gated on detection (Step 9a) and are only emitted when a project actually uses the relevant tooling. The universal block (Testing, Architecture, Documentation, Security, Error Handling) is the only content every project receives unconditionally, and it is intentionally small. Mitigation, part 3 — `best-practices-record` categorizes each captured entry as either general (universal section) or stack-specific (language/stack section); when `best-practices-sync` promotes a stack-specific entry, it lands in the matching detection-gated bootstrap block, so a future Ruby-only project never sees a Terraform entry it doesn't need. Mitigation, part 4 — when `best-practices-sync` promotes an entry into `bootstrap/SKILL.md`, it removes that entry from `~/.claude/BEST_PRACTICES.md` (Step 4 sub-step in Step 3 below); the global file stays small and reflects only entries pending promotion. Mitigation, part 5 — the `SessionStart` hook (Step 5 / Step 6) compares the project's current `docs/BEST_PRACTICES.md` against the version checksum embedded in the latest `bootstrap/SKILL.md` and prints a one-line reminder to re-run `/bootstrap` when the project is behind, so users notice when newly-promoted bootstrap content hasn't been pulled in yet.
- **Opinionated content can be wrong for some teams.** Even within the author's own work, "TDD on every line" is too strong — integration plumbing, exploratory spikes, and one-off scripts are exercised differently. Mitigation: tests are non-negotiable (a feature without tests is incomplete); TDD is the *technique* for writing them on pure logic, where it has the additional value of producing tests-as-documentation — the failing test demonstrates the component's intended interface and usage shape, which is invaluable when discussing design or onboarding new contributors. The bootstrap entries phrase TDD as a discipline that applies cleanly to algorithmic and decision-logic code (parsers, business rules, state machines), describe the design-feedback value explicitly, and acknowledge that integration and IO-heavy code is exercised at a different layer. The mitigation is in the phrasing, not in any opt-out toggle.
- **The sync skill creates a maintenance loop.** Someone has to actually run `best-practices-sync` for the global pool to reach new projects. If nobody does, the pool stagnates and bootstrap content drifts from real practice. Mitigation: the skill is fast and idempotent — running it whenever the plugin author touches this repo is realistic. The cost of forgetting is low (entries stay in the global file, available to that user). Mitigation, part 2 — the `Stop` hook in `.claude-plugin/hooks/hooks.json` and `.claude/settings.json` (Steps 5 and 6 below) detects when the session's cwd is the bytewyrd-workflow plugin checkout (heuristic: `pwd` ends in `/claude-bytewyrd-workflow` or contains a `.claude-plugin/plugin.json` whose `name` is `bytewyrd-workflow`) and, when so, appends a one-line reminder to run `/best-practices-sync` if `~/.claude/BEST_PRACTICES.md` has any entries. The reminder is a low-cost prompt, not a forced gate.
- **Renaming a skill is a breaking change in principle.** In practice this plugin currently has a single user (the author), so the rename has no external impact. The change is documented in the repository changelog for completeness; no migration aid is required.
- **Global file location is opinionated (`~/.claude/BEST_PRACTICES.md`).** Users on systems where `$HOME` isn't `/home/<user>` (rare in practice on this plugin's target machines) need to override. Mitigation: the skill resolves the path via `$HOME` and falls back to the OS home directory; no override is needed for standard setups.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Rename | `skills/extract-best-practices/` → `skills/best-practices-extract/` | Existing skill renamed; directory is moved as a unit, no content changes inside SKILL.md other than the `name:` frontmatter field |
| Modify | `skills/best-practices-extract/SKILL.md` | Update `name: extract-best-practices` to `name: best-practices-extract`. No other changes required to skill behavior |
| Create | `skills/best-practices-record/SKILL.md` | New skill: appends a single user-supplied learning to `~/.claude/BEST_PRACTICES.md`, creating the file with a header if absent |
| Create | `.claude/skills/best-practices-sync/SKILL.md` | New skill, kept **inside the plugin's own `.claude/skills/`** (not in `skills/`, not exported via `plugin.json`): read `~/.claude/BEST_PRACTICES.md`, diff against the in-tree `bootstrap/SKILL.md` starter content, present additions for approval, append approved entries to the matching section of `bootstrap/SKILL.md`, and remove the promoted entries from `~/.claude/BEST_PRACTICES.md`. Only meaningful inside this plugin's checkout; therefore lives in the plugin's local-skill directory rather than the exported `skills/` directory |
| Modify | `.claude-plugin/plugin.json` | Replace `./skills/extract-best-practices` with `./skills/best-practices-extract`; add `./skills/best-practices-record`. Do **not** add `best-practices-sync` — it is plugin-local, not exported |
| Modify | `.claude-plugin/hooks/hooks.json` | Replace every `extract-best-practices` reference with `best-practices-extract` in the `PreCompact` and `Stop` echo commands. Add a `SessionStart` hook for the bootstrap-version reminder. Extend the `Stop` hook with a `best-practices-sync` reminder gated on the plugin-checkout heuristic |
| Modify | `.claude/settings.json` | Same renames as above for the plugin's own checkout (so the local install dogfood works), plus the same `SessionStart` and extended `Stop` hooks |
| Modify | `skills/bootstrap/SKILL.md` | (1) Replace `extract-best-practices` with `best-practices-extract` in: the starter `BEST_PRACTICES.md` introduction, the `PreCompact` and `Stop` hook commands, and the Step 8 follow-up reminders. (2) Expand the existing `## Architecture` block to absorb SOLID / boundaries / dependency-direction entries. (3) Add the universal section block (`Testing`, `Documentation`, `Security`, `Error Handling`). (4) Expand existing language sections. (5) Add new language/stack sections (Svelte, Ruby, Rails, k8s+CUELang+kapply, Terraform+Terragrunt). (6) Embed a content-version checksum/marker that the `SessionStart` hook can compare against the project's bootstrapped file |
| Modify | `docs/BEST_PRACTICES.md` (this repo's own file) | Update the introductory line `Use \`/extract-best-practices\`...` to `Use \`/best-practices-extract\`...`. Do not retroactively re-seed this file with the new universal content — it is a live BP file, not a bootstrap output |

### Steps

#### Step 1 — Rename the existing skill directory and update its frontmatter

Move the directory:

```bash
git mv skills/extract-best-practices skills/best-practices-extract
```

Edit `skills/best-practices-extract/SKILL.md` line 2:

Before:
```markdown
name: extract-best-practices
```

After:
```markdown
name: best-practices-extract
```

No other changes to this file. Its body (overview, extraction pass, mandatory filters, generalization step, user-confirmation requirement, write format, post-write check, when-to-run, red flags) remains exactly as written. The skill's filter — "rule about how this project is built, not how a technology works" — is the contract that `best-practices-extract` honors, and is unchanged.

#### Step 2 — Create the `best-practices-record` skill

Create `skills/best-practices-record/SKILL.md` with this content:

````markdown
---
name: best-practices-record
description: Use when the user wants to capture a single best practice into the global cross-project pool at ~/.claude/BEST_PRACTICES.md — typically after seeing a pattern repeat across projects, or learning a stack-level lesson that future projects should ship with from day one.
---

# Record Best Practice

## Overview

Append a single, user-confirmed best-practice entry to the **global** `~/.claude/BEST_PRACTICES.md`. This file is the cross-project pool — it accumulates lessons that future projects should ship with from day one. Entries from here are reviewed and pulled into the plugin's `bootstrap/SKILL.md` via `/best-practices-sync`; once promoted, they are removed from the global file by the sync skill.

This is the counterpart to `/best-practices-extract`:

| Skill | Scope | Source | Target |
|---|---|---|---|
| `/best-practices-extract` | Project-specific | Current session | `docs/BEST_PRACTICES.md` (in the project) |
| `/best-practices-record` | Cross-project | User-supplied statement | `~/.claude/BEST_PRACTICES.md` (global) |

If the rule describes how a single project is built, prefer `/best-practices-extract`. If the rule describes how a *technology, stack, or engineering practice* should be applied — and would be true for any future project using that stack — use this skill.

## Inputs

The user invokes this skill with a single sentence or short paragraph stating the practice. If the invocation lacks the practice text, ask: "What is the best practice to record?" — wait for the answer before proceeding.

## Categorization Step

Determine the section the entry belongs in. The global file uses the same section headers as `bootstrap/SKILL.md`. The categorization also decides whether the entry will eventually land in a *general* (always-emitted) bootstrap section, or a *stack-specific* (detection-gated) section — this matters for promotion: stack-specific entries only ship to projects that use the matching tooling.

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

Present the entry as it will be written and ask for confirmation:

```
About to append to ~/.claude/BEST_PRACTICES.md under "## <header>":

- **[YYYY-MM-DD]** _<header>_: <user's statement, lightly edited for the standard format>.

Proceed? (yes / edit / cancel)
```

`yes` → write. `edit` → ask for the corrected text and re-confirm. `cancel` → stop, write nothing.

## Write Format

Format matches `best-practices-extract`:

```markdown
- **[YYYY-MM-DD]** _<Category>_: One or two sentences max.
```

`YYYY-MM-DD` is today's date. The italic category label uses a canonical abbreviated form for each section header — never the verbatim header text. Use this table:

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

Using the verbatim header (e.g., `_JavaScript / TypeScript_`) instead of the canonical abbreviation (`_JS/TS_`) breaks the dedup logic in `best-practices-sync` — the existing bootstrap entries use the abbreviated forms.

## File Bootstrap

If `~/.claude/BEST_PRACTICES.md` does not exist, create it with this header before appending:

```markdown
# Global Best Practices

Cross-project accumulator. Entries here are candidates for promotion into the bytewyrd-workflow plugin's bootstrap content via `/best-practices-sync`. Once promoted, sync removes them from this file.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```

If the target section header (`## <Category>`) does not exist, append it (with a blank line before) before writing the entry.

## Red Flags — Stop and Reconsider

- The statement is more than 2 sentences → ask the user to compress it before recording.
- The statement is project-specific ("our deploy script does X") → suggest `/best-practices-extract` instead.
- The statement is a library quirk ("the K8s HPA controller does X") → that's library documentation; suggest looking it up via Context7 / Exa instead of recording.
- A near-duplicate already exists under the target section → present the existing entry and ask whether to replace, append, or skip.
````

#### Step 3 — Create the `best-practices-sync` skill (plugin-local, not exported)

Create `.claude/skills/best-practices-sync/SKILL.md` (note the path: this skill lives in the plugin's own `.claude/skills/` directory, not in the exported `skills/` directory, because it is only meaningful inside this plugin's checkout) with this content:

````markdown
---
name: best-practices-sync
description: Use inside the bytewyrd-workflow plugin's checkout to promote vetted global best-practice entries into the plugin's bootstrap content. Run after accumulating a few entries via /best-practices-record. Surfaces a diff for the user to approve, appends approved entries to the matching section of skills/bootstrap/SKILL.md so they ship with every freshly bootstrapped project, then removes the promoted entries from ~/.claude/BEST_PRACTICES.md.
---

# Sync Best Practices Into Plugin

## Overview

Promote entries from the user's global pool (`~/.claude/BEST_PRACTICES.md`) into this plugin's distributed bootstrap content (`skills/bootstrap/SKILL.md`), and then remove the promoted entries from the global pool. This is the *only* path for a global entry to reach a freshly-bootstrapped project — the global file is private to the user; the plugin file is what consumers receive.

This skill is plugin-local: it lives at `.claude/skills/best-practices-sync/` inside the plugin checkout and is not exported via `.claude-plugin/plugin.json`. It is only invokable from within the bytewyrd-workflow plugin checkout. If the cwd does not contain `skills/bootstrap/SKILL.md` and `.claude-plugin/plugin.json`, stop with: "best-practices-sync only runs inside the bytewyrd-workflow plugin checkout. cd into the plugin repo and try again."

## Step 1 — Read both files

Read `~/.claude/BEST_PRACTICES.md` (the source). If absent or empty, stop with: "No global entries found at ~/.claude/BEST_PRACTICES.md — nothing to sync."

Read `skills/bootstrap/SKILL.md` (the destination). Locate the language-and-section blocks that get appended to the bootstrapped `docs/BEST_PRACTICES.md`. Each block is identified by its section header (e.g., `## Testing`, `## Architecture`, `## Rust`, `## Kubernetes / CUE / kapply`).

## Step 2 — Compute the candidate set

For every entry in the global file, normalize and dedup against the bootstrap file's same section.

**Normalization rule:** strip from the start of each line, in order:
1. Any `**[...]**` token matching the regex `\*\*\[.*?\]\*\*` followed by surrounding whitespace. This handles both forms:
   - `**[2026-05-09]**` — concrete-date form, used in `~/.claude/BEST_PRACTICES.md`
   - `**[<TODAY>]**` — placeholder form, used in `skills/bootstrap/SKILL.md` (rendered at bootstrap time)
   A regex limited to `\[\d{4}-\d{2}-\d{2}\]` would leave `[<TODAY>]` in place and make every bootstrap entry look unique — always strip the broader pattern.
2. The italic-category prefix matching `_[^_]+_:` followed by surrounding whitespace. This collapses entries that differ only in label form (e.g., `_JS/TS_: Use bun install...` vs `_JavaScript / TypeScript_: Use bun install...`) into the same statement body for dedup purposes.

After both strips, compare statement bodies with text-equality (case-sensitive, internal whitespace preserved).

- If the normalized statement already appears in the bootstrap file's same section → skip (already promoted).
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

## Step 4 — Append approved entries to the bootstrap file

For each approved entry, append the line to the matching section of `skills/bootstrap/SKILL.md`.

**Date placeholder:** when inserting into `bootstrap/SKILL.md`, write the entry with the `**[<TODAY>]**` placeholder (not the concrete `**[YYYY-MM-DD]**` date from the global file). Bootstrap entries are rendered at bootstrap time; the placeholder is what gets substituted with the actual date when a user runs `/bootstrap`.

**Italic category label:** use the canonical abbreviated form for the destination section (see the table in `best-practices-record`'s Write Format) — `_JS/TS_`, not `_JavaScript / TypeScript_`. This keeps bootstrap entries consistent with one another and consistent with future global-file entries written by `best-practices-record` (which also uses the abbreviated forms).

**Insertion target.** Each section block in `bootstrap/SKILL.md` uses a single Markdown code fence (` ``` `). The label line (e.g., `**Rust addition** (append after the Universal block):`) sits immediately above the opening fence. Insert the new entry before the closing ` ``` ` of the section's code fence.

The grep-anchor pattern is the section header inside the fenced block:

```
## <SectionName>

- **[<TODAY>]** _<SectionName>_: ...
- **[<TODAY>]** _<SectionName>_: ...   ← insert before the closing ``` fence
```

Insertion point: immediately after the last existing entry in that section, before any blank line that precedes the closing fence.

If the section does not yet exist in `bootstrap/SKILL.md`, **stop and tell the user**:

```
Cannot promote entry to "## <SectionName>" — that section does not exist in skills/bootstrap/SKILL.md.

Adding a new section is a structural change. Edit bootstrap/SKILL.md by hand to introduce the section (matching the existing pattern: append-after-X table row, fenced block, etc.), then re-run /best-practices-sync.
```

## Step 5 — Remove promoted entries from the global file

After Step 4 succeeds for an entry, delete the corresponding line (and only that line) from `~/.claude/BEST_PRACTICES.md`. Use a literal-line match against the original (un-normalized) line as it appeared in the global file. If the global section becomes empty after the deletions, leave the section header in place — the user may still add entries to it later.

Skipped candidates (Step 4's missing-section bail-out, or candidates the user did not approve) remain in the global file untouched.

Rewrite `~/.claude/BEST_PRACTICES.md` with the lines removed. The file's introductory header and any unmatched sections stay exactly as they were.

## Step 6 — Bump the bootstrap content version

`skills/bootstrap/SKILL.md` carries a content-version marker (a comment line near the top of the file: `<!-- bootstrap-content-version: <YYYY-MM-DD>-<short-hash> -->`). After appending entries in Step 4, recompute the marker: `<YYYY-MM-DD>` is today's date, `<short-hash>` is a 7-character hex digest of the concatenated content of every fenced markdown block in the file. Update the marker line in place. The `SessionStart` hook (Step 5 in the hooks file) compares this marker against the value cached in the project's `docs/BEST_PRACTICES.md` to decide whether to remind the user to re-run `/bootstrap`.

## Step 7 — Report

Print:

```
Promoted N entries to skills/bootstrap/SKILL.md:
  - [Testing] 2
  - [Rust] 1
  - [Kubernetes / CUE / kapply] 1

Removed N entries from ~/.claude/BEST_PRACTICES.md.

Skipped M entries (section missing):
  - [<section>] <count>

Bootstrap content version: <new-version-marker>

Run `git diff skills/bootstrap/SKILL.md ~/.claude/BEST_PRACTICES.md` to review.
```

The skill never commits. Review and commit are the user's call.

## Red Flags — Stop and Reconsider

- A candidate's text is more than 2 sentences → tell the user the entry is too long for bootstrap content and skip it (the global file may keep entries that are too rich for the bootstrap; promotion is the discipline gate).
- A candidate is project-specific (mentions a project name, internal service, or repo path) → skip it; explain why ("this looks project-specific; bootstrap content must be cross-project").
- The destination section already has > 12 entries → warn the user that the section is getting long and may need a split before appending more.
````

#### Step 4 — Update `.claude-plugin/plugin.json`

Replace the existing entry and add the `best-practices-record` entry. The plugin-local `best-practices-sync` is **not** added here — it is intentionally not exported. The full file becomes:

```json
{
  "name": "bytewyrd-workflow",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  },
  "hooks": "./.claude-plugin/hooks/hooks.json",
  "skills": [
    "./skills/best-practices-extract",
    "./skills/best-practices-record",
    "./skills/bootstrap",
    "./skills/git-branch-cleanup",
    "./skills/rfc-approve",
    "./skills/rfc-braindump",
    "./skills/rfc-consensus-review",
    "./skills/rfc-drop",
    "./skills/rfc-implement",
    "./skills/rfc-install",
    "./skills/rfc-new",
    "./skills/rfc-read-feedback",
    "./skills/rfc-update"
  ]
}
```

The skills list is alphabetized so the two exported best-practices skills sort together at the top. `best-practices-sync` is invokable inside the plugin's own checkout via the local `.claude/skills/` discovery path and does not appear in this manifest.

#### Step 5 — Update `.claude-plugin/hooks/hooks.json`

Replace each `extract-best-practices` substring with `best-practices-extract`, add a `SessionStart` hook for the bootstrap-version reminder, and extend the `Stop` hook to remind the user to run `/best-practices-sync` when the session is inside this plugin's checkout. The full file becomes:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f docs/BEST_PRACTICES.md ] && [ -f .claude/plugins/bytewyrd-workflow/skills/bootstrap/SKILL.md ]; then PROJECT_VER=$(grep -m1 'bootstrap-content-version:' docs/BEST_PRACTICES.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); PLUGIN_VER=$(grep -m1 'bootstrap-content-version:' .claude/plugins/bytewyrd-workflow/skills/bootstrap/SKILL.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); if [ -n \"$PLUGIN_VER\" ] && [ \"$PROJECT_VER\" != \"$PLUGIN_VER\" ]; then echo \"SessionStart: bootstrap content has new entries (project=$PROJECT_VER, plugin=$PLUGIN_VER). Consider running /bootstrap to refresh docs/BEST_PRACTICES.md.\"; fi; fi"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit*)",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed or data flow changed. (3) CONTRIBUTING.md — if dev workflow or quality gate changed. (4) README.md — if user-facing behavior changed. (5) docs/project-brief.md — if product scope or audience changed.'"
          },
          {
            "type": "command",
            "command": "if [ -f .claude-plugin/plugin.json ] && grep -q '\"name\": \"bytewyrd-workflow\"' .claude-plugin/plugin.json 2>/dev/null && [ -s \"$HOME/.claude/BEST_PRACTICES.md\" ]; then echo 'Session ending (plugin checkout): ~/.claude/BEST_PRACTICES.md has pending entries — consider running /best-practices-sync to promote vetted entries into bootstrap content.'; fi"
          }
        ]
      }
    ]
  }
}
```

The `SessionStart` hook reads the `bootstrap-content-version: <marker>` line from both the project's `docs/BEST_PRACTICES.md` and the plugin's installed `bootstrap/SKILL.md` and emits a one-line reminder when they differ. The second `Stop` hook command detects the plugin checkout (presence of `.claude-plugin/plugin.json` with `name: bytewyrd-workflow`) and reminds the user to sync only when the global file is non-empty.

#### Step 6 — Update `.claude/settings.json`

The plugin's own checkout has a parallel hooks block in `.claude/settings.json` (this is what makes the local install dogfood work). Apply the same three changes as Step 5: rename `extract-best-practices` to `best-practices-extract` in the existing `PreCompact` and `Stop` commands, add the `SessionStart` bootstrap-version-reminder hook, and add the second `Stop` command for the `best-practices-sync` reminder.

The renamed string at line 13 becomes:
```
"command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
```

The renamed string at line 53 becomes:
```
"command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
```

Add a `SessionStart` block at the top of the `hooks` object with the same command as in Step 5:

```json
"SessionStart": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "if [ -f docs/BEST_PRACTICES.md ] && [ -f skills/bootstrap/SKILL.md ]; then PROJECT_VER=$(grep -m1 'bootstrap-content-version:' docs/BEST_PRACTICES.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); PLUGIN_VER=$(grep -m1 'bootstrap-content-version:' skills/bootstrap/SKILL.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); if [ -n \"$PLUGIN_VER\" ] && [ \"$PROJECT_VER\" != \"$PLUGIN_VER\" ]; then echo \"SessionStart: bootstrap content has new entries (project=$PROJECT_VER, plugin=$PLUGIN_VER). Consider running /bootstrap to refresh docs/BEST_PRACTICES.md.\"; fi; fi"
      }
    ]
  }
],
```

(The path `skills/bootstrap/SKILL.md` is used here instead of `.claude/plugins/bytewyrd-workflow/skills/bootstrap/SKILL.md` because in the plugin's own checkout, the bootstrap file lives directly in `skills/`. The user-facing version of the hook in `.claude-plugin/hooks/hooks.json` (Step 5) targets the installed-plugin path.)

Append a second `Stop` command to the existing `Stop` hooks array:

```json
{
  "type": "command",
  "command": "if [ -f .claude-plugin/plugin.json ] && grep -q '\"name\": \"bytewyrd-workflow\"' .claude-plugin/plugin.json 2>/dev/null && [ -s \"$HOME/.claude/BEST_PRACTICES.md\" ]; then echo 'Session ending (plugin checkout): ~/.claude/BEST_PRACTICES.md has pending entries — consider running /best-practices-sync to promote vetted entries into bootstrap content.'; fi"
}
```

All other content in `.claude/settings.json` is unchanged.

#### Step 7 — Update `skills/bootstrap/SKILL.md` rename references

Replace `extract-best-practices` with `best-practices-extract` at these four locations:

- **Line 339** (introduction in the bootstrapped `BEST_PRACTICES.md`):

  Before:
  ```
  Use `/extract-best-practices` at the end of a session to add new entries.
  ```
  After:
  ```
  Use `/best-practices-extract` at the end of a session to add new entries.
  ```

- **Line 631** (`PreCompact` hook command in the bootstrapped `.claude/settings.json` example):

  Before:
  ```
  "command": "echo 'PreCompact: context is about to be compacted — run /extract-best-practices now to preserve non-obvious learnings before they are lost.'"
  ```
  After:
  ```
  "command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
  ```

- **Line 671** (`Stop` hook command in the bootstrapped `.claude/settings.json` example):

  Before:
  ```
  "command": "echo 'Session ending: (1) /extract-best-practices — if non-obvious learnings were not yet captured. ...'"
  ```
  After:
  ```
  "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. ...'"
  ```
  (Keep the rest of the message identical — only the skill name changes.)

- **Line 1043** (Step 8 follow-up reminders):

  Before:
  ```
  - Run `/extract-best-practices` at the end of meaningful sessions
  ```
  After:
  ```
  - Run `/best-practices-extract` at the end of meaningful sessions
  ```

Additionally, embed the content-version marker as the first non-frontmatter line of `skills/bootstrap/SKILL.md`:

```
<!-- bootstrap-content-version: 2026-05-09-init00 -->
```

Use the literal value `2026-05-09-init00` for the initial commit of this RFC's changes. The `best-practices-sync` skill (Step 6 of its body) recomputes this marker on every promotion.

The bootstrapped `docs/BEST_PRACTICES.md` introduction must also embed the same marker so the `SessionStart` hook can compare values. Add this line immediately after the file's H1 heading in the bootstrap output:

```
<!-- bootstrap-content-version: 2026-05-09-init00 -->
```

The bootstrap rendering step substitutes the literal current marker value at bootstrap time; the placeholder string `2026-05-09-init00` is what bootstrap reads from its own `SKILL.md` and writes through.

#### Step 8 — Add the universal section block to `skills/bootstrap/SKILL.md`

The universal block consists of four new sections (`## Testing`, `## Documentation`, `## Security`, `## Error Handling`) **plus an expansion of the existing `## Architecture` section** (which already carries one tracing entry; this RFC adds the SOLID, dependency-direction, and module-boundary entries to the same section so design and boundaries do not require separate top-level sections).

Insert the four new sections in the "Base content (all projects)" section, immediately **after** the (now-expanded) `## Architecture` block and **before** the language-specific addition headers ("Rust addition", "JS/TS addition", etc.).

Throughout this RFC, "the Universal block" refers to the five-section group (`## Testing`, `## Architecture`, `## Documentation`, `## Security`, `## Error Handling`). "Append after the Universal block" means append after the `## Error Handling` section — the last of the five.

Note to implementer: the outer `````-backtick fences in this RFC document are a Markdown presentation artifact that allows showing triple backtick code blocks inside. When adding content to `skills/bootstrap/SKILL.md`, use a single triple-backtick fence (` ``` `) matching the existing convention. Do not include the quadruple-backtick outer fence in the file.

Currently the bootstrap file has, in order: base content (Pitfall, Workflow, Claude Code) → "Architecture addition" (single-entry Architecture section) → "Rust addition" → "JS/TS addition" → "Python addition" → "Go addition". The change here is two-part:

**Part A — expand the existing `## Architecture` block.** Replace the current single-entry "Architecture addition" block with the expanded version below. The original tracing entry stays as the first item; SOLID, composition, illegal-states-unrepresentable, module-boundary, dependency-direction, and cross-cutting-concerns entries are appended below it.

````markdown
**Architecture addition** (append after the Claude Code section, all projects):

```markdown
## Architecture

- **[<TODAY>]** _Architecture_: Use structured tracing (`tracing` in Rust, OpenTelemetry-compatible libraries elsewhere) from day one. Adding spans retroactively is far more painful than instrumenting as you write the code.
- **[<TODAY>]** _Architecture_: Single Responsibility — a module/struct/class has one reason to change. Two reasons (e.g., "user persistence" and "user authorization") means two collaborators should split the work, not one monolith.
- **[<TODAY>]** _Architecture_: Open/Closed — extend behavior through new types or strategies, not by editing branches in the existing path. Adding a new payment provider should add a file, not add a `case` to a switch in five files.
- **[<TODAY>]** _Architecture_: Liskov Substitution — a subtype must accept everything its supertype accepts and produce nothing its supertype wouldn't. Violating this turns "polymorphism" into "if statement spread across types."
- **[<TODAY>]** _Architecture_: Interface Segregation — clients depend on the methods they actually use, not a kitchen-sink interface. A 20-method interface that callers use 3 of is 17 methods of false coupling.
- **[<TODAY>]** _Architecture_: Dependency Inversion — high-level policy depends on abstractions; low-level mechanism implements them. The abstraction lives with the policy (it captures what the policy needs), not with the mechanism (which would invert the dependency the wrong way).
- **[<TODAY>]** _Architecture_: Favor composition over inheritance even in OO languages. Inheritance ties two types together at compile time; composition lets you swap collaborators in tests, at runtime, or per environment.
- **[<TODAY>]** _Architecture_: Make illegal states unrepresentable. If a value can only be in one of three modes, model that as a sum type (enum / tagged union / sealed class) rather than three booleans, of which seven of the eight combinations are bugs waiting to happen.
- **[<TODAY>]** _Architecture_: Module boundaries follow change axes. Code that changes together belongs together; code that changes for different reasons belongs apart. Folders organized by technical layer (`controllers/`, `services/`, `models/`) often violate this — group by feature first, by layer second.
- **[<TODAY>]** _Architecture_: A module's public API is a contract; its internals are not. Mark internals as such (private modules / unexported names / `internal/` directory) and resist the pressure to widen the API surface for one-off needs.
- **[<TODAY>]** _Architecture_: Direction of dependency flows from outer (concrete: HTTP, DB, queue) to inner (abstract: domain logic). Domain code never imports adapter code; adapters import the ports the domain defines. This is what hexagonal / clean / onion architecture all boil down to.
- **[<TODAY>]** _Architecture_: Cross-cutting concerns (logging, metrics, auth) belong at the edge, not threaded through domain calls. The domain says what happened; middleware/decorators/aspects observe it.
- **[<TODAY>]** _Architecture_: When a third-party library leaks into a domain type, wrap it. Importing `mongodb::ObjectId` into your `User` struct couples your domain to that driver — when you migrate, every call site changes. A thin adapter type insulates you.
```
````

**Part B — add the four new universal sections.** Insert this block between the (newly expanded) "Architecture addition" block and the "Rust addition" block:

````markdown
**Universal additions** (append after the Architecture section, all projects):

```markdown
## Testing

- **[<TODAY>]** _Testing_: Tests are non-negotiable — a feature without tests is incomplete. The question is not *whether* to test but *at what level*: pure logic gets unit tests, subsystem boundaries get integration tests, full user flows get end-to-end tests.
- **[<TODAY>]** _Testing_: Practice TDD on pure logic — Red (failing test that captures the requirement) → Green (smallest change that passes) → Refactor (improve structure with the test as a safety net). The cycle prevents over-engineering: code exists only to pass a stated test, not to satisfy an imagined future.
- **[<TODAY>]** _Testing_: TDD-produced tests are documentation of intended usage. Because the test is written before the implementation, it must show how a caller invokes the component — its shape, inputs, and outputs — making the test a worked example a reader can study to understand the design. This is especially valuable when discussing architectural decisions, because the tests demonstrate the interface in action rather than describing it abstractly.
- **[<TODAY>]** _Testing_: TDD applies cleanly to algorithmic and decision-logic code (parsers, business rules, state machines). For integration plumbing — code whose entire job is to wire HTTP handlers to a service or shuttle bytes between systems — exercise it via a small integration test that uses the real wire format, not unit tests with mocks of every collaborator.
- **[<TODAY>]** _Testing_: Default to the testing pyramid: many fast unit tests of pure logic, fewer integration tests of subsystem boundaries, fewest end-to-end tests of full user flows. Inverting the pyramid (mostly e2e) makes the suite slow, flaky, and expensive to debug.
- **[<TODAY>]** _Testing_: Use property-based testing (`proptest` in Rust, `fast-check` in TS, `hypothesis` in Python) for code with algebraic invariants — round-tripping serializers, idempotent operations, sort/parse/normalize functions. Hand-written cases miss adversarial inputs that generators surface in seconds.
- **[<TODAY>]** _Testing_: Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code. Mocking your own collaborators couples tests to implementation details and makes refactoring expensive.
- **[<TODAY>]** _Testing_: A flaky test is a broken test — quarantine or fix it the same day, never the same week. Flaky tests train the team to ignore CI failures, which lets a real failure slip through unnoticed.

## Documentation

- **[<TODAY>]** _Documentation_: Documentation is a first-class deliverable, not a chore. A feature that ships without docs is incomplete in the same way as one without tests — the code may run, but no one outside its author can use, review, or evolve it confidently.
- **[<TODAY>]** _Documentation_: Three audiences, three files: `README.md` (users — what is this and how do I run it), `docs/CONTRIBUTING.md` (developers — how do I work on it), `docs/ARCHITECTURE.md` (system designers — how is it built and why). Mixing audiences forces every reader through irrelevant content.
- **[<TODAY>]** _Documentation_: Write docs for the *next* developer (often you in six months), not for the current one. Explain *why* a decision was made, not just what was decided — the diff already shows the what.
- **[<TODAY>]** _Documentation_: Keep docs adjacent to the code they describe. Library-level docs in module headers (`//!` in Rust, `/** */` package docs in Java/TS); function-level docs on the function. Out-of-band docs drift; in-tree docs travel with the code.
- **[<TODAY>]** _Documentation_: Examples are the highest-density docs. A working example beats a paragraph of prose — copy-paste-ability is what real users need. Keep examples in `examples/` and run them in CI so they cannot rot silently.
- **[<TODAY>]** _Documentation_: Code comments explain *why* and *what for*, not *what*. The code already shows what it does; a comment that paraphrases the code adds noise. A comment that captures the constraint, the trade-off, or the reason for an apparent contradiction is gold.
- **[<TODAY>]** _Documentation_: Architecture decision records (ADRs / RFCs) are how you preserve the *why* across years. When you reverse a past decision, link the new RFC to the old one — the historical context is part of the explanation.

## Security

- **[<TODAY>]** _Security_: Never expose tokens, credentials, or secrets in committed code, in client-side bundles, or in logs. Pull secrets from a secret manager at runtime; redact known-secret keys from log output unconditionally.
- **[<TODAY>]** _Security_: Validate input at the boundary, then trust it inside. A request enters validation once (at the HTTP layer, message boundary, etc.) and emerges as a typed domain value — no defensive re-validation throughout the stack, no reaching back to "what was the raw string."
- **[<TODAY>]** _Security_: Run with the lowest privilege required. Service accounts get the narrowest IAM role; container processes run as non-root; database users get only the schemas they need. Privileges are a one-way ratchet — easy to grant, painful to revoke.
- **[<TODAY>]** _Security_: Pin and audit dependencies. Lockfiles (`Cargo.lock`, `bun.lockb`, `go.sum`, `uv.lock`) commit the exact versions you tested; an automated audit step (`cargo audit`, `bun audit`, `govulncheck`, `pip-audit`) catches CVEs in CI rather than in the wild.
- **[<TODAY>]** _Security_: Treat AuthN and AuthZ as separate concerns. Authentication answers "who is this"; authorization answers "may they do this". Conflating them is how systems end up with `if user.is_admin` checks scattered through business logic.

## Error Handling

- **[<TODAY>]** _Error Handling_: Distinguish recoverable errors (return them) from programmer errors (panic / abort). A failed network call is recoverable; a violated invariant inside your own code is not — recovering from it produces zombie state.
- **[<TODAY>]** _Error Handling_: Errors carry context. The error returned three layers up should tell the operator what the system was trying to do, what failed, and what input was involved — not just the leaf cause. `anyhow::Context`, error wrapping, `Error.cause`, all serve the same goal.
- **[<TODAY>]** _Error Handling_: Errors should be observable before they are user-visible. Structured logs and metrics catch the error trend (rising 500s, retry exhaustion) before the user reports the symptom.
- **[<TODAY>]** _Error Handling_: Retries belong at the edge of an idempotent operation. Wrapping a non-idempotent call in retry logic doubles the transactions and corrupts state. If the operation isn't idempotent, make it idempotent (request IDs, conditional updates) before retrying.
```
````

#### Step 9 — Expand existing language sections in `skills/bootstrap/SKILL.md`

For each existing language addition block, append the new entries below to the existing list, keeping the existing entries unchanged.

**Note on Python:** the existing 2-entry Python block is retained as-is. No expansion in this RFC — a future RFC can expand it once the Python sections of other starter files have matured. The block is, however, touched for one purely structural reason: its current heading reads `(append after the Claude Code section)`, while every other language addition heading is being normalized to `(append after the Universal block)` (since the Universal block is inserted before the language additions in Step 8). Update Python's heading from `(append after the Claude Code section)` to `(append after the Universal block)` so all language-addition headings use a consistent anchor. The two existing entries (`type annotations as you write`, `uv`) stay exactly as written.

**Rust** — replace the existing "Rust addition" block with:

````markdown
**Rust addition** (append after the Universal block):

```markdown
## Rust

- **[<TODAY>]** _Rust_: Do not manage the Rust toolchain with mise — use `rust-toolchain.toml` + rustup instead. mise has a cargo PATH conflict that breaks toolchain resolution.
- **[<TODAY>]** _Rust_: Use `thiserror` for error types in library crates, `anyhow` in binary/application crates. Mixing them forces consumers to unwrap opaque errors.
- **[<TODAY>]** _Rust_: `cargo check` is significantly faster than `cargo build` for iteration — use it to validate compilation without producing artifacts.
- **[<TODAY>]** _Rust_: Prefer `Result<T, E>` over `panic!` for any error a caller might reasonably handle. `panic!` is for broken invariants (programmer error); `Result` is for runtime conditions (network, IO, parse).
- **[<TODAY>]** _Rust_: Make illegal states unrepresentable with enums — model "loading | loaded(T) | failed(E)" as one enum with three variants, not three booleans plus an `Option<T>` and an `Option<E>`.
- **[<TODAY>]** _Rust_: Lifetimes flow with ownership; if elision struggles, the structure is wrong, not the annotations. Reach for `Arc`/`Rc` only when shared ownership is genuinely required, not as a borrow-checker escape hatch.
- **[<TODAY>]** _Rust_: Use `#[derive(Debug)]` on every public type. Debug output is what shows up in error messages and logs — types without it cripple operability.
- **[<TODAY>]** _Rust_: For async work, prefer `tokio` and instrument long-running futures with `tracing::Instrument` so spans propagate across `.await` points. Untraced async code is invisible in production.
- **[<TODAY>]** _Rust_: Run `cargo clippy --workspace -- -D warnings` and `cargo fmt --all --check` in CI. Clippy catches real bugs (`needless_collect`, `redundant_clone`); fmt removes the entire class of style PR comments.
- **[<TODAY>]** _Rust_: Use `cargo deny` (or `cargo audit`) in CI to flag advisories, banned licenses, and duplicate dependencies. Each is a security or supply-chain signal you want to see immediately.
```
````

**JS/TS** — replace the existing "JS/TS addition" block with:

````markdown
**JS/TS addition** (append after the Universal block):

```markdown
## JavaScript / TypeScript

- **[<TODAY>]** _JS/TS_: Use `bun` as the JS/TS runtime and package manager — it replaces `node` + `npm`/`yarn`/`pnpm` with a single fast tool. Day-to-day commands: `bun install` for dependencies, `bun run <script>` for package scripts, `bun test` for tests, `bun <file.ts>` to execute TypeScript directly without a separate build step.
- **[<TODAY>]** _JS/TS_: Use `bun install --frozen-lockfile` in CI to catch accidental lockfile drift. Without this flag, bun silently updates the lockfile on install and masks dependency mismatches.
- **[<TODAY>]** _JS/TS_: Enable `"strict": true` in `tsconfig.json` from day one. Retrofitting strict TypeScript into a loose codebase is far more expensive than writing strict types up front.
- **[<TODAY>]** _JS/TS_: Treat `any` as a code smell, not an escape hatch. If the type genuinely is unknown at the boundary, use `unknown` and narrow it with a type guard — `unknown` forces the narrowing; `any` silently disables every check downstream.
- **[<TODAY>]** _JS/TS_: Validate external data at the boundary with a schema library (`zod`, `valibot`, `arktype`). The TypeScript type system has no presence at runtime; without runtime validation, your typed function will happily process malformed JSON until it crashes deep in the call stack.
- **[<TODAY>]** _JS/TS_: Prefer named exports over default exports. Default exports break tree-shaking heuristics, fight refactor tools (default symbols are renamed inconsistently across files), and lose the export name in the import statement.
- **[<TODAY>]** _JS/TS_: Use ESM (`import`/`export`) throughout the codebase, not a CommonJS/ESM mix. Mixing the two creates dual-package hazards and inconsistent module resolution.
- **[<TODAY>]** _JS/TS_: Configure path aliases in `tsconfig.json` (`@/foo`) and bundler config together. Using one without the other ships code that compiles but cannot resolve at runtime.
- **[<TODAY>]** _JS/TS_: Prefer `Date.now()` and explicit timezone handling (e.g., `Intl.DateTimeFormat`) over `new Date(string)` parsing. JavaScript date parsing is locale-dependent and silently wrong for ambiguous formats.
- **[<TODAY>]** _JS/TS_: Use `eslint` with `@typescript-eslint` rules and run it in CI. Pair it with `prettier` (formatting only — let eslint handle correctness rules).
```
````

**Go** — replace the existing "Go addition" block with:

````markdown
**Go addition** (append after the Universal block):

```markdown
## Go

- **[<TODAY>]** _Go_: Handle every error explicitly — assigning to `_` is almost always a latent bug. If an error genuinely can't happen, document why with a comment rather than silently discarding it.
- **[<TODAY>]** _Go_: Run `go vet ./...` and `golangci-lint run` before pushing. `go vet` catches common correctness issues; `golangci-lint` catches style and performance issues that reviewers would flag.
- **[<TODAY>]** _Go_: Pass `context.Context` as the first argument to any function that does I/O, blocks, or might cancel. Goroutines without a context are zombies waiting to leak; once you forget the context at one layer, every layer above forgets it too.
- **[<TODAY>]** _Go_: Wrap errors with `fmt.Errorf("doing X: %w", err)` so callers can `errors.Is` / `errors.As` up the chain. Bare `return err` loses the call-site context that operators need to debug.
- **[<TODAY>]** _Go_: Prefer small interfaces defined where they are used (consumer-side), not where they are implemented. The standard library's `io.Reader` works because every consumer can declare its own narrow read-only need.
- **[<TODAY>]** _Go_: Avoid empty interfaces (`interface{}` / `any`) at API boundaries. They turn the type system off. If you need a sum type, use a sealed interface (unexported method) or a tagged struct.
- **[<TODAY>]** _Go_: Run goroutines with explicit lifetime control — `errgroup.Group`, `sync.WaitGroup`, or a context-cancelled worker pool. Naked `go func() { ... }()` calls are how production hangs and panics with no stack you can find.
- **[<TODAY>]** _Go_: Build for the linker — keep packages small and the dependency graph shallow. Cyclic imports are forbidden by the compiler; near-cyclic imports (A → B → C → A-via-interface) signal a missing third package.
- **[<TODAY>]** _Go_: Use table-driven tests for any function with multiple input shapes. The pattern (`for _, tc := range cases { t.Run(tc.name, ...) }`) makes adding a case a one-line change and surfaces coverage gaps visually.
```
````

#### Step 9a — Update bootstrap detection for new stacks

Step 10 introduces five new section blocks (Svelte, Ruby, Rails, Kubernetes/CUE/kapply, Terraform/Terragrunt), each gated on a detection heuristic. Step 3 of `skills/bootstrap/SKILL.md` ("Detect component structure") currently only scans for `Cargo.toml`, `package.json`, `go.mod`, and `pyproject.toml`/`setup.py`. Without new detection commands, the five new sections are dead code — bootstrap will never emit them on a fresh run.

Add the following detection commands to bootstrap's Step 3, after the existing four language scans:

```bash
# Svelte
find . -name "*.svelte" -not -path "*/node_modules/*" | head -1

# Ruby / Rails
find . -name "Gemfile" -not -path "*/vendor/*" | head -1
find . -name "config/application.rb" | head -1

# Kubernetes / CUE / kapply
find . -name "*.cue" -path "*/k8s/*" | head -1
grep -rl "kapply" .github/ Dockerfile* Makefile 2>/dev/null | head -1

# Terraform / Terragrunt
find . -name "*.tf" -not -path "*/.terraform/*" | head -1
find . -name "terragrunt.hcl" | head -1
```

Derive the following flags from the scan results, and document them in the detection-output structure (the `component_roots` table or equivalent):

- `has_svelte = true` if any `*.svelte` file is found OR `"svelte"` appears in any `package.json` `dependencies` or `devDependencies` field.
- `has_ruby = true` if a `Gemfile` is found.
- `has_rails = true` if `config/application.rb` is found OR `"rails"` gem is listed in the `Gemfile`.
- `has_k8s_cue = true` if any `*.cue` file under `k8s/` is found OR `kapply` appears in a CI workflow or `Dockerfile`.
- `has_terraform = true` if any `*.tf` file is found OR any `terragrunt.hcl` is found.

Update the Step 5 file-creation policy to gate the new addition blocks on these flags: bootstrap appends the Svelte block only when `has_svelte`, the Ruby block only when `has_ruby`, the Rails block only when `has_rails` (and after the Ruby block, since Rails depends on Ruby being present), the K8s/CUE/kapply block only when `has_k8s_cue`, and the Terraform/Terragrunt block only when `has_terraform`.

#### Step 10 — Add new language and stack sections to `skills/bootstrap/SKILL.md`

Add the following blocks after the existing language additions (after the Go addition). Each block follows the same pattern as the Rust/JS/TS/Go additions: a `**<Language> addition** (append after the <anchor>, when <language> is detected — heuristic: ...):` heading, then a fenced markdown block with the section header and entries.

````markdown
**Svelte addition** (append after the Universal block, when Svelte is detected — heuristic: any `*.svelte` file or `svelte` in `package.json` dependencies):

```markdown
## Svelte

- **[<TODAY>]** _Svelte_: Use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`) for new components. Runes are explicit about reactivity boundaries; the legacy `let` + `$:` pattern works but obscures whether a value is reactive or not.
- **[<TODAY>]** _Svelte_: `$effect` is for side effects (DOM, network, timers), not for deriving values. If you find yourself writing `$effect(() => { derived = a + b })`, replace it with `let derived = $derived(a + b)` — the compiler builds a smaller, more correct dependency graph.
- **[<TODAY>]** _Svelte_: Co-locate component-scoped styles in `<style>` blocks; reach for global stylesheets only for tokens (color/spacing variables) and resets. Scoped styles let you delete a component without orphaning its CSS.
- **[<TODAY>]** _Svelte_: Use SvelteKit's load functions (`+page.ts`, `+page.server.ts`) for data fetching, not `onMount`. Load functions run during SSR, integrate with the router's loading state, and avoid the "blank page → flash of content" pattern.
- **[<TODAY>]** _Svelte_: Type `$props` explicitly with a `Props` interface. Untyped props lose autocomplete in consumers and silently accept misspelled prop names.
- **[<TODAY>]** _Svelte_: Prefer the `bind:` directive over manual two-way state plumbing for form inputs and component-shared state. Custom plumbing reinvents what `bind:value` already does and gets it wrong on edge cases (composition events, paste, etc.).
- **[<TODAY>]** _Svelte_: Server-only code goes in `+*.server.ts` files; never import server modules from client code. The bundler can usually catch this, but a server import inside a `$lib` shared module sneaks past — check both ends of every shared module.
```
````

````markdown
**Ruby addition** (append after the Universal block, when Ruby is detected — heuristic: any `Gemfile`, `*.gemspec`, or `*.rb` source file):

```markdown
## Ruby

- **[<TODAY>]** _Ruby_: Pin Ruby version in `.ruby-version` and lock dependencies in `Gemfile.lock`; install via `mise` (or `rbenv` / `chruby`). Mixed Ruby installations across machines produce silent gem-load mismatches.
- **[<TODAY>]** _Ruby_: Run `bundle exec` for project commands (`bundle exec rake`, `bundle exec rspec`) — it pins binaries to the bundle. Direct `rspec` invocations pick up the system gem version and produce results that don't match CI.
- **[<TODAY>]** _Ruby_: Prefer keyword arguments over positional hashes for any method with more than two parameters. Keyword args are self-documenting at the call site and produce clear errors on missing/extra keys.
- **[<TODAY>]** _Ruby_: Treat `nil` checks as a smell. Ruby's null object pattern, `&.` (safe navigation), or `Array(maybe_nil_array)` produce more readable code than `if foo.nil? ...` ladders.
- **[<TODAY>]** _Ruby_: Run `rubocop` and `standard` (pick one) in CI. Both enforce style consistency that reviewers would otherwise spend energy on.
- **[<TODAY>]** _Ruby_: Use `rspec` or `minitest` consistently — don't mix. Each has its own conventions for fixtures, doubles, and matchers; mixing forces every contributor to context-switch between them.
- **[<TODAY>]** _Ruby_: Prefer immutable data classes (`Data.define`, structs frozen on creation) over mutable hashes for typed records. Mutability is the fastest path to spooky-action-at-a-distance bugs.
```
````

````markdown
**Rails addition** (append after the Ruby section, when Rails is detected — heuristic: a `config/application.rb` file or `rails` in `Gemfile`):

```markdown
## Rails

- **[<TODAY>]** _Rails_: Fat controllers and fat models are both anti-patterns. Push business logic into plain Ruby objects (services, form objects, query objects) under `app/services/`, `app/queries/`, etc. The model owns persistence; the controller owns request/response shape; the rest is its own concern.
- **[<TODAY>]** _Rails_: Use strong parameters at the controller boundary, but parse them into a typed object (form object, dry-struct, ActiveModel) before passing to services. Services that take raw params couple to the HTTP shape.
- **[<TODAY>]** _Rails_: Database migrations are append-only history. Never edit a merged migration; add a new one. Rolling back in production is risky enough that you want an explicit reverse migration, not a silent "rerun this".
- **[<TODAY>]** _Rails_: Use `find_each` (or `in_batches`) for any query over more than a few hundred records. `User.all.each` loads the entire table into memory and OOMs the dyno on first real-world data.
- **[<TODAY>]** _Rails_: Wrap multi-record writes in `ActiveRecord::Base.transaction`. Without one, a partial failure (network blip on the second `INSERT`, validation error on the fifth row) leaves the database in a state nobody designed for.
- **[<TODAY>]** _Rails_: Background jobs are at-least-once by default — make them idempotent. The worker that received a job once will receive it twice when the queue retries; if the job mutates state without a unique-key guard, you've created duplicates.
- **[<TODAY>]** _Rails_: Use `bin/rails credentials:edit --environment <env>` for secrets in committed config; never commit secrets in plaintext. The Rails master key goes in your secret manager and into the deploy pipeline as an env var.
- **[<TODAY>]** _Rails_: Eager-load associations in any list view (`includes(:author, :tags)`). N+1 queries pass tests on three rows and crash on three thousand. Add `bullet` (or the `prosopite` gem) in development so they fail loudly during development.
- **[<TODAY>]** _Rails_: Prefer `where.missing(:association)` and Active Record query methods over raw SQL. When raw SQL is necessary, sanitize with bind parameters — never interpolate strings into a query.
```
````

````markdown
**Kubernetes / CUE / kapply addition** (append after the Universal block, when k8s tooling is detected — heuristic: any `*.cue` file under `k8s/`, or `kapply` listed in CI / Dockerfile):

```markdown
## Kubernetes / CUE / kapply

- **[<TODAY>]** _K8s/CUE_: Render manifests with CUE, not Helm templating or YAML anchors. CUE constraints catch invalid shapes (missing `resources.limits`, malformed selectors) at build time; Helm catches them at apply time, sometimes after partial application has already happened.
- **[<TODAY>]** _K8s/CUE_: Pipeline shape is `cue export --out yaml -e resources ./k8s/clusters/<env> | kapply -n <env> -`. CUE produces the desired stream; kapply tracks the inventory and prunes anything that left the desired set. Never apply YAML directly with `kubectl apply` from a render — you lose the prune story.
- **[<TODAY>]** _kapply_: kapply tracks the applied set in a ConfigMap inventory and refuses to run on an empty input stream — that guard is what prevents an accidental "prune everything" when the render layer fails or emits nothing. Do not work around it; fix the render.
- **[<TODAY>]** _kapply_: kapply exit codes have meaning: `0` = no changes, `2` = changes applied successfully, `1` = error/conflict. Deploy scripts should treat both `0` and `2` as success and only fail on `1`.
- **[<TODAY>]** _kapply_: kapply uses server-side apply with `force-conflicts` and a per-distribution field manager. If two distributions try to manage the same field, kapply refuses to take over — fix ownership in CUE rather than working around the conflict.
- **[<TODAY>]** _K8s/CUE_: Pin the API version of every manifest (`apiVersion: apps/v1`, not the latest implicit). Cluster upgrades occasionally remove old API versions; pinning surfaces the migration as a CUE compile error rather than a silent runtime regression.
- **[<TODAY>]** _K8s_: Set `resources.requests` and `resources.limits` on every container. Without requests, the scheduler treats the pod as best-effort; without limits, a noisy neighbor can starve the node.
- **[<TODAY>]** _K8s_: Use `readinessProbe` and `livenessProbe` thoughtfully — readiness gates traffic, liveness restarts pods. A liveness probe that's too aggressive on a slow-starting service crashes a healthy pod; a readiness probe missing on a slow-starting service routes traffic to a not-ready container.
- **[<TODAY>]** _K8s_: Don't set `spec.replicas` on a Deployment that has an HPA — they fight. Either set replicas (no HPA) or set HPA bounds (no static replicas).
- **[<TODAY>]** _K8s_: Run with the lowest privilege necessary: drop all capabilities except those required, run as non-root, set `readOnlyRootFilesystem: true` where the workload allows. PodSecurityPolicy / Pod Security Admission catches the rest.
- **[<TODAY>]** _K8s_: Namespace everything. The default namespace is fine for one-off tools; production workloads belong in named namespaces so RBAC, NetworkPolicies, and resource quotas can be applied.
- **[<TODAY>]** _kapply_: Use `kapply verify` after a deploy to confirm every inventoried resource is still present and stamped. A passing deploy that subsequently drifts (manual edit, garbage collector reaping a parent) is invisible without the verify pass.
```
````

````markdown
**Terraform / Terragrunt addition** (append after the Universal block, when Terraform is detected — heuristic: any `*.tf` file or `terragrunt.hcl`):

```markdown
## Terraform / Terragrunt

- **[<TODAY>]** _Terraform_: Pin provider versions in every module (`required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }`). An unpinned provider can change resource schema between plan and apply, producing destructive diffs nobody asked for.
- **[<TODAY>]** _Terraform_: Pin Terraform itself with `required_version = ">= 1.6.0, < 2.0.0"` in every module. Across-major upgrades deprecate behavior; pinning forces a deliberate upgrade path.
- **[<TODAY>]** _Terraform_: Remote state with locking is non-negotiable for any shared environment. S3 + DynamoDB or GCS + native locks. Local state is fine for a single-author personal stack and disastrous for a team.
- **[<TODAY>]** _Terraform_: Run `terraform plan` in CI on every PR and require the plan output as a review artifact. A merged PR whose plan was never inspected is a merge to production by-accident.
- **[<TODAY>]** _Terraform_: Treat `terraform apply` as a privileged operation. Apply happens through CI on a protected branch, never from a developer's laptop in a shared environment.
- **[<TODAY>]** _Terragrunt_: Use Terragrunt to orchestrate multiple Terraform modules with shared inputs. The DRY pattern (`terragrunt.hcl` per environment, generating provider/backend blocks) is what Terragrunt is for; treat the per-env files as configuration, not code.
- **[<TODAY>]** _Terragrunt_: Run `terragrunt run-all plan` from the root only when you genuinely need to plan everything. For day-to-day work, `cd` into the affected module and run `terragrunt plan` there — it's faster and the blast radius is one module.
- **[<TODAY>]** _Terraform_: Module inputs must be typed (`variable "x" { type = string }`). An untyped variable accepts anything and surfaces type errors deep in the resource block instead of at the boundary.
- **[<TODAY>]** _Terraform_: Don't use `null_resource` + `local-exec` to glue together what providers can do natively. Glue scripts have no dependency graph, no idempotency, and no rollback — they're the easiest way to make a deterministic system non-deterministic.
- **[<TODAY>]** _Terraform_: Tag every resource with a standard set (owner, environment, cost-center, managed-by-terraform=true). Tags are the only path from "what is this resource?" to an answer the cost-management and audit teams can use.
- **[<TODAY>]** _Terraform_: Run `tflint` and `tfsec` (or `checkov`) in CI. tflint catches style and provider-specific issues; tfsec/checkov catches security misconfigurations (public S3 buckets, unencrypted volumes) before they're applied.
- **[<TODAY>]** _Terraform_: Refactor with `moved` blocks, not `terraform state rm` + `terraform import`. `moved` is reversible, declarative, and reviewable; manual state surgery is none of those.
```
````

#### Step 11 — Update this repo's own `docs/BEST_PRACTICES.md`

Replace the line:
```
Use `/extract-best-practices` at the end of a session to add new entries.
```

with:
```
Use `/best-practices-extract` at the end of a session to add new entries.
```

Do **not** retroactively re-seed this file with the new universal content. This file is a live best-practices accumulator for this specific project, not a bootstrap output. Adding the universal content here would conflate the two roles.

#### Step 12 — Verification

After all changes, run these checks:

1. **Skill registration**:
   ```bash
   cat .claude-plugin/plugin.json | grep -E "best-practices|extract"
   ```
   Expected output:
   ```
       "./skills/best-practices-extract",
       "./skills/best-practices-record",
   ```
   The string `extract-best-practices` (verb-first form) must not appear. The string `best-practices-sync` must also **not** appear in `plugin.json` — it is a plugin-local skill (lives at `.claude/skills/best-practices-sync/`) and is intentionally not exported.

2. **Plugin-local sync skill exists**:
   ```bash
   test -f .claude/skills/best-practices-sync/SKILL.md && echo OK
   ```
   Expected output: `OK`.

3. **No stale references in active code/config**:
   ```bash
   grep -rn "extract-best-practices" .claude-plugin/ .claude/ skills/ docs/BEST_PRACTICES.md
   ```
   Expected output: `(empty)`. Any remaining occurrence is a missed reference.

   Note: RFC files in `docs/rfcs/` legitimately preserve the old name `extract-best-practices` as historical record (this RFC, for instance, references it throughout the Current State and File Structure sections). Those occurrences are excluded from this check by scoping to the directories that must be clean after the rename.

4. **Hook commands resolve to the new name and include the new reminders**:
   ```bash
   grep -E "best-practices-extract|best-practices-sync|bootstrap-content-version" .claude-plugin/hooks/hooks.json .claude/settings.json
   ```
   Expected: matches in both files for `best-practices-extract` (PreCompact + Stop), `best-practices-sync` (Stop reminder), and `bootstrap-content-version` (SessionStart hook).

5. **Bootstrap content has the new sections** (consolidated structure: 5 universal sections, of which Architecture pre-existed and got expanded, plus the new language/stack sections):
   ```bash
   grep -E "^## (Testing|Architecture|Documentation|Security|Error Handling|Svelte|Ruby|Rails|Kubernetes / CUE / kapply|Terraform / Terragrunt)$" skills/bootstrap/SKILL.md
   ```
   Expected output (in order):
   ```
   ## Architecture
   ## Testing
   ## Documentation
   ## Security
   ## Error Handling
   ## Svelte
   ## Ruby
   ## Rails
   ## Kubernetes / CUE / kapply
   ## Terraform / Terragrunt
   ```
   (`## Architecture` appears first because it pre-existed in the file's "Architecture addition" block and is now expanded in place; the four new universal sections are inserted after it.)

6. **Bootstrap content version marker present**:
   ```bash
   grep -m1 'bootstrap-content-version:' skills/bootstrap/SKILL.md
   ```
   Expected: a single matching comment line of the form `<!-- bootstrap-content-version: 2026-05-09-init00 -->` (or whatever value the latest sync run wrote).

7. **Local plugin install works** (manual): `claude plugin update bytewyrd-workflow` then restart Claude Code, run `/best-practices-extract` to confirm the renamed skill is invokable, run `/best-practices-record` to confirm the new exported skill is registered, and inside the plugin checkout run `/best-practices-sync` to confirm the plugin-local skill is invokable. Old name `/extract-best-practices` should produce a "skill not found" error. Outside the plugin checkout, `/best-practices-sync` should produce a "skill not found" error (it is plugin-local).

## Risks and open questions

- **Risk: section-header drift between extract, record, and sync.** All three skills assume the same section names (`Testing`, `Architecture`, `Documentation`, `Security`, `Error Handling`, plus the language/stack headers). If a project renames a section in its `docs/BEST_PRACTICES.md`, `best-practices-extract` will create a new mismatched section instead of appending. **Mitigation:** the bootstrap content is the source of truth for section names; the extract skill's "create the section header if it doesn't exist yet" rule means renames in the project propagate naturally to future entries.

- **Risk: the universal Testing entries push TDD harder than every team's reality.** "Practice TDD on pure logic" is opinionated. **Mitigation:** the entries lead with the non-negotiable ("tests are non-negotiable — a feature without tests is incomplete") and frame TDD as the *technique* for pure-logic code with the additional benefit of producing tests-as-documentation. Integration plumbing is explicitly carved out. The reasoning is on the page; the framing makes the entries useful as starting points to question, not commandments.

- **Open question: should the global file path be configurable?** Right now it's hard-coded to `~/.claude/BEST_PRACTICES.md`. If a user runs Claude Code in a non-standard `$CLAUDE_HOME`, this won't follow. The skills resolve `~` via `$HOME`. If `$CLAUDE_HOME` becomes a real concern, add a `BYTEWYRD_GLOBAL_BP` env var override in a follow-up RFC. Not blocking this RFC.

- **Open question: kapply detection heuristic.** The bootstrap detection rule is "any `*.cue` file under `k8s/`, or `kapply` listed in CI / Dockerfile". The `*.cue` heuristic will false-positive on CUE used outside k8s contexts (e.g., config validation in a Go service). **Resolution within this RFC:** the heuristic is acceptable — false positives produce a section in `BEST_PRACTICES.md` that the user can delete; false negatives miss the section entirely, which is the worse outcome. We bias toward false positives.

- **Open question: when Svelte/Ruby/Rails/k8s/Terraform projects pre-exist (no fresh bootstrap), how do they get the new content?** They don't, automatically — bootstrap is idempotent, but it skips existing files. The `SessionStart` hook (Step 5/6) catches this case: when the project's `bootstrap-content-version` marker lags the plugin's, the hook prints a one-line reminder to re-run `/bootstrap`. The user then either re-runs bootstrap (which currently skips existing files and would need a future "update mode") or manually copies the new sections. A future "BEST_PRACTICES update" skill could close this gap; out of scope for this RFC.

- **Risk: `kapply` is referenced but not yet in a public repo.** The README cites `/home/divoxx/code/own/infra/.worktrees/...` — internal to the author. **Mitigation:** the entries in the K8s/CUE/kapply section describe the pattern and command shape, which are stable, and do not reference the internal path. When kapply is extracted to a public repo, the entries remain accurate. If the kapply project is renamed at extraction, a follow-up `/best-practices-sync` run patches the entries.

- **Risk: the `best-practices-sync` skill's text-equality match may produce false negatives (light editing of the same statement).** A user records "Use TDD for pure logic" and the bootstrap already has "Practice TDD on pure logic — Red/Green/Refactor..."; the sync skill treats them as different and presents the user's variant as a candidate. **Mitigation:** the candidate-presentation step lets the user say "skip — already covered". Cost of a false negative is one extra skip; cost of a false positive (silent dedup of a genuinely new entry) is a missed promotion. Bias toward false negatives is correct here.

## Relationship to other RFCs

None. This RFC is self-contained — it touches `bootstrap`, `extract-best-practices`, the plugin manifest, and hook configurations, none of which have an open RFC.
