
# Best Practices

<!-- bootstrap-content-version: 2026-05-12-586cc3f -->

## Where do entries live, and why?

This file is the **per-project accumulator**. It holds non-obvious learnings extracted from this
project's sessions (via `/best-practices-extract`). Both *generalizable* and *project-specific*
entries live here, separated by section:

- **Thematic sections** (`## Testing`, `## Architecture`, `## Documentation`, etc.) hold
  generalizable entries — they passed the three portability questions in `TRIAGE-AND-LIFT.md`
  and could theoretically ship to any project that uses the matching stack. They are *eligible*
  for promotion to the global pool.
- **`## Project-Specific`** holds entries that failed any portability question. They are
  valuable to this project (gotchas, internal conventions, project-name-specific quirks) but
  do not transfer. They are never promoted.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `docs/BEST_PRACTICES.md` (this file) | Per-project | Session extraction | Generalizable entries may be promoted to `~/.claude/BEST_PRACTICES.md` via `/best-practices-extract`'s per-entry prompt |
| `~/.claude/BEST_PRACTICES.md` | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into bootstrap content (plugin-author only) |
| `skills/sync/SKILL.md` (bootstrap content, plugin-internal) | Distributed | `/best-practices-sync` from global pool | Renders here, in every new project's starter `docs/BEST_PRACTICES.md`, at `/sync` time |

Format: _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries. Generalizable entries
can be opted into the global pool via the per-entry prompt in that same flow.

## Refactoring

- _Refactoring_: Never mix refactoring with behavior changes in the same commit. A refactor commit should have a trivially passing review — "structure changed, nothing else." This constraint also forces you to understand the code before changing it.
- _Refactoring_: Before refactoring, establish a test that pins the current behavior. If no test exists, write one first. Refactoring without a safety net is rewriting with hope.
- _Refactoring_: Prefer small, surgical refactors over large "cleanup" PRs. A 5-line rename is reviewable in minutes; a 500-line restructure takes hours and hides bugs inside the noise.
- _Refactoring_: Rename aggressively. Wrong names compound — they mislead future readers and spawn more wrong names. A precise rename is one of the highest-ROI refactors available.
- _Refactoring_: Refactor toward the problem domain, not toward patterns. "This should be a Strategy" is a weak reason; "this switch will gain a fourth case next sprint" is a strong one.

## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md).

- _Project-Specific_: The `PreCompact` hook blocks compaction until `/best-practices-extract` runs; release condition is the sentinel file `.bytewyrd/precompact-extraction-done`, written by the skill's final step. Bypass: `touch .bytewyrd/precompact-extraction-done` then `/compact`.
- _Project-Specific_: claude-bytewyrd: the plugin namespace in Claude Code sessions is `bytewyrd:` (hence `/bytewyrd:sync`) but the install address is `bytewyrd/claude-bytewyrd` — these are distinct identifiers for distinct contexts and must not be conflated in docs or code.
