---
rfc: "2026-05-12-sync-enforce-github-branch-auto-delete"
title: "/sync Enforces GitHub Branch Auto-Delete Setting"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Extend `/sync` Step 6 (GitHub artifacts) to inspect the project's GitHub repository settings and ensure `delete_branch_on_merge` is enabled, bringing remote configuration under the same idempotent convention-enforcement umbrella that currently only covers local files (`CLAUDE.md`, `.gitignore`, `docs/`, `.github/`, etc.) plus the existing `gh repo edit --description` call. The new sub-step detects the GitHub remote (reusing the `git remote get-url origin` check Step 1 already performs), reads the current setting via `gh repo view --json deleteBranchOnMerge`, and — when the setting is `false` — writes `true` via `gh repo edit --delete-branch-on-merge`. The setting change is announced to the conversation before it is applied and reported in Step 8 as a categorical outcome (`already enabled` / `enabled by /sync` / `skipped (gh not authenticated)` / `skipped (repo not visible)` / `skipped (insufficient permissions)`). When `gh` is missing or the remote is not GitHub, the sub-step is silently gated out with no Step 8 row. When the user is not authenticated or the GitHub API returns a 403/404, `/sync` skips the check with an explicit line in the report — never silently mutates the remote, never errors out the whole sync.

## Should we do this?

**Yes.** Repositories created without "automatically delete head branches" enabled accumulate stale merged branches indefinitely — every PR's head branch survives the merge unless someone remembers to delete it, and "remembering" is precisely the kind of recurring small task that compounds into hundreds of dead branches in any project older than a few months. The setting exists for exactly this problem, and toggling it is a one-time action that requires the user to remember to do it at repo creation; in practice it is forgotten. The mismatch between *every* Bytewyrd project's stated convention (PRs are short-lived, branches die on merge, the worktree workflow assumes branches are reaped) and the *default* GitHub repo configuration (delete is off) is exactly the kind of drift `/sync` is designed to close.

`/sync` already enforces the local half of this convention — `.worktrees/` directories, `CLAUDE.md` workflow guidance, `.gitignore` rules — and already mutates the remote in one specific way (`gh repo edit --description` propagates the brief's description). Adding a second remote check is structurally identical: read the current state, compare to the convention, write the missing value, report the outcome. The cost is roughly 25 lines added to Step 6 of `skills/sync/SKILL.md`, one new row in the Step 8 report table, and the verification checklist. The benefit accrues to every new project and to every existing project the next time `/sync` runs.

The alternative is keeping the setting flip as informal tribal knowledge — a footnote in `CLAUDE.md` that nobody reads at the right moment. That is the worst kind of convention: stated but not enforced. This RFC ends that gap.

## Current state

`/sync` already touches the GitHub remote in exactly two places, both inside Step 6 of `skills/sync/SKILL.md`:

1. **`git remote get-url origin` detection** (Step 1, lines 47–57) — populates `github_description` (used as a Step 2 default) and is used by Step 6 to gate "is this repo on GitHub?". The detection is robust: the URL string is checked for `github.com` as a substring.
2. **`gh repo edit --description "<description>"`** (Step 6, lines 1166–1185) — propagates the description from `docs/project-brief.md` to the GitHub repo's description field. The call is guarded by: (a) the remote URL contains `github.com`, (b) `description` is non-empty, (c) the `gh` CLI is available. If any guard fails, the call is skipped and the Step 8 report records `skipped (no remote or no description)`.

**No other remote setting is touched by `/sync` today.** The "automatically delete head branches after merge" setting — surfaced in the GitHub UI under *Settings → General → Pull Requests* and stored in the API as `delete_branch_on_merge` (REST PATCH `/repos/{owner}/{repo}`, body field) or `deleteBranchOnMerge` (GraphQL via `gh repo view --json`) — defaults to `false` on every new repository. There is no automation in the bytewyrd plugin that enables it, no documentation reminder, and no checklist on `/sync` runs that surfaces its absence.

**What the user experiences today:**

- A maintainer creates a new repo on GitHub, runs `/sync` in a fresh clone — the plugin sets up `.worktrees/`, `CLAUDE.md`, `.github/workflows/ci.yml`, and updates the repo description. The branch auto-delete setting remains `false`. Three months later, the repo has accumulated 40+ merged feature branches that nobody noticed.
- The user runs `/sync` again after the plugin updates — every file is reported as `created` or `skipped (exists)`, the description is re-confirmed, but the branch-auto-delete setting is still `false`. There is no surface in the report that flags the gap.
- A user who notices the problem manually clicks the setting in the GitHub UI, or runs `gh repo edit --delete-branch-on-merge` from memory. There is no record in the project that the convention has been applied; on the next `/sync` run, nothing reads or reports the state.

**Existing structural hooks the new design will reuse:**

- The `github.com` substring check on `git remote get-url origin` already establishes the "is GitHub" gate (Step 1 and Step 6 both use it). The new sub-step reuses the same gate without adding a second detection mechanism.
- The `gh` CLI availability check (Step 6 already guards `gh repo edit` on `gh` being available) is the same precondition.
- The Step 8 report table already has a "GitHub repo description" row with the `updated / skipped` pattern. The new "GitHub branch auto-delete" row follows the identical pattern.
- The "skip cleanly when remote/auth is unavailable" rule from the existing `gh repo edit --description` call is the same rule that applies to the new sub-step. No new error-handling paradigm is introduced.

The bytewyrd plugin's `CLAUDE.md` (line 1 of the project root) lists the worktree workflow as standard practice — "feature branches are short-lived; merge to main, delete branch" — which is precisely what `delete_branch_on_merge` automates. The local-side enforcement (`.worktrees/` directory, `clean_gone` skill that prunes branches marked `[gone]`) presupposes the server-side setting being enabled; today the local side cleans up dangling references after the fact, while the server-side setting would prevent the dangling references from being created in the first place.

## Analysis / Options

Four decisions: (1) how to check and mutate the setting (which tool — GitHub MCP, `gh api`, `gh repo view` / `gh repo edit`), (2) when to mutate (silent vs. announce-then-apply vs. ask), (3) how to handle the failure modes (missing CLI, missing auth, organization-owner restriction, non-GitHub remote), and (4) whether the verification belongs inside `/sync` at all or in a dedicated sub-command (`/git-verify`, `/github-verify`).

### Decision 1 — Which tool reads and writes the setting?

**Background.** The setting has two surfaces:

- **REST API:** `GET /repos/{owner}/{repo}` returns `delete_branch_on_merge: boolean` in the response body; `PATCH /repos/{owner}/{repo}` accepts `delete_branch_on_merge: boolean` in the request body.
- **GraphQL / `gh repo view`:** `gh repo view --json deleteBranchOnMerge` returns `{"deleteBranchOnMerge": <bool>}`. (Note the JSON field name in the `gh` output is camelCase; the underlying GraphQL field is also `deleteBranchOnMerge`.)
- **`gh repo edit`:** the CLI exposes `--delete-branch-on-merge` (enable, sets to true) and `--delete-branch-on-merge=false` (disable). Internally this translates to a REST PATCH with `delete_branch_on_merge` in the body — confirmed against the `cli/cli` source at `pkg/cmd/repo/edit/edit.go` (see source: the `DeleteBranchOnMerge *bool` field maps to JSON tag `delete_branch_on_merge,omitempty`).

The GitHub MCP server (the official `github/github-mcp-server` shipped at `github@claude-plugins-official` and tracked in `installed_plugins.json`) **does not** ship a "update repository settings" tool. The `repos` toolset includes `create_repository`, `fork_repository`, `get_file_contents`, `create_or_update_file`, `delete_file`, `push_files`, `create_branch`, `list_branches`, `list_commits`, `list_tags`, `get_commit`, `get_tag`, `search_repositories` — and that is the full set. There is no `update_repository`, no `edit_repository`, no equivalent of `gh repo edit`. The closest tool, `update_pull_request`, edits a PR, not the repo. This is confirmed by surveying the deferred tool list in the current session (every `mcp__plugin_github_github__*` tool is enumerated) and by the public `github/github-mcp-server` tool catalog.

This rules out using the GitHub MCP for the *write* path. The MCP can be used for the *read* path only if there is a tool that returns repo settings — and there is not. The only MCP repos-toolset tool that returns repository-level metadata is `search_repositories`, which returns search-result snippets (name, description, stars), not the branch-auto-delete setting. The MCP is therefore unusable for both halves of this operation.

**Option A — `gh` CLI for both read and write (recommended).**

Read with `gh repo view --json deleteBranchOnMerge`; write with `gh repo edit --delete-branch-on-merge`. The CLI is already a precondition for Step 6 (it is used for `gh repo edit --description`); no new tool dependency is introduced. The CLI handles authentication via the user's logged-in `gh auth status` state; it auto-resolves the owner/repo from the current working directory's git remote; it returns clean exit codes and JSON output.

Exact commands:

```bash
# Read (returns JSON: {"deleteBranchOnMerge": true} or {"deleteBranchOnMerge": false})
gh repo view --json deleteBranchOnMerge --jq '.deleteBranchOnMerge'

# Write (enables the setting)
gh repo edit --delete-branch-on-merge
```

Both commands operate on the repo identified by the current working directory's `origin` remote (the same resolution `gh repo edit --description` already uses today).

**Option B — `gh api` for both read and write.**

Read with `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'`; write with `gh api repos/{owner}/{repo} -X PATCH -f delete_branch_on_merge=true`. This exposes the raw REST endpoint instead of going through the `gh repo edit` wrapper.

Rejected because the wrapper is the more stable surface: `gh repo edit` has been stable since 2021, its `--delete-branch-on-merge` flag is documented in the CLI manual, and it handles owner/repo resolution from the working directory automatically. The `gh api` form requires owner/repo extraction from the remote URL (an extra string-parsing step that can fail on SSH-style remotes like `git@github.com:owner/repo.git` vs HTTPS `https://github.com/owner/repo.git`). The wrapper avoids the parsing bug class entirely.

The `gh api` form is preserved as a fallback for the specific case where `gh repo edit --delete-branch-on-merge` is not available in the user's `gh` CLI version (the flag was added in 2.0; older systems may have 1.x). The fallback is described in Implementation spec.

**Option C — Direct `curl` + GitHub token from `GH_TOKEN` / `.config/gh/hosts.yml`.**

Skip the `gh` CLI entirely; use `curl` to call the REST API with the user's GitHub token.

Rejected because it requires the skill to discover and load the token from `gh`'s config file (not a public API), implement HTTP request construction, handle auth scope errors, and reimplement what `gh` already does. The marginal independence from `gh` is not worth the implementation cost; `gh` is already a hard dependency of Step 6.

**Recommendation: Option A.** The `gh repo view --json deleteBranchOnMerge --jq '.deleteBranchOnMerge'` + `gh repo edit --delete-branch-on-merge` pair is the smallest reliable surface, reuses the existing `gh` precondition, and avoids parsing the remote URL by hand.

### Decision 2 — When does `/sync` mutate the setting?

**Option A — Read first; announce-then-apply if disabled (recommended).**

Step 6 runs the read command. If the setting is already `true`, report `already enabled` and proceed (no write, no prompt). If the setting is `false`, print a one-line announcement to the conversation immediately before the write:

```
GitHub repo setting "delete_branch_on_merge" is currently disabled. Enabling now via gh repo edit --delete-branch-on-merge.
```

Then run the write command. On success, report `enabled by /sync`; on failure, report `skipped (<reason>)` and continue with the rest of Step 6 / 7 / 8.

The announcement is informational, not interactive — `/sync` does not call AskUserQuestion for this. Rationale: the convention is project-wide and well-established (every Bytewyrd project enforces it via `CLAUDE.md` workflow guidance and the `clean_gone` skill); asking the user every time would be friction without a real choice point. The user who *actively wants* the setting off is exceptional and can run `gh repo edit --delete-branch-on-merge=false` after `/sync` completes (and will see it re-enabled on the next `/sync` run — which is the correct behavior for an idempotent convention enforcer).

**Option B — Prompt the user before mutating.**

Use AskUserQuestion: "Enable 'delete_branch_on_merge' on this GitHub repo? Recommended by Bytewyrd convention. Yes / No / Skip this run."

Rejected because (a) `/sync` already mutates the GitHub description without prompting (under the same convention banner), (b) the AskUserQuestion budget of a typical `/sync` run is already dense (Step 2 alone can ask up to 4 prompts in the gap-fill flow), and (c) the announcement-then-apply pattern matches what `/sync` does for every other plugin-managed convention. Adding a prompt would be inconsistent with the existing model.

**Option C — Silent mutation, no announcement.**

Just write the setting if it's disabled; don't announce.

Rejected because the user-stated constraint in the braindump ("surface the change to the user rather than silently mutating remote settings") explicitly requires visibility. The announcement is the surface.

**Recommendation: Option A.** Read first, announce, apply if needed, report the outcome. Matches the existing `gh repo edit --description` behavior (which also runs without prompting, but the description update is naturally visible to the user as part of the Step 8 report). This distinction is intentional — auto-delete is a convention the user did not consciously choose when setting up the project, so surfacing the change to the user is appropriate; the description update, by contrast, is explicitly user-supplied content that flows through Step 2 and carries implicit user intent.

### Decision 3 — How are failure modes handled?

The mutation can fail in five distinct ways, each requiring its own handling:

1. **No GitHub remote.** `git remote get-url origin` returns a URL that does not contain `github.com` (e.g., a GitLab remote, an internal GitHost, no remote at all). Resolution: skip the entire sub-step with **no Step 8 row** — the sub-step never ran, so there is nothing to report. This is consistent with how the `GitHub repo description` row is omitted entirely when there is no GitHub remote (per the `only if GitHub=yes` condition on that row).
2. **`gh` CLI not installed.** `command -v gh` exits non-zero. Resolution: skip the entire sub-step with **no Step 8 row**. Unlike failure modes 3–5 (which occur after `gh` runs and produce an outcome row), when `gh` is absent the sub-step cannot execute at all and produces no reportable outcome. The `GitHub repo description` row is also gated on `only if GitHub=yes`; the auto-delete row goes one step further and requires `gh` to be available before a row appears at all.
3. **`gh` CLI installed but not authenticated.** `gh auth status` exits non-zero, or `gh repo view` returns "authentication required" / `401`. Resolution: skip the sub-step, report `skipped (gh not authenticated)` with a one-line follow-up hint: `Run 'gh auth login' to enable this check.`
4. **Authenticated but insufficient permissions.** The user can read the repo (the `gh repo view` call succeeds) but the write attempt returns `403 Forbidden`. The most common cause: the repo is in an organization where the authenticated user is a member, not an owner, and (per GitHub's documented API constraint) `delete_branch_on_merge=true` can be set by org admins/owners but not by regular members on some org policies. Resolution: report `skipped (insufficient permissions — must be a repo admin or org owner)`.
5. **Network or API outage.** `gh repo view` returns a non-zero exit code with a non-403 reason (5xx, network timeout, rate limit). Resolution: skip the sub-step, report `skipped (gh repo view failed — see error above)`, do not re-attempt.

In every failure mode, the sub-step **does not stop the overall `/sync` run.** Step 7 (RFC process) and Step 8 (report) still execute. The categorical skip reason is captured so the report is informative.

**Option A — Categorical skip with reasons (recommended).** When the sub-step runs (GitHub remote detected *and* `gh` is available), each outcome maps to one of these reason strings in the Step 8 row: `already enabled`, `enabled by /sync`, `skipped (gh not authenticated — run 'gh auth login')`, `skipped (repo not visible to authenticated user)`, `skipped (insufficient permissions — must be repo admin or org owner)`, `skipped (gh repo view failed: <snippet>)`, `skipped (gh repo edit failed: <snippet>)`. When the sub-step is gated out entirely (no GitHub remote, or `gh` unavailable), **no row appears** — there is no outcome to report. The user sees exactly what happened when the sub-step ran; silence means it was not applicable.

**Option B — Single `skipped` outcome with a generic reason.** All failure modes collapse to one row: `skipped (could not verify)`.

Rejected because the user has no way to differentiate "I forgot to log in" from "I'm not an org owner" — the resolution is completely different. Categorical reasons direct the user to the next action.

**Option C — Treat permission failures as fatal.** If the user cannot write the setting, `/sync` halts with an error.

Rejected because the whole `/sync` flow is structured to be idempotent and partial-success-friendly. A user who runs `/sync` on a fork they can read but not write should still get every other benefit of the sync.

**Recommendation: Option A.** Categorical skip reasons. The categorization is implemented in the SKILL.md additions and reported per-category in Step 8.

### Decision 4 — Should verification concerns be split into dedicated sub-commands?

A reasonable design question: rather than bundling all verification and enforcement behind `/sync`, should the plugin expose focused sub-commands like `/git-verify` (local git conventions) and `/github-verify` (remote GitHub settings)? Each would have a single, clearly-scoped purpose, and the developer's workflow would compose them as needed.

**Option A — Keep everything in `/sync` (recommended).**

`/sync` is already the idempotent project-bootstrapping convention enforcer. Its job is precisely to take a project and bring it up to all Bytewyrd conventions in a single pass — local files, remote settings, RFC scaffolding, CI workflows. Adding a sub-step for `delete_branch_on_merge` follows the exact same pattern as the existing `gh repo edit --description` call: read current state, compare to convention, apply the fix, report the outcome. The mental model the user already has of `/sync` ("one command brings a project fully up to convention") is preserved.

Creating separate `/git-verify` and `/github-verify` commands would fragment the developer workflow. Instead of one command that brings a project fully up to convention, users would need to remember to run multiple commands — `/sync`, then `/git-verify`, then `/github-verify`, possibly in some specific order, possibly with overlapping responsibilities. The value of `/sync` is that it is comprehensive and idempotent; splitting it reduces that value. The user has to know less when there is one entry point, not three.

**Option B — Add dedicated `/git-verify` and `/github-verify` sub-commands.**

These could serve as focused "check only, don't mutate" verification passes, separate from `/sync`'s "check and fix" mode. A user could run `/github-verify` on a PR review to confirm a project's settings without applying changes, or in CI to audit drift.

Rejected for this RFC: the braindump's use case is **enforcement**, not audit-only verification, and enforcement belongs in `/sync` (where fixes are also applied). The audit-only use case is real but distinct from this RFC's scope — it can be a future RFC that introduces either a `/sync --check` mode (which audits without mutating) or a dedicated `/github-verify` command. Either approach can be designed cleanly once the underlying state-reading logic exists in `/sync`; introducing it here would conflate two concerns.

**Recommendation: Option A.** Keep the new sub-step inside `/sync`. The decomposition into focused verify-only commands is a reasonable future direction (a dedicated `/github-verify` or a `/sync --check` mode that audits without mutating) and is captured here as a possible follow-up RFC, but it is out of scope for this one.

## Drawbacks

- **Adds 25–30 lines to `skills/sync/SKILL.md` Step 6 plus one row to the Step 8 report.** The skill body is already 1449 lines; growth is modest but real. **Mitigation:** the new sub-step is self-contained (it has no cross-references to other Step 6 logic and does not entangle with the `.github/*` file-creation logic that dominates Step 6), so the addition reads as a discrete block. The skill body is structured by step number; adding one bullet at the top of Step 6 does not increase cognitive load for the rest of the file.

- **Depends on `gh` CLI being installed and authenticated.** Users without `gh` (rare in Bytewyrd workflows, but possible in CI containers or fresh dev machines) get the skip path. **Mitigation:** the skip is graceful and the report explicitly tells the user how to fix it (`Run 'gh auth login' to enable this check.`). The existing `gh repo edit --description` step has the same dependency, so this RFC does not introduce a new requirement — it shares the existing one.

- **The mutation is silent in the sense that `/sync` does not ask for explicit confirmation.** A user who wanted the setting off and ran `/sync` will see it flipped back on. **Mitigation:** the announcement line ("Enabling now...") is printed before the write, giving the user a chance to abort the run (Ctrl-C) before the mutation lands. The Step 8 report records `enabled by /sync` so the change is traceable. The user who has a genuine reason to keep auto-delete disabled (e.g., a long-lived archive repo) can document the exception in `docs/project-brief.md` and request a future RFC to add a per-project opt-out flag — out of scope for this RFC.

- **Cannot enable the setting on org repos where the user lacks admin rights.** GitHub's REST API restricts `delete_branch_on_merge=true` on some org-owned repos to org owners/admins. **Mitigation:** the categorical skip reason (`skipped (insufficient permissions — must be repo admin or org owner)`) tells the user exactly why, and the user can ask their org admin to flip the setting once. After the admin enables it, future `/sync` runs report `already enabled` and never re-prompt.

- **The GitHub MCP cannot perform the write.** This RFC commits to `gh` CLI for the write path, which means if a future plugin update wires `/sync` to use the GitHub MCP for *other* operations (e.g., creating issues, opening PRs), this sub-step remains on the CLI. **Mitigation:** when the GitHub MCP adds an `update_repository` tool (proposed in [github/github-mcp-server#1476](https://github.com/github/github-mcp-server/issues/1476) and adjacent issues — the MCP team has explicitly expressed interest in repo-settings tooling), the implementation in SKILL.md can switch transparently. The classification matrix in Implementation spec preserves the option to swap tools without changing the user-facing report.

- **Adds latency to `/sync` Step 6.** Two `gh` API round-trips (one read, one write — when the write is needed) add ~500ms–2s per run. **Mitigation:** Step 6 already includes one `gh repo edit --description` call; adding one more read and (conditionally) one more write is incremental. `/sync` is interactive and not on a hot path.

- **Claude Code sandbox compatibility: the `gh` CLI writes cache/session files to `~/.cache/gh`.** In Claude Code's default sandbox (bwrap/bubblewrap), this path may not be writable, causing `gh` commands to fail with misleading errors (often surfacing as "authentication required" or generic network errors rather than as a sandbox permission denial). **Mitigation:** the Implementation spec includes a "Claude Code sandbox accommodation" subsection that documents the required `.claude/settings.local.json` change (adding `"gh *"` to `sandbox.excludedCommands`). This is a manual, user-local step (`settings.local.json` is gitignored), so it must be communicated as part of rollout — the SKILL.md instructions can detect sandbox-related failures and direct the user to the accommodation, but cannot auto-apply it.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/sync/SKILL.md` | Add a new sub-step "GitHub branch auto-delete" inside Step 6, immediately after the existing "GitHub repository metadata" sub-section (lines 1166–1185 of the current SKILL.md). Update the Step 8 report table to include one new row for the auto-delete outcome. |
| Modify | `docs/BEST_PRACTICES.md` | Add one bullet to the existing `## Workflow` section noting that `/sync` enforces `delete_branch_on_merge=true`. (One-line note; no new section.) Suggested text: `**[YYYY-MM-DD]** _Workflow_: \`/sync\` automatically enables GitHub's "delete branch on merge" setting (\`delete_branch_on_merge=true\`) on every project — no manual toggle needed.` |

No new files are created. No files are deleted. The change is additive to existing files.

### Exact additions to `skills/sync/SKILL.md`

The new sub-step is inserted into Step 6 immediately after the existing **`### GitHub repository metadata`** subsection (i.e., after the paragraph that currently ends with `... any pre-existing GitHub description is left untouched.` at line 1185 of the current SKILL.md). The new subsection is a sibling at the same H3 level, before the existing `### .github/workflows/ci.yml` subsection.

The literal text to insert:

```markdown
### GitHub branch auto-delete setting

If the remote is a GitHub repo (the same `github.com` URL check used by the description update above), ensure the repository's `delete_branch_on_merge` setting is `true`. The Bytewyrd worktree workflow expects feature branches to be deleted on merge; this setting automates that on the server side and is the counterpart to the local-side `/clean_gone` skill that reaps `[gone]` branches.

**Skip the entire sub-step (no read, no write, no report row) when any of the following is true:**

- The remote URL does not contain `github.com` (the same check that gates the description update).
- The `gh` CLI is unavailable (`command -v gh` exits non-zero).

In both skip-entirely cases, do not record any outcome in the Step 8 report row for this sub-step — there is no row to fill in because the sub-step never ran. The sub-step's report row only exists when a GitHub remote *and* `gh` are both present.

**When both gates pass, run the read command:**

```bash
gh repo view --json deleteBranchOnMerge --jq '.deleteBranchOnMerge' 2>&1
```

Capture stdout, stderr, and exit code. Classify the outcome and proceed:

| Read outcome | Step 8 outcome | Action |
|--------------|----------------|--------|
| Exit 0, stdout is `true` | `already enabled` | No write. Report and continue. |
| Exit 0, stdout is `false` | (proceed to write) | Run the write command below. |
| Exit non-zero, stderr mentions `authentication` / `Not authenticated` / `gh auth login` | `skipped (gh not authenticated — run 'gh auth login')` | No write. Report and continue. |
| Exit non-zero, stderr mentions `404` / `Could not resolve` / `Not Found` | `skipped (repo not visible to authenticated user)` | No write. Report and continue. |
| Exit non-zero, any other reason | `skipped (gh repo view failed: <first 80 chars of stderr>)` | No write. Report and continue. |

**Announce and write** (only when the read returned exit 0 and stdout is `false`):

Print one line to the conversation immediately before the write call:

```
GitHub repo setting "delete_branch_on_merge" is currently disabled. Enabling now via gh repo edit --delete-branch-on-merge.
```

Then run the write command:

```bash
gh repo edit --delete-branch-on-merge 2>&1
```

Capture stdout, stderr, and exit code. Classify the outcome:

| Write outcome | Step 8 outcome |
|---------------|----------------|
| Exit 0 | `enabled by /sync` |
| Exit non-zero, stderr mentions `403` / `Forbidden` / `must have admin rights` / `Must have admin` / `must be an organization owner` | `skipped (insufficient permissions — must be repo admin or org owner)` |
| Exit non-zero, stderr mentions `unknown flag` / `unknown option` (older `gh` versions) | (fall back to `gh api` — see below) |
| Exit non-zero, any other reason | `skipped (gh repo edit failed: <first 80 chars of stderr>)` |

**Fallback for older `gh` versions** (the `--delete-branch-on-merge` flag was added in `gh` 2.0; users on `gh` 1.x will see `unknown flag`):

```bash
# Resolve owner/repo from the gh CLI itself (handles both SSH and HTTPS remotes)
owner_repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/$owner_repo" -X PATCH -f delete_branch_on_merge=true 2>&1
```

Classify the fallback's exit code with the same rules as the `gh repo edit` write outcome (403 → insufficient permissions, exit 0 → enabled, else → failed). The Step 8 report row uses the same outcome strings — the user does not see which path was taken.

**Idempotence:** the read happens first on every `/sync` run; if the setting is already `true`, the write is never attempted. Re-running `/sync` on a fully-up-to-date repo produces the `already enabled` row and no API mutation.

**Permissions note:** the `gh` CLI inherits the user's token scope. The required token scope for the write is `repo` (full repo access); the read works with any token that can see the repo (`repo` or, for public repos, `public_repo` / no scope at all). If the user has only `public_repo` and the repo is private, the read fails with the "repo not visible" outcome above and no write is attempted. This is correct behavior — `/sync` cannot mutate what it cannot read.
```

(End of new sub-section. The existing `### .github/workflows/ci.yml` H3 follows immediately after.)

### Claude Code sandbox accommodation

Claude Code runs commands inside a bwrap (bubblewrap) sandbox that restricts filesystem writes by default. The `gh` CLI writes session/cache state to `~/.cache/gh` (token cache, response cache, update-check timestamps). If `~/.cache/gh` is not in the sandbox's allowed-write paths, `gh repo view` and `gh repo edit` may fail with permission errors that look like authentication failures rather than sandbox errors. This makes the failure mode hard to diagnose: the user sees `skipped (gh not authenticated — run 'gh auth login')` even when `gh auth status` outside the sandbox reports success.

**The fix is to add `gh` to `sandbox.excludedCommands` in `.claude/settings.local.json`.** The exact snippet:

```json
{
  "sandbox": {
    "excludedCommands": ["gh *"]
  }
}
```

**Important conventions for this entry:**

- Use the wildcard form `"gh *"` (with a trailing space and `*`), not the bare `"gh"`. This matches the existing pattern documented in `docs/BEST_PRACTICES.md` for wrapper scripts (`"./run *"`, `"./deploy *"`) and is required for arguments to be passed through.
- Keep this configuration in `settings.local.json` (gitignored, user-local), **not** `settings.json` (checked in, shared). Sandbox accommodations are per-user environmental concerns, not project conventions.
- Alternative (less preferred): add `~/.cache/gh` to the sandbox's `filesystem.allowWrite` paths. This is more surgical but does not cover other paths `gh` may write (state files under `~/.config/gh`, temporary files in `$TMPDIR`). The `excludedCommands` approach is simpler and more robust.

**This is a manual, user-local step** that the SKILL.md implementation cannot auto-apply (`.claude/settings.local.json` is gitignored, so it must be edited by each user on each machine). The SKILL.md instructions should document this as part of the sub-step's preconditions: if `gh` commands fail with what appear to be authentication errors inside `/sync` but succeed when run outside the Claude Code sandbox, the user should add the `"gh *"` exclusion to `.claude/settings.local.json` and re-run `/sync`.

The Step 8 report's `skipped (gh not authenticated — ...)` row should include a hint pointing users to this accommodation when sandbox-related failures are suspected. A pragmatic implementation: if the read fails with auth-style errors AND `gh auth status` invoked separately reports success, the report row's hint should read `Run 'gh auth login' to enable this check, or add "gh *" to sandbox.excludedCommands in .claude/settings.local.json if running inside Claude Code's sandbox.` (Detecting this discrepancy is best-effort; the SKILL.md prose should describe the symptom — auth error inside sandbox but `gh` works outside — so the user can self-diagnose even if the heuristic does not catch every case.)

### Exact additions to the Step 8 report

The current Step 8 report table (lines 1411–1431 of SKILL.md) has a row for `GitHub repo description`. Add one new row immediately below it:

```markdown
| GitHub branch auto-delete | `already enabled` / `enabled by /sync` / `skipped (gh not authenticated — run 'gh auth login')` / `skipped (repo not visible to authenticated user)` / `skipped (insufficient permissions — must be repo admin or org owner)` / `skipped (gh repo view failed)` / `skipped (gh repo edit failed)` — only if GitHub=yes and `gh` is available |
```

The row is omitted entirely when the entire sub-step was skipped (no GitHub remote, or `gh` unavailable) — consistent with how the existing `GitHub repo description` row is conditional on the same gates.

### Pseudocode for the implementer

The skill body is prose-driven (it instructs the agent in English); the following pseudocode captures the control flow for the implementer who edits SKILL.md:

```
# Preconditions (already established earlier in Step 6 / Step 1):
remote_url = $(git remote get-url origin 2>/dev/null)
gh_available = command -v gh >/dev/null 2>&1
github_remote = remote_url contains "github.com"

# Gate the sub-step
if not github_remote or not gh_available:
    # Sub-step is entirely skipped — no Step 8 row.
    pass
else:
    # Read current setting
    read_output, read_exit = gh repo view --json deleteBranchOnMerge --jq '.deleteBranchOnMerge'

    if read_exit == 0 and read_output.strip() == "true":
        report_row = "already enabled"
    elif read_exit == 0 and read_output.strip() == "false":
        print "GitHub repo setting \"delete_branch_on_merge\" is currently disabled. Enabling now via gh repo edit --delete-branch-on-merge."
        write_output, write_exit = gh repo edit --delete-branch-on-merge

        if write_exit == 0:
            report_row = "enabled by /sync"
        elif write_exit != 0 and "unknown flag" in write_output:
            # Fallback for older gh CLI versions
            owner_repo, _ = gh repo view --json nameWithOwner --jq '.nameWithOwner'
            fb_output, fb_exit = gh api "repos/{owner_repo}" -X PATCH -f delete_branch_on_merge=true
            if fb_exit == 0:
                report_row = "enabled by /sync"
            elif "403" in fb_output or "Forbidden" in fb_output or "admin" in fb_output:
                report_row = "skipped (insufficient permissions — must be repo admin or org owner)"
            else:
                report_row = "skipped (gh repo edit failed: " + first_80_chars(fb_output) + ")"
        elif "403" in write_output or "Forbidden" in write_output or "admin" in write_output or "organization owner" in write_output:
            report_row = "skipped (insufficient permissions — must be repo admin or org owner)"
        else:
            report_row = "skipped (gh repo edit failed: " + first_80_chars(write_output) + ")"
    elif read_exit != 0 and ("authentication" in read_output or "Not authenticated" in read_output or "gh auth login" in read_output):
        report_row = "skipped (gh not authenticated — run 'gh auth login')"
    elif read_exit != 0 and ("404" in read_output or "Could not resolve" in read_output or "Not Found" in read_output):
        report_row = "skipped (repo not visible to authenticated user)"
    else:
        report_row = "skipped (gh repo view failed: " + first_80_chars(read_output) + ")"

    # Append the row to the Step 8 report's GitHub block.
```

The implementer pastes this control flow into the SKILL.md addition as Markdown prose with the embedded commands and the table. The pseudocode above is for review clarity; it is not embedded verbatim in the SKILL.md (the SKILL.md is the agent-readable instructions, not Python).

### Exact user-facing output

**Case 1: setting was already enabled.**

The conversation shows nothing during Step 6 (this sub-step prints nothing when the read returns `true`). The Step 8 report row reads:

```
GitHub branch auto-delete  already enabled
```

**Case 2: setting was disabled and `/sync` enabled it.**

During Step 6, between the description-update line and the start of `.github/` file creation, the conversation prints:

```
GitHub repo setting "delete_branch_on_merge" is currently disabled. Enabling now via gh repo edit --delete-branch-on-merge.
```

After the write succeeds, the next interactive output is the start of `.github/` file creation (no additional confirmation). The Step 8 report row reads:

```
GitHub branch auto-delete  enabled by /sync
```

**Case 3: user is not authenticated (`gh auth status` fails or read returns auth error).**

During Step 6, no announcement line is printed (the read fails before the announcement code is reached). The Step 8 report row reads:

```
GitHub branch auto-delete  skipped (gh not authenticated — run 'gh auth login')
```

**Case 4: user lacks repo admin / org owner rights to set the value.**

During Step 6, the announcement line *is* printed (the read succeeded with `false`, so `/sync` attempts the write). The write fails with 403. The Step 8 report row reads:

```
GitHub branch auto-delete  skipped (insufficient permissions — must be repo admin or org owner)
```

The user sees both the announcement and the report row — they know `/sync` tried, and they know why it could not complete.

**Case 5: non-GitHub remote (e.g., GitLab) or no `gh` CLI installed.**

The sub-step is gated out entirely. No announcement, no report row. Step 8's GitHub block lists only the rows for sub-steps that actually ran — consistent with how `GitHub repo description` is omitted today when no GitHub remote is detected.

### Verification

After implementing, run these checks. The first three exercise the happy path on a real GitHub repo; the rest exercise the failure modes.

1. **Already-enabled idempotence.** In a GitHub repo where `delete_branch_on_merge=true` is already set, run `/sync`. Expected: no announcement line in Step 6; Step 8 report row reads `GitHub branch auto-delete  already enabled`. No `gh repo edit` call is made (verify by running with `GH_DEBUG=1` and checking the `gh` log).

2. **Enable on a fresh repo.** Create a new GitHub repo (with the default `delete_branch_on_merge=false`). Clone it. Run `/sync`. Expected: announcement line is printed during Step 6; `gh repo view --json deleteBranchOnMerge --jq '.deleteBranchOnMerge'` after the run returns `true`; Step 8 report row reads `GitHub branch auto-delete  enabled by /sync`. Re-run `/sync`. Expected: this run reports `already enabled` (verifies idempotence after the first enable).

3. **Older `gh` fallback.** With `gh` 1.x installed (or with the `--delete-branch-on-merge` flag artificially stripped via `gh_path=mock-gh`), run `/sync` on a repo with the setting disabled. Expected: the primary `gh repo edit --delete-branch-on-merge` call exits non-zero with "unknown flag"; the fallback `gh api repos/{owner_repo} -X PATCH -f delete_branch_on_merge=true` runs and succeeds; Step 8 reports `enabled by /sync`.

4. **No GitHub remote.** Create a repo with only a GitLab or a non-GitHub remote (`git remote add origin git@gitlab.com:foo/bar.git`). Run `/sync`. Expected: no announcement, no report row for `GitHub branch auto-delete`. The Step 8 GitHub block still shows other rows that are gated on different conditions (e.g., the description update is also gated out, but the row for it is also omitted).

5. **No `gh` CLI.** Temporarily remove `gh` from `$PATH` (`PATH=$(echo $PATH | sed 's|:[^:]*github-cli[^:]*||g')`). Run `/sync`. Expected: no announcement, no report row for `GitHub branch auto-delete`. The Step 8 GitHub block similarly omits the description row.

6. **Not authenticated.** Run `gh auth logout`. Run `/sync` on a GitHub repo. Expected: announcement is NOT printed (read fails before it). Step 8 row reads `skipped (gh not authenticated — run 'gh auth login')`.

7. **Insufficient permissions (org repo as non-admin).** Find or create an org repo where the authenticated user is a regular member but not an owner/admin, with `delete_branch_on_merge=false`. Run `/sync`. Expected: announcement line is printed (read succeeded, value is `false`); `gh repo edit` returns 403; Step 8 row reads `skipped (insufficient permissions — must be repo admin or org owner)`.

8. **Read failure on private repo without scope.** Run `gh auth refresh -s public_repo` (downgrade scope). Run `/sync` on a private repo. Expected: read returns 404 (the repo is invisible at this scope); Step 8 row reads `skipped (repo not visible to authenticated user)`.

9. **Network outage simulation.** With `gh` configured to point at a non-resolving host (e.g., `GH_HOST=invalid.example.com`), run `/sync`. Expected: read fails with a network-level error; Step 8 row reads `skipped (gh repo view failed: <error snippet>)`. The first 80 characters of stderr are visible in the row so the user can diagnose.

10. **Sub-step does not stop the rest of `/sync`.** Force any failure case (4 through 9). Verify that Step 7 (RFC process sync) and the rest of Step 8 (file outcome rows) still execute. Specifically: the `docs/rfc-process.md` file is still synced, the `.github/workflows/ci.yml` is still created if missing, and the final Step 8 report still prints.

11. **Sandbox accommodation.** Inside Claude Code's sandbox without the `"gh *"` exclusion, run `/sync` on a GitHub repo where `gh auth status` (outside the sandbox) confirms authentication. Expected: the read may fail with what appears to be an authentication error; the user follows the documented accommodation (add `"gh *"` to `sandbox.excludedCommands` in `.claude/settings.local.json`); re-run `/sync`. Expected: the sub-step now completes normally and the Step 8 row reads `already enabled` or `enabled by /sync` depending on prior state.

If any verification step fails, the failure points to one of: (a) the gate logic is wrong (the sub-step runs when it should not, or skips when it should not), (b) the categorization of `gh` stderr is wrong (a specific failure does not match the substring patterns), (c) the write happens despite the read returning `true` (idempotence bug), or (d) a failure case halts the overall `/sync` run (the sub-step is leaking exceptions instead of skipping cleanly).

### Compatibility check: existing `gh repo edit --description` call

The new sub-step runs *after* the existing `gh repo edit --description "<description>"` call inside Step 6. The two calls are independent: one mutates the description field, the other mutates the `delete_branch_on_merge` field. The GitHub PATCH `/repos/{owner}/{repo}` endpoint accepts both fields in the same body, but `gh repo edit` issues a separate PATCH per invocation. The implementation keeps the two calls separate (matching the current Step 6 structure of "one sub-section per mutation") rather than batching them, because:

- The two calls have different skip conditions (description is gated on `description` being non-empty; auto-delete has no analogous content gate).
- The two calls have different failure modes (description failure does not block auto-delete; auto-delete failure does not block description).
- Batching them would require restructuring the existing description-update flow, which is out of scope.

The two PATCHes incur a total of ~1–2 seconds extra latency per `/sync` run when both fire. This is acceptable; `/sync` is interactive and not on a hot path.

## Risks and open questions

- **Risk: `gh` stderr string-matching is brittle.** The implementation classifies failures by substring matching on stderr (`403`, `Forbidden`, `must be an organization owner`, etc.). If `gh` changes its error messages in a future release, the classification could fall into the catch-all `skipped (gh repo edit failed: ...)` bucket and lose the more-specific reason. **Mitigation:** the catch-all bucket includes the first 80 characters of stderr, so the user can read the actual error and act on it. The categorization is best-effort, not load-bearing. If a future `gh` version produces a structured error response (JSON), the implementation can switch to parsing it; this RFC does not depend on `gh` ever emitting JSON errors.

- **Risk: GitHub Enterprise Server (GHES) endpoints differ.** A user on GHES runs `gh` against an internal GitHub instance. The REST endpoint and field name are identical (`delete_branch_on_merge`); the `gh` CLI handles GHES via `GH_HOST` automatically. **Mitigation:** the implementation does not need to special-case GHES — `gh` abstracts it away. The `github.com` substring check in the remote URL works for `github.com` repos; GHES users have a different host (e.g., `github.acme.com`) and would currently fall into the "no GitHub remote" gate and be skipped. **Resolution within this RFC:** out of scope. If GHES support is needed, a future RFC can broaden the gate to "any host running GitHub" by reading `gh auth status --hostname` or by accepting a config flag. This RFC keeps the gate aligned with the existing `gh repo edit --description` gate (also `github.com`-only today).

- **Risk: organization policy explicitly disables `delete_branch_on_merge` at the org level.** Some GitHub Enterprise orgs centrally enforce that the setting must be off (rare but possible). In that case, `gh repo edit --delete-branch-on-merge` either silently no-ops or returns a specific error. **Mitigation:** the implementation classifies this under `skipped (insufficient permissions)` if a `403` is returned, or under the catch-all bucket if the API silently accepts the call but does not change the value. The verification checklist test 7 covers the 403 path. The "silent no-op" path is not testable without an org that exhibits the behavior; the catch-all reporting (with the actual stderr snippet) is the user's safety net.

- **Risk: rate limit.** Each `/sync` run consumes 1–2 API calls (one `gh repo view`, conditionally one `gh repo edit`). For a developer running `/sync` ~10 times a day, that is well under the 5000-requests-per-hour authenticated rate limit. **Mitigation:** none needed.

- **Open question: should the announcement be a configurable verbosity level?** A user who runs `/sync` daily on the same repo and consistently sees `already enabled` may want to suppress the report row for clarity. **Resolution within this RFC:** keep the row always-on. The row is one line in a report that already lists ~15+ files; the marginal noise is negligible. If a future RFC introduces a `--quiet` flag for `/sync`, the auto-delete row can be collapsed into the unchanged summary; that is a separate concern.

- **Open question: should `/sync` also report any pre-existing merged-branches that need cleanup (a one-time backfill of branches the setting did not delete because it was off)?** That would be a separate "list stale branches and offer to delete them" operation. **Resolution within this RFC:** out of scope. The existing `clean_gone` skill (`commit-commands:clean_gone`) already handles the local-side cleanup of `[gone]` branches; the GitHub-side backfill is a different problem and would require a new skill (`/github-cleanup-merged-branches` or similar). Captured as a follow-up in the braindump.

- **Open question: should `/sync` also enforce `allow_squash_merge` / `allow_rebase_merge` / `allow_merge_commit` settings?** Bytewyrd projects use `squash` as the merge method (per `CLAUDE.md` workflow guidance: "Squash merge to keep history clean"). The repo settings for which merge types are allowed could be similarly enforced. **Resolution within this RFC:** out of scope. This RFC focuses on `delete_branch_on_merge` because the braindump explicitly named it. Enforcing merge-type settings is a separate convention check; a follow-up braindump can capture it.

- **Open question: should the sub-step be opt-in via a project flag (e.g., a line in `docs/project-brief.md` or `.claude/settings.json`)?** A user whose project is an archive (frozen content, no active PRs) might prefer to leave the setting off. **Resolution within this RFC:** keep the sub-step always-on by default. Per the analysis above, the cost of being wrong (a project that has the setting wrongly enabled) is near-zero — the user can just disable it manually after `/sync` completes. The cost of being wrong in the other direction (a project that needed the setting and never got it) is the accumulation problem the RFC is solving. The defaults favor enforcement. A future RFC can add an opt-out flag if real cases emerge.

- **Risk: the bytewyrd plugin ships to projects on a wide range of `gh` versions.** Verification step 3 covers the fallback to `gh api` for older `gh`. If a user is on `gh` 0.x (very old, pre-`gh repo edit` entirely), the fallback also fails. **Mitigation:** the catch-all `skipped (gh repo edit failed: ...)` row surfaces the issue, and the user is on a sufficiently old toolchain that upgrading `gh` is the right answer. This is not a meaningful population.

## Relationship to other RFCs

- **`2026-05-10-sync-interactive-diff`** (status: Draft) — proposes replacing `/sync`'s silent-skip behavior with a categorized three-way diff and confirmation flow. This RFC's new sub-step is structurally independent of the diff engine (it operates on remote state, not local files), but the Step 8 report format is shared. If the interactive-diff RFC lands first, the `GitHub branch auto-delete` row appears in the new categorized report under a new "Remote settings" category; if this RFC lands first, the row appears in the current Step 8 table. Either order works; no merge conflict at the SKILL.md level beyond a small report-table reformat.

- **`2026-05-10-project-brief-sync-source-of-truth`** (status: Done) — established `docs/project-brief.md` as the source of truth for project identity, with `/sync` propagating `description` to GitHub via `gh repo edit --description`. This RFC follows the same pattern for a different remote setting; the two are siblings under the same "Step 6 — GitHub artifacts" umbrella.

- **`commit-commands:clean_gone` skill** — locally prunes branches marked `[gone]` (branches the remote no longer has). This RFC's setting (`delete_branch_on_merge=true`) ensures the remote *creates* the `[gone]` state in the first place (by deleting the head branch after merge), so the two work together: the server-side setting reaps remote branches; `/clean_gone` reaps the local pointers. This RFC does not modify `clean_gone`; it just removes the need for the user to remember to delete branches via the PR UI.

- **Future RFC — GitHub merge-type policy enforcement** (potential braindump entry) — would extend `/sync` to enforce `allow_squash_merge=true`, `allow_rebase_merge=false`, `allow_merge_commit=false` per Bytewyrd's "squash merge to keep history clean" convention. The implementation pattern in this RFC (read → categorize → announce → write → categorize outcome) is directly reusable. This RFC does not implement merge-type enforcement; it just demonstrates the pattern.

- **Future RFC — bulk backfill of stale merged branches** (mentioned in Risks and open questions) — would add a separate skill that, on demand, lists branches whose PRs have been merged but the branch still exists on the remote, and offers to delete them. This RFC does not address backfill; new repos and repos that get the setting flipped today will accumulate cleanly going forward. The backfill is a separate concern.

- **Future RFC — `/sync --check` mode or dedicated `/github-verify` command** (potential follow-up) — would introduce an audit-only mode that reads and reports remote settings without mutating them, useful for CI checks and PR reviews. This RFC's Decision 4 explicitly leaves this design space open: the underlying read logic introduced here would be directly reusable by an audit-only entry point. Scope, ergonomics, and naming (`/sync --check`, `/github-verify`, or a focused split into `/git-verify` + `/github-verify`) are intentionally deferred.
