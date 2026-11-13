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

### 2. Enumerate, parse, and sort

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-summary.sh")"
```

`$result` is a JSON object `{"rfcs": [...], "warnings": [...]}`. Extract:

```bash
rfcs="$(printf '%s' "$result" | jq -c '.rfcs')"
warnings="$(printf '%s' "$result" | jq -r '.warnings[]?')"
```

`$rfcs` is a JSON array sorted ascending by `created` then by `rfc` identifier. Iterate it with `printf '%s' "$rfcs" | jq -c '.[]'` to grab each row as an object for step 3's grouping. Print any per-file `$warnings` (incomplete frontmatter, unrecognized status) so the user sees them before the rendered summary. If the script exits non-zero, show the error and stop: either `.error` from `$result` (`jq -r .error`), or the message it wrote to stderr (for example, that bash >= 4 is required). A missing `docs/rfcs/` cannot be the cause here, because step 1 already checked for it.

### 3. Filter and group

Group the sorted rows by status. Build three lists:

- **Approved** — rows whose `status` is `Approved`
- **Draft** — rows whose `status` is `Draft`
- **Other** — rows whose `status` is `Done` or `Dropped`; not displayed by row, only counted

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
