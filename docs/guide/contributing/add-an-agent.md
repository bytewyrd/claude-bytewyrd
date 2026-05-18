# Add a new agent to the plugin

A subagent is a specialist that the main agent can spawn for a focused task. Agents have their own system prompt, tool allow-list, and model preference. They live in `agents/<name>.md` at the plugin root.

This guide covers adding a new agent. For pulling improvements to an existing agent from the upstream `VoltAgent/awesome-claude-code-subagents` project, see [`docs/CONTRIBUTING.md`](../../CONTRIBUTING.md).

## When to author a new agent

Add a new agent when:

- A skill needs a focused system prompt that does not fit anywhere in the existing catalog.
- A recurring task in the plugin's workflow benefits from a curated tool list (e.g., only Read + Bash + Grep, no Write).
- You want a specific model assignment (Opus for deliberate reasoning, Haiku for cheap lookups).

Do **not** add an agent for one-off work that could just be a skill body running inline against the main agent. Subagents are spawned in separate contexts and cost extra round-trips — they should earn their place.

## Anatomy of an agent file

Every agent is a single `.md` file with YAML frontmatter:

```markdown
---
name: my-agent
description: Use this agent when <trigger>. <Examples block>
model: sonnet
color: blue
---

You are a <role description>...
```

Required fields:

- `name` — must match the filename (`my-agent` → `my-agent.md`). Claude Code's discovery is name-based.
- `description` — autoload trigger. Should contain `<example>` blocks per the bytewyrd plugin's [agent audit criteria](../../agent-audit-criteria.md).
- `model` — `haiku`, `sonnet`, or `opus`. Default to the cheapest model that fits.

Optional:

- `color` — visual marker in `/agents` output.
- `tools` — explicit allow-list; omit to inherit all tools (which is the default for most agents).

## Pick the right model

| Task | Model |
|------|-------|
| Exploration, file search, simple lookups, routine checks | `haiku` |
| Routine code review, refactoring, implementation of well-defined tasks | `sonnet` |
| RFC and architectural review, complex multi-step problems, ambiguous tasks | `opus` |

Err on the cheaper side. The skill body that spawns the agent can override the model at invocation time, so the frontmatter is the default for standalone invocations, not a hard binding.

## Pre-audit checklist

Before committing, walk through the criteria in [`docs/agent-audit-criteria.md`](../../agent-audit-criteria.md):

- **H1 — Tool allow-list:** is the tool set the minimum needed? Omitting `tools:` inherits everything, which is fine for general-purpose agents but wrong for narrow ones.
- **H2 — Examples in description:** at least two `<example>` blocks covering the agent's actual triggers. The autoload heuristic uses them.
- **H3 — Model matches tier:** Tier 1 (actively-delegated, on a hot path) defaults to `opus`. Tier 2 (routine work) defaults to `sonnet`. Tier 3 (cheap one-shot) is `haiku`.
- **H4 — No fictional coordination prose:** do not claim the agent "coordinates with" other agents or "communicates via the context manager." Subagents run alone.
- **H7 — Project context:** name the bytewyrd plugin and how the agent fits into the workflow.

Each new agent gets an `<!-- Audit log -->` comment at the bottom recording the criteria version and what was checked. Existing agents are re-audited when the criteria file is updated.

## Create the agent

```bash
$EDITOR agents/my-agent.md
```

Write the frontmatter, the system prompt, and the audit log. Keep the body under 250 lines — long agent prompts hurt routing quality and inflate every invocation's token cost.

## Wire it into a skill (if applicable)

If the agent is meant to be spawned by a specific skill, update that skill's `SKILL.md` to invoke it with the correct model and arguments. The skill body is the prompt the main agent sees — make it spell out exactly when and how to spawn the new agent.

## Test the agent

Restart Claude Code. In a session, invoke the skill that spawns the agent, or invoke the agent directly:

```
Use the my-agent subagent to <task>.
```

Watch the spawn: the main agent should describe handing off to `my-agent` with the expected prompt and model. The agent's response should match its system prompt's tone and scope.

## Update the agent delegation table

In `CLAUDE.md`, add a row to the **Agent delegation** table mapping the agent's role to its name. This is what future sessions read to know the agent exists.

## Update the README agents table

Add a row in the **Agents** table in `README.md`. The table is the consumer's entry point for discovering the catalog. If your addition pushes the count past the rounded marketing number, update the count in the surrounding prose too.

## Commit

```
feat(agent): add my-agent — <one-line summary>
```

## Related

- [Add a new skill to the plugin](add-a-skill.md) — for the skill-and-agent pair pattern.
- [Agents reference](../reference/agents.md) — every existing agent's role and model.
- [`docs/agent-audit-criteria.md`](../../agent-audit-criteria.md) — the audit checklist.
- [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md) — agents-vs-skills design rationale.
