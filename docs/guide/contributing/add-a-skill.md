# Add a new skill to the plugin

A skill is a slash command that consumers invoke as `/skill-name` (or `/bytewyrd:skill-name` when there is a naming collision with another plugin). Skills live in `skills/<name>/SKILL.md` at the plugin root and are discovered automatically by Claude Code.

This guide walks through adding a new skill end-to-end.

## Pick the right shape

Two shapes work well:

- **Inline skill** — the skill body is the prompt for the main agent. Use this for short, deterministic flows like `/rfc-summary` or `/rfc-approve` where no subagent is needed.
- **Spawn-an-agent skill** — the skill body instructs the main agent to spawn a specialist subagent with a specific model and tool set. Use this for `/rfc-new`, `/rfc-implement`, `/refactor`, `/docs-review` — anything that benefits from a focused system prompt and a cost-tuned model.

If the work involves multi-step reasoning, file mutations, or a quality gate, prefer the spawn-an-agent shape and write the agent in `agents/<name>.md`.

## Anatomy of a SKILL.md

Every skill file starts with YAML frontmatter:

```markdown
---
name: my-skill
description: Use to do X when Y. Triggered by "/my-skill".
---

# My Skill

(Skill body — markdown that the main agent reads as its prompt.)
```

The `description` field is what Claude Code's autoload heuristic sees. It should:

- Start with a strong trigger word ("Use to…", "Run when…").
- Mention the concrete task and the trigger phrase.
- Be one or two sentences — long descriptions hurt autoload accuracy.

## Choose a name

Use noun-first kebab-case so related skills sort together. Compare:

- Good: `rfc-new`, `rfc-approve`, `rfc-implement`, `best-practices-record`, `best-practices-extract`
- Bad: `new-rfc`, `record-best-practice`

Check `skills/` to make sure your name does not collide with an existing skill. If it does, pick a different name — Claude Code's namespace is flat per plugin.

## Create the skill

From the plugin checkout:

```bash
mkdir skills/my-skill
$EDITOR skills/my-skill/SKILL.md
```

Author the frontmatter and body. If the skill spawns an agent, write the agent file at `agents/<agent-name>.md` and reference it from the skill body. Match the agent's `name` frontmatter to the filename — Claude Code's discovery is name-based.

## Test the skill locally

The plugin's own checkout is installed as a local plugin (see [`docs/CONTRIBUTING.md`](../../CONTRIBUTING.md) for the setup). Restart Claude Code so the new skill is picked up, then in a session:

```
/my-skill
```

If your skill takes arguments:

```
/my-skill <argument>
```

Iterate. Each Claude Code restart re-reads `skills/`, so your edit-cycle is: edit → restart → invoke → observe → repeat.

## Update the agent delegation table

If the skill changes how agents are delegated (e.g., it spawns a new specialist), update the **Agent delegation** table in `CLAUDE.md` so future sessions know the skill exists.

## Update the README skills table

Add a row to the **Skills** table in `README.md` with the trigger and a one-line summary. The table is the user's first stop for discovering what the plugin can do.

## Commit

Use the Conventional Commits format with the `skill` scope:

```
feat(skill): add /my-skill — <one-line summary>
```

If the change is meaningful for end users (which a new skill usually is), capture it via `/best-practices-extract` at the end of the session so future projects pick up the pattern.

## Related

- [Add a new agent to the plugin](add-an-agent.md) — for the spawn-an-agent shape.
- [`docs/CONTRIBUTING.md`](../../CONTRIBUTING.md) — local-install setup and edit cycle.
- [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md) — design rationale for the skills/agents split.
