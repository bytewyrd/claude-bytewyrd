---
name: sync
description: Set up or refresh a project repository with all standard conventions — idempotent, safe to re-run whenever the plugin updates. Triggered by "/sync".
---

<!-- bootstrap-content-version: 2026-05-12-b9f3e2a -->

# Sync

Sets up or refreshes a project repository with all standard conventions. Idempotent — re-running computes a three-way diff for every plugin-managed artifact and presents a categorized summary (additions, fast-forward updates, conflicts, local-only edits, unchanged) before writing anything.

## Interaction model

Sync collects user input at two points:

1. **Steps 2a–2c (project identity)** — Only when `docs/project-brief.md` is absent or incomplete. Same as before: one AskUserQuestion for gaps in name/description, optional body-fill, brief creation.
2. **Step 4a (batch confirmation)** — One AskUserQuestion with up to two questions (one for additions, one for fast-forward updates). Omitted entirely when there are no additions or fast-forward updates.
3. **Step 4b (per-conflict resolution)** — One AskUserQuestion per conflict. Run sequentially, one at a time.

When `docs/project-brief.md` already exists with complete identity *and* all plugin-managed files are already at the current plugin version, both Steps 4a and 4b are skipped — `/sync` reports everything as unchanged and exits without prompting.

## Step 1 — Validate environment + detect installed plugins + detect GitHub remote

Run:
```bash
git rev-parse --show-toplevel
git config user.name
```

If either fails, stop with a clear error message.

**Additional pre-flight checks required for diff computation:**

```bash
# Required for /sync diff computation
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "/sync requires sha256sum or shasum for diff computation. Install with: brew install coreutils (macOS) or apt install coreutils (Debian/Ubuntu)" >&2; exit 1; }
command -v jq >/dev/null || { echo "/sync requires jq for diff computation. Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "/sync requires python3 for TOML parsing. Install with: brew install python3 (macOS) or apt install python3 (Debian/Ubuntu)" >&2; exit 1; }
```

If any required tool is missing, stop with the error message shown above naming the missing tool and the one-line install hint.

**Write target:** all files created or modified by sync go to the directory returned by `git rev-parse --show-toplevel`. This is always the correct target — whether you're in a standard checkout or a worktree. **Never** run `git rev-parse --git-common-dir` or otherwise detect the "main" repo root and redirect writes there. If sync is invoked from a worktree, the worktree is the intended working context; changes land on a branch and flow through a PR — that is the desired workflow.

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

The `bytewyrd@bytewyrd` plugin is NOT in this table and NOT written to project settings — it is installed once per machine at user scope. The plugin's `SessionStart` hook validates companion plugins and MCP servers for users who have it installed; new collaborators who don't have it are directed to install via the CONTRIBUTING.md hint `/sync` adds to every consumer project.

Note: Exa is a separate MCP server (not a plugin) — its permissions go unconditionally in `settings.local.json`.

Store:
- `installed`: set of installed plugin identifiers
- `missing`: recommended plugins not in `installed`

If `github@claude-plugins-official` is missing from `installed`, warn but do not stop.

---

## Step 1.5 — Detect docs-agent version drift

Read the plugin's `docs-agent-version` marker from `$CLAUDE_PLUGIN_ROOT/agents/docs-agent.md`:

```bash
PLUGIN_DOCS_VER=$(grep -m1 'docs-agent-version:' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/agents/docs-agent.md" 2>/dev/null | sed -E 's/.*docs-agent-version: ([^ ]+).*/\1/')
```

Read the project's recorded marker from `.bytewyrd/docs-agent-version`:

```bash
PROJECT_DOCS_VER=$(cat .bytewyrd/docs-agent-version 2>/dev/null || echo "")
```

If `PLUGIN_DOCS_VER` is non-empty and differs from `PROJECT_DOCS_VER` (including the case where `PROJECT_DOCS_VER` is empty because the file does not exist yet), print this suggestion to the agent's output:

```
The plugin's docs-agent has improved (project=<PROJECT_DOCS_VER>, plugin=<PLUGIN_DOCS_VER>). Consider running /docs-review against docs/guide/** to re-audit user-facing documentation with the updated checks.
```

Then record the new version so subsequent sync runs do not re-prompt until the marker changes again. Only write the marker if `PLUGIN_DOCS_VER` is non-empty (guard with `[ -n "$PLUGIN_DOCS_VER" ]`) to prevent overwriting a valid marker with an empty string when the plugin's agent file is unreachable.

```bash
mkdir -p .bytewyrd
echo "$PLUGIN_DOCS_VER" > .bytewyrd/docs-agent-version
```

Do **not** auto-invoke `/docs-review` — `/sync` only prints the suggestion. The decision to run the review belongs to the main agent or the user.

If `PLUGIN_DOCS_VER` is empty (the plugin's `agents/docs-agent.md` does not yet exist or does not carry the marker), skip this step silently — the plugin may be on a version that predates this feature.

---

## Step 2 — Gather project identity from the brief

Project identity (`project_name` and `description`) is sourced from `docs/project-brief.md`. The brief is the single source of truth — `/sync` does not maintain identity values independently of it.

`"Other"` is a special label in the Claude Code UI — it renders as a text input field rather than a plain button. Do not add any label like "Type below" or "Enter custom"; the text field is self-explanatory.

### 2a — Read existing brief, if any

If `docs/project-brief.md` exists, parse it (parser rules are documented in the RFC `2026-05-10-project-brief-sync-source-of-truth`). The parse yields these outputs:

- `brief_name` — string from the H1 (regex `/^#\s+(.+?)\s*$/m`), or `None` if no H1 is present
- `brief_description` — string from the first non-blank paragraph of the `## Description` section, or `None` if the section is absent or its body is empty after trimming
- `brief_problem`, `brief_goals`, `brief_nongoals`, `brief_constraints` — body of each named section, plus a `<section>_is_placeholder` flag set to `true` when the section is absent, empty after trimming, or its body (after trimming) is exactly one of these recognized placeholder strings: the literal `<...>`, `—`, `TBD`, or `TODO` (case-insensitive). Any other content — including a single real sentence — is treated as non-placeholder.

Resolve `project_name`:
1. If `brief_name` is non-`None` and non-empty AND not equal to `"Project Brief"` (case-insensitive — the literal placeholder from older brief templates) → `project_name = brief_name`.
2. Else → set `project_name_missing = true` (will be filled by the identity gap-fill prompt below). Also set `needs_migration = true` (the brief exists but has the placeholder H1 or no H1 at all, so the H1 line will be rewritten by Change 3).

Resolve `description`:
1. If `brief_description` is non-`None` and non-empty → `description = brief_description`.
2. Else → set `description_missing = true` (will be filled by the identity gap-fill prompt below). Also set `needs_migration = true` (the brief exists but lacks a usable `## Description` section, so the section will be inserted/replaced by Change 3).

#### 2a.i — Identity gap-fill (only if name or description is missing)

If `project_name_missing` is set OR `description_missing` is set, ask one AskUserQuestion to fill the gaps:

- If only `project_name_missing`: include question 1 only.
- If only `description_missing`: include question 2 only.
- If both: include both questions in one call.

**Question 1 — "Project name (display)?"**: suggestion is `Title Case(project_slug)`; the auto-rendered `Other` is a free-text input. Falls back to the suggestion if `Other` is empty.

**Question 2 — "One-sentence description?"**: if `github_description` from Step 1 is non-empty, it is the suggestion; otherwise the suggestion is a slug-derived placeholder like `<project_slug> — <one-line outcome>.`. The auto-rendered `Other` is a free-text input. Falls back to the suggestion if `Other` is empty. (There is no "skip" option — every project has *some* description, even if generic. If the user wants no real description, they can type `—` or any placeholder.)

After answering, set `project_name` and `description` from the answers. The collected values are folded into `docs/project-brief.md` by Change 3's migration sub-rule.

#### 2a.ii — Optional body-fill for the four narrative sections

After the identity gap-fill (or directly, if no identity gap-fill was needed because both `project_name` and `description` were already resolved from the brief), inspect the four narrative sections. Compute `body_has_placeholders = brief_problem_is_placeholder OR brief_goals_is_placeholder OR brief_nongoals_is_placeholder OR brief_constraints_is_placeholder`.

If `body_has_placeholders = false` (every narrative section already has real, non-placeholder content), skip this sub-step entirely — no prompt, no rewrite. Proceed to Step 3.

If `body_has_placeholders = true`, ask one AskUserQuestion with a single yes/no question:

**"Some narrative sections of `docs/project-brief.md` are empty or contain placeholders. Fill them in now?"**

- Option 1: `Yes — walk me through the empty sections` — sets `fill_body = true`
- Option 2: `Skip — I'll edit the brief manually later` — sets `fill_body = false`

If `fill_body = false`, proceed to Step 3 with the body sections untouched. The migration sub-rule of Change 3 will not rewrite any narrative section; only the H1 and `## Description` section are rewritten if `needs_migration = true`.

If `fill_body = true`, ask one AskUserQuestion containing exactly one question per *placeholder-looking* narrative section (1 to 4 questions in a single call — sections that already have real content are not re-prompted):

1. **"Problem — what does this solve, and who is it for?"** — included only if `brief_problem_is_placeholder`. Suggestion inferred from the project slug and any detected language (e.g. for a Rust binary the suggestion might be `"<project_slug> — utility for <inferred-context>; for <inferred-audience>."`)
2. **"Goals — what does success look like?"** — included only if `brief_goals_is_placeholder`. Suggestion: a generic `"<project_slug> ships a <one-line-outcome> that <verb> for its users."` template adapted from the slug.
3. **"Non-goals — what is explicitly out of scope?"** — included only if `brief_nongoals_is_placeholder`. Suggestion: a generic `"Not a general-purpose <category> for arbitrary use; opinionated toward <inferred-stack>."` template adapted from the slug.
4. **"Constraints — technical, operational, or philosophical?"** — included only if `brief_constraints_is_placeholder`. Suggestion: a generic `"Must work within the user's standard <inferred-runtime> environment."` template adapted from the slug.

For every question included: each gets one suggestion option plus an auto-rendered `Other` free-text input. If the user submits an empty `Other` value for any question, fall back to that question's suggestion. None of the included questions can be skipped to empty.

Store the answers as `answer_problem`, `answer_goals`, `answer_nongoals`, `answer_constraints` — only for the sections that were actually asked. Sections that were not asked (because they already had real content) keep their existing body. Set `body_fill_applied = true` so Change 3's migration sub-rule knows to write the body sections.

### 2b — If brief is absent, decide whether to create one

If `docs/project-brief.md` does not exist, ask one AskUserQuestion:

**"Do you want to create a project brief now?"** The brief is the canonical source of project identity (name, description) and scope (problem, goals, non-goals, constraints). Without it, `/sync` will use derived defaults (Title-Case of the directory name for the project name; a slug-derived placeholder description) and will re-ask on every run.

- Option 1: `Yes — let's set it up now (single prompt, 6 questions)` — sets `create_brief = true`
- Option 2: `Skip — I'll create it later by re-running /sync` — sets `create_brief = false`

If `create_brief = false`, set `project_name = Title Case(project_slug)` and `description = ""`, then proceed directly to Step 3. The brief is not created; subsequent `/sync` runs will re-ask this question.

If `create_brief = true`, proceed to Step 2c.

### 2c — First-run unified prompt (only when brief is being created)

This step runs only when `create_brief = true`. It is a single AskUserQuestion containing six questions in one call.

Each question gets one suggestion option plus an auto-rendered `Other` free-text input. The user can either accept the pre-fill or type a custom answer:

1. **"Project name (display)?"** — suggestion: `Title Case(project_slug)` (e.g. `tinywyrd` → `Tinywyrd`)
2. **"One-sentence description?"** — suggestion: if `github_description` from Step 1 is non-empty, that string; otherwise a slug-derived placeholder like `<project_slug> — <one-line outcome>.`
3. **"Problem — what does this solve, and who is it for?"** — suggestion inferred from the project slug and any detected language (e.g. for a Rust binary the suggestion might be `"<project_slug> — utility for <inferred-context>; for <inferred-audience>."`)
4. **"Goals — what does success look like?"** — suggestion: a generic `"<project_slug> ships a <one-line-outcome> that <verb> for its users."` template adapted from the slug
5. **"Non-goals — what is explicitly out of scope?"** — suggestion: a generic `"Not a general-purpose <category> for arbitrary use; opinionated toward <inferred-stack>."` template adapted from the slug
6. **"Constraints — technical, operational, or philosophical?"** — suggestion: a generic `"Must work within the user's standard <inferred-runtime> environment."` template adapted from the slug

For every question (1 through 6): if the user submits an empty `Other` value, fall back to the suggestion. None of the six can be skipped to empty.

Store the answers as `answer_name`, `answer_description`, `answer_problem`, `answer_goals`, `answer_nongoals`, `answer_constraints`. Then:

- `project_name = answer_name`
- `description = answer_description`
- `brief_problem = answer_problem`, `brief_goals = answer_goals`, `brief_nongoals = answer_nongoals`, `brief_constraints = answer_constraints`

The brief file is written in Step 5 — not here — so that `/sync` writes all files in one block.

`has_github` is derived from Step 1 (`true` if a `github.com` remote was detected) and never asked.

`project_slug` is derived from Step 1 (`basename $(git rev-parse --show-toplevel)`) and never asked.

**Languages are not asked** — they are detected automatically in Step 3.

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

## Step 4 — Compute diff and present summary

This step replaces the former "Print creation summary." It runs the pre-flight diff procedure against the bootstrap manifest, classifies each artifact, and presents a categorized summary before any files are written.

### Pre-flight diff procedure

Determine the plugin root:

```bash
echo "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}"
```

Use the printed path as `PLUGIN_ROOT`. Read the manifest at `$PLUGIN_ROOT/.claude-plugin/bootstrap-manifest.json`. Also read the sidecar at `.claude/.bootstrap-versions.json` (treat as `{}` if absent).

**Cross-platform SHA-256:**

```bash
# Prefer sha256sum (Linux); fall back to shasum -a 256 (macOS).
if command -v sha256sum >/dev/null; then
  hash_cmd="sha256sum"
else
  hash_cmd="shasum -a 256"
fi
# Usage: echo "content" | $hash_cmd | cut -c1-12  → first 12 hex chars
```

For each artifact in the manifest (skipping the `.bootstrap-versions.json` sidecar entry itself):

1. **Compute `plugin_current_canonical_sha`** — render the template with `project_inputs` (for templated artifacts) or read the plugin source (for non-templated). Canonicalize the result per the artifact's `extension_strategy` (see Canonicalization rules below). Compute SHA-256, take first 12 hex chars.

2. **If the target file is absent** → classify as **`add`**.

3. **If the target file exists:**
   - For Markdown/TOML/gitignore/YAML files: extract `local_ancestor_sha` from the embedded marker line (the `<!-- bootstrap-content-version: <key>:<sha-12> -->` comment on line 2, or the `# bootstrap-content-version: <key>:<sha-12>` comment on line 1 for TOML/gitignore/YAML).
   - For JSON files (`.claude/settings.json`, `.claude/settings.local.json`): look up `local_ancestor_sha` from the sidecar by `upstream_key`.
   - If no marker/sidecar entry exists: `local_ancestor_sha = None` (legacy file).
   - Canonicalize the local file content → `local_current_canonical_sha` (first 12 hex chars).

4. **Classify** per the matrix:

| Conditions | Classification |
|------------|----------------|
| Target file absent | **add** |
| No marker, `local_current == plugin_current` | **unchanged_legacy** |
| No marker, `local_current != plugin_current` | **conflict_legacy** |
| Marker present, `local_ancestor == plugin_current` | **unchanged** |
| Marker present, `local_current == local_ancestor` AND `plugin_current != local_ancestor` | **fast_forward** |
| Marker present, `local_current != local_ancestor` AND `plugin_current == local_ancestor` | **local_only** |
| Marker present, all three differ AND `local_current != plugin_current` | **conflict** |
| Marker present, all three differ AND `local_current == plugin_current` | **unchanged** (converged) |

**Canonicalization rules** (same function applied to both local and plugin content — hashes must be directly comparable):

- **`whole` strategy:** full file content with the marker line(s) removed (the embedded comment line and any immediately following blank line).
- **`region` strategy:** file content from line 1 up to and including `region_end_marker`, with the marker line(s) removed. The project-extension region after the marker is excluded entirely.
- **`section` strategy:** extract each heading in `owned_sections` (manifest order). For each: the literal heading line + `\n` + section body (all lines from heading to next H2 or EOF, trimmed of leading/trailing blank lines) + `\n`. Concatenate all owned sections. Sections absent from the file contribute heading + `\n` with empty body.
- **`structured` strategy (JSON):** for each path in `owned_paths`, extract the value using `jq` (sort keys) and serialize it; concatenate. For id-based array paths (`[]:<id_key>`): serialize only entries with a non-empty id, sorted by id. For set-union array paths (`[]:union`): serialize only the plugin-contributed entries.
- **`structured` strategy (`.gitignore`):** for each tagged block in `owned_paths`, extract the `# <tag>\n` line + lines in the block + `\n`; concatenate.

### Print the summary

After classifying all artifacts, print a categorized summary:

```
/sync — change summary:

Additions (N new files):
  + <path>
  + <path>

Fast-forward updates (N files, no local edits):
  ~ <path>  (plugin: <brief description of change>)

Legacy marker injection (N files, content matches — adding version marker only):
  + <path>  (first sync after upgrade — no content change)

Conflicts (N files, local edits collide with plugin update):
  ! <path>  (<conflict scope description>)

Local-only edits (N files, plugin unchanged): <path>, <path>

Unchanged (N files): (collapsed)
```

If any category is empty, omit it entirely. If there are no changes at all, print "Everything is up to date." and skip Steps 4a and 4b.

If this is the first run after upgrading to a plugin version that ships per-file markers (i.e., any `unchanged_legacy` or `conflict_legacy` entries exist), prepend a one-time banner:

```
This is the first /sync run after an upgrade that adds per-file content tracking.
Existing plugin-managed files have been classified by comparing local content
against the plugin's current shipped content. Files that match exactly were
silently marked. Files that differ are listed under "Conflicts (legacy)" — pick
"Adopt plugin and add marker" for any file you have not intentionally edited.
Future runs will only flag files that genuinely diverged.
```

### Step 4a — Batch confirmation for additions and fast-forwards

Ask one AskUserQuestion. The question set depends on which categories have items:

- If `additions` or `unchanged_legacy` is non-empty: include Question 1 — "Apply N additions (+ N legacy marker insertions)?" with options:
  - `Yes, apply all`
  - `Review each` (drops into per-file prompts)
  - `Skip all`
- If `fast_forwards` is non-empty: include Question 2 — "Apply N fast-forward updates? (no local edits will be lost)" with the same three options.

The two questions are sent in a single AskUserQuestion call. If neither category has items, skip Step 4a entirely.

`unchanged_legacy` entries are included in the additions question because they require a file write (marker insertion) but no content change — the user should see them but does not need per-file confirmation.

`Review each` mode: for each file in the category, ask one AskUserQuestion with "Apply update to `<path>`?" and options `Apply` / `Skip`. Print the first 40 lines of the unified diff between local and plugin-rendered content immediately before the question.

### Step 4b — Per-conflict resolution

For each conflict in the `conflict` (and `conflict_legacy`) list, run sequentially. Before each question, print:

- The file path and the conflict scope (e.g., "conflict in `## Tool Usage` section of `CLAUDE.md`" for `section` strategy; "conflict in upstream region of `docs/rfc-process.md`" for `region` strategy).
- A compact unified diff (first 40 lines) of local content vs plugin content restricted to the affected owned region/section/path.
- For `conflict_legacy` only: a note that this file pre-dates per-file markers, so the diff is between local content and the plugin's current content — not a true 3-way merge.

Then ask one AskUserQuestion:

**"How to resolve conflict in `<path>`?"** with options:

- `Adopt plugin version (replace local edits in the owned region)`
- `Keep local version (skip this update; will re-surface on next /sync)`
- `Merge into local manually (write scratch files, then re-run /sync)`
- `Skip for now (revisit later)`

For `conflict_legacy` only, add a fifth option:

- `Adopt plugin and add marker (recommended if you haven't customized this file)`

**Actions:**

- `Adopt plugin version` → write plugin content merged per the artifact's `extension_strategy` (owned regions/sections/paths replaced; user-owned regions preserved). Update the marker.
- `Keep local version` → no write; marker not updated; conflict re-surfaces on next run.
- `Merge into local manually` → write plugin content to `.claude/sync-conflict-<sanitized-path>.txt` and local content to `.claude/sync-local-<sanitized-path>.txt`. Print: "Wrote scratch files for manual merge. Re-run `/sync` after merging." Do not write the target file.
- `Skip for now` → identical to `Keep local version` but recorded separately in the Step 8 report.
- `Adopt plugin and add marker` (legacy only) → write plugin content and set the marker to the plugin's current sha.

---

## Step 5 — Apply changes

This step applies the actions determined by Steps 4a and 4b. For each artifact in the diff result, apply its action. Templates are read from `$PLUGIN_ROOT/.claude-plugin/scripts/templates/`. Non-templated artifact sources are read from the `source` field in the manifest (resolved relative to `$PLUGIN_ROOT`).

**Template rendering rule:** read the template source file as a string; for each `<placeholder>` token, substitute the corresponding value from `project_inputs`. Unrecognized placeholders are replaced with empty string. For conditional regions (`<!--lang:rust-start-->...<!--lang:rust-end-->` etc.), include the block content (without the delimiter comments) when the corresponding language is detected; otherwise strip the entire block including delimiters. All delimiter comment lines are stripped from the rendered output.

**Marker insertion rule:** after rendering content for a new or updated file, insert the `bootstrap-content-version` marker. Compute `sha12 = first 12 hex chars of SHA-256(canonicalize(rendered_content, artifact))`. Insert per file type:
- Markdown (`.md`): insert `<!-- bootstrap-content-version: <upstream_key>:<sha12> -->` as line 2 (after the first line of the file).
- TOML (`.toml`): insert `# bootstrap-content-version: <upstream_key>:<sha12>` as line 1, followed by a blank line, then the file content.
- YAML (`.yml`, `.yaml`): insert `# bootstrap-content-version: <upstream_key>:<sha12>` as line 1, followed by a blank line.
- `.gitignore`: insert `# bootstrap-content-version: <upstream_key>:<sha12>` as line 1, followed by a blank line.
- JSON files: do **not** embed a marker in the file. The marker is stored in the sidecar (Step 5.5).

**Apply actions:**

1. **`add`** — Render the template with `project_inputs`. Insert the marker. Write the file. Track as `added`.

2. **`fast_forward`** (approved in Step 4a) — Render the template or read the plugin source. Apply the extension strategy to merge against the local file:
   - `whole`: replace the full file with plugin content (marker updated).
   - `region`: replace the upstream region (everything up to and including `region_end_marker`) with the plugin's rendered upstream region; preserve the project-extension region (everything after `region_end_marker`) byte-for-byte.
   - `section`: for each heading in `owned_sections`, replace the section body in the local file with the plugin's rendered body for that section. Preserve all other sections (user-owned sections, sections the plugin doesn't own). If a plugin-owned section is absent from the local file, insert it after the last preceding owned section in manifest order. Reserialize: marker on line 2, then sections in their preserved relative order.
   - `structured` (JSON/TOML): for each path in `owned_paths`, replace the value at that path with the plugin's current value. Preserve all other paths. Update the sidecar rather than embedding a marker.
   - `structured` (.gitignore): for each tag in `owned_paths`, replace the tagged block. Preserve all untagged blocks. Update marker on line 1.
   Update the marker to the new sha. Track as `fast-forward applied`.

3. **`conflict`** / **`conflict_legacy`** (resolution from Step 4b) — Apply per the chosen resolution option. Track the resolution in the Step 8 report.

4. **`unchanged_legacy`** — Silently re-write the file with the marker inserted (no content change). Track as `unchanged (legacy marker added)`.

5. **`unchanged`** / **`local_only`** — No action. Track as `unchanged` or `local-only edit preserved`.

**Non-manifest items** — the following are always applied regardless of the manifest diff flow (they do not participate in the 3-way diff because they are not plugin-managed artifacts with extension strategies):

### `.worktrees/`
Create the directory if absent (worktrunk places worktrees at `.worktrees/<branch-sanitized>`).

### `docs/guide/`
Create with a `.gitkeep` so the directory is tracked.

### `docs/project-brief.md`

The brief is the single source of truth for project identity. Apply the same logic as before:

**If the brief already exists with a usable H1, non-empty `## Description`, and no placeholder narrative sections** — skip. Track as `exists — H1, ## Description, and narrative sections present`.

**If the brief exists but `needs_migration = true` and/or `body_fill_applied = true`** — rewrite the affected regions in place, preserving every other byte exactly:

- *Case A — H1 needs replacement:* locate `^#\s+`. If found, replace with `# <resolved project_name>`. If absent, prepend.
- *Case B — `## Description` needs insertion or replacement:* locate `## Description`. If present, replace section body. If absent, insert after H1.
- *Case C — narrative section body needs replacement* (only for sections answered in Step 2a.ii): for each affected section, locate heading and replace body, or append if absent.

Track as `migrated (H1, ## Description, and/or narrative sections rewritten)`.

**If `create_brief = true`** (Step 2c was run) — write a new brief using the Step 2c answers. Track as `created (full template)`.

**If `create_brief = false` and brief is absent** — skip. Track as `skipped (user opted not to create)`.

### `.worktrees/`
Create the directory (worktrunk places worktrees at `.worktrees/<branch-sanitized>`).

### `docs/guide/`
Create with a `.gitkeep` so the directory is tracked. This is where expanded user documentation lives (tutorials, how-to guides, configuration reference). README.md links here; individual guide files are added as the project grows.

### `docs/project-brief.md`

The brief is the single source of truth for project identity. The exact action depends on what was determined in Step 2:

**If the brief already exists with a usable H1, a non-empty `## Description` section, and no placeholder narrative sections** (Step 2a found `brief_name` non-empty and non-placeholder, `brief_description` non-empty, with `needs_migration` unset and `body_fill_applied` unset) — skip the file. Track in the Step 8 report as `exists — H1, ## Description, and narrative sections present`.

**If the brief exists but `needs_migration = true` and/or `body_fill_applied = true`** (the H1 was missing/placeholder, or the `## Description` section was missing/empty, or one or more narrative sections were placeholder-looking and the user opted into Step 2a.ii's body-fill, with the gap-fill prompts providing the resolved values) — rewrite the affected regions in place, preserving every other byte exactly. Read the existing file content, then proceed by case:

- *Case A — H1 needs replacement* (no H1 present, or the existing H1 was the literal `Project Brief` case-insensitive placeholder): locate the first line matching `^#\s+`. If found, replace that single line with `# <resolved project_name>`. If no H1 line exists, prepend `# <resolved project_name>` followed by a blank line to the file.

- *Case B — `## Description` section needs insertion or replacement*: locate the line `## Description` (case-sensitive). If present, replace the section's body (every line after the heading up to the next H2 or end of file) with a single blank line, the resolved description, and a trailing blank line. If absent, insert a new `## Description` section directly after the H1 — the inserted block is one blank line, then `## Description`, then one blank line, then the resolved description, then one blank line — placed before whatever currently follows the H1.

- *Case C — narrative section body needs replacement* (only applies when `body_fill_applied = true`, and only for sections the user actually answered in Step 2a.ii — those whose `<section>_is_placeholder` flag was true and an `answer_<section>` value was collected): for each affected section (`## Problem`, `## Goals`, `## Non-Goals`, `## Constraints`), locate the section heading line. If the heading is present, replace the section's body (every line after the heading up to the next H2 or end of file) with a single blank line, the answered value, and a trailing blank line. If the heading is absent, append a new `## <Section>` block at the end of the file (a leading blank line, the heading, a blank line, the answered value, a trailing blank line). Never touch a section the user did *not* answer (whether because it had real content or because the user skipped Step 2a.ii entirely).

Cases may apply in any combination (e.g., a pre-RFC brief with `# Project Brief` H1 and no `## Description` section and `<...>` placeholders in all four narrative sections will trigger Case A, Case B, and Case C for whichever sections the user answered). Apply Case A first (rewriting the H1), then Case B (inserting/replacing the `## Description` section), then Case C (rewriting each affected narrative section). Any content not covered by an applied case (e.g., narrative sections the user did not answer, additional headings or paragraphs the user added beyond the template) is preserved exactly — no re-flowing, no other heading rewrites, no sentence-level edits.

`<resolved project_name>` is the value computed in Step 2a (which has already accounted for the `Project Brief` literal-placeholder rule and the identity gap-fill prompt). `<resolved description>` is the value computed in Step 2a. The `answer_<section>` values for Case C come from Step 2a.ii's body-fill prompt.

Track in the Step 8 report as `migrated (H1, ## Description, and/or narrative sections rewritten)`.

**If `create_brief = true`** (Step 2c was run) — write a new brief now using the answers collected in Step 2c. The full file content:

```
# <answer_name>

## Description

<answer_description>

## Problem

<answer_problem>

## Goals

<answer_goals>

## Non-Goals

<answer_nongoals>

## Constraints

<answer_constraints>
```

Track in the Step 8 report as `created (full template)`.

**If `create_brief = false` and the brief is absent** — skip entirely. Track in the Step 8 report as `skipped (user opted not to create)`.

### Template-based artifact rendering

All plugin-managed file content is rendered from templates under `$PLUGIN_ROOT/.claude-plugin/scripts/templates/`. Each template file maps to a manifest entry:

| Template file | Manifest `upstream_key` | Notes |
|---|---|---|
| `CLAUDE.md.tpl` | `bytewyrd/CLAUDE.md@v1` | Templated; placeholders: `<project_name>`, `<description>`, `<project_slug>`, `<LANGUAGE_TOOLCHAIN_SECTION>`, `<AGENT_TABLE_ROWS>`, `<TOOL_USAGE_SECTION>`; conditional regions `<!--lang:*-start/end-->` |
| `README.md.tpl` | `bytewyrd/README.md@v1` | Templated; placeholders: `<project_name>`, `<description>` |
| `BEST_PRACTICES.md.tpl` | `bytewyrd/docs/BEST_PRACTICES.md@v1` | Templated; conditional language regions |
| `CONTRIBUTING.md.tpl` | `bytewyrd/docs/CONTRIBUTING.md@v1` | Non-templated (whole strategy) |
| `ARCHITECTURE.md.tpl` | `bytewyrd/docs/ARCHITECTURE.md@v1` | Non-templated (whole strategy) |
| `settings.json.tpl` | `bytewyrd/.claude/settings.json@v1` | Templated; structured strategy; sidecar marker |
| `settings.local.json.tpl` | `bytewyrd/.claude/settings.local.json@v1` | Non-templated; structured strategy; sidecar marker |
| `mise.toml.tpl` | `bytewyrd/mise.toml@v1` | Templated; structured strategy |
| `.gitignore.tpl` | `bytewyrd/.gitignore@v1` | Non-templated; structured strategy |
| `ci.yml.tpl` | `bytewyrd/.github/workflows/ci.yml@v1` | Templated; whole strategy |
| `PULL_REQUEST_TEMPLATE.md.tpl` | `bytewyrd/.github/PULL_REQUEST_TEMPLATE.md@v1` | Non-templated; whole strategy |
| `.bootstrap-versions.json.tpl` | `bytewyrd/.claude/.bootstrap-versions.json@v1` | Whole strategy; generated at sync time |

The `rfc-process.md` source (`bytewyrd/docs/rfc-process.md@v1`) is read directly from `$PLUGIN_ROOT/rfc-process.md` (non-templated, region strategy).

**Template rendering details** (for reference when rendering templates):

**`CLAUDE.md.tpl` placeholders:**

- `<LANGUAGE_TOOLCHAIN_SECTION>`: include one line per detected language:
  - Rust: `Rust — see \`rust-toolchain.toml\`. Build: \`cargo build\`. Test: \`cargo test\`. Lint: \`cargo clippy\`.`
  - JS/TS: `JavaScript/TypeScript — see \`mise.toml\` for Bun version. Install: \`bun install\`. Test: \`bun test\`.`
  - Go: `Go — see \`mise.toml\` for Go version. Build: \`go build ./...\`. Test: \`go test ./...\`.`
  - Python: `Python — see \`mise.toml\` for Python version. Install: \`uv sync\`. Test: \`uv run pytest\`.`
  - Shell/Infra: `Infrastructure — see \`mise.toml\` for tool versions. Deploy: \`./deploy <env>\`.`
  - If no languages detected: `No language-specific toolchain detected. Add source code and re-run \`/sync\` to pick up language tooling.`

- `<AGENT_TABLE_ROWS>`: merge rows from all detected languages; deduplicate shared agents (feature-engineer, code-reviewer, rfc-architect, documentation-writer, debugger appear once):
  - Rust: `| rust-engineer | Rust-specific code |`
  - JS/TS: `| typescript-pro | TypeScript-specific code |` + `| frontend-developer | UI components |`
  - Go: `| golang-pro | Go-specific code |`
  - Python: `| python-pro | Python-specific code |`
  - Shell/Infra: terraform-engineer, kubernetes-specialist, cloud-architect, sre-engineer
  - Always: feature-engineer (new features), code-reviewer (code reviews), rfc-architect (architecture/RFCs), documentation-writer (docs), debugger (debugging)

- `<TOOL_USAGE_SECTION>`: build from installed tools. Exa and Firefox MCP are unconditional. Context7 only if `context7@claude-plugins-official` is installed. If none installed, omit the `## Tool Usage` section entirely.

**`settings.json.tpl` rendering:**

**Do NOT include `bytewyrd@bytewyrd` in `enabledPlugins` or `extraKnownMarketplaces`.** The plugin is installed once per machine at user scope (`~/.claude/settings.json`), not per-project. Adding it to project settings would recreate the per-project maintenance burden that the user-scope recommendation was specifically designed to avoid: every project would carry entries that need to be updated if the plugin name, marketplace, or source URL ever changes.

New collaborators who don't have the plugin are covered by the CONTRIBUTING.md install hint that `/sync` adds to every consumer project. The plugin's own `SessionStart` hook (`check-requirements.sh`) handles per-session validation of companion plugins and MCP servers for users who already have it installed — it cannot warn users who don't have it, because the hook only runs when the plugin is loaded.

**Cleanup of legacy entries (always run before writing):** If the existing `.claude/settings.json` contains a `bytewyrd@bytewyrd` entry under `enabledPlugins`, or a `bytewyrd` entry under `extraKnownMarketplaces`, remove them. This is a forward-only migration — 0.1.x projects had the `enabledPlugins` entry; current projects must not. Use `jq` with bracket notation (dot notation with `@` is non-portable across jq versions):

```bash
jq 'del(.enabledPlugins["bytewyrd@bytewyrd"]) | del(.extraKnownMarketplaces["bytewyrd"])' .claude/settings.json
```

The cleanup is idempotent — re-running on a clean project is a no-op.

Teams that want to mandate project-scope enablement (so Claude Code auto-installs the plugin for collaborators) can do so manually by adding both `enabledPlugins` and `extraKnownMarketplaces` entries themselves and committing them — but this is not the default, and both entries are required (see `docs/guide/installation.md`).

**Include only if installed** — an uninstalled `claude-plugins-official` plugin causes Claude Code to error on startup. Read `~/.claude/plugins/installed_plugins.json` and include each entry only if its identifier is present in the registry. Add `"github@claude-plugins-official": true`, `"context7@claude-plugins-official": true`, `"code-review@claude-plugins-official": true` only for plugins in `installed`.

The `PreToolUse` hook's quality-gate command chains gate commands for all detected languages with `&&`. Skip Shell/Infra. Wrap non-root component paths in a subshell. If no languages with a standard gate are detected, omit the `PreToolUse` hook entirely.

Quality gate commands by language:
- Rust: `cargo fmt --all --check && cargo clippy --workspace --locked -- -D warnings && cargo test --workspace --locked`
- JS/TS: `bun run typecheck && bun run lint && bun test`
- Go: `gofmt -l . | grep . && exit 1 || true && go vet ./... && go test ./...`
- Python: `uv run ruff check . && uv run mypy . && uv run pytest`

**`settings.local.json.tpl` language additions:**

Add entries for every detected language (union of all, append-only):
- Rust: `"WebFetch(domain:docs.rs)"`, `"WebFetch(domain:crates.io)"`, `"Bash(cargo:*)"`, `"Bash(rustc:*)"`
- JS/TS: `"WebFetch(domain:registry.npmjs.org)"`, `"Bash(bun:*)"`, `"Bash(npm:*)"`
- Go: `"WebFetch(domain:pkg.go.dev)"`, `"Bash(go:*)"`
- Python: `"WebFetch(domain:pypi.org)"`, `"Bash(python:*)"`, `"Bash(uv:*)"`
- Shell/Infra: `"WebFetch(domain:registry.terraform.io)"`, `"Bash(terragrunt:*)"`, `"Bash(kubectl:*)"`, `"Bash(helm:*)"`

**`mise.toml.tpl` tools section:**

Run `mise latest <tool>` to resolve the current stable version. Never write `"latest"`. Append only non-Rust languages:
- JS/TS: `bun = "<version>"`
- Go: `go = "<version>"`
- Python: `python = "<version>"`
- Shell/Infra: `terraform`, `kubectl`, `helm` (only tools actually used)

If `mise` is unavailable, write a reasonable placeholder and note it in the Step 8 report.

**`.gitignore.tpl` language entries:**

Always: `.worktrees/`, `.claude/settings.local.json` (tagged under `# bytewyrd:base`).
Per language:
- Rust: `target/` (tagged under `# bytewyrd:rust`)
- JS/TS: `node_modules/`, `dist/` (tagged under `# bytewyrd:js`)
- Python: `__pycache__/`, `*.pyc`, `.venv/` (tagged under `# bytewyrd:python`)
- Shell/Infra: `.terragrunt-cache/`, `.terraform/`, `.terraform.lock.hcl` (tagged under `# bytewyrd:infra`)

**Language tooling files** (not in the manifest — created as needed, not diff-tracked):
**If Rust is detected** — create `rust-toolchain.toml` if absent (do NOT add Rust to mise):
```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "rust-analyzer", "clippy"]
```

**CONTRIBUTING.md rendering:**

- `<PREREQUISITES_SECTION>` and `<INSTALL_COMMAND>`: expand per detected languages. Multi-language: list each non-trivial install step.
- `<QUALITY_GATE_DESCRIPTION>` per language: Rust: `` `cargo fmt --all --check`, `cargo clippy --workspace --locked -- -D warnings`, `cargo test --workspace --locked` ``; JS/TS: `` `bun run typecheck`, `bun run lint`, `bun test` ``; etc.
- **Bytewyrd plugin install hint (always include):** After the `## Prerequisites` heading and before the `## Development Setup` heading, insert the following block (idempotent: skip if `claude plugin marketplace add bytewyrd/claude-bytewyrd` is already present in the file):

```markdown
This project uses the [Bytewyrd Claude Code plugin](https://github.com/bytewyrd/claude-bytewyrd) for its dev workflow. Install once per machine (user scope; no per-project install needed):

\`\`\`bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
\`\`\`

The plugin's `SessionStart` hook will warn you if any required companion plugins or MCP servers are missing in this project — follow the printed fix command for each.
```


**ci.yml rendering:**

Assemble one job per detected language. If single language, name the job `ci`; otherwise name per language (`rust`, `frontend`, `go`, `python`). For non-root component paths, add `defaults: run: working-directory: <path>` at the job level.
---

## Step 6 — GitHub repository metadata (only if `has_github = yes`)

GitHub file artifacts (`.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md`) are now handled by the Step 4–5 manifest diff/apply flow like any other plugin-managed artifact. The only remaining Step 6 logic is the **GitHub repository metadata update**, which is not a file operation.

If a GitHub remote is configured, update the repository description to match `description` from the brief:

```bash
git remote get-url origin 2>/dev/null
```

If this returns a `github.com` URL, and `description` is non-empty:

```bash
# Update description (only if description is non-empty)
gh repo edit --description "<description>"
```

If the repo name on GitHub differs from `project_name` (GitHub repo names are typically kebab-case), note the discrepancy in the Step 8 report but do **not** rename the repo — renames break existing clones and links.

If `gh` is not available or the remote is not yet set up, note it in the Step 8 report and move on.

The `description` value is sourced from `docs/project-brief.md`, ensuring local files and the remote stay aligned. When `description` is `""`, no `gh repo edit --description` call is made.
---

## Step 7 — Set up RFC process

**Create `docs/rfcs/`** with a `.gitkeep` if the directory doesn't exist:

```bash
mkdir -p docs/rfcs && test -f docs/rfcs/.gitkeep || touch docs/rfcs/.gitkeep
```

The `docs/rfc-process.md` file is now managed as a manifest artifact with `extension_strategy: "region"` (upstream key `bytewyrd/docs/rfc-process.md@v1`). Its creation, update, and conflict handling are handled by the Step 4–5 diff/apply flow, just like any other manifest artifact. The bespoke sync logic that previously lived in this step has been removed — it was a single-file implementation of the same pattern the manifest generalizes.

---

## Step 8 — Report

### Step 5.5 — Rewrite sidecar if any JSON artifact's marker advanced

Before printing the report, check whether any JSON-format artifact's marker was updated in Step 5 (i.e., `.claude/settings.json` or `.claude/settings.local.json` was written with a new marker). If yes, rewrite `.claude/.bootstrap-versions.json` in full with all current marker entries. If no JSON artifact's marker changed, the sidecar is not rewritten.

### Final report

Print a summary of every artifact processed, grouped by outcome category. Use the new outcome labels:

| File | Outcome |
|------|---------|
| `CLAUDE.md` | added / fast-forward applied / conflict resolved (see note) / unchanged / local-only edit preserved / unchanged (legacy marker added) |
| `README.md` | added / fast-forward applied / ... |
| `docs/BEST_PRACTICES.md` | added / fast-forward applied / ... |
| `docs/CONTRIBUTING.md` | added / fast-forward applied / ... |
| `docs/ARCHITECTURE.md` | added / fast-forward applied / ... |
| `docs/rfc-process.md` | added / fast-forward applied / conflict resolved / ... |
| `.claude/settings.json` | added / fast-forward applied / ... |
| `.claude/settings.local.json` | added / fast-forward applied / ... |
| `.github/workflows/ci.yml` | added / fast-forward applied / ... |
| `.github/PULL_REQUEST_TEMPLATE.md` | added / fast-forward applied / ... |
| `mise.toml` | added / fast-forward applied / ... |
| `.gitignore` | added / fast-forward applied / ... |
| `.worktrees/` | created / already exists |
| `docs/guide/` | created / already exists |
| `docs/project-brief.md` | created (full template) / migrated / skipped (user opted not to create) / exists |
| `docs/rfcs/.gitkeep` | created / already exists |
| `rust-toolchain.toml` | created / already exists (Rust only) |
| GitHub repo description | updated via `gh repo edit` / skipped (no remote or description) |

For conflicts where the user chose `Merge into local manually`:
```
<path> — manual merge requested
  See:  .claude/sync-conflict-<sanitized-path>.txt
        .claude/sync-local-<sanitized-path>.txt
  Re-run /sync after merging.
```

For `Skip for now` resolutions, call out the deferred count explicitly:
```
N conflict(s) deferred — will re-surface on the next /sync run.
```

Collapse `unchanged` and `local-only edit preserved` to single-line summaries (count only, no per-file listing).

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
