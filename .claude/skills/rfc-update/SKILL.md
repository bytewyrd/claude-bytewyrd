---
name: rfc-update
description: Use to sync docs/rfc-process.md and .claude/skills/rfc-*/ with upstream. Replaces the core content of the process doc while preserving Project Extensions, and updates skill files that differ from upstream. Triggered by "/rfc-update" or when upstream changes.
---

# RFC Update

Syncs two things from upstream:
1. `docs/rfc-process.md` — the core section is replaced; the `## Project Extensions` section is preserved.
2. `.claude/skills/rfc-*/SKILL.md` — each skill file is compared to its upstream counterpart and replaced if different.

## Steps

### 1. Pre-flight check

Check that `docs/rfc-process.md` exists:

```bash
test -f docs/rfc-process.md && echo "EXISTS" || echo "NOT FOUND"
```

If the file does not exist: stop and suggest `/rfc-install`.

### 2. Sync `docs/rfc-process.md`

Read `~/.claude/rfc-process.md` (upstream) and `docs/rfc-process.md` (project file) in full.

Find `<!-- END_UPSTREAM_CONTENT -->` in the project file:
- Everything before = core section (to be replaced)
- Everything after = extensions section (to be preserved)

Extract the raw RFC process text from the core section (strip sync header lines and the marker). Compare to upstream.

**If identical:** note "docs/rfc-process.md already up to date."

**If different:** summarize what changed (added/removed sections, updated wording — no full diff). Rebuild:

```
<!-- UPSTREAM: ~/.claude/rfc-process.md -->
<!-- LAST_SYNCED: <today's date as YYYY-MM-DD> -->
<!-- /rfc-update replaces everything before END_UPSTREAM_CONTENT when upstream changes. -->

<full verbatim content of ~/.claude/rfc-process.md>

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

### 4. Sync RFC skill files

The skills to sync are (`rfc-braindump`, `rfc-install`, `rfc-update`, `rfc-new`, `rfc-read-feedback`, `rfc-approve`, `rfc-implement`, `rfc-drop`, `rfc-consensus-review`).

**First, probe for sandbox restrictions:**

```bash
mkdir -p .claude/skills/_probe && rm -d .claude/skills/_probe && echo "OK" || echo "SANDBOXED"
```

**If `OK`:** for each skill:

1. Check whether `~/.claude/skills/<skill>/SKILL.md` exists. If not, skip (upstream missing — no-op).
2. Check whether `.claude/skills/<skill>/SKILL.md` exists in the project. If not, create the directory and copy.
3. If both exist: compare content. If identical, skip. If different, copy the upstream version and note the update.

**If `SANDBOXED`:** write the following script to `/tmp/claude/rfc-update.sh`, then tell the user:

> The sandbox prevented writing to `.claude/skills/`. Run this to complete the update:
> `bash /tmp/claude/rfc-update.sh`

Script contents:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Syncs RFC skills from the global Claude install into this project.
# Skips skills that are already up to date.
# Run from the project root: bash /tmp/claude/rfc-update.sh

readonly GLOBAL_SKILLS="${HOME}/.claude/skills"
readonly PROJECT_SKILLS=".claude/skills"

readonly SKILLS=(
  rfc-braindump
  rfc-install
  rfc-update
  rfc-new
  rfc-read-feedback
  rfc-approve
  rfc-implement
  rfc-drop
  rfc-consensus-review
)

main() {
  local updated=0
  local unchanged=0

  echo "Syncing RFC skills in ${PROJECT_SKILLS}/ ..."

  for skill in "${SKILLS[@]}"; do
    local src="${GLOBAL_SKILLS}/${skill}/SKILL.md"
    local dst="${PROJECT_SKILLS}/${skill}/SKILL.md"

    if [[ ! -f "${src}" ]]; then
      echo "  SKIP     ${skill} — not found in global install"
      continue
    fi

    if [[ -f "${dst}" ]] && diff -q "${src}" "${dst}" > /dev/null 2>&1; then
      echo "  UNCHANGED ${skill}"
      unchanged=$(( unchanged + 1 ))
      continue
    fi

    mkdir -p "${PROJECT_SKILLS}/${skill}"
    cp "${src}" "${dst}"
    echo "  UPDATED  ${skill}"
    updated=$(( updated + 1 ))
  done

  echo ""
  echo "Done: ${updated} updated, ${unchanged} unchanged."
  if [[ "${updated}" -gt 0 ]]; then
    echo "Commit .claude/skills/ to share the updates with the team."
  fi
}

main "$@"
```

### 5. Report

Summarize what changed:

```
docs/rfc-process.md  — updated (added: scope check section)
rfc-approve/SKILL.md — updated (now requires RFC number)
rfc-new/SKILL.md     — already up to date
... (etc.)
```

If nothing changed: **"Everything is up to date."**

Do **not** commit automatically. The user decides when to commit.
