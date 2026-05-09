---
name: rfc-install
description: Use when setting up the RFC process in a project for the first time. Creates docs/rfc-process.md, docs/rfcs/.gitkeep, and copies all RFC skills into .claude/skills/ so every developer on the project has access. Triggered by "/rfc-install".
---

# RFC Install

Sets up the RFC process in the current project. Run this once per project. Copies both the process document and all RFC skills into the repo so any developer on any machine has access without global config.

## Steps

### 1. Pre-flight check

Check whether `docs/rfc-process.md` already exists:

```bash
test -f docs/rfc-process.md && echo "EXISTS" || echo "NOT FOUND"
```

If the file exists: stop and tell the user — the RFC process is already installed. Suggest `/rfc-update` to sync with upstream changes.

### 2. Read upstream process

Read `~/.claude/rfc-process.md` in full.

### 3. Write `docs/rfc-process.md`

Write the project file with this exact structure:

```
<!-- UPSTREAM: ~/.claude/rfc-process.md -->
<!-- LAST_SYNCED: <today's date as YYYY-MM-DD> -->
<!-- /rfc-update replaces everything before END_UPSTREAM_CONTENT when upstream changes. -->

<full verbatim content of ~/.claude/rfc-process.md>

<!-- END_UPSTREAM_CONTENT -->

---

## Project Extensions

*(no project-specific extensions — the global process applies as-is)*
```

The upstream content goes verbatim between the sync header and `<!-- END_UPSTREAM_CONTENT -->`. Do not modify, reformat, or summarize it.

### 4. Create `docs/rfcs/.gitkeep`

```bash
mkdir -p docs/rfcs && touch docs/rfcs/.gitkeep
```

### 5. Copy RFC skills into the project

The skills to copy are (`rfc-braindump`, `rfc-install`, `rfc-update`, `rfc-new`, `rfc-read-feedback`, `rfc-approve`, `rfc-implement`, `rfc-drop`, `rfc-consensus-review`).

**First, probe for sandbox restrictions:**

```bash
mkdir -p .claude/skills/_probe && rm -d .claude/skills/_probe && echo "OK" || echo "SANDBOXED"
```

**If `OK`:** proceed normally — create directories and write each skill file:

```bash
mkdir -p .claude/skills/rfc-braindump \
         .claude/skills/rfc-install \
         .claude/skills/rfc-update \
         .claude/skills/rfc-new \
         .claude/skills/rfc-read-feedback \
         .claude/skills/rfc-approve \
         .claude/skills/rfc-implement \
         .claude/skills/rfc-drop \
         .claude/skills/rfc-consensus-review
```

For each skill: read `~/.claude/skills/<skill-name>/SKILL.md` and write it verbatim to `.claude/skills/<skill-name>/SKILL.md`.

**If `SANDBOXED`:** copy the bundled script to `$TMPDIR/rfc-install.sh` and tell the user:

```bash
cp ~/.claude/skills/rfc-install/install-skills.sh $TMPDIR/rfc-install.sh
```

> The sandbox prevented writing to `.claude/skills/`. Run this to complete the install:
> `bash $TMPDIR/rfc-install.sh`

The script lives at `~/.claude/skills/rfc-install/install-skills.sh` — it is never regenerated inline.

### 6. Report

Tell the user:
- `docs/rfc-process.md` created (synced from upstream, LAST_SYNCED date)
- `docs/rfcs/.gitkeep` created
- 9 RFC skills copied to `.claude/skills/` (or: script written to `/tmp/claude/rfc-install.sh`)
- Next step: use `/rfc-new` to create the first RFC

Do **not** commit automatically. The user decides when to commit.
