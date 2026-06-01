# <project_name>

<description>

## Toolchain

<LANGUAGE_TOOLCHAIN_SECTION>

## File structure

```
<project_slug>/
├── CLAUDE.md          — this file
├── docs/
│   ├── ARCHITECTURE.md        — system design (devs/agents)
│   ├── BEST_PRACTICES.md      — session learnings (devs/agents)
│   ├── CONTRIBUTING.md        — dev workflow (devs/agents)
│   ├── project-brief.md       — what/why/who (optional)
│   ├── guide/                 — expanded user documentation
│   └── rfcs/                  — RFC proposals
└── src/               — source code
```

## Agent delegation

| Task | Agent |
|------|-------|
<AGENT_TABLE_ROWS>

## Auto Mode

When Claude Code is running in Auto mode, do not make independent decisions — Auto mode grants execution speed, not decision authority. Every action must be grounded in a decision already made by the user (in the conversation, an RFC, a plan, or an explicit instruction). When a choice has not been resolved, stop and surface it rather than deciding unilaterally.

Always prefer the `AskUserQuestion` tool when you need input from the user — it presents a structured, interactive prompt rather than a plain text question and is harder to overlook. Use it even for simple yes/no or option choices.

## Tool Usage

<TOOL_USAGE_SECTION>

## RFC Process

**Only applies to projects set up with `/sync`.** Check for `docs/rfc-process.md` before following any RFC guidance.

- **File exists:** read it (self-contained — full process + any project extensions). Use RFC skills for all design and implementation work.
- **File absent:** RFC process does not apply. Do not follow the RFC workflow.

RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.

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

## Git

- **Never squash commits** or use squash-merge when merging branches. Preserve the full commit history.
- **Use merge, not rebase, to integrate branches.** The only acceptable use of rebase is reorganizing or cleaning up commits within a branch (interactive rebase for tidying before a PR). Never rebase to integrate upstream changes.
- **Confirm before rebasing a shared branch.** If a branch has been pushed to the remote or is not purely local, always ask the user before running any rebase. History rewrites on shared branches affect collaborators.

## Conventions

Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
