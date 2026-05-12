---
rfc: "2026-05-12-rfc-summary-command"
title: "/rfc-summary Command for Active RFC Overview"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Add a new `/rfc-summary` skill that lists every RFC currently in `Draft` or `Approved` status, filtering out `Done` and `Dropped` entries so the output is a standup-style snapshot of work that is either pending design feedback or awaiting implementation. The skill runs inline in the main conversation (no subagent), reads each file in `docs/rfcs/`, parses the YAML frontmatter, and prints a single grouped table: `Approved` first (ready to implement), then `Draft` (needs review/approval). Each row shows the RFC identifier, title, author, and creation date. Output is plain Markdown so it renders cleanly in the conversation and is also copy-pasteable into a standup channel.

## Should we do this?

**Yes.** As the RFC parking lot grows, `docs/rfcs/` becomes a flat directory listing where everything — drafts under active review, approved RFCs awaiting implementation, completed work, and dropped ideas — sits side by side. Today the only way to answer "what's in flight?" is to open each `.md` file, scan the frontmatter for `status:`, and manually exclude the terminal states. That manual scan does not scale — there are already 13 RFCs in the directory and the trend is up. A skill that does this scan in one command is small (a single inline skill, no agent, no consensus loop) and pays for itself the first time it surfaces an `Approved` RFC the user forgot was waiting on `/rfc-implement` or a `Draft` RFC that has been sitting unreviewed. Cost is one new skill file plus one line in `plugin.json`; the implementation is read-only (no mutations, no commits) so the risk surface is essentially zero. The braindump entry explicitly framed this as "discoverability for in-flight work" — that exact framing is the user-facing value proposition and is unchanged by the implementation analysis below.

## Current state

RFCs are stored as Markdown files in `docs/rfcs/` with a `YYYY-MM-DD-<kebab-title>.md` filename pattern and a required YAML frontmatter block. Per `docs/rfc-process.md`, the lifecycle is `Draft → Approved → Done | Dropped`; `status` lives in the frontmatter and is the canonical source of truth for where each RFC sits in that lifecycle.

**What exists today:**

- `docs/rfcs/` — currently contains 20 files (excluding this RFC itself): 12 large RFCs from May 9 and May 10 (ranging in status from `Draft` through `Done`) and 8 small braindump-style RFCs all dated `2026-05-12` and currently in `Draft`. There is no aggregating view; `ls docs/rfcs/` lists files alphabetically by date prefix and conveys nothing about lifecycle state.
- Frontmatter contract (from `docs/rfc-process.md` §"Required YAML frontmatter"): every RFC must have `rfc`, `title`, `author`, `status`, `created`, and `drop_reason`. The `/rfc-new` skill creates files with exactly this shape, so every existing file in `docs/rfcs/` is structurally uniform — a single parser handles every file.
- `skills/` — 13 skill directories exist under `skills/`. At the time of this RFC, `.claude-plugin/plugin.json` has no `skills` array yet (the file is the minimal `name`/`description`/`version`/`author` scaffold). Skills are auto-discovered by Claude Code from the `skills/` directory, not from a `plugin.json` registration. None of the existing skills list RFCs. The `/rfc-approve`, `/rfc-drop`, and `/rfc-implement` skills each include a step that "lists files in `docs/rfcs/` sorted by name and takes the last as the candidate" — a degenerate form of summary, but constrained to a single defaulting candidate and not surfacing status at all.
- `CLAUDE.md` "Quick reference" section lists the RFC skills available to consumers: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`. The new `/rfc-summary` skill belongs in this list — the same line in two places, since the plugin's `CLAUDE.md` is the source seeded into project `CLAUDE.md`s by `/sync`.
- `docs/rfc-process.md` §"Maintaining project RFC files" → "Skills" table also enumerates the skill set. Adding `/rfc-summary` here keeps the project-installable docs consistent with the plugin's `CLAUDE.md`.

**What is broken or missing:**

1. **No aggregated view of in-flight work.** Today a user (or the main agent) cannot answer "which RFCs need my attention right now?" without opening every file. The information is structured (it's all in the frontmatter) but there is no skill that presents it.
2. **`Done` and `Dropped` RFCs visually crowd the directory.** As the project ages, the ratio of terminal-state RFCs to in-flight RFCs grows. A flat `ls` is increasingly noisy precisely as the need for a curated view increases.
3. **Status transitions are hard to verify after the fact.** `/rfc-approve` and `/rfc-drop` mutate `status:` in the frontmatter and commit, but there is no quick way to confirm the post-state ("did the approval actually land? is the file really in Approved status now?") without re-opening the file. `/rfc-summary` doubles as a sanity check after status-changing skills run.

The other workflow skills demonstrate the pattern this RFC follows: small-surface, single-purpose skills that do one read or one mutation. `/rfc-summary` is the read-only counterpart to the existing `/rfc-approve` / `/rfc-drop` / `/rfc-implement` mutation skills.

## Analysis / Options

Three coupled decisions: how the skill reads and parses the RFC files, whether it spawns a subagent or runs inline, and what the output shape looks like.

### Decision 1 — How does the skill parse frontmatter?

**Option A — Inline Bash + plain `grep`/`awk` (recommended).**
The skill body instructs the main agent to enumerate `docs/rfcs/*.md` (excluding `.gitkeep` and any non-RFC file), then for each file extract the `rfc:`, `title:`, `author:`, `status:`, and `created:` fields from the frontmatter using a short `awk` script. The frontmatter is bounded by `---` lines at the top of every file (the `/rfc-new` template guarantees this), so `awk '/^---$/{c++; next} c==1' file.md` cleanly isolates the frontmatter block; from there, `grep` + `sed` extract the value of each field. This is the cheapest approach: no YAML parser dependency, no agent spawn, and the parsing logic is small enough to inline in the skill body.

**Option B — A Python or Node one-liner using a real YAML parser.**
More robust to edge cases (multi-line values, quoted strings with embedded colons) but requires the user's machine to have Python+PyYAML or Node+a YAML library installed. The plugin currently makes no such assumption; introducing one for a single small read-only skill is disproportionate to the value. The frontmatter contract is constrained enough (every field is single-line, every value is a simple string) that the `awk`/`grep` approach handles every real-world case the `/rfc-new` template produces.

**Option C — Spawn an agent and have it read each file natively.**
The agent reads each `.md` file using the Read tool and assembles the summary from the parsed content. This is the most flexible approach but is also the most expensive (one Read call per file, plus an agent spawn). For a read-only listing of 20-ish files, the round-trip cost is wasteful compared to a single Bash invocation that finishes in under a second.

**Recommendation: Option A.** The frontmatter contract is uniform and the values are simple strings — `awk`/`grep` is sufficient and avoids both an external dependency (Option B) and an agent spawn (Option C). The skill body includes the exact `awk` script so the main agent does not need to invent it.

### Decision 2 — Inline execution or subagent?

**Option A — Skill runs inline in the main conversation (recommended).**
The main agent executes the skill body directly: it runs the Bash enumeration, parses frontmatter, formats output, prints. No agent spawn. This matches `/rfc-approve`, `/rfc-drop`, `/rfc-implement`, and `/rfc-read-feedback` — all of which are read-or-narrowly-mutate skills that run inline because there is no domain reasoning to delegate. The summary is mechanical: enumerate, filter by status, sort, print.

**Option B — Spawn an `rfc-architect` (or other) subagent to read and summarize.**
The plugin spawns specialists when there is reasoning to delegate (RFC content authorship, code review, refactoring planning). A flat listing has no reasoning to do; spawning Opus to print a table would be expensive theater. Rejected on consistency grounds: every other read-only skill in the plugin runs inline.

**Option C — Hybrid: inline for the listing, subagent only if the user asks for prose summaries per RFC.**
Pulls scope creep into the RFC. The braindump explicitly asked for "concise output (status, title, identifier) so it works as a quick standup-style snapshot rather than a full report." A prose-per-RFC mode is a different feature, not this one. Rejected as out-of-scope.

**Recommendation: Option A.** Inline execution. No subagent. The skill body is short and prescriptive enough that the main agent's role is mechanical orchestration, which is exactly what `/rfc-approve`, `/rfc-drop`, and `/rfc-implement` already do.

### Decision 3 — Output shape

**Option A — Two grouped tables, `Approved` first, then `Draft` (recommended).**
Group by status because that is the primary axis the user reads: "what's ready to implement?" (Approved) is a different question from "what's waiting on review?" (Draft). Within each group, sort by `created` ascending so the oldest entries surface first — those are the most likely to be languishing and need attention. Each row: `RFC` identifier, `Title`, `Author`, `Created` date.

**Option B — One combined table with a `Status` column.**
Compact but less scannable. The user has to visually filter by status; the grouped form does that filtering by layout. The braindump entry framed the output as "concise" — concise does not mean "minimum row count," it means "minimum cognitive load to read." Two short tables read faster than one long mixed table.

**Option C — Plain bulleted list with status prefix.**
`* [Approved] 2026-05-10-foo — Foo Title (Rodrigo, 2026-05-10)` — readable but loses column alignment and is harder to scan when titles vary in length. A Markdown table is what conversational rendering handles best.

**Recommendation: Option A.** Two grouped tables, `Approved` first, `Draft` second. Empty groups are explicitly noted ("No Approved RFCs." / "No Draft RFCs.") rather than omitted, so the user can distinguish "nothing approved yet" from "the skill didn't look at Approved." Total counts are appended at the bottom (`2 Approved · 11 Draft · 13 in flight`) for quick at-a-glance scale.

### Decision 4 — Should `Done` and `Dropped` be reachable from this skill at all?

**Option A — Hide them completely; this skill is for in-flight work only (recommended).**
The braindump explicitly framed the value as "filtering out `Done` and `Dropped`." If the user wants the full history, they can `ls docs/rfcs/` or run `grep ^status: docs/rfcs/*.md`. Keeping the skill single-purpose is the right tradeoff for a "quick standup snapshot."

**Option B — Show them under a collapsed footer.**
A footer line like `(plus 8 Done, 1 Dropped — not shown)` is small enough to not crowd the output and adds useful context about scale. Worth including as a single counts line.

**Option C — Add a `--all` flag that includes terminal-state RFCs.**
Flags are friction. The user who wants the full list already has `ls`. A flag adds a teaching burden for a feature that is not the skill's primary purpose.

**Recommendation: hybrid of A and B.** The body of the output shows only `Draft` and `Approved` (Option A). A single trailing counts line includes `Done` and `Dropped` for context, e.g. `(also: 8 Done, 1 Dropped)`. No flag (Option C rejected) — the skill stays single-purpose.

## Drawbacks

- **Yet another skill in the menu.** Adding `/rfc-summary` to a workflow that already exposes nine `rfc-*` skills increases the autocomplete surface and the cognitive load of "which one do I run?" **Mitigation:** the skill description is explicit ("list active RFCs — Draft and Approved only — for a quick standup snapshot") and the skill name is the obvious one a user would try. The plugin's `CLAUDE.md` "Quick reference" already enumerates the RFC skills; adding one more line is marginal.

- **Frontmatter parsing is bespoke.** A short `awk` script is less robust than a real YAML parser; a future change to the frontmatter contract (e.g., adding multi-line block values) could silently break the skill. **Mitigation:** the frontmatter contract is governed by `docs/rfc-process.md` and the `/rfc-new` template. Any contract change would already require an update to `/rfc-new` and to the rfc-process doc; `/rfc-summary` would be touched in the same PR. The parsing is small enough that a contract change is a five-line edit to the skill body. The verification step in the implementation spec (Step 4) includes a smoke test against the current `docs/rfcs/` directory so contract drift is caught early.

- **No automatic refresh.** The output is a snapshot at the moment the skill runs. A user who runs `/rfc-summary`, then runs `/rfc-approve` on one of the listed Drafts, then looks back at the original `/rfc-summary` output will see stale data. **Mitigation:** this is true of every read-only listing and is a non-issue in practice — the user re-runs the skill. The output is cheap; there is no caching to invalidate.

- **`Done` and `Dropped` counts are visible at the bottom, which slightly leaks the "hide terminal states" promise.** The counts line is one line of trailing context, not a row-by-row listing, so it does not undermine the standup-snapshot framing. **Mitigation:** none needed; the counts line is intentional and called out in Decision 4. Users who want zero mention of terminal-state RFCs can ignore the trailing parenthetical.

- **Same-day RFC ordering is undefined.** Within a status group, files are sorted by `created` date. RFCs created on the same day (every entry in the current `docs/rfcs/` 2026-05-12 batch) have the same primary sort key. **Mitigation:** secondary sort by the `rfc:` identifier (which is the filename stem) gives a stable, deterministic order. The implementation spec encodes this — `sort -t$'\t' -k2,2 -k3,3` so primary by `created`, secondary by identifier. This is purely cosmetic; same-day RFCs render in a stable alphabetical-by-kebab-title order.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `skills/rfc-summary/SKILL.md` | New skill: enumerate `docs/rfcs/*.md`, parse YAML frontmatter for `status`, `title`, `author`, `created`, and the RFC identifier, render two grouped Markdown tables (`Approved` first, then `Draft`), append a counts line including `Done` and `Dropped` totals. Runs inline; no subagent. |
| Modify | `.claude-plugin/plugin.json` | Add `./skills/rfc-summary` to the `skills` array, between `./skills/rfc-read-feedback` and `./skills/rfc-update` so the `rfc-*` block stays alphabetical. |
| Modify | `CLAUDE.md` (plugin root) | Add `/rfc-summary` to the "Quick reference (installed projects)" skill list inline with the existing comma-separated enumeration. |
| Modify | `rfc-process.md` (plugin root — **upstream source**) | Add a `/rfc-summary` row to the "Skills" table in the "Maintaining project RFC files" section, between `/rfc-read-feedback` and `/rfc-approve` (preserving the existing non-alphabetical conceptual grouping). This is the canonical source that `/rfc-update` and `/sync` copy into consumer projects — it **must** be updated alongside `docs/rfc-process.md`. |
| Modify | `docs/rfc-process.md` (plugin root — **downstream copy**) | Add a `/rfc-summary` row to the "Skills" table in the "Maintaining project RFC files" section, between `/rfc-read-feedback` and `/rfc-approve`. Bump the `<!-- LAST_SYNCED: -->` date at the top of the file to today (`2026-05-12`). |

No new agent files. No hook changes. No mutations to existing skills. No new dependencies.

### Steps

#### Step 1 — Create `skills/rfc-summary/SKILL.md`

Create the file with this exact content:

````markdown
---
name: rfc-summary
description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
---

# RFC Summary

Lists every RFC currently in `Draft` or `Approved` status, grouped by status, oldest first within each group. Output is a quick standup-style snapshot — not a full report. Read-only, no commits.

## Steps

### 1. Verify the project has an RFC directory

Run:

```bash
test -d docs/rfcs
```

If the directory does not exist, tell the user:

> "This project has no `docs/rfcs/` directory. Run `/sync` to set up the RFC process, or `/rfc-new` to create the first RFC."

Stop.

### 2. Enumerate and parse RFC files

The enumeration and sort are performed as a single pipeline in Step 3. This step describes the field format:

Each file yields one tab-separated line: `status<TAB>created<TAB>rfc<TAB>title<TAB>author`.

The `awk` script is bounded by the two `---` lines that delimit the frontmatter block; the `BEGIN { fm = 0 }` counter tracks which `---` we've crossed, and `exit` after the second one ensures we never read past the frontmatter. Field extraction strips the `key: ` prefix and removes surrounding quotes so values are clean strings.

### 3. Filter, sort, and group

Pipe the loop output from Step 2 through `sort`, sorted by `created` ascending then by `rfc` identifier ascending as a stable tiebreaker for same-day RFCs. The full combined command is:

```bash
(for f in docs/rfcs/*.md; do
  [ -f "$f" ] || continue
  awk '
    BEGIN { fm = 0 }
    /^---$/ { fm++; if (fm == 2) exit; next }
    fm == 1 {
      if ($1 == "rfc:")     { sub(/^rfc: */, ""); gsub(/"/, ""); rfc = $0 }
      if ($1 == "title:")   { sub(/^title: */, ""); gsub(/"/, ""); title = $0 }
      if ($1 == "author:")  { sub(/^author: */, ""); gsub(/"/, ""); author = $0 }
      if ($1 == "status:")  { sub(/^status: */, ""); gsub(/"/, ""); status = $0 }
      if ($1 == "created:") { sub(/^created: */, ""); gsub(/"/, ""); created = $0 }
    }
    END { printf "%s\t%s\t%s\t%s\t%s\n", status, created, rfc, title, author }
  ' "$f"
done) | sort -t$'\t' -k2,2 -k3,3
```

This emits one tab-separated line per RFC file in ascending date order, with same-date files ordered by RFC identifier.

Group the sorted output by status. Build three lists:

- **Approved** — rows whose `status` is `Approved`
- **Draft** — rows whose `status` is `Draft`
- **Other** — rows whose `status` is `Done` or `Dropped`; not displayed by row, only counted

Any row with an unrecognized `status` value (i.e., not one of the four canonical lifecycle states) is treated as a parse warning: print `Warning: <filename> has unrecognized status "<value>" — skipping.` to the output and exclude from all counts.

### 4. Render the output

Output is plain Markdown so it renders cleanly in the conversation.

If both `Approved` and `Draft` are empty (no in-flight RFCs):

```markdown
No active RFCs. All RFCs in `docs/rfcs/` are Done or Dropped.

(also: <D> Done, <X> Dropped)
```

Otherwise, render two tables. Always include both headers — if a group is empty, show "No Approved RFCs." or "No Draft RFCs." under the heading instead of an empty table:

```markdown
## Active RFCs

### Approved (ready to implement)

| RFC | Title | Author | Created |
|-----|-------|--------|---------|
| `2026-05-10-foo` | Foo Title | Rodrigo Kochenburger | 2026-05-10 |

### Draft (needs review or approval)

| RFC | Title | Author | Created |
|-----|-------|--------|---------|
| `2026-05-12-bar` | Bar Title | Rodrigo Kochenburger | 2026-05-12 |

**<A> Approved · <D> Draft · <T> in flight**

(also: <X> Done, <Y> Dropped)
```

Where `<A>`, `<D>` are the per-group counts, `<T> = A + D` is the total in-flight count, and `<X>`, `<Y>` are the Done and Dropped counts. The `rfc:` identifier is rendered in inline code (backticks) so it visually distinguishes from the title prose.

### 5. Hand off

Tell the user:

> "Run `/rfc-approve <rfc>` to approve a Draft, `/rfc-implement <rfc>` to begin an Approved RFC, or `/rfc-read-feedback <rfc>` to address inline `FEEDBACK:` comments."

This is one line; it provides the next-step hint without bloating the output. Do not commit. Do not modify any file.

## Constraints

- **Read-only.** This skill does not write, edit, or commit. If asked to "fix" something it surfaces, decline and point at the appropriate mutation skill (`/rfc-approve`, `/rfc-drop`, `/rfc-implement`).
- **No agent spawn.** The skill runs in the main conversation. Listing RFC frontmatter is mechanical; there is no domain reasoning to delegate.
- **Frontmatter contract.** This skill assumes every `docs/rfcs/*.md` file has the frontmatter shape defined in `docs/rfc-process.md` §"Required YAML frontmatter". If parsing yields an empty `rfc` or `status` for a file, print `Warning: <filename> — frontmatter incomplete; skipping.` and continue. Do not abort the whole listing on one malformed file.
````

The skill description tells the main agent (and the user, via autocomplete) what `/rfc-summary` does. The skill body is short — five orchestration steps — because the listing is mechanical.

#### Step 2 — Register the skill in `.claude-plugin/plugin.json`

Open `.claude-plugin/plugin.json`. The current `skills` array is:

```json
"skills": [
  "./skills/best-practices-extract",
  "./skills/best-practices-record",
  "./skills/sync",
  "./skills/git-branch-cleanup",
  "./skills/refactor",
  "./skills/rfc-approve",
  "./skills/rfc-braindump",
  "./skills/rfc-consensus-review",
  "./skills/rfc-drop",
  "./skills/rfc-implement",
  "./skills/rfc-new",
  "./skills/rfc-read-feedback",
  "./skills/rfc-update"
]
```

Insert `"./skills/rfc-summary"` between `"./skills/rfc-read-feedback"` and `"./skills/rfc-update"` so the `rfc-*` family stays alphabetical. The full file after this edit:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  },
  "skills": [
    "./skills/best-practices-extract",
    "./skills/best-practices-record",
    "./skills/sync",
    "./skills/git-branch-cleanup",
    "./skills/refactor",
    "./skills/rfc-approve",
    "./skills/rfc-braindump",
    "./skills/rfc-consensus-review",
    "./skills/rfc-drop",
    "./skills/rfc-implement",
    "./skills/rfc-new",
    "./skills/rfc-read-feedback",
    "./skills/rfc-summary",
    "./skills/rfc-update"
  ]
}
```

Note: the on-disk plugin.json at the time of this RFC has no `skills` array yet (the file is the minimal `name`/`description`/`version`/`author` form from the initial scaffold). If that is still true at implementation time, the implementer adds the entire `skills` array — sourced from the existing `skills/` directory contents — with `"./skills/rfc-summary"` included. If the `skills` array is already present (added by a sibling RFC like `2026-05-10-refactor-command`), insert only the new `rfc-summary` entry in the alphabetical position above and leave the surrounding entries as they exist.

#### Step 3 — Update `CLAUDE.md` (plugin root)

The current "Quick reference (installed projects)" block in `/home/divoxx/.claude/CLAUDE.md` (the user's global) and the plugin's `CLAUDE.md` enumerates the skills as:

```
- Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`
```

This edit is to the plugin's `CLAUDE.md` only (`/home/divoxx/code/bytewyrd/claude-bytewyrd/CLAUDE.md`). The plugin's `CLAUDE.md` has the same enumeration in its RFC Process section:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.
```

Add `/rfc-summary` between `/rfc-read-feedback` and `/rfc-consensus-review`, so the line becomes:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
```

This is the only change to the plugin's `CLAUDE.md`. The user's global `~/.claude/CLAUDE.md` is out of scope for this RFC — it is per-user and not maintained by the plugin.

#### Step 4 — Update `rfc-process.md` (upstream source) and `docs/rfc-process.md` (downstream copy)

**Important:** there are two `rfc-process.md` files in this repository with distinct roles:

- `rfc-process.md` (at the repo root) is the **upstream source**. The `/rfc-update` skill reads `${CLAUDE_PLUGIN_ROOT}/rfc-process.md` at runtime — which resolves to this file as installed in the plugin cache. If this file is not updated, the next `/rfc-update` or `/sync` run in any consumer project will overwrite the `/rfc-summary` row by copying from the stale upstream.
- `docs/rfc-process.md` is the **downstream copy** for this project — the installed copy that users read. It carries `<!-- UPSTREAM: ... -->` and `<!-- LAST_SYNCED: ... -->` sync markers and has a `<!-- END_UPSTREAM_CONTENT -->` separator before any project-specific extensions.

Both files must be updated with the same Skills table change. The `<!-- LAST_SYNCED: -->` bump applies only to `docs/rfc-process.md`.

Three edits total across the two files:

**Edit 4a — Skills table in `rfc-process.md` (upstream source, repo root).**

The current "Skills" table in the "Maintaining project RFC files" section of `rfc-process.md` (repo root) is identical to the one in `docs/rfc-process.md` shown below. Apply the same row insertion: add `/rfc-summary` between `/rfc-read-feedback` and `/rfc-approve`. The root file has no `<!-- LAST_SYNCED: -->` header — only the downstream copy does. No other changes to the root file.

**Edit 4b — Skills table in `docs/rfc-process.md` (downstream copy).**

The current "Skills" table in the "Maintaining project RFC files" section is:

```markdown
| Skill | Purpose |
|-------|---------|
| `/rfc-braindump` | Capture a quick RFC idea into `docs/rfc-braindump.md` |
| `/rfc-new` | Create a new RFC from template, run agent review, run consensus review, and fix critical findings |
| `/rfc-consensus-review` | Spawn 5 parallel reviewers, synthesize findings by consensus, report tiered results |
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments left by humans in an RFC |
| `/rfc-approve` | Approve a Draft RFC (human-invoked) |
| `/rfc-implement` | Begin implementing an Approved RFC |
| `/rfc-drop` | Drop an RFC with a reason |
| `/rfc-update` | Pull upstream changes into `docs/rfc-process.md` (also handled automatically by `/sync`) |
| `/sync` | Set up or refresh the full project Claude Code environment, including RFC process |
```

Insert a `/rfc-summary` row between `/rfc-read-feedback` and `/rfc-approve` (preserving the existing order — the table is not strictly alphabetical, it groups conceptually):

```markdown
| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
```

So the table becomes:

```markdown
| Skill | Purpose |
|-------|---------|
| `/rfc-braindump` | Capture a quick RFC idea into `docs/rfc-braindump.md` |
| `/rfc-new` | Create a new RFC from template, run agent review, run consensus review, and fix critical findings |
| `/rfc-consensus-review` | Spawn 5 parallel reviewers, synthesize findings by consensus, report tiered results |
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments left by humans in an RFC |
| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
| `/rfc-approve` | Approve a Draft RFC (human-invoked) |
| `/rfc-implement` | Begin implementing an Approved RFC |
| `/rfc-drop` | Drop an RFC with a reason |
| `/rfc-update` | Pull upstream changes into `docs/rfc-process.md` (also handled automatically by `/sync`) |
| `/sync` | Set up or refresh the full project Claude Code environment, including RFC process |
```

**Edit 4c — `LAST_SYNCED` header in `docs/rfc-process.md`.**

The file currently has these two header comment lines:

```html
<!-- UPSTREAM: $CLAUDE_PLUGIN_ROOT/rfc-process.md -->
<!-- LAST_SYNCED: 2026-05-10 -->
```

Update the second line to today's date:

```html
<!-- LAST_SYNCED: 2026-05-12 -->
```

This signals that the file is current with respect to upstream as of today, matching the convention `/sync` uses elsewhere.

#### Step 5 — Verification

After all changes, run these checks:

1. **Skill file exists and parses:**

   ```bash
   test -f skills/rfc-summary/SKILL.md && head -4 skills/rfc-summary/SKILL.md
   ```

   Expected output:

   ```
   ---
   name: rfc-summary
   description: Use to list active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date. Filters out Done and Dropped so the output is a standup-style snapshot of in-flight work. Read-only, runs inline (no agent spawn). Triggered by "/rfc-summary".
   ---
   ```

2. **Skill is registered in plugin.json:**

   ```bash
   grep -F '"./skills/rfc-summary"' .claude-plugin/plugin.json
   ```

   Expected output:

   ```
       "./skills/rfc-summary",
   ```

3. **CLAUDE.md mentions the skill:**

   ```bash
   grep -F '/rfc-summary' CLAUDE.md
   ```

   Expected output:

   ```
   RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
   ```

4. **Both rfc-process.md files include the new row:**

   ```bash
   grep -F '| `/rfc-summary` |' rfc-process.md docs/rfc-process.md
   ```

   Expected output: two matching lines, one prefixed `rfc-process.md:` and one prefixed `docs/rfc-process.md:`:

   ```
   rfc-process.md:| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
   docs/rfc-process.md:| `/rfc-summary` | List active RFCs (Draft and Approved) grouped by status for a quick standup snapshot |
   ```

5. **docs/rfc-process.md `LAST_SYNCED` is today:**

   ```bash
   grep -F 'LAST_SYNCED: 2026-05-12' docs/rfc-process.md
   ```

   Expected output:

   ```
   <!-- LAST_SYNCED: 2026-05-12 -->
   ```

6. **Frontmatter parsing smoke test against the current `docs/rfcs/` directory.** Run the `awk` script from Step 2 of `skills/rfc-summary/SKILL.md` against the present `docs/rfcs/` and inspect the tab-separated output:

   ```bash
   for f in docs/rfcs/*.md; do
     [ -f "$f" ] || continue
     awk '
       BEGIN { fm = 0 }
       /^---$/ { fm++; if (fm == 2) exit; next }
       fm == 1 {
         if ($1 == "rfc:")     { sub(/^rfc: */, ""); gsub(/"/, ""); rfc = $0 }
         if ($1 == "title:")   { sub(/^title: */, ""); gsub(/"/, ""); title = $0 }
         if ($1 == "author:")  { sub(/^author: */, ""); gsub(/"/, ""); author = $0 }
         if ($1 == "status:")  { sub(/^status: */, ""); gsub(/"/, ""); status = $0 }
         if ($1 == "created:") { sub(/^created: */, ""); gsub(/"/, ""); created = $0 }
       }
       END { printf "%s\t%s\t%s\t%s\t%s\n", status, created, rfc, title, author }
     ' "$f"
   done
   ```

   Expected output: one line per `docs/rfcs/*.md` file (excluding `.gitkeep`, which has no `.md` suffix and is skipped). At time of writing, the directory contains 20 RFC files, so the output is 20 lines. Each line has five tab-separated fields and no empty fields (every RFC has all five required frontmatter values per `docs/rfc-process.md`). If any line shows an empty field, that file's frontmatter is malformed and is a separate fix outside this RFC's scope.

7. **Manual smoke test (after `claude plugin update bytewyrd` and Claude Code restart):**

   - Type `/` in Claude Code; confirm `/rfc-summary` appears in the autocomplete menu.
   - Type `/rfc-summary` (no arguments) and confirm:
     - Output starts with `## Active RFCs`.
     - There is an `### Approved` section (showing rows or "No Approved RFCs." if empty).
     - There is a `### Draft` section (showing rows or "No Draft RFCs." if empty).
     - Each row has the four columns: `RFC`, `Title`, `Author`, `Created`.
     - The RFC identifier is rendered in `inline code`.
     - The trailing counts line shows `<A> Approved · <D> Draft · <T> in flight`.
     - The trailing parenthetical shows `(also: <X> Done, <Y> Dropped)`.
   - Confirm no commits were made (`git status` shows a clean working tree, assuming it was clean before invocation).
   - Confirm the skill does not prompt for any input or require any arguments.

   If any of these steps fail, the issue is most likely (in order): (a) the `awk` script in Step 2 has a typo causing one or more fields to come back empty (re-check the field-extraction `sub` patterns), (b) the skill is missing from `plugin.json` so `/rfc-summary` does not appear in autocomplete, (c) the user has not run `claude plugin update bytewyrd` to pick up the new skill (the registration only takes effect after the plugin is refreshed).

## Risks and open questions

- **Risk: a malformed RFC frontmatter could cause the `awk` script to emit an incomplete row.** The script has no validation beyond extracting fields by name; a file missing `status:` entirely would produce a row with an empty status, which the filter step treats as unrecognized and warns about. **Mitigation:** the warning is surfaced inline (not silenced). The skill body explicitly says "Do not abort the whole listing on one malformed file" so a single bad file does not break the snapshot. The verification step in Step 4 includes a smoke test against the current `docs/rfcs/` directory that surfaces any current malformed file before the skill ships.

- **Risk: glob pattern matches non-RFC files.** `docs/rfcs/*.md` would include any future hand-added `.md` file in the directory (e.g., an index, a notes file). **Mitigation:** the directory convention per `docs/rfc-process.md` is "one RFC per file, filename `YYYY-MM-DD-<kebab-title>.md`." A non-RFC `.md` file in `docs/rfcs/` would be a process violation; the skill's frontmatter-incomplete warning would surface it for the user to fix. The `.gitkeep` file currently in the directory is correctly skipped because it has no `.md` extension.

- **Open question: should the skill also surface RFCs with inline `FEEDBACK:` markers?** A Draft RFC with unaddressed inline feedback is conceptually different from a Draft RFC awaiting first review. **Resolution within this RFC:** not in scope. The braindump entry asked for "status, title, identifier" only. A future extension could add a `Feedback?` column (a y/n derived from `grep -l 'FEEDBACK:' docs/rfcs/<file>`); that is a one-line addition to the `awk` step if and when the need is concrete. Defer until real-world use shows the need.

- **Open question: should the skill respect a recency cutoff (hide RFCs older than N days even if still in Draft)?** Today the only sort is `created` ascending so old Drafts surface first — which is the desired behavior (old work needs attention). A hide-old-things cutoff would obscure exactly the entries the skill exists to surface. **Resolution within this RFC:** no cutoff. All Drafts and Approved entries are shown regardless of age. If "stale" becomes a meaningful concept, that is a follow-up RFC.

- **Open question: should the skill display anything about the `rfc-braindump.md` file?** Braindump entries are pre-RFC ideas, separate from RFC files in `docs/rfcs/`. They share the "in-flight, not yet acted on" property with `Draft` RFCs, so an argument exists for including them. **Resolution within this RFC:** no. The braindump and the RFC list are conceptually distinct surfaces (the braindump is a parking lot; the RFC list is the active design pipeline). Mixing them would muddy the standup-snapshot framing the braindump entry asked for. A separate `/rfc-braindump-list` (or equivalent) could be added later if needed; out of scope here.

- **Risk: the verification step's expected output assumes today's directory contents.** If a maintainer implements this RFC weeks later, the file counts in Step 4.6 will differ. **Mitigation:** Step 4.6's expected-output language already says "at time of writing" and specifies the shape of the output (five tab-separated fields, no empty fields) rather than a specific count. The shape check is durable; the count is illustrative. Implementers verify the shape, not the count.

## Relationship to other RFCs

This RFC is independent of every other RFC currently in the `docs/rfcs/` directory. It adds a new read-only skill that consumes data the existing RFC process already produces (the frontmatter of files in `docs/rfcs/`); it does not modify the frontmatter contract, the lifecycle, or any other skill.

The closest adjacencies are:

- **2026-05-10-refactor-command** (status: Done) — established the precedent for adding a single new skill to the plugin via a `skills/<name>/SKILL.md` file plus a `plugin.json` registration plus a `CLAUDE.md` mention. This RFC follows the same pattern at a smaller scale (no agent spawn, no `effort:` pinning, no protocol — just a flat listing).
- **`/rfc-approve`, `/rfc-drop`, `/rfc-implement`** — each of these mutation skills includes a step that "lists files in `docs/rfcs/` sorted by name and takes the last as the candidate." That degenerate listing logic is unchanged by this RFC; `/rfc-summary` is a different surface (full listing, status-aware, read-only) that does not displace or duplicate the per-skill defaulting behavior.
- **2026-05-12-post-approval-discretionary-revisions** (status: Draft) — proposes a new section in the RFC template for logging post-approval edits. If that RFC lands, `/rfc-summary` is unaffected (the new section lives in the body, not the frontmatter, so the parser does not need to change). No coordination required.
- **2026-05-12-modular-plugin-feature-toggles** (status: Draft) — proposes feature-toggle-based installation. If that RFC lands and the RFC workflow becomes an opt-in feature, `/rfc-summary` ships with that feature toggle; no change to this RFC required.
