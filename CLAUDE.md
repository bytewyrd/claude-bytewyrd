<!-- bytewyrd:scaffold v1 tpl=CLAUDE.md:96fff00d5f06 plugin=bbef72e2bec6 -->
@AGENTS.md

## Claude Code

- The bytewyrd plugin loads this workflow's conventions at session start. It needs Python 3.11 or newer on `PATH`, or in `BYTEWYRD_PYTHON`. Install it once per machine:
  `claude plugin marketplace add anthropics/claude-plugins-official`, then
  `claude plugin marketplace add bytewyrd/claude-bytewyrd`, then `claude plugin install bytewyrd@bytewyrd`.
  Install its dependencies explicitly too, so updates keep them resolved: `claude plugin install github@claude-plugins-official`, and the same for `context7` and `code-review`.
- Plugin skills are namespaced, for example `/bytewyrd:rfc-new` and `/bytewyrd:drift`.
- Open decisions are asked with AskUserQuestion.

## Agent delegation

New agents added to `agents/` must meet the criteria in [`docs/agent-audit-criteria.md`](docs/agent-audit-criteria.md). Existing agents may be re-audited when the criteria file is updated; the tracking table in that file shows each agent's last-audited criteria version.

## Model Usage Optimization

When spawning subagents, use the cheapest model that fits the task:
- **`model: "haiku"`** — exploration, file search, simple lookups, routine checks, formatting
- **`model: "sonnet"`** — routine code review (correctness, conventions, security), refactoring, implementation of well-defined tasks
- **`model: "opus"`** — RFC and architectural review, complex multi-step problem solving, ambiguous or novel tasks where the problem space itself is unclear

Default to `haiku` unless the task clearly requires more. Err on the side of cheaper models.

## Workflow

### Session start

1. Run `git worktree list` and `git branch --show-current`. Surface active feature-branch worktrees and ask: resume or start new?
2. Run `git fetch --all` before creating branches or worktrees.
3. On `main` with new work: `git worktree add .worktrees/<branch> -b <branch>`.

### Plugin hooks

`hooks/hooks.json` declares three hooks, which run in every project where the plugin is enabled:

- **Always-on rules** (`SessionStart`, matcher `startup|clear|compact`): `cat` prints `hooks/always-on-rules.json`, whose `additionalContext` adds the five workflow conventions to the session. It needs no Python. CI caps that context at 2,000 characters, and the rules change only by reviewed PR.
- **Compact reminder** (`SessionStart`, matcher `compact`): `scripts/bw compact-reminder` reminds Claude to ask the user to run `/docs-review` while `.bytewyrd/last-feature-engineer-stop` is under a day old.
- **SubagentStop reminder** (matcher `(^|:)feature-engineer$`): when a `feature-engineer` subagent finishes, an `echo` reminds Claude to ask the user to run `/docs-review` if the change is user-visible, and `scripts/bw state-touch last-feature-engineer-stop` writes the sentinel the compact reminder reads. `/docs-review` removes it with `state-touch --rm`.

The two `scripts/bw` commands need Python 3.11 or newer and end in `|| true`, so without it they print one stderr line and the hook still exits 0. Hooks run outside the sandbox, so `state-touch`, the only writer into `.bytewyrd/`, refuses symlinks. `tests/scripts/hooks.bats` runs each hook's command string from `hooks.json`.

When you add a skill or agent that depends on a specific external tool, add a probe to the skill body (the in-skill pattern used by `best-practices-extract`) and handle a missing tool there.

### During work

- Use the RFC process (`/rfc-new`) for changes requiring design decisions — read the `rfc-process` skill first.
- Prefer specialized agents over direct implementation in the main context.
- Each parallel agent needs its own worktree. Sub-agents share the parent worktree.
- Never start long-running processes — ask the user to run in a separate terminal.
- **Always write to the current working directory** — if invoked from a worktree, write there. Never use `git rev-parse --git-common-dir` to find the "main" repo root and redirect writes to it. A worktree is the intended branch context; files written there are committed on the branch and reviewed via PR.

### Considering /refactor

Before extending or modifying existing code, consider whether a deliberate refactoring pass would make the upcoming change cleaner. Ask the user to run `/refactor <scope-hint>` when:

- The area you are about to touch has thin test coverage, and adding characterization tests now will protect both the refactor and the subsequent feature work.
- A structural smell (long method, fat conditional, primitive obsession, divergent change) will be amplified by the upcoming feature; refactor first so the new code has a clean place to land.
- A recent PR you are about to merge has cleanup that was deferred because the diff was already large.

`/refactor` instructs the main agent to spawn the `refactoring-specialist` subagent on Opus with `max` effort. It is deliberately expensive — use it for genuine refactoring passes, not for tiny renames (just edit the files for those).

The skill enforces a six-phase protocol: pre-flight (resolve scope, discover test command) → analyze → characterization tests → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific steps, and the subagent applies them one commit at a time.

### Considering /docs-review

Ask the user to run `/docs-review <scope-hint>` when:

- A `/rfc-implement` just landed user-visible changes (a new skill, an agent change, a new flag, a new workflow) — check whether `docs/guide/**` needs updates to match.
- The docs-agent definition has improved — re-audit `docs/guide/**` with the updated checks.
- A user reports a tutorial does not work, a how-to guide references a missing flag, or a reference page is out of date.
- Before a release — sweep `docs/guide/**` to confirm no broken examples or stale references ship to users.

`/docs-review` spawns the `docs-agent` subagent on Sonnet. It is scoped to `docs/guide/**`, the contributor section, and `README.md` (project-owned) — it never touches `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, or anything under `docs/rfcs/`. Those files have separate owners.

The skill enforces a seven-phase protocol: resolve scope → coverage audit → drift detection → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific findings, and the subagent applies them one commit at a time.

### Session end

- Run `/best-practices-extract` if non-obvious learnings emerged.
- Update `docs/ARCHITECTURE.md` if components changed.
- Update `docs/CONTRIBUTING.md` if dev workflow or quality gates changed.
- Commit with Conventional Commits: `type(scope): message`.
