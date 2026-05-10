## Evidence-Based Development

The core operating principle: every claim, diagnosis, and recommendation must be grounded in evidence — not assumption, intuition, or training knowledge.

**Gather symptoms before diagnosing.** When something is broken, collect actual errors first: check logs, examine observable state, reproduce the problem. Read code to understand a known problem — not to find an unknown one.

**Distinguish hypothesis from conclusion.** When you think you know the cause, say so explicitly: "I think X might be causing Y." Don't compress a hypothesis into a stated fact because it feels likely. Verify before acting.

**Verify what you test.** Before proposing a verification step, trace the exact execution path it exercises. Ask: does this actually trigger the specific change I made, or does it go through an adjacent path that could give a false positive?

**Training knowledge is a search query, not a source of truth.** For any external API, cloud service, library, or tool — look it up before asserting behavior. Use **Exa** and **Context7** as described in the Tool Usage section below. If no authoritative source is found, say so explicitly rather than guessing.

**Reason through the full problem.** Many problems contain subtle constraints, hidden assumptions, or trick aspects invisible to surface-level pattern matching. Verify that your answer holds given all the details — not just the most salient one.

## Operating Rules

- Before executing any task, check the skills and agents available in the session context. Prefer specialized agents and skills over direct implementation in the main context.
- Never start long-running processes (dev servers, test watchers, etc.) — always ask the user to run these in a separate terminal.
- When refactoring, ensure behavior, design, and output are exactly the same. Write missing tests if needed.
- Before starting any work, run `git fetch --all` to ensure the local copy is up to date.
- **Never create git worktrees autonomously.** If you determine a worktree is needed, ask the user to create it. If the current branch is `main`, always ask the user whether to create a worktree or whether changes directly to `main` are appropriate — never proceed without explicit confirmation.

## Tool Usage

### Exa — web search and URL fetching

**Use Exa as the default for any web lookup.** Do not use `WebSearch` unless Exa is unavailable.

Use `mcp__exa__web_search_exa` whenever you need:
- Information from the web about anything not in the codebase
- Error messages, changelogs, release notes, or community discussions
- Package or crate information not covered by Context7
- Cross-referencing behavior across multiple sources

Use `mcp__exa__crawling_exa` to fetch a specific URL's full content (docs pages, GitHub issues, blog posts).

**Never say "I don't have access to current information"** before trying Exa. Try first.

### Context7 — library and SDK documentation

**Mandatory before writing code that uses an external library, framework, or CLI tool** — even ones you know well. API signatures and configuration options change between versions; training knowledge is unreliable.

Use `mcp__plugin_context7_context7__resolve-library-id` then `mcp__plugin_context7_context7__query-docs` for:
- Any npm package, Rust crate, Go module, Python package
- Frameworks (Svelte, React, Axum, Actix, etc.)
- Cloud SDKs and CLI tools
- Any time the user asks "how do I use X" or "what's the API for Y"

If Context7 has no entry for a library, fall back to Exa.

### Firefox MCP — visual verification

**Required for any frontend or UI change before reporting work done.**

The dev server must already be running (the user starts it — never start long-running processes yourself). If it's not running, ask the user to start it before attempting visual verification.

Standard verification flow for frontend changes:
1. `mcp__firefox-devtools__list_pages` — find the running app tab, or use `mcp__firefox-devtools__navigate_page` to open it
2. `mcp__firefox-devtools__screenshot_page` — capture the current state
3. Exercise the changed feature: use `mcp__firefox-devtools__click_by_uid`, `mcp__firefox-devtools__fill_by_uid`, etc.
4. `mcp__firefox-devtools__list_console_messages` — verify no errors or warnings
5. `mcp__firefox-devtools__screenshot_page` — capture the result

Use `mcp__firefox-devtools__take_snapshot` to inspect the accessibility tree when diagnosing layout or interaction issues.

**Do not skip visual verification for UI changes** and then claim the feature works. If Firefox is not open, say so explicitly rather than skipping the step.

## GitHub Operations

- **Prefer the GitHub MCP** (`mcp__plugin_github_github__*` tools) for all GitHub operations — no re-prompting, session-scoped auth, cleaner than CLI.
- **If the GitHub MCP is not available**, recommend installing it before falling back to the CLI.
- When writing PRs and comments/reviews, always sign as Generated with Claude Code

## Security

- Never expose token or credentials in committed code, or by making it available to the browser/frontend.

## Development Workflow

### Step 1 — Session start: new work or continuation?

**FIRST ACTION every session — before reading files, issues, or doing anything else:**

Run these two checks:
```bash
git worktree list
git branch --show-current
```

**If you find active feature-branch worktrees or you're already on a feature branch:**

Gather context, then surface it to the user before doing anything:
- Branch name and worktree path (from `git worktree list`)
- Task summary from a plan file if one exists in `docs/plans/` in the worktree (optional — not all repos use plans)
- Summary of recent commits (`git log --oneline -5` in the worktree)

Then ask:
> "I see in-progress work on `<branch>` at `<path>` — [brief task description from plan/commits].
> Resume that, or start something new?"

Wait for the user to decide.

- **Resume:** `cd` into the worktree, read the plan file if present, review todo state, then continue.
- **New work:** proceed with Step 2 below.

**If on main with no active feature worktrees:** proceed directly to Step 2.

---

### Step 2 — Starting new work

1. `git checkout main && git pull`
2. Use the `/worktrunk` skill to create an isolated worktree + branch for this task.

**Parallel agents:** each agent must run in its own worktree on its own branch. Never share a worktree
between agents. This enables independent, parallel work without conflicts. This doesn't apply to sub-agents.

All work — code, plans, specs — happens inside the worktree so it's committed with the PR.

## Superpowers

Superpowers skills (brainstorming, writing-plans, etc.) are for **brainstorming and ideation only**.

**If the current project has `docs/rfc-process.md`** (set up with `/sync`): use the RFC process for all design, architecture, and implementation planning — do **not** use superpowers brainstorming or writing-plans skills for this work.

**If the project has not been set up with `/sync`**: superpowers skills are the accepted approach for planning and ideation.

**Spec and plan storage:** Write all brainstorming specs and plans outside project repositories, to:
```
~/.claude/superpowers/<project-path>/
```
where `<project-path>` mirrors Claude Code's memory path convention: take the absolute repo root path, strip the leading `/`, and replace every `/` with `-`.

Example: `/home/user/code/myproject` → `~/.claude/superpowers/-home-user-code-myproject/`

Filename format: `YYYY-MM-DD-<topic>-design.md` for specs, `YYYY-MM-DD-<topic>-plan.md` for plans.

## RFC Process

**The RFC process only applies to projects that have been set up with `/sync`.** Check for `docs/rfc-process.md` before following any RFC guidance.

- **File exists:** read `docs/rfc-process.md` (self-contained — full process + any project extensions). Use the RFC skills for all design and implementation work.
- **File absent:** the RFC process does not apply to this project. Do not read `~/.claude/rfc-process.md` or follow the RFC workflow. Use superpowers skills for planning instead.

**Quick reference (installed projects):**
- RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`
- Lifecycle: `Draft → Approved → Done | Dropped`
- Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`

## Claude Code Sandbox — Container Tool Compatibility

Claude Code's Linux sandbox uses bwrap (bubblewrap). When bwrap is not installed setuid (check: `ls -la $(which bwrap)`), it creates an unprivileged user namespace to perform bind-mounts. This makes rootless container tools (podman, docker) fail inside the sandbox because their UID-remapping step (`newuidmap`) sees the process as owned by UID 65534 (nobody) rather than the real user.

**The fix:** add wrapper scripts to `sandbox.excludedCommands` in `.claude/settings.local.json`. Commands in this list bypass bwrap entirely — all their child processes (including the container runtime) also run unsandboxed.

```json
{
  "permissions": {
    "allow": ["Bash(./run *)", "Bash(./deploy *)", "Bash(./bootstrap *)"]
  },
  "sandbox": {
    "excludedCommands": ["./run *", "./deploy *", "./bootstrap *"]
  }
}
```

**What does NOT work:**
- `enableWeakerNestedSandbox: true` — only removes `--proc /proc` from bwrap, has no effect on user namespaces or UID remapping
- `sandbox.filesystem.allowWrite` paths alone — the problem is a kernel security check, not a filesystem permission
- Adding `podman` directly to `excludedCommands` — bwrap wraps the shell session, so child processes of an included parent are still inside the namespace

**Pattern format matters:** use `"./run *"` (with wildcard), not `"./run"` — the docs show `"docker *"` as the canonical example.

**Settings file scope:** keep this in `.claude/settings.local.json` (gitignored), not the committed `settings.json`, since it is personal to the developer's machine.

## Model Usage Optimization

When spawning subagents via the Task tool, conserve quota by selecting the cheapest model that fits the task:
- **`model: "haiku"`** — exploration, file search, simple lookups, routine checks, formatting
- **`model: "sonnet"`** — code review, moderate refactoring, implementation of well-defined tasks
- **`model: "opus"`** — complex architectural reasoning, multi-step problem solving, ambiguous or novel tasks

Default to `haiku` unless the task clearly requires more capability. Err on the side of cheaper models.
