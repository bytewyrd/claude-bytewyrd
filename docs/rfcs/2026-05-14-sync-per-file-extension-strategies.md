---
rfc: "2026-05-14-sync-per-file-extension-strategies"
title: "Sync Per-File Extension Strategies"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-14"
drop_reason: ~
---

## Summary

Introduce three named extension strategies — `additive-merge`, `bootstrap`, and `authoritative` — and assign each of the four currently-stuck plugin-managed files to the strategy that matches how the plugin actually relates to that file's content. `CLAUDE.md` becomes `additive-merge`: the plugin is the authoritative source for every concept it ships, but it adds new items rather than replacing the file. `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` become `bootstrap`: the plugin writes a starter template once, and from that point forward the file is local-owned and the plugin never touches it again. `docs/rfc-process.md` becomes `authoritative`: the plugin's content is always the file's content, presented in the same Step 4a batch confirmation as additions and fast-forwards, and there is no local extensions section. The three new strategies are **additions** to the existing four (`whole`, `section`, `region`, `structured`) — the existing strategies continue to govern every other file in the manifest. After the change, the `conflict_legacy` loop (the "Keep local version" action explicitly does not stamp the marker — verified: skills/sync/SKILL.md:L420) terminates for all four files: the next `/sync` either classifies each file as `unchanged` (it already matches plugin canonical content) or applies the strategy's deterministic decision after one batched confirmation. The three strategies replace the file-level conflation that today routes substantively different ownership models through the same `whole`/`section`/`region`/`structured` matrix for these four files only.

## Should we do this?

**Yes.** The current behavior is a hard regression for every consumer project that has run `/sync` after the per-file marker system shipped. Each of the four files re-surfaces as `conflict_legacy` on every subsequent `/sync` run regardless of whether the user has touched the file since (verified: skills/sync/SKILL.md:L323-L332 — the classification matrix routes any file lacking a `<!-- bootstrap-content-version: ... -->` marker to either `unchanged_legacy` or `conflict_legacy` depending on whether canonical content matches). The only escape paths today are "Adopt plugin version" (which overwrites real local content with the plugin's stub) or "Keep local version" (which does not stamp the marker, so the same prompt re-surfaces on the next run — the action description at `skills/sync/SKILL.md:L420` says this explicitly: "no write; marker not updated; conflict re-surfaces on next run"). The loop is structural: the manifest declares ownership semantics that do not match how the plugin actually relates to the file's content, so the diff engine's classification matrix produces a wrong answer every time. The fix is to make the manifest describe the actual relationships — three different relationships, three named strategies, one per file (or pair of files). All three strategies fold their decisions into the existing Step 4a batch confirmation rather than firing a separate per-file conflict prompt every run — `bootstrap` shows a one-time "create this file?" checkbox, `authoritative` shows an "update this file?" checkbox per plugin-version update, and `additive-merge` only fires the legacy-style conflict menu in Step 4b when an item-level semantic contradiction is detected. This collapses an unbounded series of per-run conflict prompts into a single batched approval per `/sync`.

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

### Strategy coexistence — new strategies are additive

The three new strategies (`additive-merge`, `bootstrap`, `authoritative`) are **additions** to the existing four (`whole`, `section`, `region`, `structured`), not replacements. Only the four files this RFC reclassifies move off their existing strategy values; every other file in `.claude-plugin/bootstrap-manifest.json` continues to use its current strategy. After this RFC ships, the diff engine supports seven strategies total, distributed across the manifest as follows (each row verified against `.claude-plugin/bootstrap-manifest.json`):

- **`whole`** — `.claude/.bootstrap-versions.json` (verified: .claude-plugin/bootstrap-manifest.json:L8), `.github/PULL_REQUEST_TEMPLATE.md` (verified: .claude-plugin/bootstrap-manifest.json:L53), `.github/workflows/ci.yml` (verified: .claude-plugin/bootstrap-manifest.json:L61). (`docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` move off `whole` to `bootstrap` per this RFC.)
- **`section`** — `README.md` (verified: .claude-plugin/bootstrap-manifest.json:L112) and `docs/BEST_PRACTICES.md` (verified: .claude-plugin/bootstrap-manifest.json:L139). (`CLAUDE.md` moves off `section` to `additive-merge` per this RFC.)
- **`region`** — no files after this RFC ships. `docs/rfc-process.md` is the only current user (verified: .claude-plugin/bootstrap-manifest.json:L184) and it moves to `authoritative`. The `region` strategy stays in the schema and the diff engine: removing it would be a breaking change for consumer projects that have manifest entries referencing it, and a future plugin file or a consumer-defined artifact may legitimately want regional ownership. Keeping it costs nothing — its code path is independent of the new strategies.
- **`structured`** — `.claude/settings.json` (verified: .claude-plugin/bootstrap-manifest.json:L16), `.claude/settings.local.json` (verified: .claude-plugin/bootstrap-manifest.json:L39), `.gitignore` (verified: .claude-plugin/bootstrap-manifest.json:L73), `mise.toml` (verified: .claude-plugin/bootstrap-manifest.json:L193).
- **`additive-merge`** (new) — `CLAUDE.md` only (per this RFC).
- **`bootstrap`** (new) — `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md` (per this RFC).
- **`authoritative`** (new) — `docs/rfc-process.md` (per this RFC).

The strategy-first dispatch in the integrated classifier (described in "Diff-engine integration" below) routes each artifact to its strategy's code path. The four canonicalization-based strategies share the existing classification matrix at `skills/sync/SKILL.md:L323-L332` (verified); the three new strategies short-circuit it. No artifact uses more than one strategy, and no strategy depends on another.

### Decision 1 — New strategies vs. acknowledgment path

**Option A — Introduce three new extension strategies (`additive-merge`, `bootstrap`, `authoritative`) and assign each affected file to the strategy that matches its actual relationship to the plugin (recommended).**

For each file, the manifest declares a strategy whose semantics directly describe the relationship: "the plugin contributes items here and merges them additively," "the plugin writes a starter template once and never touches the file again," or "the plugin is the source of truth and always wins." The diff engine implements the three strategies' classification and apply logic; the user sees no `conflict_legacy` prompt for these files unless a strategy explicitly produces a conflict (which only `additive-merge` can do, and only when local and plugin items semantically contradict). All three strategies route their decisions into the existing Step 4a batch confirmation — `bootstrap` shows a one-time "create this file?" checkbox, `authoritative` shows an "update this file?" checkbox per plugin-version update that changes the file, and `additive-merge` enters Step 4a only when there are plugin items to append. None of the three strategies produces a separate per-file conflict prompt outside that batch.

This option requires three new strategy values, three new classification-and-apply code paths in the diff engine, and the manifest schema accepting new values for `extension_strategy`. It does not add new resolution options to the existing Step 4b conflict menu — `bootstrap` and `authoritative` never enter Step 4b, and `additive-merge` only enters Step 4b when an item-level contradiction is detected (using a new four-option menu described in the algorithm section). The Step 4a batch confirmation gains additional per-file checkbox categories (one for `bootstrap` creations, one for `authoritative` adds, one for `authoritative` updates) alongside the existing additions and fast-forwards.

**Option B — Keep the existing four strategies and add a fifth resolution option, "Keep local and mark acknowledged," that stamps the marker without modifying content.**

A new option on the Step 4b menu for `conflict_legacy` files: pick "Keep local and mark acknowledged" and the diff engine writes a `<!-- bootstrap-content-version: <upstream_key>:<local_current_canonical_sha> -->` marker into the local file without modifying any body content. The marker's SHA is the hash of the local canonical content, so the next `/sync` reads the marker, hashes the (unchanged) local content, and classifies as `local_only` — no prompt.

This works mechanically but has three structural problems:

1. **It papers over a semantic mismatch rather than fixing it.** The manifest is supposed to describe how the plugin relates to a file. If the plugin's relationship to `docs/ARCHITECTURE.md` is "write once and never touch again," the manifest should say so — not declare `whole` ownership and then offer an opt-out that lets the diff engine ignore the lie.
2. **The acknowledgment is one-shot.** Every future plugin update to the file will land a new template SHA and re-trigger the classification, because the marker recorded the *local* SHA rather than the plugin's SHA. The user will be re-prompted on every plugin update, with the same useless choice each time.
3. **It conflates relationships.** A file resolved by "Adopt plugin and add marker" and a file resolved by "Keep local and mark acknowledged" both end up with a bootstrap-content-version marker present. The diff engine reads only the marker, not the resolution path that produced it. If the plugin updates the file later, the diff engine has no way to know whether the user merged the previous plugin version into local content or ignored it. That uncertainty bleeds into every subsequent prompt.

**Recommendation: Option A.** The three relationships are real — `additive-merge`, `bootstrap`, and `authoritative` describe what the plugin and the project actually do with each file. Encoding them as named strategies makes the manifest the precise source of truth and removes per-run prompts for two of the three. Option B's acknowledgment path is genuinely useful for files where no strategy fits, but adding it without first naming the strategies leaves the architecture incoherent: the manifest would still misdescribe the file's relationship, and the acknowledgment option would be a workaround for the misdescription rather than a way to handle a genuinely exceptional case.

**Door stays open on Option B.** Nothing in Option A precludes adding the acknowledgment option later as a fallback. The two options operate at different layers (strategy declaration vs. resolution-time interaction) and a future RFC can add it if a file emerges that needs ownership semantics none of the three strategies covers.

### Decision 2 — Strategy assignment per file

The three strategies in detail (each defined first, then assigned to files):

#### Strategy 1: `additive-merge` — for `CLAUDE.md`

**Definition.** The plugin is the authoritative source for every concept it expresses, but the file is structurally an open list that the project may extend. The plugin's contribution and the local file's contribution are merged item-by-item rather than canonical-form-vs-canonical-form. Merge semantics:

- **Plugin item not in local file** → add it to local (the plugin is shipping a new concept; the project gets it)
- **Local item not in plugin manifest** → preserve it (the local file is adding a novel concept the plugin doesn't ship)
- **Same concept appears in both with different wording** → plugin wording wins (the plugin is authoritative for the concepts it ships; the local wording is replaced)
- **Local item explicitly contradicts a plugin item** → flag as conflict for human resolution

"Same concept, different wording" and "explicit contradiction" require semantic comparison, not byte equality. Two strings expressing the same rule (e.g., "Default to `haiku` unless the task clearly requires more" and "Prefer the cheapest model unless complexity demands more") are conceptually identical. Detection is by LLM-assisted matching: during `/sync`'s execution the agent prompts itself, item-by-item, to classify each (plugin-item, local-item) pair as "same concept", "different concepts", or "explicit contradiction." Contradiction = the local item negates, prohibits, or sets an opposing prescription to a plugin item (for example, local says "never do X" when the plugin says "do X"). This is feasible because `/sync` is an agent-driven skill — its body is markdown executed by an agent (verified: skills/sync/SKILL.md:L1-L4 declares the skill name and description; the body that follows is a sequence of natural-language steps including `AskUserQuestion` calls at e.g. skills/sync/SKILL.md:L146, not a script), so LLM-mediated comparison is a natural fit rather than an architectural mismatch.

**`owned_sections` stays at the full list of sections the plugin ships.** The plugin does not narrow what it claims to own — that's what `bootstrap` is for. `additive-merge` says "I own every concept I express, but I express them as additive items, not as a full-section overwrite." The owned-sections list for `CLAUDE.md` is therefore the same ten headings the manifest declares today (verified: .claude-plugin/bootstrap-manifest.json:L85-L96), and the merge operates within each section's body items.

**Why `CLAUDE.md` fits.** The plugin contributes a stable, growing corpus of conventions — Tool Usage rules, Evidence-Based Development principles, Model Usage Optimization rules, Sandbox compatibility guidance, Security rules, RFC Process pointers, etc. Projects extend these (the bytewyrd plugin's own checkout has a full `## Workflow` section with project-specific session-start, requirement-check, refactor, and docs-review subsections that the template does not ship — verified: CLAUDE.md as injected in this RFC's session, lines for `## Workflow` and its subsections). Replacing the whole file would destroy that work; replacing the section bodies would destroy partial customizations within a plugin-owned section. Additive item-by-item merging is the only model that does the right thing for both directions.

#### Strategy 2: `bootstrap` — for `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`

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

#### Strategy 3: `authoritative` — for `docs/rfc-process.md`

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

#### Variant considered (and rejected): use `additive-merge` for all four files

A consistent shape would be appealing — every file gets the same additive treatment. Rejected for two reasons. First, it would force semantic merging on `docs/ARCHITECTURE.md`, where the plugin's contribution is a placeholder template and the local file is a fully-composed document; there are no overlapping "concepts" to merge, just a template that has served its purpose. Second, it would force semantic merging on `docs/rfc-process.md`, where the plugin's intent is to be authoritative (the workflow must be shared exactly); allowing additive local extensions would re-introduce the divergence problem `authoritative` exists to solve. The three strategies exist because the three relationships are genuinely different.

## Drawbacks

1. **`additive-merge` requires LLM-assisted semantic comparison and accepts its failure modes.** The diff engine cannot do byte-equality for "same concept, different wording" — it has to ask an LLM. This carries two costs: (a) a per-`/sync` token spend proportional to the size of `additive-merge` files (small in practice — `CLAUDE.md` is ~180 lines, comparisons are bounded by the number of plugin-owned items, not file length); and (b) the LLM can produce false positives ("two items mean the same thing" when they don't — leading to silent overwrites of local wording) and false negatives ("two items are different" when they're conceptually identical — leading to spurious additions or false-flagged conflicts). The error rate is low for well-defined rules with clear semantic boundaries, higher for vague boilerplate. The cost is real but bounded: false positives produce a wording change the user can revert via git; false negatives produce a duplicate item the user can clean up manually. Both modes are recoverable, unlike the current loop, which is not.

2. **`bootstrap` gives up all future plugin authority over the file.** Once a project has `docs/CONTRIBUTING.md` or `docs/ARCHITECTURE.md`, the plugin cannot update it via `/sync` — even if the template improves substantially, even if the project genuinely wants to pick up the new template content. The only recovery path is "delete the local file, then re-run `/sync`," which is destructive and not discoverable from the `/sync` output. A maintainer who improves the template body has no automated way to flow the improvement to existing projects.

3. **`authoritative` overwrites any local edits to `docs/rfc-process.md` after a single batch confirmation.** A project that edits the file directly (perhaps to add a project-specific reviewer table or rename a status label) will see those edits replaced on the next `/sync`. The user does see the update as a checkbox in the Step 4a batch confirmation and can defer it (deselect the checkbox) to keep the local edits for now, but `authoritative` provides no per-line conflict resolution path — the choice is "approve the overwrite" or "keep the file as-is and be re-prompted next run." Today the diff engine offers a richer conflict menu (Adopt / Keep / Merge / Skip) on the same file. Mitigation: document the strategy's overwrite semantics prominently in the second line of the file's two-line header ("Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync."), in `docs/CONTRIBUTING.md` for the plugin (so plugin maintainers don't forget), and in consumer-facing release notes for the plugin version that introduces this RFC's changes (so projects that customized `rfc-process.md` know to migrate their customizations elsewhere before upgrading).

4. **Manifest schema gains three new strategy values, each with its own apply logic.** The diff engine's strategy switch becomes wider: today four cases (`whole`, `section`, `region`, `structured`); after this RFC, seven cases. Maintenance of the strategy switch grows correspondingly; the test surface for the apply step grows; the documentation in `skills/sync/SKILL.md` grows. Each new strategy is independent (their apply logic does not depend on the others), so the additional surface is additive complexity rather than entangled complexity, but it is still more code paths to keep correct.

5. **The `## Project Extensions` section in existing `docs/rfc-process.md` files is dropped on the first `authoritative` apply.** Under `authoritative`, the next `/sync` run after this RFC ships presents the file as an item in the Step 4a batch confirmation; approving the item replaces the local file with the plugin's version, including the loss of any `## Project Extensions` content. Any project that customized `## Project Extensions` (today none, per the verification above, but future projects might) would lose that section if they approve the batch item. Mitigation: the user sees the rfc-process.md item in the batch checklist with a clear label that names the strategy, and the implementation spec's first-run migration check additionally surfaces a one-time warning quoting any non-placeholder `## Project Extensions` body *before* the batch confirmation is rendered, giving the user a chance to copy the content elsewhere before deciding how to vote on the checkbox.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `.claude-plugin/bootstrap-manifest.json` | Replace four artifact declarations: `CLAUDE.md` gets `extension_strategy: "additive-merge"` with the unchanged ten-section `owned_sections`; `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` get `extension_strategy: "bootstrap"` (no other strategy fields needed); `docs/rfc-process.md` gets `extension_strategy: "authoritative"` with `region_end_marker` removed. |
| Modify | `skills/sync/SKILL.md` | Extend the canonicalization-rules block (at lines 334-340), the Step 4a batch-confirmation block (at lines 380-394), and the apply-actions block (at lines 440-456) with three new branches: `additive-merge` (item-level matching against the manifest's `owned_sections`; LLM-assisted comparison helper); `bootstrap` (presence-check short-circuit; batch checkbox on file-absent; no canonicalization or diff on file-present); `authoritative` (full-content compare after two-line-header strip; batch checkbox on differing content; no Step 4b menu). Extend the classification matrix at lines 323-332 with three new outcome branches that route `additive-merge`, `bootstrap`, and `authoritative` files to their strategy-specific paths before the existing matrix runs. Convert the Step 4a yes/no two-question pattern to a single `multiSelect: true` AskUserQuestion with per-file checkboxes spanning additions, fast-forwards, legacy-marker insertions, bootstrap creations, authoritative adds, and authoritative updates. Extend Step 4b's resolution menu to handle the one prompt `additive-merge` can produce (item-level contradiction). |
| Modify | `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` | No structural change — the template body stays as-is (the existing generic skeleton with `<PREREQUISITES_SECTION>`, `<INSTALL_COMMAND>`, `<QUALITY_GATE_DESCRIPTION>` placeholders is still the right thing for a new project to start with). Verified: the current template at lines 1-67 is a reasonable starting point for any project. |
| Modify | `.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl` | No structural change — the placeholder-heavy template is the right thing for a new project to start with (the placeholders guide the user through composing each section). |
| Modify | `docs/rfc-process.md` (in the bytewyrd plugin's own checkout; this is the file consumer projects sync from) | Remove the `## Project Extensions` section entirely (lines 230-232 inclusive: heading, blank, placeholder body), the separator line before it (line 228: `---`), and the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226. Under `authoritative` the entire file is plugin-owned; the separator and the project-extensions section no longer have meaning. The three leader comments on lines 1-3 (`<!-- UPSTREAM: ... -->`, `<!-- LAST_SYNCED: ... -->`, and the explanatory comment about `END_UPSTREAM_CONTENT`) plus the blank line 4 are also removed — they were part of the older marker convention. After the edits, the file's line 1 is the H1 `# RFC Process` (currently line 5). The plugin's source file in the repo does **not** carry the two-line `authoritative` header — that header is inserted by the sync skill at write time on every consumer-project apply, not stored in the plugin source. |
| Add | (none) | No new files. Three new strategies live as additional branches inside the existing `skills/sync/SKILL.md` body; no new template files; no new manifest fields beyond the three strategy values. |

### Exact manifest changes

The full diff against the current `.claude-plugin/bootstrap-manifest.json`:

**1. `CLAUDE.md` — change `extension_strategy` to `additive-merge`.**

Replace the existing `extension_strategy: "section"` value (currently at line 84) with `extension_strategy: "additive-merge"`. The `owned_sections` array (lines 85-96, ten entries) is unchanged. The `templated`, `template_inputs`, `target`, `source`, and `upstream_key` fields are unchanged. The `template_sha` field is recomputed by `build-manifest.sh` only if the template body changes; it does not depend on the strategy field. The final entry shape:

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "source": ".claude-plugin/scripts/templates/CLAUDE.md.tpl",
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
  "source": ".claude-plugin/scripts/templates/CONTRIBUTING.md.tpl",
  "target": "docs/CONTRIBUTING.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "bootstrap",
  "templated": false
}
```

The `sha256` field stays — `build-manifest.sh` writes it from the template source (verified: .claude-plugin/scripts/build-manifest.sh:L36-L42), and the diff engine uses it only on the very first `/sync` in a project that lacks the file (where the SHA records the plugin version that produced the local file's contents). No `owned_sections`, `owned_paths`, or `region_end_marker` fields — `bootstrap` has no concept of partial ownership.

**3. `docs/ARCHITECTURE.md` — change `extension_strategy` to `bootstrap`.**

Replace the existing entry (currently lines 126-133 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/ARCHITECTURE.md@v1",
  "source": ".claude-plugin/scripts/templates/ARCHITECTURE.md.tpl",
  "target": "docs/ARCHITECTURE.md",
  "sha256": "<existing hash, recomputed by build-manifest.sh>",
  "extension_strategy": "bootstrap",
  "templated": false
}
```

Same shape as `docs/CONTRIBUTING.md`. `templated` stays `false` because the existing template body is plain text (verified: .claude-plugin/scripts/templates/ARCHITECTURE.md.tpl has no `<...>` placeholders that the renderer would substitute — the angle-bracket strings inside the body are documentation guidance, not renderer tokens; the renderer's "Unrecognized placeholders are replaced with empty string" rule at `skills/sync/SKILL.md:L431` would silently delete them if `templated` were `true`).

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

6. **Reserialize the file.** Marker on line 2 (per `skills/sync/SKILL.md:L434`, verified). Sections in their preserved relative order. Update the marker SHA to the new canonical-form hash.

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

### Diff-engine integration

The three new branches plug into the existing diff engine before the current classification matrix. Pseudocode for the integrated classification function:

```
def classify(artifact, target_path, plugin_root, project_inputs):
    strategy = artifact.extension_strategy

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

    if strategy == "additive-merge":
        # Cheap pre-check via canonical-form hashing (same as section strategy)
        if not target_path.exists():
            return "add"
        plugin_canonical = canonicalize_sections(render_template(artifact, project_inputs), artifact.owned_sections)
        local_canonical = canonicalize_sections(target_path.read_text(), artifact.owned_sections)
        if sha256_12(plugin_canonical) == sha256_12(local_canonical):
            return "unchanged"
        return "additive_merge_apply"

    # Existing matrix for whole, section, region, structured
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

    # Existing dispatch for whole, section, region, structured
    return apply_existing(artifact, classification, target_path, plugin_root, project_inputs)
```

Constants used above:

```
BOOTSTRAP_SECOND_LINE     = "<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project — /sync will not update it. Maintain it as part of your codebase. -->"
AUTHORITATIVE_SECOND_LINE = "<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->"
```

`write_with_two_line_header` writes the file with these two lines as the first two lines (header on line 1, second-line label on line 2, then a blank line on line 3, then the body). `write_with_marker` is the existing single-line writer used by all other strategies. `apply_additive_merge` implements the section-by-section, item-by-item algorithm described above. `apply_existing` is the current Step 5 apply logic at `skills/sync/SKILL.md:L440-L456` (verified) unchanged.

### Step 4a batch confirmation — combined for additions, fast-forwards, bootstrap creations, and authoritative updates

The existing Step 4a (verified: skills/sync/SKILL.md:L380-L394) asks one AskUserQuestion containing up to two questions (additions, fast-forwards). This RFC extends it to a single AskUserQuestion with **per-file checkboxes** rather than a per-category yes/no, so the user can selectively defer individual items across the four batched classifications.

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

1. **Edit the manifest.** Open `.claude-plugin/bootstrap-manifest.json`. Apply the four entry replacements documented under "Exact manifest changes" above. After editing, the `template_sha` for `CLAUDE.md` is unchanged (the template body is not changing in this RFC); the `sha256` values for `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, and `docs/rfc-process.md` are recomputed by step 4 below.

2. **Remove the `## Project Extensions` section from `docs/rfc-process.md` in the bytewyrd plugin's own checkout.** Delete lines 226-232 inclusive (the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226, the blank line 227, the `---` separator on line 228, the blank line 229, the `## Project Extensions` heading on line 230, the blank line 231, and the placeholder body on line 232). Also delete lines 1-4 inclusive (the `<!-- UPSTREAM: ... -->` comment on line 1, the `<!-- LAST_SYNCED: ... -->` comment on line 2, the explanatory comment about `END_UPSTREAM_CONTENT` on line 3, and the blank line 4). After the edits, line 1 of the file is the H1 `# RFC Process` (currently at line 5). After the edit, the file is the canonical plugin RFC process content with no leader comments and no extension region.

3. **Update `skills/sync/SKILL.md`** with three new strategy branches. The changes are localized to:

   - The Canonicalization rules block (currently lines 334-340): generalize the existing "marker line(s) removed" rule to a single `strip_two_line_header` function that removes every contiguous line at the top of the file starting with `<!-- bootstrap-content-version:`, `<!-- Managed by the Bytewyrd plugin.`, or `<!-- Bootstrapped by the Bytewyrd plugin.`, plus any immediately following blank line. The new function is a superset of today's strip (which already supports "marker line(s)" — plural) and is shared by every strategy's canonicalizer. Add three new bullet points for `additive-merge`, `bootstrap`, and `authoritative`. The `bootstrap` and `authoritative` entries explicitly note "no canonical-form hash compare against plugin canonical content — strategy bypasses the canonicalization-and-hash classification matrix in favor of presence-check (bootstrap) or full-content compare after header strip (authoritative)."
   - The Classification matrix block (currently lines 323-332): add a preamble paragraph that documents the strategy-first dispatch: "Before applying the matrix below, dispatch to the strategy-specific classifier when `extension_strategy` is `additive-merge`, `bootstrap`, or `authoritative`. The matrix below applies only to the four canonicalization-based strategies (`whole`, `section`, `region`, `structured`)."
   - The Step 4a batch-confirmation block (currently lines 380-394): replace the two-question yes/no pattern with the single-question multiSelect pattern described in "Step 4a batch confirmation" above. The new question's options come from the union of additions, fast-forwards, legacy-marker insertions, bootstrap creations, authoritative additions, and authoritative updates — one option per artifact, with the label format that names the category and consequence. Preserve the existing `Review each` mode as a per-category escape hatch.
   - The Step 4b resolution menu (currently lines 396-423): add a new variant for `additive-merge`'s contradiction case (the four-option menu described in the `additive-merge` algorithm above). `authoritative` and `bootstrap` files never enter Step 4b — their decision is the Step 4a checkbox.
   - The Apply actions block (currently lines 440-456): add three new top-level cases for `additive-merge`, `bootstrap`, and `authoritative`, each documenting their apply step. The `additive-merge` case references the item-by-item algorithm; the `bootstrap` and `authoritative` cases describe the two-line header write (using the `BOOTSTRAP_SECOND_LINE` and `AUTHORITATIVE_SECOND_LINE` constants defined in "Diff-engine integration" above) and the deferred-item bookkeeping for deselected batch items.

4. **Regenerate the manifest.** Run `.claude-plugin/scripts/build-manifest.sh` from the repo root (verified: build-manifest.sh:L1-L55 walks the manifest and recomputes `sha256`/`template_sha` for each artifact's source file). Expected stdout: `Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/.claude-plugin/bootstrap-manifest.json`. Expected exit code: `0`.

5. **Verify the manifest passes the pre-commit check.** Run `.claude-plugin/scripts/build-manifest.sh --check` (verified: build-manifest.sh:L45-L51 exits non-zero if regenerated output differs from the committed manifest). Expected exit code: `0`. If non-zero, re-run step 4.

6. **Run `/sync` in a consumer project (smoke test).** From a consumer project (the bytewyrd plugin's own worktree at `/home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/` is a valid consumer for testing), invoke `/sync`. Expected classification per file on the first run after this RFC ships:

   - `CLAUDE.md` → **additive_merge_apply** (or **unchanged** if every plugin-owned item already has a `same_concept` match in local). On the bytewyrd plugin's own checkout, the file has all ten plugin-owned sections present with bodies that match the template's items conceptually — verified by inspection of CLAUDE.md vs CLAUDE.md.tpl in this RFC's session. Outcome: `additive_merge_apply` with all items resolved as `same_concept` (no contradictions), local wording potentially replaced where plugin and local differ. Single-line marker stamped on completion.
   - `docs/CONTRIBUTING.md` → **local_only** — the file exists; `bootstrap` short-circuits to `local_only`. No prompt, no diff, no write.
   - `docs/ARCHITECTURE.md` → **local_only** — same.
   - `docs/rfc-process.md` → **authoritative_update** on first run (local content has leader comments and `## Project Extensions` section, plugin content does not, so they differ after stripping the two-line header). The migration-time warning is printed inline above the Step 4a batch prompt (the local `## Project Extensions` body in this worktree is the placeholder, so the warning's "non-placeholder content" branch does not fire for this specific run — but the migration-check code is exercised). The Step 4a batch prompt renders with one item: `Update docs/rfc-process.md to plugin version <sha12> (authoritative — local edits will be replaced)`. The user approves it; the file is overwritten with the plugin's canonical content and the two-line `authoritative` header is stamped. On the very next run, classification is **unchanged** and no further interaction.

   The Step 4a batch prompt fires for `docs/rfc-process.md` (one `authoritative_update` item) on the first post-RFC run, and `CLAUDE.md` enters Step 4a only if it has new `additive-merge` *additions* (plugin items that need to be appended — this is the `add`-shaped sub-case of `additive_merge_apply`). On the bytewyrd plugin's own checkout there are zero such additions today, so `CLAUDE.md` does not enter Step 4a. The Step 4b conflict prompt fires only for `additive-merge` items in `contradiction` state, of which there are zero in the bytewyrd plugin's own checkout (verified by item-by-item inspection of CLAUDE.md vs CLAUDE.md.tpl during this RFC's session — every plugin item has a same-concept match in local).

7. **Verify the headers were written.** After `/sync`:

   ```bash
   sed -n '1,2p' CLAUDE.md docs/rfc-process.md
   ls -la docs/CONTRIBUTING.md docs/ARCHITECTURE.md  # files exist, not touched by /sync
   ```

   Expected:
   - `CLAUDE.md` line 1 is the first line of body (no leading marker on this strategy unless the marker convention has changed for `additive-merge`); line 2 is `<!-- bootstrap-content-version: ... -->` (single-line marker per the existing `section`/`additive-merge` convention at `skills/sync/SKILL.md:L434`, verified).
   - `docs/rfc-process.md` lines 1-2 are the two-line `authoritative` header: `<!-- bootstrap-content-version: ... -->` on line 1, `<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->` on line 2.
   - `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` are unmodified by this `/sync` (these are `local_only` — no header is injected because the strategy classified them as already-owned-by-project; the two-line `bootstrap` header is only written on the initial `bootstrap_create` apply, which does not fire on this run because the files already exist).

8. **Run `/sync` again (idempotence check).** Invoke `/sync` a second time. Expected stdout: `Everything is up to date.` (per `skills/sync/SKILL.md:L367`, verified) — every file classifies as `unchanged` or `local_only`. No prompts, no resolutions, no per-file output.

### Verification commands

After step 8 succeeds, the four files are out of the `conflict_legacy` loop permanently:

- `CLAUDE.md` carries a single-line `<!-- bootstrap-content-version: ... -->` marker on line 2 (as today). Subsequent plugin updates re-run the `additive-merge` algorithm: same-concept matches silently update local wording, new plugin items are appended (and surface as `add`-shaped items in Step 4a for confirmation), local-only items are preserved, contradictions prompt explicitly in Step 4b.
- `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` carry the two-line `bootstrap` header only if they were created by this RFC's `/sync` flow. Existing files (the common case on first run after this RFC ships) are not modified and do not gain the header — they are classified as `local_only` from this point forward, and the plugin can update the template body in future versions without the change flowing to existing projects (by design).
- `docs/rfc-process.md` carries the two-line `authoritative` header on lines 1-2 after the first approved update. Subsequent plugin updates appear as `authoritative_update` items in Step 4a; approving the item overwrites local content with the plugin version; deselecting the item defers the update to the next run.

The `conflict_legacy` cycle for these files is terminated. The only per-run interactions that can still arise are: (a) an `additive-merge` contradiction on `CLAUDE.md` (Step 4b), which is bounded by genuine semantic opposition between project and plugin rules; (b) an `additive-merge` plugin-item addition on `CLAUDE.md` (Step 4a checkbox), which is bounded by the rate at which the plugin ships new items; (c) the one-time migration warning on `docs/rfc-process.md` for projects with non-empty `## Project Extensions` content; and (d) every plugin-version update to `docs/rfc-process.md` surfaces as one Step 4a checkbox.

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

7. **The manifest pre-commit hook does not validate strategy-specific fields.** `build-manifest.sh --check` (verified: .claude-plugin/scripts/build-manifest.sh:L45-L51) verifies that recorded SHAs match source files. It does not check that `additive-merge` entries have `owned_sections`, that `bootstrap` entries omit `owned_sections`/`owned_paths`/`region_end_marker`, or that `authoritative` entries omit `region_end_marker`. A maintainer who edits the manifest by hand and forgets to remove an obsolete field will see no error.

   **Mitigation:** extending the pre-commit check to validate per-strategy field requirements is a small follow-up (out of scope here). The first symptom of a malformed manifest is a runtime error during `/sync` classification dispatch, which is loud and immediate; the manifest is a small file and the strategy fields are easy to inspect manually.

## Relationship to other RFCs

This RFC builds on the per-file marker infrastructure introduced by `2026-05-10-sync-interactive-diff` (Done) and does not depend on or block any other RFC. It supersedes any prior assumption (including in this RFC's earlier draft) that the fix for the `conflict_legacy` loop would be a narrowing of `CLAUDE.md`'s `owned_sections` and a migration to `section`/`region` strategies for `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`. That approach is dropped entirely in favor of the three-strategy model described here.
