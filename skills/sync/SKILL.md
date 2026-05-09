---
name: sync
description: Set up or refresh a project repository with all standard conventions — idempotent, safe to re-run whenever the plugin updates. Triggered by "/sync".
---

<!-- bootstrap-content-version: 2026-05-09-init03 -->

# Sync

Sets up or refreshes a project repository with all standard conventions. Idempotent — safe to re-run whenever the plugin updates; existing files are skipped, missing files are created.

## Interaction model

Sync runs almost entirely autonomously. There are exactly **two points** where user input is collected:

1. **Step 2** — Two AskUserQuestion calls: project brief preference, then display name and description.
2. **Step 5** (only if `brief_mode = "help"`) — One AskUserQuestion call with 4 project-brief questions.

Everything else — environment detection, file creation, GitHub metadata update, RFC install, and the final report — happens without asking the user.

## Step 1 — Validate environment + detect installed plugins + detect GitHub remote

Run:
```bash
git rev-parse --show-toplevel
git config user.name
```

If either fails, stop with a clear error message.

If the repo already has substantial committed content (more than a LICENSE/README), note: "This repo already has content — sync will skip any files that already exist and only create the ones that are missing."

**Derive `project_slug`** — the repo/package identity name:

```bash
basename $(git rev-parse --show-toplevel)
```

This is the raw directory name as-is (e.g., `tinywyrd`, `eve-platform`). It is never changed or asked about. It is used anywhere the machine-readable name is needed: CLI binary references, package name examples, `cd <project-slug>` in setup docs, etc.

**Detect GitHub remote (use to pre-populate defaults in Step 2):**

```bash
git remote get-url origin 2>/dev/null
```

If this returns a `github.com` URL, run:

```bash
gh repo view --json name,description
```

Store `github_description` (the repo's current description, empty string if unset) as the default for the description question in Step 2. If `gh` is unavailable or fails, proceed without it.

Then read `~/.claude/plugins/installed_plugins.json`. Extract the `plugins` object keys to get the set of installed plugin identifiers. Cross-check against:

| Plugin | Identifier | Criticality |
|--------|-----------|-------------|
| GitHub MCP | `github@claude-plugins-official` | Critical |
| Context7 | `context7@claude-plugins-official` | Recommended |
| Code Review | `code-review@claude-plugins-official` | Recommended |

Note: Exa is a separate MCP server (not a plugin) — its permissions go unconditionally in `settings.local.json`.

Store:
- `installed`: set of installed plugin identifiers
- `missing`: recommended plugins not in `installed`

If `github@claude-plugins-official` is missing from `installed`, warn but do not stop.

---

## Step 2 — Gather project info

This step uses **two sequential AskUserQuestion calls**: brief first, then name and description. The brief is asked first because an existing brief can supply the project name and description, which informs the defaults for the second call.

`"Other"` is a special label in the Claude Code UI — it renders as a text input field rather than a plain button. Do not add any label like "Type below" or "Enter custom"; the text field is self-explanatory.

### 2a — Project brief

**Check first:** if `docs/project-brief.md` already exists, skip the question entirely — set `brief_mode = "added"` automatically and proceed to extract name and description from it. Do not ask the user.

If the file does not exist, ask one question:

**"Do you have a project brief?"** — a short document capturing what the project is for, who it serves, and what's in/out of scope
- Option 1: `Help me create one` — sync will ask you 4 questions after setup and fill in `docs/project-brief.md`
- Option 2: `I've added the file to docs/project-brief.md` — sync reads it and uses it to pre-populate name and description
- Auto-added `Other` text input: anything entered is treated as skip (store `null`)

Store `brief_mode`:
- `"help"` if "Help me create one" selected
- `"added"` if "I've added the file" selected (or if the file was already present)
- `null` otherwise

**If `brief_mode = "added"`:** read `docs/project-brief.md`. Extract:
- `brief_name` — first `# Heading` line if present, strip the `# ` prefix
- `brief_description` — first non-heading, non-blank, non-HTML-comment sentence or paragraph

These become the defaults for Step 2b.

### 2b — Name and description

AskUserQuestion with two questions:

1. **"What is the project name?"** *(human/display name — used in headings and docs)*
   - Default option: `brief_name` if extracted, otherwise Title Case of `project_slug` (e.g., `tinywyrd` → `Tinywyrd`)
   - `Other` option: free-text input for a custom display name

2. **"One-sentence description?"**
   - If `brief_description` is non-empty: options are `<brief_description>` (click to accept), `Other` (text input to replace it)
   - Else if `github_description` is non-empty: options are `<github_description>` (click to accept), `Other` (text input to replace it)
   - Otherwise: options are `Skip — I'll fill it in later`, `Other` (text input for description)
   - If "Skip" is selected, store an empty string and leave the `<description>` placeholder in generated files.

Store answers as:
- `project_name` — human display name (from 2b question 1)
- `project_slug` — repo identity name (derived in Step 1, not asked)
- `description` — (from 2b question 2)
- `has_github` — derived from Step 1: `true` if a `github.com` remote was detected, `false` otherwise. Never asked.
- `brief_mode` — `"help"`, `"added"`, or `null`

**Languages are not asked** — they are detected automatically in Step 3 by scanning manifest files. Sync is idempotent: re-run it after adding source code to pick up new languages and fill in any missing language-specific files.

---

## Step 3 — Detect component structure

Scan the repo for language manifest files to determine component roots. Run all commands — language detection is the output of this step, not an input:

```bash
# Rust
find . -name "Cargo.toml" -not -path "*/target/*" | sort

# JS/TS
find . -name "package.json" -not -path "*/node_modules/*" | sort

# Go
find . -name "go.mod" | sort

# Python
find . -name "pyproject.toml" -o -name "setup.py" | grep -v "*/node_modules/*" | sort

# Svelte
find . -name "*.svelte" -not -path "*/node_modules/*" | head -1

# Ruby / Rails
find . -name "Gemfile" -not -path "*/vendor/*" | head -1
find . -name "config/application.rb" | head -1

# Kubernetes / CUE / kapply
find . -name "*.cue" -path "*/k8s/*" | head -1
grep -rl "kapply" .github/ Dockerfile* Makefile 2>/dev/null | head -1

# Terraform / Terragrunt
find . -name "*.tf" -not -path "*/.terraform/*" | head -1
find . -name "terragrunt.hcl" | head -1
```

**Build `component_roots`** — a list of `{ language, path, name }` entries:

- **Rust**: If root `Cargo.toml` contains `[workspace]`, read its `members` array — each member is a component. If it's a standalone crate, the component is `.`. If no `Cargo.toml` exists, default to `.`.
- **JS/TS**: Each directory containing a `package.json` is a component. Use the `name` field from the JSON as the component name, falling back to the directory name.
- **Go**: Each directory containing a `go.mod` is a module/component.
- **Python**: Each directory containing `pyproject.toml` or `setup.py` is a component.
- **If nothing is found for a language**: default to a single component at `.`.

**Derive stack-detection flags** — independent of component roots, the following booleans gate the stack-specific best-practice sections appended in Step 5:

- `has_svelte = true` if any `*.svelte` file is found OR `"svelte"` appears in any `package.json` `dependencies` or `devDependencies` field.
- `has_ruby = true` if a `Gemfile` is found.
- `has_rails = true` if `config/application.rb` is found OR `"rails"` gem is listed in the `Gemfile`.
- `has_k8s_cue = true` if any `*.cue` file under `k8s/` is found OR `kapply` appears in a CI workflow or `Dockerfile`.
- `has_terraform = true` if any `*.tf` file is found OR any `terragrunt.hcl` is found.

These flags are consumed by Step 5's `docs/BEST_PRACTICES.md` creation policy: sync appends the matching addition block only when its flag is true (e.g., the Svelte block only when `has_svelte`, the Rails block only when `has_rails` and after the Ruby block since Rails depends on Ruby being present).

Since sync is idempotent, re-running it after adding new components will detect them and fill in any missing config.

---

## Step 4 — Print creation summary

Check which target files already exist. Print:
1. Detected components (language → paths), so the user can see what was found
2. A two-column file summary — **will create** vs **will skip** (exists)

Proceed immediately — no confirmation needed.

---

## Step 5 — Create core files

**File creation policy:** Check whether each file exists before writing. **Skip any file that already exists — never overwrite.** The only exceptions are:
- `.gitignore` — always append-only: add missing entries, never remove existing ones
- `.worktrees/` — always create if absent (idempotent)
- **Name and description sync** — always apply, even to existing files:
  - In `CLAUDE.md`: update the `# <heading>` on line 1 if it differs from `project_name`; update the description paragraph directly after the heading if it differs from `description` (skip if description is empty)
  - In `README.md`: update the `# <heading>` on line 1 if it differs; update the `> <blockquote>` description on line 3 if it differs (skip if description is empty)

Track each file as `created`, `updated`, or `skipped` for the Step 8 report.

### `.worktrees/`
Create the directory (worktrunk places worktrees at `.worktrees/<branch-sanitized>`).

### `docs/guide/`
Create with a `.gitkeep` so the directory is tracked. This is where expanded user documentation lives (tutorials, how-to guides, configuration reference). README.md links here; individual guide files are added as the project grows.

### `docs/project-brief.md`

**If `brief_mode = "added"`** — the file already exists; skip creation. Note it in the Step 8 report as "exists — used for name/description".

**If `brief_mode = "help"`** — create the blank template first (so the file exists), then after completing all other steps, ask the user four questions conversationally and fill in the answers:

```markdown
# Project Brief

## Problem

<!-- What problem does this project solve? Who is it for? -->

## Goals

<!-- What does success look like? What are the key outcomes? -->

## Non-Goals

<!-- What is explicitly out of scope? -->

## Constraints

<!-- Technical, time, budget, or other constraints that shape the solution -->
```

Ask using AskUserQuestion with all four questions in a single call. For each question, include exactly two options:
1. A pre-generated contextual suggestion (infer from `project_name`, `description`, and detected language — e.g. for a Rust buildpack the problem option might be "Enables deploying Rust apps to CNB-compatible platforms without custom Dockerfiles, for Rust developers and platform teams.")
2. `Other` — label only, **no description text**

`"Other"` is a special label that the Claude Code UI renders as a free-text input. Do not add any description to it, and do not use any variant label like "Type my answer below" or "Enter custom".

Write the answers into the corresponding sections of `docs/project-brief.md`. If the user typed a custom answer via `Other`, use that text. If the user selected the pre-generated option, use it verbatim. Leave the HTML comment placeholder in place for any section the user skipped.

**If `brief_mode = null`** — skip entirely; do not create the file.

### `.gitignore`
If the file exists, read it first and append only entries that are not already present.
If absent, create it.

Always add:
```
.worktrees/
.claude/settings.local.json
```

Add the entries for every detected language (union of all, append-only):
- **Rust**: `target/`
- **JS/TS**: `node_modules/`, `dist/`
- **Go**: (nothing extra — Go's standard toolchain handles this)
- **Python**: `__pycache__/`, `*.pyc`, `.venv/`
- **Shell/Infra**: `.terragrunt-cache/`, `.terraform/`, `.terraform.lock.hcl`

### `CLAUDE.md`

Create with the following template, filling in the placeholders:

```markdown
# <project_name>

<description>

## Toolchain

<LANGUAGE_TOOLCHAIN_SECTION — see table below>

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
<AGENT_TABLE_ROWS — see table below>

## Tool Usage

<TOOL_USAGE_SECTION — see table below>

## RFC Process

**Only applies to projects set up with `/rfc-install`.** Check for `docs/rfc-process.md` before following any RFC guidance.

- **File exists:** read it (self-contained — full process + any project extensions). Use RFC skills for all design and implementation work.
- **File absent:** RFC process does not apply. Do not follow the RFC workflow.

RFCs live in `docs/rfcs/`; filename format `NNN-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.

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

## Conventions

Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
```

**Toolchain section:** Include one line per detected language:

| Language | Toolchain text |
|---|---|
| Rust | `Rust — see \`rust-toolchain.toml\`. Build: \`cargo build\`. Test: \`cargo test\`. Lint: \`cargo clippy\`.` |
| JS/TS | `JavaScript/TypeScript — see \`mise.toml\` for Bun version. Install: \`bun install\`. Test: \`bun test\`.` |
| Go | `Go — see \`mise.toml\` for Go version. Build: \`go build ./...\`. Test: \`go test ./...\`.` |
| Python | `Python — see \`mise.toml\` for Python version. Install: \`uv sync\`. Test: \`uv run pytest\`.` |
| Shell/Infra | `Infrastructure — see \`mise.toml\` for tool versions. Deploy: \`./deploy <env>\`.` |

If no languages are detected, write: `No language-specific toolchain detected. Add source code and re-run \`/sync\` to pick up language tooling.`

**Agent delegation table:** Merge rows from all detected languages; deduplicate shared agents (feature-engineer, code-reviewer, rfc-architect, documentation-writer, debugger appear once regardless of how many languages are detected):

| Language | Language-specific agent |
|---|---|
| Rust | rust-engineer (Rust-specific code) |
| JS/TS | typescript-pro (TypeScript-specific), frontend-developer (UI components) |
| Go | golang-pro (Go-specific code) |
| Python | python-pro (Python-specific code) |
| Shell/Infra | terraform-engineer (IaC), kubernetes-specialist (k8s manifests), cloud-architect (architecture), sre-engineer (reliability) |

Shared agents always added (once): feature-engineer (new features), code-reviewer (code reviews), rfc-architect (architecture/RFCs), documentation-writer (docs), debugger (debugging).

**Tool Usage section:** Build from what is available. Include a block for each tool present. Exa and Firefox MCP are unconditional (always included because their permissions are always written to `settings.local.json`). Context7 is included only if `context7@claude-plugins-official` is in `installed`.

Exa block (always):
```
### Exa — web search

Use `mcp__exa__web_search_exa` for any web lookup — error messages, release notes, package info, community discussions. It is the default, not a fallback. Use `mcp__exa__crawling_exa` to fetch a specific URL's content. Never say "I don't have access to current information" without trying Exa first.
```

Context7 block (if `context7@claude-plugins-official` is installed):
```
### Context7 — library documentation

Mandatory before writing code that uses an external library, framework, or CLI tool. Use `mcp__plugin_context7_context7__resolve-library-id` then `mcp__plugin_context7_context7__query-docs`. Fall back to Exa if Context7 has no entry.
```

Firefox MCP block (always):
```
### Firefox MCP — visual verification

Required before reporting any UI or frontend change done. The dev server must already be running (never start long-running processes yourself — ask the user). Standard flow: `list_pages` → `screenshot_page` → interact with the feature → `list_console_messages` → `screenshot_page` to confirm result. Use `take_snapshot` for accessibility tree inspection.
```

If none of the above tools are installed, omit the `## Tool Usage` section entirely from `CLAUDE.md`.

### `docs/BEST_PRACTICES.md`

Create with the base content below, substituting `<TODAY>` with today's date in `YYYY-MM-DD` format. Then append every applicable section.

**Append order:**
1. **Architecture addition** — always.
2. **Universal additions** (Testing, Documentation, Security, Error Handling) — always.
3. **Language additions** — append every language-specific block that matches a detected component:
   - **Rust** — if Rust is detected.
   - **JS/TS** — if JS/TS is detected.
   - **Python** — if Python is detected.
   - **Go** — if Go is detected.
   - **Svelte** — if `has_svelte` is true (Step 3).
   - **Ruby** — if `has_ruby` is true (Step 3).
   - **Rails** — if `has_rails` is true; appended after the Ruby block.
   - **Kubernetes / CUE / kapply** — if `has_k8s_cue` is true (Step 3).
   - **Terraform / Terragrunt** — if `has_terraform` is true (Step 3).

A mixed project like Rust + Svelte frontend + Terraform infra gets the Rust, JS/TS, Svelte, and Terraform blocks (Svelte implies the underlying JS/TS also applies).

**Base content (all projects):**

```markdown
# Best Practices

<!-- bootstrap-content-version: 2026-05-09-init03 -->

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries.

## Pitfall

- **[<TODAY>]** _Pitfall_: `git add .` fails at repo root in Claude Code sandbox sessions because the sandbox creates null-device character files (`.bash_profile`, `.bashrc`, `.gitconfig`, etc.) that aren't real files. Use explicit paths: `git add src/ docs/ CLAUDE.md .claude/` etc.
- **[<TODAY>]** _Pitfall_: Bash `mkdir`/`cp` may fail in Claude Code sandbox sessions due to write restrictions. The Write file tool often bypasses those restrictions — prefer it over Bash for creating files in restricted directories.

## Workflow

- **[<TODAY>]** _Workflow_: Claude Code agents should never start long-running processes (dev servers, test watchers, build watchers) — always ask the user to run these in a separate terminal.
- **[<TODAY>]** _Workflow_: Run `git fetch --all` at the start of every session before creating branches or worktrees to avoid working from stale refs.
- **[<TODAY>]** _Workflow_: Before pushing any change, run the full quality gate locally (fmt check, linter, tests) — not just the step you touched. The pre-push hook enforces this, but run it yourself first so failures are found before the hook fires.
- **[<TODAY>]** _Workflow_: Keep PRs small and focused on a single concern. Large PRs are harder to review, harder to revert, and hide bugs in unrelated diffs.
- **[<TODAY>]** _Workflow_: Commit messages should describe the WHY, not the WHAT. The diff already shows what changed; the message should explain why the change was necessary.
- **[<TODAY>]** _Workflow_: README.md is a user-facing landing page — not a developer guide. It answers: what is this, why should I care, how does it work, how do I get started. Build commands, test commands, and setup steps belong in CONTRIBUTING.md.

## Claude Code

- **[<TODAY>]** _Claude Code_: Gather actual error output and logs before diagnosing a problem — don't assume a cause from symptoms. State hypotheses explicitly ("I think X might be causing Y") rather than compressing them into stated facts.
- **[<TODAY>]** _Claude Code_: Verify subagent outputs before reporting success. An agent's summary describes what it intended to do, not necessarily what it did — check the actual file changes or command output.
- **[<TODAY>]** _Claude Code_: Prefer specialized agents (rust-engineer, python-pro, frontend-developer, etc.) for language- and domain-specific work. They have narrower prompts and better defaults for their domain.
```

**Architecture addition** (append after the Claude Code section, all projects):

```markdown
## Architecture

- **[<TODAY>]** _Architecture_: Use structured tracing (`tracing` in Rust, OpenTelemetry-compatible libraries elsewhere) from day one. Adding spans retroactively is far more painful than instrumenting as you write the code.
- **[<TODAY>]** _Architecture_: Single Responsibility — a module/struct/class has one reason to change. Two reasons (e.g., "user persistence" and "user authorization") means two collaborators should split the work, not one monolith.
- **[<TODAY>]** _Architecture_: Open/Closed — extend behavior through new types or strategies, not by editing branches in the existing path. Adding a new payment provider should add a file, not add a `case` to a switch in five files.
- **[<TODAY>]** _Architecture_: Liskov Substitution — a subtype must accept everything its supertype accepts and produce nothing its supertype wouldn't. Violating this turns "polymorphism" into "if statement spread across types."
- **[<TODAY>]** _Architecture_: Interface Segregation — clients depend on the methods they actually use, not a kitchen-sink interface. A 20-method interface that callers use 3 of is 17 methods of false coupling.
- **[<TODAY>]** _Architecture_: Dependency Inversion — high-level policy depends on abstractions; low-level mechanism implements them. The abstraction lives with the policy (it captures what the policy needs), not with the mechanism (which would invert the dependency the wrong way).
- **[<TODAY>]** _Architecture_: Favor composition over inheritance even in OO languages. Inheritance ties two types together at compile time; composition lets you swap collaborators in tests, at runtime, or per environment.
- **[<TODAY>]** _Architecture_: Make illegal states unrepresentable. If a value can only be in one of three modes, model that as a sum type (enum / tagged union / sealed class) rather than three booleans, of which seven of the eight combinations are bugs waiting to happen.
- **[<TODAY>]** _Architecture_: Module boundaries follow change axes. Code that changes together belongs together; code that changes for different reasons belongs apart. Folders organized by technical layer (`controllers/`, `services/`, `models/`) often violate this — group by feature first, by layer second.
- **[<TODAY>]** _Architecture_: A module's public API is a contract; its internals are not. Mark internals as such (private modules / unexported names / `internal/` directory) and resist the pressure to widen the API surface for one-off needs.
- **[<TODAY>]** _Architecture_: Direction of dependency flows from outer (concrete: HTTP, DB, queue) to inner (abstract: domain logic). Domain code never imports adapter code; adapters import the ports the domain defines. This is what hexagonal / clean / onion architecture all boil down to.
- **[<TODAY>]** _Architecture_: Cross-cutting concerns (logging, metrics, auth) belong at the edge, not threaded through domain calls. The domain says what happened; middleware/decorators/aspects observe it.
- **[<TODAY>]** _Architecture_: When a third-party library leaks into a domain type, wrap it. Importing `mongodb::ObjectId` into your `User` struct couples your domain to that driver — when you migrate, every call site changes. A thin adapter type insulates you.
```

**Universal additions** (append after the Architecture section, all projects):

```markdown
## Testing

- **[<TODAY>]** _Testing_: Tests are non-negotiable — a feature without tests is incomplete. The question is not *whether* to test but *at what level*: pure logic gets unit tests, subsystem boundaries get integration tests, full user flows get end-to-end tests.
- **[<TODAY>]** _Testing_: Practice TDD on pure logic — Red (failing test that captures the requirement) → Green (smallest change that passes) → Refactor (improve structure with the test as a safety net). The cycle prevents over-engineering: code exists only to pass a stated test, not to satisfy an imagined future.
- **[<TODAY>]** _Testing_: TDD-produced tests are documentation of intended usage. Because the test is written before the implementation, it must show how a caller invokes the component — its shape, inputs, and outputs — making the test a worked example a reader can study to understand the design. This is especially valuable when discussing architectural decisions, because the tests demonstrate the interface in action rather than describing it abstractly.
- **[<TODAY>]** _Testing_: TDD applies cleanly to algorithmic and decision-logic code (parsers, business rules, state machines). For integration plumbing — code whose entire job is to wire HTTP handlers to a service or shuttle bytes between systems — exercise it via a small integration test that uses the real wire format, not unit tests with mocks of every collaborator.
- **[<TODAY>]** _Testing_: Default to the testing pyramid: many fast unit tests of pure logic, fewer integration tests of subsystem boundaries, fewest end-to-end tests of full user flows. Inverting the pyramid (mostly e2e) makes the suite slow, flaky, and expensive to debug.
- **[<TODAY>]** _Testing_: Use property-based testing (`proptest` in Rust, `fast-check` in TS, `hypothesis` in Python) for code with algebraic invariants — round-tripping serializers, idempotent operations, sort/parse/normalize functions. Hand-written cases miss adversarial inputs that generators surface in seconds.
- **[<TODAY>]** _Testing_: Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code. Mocking your own collaborators couples tests to implementation details and makes refactoring expensive.
- **[<TODAY>]** _Testing_: A flaky test is a broken test — quarantine or fix it the same day, never the same week. Flaky tests train the team to ignore CI failures, which lets a real failure slip through unnoticed.

## Documentation

- **[<TODAY>]** _Documentation_: Documentation is a first-class deliverable, not a chore. A feature that ships without docs is incomplete in the same way as one without tests — the code may run, but no one outside its author can use, review, or evolve it confidently.
- **[<TODAY>]** _Documentation_: Three audiences, three files: `README.md` (users — what is this and how do I run it), `docs/CONTRIBUTING.md` (developers — how do I work on it), `docs/ARCHITECTURE.md` (system designers — how is it built and why). Mixing audiences forces every reader through irrelevant content.
- **[<TODAY>]** _Documentation_: Write docs for the *next* developer (often you in six months), not for the current one. Explain *why* a decision was made, not just what was decided — the diff already shows the what.
- **[<TODAY>]** _Documentation_: Keep docs adjacent to the code they describe. Library-level docs in module headers (`//!` in Rust, `/** */` package docs in Java/TS); function-level docs on the function. Out-of-band docs drift; in-tree docs travel with the code.
- **[<TODAY>]** _Documentation_: Examples are the highest-density docs. A working example beats a paragraph of prose — copy-paste-ability is what real users need. Keep examples in `examples/` and run them in CI so they cannot rot silently.
- **[<TODAY>]** _Documentation_: Code comments explain *why* and *what for*, not *what*. The code already shows what it does; a comment that paraphrases the code adds noise. A comment that captures the constraint, the trade-off, or the reason for an apparent contradiction is gold.
- **[<TODAY>]** _Documentation_: Architecture decision records (ADRs / RFCs) are how you preserve the *why* across years. When you reverse a past decision, link the new RFC to the old one — the historical context is part of the explanation.

## Security

- **[<TODAY>]** _Security_: Never expose tokens, credentials, or secrets in committed code, in client-side bundles, or in logs. Pull secrets from a secret manager at runtime; redact known-secret keys from log output unconditionally.
- **[<TODAY>]** _Security_: Validate input at the boundary, then trust it inside. A request enters validation once (at the HTTP layer, message boundary, etc.) and emerges as a typed domain value — no defensive re-validation throughout the stack, no reaching back to "what was the raw string."
- **[<TODAY>]** _Security_: Run with the lowest privilege required. Service accounts get the narrowest IAM role; container processes run as non-root; database users get only the schemas they need. Privileges are a one-way ratchet — easy to grant, painful to revoke.
- **[<TODAY>]** _Security_: Pin and audit dependencies. Lockfiles (`Cargo.lock`, `bun.lockb`, `go.sum`, `uv.lock`) commit the exact versions you tested; an automated audit step (`cargo audit`, `bun audit`, `govulncheck`, `pip-audit`) catches CVEs in CI rather than in the wild.
- **[<TODAY>]** _Security_: Treat AuthN and AuthZ as separate concerns. Authentication answers "who is this"; authorization answers "may they do this". Conflating them is how systems end up with `if user.is_admin` checks scattered through business logic.

## Error Handling

- **[<TODAY>]** _Error Handling_: Distinguish recoverable errors (return them) from programmer errors (panic / abort). A failed network call is recoverable; a violated invariant inside your own code is not — recovering from it produces zombie state.
- **[<TODAY>]** _Error Handling_: Errors carry context. The error returned three layers up should tell the operator what the system was trying to do, what failed, and what input was involved — not just the leaf cause. `anyhow::Context`, error wrapping, `Error.cause`, all serve the same goal.
- **[<TODAY>]** _Error Handling_: Errors should be observable before they are user-visible. Structured logs and metrics catch the error trend (rising 500s, retry exhaustion) before the user reports the symptom.
- **[<TODAY>]** _Error Handling_: Retries belong at the edge of an idempotent operation. Wrapping a non-idempotent call in retry logic doubles the transactions and corrupts state. If the operation isn't idempotent, make it idempotent (request IDs, conditional updates) before retrying.
```

**Rust addition** (append after the Universal block):

```markdown
## Rust

- **[<TODAY>]** _Rust_: Do not manage the Rust toolchain with mise — use `rust-toolchain.toml` + rustup instead. mise has a cargo PATH conflict that breaks toolchain resolution.
- **[<TODAY>]** _Rust_: Use `thiserror` for error types in library crates, `anyhow` in binary/application crates. Mixing them forces consumers to unwrap opaque errors.
- **[<TODAY>]** _Rust_: `cargo check` is significantly faster than `cargo build` for iteration — use it to validate compilation without producing artifacts.
- **[<TODAY>]** _Rust_: Prefer `Result<T, E>` over `panic!` for any error a caller might reasonably handle. `panic!` is for broken invariants (programmer error); `Result` is for runtime conditions (network, IO, parse).
- **[<TODAY>]** _Rust_: Make illegal states unrepresentable with enums — model "loading | loaded(T) | failed(E)" as one enum with three variants, not three booleans plus an `Option<T>` and an `Option<E>`.
- **[<TODAY>]** _Rust_: Lifetimes flow with ownership; if elision struggles, the structure is wrong, not the annotations. Reach for `Arc`/`Rc` only when shared ownership is genuinely required, not as a borrow-checker escape hatch.
- **[<TODAY>]** _Rust_: Use `#[derive(Debug)]` on every public type. Debug output is what shows up in error messages and logs — types without it cripple operability.
- **[<TODAY>]** _Rust_: For async work, prefer `tokio` and instrument long-running futures with `tracing::Instrument` so spans propagate across `.await` points. Untraced async code is invisible in production.
- **[<TODAY>]** _Rust_: Run `cargo clippy --workspace -- -D warnings` and `cargo fmt --all --check` in CI. Clippy catches real bugs (`needless_collect`, `redundant_clone`); fmt removes the entire class of style PR comments.
- **[<TODAY>]** _Rust_: Use `cargo deny` (or `cargo audit`) in CI to flag advisories, banned licenses, and duplicate dependencies. Each is a security or supply-chain signal you want to see immediately.
```

**JS/TS addition** (append after the Universal block):

```markdown
## JavaScript / TypeScript

- **[<TODAY>]** _JS/TS_: Use `bun` as the JS/TS runtime and package manager — it replaces `node` + `npm`/`yarn`/`pnpm` with a single fast tool. Day-to-day commands: `bun install` for dependencies, `bun run <script>` for package scripts, `bun test` for tests, `bun <file.ts>` to execute TypeScript directly without a separate build step.
- **[<TODAY>]** _JS/TS_: Use `bun install --frozen-lockfile` in CI to catch accidental lockfile drift. Without this flag, bun silently updates the lockfile on install and masks dependency mismatches.
- **[<TODAY>]** _JS/TS_: Enable `"strict": true` in `tsconfig.json` from day one. Retrofitting strict TypeScript into a loose codebase is far more expensive than writing strict types up front.
- **[<TODAY>]** _JS/TS_: Treat `any` as a code smell, not an escape hatch. If the type genuinely is unknown at the boundary, use `unknown` and narrow it with a type guard — `unknown` forces the narrowing; `any` silently disables every check downstream.
- **[<TODAY>]** _JS/TS_: Validate external data at the boundary with a schema library (`zod`, `valibot`, `arktype`). The TypeScript type system has no presence at runtime; without runtime validation, your typed function will happily process malformed JSON until it crashes deep in the call stack.
- **[<TODAY>]** _JS/TS_: Prefer named exports over default exports. Default exports break tree-shaking heuristics, fight refactor tools (default symbols are renamed inconsistently across files), and lose the export name in the import statement.
- **[<TODAY>]** _JS/TS_: Use ESM (`import`/`export`) throughout the codebase, not a CommonJS/ESM mix. Mixing the two creates dual-package hazards and inconsistent module resolution.
- **[<TODAY>]** _JS/TS_: Configure path aliases in `tsconfig.json` (`@/foo`) and bundler config together. Using one without the other ships code that compiles but cannot resolve at runtime.
- **[<TODAY>]** _JS/TS_: Prefer `Date.now()` and explicit timezone handling (e.g., `Intl.DateTimeFormat`) over `new Date(string)` parsing. JavaScript date parsing is locale-dependent and silently wrong for ambiguous formats.
- **[<TODAY>]** _JS/TS_: Use `eslint` with `@typescript-eslint` rules and run it in CI. Pair it with `prettier` (formatting only — let eslint handle correctness rules).
```

**Python addition** (append after the Universal block):

```markdown
## Python

- **[<TODAY>]** _Python_: Add type annotations as you write code, not after. Retrofitting types into untyped Python is slow and often reveals design issues that are costly to fix late.
- **[<TODAY>]** _Python_: Use `uv` for dependency management (`mise.toml` pins the Python version; `uv sync` manages the venv). Mixing pip, venv, and pyenv leads to environment drift across machines.
```

**Go addition** (append after the Universal block):

```markdown
## Go

- **[<TODAY>]** _Go_: Handle every error explicitly — assigning to `_` is almost always a latent bug. If an error genuinely can't happen, document why with a comment rather than silently discarding it.
- **[<TODAY>]** _Go_: Run `go vet ./...` and `golangci-lint run` before pushing. `go vet` catches common correctness issues; `golangci-lint` catches style and performance issues that reviewers would flag.
- **[<TODAY>]** _Go_: Pass `context.Context` as the first argument to any function that does I/O, blocks, or might cancel. Goroutines without a context are zombies waiting to leak; once you forget the context at one layer, every layer above forgets it too.
- **[<TODAY>]** _Go_: Wrap errors with `fmt.Errorf("doing X: %w", err)` so callers can `errors.Is` / `errors.As` up the chain. Bare `return err` loses the call-site context that operators need to debug.
- **[<TODAY>]** _Go_: Prefer small interfaces defined where they are used (consumer-side), not where they are implemented. The standard library's `io.Reader` works because every consumer can declare its own narrow read-only need.
- **[<TODAY>]** _Go_: Avoid empty interfaces (`interface{}` / `any`) at API boundaries. They turn the type system off. If you need a sum type, use a sealed interface (unexported method) or a tagged struct.
- **[<TODAY>]** _Go_: Run goroutines with explicit lifetime control — `errgroup.Group`, `sync.WaitGroup`, or a context-cancelled worker pool. Naked `go func() { ... }()` calls are how production hangs and panics with no stack you can find.
- **[<TODAY>]** _Go_: Build for the linker — keep packages small and the dependency graph shallow. Cyclic imports are forbidden by the compiler; near-cyclic imports (A → B → C → A-via-interface) signal a missing third package.
- **[<TODAY>]** _Go_: Use table-driven tests for any function with multiple input shapes. The pattern (`for _, tc := range cases { t.Run(tc.name, ...) }`) makes adding a case a one-line change and surfaces coverage gaps visually.
```

**Svelte addition** (append after the Universal block, when Svelte is detected — heuristic: any `*.svelte` file or `svelte` in `package.json` dependencies):

```markdown
## Svelte

- **[<TODAY>]** _Svelte_: Use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`) for new components. Runes are explicit about reactivity boundaries; the legacy `let` + `$:` pattern works but obscures whether a value is reactive or not.
- **[<TODAY>]** _Svelte_: `$effect` is for side effects (DOM, network, timers), not for deriving values. If you find yourself writing `$effect(() => { derived = a + b })`, replace it with `let derived = $derived(a + b)` — the compiler builds a smaller, more correct dependency graph.
- **[<TODAY>]** _Svelte_: Co-locate component-scoped styles in `<style>` blocks; reach for global stylesheets only for tokens (color/spacing variables) and resets. Scoped styles let you delete a component without orphaning its CSS.
- **[<TODAY>]** _Svelte_: Use SvelteKit's load functions (`+page.ts`, `+page.server.ts`) for data fetching, not `onMount`. Load functions run during SSR, integrate with the router's loading state, and avoid the "blank page → flash of content" pattern.
- **[<TODAY>]** _Svelte_: Type `$props` explicitly with a `Props` interface. Untyped props lose autocomplete in consumers and silently accept misspelled prop names.
- **[<TODAY>]** _Svelte_: Prefer the `bind:` directive over manual two-way state plumbing for form inputs and component-shared state. Custom plumbing reinvents what `bind:value` already does and gets it wrong on edge cases (composition events, paste, etc.).
- **[<TODAY>]** _Svelte_: Server-only code goes in `+*.server.ts` files; never import server modules from client code. The bundler can usually catch this, but a server import inside a `$lib` shared module sneaks past — check both ends of every shared module.
```

**Ruby addition** (append after the Universal block, when Ruby is detected — heuristic: any `Gemfile`, `*.gemspec`, or `*.rb` source file):

```markdown
## Ruby

- **[<TODAY>]** _Ruby_: Pin Ruby version in `.ruby-version` and lock dependencies in `Gemfile.lock`; install via `mise` (or `rbenv` / `chruby`). Mixed Ruby installations across machines produce silent gem-load mismatches.
- **[<TODAY>]** _Ruby_: Run `bundle exec` for project commands (`bundle exec rake`, `bundle exec rspec`) — it pins binaries to the bundle. Direct `rspec` invocations pick up the system gem version and produce results that don't match CI.
- **[<TODAY>]** _Ruby_: Prefer keyword arguments over positional hashes for any method with more than two parameters. Keyword args are self-documenting at the call site and produce clear errors on missing/extra keys.
- **[<TODAY>]** _Ruby_: Treat `nil` checks as a smell. Ruby's null object pattern, `&.` (safe navigation), or `Array(maybe_nil_array)` produce more readable code than `if foo.nil? ...` ladders.
- **[<TODAY>]** _Ruby_: Run `rubocop` and `standard` (pick one) in CI. Both enforce style consistency that reviewers would otherwise spend energy on.
- **[<TODAY>]** _Ruby_: Use `rspec` or `minitest` consistently — don't mix. Each has its own conventions for fixtures, doubles, and matchers; mixing forces every contributor to context-switch between them.
- **[<TODAY>]** _Ruby_: Prefer immutable data classes (`Data.define`, structs frozen on creation) over mutable hashes for typed records. Mutability is the fastest path to spooky-action-at-a-distance bugs.
```

**Rails addition** (append after the Ruby section, when Rails is detected — heuristic: a `config/application.rb` file or `rails` in `Gemfile`):

```markdown
## Rails

- **[<TODAY>]** _Rails_: Fat controllers and fat models are both anti-patterns. Push business logic into plain Ruby objects (services, form objects, query objects) under `app/services/`, `app/queries/`, etc. The model owns persistence; the controller owns request/response shape; the rest is its own concern.
- **[<TODAY>]** _Rails_: Use strong parameters at the controller boundary, but parse them into a typed object (form object, dry-struct, ActiveModel) before passing to services. Services that take raw params couple to the HTTP shape.
- **[<TODAY>]** _Rails_: Database migrations are append-only history. Never edit a merged migration; add a new one. Rolling back in production is risky enough that you want an explicit reverse migration, not a silent "rerun this".
- **[<TODAY>]** _Rails_: Use `find_each` (or `in_batches`) for any query over more than a few hundred records. `User.all.each` loads the entire table into memory and OOMs the dyno on first real-world data.
- **[<TODAY>]** _Rails_: Wrap multi-record writes in `ActiveRecord::Base.transaction`. Without one, a partial failure (network blip on the second `INSERT`, validation error on the fifth row) leaves the database in a state nobody designed for.
- **[<TODAY>]** _Rails_: Background jobs are at-least-once by default — make them idempotent. The worker that received a job once will receive it twice when the queue retries; if the job mutates state without a unique-key guard, you've created duplicates.
- **[<TODAY>]** _Rails_: Use `bin/rails credentials:edit --environment <env>` for secrets in committed config; never commit secrets in plaintext. The Rails master key goes in your secret manager and into the deploy pipeline as an env var.
- **[<TODAY>]** _Rails_: Eager-load associations in any list view (`includes(:author, :tags)`). N+1 queries pass tests on three rows and crash on three thousand. Add `bullet` (or the `prosopite` gem) in development so they fail loudly during development.
- **[<TODAY>]** _Rails_: Prefer `where.missing(:association)` and Active Record query methods over raw SQL. When raw SQL is necessary, sanitize with bind parameters — never interpolate strings into a query.
```

**Kubernetes / CUE / kapply addition** (append after the Universal block, when k8s tooling is detected — heuristic: any `*.cue` file under `k8s/`, or `kapply` listed in CI / Dockerfile):

```markdown
## Kubernetes / CUE / kapply

- **[<TODAY>]** _K8s/CUE_: Render manifests with CUE, not Helm templating or YAML anchors. CUE constraints catch invalid shapes (missing `resources.limits`, malformed selectors) at build time; Helm catches them at apply time, sometimes after partial application has already happened.
- **[<TODAY>]** _K8s/CUE_: Pipeline shape is `cue export --out yaml -e resources ./k8s/clusters/<env> | kapply -n <env> -`. CUE produces the desired stream; kapply tracks the inventory and prunes anything that left the desired set. Never apply YAML directly with `kubectl apply` from a render — you lose the prune story.
- **[<TODAY>]** _kapply_: kapply tracks the applied set in a ConfigMap inventory and refuses to run on an empty input stream — that guard is what prevents an accidental "prune everything" when the render layer fails or emits nothing. Do not work around it; fix the render.
- **[<TODAY>]** _kapply_: kapply exit codes have meaning: `0` = no changes, `2` = changes applied successfully, `1` = error/conflict. Deploy scripts should treat both `0` and `2` as success and only fail on `1`.
- **[<TODAY>]** _kapply_: kapply uses server-side apply with `force-conflicts` and a per-distribution field manager. If two distributions try to manage the same field, kapply refuses to take over — fix ownership in CUE rather than working around the conflict.
- **[<TODAY>]** _K8s/CUE_: Pin the API version of every manifest (`apiVersion: apps/v1`, not the latest implicit). Cluster upgrades occasionally remove old API versions; pinning surfaces the migration as a CUE compile error rather than a silent runtime regression.
- **[<TODAY>]** _K8s_: Set `resources.requests` and `resources.limits` on every container. Without requests, the scheduler treats the pod as best-effort; without limits, a noisy neighbor can starve the node.
- **[<TODAY>]** _K8s_: Use `readinessProbe` and `livenessProbe` thoughtfully — readiness gates traffic, liveness restarts pods. A liveness probe that's too aggressive on a slow-starting service crashes a healthy pod; a readiness probe missing on a slow-starting service routes traffic to a not-ready container.
- **[<TODAY>]** _K8s_: Don't set `spec.replicas` on a Deployment that has an HPA — they fight. Either set replicas (no HPA) or set HPA bounds (no static replicas).
- **[<TODAY>]** _K8s_: Run with the lowest privilege necessary: drop all capabilities except those required, run as non-root, set `readOnlyRootFilesystem: true` where the workload allows. PodSecurityPolicy / Pod Security Admission catches the rest.
- **[<TODAY>]** _K8s_: Namespace everything. The default namespace is fine for one-off tools; production workloads belong in named namespaces so RBAC, NetworkPolicies, and resource quotas can be applied.
- **[<TODAY>]** _kapply_: Use `kapply verify` after a deploy to confirm every inventoried resource is still present and stamped. A passing deploy that subsequently drifts (manual edit, garbage collector reaping a parent) is invisible without the verify pass.
```

**Terraform / Terragrunt addition** (append after the Universal block, when Terraform is detected — heuristic: any `*.tf` file or `terragrunt.hcl`):

```markdown
## Terraform / Terragrunt

- **[<TODAY>]** _Terraform_: Pin provider versions in every module (`required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }`). An unpinned provider can change resource schema between plan and apply, producing destructive diffs nobody asked for.
- **[<TODAY>]** _Terraform_: Pin Terraform itself with `required_version = ">= 1.6.0, < 2.0.0"` in every module. Across-major upgrades deprecate behavior; pinning forces a deliberate upgrade path.
- **[<TODAY>]** _Terraform_: Remote state with locking is non-negotiable for any shared environment. S3 + DynamoDB or GCS + native locks. Local state is fine for a single-author personal stack and disastrous for a team.
- **[<TODAY>]** _Terraform_: Run `terraform plan` in CI on every PR and require the plan output as a review artifact. A merged PR whose plan was never inspected is a merge to production by-accident.
- **[<TODAY>]** _Terraform_: Treat `terraform apply` as a privileged operation. Apply happens through CI on a protected branch, never from a developer's laptop in a shared environment.
- **[<TODAY>]** _Terragrunt_: Use Terragrunt to orchestrate multiple Terraform modules with shared inputs. The DRY pattern (`terragrunt.hcl` per environment, generating provider/backend blocks) is what Terragrunt is for; treat the per-env files as configuration, not code.
- **[<TODAY>]** _Terragrunt_: Run `terragrunt run-all plan` from the root only when you genuinely need to plan everything. For day-to-day work, `cd` into the affected module and run `terragrunt plan` there — it's faster and the blast radius is one module.
- **[<TODAY>]** _Terraform_: Module inputs must be typed (`variable "x" { type = string }`). An untyped variable accepts anything and surfaces type errors deep in the resource block instead of at the boundary.
- **[<TODAY>]** _Terraform_: Don't use `null_resource` + `local-exec` to glue together what providers can do natively. Glue scripts have no dependency graph, no idempotency, and no rollback — they're the easiest way to make a deterministic system non-deterministic.
- **[<TODAY>]** _Terraform_: Tag every resource with a standard set (owner, environment, cost-center, managed-by-terraform=true). Tags are the only path from "what is this resource?" to an answer the cost-management and audit teams can use.
- **[<TODAY>]** _Terraform_: Run `tflint` and `tfsec` (or `checkov`) in CI. tflint catches style and provider-specific issues; tfsec/checkov catches security misconfigurations (public S3 buckets, unencrypted volumes) before they're applied.
- **[<TODAY>]** _Terraform_: Refactor with `moved` blocks, not `terraform state rm` + `terraform import`. `moved` is reversible, declarative, and reviewable; manual state surgery is none of those.
```

### `README.md`

The README is a **user-facing landing page**, not a developer guide. Its job is to answer: what is this, why should I care, how does it work, and how do I get started. Build commands and test commands belong in CONTRIBUTING.md, not here.

Create with the following template. Populate "Why" and "How It Works" from `docs/project-brief.md` if it exists (extract the value proposition and core concept); otherwise leave the placeholder comments.

```markdown
# <project_name>

> <description>

## Why <project_name>

<!-- What problem does this solve? Why would a user choose it over alternatives? 2–3 sentences. -->

## How It Works

<!-- Core concept in plain language — the mental model a new user needs. No code, no jargon. -->

## Getting Started

<project_name> is under active development — no pre-packaged binaries or installers yet. For now, build from source by following the [build instructions](docs/CONTRIBUTING.md#development-setup).

## Documentation

- [Contributing](docs/CONTRIBUTING.md) — dev setup, workflow, and conventions
- [Architecture](docs/ARCHITECTURE.md) — system design and key decisions
- [User Guide](docs/guide/) — detailed usage guides
- [RFC Process](docs/rfc-process.md) — how we propose and review changes

<!--
README audience: users — people who want to use or run this project.
Update this file when:
  - A real install method is available (replace the build-from-source notice)
  - The product's value proposition or top-level workflow changes
  - A new section is added to the Documentation list

Do NOT expand this into full documentation.
Detailed user docs go in docs/guide/.
Dev docs (workflow, architecture, learnings) go in docs/.
Build/test commands belong in CONTRIBUTING.md, not here.
-->
```

### `docs/CONTRIBUTING.md`

```markdown
<!--
CONTRIBUTING scope: everything a developer needs to work on this project.
  - Prerequisites or tool versions change
  - Setup steps change
  - Dev workflow or branching conventions change
  - Quality gate commands change
  - PR or RFC process changes

Not here: what the project does or its architecture → README.md / docs/ARCHITECTURE.md
-->

# Contributing

## Prerequisites

<PREREQUISITES_SECTION — list the language runtime, relevant CLI tools (cargo, bun, go, uv), and git>

## Development Setup

```bash
git clone <repo-url>
cd <project_slug>
<INSTALL_COMMAND>
```

## Development Workflow

All work happens on feature branches. Use the [git worktree](https://git-scm.com/docs/git-worktree) workflow for parallel tasks:

```bash
git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
# work here
```

See `CLAUDE.md` for agent delegation guidance.

## Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/) with a scope:

```
feat(scope): add new capability
fix(scope): correct wrong behavior
refactor(scope): restructure without changing behavior
docs(scope): update documentation
chore(scope): tooling, deps, config
```

## Quality Gate

The pre-push hook runs automatically before every `git push`:

<QUALITY_GATE_DESCRIPTION>

Fix any reported errors before pushing.

## Pull Request Process

1. Open a PR against `main`
2. CI must pass
3. One approval required for merge
4. Squash merge to keep history clean

## RFC Process

Significant changes (new features, architectural changes, breaking changes) go through the RFC process. See [docs/rfc-process.md](docs/rfc-process.md).
```

**Prerequisites section by language:**

| Language | Text |
|---|---|
| Rust | `- [Rust](https://rustup.rs/) stable (managed via \`rust-toolchain.toml\`)` |
| JS/TS | `- [Bun](https://bun.sh/) (version pinned in \`mise.toml\`; install with [mise](https://mise.jdx.dev/))` |
| Go | `- [Go](https://go.dev/) (version pinned in \`mise.toml\`; install with [mise](https://mise.jdx.dev/))` |
| Python | `- [Python](https://python.org/) (version pinned in \`mise.toml\`), [uv](https://github.com/astral-sh/uv)` |
| Shell/Infra | `- [mise](https://mise.jdx.dev/) for tool version management (see \`mise.toml\`)` |

**Install command by language** (prefix with `cd <component_root> &&` if not at repo root, or show as a separate step):

| Language | Command |
|---|---|
| Rust | `(no install step — cargo downloads deps on build)` |
| JS/TS | `bun install` |
| Go | `go mod download` |
| Python | `uv sync` |
| Shell/Infra | `mise install` |

For multi-language projects, list each non-trivial install step with its directory. Example for Rust + JS/TS frontend in `frontend/`:
```bash
# Frontend dependencies
cd frontend && bun install
```

**Quality gate description by language:**

| Language | Description |
|---|---|
| Rust | `` `cargo fmt --all --check`, `cargo clippy --workspace --locked -- -D warnings`, `cargo test --workspace --locked` `` |
| JS/TS | `` `bun run typecheck`, `bun run lint`, `bun test` `` |
| Go | `` `gofmt -l` (must be empty), `go vet ./...`, `go test ./...` `` |
| Python | `` `uv run ruff check .`, `uv run mypy .`, `uv run pytest` `` |
| Shell/Infra | `(no automated gate — review manually)` |

### `docs/ARCHITECTURE.md`

```markdown
# Architecture

<!--
ARCHITECTURE scope: system design reference — the "how and why it's built this way."
  - A component is added, renamed, or removed
  - A significant design decision is made or reversed (update the Decisions table)
  - Data flow between components changes
  - A new external dependency or service is introduced

Not here: setup/quickstart                   → README.md
          dev workflow, commit conventions   → docs/CONTRIBUTING.md
          non-obvious session learnings      → docs/BEST_PRACTICES.md
-->

## Overview

<One paragraph describing what the system does and how it is structured at the highest level.>

## Components

<For each major component or subsystem:>

### <Component Name>

**Purpose:** <what it does>
**Location:** `<path/>`
**Key interfaces:** <what it exposes or consumes>

## Data Flow

<Optional: describe how data moves through the system. A simple diagram or numbered steps works.>

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| <topic>  | <what was chosen> | <why, and what was rejected> |

## Dependencies

<External services, databases, or infrastructure the system depends on.>
```

### `.claude/settings.json`

Build the `enabledPlugins` object from the `installed` set detected in Step 1. Only include plugins that ARE installed — an uninstalled plugin in `enabledPlugins` causes Claude Code to error on startup.

Candidate plugins to include (if installed):
- `github@claude-plugins-official`
- `context7@claude-plugins-official`
- `code-review@claude-plugins-official`

For Rust projects, include a `PreToolUse` hook (pre-push quality gate). For other languages, include the analogous gate if the toolchain is standard.

Example for a Rust project with all plugins installed:

```json
{
  "enabledPlugins": {
    "github@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "code-review@claude-plugins-official": true
  },
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git commit*)",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__push_files",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__create_or_update_file",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git push*)",
            "command": "cargo fmt --all --check && cargo clippy --workspace --locked -- -D warnings && cargo test --workspace --locked || { printf '{\"continue\":false,\"stopReason\":\"Pre-push quality gate failed. Fix errors from cargo fmt --all --check, cargo clippy --workspace --locked -- -D warnings, and cargo test --workspace --locked before pushing.\"}'; exit 1; }",
            "timeout": 300,
            "statusMessage": "Running pre-push quality gate (fmt, clippy, test)..."
          }
        ]
      }
    ]
  }
}
```

**Pre-push quality gate:** Chain the gate commands for all detected languages with `&&`, skipping Shell/Infra (no standard gate). If no languages with a standard gate are detected, omit the `PreToolUse` hook entirely.

If `component_roots[language]` is not `.`, wrap that language's segment in a subshell: `(cd <path> && <commands>)`.

| Language | Gate command segment |
|---|---|
| Rust | `cargo fmt --all --check && cargo clippy --workspace --locked -- -D warnings && cargo test --workspace --locked` |
| JS/TS | `bun run typecheck && bun run lint && bun test` |
| Go | `gofmt -l . \| grep . && exit 1 \|\| true && go vet ./... && go test ./...` |
| Python | `uv run ruff check . && uv run mypy . && uv run pytest` |
| Shell/Infra | (omit — no standard gate) |

Example — Rust at root + JS/TS in `frontend/`:
```
cargo fmt --all --check && cargo clippy --workspace --locked -- -D warnings && cargo test --workspace --locked && (cd frontend && bun run typecheck && bun run lint && bun test)
```

Stop message: if Rust is the only language use the Rust-specific wording; otherwise use `"Pre-push quality gate failed. Fix the reported errors before pushing."`

### `.claude/settings.local.json`

Build from the base plus language additions. Exa permissions are always included (Exa is a separate MCP server; these permissions silently no-op if Exa isn't configured globally).

```json
{
  "permissions": {
    "allow": [
      "WebSearch",
      "WebFetch(domain:github.com)",
      "WebFetch(domain:docs.github.com)",
      "WebFetch(domain:raw.githubusercontent.com)",
      "mcp__plugin_github_github__list_pull_requests",
      "mcp__plugin_github_github__pull_request_read",
      "mcp__plugin_github_github__issue_read",
      "mcp__plugin_github_github__issue_write",
      "mcp__plugin_github_github__list_issues",
      "mcp__plugin_github_github__create_pull_request",
      "mcp__plugin_github_github__add_issue_comment",
      "mcp__plugin_github_github__search_issues",
      "mcp__exa__web_search_exa",
      "mcp__exa__crawling_exa",
      "Bash(git:*)",
      "mcp__firefox-devtools__list_pages",
      "mcp__firefox-devtools__new_page",
      "mcp__firefox-devtools__navigate_page",
      "mcp__firefox-devtools__screenshot_page",
      "mcp__firefox-devtools__take_snapshot",
      "mcp__firefox-devtools__click_by_uid",
      "mcp__firefox-devtools__fill_by_uid",
      "mcp__firefox-devtools__fill_form_by_uid",
      "mcp__firefox-devtools__list_console_messages",
      "mcp__firefox-devtools__evaluate_script"
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  }
}
```

**Append-only on re-runs:** if this file already exists, read it and add only the language entries that aren't already in the `allow` array. Never remove existing entries.

Add entries for every detected language (union of all):

| Language | Additional entries |
|---|---|
| Rust | `"WebFetch(domain:docs.rs)"`, `"WebFetch(domain:crates.io)"`, `"Bash(cargo:*)"`, `"Bash(rustc:*)"` |
| JS/TS | `"WebFetch(domain:registry.npmjs.org)"`, `"Bash(bun:*)"`, `"Bash(npm:*)"` |
| Go | `"WebFetch(domain:pkg.go.dev)"`, `"Bash(go:*)"` |
| Python | `"WebFetch(domain:pypi.org)"`, `"Bash(python:*)"`, `"Bash(uv:*)"` |
| Shell/Infra | `"WebFetch(domain:registry.terraform.io)"`, `"Bash(terragrunt:*)"`, `"Bash(kubectl:*)"`, `"Bash(helm:*)"` |

### Language tooling files

**If Rust is detected** — create `rust-toolchain.toml` (do NOT add Rust to mise — rustup manages it and mise has a cargo PATH conflict):
```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "rust-analyzer", "clippy"]
```

**If any non-Rust language is detected** — create (or extend) `mise.toml` with all non-Rust tools in a single file. Run `mise latest <tool>` to resolve the current stable version. Never write `"latest"` — always resolve to a concrete version string first.

A repo with Rust + JS/TS gets both `rust-toolchain.toml` **and** `mise.toml` (bun only).

**Append-only on re-runs:** if `mise.toml` already exists, add only the `[tools]` entries for newly detected languages. Never remove existing entries.

Tools by language (add only the tools for detected languages):

| Language | Tool(s) |
|---|---|
| JS/TS | `bun = "<version>"` |
| Go | `go = "<version>"` |
| Python | `python = "<version>"` |
| Shell/Infra | `terraform`, `kubectl`, `helm` (include only tools actually used) |

If `mise` is not available, write a reasonable current stable version as a placeholder and note in the Step 8 report that it should be pinned after `mise install`.

---

## Step 6 — GitHub artifacts (only if `has_github = yes`)

### GitHub repository metadata

If a GitHub remote is already configured, update the repository metadata to match the collected answers.

```bash
git remote get-url origin 2>/dev/null
```

If this returns a `github.com` URL, parse the owner and repo name from it and run:

```bash
# Update description (only if description is non-empty)
gh repo edit --description "<description>"
```

If the repo name on GitHub differs from `project_name` (GitHub repo names are typically kebab-case), note the discrepancy in the Step 8 report but do **not** rename the repo — renames break existing clones and links.

If `gh` is not available or the remote is not yet set up, note it in the Step 8 report and move on.

### `.github/workflows/ci.yml`

Assemble one file with a shared header and one job per detected language. If only one language is detected, name the job `ci`; otherwise name each job after the language (`rust`, `frontend`, `go`, `python`).

**Shared header (always):**
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
```

For each job: if `component_roots[language]` is not `.`, add `defaults: run: working-directory: <path>` at the job level.

**Rust job** (append under `jobs:` if Rust is detected):
```yaml
  rust:
    runs-on: ubuntu-latest
    # defaults: run: working-directory: <rust-root>  ← add if not repo root
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo check --workspace --locked
      - run: cargo clippy --workspace --locked -- -D warnings
      - run: cargo test --workspace --locked
      - run: cargo fmt --all --check
```

**JS/TS job** (append under `jobs:` if JS/TS is detected):
```yaml
  frontend:
    runs-on: ubuntu-latest
    # defaults: run: working-directory: <js-root>  ← add if not repo root
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run typecheck
      - run: bun run lint
      - run: bun run test
```

**Go job** (append under `jobs:` if Go is detected):
```yaml
  go:
    runs-on: ubuntu-latest
    # defaults: run: working-directory: <go-root>  ← add if not repo root
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - run: go vet ./...
      - run: go test ./...
      - run: gofmt -l . | grep . && exit 1 || true
```

**Python job** (append under `jobs:` if Python is detected):
```yaml
  python:
    runs-on: ubuntu-latest
    # defaults: run: working-directory: <python-root>  ← add if not repo root
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - run: uv sync
      - run: uv run ruff check .
      - run: uv run mypy .
      - run: uv run pytest
```

**Shell/Infra:** skip — no standard CI pattern.

### `.github/PULL_REQUEST_TEMPLATE.md`

No quality checklists — CI and the pre-push hook enforce those automatically. This is a writing guide for the agent that authors the PR body.

```markdown
## Summary

<!-- 1-3 sentences: what this PR does and why -->

Closes #

## Changes

-

## Testing

<!-- How was this tested? What scenarios or edge cases were covered? -->

## Notes for Reviewers

<!-- Trade-offs, open questions, or anything non-obvious about this approach -->
```

### `.github/ISSUE_TEMPLATE/story.md`

```markdown
---
name: Story
about: A new capability or feature
title: "[Story] "
labels: "type:feature, needs-triage"
---

## Capability

<!-- What can a user do after this is complete? Write as: "User can..." -->

## Why It Matters

<!-- What does this unlock? -->

## Acceptance Criteria

- [ ]
- [ ]

## Dependencies

- Blocked by: #
```

### `.github/ISSUE_TEMPLATE/bug.md`

```markdown
---
name: Bug
about: Something isn't working
title: "[Bug] "
labels: "type:bug, needs-triage"
---

## Steps to Reproduce

1.
2.

## Expected Behavior

## Actual Behavior

## Environment

<!-- Version, runtime, relevant configuration, or anything that affects reproduction -->
```

### `.github/ISSUE_TEMPLATE/spike.md`

```markdown
---
name: Spike
about: A time-boxed investigation
title: "[Spike] "
labels: "type:spike, needs-triage"
---

## Question to Answer

## Why Now

## Expected Output

- [ ] Findings doc
- [ ] Proof of concept
- [ ] Recommendation

## Related

- #
```

---

## Step 7 — Install RFC process

Run `/rfc-install`. This creates `docs/rfc-process.md`, `docs/rfcs/.gitkeep`, and copies the RFC skills into `.claude/skills/`.

---

## Step 8 — Report

Print a summary table of every file, showing the actual outcome:

| File | Action |
|------|--------|
| `.worktrees/` | created / already exists |
| `.gitignore` | created / appended |
| `CLAUDE.md` | created / **updated** (name/desc synced) / **skipped** (no change) |
| `docs/BEST_PRACTICES.md` | created (pre-populated) / **skipped** (exists) |
| `README.md` | created / **updated** (name/desc synced) / **skipped** (no change) |
| `docs/CONTRIBUTING.md` | created / **skipped** (exists) |
| `docs/ARCHITECTURE.md` | created / **skipped** (exists) |
| `docs/guide/` | created / already exists |
| `docs/project-brief.md` | created (template) / exists — used for name/description / **skipped** (not requested) |
| `.claude/settings.json` | created / **skipped** (exists) |
| `.claude/settings.local.json` | created / **skipped** (exists) |
| `rust-toolchain.toml` or `mise.toml` | created / **skipped** (exists) |
| `.github/workflows/ci.yml` | created / **skipped** (exists) — only if GitHub=yes |
| `.github/PULL_REQUEST_TEMPLATE.md` | created / **skipped** (exists) — only if GitHub=yes |
| `.github/ISSUE_TEMPLATE/*.md` | created / **skipped** (exists) — only if GitHub=yes |
| GitHub repo description | updated via `gh repo edit` / skipped (no remote or no description) — only if GitHub=yes |
| `docs/rfc-process.md` + RFC skills | via `/rfc-install` (skips if already installed) |

If any files were skipped, note them clearly so the user knows what was already in place.

If `missing` (from Step 1) is non-empty, print:
```
Missing plugins — not added to enabledPlugins:
  - <identifier>  →  install: /install <name>
```

For Exa (always), note:
```
Exa MCP — permissions pre-configured in settings.local.json.
If Exa is not yet set up globally, configure it as an MCP server in Claude Code settings.
```

Remind the user of follow-up tasks:
- Edit `CLAUDE.md` to fill in the actual file structure once source code is added
- Fill in `docs/ARCHITECTURE.md` once the system design is settled
- Run `/best-practices-extract` at the end of meaningful sessions
