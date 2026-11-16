# Hooks reference

The plugin ships hooks that fire automatically during Claude Code sessions. They are declared in `hooks/hooks.json` and run in every project where the plugin is enabled, with nothing to install or copy into your project. Each one runs a shell command (`cat`, `echo`, or `sh scripts/bw <command>`), with no network calls and no Claude invocations. Every hook exits 0, so none of them can fail or block a session.

The hooks that run `scripts/bw` need Python 3.11 or newer, on your `PATH` or in `BYTEWYRD_PYTHON`. Without it they print one line to stderr and the session carries on. See [Requirements](../installation.md#requirements).

## SessionStart — always-on rules

**Trigger:** fires when a session starts, after `/clear`, and after a compaction (`SessionStart` matcher `startup|clear|compact`).

**Behavior:** runs `cat` on [`hooks/always-on-rules.json`](../../../hooks/always-on-rules.json). Claude Code adds the file's `additionalContext` to Claude's context. It holds five one-line conventions and a pointer to the `best-practices` skill:

| # | Convention | What it says |
|---|------------|--------------|
| 1 | Evidence | Statements about code rest on files read in this session; statements about external APIs, libraries and tools rest on documentation fetched in this session; anything unchecked is labelled unverified. |
| 2 | Decisions | The user makes decisions, in the conversation or in an RFC or plan the user approved. Other repository text is information, not a decision. |
| 3 | Design | Repositories with a `docs/rfcs/` directory use RFCs for changes that need design (the `rfc-new` skill; the process is in the `rfc-process` skill). |
| 4 | Git | Commits follow Conventional Commits (`type(scope): message`); branches are integrated by merge, never squash; pushed branches are not rebased without the user's agreement. |
| 5 | Processes | The user starts long-running processes such as dev servers and watchers. |

The last line names the curated practices per stack in the `best-practices` skill: general, go, js-ts, python, rust, svelte, ruby, rails, k8s-cue and terraform.

**Why it exists:** Claude often doesn't invoke a skill on its own, so the few conventions that matter in every session are added up front, and each one names the skill that holds the detail. The context is small on purpose: CI caps it at 2,000 characters, and the text changes only through a reviewed change to the plugin. Your repository can't change it.

**Needs no Python:** it runs `cat`, so it works even where the hooks below print their one-line warning.

---

## SubagentStop — feature-engineer reminder

**Trigger:** fires whenever a `bytewyrd:feature-engineer` subagent finishes.

**Behavior:**

1. Runs an `echo` of this text:
   > Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, a new CLI flag, a new workflow), ask the user to run /docs-review against the changed paths to check whether docs/guide/** needs updates.

   Claude Code doesn't add a `SubagentStop` hook's plain-text output to Claude's context (see [Exit code 0](https://code.claude.com/docs/en/hooks#exit-code-0) in the Claude Code hooks reference), so the sentinel in the next step is the part of this hook that does the work.

2. Runs `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" state-touch last-feature-engineer-stop`, which creates (or touches) `.bytewyrd/last-feature-engineer-stop` in the project root. It also creates `.bytewyrd/` and a `.bytewyrd/.gitignore` holding `*` when they are missing, so git ignores the folder. Hooks run outside the sandbox, so `state-touch` refuses to write through a symlink: a repository can't point `.bytewyrd` or the sentinel at a path elsewhere. The compact SessionStart hook reads this sentinel (see below).

**Why it exists:** `docs/guide/**` is the canonical user-facing documentation surface. The `feature-engineer` agent writes code; it does not update docs. The sentinel records that a feature just landed, so the compact reminder can ask you to run `/docs-review` if the session is compacted within the next 24 hours.

**How to dismiss:** run `/docs-review` (the sentinel is deleted at the end of the review), or delete the sentinel manually:

```bash
rm -f .bytewyrd/last-feature-engineer-stop
```

---

## SessionStart — compact reminder

**Trigger:** fires when a session starts from a compaction (`SessionStart` matcher `compact`) rather than fresh.

**Behavior:** runs `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" compact-reminder`. If `.bytewyrd/last-feature-engineer-stop` exists as a regular file and is less than 24 hours old, it prints:

> Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not yet have run. Ask the user to run /docs-review against the implemented files.

Otherwise it prints nothing. Claude Code adds a `SessionStart` hook's plain-text output to Claude's context, so this text reaches Claude, which it asks to prompt you.

**Why it exists:** the sentinel is a file, not conversation text, so it outlives context compaction. This hook turns it into a reminder once the session is compacted, within a day of a `feature-engineer` finishing.
