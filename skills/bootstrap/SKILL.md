---
name: bootstrap
description: Set up a new (or nearly-empty) project repository with standard conventions — .worktrees/, .gitignore, CLAUDE.md, README.md, docs/BEST_PRACTICES.md, docs/CONTRIBUTING.md, docs/ARCHITECTURE.md, docs/guide/, optional docs/project-brief.md, .claude/settings.json, .claude/settings.local.json, language tooling, GitHub CI/PR/issue templates, and RFC process. Triggered by "/bootstrap".
---

# Bootstrap

Sets up a new project repository with all standard conventions.

## Interaction model

Bootstrap runs almost entirely autonomously. There are exactly **two points** where user input is collected:

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

If the repo already has substantial committed content (more than a LICENSE/README), note: "This repo already has content — bootstrap will skip any files that already exist and only create the ones that are missing."

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
- Option 1: `Help me create one` — bootstrap will ask you 4 questions after setup and fill in `docs/project-brief.md`
- Option 2: `I've added the file to docs/project-brief.md` — bootstrap reads it and uses it to pre-populate name and description
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

**Languages are not asked** — they are detected automatically in Step 3 by scanning manifest files. Bootstrap is idempotent: re-run it after adding source code to pick up new languages and fill in any missing language-specific files.

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
```

**Build `component_roots`** — a list of `{ language, path, name }` entries:

- **Rust**: If root `Cargo.toml` contains `[workspace]`, read its `members` array — each member is a component. If it's a standalone crate, the component is `.`. If no `Cargo.toml` exists, default to `.`.
- **JS/TS**: Each directory containing a `package.json` is a component. Use the `name` field from the JSON as the component name, falling back to the directory name.
- **Go**: Each directory containing a `go.mod` is a module/component.
- **Python**: Each directory containing `pyproject.toml` or `setup.py` is a component.
- **If nothing is found for a language**: default to a single component at `.`.

Since bootstrap is idempotent, re-running it after adding new components will detect them and fill in any missing config.

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

Create with the base content below, substituting `<TODAY>` with today's date in `YYYY-MM-DD` format. Then append every language-specific section that applies (a mixed project like Rust + JS frontend gets both).

**Base content (all projects):**

```markdown
# Best Practices

Accumulated non-obvious learnings from development sessions.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).

Use `/extract-best-practices` at the end of a session to add new entries.

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

- **[<TODAY>]** _Architecture_: Instrument every component with structured tracing from day one — `tracing` + `tracing-subscriber` (Rust), OpenTelemetry SDK (JS/TS, Go, Python). Binaries initialize with an env-filter (`RUST_LOG`, `OTEL_LOG_LEVEL`) so log verbosity is controlled at runtime without recompilation. Functions that perform I/O or cross a subsystem boundary get a span (`#[instrument]`, `trace.startActiveSpan`). Never use `println!` / `console.log` for diagnostic output in production code.
```

**Rust addition** (append after the Architecture section):

```markdown
## Rust

- **[<TODAY>]** _Rust_: Do not manage the Rust toolchain with mise — use `rust-toolchain.toml` + rustup instead. mise has a cargo PATH conflict that breaks toolchain resolution.
- **[<TODAY>]** _Rust_: Use `thiserror` for error types in library crates, `anyhow` in binary/application crates. Mixing them forces consumers to unwrap opaque errors.
- **[<TODAY>]** _Rust_: `cargo check` is significantly faster than `cargo build` for iteration — use it to validate compilation without producing artifacts.
```

**JS/TS addition** (append after the Claude Code section):

```markdown
## JavaScript / TypeScript

- **[<TODAY>]** _JS/TS_: Use `bun install --frozen-lockfile` in CI to catch accidental lockfile drift. Without this flag, bun silently updates the lockfile on install and masks dependency mismatches.
- **[<TODAY>]** _JS/TS_: Enable `"strict": true` in `tsconfig.json` from day one. Retrofitting strict TypeScript into a loose codebase is far more expensive than writing strict types up front.
```

**Python addition** (append after the Claude Code section):

```markdown
## Python

- **[<TODAY>]** _Python_: Add type annotations as you write code, not after. Retrofitting types into untyped Python is slow and often reveals design issues that are costly to fix late.
- **[<TODAY>]** _Python_: Use `uv` for dependency management (`mise.toml` pins the Python version; `uv sync` manages the venv). Mixing pip, venv, and pyenv leads to environment drift across machines.
```

**Go addition** (append after the Claude Code section):

```markdown
## Go

- **[<TODAY>]** _Go_: Handle every error explicitly — assigning to `_` is almost always a latent bug. If an error genuinely can't happen, document why with a comment rather than silently discarding it.
- **[<TODAY>]** _Go_: Run `go vet ./...` and `golangci-lint run` before pushing. `go vet` catches common correctness issues; `golangci-lint` catches style and performance issues that reviewers would flag.
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
            "command": "echo 'PreCompact: context is about to be compacted — run /extract-best-practices now to preserve non-obvious learnings before they are lost.'"
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
            "command": "echo 'Session ending: (1) /extract-best-practices — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
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
- Run `/extract-best-practices` at the end of meaningful sessions
