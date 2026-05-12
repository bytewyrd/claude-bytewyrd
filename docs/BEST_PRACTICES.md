# Best Practices

<!-- bootstrap-content-version: 2026-05-10-8e478c1 -->

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries.

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
- **[2026-05-12]** _Claude Code_: Authorization for a preparatory action (rebasing, fixing a conflict, updating a file) does not imply authorization for the next step in the workflow (approving, merging). Each step that affects shared state or is hard to reverse requires its own explicit instruction — "resolve the conflict on #10" is not a mandate to approve or merge.

## Architecture

- **[2026-05-09]** _Architecture_: Instrument every component with structured tracing from day one — `tracing` + `tracing-subscriber` (Rust), OpenTelemetry SDK (JS/TS, Go, Python). Binaries initialize with an env-filter (`RUST_LOG`, `OTEL_LOG_LEVEL`) so log verbosity is controlled at runtime without recompilation. Functions that perform I/O or cross a subsystem boundary get a span (`#[instrument]`, `trace.startActiveSpan`). Never use `println!` / `console.log` for diagnostic output in production code.
- **[2026-05-09]** _Architecture_: Design at the boundary level first — define what crosses a boundary (data formats, error contracts, interfaces) before writing implementation. Changing a boundary is expensive; changing internals is cheap.
- **[2026-05-09]** _Architecture_: Separate domain logic from infrastructure from day one. Business rules must not import database drivers, HTTP clients, or framework types. This boundary makes unit testing cheap and technology migrations possible.
- **[2026-05-09]** _Architecture_: Prefer boring technology that the whole team can reason about over sophisticated patterns that only their author understands. Complexity is a liability unless it solves an equally complex problem.
- **[2026-05-09]** _Architecture_: Keep coupling explicit and directional — draw the dependency graph and verify it is a DAG. Circular dependencies are a sign that boundaries are wrong, not that more interfaces are needed.
- **[2026-05-09]** _Architecture_: Add abstraction only when you have at least two concrete cases that actually need it. One use case is not a pattern; it is premature generalization.

## Refactoring

- **[2026-05-09]** _Refactoring_: Never mix refactoring with behavior changes in the same commit. A refactor commit should have a trivially passing review — "structure changed, nothing else." This constraint also forces you to understand the code before changing it.
- **[2026-05-09]** _Refactoring_: Before refactoring, establish a test that pins the current behavior. If no test exists, write one first. Refactoring without a safety net is rewriting with hope.
- **[2026-05-09]** _Refactoring_: Prefer small, surgical refactors over large "cleanup" PRs. A 5-line rename is reviewable in minutes; a 500-line restructure takes hours and hides bugs inside the noise.
- **[2026-05-09]** _Refactoring_: Rename aggressively. Wrong names compound — they mislead future readers and spawn more wrong names. A precise rename is one of the highest-ROI refactors available.
- **[2026-05-09]** _Refactoring_: Refactor toward the problem domain, not toward patterns. "This should be a Strategy" is a weak reason; "this switch will gain a fourth case next sprint" is a strong one.

## Code Design

- **[2026-05-10]** _Code Design_: A module named `utils`, `helpers`, or `misc` is a textbook example of coincidental cohesion — the weakest type on Constantine's scale, where members are grouped by convenience rather than shared purpose. Every function that ends up there belongs in a domain-aligned module; if you cannot name the module after a concept, the abstraction is missing, not the catch-all.
- **[2026-05-10]** _Code Design_: Apply "Parse, Don't Validate" (Alexis King, 2019): convert raw input into a typed value that structurally encodes its validity constraints, so downstream code cannot use unvalidated data. When enrichment requires external context, make it a separate `resolve(context)` step — keeping parsing pure and dependency-free, and making the enrichment dependencies explicit at the call site.

## Code Style

- **[2026-05-10]** _Code Style_: Optimize code for humans first. Group logically related statements with a blank line between distinct phases (setup, execution, output). A blank line costs nothing and saves the next reader from mentally parsing what belongs together.

## Testing

- **[2026-05-10]** _Testing_: Tests are non-negotiable — a feature without tests is incomplete. The question is not *whether* to test but *at what level*: pure logic gets unit tests, subsystem boundaries get integration tests, full user flows get end-to-end tests.
- **[2026-05-10]** _Testing_: Practice TDD on pure logic — Red (failing test that captures the requirement) → Green (smallest change that passes) → Refactor (improve structure with the test as a safety net). The cycle prevents over-engineering: code exists only to pass a stated test, not to satisfy an imagined future.
- **[2026-05-10]** _Testing_: TDD-produced tests are documentation of intended usage. Because the test is written before the implementation, it must show how a caller invokes the component — its shape, inputs, and outputs — making the test a worked example a reader can study to understand the design.
- **[2026-05-10]** _Testing_: Default to the testing pyramid: many fast unit tests of pure logic, fewer integration tests of subsystem boundaries, fewest end-to-end tests of full user flows. Inverting the pyramid (mostly e2e) makes the suite slow, flaky, and expensive to debug.
- **[2026-05-10]** _Testing_: Use property-based testing (`proptest` in Rust, `fast-check` in TS, `hypothesis` in Python) for code with algebraic invariants — round-tripping serializers, idempotent operations, sort/parse/normalize functions. Hand-written cases miss adversarial inputs that generators surface in seconds.
- **[2026-05-10]** _Testing_: Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code. Mocking your own collaborators couples tests to implementation details and makes refactoring expensive.
- **[2026-05-10]** _Testing_: A flaky test is a broken test — quarantine or fix it the same day, never the same week. Flaky tests train the team to ignore CI failures, which lets a real failure slip through unnoticed.

## Documentation

- **[2026-05-10]** _Documentation_: Documentation is a first-class deliverable, not a chore. A feature that ships without docs is incomplete in the same way as one without tests — the code may run, but no one outside its author can use, review, or evolve it confidently.
- **[2026-05-10]** _Documentation_: Three audiences, three files: `README.md` (users — what is this and how do I run it), `docs/CONTRIBUTING.md` (developers — how do I work on it), `docs/ARCHITECTURE.md` (system designers — how is it built and why). Mixing audiences forces every reader through irrelevant content.
- **[2026-05-10]** _Documentation_: Write docs for the *next* developer (often you in six months), not for the current one. Explain *why* a decision was made, not just what was decided — the diff already shows the what.
- **[2026-05-10]** _Documentation_: Examples are the highest-density docs. A working example beats a paragraph of prose — copy-paste-ability is what real users need. Keep examples in `examples/` and run them in CI so they cannot rot silently.
- **[2026-05-10]** _Documentation_: Code comments explain *why* and *what for*, not *what*. The code already shows what it does; a comment that paraphrases the code adds noise. A comment that captures the constraint, the trade-off, or the reason for an apparent contradiction is gold.
- **[2026-05-10]** _Documentation_: Open source project icon pattern: a standalone square SVG icon + markdown `<h1>` is the dominant convention for developer CLI tools; the icon reuses as GitHub org avatar, npm icon, and favicon — a wordmark SVG is too wide for those contexts and name changes require SVG edits rather than a one-line markdown update.
- **[2026-05-10]** _Documentation_: `<img align="absmiddle">` inside an `<h1>` vertically aligns an icon with heading text in GitHub-rendered markdown without table layout markup.
- **[2026-05-10]** _Documentation_: Plugin/integration icon trademark: when an icon would naturally evoke a platform's trademarked mark, create a geometrically inspired original rather than reproducing the trademark — common practice in plugin ecosystems, avoids IP risk.
- **[2026-05-10]** _Documentation_: Surface org-vs-product distinction prominently in the hero and a dedicated section — not buried in Non-Goals. "Anyone can use this" buried in Non-Goals is effectively invisible to readers who skim.

## Security

- **[2026-05-10]** _Security_: Never expose tokens, credentials, or secrets in committed code, in client-side bundles, or in logs. Pull secrets from a secret manager at runtime; redact known-secret keys from log output unconditionally.
- **[2026-05-10]** _Security_: Validate input at the boundary, then trust it inside. A request enters validation once (at the HTTP layer, message boundary, etc.) and emerges as a typed domain value — no defensive re-validation throughout the stack, no reaching back to "what was the raw string."
- **[2026-05-10]** _Security_: Run with the lowest privilege required. Service accounts get the narrowest IAM role; container processes run as non-root; database users get only the schemas they need. Privileges are a one-way ratchet — easy to grant, painful to revoke.
- **[2026-05-10]** _Security_: Pin and audit dependencies. Lockfiles (`Cargo.lock`, `bun.lockb`, `go.sum`, `uv.lock`) commit the exact versions you tested; an automated audit step (`cargo audit`, `bun audit`, `govulncheck`, `pip-audit`) catches CVEs in CI rather than in the wild.
- **[2026-05-10]** _Security_: Treat AuthN and AuthZ as separate concerns. Authentication answers "who is this"; authorization answers "may they do this". Conflating them is how systems end up with `if user.is_admin` checks scattered through business logic.

## Error Handling

- **[2026-05-10]** _Error Handling_: Distinguish recoverable errors (return them) from programmer errors (panic / abort). A failed network call is recoverable; a violated invariant inside your own code is not — recovering from it produces zombie state.
- **[2026-05-10]** _Error Handling_: Errors carry context. The error returned three layers up should tell the operator what the system was trying to do, what failed, and what input was involved — not just the leaf cause. `anyhow::Context`, error wrapping, `Error.cause`, all serve the same goal.
- **[2026-05-10]** _Error Handling_: Errors should be observable before they are user-visible. Structured logs and metrics catch the error trend (rising 500s, retry exhaustion) before the user reports the symptom.
- **[2026-05-10]** _Error Handling_: Retries belong at the edge of an idempotent operation. Wrapping a non-idempotent call in retry logic doubles the transactions and corrupts state. If the operation isn't idempotent, make it idempotent (request IDs, conditional updates) before retrying.

## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md).

- **[2026-05-10]** _Project-Specific_: claude-bytewyrd: the plugin namespace in Claude Code sessions is `bytewyrd:` (hence `/bytewyrd:sync`) but the install address is `bytewyrd/claude-bytewyrd` — these are distinct identifiers for distinct contexts and must not be conflated in docs or code.
