---
name: sync
description: Set up or refresh a project repository with all standard conventions — idempotent, safe to re-run whenever the plugin updates. Triggered by "/sync".
---

<!-- bootstrap-content-version: 2026-05-12-b9f3e2a -->

# Sync

Sets up or refreshes a project repository with all standard conventions. Idempotent — re-running computes a three-way diff for every plugin-managed artifact and presents a categorized summary (additions, fast-forward updates, conflicts, local-only edits, unchanged) before writing anything.

**Output rule:** do not narrate tool calls or internal implementation steps before executing them. The user does not know or care which scripts run internally. Only output the change summary and any required prompts.

## Interaction model

/sync has three user interaction points:

1. **Steps 2a–2c (project identity)** — Only when `docs/project-brief.md` is absent or incomplete. One AskUserQuestion for name/description gaps; optional body-fill; brief creation.
2. **Step 4 — single "Proceed?" confirmation** — After printing the full change summary, one AskUserQuestion with options `Proceed` / `Cancel`. Omitted when there are no changes at all.
3. **Step 4c (additive-merge-with-diff cherry-pick only)** — One AskUserQuestion per `additive_merge_with_diff_apply` artifact. All other strategies (authoritative, structured, owned-regions, additive-merge) are applied without further input after Proceed.

When `docs/project-brief.md` already exists with complete identity *and* all plugin-managed files are at the current plugin version, Steps 4 and 4c are skipped — `ALL_UNCHANGED=true` is printed in Step 1, `/sync` presents the "Everything is up to date." summary, and exits without prompting.

## Step 1 — Validate environment, detect plugins, classify artifacts

Log: `Running /sync analysis…`

Run the consolidated deterministic-phase script **exactly once** and write its output to a session file:

```bash
bash scripts/sync-run.sh > $TMPDIR/bytewyrd-sync-data.json && \
jq -r '
  "REPO_ROOT="          + .preflight.repo_root,
  "GIT_USER="           + .preflight.git_user,
  "PROJECT_SLUG="       + .preflight.project_slug,
  "PLUGIN_ROOT="        + .preflight.plugin_root,
  "PLUGIN_VERSION="     + .preflight.plugin_version,
  "HAS_SUBSTANTIAL_CONTENT=" + (.preflight.has_substantial_content | tostring),
  "GITHUB_DESCRIPTION=" + .preflight.github_description,
  "DOCS_AGENT_DRIFTED=" + (.preflight.docs_agent_drifted | tostring),
  "SIDECAR_MIGRATED="   + (.preflight.sidecar_migrated | tostring),
  "SIDECAR_MESSAGE="    + .preflight.sidecar_message,
  "HAS_RUST="           + (.preflight.has_rust | tostring),
  "HAS_JS="             + (.preflight.has_js | tostring),
  "HAS_GO="             + (.preflight.has_go | tostring),
  "HAS_PYTHON="         + (.preflight.has_python | tostring),
  "HAS_SVELTE="         + (.preflight.has_svelte | tostring),
  "HAS_RUBY="           + (.preflight.has_ruby | tostring),
  "HAS_RAILS="          + (.preflight.has_rails | tostring),
  "HAS_K8S_CUE="        + (.preflight.has_k8s_cue | tostring),
  "HAS_TERRAFORM="      + (.preflight.has_terraform | tostring),
  "MISSING_CRITICAL="     + (.preflight.missing_critical | tostring),
  "MISSING_RECOMMENDED="  + (.preflight.missing_recommended | tostring),
  "BRIEF_COMPLETE="       + (.brief_complete | tostring),
  "RFC_HAS_EXTENSIONS="   + (.rfc_process.has_extensions | tostring),
  "CLASSIFICATIONS_COUNT=" + (.classifications | length | tostring),
  "ALL_UNCHANGED="        + (.all_unchanged | tostring)
' $TMPDIR/bytewyrd-sync-data.json && \
echo "---" && \
jq -r '.summary_text' $TMPDIR/bytewyrd-sync-data.json
```

If `sync-run.sh` exits non-zero, stop immediately — it has already printed the relevant error to stderr. The error is self-explanatory; no further wrapping needed.

The output above includes a `---` separator followed by the pre-built `/sync — change summary:` text. **Read and present that summary to the user verbatim — do not re-derive it from the raw classifications.** All subsequent data access uses `$TMPDIR/bytewyrd-sync-data.json`; never re-run `sync-run.sh`.

The script also writes `.bytewyrd/docs-agent-version` as a side effect when the plugin's docs-agent version differs from the project's recorded version — no separate Step 1.5 logic is required in the skill.

**Sidecar migration (one-time, idempotent):** preflight performs the legacy `.claude/.bootstrap-versions.json` → `.bytewyrd/.bootstrap-versions.json` move automatically. If `SIDECAR_MIGRATED == true`, log `SIDECAR_MESSAGE` in the Step 8 report under "Migration notes." The migration only fires when the old path exists and the new path does not; otherwise it's a silent no-op.

**Surface the collected context to the user as appropriate:**

- If `HAS_SUBSTANTIAL_CONTENT == true`, note: "This repo already has content — sync will skip any files that already exist and only create the ones that are missing."
- If `MISSING_CRITICAL` is a non-empty JSON array, warn that critical plugins are missing (GitHub MCP). Do not stop — the warning is informational; the user can re-run after installing.
- If `MISSING_RECOMMENDED` is a non-empty JSON array, note the recommended plugins (Context7, Code Review). Same non-blocking semantics.
- If `DOCS_AGENT_DRIFTED == true`, print the drift suggestion using `plugin_docs_ver` and `project_docs_ver` from the preflight JSON:

  ```
  The plugin's docs-agent has improved (project=<project_docs_ver>, plugin=<plugin_docs_ver>). Consider running /docs-review against docs/guide/** to re-audit user-facing documentation with the updated checks.
  ```

  Do **not** auto-invoke `/docs-review` — `/sync` only prints the suggestion. The decision to run the review belongs to the main agent or the user.

`PROJECT_SLUG` is the raw directory name as-is (e.g., `tinywyrd`, `eve-platform`). It is never changed or asked about. It is used anywhere the machine-readable name is needed: CLI binary references, package name examples, `cd <project-slug>` in setup docs, etc.

`GITHUB_DESCRIPTION` is the current GitHub repo description (empty string when no GitHub remote is configured or `gh` is unavailable). It is the pre-fill default for the description question in Step 2.

The plugin cross-check covers:

| Plugin | Identifier | Criticality |
|--------|-----------|-------------|
| GitHub MCP | `github@claude-plugins-official` | Critical |
| Context7 | `context7@claude-plugins-official` | Recommended |
| Code Review | `code-review@claude-plugins-official` | Recommended |

The `bytewyrd@bytewyrd` plugin is NOT in this table and NOT written to project settings — it is installed once per machine at user scope. The plugin's `SessionStart` hook validates companion plugins and MCP servers for users who have it installed; new collaborators who don't have it are directed to install via the CONTRIBUTING.md hint `/sync` adds to every consumer project.

Note: Exa is a separate MCP server (not a plugin) — its permissions go unconditionally in `settings.local.json`.

**Write target:** all files created or modified by sync go to the directory returned in `REPO_ROOT`. This is always the correct target — whether you're in a standard checkout or a worktree. **Never** run `git rev-parse --git-common-dir` or otherwise detect the "main" repo root and redirect writes there. If sync is invoked from a worktree, the worktree is the intended working context; changes land on a branch and flow through a PR — that is the desired workflow.

**Also record the plugin version** so the `SessionStart` hook can warn collaborators who are on an older version than the one that last ran `/sync` on this project:

```bash
PLUGIN_VER=$(jq -r '.version // empty' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/.claude-plugin/plugin.json" 2>/dev/null || echo "")
[ -n "$PLUGIN_VER" ] && echo "$PLUGIN_VER" > .bytewyrd/plugin-version
```

Only write if `PLUGIN_VER` is non-empty. If the file is unreadable (e.g. development checkout with a non-standard layout), skip silently.

---

## Step 2 — Gather project identity from the brief

**Skip this step entirely when `BRIEF_COMPLETE=true` was printed in Step 1.** In that case set `project_name` and `description` by reading the brief directly from `docs/project-brief.md` (no prompts needed), then proceed to Step 3.

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

Language detection ran in Step 1. The `HAS_*` flags were printed in the Step 1 output. `LANGUAGES` and `COMPONENT_ROOTS` are available from the session file:

```bash
jq '.preflight.languages' $TMPDIR/bytewyrd-sync-data.json
jq '.preflight.component_roots' $TMPDIR/bytewyrd-sync-data.json
```

`COMPONENT_ROOTS` is a list of `{ language, path, name }` entries with these rules baked into the script:

- **Rust**: If root `Cargo.toml` contains `[workspace]`, the script reads its `members` array via `python3 + tomllib` and emits one entry per member, resolving each member's `package.name` from its Cargo.toml. If it's a standalone crate, the component is `.` with the package name. If no `Cargo.toml` exists, no Rust entries are emitted.
- **JS/TS**: Each directory containing a `package.json` is a component. The script uses the `name` field from the JSON as the component name, falling back to the directory name.
- **Go**: Each directory containing a `go.mod` is a module/component (named by its dirname).
- **Python**: Each directory containing `pyproject.toml` or `setup.py` is a component (named by its dirname).

The stack-detection flags `HAS_SVELTE`, `HAS_RUBY`, `HAS_RAILS`, `HAS_K8S_CUE`, `HAS_TERRAFORM` are independent of component roots. They are consumed by Step 5's `docs/BEST_PRACTICES.md` creation policy: sync appends the matching addition block only when its flag is true (e.g., the Svelte block only when `HAS_SVELTE`, the Rails block only when `HAS_RAILS` and after the Ruby block since Rails depends on Ruby being present).

Since sync is idempotent, re-running it after adding new components will detect them and fill in any missing config.

---

## Step 4 — Compute diff and present summary

This step replaces the former "Print creation summary." It runs the pre-flight diff procedure against the bootstrap manifest, classifies each artifact, and presents a categorized summary before any files are written.

### Pre-flight diff procedure

`PLUGIN_ROOT` was printed by Step 1. If needed: `jq -r '.preflight.plugin_root' $TMPDIR/bytewyrd-sync-data.json`.

Read the manifest at `$PLUGIN_ROOT/bootstrap-manifest.json`. Also read the sidecar at `.bytewyrd/.bootstrap-versions.json` (treat as `{}` if absent).

**SHA-256:** all canonical-form hashing is done by `scripts/sync-canonical.sh`, which uses `sha256sum` (Linux) with a `shasum -a 256` fallback (macOS) and emits the first 12 hex chars. Callers never invoke `sha256sum` directly — they always go through the helper script so the canonical form is consistent across strategies.

`CLASSIFICATIONS` comes from the session file written in Step 1 — no second bash call to `sync-run.sh` is needed:

```bash
jq '.classifications' $TMPDIR/bytewyrd-sync-data.json
```

Each element includes the manifest entry fields (`upstream_key`, `source`, `templated`, `owned_paths`, `owned_boundaries`, `owned_sections`) merged with the classification result (`classification`, `strategy`, `target`, `recorded_sha`, `plugin_sha`, `chunks`). Parse `.classification` for the verdict; `.recorded_sha` and `.plugin_sha` are surfaced for Steps 4b/4c prompts; `.chunks` drives the per-file chunk detail in the summary.

`sync-classify.sh` implements both the strategy-first dispatch (for `bootstrap`, `authoritative`, `additive-merge`, `additive-merge-with-diff`, `owned-regions`) and the seven-cell structured matrix (for `owned-regions` and `structured`). It internally calls `sync-canonical.sh` for the per-strategy hash computation and `sync-marker-read.sh` to read the local marker. See those scripts for the per-strategy canonicalization rules and marker format.

**Plugin canonical for additive-merge:** at classification time the canonical is approximated from the raw template source under each `owned_sections` heading — sufficient to detect "template changed since we last wrote this file" without requiring full project inputs at classification time. At apply time the merge re-renders the template with full inputs and writes the true canonical SHA into the marker.

**Classification outcomes by strategy** (also tabulated in the script header for cross-reference):

| Strategy | Possible classifications |
|----------|--------------------------|
| `bootstrap` | `bootstrap_create`, `local_only` |
| `authoritative` | `authoritative_add`, `unchanged`, `authoritative_update` |
| `additive-merge` | `additive_merge_apply`, `unchanged` |
| `additive-merge-with-diff` | `additive_merge_with_diff_apply`, `unchanged` |
| `owned-regions` / `structured` | `add`, `unchanged_legacy`, `conflict_legacy`, `unchanged`, `fast_forward`, `local_only`, `conflict` |

### Print the summary

The change summary was pre-built by `sync-run.sh` and printed at the end of the Step 1 bash output (after the `---` separator). Present it to the user verbatim — do not re-derive it from the raw classifications.

**If `ALL_UNCHANGED=true` was printed in Step 1, present the summary and stop — do not show any prompt.** There is nothing to apply.

If `ALL_UNCHANGED=false`, ask one AskUserQuestion:

**"Apply these changes?"** with options:
- `Proceed` — continue to Step 4a.
- `Cancel` — exit without writing any files.

### Step 4a — Deterministic batch apply (no further confirmation)

All artifacts except `additive_merge_with_diff_apply` are applied in a single script call immediately after the user clicks Proceed:

```bash
BATCH_RESULT="$(bash scripts/sync-apply-batch.sh $TMPDIR/bytewyrd-sync-data.json)"
```

`sync-apply-batch.sh` detects the session file, extracts `plugin_root`, builds the project-inputs object from `preflight` + `brief_name`/`brief_description`, and filters out `additive_merge_with_diff_apply`, `unchanged`, and `local_only` items internally.

The batch script handles all of the following without user input:

| Classification | Strategy | Action |
|---|---|---|
| `authoritative_add`, `authoritative_update` | authoritative | Overwrite and stamp |
| `add`, `fast_forward`, `unchanged_legacy` | any | Apply owned regions/paths and stamp |
| `conflict`, `conflict_legacy` | owned-regions | Plugin-owned regions replaced; user-owned preserved; stamp |
| `conflict`, `conflict_legacy` | structured (.gitignore) | Plugin tag-blocks replaced; all other content preserved; stamp |
| `conflict`, `conflict_legacy` | structured (JSON) | Plugin dot-path values overwritten; all other keys preserved; stamp |
| `additive_merge_apply` | additive-merge | Run LLM item merge; write; stamp (if auto-merge produces contradictions, escalates to `!` cherry-pick flow) |
| `bootstrap_create` | bootstrap | Render template; write; stamp |

**Special case for `docs/rfc-process.md`** (authoritative): if `RFC_HAS_EXTENSIONS=true` was printed in Step 1, print a one-time warning quoting the `## Project Extensions` section (from `jq -r '.rfc_process.body' $TMPDIR/bytewyrd-sync-data.json`) before the batch write. No extra prompt — the user already clicked Proceed.

```
docs/rfc-process.md — your '## Project Extensions' section will be removed
because the file is now plugin-authoritative.
The content was:

  <quoted section body, indented 2 spaces, truncated to 200 chars>

Copy anything you want to keep to docs/CONTRIBUTING.md or a new
docs/rfc-process-extensions.md before the next step.
```

`unchanged` and `local_only` artifacts are silently skipped.

### Step 4c — Additive-merge-with-diff cherry-pick

Applies only to `additive_merge_with_diff_apply` artifacts (currently: `.github/PULL_REQUEST_TEMPLATE.md` and `.github/workflows/ci.yml`).

**`additive_merge_with_diff_apply` (additive-merge-with-diff strategy).** Run the per-section merge, run Pass 1 of the soundness review (auto-apply all fix types). Generate the unified diff between the local file and the (merged + Pass 1 result) by running:

```bash
bash scripts/sync-unified-diff.sh <local-file> <merged-content-file>
```

Parse the JSON output. Use `.diff` as the human-readable diff to print. Use `.hunks` (an array of `{id, label, diff}` records) to build the `Accept with exclusions` multiSelect checkbox list — each hunk becomes one option labeled by `.hunks[].label`. Then present the four-option diff-review prompt:

- `Accept all` — write the merged result, then run Pass 2 of the soundness review (explain-and-ask). The Pass 2 prompt is described below.
- `Accept with exclusions` — present the hunk multiSelect checkbox list. Deselected hunks revert to the local content for that range. Write the result; then run Pass 2.
- `Manual 3-way merge` — write the file with git-style conflict markers (`<<<<<<< local`, `=======`, `>>>>>>> plugin`); skip Pass 2; print the explanation below.
- `Defer` — no write; skip Pass 2; re-present next run.

**Soundness-review Pass 2 explain-and-ask prompt** (runs only for `additive-merge-with-diff` `Accept all` and `Accept with exclusions` paths). After the write, if Pass 2 finds any soundness issues, print each issue (location, type, description, suggested fix) and ask one AskUserQuestion:

- `Fix automatically` — apply all soundness fixes from Pass 2, then write again.
- `I'll handle it` — leave the file as-is; the user resolves the issues manually.

**Manual 3-way merge explanation** (printed when `Manual 3-way merge` is chosen):

> Wrote `<path>` with git-style conflict markers for `<N>` hunks. Open the file, resolve each conflict by keeping the version you want (or composing a merge), remove the marker lines, and re-run `/sync`.

Until the conflict markers are removed, the file classifies as `additive_merge_with_diff_apply` on subsequent runs.

**Note:** only `additive_merge_with_diff_apply` artifacts enter Step 4c. All other classifications are handled by the deterministic batch in Step 4a.

---

## Step 5 — Apply changes

This step applies the actions determined by Steps 4a and 4b. For each artifact in the diff result, apply its action. Templates are read from `$PLUGIN_ROOT/templates/`. Non-templated artifact sources are read from the `source` field in the manifest (resolved relative to `$PLUGIN_ROOT`).

**Template rendering rule:** for each templated artifact, run:

```bash
bash scripts/sync-render-template.sh <template-path> <inputs-json-path>
```

The script emits the rendered content on stdout. Internally it substitutes `<placeholder>` tokens from the inputs JSON (lowercased keys), and includes or strips `<!--lang:NAME-start-->...<!--lang:NAME-end-->` blocks based on the inputs `languages` array or `has_NAME` truthy keys. See the script header for the exact contract.

**Marker insertion rule:** after writing content for a new or updated file, compute the canonical SHA via `sync-canonical.sh`, then stamp the marker according to file type:

- Markdown (`.md`): `bash scripts/sync-write-header.sh <file> <upstream_key> <sha12> bootstrap` (or `authoritative` for plugin-owned files). The script handles both fresh-write and replace.
- TOML / YAML / `.gitignore`: insert `# bootstrap-content-version: <upstream_key>:<sha12>` as line 1, followed by a blank line, then the file content. (No header-writer script — these inline `#` markers do not have the two-line tagline form.)
- JSON files: do **not** embed a marker in the file. The marker is stored in the sidecar (Step 5.5).

To read an existing marker from a file (for diff classification or any other lookup), run `bash scripts/sync-marker-read.sh <file>` and parse `.sha12` (or branch on `.found == false` when no marker is present).

Step 4a runs the batch apply for all deterministic items. The `BATCH_RESULT` JSON array is the source of truth for Step 8 tracking. Items with `"result": "needs-agent"` in the batch result are additive-merge-with-diff items that were deferred to Step 4c.

**Apply actions (for reference — the batch script implements these):**

1. **`add`** — Render the template via `sync-render-template.sh` with `project_inputs`. Compute the canonical SHA via `sync-canonical.sh` for the artifact's strategy. Write the file, then stamp the marker per the "Marker insertion rule" above. Track as `added`.

2. **`fast_forward`** — Apply the extension strategy:
   - `owned-regions`: run `bash scripts/sync-owned-regions-apply.sh <local> <plugin-source> '<owned_boundaries-json>'` and write the result to the target. Stamp the marker.
   - `structured` (JSON, dot-path): for each path in `owned_paths`, overwrite the local value with the plugin value via `jq`. All other keys are preserved. JSON files: flag `sidecar_update_needed` (Step 5.5). `.gitignore`: replace each tagged block; stamp the inline marker.
   Track as `fast-forward applied`.

3. **`conflict`** / **`conflict_legacy`** — Same apply logic as `fast_forward` for the matching strategy. Plugin-owned regions/paths always win; project-owned content is preserved. Track as `conflict resolved (deterministic)` or `conflict_legacy resolved (deterministic)`.

4. **`unchanged_legacy`** — Silently re-write the file with the marker inserted (no content change). Track as `unchanged (legacy marker added)`.

5. **`unchanged`** / **`local_only`** — No action. Track as `unchanged` or `local-only edit preserved`.

6. **`additive_merge_apply`** (additive-merge strategy) — Run the per-section LLM item merge. If all sections merge cleanly (no contradictions): write the file, stamp the marker, track as `~`. If any section produces unresolvable contradictions: do NOT write; instead surface the item as `!` and run the `additive_merge_with_diff` interactive flow (diff display + user cherry-pick). After user resolves, write and stamp.

7. **`additive_merge_with_diff_apply`** (additive-merge-with-diff strategy) — Run the same per-section item merge as `additive-merge`. Pass 1 of the soundness review auto-applies all fix types (`duplicate`, `structural`, `ordering`, `semantic`). Render a unified diff of (local file) vs (merged + Pass 1 result) and present the Step 4c diff-review prompt. On `Accept all` or `Accept with exclusions`: write the file, then run Pass 2 of the soundness review (explain-and-ask — the user chooses `Fix automatically` or `I'll handle it`). On `Manual 3-way merge`: write the file with git-style conflict markers; skip Pass 2. On `Defer`: no write. The marker SHA is `plugin_sha` (not the merged-file SHA). Track per the chosen path.

8. **`bootstrap_create`** (bootstrap strategy, confirmed in Step 4b) — Render the template with `project_inputs` via `sync-render-template.sh`. Write the rendered content to disk, then stamp the two-line header in place:

   ```bash
   bash scripts/sync-write-header.sh <target> <upstream_key> <sha12> bootstrap
   ```

   `<sha12>` is the canonical SHA from `sync-canonical.sh` (here, the canonical for a freshly-written file is just the rendered content). The script handles both prepend (no existing header) and replace (existing recognized header).

   Track as `bootstrapped`. If the user deselected the file in Step 4b → no write, defer (re-surfaces next run). Local-only files (file present, no marker) → no write, preserve.

9. **`authoritative_add`** / **`authoritative_update`** (authoritative strategy — applied automatically in Step 4a) — Read the plugin source. Write it to the target, then stamp the two-line header:

   ```bash
   bash scripts/sync-write-header.sh <target> <upstream_key> <sha12> authoritative
   ```

   Local edits in the body are replaced without confirmation. Track as `authoritative-overwritten`. `unchanged` → no action.

10. **`owned-regions`** apply — run:

    ```bash
    bash scripts/sync-owned-regions-apply.sh <local-file> <plugin-source> '<owned_boundaries-json>'
    ```

    The script writes the merged content to stdout — the caller writes it back to the target and then stamps the marker on line 2. See the script for the exact merge semantics (replace owned headings in place, preserve user-owned content, insert absent plugin-owned headings after the last preceding present heading).

### Additive-merge algorithm

For every owned section in `owned_sections` of an `additive-merge` or `additive-merge-with-diff` artifact, the merge runs as follows. Sections in the local file that are **not** listed in `owned_sections` are invisible to this algorithm — they are never read, never compared, never modified, and never flagged as conflicts. They survive untouched into the reserialized output.

**Step A — Extract items.** For each owned section, run:

```bash
bash scripts/sync-item-parser.sh markdown --section '<heading>' < <file>
```

(For `.github/workflows/ci.yml`, use `yaml` instead of `markdown` and pass the file directly with no `--section`.) Parse the JSON output: `.items[]` is the list of discrete items, each with `index`, `text`, and `type` (one of `bullet`, `paragraph`, `codeblock`, `yaml-key`). Top-level bullets carry their sub-bullets; paragraphs are one item; code blocks are one item.

**Step B — Classify pairs in one batch LLM call per section.** The batch LLM-comparison helper is invoked once per owned section (not per pair). A single prompt lists all plugin items and all local items for the section and asks for a complete classification matrix in one JSON response. Prompt format:

```
You are classifying relationships between items in a developer documentation section.

Plugin items (indexed 0..P-1):
<plugin_items_json_array>

Local items (indexed 0..L-1):
<local_items_json_array>

For every (plugin_index, local_index) pair, classify the relationship as:
  - "same_concept": the items express the same rule or fact, possibly in different wording
  - "different_concept": the items express genuinely different concepts
  - "contradiction": the items express opposing rules — one negates or prohibits what the other prescribes

Return JSON: {"pairs": [{"pi": <int>, "li": <int>, "rel": "<one of the three>", "conf": <float 0-1>}]}
Include only pairs where you classified a meaningful relationship (same_concept or contradiction);
omit pairs where rel == "different_concept" to keep the response compact.
```

**Step C — Apply the classification.**

- `same_concept` pairs with `conf >= 0.5` → **replace** the local item with the plugin item's wording (plugin wins on phrasing for the matching concept).
- `contradiction` pairs with `conf >= 0.5` → add to the section's `pending_contradictions` list (resolved one item at a time in Step 4c's `additive_merge_apply` flow).
- Plugin items not in any `same_concept` pair → **append** to the section after the last preserved/replaced item.
- Local items not in any `same_concept` or `contradiction` pair → **preserve byte-for-byte** in their original position.

**Step D — Soundness review.** After the merge, run the soundness reviewer (described below). For `additive-merge`, auto-apply only `duplicate` and `structural` fixes; log `ordering` and `semantic` issues as suggestions in the Step 8 report. For `additive-merge-with-diff` Pass 1, auto-apply all fix types; Pass 2 explain-and-asks.

**Step E — Reserialize.** Emit the merged section body with one blank line between items. Concatenate **all** sections — owned and non-owned — in their original order in the file. Sections **not** listed in `owned_sections` are carried through **byte-for-byte, unmodified**, in their original position. They are never classified as conflicts, never shown in a diff prompt, and never modified. Newly inserted plugin sections (headings absent from the local file) are placed after the last preceding owned section that is present. Write the marker on line 2 with `plugin_sha` (canonicalized plugin items only) — not the merged-file SHA.

### Soundness review

The soundness reviewer runs as an LLM-assisted pass (one call per file per pass) after the merge step. It checks:

1. **Ordering** — sections and items appear in logical order for the file type.
2. **No duplicates** — no two items within the same section express the same concept.
3. **Structural validity** — the file is well-formed (valid YAML, valid heading hierarchy, no unclosed fences).
4. **Semantic coherence** — no two adjacent items make contradictory prescriptions.

**Reviewer output shape (one entry per issue):**

```json
{
  "location": "<line-number-or-section-heading>",
  "type": "ordering | duplicate | structural | semantic",
  "description": "<one-line explanation>",
  "suggested_fix": "<concrete edit>"
}
```

**Auto-apply matrix:**

- `additive-merge` — auto-apply `duplicate` and `structural` fixes only. Log `ordering` and `semantic` as suggestions in the Step 8 report (no edit).
- `additive-merge-with-diff` Pass 1 — auto-apply all four fix types.
- `additive-merge-with-diff` Pass 2 — explain-and-ask: print every issue, then a single AskUserQuestion with `Fix automatically` / `I'll handle it`.

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

All plugin-managed file content is rendered from templates under `$PLUGIN_ROOT/templates/`. Each template file maps to a manifest entry:

| Template file | Manifest `upstream_key` | Notes |
|---|---|---|
| `CLAUDE.md.tpl` | `bytewyrd/CLAUDE.md@v1` | Templated; additive-merge strategy; placeholders: `<project_name>`, `<description>`, `<project_slug>`, `<LANGUAGE_TOOLCHAIN_SECTION>`, `<AGENT_TABLE_ROWS>`, `<TOOL_USAGE_SECTION>`; conditional regions `<!--lang:*-start/end-->` |
| `README.md.tpl` | `bytewyrd/README.md@v1` | Templated; bootstrap strategy; placeholders: `<project_name>`, `<description>` |
| `BEST_PRACTICES.md.tpl` | `bytewyrd/docs/BEST_PRACTICES.md@v1` | Templated; owned-regions strategy; conditional language regions |
| `CONTRIBUTING.md.tpl` | `bytewyrd/docs/CONTRIBUTING.md@v1` | Non-templated; bootstrap strategy |
| `ARCHITECTURE.md.tpl` | `bytewyrd/docs/ARCHITECTURE.md@v1` | Non-templated; bootstrap strategy |
| `settings.json.tpl` | `bytewyrd/.claude/settings.json@v1` | Templated; structured strategy; sidecar marker |
| `settings.local.json.tpl` | `bytewyrd/.claude/settings.local.json@v1` | Non-templated; bootstrap strategy (create once, then project-owned; never updated by sync) |
| `mise.toml.tpl` | `bytewyrd/mise.toml@v1` | Templated; structured strategy |
| `.gitignore.tpl` | `bytewyrd/.gitignore@v1` | Non-templated; structured strategy |
| `ci.yml.tpl` | `bytewyrd/.github/workflows/ci.yml@v1` | Templated; additive-merge-with-diff strategy |
| `PULL_REQUEST_TEMPLATE.md.tpl` | `bytewyrd/.github/PULL_REQUEST_TEMPLATE.md@v1` | Non-templated; additive-merge-with-diff strategy |

The `rfc-process.md` source (`bytewyrd/docs/rfc-process.md@v1`) is read directly from `$PLUGIN_ROOT/rfc-process.md` (non-templated, authoritative strategy).

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
  - Always: feature-engineer (new features), code-reviewer (code reviews), rfc-architect (architecture/RFCs), docs-agent via `/docs-review` (`docs/guide/**` and `README.md`), documentation-writer (ad-hoc docs outside `docs/guide/**`), debugger (debugging)

- `<TOOL_USAGE_SECTION>`: build from installed tools. Exa and Firefox MCP are unconditional. Context7 only if `context7@claude-plugins-official` is installed. If none installed, omit the `## Tool Usage` section entirely.

**`settings.json.tpl` rendering:**

**Do NOT include `bytewyrd@bytewyrd` or `extraKnownMarketplaces.bytewyrd`.** The plugin is installed at user scope (`~/.claude/settings.json`); projects do not assert plugin enablement or marketplace registration in `.claude/settings.json`. Discoverability for new team members is handled by the CONTRIBUTING.md install-hint block (Step 5). (Teams that want project-scope enforcement can manually add `"bytewyrd@bytewyrd": true` to their `.claude/settings.json`'s `enabledPlugins` block; this is documented in `docs/guide/installation.md` but is not the default.)

**Cleanup of legacy entries (always run before writing):** Remove any pre-existing `bytewyrd@bytewyrd` entry under `enabledPlugins` and any `bytewyrd` key under `extraKnownMarketplaces`. These are forward-only migrations: pre-RFC projects had both; post-RFC projects must not. Use `jq -e 'del(.enabledPlugins["bytewyrd@bytewyrd"]) | del(.extraKnownMarketplaces.bytewyrd) | if .extraKnownMarketplaces == {} then del(.extraKnownMarketplaces) else . end'` if `jq` is available; otherwise hand-edit. The cleanup is idempotent — re-running `/sync` on a clean post-RFC project is a no-op.

**`<ENABLED_PLUGINS_ENTRIES>`** — this template variable expands to the full content of the `enabledPlugins` object (no leading `bytewyrd@bytewyrd` base entry). If no companion plugins are installed it is empty (resulting in `"enabledPlugins": {}`). Otherwise it expands to a newline-indented, comma-separated list of `"<id>": true` entries. Only include installed identifiers — an uninstalled `claude-plugins-official` plugin causes Claude Code to error on startup. Check each identifier against the `INSTALLED_PLUGINS` array collected in Step 1 (sourced from `~/.claude/plugins/installed_plugins.json`). Add `"github@claude-plugins-official": true`, `"context7@claude-plugins-official": true`, `"code-review@claude-plugins-official": true` only when the identifier appears in `INSTALLED_PLUGINS`.

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

The `docs/rfc-process.md` file is managed as a manifest artifact with `extension_strategy: "authoritative"` (upstream key `bytewyrd/docs/rfc-process.md@v1`). It is plugin-owned and overwritten automatically in Step 4a whenever the plugin's `rfc-process.md` source changes. Before the write, Step 4a checks for a `## Project Extensions` section and surfaces a warning with a single acknowledgement prompt so users can copy their customizations before they are replaced.

---

## Step 8 — Report

### Step 5.5 — Rewrite sidecar if any JSON artifact's marker advanced

Before printing the report, check whether any JSON-format artifact's marker was updated in Step 5 (i.e., `.claude/settings.json` was written with a new marker). If yes, rewrite `.bytewyrd/.bootstrap-versions.json` in full with all current marker entries. If no JSON artifact's marker changed, the sidecar is not rewritten.

Note: `.claude/settings.local.json` is now `bootstrap` strategy and does not use a sidecar marker — it is created once and left project-owned thereafter.

### Final report

Print a summary of every artifact processed, grouped by outcome category. Outcome labels by strategy:

| Strategy | Outcomes |
|----------|----------|
| `structured` | added / fast-forward applied / conflict resolved (see note) / unchanged / local-only edit preserved / unchanged (legacy marker added) |
| `additive-merge` | added / additive-merge applied (per-section summary, see below) / unchanged / deferred |
| `additive-merge-with-diff` | added / additive-merge-with-diff applied (Pass 1 fixes: N, Pass 2 outcome: applied / user-handled) / manual-3-way-pending / deferred |
| `bootstrap` | bootstrapped / local-only (existing) / deferred |
| `authoritative` | authoritative-overwritten / unchanged |
| `owned-regions` | added / fast-forward applied / conflict resolved / unchanged / local-only edit preserved |

Per-file outcomes:

| File | Strategy | Typical outcomes |
|------|----------|------------------|
| `CLAUDE.md` | additive-merge | additive-merge applied / unchanged |
| `README.md` | bootstrap | bootstrapped / local-only (existing) |
| `docs/BEST_PRACTICES.md` | owned-regions | added / fast-forward applied / conflict resolved / unchanged |
| `docs/CONTRIBUTING.md` | bootstrap | bootstrapped / local-only (existing) |
| `docs/ARCHITECTURE.md` | bootstrap | bootstrapped / local-only (existing) |
| `docs/rfc-process.md` | authoritative | authoritative-overwritten / unchanged |
| `.claude/settings.json` | structured | added / fast-forward applied / conflict resolved / unchanged |
| `.claude/settings.local.json` | bootstrap | bootstrapped / local-only (existing, never re-touched by sync) |
| `.github/workflows/ci.yml` | additive-merge-with-diff | additive-merge-with-diff applied / manual-3-way-pending / unchanged |
| `.github/PULL_REQUEST_TEMPLATE.md` | additive-merge-with-diff | additive-merge-with-diff applied / manual-3-way-pending / unchanged |
| `mise.toml` | structured | added / fast-forward applied / unchanged |
| `.gitignore` | structured | added / fast-forward applied / unchanged |
| `.worktrees/` | (non-manifest) | created / already exists |
| `docs/guide/` | (non-manifest) | created / already exists |
| `docs/project-brief.md` | (non-manifest) | created (full template) / migrated / skipped (user opted not to create) / exists |
| `docs/rfcs/.gitkeep` | (non-manifest) | created / already exists |
| `rust-toolchain.toml` | (non-manifest) | created / already exists (Rust only) |
| GitHub repo description | (non-manifest) | updated via `gh repo edit` / skipped (no remote or description) |

**Per-section breakdown for `additive-merge` files** (printed when at least one replacement or soundness fix occurred):

```
CLAUDE.md — additive-merge apply:
  ## Tool Usage      — 2 same-concept replacements, 1 new item appended, 0 soundness fixes
  ## Security        — 0 replacements, 0 appended, 1 soundness fix (duplicate removed)
  ## Conventions     — 1 same-concept replacement, 0 appended, 0 soundness fixes
  Total: 3 replacements, 1 appended, 1 soundness fix — run `git diff CLAUDE.md` to inspect
```

The `run \`git diff <path>\` to inspect` line is printed for every file that had at least one replacement or soundness fix.

**Deferred section.** List every file the user deferred at the Step 4b checkbox prompt or the Step 4c `Defer` option:

```
Deferred (N items, re-presented next run):
  - <path>
  - <path>
```

**Migration notes.** If the sidecar was relocated, print:

```
Migrated .bootstrap-versions.json: .claude/ → .bytewyrd/
```

**Manifest errors.** If any artifact's `extension_strategy` is unrecognized, print:

```
Manifest errors:
  - <path>: <error message>
```

These artifacts are not classified or applied — they require a manifest fix.

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

If `MISSING_RECOMMENDED` (from Step 1) is non-empty, print:
```
Missing plugins — not added to enabledPlugins:
  - <identifier>  →  install: /install <name>
```

For Exa (always), note:
```
Exa MCP — permissions pre-configured in settings.local.json.
If Exa is not yet set up globally, configure it as an MCP server in Claude Code settings.
```

