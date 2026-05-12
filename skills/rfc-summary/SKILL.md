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
