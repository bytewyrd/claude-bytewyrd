---
rfc: "2026-05-10-sync-interactive-diff"
title: "Make /sync Interactive: Diff Plugin vs Local, Confirm Changes"
author: "Rodrigo Kochenburger"
status: "Approved"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Replace `/sync`'s current silent-skip-if-exists behavior with a deterministic three-way diff against a tracked plugin-content baseline, then present a categorized summary of pending changes to the user for explicit confirmation before any file is written. Each plugin-managed artifact (skills, agents, docs templates, CI workflows, hooks blocks, best-practice entries) carries an `upstream-key` and a `bootstrap-content-version` marker; on every `/sync` run, the skill classifies each artifact into one of five outcomes — **unchanged**, **add** (file does not exist), **fast-forward update** (local matches the previously-synced version, plugin version differs), **conflict** (local diverged from previously-synced version *and* plugin version also differs), or **local-only** (file present locally but absent in plugin — never touched) — and asks the user to approve in batched AskUserQuestion calls (one batch for non-conflicting changes, then one conflict at a time). Project-local extensions (RFC `## Project Extensions`, CLAUDE.md custom sections, settings.json append-only hooks/permissions, BEST_PRACTICES.md `## Project-Specific` section) are preserved structurally — they live in named regions that the diff engine identifies and never overwrites.

## Should we do this?

**Yes.** The current `/sync` skill has a documented "idempotent, safe to re-run" property that, in practice, is silently broken: once a file exists, sync never overwrites it (except the brief-driven name/description sync and append-only `.gitignore` / `settings.local.json` entries). That means every improvement the plugin ships — a new best-practice entry, a tightened CI workflow, a clarified prompt in CLAUDE.md, a new hook in settings.json, an updated rfc-process.md core — only reaches *new* projects; existing projects stay frozen at whatever version of the plugin first set them up. The asymmetry has compounded: `docs/rfc-process.md` is partly addressed today (the rfc-update sub-step diffs upstream against the core region while preserving `## Project Extensions`), but every other artifact is stuck.

A three-way diff with categorized confirmation solves all four faces of the problem in one mechanism: (1) existing projects pull forward improvements they would otherwise miss, (2) the user sees and approves every change before it lands instead of trusting "skipped" reports they cannot verify, (3) project-local edits to plugin-managed files are protected by the conflict path rather than silently overwritten, and (4) the operation stays idempotent because the baseline marker advances only when an update is applied, so re-running on a fully-up-to-date repo is a no-op that confirms zero pending changes. The cost is a meaningful skill-body rewrite plus per-artifact upstream-key metadata, but the alternative — telling users "re-run /sync" while knowing it does nothing for their already-initialized repo — is a worse and growing problem.

## Current state

`skills/sync/SKILL.md` (1445 lines) currently classifies every file it touches into one of three behaviors, declared in Step 5's "File creation policy" block and applied throughout Steps 5–7:

1. **Skip-if-exists (the vast majority).** For `CLAUDE.md`, `README.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `.claude/settings.json`, `.claude/settings.local.json` (initial creation), `rust-toolchain.toml`, `mise.toml`, every `.github/` template, every `.github/workflows/*.yml`, and every `.github/ISSUE_TEMPLATE/*.md` — sync checks whether the file exists. If yes, it is skipped and reported as `skipped (exists)`. If no, it is created from the embedded template.

2. **Always-overwrite name/description (two specific edits).** For `CLAUDE.md` line 1 (H1) and the description paragraph directly below it, and `README.md` line 1 (H1) and the line-3 blockquote, sync always rewrites if the value differs from `project_name` / `description` resolved in Step 2. This is the only inline edit applied to an existing file outside the append-only rules. Source of truth is `docs/project-brief.md` (per RFC `2026-05-10-project-brief-sync-source-of-truth`).

3. **Append-only.** For `.gitignore` and `.claude/settings.local.json`, sync reads the existing file and appends only entries not already present. Never removes. The `mise.toml` block has the same append-only rule.

There is one **partial exception** in Step 7: `docs/rfc-process.md` is the only file that already implements a primitive three-way merge. The file carries a `<!-- UPSTREAM: ... -->` / `<!-- END_UPSTREAM_CONTENT -->` marker pair; on `/sync` (and on `/rfc-update`), the core section before `END_UPSTREAM_CONTENT` is replaced verbatim from `$PLUGIN_ROOT/rfc-process.md`, and the `## Project Extensions` section after the marker is preserved untouched. There is no conflict detection — if the user edits the core section, those edits are silently lost. There is also no version pin: the comparison is "current upstream vs current local core," not "current upstream vs the version of upstream the local was originally synced from."

The plugin already carries one piece of metadata that points toward the right model: `<!-- bootstrap-content-version: 2026-05-10-f7d5384 -->` appears twice in `skills/sync/SKILL.md` (line 6 and line 509 — the latter inside the embedded `docs/BEST_PRACTICES.md` template). The marker identifies what "version" of the embedded content `/sync` will write, but nothing currently reads it back to detect whether a synced file is up to date. The marker is also not propagated to most of the files sync writes — `CLAUDE.md`, `README.md`, `docs/CONTRIBUTING.md`, `docs/ARCHITECTURE.md`, `.claude/settings.json`, and the `.github/` templates have no version stamp at all.

**What this means for the user, today:**

- A user who ran `/sync` six months ago and runs it again today gets a report listing every file as `skipped (exists)`. The plugin has shipped multiple improvements in those six months — new best-practice entries, a refined hook for post-commit reminders, an updated agent delegation table, the CI workflow split into language-specific jobs — and none of them reach the project. The report is technically truthful (the files do exist) and operationally useless (nothing tells the user *what* they are missing).
- The `/rfc-update` skill is the only path that catches users up on one specific file (`docs/rfc-process.md`). Every other artifact remains stuck at the version that was first written.
- A user who edited the core of `docs/rfc-process.md` (assuming they wanted to customize the process for their project but did not realize the `## Project Extensions` section is the supported extension point) loses those edits silently the next time `/rfc-update` or `/sync` runs.
- Users have no way to selectively pull forward improvements. The only options today are "re-run /sync (gets nothing)" or "delete the file and re-run /sync (loses local edits)."

**Existing structural hooks the new design will reuse:**

- The `bootstrap-content-version` marker pattern — promote it to a per-artifact ancestor identifier instead of a single global version.
- The `END_UPSTREAM_CONTENT` boundary marker on `docs/rfc-process.md` — generalize the "upstream region vs project-extension region" split to other files where it applies (`CLAUDE.md`, `docs/BEST_PRACTICES.md`).
- The append-only rules for `.gitignore` / `.claude/settings.local.json` / `mise.toml` — fold these into the new diff engine as a structural-merge strategy, rather than treating them as a separate code path.
- AskUserQuestion as the confirmation channel — every existing interactive step in `/sync` uses it; the new design batches differently but does not introduce a new interaction primitive.

## Analysis / Options

Three coupled decisions: (1) how to detect that a local file has diverged from what the plugin originally shipped, (2) how to preserve project-local extensions inside otherwise-plugin-managed files, and (3) how to surface the categorized result to the user without overwhelming them with per-file prompts.

### Decision 1 — How does `/sync` know whether a local file matches what the plugin originally shipped?

**Option A — Per-artifact `bootstrap-content-version` markers as a content-derived hash (recommended).**

Every plugin-managed artifact gets an explicit `upstream-key` (a stable string identifier for what the file is — e.g. `bytewyrd/CLAUDE.md@v1`, `bytewyrd/rfc-process.md`, `bytewyrd/BEST_PRACTICES.md`, `bytewyrd/.github/workflows/ci.yml/rust-job`) and the plugin tracks the *current* canonical content for each key in a manifest at `.claude-plugin/bootstrap-manifest.json`. When `/sync` writes (or rewrites) a file, it embeds a `<!-- bootstrap-content-version: <key>:<sha256-12> -->` HTML comment on the second line of the file, where `<sha256-12>` is the first 12 hex chars of the SHA-256 of the canonical content the plugin wrote. The plugin manifest contains the full key-to-current-sha mapping for the shipped version of the plugin.

On re-run, the diff engine for each artifact:
1. Reads the local file (if present) and extracts its `bootstrap-content-version` marker — call this `local_ancestor_sha`.
2. Hashes the local file's canonical-form content (marker line removed, user-owned regions excluded — see Implementation spec) → `local_current_canonical_sha`.
3. Renders the plugin's template (or reads the plugin source for non-templated artifacts) with the consumer's current `project_inputs`, canonicalizes the same way, and hashes → `plugin_current_canonical_sha`.
4. Classifies into one of the five outcomes (see "Classification matrix" in Implementation spec):
   - File absent → **add**
   - `local_ancestor_sha == plugin_current_canonical_sha` → **unchanged** (already at the version the plugin would write right now)
   - `local_current_canonical_sha == local_ancestor_sha` and `plugin_current_canonical_sha != local_ancestor_sha` → **fast-forward update** (user has not edited owned regions; plugin update available)
   - `local_current_canonical_sha != local_ancestor_sha` and `plugin_current_canonical_sha == local_ancestor_sha` → **local-only edit** (user edited owned regions; plugin unchanged — no action needed, no overwrite)
   - `local_current_canonical_sha != local_ancestor_sha` and `plugin_current_canonical_sha != local_ancestor_sha` and the two current SHAs differ → **conflict**

Files without a marker (legacy files from a pre-this-RFC `/sync`) are classified by content equality: if the local canonical content matches the plugin's currently-rendered canonical content, treat as unchanged (and add the marker on next write); if it does not match, treat as **conflict** with `local_ancestor_sha = unknown`. The conflict prompt for these cases shows the user the plugin's current content and asks "adopt, keep local, or merge" — same UI as a real conflict, with a note that the file pre-dates the marker.

**Option B — Single-file global version marker (status quo, extended).**

Keep the current single `bootstrap-content-version` marker on `skills/sync/SKILL.md` and use it as a one-bit "is this repo up-to-date as a whole" signal. On `/sync`, if the local version (stored somewhere in the project) matches the plugin's, do nothing; otherwise re-run the templating pass and confirm per-file overwrites.

Rejected because the marker has no per-file granularity. If the plugin updates one section of `CLAUDE.md` and nothing else, the user must look at every file to figure out what actually changed. Per-file detection is what makes the diff meaningful.

**Option C — Pure content comparison, no markers.**

For each file, diff plugin's current content against local content. If different, prompt. No ancestor tracking.

Rejected because pure two-way diff cannot distinguish "user edited" from "plugin updated since last sync." Every change becomes a conflict the user must resolve, even ones where the user never touched the file. The signal-to-noise ratio is poor enough that users will rubber-stamp everything, defeating the purpose of confirmation.

**Recommendation: Option A.** The per-artifact `upstream-key` plus content-hash ancestor marker is the smallest mechanism that gives the diff engine enough information to distinguish fast-forwards from real conflicts. The manifest file (`.claude-plugin/bootstrap-manifest.json`) is one source of truth for the plugin's current content, generated at plugin build time (see Implementation spec). The marker is a single inert HTML comment on each file's second line; it does not interfere with the file's actual content or its rendering on GitHub.

### Decision 2 — How are project-local extensions preserved inside plugin-managed files?

**Background on AskUserQuestion:** the tool accepts multiple questions in a single call. The existing Step 2c of `skills/sync/SKILL.md` already issues an AskUserQuestion with six questions in one call, so batching three category-level questions in one prompt is well within tool capability. The conflict-resolution prompts are issued sequentially (one per file) because the per-conflict context (file path, diff snippet, scope) is too verbose to batch and the user benefits from reviewing each conflict in isolation.

Three categories of "files the plugin ships but the user is also expected to edit" exist:

- **Region-based extension** (used today by `docs/rfc-process.md` via `END_UPSTREAM_CONTENT`). The file has a clear "upstream-owned region" and a "project-extension region," separated by a marker comment. The upstream region is replaced verbatim from the plugin; the extension region is preserved.
- **Named-section extension** (could apply to `CLAUDE.md`, `docs/BEST_PRACTICES.md`). The file is structured into named Markdown sections (`## Foo`, `## Bar`); some sections are plugin-managed, some are project-owned (e.g., `## Project-Specific` in `BEST_PRACTICES.md`). Mixing requires section-aware merging.
- **Structured-data extension** (`.claude/settings.json`, `.claude/settings.local.json`, `mise.toml`, `.gitignore`). The file is JSON / TOML / line-based. Some entries are plugin-managed (hooks the plugin ships, permissions the plugin requires); some are user-owned (extra allow entries, additional tools). Append-only and per-key replacement are both required, depending on the entry.

**Option A — Per-file extension strategy declared in the bootstrap manifest (recommended).**

The `.claude-plugin/bootstrap-manifest.json` entry for each artifact carries an `extension_strategy` field declaring how plugin-owned content and project-owned content are partitioned. Three strategy values, each with a deterministic merge rule:

- `"region"` — file has a leading upstream region (everything from the start of the file up to a sentinel marker like `<!-- END_UPSTREAM_CONTENT -->`) and a trailing project-extension region. On update, replace the upstream region; preserve the extension region byte-for-byte. The sentinel marker is required and is itself part of the upstream region. Files: `docs/rfc-process.md`.
- `"section"` — file is Markdown. The manifest entry lists the section headings the plugin owns and writes (e.g., `["## File structure", "## Tool Usage", "## RFC Process", ...]`). On update, replace each named section's body verbatim from the plugin; preserve every other section (including new sections the user added) and any prose that appears outside named sections (preamble, etc.). Files: `CLAUDE.md`, `docs/BEST_PRACTICES.md`.
- `"structured"` — file is JSON, TOML, or `.gitignore`-line-based. The manifest entry references a sub-schema describing which keys / array entries are plugin-managed and which are user-owned. For JSON: the manifest declares a list of `json_paths` the plugin owns; updates merge by replacing each owned path's value while preserving sibling keys. For TOML: same idea with TOML key paths. For `.gitignore`: each line the plugin contributes is identified by a comment-tagged section (e.g., `# bytewyrd:rust`); the section block is replaced as a unit. Files: `.claude/settings.json`, `.claude/settings.local.json`, `mise.toml`, `.gitignore`.

The strategy declaration lives in the manifest, not in the file itself, so the rules are versioned with the plugin (a future plugin version can change a file's strategy without breaking the file format).

**Option B — Whole-file replacement, no extension regions.**

For every plugin-managed file, the plugin owns the entire content. Project-local additions must live in entirely separate files (e.g., the user creates a `CLAUDE.local.md` that the plugin never touches).

Rejected because the existing pattern is already mixed (rfc-process.md has the `## Project Extensions` section; BEST_PRACTICES.md has the `## Project-Specific` section) and moving to a "separate files only" model would require migrating every existing project. The user-research signal also points the other way — Markdown is the editing surface; asking users to split content across parallel files for a plugin internal reason is friction.

**Option C — User-provided extension comments inline.**

The user marks any line or section they edited with a `<!-- KEEP: <reason> -->` comment, and the diff engine treats those as immovable. Plugin updates flow around the marked content.

Rejected because it puts the burden on the user to remember to mark every edit, and missed marks become silent data loss on the next update. The "named sections" / "named regions" approach declares the contract in one place (the manifest) instead of relying on diligence at every edit site.

**Recommendation: Option A.** The three strategies (`region`, `section`, `structured`) cover the three categories of file the plugin actually ships, and each strategy has a deterministic merge rule that needs no human judgment at sync time — meaning fast-forward updates can be applied without prompting the user when the only change is in plugin-owned regions/sections/keys. The user is prompted only when their local edits land *inside* a plugin-owned region/section/key — which is the genuine conflict.

### Decision 3 — How is the categorized result surfaced to the user?

A typical re-run of `/sync` after the plugin has shipped multiple updates may produce 8–15 fast-forward updates, 0–3 conflicts, and a handful of additions. Asking 8–15 separate AskUserQuestion calls would be hostile. Asking one AskUserQuestion with 15 questions (even if the tool accepted it — the existing `/sync` Step 2c already issues 6 questions in one call, so the tool is more permissive than 4) would still be wall-of-text and would force the user to make every per-file decision before seeing any of them resolved.

**Option A — One batch prompt for additions and fast-forwards, sequential prompts for conflicts only (recommended).**

The flow is:
1. **Pre-flight** — Compute the diff for every artifact silently. Build five lists: `add`, `fast_forward`, `conflict`, `local_only`, `unchanged`.
2. **Summary** — Print a categorized summary (counts + per-file outcomes) to the conversation. Example:
   ```
   /sync — change summary:
     Additions (4 new files):
       + .github/workflows/ci.yml
       + docs/CONTRIBUTING.md
       + ...
     Fast-forward updates (7 files, no local edits):
       ~ CLAUDE.md
       ~ docs/BEST_PRACTICES.md
       ~ ...
     Conflicts (2 files, local edits collide with plugin update):
       ! docs/rfc-process.md (core region edited locally)
       ! .claude/settings.json (custom hook added; plugin updated the same hook)
     Local-only edits (3 files, plugin unchanged):
       . CLAUDE.md (custom ## Project Notes section preserved)
       . ...
     Unchanged (12 files): (collapsed)
   ```
3. **Batch confirmation** — One AskUserQuestion with **three questions** (one per non-conflict, non-unchanged category that has items):
   - Q1: "Apply 4 additions?" — options: `Yes, apply all` / `Review each` / `Skip all`
   - Q2: "Apply 7 fast-forward updates?" — options: `Yes, apply all` / `Review each` / `Skip all`
   - Q3 is omitted if no conflicts exist; otherwise the conflicts go through a per-file flow (Option A.4).
4. **Per-conflict resolution** — For each conflict, ask one AskUserQuestion with the conflict context (single-question, four options):
   - `Adopt plugin version (replace local)` — local edit is lost, plugin version is written, ancestor marker advances.
   - `Keep local version (skip plugin update)` — file untouched, ancestor marker does NOT advance, conflict will re-surface on next `/sync` run.
   - `Merge into local manually (open three-way view, then re-run /sync)` — print the plugin version to a scratch file (`.claude/sync-conflict-<file>.txt`) and the local version next to it; tell the user to merge by hand and re-run.
   - `Skip for now (revisit later)` — same as "Keep local" but is intended to surface on the next run.
5. **Apply** — Write all approved fast-forwards, additions, and conflict resolutions. Update the ancestor marker on each written file. Print the Step 8-style final report.

If the user chose `Review each` for a non-conflict category, the skill drops into a per-file confirmation loop for that category — same `AskUserQuestion` shape as conflicts but with simpler options (`Apply / Skip`).

**Option B — One AskUserQuestion per file.**

Every artifact gets its own AskUserQuestion. Maximum granularity but maximum friction; 15 prompts for a typical re-run is a poor UX.

Rejected because users will rubber-stamp by the third or fourth prompt and meaningful conflicts will be approved without review.

**Option C — Auto-apply everything that is not a conflict; only prompt for conflicts.**

Skip the batch confirmation; fast-forwards and additions land automatically.

Rejected because the user has no opportunity to say "I know the plugin updated CLAUDE.md, but I want to look at the diff before adopting the new agent delegation table." The whole motivation of this RFC is to make plugin changes visible *before* they land, not just visible after.

**Recommendation: Option A.** Batched confirmation for the safe categories (additions, fast-forwards) keeps the prompt count to one for the common case, with a `Review each` escape hatch when the user wants per-file judgment. Conflicts get a dedicated, per-file prompt because they are the genuinely difficult case and rare enough that the friction is proportionate to the stakes.

## Drawbacks

- **Larger skill body.** `skills/sync/SKILL.md` grows by roughly 300–500 lines (manifest schema, classification matrix, three merge strategies, batched-confirmation flow, new report format). The file is already 1445 lines; a 25–35% growth is real cost in maintainability. **Mitigation:** the new logic is structured into named sub-procedures (Pre-flight Diff, Merge Strategies, Confirmation Flow) so the file can be skimmed by section, and the merge-strategy rules are deterministic enough that the implementation is closer to a state machine than to free-form prose. The alternative — letting the silent-skip problem persist — is the larger cost over time.

- **Manifest must be generated at plugin build time, not edited by hand.** Every plugin release needs the `.claude-plugin/bootstrap-manifest.json` regenerated from the current content of every artifact. A maintainer who edits an artifact without regenerating the manifest ships a plugin where the recorded `plugin_current_sha` for that file is stale, which makes every consumer see a phantom fast-forward update (no actual change, but the ancestor doesn't match). **Mitigation:** the manifest generator is a small script (described in the Implementation spec) shipped under `.claude-plugin/scripts/build-manifest.sh`; the same script is wired into a pre-commit hook (or a CI check) on the plugin repo that fails if the manifest does not match the current artifact content. Maintainers who forget see a failed hook, not a broken release.

- **Markdown files acquire an `<!-- bootstrap-content-version: ... -->` HTML comment on line 2.** This is mildly ugly for users who read the raw Markdown. **Mitigation:** HTML comments do not render on GitHub or in any common Markdown viewer, so end-users do not see them. Maintainers do see them but the marker is one line of inert comment — comparable to the `<!-- UPSTREAM: ... -->` / `<!-- END_UPSTREAM_CONTENT -->` markers already accepted on `docs/rfc-process.md`.

- **First run after the upgrade flags every existing file as a conflict or unchanged-via-content-match.** A repo that ran the pre-this-RFC `/sync` has no per-file markers. On the first post-upgrade `/sync`, every file falls into the "no marker → fall back to content comparison" path, and any file whose local content has drifted from the plugin's current content is flagged as a conflict (with `local_ancestor_sha = unknown`). For a project that ran `/sync` six months ago, this could mean 10–15 simultaneous conflicts on first run. **Mitigation:** the conflict prompt explicitly distinguishes "no marker present (legacy file)" from "marker present and diverged"; for legacy files, it offers a fourth fast-path option `Adopt plugin version and add marker (recommended if you haven't customized this file)` so users can quickly resolve files they have not edited. Documentation (and the report banner on first run) explains the situation: "this is a one-time migration; future runs will only flag files that genuinely diverged."

- **Conflict-resolution UX is necessarily limited to the AskUserQuestion option set.** AskUserQuestion does not support inline diff rendering; the user sees option labels and the conversation prose, not a visual diff. **Mitigation:** the per-conflict prompt includes a compact unified diff snippet (first 40 lines of the diff) in the conversation prose immediately before the question, and the `Merge into local manually` option writes both versions to scratch files for a proper external diff. For deep conflicts, the user is expected to use their editor's diff tool — the skill does not try to replicate a full diff UI in chat.

- **Performance: SHA-256 of every plugin-managed file on every `/sync` run.** For 20–30 artifacts averaging a few KB each, this is sub-second; the hash work is not the bottleneck — Bash invocation is. **Mitigation:** none needed; sync is interactive, not a hot path. Hash computation is done with `sha256sum` (Linux) or `shasum -a 256` (macOS); the implementation spec calls out the cross-platform handling.

- **The "local-only edit" category (user edited a file, plugin did not change it) is technically a no-op but adds report noise.** A user who has lightly customized `CLAUDE.md` will see it listed under "Local-only edits" on every run forever. **Mitigation:** the report collapses the unchanged and local-only categories into single-line summaries with file counts; the user can expand with a follow-up `/sync --verbose` (out of scope for this RFC; the verbose flag is captured in the Risks section). Default report shows category counts only, not per-file listings for these two safe categories.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/sync/SKILL.md` | Replace Step 4 (creation summary) and Step 5 (file creation) with the new diff-classify-confirm-apply flow. Update Step 7 (RFC process sync) to consume the new manifest entry for `docs/rfc-process.md` instead of its bespoke logic. Update Step 8 (report) to use the new outcome categories. Keep Steps 1–3 (environment, identity, language detection) unchanged. Bump the bootstrap-content-version marker on line 6. |
| Create | `.claude-plugin/bootstrap-manifest.json` | New file. The per-artifact manifest enumerating every plugin-managed artifact with its `upstream-key`, current SHA-256 hash, source path inside the plugin, target path inside the consumer repo, extension strategy, and (for `section` / `structured` strategies) the list of plugin-owned sections / paths. |
| Create | `.claude-plugin/scripts/build-manifest.sh` | New file. Small Bash script that walks the plugin's source tree, hashes each artifact, and regenerates `.claude-plugin/bootstrap-manifest.json`. Idempotent; produces deterministic output (entries sorted by `upstream-key`). |
| Create | `.claude-plugin/scripts/templates/` | New directory. The current Step 5 templates that are embedded inline in `skills/sync/SKILL.md` are extracted into individual files here (`CLAUDE.md.tpl`, `README.md.tpl`, `docs/BEST_PRACTICES.md.tpl`, etc.) so the manifest can hash them as standalone units. |
| Create | `.claude-plugin/hooks/pre-commit/manifest-check.sh` | New file. Pre-commit hook that runs `build-manifest.sh --check` and fails if the committed `bootstrap-manifest.json` does not match the current artifact content. |
| Modify | `.claude-plugin/CLAUDE.md` | Add a "Maintaining the bootstrap manifest" subsection explaining the build-manifest workflow for plugin maintainers. |
| Modify | `skills/rfc-update/SKILL.md` | Update Step 2 to read the `docs/rfc-process.md` entry from the new manifest and apply the `region` merge strategy, eliminating the bespoke `END_UPSTREAM_CONTENT` parsing that lives only in this skill. The user-visible behavior of `/rfc-update` is unchanged. |
| Delete | (none) | No files are removed by this RFC. |

### Bootstrap manifest schema

`.claude-plugin/bootstrap-manifest.json` is a JSON document with one top-level array, `artifacts`. Each entry:

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "source": ".claude-plugin/scripts/templates/CLAUDE.md.tpl",
  "target": "CLAUDE.md",
  "template_sha": "a1b2c3d4e5f6...",
  "extension_strategy": "section",
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
  "template_inputs": ["project_name", "description", "project_slug", "component_roots", "installed_plugins"]
}
```

(Templated artifacts use `template_sha`; non-templated artifacts use `sha256` — never both in the same entry.)

Field semantics:

- `upstream_key` — stable string identifying the artifact across plugin versions. Format: `<plugin-name>/<target-path>[@<version-tag>]`. The version tag is bumped only when the *structure* of the artifact changes in a way that makes content comparison meaningless (e.g., `CLAUDE.md@v1` → `CLAUDE.md@v2` if the named-section list is reorganized). The version tag is *not* bumped for content changes — those flow through normally as fast-forwards.
- `source` — path inside the plugin to the canonical template / content source for this artifact.
- `target` — path inside the consumer repo where the artifact lands (relative to the repo root).
- `sha256` — SHA-256 hash of the canonical rendered content. For non-templated artifacts, this is the hash of the source file. For templated artifacts, this is the hash of a *normalized* template with a deterministic set of input values (see "Templated artifacts" below).
- `extension_strategy` — `"region"`, `"section"`, `"structured"`, or `"whole"`. `"whole"` is the default for files with no extension surface (e.g., `.github/PULL_REQUEST_TEMPLATE.md`).
- `region_end_marker` — required when `extension_strategy = "region"`. The literal text of the line that separates the upstream region (above) from the project-extension region (below). For `docs/rfc-process.md`, this is `<!-- END_UPSTREAM_CONTENT -->`. The marker is itself part of the upstream region.
- `owned_sections` — required when `extension_strategy = "section"`. Each entry is the exact Markdown heading line of a plugin-owned section. Sections not in this list are user-owned and preserved verbatim.
- `owned_paths` — required when `extension_strategy = "structured"`. The path syntax depends on the file format:
  - **JSON / TOML — single value paths:** dotted notation (e.g., `"extraKnownMarketplaces.bytewyrd"`, `"enabledPlugins.bytewyrd@bytewyrd"`). On merge, the plugin's value at that path replaces the local value at that path; sibling keys at every level are preserved.
  - **JSON / TOML — array paths with id-based identification:** `"<path>[]:<id_key>"` notation (e.g., `"hooks.PostToolUse[]:_meta.bytewyrd_hook_id"`). The plugin's array entries with matching `_meta.bytewyrd_hook_id` values replace local entries with the same id; local entries with no id (or with an id the plugin no longer ships) are preserved untouched. See "Special rule for JSON array paths" below for details.
  - **JSON / TOML — set-union array paths:** `"<path>[]:union"` notation (e.g., `"permissions.allow[]:union"`). The merged array is the set-union of local entries and plugin entries; order is preserved with local entries first, then plugin entries that were not already present.
  - **`.gitignore`:** array of section-tag identifiers (e.g., `["bytewyrd:base", "bytewyrd:rust", "bytewyrd:js"]`). Each identifier corresponds to a comment-fenced block in the file (lines between `# <tag>` and the next `# <tag>` or end-of-file). On merge, the plugin replaces each tagged block as a unit; lines outside any tagged block are preserved verbatim.
- `templated` — boolean. If true, the artifact is rendered from a template with project-specific inputs (project_name, language detection results, etc.) — see "Templated artifacts" below.
- `template_inputs` — required when `templated = true`. Lists the variables the template consumes. The diff engine knows to recompute the rendered content for each consumer's specific inputs before comparing.

### Templated artifacts

`CLAUDE.md`, `README.md`, `docs/CONTRIBUTING.md`, `.claude/settings.json`, `.claude/settings.local.json`, `mise.toml`, `.gitignore`, and `.github/workflows/ci.yml` are all rendered from templates with project-specific inputs (project name, detected languages, installed plugins). Different consumer projects render the same template to different content, so the marker on each consumer's file must record the SHA of the *rendered* canonical content (not of the template source) — that is what subsequent diffs need to compare against to detect "has the local file's owned content drifted since it was written."

**The unified marker rule** (applies to both templated and non-templated artifacts): the marker stores the SHA of the canonical content as it was when last written by `/sync` *for this specific consumer*. For non-templated artifacts, the canonical content is the artifact source; the SHA in the marker equals the SHA in the manifest. For templated artifacts, the canonical content is the result of rendering the template with the consumer's `project_inputs` at write time; the SHA in the marker is computed at write time and equals the manifest's `template_sha` *only* by coincidence — it is independently computed.

**Manifest fields** (corrected from the schema example above):

- `sha256` — for non-templated artifacts, the SHA-256 of the artifact source. Used by the diff engine as the value to compare against the marker.
- `template_sha` — for templated artifacts, the SHA-256 of the template source file. Used by the manifest-build script and by maintainers to detect "did the template itself change since last commit" (the pre-commit hook). The diff engine does *not* compare this directly to the marker; instead, the diff engine re-renders the template with the current consumer's `project_inputs` and computes the canonical rendered SHA on the fly (`plugin_current_canonical_sha` in the pseudocode below), which is the value comparable to the marker.

**Why two fields:** the `template_sha` is what the pre-commit hook and the maintainer's `build-manifest.sh` watch — it changes when the template changes. The marker on a consumer's file records the *rendered* SHA — it changes when either the template changes or the consumer's `project_inputs` change. The diff engine reconciles by re-rendering at sync time.

### Diff comparison rule (uniform for templated and non-templated)

For every artifact:

1. Compute `plugin_current_canonical_sha` = first 12 hex chars of SHA-256 of `canonicalize(render_or_read(artifact, project_inputs), artifact)`. For templated artifacts, this re-renders the template with the consumer's current inputs and then canonicalizes. For non-templated artifacts, this just reads the source file and canonicalizes.
2. Compute `local_current_canonical_sha` = first 12 hex chars of SHA-256 of `canonicalize(read_file(target), artifact)`.
3. Extract `local_ancestor_sha` from the file's marker (or sidecar). May be None.
4. Classify per the matrix below.

Because the marker stores the rendered-canonical SHA at last write, the comparison `local_ancestor_sha == plugin_current_canonical_sha` correctly answers "is the file at the version the plugin would currently produce for this consumer?" — even when the consumer's inputs have changed since the last write. If the inputs changed, the re-render produces a different canonical SHA than the marker, so the file is correctly flagged as a fast-forward (or conflict if local also drifted).

This handles three cases cleanly:
- **Common: plugin tweaked the template; consumer inputs unchanged** → re-render produces new canonical bytes, `plugin_current_canonical_sha != local_ancestor_sha`, classified as fast-forward.
- **Common: consumer renamed the project** → re-render produces new canonical bytes (different project_name), classified as fast-forward.
- **Rare: plugin added a new template input variable, consumer's project doesn't set it** → re-render produces the same canonical bytes (the new variable expands to the empty string (per the renderer's unrecognized-placeholder rule), leaving rendered output unchanged for this consumer), classified as unchanged. No false positive.

### Marker format

The marker associates each file with the version of plugin content it was written from. The storage strategy depends on whether the file format supports comments without affecting its consumers:

**For files that support comments natively** (Markdown, TOML, `.gitignore`, YAML), the marker is embedded directly:

- **Markdown** (`CLAUDE.md`, `README.md`, `docs/*.md`): an HTML comment on line 2:
  ```html
  <!-- bootstrap-content-version: <upstream_key>:<sha-12> -->
  ```
  HTML comments do not render on GitHub or in any common Markdown viewer; the existing `<!-- UPSTREAM: ... -->` markers on `docs/rfc-process.md` already establish this convention.

- **TOML** (`mise.toml`, `rust-toolchain.toml`): a `#` comment on line 1, blank line on line 2, then the file content:
  ```toml
  # bootstrap-content-version: bytewyrd/mise.toml:a1b2c3d4e5f6

  [tools]
  bun = "1.2.3"
  ```

- **`.gitignore`**: a `#` comment on line 1, blank line on line 2, then the existing tagged-block content:
  ```
  # bootstrap-content-version: bytewyrd/.gitignore:a1b2c3d4e5f6

  # bytewyrd:base
  .worktrees/
  .claude/settings.local.json
  ```

- **YAML** (`.github/workflows/ci.yml`, `.github/ISSUE_TEMPLATE/*.md` frontmatter — the markdown files use frontmatter): `#` comment on line 1, blank line, then the YAML body:
  ```yaml
  # bootstrap-content-version: bytewyrd/.github/workflows/ci.yml:a1b2c3d4e5f6

  name: CI
  on:
    push:
      branches: [main]
  ```

**For JSON files** (`.claude/settings.json`, `.claude/settings.local.json`), embedding a marker as a JSON key risks breaking Claude Code's schema validation — Claude Code reads these files as configuration and unknown top-level keys (e.g., `"_meta"`) may be rejected, warned about, or silently ignored depending on the runtime version. To avoid coupling the marker to a foreign-system schema, JSON files use a **sidecar marker file** at `.claude/.bootstrap-versions.json`:

```json
{
  "bytewyrd/.claude/settings.json": "a1b2c3d4e5f6",
  "bytewyrd/.claude/settings.local.json": "b2c3d4e5f6a7"
}
```

The sidecar is itself a plugin-managed artifact in the manifest (`upstream_key: "bytewyrd/.claude/.bootstrap-versions.json"`, `extension_strategy: "whole"` — the entire file is plugin-owned, but its content is the *consumer's* per-file version map, computed at sync time and not derived from any plugin template). **Concrete rule:** the sidecar is *not* added to `.gitignore` by `/sync`. The marker entries are project-state that arguably belong in source control (so the sync state is reproducible from a clean checkout), and the file lives in `.claude/` alongside the JSON files it tracks. If a consumer prefers to keep the sidecar gitignored (e.g., to avoid noisy diffs on every sync), they add the line `.claude/.bootstrap-versions.json` to `.gitignore` themselves — the existing append-only behavior of `.gitignore` means the line persists.

Because the sidecar holds runtime sync state (one entry per JSON-format plugin artifact, with the consumer's last-written SHA), the manifest declares its `extension_strategy` as `"whole"` for ownership purposes but the actual content is *generated* during sync, not rendered from a template. The diff engine treats the sidecar file specially: its `local_ancestor_sha`/`local_current_canonical_sha` comparison is not run (the file is always rewritten on every sync when any JSON-format artifact's marker changes); the sidecar is never classified as `conflict` or `fast_forward`. It is updated as a side effect of the apply phase (Step 5) whenever a JSON-format artifact's marker is updated.

In either case (embedded or sidecar), `<sha-12>` is the first 12 hex characters of `plugin_current_canonical_sha` as computed during the write phase — the SHA-256 of the canonical-rendered content as it was written for this specific consumer. For non-templated artifacts this equals the manifest `sha256`; for templated artifacts it is independently computed from the rendered output and does **not** equal `template_sha`.

The marker format per file type is fixed and parsed deterministically by the diff engine. When the engine extracts `local_ancestor_sha`, it looks first in the embedded marker (Markdown/TOML/gitignore/YAML) and second in `.claude/.bootstrap-versions.json` (JSON files). A file with no embedded marker and no sidecar entry is classified as "legacy" (see Classification matrix).

### Classification matrix

For each artifact in the manifest, classify into one of five (or seven, counting the two legacy variants) outcomes. The condition column uses the sha variables defined in the pseudocode below; all variables are 12-hex-char truncated SHA-256 of canonical-form content:

| Conditions | Classification | Action |
|------------|----------------|--------|
| Target file absent | **add** | Write rendered content + marker |
| No marker, `local_current_canonical_sha == plugin_current_canonical_sha` | **unchanged_legacy** | Re-write file with marker added; report as unchanged |
| No marker, `local_current_canonical_sha != plugin_current_canonical_sha` | **conflict_legacy** | Per-conflict prompt with the four standard options plus the legacy fast-path |
| Marker present, `local_ancestor_sha == plugin_current_canonical_sha` | **unchanged** | No action |
| Marker present, `local_current_canonical_sha == local_ancestor_sha` AND `plugin_current_canonical_sha != local_ancestor_sha` | **fast_forward** | Re-write file with plugin content (merged per strategy) + new marker |
| Marker present, `local_current_canonical_sha != local_ancestor_sha` AND `plugin_current_canonical_sha == local_ancestor_sha` | **local_only** | No action (collapse into report summary) |
| Marker present, `local_current_canonical_sha != local_ancestor_sha` AND `plugin_current_canonical_sha != local_ancestor_sha` AND `local_current_canonical_sha != plugin_current_canonical_sha` | **conflict** | Per-conflict prompt |

The last row's third clause (`local_current_canonical_sha != plugin_current_canonical_sha`) is a defensive check: if local and plugin both diverged from ancestor but happened to converge to the same content (extremely rare — both edited and arrived at the same answer), the file is effectively unchanged and is classified as `unchanged` rather than `conflict`. This is the "merge-resolves-itself" case that a literal pseudo-three-way merge would correctly resolve.

For `extension_strategy = "section"` / `"structured"`, the classification is performed *only on the plugin-owned regions/sections/keys*. Edits that fall entirely within user-owned regions do not advance `local_current_canonical_sha` relative to `local_ancestor_sha` — the sha for marker purposes is computed over the canonical-form serialization of just the plugin-owned content. This means a user who adds a `## My Notes` section to `CLAUDE.md` does not generate a conflict on every plugin update.

**Canonical-form serialization rules** (used for both `local_current_sha` and `plugin_current_sha` computation — both must use identical rules so the hashes are comparable):

- **`whole` strategy:** canonical form is the file content with the marker line(s) removed (the first comment line of the appropriate kind for that file type — e.g., the `<!-- bootstrap-content-version: ... -->` line and any subsequent blank line). For sidecar-marker JSON files, the marker is not in the file at all, so canonical form is the full file content.
- **`region` strategy:** canonical form is the file content from line 1 up to and including the `region_end_marker` line, with the marker line(s) removed (same removal rule as `whole`). The project-extension region after the marker is excluded from the hash entirely.
- **`section` strategy:** canonical form is built by extracting each heading in `owned_sections` in *manifest order* and concatenating, for each: the literal heading line + `\n` + the section body (every line between the heading and the next H2 or end of file, trimmed of leading and trailing blank lines) + `\n`. Sections present in the local file but not in `owned_sections` are excluded from the hash. If a section listed in `owned_sections` is absent from the file being canonicalized, it contributes the literal heading line + `\n` with an empty body (no body lines). This rule applies identically to local and plugin canonicalization — an owned section missing from the local file produces a different hash from the plugin's rendered content (which always includes all owned sections), correctly classifying the file as `fast_forward`. The marker line is not part of any owned section, so it is not part of the hash by construction.
- **`structured` strategy (JSON / TOML):** canonical form is built by extracting each path in `owned_paths` in manifest order. For each path: serialize the value at the path using `jq --sort-keys --indent 2` (for JSON) or the equivalent canonical TOML serialization (for TOML), then append a `\n`. For id-based array paths (`[]:<id_key>`), serialize only the entries with a non-empty id key, sorted by id ascending; user-added entries (no id) are excluded from the hash. For set-union array paths (`[]:union`), serialize the set of plugin-contributed entries (identified by comparing to the manifest's current rendered array contents); user-added local-only entries are excluded.
- **`structured` strategy (`.gitignore`):** canonical form is built by extracting each tagged block in `owned_paths` order. For each tag: the literal `# <tag>\n` line + the lines in the block + `\n`. Free-form (untagged) blocks are excluded.

The same canonicalization function is applied to both local content (after parsing) and plugin content (after rendering); the resulting SHA-256 hashes are directly comparable.

### Merge strategies — exact rules

**`whole` strategy** (used for files with no extension surface — e.g., `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md`, `rust-toolchain.toml`).

For fast-forward updates: write the plugin's rendered content + marker, replacing the local file in full.

For conflicts: present the per-conflict prompt with the four standard options.

**`region` strategy** (used for `docs/rfc-process.md`).

Manifest entry includes `region_end_marker` (e.g., `<!-- END_UPSTREAM_CONTENT -->`). The upstream region is everything from the start of the file (including the marker line on line 2) up to and including `region_end_marker`. The project-extension region is everything after.

For fast-forward updates: replace the upstream region with the plugin's current rendered content (including the new `bootstrap-content-version` marker on line 2 and the `region_end_marker` line). Preserve the project-extension region byte-for-byte.

For conflicts: the only way `region` strategy can conflict is if the user edited content inside the upstream region (above the `END_UPSTREAM_CONTENT` marker). Detect this by hashing the local upstream-region content against `local_ancestor_sha`. Present the per-conflict prompt.

**`section` strategy** (used for `CLAUDE.md`, `docs/BEST_PRACTICES.md`).

Parse the file as a sequence of Markdown sections. A section starts at a heading line matching `^##\s+(.+)$` (or `^#\s+(.+)$` for the H1) and extends to the next H2 (or H1) heading line, or end of file. H3 and deeper headings inside an H2 section are part of that H2's body and do not begin a new section.

For fast-forward updates:
1. Parse local file into a section map: `section_heading → (heading_line, body, position_in_file)`.
2. For each section in `owned_sections` (manifest order): replace the body in the section map with the plugin's current rendered body for that section. If the section heading is not present in the local file, insert it at the position dictated by the manifest's order (after the previous owned section in the manifest list, or at the end if no previous owned section exists).
3. Preserve every section in the local file that is *not* in `owned_sections`, including its position relative to the surrounding sections (preamble, position between owned sections, trailing position).
4. Reserialize the file: marker line on line 2 (updated to the new sha), then the sections in their preserved order.

For conflicts: detected when the canonical-form hash of just the owned sections in the local file differs from `local_ancestor_sha` *and* the plugin's owned-section content differs from `local_ancestor_sha`. Present the per-conflict prompt; conflict resolution for `section` strategy operates only on the owned sections (user-owned sections are always preserved regardless of the resolution choice).

**`structured` strategy** (used for `.claude/settings.json`, `.claude/settings.local.json`, `mise.toml`, `.gitignore`).

For JSON / TOML files:
1. Parse local file into the in-memory data structure.
2. For each path in `owned_paths` (manifest order): replace the value at that path with the plugin's current rendered value. If the path does not exist in the local file, create it (parent objects are created as empty `{}` if missing).
3. Preserve every other path in the local data, including paths the user added (e.g., custom `permissions.allow` entries, custom `[tools]` entries).
4. Reserialize. For JSON: pretty-print with two-space indent, preserving the order of keys as parsed (with new keys appended after existing ones). The JSON file itself carries no marker — the marker for this artifact is updated in the sidecar at Step 5.5. For TOML: serialize using the small hand-written generator (see Step 5 template rendering rule — `mise.toml` and `rust-toolchain.toml` both have simple, fixed shapes that round-trip cleanly through a line-oriented generator).

**Special rule for JSON array paths** (`hooks.PostToolUse[]:_meta.bytewyrd_hook_id`, `permissions.allow[]:union`): array merging uses the syntax declared in the manifest's `owned_paths` entry. Two array-merge modes are supported:

- **Id-based merge** (syntax: `"<path>[]:<id_key>"`). The plugin's hook entries in `settings.json` carry an `_meta.bytewyrd_hook_id` field that identifies which plugin-shipped hook the entry represents (e.g., `"bytewyrd-post-bash-commit"`, `"bytewyrd-pre-push-rust-gate"`). The diff engine, on merge, performs three steps:
  1. Build the local array's id index: `{ id → entry }` for every local entry that has a non-empty `_meta.<id_key>` value. Entries with no id are tagged as "unowned" (user-added entries).
  2. Build the plugin array's id index: `{ id → entry }` from the plugin's current rendered content.
  3. Compose the merged array as: (unowned local entries, in their original local order) ++ (plugin entries, in their plugin-order, each replacing any local entry with the same id).

  The result: user-added hook entries (no id) are preserved at their original positions relative to plugin entries; plugin-managed entries are replaced wholesale by the current plugin version. A user who customizes a plugin-shipped hook by editing its body in place creates a conflict (the id-tagged entry's content differs from `local_ancestor`); a user who adds a new entry with no id creates no conflict (the entry is preserved).

- **Set-union merge** (syntax: `"<path>[]:union"`). The merged array contains the union of local and plugin entries, deduplicated by exact string/value equality. Order: local entries first (in original local order), then plugin entries not already present in local. Used for unordered permission lists like `permissions.allow` where the user freely adds entries and the plugin contributes a baseline set.

For both modes: the conflict check operates only on the plugin-owned subset of the array (entries with a plugin id, for id-based; entries that the plugin contributed, for union). User-added entries (no id, or local-only union entries) do not generate conflicts.

For `.gitignore`:
1. Parse local file as a sequence of blocks separated by comment-tagged section markers (`# bytewyrd:base`, `# bytewyrd:rust`, etc.) and free-form blocks (everything not inside a tagged section).
2. For each tag in `owned_paths` (manifest order): replace the block with the plugin's current rendered block. If the tag is absent in the local file, append it after the last tagged block (or at the end of the file).
3. Preserve every free-form block in its position relative to surrounding tagged blocks.
4. Reserialize.

For conflicts: detected when the canonical-form hash of just the owned paths/blocks differs from `local_ancestor_sha` *and* the plugin's owned content differs from `local_ancestor_sha`. The per-conflict prompt operates on the affected paths/blocks only.

### Pre-flight diff procedure

This procedure runs as part of Step 4 (which is renamed from "Print creation summary" to "Compute diff and present summary"). Pseudocode (the variable names are normative — implementations should use them):

```
# Inputs (already computed by Steps 1-3 of /sync):
#   project_inputs        — { project_name, description, project_slug, languages, ... }
#
# Read manifest and sidecar:
manifest = read_manifest(f"{CLAUDE_PLUGIN_ROOT}/.claude-plugin/bootstrap-manifest.json")
sidecar = read_sidecar(".claude/.bootstrap-versions.json")  # {} if file absent
results = []

for artifact in manifest.artifacts:
    # The sidecar is managed separately — skip in pre-flight classification.
    if artifact.upstream_key.endswith("/.bootstrap-versions.json"):
        continue

    target = artifact.target          # path inside consumer repo
    upstream_key = artifact.upstream_key

    # Compute plugin_current_canonical_sha — what the plugin would write for this consumer right now.
    plugin_content = render_template(artifact, project_inputs) if artifact.templated else read_plugin_source(artifact)
    plugin_canonical = canonicalize(plugin_content, artifact)
    plugin_current_canonical_sha = sha256(plugin_canonical)[:12]

    if not file_exists(target):
        results.append({
            artifact: artifact,
            classification: "add",
            new_content: plugin_content,
            new_sha: plugin_current_canonical_sha,
        })
        continue

    local_content = read_file(target)

    # Extract local_ancestor_sha from embedded marker OR sidecar.
    # For JSON files, the marker lives in sidecar (lookup by upstream_key).
    # For all other supported formats, the marker is embedded on line 1 or line 2.
    local_ancestor_sha = extract_embedded_marker(local_content, artifact.target) \
                      or sidecar.get(upstream_key) \
                      or None

    # Compute local canonical form (excludes user-owned regions, excludes marker line(s))
    local_canonical = canonicalize(local_content, artifact)
    local_current_canonical_sha = sha256(local_canonical)[:12]

    if local_ancestor_sha is None:
        # No marker — legacy file from pre-this-RFC /sync
        if local_current_canonical_sha == plugin_current_canonical_sha:
            results.append({
                artifact: artifact,
                classification: "unchanged_legacy",
                new_content: plugin_content,        # for marker insertion on next write
                new_sha: plugin_current_canonical_sha,
            })
        else:
            results.append({
                artifact: artifact,
                classification: "conflict_legacy",
                local_canonical: local_canonical,
                plugin_canonical: plugin_canonical,
                new_content: plugin_content,
                new_sha: plugin_current_canonical_sha,
            })
        continue

    # Marker present — full 3-way comparison.
    if local_ancestor_sha == plugin_current_canonical_sha:
        # Local marker matches what plugin would write now → file is current.
        # (Includes the case where neither local nor plugin has changed since last sync.)
        results.append({artifact: artifact, classification: "unchanged"})
        continue

    if local_current_canonical_sha == local_ancestor_sha:
        # Local owned-content hasn't drifted since last sync; plugin has changed.
        results.append({
            artifact: artifact,
            classification: "fast_forward",
            new_content: plugin_content,
            new_sha: plugin_current_canonical_sha,
        })
    elif plugin_current_canonical_sha == local_ancestor_sha:
        # Plugin would still render the same content the local was synced from
        # (no plugin update affects this consumer); local owned-content drifted.
        # User edited owned content in CLAUDE.md, BEST_PRACTICES.md, settings.json, etc.
        # This is the "user customized a plugin-owned region" case.
        results.append({artifact: artifact, classification: "local_only"})
    elif local_current_canonical_sha == plugin_current_canonical_sha:
        # Both local and plugin drifted from ancestor but converged to same content.
        # Treat as unchanged — the stale marker is harmless since both sides canonicalize
        # to the same SHA; future runs will hit this same branch until one side diverges.
        results.append({artifact: artifact, classification: "unchanged"})
    else:
        # All three are different — true conflict.
        results.append({
            artifact: artifact,
            classification: "conflict",
            local_ancestor_sha: local_ancestor_sha,
            local_current_canonical_sha: local_current_canonical_sha,
            plugin_current_canonical_sha: plugin_current_canonical_sha,
            local_canonical: local_canonical,
            plugin_canonical: plugin_canonical,
            new_content: plugin_content,
            new_sha: plugin_current_canonical_sha,
        })

return results
```

Every variable holding a sha is the first 12 hex chars of the SHA-256 of canonical content. Truncation happens once at the boundary (right after `sha256()`) so every downstream comparison uses the same number of characters.

### Step 4 — Compute diff and present summary

(This step replaces the existing "Step 4 — Print creation summary".)

Run the pre-flight diff procedure above. Print a categorized summary to the conversation, grouped in this order: `Additions`, `Fast-forward updates`, `Legacy marker injection`, `Conflicts`, `Local-only edits (collapsed)`, `Unchanged (collapsed)`. Example output for a re-run scenario:

```
/sync — change summary:

Additions (3 new files):
  + .github/workflows/ci.yml
  + docs/CONTRIBUTING.md
  + rust-toolchain.toml

Fast-forward updates (5 files, no local edits):
  ~ CLAUDE.md              (plugin: agent delegation table updated)
  ~ docs/BEST_PRACTICES.md (plugin: new entries in ## Testing, ## Architecture)
  ~ docs/rfc-process.md    (plugin: scope-check section added; ## Project Extensions preserved)
  ~ .claude/settings.json  (plugin: new PostToolUse hook added)
  ~ README.md              (plugin: "Documentation" section reformatted)

Legacy marker injection (2 files, content matches — adding version marker only):
  + CLAUDE.md               (first sync after upgrade — no content change)
  + docs/BEST_PRACTICES.md  (first sync after upgrade — no content change)

Conflicts (1 file, local edits collide with plugin update):
  ! .claude/settings.json/hooks.PreToolUse[bytewyrd-prepush]
      (you customized the prepush hook; plugin updated the same hook)

Local-only edits (2 files, plugin unchanged): CLAUDE.md, .gitignore

Unchanged (8 files): docs/ARCHITECTURE.md, .github/PULL_REQUEST_TEMPLATE.md, ...
```

The summary is printed verbatim before any confirmation prompt — the user sees the full landscape first, then approves in batches.

### Step 4a — Batch confirmation for additions and fast-forwards

Ask one AskUserQuestion. The question set depends on which categories have items:

- If `additions` is non-empty: include Question 1 — "Apply 3 additions?" with options:
  - `Yes, apply all`
  - `Review each` (drops into per-file prompts for additions)
  - `Skip all`
- If `fast_forwards` is non-empty: include Question 2 — "Apply 5 fast-forward updates? (no local edits will be lost)" with the same three options.

The two questions are sent in a single AskUserQuestion call (the existing `/sync` Step 2c already sends 6 questions in one call, so two is well-supported). If neither category has items, skip Step 4a entirely.

Files in the `Legacy marker injection` category are shown for visibility only; they do not require confirmation and are rewritten silently as part of Step 5.

`Review each` mode for a category: for each file in the category, ask one AskUserQuestion with the single question "Apply update to `<path>`?" and options `Apply` / `Skip`. The file's content diff (first 40 lines of unified diff between local and plugin-rendered content) is printed to the conversation immediately before the question.

### Step 4b — Per-conflict resolution

For each conflict in the `conflict` (and `conflict_legacy`) list, run sequentially (one AskUserQuestion per conflict). Before each question, print to the conversation:
- The file path and the conflict scope (e.g., "conflict in `## Tool Usage` section of `CLAUDE.md`" for `section` strategy; "conflict in `hooks.PreToolUse[bytewyrd-prepush]` of `.claude/settings.json`" for `structured` strategy; "conflict in upstream region of `docs/rfc-process.md`" for `region` strategy).
- A compact unified diff (first 40 lines) of `local_content` vs `plugin_content` restricted to the affected owned region/section/path.
- For `conflict_legacy` only: a note that this file pre-dates per-file markers, so the diff is informational; the user is choosing between "trust plugin" and "trust local" without a true 3-way merge.

Then ask one AskUserQuestion with the question "How to resolve conflict in `<path>`?" and options:
- `Adopt plugin version (replace local edits in the owned region)`
- `Keep local version (skip this update; will re-surface on next /sync)`
- `Merge into local manually (open three-way view, then re-run /sync)`
- `Skip for now (revisit later)`

For `conflict_legacy` only, add a fifth option:
- `Adopt plugin and add marker (recommended if you haven't customized this file)`

Action on each choice:
- `Adopt plugin version` → write plugin content (merged per the appropriate strategy: for `section`, only the owned sections are replaced; for `structured`, only the owned paths/blocks; for `region`, the upstream region; for `whole`, the full file). Update the marker to the new sha.
- `Keep local version` → no write. The marker is *not* updated, so the same conflict will surface again on the next `/sync` run. (This is intentional — `Keep local` means "I want to keep what I have, and I want to be re-prompted later in case I change my mind.")
- `Merge into local manually` → write the plugin's rendered content to `.claude/sync-conflict-<sanitized-path>.txt` and the local file's current content to `.claude/sync-local-<sanitized-path>.txt`. Print a one-line note: "Wrote `.claude/sync-conflict-<sanitized-path>.txt` and `.claude/sync-local-<sanitized-path>.txt` for manual three-way merge. Re-run `/sync` after merging." Do not write the target file.
- `Skip for now` → identical to `Keep local version` but recorded separately in the report so the user can see they explicitly deferred (vs. actively kept local).
- `Adopt plugin and add marker` (legacy only) → write the plugin content and set the marker to the plugin's current sha. Treats the file as if the user had never edited it (because, by their own assertion via this option, they had not).

### Step 5 — Apply changes

(This step replaces the existing "Step 5 — Create core files".)

For each artifact in the diff result, apply the action determined by Step 4a / 4b:

1. **add** — Render the template with the project's inputs (project_name, description, languages, installed_plugins, etc. — same inputs as the existing Step 5 templating logic). Insert the `bootstrap-content-version` marker on line 2 (per "Marker format"). Write the file.
2. **fast_forward** (approved in Step 4a) — Render the template (for templated artifacts) or read the plugin source (for non-templated). Merge per the artifact's `extension_strategy` against the local file (preserving user-owned regions/sections/paths). Update the marker (per the file's marker format — embedded comment on line 2 for Markdown/TOML/gitignore/YAML, sidecar entry for JSON) to `<upstream_key>:<plugin_current_canonical_sha>` from the pre-flight diff result. Write the file.
3. **conflict** (resolution chosen in Step 4b) — Apply the resolution as described above.
4. **conflict_legacy** (resolution chosen in Step 4b) — Apply the resolution as described above; the `Adopt plugin and add marker` option specifically inserts a marker on a previously-unmarked file.
5. **unchanged_legacy** — Silently re-write the file with the marker inserted (no content change); report as `unchanged (legacy marker added)`. This is the one-time migration write listed in the Step 4 "Legacy marker injection" summary.
6. **unchanged**, **local_only** — No action.

The existing Step 5 template content (the inline CLAUDE.md template, the BEST_PRACTICES.md template, the per-language tool entries, the language-specific BEST_PRACTICES.md sections, etc.) is **extracted into the new `.claude-plugin/scripts/templates/` directory** as part of this RFC's implementation. The templates retain the same `<project_name>`, `<description>`, `<TODAY>`, and other placeholders they use today.

**Template rendering rule** (used by the skill body in both the diff phase and the apply phase): read the template source file as a string; for each `<placeholder>` token in the template, substitute the corresponding value from `project_inputs`. The substitution is a literal string-replace; nested placeholders are not supported. Unrecognized `<placeholder>` tokens (present in the template but absent from `project_inputs`) are replaced with an empty string. Callers must not rely on a missing placeholder to preserve literal angle-bracket text; any literal `<...>` text in template output must use an HTML-escaped form or a non-placeholder-looking pattern. For sections that depend on detected languages (e.g., the Toolchain block in `CLAUDE.md`, the per-language BEST_PRACTICES blocks), the template uses named conditional regions (e.g., `<!--lang:rust-start-->...<!--lang:rust-end-->`) that the renderer includes when the corresponding language is detected. Conditional regions and their delimiter comments are stripped from the rendered output; the canonicalize function operates on the rendered output, not the template.

This extraction is what makes hashing the canonical templated content possible (the template source becomes a single file the manifest can reference). The renderer is a small function inside `skills/sync/SKILL.md` (~30 lines) implementing the literal-substitution and conditional-region semantics described above. The skill is not language-agnostic about *how* templates are written — it owns the template format end-to-end.

The existing inline template prose in `skills/sync/SKILL.md` Step 5 (templates for CLAUDE.md, BEST_PRACTICES.md base, BEST_PRACTICES.md per-language additions, README.md, CONTRIBUTING.md, ARCHITECTURE.md, settings.json, settings.local.json, mise.toml, the GitHub templates, and the CI workflow jobs) is deleted from the skill body and replaced with references to the corresponding template file. The skill body shrinks by roughly 600 lines as a result; the manifest plus the templates carry the content instead.

### Step 5.5 — Rewrite sidecar if any JSON artifact's marker advanced

After all artifacts have been processed in Step 5, check whether any JSON-format artifact's marker was updated (i.e., the apply phase wrote a new marker to the sidecar for any JSON artifact). If yes, rewrite `.claude/.bootstrap-versions.json` in full with all current marker entries — including any entries that were not changed in this run. This is the only write that touches the sidecar; do not update it piecemeal during the apply loop. If no JSON artifact's marker changed, the sidecar is not rewritten (its mtime is preserved, which verifies the no-op property in Verification step 4).

### Step 6 — GitHub artifacts (unchanged surface, manifest-aware internals)

The existing Step 6 (GitHub metadata, `.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md`) becomes a no-op when the GitHub-related artifacts are already listed in the manifest — those artifacts are handled by the Step 4–5 diff/apply flow like any other artifact. The only Step 6 logic that remains as a separate step is the **GitHub repository metadata update** via `gh repo edit --description` (Step 6 currently calls this independently of the file-write logic); that block is unchanged because it is not a file operation.

### Step 7 — Set up RFC process

The existing Step 7 logic for `docs/rfcs/.gitkeep` (create if absent) remains as a small "ensure directory exists" check.

The `docs/rfc-process.md` sync logic is **removed from Step 7** — that artifact is now in the manifest with `extension_strategy = "region"` and `region_end_marker = "<!-- END_UPSTREAM_CONTENT -->"`, and is handled by the Step 4–5 flow. The reasoning: the bespoke logic that lived in Step 7 was a one-file implementation of the same pattern the new diff engine generalizes; consolidating eliminates the special case.

The user-visible behavior of `/rfc-update` (which runs the same `docs/rfc-process.md` sync as a standalone skill) is unchanged. `skills/rfc-update/SKILL.md` is updated to consume the manifest entry (Step 2 of that skill reads the manifest, fetches the `docs/rfc-process.md` artifact, runs the same `region` merge strategy, and applies it). This eliminates the duplicated `END_UPSTREAM_CONTENT` parsing logic that currently exists in both `skills/sync/SKILL.md` Step 7 and `skills/rfc-update/SKILL.md` Step 2.

### Step 8 — Report

The existing Step 8 report table is updated to use the new outcome categories. For each artifact in the diff result, the report shows the outcome:

| File | Outcome |
|------|---------|
| `CLAUDE.md` | fast-forward applied (plugin: agent delegation table updated) |
| `docs/BEST_PRACTICES.md` | fast-forward applied (plugin: new entries in ## Testing) |
| `docs/rfc-process.md` | fast-forward applied (## Project Extensions preserved) |
| `.claude/settings.json` | conflict resolved (chose: Keep local — re-runs will re-prompt) |
| `.github/workflows/ci.yml` | added |
| ... | unchanged (collapsed: 8 files) |

For conflicts where the user chose `Merge into local manually`, the report includes the path to the scratch files:
```
.claude/settings.json — manual merge requested
  See:  .claude/sync-conflict-claude-settings-json.txt
        .claude/sync-local-claude-settings-json.txt
  Re-run /sync after merging.
```

For `Skip for now`, the report explicitly calls out the count of deferred conflicts and reminds the user they will re-surface on the next run.

### Plugin maintainer workflow: regenerating the manifest

After editing any artifact in `.claude-plugin/scripts/templates/` (or the source for a non-templated artifact like `agents/*.md`), the maintainer runs:

```bash
.claude-plugin/scripts/build-manifest.sh
```

The script:
1. Walks `.claude-plugin/scripts/templates/` and the other artifact source paths declared in the script.
2. For each artifact, computes the `template_sha` (templated files) or `sha256` (non-templated files).
3. Updates `.claude-plugin/bootstrap-manifest.json` with the new hashes, preserving the `upstream_key`, `extension_strategy`, `owned_sections` / `owned_paths`, and `templated` / `template_inputs` declarations from the existing manifest.
4. Validates that every artifact source referenced in the manifest exists and is readable.

If the maintainer adds a new artifact, they edit the manifest directly to add the new entry (with `upstream_key`, `source`, `target`, `extension_strategy`, etc.) and run `build-manifest.sh` to compute the hash. The script never invents `upstream_key` or `extension_strategy` values — those are maintainer judgment.

The `.claude-plugin/hooks/pre-commit/manifest-check.sh` script runs `build-manifest.sh --check`, which computes the expected manifest in memory and exits non-zero if it differs from the committed manifest. Maintainers wire this into their pre-commit hook (the bytewyrd plugin already ships a settings.json hooks block; this hook is added there for the plugin repo specifically — not propagated to consumer projects, since consumers do not edit the manifest).

The script content (`.claude-plugin/scripts/build-manifest.sh`):

```bash
#!/usr/bin/env bash
# Regenerate .claude-plugin/bootstrap-manifest.json from current artifact content.
# Usage: build-manifest.sh           — regenerate in place
#        build-manifest.sh --check    — exit non-zero if regenerated differs from committed
set -euo pipefail

PLUGIN_ROOT="$(git rev-parse --show-toplevel)"
MANIFEST="$PLUGIN_ROOT/.claude-plugin/bootstrap-manifest.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Cross-platform sha256: prefer sha256sum, fall back to shasum -a 256.
hash_file() {
  local f="$1"
  if command -v sha256sum >/dev/null; then
    sha256sum "$f" | cut -d' ' -f1
  else
    shasum -a 256 "$f" | cut -d' ' -f1
  fi
}

# Walk the existing manifest, recompute each artifact's sha256 from its source path.
# For templated artifacts (templated == true), the field name is template_sha;
# for non-templated artifacts, it is sha256. The script preserves all other fields
# (upstream_key, source, target, extension_strategy, owned_sections, owned_paths,
#  templated, template_inputs) from the existing manifest.

jq -c '.artifacts[]' "$MANIFEST" \
  | while read -r artifact; do
      source_rel=$(echo "$artifact" | jq -r '.source')
      source_abs="$PLUGIN_ROOT/$source_rel"
      if [[ ! -f "$source_abs" ]]; then
        echo "manifest references missing source: $source_rel" >&2
        exit 2
      fi
      full_hash=$(hash_file "$source_abs")
      # Manifest stores the full 64-char hash; the diff engine truncates to 12 at marker-write time.
      templated=$(echo "$artifact" | jq -r '.templated // false')
      field=$([[ "$templated" == "true" ]] && echo "template_sha" || echo "sha256")
      # Emit the updated artifact JSON on stdout.
      echo "$artifact" | jq --arg h "$full_hash" --arg f "$field" '.[$f] = $h'
    done \
  | jq -s '{artifacts: (sort_by(.upstream_key))}' > "$TMP"

if [[ "${1:-}" == "--check" ]]; then
  if ! diff -q "$MANIFEST" "$TMP" >/dev/null; then
    echo "bootstrap-manifest.json is stale; run .claude-plugin/scripts/build-manifest.sh to regenerate." >&2
    diff "$MANIFEST" "$TMP" >&2 || true
    exit 1
  fi
  exit 0
fi

mv "$TMP" "$MANIFEST"
echo "Regenerated $MANIFEST"
```

The script is intentionally simple: read the existing manifest for structural metadata (`upstream_key`, `source`, `target`, `extension_strategy`, `owned_sections`, `owned_paths`, `templated`, `template_inputs`), recompute the content hash for each artifact's source file, and write back a sorted, pretty-printed manifest. It does not invent new artifacts and it does not mutate non-hash fields. The script's contract is: **given the current artifact sources, produce a deterministic manifest JSON whose hashes match the current source content.**

If a maintainer needs to add a new artifact, they edit `.claude-plugin/bootstrap-manifest.json` by hand to add the entry (with placeholder `sha256: ""` or `template_sha: ""`), then run `build-manifest.sh` to populate the hash. The script never invents `upstream_key` or `extension_strategy` values — those are maintainer judgment.

### Cross-platform compatibility (SHA-256, JSON / TOML parsing)

The skill body executes inside Claude Code, which runs on macOS, Linux, and (via WSL or remote dev containers) Windows. All sha computation and parsing must use tools present in the standard Claude Code Bash environment.

- **SHA-256:** prefer `sha256sum` (Linux); fall back to `shasum -a 256` (macOS). The skill detects platform with `uname -s` and selects the command; the output is uniformly the first 12 hex characters of the hash.
- **JSON parsing / serialization:** the skill uses `jq` (present in standard Claude Code envs); the rendering of merged JSON files goes through `jq --indent 2` for stable formatting.
- **TOML parsing / serialization:** the skill uses the `python3 -c "import tomllib, json; ..."` one-liner for parsing (Python 3.11+ ships `tomllib`); for serialization, the skill renders TOML by hand using a small generator (`mise.toml` and `rust-toolchain.toml` are the only TOML files and both have simple, fixed shapes).
- **`.gitignore` parsing:** line-oriented; the skill uses standard Bash `while read` plus regex for tag-comment detection.

If a required tool is missing (`jq`, `sha256sum`/`shasum`, `python3`), Step 4 stops with: `"/sync requires <tool> for diff computation. Please install <tool> and re-run."` This is a precondition, checked at the start of Step 4 alongside the existing `git rev-parse` / `git config user.name` checks in Step 1.

### Step 1 — Pre-flight additions

Add to the existing Step 1 environment validation:

```bash
# Required for /sync diff computation
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "sha256sum or shasum required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required for TOML parsing" >&2; exit 1; }
```

If any command is missing, stop with an error message naming the missing tool and a one-line install hint (`brew install jq`, `apt install jq`, etc.).

### Migration path for existing consumer projects

On the first `/sync` run after a project upgrades to a plugin version that ships this RFC, all plugin-managed files exist locally without markers. Step 4's diff classifies them as `unchanged_legacy` (content matches plugin current) or `conflict_legacy` (content differs).

For `unchanged_legacy`: the file content is bit-equal to the plugin's current content. No prompt needed; these files are listed in the Step 4 summary under "Legacy marker injection" for visibility, then Step 5 silently re-writes each file with the marker added, reporting `unchanged (legacy marker added)`. This is a one-time rewrite to put the marker in place.

For `conflict_legacy`: the user is prompted with the four standard options plus the fast-path `Adopt plugin and add marker (recommended if you haven't customized this file)`. The fast-path adopts the plugin's content (which may include legitimate plugin updates the user wants) and stamps the marker; users who have intentionally customized a file pick one of the other options and proceed with proper conflict resolution from there.

The first-run report includes a one-time banner:

```
This is the first /sync run after an upgrade that adds per-file content tracking.
Existing plugin-managed files have been classified by comparing local content
against the plugin's current shipped content. Files that match exactly were
silently marked. Files that differ are listed under "Conflicts (legacy)" — pick
"Adopt plugin and add marker" for any file you have not intentionally edited.
Future runs will only flag files that genuinely diverged.
```

### Verification

After implementation, run these checks to confirm correctness:

1. **Manifest builds cleanly on the plugin repo:**

   ```bash
   .claude-plugin/scripts/build-manifest.sh
   git diff --exit-code .claude-plugin/bootstrap-manifest.json
   ```

   Expected: the second command exits 0 (no diff — the manifest was already up to date).

2. **Pre-commit hook fires on stale manifest:**

   ```bash
   # Simulate: edit an artifact source without regenerating manifest
   echo "" >> .claude-plugin/scripts/templates/CLAUDE.md.tpl
   .claude-plugin/scripts/build-manifest.sh --check
   ```

   Expected: exits non-zero with "bootstrap-manifest.json is stale" message.

3. **New project — first `/sync` run writes markers:**

   In an empty repo, run `/sync`. Open `CLAUDE.md`; line 2 should be `<!-- bootstrap-content-version: bytewyrd/CLAUDE.md@v1:<12-hex-chars> -->`. Same for every plugin-managed Markdown file. For TOML and `.gitignore` files, the marker appears as a `#` comment on line 1. For JSON files, the marker is NOT in the file itself — check `.claude/.bootstrap-versions.json` to see the per-file markers for JSON artifacts.

4. **Re-run on up-to-date project is a no-op:**

   Immediately after the first run, re-run `/sync`. Expected report: every file shows `unchanged`; no AskUserQuestion is invoked.

5. **Plugin update produces a fast-forward:**

   In the plugin repo, edit one artifact (e.g., add a new entry to `CLAUDE.md.tpl`'s agent delegation table). Run `build-manifest.sh`. In a consumer project, run `/sync`. Expected: one file in `Fast-forward updates`; Step 4a asks one batch question; user approves; the file is rewritten with the new content and an updated marker.

6. **User local edit in a non-owned section is preserved:**

   In a consumer project, add a new section `## My Custom Notes` to `CLAUDE.md` (a section the plugin does not own — i.e., not in the manifest's `owned_sections` list for the `CLAUDE.md` artifact). Run `/sync`. Expected: `CLAUDE.md` classified as `unchanged` (the canonical-form hash over only the owned sections is still equal to `local_ancestor_sha`); the `## My Custom Notes` section is preserved verbatim. If the plugin had concurrently updated a plugin-owned section, expected: classification is `fast_forward`, the user approves, the owned sections are replaced, and `## My Custom Notes` is still preserved verbatim.

7. **Conflict in an owned section produces a prompt:**

   In a consumer project, edit a *plugin-owned* section of `CLAUDE.md` (e.g., the `## Agent delegation` table). In the plugin repo, also edit the same section and rebuild the manifest. In the consumer project, run `/sync`. Expected: `CLAUDE.md` listed under `Conflicts`; Step 4b asks one AskUserQuestion; the four resolution options are presented; the chosen action is applied correctly.

8. **`region` strategy preserves `## Project Extensions`:**

   In a consumer project, add content to the `## Project Extensions` section of `docs/rfc-process.md`. In the plugin repo, edit the core rfc-process.md content and rebuild the manifest. In the consumer project, run `/sync`. Expected: `docs/rfc-process.md` listed under `Fast-forward updates` (the `## Project Extensions` content is untouched, only the upstream region changes); after approval, the file is rewritten with the new upstream content + the preserved `## Project Extensions` section.

9. **`structured` strategy preserves user-added `permissions.allow` entries:**

   In a consumer project, add a custom entry like `"WebFetch(domain:example.com)"` to `permissions.allow` in `.claude/settings.local.json`. In the plugin repo, add a new entry to the plugin-shipped permissions list and rebuild the manifest. In the consumer project, run `/sync`. Expected: `.claude/settings.local.json` listed under `Fast-forward updates`; after approval, the new plugin entry is added and the user's custom entry is still present.

10. **Conflict scratch files for manual merge:**

    Trigger a conflict on `.claude/settings.json`. Choose `Merge into local manually`. Expected: `.claude/sync-conflict-claude-settings-json.txt` and `.claude/sync-local-claude-settings-json.txt` are written; the report includes the paths; the target file is not modified.

If any verification step fails, the failure points to one of: (a) marker format mismatch (the parser cannot find the marker on line 2 because it was written incorrectly), (b) canonical-form hash mismatch (the diff engine is hashing different content than the marker recorded — usually a marker-line stripping bug), (c) section/path identification mismatch (the manifest's `owned_sections` / `owned_paths` does not match the file's actual structure), or (d) cross-platform tool selection (sha256sum on Linux, shasum on macOS).

## Risks and open questions

- **Risk: a plugin maintainer ships a manifest where `sha256` does not match the artifact's actual content.** This produces a phantom fast-forward for every consumer (the local file matches the plugin source but the manifest's sha is wrong, so the diff engine sees a "change" and prompts). **Mitigation:** the `manifest-check.sh` pre-commit hook prevents this from being committed. Defense in depth: the `build-manifest.sh` script is idempotent and runnable by anyone — if a consumer hits a phantom fast-forward, they can ask the maintainer to regenerate.

- **Risk: a plugin update changes the `owned_sections` list (e.g., renames `## Agent delegation` to `## Agents`).** Existing consumer files have the old section heading; the new manifest looks for the new heading and does not find it. The diff engine classifies the file as "old heading section present but not owned" plus "new heading section absent" → likely treats the file as a conflict on every consumer. **Mitigation:** the manifest entry can include an `aliases` field (`owned_sections_aliases: { "## Agents": ["## Agent delegation"] }`); during diff, the engine treats any aliased heading as equivalent to the canonical one for the purpose of section identification, and on write replaces the old heading with the new canonical name. Captured as a follow-up in the Implementation spec — alias support is added in a second commit once the base path is working.

- **Open question: should `section` strategy support sub-headings (H3, H4)?** The current spec treats H2 as the section boundary; an `## H2` containing an `### H3` is one section, body is the H3 + H3 body (the current rule uses H2-only boundaries as specified above; see `owned_sections_level` open question for future extension). This works for the current `CLAUDE.md` and `BEST_PRACTICES.md` structures, but a future file that wants finer-grained ownership might need H3 boundaries. **Resolution within this RFC:** keep H2-only for now. If a future artifact needs H3 ownership, add an `owned_sections_level` field (default `2`) to the manifest entry. Not implementing it preemptively avoids cost for a hypothetical case.

- **Open question: what happens if the consumer's project name changes after the initial `/sync`?** Templated artifacts re-render at sync time with the new project_name; their `rendered SHA` changes; but the `template_sha` is the same (the template did not change). The diff engine compares the local file's content to the re-rendered template output; differences in templated values would be detected as content differences. **Resolution within this RFC:** templated values that come from `docs/project-brief.md` (project_name, description) are already kept in sync by the existing brief→docs propagation rule from the prior RFC. The diff engine handles a project rename as a fast-forward on every templated artifact (because the local content has the old name, and the re-rendered template has the new name — local content differs from re-rendered template, but the local content's marker matches the plugin's template_sha, so it's a fast-forward not a conflict). This is the correct behavior: the user changes the brief; `/sync` propagates to all templated artifacts; the user confirms the batch.

- **Open question: should the user be able to ask `/sync` for verbose output?** The default report collapses unchanged and local-only categories to counts. A user who wants to see every file's classification (for debugging or for an audit trail) has no option today. **Resolution within this RFC:** out of scope. The default report is the baseline; a future RFC can add a `--verbose` flag (or a separate `/sync-status` skill that runs the diff without applying anything).

- **Open question: how does `/sync` interact with a project that uses multiple plugins, each with their own manifest?** Today only the bytewyrd plugin ships a `/sync`; if another plugin also adds a `/sync` skill, the two would conflict at the slash-command level. **Resolution within this RFC:** out of scope. The bytewyrd plugin's `/sync` reads its own manifest at `.claude-plugin/bootstrap-manifest.json` (relative to `$CLAUDE_PLUGIN_ROOT`). If a future plugin ships its own `/sync`, the two skills would need to be reconciled at the user level — a problem this RFC does not need to solve.

- **Risk: large files (e.g., BEST_PRACTICES.md after many sync updates) may have many owned sections, making the section-merge logic slow.** The current `BEST_PRACTICES.md` template has ~12 owned sections; doubling that is plausible over time. **Mitigation:** none needed at current scale. The section-merge work is O(n) in section count and O(m) in file bytes; both are small. If a file ever exceeds 100 KB or 50 owned sections, revisit.

- **Risk: the merge logic for `structured` JSON files is non-trivial — preserving key order, handling deeply-nested paths, dealing with array-element identification.** Bugs here lose user data (e.g., a permission entry the user added gets dropped). **Mitigation:** the merge logic is precisely specified above (sorted keys via `jq --sort-keys`, array entries identified by `_meta.bytewyrd_hook_id` for id-based merge and by element equality for set-union merge); the verification checklist in the spec includes specific tests for each merge case. The manifest schema is conservative — files start with `extension_strategy = "whole"` if their merge semantics are unclear; only files with proven structural-merge needs (settings.json, settings.local.json, mise.toml, .gitignore) get `structured`.

- **Risk: Claude Code may reject or warn about the `_meta.bytewyrd_hook_id` field inside individual hook entries.** The Claude Code hooks schema is documented as accepting `type`, `command`, `matcher`, `timeout`, `statusMessage`, `if`, etc. Adding an unknown sibling key (`_meta`) at the entry level *should* be tolerated since the hooks schema permits forward-compatible fields, but this is not formally guaranteed. **Mitigation:** if Claude Code rejects the field, the fallback is to track hook ownership via a sidecar file (similar to the `.bootstrap-versions.json` sidecar used for whole-file versions). The sidecar would list `{ hook_index → bytewyrd_hook_id }` for each managed array. This adds complexity but is a contained fallback. Verification step 1 of the implementation (running `/sync` on a fresh repo and confirming Claude Code does not warn on startup) catches the issue before it ships. If the field is rejected, the implementation switches to the sidecar approach and the spec is updated in a follow-up RFC.

- **Open question: should the conflict prompt for legacy files default to `Adopt plugin and add marker`?** The fast-path is "recommended if you haven't customized this file," and most users haven't. AskUserQuestion does not natively support "default selection on Enter" — the user always picks an option. **Resolution within this RFC:** keep the order as listed (Adopt plugin / Keep local / Merge / Skip / Adopt-and-mark-legacy). The fast-path option is last so a user who reads the prompt sees the four standard options first and only reaches for the fast-path if they recognize their situation.

- **Open question: how is the upstream manifest fetched in environments where `$CLAUDE_PLUGIN_ROOT` is set to a remote checkout (e.g., GitHub-installed plugin)?** Step 1 of the current `/sync` already handles this via `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}`. The manifest lives at `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/bootstrap-manifest.json`; the templates live at `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/scripts/templates/`. Both paths resolve identically regardless of how the plugin was installed. **No risk** — the existing path resolution is sufficient.

## Relationship to other RFCs

This RFC builds on and modifies several recent RFCs:

- **`2026-05-10-project-brief-sync-source-of-truth`** (status: Done) — established `docs/project-brief.md` as the single source of truth for project identity, with `/sync` propagating identity values into `CLAUDE.md` and `README.md`. This RFC preserves that mechanism: templated artifacts continue to use `project_name` and `description` from the brief as template inputs; the diff engine sees a brief edit as a fast-forward on every templated artifact (which is the correct, documented behavior of brief→docs propagation).

- **`2026-05-09-best-practices-content-and-tooling`** (status: Done) — established the verb-suffix naming convention for the `/best-practices-*` skill family and the content structure of `docs/BEST_PRACTICES.md`. This RFC preserves the `## Project-Specific` section as a user-owned section (declared as such in the manifest entry for `docs/BEST_PRACTICES.md`); the section is never overwritten by `/sync`, matching the existing contract.

- **`2026-05-10-best-practice-extraction-principles`** (status: Done) — established the triage and lift principles for promoting global best-practice entries into the plugin's distributed content. This RFC does not interact with the `/best-practices-*` skill family directly — those skills modify `~/.claude/BEST_PRACTICES.md` (global) and `skills/sync/SKILL.md` (plugin sync content), neither of which is a consumer-repo file. The diff engine handles `docs/BEST_PRACTICES.md` (the consumer-repo file) with the `section` strategy, which is downstream of the best-practices pipeline.

- **`/rfc-update` skill** — currently implements a one-file version of the same pattern this RFC generalizes. This RFC consolidates the bespoke logic into the new diff engine; `/rfc-update` is updated to consume the manifest entry for `docs/rfc-process.md` and apply the `region` merge strategy. The user-visible behavior of `/rfc-update` is unchanged (it still updates only the rfc-process.md file, still preserves `## Project Extensions`). Internally, the skill becomes a thin wrapper that calls into the same shared diff-and-merge primitives that `/sync` uses for all artifacts.

- **Future RFC — `/agents-diff`** (captured in `docs/rfc-braindump.md`) — proposed read-only diff for vendored agent definitions in `agents/`. The current RFC's diff engine is general enough that `/agents-diff` could be implemented as `/sync --dry-run --filter agents/` (a future enhancement); the manifest can carry agent files as artifacts with `extension_strategy = "whole"` once the project decides to manage them through the same flow. This RFC does not add agent files to the manifest (the project's current posture, per the `/refactor` RFC, is that agent files are locally owned and not synced); the door stays open for the future RFC to bring them in.
