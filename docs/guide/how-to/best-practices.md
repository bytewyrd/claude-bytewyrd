# Capture and propagate best practices

The plugin gives you two skills for capturing engineering learnings, and they serve different moments in the workflow.

---

## Which skill to use

| Situation | Skill |
|-----------|-------|
| You want to record a single principle right now, stated from scratch | `/best-practices-record` |
| You are finishing a session and want to extract everything non-obvious | `/best-practices-extract` |

**In-the-moment capture:** use `/best-practices-record` when you recognize a pattern during or after a session — something you have seen repeat across projects, a stack-level lesson, or a recovery path for a common mistake. The skill focuses on one entry at a time and writes only to the global cross-project pool (`~/.claude/BEST_PRACTICES.md`).

**End-of-session extraction:** use `/best-practices-extract` when you want to review the whole session for non-obvious learnings. The skill scans the conversation, triages candidates, and produces a categorized list for your approval. Approved entries go into the project's `docs/BEST_PRACTICES.md`. Generalizable ones are also offered for promotion to the global pool in the same approval flow.

---

## The two destinations

| File | Scope | What ends up there |
|------|-------|-------------------|
| `docs/BEST_PRACTICES.md` | This project | Everything approved from extraction (both generalizable and project-specific entries) |
| `~/.claude/BEST_PRACTICES.md` | All your projects | Only generalizable entries you promote (via `/best-practices-extract`'s checkbox prompt or `/best-practices-record`) |

Project-specific entries — those that reference a particular file path, module name, or project-level decision — stay in `docs/BEST_PRACTICES.md` under a `## Project-Specific` section. They are never promoted to the global pool.

---

## Using `/best-practices-record`

Call it with the principle you want to capture:

```
/bytewyrd:best-practices-record When a wrapper component renders slot content and needs to share state with it, use provide/inject — slot content has no prop access to its wrapper.
```

The skill runs three portability tests on your statement:

1. **Framework portability** — does this apply outside one specific ecosystem?
2. **Project portability** — does this apply to any project, not just this one?
3. **Audience portability** — does this apply to any engineer, not just someone with project context?

If the statement fails any test, the skill refuses and tells you to use `/best-practices-extract` instead (for project-specific entries). If it passes, the skill shows you a "lifted" version — the principle rewritten with project-specific identifiers replaced by their roles — and asks which version to record.

You confirm via a single checkbox. The entry is written to `~/.claude/BEST_PRACTICES.md` if you confirm.

---

## Using `/best-practices-extract`

Run at any point, but especially at the end of a meaningful session:

```
/bytewyrd:best-practices-extract
```

The skill:

1. Scans the conversation for non-obvious learnings.
2. Applies the portability triage to each candidate.
3. Presents candidates grouped by destination (generalizable vs. project-specific).
4. Waits for your selection (`1`, `2`, `all`, `none`, etc.).
5. For approved generalizable entries, presents a bulk-checkbox promotion prompt.

### The triage-and-lift process

Before showing you any candidate, the skill lifts generalizable entries: project names, file paths, type names, and function names are replaced by their roles. A principle about a specific `UserSessionStore` class becomes a principle about "state stores that accumulate across requests." This lifting makes the entry useful two years from now when no one remembers the context.

### The bulk-checkbox promotion prompt

After you approve candidates for the project file, a single checkbox prompt appears — one row per generalizable entry. The skill pre-checks entries it recommends for the global pool (broadly applicable) and leaves narrowly applicable entries unchecked. You audit the list and confirm once.

Checked entries are written to both `docs/BEST_PRACTICES.md` and `~/.claude/BEST_PRACTICES.md`. Project-specific entries are written only to `docs/BEST_PRACTICES.md`.

### Older installs: the compaction gate

The plugin ships no compaction gate, so nothing blocks context compaction until extraction has run. A repository set up with 0.2.x may still have a `PreCompact` hook in its `.claude/settings.json` that blocks the first compaction of a session until `/best-practices-extract` has run. For such a repository, the skill writes `.bytewyrd/precompact-extraction-done` when it finishes, and that releases the hook.

To compact without extracting (for sessions with nothing worth capturing), create the file yourself:

```bash
touch .bytewyrd/precompact-extraction-done
```

`/bytewyrd:drift` lists the hook as `legacy-settings-hooks`. Its fix is to delete the 0.2.x hook entries from `.claude/settings.json`, which ends the gate.

---

## How learnings propagate to future projects

Entries in `~/.claude/BEST_PRACTICES.md` are the source for the plugin's `best-practices` skill. When a plugin maintainer runs `/best-practices-sync` (a plugin-local maintenance skill), vetted global entries are promoted into `skills/best-practices/references/<stack>.md`. Claude reads that skill from the plugin at runtime, so every project gets the promoted entries when the plugin updates. Nothing is copied into your project.

The flow:

```
Session learning
  → /best-practices-extract (or /best-practices-record)
  → ~/.claude/BEST_PRACTICES.md (global pool)
  → /best-practices-sync (plugin maintenance)
  → skills/best-practices/references/<stack>.md (the best-practices skill)
  → read by Claude at runtime in every project
```

---

## Related

- [Reference: Skills](../reference/skills.md) — full skill descriptions including `/best-practices-record` and `/best-practices-extract`.
