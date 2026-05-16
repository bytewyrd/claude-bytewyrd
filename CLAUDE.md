# Bytewyrd's Claude Plugin

Opinionated Claude Code plugin for Bytewyrd projects — skills, agents, and RFC-driven workflow

## Toolchain

No language-specific toolchain detected. Add source code and re-run `/sync` to pick up language tooling.

## File structure

```
claude-bytewyrd/
├── CLAUDE.md                    — this file
├── agents/                      — subagent definitions (originally from VoltAgent/awesome-claude-code-subagents, MIT; now locally owned)
├── skills/                      — exported plugin skills (auto-discovered by Claude Code)
├── .claude-plugin/
│   └── plugin.json              — plugin identity and metadata
├── .claude/skills/              — plugin-local maintenance skills (not exported to consumers)
├── docs/
│   ├── ARCHITECTURE.md          — system design (devs/agents)
│   ├── BEST_PRACTICES.md        — session learnings (devs/agents)
│   ├── CONTRIBUTING.md          — dev workflow (devs/agents)
│   ├── project-brief.md         — what/why/who (optional)
│   ├── guide/                   — expanded user documentation
│   └── rfcs/                    — RFC proposals
└── README.md
```

## Agent delegation

| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| User-facing docs (`docs/guide/**`, `README.md`) | docs-agent (via `/docs-review`) |
| General-purpose docs (ad-hoc) | documentation-writer |
| Claude agent authoring | claude-agent-author |
| Debugging | debugger |

New agents added to `agents/` must meet the criteria in [`docs/agent-audit-criteria.md`](docs/agent-audit-criteria.md). Existing agents may be re-audited when the criteria file is updated; the tracking table in that file shows each agent's last-audited criteria version.

## Tool Usage

### Exa — web search

Use `mcp__exa__web_search_exa` for any web lookup — error messages, release notes, package info, community discussions. It is the default, not a fallback. Use `mcp__exa__crawling_exa` to fetch a specific URL's content. Never say "I don't have access to current information" without trying Exa first.

### Context7 — library documentation

Mandatory before writing code that uses an external library, framework, or CLI tool. Use `mcp__plugin_context7_context7__resolve-library-id` then `mcp__plugin_context7_context7__query-docs`. Fall back to Exa if Context7 has no entry.

### Firefox MCP — visual verification

Required before reporting any UI or frontend change done. The dev server must already be running (never start long-running processes yourself — ask the user). Standard flow: `list_pages` → `screenshot_page` → interact with the feature → `list_console_messages` → `screenshot_page` to confirm result. Use `take_snapshot` for accessibility tree inspection.

## RFC Process

**Only applies to projects set up with `/sync`.** Check for `docs/rfc-process.md` before following any RFC guidance.

- **File exists:** read it (self-contained — full process + any project extensions). Use RFC skills for all design and implementation work.
- **File absent:** RFC process does not apply. Do not follow the RFC workflow.

RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.

## Evidence-Based Development

Every claim, diagnosis, and recommendation must be grounded in evidence — not assumption, intuition, or training knowledge.

**Gather symptoms before diagnosing.** Collect actual errors first: check logs, examine observable state, reproduce the problem. Read code to understand a known problem — not to find an unknown one.

**Distinguish hypothesis from conclusion.** Say "I think X might be causing Y" — don't compress a hypothesis into a stated fact. Verify before acting.

**Verify what you test.** Trace the exact execution path a verification step exercises. Ask: does this actually trigger the specific change I made, or is it a false positive?

**Training knowledge is a search query, not a source of truth.** For any external API, cloud service, library, or tool — look it up with Exa or Context7 before asserting behavior. If no authoritative source is found, say so explicitly.

## Model Usage Optimization

When spawning subagents, use the cheapest model that fits the task:
- **`model: "haiku"`** — exploration, file search, simple lookups, routine checks, formatting
- **`model: "sonnet"`** — routine code review (correctness, conventions, security), refactoring, implementation of well-defined tasks
- **`model: "opus"`** — RFC and architectural review, complex multi-step problem solving, ambiguous or novel tasks where the problem space itself is unclear

Default to `haiku` unless the task clearly requires more. Err on the side of cheaper models.

## Claude Code Sandbox — Container Tool Compatibility

Claude Code's Linux sandbox uses bwrap (bubblewrap). When bwrap is not installed setuid, rootless container tools (podman, docker) fail inside the sandbox because `newuidmap` sees the process as owned by UID 65534 (nobody).

**The fix:** add wrapper scripts to `sandbox.excludedCommands` in `.claude/settings.local.json`:

```json
{
  "permissions": { "allow": ["Bash(./run *)", "Bash(./deploy *)"] },
  "sandbox": { "excludedCommands": ["./run *", "./deploy *"] }
}
```

Use `"./run *"` (with wildcard), not `"./run"`. Keep in `settings.local.json` (gitignored), not `settings.json`.

**What does NOT work:** `enableWeakerNestedSandbox: true`, `sandbox.filesystem.allowWrite` paths, or adding `podman` directly to `excludedCommands`.

## Security

- Never expose tokens, credentials, or API keys in committed code, logs, or environment variable dumps.
- Never make secrets available to the browser or frontend, even temporarily.
- **Never paste secret values, `.env` files, or credential files into the conversation.** If you need to reference a secret, use a placeholder (e.g. `$DATABASE_URL`) and describe where it is stored — Claude does not need to see the value to help you.
- If asked to read a file that may contain secrets (`.env`, `credentials.json`, `*.pem`, `~/.aws/credentials`, etc.) — refuse and ask for a sanitized version or structural description instead.
- Validate and sanitize all external input at system boundaries before it enters domain logic.
- Use a secret manager or environment variables at runtime; never hardcode secret values in source files, config templates, or test fixtures.

## Workflow

### Session start

1. Run `git worktree list` and `git branch --show-current`. Surface active feature-branch worktrees and ask: resume or start new?
2. Run `git fetch --all` before creating branches or worktrees.
3. On `main` with new work: `git worktree add .worktrees/<branch> -b <branch>`.

### Requirement-check hook

The plugin ships a `SessionStart` hook (`hooks/hooks.json` → `scripts/check-requirements.sh`) that runs once per session in every project where the plugin is enabled. The hook probes:

- Companion plugin enable-state (`github@claude-plugins-official`, `context7@claude-plugins-official`, `code-review@claude-plugins-official`) via `~/.claude/settings.json` and the project's `.claude/settings.json`.
- MCP server configuration (Exa, Firefox MCP) via permission entries in user or project settings.
- `git` and `gh` CLI availability on `PATH`.
- Stale references in the project's `.claude/settings.json` pointing at uninstalled plugins.

The hook outputs nothing when everything is satisfied. It outputs a warning bundle when soft dependencies are missing (session continues). It exits with status 2 only on two conditions: missing `git`, or a stale `claude-plugins-official` reference that Claude Code itself would error on later. Individual warnings can be suppressed via `BYTEWYRD_SKIP_WARN=<id1>,<id2>` in the user's shell environment.

When you add a new skill or agent that depends on a specific external tool, decide whether to (a) add a probe to the skill body (the in-skill pattern used by `best-practices-extract`, `refactor`, and `rfc-implement`), or (b) extend `scripts/check-requirements.sh` to surface the gap at session start. Use (a) when the dependency is specific to one skill and the failure can be handled locally; use (b) when the dependency is plugin-wide and the user should know about it on day one rather than mid-task.

### During work

- Use the RFC process (`/rfc-new`) for changes requiring design decisions — check for `docs/rfc-process.md` first.
- Prefer specialized agents over direct implementation in the main context.
- Each parallel agent needs its own worktree. Sub-agents share the parent worktree.
- Never start long-running processes — ask the user to run in a separate terminal.
- **Always write to the current working directory** — if invoked from a worktree, write there. Never use `git rev-parse --git-common-dir` to find the "main" repo root and redirect writes to it. A worktree is the intended branch context; files written there are committed on the branch and reviewed via PR.

### Considering /refactor

Before extending or modifying existing code, consider whether a deliberate refactoring pass would make the upcoming change cleaner. Run `/refactor <scope-hint>` when:

- The area you are about to touch has thin test coverage, and adding characterization tests now will protect both the refactor and the subsequent feature work.
- A structural smell (long method, fat conditional, primitive obsession, divergent change) will be amplified by the upcoming feature; refactor first so the new code has a clean place to land.
- A recent PR you are about to merge has cleanup that was deferred because the diff was already large.

`/refactor` instructs the main agent to spawn the `refactoring-specialist` subagent on Opus with `max` effort. It is deliberately expensive — use it for genuine refactoring passes, not for tiny renames (just edit the files for those).

The skill enforces a six-phase protocol: pre-flight (resolve scope, discover test command) → analyze → characterization tests → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific steps, and the subagent applies them one commit at a time.

### Considering /docs-review

Run `/docs-review <scope-hint>` when:

- A `/rfc-implement` just landed user-visible changes (a new skill, an agent change, a new flag, a new workflow) — check whether `docs/guide/**` needs updates to match. (A `SubagentStop` hook on `feature-engineer` surfaces a reminder at this moment.)
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

The script walks the manifest, recomputes the `sha256` or `template_sha` for each artifact's source file, and writes back a sorted, pretty-printed manifest. It preserves all structural metadata (`upstream_key`, `extension_strategy`, `owned_sections`, `owned_paths`, `templated`, `template_inputs`) from the existing manifest — it only updates the hash fields.

**Adding a new artifact:** edit the manifest by hand to add the new entry (with a placeholder `sha256: ""` or `template_sha: ""`), then run `build-manifest.sh` to compute the hash. The script never invents `upstream_key` or `extension_strategy` values — those require maintainer judgment.

**The pre-commit hook** (`hooks/pre-commit/manifest-check.sh`) runs `build-manifest.sh --check` and fails the commit if the manifest is stale. This prevents shipping a plugin where the recorded hash for an artifact does not match the artifact's current content, which would cause every consumer to see phantom fast-forward updates on the next `/sync` run.

To wire the hook into git (one-time setup on a fresh clone):

```bash
ln -sf ../../hooks/pre-commit/manifest-check.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Conventions

Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
