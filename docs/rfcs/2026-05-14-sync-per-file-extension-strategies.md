---
rfc: "2026-05-14-sync-per-file-extension-strategies"
title: "Sync Per-File Extension Strategies"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-14"
drop_reason: ~
---

## Summary

Introduce five named extension strategies — `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, and `owned-regions` — and reassign every in-tree plugin-managed file to the strategy that matches how the plugin actually relates to that file's content. `CLAUDE.md` becomes `additive-merge`: the plugin is the authoritative source for every concept it ships, but it adds new items rather than replacing the file, with an automatic soundness-review pass that auto-corrects ordering, duplicates, structural validity, and semantic coherence before writing. `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` become `additive-merge-with-diff`: same item-level merge as `additive-merge` but the user reviews the merged result as a unified diff with hunk-level accept/exclude, manual-3-way-merge, and defer options; two soundness-review passes run (one pre-diff auto-apply, one post-accept explain-and-ask). `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` become `bootstrap`: the plugin writes a starter template once, and from that point forward the file is local-owned and the plugin never touches it again. `docs/rfc-process.md` becomes `authoritative`: the plugin's content is always the file's content, presented in the same Step 4a batch confirmation as additions and fast-forwards, and there is no local extensions section. `README.md` and `docs/BEST_PRACTICES.md` move from `section` to `owned-regions`: a unified replacement for both `section` and `region` that declares plugin-owned content as a list of typed heading boundaries; `section` is recognized as a deprecation alias. The plugin's runtime sidecar `.bootstrap-versions.json` relocates from `.claude/` to `.bytewyrd/` and switches from `whole` to `structured` (its entries are plugin-managed SHA12 hashes; `owned_paths: ["*"]`). After the change, the `conflict_legacy` loop (the "Keep local version" action explicitly does not stamp the marker — verified: skills/sync/SKILL.md:L420) terminates for every file: the next `/sync` either classifies the file as `unchanged` (it already matches plugin canonical content) or applies the strategy's deterministic decision after one batched confirmation. The five strategies replace the file-level conflation that today routes substantively different ownership models through the same `whole`/`section`/`region`/`structured` matrix.

## Should we do this?

**Yes.** The current behavior is a hard regression for every consumer project that has run `/sync` after the per-file marker system shipped. Each of the four files re-surfaces as `conflict_legacy` on every subsequent `/sync` run regardless of whether the user has touched the file since (verified: skills/sync/SKILL.md:L323-L332 — the classification matrix routes any file lacking a `<!-- bootstrap-content-version: ... -->` marker to either `unchanged_legacy` or `conflict_legacy` depending on whether canonical content matches). The only escape paths today are "Adopt plugin version" (which overwrites real local content with the plugin's stub) or "Keep local version" (which does not stamp the marker, so the same prompt re-surfaces on the next run — the action description at `skills/sync/SKILL.md:L420` says this explicitly: "no write; marker not updated; conflict re-surfaces on next run"). The loop is structural: the manifest declares ownership semantics that do not match how the plugin actually relates to the file's content, so the diff engine's classification matrix produces a wrong answer every time. The fix is to make the manifest describe the actual relationships — five distinct relationships, five named strategies, each assigned to the files whose ownership semantics it describes. The strategies fold their decisions into one of three interaction points (the Step 4a batch confirmation, the diff-review prompt for `additive-merge-with-diff`, or the Step 4b contradiction prompt for `additive-merge`) rather than firing a separate per-file `conflict_legacy` prompt every run. This collapses an unbounded series of per-run conflict prompts into a single batched approval (or a structured diff review) per `/sync`.

## Current state

The diff engine recognizes four `extension_strategy` values today — `whole`, `section`, `region`, `structured` — and the canonicalization rules at `skills/sync/SKILL.md:L334-L340` (verified) treat them as pure structural partitions of file content. None of the four values encode anything about *how* the plugin's contribution relates to local content. The Step 4b resolution menu for `conflict` and `conflict_legacy` cases has four resolution options (Adopt / Keep / Merge / Skip) plus a fifth `Adopt plugin and add marker` option exclusive to `conflict_legacy` (verified: skills/sync/SKILL.md:L408-L415). None of those options expresses "the plugin's contribution and the local file's contribution are both intended to coexist, and the plugin's job is to add or update only what it owns without prompting." That semantic — the one most of these files actually need — has nowhere to live in the current model.

**The four files and their current manifest declarations** (each row verified against `.claude-plugin/bootstrap-manifest.json`):

| File | Current `extension_strategy` | Current `owned_*` (verified excerpt) | Local file body (verified) |
|------|------------------------------|---------------------------------------|----------------------------|
| `CLAUDE.md` | `section` (verified: .claude-plugin/bootstrap-manifest.json:L84) | `owned_sections` lists ten H2 headings: `## Toolchain`, `## File structure`, `## Agent delegation`, `## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions` (verified: .claude-plugin/bootstrap-manifest.json:L85-L96) | Local carries all ten plugin-owned sections plus a `## Workflow` section with five subsections (Session start, Requirement-check hook, During work, Considering /refactor, Considering /docs-review, Session end), and the local body of `## Security` is longer than the plugin's body of the same heading (verified: CLAUDE.md as injected in this RFC's session — local `## Security` has six bullet points vs template's six but with project-specific wording about `.env` files and external input validation). |
| `docs/CONTRIBUTING.md` | `whole` (verified: .claude-plugin/bootstrap-manifest.json:L176) | No section/region metadata (whole-file strategy) | Local has plugin-development-specific content the template does not ship: `## Plugin Setup (one-time)` with detailed local-install instructions, `## Agents` with VoltAgent provenance and pull-down procedure, `## Sync` describing `/sync` semantics — none of which appears in `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` (verified: docs/CONTRIBUTING.md:L25-L65, .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl). Template body is a generic skeleton with placeholder substitutions `<PREREQUISITES_SECTION>`, `<INSTALL_COMMAND>`, and `<QUALITY_GATE_DESCRIPTION>` (verified: .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L16,L23,L54). |
| `docs/ARCHITECTURE.md` | `whole` (verified: .claude-plugin/bootstrap-manifest.json:L131) | No section/region metadata (whole-file strategy) | Local has real architecture documentation: detailed `## Overview` paragraph, four `## Components` subsections, `## Data Flow`, six `## Design Decisions` entries, extended notes on plugin installation scope, and a Dependencies table (verified: docs/ARCHITECTURE.md:L1-L76 — file is 76 lines of project-specific content). Template is placeholder-only — every body value reads `<...>` (verified: .claude-plugin/scripts/templates/ARCHITECTURE.md.tpl:L17,L23,L25,L27,L37,L41). |
| `docs/rfc-process.md` | `region` (verified: .claude-plugin/bootstrap-manifest.json:L184) with `region_end_marker: "<!-- END_UPSTREAM_CONTENT -->"` (verified: .claude-plugin/bootstrap-manifest.json:L185) | Local body has the upstream content (lines 1-226) plus a `## Project Extensions` section after the marker (verified: docs/rfc-process.md:L230). The local `## Project Extensions` body is the literal text `*(no project-specific extensions — the global process applies as-is)*` (verified: docs/rfc-process.md:L232) — no project has customized this section. The file also carries `<!-- UPSTREAM: ... -->` and `<!-- LAST_SYNCED: ... -->` leader comments on lines 1-2 (verified: docs/rfc-process.md:L1-L2) but no `<!-- bootstrap-content-version: ... -->` marker. |

**Why each currently classifies as `conflict_legacy`:**

The classification matrix routes any file lacking a `<!-- bootstrap-content-version: ... -->` marker to either `unchanged_legacy` (canonicalized local content matches plugin's canonical content) or `conflict_legacy` (they differ) (verified: skills/sync/SKILL.md:L323-L332). Each file's failure mode is specific to its current strategy:

- `CLAUDE.md` — `section`-strategy canonicalization (verified: skills/sync/SKILL.md:L338) concatenates the bodies of every heading in `owned_sections`. Because the plugin claims ten sections but consumer projects (including the bytewyrd plugin's own checkout) carry locally-customized bodies in at least one of those sections, the plugin's canonical-form SHA and the local canonical-form SHA diverge. Net classification: `conflict_legacy` on every run, with no path to "this divergence is fine, keep both."
- `docs/CONTRIBUTING.md` — `whole`-strategy canonicalization is the full file body minus marker line(s) (verified: skills/sync/SKILL.md:L336). The template body is a generic skeleton; the local body is project-specific. The two are never byte-equal, so the file is always `conflict_legacy`. The user's choices are "destroy local content" or "be prompted again forever."
- `docs/ARCHITECTURE.md` — same failure mode as CONTRIBUTING.md, with greater divergence because the template is pure placeholders while the local file contains a fully-composed architecture document.
- `docs/rfc-process.md` — `region`-strategy canonicalization is content from line 1 to `region_end_marker` with marker lines removed (verified: skills/sync/SKILL.md:L337). The local upstream region matches the plugin's upstream region byte-for-byte today (because `/rfc-update` and earlier `/sync` runs kept it current), so technically this file classifies as `unchanged_legacy` rather than `conflict_legacy` — but the file still flows through the legacy-marker-injection path on every run that lacks the bootstrap marker, and the existing `<!-- UPSTREAM: ... -->`/`<!-- LAST_SYNCED: ... -->` leader-comment convention competes with the new marker-insertion rule at `skills/sync/SKILL.md:L434`. The file is not stable either.

**The loop:** when the user picks "Keep local version" for any of these, no marker is written (verified: skills/sync/SKILL.md:L420). The next `/sync` re-classifies the file with no marker → `conflict_legacy` again. The user is told the same thing every run. This is the exact problem this RFC closes.

## Analysis / Options

Two coupled decisions: (1) the high-level fix shape — introduce new strategies that describe the relationships precisely, or add an acknowledgment path that lets the user opt out of the existing model; and (2) for each affected file, which strategy is the right match for its actual relationship to the plugin.

### Strategy coexistence — new strategies replace and extend the existing model

This RFC introduces five new strategies — `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, and `owned-regions` — and retires three of the four existing ones for in-tree files. The retirements:

- **`whole`** — deprecated for in-tree files. Every file currently using `whole` moves to a more precise strategy (`additive-merge-with-diff` for templates that the project edits, `structured` for the sidecar — see item below). The strategy stays in the schema for backward compatibility with consumer manifests that have not yet upgraded.
- **`section`** — replaced by `owned-regions`. The `section` value is recognized as a deprecation alias (see `owned-regions` strategy below) and triggers a one-time upgrade notice; behavior is unchanged.
- **`region`** — replaced by `owned-regions`. Zero files use `region` after this RFC ships (the only current user, `docs/rfc-process.md`, moves to `authoritative`). The diff engine emits an error rather than carrying alias logic, because no in-tree file exercises the alias path.

After this RFC ships, every artifact in `bootstrap-manifest.json` (relocated from `.claude-plugin/bootstrap-manifest.json` per Decision 3) is assigned to one of seven strategies (each row reflects the final assignment after the manifest changes documented in "Implementation spec" below):

- **`whole`** — no remaining in-tree files. (Strategy retained in the schema for backward compatibility with consumer manifests; deprecated for new entries.)
- **`section`** — replaced by `owned-regions`; no files remain.
- **`region`** — zero users post-RFC; replaced by `owned-regions`.
- **`structured`** — `.claude/settings.json` (verified: .claude-plugin/bootstrap-manifest.json:L16), `.claude/settings.local.json` (verified: .claude-plugin/bootstrap-manifest.json:L39), `.gitignore` (verified: .claude-plugin/bootstrap-manifest.json:L73), `mise.toml` (verified: .claude-plugin/bootstrap-manifest.json:L193), and `.bytewyrd/.bootstrap-versions.json` (moved from `.claude/.bootstrap-versions.json` per this RFC — see item 9 of "Exact manifest changes" in the Implementation spec below).
- **`additive-merge`** (new) — `CLAUDE.md`.
- **`additive-merge-with-diff`** (new) — `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/ci.yml`.
- **`bootstrap`** (new) — `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`.
- **`authoritative`** (new) — `docs/rfc-process.md`.
- **`owned-regions`** (new) — `README.md`, `docs/BEST_PRACTICES.md`.

The strategy-first dispatch in the integrated classifier (described in "Diff-engine integration" below) routes each artifact to its strategy's code path. The two retained canonicalization-based strategies (`structured` and the legacy-aliased `whole`) share the existing classification matrix at `skills/sync/SKILL.md:L323-L332` (verified); the five new strategies short-circuit it. No artifact uses more than one strategy, and no strategy depends on another.

### Decision 1 — New strategies vs. acknowledgment path

**Option A — Introduce five new extension strategies (`additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, `owned-regions`) and assign each plugin-managed file to the strategy that matches its actual relationship to the plugin (recommended).**

For each file, the manifest declares a strategy whose semantics directly describe the relationship: "the plugin contributes items here and merges them additively" (`additive-merge`), "the plugin contributes items, but the project reviews the merged result as a diff before writing" (`additive-merge-with-diff`), "the plugin writes a starter template once and never touches the file again" (`bootstrap`), "the plugin is the source of truth and always wins" (`authoritative`), or "the plugin owns specific bounded regions of the file" (`owned-regions`). The diff engine implements each strategy's classification and apply logic; the user sees no `conflict_legacy` prompt for these files unless a strategy explicitly produces a conflict (which only `additive-merge` and `additive-merge-with-diff` can do, and only when local and plugin items semantically contradict). The strategies route their decisions into one of three interaction points: the Step 4a batch confirmation (`bootstrap` shows a one-time "create this file?" checkbox; `authoritative` shows an "update this file?" checkbox per plugin-version update; `additive-merge` enters Step 4a only when there are plugin items to append); the diff-review prompt (`additive-merge-with-diff` only); or the Step 4b contradiction menu (`additive-merge` and `additive-merge-with-diff` only, and only when an item-level semantic contradiction is detected).

This option requires five new strategy values, five new classification-and-apply code paths in the diff engine, the manifest schema accepting new values for `extension_strategy`, and a new `owned_boundaries` array field that pairs with `owned-regions`. It adds two new prompt types beyond the existing Step 4b menu: a four-option contradiction menu for `additive-merge` and `additive-merge-with-diff` (Adopt plugin / Keep local / Keep both / Skip for now), and a four-option diff-review prompt for `additive-merge-with-diff` (Accept all / Accept with exclusions / Manual 3-way merge / Defer). `bootstrap` and `authoritative` never enter Step 4b or the diff-review prompt — their decisions are Step 4a checkboxes. The Step 4a batch confirmation gains additional per-file checkbox categories (one for `bootstrap` creations, one for `authoritative` adds, one for `authoritative` updates) alongside the existing additions and fast-forwards.

**Option B — Keep the existing four strategies and add a fifth resolution option, "Keep local and mark acknowledged," that stamps the marker without modifying content.**

A new option on the Step 4b menu for `conflict_legacy` files: pick "Keep local and mark acknowledged" and the diff engine writes a `<!-- bootstrap-content-version: <upstream_key>:<local_current_canonical_sha> -->` marker into the local file without modifying any body content. The marker's SHA is the hash of the local canonical content, so the next `/sync` reads the marker, hashes the (unchanged) local content, and classifies as `local_only` — no prompt.

This works mechanically but has three structural problems:

1. **It papers over a semantic mismatch rather than fixing it.** The manifest is supposed to describe how the plugin relates to a file. If the plugin's relationship to `docs/ARCHITECTURE.md` is "write once and never touch again," the manifest should say so — not declare `whole` ownership and then offer an opt-out that lets the diff engine ignore the lie.
2. **The acknowledgment is one-shot.** Every future plugin update to the file will land a new template SHA and re-trigger the classification, because the marker recorded the *local* SHA rather than the plugin's SHA. The user will be re-prompted on every plugin update, with the same useless choice each time.
3. **It conflates relationships.** A file resolved by "Adopt plugin and add marker" and a file resolved by "Keep local and mark acknowledged" both end up with a bootstrap-content-version marker present. The diff engine reads only the marker, not the resolution path that produced it. If the plugin updates the file later, the diff engine has no way to know whether the user merged the previous plugin version into local content or ignored it. That uncertainty bleeds into every subsequent prompt.

**Recommendation: Option A.** The five relationships are real — `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, and `owned-regions` each describe a distinct way the plugin and the project actually relate to a file's content. Encoding them as named strategies makes the manifest the precise source of truth and removes per-run prompts for the strategies that have a deterministic outcome (`bootstrap`'s `local_only` and `authoritative`'s `unchanged`). Option B's acknowledgment path is genuinely useful for files where no strategy fits, but adding it without first naming the strategies leaves the architecture incoherent: the manifest would still misdescribe the file's relationship, and the acknowledgment option would be a workaround for the misdescription rather than a way to handle a genuinely exceptional case.

**Door stays open on Option B.** Nothing in Option A precludes adding the acknowledgment option later as a fallback. The two options operate at different layers (strategy declaration vs. resolution-time interaction) and a future RFC can add it if a file emerges that needs ownership semantics none of the five strategies covers.

### Decision 2 — Strategy assignment per file

The five strategies in detail (each defined first, then assigned to files):

#### Strategy 1: `additive-merge` — for `CLAUDE.md`

**Definition.** The plugin is the authoritative source for every concept it expresses, but the file is structurally an open list that the project may extend. The plugin's contribution and the local file's contribution are merged item-by-item rather than canonical-form-vs-canonical-form. Merge semantics:

- **Plugin item not in local file** → add it to local (the plugin is shipping a new concept; the project gets it)
- **Local item not in plugin manifest** → preserve it (the local file is adding a novel concept the plugin doesn't ship)
- **Same concept appears in both with different wording** → plugin wording wins (the plugin is authoritative for the concepts it ships; the local wording is replaced)
- **Local item explicitly contradicts a plugin item** → flag as conflict for human resolution

"Same concept, different wording" and "explicit contradiction" require semantic comparison, not byte equality. Two strings expressing the same rule (e.g., "Default to `haiku` unless the task clearly requires more" and "Prefer the cheapest model unless complexity demands more") are conceptually identical. Detection is by LLM-assisted matching: during `/sync`'s execution the agent prompts itself, item-by-item, to classify each (plugin-item, local-item) pair as "same concept", "different concepts", or "explicit contradiction." Contradiction = the local item negates, prohibits, or sets an opposing prescription to a plugin item (for example, local says "never do X" when the plugin says "do X"). This is feasible because `/sync` is an agent-driven skill — its body is markdown executed by an agent (verified: skills/sync/SKILL.md:L1-L4 declares the skill name and description; the body that follows is a sequence of natural-language steps including `AskUserQuestion` calls at e.g. skills/sync/SKILL.md:L146, not a script), so LLM-mediated comparison is a natural fit rather than an architectural mismatch.

**`owned_sections` stays at the full list of sections the plugin ships.** The plugin does not narrow what it claims to own — that's what `bootstrap` is for. `additive-merge` says "I own every concept I express, but I express them as additive items, not as a full-section overwrite." The owned-sections list for `CLAUDE.md` is therefore the same ten headings the manifest declares today (verified: .claude-plugin/bootstrap-manifest.json:L85-L96), and the merge operates within each section's body items.

**Why `CLAUDE.md` fits.** The plugin contributes a stable, growing corpus of conventions — Tool Usage rules, Evidence-Based Development principles, Model Usage Optimization rules, Sandbox compatibility guidance, Security rules, RFC Process pointers, etc. Projects extend these (the bytewyrd plugin's own checkout has a full `## Workflow` section with project-specific session-start, requirement-check, refactor, and docs-review subsections that the template does not ship — verified: CLAUDE.md as injected in this RFC's session, lines for `## Workflow` and its subsections). Replacing the whole file would destroy that work; replacing the section bodies would destroy partial customizations within a plugin-owned section. Additive item-by-item merging is the only model that does the right thing for both directions.

**Soundness review.** `additive-merge` runs one soundness-review pass after the merge step computes the candidate body. All issues are auto-applied with no user prompt (the user never sees the issue list or the pre-correction state). Zero issues → write directly. See "Soundness review" below for the reviewer's checks and the output shape.

#### Strategy 2: `additive-merge-with-diff` — for `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml`

**Definition.** Identical to `additive-merge` for the merge step (LLM item matching, plugin wins on same-concept, local-only preserved, contradictions flagged). The differences are: (a) after the merge is computed in memory but before writing, a **soundness-review pass** auto-applies corrections; (b) the user then reviews the merged result as a **unified diff** (merged result vs current local file) with hunk-level controls; (c) after the user accepts, a second soundness-review pass runs to explain any remaining issues and ask how to handle them.

User options at the diff-review prompt:

- **`Accept all`** — write the merged result as-is.
- **`Accept with exclusions`** — present hunks as a multiSelect checkbox list (one entry per hunk, labeled with file location and a short summary); the user deselects hunks they want to exclude. Excluded hunks revert to local content (the merged result is recomposed with the deselected hunks reverted).
- **`Manual 3-way merge`** — write the file with git-style conflict markers (`<<<<<<< local`, `=======`, `>>>>>>> plugin`) for changed sections; unchanged sections written cleanly. The user resolves the markers manually and re-runs `/sync`.
- **`Defer`** — no write; re-surface on the next run.

**File-type-specific item parsing.** The merge step's item parser has rules per file type:

- `.github/PULL_REQUEST_TEMPLATE.md` — markdown items (list items, code blocks, paragraphs, labeled blocks) within H2 sections.
- `.github/workflows/ci.yml` — YAML structure: each top-level YAML key (`name:`, `on:`, `jobs:`, `env:`) is one item; within `jobs:`, each job key is a sub-item. The parser preserves YAML indentation and structure.

**Soundness review (two passes).** *Pass 1* runs before showing the diff and auto-applies fixes — the diff that the user sees reflects the already-corrected result, not the raw merge output. *Pass 2* runs after the user selects `Accept all` or `Accept with exclusions`; if issues remain, the user is presented with the issue list and asked whether to fix automatically or write as-is. The `Manual 3-way merge` and `Defer` branches skip Pass 2 (the file is either written with conflict markers, which the reviewer cannot meaningfully evaluate, or not written at all). See "Soundness review" below for the reviewer's checks and the output shape.

**Why `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` fit.** Both files are routinely customized per-project (a PR template often gains a project-specific checklist; CI workflows gain project-specific jobs, secrets, and steps) but also receive plugin updates (a new top-level section in the PR template, a new linter job in CI). The plugin's contribution is meaningful and the local customizations are equally meaningful — neither side can be silently overwritten or silently appended without breaking the file's purpose. The user needs to see the proposed change as a diff and decide hunk by hunk. The two soundness-review passes catch ordering errors (e.g., the new `## Testing` section landing before `## Summary`), duplicates, structural validity (broken YAML indentation), and semantic coherence (two adjacent rules contradicting each other).

#### Strategy 3: `bootstrap` — for `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`

**Definition.** The plugin's role is to provide a starter template on the first `/sync` in a project that does not yet have the file. The creation is surfaced in the **Step 4a batch confirmation** so the user explicitly opts in to the new file. Once the file exists locally (whether the plugin wrote it or not), the plugin gives up authority over the file forever. Classification semantics:

- **File absent in local repo** → classify as `bootstrap_create`; surface as a batch checkbox in Step 4a:
  - If the user confirms the item → render the template, write the file with the two-line bootstrap header (see below), track as `bootstrapped`. The file is reclassified as `local_only` on every subsequent `/sync` run — no future prompts, no updates.
  - If the user deselects the item → no write; record as `deferred (bootstrap)`; re-presented on the next `/sync` run.
- **File present in local repo (regardless of marker state)** → classify as `local_only`; no diff, no prompt, no update, ever

There is no "fast-forward" path for `bootstrap` files. The plugin's template can change in future plugin versions, and that change will *not* propagate to existing files — by design. The plugin's job ends after the first write.

**Two-line file header.** After the initial write, the sync skill writes a two-line block at the top of the file in place of the single-line `<!-- bootstrap-content-version: ... -->` marker used by the existing strategies:

```
<!-- bootstrap-content-version: <upstream_key>:<sha12> -->
<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->
```

Both lines are stripped during canonicalization for any future classification compare (same rule as the existing single-marker strip — `bootstrap` does not run that compare because the file classifies as `local_only` on subsequent runs, but the stripping rule is consistent with the rest of the diff engine so a future strategy change for the file would behave correctly). The second line is a fixed string; it does not vary by file and is not part of the manifest. It exists for human readers who open the file and need to know the plugin will not touch it again.

**Why `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` fit.** Both files document project-specific reality: how to set up *this* project's development environment, what *this* project's architecture is. A generic template is useful exactly once — on day one of a fresh repo. After that, every meaningful change is project-specific and any attempt by the plugin to keep them in sync amounts to overwriting the project's own documentation. `bootstrap` describes the only sane plugin role for these files: hand the project a starting point, then step out of the way.

#### Strategy 4: `authoritative` — for `docs/rfc-process.md`

**Definition.** The plugin's content is always the file's content. Every `/sync` run that would change the file presents it in the **Step 4a batch confirmation** alongside additions and fast-forwards, so the user always sees and approves the update — but the user has no per-line conflict resolution, and they cannot keep local edits selectively. The choices for an `authoritative` item in the batch are "approve the overwrite" or "defer this file to the next run." There is no local extensions section. Classification and apply semantics:

- **Plugin content equals local content** → classify as `unchanged`; no write, no batch entry
- **Plugin content differs from local content (regardless of whether local edits exist)** → classify as `authoritative_update`; surface as a batch checkbox in Step 4a:
  - If the user confirms the item → overwrite local with plugin content; stamp the two-line header (see below); track as `authoritative update applied`
  - If the user deselects the item → no write; record as `deferred (authoritative)`; re-presented on the next `/sync` run

The plugin's `rfc-process.md` upstream content is the entire file content. There is no `region_end_marker` because there is no project-extension region; what used to live under `## Project Extensions` in the local file is dropped under this strategy.

**Two-line file header.** After every write (both `add` and `authoritative_update`), the sync skill writes a two-line block at the top of the file in place of the single-line `<!-- bootstrap-content-version: ... -->` marker used by the existing strategies:

```
<!-- bootstrap-content-version: <upstream_key>:<sha12> -->
<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->
```

Both lines are stripped during canonicalization for the classification compare (same rule as the existing single-marker strip — see canonicalization rules in "Algorithm for each strategy" below). The second line is a fixed string; it does not vary by file and is not part of the manifest. It exists for human readers who open the file and need to know not to edit it.

**Why `docs/rfc-process.md` fits.** The RFC process is a workflow the plugin enforces across every consumer project. Divergent local versions are an anti-feature — they break the shared vocabulary that makes the RFC skills (`/rfc-new`, `/rfc-implement`, etc.) interoperable. The existing `## Project Extensions` section was a hedge against the case where a project genuinely needed to extend the process locally; in practice, no consumer project has used it (verified: docs/rfc-process.md:L232 — the only existing instance has the body `*(no project-specific extensions — the global process applies as-is)*`, and the plugin ships in the only repo that carries the file). Dropping the extension region simplifies the model: the plugin owns the file outright, every update is a one-checkbox approval in the same batch as everything else, and every consumer is always on the current process after one confirmation.

#### Strategy 5: `owned-regions` — for `README.md` and `docs/BEST_PRACTICES.md`

**Definition.** A unified strategy that replaces both `section` and `region`. Plugin-owned content is declared as a list of typed boundaries; everything outside the declared boundaries is local-owned. The strategy is the long-term replacement for `section` and `region` — both of which had subtly different semantics that confused maintainers and produced surprising results on edge cases (a project that customized a section heading wording, a section that wrapped a region marker, a region marker that landed inside a code fence).

Boundary types (initial implementation):

- `{ "type": "heading", "heading": "## Name" }` — owns the body from the heading line (inclusive) to the next H2 or H1 heading, or EOF, whichever comes first.

Only heading boundaries are implemented in this RFC because no file currently uses `region`-style ownership after the four reclassifications above. A future RFC may add a `comment-region` boundary type for files that need comment-delimited regions (e.g., `{ "type": "comment-region", "start": "<!-- BEGIN -->", "end": "<!-- END -->" }`); the schema is forward-compatible (the array's `type` discriminator allows new types to be added without breaking existing entries).

**Manifest schema.** A new manifest field `owned_boundaries` (array of boundary objects):

```json
"owned_boundaries": [
  { "type": "heading", "heading": "## Overview" },
  { "type": "heading", "heading": "## Installation" }
]
```

`owned_sections` (the legacy field used by `section` strategy) is recognized as an alias: when present, the diff engine reads it as `[{ "type": "heading", "heading": s } for s in owned_sections]` and emits a one-time deprecation notice in the Step 8 report (`This project uses deprecated strategy 'section' in <path> — run /sync to upgrade`). The upgrade notice fires once per artifact per `/sync` run; running `/sync` after upgrading the manifest (per the maintainer-facing migration documented in "Implementation spec" below) clears the notice.

**Backward compatibility for `region`.** Because no file uses `region` after this RFC ships, the diff engine does **not** carry alias logic for `region`. Instead, it emits a clear error if it encounters `extension_strategy: "region"` in any manifest: `no files use region strategy — did you mean 'owned-regions'?` This trades a future-proof carry-forward path for simplicity; the only way to hit the error is for a consumer project to author a manifest from scratch with the obsolete strategy name, which is sufficiently unlikely that the simpler implementation wins.

**Apply logic.** Identical to the existing `section`-strategy apply step (extract bodies for each owned boundary; replace local bodies with plugin bodies; preserve content outside boundaries). The change is purely the schema and the boundary type — the apply loop walks `owned_boundaries` instead of `owned_sections`, and for the only implemented type (`heading`) the resulting region range is identical to what `section` computed.

**Upgrade path for existing `section` files.** Each file currently using `extension_strategy: "section"` is rewritten in the manifest:
- `README.md` (verified: .claude-plugin/bootstrap-manifest.json:L112-L130): `extension_strategy` becomes `owned-regions`; `owned_boundaries` is one heading entry per current `owned_sections` entry (five heading entries: `## Overview`, `## Installation`, `## Usage`, `## Skills`, `## Agents`).
- `docs/BEST_PRACTICES.md` (verified: .claude-plugin/bootstrap-manifest.json:L139-L167): same transformation; nineteen heading entries.

The transformation is mechanical and the apply logic is unchanged — the only behavior change is that consumer projects which have not yet upgraded their manifest see the deprecation notice once per `/sync` until they re-run `/sync` against the upgraded plugin.

**Why `README.md` and `docs/BEST_PRACTICES.md` fit.** Both are mixed-ownership files: the plugin owns specific sections (overview, installation, usage; or pitfall, workflow, language-specific best practices) while the project owns the rest (project-specific notes, language-specific entries the project has added). Heading-bounded ownership is the right semantic for both. Moving them off `section` to `owned-regions` produces no behavioral change today; the strategy switch is a consolidation move that pays off later when a new boundary type (e.g., `comment-region`) is needed for a different file.

#### Variant considered (and rejected): use `additive-merge` for every plugin-managed file

A consistent shape would be appealing — every file gets the same additive treatment. Rejected for three reasons. First, it would force semantic merging on `docs/ARCHITECTURE.md`, where the plugin's contribution is a placeholder template and the local file is a fully-composed document; there are no overlapping "concepts" to merge, just a template that has served its purpose. Second, it would force semantic merging on `docs/rfc-process.md`, where the plugin's intent is to be authoritative (the workflow must be shared exactly); allowing additive local extensions would re-introduce the divergence problem `authoritative` exists to solve. Third, files where the user benefits from reviewing the merged result hunk-by-hunk before writing (PR templates, CI workflows) would either get silent merges they cannot inspect or would force the same hunk-level diff prompt on every `additive-merge` file (including `CLAUDE.md`, where a hunk-level diff would be hostile noise for the common case of a single same-concept replacement). The five strategies exist because the five relationships are genuinely different.

### Decision 3 — Correct plugin directory layout to match official conventions

**Problem.** The current plugin puts infrastructure files inside `.claude-plugin/` that the official Claude Code plugin authoring convention does not allow there. The official constraint is: only `plugin.json` goes inside `.claude-plugin/`; all other directories must be at the plugin root level (verified: the working tree confirms this — verified: .claude-plugin/ contains `bootstrap-manifest.json`, `CLAUDE.md`, `marketplace.json`, `hooks/`, and `scripts/`, none of which are `plugin.json`). Placing these artifacts inside `.claude-plugin/` means the manifest `source` paths, the pre-commit hook symlink, and the build script path all assume a non-standard nesting that the official convention explicitly prohibits.

**Required moves.** The following files are relocated from inside `.claude-plugin/` to the plugin root or a new top-level directory:

| Current path (wrong) | Correct path |
|---|---|
| `.claude-plugin/scripts/build-manifest.sh` | `scripts/build-manifest.sh` |
| `.claude-plugin/scripts/templates/` (all `.tpl` files) | `templates/` (new top-level directory) |
| `.claude-plugin/hooks/hooks.json` | `hooks/hooks.json` |
| `.claude-plugin/hooks/pre-commit/manifest-check.sh` | `hooks/pre-commit/manifest-check.sh` |
| `.claude-plugin/bootstrap-manifest.json` | `bootstrap-manifest.json` |
| `.claude-plugin/marketplace.json` | `marketplace.json` |
| `.claude-plugin/CLAUDE.md` | deleted (orphaned — not consumed by Claude Code's plugin system, which only auto-loads `plugin.json`; not used by `/sync`, which reads from `templates/CLAUDE.md.tpl`) |

**Two cascading updates after the moves:**

1. **`bootstrap-manifest.json` source paths** — every `"source": ".claude-plugin/scripts/templates/FILENAME"` entry changes to `"source": "templates/FILENAME"`. This includes `.bootstrap-versions.json.tpl`, `settings.json.tpl`, `settings.local.json.tpl`, `PULL_REQUEST_TEMPLATE.md.tpl`, `ci.yml.tpl`, `.gitignore.tpl`, `CLAUDE.md.tpl`, `README.md.tpl`, `ARCHITECTURE.md.tpl`, `BEST_PRACTICES.md.tpl`, `CONTRIBUTING.md.tpl`, and `mise.toml.tpl`. The manifest `source` path for `docs/rfc-process.md` is already `"rfc-process.md"` (a plugin-root-relative path with no `.claude-plugin/` prefix — verified: .claude-plugin/bootstrap-manifest.json:L181) and does not change.

2. **Git pre-commit hook symlink** — the symlink at `.git/hooks/pre-commit` currently resolves to `../../.claude-plugin/hooks/pre-commit/manifest-check.sh`. After the move it must resolve to `../../hooks/pre-commit/manifest-check.sh`. The symlink is a developer machine artifact (created by the one-time setup step in `docs/CONTRIBUTING.md`), not a committed file. Existing contributors must re-run the setup command to update their symlink. The setup instruction in `docs/CONTRIBUTING.md` and the reminder in `CLAUDE.md` must be updated to reference the new path.

**Why this belongs in this RFC.** The manifest restructuring in Decision 1 and Decision 2 already requires opening `bootstrap-manifest.json` and editing every artifact entry. Correcting the `source` paths at the same time (same file, same edit pass) is the lowest-friction moment to apply the directory fix. Doing the structural correction in a separate RFC would require a second manifest edit pass and a second round of consumer-project re-syncs. The directory restructuring is a mechanical rename with no behavioral change to `/sync`'s runtime logic; it does not introduce new strategies or alter the classification matrix.

## Drawbacks

1. **`additive-merge` requires LLM-assisted semantic comparison and accepts its failure modes.** The diff engine cannot do byte-equality for "same concept, different wording" — it has to ask an LLM. This carries two costs: (a) a per-`/sync` token spend proportional to the size of `additive-merge` files (small in practice — `CLAUDE.md` is ~180 lines, comparisons are bounded by the number of plugin-owned items, not file length); and (b) the LLM can produce false positives ("two items mean the same thing" when they don't — leading to silent overwrites of local wording) and false negatives ("two items are different" when they're conceptually identical — leading to spurious additions or false-flagged conflicts). The error rate is low for well-defined rules with clear semantic boundaries, higher for vague boilerplate. The cost is real but bounded: false positives produce a wording change the user can revert via git; false negatives produce a duplicate item the user can clean up manually. Both modes are recoverable, unlike the current loop, which is not.

2. **`bootstrap` gives up all future plugin authority over the file.** Once a project has `docs/CONTRIBUTING.md` or `docs/ARCHITECTURE.md`, the plugin cannot update it via `/sync` — even if the template improves substantially, even if the project genuinely wants to pick up the new template content. The only recovery path is "delete the local file, then re-run `/sync`," which is destructive and not discoverable from the `/sync` output. A maintainer who improves the template body has no automated way to flow the improvement to existing projects.

3. **`authoritative` overwrites any local edits to `docs/rfc-process.md` after a single batch confirmation.** A project that edits the file directly (perhaps to add a project-specific reviewer table or rename a status label) will see those edits replaced on the next `/sync`. The user does see the update as a checkbox in the Step 4a batch confirmation and can defer it (deselect the checkbox) to keep the local edits for now, but `authoritative` provides no per-line conflict resolution path — the choice is "approve the overwrite" or "keep the file as-is and be re-prompted next run." Today the diff engine offers a richer conflict menu (Adopt / Keep / Merge / Skip) on the same file. Mitigation: document the strategy's overwrite semantics prominently in the second line of the file's two-line header ("Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync."), in `docs/CONTRIBUTING.md` for the plugin (so plugin maintainers don't forget), and in consumer-facing release notes for the plugin version that introduces this RFC's changes (so projects that customized `rfc-process.md` know to migrate their customizations elsewhere before upgrading).

4. **Manifest schema gains five new strategy values plus a new `owned_boundaries` field, each with its own apply logic.** The diff engine's strategy switch becomes wider: today four cases (`whole`, `section`, `region`, `structured`); after this RFC, nine — `whole` and `structured` stay as canonicalization-based; `section` becomes a deprecation alias for `owned-regions`; `region` becomes an error case; and five new strategies (`additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, `owned-regions`) are added. Maintenance of the strategy switch grows correspondingly; the test surface for the apply step grows; the documentation in `skills/sync/SKILL.md` grows. Each new strategy is independent (their apply logic does not depend on the others), so the additional surface is additive complexity rather than entangled complexity, but it is still more code paths to keep correct.

5. **The `## Project Extensions` section in existing `docs/rfc-process.md` files is dropped on the first `authoritative` apply.** Under `authoritative`, the next `/sync` run after this RFC ships presents the file as an item in the Step 4a batch confirmation; approving the item replaces the local file with the plugin's version, including the loss of any `## Project Extensions` content. Any project that customized `## Project Extensions` (today none, per the verification above, but future projects might) would lose that section if they approve the batch item. Mitigation: the user sees the rfc-process.md item in the batch checklist with a clear label that names the strategy, and the implementation spec's first-run migration check additionally surfaces a one-time warning quoting any non-placeholder `## Project Extensions` body *before* the batch confirmation is rendered, giving the user a chance to copy the content elsewhere before deciding how to vote on the checkbox.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Move | `.claude-plugin/scripts/build-manifest.sh` → `scripts/build-manifest.sh` | Relocate to plugin root per official convention; path referenced in Step 5 and Step 6 of Exact steps below. |
| Move | `.claude-plugin/scripts/templates/` → `templates/` | Relocate entire templates directory to plugin root; all twelve `.tpl` files move with the directory. |
| Move | `.claude-plugin/hooks/hooks.json` → `hooks/hooks.json` | Relocate to plugin root `hooks/` directory. |
| Move | `.claude-plugin/hooks/pre-commit/manifest-check.sh` → `hooks/pre-commit/manifest-check.sh` | Relocate pre-commit hook script; pre-commit symlink path must be updated in `docs/CONTRIBUTING.md` and `CLAUDE.md`. |
| Move | `.claude-plugin/bootstrap-manifest.json` → `bootstrap-manifest.json` | Relocate to plugin root. |
| Move | `.claude-plugin/marketplace.json` → `marketplace.json` | Relocate to plugin root. |
| Delete | `.claude-plugin/CLAUDE.md` | Orphaned file — not consumed by the Claude Code plugin system (only `plugin.json` is auto-loaded from `.claude-plugin/`), and not used by `/sync` (the template source is `templates/CLAUDE.md.tpl`). |
| Modify | `bootstrap-manifest.json` | Replace artifact declarations: `CLAUDE.md` gets `extension_strategy: "additive-merge"` with the unchanged ten-section `owned_sections`; `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` get `extension_strategy: "bootstrap"`; `docs/rfc-process.md` gets `extension_strategy: "authoritative"` with `region_end_marker` removed; `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` get `extension_strategy: "additive-merge-with-diff"`; `README.md` and `docs/BEST_PRACTICES.md` convert from `extension_strategy: "section"` to `extension_strategy: "owned-regions"` with `owned_sections` rewritten as `owned_boundaries` (one heading entry per current `owned_sections` entry); the `.bootstrap-versions.json` artifact moves to a new entry — `target` changes from `.claude/.bootstrap-versions.json` to `.bytewyrd/.bootstrap-versions.json`, `extension_strategy` changes from `whole` to `structured` with `owned_paths: ["*"]` (every key in the JSON object is plugin-managed), and `upstream_key` bumps to `bytewyrd/.bytewyrd/.bootstrap-versions.json@v2` (path changed, requires re-sync). All `source` paths are updated from `.claude-plugin/scripts/templates/FILENAME` to `templates/FILENAME` (see Decision 3). |
| Modify | `templates/.gitignore.tpl` | Change the `.bytewyrd/` ignore entry to `.bytewyrd/*` plus `!.bytewyrd/.bootstrap-versions.json` so the sidecar is tracked while other runtime state files under `.bytewyrd/` remain ignored. |
| Modify | `skills/sync/SKILL.md` | Extend the canonicalization-rules block (currently lines 334-340), the Step 4a batch-confirmation block (currently lines 380-394), and the apply-actions block (currently lines 440-456) with five new strategy branches: `additive-merge` (item-level matching with one auto-apply soundness pass); `additive-merge-with-diff` (item-level matching with two soundness passes — pre-diff auto-apply, post-accept explain-and-ask — plus a unified-diff review prompt with `Accept all`/`Accept with exclusions`/`Manual 3-way merge`/`Defer` options); `bootstrap` (presence-check short-circuit; batch checkbox on file-absent; no canonicalization or diff on file-present); `authoritative` (full-content compare after two-line-header strip; batch checkbox on differing content; no Step 4b menu); `owned-regions` (unified replacement for `section` and `region`; reads `owned_boundaries` or the `owned_sections` deprecation alias). Extend the classification matrix at lines 323-332 with five new outcome branches that route files to their strategy-specific paths before the existing matrix runs; emit an error on `extension_strategy: "region"` and a deprecation notice on `extension_strategy: "section"`. Convert the Step 4a yes/no two-question pattern to a single `multiSelect: true` AskUserQuestion with per-file checkboxes spanning additions, fast-forwards, legacy-marker insertions, bootstrap creations, authoritative adds, and authoritative updates. Extend Step 4b's resolution menu to handle the one prompt `additive-merge` can produce (item-level contradiction); add the diff-review prompt and the soundness Pass 2 explain-and-ask prompt for `additive-merge-with-diff`. Update Step 5.5's sidecar path from `.claude/.bootstrap-versions.json` to `.bytewyrd/.bootstrap-versions.json` (currently referenced at SKILL.md L295, L309, L557, L698, verified). Add a one-time migration check at the top of Step 3 that copies the sidecar from `.claude/` to `.bytewyrd/` if the old path exists and the new path does not, then deletes the old file. |
| Modify | `templates/CONTRIBUTING.md.tpl` | No structural change — the template body stays as-is (the existing generic skeleton with `<PREREQUISITES_SECTION>`, `<INSTALL_COMMAND>`, `<QUALITY_GATE_DESCRIPTION>` placeholders is still the right thing for a new project to start with). Verified: the current template at lines 1-67 is a reasonable starting point for any project. |
| Modify | `templates/ARCHITECTURE.md.tpl` | No structural change — the placeholder-heavy template is the right thing for a new project to start with (the placeholders guide the user through composing each section). |
| Modify | `docs/rfc-process.md` (in the bytewyrd plugin's own checkout; this is the file consumer projects sync from) | Remove the `## Project Extensions` section entirely (lines 230-232 inclusive: heading, blank, placeholder body), the separator line before it (line 228: `---`), and the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226. Under `authoritative` the entire file is plugin-owned; the separator and the project-extensions section no longer have meaning. The three leader comments on lines 1-3 (`<!-- UPSTREAM: ... -->`, `<!-- LAST_SYNCED: ... -->`, and the explanatory comment about `END_UPSTREAM_CONTENT`) plus the blank line 4 are also removed — they were part of the older marker convention. After the edits, the file's line 1 is the H1 `# RFC Process` (currently line 5). The plugin's source file in the repo does **not** carry the two-line `authoritative` header — that header is inserted by the sync skill at write time on every consumer-project apply, not stored in the plugin source. |
| Modify | `docs/CONTRIBUTING.md` | Update the pre-commit hook setup command: the symlink target path changes from `../../.claude-plugin/hooks/pre-commit/manifest-check.sh` to `../../hooks/pre-commit/manifest-check.sh`. |
| Modify | `CLAUDE.md` | Update any path references to the pre-commit hook or to `.claude-plugin/` subdirectories to use the new plugin-root paths. |
| Add | (none) | No new files. Five new strategies live as additional branches inside the existing `skills/sync/SKILL.md` body; no new template files (all existing templates move from `.claude-plugin/scripts/templates/` to `templates/`); new manifest fields are the `owned_boundaries` array (for `owned-regions`) — added alongside the existing `owned_paths`/`owned_sections` fields, not replacing them. |

### Exact manifest changes

The full diff against `bootstrap-manifest.json` (relocated from `.claude-plugin/bootstrap-manifest.json` per Decision 3):

**1. `CLAUDE.md` — change `extension_strategy` to `additive-merge`.**

Replace the existing `extension_strategy: "section"` value (currently at line 84) with `extension_strategy: "additive-merge"`. The `owned_sections` array (lines 85-96, ten entries) is unchanged. The `templated`, `template_inputs`, `target`, `source`, and `upstream_key` fields are unchanged. The `template_sha` field is recomputed by `build-manifest.sh` only if the template body changes; it does not depend on the strategy field. The final entry shape:

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "source": "templates/CLAUDE.md.tpl",
  "target": "CLAUDE.md",
  "template_sha": "<existing hash>",
  "extension_strategy": "additive-merge",
  "owned_sections": [
    "## Toolchain",
    "## File structure",
    "## Agent delegation",
    "## Tool Usage",
    "## RFC Process",
    "## Evidence-Based Development",
    "## Model Usage Optimization",
    "## Claude Code Sandbox — Container Tool Compatibility",
    "## Security",
    "## Conventions"
  ],
  "templated": true,
  "template_inputs": [
    "project_name",
    "description",
    "project_slug",
    "languages",
    "installed_plugins",
    "component_roots"
  ]
}
```

**2. `docs/CONTRIBUTING.md` — change `extension_strategy` to `bootstrap`.**

Replace the existing entry (currently lines 171-178 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/CONTRIBUTING.md@v1",
  "source": "templates/CONTRIBUTING.md.tpl",
  "target": "docs/CONTRIBUTING.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "bootstrap",
  "templated": false
}
```

The `sha256` field stays — `build-manifest.sh` writes it from the template source (verified: .claude-plugin/scripts/build-manifest.sh:L36-L42; relocated to `scripts/build-manifest.sh` per Decision 3), and the diff engine uses it only on the very first `/sync` in a project that lacks the file (where the SHA records the plugin version that produced the local file's contents). No `owned_sections`, `owned_paths`, or `region_end_marker` fields — `bootstrap` has no concept of partial ownership.

**3. `docs/ARCHITECTURE.md` — change `extension_strategy` to `bootstrap`.**

Replace the existing entry (currently lines 126-133 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/ARCHITECTURE.md@v1",
  "source": "templates/ARCHITECTURE.md.tpl",
  "target": "docs/ARCHITECTURE.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "bootstrap",
  "templated": false
}
```

Same shape as `docs/CONTRIBUTING.md`. `templated` stays `false` because the existing template body is plain text (verified: templates/ARCHITECTURE.md.tpl has no `<...>` placeholders that the renderer would substitute — the angle-bracket strings inside the body are documentation guidance, not renderer tokens; the renderer's "Unrecognized placeholders are replaced with empty string" rule at `skills/sync/SKILL.md:L431` would silently delete them if `templated` were `true`).

**4. `docs/rfc-process.md` — change `extension_strategy` to `authoritative`; remove `region_end_marker`.**

Replace the existing entry (currently lines 179-186 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/rfc-process.md@v1",
  "source": "rfc-process.md",
  "target": "docs/rfc-process.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "authoritative",
  "templated": false
}
```

The `region_end_marker: "<!-- END_UPSTREAM_CONTENT -->"` field is removed. `authoritative` does not partition the file; the entire file is plugin-owned.

**5. `.github/PULL_REQUEST_TEMPLATE.md` — change `extension_strategy` to `additive-merge-with-diff`.**

Replace the existing entry (currently lines 47-53 in the manifest, verified) with:

```json
{
  "upstream_key": "bytewyrd/.github/PULL_REQUEST_TEMPLATE.md@v1",
  "source": "templates/PULL_REQUEST_TEMPLATE.md.tpl",
  "target": ".github/PULL_REQUEST_TEMPLATE.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "additive-merge-with-diff",
  "templated": false
}
```

The item parser for `additive-merge-with-diff` operates on the markdown items inside each H2 section (`## Summary`, `## Changes`, `## Testing`, `## Notes for Reviewers` — verified: templates/PULL_REQUEST_TEMPLATE.md.tpl:L1-L21, relocated from `.claude-plugin/scripts/templates/` per Decision 3); there is no manifest field that enumerates the sections, because the parser walks the file's actual H2 headings.

**6. `.github/workflows/ci.yml` — change `extension_strategy` to `additive-merge-with-diff`.**

Replace the existing entry (currently lines 54-69 in the manifest, verified) with:

```json
{
  "upstream_key": "bytewyrd/.github/workflows/ci.yml@v1",
  "source": "templates/ci.yml.tpl",
  "target": ".github/workflows/ci.yml",
  "template_sha": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "additive-merge-with-diff",
  "templated": true,
  "template_inputs": [
    "languages",
    "component_roots"
  ]
}
```

The YAML item parser treats each top-level YAML key as one item; within `jobs:`, each job key is a sub-item (see "Algorithm for each strategy" below).

**7. `README.md` — convert `extension_strategy` from `section` to `owned-regions`.**

Replace the existing entry (currently lines 107-126 in the manifest, verified) with:

```json
{
  "upstream_key": "bytewyrd/README.md@v1",
  "source": "templates/README.md.tpl",
  "target": "README.md",
  "template_sha": "<existing hash>",
  "extension_strategy": "owned-regions",
  "owned_boundaries": [
    { "type": "heading", "heading": "## Overview" },
    { "type": "heading", "heading": "## Installation" },
    { "type": "heading", "heading": "## Usage" },
    { "type": "heading", "heading": "## Skills" },
    { "type": "heading", "heading": "## Agents" }
  ],
  "templated": true,
  "template_inputs": [
    "project_name",
    "description"
  ]
}
```

The five heading entries correspond one-to-one with the previous `owned_sections` array (verified: .claude-plugin/bootstrap-manifest.json:L112-L130). Apply behavior is unchanged.

**8. `docs/BEST_PRACTICES.md` — convert `extension_strategy` from `section` to `owned-regions`.**

Replace the existing entry (currently lines 134-167 in the manifest, verified) with:

```json
{
  "upstream_key": "bytewyrd/docs/BEST_PRACTICES.md@v1",
  "source": "templates/BEST_PRACTICES.md.tpl",
  "target": "docs/BEST_PRACTICES.md",
  "template_sha": "<existing hash>",
  "extension_strategy": "owned-regions",
  "owned_boundaries": [
    { "type": "heading", "heading": "## Pitfall" },
    { "type": "heading", "heading": "## Workflow" },
    { "type": "heading", "heading": "## Claude Code" },
    { "type": "heading", "heading": "## Code Design" },
    { "type": "heading", "heading": "## Code Style" },
    { "type": "heading", "heading": "## Architecture" },
    { "type": "heading", "heading": "## Testing" },
    { "type": "heading", "heading": "## Documentation" },
    { "type": "heading", "heading": "## Security" },
    { "type": "heading", "heading": "## Error Handling" },
    { "type": "heading", "heading": "## Rust" },
    { "type": "heading", "heading": "## JavaScript / TypeScript" },
    { "type": "heading", "heading": "## Python" },
    { "type": "heading", "heading": "## Go" },
    { "type": "heading", "heading": "## Svelte" },
    { "type": "heading", "heading": "## Ruby" },
    { "type": "heading", "heading": "## Rails" },
    { "type": "heading", "heading": "## Kubernetes / CUE / kapply" },
    { "type": "heading", "heading": "## Terraform / Terragrunt" }
  ],
  "templated": true,
  "template_inputs": [
    "languages",
    "has_svelte",
    "has_ruby",
    "has_rails",
    "has_k8s_cue",
    "has_terraform"
  ]
}
```

Nineteen heading entries correspond one-to-one with the previous `owned_sections` array (verified: .claude-plugin/bootstrap-manifest.json:L139-L167).

**9. `.bootstrap-versions.json` — relocate to `.bytewyrd/`, switch to `structured` strategy, bump `upstream_key` to `@v2`.**

Replace the existing entry (currently lines 3-9 in the manifest, verified) with:

```json
{
  "upstream_key": "bytewyrd/.bytewyrd/.bootstrap-versions.json@v2",
  "source": "templates/.bootstrap-versions.json.tpl",
  "target": ".bytewyrd/.bootstrap-versions.json",
  "sha256": "<existing hash>",
  "extension_strategy": "structured",
  "owned_paths": ["*"],
  "templated": false
}
```

Three changes from the current entry:

1. **`target`** changes from `.claude/.bootstrap-versions.json` to `.bytewyrd/.bootstrap-versions.json`.
2. **`extension_strategy`** changes from `whole` to `structured`. Every key in the JSON object is a plugin-managed SHA12 entry (one key per artifact's marker), so `owned_paths: ["*"]` declares every key plugin-owned; there are no project-owned keys.
3. **`upstream_key`** bumps from `bytewyrd/.claude/.bootstrap-versions.json@v1` to `bytewyrd/.bytewyrd/.bootstrap-versions.json@v2`. The path change makes the existing key obsolete; the bump signals that consumer projects must re-sync to pick up the new location.

The `.gitignore` template change (item below) tracks the relocated sidecar while ignoring other runtime state files under `.bytewyrd/`. The migration check in Step 3 of the sync algorithm handles the one-time copy from the old path to the new path.

**10. `.gitignore.tpl` — ignore `.bytewyrd/*` but track the relocated sidecar.**

Modify `templates/.gitignore.tpl` (relocated from `.claude-plugin/scripts/templates/` per Decision 3; current content verified — includes a `.bytewyrd/` line at `.claude-plugin/scripts/templates/.gitignore.tpl`). Change the existing `.bytewyrd/` line (which ignores the whole folder) to:

```
.bytewyrd/*
!.bytewyrd/.bootstrap-versions.json
```

This pattern (ignore all contents of `.bytewyrd/`, then negate the ignore for the sidecar) tracks only `.bootstrap-versions.json` while leaving other runtime state files (logs, caches, scratch outputs) ignored. The negation pattern is standard `.gitignore` syntax.

### Algorithm for each strategy

#### `additive-merge` — `CLAUDE.md`

**Canonicalization for classification.** Same as today's `section` strategy: extract each heading in `owned_sections` (manifest order); for each, concatenate the heading line + `\n` + body (trimmed of leading/trailing blank lines) + `\n`. Hash the concatenation. This canonical form is used only for the cheap pre-check: "is the local file already identical to the plugin's canonical content?" If yes, classify as `unchanged` and skip the rest. The cheap pre-check matches today's `unchanged_legacy` path semantics and short-circuits the LLM-assisted comparison for files that need no merging.

**Apply step (when classification is not `unchanged`).** For each plugin-owned section listed in `owned_sections`:

1. **Locate the section in the plugin's rendered template** (call this `plugin_section_body`). Parse it into a list of items. An item is a discrete unit of meaning — typically a list item (`- `, `* `, `1. `), a code block, a paragraph, or a labeled block (e.g., `**Bold label** description`). The parser splits at line-boundary item starts and preserves nested content (e.g., a list item that contains a nested code block is one item).

2. **Locate the section in the local file** (call this `local_section_body`). If the section is absent from local, insert the plugin's full rendered body at the section's manifest-order position (after the last preceding owned section that is present in local). Skip to the next section. If the section is present, parse it into items using the same parser.

3. **For each item in `plugin_items`:**
   a. Run the LLM-comparison helper against each item in `local_items` to find the best match. The helper returns one of: `same_concept`, `different_concept`, or `contradiction`. The helper's prompt is fixed and short — included in full below. Apply a confidence threshold (the helper returns a confidence in [0.0, 1.0]); below 0.5, treat the result as `different_concept` to err on the side of preserving local content.
   b. If a `same_concept` match exists: replace the local item's text with the plugin item's text (plugin wins on wording).
   c. If no match exists: append the plugin item to the section, after the last item that came from the plugin (manifest-order: plugin items are kept contiguous within the section, in the order they appear in the template).
   d. If a `contradiction` match exists: record the (plugin_item, local_item, section) tuple in a `pending_contradictions` list. Do not modify either item yet.

4. **For each item in `local_items` that was not matched as `same_concept` to any plugin item:** preserve it byte-for-byte in the local section.

5. **After all sections are processed**, if `pending_contradictions` is non-empty, present them to the user. For each contradiction, ask one AskUserQuestion: "In `CLAUDE.md` section `<heading>`, the plugin and local file have contradicting items. Plugin says: `<plugin_item_text>`. Local says: `<local_item_text>`. Resolve?" with options:

   - `Adopt plugin item (replace local with plugin)`
   - `Keep local item (skip plugin update for this item)`
   - `Keep both (rare — append plugin without removing local)`
   - `Skip for now (re-surface next run)`

   The contradiction prompt is the only per-run user interaction `additive-merge` produces. It only fires when the helper returns `contradiction` with confidence ≥ 0.5, which is by construction rare (genuine semantic opposition between project and plugin rules is rare).

6. **Soundness review (single auto-apply pass, before reserialization).** After steps 1-5 produce the merged file in memory, run the soundness review (defined in "Soundness review" below). The reviewer returns a structured list of issues. Apply all suggested fixes automatically with no user prompt — `additive-merge` does not surface the diff or the issues. If the reviewer returns an empty issue list, proceed unchanged. The reviewer is best-effort; failures are treated as zero issues.

7. **Reserialize the file.** Marker on line 2 (per `skills/sync/SKILL.md:L434`, verified). Sections in their preserved relative order. Update the marker SHA to the new canonical-form hash.

**LLM-comparison helper prompt** (used in step 3a above; this is the fixed prompt the agent submits to itself):

```
You are comparing two text items from a developer documentation file.

Plugin item: <plugin_item_text>
Local item:  <local_item_text>

Classify the relationship as one of:
- same_concept: the items express the same rule, guidance, or fact, possibly in different wording
- different_concept: the items express different concepts; neither is a restatement of the other
- contradiction: the items express opposing rules — one prohibits or negates what the other prescribes

Return JSON: {"relationship": "<one of the three>", "confidence": <float in [0.0, 1.0]>}
```

The helper is invoked once per (plugin_item, local_item) pair. For a typical `CLAUDE.md` section with 5-10 items on each side, this is 25-100 invocations per section, executed during `/sync`. The cost is bounded because the prompt is small and the response is a single JSON line; the agent batches them where possible.

#### `additive-merge-with-diff` — `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml`

**Canonicalization for classification.** Same as `additive-merge`: extract owned items from plugin and local, hash the concatenation as a cheap pre-check. If equal, classify as `unchanged` and skip the rest. Otherwise classify as `additive_merge_with_diff_apply`.

**Apply step (when classification is not `unchanged`).**

1. **Run the same item-by-item merge as `additive-merge`** (steps 1-5 of the `additive-merge` algorithm above): parse plugin and local items, run the LLM-comparison helper, append plugin items that have no `same_concept` match, replace local item text when a `same_concept` match exists, preserve local-only items, collect contradictions into `pending_contradictions`.

2. **File-type-specific item parsing.** The item parser used in step 1 has rules per file type:
   - `.github/PULL_REQUEST_TEMPLATE.md` — markdown items as in `additive-merge` (list items, code blocks, paragraphs, labeled blocks). The top-level structure is H2 headings (`## Summary`, `## Changes`, `## Testing`, `## Notes for Reviewers` — verified: templates/PULL_REQUEST_TEMPLATE.md.tpl:L1-L21, relocated from `.claude-plugin/scripts/templates/` per Decision 3). The merge runs section-by-section within those headings.
   - `.github/workflows/ci.yml` — YAML structure parsing: each top-level YAML key (`name:`, `on:`, `jobs:`, `env:`) is one item. Within `jobs:`, each job key is a sub-item. The parser preserves YAML indentation and structure when emitting the merged file. Verified: templates/ci.yml.tpl:L1-L8 (relocated from `.claude-plugin/scripts/templates/` per Decision 3) — the current template has top-level keys `name`, `on`, `jobs` and a `<CI_JOBS_SECTION>` placeholder under `jobs:`; the strategy's item parser treats each top-level key as a single item and walks into `jobs:` to enumerate per-job sub-items.

3. **Pass 1 — soundness review before showing the diff (auto-apply).** Run the soundness reviewer (defined in "Soundness review" below) against the merged candidate body. Apply all suggested fixes automatically. The diff that the user sees in step 4 reflects the already-corrected result; the user never sees the pre-correction state. Zero issues → proceed directly to step 4.

4. **Render the unified diff.** Produce a standard unified diff (`(current local file body) → (merged result after Pass 1)`) with three lines of context. Enumerate hunks; each hunk gets an identifier (`hunk-1`, `hunk-2`, …) for the `Accept with exclusions` checkbox list. Each hunk's checkbox label includes the hunk's first line of changed content (truncated to 60 chars) and the heading or YAML key it falls under for orientation.

5. **Diff-review prompt.** Present the diff to the user with one AskUserQuestion offering four options:
   - **`Accept all`** — write the merged result (from Pass 1) as-is, then run Pass 2.
   - **`Accept with exclusions`** — open a multiSelect checkbox list of the enumerated hunks; each hunk starts selected. The user deselects hunks they want to revert. Recompute the final file body by reverting the deselected hunks to local content. Then run Pass 2.
   - **`Manual 3-way merge`** — write the file with git-style conflict markers (`<<<<<<< local`, `=======`, `>>>>>>> plugin`) for changed sections; unchanged sections are written cleanly. Skip Pass 2. Print an explanation: "Wrote `<path>` with git-style conflict markers for `<N>` hunks. Open the file, resolve each conflict by keeping the version you want (or composing a merge), remove the marker lines, and re-run `/sync`." Until the conflict markers are removed, the file classifies as `additive_merge_with_diff_apply` on subsequent runs.
   - **`Defer`** — no write; record as `deferred (additive-merge-with-diff)`; skip Pass 2; re-presented on the next `/sync` run.

6. **Pass 2 — soundness review after the user accepts the diff (explain-and-ask).** Applies only on the `Accept all` and `Accept with exclusions` branches. Run the soundness reviewer against the final file body composed in step 5. If issues are found, present them as a numbered list with their `description` and `suggested_fix`, then ask one AskUserQuestion:
   - **`Fix automatically`** — apply all fixes, then write.
   - **`I'll handle it`** — write the file as-is; the user fixes manually.

   Zero issues from Pass 2 → write immediately without prompting.

7. **Handle contradictions and reserialize.** If `pending_contradictions` from step 1 is non-empty, present them after the file is written (or in the same prompt batch as Pass 2 issues — implementation may interleave them). The four-option contradiction resolution menu from `additive-merge` (Adopt plugin / Keep local / Keep both / Skip for now) applies unchanged. Marker on line 2 (single-line marker, same convention as `additive-merge`). Update the marker SHA to the new canonical-form hash.

#### Soundness review (used by `additive-merge` and `additive-merge-with-diff`)

After the merge step computes a candidate file body, a **soundness reviewer** inspects the result for four classes of issues and returns a structured list. The reviewer is an LLM-driven pass — one call per file per pass — that consumes the candidate body and the file type and produces issues with suggested fixes.

**What the reviewer checks:**

1. **Ordering** — sections and items appear in a logical order for the file type. Examples: in `.github/workflows/ci.yml`, the `on:` top-level key precedes `jobs:`; in `CLAUDE.md`, `## Toolchain` precedes `## Workflow`; in markdown documents, headings follow a reasonable narrative arc rather than an interleaved jumble produced by mechanical appending.
2. **No duplicates** — no two items within the same section express the same concept. Catches the case where the LLM-comparison helper produced a false-negative `different_concept` classification and appended a near-duplicate item.
3. **Structural validity** — the file is well-formed for its type. YAML files have valid indentation and no unbalanced quote strings. Markdown files have a valid heading hierarchy (no H3 directly under H1 without an intervening H2), no unclosed code fences, no broken list nesting.
4. **Semantic coherence** — no two adjacent items make contradictory prescriptions (e.g., one bullet says "always do X" and the next says "never do X"). This is distinct from the `additive-merge` contradiction-detection step: that step compares each plugin item against each local item to detect cross-source contradictions; the soundness reviewer compares adjacent items in the *final* candidate body to detect coherence problems that emerge from the merge itself.

**Reviewer output shape.** For each issue:

```json
{
  "location": "<line-number-or-section-heading>",
  "type": "ordering | duplicate | structural | semantic",
  "description": "<one-line explanation>",
  "suggested_fix": "<concrete edit, e.g., 'move section X to before section Y' or 'remove duplicate item: \"<item text>\"'>"
}
```

An empty list means no issues found.

**Timing differs per strategy variant:**

*`additive-merge` (single auto-apply pass):* the reviewer runs once, after the merge step completes. All suggested fixes are applied automatically with no user prompt. The corrected file is written. If the reviewer returns zero issues, the file is written as-is. The user does not see the issue list or the original (pre-correction) merge output. This keeps `additive-merge` as a no-prompt strategy in the common case.

*`additive-merge-with-diff` (two passes — pre-diff auto-apply, post-accept explain-and-ask):*

- **Pass 1 — before showing the diff (auto-apply).** After the merge step completes, run the reviewer. Apply all suggested fixes automatically. The diff that the user sees in the `Accept all` / `Accept with exclusions` prompt reflects the already-corrected result, not the raw merge output. The user never sees the pre-correction state.
- **Pass 2 — after the user accepts the diff (explain-and-ask).** After the user selects `Accept all` or `Accept with exclusions` (and the final file body is composed — including the reversion of any excluded hunks), run the reviewer again. If issues are found, present them as a numbered list with their `description` and `suggested_fix`, then ask one AskUserQuestion:
  - `Fix automatically` — apply all fixes, then write the file.
  - `I'll handle it` — write the file as-is; the user fixes the remaining issues manually.

  Zero issues from Pass 2 → write immediately without prompting. The `Manual 3-way merge` and `Defer` branches of the diff prompt do not run Pass 2 (the file is either written with conflict markers, which the soundness reviewer cannot meaningfully evaluate, or not written at all).

**Best-effort, not a hard block.** The soundness reviewer is a quality gate, not a correctness gate. It can produce false positives (flagging an issue that is not real) and false negatives (missing an issue that is real). The user always has a way out: `additive-merge` users can inspect `git diff` after `/sync`; `additive-merge-with-diff` users can choose `I'll handle it` in Pass 2. A reviewer failure (network error, malformed JSON response, timeout) is treated as zero issues; the merge proceeds without the soundness pass.

**Token cost.** One LLM call per pass per file. `additive-merge` pays one call (a single auto-apply pass on a ~200-500-line file). `additive-merge-with-diff` pays two calls — one before the diff is shown, one after the user accepts. The reviewer prompt fits in a single context window for any file in the manifest (the largest `additive-merge-with-diff` file is `.github/workflows/ci.yml`, expected to stay under 500 lines for the lifetime of this RFC).

#### `bootstrap` — `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`

**Classification.** The classification matrix gets a new branch that runs *before* the existing matrix:

```
If extension_strategy == "bootstrap":
    if target_file is absent:
        classify as "bootstrap_create"
    else:
        classify as "local_only"  (regardless of marker state)
    return
```

`bootstrap_create` is surfaced in the Step 4a batch confirmation as a checkbox item labeled e.g. `Create docs/CONTRIBUTING.md from plugin template (bootstrap — this project will own it going forward)`. The label explicitly names the strategy so the user understands the long-term consequence (the plugin will not update the file in future runs). If the user confirms the item, the apply step runs; if the user deselects it, the file is not created this run and the item re-surfaces on the next `/sync`.

The `local_only` classification means: no diff is computed, no prompt is presented, the file is preserved exactly as it is. The Step 8 report lists the file under "Local-only edits (N files, plugin unchanged)" (verified: skills/sync/SKILL.md:L362).

**Apply step.**

- `bootstrap_create` outcome (confirmed in Step 4a): render the template with `project_inputs` (for `bootstrap` files with `templated: true` — none in this RFC's scope, but the strategy supports it). For `templated: false`, read the template source as-is. Prepend the **two-line bootstrap header** as lines 1-2 of the file:
  ```
  <!-- bootstrap-content-version: <upstream_key>:<sha12> -->
  <!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->
  ```
  Write the file. Track as `bootstrapped`. On all subsequent `/sync` runs the file classifies as `local_only`.
- `bootstrap_create` outcome (deselected in Step 4a): no write. Track as `deferred (bootstrap)`.
- `local_only` outcome: no write. Track as `local-only edit preserved`.

There is no `fast_forward`, `conflict`, `conflict_legacy`, `unchanged_legacy`, or `unchanged` outcome for `bootstrap` files. The strategy's classification is trimodal at first creation (create / defer / file already exists) and bimodal thereafter (the file exists and is `local_only` forever).

**Two-line header canonicalization rule.** When the diff engine canonicalizes a file produced by `bootstrap` for any future strategy compare, both header lines (lines 1 and 2) are stripped before hashing. The rule extends the existing single-marker strip at `skills/sync/SKILL.md:L336` (verified) — the canonicalizer skips every contiguous line at the top of the file that starts with `<!-- bootstrap-content-version:` or `<!-- Bootstrapped by the Bytewyrd plugin.`, plus any immediately following blank line. This generalization is described in the canonicalization-rules update in step 3 of "Exact steps" below.

#### `authoritative` — `docs/rfc-process.md`

**Classification.** Like `bootstrap`, the classification matrix gets a new branch that runs before the existing matrix:

```
If extension_strategy == "authoritative":
    plugin_content = read plugin source, strip the two-line header if present
    if target_file is absent:
        classify as "authoritative_add"
    else:
        local_content_stripped = read target, strip the two-line header if present
        if local_content_stripped == plugin_content:
            classify as "unchanged"
        else:
            classify as "authoritative_update"
    return
```

`authoritative_add` and `authoritative_update` are both surfaced in the Step 4a batch confirmation as checkbox items. The label for an `authoritative_update` item is e.g. `Update docs/rfc-process.md to plugin version <sha12> (authoritative — local edits will be replaced)`; the label for `authoritative_add` is e.g. `Add docs/rfc-process.md from plugin (authoritative — plugin owns this file)`. The label explicitly names the strategy and its consequence (local edits replaced; plugin owns the file). If the user confirms the item, the apply step runs; if the user deselects it, the file is not modified this run and the item re-surfaces on the next `/sync`.

Unlike the existing four strategies, `authoritative_update` does not enter the Step 4b conflict-resolution menu — `authoritative` has no per-line merge or "keep local" path. The batch checkbox is the only decision point.

**Apply step.**

- `authoritative_add` (confirmed in Step 4a): read the plugin source, prepend the two-line `authoritative` header as lines 1-2 of the file:
  ```
  <!-- bootstrap-content-version: <upstream_key>:<sha12> -->
  <!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->
  ```
  Write the file. Track as `added`.
- `authoritative_add` (deselected): no write. Track as `deferred (authoritative)`.
- `unchanged`: no write, not surfaced in Step 4a. Track as `unchanged`.
- `authoritative_update` (confirmed in Step 4a): read the plugin source, prepend the same two-line header, write the file (replacing any local content). Track as `authoritative update applied`.
- `authoritative_update` (deselected): no write. Track as `deferred (authoritative)`.

**Two-line header canonicalization rule.** When computing `local_content_stripped` for the classification compare, the canonicalizer strips every contiguous line at the top of the file that starts with `<!-- bootstrap-content-version:` or `<!-- Managed by the Bytewyrd plugin.`, plus any immediately following blank line. This generalization is described in the canonicalization-rules update in step 3 of "Exact steps" below. The plugin source itself does not carry the two-line header (the header is inserted on write, not stored in the upstream source).

**Migration-time check (one-time, on the first `/sync` after this RFC ships, before the Step 4a batch is rendered):** if the local file contains a `## Project Extensions` section whose body (after trimming) is anything other than the placeholder `*(no project-specific extensions — the global process applies as-is)*` or an empty body, print a one-time warning before composing the Step 4a question set:

```
docs/rfc-process.md — your '## Project Extensions' section will be removed
if you approve the upcoming batch item, because the file is now plugin-authoritative.
The content was:

  <quoted section body, indented 2 spaces, truncated to 200 chars>

If you need to keep these customizations, copy them now to another file
(e.g., docs/CONTRIBUTING.md or a new docs/rfc-process-extensions.md)
before deciding whether to approve the docs/rfc-process.md update in the
batch confirmation that follows.
```

The warning is printed inline above the Step 4a batch prompt and does not itself ask a question — the existing batch checkbox is the decision point. If the user deselects the `docs/rfc-process.md` item in the batch, the local file (including the `## Project Extensions` section) is preserved for this run, and the warning re-prints on the next `/sync` until either the item is approved or the local extensions section is removed. After the first successful apply, local content matches the plugin and the strategy classifies as `unchanged` on subsequent runs.

#### `owned-regions` — `README.md` and `docs/BEST_PRACTICES.md`

**Canonicalization for classification.** Walk `owned_boundaries`; for each boundary, extract the region of the file delimited by the boundary's rules. For the only currently-implemented boundary type (`heading`), the region is the heading line + body until the next H2/H1 or EOF. Concatenate every extracted region with `\n` separators. Hash the concatenation. This is the canonical form used by the diff engine's existing classification matrix (same semantics as the legacy `section` canonicalization at `skills/sync/SKILL.md:L338`, verified, with the boundary loop substituted for the section-heading loop).

**Apply step.** Identical in shape to the legacy `section` apply step: for each boundary in `owned_boundaries`, locate the region in the local file, replace its body with the plugin's body for the same region. Content outside boundaries is preserved exactly.

**Schema discrimination.** The manifest entry's strategy dispatch reads `owned_boundaries` first; if absent, it falls back to `owned_sections` (legacy alias) and translates each entry to a `heading`-type boundary in memory. The deprecation notice is emitted exactly once per artifact per `/sync` run when the fallback path is taken.

**`region` error path.** If the diff engine encounters `extension_strategy: "region"` in any manifest, it emits the error `no files use 'region' strategy — did you mean 'owned-regions'?` and aborts classification for that artifact. The artifact is listed in the Step 8 report under "Manifest errors" so the user knows to fix the manifest entry; other artifacts continue to classify normally.

**Pre-existing `section` entries.** For consumer projects that have not yet upgraded their manifest, the diff engine routes `extension_strategy: "section"` to the `owned-regions` apply path via the alias. Behavior is identical; only the deprecation notice is new. Existing `section` entries in `bootstrap-manifest.json` (the plugin's own manifest, relocated from `.claude-plugin/bootstrap-manifest.json` per Decision 3) for `README.md` and `docs/BEST_PRACTICES.md` are rewritten as part of this RFC's manifest changes (see "Implementation spec" below) so that the plugin itself no longer ships with the legacy strategy.

### Diff-engine integration

The five new branches plug into the existing diff engine before the current classification matrix. Pseudocode for the integrated classification function:

```
def classify(artifact, target_path, plugin_root, project_inputs):
    strategy = artifact.extension_strategy

    if strategy == "region":
        raise ManifestError(
            "no files use 'region' strategy — did you mean 'owned-regions'?")

    if strategy == "bootstrap":
        if not target_path.exists():
            return "bootstrap_create"
        return "local_only"

    if strategy == "authoritative":
        plugin_content = strip_two_line_header(read_plugin_source(artifact, plugin_root))
        if not target_path.exists():
            return "authoritative_add"
        local_content = strip_two_line_header(target_path.read_text())
        if local_content == plugin_content:
            return "unchanged"
        return "authoritative_update"

    if strategy in ("additive-merge", "additive-merge-with-diff"):
        # Cheap pre-check via canonical-form hashing
        if not target_path.exists():
            return "add"
        plugin_canonical = canonicalize_owned_items(render_template(artifact, project_inputs), artifact)
        local_canonical  = canonicalize_owned_items(target_path.read_text(), artifact)
        if sha256_12(plugin_canonical) == sha256_12(local_canonical):
            return "unchanged"
        return "additive_merge_apply" if strategy == "additive-merge" else "additive_merge_with_diff_apply"

    if strategy == "owned-regions" or (strategy == "section" and artifact.has_owned_sections):
        # 'section' is an alias for 'owned-regions' with owned_sections → heading boundaries
        boundaries = resolve_boundaries(artifact)  # reads owned_boundaries or owned_sections alias
        if strategy == "section":
            emit_deprecation_notice(artifact)  # once per artifact per /sync
        if not target_path.exists():
            return "add"
        plugin_canonical = canonicalize_boundaries(render_template(artifact, project_inputs), boundaries)
        local_canonical  = canonicalize_boundaries(target_path.read_text(), boundaries)
        if sha256_12(plugin_canonical) == sha256_12(local_canonical):
            return "unchanged"
        return classify_existing_matrix(artifact, target_path, plugin_canonical, local_canonical)

    # Existing matrix for whole and structured (and 'section' without owned_sections, which is malformed)
    return classify_existing(artifact, target_path, plugin_root, project_inputs)
```

`strip_two_line_header` removes the contiguous block of header comments at the top of the file (lines starting with `<!-- bootstrap-content-version:`, `<!-- Managed by the Bytewyrd plugin.`, or `<!-- Bootstrapped by the Bytewyrd plugin.`) plus any immediately following blank line. It is a strict superset of the existing single-marker strip used by `whole`, `section`, `region`, and `structured` strategies (verified: skills/sync/SKILL.md:L336-L340 — each existing rule says "marker line(s) removed", which already supports a multi-line block; the new function makes the rule explicit and adds the `Managed by` and `Bootstrapped by` line prefixes).

After classification, the Step 4a batch composer (see "Step 4a batch confirmation" below) gathers every classification in `{add, fast_forward, unchanged_legacy, bootstrap_create, authoritative_add, authoritative_update}` into a single AskUserQuestion before the apply step runs. The user's per-item checkbox choices are recorded on each artifact and consumed by the apply function below.

The apply function gets matching dispatch:

```
def apply(artifact, classification, batch_choice, target_path, plugin_root, project_inputs):
    # batch_choice is "approved" / "deselected" / None (None for classifications
    # that bypass Step 4a, e.g. "unchanged", "local_only", "additive_merge_apply",
    # and existing "conflict"/"conflict_legacy" which are routed through Step 4b).

    if classification == "bootstrap_create":
        if batch_choice == "deselected":
            return "deferred (bootstrap)"
        rendered = render_or_read(artifact, plugin_root, project_inputs)
        write_with_two_line_header(target_path, rendered, artifact,
                                   second_line=BOOTSTRAP_SECOND_LINE)
        return "bootstrapped"

    if classification == "local_only" and artifact.extension_strategy == "bootstrap":
        return "local-only edit preserved"

    if classification == "authoritative_add":
        if batch_choice == "deselected":
            return "deferred (authoritative)"
        rendered = render_or_read(artifact, plugin_root, project_inputs)
        write_with_two_line_header(target_path, rendered, artifact,
                                   second_line=AUTHORITATIVE_SECOND_LINE)
        return "added"

    if classification == "authoritative_update":
        if batch_choice == "deselected":
            return "deferred (authoritative)"
        if first_run_with_authoritative(artifact, target_path):
            warn_project_extensions_if_present(target_path)  # printed before Step 4a runs
        rendered = render_or_read(artifact, plugin_root, project_inputs)
        write_with_two_line_header(target_path, rendered, artifact,
                                   second_line=AUTHORITATIVE_SECOND_LINE)
        return "authoritative update applied"

    if artifact.extension_strategy == "authoritative" and classification == "unchanged":
        return "unchanged"

    if artifact.extension_strategy == "additive-merge":
        if classification == "unchanged":
            return "unchanged"
        if classification == "add":
            rendered = render_template(artifact, project_inputs)
            write_with_marker(target_path, rendered, artifact)  # single-line marker for additive-merge
            return "added"
        # classification == "additive_merge_apply"
        return apply_additive_merge(artifact, target_path, plugin_root, project_inputs)

    if artifact.extension_strategy == "additive-merge-with-diff":
        if classification == "unchanged":
            return "unchanged"
        if classification == "add":
            rendered = render_template(artifact, project_inputs)
            write_with_marker(target_path, rendered, artifact)  # single-line marker
            return "added"
        # classification == "additive_merge_with_diff_apply"
        return apply_additive_merge_with_diff(artifact, target_path, plugin_root, project_inputs)

    if artifact.extension_strategy in ("owned-regions", "section"):
        # 'section' routes here via the deprecation alias
        if classification == "unchanged":
            return "unchanged"
        # Delegates to the existing region/section apply step, parameterized by boundaries
        return apply_owned_regions(artifact, classification, target_path, plugin_root, project_inputs)

    # Existing dispatch for whole and structured
    return apply_existing(artifact, classification, target_path, plugin_root, project_inputs)
```

Constants used above:

```
BOOTSTRAP_SECOND_LINE     = "<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->"
AUTHORITATIVE_SECOND_LINE = "<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->"
```

`write_with_two_line_header` writes the file with these two lines as the first two lines (header on line 1, second-line label on line 2, then a blank line on line 3, then the body). `write_with_marker` is the existing single-line writer used by all other strategies. `apply_additive_merge` implements the section-by-section, item-by-item algorithm described above. `apply_existing` is the current Step 5 apply logic at `skills/sync/SKILL.md:L440-L456` (verified) unchanged.

### Step 4a batch confirmation — combined for additions, fast-forwards, bootstrap creations, and authoritative updates

The existing Step 4a (verified: skills/sync/SKILL.md:L380-L394) asks one AskUserQuestion containing up to two questions (additions, fast-forwards). This RFC extends it to a single AskUserQuestion with **per-file checkboxes** rather than a per-category yes/no, so the user can selectively defer individual items across the six batched classifications listed below.

The AskUserQuestion has `multiSelect: true` and groups options by category for readability. Each option corresponds to one artifact:

- **Additions** (existing): `Add <path>` (label as today)
- **Fast-forward updates** (existing): `Update <path> (fast-forward — no local edits exist)`
- **Legacy marker insertions** (existing `unchanged_legacy`): `Stamp marker on <path> (content matches; first sync after upgrade)`
- **Bootstrap creations** (new): `Create <path> from plugin template (bootstrap — this project will own it going forward)`
- **Authoritative additions** (new): `Add <path> from plugin (authoritative — plugin owns this file)`
- **Authoritative updates** (new): `Update <path> to plugin version <sha12> (authoritative — local edits will be replaced)`

The label format includes the category and its consequence so the user can decide each item with full context. Selecting an option means "apply this item this run"; deselecting means "defer it." Deferred items are tracked in the Step 8 report under a `Deferred (N items, re-presented next run)` section and re-classify on the next `/sync`.

If the AskUserQuestion's `multiSelect` mode is not used (e.g., a legacy fallback path where only a single question is in flight), the composer falls back to a per-item yes/no flow: each batched item becomes a separate AskUserQuestion with `Apply` / `Defer` options. The default flow is the multiSelect batch.

The `Review each` mode at `skills/sync/SKILL.md:L394` (verified) still exists as a per-category escape hatch for the existing `additions` / `fast_forwards` questions in projects that prefer one prompt per file with the unified diff printed; it is unchanged by this RFC and orthogonal to the per-file checkbox model added here. A future RFC may converge the two, but the existing behavior is preserved for backward compatibility.

If the union of all six batched categories is empty (i.e., every artifact classifies as `unchanged`, `local_only`, `conflict`, or `conflict_legacy`), Step 4a is skipped entirely as it is today.

### Exact steps

0. **Restructure the plugin directory layout (Decision 3).** Move files out of `.claude-plugin/` to the plugin root per the official convention, then delete the orphaned `CLAUDE.md`:

   ```bash
   # Move scripts and templates
   git mv .claude-plugin/scripts/build-manifest.sh scripts/build-manifest.sh
   git mv .claude-plugin/scripts/templates templates

   # Move hooks
   git mv .claude-plugin/hooks/hooks.json hooks/hooks.json
   git mv .claude-plugin/hooks/pre-commit/manifest-check.sh hooks/pre-commit/manifest-check.sh
   rmdir .claude-plugin/hooks/pre-commit .claude-plugin/hooks .claude-plugin/scripts

   # Move root files
   git mv .claude-plugin/bootstrap-manifest.json bootstrap-manifest.json
   git mv .claude-plugin/marketplace.json marketplace.json

   # Delete orphaned file
   git rm .claude-plugin/CLAUDE.md
   ```

   After the moves, `.claude-plugin/` contains only `plugin.json`.

   **Update `bootstrap-manifest.json` source paths.** Every `"source": ".claude-plugin/scripts/templates/FILENAME"` entry becomes `"source": "templates/FILENAME"`. The twelve affected entries are: `.bootstrap-versions.json.tpl`, `settings.json.tpl`, `settings.local.json.tpl`, `PULL_REQUEST_TEMPLATE.md.tpl`, `ci.yml.tpl`, `.gitignore.tpl`, `CLAUDE.md.tpl`, `README.md.tpl`, `ARCHITECTURE.md.tpl`, `BEST_PRACTICES.md.tpl`, `CONTRIBUTING.md.tpl`, and `mise.toml.tpl`. The `rfc-process.md` entry already uses `"source": "rfc-process.md"` (no `.claude-plugin/` prefix) and does not change.

   **Update the pre-commit hook symlink instruction.** In `docs/CONTRIBUTING.md`, change the one-time setup command for the pre-commit hook from:
   ```
   ln -sf ../../.claude-plugin/hooks/pre-commit/manifest-check.sh .git/hooks/pre-commit
   ```
   to:
   ```
   ln -sf ../../hooks/pre-commit/manifest-check.sh .git/hooks/pre-commit
   ```
   Make the same correction in `CLAUDE.md` if it references the pre-commit hook path.

   Existing contributors must re-run the updated setup command to replace their symlink. The old symlink will silently fail (target no longer exists) until re-created; the pre-commit check simply does not run until then.

1. **Edit the manifest.** Open `bootstrap-manifest.json` (relocated in step 0). Apply the nine strategy-change replacements documented under "Exact manifest changes" above (`CLAUDE.md`, `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `docs/rfc-process.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/ci.yml`, `README.md`, `docs/BEST_PRACTICES.md`, and the `.bootstrap-versions.json` relocation). After editing, the `template_sha` for `CLAUDE.md`, `README.md`, `docs/BEST_PRACTICES.md`, and `.github/workflows/ci.yml` is unchanged (no template body changes in this RFC); the `sha256` values for files without a template body are recomputed by step 5 below.

2. **Update `templates/.gitignore.tpl` (relocated from `.claude-plugin/scripts/templates/` in step 0).** Change the existing `.bytewyrd/` line (which ignores the whole folder) to `.bytewyrd/*` plus `!.bytewyrd/.bootstrap-versions.json`. Consumer projects that re-run `/sync` after this RFC ships pick up the updated template via the `structured`-strategy merge of `.gitignore` (the new lines are owned by the `bytewyrd:base` block).

3. **Remove the `## Project Extensions` section from `docs/rfc-process.md` in the bytewyrd plugin's own checkout.** Delete lines 226-232 inclusive (the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226, the blank line 227, the `---` separator on line 228, the blank line 229, the `## Project Extensions` heading on line 230, the blank line 231, and the placeholder body on line 232). Also delete lines 1-4 inclusive (the `<!-- UPSTREAM: ... -->` comment on line 1, the `<!-- LAST_SYNCED: ... -->` comment on line 2, the explanatory comment about `END_UPSTREAM_CONTENT` on line 3, and the blank line 4). After the edits, line 1 of the file is the H1 `# RFC Process` (currently at line 5). After the edit, the file is the canonical plugin RFC process content with no leader comments and no extension region.

4. **Update `skills/sync/SKILL.md`** with five new strategy branches and the sidecar-path migration. The changes are localized to:

   - **The Canonicalization rules block** (currently lines 334-340): generalize the existing "marker line(s) removed" rule to a single `strip_two_line_header` function that removes every contiguous line at the top of the file starting with `<!-- bootstrap-content-version:`, `<!-- Managed by the Bytewyrd plugin.`, or `<!-- Bootstrapped by the Bytewyrd plugin.`, plus any immediately following blank line. The new function is a superset of today's strip (which already supports "marker line(s)" — plural) and is shared by every strategy's canonicalizer. Add five new bullet points for `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, and `owned-regions`. The `bootstrap` and `authoritative` entries explicitly note "no canonical-form hash compare against plugin canonical content — strategy bypasses the canonicalization-and-hash classification matrix in favor of presence-check (bootstrap) or full-content compare after header strip (authoritative)."
   - **The Classification matrix block** (currently lines 323-332): add a preamble paragraph that documents the strategy-first dispatch: "Before applying the matrix below, dispatch to the strategy-specific classifier when `extension_strategy` is `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, or `owned-regions`. Emit an error if `extension_strategy` is `region`. Emit a deprecation notice and translate to `owned-regions` if `extension_strategy` is `section` and `owned_sections` is present. The matrix below applies only to `whole` and `structured`."
   - **The Step 4a batch-confirmation block** (currently lines 380-394): replace the two-question yes/no pattern with the single-question multiSelect pattern described in "Step 4a batch confirmation" above. The new question's options come from the union of additions, fast-forwards, legacy-marker insertions, bootstrap creations, authoritative additions, and authoritative updates — one option per artifact, with the label format that names the category and consequence. Preserve the existing `Review each` mode as a per-category escape hatch.
   - **The Step 4b resolution menu** (currently lines 396-423): add a new variant for `additive-merge`'s contradiction case (the four-option menu described in the `additive-merge` algorithm above). `authoritative` and `bootstrap` files never enter Step 4b — their decision is the Step 4a checkbox. Add the `additive-merge-with-diff` diff-review prompt (`Accept all` / `Accept with exclusions` / `Manual 3-way merge` / `Defer`) and the soundness-review Pass 2 explain-and-ask prompt (`Fix automatically` / `I'll handle it`).
   - **The Apply actions block** (currently lines 440-456): add five new top-level cases for `additive-merge`, `additive-merge-with-diff`, `bootstrap`, `authoritative`, and `owned-regions`, each documenting their apply step. The `additive-merge` case references the item-by-item algorithm and the single-pass soundness review; the `additive-merge-with-diff` case adds the diff-review prompt and the two-pass soundness review; the `bootstrap` and `authoritative` cases describe the two-line header write (using the `BOOTSTRAP_SECOND_LINE` and `AUTHORITATIVE_SECOND_LINE` constants defined in "Diff-engine integration" above) and the deferred-item bookkeeping for deselected batch items; the `owned-regions` case reuses the existing `section`-apply logic, parameterized by `owned_boundaries`.
   - **Sidecar-path migration in Step 3** (currently SKILL.md L295, L309): replace `.claude/.bootstrap-versions.json` with `.bytewyrd/.bootstrap-versions.json`. Add a migration check at the top of Step 3: if `.claude/.bootstrap-versions.json` exists and `.bytewyrd/.bootstrap-versions.json` does not, copy the contents to the new path and delete the old file. Log the migration in the Step 8 report (`Migrated .bootstrap-versions.json: .claude/ → .bytewyrd/`). Update the per-file references at SKILL.md L557 (sidecar manifest entry description) and L698 (sidecar rewrite step) to the new path.

5. **Regenerate the manifest.** Run `scripts/build-manifest.sh` from the repo root (relocated from `.claude-plugin/scripts/` in step 0; verified: build-manifest.sh:L1-L55 walks the manifest and recomputes `sha256`/`template_sha` for each artifact's source file). Expected stdout: `Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/bootstrap-manifest.json`. Expected exit code: `0`.

6. **Verify the manifest passes the pre-commit check.** Run `scripts/build-manifest.sh --check` (relocated from `.claude-plugin/scripts/` in step 0; verified: build-manifest.sh:L45-L51 exits non-zero if regenerated output differs from the committed manifest). Expected exit code: `0`. If non-zero, re-run step 5.

7. **Run `/sync` in a consumer project (smoke test).** From a consumer project (the bytewyrd plugin's own worktree at `/home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/` is a valid consumer for testing), invoke `/sync`. Expected classification per file on the first run after this RFC ships:

   - `CLAUDE.md` → **additive_merge_apply** (or **unchanged** if every plugin-owned item already has a `same_concept` match in local). On the bytewyrd plugin's own checkout, the file has all ten plugin-owned sections present with bodies that match the template's items conceptually — verified by inspection of CLAUDE.md vs CLAUDE.md.tpl in this RFC's session. Outcome: `additive_merge_apply` with all items resolved as `same_concept` (no contradictions), local wording potentially replaced where plugin and local differ. The single auto-apply soundness-review pass runs after the merge and applies any fixes silently. Single-line marker stamped on completion.
   - `docs/CONTRIBUTING.md` → **local_only** — the file exists; `bootstrap` short-circuits to `local_only`. No prompt, no diff, no write.
   - `docs/ARCHITECTURE.md` → **local_only** — same.
   - `docs/rfc-process.md` → **authoritative_update** on first run (local content has leader comments and `## Project Extensions` section, plugin content does not, so they differ after stripping the two-line header). The migration-time warning is printed inline above the Step 4a batch prompt (the local `## Project Extensions` body in this worktree is the placeholder, so the warning's "non-placeholder content" branch does not fire for this specific run — but the migration-check code is exercised). The Step 4a batch prompt renders with one item: `Update docs/rfc-process.md to plugin version <sha12> (authoritative — local edits will be replaced)`. The user approves it; the file is overwritten with the plugin's canonical content and the two-line `authoritative` header is stamped. On the very next run, classification is **unchanged** and no further interaction.
   - `.github/PULL_REQUEST_TEMPLATE.md` → **additive_merge_with_diff_apply** if the plugin and local differ; **unchanged** otherwise. On `additive_merge_with_diff_apply`, the merge step computes the candidate file, Pass 1 auto-applies any soundness fixes, the unified diff is rendered for the user, and the user chooses one of `Accept all` / `Accept with exclusions` / `Manual 3-way merge` / `Defer`. On `Accept all` / `Accept with exclusions`, Pass 2 runs against the final body; if the reviewer finds no issues the file is written immediately. Single-line marker stamped on completion.
   - `.github/workflows/ci.yml` → **additive_merge_with_diff_apply** (same flow as `PULL_REQUEST_TEMPLATE.md` above; the YAML item parser walks top-level keys and per-job sub-items).
   - `README.md` → **unchanged** if local matches plugin canonical content for every `owned_boundaries` entry; otherwise classified by the existing classification matrix (now reached via the `owned-regions` path, with the alias deprecation notice fired once if any consumer manifest still uses `extension_strategy: "section"`). On the bytewyrd plugin's own checkout the manifest is upgraded as part of this RFC's step 1, so the alias path is not exercised by the smoke test — but a consumer-project test (a project that has not yet upgraded its manifest) would exercise it.
   - `docs/BEST_PRACTICES.md` → same as `README.md` — `owned-regions` apply via the upgraded manifest; alias path exercised by un-upgraded consumer projects.
   - `.bytewyrd/.bootstrap-versions.json` → first run after this RFC ships, the migration check at the top of Step 3 finds the old sidecar at `.claude/.bootstrap-versions.json`, copies the contents to the new path, and deletes the old file. The migration is logged in Step 8 (`Migrated .bootstrap-versions.json: .claude/ → .bytewyrd/`). After the migration, the new path's content matches the plugin's expectation for the `structured`-strategy sidecar, and the file classifies as **unchanged** on subsequent runs.

   The Step 4a batch prompt fires for `docs/rfc-process.md` (one `authoritative_update` item) on the first post-RFC run, and `CLAUDE.md` enters Step 4a only if it has new `additive-merge` *additions* (plugin items that need to be appended — this is the `add`-shaped sub-case of `additive_merge_apply`). On the bytewyrd plugin's own checkout there are zero such additions today, so `CLAUDE.md` does not enter Step 4a. The Step 4b conflict prompt fires only for `additive-merge` items in `contradiction` state, of which there are zero in the bytewyrd plugin's own checkout (verified by item-by-item inspection of CLAUDE.md vs CLAUDE.md.tpl during this RFC's session — every plugin item has a same-concept match in local). The diff-review prompt for `additive-merge-with-diff` fires for `PULL_REQUEST_TEMPLATE.md` and `ci.yml` if and only if local and plugin canonical hashes differ; on a fresh checkout where the local files match the plugin templates byte-for-byte (modulo header), the cheap pre-check short-circuits to `unchanged` and the prompt does not fire.

8. **Verify the headers were written.** After `/sync`:

   ```bash
   sed -n '1,2p' CLAUDE.md docs/rfc-process.md
   ls -la docs/CONTRIBUTING.md docs/ARCHITECTURE.md  # files exist, not touched by /sync
   ```

   Expected:
   - `CLAUDE.md` line 1 is the first line of body (no leading marker on this strategy unless the marker convention has changed for `additive-merge`); line 2 is `<!-- bootstrap-content-version: ... -->` (single-line marker per the existing `section`/`additive-merge` convention at `skills/sync/SKILL.md:L434`, verified).
   - `docs/rfc-process.md` lines 1-2 are the two-line `authoritative` header: `<!-- bootstrap-content-version: ... -->` on line 1, `<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->` on line 2.
   - `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` are unmodified by this `/sync` (these are `local_only` — no header is injected because the strategy classified them as already-owned-by-project; the two-line `bootstrap` header is only written on the initial `bootstrap_create` apply, which does not fire on this run because the files already exist).

9. **Run `/sync` again (idempotence check).** Invoke `/sync` a second time. Expected stdout: `Everything is up to date.` (per `skills/sync/SKILL.md:L367`, verified) — every file classifies as `unchanged` or `local_only`. No prompts, no resolutions, no per-file output.

### Verification commands

After step 9 succeeds, every plugin-managed file is out of the `conflict_legacy` loop permanently:

- `CLAUDE.md` carries a single-line `<!-- bootstrap-content-version: ... -->` marker on line 2 (as today). Subsequent plugin updates re-run the `additive-merge` algorithm: same-concept matches silently update local wording, new plugin items are appended (and surface as `add`-shaped items in Step 4a for confirmation), local-only items are preserved, contradictions prompt explicitly in Step 4b. The single auto-apply soundness-review pass runs on every `additive_merge_apply` write.
- `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml` carry a single-line `<!-- bootstrap-content-version: ... -->` marker after the first `additive-merge-with-diff` apply. Subsequent plugin updates re-run the same algorithm: merge in memory, Pass 1 soundness review auto-applies fixes, render the unified diff, user picks `Accept all` / `Accept with exclusions` / `Manual 3-way merge` / `Defer`; on the two accept paths, Pass 2 soundness review prompts the user only if issues are detected.
- `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` carry the two-line `bootstrap` header only if they were created by this RFC's `/sync` flow. Existing files (the common case on first run after this RFC ships) are not modified and do not gain the header — they are classified as `local_only` from this point forward, and the plugin can update the template body in future versions without the change flowing to existing projects (by design).
- `docs/rfc-process.md` carries the two-line `authoritative` header on lines 1-2 after the first approved update. Subsequent plugin updates appear as `authoritative_update` items in Step 4a; approving the item overwrites local content with the plugin version; deselecting the item defers the update to the next run.
- `README.md` and `docs/BEST_PRACTICES.md` continue to carry a single-line `<!-- bootstrap-content-version: ... -->` marker (as they do today under `section` strategy). The behavior of plugin updates is unchanged from before this RFC — the strategy switch from `section` to `owned-regions` is a consolidation, not a semantic change. The deprecation notice fires once per `/sync` until the consumer project re-runs `/sync` against an upgraded manifest.
- `.bytewyrd/.bootstrap-versions.json` is the sole new sidecar location. The old path (`.claude/.bootstrap-versions.json`) is removed by the one-time migration check on the first `/sync` after this RFC ships. The file is `structured` strategy with `owned_paths: ["*"]` — every key is a plugin-managed marker SHA, and the diff engine maintains the file as a whole on every run that updates any artifact's marker.

The `conflict_legacy` cycle for these files is terminated. The only per-run interactions that can still arise are: (a) an `additive-merge` contradiction on `CLAUDE.md` (Step 4b), which is bounded by genuine semantic opposition between project and plugin rules; (b) an `additive-merge` plugin-item addition on `CLAUDE.md` (Step 4a checkbox), which is bounded by the rate at which the plugin ships new items; (c) the one-time migration warning on `docs/rfc-process.md` for projects with non-empty `## Project Extensions` content; (d) every plugin-version update to `docs/rfc-process.md` surfaces as one Step 4a checkbox; (e) every plugin-version update to `.github/PULL_REQUEST_TEMPLATE.md` or `.github/workflows/ci.yml` that produces a non-trivial diff surfaces as one diff-review prompt with the four-option menu; (f) the soundness-review Pass 2 prompt fires for `additive-merge-with-diff` files only when the reviewer detects issues in the final body.

## Risks and open questions

1. **`additive-merge`'s LLM helper produces false-positive `same_concept` matches and silently overwrites local wording.** The helper is asked, item by item, to classify the relationship between a plugin item and a local item. A confidently-wrong "same_concept" classification leads to the local item's wording being replaced by the plugin's. The user has no visibility into individual replacements unless they read the resulting git diff.

   **Mitigation:** the Step 8 report lists each section where any item was modified, along with a count of `same_concept` replacements applied. The user can run `git diff CLAUDE.md` after `/sync` to inspect every replacement and revert any they disagree with via `git checkout -- CLAUDE.md` or selective edits. The confidence threshold (≥ 0.5) and the helper's prompt design (returning a discrete relationship label rather than a free-form judgment) reduce the false-positive rate but do not eliminate it. The recoverability via git history is the safety net: every replacement is in a single commit that can be selectively reverted.

2. **`additive-merge`'s LLM helper produces false-negative `different_concept` matches and creates duplicate items.** The helper fails to recognize that two items express the same concept, so the plugin item is appended even though local already has a (different-wording) version of it. The result is two items in the section that say nearly the same thing — clutter, not a wrong rule.

   **Mitigation:** the duplication is cosmetic, not destructive. The user can deduplicate in their next edit pass. The Step 8 report's per-section change summary makes the appended items visible. Over time, the user's deduplication edits should converge the local file toward wording that matches the plugin's exactly (which the helper then classifies confidently as `same_concept`), reducing the false-negative rate organically.

3. **`bootstrap` files diverge from the plugin's template over time with no automated recovery.** A project that adopted `docs/ARCHITECTURE.md` early gets a v1 template body. The plugin maintainer improves the template (better scope comment, additional guidance) for v2. Existing projects do not pick up the improvement — `bootstrap` short-circuits to `local_only` regardless of plugin version. The maintainer has no `/sync`-driven path to push improvements.

   **Mitigation (out of scope of this RFC, documented as an open question):** a future RFC may introduce a "re-bootstrap" command (e.g., `/sync --rebootstrap docs/ARCHITECTURE.md`) that explicitly opts the user into overwriting a `bootstrap` file with the plugin's current template, with a backup of the existing content (written to `docs/ARCHITECTURE.md.local-backup`) before the overwrite. This is a deliberate manual escape hatch, not an automated update — it inverts the strategy temporarily for one file, prompting the user explicitly. Out of scope here because no consumer project currently needs it.

4. **`authoritative` dropping local customizations after a single batch confirmation is a new failure mode for projects that previously used `## Project Extensions`.** Today, the local copy of `docs/rfc-process.md` has a `## Project Extensions` section that the diff engine preserves (because `region` strategy stops at `<!-- END_UPSTREAM_CONTENT -->`). After this RFC, that section is removed on the first `/sync` whose batch confirmation the user approves, and any future local edits to the file are replaced on the next approved batch confirmation. The user does see and approve each replacement (it is a Step 4a checkbox), but the strategy provides no per-line conflict resolution path — the choice per run is "approve the overwrite" or "defer."

   **Mitigation:** the migration-time check described in the implementation spec fires exactly once on the first `/sync` after this RFC ships. If the local `## Project Extensions` section has non-placeholder content, the warning is printed inline above the Step 4a batch prompt with the section's content quoted and instructions to copy the content elsewhere before deciding how to vote on the rfc-process.md checkbox. The user can defer the rfc-process.md item (deselect its checkbox) to preserve the local file for now; the warning re-prints on every subsequent `/sync` until either the item is approved or the local extensions section is removed. After the migration, future plugin-version updates to `docs/rfc-process.md` continue to surface as Step 4a checkboxes — this is the strategy's defining property and is documented on line 2 of the file itself (the `Managed by the Bytewyrd plugin` header), in `docs/CONTRIBUTING.md` for the plugin, and in release notes (per the drawback above).

5. **Per-`/sync` token cost for `additive-merge`'s LLM helper.** The helper invokes the agent's underlying model once per (plugin_item, local_item) pair, per section. For `CLAUDE.md` with ten sections averaging seven items per side, that's up to 490 invocations per `/sync` run. With short prompts and short responses, each invocation is a few hundred tokens; the total token spend is bounded but non-zero on every run that classifies `CLAUDE.md` as `additive_merge_apply`.

   **Mitigation:** the cheap pre-check (canonical-form hash equality between plugin and local) short-circuits to `unchanged` whenever the file has not drifted, eliminating all helper invocations for the common case. The cost is paid only when the plugin's template has changed *or* the local file has been edited since the last `/sync`. The agent batches helper invocations across pairs in a single section to amortize prompt overhead.

6. **The diff engine's Step 4b resolution menu gains a new variant for `additive-merge` contradictions.** The existing four-option menu (Adopt / Keep / Merge / Skip) plus the fifth `Adopt plugin and add marker` option (verified: skills/sync/SKILL.md:L408-L415) is now joined by an item-level menu for `additive-merge` contradictions. The two menus have different option sets and different scopes (file-level vs item-level), so they are presented separately. Maintaining two menus in the same step is a documentation burden — the `skills/sync/SKILL.md` body must clearly disambiguate which menu applies when.

   **Mitigation:** the integrated skill body in step 3 of "Exact steps" above explicitly differentiates the two menus in the Step 4b documentation. The implementation can also factor the option-rendering into two named helpers (`render_file_conflict_menu` and `render_item_contradiction_menu`) so the call sites are unambiguous in code. This is a small refactor, not a structural change.

7. **The manifest pre-commit hook does not validate strategy-specific fields.** `build-manifest.sh --check` (verified: .claude-plugin/scripts/build-manifest.sh:L45-L51; relocated to `scripts/build-manifest.sh` per Decision 3) verifies that recorded SHAs match source files. It does not check that `additive-merge` entries have `owned_sections`, that `bootstrap` entries omit `owned_sections`/`owned_paths`/`region_end_marker`, or that `authoritative` entries omit `region_end_marker`. A maintainer who edits the manifest by hand and forgets to remove an obsolete field will see no error.

   **Mitigation:** extending the pre-commit check to validate per-strategy field requirements is a small follow-up (out of scope here). The first symptom of a malformed manifest is a runtime error during `/sync` classification dispatch, which is loud and immediate; the manifest is a small file and the strategy fields are easy to inspect manually.

8. **The `Manual 3-way merge` option's git-style conflict markers may confuse users unfamiliar with that format.** The `<<<<<<< local`, `=======`, `>>>>>>> plugin` syntax is standard for anyone who has resolved a git merge conflict, but the sync skill is also used by people who have not. A user who picks `Manual 3-way merge` without recognizing the format may save the file with the markers still embedded, breaking the file (YAML parse failure for `ci.yml`; rendered conflict-marker text in the PR template).

   **Mitigation:** before writing the file in conflict-marker mode, the sync skill prints a short, fixed explanation that names the format ("git-style conflict markers"), describes the marker syntax (`<<<<<<< local` / `=======` / `>>>>>>> plugin`), and lists the resolution steps (open the file, keep one side or compose a merge, remove the marker lines, re-run `/sync`). The next `/sync` run after the user resolves the markers re-classifies the file and the prompt re-surfaces if any markers were left in place — the file does not silently land in a broken state.

9. **`additive-merge-with-diff`'s `Accept with exclusions` creates partial merges that can be subtly inconsistent.** When a user excludes a hunk, that hunk reverts to local content while the surrounding accepted hunks land as plugin content. If the accepted hunks depend on a definition or value that lived in the excluded hunk (a YAML anchor reference, a markdown link target, a job name), the resulting file may be syntactically valid but semantically incoherent — e.g., a CI job that references a step name that only existed in the plugin's version of the now-excluded hunk.

   **Mitigation:** the soundness review's Pass 2 (which runs after the user accepts the diff) catches most ordering and coherence issues this creates — the reviewer's "semantic coherence" check explicitly looks for adjacent items that contradict each other, and its "structural validity" check catches references to undefined names in YAML. Issues are presented to the user with suggested fixes before the file is written. The mitigation is not perfect — the reviewer is best-effort — but it converts the "silently broken file" failure mode into a "user is warned and asked" failure mode.

10. **Soundness review false positives block or clutter the merge.** The reviewer can flag an issue that is not real — a "duplicate" that is intentional (e.g., two CI jobs that do the same check on different OS targets), an "ordering" violation that is actually meaningful (a deliberate ordering the project prefers), or a "semantic coherence" warning that misreads the intent of two adjacent items.

    **Mitigation:** three properties keep false positives bounded. (a) In `additive-merge-with-diff` Pass 2, the user can always choose `I'll handle it`, which writes the file as-is and skips the auto-fix step — false positives never produce a broken file. (b) The reviewer runs once per pass on the final file body, not per item, so a false positive is one extra line in the issue list rather than a per-item interruption. (c) Issues are presented with `suggested_fix` text and clear `description` text, not as hard errors — the user can read the suggestion, judge it, and reject it. In `additive-merge`, false positives are silently auto-applied, so the safety net is git: the user can inspect `git diff` after `/sync` and revert any auto-applied fix they disagree with.

11. **`owned-regions`'s `section` deprecation alias adds maintenance burden until all consumer projects upgrade.** The alias must remain recognized in the diff engine until every consumer project's manifest has been rewritten. While that backlog exists, every `/sync` run on a consumer project must execute the alias-translation path, emit the deprecation notice, and consume the legacy `owned_sections` field. The longer the deprecation period, the longer that code path lingers.

    **Mitigation:** the deprecation notice in the Step 8 report names the file with the legacy strategy and tells the user to re-run `/sync` to upgrade, so the path to clearing the notice is discoverable. The alias-translation code is small (one for-loop that wraps strings in `{ "type": "heading", "heading": s }` objects) and self-contained — there is no shared state between the alias path and the modern path. `region` needs no backward-compat at all (zero users), so the deprecation burden is bounded to `section` alone.

12. **`.bootstrap-versions.json` relocation leaves an orphaned file at the old path.** Existing consumer projects have the sidecar at `.claude/.bootstrap-versions.json`. After this RFC ships, the manifest declares the target at `.bytewyrd/.bootstrap-versions.json` and the `upstream_key` bumps to `@v2` (path changed, requires re-sync). The diff engine treats the new path as a fresh artifact — it does not know that the old path's content is the same sidecar data.

    **Mitigation:** the sync skill's Step 3 (post-manifest-load, pre-classification) performs a one-time migration check: if `.claude/.bootstrap-versions.json` exists and `.bytewyrd/.bootstrap-versions.json` does not, the skill copies the contents to the new path and deletes the old file. The migration is logged in the Step 8 report ("Migrated .bootstrap-versions.json: `.claude/` → `.bytewyrd/`") and is idempotent — on every subsequent run, the old path is absent and the migration is a no-op.

13. **Plugin directory restructuring breaks the git pre-commit hook symlink for existing contributors.** The symlink at `.git/hooks/pre-commit` on each contributor's machine currently resolves to `../../.claude-plugin/hooks/pre-commit/manifest-check.sh`. After the directory moves in step 0, that path no longer exists. The symlink becomes dangling and the pre-commit check silently stops running — contributors can commit without the manifest freshness check until they re-create the symlink.

    **Mitigation:** update the one-time setup command in `docs/CONTRIBUTING.md` and `CLAUDE.md` to reference the new path (`../../hooks/pre-commit/manifest-check.sh`) as part of step 0 of the implementation. Include a note in the PR description (or a changelog entry) calling out that existing contributors must re-run the one-time setup command to update their local symlink. The failure mode is silent (no error at commit time — the check simply does not run), so the call-out must be explicit; contributors who miss it will have a passing pre-commit step that does nothing until they update.

## Relationship to other RFCs

This RFC builds on the per-file marker infrastructure introduced by `2026-05-10-sync-interactive-diff` (Done) and does not depend on or block any other RFC. It supersedes any prior assumption (including in this RFC's earlier draft) that the fix for the `conflict_legacy` loop would be a narrowing of `CLAUDE.md`'s `owned_sections` and a migration to `section`/`region` strategies for `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`. That approach is dropped entirely in favor of the five-strategy model described here.
