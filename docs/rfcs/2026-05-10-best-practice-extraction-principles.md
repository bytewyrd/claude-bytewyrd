---
rfc: "2026-05-10-best-practice-extraction-principles"
title: "Best-Practice Extraction: Triage and Lift Principles"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add an explicit two-part discipline to all three best-practice skills (`best-practices-extract`, `best-practices-record`, `best-practices-sync`) so they stop accumulating literal-level observations and start capturing transferable principles. Part one is a **triage** step that runs before any candidate is presented: decide whether the learning is generalizable at all. If it is project-specific, route it to the project's `docs/BEST_PRACTICES.md` (or refuse to record it globally); only generalizable learnings continue. Part two is a **lift** step that runs on each generalizable candidate: restate it at the level of the underlying principle, stripped of project names, file paths, type names, and instance-specific details, then verify the lifted statement still survives a "read in isolation, in another project, two years later" test. The same triage-and-lift gate is wired into all three skills so a project-specific gotcha can never reach `~/.claude/BEST_PRACTICES.md` or `skills/sync/SKILL.md`, and a genuinely generalizable insight is never frozen at the narrow scope of its first observation.

## Should we do this?

**Yes.** The current `best-practices-extract` skill has a "Generalization Step" that asks for the underlying principle, but it runs *after* the candidate has been picked, applies only to the project-local file, and shares no contract with `best-practices-record` or `best-practices-sync`. The result is the failure mode the braindump names: K8s-specific gotchas seep into the global pool when a session feels "general enough"; broadly transferable insights are anchored to the project where they were noticed and never get re-stated. The fix is small in code (steps in three SKILL files) but compounding in value: it converts the pipeline from "snapshot whatever the session noticed" into "preserve the principle, drop the instance." The cost — one extra triage pass per candidate, one extra lift pass per kept candidate — is paid by the agent at capture time, where the human is already engaged. Doing this now also means the global file (`~/.claude/BEST_PRACTICES.md`), which is currently almost empty, is shaped by the discipline from day one rather than retro-cleaned later.

## Current state

Three skills handle best-practice capture:

| Skill | Path | Destination |
|---|---|---|
| `best-practices-extract` | `skills/best-practices-extract/SKILL.md` | `docs/BEST_PRACTICES.md` (project-local) |
| `best-practices-record` | `skills/best-practices-record/SKILL.md` | `~/.claude/BEST_PRACTICES.md` (global) |
| `best-practices-sync` | `.claude/skills/best-practices-sync/SKILL.md` (plugin-local, not exported) | `skills/sync/SKILL.md` (bootstrap content) |

`best-practices-extract` has the most evolved discipline. It has:

- **Mandatory Filters** (lines 22–38) — skip rules for already-documented, library behavior, one-off, inferrable-from-code, and framework-portability tests.
- **Generalization Step** (lines 41–55) — for each surviving candidate, ask "What is the general principle here, stripped of names, file paths, and implementation details?" and a too-specific / too-abstract / good comparison table.
- **User Confirmation** (lines 56–72) — present numbered candidates; never write without approval.
- **Red Flags** (lines 100–107) — additional refusal rules.

The Generalization Step is the right idea but is described as a writing-style improvement ("rewrite the candidate to express the rule in terms of the pattern"), not as a hard gate that decides *destination*. A learning that resists generalization is told to "skip it" — but only after the agent has already mentally classified it as a candidate. There is no upstream triage that decides "this is project-specific, route it differently."

`best-practices-record` operates on a user-supplied sentence directly. Its discipline is much thinner:

- **Categorization Step** (lines 25–44) — pick a section header from a fixed table.
- **Confirmation Step** (lines 46–58) — show the formatted entry and ask `yes/edit/cancel`.
- **Red Flags** (lines 106–111) — refuse if statement is project-specific (suggest `/best-practices-extract` instead), is a library quirk (suggest Context7/Exa), or > 2 sentences.

The Red Flag for "project-specific" is the only gate currently distinguishing global from project scope, and it's a passive check the agent applies to the user-supplied text rather than an active reformulation pass. There is no lift step at all — the user's wording goes through almost verbatim, modulo the standard format.

`best-practices-sync` is the last gate before content reaches *every* project that runs `/sync`. Its discipline is:

- **Classify each global entry** (lines 20–37) — EXACT_DUPLICATE / CONFLICT / NEW.
- **Resolve conflicts** (lines 39–69) — Opus-merged version + user picks one of three.
- **Red Flags** (lines 168–172) — skip project-specific candidates ("mentions a project name, internal service, or repo path"); warn on > 2 sentences; warn when destination section has > 12 entries.

The "skip project-specific" Red Flag fires on the wrong layer: by the time an entry has reached the global file and is being synced, the project-specific failure has already crossed the boundary the global file was supposed to enforce. Sync catches the leak instead of preventing it.

The cumulative effect of the current state:

1. A project-specific learning can flow into `~/.claude/BEST_PRACTICES.md` if the user phrases it generally enough at record time. Sync may catch it; or may not, if the project-name leak is subtle.
2. A genuinely generalizable insight extracted in one project is recorded with that project's vocabulary ("our `RouterConfig` should not call into `auth::token` — auth resolution belongs in `core::auth`"), and is then either (a) kept project-local and lost to other projects, or (b) re-recorded later by a human who happens to remember it, in a different vocabulary, fragmenting the same insight across two entries.
3. The three skills don't share a common predicate for "is this generalizable?" — each has its own ad-hoc test, so the same learning gets a different verdict depending on which skill saw it first.

## Analysis / Options

There are two coupled decisions: where to enforce the discipline, and what the discipline actually consists of.

### Decision 1 — Where the triage-and-lift gate runs

**Option A — Add the gate to all three skills, with the same predicate (recommended).**
Each skill runs its own triage and its own lift, but the criteria and the lift template are identical, defined once and referenced from each skill. `best-practices-extract` triages session candidates and keeps only the generalizable ones (project-specific learnings stay in `docs/BEST_PRACTICES.md` under a project-local section, with no upward path). `best-practices-record` triages user-supplied statements and refuses to record project-specific ones (suggests `/best-practices-extract` instead) — same triage as today's Red Flag, but moved upstream and made the first action of the skill, not a final check. `best-practices-sync` re-applies triage as a defense-in-depth pass: any global entry that fails the test at sync time is held back and surfaced to the user with a "this looks project-specific — keep in global file or delete?" prompt. The lift step also runs at every gate: extract lifts before user confirmation (generalize while context is fresh), record lifts before confirmation (rewrite the user's statement), sync lifts only when promoting a CONFLICT-resolved entry (the Opus-merged version goes through one more lift pass).

**Option B — Add the gate only to `best-practices-record` (single point of truth).**
Defends the global file at the only direct write point. Simpler to maintain — one skill, one predicate. But fails on two flanks: (1) it does nothing for `best-practices-extract` (project files keep accumulating instance-level entries that no one ever lifts), and (2) entries already in the global file from before this RFC are never re-triaged because sync doesn't look at the predicate.

**Option C — Add the gate only to `best-practices-sync` (last-mile filter).**
Defends bootstrap content but lets the global file rot freely. Sync becomes a heavy review session because every global entry has to be re-evaluated against the predicate before promotion. The user pays cost in batches at sync time instead of in flow at capture time, which inverts the design of the pipeline.

**Recommendation: Option A.** The three skills form a pipeline; each gate prevents a specific class of leak the others can't catch. Extract prevents project-specific entries from being written in the first place (their natural home is the project file, and they stay there). Record prevents user-supplied project-specific text from contaminating the global pool. Sync provides defense-in-depth for entries written before this RFC or by a less disciplined session. Yes, the predicate is duplicated across three SKILL files; the fix for that is a shared "Triage and Lift" reference document (`skills/best-practices-extract/TRIAGE-AND-LIFT.md`) the other two skills link to, created in Step 1 of the implementation spec.

### Decision 2 — What the triage predicate actually is

**Option A — Boolean test: "Would this rule still apply if the project changed languages or frameworks?" (status-quo phrasing in `best-practices-extract`).**
Concise but underdetermined. Many entries pass that test in spirit but fail in the wording — "Use `bun install --frozen-lockfile` in CI" passes the framework-change test (the principle "lock dependency versions in CI" is universal) but is written as a Bun-specific command. The test doesn't catch the wording mismatch.

**Option B — Multi-test: framework-portability + project-portability + audience-portability (recommended).**
Three explicit questions:

1. **Framework portability** — would this still be true if the project changed languages or frameworks?
2. **Project portability** — would a developer on a different project, with no knowledge of this codebase, still benefit from reading this?
3. **Audience portability** — does this entry survive being read in two years, by someone who has no memory of the session that produced it?

If all three are yes → generalizable (continue to lift). If any is no → project-specific (route to project file or refuse, depending on which skill is running). The third question is what catches "the lockfile entry is universal in concept but written as a specific tool's command" — `bun install --frozen-lockfile` in isolation doesn't survive an audience that has never used Bun; "lock dependency versions in CI to catch lockfile drift; the exact command depends on the package manager (`bun install --frozen-lockfile`, `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`)" does.

**Option C — LLM-judged: "ask Opus to classify the candidate as general / project-specific."**
Replaces a deterministic checklist with a model call. Opus is good at this but inconsistent across runs, and the failure mode is silent (a project-specific entry classified general gets written without any human visible signal). The deterministic checklist gives the user a chance to push back on the classification — "I disagree, this is general."

**Recommendation: Option B.** The three-question test is short enough to memorize, deterministic enough to be predictable across runs, and catches the specific failure mode (audience portability) that the braindump names — a learning anchored to the specific instance where it was first observed.

### Decision 3 — What the lift step actually does

**Option A — A single sentence: "rewrite the rule at the level of the principle, not the instance" (status quo).**
Underspecified. Different agents lift to different altitudes — sometimes too abstract ("use provide/inject for state sharing"), sometimes still too specific ("Vue `provide`/`inject`...").

**Option B — A two-pass procedure with a verification check (recommended).**
Pass 1 — strip the instance: remove project names, file paths, type names, function names, package names, version numbers, and identifiers private to the project. Replace each with the role it played ("the wrapper component" instead of "`DetailOverlay`"; "the render layer" instead of "`cue export`"). Pass 2 — name the domain: prepend the technology, layer, or domain the principle applies to ("Vue:", "Rust async:", "K8s:", "Architecture:") so the entry is self-contained when read in isolation. Verification — re-read the lifted statement and ask the audience-portability question: "would this still be useful to someone who has never seen this codebase, in two years?" If no, lift higher or skip.

**Option C — Use Opus to do the lift mechanically.**
Same downsides as Option C in Decision 2 — non-deterministic and silent on failure.

**Recommendation: Option B.** Two passes give the agent an explicit script to follow, and the verification check catches "I lifted but not enough" before user confirmation.

### Decision 4 — How project-specific entries are stored

**Option A — A dedicated `## Project-Specific` section in `docs/BEST_PRACTICES.md` (recommended).**
When `best-practices-extract` triages a candidate as project-specific, the candidate is still valuable to *this* project — it's the kind of thing a code comment would carry, but it survives across files. Keep it, but in a clearly labeled section that signals "this entry is local; do not promote it." The section header is the explicit boundary: anything inside it is permanently local; anything outside is implicitly generalizable.

**Option B — Skip project-specific entries entirely.**
Loses high-value local context. A Bytewyrd contributor learning that "the `sync` skill must read from the worktree, never the main repo root" is exactly the kind of learning a project file should preserve, even though it's not transferable.

**Option C — Inline project-specific entries with an inline marker.**
e.g., `**[2026-05-10]** _Architecture (project-specific)_: ...`. Mixes local and global entries in the same section, requires reviewers to scan an inline marker to know which is which. Loses the "the section header is the boundary" property of Option A.

**Recommendation: Option A.** The named section makes the boundary visible; sync skips the section by name; humans scanning the file can see at a glance which entries are local and which are general.

## Drawbacks

- **Capture takes longer at the moment of capture.** Three triage questions plus a two-pass lift adds wall-clock time to every `best-practices-extract` and `best-practices-record` invocation. Mitigation, part 1: the cost is paid in flow, when the human is already engaged with the topic — adding a minute at capture saves much more than a minute later when a stale entry has to be re-triaged or removed. Mitigation, part 2: the triage is fast in the common case — most session learnings either obviously pass (TDD discipline, Rust async patterns) or obviously fail (a specific bug fix). Only borderline cases need the audience-portability check applied carefully.

- **Some learnings will be lost when they fail triage at extract time.** A candidate that fails the framework-portability test goes into the project's "Project-Specific" section but never reaches the global pool. If the same learning recurs in three more projects under different framing, the agent will independently capture it three times instead of once at the principle level. Mitigation: this is the *correct* failure mode — a single observation isn't enough evidence that the underlying principle is generalizable. When the third project hits it, the human can record it explicitly via `/best-practices-record` with the lifted phrasing, which is the point of having `record` as a separate manual entry path.

- **Different agents will draw the lift line at different altitudes.** Even with the two-pass procedure and verification check, "lift to the principle" is a judgment call. Two sessions extracting the same observation may produce one entry phrased at "Architecture: domain code does not import adapter code" and another phrased at "Architecture: keep the dependency direction inward." Mitigation, part 1: the lift script (Pass 1 strip, Pass 2 name the domain, Verification re-read) constrains the variation. Mitigation, part 2: `best-practices-sync`'s CONFLICT-detection step (already present) merges near-duplicates at promotion time using an Opus-generated combined version — so altitude variance gets normalized at the gate that matters most.

- **The triage step will occasionally produce false negatives (generalizable entries marked project-specific).** A learning written with strong project-name vocabulary may fail the audience-portability test even though the underlying principle is transferable. The agent then routes it to `## Project-Specific` and the principle is hidden in the project file. Mitigation: the triage step's Pass 1 strip is also a *test* — if stripping the project-specific names produces a sentence that still says something useful, the entry is generalizable. The lift script makes this explicit. If after Pass 1 the sentence is empty or vacuous ("The wrapper component should call the inner module"), the original was project-specific in fact.

- **Changes to three SKILL files at once.** Coordinating updates across `best-practices-extract`, `best-practices-record`, and `best-practices-sync` means the three skills must agree on the predicate, the lift procedure, and the section names at the same time. A drift between them re-creates the failure mode this RFC fixes. Mitigation: the shared predicate and lift procedure live in one file (`skills/best-practices-extract/TRIAGE-AND-LIFT.md`), and the other two skills link to it rather than duplicating. The verification step in the RFC's Step 7 grep-checks for the literal reference link in all three SKILL files (Step 7 check #1) — if the link is missing in one, the verification fails.

- **The `## Project-Specific` section name is opinionated.** Some teams may already have project-specific notes scattered under other section headers. Mitigation: this RFC does not retroactively re-section existing entries — the section is created fresh and is filled only by future extractions. Existing entries in `Architecture`, `Workflow`, `Code Design`, etc. are left where they are; the human can move them if they want.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `skills/best-practices-extract/TRIAGE-AND-LIFT.md` | Single source of truth for the triage predicate (3 portability questions) and the lift procedure (Pass 1 strip / Pass 2 name domain / Verification re-read). Linked to from the three skills. |
| Modify | `skills/best-practices-extract/SKILL.md` | (1) Insert a new "Triage Step" before the existing "Mandatory Filters" section so triage runs first. (2) Replace the existing "Generalization Step (Before Presenting Candidates)" section with a "Lift Step" that references the shared procedure and applies the two-pass + verification flow. (3) Update "Write Format" to introduce the `## Project-Specific` section and explain when an entry lands there vs. a thematic section. (4) Update "Red Flags" with new failure modes specific to triage and lift. |
| Modify | `skills/best-practices-record/SKILL.md` | (1) Insert a new "Triage Step" as the first action after Inputs, before "Categorization Step". (2) Insert a "Lift Step" between Triage and Categorization, referencing the shared procedure. (3) Update "Red Flags" — the existing project-specific Red Flag is preserved as defense-in-depth, but the triage step is now the primary refusal point. |
| Modify | `.claude/skills/best-practices-sync/SKILL.md` | (1) Insert a new "Step 2a — Re-triage" between the existing "Step 2 — Classify each global entry" and "Step 3 — Resolve conflicts". Re-triage applies the shared predicate as defense-in-depth on every global entry being synced. (2) Update "Red Flags" so the existing "project-specific candidate" rule references the shared predicate by link. (3) When promoting a CONFLICT-resolved entry whose Combined version came from Opus, run one more lift pass on the Opus output before writing it to the sync file. |
| Modify | `skills/sync/SKILL.md` | Modify the starter `docs/BEST_PRACTICES.md` template (currently around line 444 / surrounding lines) to add a `## Project-Specific` section header at the bottom of the file, with a one-line introduction explaining the boundary. No content changes to other sections. |
| Modify | `docs/BEST_PRACTICES.md` (this repo's own file) | Add a `## Project-Specific` section header at the bottom with the same one-line introduction. No retroactive re-sectioning of existing entries. |

### Steps

#### Step 1 — Create the shared triage-and-lift reference

Create `skills/best-practices-extract/TRIAGE-AND-LIFT.md` with this content:

````markdown
# Triage and Lift

Shared procedure for `best-practices-extract`, `best-practices-record`, and `best-practices-sync`. The three skills reference this file rather than duplicating the text. When this file changes, all three skills inherit the change.

## Triage — three portability questions

Apply these three questions in order to every candidate before any other action. The candidate is **generalizable** only if all three are yes.

### Question 1 — Framework portability

Would this rule still be true if the project changed languages, frameworks, or major libraries?

- "Use `Result<T, E>` over panic for recoverable errors" → if the project switched from Rust to Go, the equivalent would be "return an `error` value instead of calling `panic`" — same principle. **Yes.**
- "Use `bun install --frozen-lockfile` in CI" → the principle ("lock dependency versions in CI") survives a switch to npm or pnpm; the wording ("`bun install --frozen-lockfile`") does not. **No, in this wording**; **yes** if rewritten as the principle.
- "The `RouterConfig` struct should not call into `auth::token`" → if the project changed languages, this entry has no meaning. **No.**

### Question 2 — Project portability

Would a developer on a different project, with no knowledge of this codebase, benefit from reading this?

- "Practice TDD on pure logic — Red/Green/Refactor" → universal engineering advice. **Yes.**
- "Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code" → universal testing principle. **Yes.**
- "Our `sync` skill must read from the worktree, not from `git rev-parse --git-common-dir`" → only meaningful for the bytewyrd plugin codebase. **No.**

### Question 3 — Audience portability

Does this entry survive being read in two years, by someone with no memory of the session that produced it?

- "Validate input at the boundary, then trust it inside" → reads cleanly without context. **Yes.**
- "Use `bind:` for two-way binding in Svelte form inputs" → reads cleanly with the explicit `Svelte:` prefix. **Yes.**
- "We had to refactor `RouterConfig::from_env` to delegate auth resolution to `core::auth::resolve_token` instead" → meaningless without the session's context. **No.**

### Outcome

- **All three yes** → generalizable. Continue to the lift step.
- **Any one no** → project-specific. The originating skill decides what to do (see the per-skill instructions for routing).

## Lift — two-pass rewrite plus verification

Apply these passes only to candidates that passed triage.

### Pass 1 — Strip the instance

Remove from the candidate text:

- Project names, repo names, package names ("`bytewyrd-workflow`", "`tinywyrd`", "`eve-platform`").
- File paths ("`src/auth/token.rs`", "`skills/sync/SKILL.md`").
- Type names, function names, struct names, class names ("`RouterConfig`", "`DetailOverlay::new`", "`processOrder`").
- Module names and namespaces ("`core::k8s::target`", "`@scope/package`").
- Version numbers and tool versions specific to a single moment in time ("Rust 1.78", "Svelte 4.2.7").
- Internal vocabulary the project invented ("the resolver", "the dispatcher" — unless these are domain words a reader of any project would know).

Replace each removed identifier with the *role it played* in the principle:

- "`DetailOverlay`" → "the wrapper component"
- "`core::k8s::target`" → "the subsystem responsible for assembling the K8s target"
- "`auth::token`" → "the authentication submodule"

If after stripping, the candidate is empty or vacuous ("The component calls the module"), the original was project-specific in fact — re-triage it as project-specific and route accordingly.

### Pass 2 — Name the domain

Prepend the technology, layer, or domain the principle applies to. The prefix makes the entry self-contained when read in isolation.

| Domain | Prefix |
|---|---|
| Vue, React, Svelte component model | `Vue:` / `React:` / `Svelte:` |
| Rust async or trait system | `Rust:` (with sub-qualifier as needed: `Rust async:`) |
| Kubernetes manifests / CUE / kapply | `K8s:` / `K8s/CUE:` / `kapply:` |
| Cross-cutting architecture | `Architecture:` |
| Testing methodology | `Testing:` |
| Documentation discipline | `Documentation:` |
| Security hygiene | `Security:` |
| Error handling | `Error Handling:` |

Match the prefix to the existing section header in `~/.claude/BEST_PRACTICES.md` and `skills/sync/SKILL.md` (use the canonical abbreviated label — `_K8s_`, `_Rust_`, `_JS/TS_`, etc.) so the entry lands in the right destination section without rework.

### Verification — re-read in isolation

Read the lifted candidate one more time, with this question in mind:

> "If I encounter this entry in `~/.claude/BEST_PRACTICES.md` two years from now, with no other context, can I act on it?"

If the answer is no — the entry still references something only the originating session would know — return to Pass 1 and lift higher. If after a second pass the entry still fails, treat it as project-specific (the principle is real but you cannot extract it without losing meaning; record the instance-level statement project-locally instead).

## Worked examples

| Original (project-specific) | After Pass 1 (stripped) | After Pass 2 (named domain) | Verdict |
|---|---|---|---|
| `RouterConfig::from_env` should delegate auth resolution to `core::auth::resolve_token` | The configuration layer should delegate auth resolution to the authentication submodule | Architecture: subsystem boundaries own their domain assembly; configuration layers only resolve and forward inputs | Generalizable, lifted |
| `DetailOverlay` passes compact state via `provide` so slot content can inject it | The wrapper component shares state with slot content via `provide` / `inject` | Vue: when a wrapper component renders arbitrary slot content and needs to share state with it, use `provide` / `inject` — slot content has no prop access to its wrapper | Generalizable, lifted |
| The `bytewyrd-sync` skill should write to the worktree, not the main repo | The skill should write to the current working directory, not a parent repo root | Skill design: worktree-aware tooling must write to the cwd-derived working tree, never to a "common" repo root | Generalizable, lifted |
| The `sync.skill` reads from `~/.claude/plugins/installed_plugins.json` to detect the GitHub MCP | (after strip) The skill reads from a JSON file to detect a plugin | (after Pass 2) (still vacuous — no useful principle) | Project-specific, route to `## Project-Specific` |
````

#### Step 2 — Update `skills/best-practices-extract/SKILL.md`

The existing skill structure is preserved; this RFC inserts a new Triage step before Mandatory Filters and replaces the existing Generalization Step with a Lift Step that references the shared procedure.

**Replace lines 14–55** (the existing "Extraction Pass", "Mandatory Filters", and "Generalization Step (Before Presenting Candidates)" sections) with:

````markdown
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
````

**Replace lines 56–72** (the existing "User Confirmation (Always Required)" section) with:

````markdown
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
````

**Replace lines 74–84** (the existing "Write Format" section) with:

````markdown
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
````

**Replace lines 100–107** (the existing "Red Flags" section) with:

````markdown
## Red Flags — Stop and Reconsider

- You're about to write more than 2 generalizable items from one session → you're being too permissive at the triage step. Re-apply the audience-portability question to each.
- A candidate passed triage but the lifted text still mentions a project-specific identifier → Pass 1 missed something. Strip again or demote to project-specific.
- A candidate failed triage but you're about to write it to a thematic section (not `## Project-Specific`) → routing error. Move it to `## Project-Specific` or re-evaluate the triage decision.
- The lifted entry is so abstract it could appear in any project's best practices ("Use proper error handling") → Pass 2 over-lifted. Add the domain back, or skip — over-abstraction is just as bad as under-abstraction.
- Entry is longer than 2 sentences → consolidate or skip.
- You're adding without asking the user → violation.
````

The remainder of the SKILL.md (Overview, "When to Run", "Post-Write Check") is unchanged.

#### Step 3 — Update `skills/best-practices-record/SKILL.md`

The existing skill structure is preserved; this RFC inserts a Triage and a Lift step between "Inputs" and "Categorization Step", and updates Red Flags.

**Insert a new section between the existing "Inputs" (lines 22–24) and "Categorization Step" (line 26)**:

````markdown
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
````

**No changes to "Categorization Step" (lines 26–44)** — it operates on the now-lifted text.

**No changes to "Confirmation Step", "Write Format", or "File Bootstrap"** — they operate on the categorized lifted text.

**Replace the existing "Red Flags" section (lines 106–111)** with:

````markdown
## Red Flags — Stop and Reconsider

- The statement is more than 2 sentences → ask the user to compress it before recording.
- The statement is project-specific ("our deploy script does X") → handled by the Triage Step refusal above, but if it slips through Triage, refuse here too.
- The statement is a library quirk ("the K8s HPA controller does X") → that's library documentation; suggest looking it up via Context7 / Exa instead of recording.
- The lifted version differs from the original only in cosmetic ways (whitespace, capitalization) → the lift didn't actually change anything; either the original was already lifted, or Pass 1 missed identifiers. Re-check.
- A near-duplicate already exists under the target section → present the existing entry and ask whether to replace, append, or skip.
````

#### Step 4 — Update `.claude/skills/best-practices-sync/SKILL.md`

`best-practices-sync` is the last gate before content reaches every project. This RFC adds a re-triage pass between classification and conflict resolution, and adds a lift pass on Opus-merged combined versions.

**Insert a new section between the existing "Step 2 — Classify each global entry" (lines 20–37) and "Step 3 — Resolve conflicts" (line 39)**:

````markdown
## Step 2a — Re-triage (defense in depth)

For every entry classified NEW or CONFLICT in Step 2, re-apply the three portability questions defined in [`../../skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../../skills/best-practices-extract/TRIAGE-AND-LIFT.md):

1. Framework portability
2. Project portability
3. Audience portability

This is defense in depth — the entry should already have passed triage at `best-practices-extract` or `best-practices-record` time, but entries written by older sessions (before this RFC) or by less disciplined invocations may have leaked through.

For each entry that fails re-triage:

- **Stop and ask the user** with AskUserQuestion (single-select):

  ```
  Re-triage failed for this entry:
    <entry text>

  Which portability question failed: <question 1 / 2 / 3>

  Options:
  - Option 1: Skip — leave in ~/.claude/BEST_PRACTICES.md (manual cleanup later)
  - Option 2: Delete — remove from global file (it should not be there)
  - Option 3: Lift now — open the lift procedure interactively, rewrite the entry,
             then re-classify (NEW or CONFLICT) against the sync file
  ```

- Act on the user's choice:
  - **Skip**: leave the entry in the global file and exclude it from this sync run. It may be re-triaged on the next run.
  - **Delete**: remove the entry from `~/.claude/BEST_PRACTICES.md` and exclude it from sync. Do not write to the sync file.
  - **Lift now**: walk the user through Pass 1 → Pass 2 → Verification interactively (one AskUserQuestion call per pass for confirmation). Replace the entry text with the lifted version, then re-run Step 2's classification on the new text.

EXACT_DUPLICATE entries are not re-triaged — they already exist in the sync file and are handled by Step 6's removal-from-global step.

Entries that pass re-triage proceed to Step 3 unchanged.
````

**Insert a new step at the end of "Step 3 — Resolve conflicts" (after line 69)**:

````markdown
### Lift the Combined version (when chosen)

If the user picked the **Combined (Opus)** option for a CONFLICT resolution, run one final lift pass on the Opus output before writing it to the sync file. Apply Pass 1 (strip) and Pass 2 (name domain) from the shared procedure; skip the user-facing verification dialog (the user has already approved the Combined text). If Pass 1 changes the text, surface the change with AskUserQuestion (single-select):

```
You picked the Combined version:
  <Opus output>

Lift pass produced:
  <lifted text>

The lift removed: <list of stripped identifiers>

Use which?
- Option 1: Lifted (recommended)
- Option 2: Original Combined (Opus)
```

Default is Lifted. The Original-Combined option exists because Opus may produce a generic example that the lift step incorrectly interprets as a project-specific reference.

Global and Plugin choices do not get an extra lift pass — the Plugin version is already in the sync file (so it has been lifted previously), and the Global version was lifted at record time (and just passed Step 2a re-triage).
````

**Update the existing "Red Flags — Stop and Reconsider" section (lines 168–172)** by replacing the first bullet with:

````markdown
- A candidate is project-specific (mentions a project name, internal service, or repo path) → Step 2a should have caught this. If it didn't, the triage predicate may need refinement — see [`../../skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../../skills/best-practices-extract/TRIAGE-AND-LIFT.md). Skip the entry, surface the miss to the user, and ask whether to update the predicate.
````

The other two Red Flag bullets (`> 2 sentences`, `> 12 entries in destination section`) are unchanged.

#### Step 5 — Add the `## Project-Specific` section to the bootstrap template

`skills/sync/SKILL.md` writes a starter `docs/BEST_PRACTICES.md` whose template currently ends after the language sections. This RFC adds a `## Project-Specific` section header at the bottom so freshly-bootstrapped projects ship with the boundary already in place.

The exact insertion point is at the end of the `# Best Practices` template, after every language and stack section but before any closing matter. Search for the "Use `/best-practices-extract` at the end of a session to add new entries." line and the bootstrap-content template that follows; the `## Project-Specific` block is appended at the end of the template.

The block to append:

````markdown
## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md) (path resolves inside the bytewyrd plugin checkout; in a consumer project the file lives at `.claude/plugins/bytewyrd/skills/best-practices-extract/TRIAGE-AND-LIFT.md`).

(none yet — entries are added by `/best-practices-extract` when a learning fails the portability triage)
````

The section starts empty (the `(none yet — ...)` placeholder text). When `/best-practices-extract` writes the first project-specific entry, it removes the placeholder and writes the entry in its place; subsequent writes append below.

Also bump the bootstrap content version marker in `skills/sync/SKILL.md` (the comment line `<!-- bootstrap-content-version: <date>-<hash> -->` near the top of the file) to today's date plus a fresh short hash, so the `SessionStart` hook surfaces the new section to existing projects on next session.

#### Step 6 — Add the `## Project-Specific` section to this repo's `docs/BEST_PRACTICES.md`

Add the same block to the bottom of `/home/divoxx/code/bytewyrd/claude-bytewyrd-workflow/docs/BEST_PRACTICES.md`:

````markdown
## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md).

(none yet — entries are added by `/best-practices-extract` when a learning fails the portability triage)
````

This is a manual write to the existing file; the file's existing entries are left untouched. No retroactive re-sectioning — entries that may belong in `## Project-Specific` (e.g., the "Always write to the current worktree, not main repo root" workflow entry) stay where they are; if a future session re-extracts them, the new triage pass will route them correctly.

#### Step 7 — Verification

After all changes, run these checks. The expected output is the literal text shown.

1. **Shared reference exists and is referenced from all three skills:**
   ```bash
   test -f skills/best-practices-extract/TRIAGE-AND-LIFT.md && echo "OK: TRIAGE-AND-LIFT.md present"
   grep -l 'TRIAGE-AND-LIFT.md' skills/best-practices-extract/SKILL.md skills/best-practices-record/SKILL.md .claude/skills/best-practices-sync/SKILL.md
   ```
   Expected output:
   ```
   OK: TRIAGE-AND-LIFT.md present
   skills/best-practices-extract/SKILL.md
   skills/best-practices-record/SKILL.md
   .claude/skills/best-practices-sync/SKILL.md
   ```
   All three SKILL files must reference the shared procedure. If any is missing, the cross-skill consistency the RFC depends on is broken.

2. **Each skill has a Triage Step in the right position:**
   ```bash
   grep -n '^## Triage Step' skills/best-practices-extract/SKILL.md skills/best-practices-record/SKILL.md
   grep -n '^## Step 2a — Re-triage' .claude/skills/best-practices-sync/SKILL.md
   ```
   Expected output: one match per file. The extract and record files must have the `## Triage Step` heading; the sync file must have the `## Step 2a — Re-triage` heading.

3. **Each skill has a Lift Step:**
   ```bash
   grep -n '^## Lift Step' skills/best-practices-extract/SKILL.md skills/best-practices-record/SKILL.md
   grep -n 'Lift the Combined version' .claude/skills/best-practices-sync/SKILL.md
   ```
   Expected output: one match per file.

4. **The `## Project-Specific` section template is in the bootstrap output:**
   ```bash
   grep -A2 '^## Project-Specific$' skills/sync/SKILL.md
   ```
   Expected output: a match for the section header followed by the introductory text starting with "Entries below describe rules and gotchas specific to this codebase."

5. **The `## Project-Specific` section is in this repo's `docs/BEST_PRACTICES.md`:**
   ```bash
   grep -n '^## Project-Specific' docs/BEST_PRACTICES.md
   ```
   Expected output: a single line match.

6. **No project-specific identifiers leaked into the new normative content** (sanity check on the RFC author's own writing). The grep targets only the three SKILL files (not `TRIAGE-AND-LIFT.md`, which legitimately contains the example identifiers in its worked-examples table and Pass 1 strip-list):
   ```bash
   grep -n 'RouterConfig\|DetailOverlay\|core::k8s::target' skills/best-practices-extract/SKILL.md skills/best-practices-record/SKILL.md .claude/skills/best-practices-sync/SKILL.md
   ```
   Expected output: empty (no matches). If matches appear, those are leaks of example identifiers from `TRIAGE-AND-LIFT.md` into normative skill text — fix them.

7. **Bootstrap content version marker has been bumped:**
   ```bash
   grep -m1 'bootstrap-content-version:' skills/sync/SKILL.md
   ```
   Expected output: a single matching comment line whose date portion is today's date (`2026-05-10`).

8. **Manual: re-run `/best-practices-extract` in any project session.** Confirm the output presents candidates grouped by destination (`GENERALIZABLE` and `PROJECT-SPECIFIC` headers) before the user is asked to pick. Confirm a project-specific candidate is written to `## Project-Specific` and never appears in `~/.claude/BEST_PRACTICES.md` even if the user accepts.

9. **Manual: re-run `/best-practices-record` with a deliberately project-specific input** (e.g., "the `sync` skill should read from the worktree"). Confirm the skill refuses with the exact message specified in Step 3 of this RFC, with the failed portability question named.

10. **Manual: re-run `/best-practices-sync` after seeding `~/.claude/BEST_PRACTICES.md` with a project-specific entry left over from before this RFC.** Confirm Step 2a presents the re-triage prompt with three options (Skip / Delete / Lift now). Confirm choosing "Lift now" walks through Pass 1, Pass 2, and Verification.

## Risks and open questions

- **Risk: agents over-skip at the triage step.** A learning that is in fact generalizable is marked project-specific because the agent gives too much weight to the wording rather than the principle. Mitigation: the lift step's Pass 1 strip is also a *test* — if Pass 1 produces a useful sentence, the entry is generalizable regardless of the original wording. Agents that internalize this in addition to the three portability questions will under-skip rather than over-skip.

- **Risk: the `## Project-Specific` section becomes a graveyard.** A project file with 30 thematic entries and 200 project-specific entries is not useful — readers stop scanning it. Mitigation: project-specific entries are still subject to the same red flags as generalizable ones (one-off, inferrable from code, library behavior). Triage failure does not lower the bar; it routes the entry to a different section. If a project-specific entry would have been skipped by the existing Mandatory Filters, it stays skipped.

- **Risk: re-triage at sync time produces churn for the user.** Every sync run prompts the user to skip / delete / lift on a backlog of pre-RFC entries. Mitigation: the Skip option leaves entries untouched and excludes them from the run, so the prompts only have to be answered once per entry; subsequent runs re-triage only newly-recorded entries. After the backlog is processed, sync runs are silent on triage.

- **Open question: should the triage predicate be tunable per project?** A polyglot monorepo has weaker framework-portability — a Rust subsystem and a TS subsystem are "the same project" but a learning about one is not portable to the other. Right now the predicate treats project-portability as a single yes/no. **Resolution within this RFC:** the predicate stays uniform. If a Rust learning is recorded in a polyglot project, project-portability is yes (other Rust projects benefit), framework-portability is no (TS projects don't), so the entry passes triage only when phrased as a Rust principle. The polyglot edge case is the same case as a single-language project that switches frameworks. No special tuning needed.

- **Open question: should the lift step be invokable as its own skill?** A user might want to lift an existing entry without going through the full record flow. Right now `best-practices-record`'s lift step is internal — there's no `/best-practices-lift` to lift a sentence in isolation. Out of scope for this RFC; if usage shows the need, a follow-up can extract the lift step into a standalone skill that all three current skills delegate to.

- **Open question: how does this interact with the existing `## Refactoring`, `## Code Design`, `## Code Style` sections in `docs/BEST_PRACTICES.md`?** Those sections are populated by entries that pre-date this RFC and that pre-date even the consolidated thematic structure of `skills/sync/SKILL.md`. They are not in the canonical category list this RFC reuses (which inherits from `best-practices-record`'s table). **Resolution within this RFC:** the canonical list is not exhaustive; existing custom sections (`Refactoring`, `Code Design`, `Code Style`) remain valid destinations. The lift step's Pass 2 prefix table covers the categories `best-practices-record` knows about; for entries that land in `Refactoring` / `Code Design` / `Code Style`, the prefix is the section name itself (`Refactoring:`, `Code Design:`, `Code Style:`) and the entry is written under that section. A future RFC can rationalize the canonical list once usage stabilizes.

- **Note: the worked-examples table in `TRIAGE-AND-LIFT.md` deliberately uses project-specific identifiers (`RouterConfig`, `DetailOverlay`, `core::k8s::target`).** This is intentional — the examples must be concrete to teach the strip procedure; abstract examples ("Component X uses Pattern Y") don't show how to strip identifiers because there are no identifiers to strip. The verification grep in Step 7 check #6 explicitly excludes `TRIAGE-AND-LIFT.md` from the leak-check, and only flags identifier appearances in the three SKILL files.

## Relationship to other RFCs

- **Builds on `2026-05-09-best-practices-content-and-tooling`** (Done). That RFC introduced the three-skill pipeline (`best-practices-extract`, `best-practices-record`, `best-practices-sync`), the canonical category list, and the global file at `~/.claude/BEST_PRACTICES.md`. This RFC adds the triage-and-lift discipline on top of that pipeline. The canonical category list and bootstrap-content-version marker established by the prior RFC are reused unchanged.

- **No conflicts with open RFCs.** The braindump entry for `/refactor` (a separate slash command) is unrelated. The braindump entry for `project-brief as the SSoT in /sync` is unrelated.

- **Future enabler.** Once triage and lift are wired in, a future RFC could add a `/best-practices-audit` skill that walks an existing `BEST_PRACTICES.md` (project-local or global) and re-triages every entry, surfacing leaks for cleanup. The shared `TRIAGE-AND-LIFT.md` file is the contract that audit skill would read.
