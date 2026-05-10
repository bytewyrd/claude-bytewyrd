---
name: rfc-update
description: Use to sync docs/rfc-process.md with upstream. Replaces the core content of the process doc while preserving Project Extensions. Triggered by "/rfc-update" or when upstream changes.
---

# RFC Update

Syncs `docs/rfc-process.md` from upstream — the core section is replaced; the `## Project Extensions` section is preserved.

## Steps

### 1. Pre-flight check

Check that `docs/rfc-process.md` exists:

```bash
test -f docs/rfc-process.md && echo "EXISTS" || echo "NOT FOUND"
```

If the file does not exist: stop and suggest `/sync` (which creates it automatically as part of project setup).

### 2. Sync `docs/rfc-process.md`

Determine the upstream source root:

```bash
echo "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
```

Use the printed path as `PLUGIN_ROOT`. Read `$PLUGIN_ROOT/rfc-process.md` (upstream) and `docs/rfc-process.md` (project file) in full.

Find `<!-- END_UPSTREAM_CONTENT -->` in the project file:
- Everything before = core section (to be replaced)
- Everything after = extensions section (to be preserved)

Extract the raw RFC process text from the core section (strip sync header lines and the marker). Compare to upstream.

**If identical:** note "docs/rfc-process.md already up to date."

**If different:** summarize what changed (added/removed sections, updated wording — no full diff). Rebuild (substitute the literal `$PLUGIN_ROOT` path in the header):

```
<!-- UPSTREAM: <$PLUGIN_ROOT>/rfc-process.md -->
<!-- LAST_SYNCED: <today's date as YYYY-MM-DD> -->
<!-- /rfc-update or /sync replaces everything before END_UPSTREAM_CONTENT when upstream changes. -->

<full verbatim content of $PLUGIN_ROOT/rfc-process.md>

<!-- END_UPSTREAM_CONTENT -->

<preserved extensions section — verbatim, unchanged>
```

Write to `docs/rfc-process.md`.

### 3. Migrate legacy NNN-named RFCs (if present)

Check for files still using the legacy three-digit sequence number format:

```bash
ls docs/rfcs/*.md 2>/dev/null | grep -E '/[0-9]{3}-'
```

If any are found, offer to migrate them:

> Found N RFC(s) with legacy NNN naming:
> - docs/rfcs/001-gateway-namespace.md
> - docs/rfcs/006-billing-budget-alerts-and-enforcement.md
>
> Migrate to YYYY-MM-DD format? This renames each file using the `created:` date from its frontmatter, dropping the NNN prefix. (yes/no)

If confirmed: for each legacy file, read its `created:` frontmatter field for the date. Rename to `docs/rfcs/YYYY-MM-DD-<existing-kebab-title>.md` (strip the `NNN-` prefix, keep the rest). Update the `rfc:` field in the frontmatter to the filename stem (e.g., `"2026-01-15-gateway-namespace"`). Report what was renamed.

If declined, skip and continue.

### 4. Report

Summarize what changed:

```
docs/rfc-process.md  — updated (added: scope check section)
```

If nothing changed: **"Everything is up to date."**

Do **not** commit automatically. The user decides when to commit.
