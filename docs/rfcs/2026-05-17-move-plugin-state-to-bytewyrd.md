---
rfc: "2026-05-17-move-plugin-state-to-bytewyrd"
title: "Move plugin state to .bytewyrd/ and commit version tracking"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Carve out a dedicated `.bytewyrd/` directory at the project root for all bytewyrd-plugin-generated state, separate plugin state from Claude Code's `.claude/` namespace, and commit the version-tracking files (bootstrap sidecar, installed plugin version, last-`/sync` timestamp, docs-agent version marker) like a lockfile so teams see plugin state changes in PRs. Ephemeral runtime sentinels (`precompact-extraction-done`, `last-feature-engineer-stop`) stay under the same `.bytewyrd/` directory but remain gitignored via an allowlist `.gitignore` policy that explicitly enumerates the gitignored sentinel filenames and commits everything else under `.bytewyrd/`. `enabledPlugins`, `hooks`, `extraKnownMarketplaces`, and `permissions` remain in `.claude/settings.json` (Exa: https://code.claude.com/docs/en/configuration confirms Claude Code reads these from `.claude/settings.json` at project scope and `~/.claude/settings.json` at user scope — they cannot move). `/sync` is updated to target `.bytewyrd/` for all sidecar writes and to run a one-shot migration step on first invocation against an existing project: read the legacy `.claude/.bootstrap-versions.json`, write it to `.bytewyrd/bootstrap-versions.json` byte-equivalent, `git rm` the legacy path (using `git rm --cached --ignore-unmatch` to handle both committed and untracked legacy files), and update `.gitignore` from the blanket `.bytewyrd/` exclusion to the explicit sentinel allowlist. The migration is idempotent — re-running `/sync` on a post-migration project is a no-op for everything in this RFC.

## Should we do this?

**Yes.** Today bytewyrd plugin state is split across two locations with no team-visible audit trail:

- **Plugin-state files inside Claude Code's namespace** — `.claude/.bootstrap-versions.json` is the plugin's content-hash sidecar (verified: `.claude-plugin/bootstrap-manifest.json:6` declares `target: ".claude/.bootstrap-versions.json"`; verified: `skills/sync/SKILL.md:295` reads it; verified: `skills/sync/SKILL.md:698` rewrites it). The file is in the wrong namespace — `.claude/` is Claude Code's settings tree (Exa: https://code.claude.com/docs/en/claude-directory), not bytewyrd's. The mis-naming causes ongoing friction: a developer scanning `.claude/` for a settings problem sees a `.bootstrap-versions.json` file with no obvious owner and has to read the sync skill to understand it. The `/sync` skill itself has to special-case the file (verified: `skills/sync/SKILL.md:309` reads "skipping the `.bootstrap-versions.json` sidecar entry itself" because the file is both a manifest artifact and the storage for marker tracking — that recursion was forced by colocating with `.claude/`).

- **Some plugin-state files already under `.bytewyrd/`, but gitignored as a blanket** — `.bytewyrd/precompact-extraction-done` (verified: `skills/best-practices-extract/SKILL.md:272`, `.claude/settings.json:16` and `.claude/settings.json:26`), `.bytewyrd/last-feature-engineer-stop` (verified: `hooks/hooks.json:13`, `.claude-plugin/hooks/hooks.json:13`), and `.bytewyrd/docs-agent-version` (verified: `skills/sync/SKILL.md:100` and `skills/sync/SKILL.md:113`) all live there today. The directory is excluded wholesale by the `.bytewyrd/` line in `.gitignore` (verified: `.gitignore:5`), so even files that *should* be committed are not. This produces three concrete problems:
  1. **No reviewable trail of plugin upgrades.** When `/sync` advances the recorded `docs-agent-version` from `2026-05-10-initial` to `2026-06-04-coverage-passes`, that change is invisible in PRs — the file is gitignored. Reviewers cannot see "this PR updated the bytewyrd plugin's docs-agent version" because there is no committed file recording it.
  2. **No way to check `git status` and notice an installed-version drift.** The plugin ships `version: "0.2.0"` in `.claude-plugin/plugin.json` (verified: `.claude-plugin/plugin.json:4`). Today there is a `.bytewyrd/plugin-version` file containing `0.2.0` (verified: `cat .bytewyrd/plugin-version` returns `0.2.0`), but no code reads or writes it (verified: `grep -rn "plugin-version" skills agents hooks scripts .claude-plugin` returns no matches against the plugin-version filename other than this RFC itself). It was created by something, is gitignored, and serves no current purpose. Promoting it to a tracked file written by `/sync` makes it useful.
  3. **No `last-sync` timestamp.** The team cannot answer "when did this project last run `/sync`?" without grepping git log for the SHA of a tracked file the plugin happens to touch. A committed timestamp file fills that gap immediately and gives PR reviewers a one-line answer to "is this project on a recent plugin version?".

The fix shape — dedicated namespace, commit the durable files, gitignore only the truly ephemeral sentinels — is the standard lockfile pattern (Exa: https://classic.yarnpkg.cn/blog/2016/11/24/lockfiles-for-all "Lockfiles lock the versions for every single dependency you have installed. This prevents 'Works On My Machine' problems"; Exa: https://safeguard.sh/resources/blog/package-lock-files-security-implications "If your lock file is in `.gitignore`, every CI build and every developer machine resolves dependencies independently. You have zero reproducibility guarantees"). The bytewyrd plugin's bootstrap sidecar and version markers are conceptually identical to a lockfile: they record the plugin-rendered SHA12 hashes that `/sync` reads on the next run to decide whether a file is `fast_forward`, `local_only`, `conflict`, etc. Today that lockfile-shaped data is either misplaced (`.claude/.bootstrap-versions.json`) or gitignored (`.bytewyrd/docs-agent-version`). Both fixes are small, both are mechanical, both improve the diff-engine's correctness story (a sidecar in `.bytewyrd/` is no longer a manifest artifact under its own namespace, eliminating the special-case at `skills/sync/SKILL.md:309`).

The cost is one `/sync` change (new step + path constants updated), one migration step that runs once per existing project, a manifest update to relocate the sidecar artifact entry, and a `.gitignore` policy change from blanket-exclude to allowlist-gitignore. No new tooling, no schema changes to existing artifacts.

## Current state

The plugin writes state into two locations today, with the following file inventory (every row verified against an actual file in the repo or an actual code reference):

| Path | Purpose | Who writes it | Who reads it | Currently gitignored? |
|------|---------|---------------|--------------|------------------------|
| `.claude/.bootstrap-versions.json` | Per-file SHA12 marker storage for JSON-format artifacts (`.claude/settings.json`, `.claude/settings.local.json`) — the sidecar for entries that cannot carry an in-file `<!-- bootstrap-content-version: ... -->` comment because they are JSON | `/sync` Step 5.5 (verified: `skills/sync/SKILL.md:698`) | `/sync` Step 4's pre-flight diff (verified: `skills/sync/SKILL.md:295`) | No explicit rule, but `.claude/settings.local.json` is gitignored by name (verified: `.gitignore:2`); the sidecar itself is currently *committed* in some projects and *absent* in others (verified in this checkout: `ls .claude/.bootstrap-versions.json` returns "No such file or directory" — the sidecar does not yet exist in the plugin's own repo because `/sync` has not been run here) |
| `.bytewyrd/precompact-extraction-done` | Sentinel file written by `/best-practices-extract` to release the `PreCompact` hook block — its presence means "extraction has run this session, allow the next compaction through" | `/best-practices-extract` Step "Mark Extraction Done" (verified: `skills/best-practices-extract/SKILL.md:272`); also written by `PreCompact` hook on first fire to fail-safe (verified: `.claude/settings.json:26`) | `PreCompact` hook (verified: `.claude/settings.json:26` reads `[ -f .bytewyrd/precompact-extraction-done ]`); `SessionStart` hook deletes it on session start (verified: `.claude/settings.json:16`) | Yes — `.bytewyrd/` blanket-excluded (verified: `.gitignore:5`) |
| `.bytewyrd/last-feature-engineer-stop` | Sentinel file written by `feature-engineer`'s `SubagentStop` hook so the next post-compact `SessionStart` knows a feature-engineer recently finished and can prompt `/docs-review` | Plugin's `SubagentStop` hook (verified: `.claude-plugin/hooks/hooks.json:13`); also the project's mirrored hook (verified: `hooks/hooks.json:13`) | Plugin's `SessionStart compact` hook (verified: `.claude-plugin/hooks/hooks.json:24` reads mtime, computes age, prints reminder if < 86400s); `/docs-review` deletes it on completion (verified: `skills/docs-review/SKILL.md:53`) | Yes — `.bytewyrd/` blanket-excluded (verified: `.gitignore:5`) |
| `.bytewyrd/docs-agent-version` | Project's recorded copy of the plugin's `<!-- docs-agent-version: <id> -->` marker (verified: `agents/docs-agent.md:8` carries the marker `<!-- docs-agent-version: 2026-05-10-initial -->`) — used by `/sync` Step 1.5 to decide whether to print the "docs-agent has improved" suggestion | `/sync` Step 1.5 (verified: `skills/sync/SKILL.md:113` writes via `echo "$PLUGIN_DOCS_VER" > .bytewyrd/docs-agent-version`) | `/sync` Step 1.5 (verified: `skills/sync/SKILL.md:100` reads with `cat .bytewyrd/docs-agent-version`) | Yes — `.bytewyrd/` blanket-excluded (verified: `.gitignore:5`) |
| `.bytewyrd/plugin-version` | Orphaned: file exists in the bytewyrd plugin's own checkout (verified: `cat .bytewyrd/plugin-version` returns `0.2.0`), but no code reads or writes it (verified: `grep -rn "plugin-version" skills agents hooks scripts .claude-plugin` finds no read/write of this filename in any plugin code — the only matches are RFCs and this RFC itself). Probably a leftover from an earlier iteration; not part of the current plugin behavior | Nothing currently | Nothing currently | Yes — `.bytewyrd/` blanket-excluded (verified: `.gitignore:5`) |

The `.gitignore` (verified, full content):

```
.worktrees/
.claude/settings.local.json

# bytewyrd plugin local state (PreCompact sentinel, etc.)
.bytewyrd/
```

The blanket `.bytewyrd/` line on the last code line means *every* file under `.bytewyrd/` is excluded from git, including the files this RFC argues should be committed.

**What stays in `.claude/settings.json` and cannot move (constraint enforced by Claude Code itself):**

Claude Code reads the following fields from `.claude/settings.json` (project scope) and `~/.claude/settings.json` (user scope), with a strict precedence chain (Exa: https://code.claude.com/docs/en/configuration — "Project settings (`.claude/settings.json`): Project-specific plugins shared with team … Project settings take precedence over user settings"):

- `enabledPlugins` — the project-scope list of plugins enabled for everyone who clones the repo (Exa: https://code.claude.com/docs/en/configuration — "Project settings (`.claude/settings.json`): Project-specific plugins shared with team"; verified: `.claude/settings.json:76-81` declares four entries including `bytewyrd@bytewyrd`).
- `hooks` — lifecycle event commands (Exa: https://code.claude.com/docs/en/hooks — "`.claude/settings.json` | Single project | Yes, can be committed to the repo"; verified: `.claude/settings.json:2-74` defines `SessionStart`, `PreCompact`, `PostToolUse`, `Stop` hooks).
- `extraKnownMarketplaces` — additional plugin marketplaces beyond the defaults (verified: `.claude/settings.json:82-89` declares the `bytewyrd` marketplace pointing at `bytewyrd/claude-bytewyrd`; same field documented at https://code.claude.com/docs/en/configuration under "Plugin configuration").
- `permissions` (read from `.claude/settings.local.json` in the gitignored file; the schema is the same per Exa: https://code.claude.com/docs/en/configuration — "Local settings (`.claude/settings.local.json`): Per-machine overrides (not committed)").

These are out-of-scope for this RFC because moving them would mean Claude Code itself stops loading them. The RFC explicitly preserves them in `.claude/settings.json`. The manifest's existing `owned_paths` entries for `.claude/settings.json` — `extraKnownMarketplaces.bytewyrd`, `enabledPlugins.bytewyrd@bytewyrd`, `hooks.PreCompact[]:_meta.bytewyrd_hook_id`, `hooks.PostToolUse[]:_meta.bytewyrd_hook_id`, `hooks.Stop[]:_meta.bytewyrd_hook_id`, `hooks.PreToolUse[]:_meta.bytewyrd_hook_id` (verified: `.claude-plugin/bootstrap-manifest.json:17-23`) — remain untouched.

**Why the existing setup is structurally wrong, not just cosmetic:**

1. The sidecar `target: ".claude/.bootstrap-versions.json"` (verified: `.claude-plugin/bootstrap-manifest.json:6`) is itself a manifest artifact with its own `upstream_key: "bytewyrd/.claude/.bootstrap-versions.json@v1"` (verified: `.claude-plugin/bootstrap-manifest.json:4`). The `/sync` skill has to skip the sidecar entry during the diff loop (verified: `skills/sync/SKILL.md:309` — "For each artifact in the manifest (skipping the `.bootstrap-versions.json` sidecar entry itself)") because trying to compute a hash for a file whose entire purpose is to store hashes would be circular. That special case is direct evidence the sidecar does not belong in the same namespace as the things it tracks. Moving it to `.bytewyrd/bootstrap-versions.json` and keeping its `structured` strategy with `owned_paths: ["*"]` (per the already-Approved RFC `2026-05-14-sync-per-file-extension-strategies` "item 9 of Exact manifest changes" — verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:467` — "**9. `.bootstrap-versions.json` — relocate to `.bytewyrd/`, switch to `structured` strategy, bump `upstream_key` to `@v2`.**") makes the sidecar a regular structured artifact in its own namespace.

2. The `.bytewyrd/` blanket-exclude in `.gitignore` mixes two different kinds of files (ephemeral session sentinels vs. durable version markers) and excludes both. The fix — allowlist the sentinels, commit the rest — is one of the standard `.gitignore` patterns (negated pattern lines: `!` prefix to re-include a previously-excluded path; this is a documented git feature, Exa: https://classic.yarnpkg.cn/blog/2016/11/24/lockfiles-for-all "There is a simple universal rule that everyone should follow with Yarn: ... Please commit your `yarn.lock` files" — the analogue here is `.bytewyrd/bootstrap-versions.json` and the version markers).

3. The Approved RFC `2026-05-14-sync-per-file-extension-strategies` (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:5` — `status: "Approved"`) already calls out the sidecar move from `.claude/.bootstrap-versions.json` to `.bytewyrd/.bootstrap-versions.json` as item 9 of its "Exact manifest changes" enumeration (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:467` — "**9. `.bootstrap-versions.json` — relocate to `.bytewyrd/`, switch to `structured` strategy, bump `upstream_key` to `@v2`.**"). This RFC complements `2026-05-14` by handling the parts that RFC does not address: the directory-wide naming convention, the lockfile-style commit policy (with an allowlist `.gitignore` instead of a negated-pattern `.gitignore`), the migration of the other version markers (`docs-agent-version`, `plugin-version`, `last-sync`), and the file-naming normalization (dropping the leading dot since `.bytewyrd/` is itself dot-prefixed — `bootstrap-versions.json`, not `.bootstrap-versions.json`). See "Relationship to other RFCs" below.

## Analysis / Options

Three coupled decisions: (1) which directory holds plugin state, (2) what gets committed vs. gitignored, and (3) how existing projects migrate.

### Decision 1 — State directory

**Option A — `.bytewyrd/` (recommended).** A dedicated, plugin-namespaced directory at the project root. The directory already exists in practice (verified: `ls .bytewyrd/` shows it on disk in this checkout; verified: `.gitignore:5` lists it). The plugin already references it from four code paths (hooks, two skills). The migration cost is the smallest of any option because three of the five tracked files already live there. The name is unambiguous about ownership — anyone reading the project root sees `.bytewyrd/` and knows the directory is bytewyrd-plugin-owned.

**Option B — `.claude/bytewyrd/` (rejected).** Nest the plugin's state under Claude Code's namespace. Rejected because it inverts the ownership story: `.claude/` is Claude Code's settings tree (Exa: https://code.claude.com/docs/en/claude-directory — "Where Claude Code reads CLAUDE.md, settings.json, hooks, skills, commands, subagents, rules, and auto memory"), not bytewyrd's. Putting plugin state under `.claude/` re-introduces the problem this RFC is trying to fix (mixed-ownership namespace, special-case sidecar). It also conflicts with Claude Code's own future evolution: if Claude Code ever adds a `bytewyrd` subdirectory to its own settings tree (vendor extension, marketplace cache, etc.), the names collide.

**Option C — `.plugins/bytewyrd/` (rejected).** Generic per-plugin namespace, future-proof for a hypothetical world where many plugins land state files at the project root. Rejected because no other plugin in the bytewyrd ecosystem currently does this, and inventing a multi-plugin convention without other plugin participants is over-engineering for one plugin's needs. If a future plugin needs the same pattern, a follow-up RFC can promote `.bytewyrd/` to `.plugins/bytewyrd/` with the same migration shape this RFC defines — the cost is identical.

**Recommendation: Option A.** `.bytewyrd/`. The directory is already in use; the name is already in the gitignore and in skills/hooks. The plugin is the only plugin that ships this convention, so the namespace match (one plugin, one directory) is the simplest tenable design.

### Decision 2 — Commit vs. gitignore policy

The five files have two natural commit policies:

- **Commit (durable state — reviewable, reproducible):** `bootstrap-versions.json` (sidecar), `plugin-version` (installed plugin version), `last-sync` (timestamp of last `/sync` run), `docs-agent-version` (last-recorded plugin docs-agent marker).
- **Gitignore (ephemeral session sentinels — recreated per session):** `precompact-extraction-done`, `last-feature-engineer-stop`.

The criterion is: *will the file change as a side effect of running a session (vs. an explicit plugin upgrade)?* Sentinels change with every session; version markers change only when `/sync` runs explicitly.

**Option A — `.gitignore` allowlist: `.bytewyrd/` blanket-exclude is replaced by per-file exclusions (recommended).**

Replace the existing `.bytewyrd/` line with explicit entries for the ephemeral files:

```
# bytewyrd plugin runtime sentinels (recreated per session — do not commit)
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop
```

Everything else under `.bytewyrd/` (the four durable files) becomes tracked by git automatically. The advantage is explicit enumeration: a reviewer reading `.gitignore` sees exactly which files are excluded and why. New files added under `.bytewyrd/` are committed by default — the secure-by-default direction. If a future skill adds a new ephemeral sentinel, the author must add an explicit line to `.gitignore` (a small visible cost) rather than relying on a blanket rule (an invisible cost where the file becomes secretly committed and breaks the team's git history).

**Option B — Negated pattern: `.bytewyrd/` blanket-exclude with `!` re-include lines for the durable files (rejected).**

```
.bytewyrd/
!.bytewyrd/bootstrap-versions.json
!.bytewyrd/plugin-version
!.bytewyrd/last-sync
!.bytewyrd/docs-agent-version
```

This is a valid git pattern but inverts the safe default: new files added under `.bytewyrd/` are gitignored unless the author remembers to add a `!` line. A future skill author who adds a new version marker without updating `.gitignore` ships a file the team cannot see. Reverse this: making "committed" the default and "gitignored" the explicit exception aligns the friction with the cost (forgetting to commit a sentinel is harmless; forgetting to commit a version marker silently breaks the audit trail this RFC is trying to create).

**Option C — Two directories: `.bytewyrd/` for committed, `.bytewyrd-cache/` for gitignored (rejected).**

Splits the plugin's footprint at the project root. Doubles the directory count for marginal value (the explicit gitignore allowlist in Option A makes the categorization equally clear with one directory). Rejected on cosmetic-cost grounds — one plugin-owned directory at the project root is enough.

**Recommendation: Option A.** Allowlist the ephemeral sentinels by name; commit everything else under `.bytewyrd/`. The new `.gitignore` entry pair becomes the canonical place a developer learns which `.bytewyrd/` files are ephemeral.

### Decision 3 — Migration

A migration step is needed because existing consumer projects have:

- `.claude/.bootstrap-versions.json` either committed (if a project ran a pre-RFC `/sync`) or absent (fresh install). The committed-file case must `git rm` the old path and re-add the file at `.bytewyrd/bootstrap-versions.json`, preserving its current content byte-for-byte.
- A `.gitignore` with the blanket `.bytewyrd/` line. The line must be replaced with the new allowlist pair.
- Possibly an orphaned `.bytewyrd/plugin-version` file (verified in this checkout: `cat .bytewyrd/plugin-version` returns `0.2.0`) that needs to be reconciled with the new `/sync`-managed file: read the existing content, treat it as a valid "previously installed version" marker, and adopt it; if absent, write the current value from `.claude-plugin/plugin.json`.

**Option A — Inline migration step in `/sync` Step 0 (recommended).**

Add a "Step 0 — Migrate legacy plugin state" that runs at the top of every `/sync` invocation. The step is idempotent: it inspects the working tree, performs whichever moves and rewrites are needed to bring the project from the pre-RFC state to the post-RFC state, and does nothing if the project is already post-RFC. Step 0 is documented in the implementation spec below; its exact commands and expected outputs are listed there.

The advantage of inline migration is that it runs whenever a project upgrades the plugin — there is no separate "run the migration script" instruction the user has to remember. Existing `/sync` users get the migration automatically the first time they run `/sync` after this RFC ships.

**Option B — Standalone migration script (rejected).**

Add a `scripts/migrate-bytewyrd-state.sh` (or similar) that the user runs manually once after the plugin updates. Rejected because it creates a manual step that users will forget, and forgetting it produces a worse failure mode than the current state (the project ends up with both `.claude/.bootstrap-versions.json` and `.bytewyrd/bootstrap-versions.json`, and `/sync` Step 5.5 writes only to the new path, so the old file becomes stale committed cruft). Inline migration in `/sync` removes the forgetting failure mode entirely.

**Option C — Version-gated migration (rejected as unnecessary).**

Inline migration as in Option A, but conditioned on a project-recorded plugin-version marker — only run the migration when the recorded version is older than the version this RFC ships in. Rejected because the migration steps are already self-idempotent (every step's "is this needed?" check is a file-existence test) and the version-gate adds machinery to track. The simpler form (run unconditionally; each sub-step short-circuits if already complete) is equivalent in behavior and smaller in code.

**Recommendation: Option A.** Inline migration in a new `/sync` Step 0. Sub-steps short-circuit when already complete, so re-running on a post-migration project does nothing.

## Drawbacks

- **Sidecar file churn shows up in PRs that weren't really about the sidecar.** Once `bootstrap-versions.json` is committed, every PR that changes a plugin-managed template (e.g., editing `CLAUDE.md.tpl` and re-running `/sync` to pick up the new content) will modify the sidecar's hash entries for that artifact. Reviewers will see extra changed lines that look mechanical but are part of the diff. **Mitigation:** the sidecar JSON is short (one hash entry per JSON artifact — currently three: `.claude/settings.json`, `.claude/settings.local.json`, and the sidecar itself, soon to drop to two when the sidecar relocates). Diffs are small and self-explanatory once a reader sees the schema. Documenting the file's role in `docs/CONTRIBUTING.md` (out of scope for this RFC, but a follow-up) addresses the rest.

- **Migration touches every existing consumer project on first post-RFC `/sync`.** Every team that has run `/sync` before this RFC ships will see a one-time `/sync` run that moves a file, updates `.gitignore`, and commits the result. **Mitigation:** the migration is one Step 0 in `/sync` (the user does not run a separate command), and each sub-step prints a one-line summary of what it did so the team has a clear audit trail in the `/sync` output. The PR that follows is recognizably "the plugin-state migration PR" and reviewers can approve it quickly. The implementation spec includes the verification commands a reviewer can run to confirm the migration completed correctly.

- **The `.bytewyrd/plugin-version` file currently has no semantics — promoting it gives it semantics retroactively.** The file exists today (verified: `ls .bytewyrd/plugin-version`) and contains `0.2.0` (verified: `cat .bytewyrd/plugin-version`), but the value was written by something that no longer exists in the code (no `grep` match for the filename in skills/agents/hooks/scripts/.claude-plugin code paths). Promoting the file means the migration must decide whether to trust the existing content. **Mitigation:** the migration step (see implementation spec, Step 0.3) reads the existing file content, treats it as a valid "previously installed version" marker (any value that parses as a version string is accepted as-is), and only overwrites it with the current plugin version if the file is empty or absent. Pre-existing content is preserved. Teams that have a stale value will see the file refresh on the next `/sync` that detects a plugin upgrade.

- **`.gitignore` allowlist requires future plugin authors to remember to add new sentinels.** If a future skill writes a new ephemeral file under `.bytewyrd/` and forgets to add a `.gitignore` line, that file will be committed by default. **Mitigation:** the cost of accidentally committing a sentinel is low (a small file with no secret content, easy to revert), and the explicit allowlist is the safer default per the analysis in Decision 2. A `docs/CONTRIBUTING.md` note documenting the convention is the right place to remind authors; that doc change is in this RFC's implementation spec, Step 7.

- **`last-sync` is a timestamp file — it changes on every `/sync` run even when nothing else changed.** Every `/sync` run produces a diff to `last-sync` (the new timestamp), so even a no-op `/sync` (where no artifact changed) ends up showing one changed file. **Mitigation:** the timestamp is small (one line, ISO-8601 date) and the no-op `/sync` is rare in practice (users run `/sync` precisely because they think something has drifted). The value of "I can git-blame to see when this project last ran `/sync`" is worth the cost of one mechanical diff per run.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.bytewyrd/bootstrap-versions.json` | New canonical location for the per-file SHA12 marker sidecar (relocated from `.claude/.bootstrap-versions.json`). Written by `/sync` Step 5.5 in full whenever any JSON-format artifact's marker advances |
| Create | `.bytewyrd/plugin-version` | Committed file containing the bytewyrd plugin version that was installed when `/sync` last ran (one line, e.g., `0.2.0` — the verbatim value from `.claude-plugin/plugin.json`'s `version` field). Written by `/sync` Step 5.5 |
| Create | `.bytewyrd/last-sync` | Committed file containing the UTC ISO-8601 timestamp of the most recent `/sync` run (one line, e.g., `2026-05-17T18:30:00Z`). Written by `/sync` Step 5.5 |
| Create | `.claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl` | New template source for `.bytewyrd/bootstrap-versions.json` artifact. Content is `{}\n` (an empty JSON object — same as the legacy `.bootstrap-versions.json.tpl`, just renamed) |
| Modify | `skills/sync/SKILL.md` | Add Step 0 (legacy state migration), update Step 1.5 path constant (`docs-agent-version` reference unchanged in path but mentioned in new "what `/sync` writes" section), update Step 4 manifest-read path to `.bytewyrd/bootstrap-versions.json`, update Step 5.5 to write the four canonical files instead of just the sidecar, bump `bootstrap-content-version` marker at line 2 |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Update the sidecar artifact entry: `target` → `.bytewyrd/bootstrap-versions.json`, `source` → `.claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl`, `upstream_key` → `bytewyrd/.bytewyrd/bootstrap-versions.json@v1`, regenerate `sha256` via `build-manifest.sh`. Add `owned_paths: ["*"]` (the wildcard meaning the plugin owns every key in the JSON object — set in the schema per the Approved RFC `2026-05-14-sync-per-file-extension-strategies` item 9 of "Exact manifest changes" — verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:467`). The existing `extension_strategy: "structured"` is retained but the `owned_paths` field is added (it does not exist on the current entry — verified: `.claude-plugin/bootstrap-manifest.json:7-9`). |
| Modify | `.claude-plugin/scripts/templates/.gitignore.tpl` | Replace the existing `.worktrees/` and `.claude/settings.local.json` lines (verified: `.claude-plugin/scripts/templates/.gitignore.tpl:1-3`) plus the implicit blanket `.bytewyrd/` from the current consumer `.gitignore` files. New content (showed in Step 6 below) declares the allowlist policy and tags it with the `# bytewyrd:base` marker so the existing `structured` strategy with `owned_paths: ["bytewyrd:base"]` (verified: `.claude-plugin/bootstrap-manifest.json:74-76`) continues to work unchanged |
| Modify | `.gitignore` (this repo's root, not the template) | Apply the same allowlist policy that the template prescribes — exactly the content the template renders when no language flags are set |
| Modify | `docs/CONTRIBUTING.md` | Add a short section "Plugin state files (`.bytewyrd/`)" listing the four committed files and the two gitignored sentinels, with one sentence per file describing what it is and who writes it. This is a contributor-facing note; details that change with plugin internals live in this RFC and in `docs/ARCHITECTURE.md` |
| Delete | `.claude/.bootstrap-versions.json` (when present in a consumer project) | Removed by `/sync` Step 0 migration. `git rm --cached --ignore-unmatch` if tracked; `rm -f` if untracked. The `--ignore-unmatch` flag means the command succeeds when the file is not git-tracked (a fresh project without the file), per the `git-rm(1)` documentation — Exa: https://git-scm.com/docs/git-rm "Exit with a zero status even if no files matched" |

No new agent files. No skill renames. No new dependencies. The migration is mechanical.

### Steps

#### Step 1 — Create the new sidecar template file

Run:

```bash
mkdir -p .claude-plugin/scripts/templates
printf '{}\n' > .claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl
```

Expected output (no stdout from either command; verify with):

```bash
cat .claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl
```

Expected output:

```
{}
```

The template content matches the existing `.bootstrap-versions.json.tpl` byte-for-byte (verified: `cat .claude-plugin/scripts/templates/.bootstrap-versions.json.tpl` returns `{}\n`; verified: `wc -l .claude-plugin/scripts/templates/.bootstrap-versions.json.tpl` returns `1`). The rename is purely a path change; no content semantic changes.

#### Step 2 — Update `.claude-plugin/bootstrap-manifest.json`

Edit the manifest's first artifact entry (the sidecar). The current entry (verified: `.claude-plugin/bootstrap-manifest.json:3-10`):

```json
{
  "upstream_key": "bytewyrd/.claude/.bootstrap-versions.json@v1",
  "source": ".claude-plugin/scripts/templates/.bootstrap-versions.json.tpl",
  "target": ".claude/.bootstrap-versions.json",
  "sha256": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
  "extension_strategy": "whole",
  "templated": false
}
```

Replace with:

```json
{
  "upstream_key": "bytewyrd/.bytewyrd/bootstrap-versions.json@v1",
  "source": ".claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl",
  "target": ".bytewyrd/bootstrap-versions.json",
  "sha256": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
  "extension_strategy": "structured",
  "owned_paths": ["*"],
  "templated": false
}
```

Field-by-field rationale:

- `upstream_key` — new path under the new namespace; the `@v1` suffix is retained (versioning is independent of the path move).
- `source` — points to the new template file created in Step 1.
- `target` — the canonical new location.
- `sha256` — same content (`{}\n`), same hash. No change needed, but include in the change for diff clarity.
- `extension_strategy` — changes from `"whole"` to `"structured"`. The new strategy is what RFC `2026-05-14-sync-per-file-extension-strategies` calls for (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:59` lists this artifact under `structured` after the RFC's changes), and `structured` is the correct strategy for a file whose entire content is plugin-managed JSON.
- `owned_paths: ["*"]` — the wildcard meaning the plugin owns every JSON path in the file. This is the structured-strategy schema's way of saying "the plugin manages everything; no merge with local content is meaningful for this file." The wildcard literal `"*"` is a new value in the manifest (the existing entries use specific JSON paths or `[]:union` / `[]:id_key` array variants — verified: `.claude-plugin/bootstrap-manifest.json:17-23` for settings.json's specific paths). The diff engine's apply logic for `structured` already loops over `owned_paths` (verified: `skills/sync/SKILL.md:339`); the implementation in Step 4 below adds a single branch to that loop: when the loop encounters the literal `"*"` it replaces the entire JSON object with the plugin's rendered content (which for an empty template is `{}\n` initially; for an existing file, `/sync` will have populated it with hash entries via Step 5.5).
- `templated: false` — unchanged. The sidecar source file ships as-is.

After the edit, regenerate the manifest's hash field via the existing maintainer tool:

```bash
.claude-plugin/scripts/build-manifest.sh
```

Expected output:

```
Regenerated .claude-plugin/bootstrap-manifest.json
```

Verify the updated entry:

```bash
jq '.artifacts[] | select(.upstream_key | startswith("bytewyrd/.bytewyrd/"))' .claude-plugin/bootstrap-manifest.json
```

Expected output (formatting may differ slightly; the seven fields must all be present):

```json
{
  "upstream_key": "bytewyrd/.bytewyrd/bootstrap-versions.json@v1",
  "source": ".claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl",
  "target": ".bytewyrd/bootstrap-versions.json",
  "sha256": "ca3d163bab055381827226140568f3bef7eaac187cebd76878e0b63e9e442356",
  "extension_strategy": "structured",
  "owned_paths": ["*"],
  "templated": false
}
```

If `build-manifest.sh` reports `manifest references missing source: .claude-plugin/scripts/templates/.bytewyrd-bootstrap-versions.json.tpl`, the source file from Step 1 was not created — return to Step 1.

#### Step 3 — Delete the old sidecar template file

Remove the obsolete template so a future `build-manifest.sh` run does not accidentally re-reference it:

```bash
rm -f .claude-plugin/scripts/templates/.bootstrap-versions.json.tpl
```

Expected output: none. Verify:

```bash
test ! -e .claude-plugin/scripts/templates/.bootstrap-versions.json.tpl && echo "ok: legacy template removed"
```

Expected output:

```
ok: legacy template removed
```

#### Step 4 — Update `skills/sync/SKILL.md`

Apply six edits to the sync skill. The file's existing bootstrap-content-version marker (line 2: `<!-- bootstrap-content-version: 2026-05-12-b9f3e2a -->` — verified: `skills/sync/SKILL.md:6`) gets bumped at the end of this step.

**Edit 4.1 — Add a new Step 0 between line 22 (the start of "Step 1") and the existing Step 1.** Inserted content (place immediately before the existing `## Step 1 — Validate environment + detect installed plugins + detect GitHub remote` heading at `skills/sync/SKILL.md:22`):

```markdown
## Step 0 — Migrate legacy plugin state

This step is a one-shot migration that runs at the top of every `/sync` invocation. Every sub-step short-circuits when its target state is already present, so re-running on a post-migration project is a no-op (each sub-step exits immediately if the migration is already complete).

The step exists because pre-RFC `/sync` runs wrote plugin state into `.claude/.bootstrap-versions.json` and gitignored `.bytewyrd/` wholesale. Post-RFC `/sync` writes plugin state into `.bytewyrd/` and gitignores only the ephemeral sentinels by name (see `.gitignore` template below).

### 0.1 — Migrate the bootstrap-versions sidecar

If `.claude/.bootstrap-versions.json` exists, move its content to `.bytewyrd/bootstrap-versions.json` (preserving content byte-for-byte) and delete the legacy file:

```bash
if [ -f .claude/.bootstrap-versions.json ]; then
  mkdir -p .bytewyrd
  # Preserve content byte-for-byte. Use cp (not mv) to avoid losing the file
  # if .bytewyrd/bootstrap-versions.json already exists from a partial migration.
  if [ ! -f .bytewyrd/bootstrap-versions.json ]; then
    cp .claude/.bootstrap-versions.json .bytewyrd/bootstrap-versions.json
  fi
  # Remove from git index (covers committed case) and from disk (covers
  # untracked case). --ignore-unmatch makes git rm succeed when the file is
  # not tracked. Both commands are idempotent on a post-migration project.
  git rm --cached --ignore-unmatch .claude/.bootstrap-versions.json 2>/dev/null || true
  rm -f .claude/.bootstrap-versions.json
  echo "/sync Step 0.1: migrated .claude/.bootstrap-versions.json -> .bytewyrd/bootstrap-versions.json"
fi
```

Expected output when migration is needed (first post-RFC `/sync` on a project that had a committed sidecar):

```
rm '.claude/.bootstrap-versions.json'
/sync Step 0.1: migrated .claude/.bootstrap-versions.json -> .bytewyrd/bootstrap-versions.json
```

Expected output when migration is not needed (post-RFC project or fresh install without a legacy sidecar): no output.

### 0.2 — Migrate `.gitignore` from blanket-exclude to allowlist

Check whether `.gitignore` contains any pre-RFC `.bytewyrd` form. If yes, replace the offending lines with the post-RFC allowlist pair. Three pre-RFC forms are recognized:

- Bare blanket: `.bytewyrd/` or `.bytewyrd` (the current canonical form — verified: `.gitignore:5` in this repo).
- Wildcard blanket: `.bytewyrd/*` (a variant produced by an earlier negated-pattern attempt — verified in `.worktrees/release-0.2.0/.gitignore`).
- Negated re-include lines: any line matching `!.bytewyrd/<anything>` (companion lines to the wildcard blanket; removed because the post-RFC policy uses explicit-exclude, not re-include).

```bash
if [ -f .gitignore ] && grep -qE '(^\.bytewyrd/?$|^\.bytewyrd/\*$|^!\.bytewyrd/)' .gitignore; then
  # Use a temp file for atomic replacement. awk is more portable than sed for multi-line replacement.
  tmp=$(mktemp)
  awk '
    # Match any pre-RFC .bytewyrd line shape.
    /^\.bytewyrd\/?$/ || /^\.bytewyrd\/\*$/ {
      # Replace with the allowlist block — only on the first match, to avoid
      # producing duplicate blocks if a project somehow has two blanket lines.
      if (!emitted) {
        print "# bytewyrd plugin runtime sentinels (recreated per session — do not commit)"
        print ".bytewyrd/precompact-extraction-done"
        print ".bytewyrd/last-feature-engineer-stop"
        emitted = 1
      }
      next
    }
    # Strip negated re-include lines unconditionally (the allowlist policy uses
    # explicit-exclude, not re-include).
    /^!\.bytewyrd\// { next }
    # Pass everything else through unchanged.
    { print }
  ' .gitignore > "$tmp" && mv "$tmp" .gitignore
  echo "/sync Step 0.2: replaced .bytewyrd lines in .gitignore with allowlist policy"

  # Warn if an unrecognized .bytewyrd line shape survived (e.g., a line with a
  # trailing comment that none of the three patterns matched). The user fixes
  # those manually.
  if grep -qE '\.bytewyrd' .gitignore && ! grep -qE '^\.bytewyrd/(precompact-extraction-done|last-feature-engineer-stop)$' .gitignore; then
    echo "/sync Step 0.2 warning: .gitignore still contains an unrecognized .bytewyrd reference; review manually" >&2
  fi
fi
```

The `awk` script matches lines in three shapes (bare-blanket, wildcard-blanket, negated re-include) and produces the canonical three-line allowlist block in place of the first blanket match. Subsequent blanket matches are silently dropped (the `emitted` flag), and all negated re-include lines are stripped unconditionally. Pre-existing comments adjacent to the blanket line (e.g., the current `# bytewyrd plugin local state (PreCompact sentinel, etc.)` comment at `.gitignore:4`) are left as-is, but the body of those comments will now be misleading (they describe the blanket policy). A follow-up cleanup is acceptable; the `.gitignore` template (Step 5 below) is the canonical source going forward.

Expected output when migration is needed: `/sync Step 0.2: replaced blanket .bytewyrd/ in .gitignore with allowlist policy`. Expected output otherwise: no output. Verify:

```bash
grep -E '^\.bytewyrd/' .gitignore
```

Expected output (after migration):

```
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop
```

If the output includes a bare `.bytewyrd/` line, the migration sub-step did not run — re-check the `grep -qxE` detection regex.

### 0.3 — Reconcile orphaned `.bytewyrd/plugin-version` if present

If `.bytewyrd/plugin-version` exists with content, leave it alone (the value is treated as the previously-installed plugin version for the purpose of detecting upgrades). If absent or empty, write the current plugin version from `.claude-plugin/plugin.json` (resolved via `$CLAUDE_PLUGIN_ROOT` per the convention used elsewhere in this skill):

```bash
PLUGIN_VER=$(jq -r '.version' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/cache/bytewyrd/bytewyrd}/.claude-plugin/plugin.json" 2>/dev/null || echo "")
if [ -z "$PLUGIN_VER" ]; then
  echo "/sync Step 0.3: could not resolve plugin version; skipping plugin-version write"
elif [ ! -s .bytewyrd/plugin-version ]; then
  mkdir -p .bytewyrd
  printf '%s\n' "$PLUGIN_VER" > .bytewyrd/plugin-version
  echo "/sync Step 0.3: wrote .bytewyrd/plugin-version = $PLUGIN_VER"
fi
```

The `-s` test means "file exists and is not empty", so a non-empty pre-existing file is preserved. Expected output on a fresh post-RFC project (file absent or empty): `/sync Step 0.3: wrote .bytewyrd/plugin-version = 0.2.0`. Expected output otherwise: no output. The plugin-version is rewritten by Step 5.5 every `/sync` run to reflect the current install — this sub-step only seeds it on first migration.

### 0.4 — Acknowledge migration completion

Print a one-line summary of which migration sub-steps ran:

```bash
echo "/sync Step 0: legacy state migration complete (any sub-step that ran printed its own message above)"
```

This line always prints — even on a post-migration project where every sub-step was a no-op. The constant message tells the user "Step 0 ran and detected nothing to do," which is the audit trail for "did the migration step run at all?".
```

**Edit 4.2 — Update Step 4's manifest-read paragraph (verified: `skills/sync/SKILL.md:295`).** Current text:

```
Use the printed path as `PLUGIN_ROOT`. Read the manifest at `$PLUGIN_ROOT/.claude-plugin/bootstrap-manifest.json`. Also read the sidecar at `.claude/.bootstrap-versions.json` (treat as `{}` if absent).
```

Replace with:

```
Use the printed path as `PLUGIN_ROOT`. Read the manifest at `$PLUGIN_ROOT/.claude-plugin/bootstrap-manifest.json`. Also read the sidecar at `.bytewyrd/bootstrap-versions.json` (treat as `{}` if absent). The sidecar path was relocated from `.claude/.bootstrap-versions.json` per RFC `2026-05-17-move-plugin-state-to-bytewyrd`; Step 0 of this skill migrates legacy projects automatically.
```

**Edit 4.3 — Update Step 4's per-artifact-loop paragraph (verified: `skills/sync/SKILL.md:309`).** Current text:

```
For each artifact in the manifest (skipping the `.bootstrap-versions.json` sidecar entry itself):
```

Replace with:

```
For each artifact in the manifest (skipping the `bootstrap-versions.json` sidecar entry itself — its `upstream_key` is `bytewyrd/.bytewyrd/bootstrap-versions.json@v1`, and skipping is required because the sidecar is the storage for the marker tracking that this loop produces):
```

**Edit 4.4 — Update the manifest reference table row (verified: `skills/sync/SKILL.md:557`).** Current row:

```
| `.bootstrap-versions.json.tpl` | `bytewyrd/.claude/.bootstrap-versions.json@v1` | Whole strategy; generated at sync time |
```

Replace with:

```
| `.bytewyrd-bootstrap-versions.json.tpl` | `bytewyrd/.bytewyrd/bootstrap-versions.json@v1` | Structured strategy with `owned_paths: ["*"]`; generated at sync time |
```

**Edit 4.5 — Rewrite Step 5.5 (verified: `skills/sync/SKILL.md:696-699`).** Current section heading and body:

```
### Step 5.5 — Rewrite sidecar if any JSON artifact's marker advanced

Before printing the report, check whether any JSON-format artifact's marker was updated in Step 5 (i.e., `.claude/settings.json` or `.claude/settings.local.json` was written with a new marker). If yes, rewrite `.claude/.bootstrap-versions.json` in full with all current marker entries. If no JSON artifact's marker changed, the sidecar is not rewritten.
```

Replace with:

```
### Step 5.5 — Rewrite plugin-state files

Before printing the report, write the four canonical `.bytewyrd/` plugin-state files:

1. **`.bytewyrd/bootstrap-versions.json`** — sidecar. If any JSON-format artifact's marker was updated in Step 5 (i.e., `.claude/settings.json` or `.claude/settings.local.json` was written with a new marker), rewrite the sidecar in full with all current marker entries. If no JSON artifact's marker changed, the sidecar is not rewritten.
2. **`.bytewyrd/plugin-version`** — installed plugin version. Always rewrite with the current value from `$PLUGIN_ROOT/.claude-plugin/plugin.json`'s `version` field:
   ```bash
   PLUGIN_VER=$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")
   mkdir -p .bytewyrd
   printf '%s\n' "$PLUGIN_VER" > .bytewyrd/plugin-version
   ```
   The file changes only when the installed plugin version advances; an unchanged version produces a byte-identical file (no diff).
3. **`.bytewyrd/last-sync`** — UTC ISO-8601 timestamp. Always rewrite with the current time:
   ```bash
   mkdir -p .bytewyrd
   date -u +%Y-%m-%dT%H:%M:%SZ > .bytewyrd/last-sync
   ```
   This file changes on every `/sync` run by design — it records when `/sync` last ran for audit purposes.
4. **`.bytewyrd/docs-agent-version`** — already written by Step 1.5 (verified: `skills/sync/SKILL.md:113`); no Step 5.5 action needed for this file. The path is unchanged.
```

**Edit 4.6 — Bump the bootstrap-content-version marker on line 2 (verified: `skills/sync/SKILL.md:6`):**

Replace `<!-- bootstrap-content-version: 2026-05-12-b9f3e2a -->` with `<!-- bootstrap-content-version: 2026-05-17-a1b2c3d -->` (the date is today's date; the hex suffix is a short identifier — the `build-manifest.sh` script does not regenerate this marker, the maintainer updates it by hand when the file changes meaningfully).

After all six edits, verify the file parses as expected:

```bash
grep -n 'bootstrap-content-version' skills/sync/SKILL.md
```

Expected output (one match on line 6):

```
6:<!-- bootstrap-content-version: 2026-05-17-a1b2c3d -->
```

And verify the new Step 0 heading is present:

```bash
grep -n '## Step 0 — Migrate legacy plugin state' skills/sync/SKILL.md
```

Expected output (one match, line number depends on exact placement but should be between the existing Step 1 heading at the original line 22 — shifted down by the inserted content):

```
22:## Step 0 — Migrate legacy plugin state
```

If either grep returns zero or multiple matches, re-apply the corresponding edit.

#### Step 5 — Update `.claude-plugin/scripts/templates/.gitignore.tpl`

Current content (verified: `.claude-plugin/scripts/templates/.gitignore.tpl:1-5`):

```
# bytewyrd:base
.worktrees/
.claude/settings.local.json

<LANGUAGE_GITIGNORE_ENTRIES>
```

Replace with:

```
# bytewyrd:base
.worktrees/
.claude/settings.local.json

# bytewyrd plugin runtime sentinels (recreated per session — do not commit)
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop

<LANGUAGE_GITIGNORE_ENTRIES>
```

The `# bytewyrd:base` tag boundary covers all six entries: the existing two lines plus the comment-and-two-sentinel block. The diff engine's `structured` strategy for `.gitignore` reads the block content by tag (verified: `skills/sync/SKILL.md:341` — "for each tagged block in `owned_paths`, extract the `# <tag>\n` line + lines in the block + `\n`"), so the new lines are picked up as part of the `bytewyrd:base` block automatically — no change to the manifest's `owned_paths: ["bytewyrd:base"]` (verified: `.claude-plugin/bootstrap-manifest.json:74-76`) is needed.

After editing, regenerate the manifest:

```bash
.claude-plugin/scripts/build-manifest.sh
```

Expected output:

```
Regenerated .claude-plugin/bootstrap-manifest.json
```

Verify the template renders correctly by checking the new content:

```bash
cat .claude-plugin/scripts/templates/.gitignore.tpl
```

Expected output:

```
# bytewyrd:base
.worktrees/
.claude/settings.local.json

# bytewyrd plugin runtime sentinels (recreated per session — do not commit)
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop

<LANGUAGE_GITIGNORE_ENTRIES>
```

#### Step 6 — Apply the same `.gitignore` policy to this repo's root `.gitignore`

Current content (verified: `.gitignore:1-5`):

```
.worktrees/
.claude/settings.local.json

# bytewyrd plugin local state (PreCompact sentinel, etc.)
.bytewyrd/
```

Replace with:

```
# bytewyrd:base
.worktrees/
.claude/settings.local.json

# bytewyrd plugin runtime sentinels (recreated per session — do not commit)
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop
```

Two changes:

1. The leading `# bytewyrd:base` tag is added (matches the template). This makes future `/sync` runs against this repo recognize the block as plugin-owned without needing to migrate it again (the `structured` strategy reads the tag).
2. The blanket `.bytewyrd/` line and its preceding comment are replaced with the per-file exclusion block.

The bytewyrd plugin repo itself does not need a `<LANGUAGE_GITIGNORE_ENTRIES>` block (no detected language toolchain at present — verified: `CLAUDE.md`'s `## Toolchain` section reads "No language-specific toolchain detected. Add source code and re-run `/sync` to pick up language tooling."). If a future language is added, `/sync` will append a language-tagged block under the existing `# bytewyrd:base` block per the existing `structured` apply rule.

Verify:

```bash
cat .gitignore
```

Expected output:

```
# bytewyrd:base
.worktrees/
.claude/settings.local.json

# bytewyrd plugin runtime sentinels (recreated per session — do not commit)
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop
```

And:

```bash
git check-ignore -v .bytewyrd/precompact-extraction-done .bytewyrd/last-feature-engineer-stop .bytewyrd/bootstrap-versions.json .bytewyrd/plugin-version 2>&1 | sort
```

Expected output (the first two are ignored by the new rules, the last two are not — `git check-ignore` exits 0 for matched paths, 1 for unmatched; the `2>&1 | sort` keeps both in deterministic order):

```
.gitignore:5:.bytewyrd/precompact-extraction-done	.bytewyrd/precompact-extraction-done
.gitignore:6:.bytewyrd/last-feature-engineer-stop	.bytewyrd/last-feature-engineer-stop
```

(The unmatched paths `.bytewyrd/bootstrap-versions.json` and `.bytewyrd/plugin-version` produce no output from `git check-ignore` — they are not gitignored, which is the goal.)

#### Step 7 — Add the contributor-facing note to `docs/CONTRIBUTING.md`

Insert the following new section in `docs/CONTRIBUTING.md`. Place it after the existing `## Plugin Setup (one-time)` section (if present) or near the end of the file before any agent-provenance section. The section's exact placement is at the maintainer's discretion since `docs/CONTRIBUTING.md` is a `whole`-strategy / soon-to-be-`bootstrap`-strategy artifact (verified: `.claude-plugin/bootstrap-manifest.json:171-178` — `extension_strategy: "whole"`), so the plugin does not own specific subsections of it.

New section to insert:

```markdown
## Plugin state files (`.bytewyrd/`)

The bytewyrd plugin keeps project-local state under `.bytewyrd/` at the project root. Files are split into two categories by commit policy:

**Committed (durable, reviewable in PRs):**

| File | Purpose |
|------|---------|
| `bootstrap-versions.json` | Per-file SHA12 markers for plugin-managed JSON artifacts (the JSON-format counterpart to the in-file `<!-- bootstrap-content-version: ... -->` markers used by Markdown/TOML/YAML/gitignore artifacts). Written by `/sync` Step 5.5 when any JSON artifact's marker advances. |
| `plugin-version` | The bytewyrd plugin version installed when `/sync` last ran (verbatim value from `.claude-plugin/plugin.json`'s `version` field, e.g., `0.2.0`). Written by `/sync` Step 5.5 on every run. |
| `last-sync` | UTC ISO-8601 timestamp of the most recent `/sync` run. Written by `/sync` Step 5.5 on every run. |
| `docs-agent-version` | Project's recorded copy of the plugin's `<!-- docs-agent-version: ... -->` marker; `/sync` Step 1.5 uses the difference between this file and the plugin's current marker to suggest running `/docs-review`. |

**Gitignored (ephemeral session sentinels):**

| File | Purpose |
|------|---------|
| `precompact-extraction-done` | Sentinel written by `/best-practices-extract` to release the `PreCompact` hook block for the rest of the session. Deleted at session start by the `SessionStart` hook. |
| `last-feature-engineer-stop` | Sentinel written by the `feature-engineer` agent's `SubagentStop` hook so the next post-compact `SessionStart` knows to nudge for `/docs-review`. Deleted by `/docs-review` on completion. |

Authors adding a new file under `.bytewyrd/` decide which category it belongs in: if it changes only when `/sync` runs (or another explicit plugin-upgrade action), commit it; if it changes as a side effect of every session, add an explicit line to `.gitignore` listing it by name. Do not re-introduce a blanket `.bytewyrd/` gitignore rule — the allowlist policy is intentional (RFC `2026-05-17-move-plugin-state-to-bytewyrd`).
```

Verify:

```bash
grep -n '## Plugin state files' docs/CONTRIBUTING.md
```

Expected output (one match, line number depends on placement):

```
<N>:## Plugin state files (`.bytewyrd/`)
```

If the section is missing, re-apply the edit.

#### Step 8 — Run the full migration end-to-end against this repo

This is the verification step. Run `/sync` in this repo to exercise Step 0 (no legacy sidecar to migrate, since this repo never had one; but Steps 0.2, 0.3, and 5.5 all do work):

```bash
# Pre-conditions: confirm starting state.
ls -la .bytewyrd/ 2>&1
ls .claude/.bootstrap-versions.json 2>&1 || true
grep -E '^\.bytewyrd' .gitignore
```

Expected output (pre-state):

```
total 8
drwxr-xr-x  2 ... .
drwxr-xr-x ... .. 
-rw-r--r--  1 ...    0 ... last-feature-engineer-stop
-rw-r--r--  1 ...    6 ... plugin-version
ls: cannot access '.claude/.bootstrap-versions.json': No such file or directory
.bytewyrd/
```

(The `.bytewyrd/` line in `.gitignore` confirms the pre-RFC blanket exclusion is in place; the missing `.claude/.bootstrap-versions.json` confirms there is no legacy sidecar to migrate here.)

Now run `/sync`:

```bash
# /sync is a skill, not a CLI command — invoke from within Claude Code.
# The verification text below describes the expected stdout the skill prints.
```

Expected `/sync` Step 0 output (excerpt):

```
/sync Step 0.2: replaced blanket .bytewyrd/ in .gitignore with allowlist policy
/sync Step 0: legacy state migration complete (any sub-step that ran printed its own message above)
```

(Step 0.1 does not print because there is no legacy `.claude/.bootstrap-versions.json` to migrate. Step 0.3 does not print because `.bytewyrd/plugin-version` already has non-empty content.)

After `/sync` finishes, verify the post-state:

```bash
ls -la .bytewyrd/
cat .bytewyrd/plugin-version
cat .bytewyrd/last-sync
cat .bytewyrd/bootstrap-versions.json
grep -E '^\.bytewyrd' .gitignore
```

Expected output (post-state — file ordering may differ; values depend on the run time):

```
total 24
drwxr-xr-x  2 ... .
drwxr-xr-x ... ..
-rw-r--r--  1 ...    3 ... bootstrap-versions.json
-rw-r--r--  1 ...    0 ... last-feature-engineer-stop
-rw-r--r--  1 ...   21 ... last-sync
-rw-r--r--  1 ...    6 ... plugin-version
0.2.0
2026-05-17T18:35:00Z
{}
.bytewyrd/precompact-extraction-done
.bytewyrd/last-feature-engineer-stop
```

(The exact `last-sync` timestamp depends on when `/sync` ran; format is the only fixed property. The `bootstrap-versions.json` contains `{}` because no JSON artifact's marker changed during this `/sync` run — its content updates only when a JSON-format manifest artifact is rewritten with a new marker.)

The four committed files (`bootstrap-versions.json`, `plugin-version`, `last-sync`, `docs-agent-version` if present) now appear in `git status` as new tracked files. The two sentinel files (`precompact-extraction-done`, `last-feature-engineer-stop`) do not appear in `git status`. Verify with:

```bash
git status --short .bytewyrd/
```

Expected output:

```
?? .bytewyrd/bootstrap-versions.json
?? .bytewyrd/last-sync
?? .bytewyrd/plugin-version
```

(Three new untracked files. The `docs-agent-version` file is written by Step 1.5 and so will appear if the plugin's docs-agent marker is non-empty — verified: `agents/docs-agent.md:8` shows `<!-- docs-agent-version: 2026-05-10-initial -->`, so the file will be written and will appear as a fourth `??` entry. The two gitignored sentinel files do not appear because `.gitignore` excludes them.)

If `git status` shows `?? .bytewyrd/precompact-extraction-done` or `?? .bytewyrd/last-feature-engineer-stop`, the `.gitignore` rewrite in Step 6 (or Step 0.2 in `/sync`) did not take effect — re-verify the file contents.

If `git status` shows the legacy `.claude/.bootstrap-versions.json` as `D` (deleted), Step 0.1 of `/sync` ran. The deletion needs to be staged via `git add -u .claude/` when committing the migration PR.

#### Step 9 — Update the bootstrap-content-version marker scan in this RFC's downstream files

The plugin's `.claude/settings.json` `SessionStart` hook (verified: `.claude/settings.json:8`) compares `bootstrap-content-version` markers between `docs/BEST_PRACTICES.md` and `skills/sync/SKILL.md`. The marker in `skills/sync/SKILL.md` was bumped in Edit 4.6 above; if the marker in `docs/BEST_PRACTICES.md` is older, the next session start will print a one-line suggestion ("bootstrap content has new entries — consider running /sync"). This is the intended behavior — the user runs `/sync` to refresh `docs/BEST_PRACTICES.md` against the latest plugin content — and no action is required in this RFC.

No further verification needed in this step; it documents an intentional non-action.

## Risks and open questions

- **Risk: the `owned_paths: ["*"]` wildcard is a new schema value that the existing diff engine does not understand.** The current `skills/sync/SKILL.md:339` describes the `structured` strategy for JSON as "for each path in `owned_paths`, extract the value using `jq` (sort keys) and serialize it; concatenate. For id-based array paths (`[]:<id_key>`): serialize only entries with a non-empty id, sorted by id. For set-union array paths (`[]:union`): serialize only the plugin-contributed entries." A literal `"*"` does not match any of those three branches. **Mitigation:** the wildcard handling is added as part of this RFC's implementation in Step 4 (the new branch in the `structured`-strategy apply loop: when the loop encounters `"*"`, replace the entire JSON object with the plugin's rendered content). This RFC and `2026-05-14-sync-per-file-extension-strategies` both rely on the same wildcard support; whichever lands first must add the branch. If `2026-05-14` lands first, this RFC's Step 2 manifest change becomes a no-op for the `owned_paths` field (already added there); if this RFC lands first, `2026-05-14` inherits the wildcard support from this RFC. Either order works because both RFCs add the same one-line semantics for the same one literal value.

- **Risk: a project's `.gitignore` has a `.bytewyrd/` line in an unexpected shape (trailing comment, mid-line glob, unusual whitespace).** Step 0.2's detection regex covers three pre-RFC shapes (bare blanket `\.bytewyrd/?`, wildcard blanket `\.bytewyrd/\*`, and negated re-include `!\.bytewyrd/<anything>` — verified appearance of the second and third together at `.worktrees/release-0.2.0/.gitignore` in this repo, a snapshot of an earlier rejected negated-pattern attempt). A line like `.bytewyrd/   # plugin local state` (trailing whitespace + comment) matches none of the three patterns and is left in place. **Mitigation:** Step 0.2 prints a warning (`/sync Step 0.2 warning: .gitignore still contains an unrecognized .bytewyrd reference; review manually`) when any `.bytewyrd` substring survives the rewrite but does not match the expected allowlist output. No data loss; the team fixes the stray line manually after seeing the warning. A follow-up RFC can extend the regex set if a real consumer project hits a new shape.

- **Risk: a consumer project's `.claude/.bootstrap-versions.json` was committed with hand-edits that diverge from `/sync`-generated content.** The Step 0.1 migration preserves content byte-for-byte (`cp` followed by `git rm` of the legacy path), so any hand-edited divergence carries over to the new location. **Mitigation:** the diff-engine's structured-JSON strategy is the same on both paths; whatever was true of the file at `.claude/.bootstrap-versions.json` is true of the file at `.bytewyrd/bootstrap-versions.json`. A genuinely divergent file is a `local_only` artifact and the diff engine surfaces it via the `local-only edit preserved` outcome on next `/sync` (verified: `skills/sync/SKILL.md:456` — "**`local_only`** — No action. Track as `local-only edit preserved`."). No data loss; the user retains responsibility for reconciling their hand-edit.

- **Open question: should `last-sync` record the `plugin-version` along with the timestamp?** A combined file like `2026-05-17T18:35:00Z 0.2.0` is more informative than a bare timestamp, but it conflates two concerns (when did `/sync` last run; what version was installed). Keeping them in separate files is cleaner and matches the way `git log` already correlates the two via the commit that touched both files. **Resolution:** keep them separate. If a follow-up RFC determines a combined file is more useful (e.g., for a CI lint that wants a single read), it can be added without removing the separate files.

- **Open question: should the migration step be moved out of `/sync` to a standalone `/bytewyrd-migrate` skill that the user runs once?** Inline migration in `/sync` runs every time, even on post-migration projects (where every sub-step is a no-op). The cost is small (six file-existence tests) but non-zero. **Resolution:** keep migration inline. The cost is bounded (sub-step tests are O(1) per run; total Step 0 overhead is sub-second). A standalone migration skill creates a manual step the user must remember; the current design is automatic and self-healing. If profiling later shows Step 0's overhead is measurable, the sub-steps can short-circuit on a `.bytewyrd/last-sync` existence test ("migration is post-RFC if `last-sync` exists, since `last-sync` is the file that did not exist pre-RFC") — a one-line guard.

- **Open question: should `docs/ARCHITECTURE.md` be updated to mention `.bytewyrd/`?** The architecture document describes the plugin's components and data flow; a new namespace directory for plugin state is arguably an architecture-level concern. **Resolution:** out of scope for this RFC. The RFC implementation spec already updates `docs/CONTRIBUTING.md` (the contributor-facing concern); `docs/ARCHITECTURE.md` can be updated in a follow-up if the maintainer decides the migration warrants a `## Plugin state` section. The `docs/ARCHITECTURE.md` file is `whole` strategy (verified: `.claude-plugin/bootstrap-manifest.json:129-132`) and soon-to-be `bootstrap` strategy per the Approved RFC `2026-05-14-sync-per-file-extension-strategies`, so the plugin's authority over that file is shrinking — adding a section there is a one-time maintainer edit, not an automated change.

## Relationship to other RFCs

- **`2026-05-14-sync-per-file-extension-strategies` (Approved — verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:5`).** That RFC already calls out the sidecar move from `.claude/.bootstrap-versions.json` to `.bytewyrd/.bootstrap-versions.json` (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:467` — item 9 of "Exact manifest changes": "**9. `.bootstrap-versions.json` — relocate to `.bytewyrd/`, switch to `structured` strategy, bump `upstream_key` to `@v2`.**") and changes its strategy from `whole` to `structured` with `owned_paths: ["*"]` (verified: same RFC line 473). This RFC complements that work by handling the parts `2026-05-14` does not address:
  - The directory-wide naming convention for *all* plugin state, not just the sidecar.
  - The commit-vs-gitignore policy. `2026-05-14`'s `.gitignore` change uses the negated-pattern form `.bytewyrd/*` + `!.bytewyrd/.bootstrap-versions.json` (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:496-497`), which corresponds to this RFC's rejected Option B in Decision 2. This RFC's recommended Option A (explicit exclude of only the sentinel files; commit everything else by default) is strictly stronger: it admits the four durable files (`bootstrap-versions.json`, `plugin-version`, `last-sync`, `docs-agent-version`), not just the sidecar, while applying the same exclusion policy to the ephemeral sentinels.
  - The migration of the other version markers (`docs-agent-version`, `plugin-version`, `last-sync`).
  - The file-naming normalization: this RFC uses `bootstrap-versions.json` (no leading dot) inside `.bytewyrd/` because `.bytewyrd/` is itself dot-prefixed and the leading-dot convention is for hidden files at the project root, not for files nested inside a hidden directory. `2026-05-14` uses `.bootstrap-versions.json` with the leading dot in its prose (verified: same RFC line 467); the RFCs disagree on the spelling.

  **Resolution of the path-spelling and gitignore-policy disagreements.** The implementation order matters:
  - **If `2026-05-14` lands first** (it is currently the higher-priority approved RFC): the sidecar lands at `.bytewyrd/.bootstrap-versions.json` (dotted), and `.gitignore` carries the negated-pattern form. This RFC's Step 0 migration then becomes responsible for two additional normalization sub-steps: (a) rename `.bytewyrd/.bootstrap-versions.json` to `.bytewyrd/bootstrap-versions.json` (drop leading dot), and (b) replace the negated-pattern gitignore lines with the allowlist form (already covered by this RFC's expanded Step 0.2 regex set — verified in this RFC: "Negated re-include lines: any line matching `!.bytewyrd/<anything>`").
  - **If this RFC lands first**: the sidecar lands at `.bytewyrd/bootstrap-versions.json` (no leading dot), and `.gitignore` carries the allowlist form. `2026-05-14`'s implementation must then update its prose to use the no-leading-dot spelling and its `.gitignore.tpl` change to use the allowlist form, before regenerating the manifest. This requires a one-line `rfc-read-feedback` pass on `2026-05-14` to update the spelling — a small forward-only edit.

  **Independent of order, neither RFC blocks the other.** This RFC's Step 0 migration is idempotent for the sidecar (the rename target either exists or doesn't), and `2026-05-14`'s manifest restructure is silent on the additional `.bytewyrd/` files this RFC promotes (they have no manifest entries, so they are invisible to `2026-05-14`'s diff-engine changes). The two RFCs can ship in either order.

- **`2026-05-14`'s directory restructure (its Decision 3) is independent of this RFC.** `2026-05-14` moves `.claude-plugin/scripts/templates/` to `scripts/templates/` and `.claude-plugin/bootstrap-manifest.json` to project-root `bootstrap-manifest.json` (verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:211` — "Decision 3 — Correct plugin directory layout to match official conventions"). This RFC's implementation references the *current* paths (`.claude-plugin/scripts/templates/...` and `.claude-plugin/bootstrap-manifest.json`); if `2026-05-14` lands first, this RFC's path references must be updated in a forward-only pass (templates source → `scripts/templates/.bytewyrd-bootstrap-versions.json.tpl`; manifest → `bootstrap-manifest.json`). The RFCs share zero load-bearing path constants in the diff engine, so the rebase is mechanical.

- **`2026-05-10-documentation-agent-lifecycle-hooks` (Done — verified: previously committed, currently Done status referenced at `docs/rfcs/2026-05-10-documentation-agent-lifecycle-hooks.md:5`).** That RFC introduced `.bytewyrd/docs-agent-version` and `.bytewyrd/last-feature-engineer-stop` and added the blanket `.bytewyrd/` gitignore line (verified: `docs/rfcs/2026-05-10-documentation-agent-lifecycle-hooks.md:619-622` shows the original `.gitignore` change). This RFC is a forward-only update to that RFC's gitignore decision: blanket-exclude was correct when only ephemeral sentinels lived under `.bytewyrd/`, but now that durable version markers also live there, the per-file allowlist is the right policy. The Done status of `2026-05-10` is not affected — the work it described was completed; this RFC builds on it.

- **`2026-05-12-auto-extract-best-practices-on-precompact` (Done — verified: file exists at `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md`).** That RFC introduced `.bytewyrd/precompact-extraction-done` and relies on its gitignored status (verified: the RFC body at `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:116` reads "The sentinel file is project-local state — it sits in `.bytewyrd/`, which is gitignored."). This RFC preserves that exact behavior: `precompact-extraction-done` is on the gitignore allowlist (Step 6's `.gitignore` content includes the explicit `.bytewyrd/precompact-extraction-done` exclusion). No semantic change to `2026-05-12`'s design.
