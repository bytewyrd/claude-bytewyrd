# claude-bytewyrd User Guide

This guide is for people who *use* the `claude-bytewyrd` plugin in their projects — and for people who want to contribute to the plugin itself.

If you are looking for the plugin's internal design or developer workflow, see [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) and [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md) instead — those serve plugin maintainers, not consumers.

## Where to start

This guide is organized using the [Diátaxis](https://diataxis.fr/) framework. Pick the section that matches what you want to do right now:

### Tutorials — *learn by doing*

Step-by-step lessons that take you from zero to a working result. Start here if you are new.

- [Getting started](tutorials/getting-started.md) — install the plugin, run `/sync`, author and approve your first RFC, then implement it.

### How-to guides — *recipes for specific tasks*

Task-oriented guides for things you already know you want to do.

- [Install the plugin](installation.md) — install at user or project scope.
- [Add a new skill to the plugin](how-to/add-a-skill.md) — author a `/skill-name` command consumers can invoke.
- [Add a new agent to the plugin](how-to/add-an-agent.md) — drop a specialist subagent into `agents/` for delegation.
- [Suppress session-start warnings](how-to/suppress-session-warnings.md) — silence individual requirement-check warnings when they don't apply to your project.

### Reference — *look it up*

The full surface of the plugin. Skills and agents, the data behind them.

- [Skills reference](reference/skills.md) — every slash command, sourced from each skill's frontmatter.
- [Agents reference](reference/agents.md) — every specialist agent, sourced from each agent's frontmatter.

### Contributing to the plugin

If you want to work on the plugin itself — propose changes, add skills, modify agents — start with [contributing.md](contributing.md). It covers plugin anatomy, conventions, and the extension points you'll touch most often.

For the narrow dev-workflow ops (clone, install locally, commit conventions, quality gate), see [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md) — `contributing.md` here cross-links to it rather than duplicating.
