---
rfc: "2026-05-14-sync-per-file-extension-strategies"
title: "Sync Per-File Extension Strategies"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-14"
drop_reason: ~
---

## Summary

Move four plugin-managed files — `CLAUDE.md`, `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `docs/rfc-process.md` — onto `extension_strategy` values that correctly partition plugin-owned content from project-owned content. The current state mixes one file already declared `section` whose owned-section list is too aggressive (it claims headings the project has substantially customized), two files declared `whole` that have rich local content the plugin template only stubs out, and one file declared `region` whose project copy never received the `bootstrap-content-version` marker so it still classifies as legacy. All four collide with the diff engine's classification matrix on every `/sync` run and re-surface as `conflict_legacy`; resolving them as "keep local" stamps no marker, so the cycle never terminates (verified: skills/sync/SKILL.md:L429). This RFC narrows what the plugin claims to own in each file, adds a `section`-strategy ownership boundary inside `docs/CONTRIBUTING.md`, replaces the `whole` strategy on `docs/ARCHITECTURE.md` with a thin `region`-strategy header, and confirms `docs/rfc-process.md`'s existing region delimiter is what the diff engine respects. After the change, the **first** `/sync` after the RFC ships classifies all four files as `unchanged_legacy` (content matches plugin canonical form under the new strategies; marker injection only, no body rewrite); the **second** `/sync` classifies them as `unchanged` (marker present, ancestor matches plugin) and the `conflict_legacy` cycle ends.

## Should we do this?

**Yes.** The `conflict_legacy` loop is not a hypothetical: every project that ran `/sync` after the per-file marker system shipped sees these four files re-listed as conflicts on every subsequent run, regardless of whether the user has touched them since. The user's only escape today is to pick "Adopt plugin version" — which overwrites real local content with the plugin's stub — or "Keep local version," which leaves the marker unwritten and guarantees the same prompt next time (verified: skills/sync/SKILL.md:L429). There is no acknowledgment path that lets the user say "the plugin's intended contribution is a strict subset of what's in this file, mark it acknowledged and move on." The fix is to make the manifest tell the truth about what the plugin actually contributes to each file. Once the manifest declares precise ownership, the diff engine's existing `section` and `region` code paths handle the rest correctly — no new strategy types, no new resolution options, no new marker formats. The only new code path is a small first-run marker-injection branch for `region`-strategy files that don't yet carry the region delimiter (`docs/ARCHITECTURE.md`); the branch is invoked once per project and the standard region-strategy path takes over on subsequent runs. The cost is one manifest edit per file, the small diff-engine extension for first-run marker injection, a template rewrite for `ARCHITECTURE.md` so the plugin's region matches what it claims to own, and a `<!-- bootstrap-content-version: ... -->` marker injection on the next `/sync` run.

## Current state

`skills/sync/SKILL.md` defines four `extension_strategy` values — `whole`, `section`, `region`, `structured` — and the diff engine's classification matrix routes every file to one of them at canonicalization time (verified: skills/sync/SKILL.md:L344-L348). The Step 4b resolution menu has exactly four options for `conflict` (plus a fifth `Adopt plugin and add marker` option exclusive to `conflict_legacy`); none of those options offers "keep local content and stamp the marker so we stop asking" for the case where the plugin's intended contribution genuinely does not overlap the local file's content (verified: skills/sync/SKILL.md:L416-L425). The "Keep local version" action explicitly does not update the marker, and the comment immediately after the action description confirms the consequence: "conflict re-surfaces on next run" (verified: skills/sync/SKILL.md:L429).

**The four files and their current manifest declarations** (verified by reading `.claude-plugin/bootstrap-manifest.json`):

| File | Manifest strategy | Manifest `owned_*` (verified excerpt) | Local file (verified) |
|------|---|---|---|
| `CLAUDE.md` | `section` (verified: .claude-plugin/bootstrap-manifest.json:L84) | `owned_sections` lists 10 H2 headings: `## Toolchain`, `## File structure`, `## Agent delegation`, `## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions` (verified: .claude-plugin/bootstrap-manifest.json:L85-L96) | Local has all 10 of those PLUS `## Workflow` (with five subsections including `### Session start`, `### Requirement-check hook`, `### During work`, `### Considering /refactor`, `### Considering /docs-review`, `### Session end`) — none of which are declared plugin-owned. The `## Security` section in the local file is also longer and reads differently from the template body. |
| `docs/CONTRIBUTING.md` | `whole` (verified: .claude-plugin/bootstrap-manifest.json:L176) | No section/region metadata (whole-file strategy) | Local has full project-specific setup (plugin local install, edit cycle, agents pulldown procedure, sync description) — none of which appears in the template. The template only has a generic Prerequisites / Setup / Workflow / Quality Gate / PR Process / RFC Process skeleton with `<PREREQUISITES_SECTION>` and `<INSTALL_COMMAND>` placeholders (verified: .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl). |
| `docs/ARCHITECTURE.md` | `whole` (verified: .claude-plugin/bootstrap-manifest.json:L131) | No section/region metadata (whole-file strategy) | Local has real architecture documentation: Overview, four detailed Components sections, Data Flow, six Design Decisions, an extended note on "Plugin installation scope," and a Dependencies table. The template is placeholder-only — every value is `<...>` (verified: .claude-plugin/scripts/templates/ARCHITECTURE.md.tpl). |
| `docs/rfc-process.md` | `region` (verified: .claude-plugin/bootstrap-manifest.json:L184) with `region_end_marker: "<!-- END_UPSTREAM_CONTENT -->"` (verified: .claude-plugin/bootstrap-manifest.json:L185) | `region_end_marker` boundary correctly delimits where the plugin's upstream ends and project extensions begin | Local has the upstream region (the bulk of the file) plus a `## Project Extensions` section after the `<!-- END_UPSTREAM_CONTENT -->` marker (verified: docs/rfc-process.md:L226-L233). The file does **not** carry a `<!-- bootstrap-content-version: ... -->` marker on line 2; instead it has `<!-- UPSTREAM: ... -->` and `<!-- LAST_SYNCED: ... -->` comments from an earlier marker convention (verified: docs/rfc-process.md:L1-L3). |

**Why each currently classifies as `conflict_legacy`:**

The classification matrix routes any file lacking a `<!-- bootstrap-content-version: ... -->` marker to either `unchanged_legacy` (canonicalized local content matches plugin's canonical content) or `conflict_legacy` (they differ) (verified: skills/sync/SKILL.md:L335-L342). Three of the four files have substantial content the plugin does not ship, so canonicalization-by-strategy returns different bytes on each side and the matrix lands on `conflict_legacy`:

- `CLAUDE.md` — `section`-strategy canonicalization concatenates the bodies of every heading in `owned_sections`. Local includes content under `## Security` that the template body does not; the templated render of `## Toolchain` is `No language-specific toolchain detected. Add source code and re-run /sync to pick up language tooling.` (matches local), but the templated render of `## File structure` includes a Bytewyrd-specific tree (matches local). However, sections like `## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions` are also declared plugin-owned and local body diverges enough on each that canonicalization differs. Net: classify as `conflict_legacy`.
- `docs/CONTRIBUTING.md` — `whole`-strategy canonicalization is the full file content minus the marker line. Local has hundreds of lines of plugin-authoring detail that the template lacks. Always `conflict_legacy`.
- `docs/ARCHITECTURE.md` — same as above with even greater divergence (template is pure placeholders).
- `docs/rfc-process.md` — `region`-strategy canonicalization is the upstream region only (everything up to and including `<!-- END_UPSTREAM_CONTENT -->`), with marker line(s) removed. The plugin's `rfc-process.md` upstream and the local upstream region are byte-identical for the actual upstream content, so technically this file would classify as `unchanged_legacy` rather than `conflict_legacy` — but the resolution path still requires writing a `<!-- bootstrap-content-version: ... -->` marker on the next sync, which is fine; the issue is making sure the diff engine writes that marker without overwriting the `<!-- UPSTREAM: ... -->` / `<!-- LAST_SYNCED: ... -->` comments that are part of the project file's leader.

**The loop:** when the user picks "Keep local version" for any of these, no marker is written. The next `/sync` re-classifies the file with no marker → `conflict_legacy` again. The user is told the same thing every time. This is the exact problem this RFC closes.

## Analysis / Options

Two coupled decisions: (1) the high-level fix shape — change per-file extension strategies vs. add a "keep local and acknowledge" resolution option, and (2) for each affected file, which specific strategy to land on.

### Decision 1 — Strategy refinement vs. acknowledgment path

**Option A — Refine the per-file extension strategy so the plugin's declared ownership matches what it actually contributes (recommended).**

For each affected file, change the manifest entry so the strategy and ownership list precisely match what the plugin's template intends to write. After the change, the diff engine's existing canonicalization rule for the new strategy produces a hash that compares correctly against the local file's same-strategy canonicalization. When the plugin's owned bytes match the local file's same-owned bytes, the file classifies as `fast_forward` with a marker-injection-only delta (the body is unchanged), and the next `/sync` writes the marker and the loop terminates. The "true conflicts" that remain (the plugin's actual contribution diverges from local) become real `conflict` cases the user can resolve properly with the existing four-option menu.

This option requires no changes to the diff engine, no new strategy type, no new resolution option, no new marker format. It is purely a manifest-and-template edit per file. It also pays an architectural dividend: the manifest becomes a precise description of "what the plugin owns in each file" rather than a coarse "plugin owns this whole file" claim that is operationally false for three of the four files.

**Option B — Add a fifth resolution option, "Keep local and mark acknowledged," that stamps the marker without changing content.**

A new option on the Step 4b menu for `conflict_legacy` files: pick "Keep local and mark acknowledged" and the diff engine writes a `<!-- bootstrap-content-version: <upstream_key>:<local_current_canonical_sha> -->` marker into the local file without modifying any body content. The marker's sha is the hash of the local canonical content, so the next `/sync` reads the marker, hashes the (unchanged) local content, and classifies as `local_only` — no prompt.

This works mechanically but has three structural problems:

1. **It papers over a manifest bug rather than fixing it.** The manifest is supposed to be the source of truth for what the plugin owns in each file. If the manifest declares `whole` for `docs/ARCHITECTURE.md` but the plugin in fact owns nothing beyond a placeholder template, the right fix is to make the manifest say "the plugin owns a thin header region," not to teach the diff engine to ignore the lie via a new resolution option.
2. **It propagates forward.** Every future plugin update to one of these files will produce another `conflict_legacy` (the plugin shipped new template content, the local file still doesn't have a bootstrap-content-version marker that matches the new plugin sha) and the user will be re-prompted. The acknowledgment option is a one-shot escape hatch; the cycle would simply restart on the next plugin upgrade.
3. **It makes "marker acknowledged" indistinguishable from "marker stamped after adopting plugin."** Both end up with a `<!-- bootstrap-content-version: ... -->` marker present; the diff engine reads only the marker, not the resolution path that produced it. So an acknowledged file looks identical to an adopted file on the next sync. If the plugin then updates that file, the diff engine has no way to know whether the user "merged the previous plugin version into local content" or "ignored the previous plugin version and just wanted to silence the prompt." That uncertainty bleeds into every subsequent prompt the user sees.

**Recommendation: Option A.** Fix the manifest. The mechanism for partitioning ownership inside a file already exists in the diff engine (the `section` and `region` strategies are implemented and tested for the files that use them); the only work to do is to extend that pattern to the three files where the manifest currently mis-declares ownership. Option B's acknowledgment path is genuinely useful in some edge case where the user knows the plugin's intent will never match their file, but that edge case is rare enough that the right time to add it is after we have established what "real" ownership looks like across the codebase — not before.

**Door stays open on Option B.** Nothing in Option A precludes adding the acknowledgment option later for files where Option A still produces unresolvable conflicts. The two options are not mutually exclusive; they operate at different layers (manifest declarations vs. resolution-time interaction).

### Decision 2 — Per-file strategy choices

**`CLAUDE.md`** — currently `section` with too many owned headings. Narrow `owned_sections` to the three headings the plugin actually templates: `## Toolchain` (rendered from language detection), `## File structure` (rendered with `<project_slug>`), and `## Agent delegation` (rendered from `<AGENT_TABLE_ROWS>`). The other seven currently-declared sections — `## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions` — are stable boilerplate that the local file has heavily customized (the bytewyrd plugin's own checkout is the case in point). Move them to local ownership; the template stops shipping rewrites of those sections.

**`docs/CONTRIBUTING.md`** — currently `whole`. Move to `section`. The plugin contributes exactly two things to a consumer project's CONTRIBUTING: the install hint block (described at `skills/sync/SKILL.md:L658-L669` — "Bytewyrd plugin install hint (always include)") and a Prerequisites section template (rendered from `<PREREQUISITES_SECTION>` per detected language). Everything else in the local file — Development Setup specifics, Quality Gate descriptions for the consumer project, agent pulldown procedure, custom workflows — is owned by the project. Declare the plugin's two contributions as two narrowly-named sections in `owned_sections`, namely `## Prerequisites` and `## Plugin Setup`, where `## Plugin Setup` is the new heading the install hint will live under.

**`docs/ARCHITECTURE.md`** — currently `whole` with a placeholder-only template. Move to `region`. The plugin's contribution is a single thin header region: the H1 `# Architecture`, the scope-comment HTML block immediately following it (the `<!-- ARCHITECTURE scope: ... -->` documentation comment from the template), and a region-end marker `<!-- END_BYTEWYRD_HEADER -->`. The plugin template is rewritten to consist of exactly these three elements, with no placeholder content below the region marker. Local owns everything from `<!-- END_BYTEWYRD_HEADER -->` onward.

**`docs/rfc-process.md`** — already `region` with `region_end_marker: "<!-- END_UPSTREAM_CONTENT -->"`. No change required at the manifest level. The work for this file is to inject the `<!-- bootstrap-content-version: ... -->` marker (line 2) on the next `/sync` so future runs classify it correctly. Per the marker-insertion rule at `skills/sync/SKILL.md:L443`, the marker goes on line 2 — which means the existing `<!-- UPSTREAM: ... -->` comment (current line 1) stays where it is, and the new bootstrap marker is inserted at line 2, pushing the existing `<!-- LAST_SYNCED: ... -->` and other leader comments down by one line. The diff-engine canonicalization for region strategy already accounts for "marker line(s) removed" (verified: skills/sync/SKILL.md:L346).

### Variant considered (and rejected): use `region` for all four files

A consistent shape would be appealing — every file gets the same `region` treatment with a thin plugin header at the top. Rejected because `CLAUDE.md` has three sections the plugin auto-renders from project inputs (`## Toolchain`, `## File structure`, `## Agent delegation`), and those sections are anchored by their H2 headings — they should be updated in place when language detection changes, not relegated to a top-of-file region. `section` strategy correctly handles "this specific heading body is plugin-owned and gets rerendered." Similarly, `CONTRIBUTING.md` has two distinct contributions (Prerequisites, install hint) that the plugin wants to keep current as project languages and plugin install procedures change; `section` strategy is the right semantics. `ARCHITECTURE.md` and `rfc-process.md` are the two files where the plugin's contribution is genuinely a "header preamble" or "upstream body" with everything else being project content, so `region` fits there.

## Drawbacks

1. **Manifest complexity grows.** Three files move from one strategy to a more refined one. The manifest gains two new `section` declarations and one new `region` declaration, and the existing `CLAUDE.md` `section` declaration is rewritten with a narrower `owned_sections` list. Maintainers must keep `owned_sections` and `owned_paths` synchronized with template content as the plugin evolves; if the plugin starts writing a new section that is not declared, that section will not flow to consumer projects on `/sync`.
2. **Section and region boundaries must be maintained going forward.** When a maintainer edits a template under `.claude-plugin/scripts/templates/`, they must respect the ownership boundary declared in the manifest. Adding content outside the owned sections in `CLAUDE.md.tpl` will not propagate to consumers because the diff engine writes only the owned sections. Adding content after `<!-- END_BYTEWYRD_HEADER -->` in `ARCHITECTURE.md.tpl` will be ignored by the diff engine because the region strategy stops at the marker. This requires discipline; `docs/CONTRIBUTING.md` (the plugin's own contributing guide) should document the rule.
3. **One-time migration friction.** The next `/sync` run on any project that has these four files will show them in the legacy-marker-injection category (no prompt — `unchanged_legacy` files are silently re-written with the marker inserted, per `skills/sync/SKILL.md:L463`). For `docs/ARCHITECTURE.md` specifically, the first-run marker-injection branch inserts `<!-- END_BYTEWYRD_HEADER -->` between the header and the body; if the local file's header does not match the plugin's header, the file falls through to `conflict_legacy` and the user resolves it via the standard menu (Adopt / Keep / Merge / Skip / Adopt-and-mark). Either path terminates the loop.
4. **`docs/ARCHITECTURE.md` template loses its placeholder content.** Today the template (`.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl`) ships placeholder values like `<One paragraph describing what the system does...>` and `<Component Name>` that guide the user through filling in a fresh architecture document. After this RFC, the template is reduced to header-only — new projects start with an empty body after the header region and must compose architecture content from scratch. Mitigated by leaving the in-band scope-comment HTML block in the region (`<!-- ARCHITECTURE scope: ... -->`), which already explains what belongs in the document.
5. **Owned-section list ordering matters.** The diff engine's `section`-strategy apply step inserts plugin-owned sections "after the last preceding owned section in manifest order" when a section is absent from the local file (verified: skills/sync/SKILL.md:L456). So manifest `owned_sections` ordering effectively chooses where new plugin-owned sections land in consumer projects. The ordering chosen for `CLAUDE.md` (Toolchain → File structure → Agent delegation) and `CONTRIBUTING.md` (Prerequisites → Plugin Setup) follows the order those sections appear in the plugin's own checkout, which is the order they appear in the templates.

6. **One new code path in the diff engine.** The first-run marker-injection branch for `region`-strategy files lacking `region_end_marker` (the migration for `docs/ARCHITECTURE.md`) is a small addition to the diff-engine pseudocode in `skills/sync/SKILL.md`. The branch is invoked at most once per file per project (after the first `/sync` succeeds, the file has the marker and the standard region path takes over). The branch's heuristic — split at the first H2 heading — is project-agnostic and has no language- or framework-specific assumptions, but adds a small amount of new logic the maintainer must keep in mind when changing canonicalization rules in the future.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `.claude-plugin/bootstrap-manifest.json` | Change four artifact declarations: narrow `CLAUDE.md` `owned_sections` to three entries; change `docs/CONTRIBUTING.md` from `whole` to `section` with two owned entries; change `docs/ARCHITECTURE.md` from `whole` to `region` with a new `region_end_marker`; leave `docs/rfc-process.md` unchanged. |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | Remove the body of the seven sections that are no longer plugin-owned (`## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions`). The headings remain in the template only as in-line documentation — they are not part of the plugin's contribution. |
| Modify | `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` | Restructure to two plugin-owned sections (`## Prerequisites` and `## Plugin Setup`) with body content; move the install hint into `## Plugin Setup`. Remove everything that is not part of those two sections (Development Setup, Development Workflow, Commit Conventions, Quality Gate, Pull Request Process, RFC Process) — these are now project-owned. |
| Modify | `.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl` | Rewrite as a thin header: the H1 `# Architecture`, the existing scope-comment HTML block, then a new `<!-- END_BYTEWYRD_HEADER -->` marker line. Remove all placeholder sections (`## Overview`, `## Components`, etc.). |
| Modify | `skills/sync/SKILL.md` | (a) Confirm the diff-engine canonicalization rules for `section` and `region` already match what this RFC needs (they do — verified at L344-L348). (b) Add a short note in the "Apply actions" section explaining that the bootstrap marker for `region`-strategy markdown files is inserted as line 2, ahead of any existing leader comments that the file may carry (e.g., the `<!-- UPSTREAM: ... -->` comment on `docs/rfc-process.md`). The note clarifies what was already implicit in the rule at L443 ("insert ... as line 2"). (c) Add a "First-run marker injection for region strategy" sub-section under the canonicalization rules block that documents the heuristic described in "First-run migration: injecting the `<!-- END_BYTEWYRD_HEADER -->` marker" below — this is the one new code path the RFC introduces. |
| Add | (none) | No new files. No new strategy types. One new code path (the first-run marker-injection branch for `region`-strategy files lacking `region_end_marker`) lives inside `skills/sync/SKILL.md`'s existing diff-engine pseudocode. |

### Exact manifest changes

The full diff against the current `.claude-plugin/bootstrap-manifest.json`:

**1. `CLAUDE.md` — narrow `owned_sections`.**

Replace the existing entry's `owned_sections` array (currently 10 entries, lines 85-96 in the manifest) with three entries:

```json
"owned_sections": [
  "## Toolchain",
  "## File structure",
  "## Agent delegation"
]
```

The `extension_strategy: "section"`, `templated: true`, `template_inputs`, `target`, `source`, and `upstream_key` fields are unchanged. The `template_sha` field is recomputed by `build-manifest.sh` after the template body change.

**2. `docs/CONTRIBUTING.md` — move from `whole` to `section`.**

Replace the existing entry (currently lines 172-178 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/CONTRIBUTING.md@v1",
  "source": ".claude-plugin/scripts/templates/CONTRIBUTING.md.tpl",
  "target": "docs/CONTRIBUTING.md",
  "template_sha": "",
  "extension_strategy": "section",
  "owned_sections": [
    "## Prerequisites",
    "## Plugin Setup"
  ],
  "templated": true,
  "template_inputs": [
    "languages",
    "component_roots"
  ]
}
```

Two behavioral changes: (a) `templated` flips from `false` to `true` because Prerequisites content depends on detected languages (the existing template already uses `<PREREQUISITES_SECTION>` and `<INSTALL_COMMAND>` placeholders, verified: `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L16,L23`). The previous `sha256` field is replaced with a `template_sha` placeholder that `build-manifest.sh` populates from the rewritten template. (b) `template_inputs` is added per the manifest schema convention used by other templated entries.

**3. `docs/ARCHITECTURE.md` — move from `whole` to `region`.**

Replace the existing entry (currently lines 127-133 in the manifest) with:

```json
{
  "upstream_key": "bytewyrd/docs/ARCHITECTURE.md@v1",
  "source": ".claude-plugin/scripts/templates/ARCHITECTURE.md.tpl",
  "target": "docs/ARCHITECTURE.md",
  "sha256": "",
  "extension_strategy": "region",
  "region_end_marker": "<!-- END_BYTEWYRD_HEADER -->",
  "templated": false
}
```

`templated` stays `false` (the template is plain text — no placeholder substitution needed for the header). The `sha256` placeholder is filled by `build-manifest.sh`.

**4. `docs/rfc-process.md` — no manifest change.**

The existing entry already declares `extension_strategy: "region"` and `region_end_marker: "<!-- END_UPSTREAM_CONTENT -->"`. The fix for this file is purely a marker-injection on the next `/sync` run (the diff engine's existing region-strategy apply step writes the `<!-- bootstrap-content-version: ... -->` marker as line 2 per the marker-insertion rule at `skills/sync/SKILL.md:L443`). No manifest edit required.

### Exact template changes

**`.claude-plugin/scripts/templates/CLAUDE.md.tpl` — narrow to three owned sections.**

The new template file content, in full:

````markdown
# <project_name>

<description>

## Toolchain

<LANGUAGE_TOOLCHAIN_SECTION>

## File structure

```
<project_slug>/
├── CLAUDE.md          — this file
├── docs/
│   ├── ARCHITECTURE.md        — system design (devs/agents)
│   ├── BEST_PRACTICES.md      — session learnings (devs/agents)
│   ├── CONTRIBUTING.md        — dev workflow (devs/agents)
│   ├── project-brief.md       — what/why/who (optional)
│   ├── guide/                 — expanded user documentation
│   └── rfcs/                  — RFC proposals
└── src/               — source code
```

## Agent delegation

| Task | Agent |
|------|-------|
<AGENT_TABLE_ROWS>
````

All seven previously-shipped sections (`## Tool Usage`, `## RFC Process`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions`) are removed from the template. The plugin no longer contributes any body content for those headings; consumer projects compose them locally.

The `<TOOL_USAGE_SECTION>` rendering branch in `skills/sync/SKILL.md` (the section that conditionally builds the tool-usage table based on installed companion plugins, verified at `skills/sync/SKILL.md:L590`) becomes dead code with respect to `CLAUDE.md`. Two ways to handle the dead code: (a) leave it in place and unreferenced — the placeholder substitution is a no-op when the placeholder is absent from the template (per the template rendering rule at `skills/sync/SKILL.md:L440`: "Unrecognized placeholders are replaced with empty string"); (b) delete the rendering branch entirely in a follow-up cleanup PR. Choose (a) — the rendering rule's "unrecognized → empty string" semantics make this safe and the cleanup can land separately without coupling to this RFC.

**`.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` — restructure to two owned sections.**

The new template file content, in full:

````markdown
<!--
CONTRIBUTING scope: everything a developer needs to work on this project.
  - Prerequisites or tool versions change
  - Setup steps change
  - Dev workflow or branching conventions change
  - Quality gate commands change
  - PR or RFC process changes

Not here: what the project does or its architecture → README.md / docs/ARCHITECTURE.md
-->

# Contributing

## Prerequisites

<PREREQUISITES_SECTION>

## Plugin Setup

This project uses the [Bytewyrd Claude Code plugin](https://github.com/bytewyrd/claude-bytewyrd) for its dev workflow. Install once per machine (user scope; no per-project install needed):

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
```

The plugin's `SessionStart` hook will warn you if any required companion plugins or MCP servers are missing in this project — follow the printed fix command for each.
````

The body of `## Prerequisites` is the `<PREREQUISITES_SECTION>` placeholder rendered per the existing language-detection rule in `skills/sync/SKILL.md` (the rule for `<PREREQUISITES_SECTION>` lives at `skills/sync/SKILL.md:L656`). `## Plugin Setup` is the install-hint block previously inserted by the rendering step at `skills/sync/SKILL.md:L658-L669` — that step is now redundant because the install hint lives in the template under its own owned section. The CONTRIBUTING.md rendering step in the sync skill (the body that previously inserted the install hint into the rendered file) can be simplified in a follow-up to remove the manual insertion logic; for this RFC, the template-side ownership is sufficient because `section`-strategy canonicalization extracts only the named sections and the install hint is now stably positioned inside `## Plugin Setup`. The legacy `## Development Setup`, `## Development Workflow`, `## Commit Conventions`, `## Quality Gate`, `## Pull Request Process`, `## RFC Process` sections — and their `<INSTALL_COMMAND>` and `<QUALITY_GATE_DESCRIPTION>` placeholders — are removed from the template body. Consumer projects compose those sections locally (the bytewyrd plugin's own `docs/CONTRIBUTING.md` is the canonical example; it has all of those plus several plugin-specific subsections, verified: docs/CONTRIBUTING.md).

**`.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl` — reduce to header region.**

The new template file content, in full:

```markdown
# Architecture

<!--
ARCHITECTURE scope: system design reference — the "how and why it's built this way."
  - A component is added, renamed, or removed
  - A significant design decision is made or reversed (update the Decisions table)
  - Data flow between components changes
  - A new external dependency or service is introduced

Not here: setup/quickstart                   → README.md
          dev workflow, commit conventions   → docs/CONTRIBUTING.md
          non-obvious session learnings      → docs/BEST_PRACTICES.md
-->

<!-- END_BYTEWYRD_HEADER -->
```

All placeholder sections (`## Overview`, `## Components`, `## Data Flow`, `## Design Decisions`, `## Dependencies`) are removed. Consumer projects start with an empty body below the marker and compose architecture content from scratch — the bytewyrd plugin's own `docs/ARCHITECTURE.md` is the canonical example of what a filled-in body looks like.

### Diff-engine and apply-step behavior (mostly verification; one new code path)

The diff engine and apply step already handle the new strategy values correctly for the steady state — the one exception (a first-run migration for `docs/ARCHITECTURE.md`) is described in its own sub-section below. The existing canonicalization and apply rules:

**Canonicalization rules** (verified: skills/sync/SKILL.md:L344-L348):

- `section`: extracts each heading in `owned_sections` (manifest order), concatenates `heading\n + body + \n` for each. After the change, `CLAUDE.md`'s canonical form is the concatenation of three sections; `docs/CONTRIBUTING.md`'s is the concatenation of two sections. The plugin's canonical-form hash and the local file's canonical-form hash are byte-equal when those specific sections agree, which is the case in the bytewyrd plugin's own checkout for the narrowed list.
- `region`: file content from line 1 up to and including `region_end_marker`, with the marker line(s) removed. After the change, `docs/ARCHITECTURE.md`'s canonical form is the H1 + scope comment + region-end marker (with the bootstrap-content-version marker removed during canonicalization). `docs/rfc-process.md`'s canonical form is unchanged — the upstream region from line 1 to `<!-- END_UPSTREAM_CONTENT -->`, with marker line(s) removed.

**Apply actions** (verified: skills/sync/SKILL.md:L450-L466):

- `section` (fast-forward case): for each heading in `owned_sections`, replace the section body in the local file with the plugin's rendered body for that section. Preserve all other sections. If a plugin-owned section is absent from the local file, insert it after the last preceding owned section in manifest order. Reserialize: marker on line 2, then sections in their preserved relative order. After the RFC: `CLAUDE.md`'s `## Toolchain`, `## File structure`, and `## Agent delegation` bodies are written; all other headings (including `## Workflow` and its subsections, `## Tool Usage`, `## Security`, etc.) are preserved byte-for-byte from the local file. `docs/CONTRIBUTING.md`'s `## Prerequisites` and `## Plugin Setup` bodies are written; all other content (Development Setup, Workflow, Quality Gate, agent pulldown procedure) is preserved.
- `region` (fast-forward case): replace the upstream region (everything up to and including `region_end_marker`) with the plugin's rendered upstream region; preserve the project-extension region (everything after `region_end_marker`) byte-for-byte. After the RFC: `docs/ARCHITECTURE.md`'s region (H1 + scope comment + `<!-- END_BYTEWYRD_HEADER -->`) is written; everything from `<!-- END_BYTEWYRD_HEADER -->` onward in the local file is preserved. `docs/rfc-process.md`'s region (up to and including `<!-- END_UPSTREAM_CONTENT -->`) is written; the `## Project Extensions` section after the marker is preserved.

**Marker insertion rule** (verified: skills/sync/SKILL.md:L443):

"Markdown (`.md`): insert `<!-- bootstrap-content-version: <upstream_key>:<sha12> -->` as line 2 (after the first line of the file)."

For region-strategy files, this means the marker is inserted as line 2 of the final written file — between the H1 (`# Architecture`) and the scope-comment HTML block. For `docs/rfc-process.md`, the marker is inserted as line 2 — between the existing line-1 `<!-- UPSTREAM: ... -->` comment and the line-2 `<!-- LAST_SYNCED: ... -->` comment. The canonicalization rule's "with marker line(s) removed" clause means the marker is not part of the hash input, so subsequent /sync runs read past it cleanly.

**The marker format is unchanged.** The same `<!-- bootstrap-content-version: <upstream_key>:<sha12> -->` form is used for `whole`, `section`, and `region` strategies on markdown files. Section and region delimiters (`<!-- END_BYTEWYRD_HEADER -->`, `<!-- END_UPSTREAM_CONTENT -->`, and the `##` headings themselves) are separate inline boundary markers, not file-level marker lines. The structured (JSON) strategy keeps its sidecar marker; nothing in the JSON path changes.

### First-run migration: injecting the `<!-- END_BYTEWYRD_HEADER -->` marker into `docs/ARCHITECTURE.md`

This RFC introduces a new region delimiter (`<!-- END_BYTEWYRD_HEADER -->`) to `docs/ARCHITECTURE.md`. The diff engine's `region`-strategy canonicalization rule reads "file content from line 1 up to and including `region_end_marker`" (verified: skills/sync/SKILL.md:L346) — which requires the marker to exist in the local file to produce a canonical form. Projects that ran `/sync` before this RFC have local `docs/ARCHITECTURE.md` files that do *not* contain `<!-- END_BYTEWYRD_HEADER -->`; the diff engine cannot canonicalize them under the new strategy without first injecting the marker. (For `docs/rfc-process.md`, the marker `<!-- END_UPSTREAM_CONTENT -->` is already present in local files because `/rfc-update` or earlier `/sync` runs put it there, so this migration is not needed for that file.)

The migration is handled by extending the diff engine with a one-time "marker injection" path that triggers when:

1. The artifact's `extension_strategy` is `region`
2. The local file does not contain `region_end_marker`
3. The local file's content up to a heuristic split point (described below) matches the plugin's pre-marker header bytes-for-bytes after trimming

The heuristic split point: scan the local file for the first H2 heading (`^## ` at the start of a line). The bytes before that heading are the file's "header region"; the bytes from that heading onward are the "body region". For a `docs/ARCHITECTURE.md` that contains `# Architecture` + scope-comment HTML + `## Overview ...`, the split point is the line index of `## Overview`. The migration:

1. Read the local file.
2. Compute `local_header_bytes` = file content up to (but not including) the first H2 heading line.
3. Compute `plugin_header_bytes` = the plugin's canonical region content with the bootstrap marker removed and the `<!-- END_BYTEWYRD_HEADER -->` marker removed.
4. If `local_header_bytes` (after stripping trailing blank lines) equals `plugin_header_bytes` (after stripping trailing blank lines), the local file's header matches the plugin's header. Write the migrated file: plugin header + `\n<!-- bootstrap-content-version: ... -->\n` + `\n<!-- END_BYTEWYRD_HEADER -->\n` + `local_body_bytes` (the bytes from the first H2 heading onward). Classify as `unchanged_legacy` and silently complete.
5. If the local header does *not* match the plugin's header, classify as `conflict_legacy` and present the standard resolution menu (Adopt / Keep / Merge / Skip / Adopt-and-mark).

This migration is encoded in the diff engine as an additional canonicalization-and-classification branch that runs *before* the standard region-strategy classification when the local file lacks `region_end_marker`. The migration runs exactly once per file per project (after the first `/sync`, the local file has the marker and the standard region-strategy path applies on every subsequent run).

This adds one branch to the diff engine's region-strategy handling — a small but non-zero code change. It is the minimum work required to migrate existing projects without forcing users to manually edit `docs/ARCHITECTURE.md` themselves. The branch's heuristic ("first H2 heading is the body start") is sufficient for the current local files of every consumer project that has run `/sync` before this RFC (each such project's `docs/ARCHITECTURE.md` is either the placeholder template, which has `## Overview` as the first H2, or a customized version that has at least one H2 below the scope-comment HTML block).

### Exact steps

1. **Edit the manifest.** Open `.claude-plugin/bootstrap-manifest.json`. Apply the four manifest changes listed under "Exact manifest changes" above. After editing, the `template_sha` (for `CLAUDE.md` and `docs/CONTRIBUTING.md`) and `sha256` (for `docs/ARCHITECTURE.md`) fields will be placeholder values; they are recomputed by step 5.

2. **Rewrite the three templates.** Replace the body of `.claude-plugin/scripts/templates/CLAUDE.md.tpl` with the new content under "Exact template changes — CLAUDE.md.tpl" above. Replace `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` similarly. Replace `.claude-plugin/scripts/templates/ARCHITECTURE.md.tpl` similarly.

3. **Add the documentation note to skills/sync/SKILL.md.** Append the following sentence to the existing "Marker insertion rule" block (just after the bullet for `JSON files: do **not** embed a marker in the file.` at L447):

   > For region-strategy markdown files that carry pre-existing leader comments (e.g., `docs/rfc-process.md`'s `<!-- UPSTREAM: ... -->` comment), the bootstrap marker is inserted as line 2 ahead of those comments — line 1 stays as the file's H1 or first leader comment, the new bootstrap marker becomes line 2, and any previous line-2-or-later comments shift down by one line.

4. **Regenerate the manifest.** Run `.claude-plugin/scripts/build-manifest.sh` from the repo root. The script walks the manifest, recomputes the `sha256` or `template_sha` for each artifact's source file, and writes back a sorted, pretty-printed manifest (verified: `.claude-plugin/scripts/build-manifest.sh:L28-L43`). Expected stdout: `Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/.claude-plugin/bootstrap-manifest.json`. Expected exit code: `0`.

5. **Verify the manifest passes the pre-commit check.** Run `.claude-plugin/scripts/build-manifest.sh --check`. Expected exit code: `0` (no diff). If the check fails, return to step 4 and re-run regeneration.

6. **Run `/sync` in a consumer project (smoke test).** From a consumer project that already has the four affected files (the bytewyrd plugin's own checkout is the canonical case; the worktree at `/home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-sync-section-ownership/` is itself a valid consumer project for the plugin), invoke `/sync`. Expected classification per file on the **first** run after this RFC ships (per the matrix at `skills/sync/SKILL.md:L335-L342`):

   - `CLAUDE.md` → **unchanged_legacy** — the marker is absent, and `section`-strategy canonicalization on the narrowed three-section list (`## Toolchain`, `## File structure`, `## Agent delegation`) matches the plugin's canonical form. Per `skills/sync/SKILL.md:L463`, `unchanged_legacy` files are silently re-written with the marker inserted (no content change).
   - `docs/CONTRIBUTING.md` → **unchanged_legacy** when the local `## Prerequisites` and `## Plugin Setup` bodies match the plugin's canonical content; falls back to **conflict_legacy** only if those two sections diverge from plugin canonical content (e.g., a project that customized the install hint wording).
   - `docs/ARCHITECTURE.md` → **unchanged_legacy** via the first-run marker-injection branch (the local file lacks `<!-- END_BYTEWYRD_HEADER -->`; the migration branch finds the local header bytes match the plugin's pre-marker header bytes and writes the migrated file with the marker injected between the header and the body). Falls back to **conflict_legacy** only if the H1 or scope-comment was edited locally. (Editing the scope-comment is unusual — projects typically don't touch it.)
   - `docs/rfc-process.md` → **unchanged_legacy** — the upstream region matches between plugin and local (because `/sync` and `/rfc-update` already kept it in sync today).

   Expected stdout summary section: a `Legacy marker injection (4 files, content matches — adding version marker only)` block listing the four files, per the format at `skills/sync/SKILL.md:L365-L366`. The terminology `fast_forward` from this RFC's Summary applies to **subsequent** plugin upgrades after the markers are stamped — at that point, an updated plugin canonical form vs an unchanged local file classifies as `fast_forward` rather than `unchanged_legacy`.

7. **Verify the markers were written.** After the `/sync` run, check each file:

   ```bash
   sed -n '2p' CLAUDE.md docs/CONTRIBUTING.md docs/ARCHITECTURE.md docs/rfc-process.md
   ```

   Expected: each file's line 2 is a `<!-- bootstrap-content-version: <upstream_key>:<sha12> -->` comment matching the plugin's canonical-form SHA.

8. **Run `/sync` again (idempotence check).** Invoke `/sync` a second time. Expected stdout: `Everything is up to date.` per `skills/sync/SKILL.md:L376`. No prompts, no resolutions, no per-file output.

### Verification commands

After step 8 succeeds, the four files are no longer in the `conflict_legacy` cycle. The diff engine sees each carrying a bootstrap-content-version marker on line 2, hashes the local canonical content against the marker's recorded `local_ancestor_sha`, finds them equal, and classifies as `unchanged` (verified: skills/sync/SKILL.md:L337). The cycle terminates permanently — until the plugin ships a future update to one of the four files, in which case the diff engine classifies as `fast_forward` and the user gets the standard four-option resolution flow on real divergence.

## Risks and open questions

1. **Local section name collides with a plugin section name added in a future plugin version.** A consumer project has authored a local `## Tool Usage` section in `CLAUDE.md` (which is currently project-owned per this RFC). A future plugin version adds `## Tool Usage` back to `owned_sections` to start managing tool docs centrally. On the next `/sync`, the diff engine's `section`-strategy apply step replaces the local body with the plugin's body — overwriting the user's local content silently.

   **Mitigation (convention):** Sections appearing in the manifest's `owned_sections` list are plugin-owned. Any section name *not* listed is local-owned. The convention is one-directional: a maintainer adding a new plugin-owned section must (a) add it to `owned_sections` in the manifest, and (b) treat the addition as a breaking change to the file's contract — bump the `upstream_key` (e.g., from `bytewyrd/CLAUDE.md@v1` to `bytewyrd/CLAUDE.md@v2`) so the diff engine treats the file as a fresh artifact. The `@v2` reset means the `local_ancestor_sha` lookup misses (the local marker says `@v1:...`, the plugin says `@v2:...`); the file classifies as `unchanged_legacy` or `conflict_legacy` and the user is prompted explicitly. This is the same mechanism the existing manifest schema uses to handle versioning (every `upstream_key` ends with `@v1` today; bumping to `@v2` is the documented escape hatch).

   This mitigation is not foolproof — a maintainer who forgets the `upstream_key` bump will still cause silent overwrites — so the manifest pre-commit hook (`build-manifest.sh --check`, verified: `.claude-plugin/hooks/pre-commit/manifest-check.sh`) should be extended to fail when an existing `upstream_key`'s `owned_sections` list adds a new entry without an `upstream_key` bump. Implementation of that pre-commit check is a small follow-up; not part of this RFC's scope.

2. **The narrow ownership list for `CLAUDE.md` produces an unhelpful template for new projects.** A user runs `/sync` in a brand-new project that has no `CLAUDE.md`. The plugin writes a file containing only `## Toolchain`, `## File structure`, and `## Agent delegation` — none of the boilerplate sections (`## Tool Usage`, `## RFC Process`, `## Security`, etc.) that were previously shipped. The new project starts with a minimal CLAUDE.md and the user must compose all the other sections by hand.

   **Mitigation:** the boilerplate sections that have been removed from the template *are* in the bytewyrd plugin's own `CLAUDE.md` checkout, which is structurally identical to what a new consumer project would want. A follow-up RFC may introduce a separate "seed pack" of project-owned sections that `/sync` offers to install on first run (with a single `Yes / Skip` prompt), but that is a separate concern. For now, the trade-off is that the plugin stops re-rendering sections it doesn't auto-template, at the cost of new projects starting with less prefilled boilerplate. This is consistent with the RFC's stated principle: the plugin owns what it generates, not what it merely templated once.

3. **`docs/rfc-process.md`'s existing `<!-- UPSTREAM: ... -->` and `<!-- LAST_SYNCED: ... -->` leader comments interact with the bootstrap marker injection.** The marker-insertion rule says "insert as line 2" (verified: skills/sync/SKILL.md:L443). On the next `/sync`, the diff engine inserts `<!-- bootstrap-content-version: ... -->` as line 2 between `<!-- UPSTREAM: ... -->` (line 1) and `<!-- LAST_SYNCED: ... -->` (current line 2, will become line 3). The result is structurally fine — three leader comments instead of two, all valid HTML — but worth confirming.

   **Resolution:** the canonicalization rule for `region` strategy says "with the marker line(s) removed" (verified: skills/sync/SKILL.md:L346). The plural "line(s)" reads as covering both the bootstrap-content-version marker and any other comment lines that are part of the file's marker-leader. Step 3 of "Exact steps" above adds documentation to `skills/sync/SKILL.md` confirming this interpretation. If a future refactor of the canonicalization rule wants to be strict and remove only the `bootstrap-content-version` line, a separate one-time migration step would be needed to either remove the legacy `<!-- UPSTREAM: ... -->` and `<!-- LAST_SYNCED: ... -->` comments or fold them into a non-canonicalized region of the file. That migration is not part of this RFC.

4. **The `## Plugin Setup` section name in `CONTRIBUTING.md` differs from the wording in the existing local file (which has `## Plugin Setup (one-time)`).** The plugin's new ownership claim is `## Plugin Setup` (without the parenthetical). On the first `/sync` after this RFC, the diff engine's `section`-strategy apply step will look for `## Plugin Setup` in the local file. If the local file uses a slightly different heading (`## Plugin Setup (one-time)`), the engine treats the plugin's section as absent and inserts it as a new section.

   **Resolution (in scope of this RFC):** the bytewyrd plugin's own checkout has `## Plugin Setup (one-time)` (verified: docs/CONTRIBUTING.md:L25). The next `/sync` on the plugin's own checkout will insert a new `## Plugin Setup` section ahead of the existing `## Plugin Setup (one-time)` section. The duplication is a one-time cleanup the maintainer resolves by renaming the local heading from `## Plugin Setup (one-time)` to `## Plugin Setup` and merging the two bodies. Consumer projects that already have the install hint under a heading other than `## Plugin Setup` will see similar duplication and resolve it manually. The choice of heading name in the manifest (`## Plugin Setup`, without the parenthetical) is deliberate: it is the cleanest exact-string match for both the heading name in `skills/sync/SKILL.md`'s install-hint description and a reasonable section heading for a consumer project.

5. **Manifest pre-commit hook may need updating.** The current `build-manifest.sh --check` (verified: `.claude-plugin/hooks/pre-commit/manifest-check.sh`) verifies that the manifest's recorded `sha256`/`template_sha` values match the actual source file content. It does not validate `owned_sections` against the template body, so a maintainer who forgets to update `owned_sections` when adding a new section to a template will see no error from the hook. The mitigation in risk 1 above proposes a follow-up extension of this check; outside this RFC's scope.

## Relationship to other RFCs

None currently. This RFC builds on the per-file marker infrastructure introduced by `2026-05-10-sync-interactive-diff` (Done) but does not depend on or block any other RFC.
