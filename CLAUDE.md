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

When you add a skill or agent that depends on a specific external tool, add a probe to the skill body (the in-skill pattern used by `best-practices-extract`, `refactor`, and `rfc-implement`) and handle a missing tool there.

### During work

- Use the RFC process (`/rfc-new`) for changes requiring design decisions — check for `docs/rfc-process.md` first.
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
- `/sync` reports the docs-agent definition has improved — re-audit `docs/guide/**` with the updated checks.
- A user reports a tutorial does not work, a how-to guide references a missing flag, or a reference page is out of date.
- Before a release — sweep `docs/guide/**` to confirm no broken examples or stale references ship to users.

`/docs-review` spawns the `docs-agent` subagent on Sonnet. It is scoped to `docs/guide/**`, the contributor section, and `README.md` (bootstrap-once: written by `/sync` at project creation, then project-owned) — it never touches `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, or anything under `docs/rfcs/`. Those files have separate owners.

The skill enforces a seven-phase protocol: resolve scope → coverage audit → drift detection → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific findings, and the subagent applies them one commit at a time.

### Session end

- Run `/best-practices-extract` if non-obvious learnings emerged.
- Update `docs/ARCHITECTURE.md` if components changed.
- Update `docs/CONTRIBUTING.md` if dev workflow or quality gates changed.
- Commit with Conventional Commits: `type(scope): message`.

## Maintaining the bootstrap manifest

The `bootstrap-manifest.json` file records the current SHA-256 hash of every artifact source that `/sync` manages. It must stay in sync with the actual source files.

**After editing any artifact source or template file** (anything under `templates/`, or a non-templated source like `rfc-process.md`), regenerate the manifest:

```bash
scripts/build-manifest.sh
```

The script walks the manifest, recomputes the `sha256` or `template_sha` for each artifact's source file, and also recomputes `upstream_key` (fingerprinted from `extension_strategy` + strategy config — see Architecture Decision table). It preserves all other structural metadata (`extension_strategy`, `owned_sections`, `owned_paths`, `templated`, `template_inputs`) — it never modifies those fields.

**Adding a new artifact:** edit the manifest by hand to add the new entry (with a placeholder `sha256: ""` or `template_sha: ""`), then run `build-manifest.sh` to compute the hash and `upstream_key`. The script computes `upstream_key` automatically — `extension_strategy` still requires maintainer judgment, `upstream_key` does not.

**The pre-commit hook** (`hooks/pre-commit/manifest-check.sh`) runs `build-manifest.sh --check` and fails the commit if the manifest is stale. This prevents shipping a plugin where the recorded hash for an artifact does not match the artifact's current content, which would cause every consumer to see phantom fast-forward updates on the next `/sync` run.

To wire the hook into git (one-time setup per clone; run it from the main checkout, not a worktree):

```bash
ln -sf "$(git rev-parse --show-toplevel)/hooks/pre-commit/manifest-check.sh" "$(git rev-parse --git-path hooks)/pre-commit"
```

If `git config core.hooksPath` prints a directory that other repositories share (for example one set in your global git config), don't run this: it would install this repository's hook for all of them, and their commits would fail because they have no `scripts/build-manifest.sh`. Rely on CI's check instead. Otherwise, `git rev-parse --git-path hooks` resolves to the hooks directory git actually uses: the shared `.git/hooks` of the main checkout (also from inside a worktree, where `.git` is a file and a literal `.git/hooks/...` path fails), or `core.hooksPath` when that is set. Every worktree shares that one hook, and the script it points to checks the manifest of whichever checkout is committing. Create the link from the main checkout because a link into a worktree dangles once the worktree is removed, and git then skips the hook without any message. The script is committed executable (`100755`), so no `chmod` is needed. CI's `lint` job runs the same `build-manifest.sh --check` on every pull request.
