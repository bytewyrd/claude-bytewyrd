---
rfc: "2026-05-14-sync-per-file-extension-strategies"
title: "Sync Per-File Extension Strategies"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-14"
drop_reason: ~
---

## Summary

Introduce three named extension strategies — `additive-merge`, `bootstrap`, and `authoritative` — and assign each of the four currently-stuck plugin-managed files to the strategy that matches how the plugin actually relates to that file's content. `CLAUDE.md` becomes `additive-merge`: the plugin is the authoritative source for every concept it ships, but it adds new items rather than replacing the file. `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` become `bootstrap`: the plugin writes a starter template once, and from that point forward the file is local-owned and the plugin never touches it again. `docs/rfc-process.md` becomes `authoritative`: the plugin's content is always the file's content, applied silently with no per-run prompts and no local extensions section. After the change, the `conflict_legacy` loop (the "Keep local version" action explicitly does not stamp the marker — verified: skills/sync/SKILL.md:L420) terminates for all four files: the next `/sync` either classifies each file as `unchanged` (it already matches plugin canonical content) or applies the strategy's deterministic decision with no per-run prompting. The three strategies replace the file-level conflation that today routes substantively different ownership models through the same `whole`/`section`/`region`/`structured` matrix.

## Should we do this?

**Yes.** The current behavior is a hard regression for every consumer project that has run `/sync` after the per-file marker system shipped. Each of the four files re-surfaces as `conflict_legacy` on every subsequent `/sync` run regardless of whether the user has touched the file since (verified: skills/sync/SKILL.md:L323-L332 — the classification matrix routes any file lacking a `<!-- bootstrap-content-version: ... -->` marker to either `unchanged_legacy` or `conflict_legacy` depending on whether canonical content matches). The only escape paths today are "Adopt plugin version" (which overwrites real local content with the plugin's stub) or "Keep local version" (which does not stamp the marker, so the same prompt re-surfaces on the next run — the action description at `skills/sync/SKILL.md:L420` says this explicitly: "no write; marker not updated; conflict re-surfaces on next run"). The loop is structural: the manifest declares ownership semantics that do not match how the plugin actually relates to the file's content, so the diff engine's classification matrix produces a wrong answer every time. The fix is to make the manifest describe the actual relationships — three different relationships, three named strategies, one per file (or pair of files). Two of the three strategies introduce no per-file user prompts at all, eliminating an entire class of routine interruption.

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

### Decision 1 — New strategies vs. acknowledgment path

**Option A — Introduce three new extension strategies (`additive-merge`, `bootstrap`, `authoritative`) and assign each affected file to the strategy that matches its actual relationship to the plugin (recommended).**

For each file, the manifest declares a strategy whose semantics directly describe the relationship: "the plugin contributes items here and merges them additively," "the plugin writes a starter template once and never touches the file again," or "the plugin is the source of truth and always wins." The diff engine implements the three strategies' classification and apply logic; the user sees no `conflict_legacy` prompt for these files unless a strategy explicitly produces a conflict (which only `additive-merge` can do, and only when local and plugin items semantically contradict). Two of the three strategies — `bootstrap` and `authoritative` — produce no per-run prompts at all once the strategy is in place.

This option requires three new strategy values, three new classification-and-apply code paths in the diff engine, and the manifest schema accepting new values for `extension_strategy`. It does not add new resolution options to the existing menu — the new strategies have their own resolution semantics encoded in the strategy itself (no menu for `bootstrap` and `authoritative`; a different one for `additive-merge`'s rare conflict case).

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

**Definition.** The plugin's role is to provide a starter template on the first `/sync` in a project that does not yet have the file. Once the file exists locally (whether the plugin wrote it or not), the plugin gives up authority over the file forever. Classification semantics:

- **File absent in local repo** → write from the plugin's template; stamp the bootstrap marker on completion
- **File present in local repo (regardless of marker state)** → classify as `local_only`; no diff, no prompt, no update, ever

There is no "fast-forward" path for `bootstrap` files. The plugin's template can change in future plugin versions, and that change will *not* propagate to existing files — by design. The plugin's job ends after the first write.

**Why `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` fit.** Both files document project-specific reality: how to set up *this* project's development environment, what *this* project's architecture is. A generic template is useful exactly once — on day one of a fresh repo. After that, every meaningful change is project-specific and any attempt by the plugin to keep them in sync amounts to overwriting the project's own documentation. `bootstrap` describes the only sane plugin role for these files: hand the project a starting point, then step out of the way.

#### Strategy 3: `authoritative` — for `docs/rfc-process.md`

**Definition.** The plugin's content is always the file's content. Every `/sync` run applies the plugin version silently, with no per-file user prompt. There is no local extensions section. Classification and apply semantics:

- **Plugin content equals local content** → classify as `unchanged`; no write
- **Plugin content differs from local content (fast-forward direction)** → silently overwrite with plugin content; stamp marker; no prompt
- **Plugin content differs from local content (any other direction, including local edits)** → silently overwrite with plugin content; stamp marker; no prompt. Local edits are not preserved.

The plugin's `rfc-process.md` upstream content is the entire file content. There is no `region_end_marker` because there is no project-extension region; what used to live under `## Project Extensions` in the local file is dropped under this strategy.

**Why `docs/rfc-process.md` fits.** The RFC process is a workflow the plugin enforces across every consumer project. Divergent local versions are an anti-feature — they break the shared vocabulary that makes the RFC skills (`/rfc-new`, `/rfc-implement`, etc.) interoperable. The existing `## Project Extensions` section was a hedge against the case where a project genuinely needed to extend the process locally; in practice, no consumer project has used it (verified: docs/rfc-process.md:L232 — the only existing instance has the body `*(no project-specific extensions — the global process applies as-is)*`, and the plugin ships in the only repo that carries the file). Dropping the extension region simplifies the model: the plugin owns the file outright, the diff engine never prompts on it, and every consumer is always on the current process.

#### Variant considered (and rejected): use `additive-merge` for all four files

A consistent shape would be appealing — every file gets the same additive treatment. Rejected for two reasons. First, it would force semantic merging on `docs/ARCHITECTURE.md`, where the plugin's contribution is a placeholder template and the local file is a fully-composed document; there are no overlapping "concepts" to merge, just a template that has served its purpose. Second, it would force semantic merging on `docs/rfc-process.md`, where the plugin's intent is to be authoritative (the workflow must be shared exactly); allowing additive local extensions would re-introduce the divergence problem `authoritative` exists to solve. The three strategies exist because the three relationships are genuinely different.

## Drawbacks

1. **`additive-merge` requires LLM-assisted semantic comparison and accepts its failure modes.** The diff engine cannot do byte-equality for "same concept, different wording" — it has to ask an LLM. This carries two costs: (a) a per-`/sync` token spend proportional to the size of `additive-merge` files (small in practice — `CLAUDE.md` is ~180 lines, comparisons are bounded by the number of plugin-owned items, not file length); and (b) the LLM can produce false positives ("two items mean the same thing" when they don't — leading to silent overwrites of local wording) and false negatives ("two items are different" when they're conceptually identical — leading to spurious additions or false-flagged conflicts). The error rate is low for well-defined rules with clear semantic boundaries, higher for vague boilerplate. The cost is real but bounded: false positives produce a wording change the user can revert via git; false negatives produce a duplicate item the user can clean up manually. Both modes are recoverable, unlike the current loop, which is not.

2. **`bootstrap` gives up all future plugin authority over the file.** Once a project has `docs/CONTRIBUTING.md` or `docs/ARCHITECTURE.md`, the plugin cannot update it via `/sync` — even if the template improves substantially, even if the project genuinely wants to pick up the new template content. The only recovery path is "delete the local file, then re-run `/sync`," which is destructive and not discoverable from the `/sync` output. A maintainer who improves the template body has no automated way to flow the improvement to existing projects.

3. **`authoritative` silently overwrites any local edits to `docs/rfc-process.md`.** A project that edits the file directly (perhaps to add a project-specific reviewer table or rename a status label) will see those edits disappear silently on the next `/sync`. Today the diff engine prompts on conflicts; under `authoritative` it does not. Mitigation: document the strategy's silent-overwrite semantics prominently in `docs/CONTRIBUTING.md` for the plugin (so plugin maintainers don't forget), and document them in consumer-facing release notes for the plugin version that introduces this RFC's changes (so projects that customized `rfc-process.md` know to migrate their customizations elsewhere before upgrading).

4. **Manifest schema gains three new strategy values, each with its own apply logic.** The diff engine's strategy switch becomes wider: today four cases (`whole`, `section`, `region`, `structured`); after this RFC, seven cases. Maintenance of the strategy switch grows correspondingly; the test surface for the apply step grows; the documentation in `skills/sync/SKILL.md` grows. Each new strategy is independent (their apply logic does not depend on the others), so the additional surface is additive complexity rather than entangled complexity, but it is still more code paths to keep correct.

5. **The `## Project Extensions` section in existing `docs/rfc-process.md` files is dropped without warning.** Under `authoritative`, the next `/sync` run silently replaces the local file with the plugin's version. Any project that customized `## Project Extensions` (today none, per the verification above, but future projects might) would lose that section. Mitigation: this RFC's first-run migration explicitly checks for non-empty `## Project Extensions` content and surfaces a one-time warning before overwriting (described in the implementation spec).

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `.claude-plugin/bootstrap-manifest.json` | Replace four artifact declarations: `CLAUDE.md` gets `extension_strategy: "additive-merge"` with the unchanged ten-section `owned_sections`; `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` get `extension_strategy: "bootstrap"` (no other strategy fields needed); `docs/rfc-process.md` gets `extension_strategy: "authoritative"` with `region_end_marker` removed. |
| Modify | `skills/sync/SKILL.md` | Extend the canonicalization-rules block (at lines 334-340) and apply-actions block (at lines 440-456) with three new branches: `additive-merge` (item-level matching against the manifest's `owned_sections`; LLM-assisted comparison helper); `bootstrap` (presence-check short-circuit; no canonicalization, no diff); `authoritative` (silent overwrite, no prompt). Extend the classification matrix at lines 323-332 with three new outcome branches that route `additive-merge`, `bootstrap`, and `authoritative` files to their strategy-specific paths before the existing matrix runs. Extend Step 4b's resolution menu to handle the one prompt `additive-merge` can produce (item-level contradiction). |
| Modify | `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` | No structural change — the template body stays as-is (the existing generic skeleton with `<PREREQUISITES_SECTION>`, `<INSTALL_COMMAND>`, `<QUALITY_GATE_DESCRIPTION>` placeholders is still the right thing for a new project to start with). Verified: the current template at lines 1-67 is a reasonable starting point for any project. |
| Modify | `.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl` | No structural change — the placeholder-heavy template is the right thing for a new project to start with (the placeholders guide the user through composing each section). |
| Modify | `docs/rfc-process.md` (in the bytewyrd plugin's own checkout; this is the file consumer projects sync from) | Remove the `## Project Extensions` section entirely (lines 230-232 inclusive: heading, blank, placeholder body), the separator line before it (line 228: `---`), and the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226. Under `authoritative` the entire file is plugin-owned; the separator and the project-extensions section no longer have meaning. The three leader comments on lines 1-3 (`<!-- UPSTREAM: ... -->`, `<!-- LAST_SYNCED: ... -->`, and the explanatory comment about `END_UPSTREAM_CONTENT`) plus the blank line 4 are also removed — they were part of the older marker convention and are not needed under `authoritative`, which has no leader-comment requirement. After the edits, the file's line 1 is the H1 `# RFC Process` (currently line 5). |
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
        classify as "add"
    else:
        classify as "local_only"  (regardless of marker state)
    return
```

The `local_only` classification means: no diff is computed, no prompt is presented, the file is preserved exactly as it is. The Step 8 report lists the file under "Local-only edits (N files, plugin unchanged)" (verified: skills/sync/SKILL.md:L362).

**Apply step.**

- `add` outcome: render the template with `project_inputs` (for `bootstrap` files with `templated: true` — none in this RFC's scope, but the strategy supports it). For `templated: false`, read the template source as-is. Insert the `<!-- bootstrap-content-version: ... -->` marker as line 2 per `skills/sync/SKILL.md:L434`. Write the file. Track as `added`.
- `local_only` outcome: no write. Track as `local-only edit preserved`.

There is no `fast_forward`, `conflict`, `conflict_legacy`, `unchanged_legacy`, or `unchanged` outcome for `bootstrap` files. The strategy's classification is bimodal: either the file does not exist (and the plugin writes it once) or it exists (and the plugin leaves it alone forever).

#### `authoritative` — `docs/rfc-process.md`

**Classification.** Like `bootstrap`, the classification matrix gets a new branch that runs before the existing matrix:

```
If extension_strategy == "authoritative":
    plugin_content = read plugin source, strip any existing marker line(s)
    if target_file is absent:
        classify as "add"
    elif local_content (stripped of marker) == plugin_content:
        classify as "unchanged"
    else:
        classify as "fast_forward"   # but with no user prompt
    return
```

The `fast_forward` here is a strategy-specific variant — it is auto-applied without entering Step 4a's "fast-forward updates" confirmation list. Step 4a is the right place for that confirmation in the `whole`/`section`/`region`/`structured` strategies because the user might want to review changes; for `authoritative` the plugin is the source of truth by design, and confirming each run defeats the strategy's purpose.

**Apply step.**

- `add`: read the plugin source, insert the marker as line 2 per `skills/sync/SKILL.md:L434`, write the file. Track as `added`.
- `unchanged`: no write. Track as `unchanged`.
- `fast_forward`: read the plugin source, insert the marker, write the file (silently overwriting any local content). Track as `authoritative update applied`.

**Migration-time check (one-time, on the first `/sync` after this RFC ships):** if the local file contains a `## Project Extensions` section whose body (after trimming) is anything other than the placeholder `*(no project-specific extensions — the global process applies as-is)*` or an empty body, print a one-time warning:

```
docs/rfc-process.md — your '## Project Extensions' section will be removed
on this /sync because the file is now plugin-authoritative. The content was:

  <quoted section body, indented 2 spaces, truncated to 200 chars>

If you need to keep these customizations, copy them now to another file
(e.g., docs/CONTRIBUTING.md or a new docs/rfc-process-extensions.md)
before continuing. Press Ctrl-C to abort, or proceed to overwrite.
```

The warning is presented as a synchronous read-line prompt (the existing `/sync` agent loop already uses synchronous prompts via AskUserQuestion — verified: skills/sync/SKILL.md:L14-L17). If the user proceeds, the file is overwritten. If the user aborts, `/sync` exits cleanly with no writes. This is the only per-file user interaction `authoritative` produces, and it fires exactly once per project (after the first apply, the local content matches the plugin and the strategy classifies as `unchanged` on subsequent runs).

### Diff-engine integration

The three new branches plug into the existing diff engine before the current classification matrix. Pseudocode for the integrated classification function:

```
def classify(artifact, target_path, plugin_root, project_inputs):
    strategy = artifact.extension_strategy

    if strategy == "bootstrap":
        if not target_path.exists():
            return "add"
        return "local_only"

    if strategy == "authoritative":
        plugin_content = strip_markers(read_plugin_source(artifact, plugin_root))
        if not target_path.exists():
            return "add"
        local_content = strip_markers(target_path.read_text())
        if local_content == plugin_content:
            return "unchanged"
        return "authoritative_fast_forward"

    if strategy == "additive-merge":
        # Cheap pre-check via canonical-form hashing (same as section strategy)
        plugin_canonical = canonicalize_sections(render_template(artifact, project_inputs), artifact.owned_sections)
        local_canonical = canonicalize_sections(target_path.read_text(), artifact.owned_sections) if target_path.exists() else None
        if not target_path.exists():
            return "add"
        if sha256_12(plugin_canonical) == sha256_12(local_canonical):
            return "unchanged"
        return "additive_merge_apply"

    # Existing matrix for whole, section, region, structured
    return classify_existing(artifact, target_path, plugin_root, project_inputs)
```

The apply function gets matching dispatch:

```
def apply(artifact, classification, target_path, plugin_root, project_inputs):
    if classification == "add":
        # All three new strategies share the "add" path: render, insert marker, write
        rendered = render_or_read(artifact, plugin_root, project_inputs)
        write_with_marker(target_path, rendered, artifact)
        return "added"

    if artifact.extension_strategy == "bootstrap":
        return "local-only edit preserved"  # classification == "local_only"

    if artifact.extension_strategy == "authoritative":
        if classification == "unchanged":
            return "unchanged"
        # classification == "authoritative_fast_forward"
        if first_run_with_authoritative(artifact, target_path):
            warn_project_extensions_if_present(target_path)
        rendered = render_or_read(artifact, plugin_root, project_inputs)
        write_with_marker(target_path, rendered, artifact)
        return "authoritative update applied"

    if artifact.extension_strategy == "additive-merge":
        if classification == "unchanged":
            return "unchanged"
        # classification == "additive_merge_apply"
        return apply_additive_merge(artifact, target_path, plugin_root, project_inputs)

    # Existing dispatch for whole, section, region, structured
    return apply_existing(artifact, classification, target_path, plugin_root, project_inputs)
```

`apply_additive_merge` implements the section-by-section, item-by-item algorithm described above. `apply_existing` is the current Step 5 apply logic at `skills/sync/SKILL.md:L440-L456` (verified) unchanged.

### Exact steps

1. **Edit the manifest.** Open `.claude-plugin/bootstrap-manifest.json`. Apply the four entry replacements documented under "Exact manifest changes" above. After editing, the `template_sha` for `CLAUDE.md` is unchanged (the template body is not changing in this RFC); the `sha256` values for `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, and `docs/rfc-process.md` are recomputed by step 4 below.

2. **Remove the `## Project Extensions` section from `docs/rfc-process.md` in the bytewyrd plugin's own checkout.** Delete lines 226-232 inclusive (the `<!-- END_UPSTREAM_CONTENT -->` marker on line 226, the blank line 227, the `---` separator on line 228, the blank line 229, the `## Project Extensions` heading on line 230, the blank line 231, and the placeholder body on line 232). Also delete lines 1-4 inclusive (the `<!-- UPSTREAM: ... -->` comment on line 1, the `<!-- LAST_SYNCED: ... -->` comment on line 2, the explanatory comment about `END_UPSTREAM_CONTENT` on line 3, and the blank line 4). After the edits, line 1 of the file is the H1 `# RFC Process` (currently at line 5). After the edit, the file is the canonical plugin RFC process content with no leader comments and no extension region.

3. **Update `skills/sync/SKILL.md`** with three new strategy branches. The changes are localized to:

   - The Canonicalization rules block (currently lines 334-340): add three new bullet points for `additive-merge`, `bootstrap`, and `authoritative`, each documenting the strategy's classification short-circuit. The `bootstrap` and `authoritative` entries explicitly note "no canonicalization — strategy bypasses the canonicalization-and-hash classification matrix."
   - The Classification matrix block (currently lines 323-332): add a preamble paragraph that documents the strategy-first dispatch: "Before applying the matrix below, dispatch to the strategy-specific classifier when `extension_strategy` is `additive-merge`, `bootstrap`, or `authoritative`. The matrix below applies only to the four canonicalization-based strategies (`whole`, `section`, `region`, `structured`)."
   - The Step 4b resolution menu (currently lines 396-423): add a new variant for `additive-merge`'s contradiction case (the four-option menu described in the `additive-merge` algorithm above).
   - The Apply actions block (currently lines 440-456): add three new top-level cases for `additive-merge`, `bootstrap`, and `authoritative`, each documenting their apply step. The `additive-merge` case references the item-by-item algorithm; the `bootstrap` and `authoritative` cases are short (no diff, deterministic write or no-op).

4. **Regenerate the manifest.** Run `.claude-plugin/scripts/build-manifest.sh` from the repo root (verified: build-manifest.sh:L1-L55 walks the manifest and recomputes `sha256`/`template_sha` for each artifact's source file). Expected stdout: `Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/.claude-plugin/bootstrap-manifest.json`. Expected exit code: `0`.

5. **Verify the manifest passes the pre-commit check.** Run `.claude-plugin/scripts/build-manifest.sh --check` (verified: build-manifest.sh:L45-L51 exits non-zero if regenerated output differs from the committed manifest). Expected exit code: `0`. If non-zero, re-run step 4.

6. **Run `/sync` in a consumer project (smoke test).** From a consumer project (the bytewyrd plugin's own worktree at `/home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/` is a valid consumer for testing), invoke `/sync`. Expected classification per file on the first run after this RFC ships:

   - `CLAUDE.md` → **additive_merge_apply** (or **unchanged** if every plugin-owned item already has a `same_concept` match in local). On the bytewyrd plugin's own checkout, the file has all ten plugin-owned sections present with bodies that match the template's items conceptually — verified by inspection of CLAUDE.md vs CLAUDE.md.tpl in this RFC's session. Outcome: `additive_merge_apply` with all items resolved as `same_concept` (no contradictions), local wording potentially replaced where plugin and local differ. Marker stamped on completion.
   - `docs/CONTRIBUTING.md` → **local_only** — the file exists; `bootstrap` short-circuits to `local_only`. No prompt, no diff, no write.
   - `docs/ARCHITECTURE.md` → **local_only** — same.
   - `docs/rfc-process.md` → **authoritative_fast_forward** on first run (local content has leader comments and `## Project Extensions` section, plugin content does not, so they differ after stripping markers). The migration-time check fires: the warning is printed; the user proceeds; the file is overwritten with the plugin's canonical content; marker stamped. On the very next run, classification is **unchanged** and no further interaction.

   The Step 4a batch-confirmation prompt is skipped for all four files (none of them produces an `add` or `fast_forward` in the existing strategies' sense). The Step 4b conflict prompt fires only for `additive-merge` items in `contradiction` state, of which there are zero in the bytewyrd plugin's own checkout (verified by item-by-item inspection of CLAUDE.md vs CLAUDE.md.tpl during this RFC's session — every plugin item has a same-concept match in local).

7. **Verify the markers were written.** After `/sync`:

   ```bash
   sed -n '2p' CLAUDE.md docs/CONTRIBUTING.md docs/ARCHITECTURE.md docs/rfc-process.md
   ```

   Expected: `CLAUDE.md` and `docs/rfc-process.md` line 2 are `<!-- bootstrap-content-version: ... -->` markers matching the plugin's canonical-form SHA. `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` line 2 is whatever was already there (these are `local_only` — no marker is injected because the strategy does not require it; the file is project-owned).

8. **Run `/sync` again (idempotence check).** Invoke `/sync` a second time. Expected stdout: `Everything is up to date.` (per `skills/sync/SKILL.md:L367`, verified) — every file classifies as `unchanged` or `local_only`. No prompts, no resolutions, no per-file output.

### Verification commands

After step 8 succeeds, the four files are out of the `conflict_legacy` loop permanently:

- `CLAUDE.md` carries a bootstrap-content-version marker. Subsequent plugin updates re-run the `additive-merge` algorithm: same-concept matches silently update local wording, new plugin items are appended, local-only items are preserved, contradictions prompt explicitly.
- `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md` are never re-checked. The plugin can update the template body in future versions and the change does not flow to existing projects — by design.
- `docs/rfc-process.md` carries a bootstrap-content-version marker. Subsequent plugin updates apply silently with no prompt; any future local edits are silently overwritten on the next `/sync`.

The `conflict_legacy` cycle for these files is terminated. The only per-run interactions that can still arise are: (a) an `additive-merge` contradiction on `CLAUDE.md`, which is bounded by genuine semantic opposition between project and plugin rules; and (b) the one-time migration warning on `docs/rfc-process.md` for projects with non-empty `## Project Extensions` content.

## Risks and open questions

1. **`additive-merge`'s LLM helper produces false-positive `same_concept` matches and silently overwrites local wording.** The helper is asked, item by item, to classify the relationship between a plugin item and a local item. A confidently-wrong "same_concept" classification leads to the local item's wording being replaced by the plugin's. The user has no visibility into individual replacements unless they read the resulting git diff.

   **Mitigation:** the Step 8 report lists each section where any item was modified, along with a count of `same_concept` replacements applied. The user can run `git diff CLAUDE.md` after `/sync` to inspect every replacement and revert any they disagree with via `git checkout -- CLAUDE.md` or selective edits. The confidence threshold (≥ 0.5) and the helper's prompt design (returning a discrete relationship label rather than a free-form judgment) reduce the false-positive rate but do not eliminate it. The recoverability via git history is the safety net: every replacement is in a single commit that can be selectively reverted.

2. **`additive-merge`'s LLM helper produces false-negative `different_concept` matches and creates duplicate items.** The helper fails to recognize that two items express the same concept, so the plugin item is appended even though local already has a (different-wording) version of it. The result is two items in the section that say nearly the same thing — clutter, not a wrong rule.

   **Mitigation:** the duplication is cosmetic, not destructive. The user can deduplicate in their next edit pass. The Step 8 report's per-section change summary makes the appended items visible. Over time, the user's deduplication edits should converge the local file toward wording that matches the plugin's exactly (which the helper then classifies confidently as `same_concept`), reducing the false-negative rate organically.

3. **`bootstrap` files diverge from the plugin's template over time with no automated recovery.** A project that adopted `docs/ARCHITECTURE.md` early gets a v1 template body. The plugin maintainer improves the template (better scope comment, additional guidance) for v2. Existing projects do not pick up the improvement — `bootstrap` short-circuits to `local_only` regardless of plugin version. The maintainer has no `/sync`-driven path to push improvements.

   **Mitigation (out of scope of this RFC, documented as an open question):** a future RFC may introduce a "re-bootstrap" command (e.g., `/sync --rebootstrap docs/ARCHITECTURE.md`) that explicitly opts the user into overwriting a `bootstrap` file with the plugin's current template, with a backup of the existing content (written to `docs/ARCHITECTURE.md.local-backup`) before the overwrite. This is a deliberate manual escape hatch, not an automated update — it inverts the strategy temporarily for one file, prompting the user explicitly. Out of scope here because no consumer project currently needs it.

4. **`authoritative` silently dropping local customizations is a new failure mode for projects that previously used `## Project Extensions`.** Today, the local copy of `docs/rfc-process.md` has a `## Project Extensions` section that the diff engine preserves (because `region` strategy stops at `<!-- END_UPSTREAM_CONTENT -->`). After this RFC, that section is removed on the first `/sync` and any future local edits to the file are silently overwritten on subsequent runs.

   **Mitigation:** the migration-time check described in the implementation spec fires exactly once on the first `/sync` after this RFC ships. If the local `## Project Extensions` section has non-placeholder content, the user is prompted with the section's content quoted, given a clear "press Ctrl-C to abort" path, and instructed to copy the content elsewhere before continuing. After the migration, future local edits to `docs/rfc-process.md` are silently overwritten — this is the strategy's defining property and is documented in `docs/CONTRIBUTING.md` and release notes (per the drawback above).

5. **Per-`/sync` token cost for `additive-merge`'s LLM helper.** The helper invokes the agent's underlying model once per (plugin_item, local_item) pair, per section. For `CLAUDE.md` with ten sections averaging seven items per side, that's up to 490 invocations per `/sync` run. With short prompts and short responses, each invocation is a few hundred tokens; the total token spend is bounded but non-zero on every run that classifies `CLAUDE.md` as `additive_merge_apply`.

   **Mitigation:** the cheap pre-check (canonical-form hash equality between plugin and local) short-circuits to `unchanged` whenever the file has not drifted, eliminating all helper invocations for the common case. The cost is paid only when the plugin's template has changed *or* the local file has been edited since the last `/sync`. The agent batches helper invocations across pairs in a single section to amortize prompt overhead.

6. **The diff engine's Step 4b resolution menu gains a new variant for `additive-merge` contradictions.** The existing four-option menu (Adopt / Keep / Merge / Skip) plus the fifth `Adopt plugin and add marker` option (verified: skills/sync/SKILL.md:L408-L415) is now joined by an item-level menu for `additive-merge` contradictions. The two menus have different option sets and different scopes (file-level vs item-level), so they are presented separately. Maintaining two menus in the same step is a documentation burden — the `skills/sync/SKILL.md` body must clearly disambiguate which menu applies when.

   **Mitigation:** the integrated skill body in step 3 of "Exact steps" above explicitly differentiates the two menus in the Step 4b documentation. The implementation can also factor the option-rendering into two named helpers (`render_file_conflict_menu` and `render_item_contradiction_menu`) so the call sites are unambiguous in code. This is a small refactor, not a structural change.

7. **The manifest pre-commit hook does not validate strategy-specific fields.** `build-manifest.sh --check` (verified: .claude-plugin/scripts/build-manifest.sh:L45-L51) verifies that recorded SHAs match source files. It does not check that `additive-merge` entries have `owned_sections`, that `bootstrap` entries omit `owned_sections`/`owned_paths`/`region_end_marker`, or that `authoritative` entries omit `region_end_marker`. A maintainer who edits the manifest by hand and forgets to remove an obsolete field will see no error.

   **Mitigation:** extending the pre-commit check to validate per-strategy field requirements is a small follow-up (out of scope here). The first symptom of a malformed manifest is a runtime error during `/sync` classification dispatch, which is loud and immediate; the manifest is a small file and the strategy fields are easy to inspect manually.

## Relationship to other RFCs

This RFC builds on the per-file marker infrastructure introduced by `2026-05-10-sync-interactive-diff` (Done) and does not depend on or block any other RFC. It supersedes any prior assumption (including in this RFC's earlier draft) that the fix for the `conflict_legacy` loop would be a narrowing of `CLAUDE.md`'s `owned_sections` and a migration to `section`/`region` strategies for `docs/CONTRIBUTING.md` and `docs/ARCHITECTURE.md`. That approach is dropped entirely in favor of the three-strategy model described here.
