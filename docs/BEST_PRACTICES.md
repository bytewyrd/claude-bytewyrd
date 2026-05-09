# Best Practices

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/extract-best-practices` at the end of a session to add new entries.

## Pitfall

- **[2026-05-09]** _Pitfall_: `git add .` fails at repo root in Claude Code sandbox sessions because the sandbox creates null-device character files (`.bash_profile`, `.bashrc`, `.gitconfig`, etc.) that aren't real files. Use explicit paths: `git add src/ docs/ CLAUDE.md .claude/` etc.
- **[2026-05-09]** _Pitfall_: Bash `mkdir`/`cp` may fail in Claude Code sandbox sessions due to write restrictions. The Write file tool often bypasses those restrictions — prefer it over Bash for creating files in restricted directories.

## Workflow

- **[2026-05-09]** _Workflow_: Claude Code agents should never start long-running processes (dev servers, test watchers, build watchers) — always ask the user to run these in a separate terminal.
- **[2026-05-09]** _Workflow_: Run `git fetch --all` at the start of every session before creating branches or worktrees to avoid working from stale refs.
- **[2026-05-09]** _Workflow_: Before pushing any change, run the full quality gate locally (fmt check, linter, tests) — not just the step you touched. The pre-push hook enforces this, but run it yourself first so failures are found before the hook fires.
- **[2026-05-09]** _Workflow_: Keep PRs small and focused on a single concern. Large PRs are harder to review, harder to revert, and hide bugs in unrelated diffs.
- **[2026-05-09]** _Workflow_: Commit messages should describe the WHY, not the WHAT. The diff already shows what changed; the message should explain why the change was necessary.
- **[2026-05-09]** _Workflow_: README.md is a user-facing landing page — not a developer guide. It answers: what is this, why should I care, how does it work, how do I get started. Build commands, test commands, and setup steps belong in CONTRIBUTING.md.

## Claude Code

- **[2026-05-09]** _Claude Code_: Gather actual error output and logs before diagnosing a problem — don't assume a cause from symptoms. State hypotheses explicitly ("I think X might be causing Y") rather than compressing them into stated facts.
- **[2026-05-09]** _Claude Code_: Verify subagent outputs before reporting success. An agent's summary describes what it intended to do, not necessarily what it did — check the actual file changes or command output.
- **[2026-05-09]** _Claude Code_: Prefer specialized agents (rust-engineer, python-pro, frontend-developer, etc.) for language- and domain-specific work. They have narrower prompts and better defaults for their domain.

## Architecture

- **[2026-05-09]** _Architecture_: Instrument every component with structured tracing from day one — `tracing` + `tracing-subscriber` (Rust), OpenTelemetry SDK (JS/TS, Go, Python). Binaries initialize with an env-filter (`RUST_LOG`, `OTEL_LOG_LEVEL`) so log verbosity is controlled at runtime without recompilation. Functions that perform I/O or cross a subsystem boundary get a span (`#[instrument]`, `trace.startActiveSpan`). Never use `println!` / `console.log` for diagnostic output in production code.
