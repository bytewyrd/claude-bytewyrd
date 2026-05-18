---
rfc: "2026-05-18-distribute-best-practices-hooks-to-consumers"
title: "Distribute Best-Practices Extraction Hooks to Consumer Projects"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-18"
drop_reason: ~
---

## Summary

Relocate the `PreCompact` extraction gate and its companion `SessionStart` sentinel-reset hook from the consumer-rendered `templates/settings.json.tpl` route to the plugin-bundled `hooks/hooks.json` route. Today the two hooks reach a consumer project only after `/sync` runs (they are written into the consumer's `.claude/settings.json` as plugin-owned content under the `structured` strategy with `owned_paths: ["hooks"]` — verified: `bootstrap-manifest.json:L4-L20`). After this RFC the same two hooks load automatically the moment a consumer enables `bytewyrd@bytewyrd`, with no `/sync` required, because Claude Code merges a plugin's `hooks/hooks.json` into the active hook set whenever the plugin is enabled (Exa: https://code.claude.com/docs/en/hooks — "When a plugin is enabled, its hooks merge with your user and project hooks"). The `Stop` session-end checklist and the `PostToolUse` post-commit reminders stay in `templates/settings.json.tpl` because they reference project-local file conventions (`ARCHITECTURE.md`, `CONTRIBUTING.md`, `README.md`, `docs/project-brief.md`) that consumers may rename or omit — those reminders are a `/sync`-time opt-in, not a plugin-time default. The implementation is: extend `hooks/hooks.json` with the two events, remove the same two events from the plugin's own in-checkout `.claude/settings.json` (so the plugin-route copy is the sole source — keeping both would create a destructive parallel-fire race on the sentinel file), strip the same two events out of `templates/settings.json.tpl`, regenerate `bootstrap-manifest.json` so existing consumers see a one-time fast-forward update on their next `/sync` run that removes the now-duplicate entries, and update the consumer-facing reference documentation (`docs/guide/reference/hooks.md`) and the internal architecture doc (`docs/ARCHITECTURE.md`) to reflect the new distribution route. `templates/.gitignore.tpl` already excludes `.bytewyrd/*` (verified: `templates/.gitignore.tpl:L4`), so the gitignore template is untouched by this RFC.

## Should we do this?

**Yes.** The whole point of the extraction gate (RFC `2026-05-12-auto-extract-best-practices-on-precompact`, status `Done` — verified: `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L5`) is that compaction without an extraction step throws away the most valuable artifact a session produces; that argument applies just as much to consumer projects as it does to the plugin's own checkout. The current distribution route works, but it has two real costs: (1) **`/sync` is required to activate the gate** — a fresh consumer install of `bytewyrd@bytewyrd` does not get the gate until the user runs `/sync` for the first time, which means the first long session in a freshly installed project is exactly the session most likely to hit a compaction without ever having had the gate active, and (2) **two source-of-truth surfaces for the same hook content** — the gate's exact bash one-liner is duplicated between `templates/settings.json.tpl` and the plugin's own `.claude/settings.json`, and any future tweak to the reminder text or the sentinel path has to land in both places (the plugin author already maintains the in-checkout copy under the existing `2026-05-12` RFC; the template copy was added by the same RFC as a separate edit — verified: `templates/settings.json.tpl:L4-L23`). Moving the gate to `hooks/hooks.json` collapses both routes into one: the plugin author edits one file, the gate activates on install for every consumer, and `/sync` becomes responsible only for content that genuinely depends on per-project configuration. The cost is a one-time fast-forward `/sync` update for existing consumers (the plugin-owned `hooks` block in their `.claude/settings.json` shrinks because the two events move out), which is the normal `structured`-strategy update path and produces no merge conflicts — it overwrites the plugin-owned content cleanly (verified: `scripts/sync-classify.sh:L40-L46` for the `fast_forward` classification path).

## Current state

### How the existing distribution works

The `PreCompact` extraction gate and the `SessionStart` sentinel-reset hook live in two places today:

- **The plugin's own checkout** — `.claude/settings.json:L12-L19` (the second `SessionStart` array entry, whose single hook is the `rm -f` sentinel-reset) and `.claude/settings.json:L21-L30` (the `PreCompact` block). These run when a Claude Code session is opened in the plugin's own repository. They are project-local hooks under Claude Code's standard `.claude/settings.json` resolution (Exa: https://code.claude.com/docs/en/hooks — "`.claude/settings.json` | Single project | Yes, can be committed to the repo").
- **The consumer-rendered template** — `templates/settings.json.tpl:L5-L23`. `/sync` reads this template, renders it with project inputs, and writes the result to the consumer's `.claude/settings.json`. The artifact is tracked in `bootstrap-manifest.json` as `bytewyrd/.claude/settings.json` with `extension_strategy: "structured"` and `owned_paths: ["hooks"]` (verified: `bootstrap-manifest.json:L4-L20`). The strategy means the plugin owns the entire `hooks` block in the consumer's settings file; the rest of the file (e.g., a consumer-added `permissions` block) is preserved across `/sync` runs (verified: `scripts/sync-classify.sh:L38-L46`).

The companion plugin-distributed hooks file at `hooks/hooks.json:L1-L38` currently ships **different** hooks:

- A `SubagentStop` matcher for `(^|:)feature-engineer$` that prints a `/docs-review` reminder and writes the `.bytewyrd/last-feature-engineer-stop` sentinel (verified: `hooks/hooks.json:L3-L17`).
- A `SessionStart` matcher for `compact` that surfaces the post-feature-implementation reminder if the sentinel is fresh (verified: `hooks/hooks.json:L18-L27`).
- A matcher-less `SessionStart` that invokes `scripts/check-requirements.sh` (verified: `hooks/hooks.json:L28-L36`).

These three are auto-loaded by Claude Code when the plugin is enabled (Exa: https://code.claude.com/docs/en/hooks — "Define plugin hooks in `hooks/hooks.json` with an optional top-level `description` field. When a plugin is enabled, its hooks merge with your user and project hooks"). The `PreCompact` gate is conspicuously absent from this file; it lives only in the `.claude/settings.json` routes named above.

### What is broken

The current arrangement has three concrete problems, in increasing order of severity.

1. **A fresh consumer install does not have the gate active until `/sync` runs.** The plugin install does not write to a consumer's `.claude/settings.json`; only `/sync` does. A developer who runs `claude plugin install bytewyrd@bytewyrd` on a brand-new machine and immediately starts a session in a not-yet-`/sync`-ed project has the plugin's skills and agents available, but the `PreCompact` block is not active in that project. The first compaction proceeds without extraction. The pre-existing RFC's whole motivation — "extraction-by-default" — fails for exactly the session most likely to produce extractable insight: the initial onboarding session where a new collaborator learns the project. The plugin's own checkout is unaffected because the in-repo `.claude/settings.json` is committed; consumer projects are affected because their `.claude/settings.json` is built by `/sync` from this plugin's template.

2. **Two sources of truth for the same gate content.** The exact bash command — sentinel check, block decision, `additionalContext` reminder, bypass instructions — appears verbatim in both `templates/settings.json.tpl` (the consumer-rendered template) and the plugin's own `.claude/settings.json` (the in-checkout file). A future tweak to the reminder wording, the bypass message, or the sentinel path requires editing both files and remembering to keep them in lockstep. The pre-existing `2026-05-12` RFC's Step 1 (verified: `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L160-L293`) shows the in-checkout edit; the template copy was added separately and is not annotated in either RFC. Any current or future maintainer who edits one half without the other introduces silent drift that surfaces only on the next consumer `/sync` run.

3. **The `.bytewyrd/` directory is already gitignored on `/sync` but not before.** The current `templates/.gitignore.tpl` excludes `.bytewyrd/*` inside the `# bytewyrd:base` tagged block, with an explicit allowlist for `.bytewyrd/.bootstrap-versions.json` (verified: `templates/.gitignore.tpl:L1-L5`). The exclusion reaches consumers after `/sync` runs — same activation gap as point (1) above. A consumer who installs the plugin and starts a session before running `/sync` will see the sentinel file in `git status` if they happen to `git add` before their first sync. This is a minor cosmetic issue, but the same root cause (`/sync` is the activation point) is what point (1) addresses. Moving the hook to `hooks/hooks.json` does not on its own fix this; the gitignore entry stays in `templates/.gitignore.tpl` and a pre-`/sync` consumer still sees the file. The mitigation is to keep the existing `templates/.gitignore.tpl` line as-is and accept that pre-`/sync` sessions briefly surface the sentinel — the sentinel is empty, ephemeral, and visually distinct (it starts with a `.`), so the surface area for harm is "one stray entry in `git status` between plugin install and first `/sync`."

### Why the distribution route matters

Claude Code's hook resolution does not care about source: hooks from `~/.claude/settings.json`, from `.claude/settings.json`, from `.claude/settings.local.json`, from a plugin's `hooks/hooks.json`, from a skill's frontmatter, and from managed-policy settings all merge into the active hook set at session start (Exa: https://code.claude.com/docs/en/hooks — "Plugin `hooks/hooks.json` | When plugin is enabled | Yes, bundled with the plugin"). What changes between routes is **when** the hook becomes active for a given consumer project:

- **`templates/settings.json.tpl` route** — hook activates after `/sync` runs in the consumer project. Recovery from "I forgot to `/sync`" is: run `/sync`.
- **`hooks/hooks.json` route** — hook activates as soon as the consumer enables the plugin. Recovery from "the plugin is enabled but the hook is not active" is: there is no recovery, because there is nothing the consumer can fail to do — the hook ships with the plugin.

The second route is strictly stronger for hooks whose behavior is uniform across consumer projects. The first route is the right choice for hooks whose content depends on consumer project layout (file names, conventions, agents the project chose to enable, etc.). The two extraction-gate hooks are uniform — they reference one well-known sentinel path and invoke one well-known skill name (`/best-practices-extract`), neither of which varies by consumer.

## Analysis / Options

### Option A — Status quo (do nothing)

Keep the two hooks in `templates/settings.json.tpl`. Consumers must run `/sync` to activate the gate. The duplication between `templates/settings.json.tpl` and the plugin's own `.claude/settings.json` persists.

**Why this might be acceptable:** the `/sync` route is documented; the consumer-facing `docs/guide/reference/hooks.md` already names the hooks (verified: `docs/guide/reference/hooks.md:L1-L80`); the gate is at least eventually-active in every consumer project that ever runs `/sync`.

**Why it is not acceptable:** the explicit case for the gate is "extraction must run before context loss." A consumer who never runs `/sync` has no gate. A consumer who runs `/sync` once and then never updates has the gate but lacks any future updates to the reminder text. The maintenance burden of keeping two files in lockstep is a forever cost; the `/sync` requirement for activation is a per-consumer cost.

### Option B — Migrate `PreCompact` and `SessionStart` sentinel-reset to `hooks/hooks.json` (recommended)

Add two entries to `hooks/hooks.json`: the `PreCompact` block and the `SessionStart` sentinel-reset. Remove the same two entries from `templates/settings.json.tpl` **and** from the plugin's own in-checkout `.claude/settings.json`. The plugin's own checkout always runs with the plugin enabled (dogfood model — verified: `docs/ARCHITECTURE.md`), so the plugin's `hooks/hooks.json` is the sole source of the gate in the plugin's own repo too. Retaining the in-checkout copy would create a destructive parallel-fire race (see "Why the plugin's own `.claude/settings.json` does NOT keep a copy" below).

**Why this is the right move:** the two hooks are uniform across consumers (no project-layout dependencies); plugin-route activation is strictly stronger than `/sync`-route activation for uniform hooks; the duplication between the in-checkout file and the consumer template collapses entirely (after this RFC the only copy of the gate is in `hooks/hooks.json`, which is what consumers and the plugin's own checkout both see — there is no in-checkout duplicate to keep in sync).

**What stays in `templates/settings.json.tpl`:** the `Stop` session-end checklist and the three `PostToolUse` post-commit reminders. These reference filenames that are project conventions (`ARCHITECTURE.md`, `CONTRIBUTING.md`, `README.md`, `docs/project-brief.md`), not plugin globals. A consumer who renamed `ARCHITECTURE.md` to `DESIGN.md` would want the reminder to say `DESIGN.md`; a consumer who has no `docs/project-brief.md` (e.g., a project that opted out of the brief at `/sync` Step 2b) would want the reminder to skip that line. Today the template hard-codes the consumer-bytewyrd defaults, which is fine for an opt-in `/sync`-distributed reminder; it would be wrong for a plugin-distributed hook that consumers cannot tailor.

**Why the `SubagentStop` `feature-engineer` reminder stays in `hooks/hooks.json` (where it already is):** same reason — it references the `bytewyrd:feature-engineer` agent that ships with the plugin, not a project-local agent. It is a uniform plugin-time hook by construction; it has been in the right place since it was added.

**Why the plugin's own `.claude/settings.json` does NOT keep a copy (and must not):** The PreCompact hook's release path deletes the sentinel file before returning `{"continue":true}`. If both an in-checkout `.claude/settings.json` copy and the plugin's `hooks/hooks.json` copy were present simultaneously, they would fire in parallel. One copy would delete the sentinel and emit `continue`; the other copy would see no sentinel and emit `block` — permanently breaking the gate in the plugin's own checkout even after extraction ran. The plugin's own checkout always runs with the plugin enabled (dogfood model — `docs/ARCHITECTURE.md`), so the `hooks/hooks.json` copy is the sole source of the gate in the plugin's checkout. This RFC therefore removes the `PreCompact` block and `SessionStart` sentinel-reset from `.claude/settings.json` (Step 2 below) rather than retaining them.

### Option C — Migrate everything (PreCompact, SessionStart sentinel-reset, Stop, PostToolUse) to `hooks/hooks.json`

Move every entry currently in `templates/settings.json.tpl`'s `hooks` block to `hooks/hooks.json`. The template's `hooks` block becomes empty (or the entry is removed from the manifest entirely).

**Why this is tempting:** it is the maximalist form of Option B. The `templates/settings.json.tpl` strategy entry (`structured` with `owned_paths: ["hooks"]`) becomes unused, and the `templates/settings.json.tpl` artifact can be simplified to managing only `enabledPlugins` and `extraKnownMarketplaces`.

**Why it is wrong:** the `Stop` session-end checklist references `ARCHITECTURE.md`, `CONTRIBUTING.md`, `README.md`, and `docs/project-brief.md` by literal filename (verified: `templates/settings.json.tpl:L60`). A consumer who has renamed any of those or omitted any of them gets a checklist that names files they do not have. The reminder is a non-blocking `echo` (no exit-2, no decision-block), so the consequence is one wrong-filename suggestion per session-end, not a workflow break — but it is still noise. Claude Code's hook system does not provide a way to make the reminder text *consumer-project-aware* (the hook has access to env vars like `CLAUDE_PROJECT_DIR` but the reminder text is a literal `echo` argument, not a templated string). For consumer-tailored content the `/sync`-template route is the right route. Moving everything to `hooks/hooks.json` either bakes the bytewyrd-convention filenames into every consumer regardless of their conventions, or forces a more elaborate hook that reads project state at fire time — both options worse than Option B's "move the uniform hooks; leave the consumer-tailored ones alone."

The `PostToolUse` post-commit reminders are similarly consumer-tailored (same files), so they belong in the same `/sync`-template bucket as `Stop`.

### Recommendation — Option B

Adopt Option B. It is the smallest change that fixes both real problems (fresh-install gate-inactive, two-source-of-truth duplication) without introducing the wrong-route artifacts that Option C would force.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `hooks/hooks.json` | Add two new `hooks.<event>` entries: a `PreCompact` block with the same sentinel-check shell command currently in `templates/settings.json.tpl:L15-L23`, and a matcher-less `SessionStart` block with the same `rm -f` sentinel-reset command currently in `templates/settings.json.tpl:L5-L13`. Both new entries use `${CLAUDE_PROJECT_DIR:-$PWD}` for the sentinel path (so the sentinel lives in the consumer's project root, not the plugin install). Preserve the three existing entries (`SubagentStop` for `feature-engineer`, `SessionStart` for `compact`, matcher-less `SessionStart` for requirement-check) byte-for-byte. |
| Modify | `.claude/settings.json` | Remove the `SessionStart` sentinel-reset entry and the `PreCompact` block. The plugin's own checkout runs with the plugin enabled (dogfood model — `docs/ARCHITECTURE.md`), so the gate is served by `hooks/hooks.json`. Retaining a byte-non-identical duplicate would create a parallel-fire race: the release path deletes the sentinel before returning `{"continue":true}`, so the second copy sees no sentinel and returns `{"decision":"block"}`, permanently breaking the gate in the plugin's own checkout. |
| Modify | `templates/settings.json.tpl` | Remove the `SessionStart` array's sentinel-reset entry (lines L5-L13 today). Remove the `PreCompact` array entirely (lines L15-L23 today, plus the surrounding `,` separator). Leave the `PostToolUse` and `Stop` arrays intact. Leave `enabledPlugins`, `extraKnownMarketplaces` (if present), and the `<PRE_TOOL_USE_HOOK>` substitution untouched. |
| Modify | `bootstrap-manifest.json` | Regenerate the manifest so the new content hash matches. `templates/settings.json.tpl`'s `template_sha` will change (the file shrinks). `templates/.gitignore.tpl` is **not** modified by this RFC — the existing `.bytewyrd/*` exclusion at `templates/.gitignore.tpl:L4` already covers the sentinel file (verified: `templates/.gitignore.tpl:L1-L5`), so the gitignore template's `sha256` does not change. The `upstream_key` recomputation runs automatically because `scripts/build-manifest.sh` always recomputes it from the strategy fingerprint (verified: `scripts/build-manifest.sh:L43-L51`). The `structured`-strategy `owned_paths: ["hooks"]` does not change, so the `upstream_key` value itself does not change — only the `template_sha` field of the settings template changes. |
| Modify | `docs/guide/reference/hooks.md` | Move the `PreCompact — compaction gate` and `SessionStart — precompact sentinel reset` sections (which currently document the project-local hooks under `docs/guide/contributing.md:L107-L117`) into this consumer-facing reference page, so consumers learn that these hooks ship as plugin hooks. Update `docs/guide/contributing.md:L103-L121` to drop the two migrated entries from its "Hooks in the plugin checkout" section. |
| Modify | `docs/guide/contributing.md` | Remove the `SessionStart — precompact sentinel reset` and `PreCompact — compaction gate` entries from the "Hooks in the plugin checkout" section. These hooks now ship as plugin-distributed hooks (see `docs/guide/reference/hooks.md`), not as plugin-checkout-only hooks. |
| Modify | `docs/ARCHITECTURE.md` | Update the Hooks section (verified: `docs/ARCHITECTURE.md:L51-L56`) — the implementer should read the current text before editing, since the existing prose count may be stale. After this RFC the plugin ships five hooks (the requirement check, the feature-engineer reminder, the post-compact docs-review reminder, the `PreCompact` gate, and the `SessionStart` sentinel-reset). Update the count to five and add the gate's relationship to `skills/best-practices-extract/SKILL.md`. |
| (Optional, deferred) | `skills/best-practices-extract/SKILL.md` | No changes required for this RFC. The sentinel-write line at L271-L273 already uses a relative path (`.bytewyrd/precompact-extraction-done`), which resolves against the live session's `cwd` — the same path the gate's hook checks. The skill is unchanged by this distribution change. |

No new files, no new skills, no new agents, no new scripts.

### Steps

The steps below assume work happens on a feature branch with a worktree, per the project's standard workflow (verified: `CLAUDE.md` Workflow section). The exact commands shown are the canonical commands to land each change; the implementer may use equivalent forms (e.g., a `git apply` patch instead of an `Edit` tool call) so long as the resulting file content matches what each step describes.

#### Step 1 — Extend `hooks/hooks.json` with the two migrated entries

The current `hooks/hooks.json` is the file at `/home/divoxx/code/bytewyrd/claude-bytewyrd/hooks/hooks.json`, structured as:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "(^|:)feature-engineer$",
        "hooks": [ ...the docs-review reminder + sentinel-write... ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [ ...the post-compact docs-review reminder... ]
      },
      {
        "hooks": [ ...the requirement-check script invocation... ]
      }
    ]
  }
}
```

Add two entries: a `PreCompact` event array (top-level, alongside `SubagentStop` and `SessionStart`), and a third element in the existing `SessionStart` array (the sentinel-reset hook). The result must be:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "(^|:)feature-engineer$",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, a new CLI flag, a new workflow), consider running /docs-review against the changed paths to check whether docs/guide/** needs updates.'"
          },
          {
            "type": "command",
            "command": "mkdir -p .bytewyrd && : > .bytewyrd/last-feature-engineer-stop"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .bytewyrd/last-feature-engineer-stop ]; then MTIME=$(stat -c %Y .bytewyrd/last-feature-engineer-stop 2>/dev/null || stat -f %m .bytewyrd/last-feature-engineer-stop 2>/dev/null); if echo \"$MTIME\" | grep -qE '^[0-9]+$'; then SENTINEL_AGE=$(( $(date -u +%s) - $MTIME )); else SENTINEL_AGE=999999; fi; if [ \"$SENTINEL_AGE\" -lt 86400 ]; then echo 'Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not yet have run. Consider running /docs-review against the implemented files.'; fi; fi"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/check-requirements.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/check-requirements.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/check-requirements.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then echo 'bytewyrd: check-requirements.sh not found in plugin root or cache; skipping' >&2; exit 0; fi; bash \"$_bw_script\""
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "rm -f \"${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done\""
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "SENTINEL=\"${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done\"; if [ -f \"$SENTINEL\" ]; then rm -f \"$SENTINEL\"; printf '%s\\n' '{\"continue\":true}'; else mkdir -p \"${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd\"; printf '%s\\n' '{\"decision\":\"block\",\"reason\":\"Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is blocked until /best-practices-extract runs in this session. The sentinel file .bytewyrd/precompact-extraction-done does not exist, which means extraction has not yet completed. The expected next action is to invoke /best-practices-extract; the skill itself preserves the per-candidate human-approval prompt, so this gate does not write anything without confirmation. When the skill completes (including the no-op path where nothing passes triage), it creates the sentinel file and the next compaction trigger will be allowed through. To bypass without extraction, the user can run: touch .bytewyrd/precompact-extraction-done then /compact.\"}}'; fi"
          }
        ]
      }
    ]
  }
}
```

Three things to note about the new entries:

1. **The `PreCompact` command uses `${CLAUDE_PROJECT_DIR:-$PWD}` for the sentinel path.** This differs from the consumer-template's existing command at `templates/settings.json.tpl:L20`, which uses the bare relative path `.bytewyrd/precompact-extraction-done`. Plugin hooks fire with `cwd` set to the project root in normal cases, but Claude Code documents `${CLAUDE_PROJECT_DIR}` as the canonical placeholder for "the project root, regardless of the working directory when the hook runs" (Exa: https://code.claude.com/docs/en/hooks — "`${CLAUDE_PROJECT_DIR}`: the project root"). Using the placeholder makes the sentinel path robust to any future change in how Claude Code spawns plugin-hook processes; the fallback to `$PWD` preserves correctness in the unlikely event that the env var is unset (e.g., a non-Claude-Code invocation of the script during a developer's manual smoke test). The skill's own sentinel-write at `skills/best-practices-extract/SKILL.md:L271-L273` uses the bare relative path, which is fine because skills run inside the live session's `cwd` by construction — they do not need the env-var placeholder.

2. **The new matcher-less `SessionStart` entry sits as the third element of the existing `SessionStart` array.** Claude Code allows multiple objects in the same event array; they fire concurrently. The existing entries (the `compact`-matcher reminder and the matcher-less requirement-check) keep firing exactly as before; the new sentinel-reset fires alongside them. Concurrency is not behaviorally significant here — the three commands are independent — but appending preserves a clean diff for reviewers.

3. **The `PreCompact` array has no `matcher` field.** Per the Claude Code hooks reference, `PreCompact` supports matcher values `manual` and `auto` (Exa: https://code.claude.com/docs/en/hooks — "`PreCompact`, `PostCompact` | what triggered compaction | `manual`, `auto`"). Omitting the matcher means the hook fires for both triggers, which matches the gate's intent (the user's explicit `/compact` is gated just as much as the auto-compact). This matches the existing `templates/settings.json.tpl:L15-L23` behavior.

To apply this step:

```bash
cd /home/divoxx/code/bytewyrd/claude-bytewyrd  # or the worktree path the implementer is working in
# Edit hooks/hooks.json by hand or via the Edit tool to produce the structure above.
python3 -m json.tool hooks/hooks.json > /dev/null && echo ok
```

Expected output: `ok` (confirms the resulting file is valid JSON).

#### Step 2 — Remove the gate entries from `.claude/settings.json`

The plugin's own `.claude/settings.json` currently contains two entries that are migrating to `hooks/hooks.json`: the `SessionStart` sentinel-reset (the entry at the third position of the `SessionStart` array whose sole hook is `rm -f .bytewyrd/precompact-extraction-done`) and the `PreCompact` block. Both must be removed from `.claude/settings.json` in this step.

**Why:** Keeping the in-checkout copy would create a destructive-race condition. The PreCompact hook's release path deletes the sentinel file before returning `{"continue":true}`. If both the `.claude/settings.json` copy (which uses the bare path `.bytewyrd/precompact-extraction-done`) and the `hooks/hooks.json` copy (which uses `${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done`) fire in parallel, one copy deletes the sentinel and returns `continue` while the other sees no sentinel and returns `block` — permanently blocking compaction in the plugin's own checkout even after extraction has run.

**Why it is safe to remove:** The plugin's own checkout is always run with the plugin enabled (dogfood model — verified: `docs/ARCHITECTURE.md`). With the plugin enabled, `hooks/hooks.json` is active and provides the gate. A contributor who explicitly disables the plugin in the checkout opts out of the gate — the same as a consumer who disables the plugin. This is the documented opt-out path.

**Validation sub-check:**

```bash
grep -c 'precompact-extraction-done' .claude/settings.json
```

Expected output: `0` after this step.

#### Step 3 — Strip the migrated entries from `templates/settings.json.tpl`

The current template at `templates/settings.json.tpl:L1-L66` contains five hook event blocks under `"hooks"`: `SessionStart` (with the sentinel-reset as its only child), `PreCompact`, `PostToolUse` (three matcher-specific reminders), `Stop`, and the `<PRE_TOOL_USE_HOOK>` substitution token at L64.

Remove two of them — the entire `SessionStart` block and the entire `PreCompact` block. The result must be:

```json
{
  "enabledPlugins": {<ENABLED_PLUGINS_ENTRIES>
  },
  "hooks": {
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
      },
      {
        "matcher": "mcp__plugin_github_github__push_files",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__create_or_update_file",
        "hooks": [
          {
            "type": "command",
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
            "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
          }
        ]
      }
    ]<PRE_TOOL_USE_HOOK>
  }
}
```

Three things to note:

1. **The `<PRE_TOOL_USE_HOOK>` substitution token at L64 stays exactly where it is.** It is the placeholder where `/sync` injects a `PreToolUse` quality-gate hook if any language toolchain was detected (verified: `skills/sync/SKILL.md:L627-L633`). It is independent of this RFC.

2. **The `<ENABLED_PLUGINS_ENTRIES>` substitution at L2 stays exactly where it is.** Same reason — independent of this RFC.

3. **The comma placement.** After removing the `SessionStart` and `PreCompact` array entries, the surviving `PostToolUse` array becomes the first child of `"hooks"` and must not be preceded by a `,`. The surviving `Stop` array becomes the last child and must not be followed by a `,`. The new file must validate as JSON (Step 6 verifies this).

To apply this step:

```bash
# Edit templates/settings.json.tpl to produce the structure above.
# Verify the result is valid JSON (note: <ENABLED_PLUGINS_ENTRIES> and
# <PRE_TOOL_USE_HOOK> are template tokens, so we first substitute placeholder
# strings to make the file parseable):
python3 -c "
import json, sys
with open('templates/settings.json.tpl') as f:
    s = f.read()
s = s.replace('<ENABLED_PLUGINS_ENTRIES>', '').replace('<PRE_TOOL_USE_HOOK>', '')
json.loads(s)
print('ok')
"
```

Expected output: `ok` (the substitution-stripped form is valid JSON).

#### Step 4 — Regenerate `bootstrap-manifest.json`

The manifest tracks the content hash of each template; `templates/settings.json.tpl` shrinks in Step 3 so its `template_sha` must change. `templates/.gitignore.tpl` is unchanged by this RFC (the existing `.bytewyrd/*` wildcard exclusion at `templates/.gitignore.tpl:L4` already covers the sentinel — verified: `templates/.gitignore.tpl:L1-L5`). The regeneration script `scripts/build-manifest.sh` is the canonical way to refresh the manifest (verified: `scripts/build-manifest.sh:L1-L64`).

```bash
bash scripts/build-manifest.sh
```

Expected output: `Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/bootstrap-manifest.json` (or the equivalent path in the worktree).

After regeneration, verify the `.claude/settings.json` artifact's hash reflects the smaller template:

```bash
jq '.artifacts[] | select(.target == ".claude/settings.json") | {target, template_sha, upstream_key}' bootstrap-manifest.json
```

Expected output: a single JSON object with `template_sha` differing from the committed manifest's value and `upstream_key` unchanged. `git diff bootstrap-manifest.json` should show only the `template_sha` field of the `.claude/settings.json` artifact changing (the artifacts are stored sorted by `upstream_key` — verified: `scripts/build-manifest.sh:L51` — so the entry's position does not move).

The `upstream_key` field for `.claude/settings.json` does **not** change: `upstream_key` is computed from `extension_strategy` + strategy config (verified: `scripts/build-manifest.sh:L25-L49`), and neither `extension_strategy` ("structured") nor `owned_paths` (`["hooks"]`) changes in this RFC. The pre-commit manifest check (`hooks/pre-commit/manifest-check.sh`) calls `build-manifest.sh --check`, so a stale manifest would fail the commit (verified: `CLAUDE.md` "Maintaining the bootstrap manifest" section).

#### Step 5 — Update consumer-facing and architecture documentation

The two hooks now reach consumers via a different route, so two prose surfaces need to follow.

**5a. Move two sections from the contributor-facing page to the consumer-facing page.**

In `docs/guide/contributing.md`, the "Hooks in the plugin checkout" section currently lists five entries (verified: `docs/guide/contributing.md:L103-L125`):

- SessionStart — bootstrap version check
- SessionStart — precompact sentinel reset
- PreCompact — compaction gate
- Stop — session-end checklist
- PostToolUse — post-commit documentation reminder

After this RFC, the second and third entries (sentinel reset and PreCompact gate) ship as plugin hooks and are no longer plugin-checkout-only. Remove those two entries from `docs/guide/contributing.md` (preserve the bootstrap-version-check, Stop, and PostToolUse entries — they remain project-local hooks defined in the plugin's own `.claude/settings.json`).

In `docs/guide/reference/hooks.md`, add two new sections alongside the existing "SubagentStop — feature-engineer reminder", "SessionStart — compact reminder", and "SessionStart — requirement check" sections (verified: `docs/guide/reference/hooks.md:L7-L78`):

```markdown
## SessionStart — precompact sentinel reset

**Trigger:** fires at the start of every Claude Code session (no matcher — all session-start triggers).

**Behavior:** removes the file `${CLAUDE_PROJECT_DIR}/.bytewyrd/precompact-extraction-done` if it exists. The sentinel is the release condition for the PreCompact compaction gate (next section); removing it on session start ensures every new session begins with the gate armed, regardless of what the prior session did or did not write.

**Why it exists:** without the reset, a sentinel left by a previous session would let the *first* compaction of the new session bypass the extraction step — defeating the gate's purpose for the most common context-loss case (long sessions that compact for the first time).

---

## PreCompact — compaction gate

**Trigger:** fires before any context compaction (both `/compact` manual triggers and auto-compact when the window fills).

**Behavior:** if the file `${CLAUDE_PROJECT_DIR}/.bytewyrd/precompact-extraction-done` is absent, the hook returns `{"decision": "block"}` and injects an `additionalContext` system reminder instructing Claude to run `/best-practices-extract`. If the file is present, the hook removes it and returns `{"continue": true}`, allowing the compaction to proceed.

**Why it exists:** non-obvious learnings discovered during a session are lost when the session compacts. The gate makes extraction a true first-class phase of compaction rather than an advisory reminder the agent may ignore.

**How to bypass:** if the session genuinely has no learnings to extract (e.g., the user ran a short read-only query), bypass the gate with:

```bash
touch .bytewyrd/precompact-extraction-done && /compact
```

The bypass instruction is also surfaced in the hook's `reason` field at the moment the block is encountered.
```

The exact wording is the canonical doc text for these hooks; reviewers may polish style but the trigger/behavior/why/bypass structure should match the surrounding entries in `docs/guide/reference/hooks.md`.

**5b. Update `docs/ARCHITECTURE.md`'s Hooks section.**

The current Hooks section lives at `docs/ARCHITECTURE.md:L51-L56`. The count may be stale (the actual file may describe 3 or more hooks — the implementer should read `docs/ARCHITECTURE.md:L51-L56` before editing to confirm). Update the count to five and add the new hooks to the inventory. The post-RFC text (suggested wording — the implementer may adjust phrasing as long as the inventory is complete):

```markdown
### Hooks (`hooks/`, `scripts/`)

**Purpose:** Shell-level automation that Claude Code executes in response to session lifecycle events. The plugin ships five hooks, all defined in `hooks/hooks.json` and auto-loaded when the plugin is enabled: a `SessionStart` probe that runs once per session (requirement check via `scripts/check-requirements.sh`); a `SubagentStop` reminder that prompts `/docs-review` after a `feature-engineer` finishes; a `SessionStart` reminder (matcher `compact`) that re-surfaces the docs-review reminder after compaction loses context; a `SessionStart` sentinel reset that arms the PreCompact gate at the start of every session; and a `PreCompact` block-and-release gate that requires `/best-practices-extract` to run before compaction proceeds.
**Location:** `hooks/hooks.json` (hook declarations) + `scripts/check-requirements.sh` (the requirement-check probe).
**Key behavior:** Hooks are silent on the happy path. The PreCompact gate uses a sentinel file at `${CLAUDE_PROJECT_DIR}/.bytewyrd/precompact-extraction-done` as its release condition; `/best-practices-extract` writes the sentinel on every exit path (verified: `skills/best-practices-extract/SKILL.md:L267-L286`). The SessionStart reset ensures stale sentinels from prior sessions cannot pre-release the gate.
```

**5c. Verify the doc updates land.**

```bash
# 5a check — the two entries are removed from contributing.md
grep -F 'precompact sentinel reset' docs/guide/contributing.md
grep -F 'PreCompact — compaction gate' docs/guide/contributing.md
```

Expected: zero matches for each.

```bash
# 5a check — the two entries are present in hooks.md
grep -F 'precompact sentinel reset' docs/guide/reference/hooks.md
grep -F 'PreCompact — compaction gate' docs/guide/reference/hooks.md
```

Expected: one match for each.

```bash
# 5b check — ARCHITECTURE.md now describes five hooks and includes the PreCompact gate
grep -F 'five hooks' docs/ARCHITECTURE.md
grep -F 'PreCompact' docs/ARCHITECTURE.md
```

Expected: at least one match for each.

#### Step 6 — Validation

Run these checks in order. Each check has an explicit expected output. If any check fails, the listed cause is the first thing to investigate.

1. **`hooks/hooks.json` is valid JSON:**

   ```bash
   python3 -m json.tool hooks/hooks.json > /dev/null && echo ok
   ```

   Expected: `ok`.

   *Failure cause:* trailing-comma error after adding the new `PreCompact` block, or unbalanced bracket after the new `SessionStart` entry. Re-check Step 1's full file content.

2. **`hooks/hooks.json` contains the `PreCompact` block with the expected sentinel command:**

   ```bash
   jq -r '.hooks.PreCompact[0].hooks[0].command' hooks/hooks.json | head -c 200
   ```

   Expected output begins with: `SENTINEL="${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done"; if [ -f "$SENTINEL" ]; then rm -f "$SENTINEL"; printf '%s\n' '{"continue":true}'`

   *Failure cause:* the migrated block used the bare relative path instead of the env-var-prefixed path. Re-check Step 1, point (1).

3. **`hooks/hooks.json` contains the new `SessionStart` sentinel-reset entry:**

   ```bash
   jq -r '.hooks.SessionStart | map(.hooks[0].command) | .[] | select(contains("rm -f") and contains("precompact-extraction-done"))' hooks/hooks.json
   ```

   Expected output: one line matching `rm -f "${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done"`.

   *Failure cause:* the sentinel-reset entry was added to the wrong event (e.g., placed in the `compact`-matcher entry instead of as its own matcher-less object). Re-check Step 1's `SessionStart` array structure.

4. **`templates/settings.json.tpl` no longer contains the migrated commands:**

   ```bash
   grep -F 'precompact-extraction-done' templates/settings.json.tpl
   ```

   Expected: zero matches (the command no longer appears in the template).

   *Failure cause:* Step 3 removed the surrounding `[ { } ]` array but left a stray fragment of the inner command. Re-check the resulting JSON structure of the template.

5. **`templates/settings.json.tpl` substitution-stripped form is valid JSON:**

   ```bash
   python3 -c "
   with open('templates/settings.json.tpl') as f:
       s = f.read()
   import json
   json.loads(s.replace('<ENABLED_PLUGINS_ENTRIES>', '').replace('<PRE_TOOL_USE_HOOK>', ''))
   print('ok')
   "
   ```

   Expected: `ok`.

   *Failure cause:* a `,` was left behind after removing the `SessionStart` or `PreCompact` block. Re-check the surrounding punctuation around the surviving `PostToolUse` and `Stop` blocks.

6. **`templates/.gitignore.tpl` still excludes `.bytewyrd/*`** (regression check — this RFC does not modify the template, but the existing exclusion is load-bearing for consumers running pre-`/sync`):

   ```bash
   grep -F '.bytewyrd/*' templates/.gitignore.tpl
   ```

   Expected: one match — `.bytewyrd/*`. The match must be inside the `# bytewyrd:base` tagged block (the tagged block is the contiguous run of non-blank lines starting at `# bytewyrd:base` and ending at the next blank line — verified: `scripts/sync-canonical.sh:L29-L31`). The expected gitignore body (verified against the file at file-write time of this RFC) is:

   ```
   # bytewyrd:base
   .worktrees/
   .claude/settings.local.json
   .bytewyrd/*
   !.bytewyrd/.bootstrap-versions.json
   ```

   *Failure cause:* an unrelated change to `templates/.gitignore.tpl` removed or rewrote the exclusion. Restore the line at its original position.

7. **Manifest regeneration is idempotent (re-running the script does not produce a diff):**

   ```bash
   bash scripts/build-manifest.sh && git diff --quiet bootstrap-manifest.json && echo ok
   ```

   Expected: `ok` (no further changes after a second regeneration).

   *Failure cause:* either the manifest script itself is broken (rare; out of scope for this RFC) or one of the source files referenced by the manifest has unstable content (very rare; would indicate a generation-time race or a non-deterministic template renderer). The manifest's pre-commit hook would also catch this.

8. **Manifest's `upstream_key` for `.claude/settings.json` is unchanged from before Step 4:**

   ```bash
   git diff bootstrap-manifest.json | grep upstream_key
   ```

   Expected: zero lines printed (no `upstream_key` field changed in the diff). The only diff in the manifest must be the two `template_sha`/`sha256` fields.

   *Failure cause:* the `extension_strategy` or `owned_paths` field was accidentally edited; `upstream_key` is fingerprinted from those fields, and either edit invalidates every consumer's existing marker (forcing every consumer to a legacy-classification re-`/sync`). This would be a significant unintended consequence — investigate immediately before committing.

9. **End-to-end consumer-side simulation (manual):**

   Pick any consumer project that has previously run `/sync` against this plugin (e.g., a sibling repository where `.bytewyrd/.bootstrap-versions.json` records the prior `.claude/settings.json` marker). In that consumer's working directory, after this RFC's changes are committed and the plugin's cache is refreshed:

   ```bash
   # In the consumer project, with the bytewyrd plugin enabled:
   bash $CLAUDE_PLUGIN_ROOT/scripts/sync-run.sh > /tmp/sync-out.json
   jq '.classifications[] | select(.target == ".claude/settings.json") | .classification' /tmp/sync-out.json
   ```

   Expected: `"fast_forward"` (the plugin's `owned_paths: ["hooks"]` block changed in the template, so `/sync` will refresh it on next run). After confirming, run `/sync` in the consumer to apply, then verify:

   ```bash
   jq '.hooks.PreCompact // empty, .hooks.SessionStart // empty' .claude/settings.json
   ```

   Expected: `PreCompact` is empty/missing; `SessionStart` either is missing or no longer contains the sentinel-reset command. The gate is then served exclusively by the plugin's `hooks/hooks.json`.

   This validation step is *manual* because it requires (a) a real consumer project with the plugin enabled, and (b) the plugin's cache refreshed to the new version. The plugin author should run it on at least one consumer before tagging a release.

10. **In-checkout regression check:**

    Open a Claude Code session inside the plugin's own checkout. Trigger a compaction via `/compact`. Confirm the gate fires (compaction is blocked, the `additionalContext` reminder appears in the live session). Confirm running `/best-practices-extract` releases the gate and the next `/compact` proceeds. This verifies that only ONE copy of the gate fires (via `hooks/hooks.json`), not two. With the in-checkout `.claude/settings.json` entries removed in Step 2, the gate should fire exactly once per compaction trigger.

## Risks and open questions

- **Risk: the in-checkout `.claude/settings.json` entries are removed in Step 2, leaving only the plugin-route copy.** A contributor who explicitly disables the `bytewyrd@bytewyrd` plugin in the plugin's own checkout will have no gate active. This is the documented opt-out path for any consumer (disabling the plugin opts out of all plugin hooks). The expected operating model for the plugin's own checkout is plugin-enabled; the project brief, ARCHITECTURE.md, and CONTRIBUTING.md all assume the plugin is installed. **Mitigation:** `docs/CONTRIBUTING.md` should note that contributors need the plugin enabled to get the gate. This documentation update is deferred to the `/rfc-implement` step per the contributor-docs section in CLAUDE.md's Session end guidance. No code change required.

- **Risk: existing consumer markers cross-check stays valid.** The `upstream_key` for `.claude/settings.json` does not change (Step 4 documents and Step 6 verifies this). Existing consumer markers (the per-file sidecar entries in `.bytewyrd/.bootstrap-versions.json` or the in-file two-line headers) remain comparable to the new template_sha, so the next `/sync` run classifies the artifact as `fast_forward` (verified: the structured matrix in `scripts/sync-classify.sh:L38-L46`). If `upstream_key` *did* change (e.g., by an accidental edit to `owned_paths`), every consumer would see a `conflict_legacy` classification and be forced into the (deterministic) legacy-reconciliation path — still correct, but more `/sync` Step 8 noise. **Mitigation:** Step 6.8 of the validation checklist explicitly checks that `upstream_key` did not change. The pre-commit manifest hook (`hooks/pre-commit/manifest-check.sh`) would also catch an unexpected manifest mutation before the commit lands.

- **Risk: a consumer's project-local `PreCompact` hook would conflict.** A consumer who has manually added their own `PreCompact` hook to `.claude/settings.json` (e.g., their own enterprise policy or a different code-quality gate) might see both their hook and the plugin's hook fire. Claude Code's documentation says hooks "merge" (Exa: https://code.claude.com/docs/en/hooks — "Plugin `hooks/hooks.json` | When plugin is enabled | Yes, bundled with the plugin"); the documented decision-control behavior is that any hook returning `decision: "block"` blocks the action, with the merged reasons concatenated. **Mitigation:** the gate's `reason` field names the bypass explicitly (`touch .bytewyrd/precompact-extraction-done && /compact`), so a consumer whose own hook also runs sees both reasons and can address each. No code change required.

- **Risk: Claude Code version requirement.** The `PreCompact` block decision was added in Claude Code v2.1.105 (2026-04-13, per the prior `2026-05-12` RFC — verified: `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L49`). A consumer on an older Claude Code release that does not honor `decision: "block"` for `PreCompact` will silently fall back to "the hook ran, the JSON was parsed, the block was ignored" — exactly the pre-RFC failure mode. **Mitigation:** the pre-existing `2026-05-12` RFC already names this risk; this RFC does not change it. The README's install instructions could be updated to call out the version requirement, but that is a documentation polish item out of scope here.

- **Risk: discoverability for consumers reading the project-local `.claude/settings.json`.** A consumer who opens their `.claude/settings.json` looking for "where does the compaction-block come from?" will not find anything there anymore. Without this RFC, the same consumer would have found the hook in their own settings file (after `/sync`); after this RFC, the hook is in the plugin's `hooks/hooks.json` which sits inside the plugin install directory. **Mitigation:** the consumer-facing `docs/guide/reference/hooks.md` is updated (Step 5 in the implementation spec) to document the plugin-distributed gate alongside the existing requirement-check and feature-engineer reminders. Consumers who reach for the hooks reference get the answer immediately.

- **Open question: should the `Stop` checklist also migrate to `hooks/hooks.json`?** Option C above evaluates this and rejects it on the consumer-tailoring grounds (the checklist names specific filenames that consumers may rename). **Resolution within this RFC:** keep `Stop` in the template route. If future work introduces a mechanism for consumer-tailored plugin-route reminders (e.g., a hook-readable manifest of "what filenames does this project use"), revisit then.

- **Open question: should the gate optionally write to a path other than `.bytewyrd/precompact-extraction-done`?** Consumers may have their own conventions about hidden-directory naming, or may not want a tool-specific hidden directory at all. **Resolution within this RFC:** no. The sentinel path is documented in the consumer-facing `docs/guide/reference/hooks.md`; consumers who object can disable the plugin's hook by overriding it via their `.claude/settings.json`. Making the path configurable would require a `user_config` schema entry in `plugin.json` — out of scope.

- **Open question: should `bytewyrd@bytewyrd` be enabled-by-default in consumer `.claude/settings.json`?** Today, `/sync` does not write `bytewyrd@bytewyrd` to consumer `enabledPlugins` (verified: `docs/ARCHITECTURE.md:L83-L103`); the plugin is installed and enabled at user scope per developer. A team that has the plugin installed at user scope gets the gate via the plugin route as soon as they enable the plugin (which they do by installing it — Claude Code's `claude plugin install` flow enables the plugin in user settings by default per the Mintlify plugin install docs — Exa: https://www.mintlify.com/anthropics/claude-code/plugins/installation). **Resolution within this RFC:** no change to the `enabledPlugins` policy. The plugin-route distribution still works for the dominant case (user-scope install + plugin auto-enabled); the small subset of teams who explicitly disable the plugin in a project's `.claude/settings.json` will not get the gate, but that is the documented opt-out path and respecting it is correct.

## Relationship to other RFCs

- **`2026-05-12-auto-extract-best-practices-on-precompact`** (status: `Done`, verified: `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L5`). This RFC builds directly on it: the prior RFC implemented the gate in the plugin's own checkout and updated `skills/best-practices-extract/SKILL.md` to write the sentinel; this RFC extends the same gate to consumer projects via the plugin route. The skill itself is unchanged. The prior RFC added a project-local `.gitignore` entry for `.bytewyrd/`; `templates/.gitignore.tpl` already carries the matching consumer-side exclusion at `templates/.gitignore.tpl:L4` (verified: `templates/.gitignore.tpl:L1-L5`), so the gitignore template is **not** modified by this RFC.

- **`2026-05-09-best-practices-content-and-tooling`** (status presumed `Done` per file age — verified: `docs/rfcs/2026-05-09-best-practices-content-and-tooling.md` exists). Established the `docs/BEST_PRACTICES.md` destination, the per-session extraction flow, and the relationship between `/best-practices-extract` and `/best-practices-record`. This RFC does not change that flow; it changes only the distribution route of the hook that enforces the flow.

- **`2026-05-12-unify-best-practices-destinations`** (status: `Draft` per prior RFC's relationship table). Orthogonal: that RFC concerns where approved entries are written; this RFC concerns when and how the extraction step itself is triggered.

- **`2026-05-14-sync-per-file-extension-strategies`** (status presumed `Done` per file presence — verified: `docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md` exists in `docs/rfcs/`). Established the `extension_strategy` field and the `structured` strategy with `owned_paths` used by `templates/settings.json.tpl`. This RFC does not change the strategy; it changes only the *content* the strategy distributes (the `hooks` block shrinks by two events).

- **Future RFC (none required for in-checkout duplicate cleanup): this RFC removes the duplicate.** Earlier drafts of this proposal deferred removal of the in-checkout `.claude/settings.json` copy to a follow-up RFC. The discovery during review that retaining both copies would create a destructive parallel-fire race on the sentinel file (one copy deletes the sentinel and emits `continue`; the other sees no sentinel and emits `block` — permanently breaking the gate) made the removal load-bearing for correctness, so it is rolled into Step 2 of this RFC.
