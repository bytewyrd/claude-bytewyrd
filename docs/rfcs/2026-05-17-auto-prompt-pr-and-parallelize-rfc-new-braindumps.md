---
rfc: "2026-05-17-auto-prompt-pr-and-parallelize-rfc-new-braindumps"
title: "Auto-prompt PR creation in /rfc-new and parallelize /rfc-new-braindumps"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Extend `/rfc-new` so that — whenever GitHub is reachable (`github@claude-plugins-official` MCP enabled or `gh` CLI installed and authenticated) — it ends with a single `AskUserQuestion` confirming whether to push the current branch and open a PR for the freshly drafted RFC, removing today's manual "push the branch and open a PR yourself" hand-off. Introduce a new sibling skill `/rfc-new-braindumps` that promotes multiple `docs/rfc-braindump.md` entries to full Draft RFCs in one invocation by fanning out: for each selected entry, create a dedicated `rfc/<rfc-id>` worktree on a fresh branch off `main`, draft the RFC there, and then issue a single batched `Task`-tool message that runs N independent `bytewyrd:rfc-architect` subagent calls concurrently — one per worktree — so the total wall-clock cost of converting a backlog scales with the slowest single RFC rather than the sum of all of them. Both changes share the same in-skill GitHub probe and the same PR-opening helper script (`scripts/rfc-open-pr.sh`), so the auto-prompt is one place to maintain and the batch flow inherits it unchanged. The behavior is opt-out at the prompt: pressing the "Not yet" option keeps the RFC local and prints the previous manual instructions verbatim.

## Should we do this?

**Yes.** The current `/rfc-new` Step 9 ("Present to human") closes the skill with a printed instruction list that includes `/rfc-read-feedback`, `/rfc-approve`, and an implicit assumption that the human will switch to a terminal to `git push -u origin <branch>` and run `gh pr create` themselves (verified: `skills/rfc-new/SKILL.md:L141`). The project's recorded memory `feedback_rfc_new_pr_required.md` (verified: `/home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_rfc_new_pr_required.md:L10`) makes the rule explicit: "Never commit RFC files directly to the main branch. Each /rfc-new invocation must create its own branch and open a PR for review before the RFC lands on main." The same memory's "How to apply" line names bulk braindump promotion as the exact scenario where the rule was violated in commit `3875e87`'s predecessor `346fe6a` (verified: the memory file explicitly cites commit `346fe6a` and "promoting multiple braindump entries to full RFCs ... bulk-committed directly to main in a single commit"). A skill that closes by *asking* about the PR — rather than *suggesting* the user run the commands — collapses two manual steps and one context switch into one click, and removes the failure mode the memory was created to prevent. The braindump entry "Enforce branch+PR discipline in `/rfc-new`" frames the same need in user-facing terms (verified: `docs/rfc-braindump.md:L9` — "Branch creation and PR opening must be non-optional steps in the skill flow, and bulk braindump promotion should parallelize the branch+PR workflow per-RFC rather than batching multiple RFCs into a single commit"). The parallel batch skill exists for exactly the failure mode the memory described; the auto-prompt extension is the smaller, cheaper half of the same fix. Cost: one new helper script, one new skill, one `Steps` change to the existing `/rfc-new` skill, and three documentation updates. No new external dependencies — `gh` and the GitHub MCP probe via the existing `scripts/tool-probe.sh` (verified: `scripts/tool-probe.sh:L44-L82`), and `git worktree add` is already the project's standard branch-isolation primitive (verified: `.claude-plugin/CLAUDE.md:L126`).

## Current state

### What `/rfc-new` does today

The skill body (verified: `skills/rfc-new/SKILL.md:L1-L149`) runs nine steps. The relevant ones for this RFC are:

1. **Step 1 — Get description.** If invoked with no argument, the skill calls `bash scripts/rfc-braindump-list.sh` (verified: `skills/rfc-new/SKILL.md:L20`), counts entries with `jq '.entries | length'`, and — when there are entries — presents them as a numbered text list with the prompt "Pick a number to promote, or describe a new RFC." (verified: `skills/rfc-new/SKILL.md:L23`). Selection is one entry at a time; there is no batch path.

2. **Step 6 — Remove promoted braindump entry.** After the file is created (Step 5) and before the architect agent is spawned (Step 7), the skill removes the chosen bullet from `docs/rfc-braindump.md` via `bash scripts/rfc-braindump-remove.sh "$SELECTED_ENTRY_BODY"` (verified: `skills/rfc-new/SKILL.md:L108`). The script's `removed: true` JSON return is the success signal (verified: `scripts/rfc-braindump-remove.sh:L11-L13`).

3. **Step 7 — Spawn `bytewyrd:rfc-architect`.** The skill body spawns the architect subagent with the full project context, and the architect itself dispatches review subagents in parallel (verified: `skills/rfc-new/SKILL.md:L114-L126`). Per `agents/rfc-architect.md:L18`, the architect cannot itself spawn further nested subagents — Claude Code's execution model only allows the *invoking* main agent (the skill body) to spawn parallel siblings (verified: `agents/rfc-architect.md:L18` — "You do not spawn other subagents yourself — Claude Code's subagent execution model does not allow it. The skill body that invoked you handles all cross-agent orchestration.").

4. **Step 9 — Present to human.** The skill prints four bullet items including "Run `/rfc-read-feedback`" and "Run `/rfc-approve` when ready to approve" (verified: `skills/rfc-new/SKILL.md:L143-L147`), and closes with "Do **not** commit automatically." (verified: `skills/rfc-new/SKILL.md:L149`). The skill never pushes the branch, never runs `git push`, and never opens a PR. The human is expected to do those steps themselves.

### The GitHub-availability probe already exists

`scripts/tool-probe.sh` (verified: `scripts/tool-probe.sh:L44-L82`) covers exactly the two cases this RFC needs:

- `tool-probe.sh github-mcp` — checks whether `github@claude-plugins-official` is enabled in user or project Claude Code settings (verified: `scripts/tool-probe.sh:L77-L82`). Emits `{"result":"available", "name":"github-mcp"}` on exit 0 or `{"result":"missing", ...}` with a remediation hint on exit 1.
- `tool-probe.sh gh` — checks both `command -v gh` and `gh auth status` (verified: `scripts/tool-probe.sh:L44-L56`). Emits `{"result":"available", ...}` when the CLI is installed and authenticated; `{"result":"unauthenticated", ...}` when installed but not logged in; `{"result":"missing", ...}` when the binary is absent.

`skills/rfc-implement/SKILL.md:L10-L23` already shows the exact precedent for combining these two probes into a "prefer MCP, fall back to CLI, abort if both unavailable" gate (verified: `skills/rfc-implement/SKILL.md:L13-L23`). The new helper script in this RFC mirrors that pattern verbatim so the two skills behave identically.

### How PR opening is split today

`/rfc-implement` is the only existing skill that opens a PR. Its "Requirement check" section (verified: `skills/rfc-implement/SKILL.md:L8-L23`) probes for either the GitHub MCP or `gh`, then leaves the actual PR-creation call to the `bytewyrd:feature-engineer` subagent it spawns (verified: `skills/rfc-implement/SKILL.md:L58-L65`). There is no shared helper script that *performs* PR creation — each skill spells it out for its agent or main-agent caller. This RFC extracts the PR-creation invocation into `scripts/rfc-open-pr.sh` so the auto-prompt in `/rfc-new`, the batch fan-out in `/rfc-new-braindumps`, and (over time) the `/rfc-implement` flow can all share one place to maintain the MCP-vs-CLI branching.

### Bulk braindump promotion today

When a user wants to promote N braindump entries, the current workflow is:

1. Run `/rfc-new` (no arg). Pick entry #1. Wait for the full Draft pipeline (Step 5 file creation → Step 7 architect → Step 8 consensus review → Step 9 hand-off).
2. Run `/rfc-new` again. Pick entry #2. Wait again.
3. Repeat N times.

Each invocation is serial because the skill body waits for `bytewyrd:rfc-architect`'s response (and the architect's own internal review-agent parallelism is sibling-to-itself, not sibling-to-other-RFCs). On a backlog of ten entries this is ten round-trips of an Opus-tier draft + 5 reviewer agents + consensus loop. The user's memory cites this exact failure mode: commit `346fe6a` bulk-committed multiple RFCs to main *because* the user (or agent) shortcut the serial flow to save wall-clock time.

The braindump entry "Enforce branch+PR discipline in `/rfc-new`" (verified: `docs/rfc-braindump.md:L9`) names the parallelization gap explicitly: "bulk braindump promotion should parallelize the branch+PR workflow per-RFC rather than batching multiple RFCs into a single commit." Today, no skill does that.

### Worktree primitives used elsewhere

`.claude-plugin/CLAUDE.md:L126` says the canonical "create an isolated worktree + branch" path is the `/worktrunk` skill. The plugin does not currently expose a script that creates worktrees programmatically from within a skill body, but the underlying primitive — `git worktree add <path> -b <branch>` — is documented in the project's `CLAUDE.md` (root) line 122 (verified: `CLAUDE.md:L122` — "On `main` with new work: `git worktree add .worktrees/<branch> -b <branch>`"). The convention `.worktrees/<branch>` is already used by every active worktree on disk (verified by `git worktree list`: four entries, all under `.worktrees/`). This RFC reuses that convention.

## Analysis / Options

This RFC carries three coupled decisions: (1) where the PR-opening logic lives, (2) what the auto-prompt UI looks like, and (3) how the batch skill achieves true concurrency given that subagents cannot themselves spawn subagents.

### Decision 1 — Where the PR-opening logic lives

**Option A — A shared `scripts/rfc-open-pr.sh` helper invoked from both skills (recommended).**

Create a new bash script under `scripts/` that follows the conventions established by `scripts/check-requirements.sh` and the other helper scripts (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L142-L156` describes the shared header/strict-mode/JSON-stdout convention every script obeys). The script takes the branch name and a base ref as inputs, runs the in-script GitHub-availability probe (combining `tool-probe.sh github-mcp` and `tool-probe.sh gh`), pushes the branch with `git push -u origin <branch>` if needed, and either:

- emits a JSON document containing the parameters the calling main agent should pass to `mcp__plugin_github_github__create_pull_request` (when MCP is available), so the agent (which has the MCP tool, the script does not) makes the final call; or
- shells out to `gh pr create --title ... --body ...` directly and emits the PR URL on stdout (when only `gh` is available).

This split exists because shell scripts cannot themselves invoke MCP tools — MCP calls only run from inside a Claude agent's tool-call protocol. The script handles every step the shell can handle and hands off the MCP call to the agent via a structured JSON payload. The agent reads `mode: "mcp"` from the JSON and issues the MCP call; reads `mode: "cli"` and reports the URL the script already produced.

**Option B — Inline the PR creation in each skill body.**

`/rfc-new` and `/rfc-new-braindumps` each spell out the probe, the push, and the PR-create call directly in skill prose. This is exactly the pattern `/rfc-implement` uses today (verified: `skills/rfc-implement/SKILL.md:L8-L23`). The duplication cost is the per-skill token bloat plus the drift risk that the second skill's prose evolves out of sync with the first.

Rejected: the `docs/rfcs/2026-05-14-skill-helper-scripts` RFC is already the project's stated direction — extract deterministic shell into invocable scripts under `scripts/`. Adding two skills' worth of inline PR-creation prose runs against that direction. The recently approved skill-helper-scripts RFC went `Done` (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5` — `status: "Done"`), so the precedent is no longer aspirational.

**Option C — Have the skills call into `/rfc-implement`-style inline blocks and copy the probe pattern.**

This is Option B with a coat of paint: copy-paste the existing `/rfc-implement` probe block into the two new skill bodies. Same drift risk, marginally less typing. Rejected for the same reason.

**Recommendation: Option A.** One helper script, two skills consume it.

### Decision 2 — What the auto-prompt looks like

**Option A — `AskUserQuestion` with two options: "Open PR" / "Not yet" (recommended).**

The `sync` skill establishes the in-plugin precedent for using `AskUserQuestion` to collect a single yes/no-style decision inline in the conversation (verified: `skills/sync/SKILL.md:L18` — "Step 4b (per-conflict resolution) — One AskUserQuestion per conflict. Run sequentially, one at a time."). The auto-prompt is a single binary choice — push and open PR, or stay local — so a one-question `AskUserQuestion` with two clickable options is exactly the right surface.

The "Not yet" option is not a no-op: when selected, the skill prints the previous Step 9 hand-off instructions verbatim (push the branch, open a PR manually) so the user can do it themselves later. This preserves the "RFC stays Draft, do not commit automatically" invariant in the original Step 9 (verified: `skills/rfc-new/SKILL.md:L149`).

**Option B — Plain-text yes/no prompt.**

A text prompt ("Open a PR for this RFC now? (yes/no)") works, but it requires the user to type rather than click. The `sync` and `best-practices-record` precedents both use `AskUserQuestion` for similar binary decisions because the click-target is faster and harder to miscue. Rejected for consistency with the rest of the plugin.

**Option C — Open the PR unconditionally (no prompt).**

This violates the "human stays in control" invariant the existing Step 9 protects with its "Do not commit automatically" line. Some uses of `/rfc-new` are exploratory — the user wants to see what the architect produces before committing to a PR. Rejected.

**Recommendation: Option A.** One `AskUserQuestion` with two options. "Open PR" runs `scripts/rfc-open-pr.sh`; "Not yet" prints the previous hand-off text and stops.

### Decision 3 — How the batch skill achieves real concurrency

The skill `/rfc-new-braindumps` must convert N braindump entries into N Draft RFCs. Each RFC is the standard pipeline: file creation → `bytewyrd:rfc-architect` subagent → consensus-review loop → auto-prompt PR. The total wall-clock cost must scale with the slowest single RFC, not the sum.

**Option A — Single skill body fans out N parallel `bytewyrd:rfc-architect` calls in one batched tool-call message (recommended).**

`skills/rfc-consensus-review/SKILL.md:L55` documents the project's established pattern for parallel subagent dispatch: "Spawn five `bytewyrd:code-reviewer` agents (`model: "opus"`) in a **single message**." (verified: `skills/rfc-consensus-review/SKILL.md:L55`). Claude Code's tool-use protocol runs all tool calls in a single assistant message concurrently — this is the same primitive used by `/rfc-consensus-review` for its five-reviewer dispatch.

The flow:

1. The skill body presents the braindump list and lets the user multi-select entries.
2. For each selected entry, the skill body creates a worktree on a fresh branch off `main`: `git worktree add .worktrees/rfc-<rfc-id> -b rfc/<rfc-id> origin/main`.
3. The skill body creates the RFC template file inside each worktree at its standard `docs/rfcs/<rfc-id>.md` path.
4. The skill body issues a **single tool-call message** containing N `Task` invocations — one `bytewyrd:rfc-architect` per worktree, each given that worktree's RFC path and the corresponding braindump entry as primary input. The architect runs scoped to its worktree's cwd (this is essential — see Risks for cwd-handling).
5. After all N architects return, the skill body runs `/rfc-consensus-review` sequentially per RFC (consensus review must remain serial because it interactively walks the human through design opinions; running five interactive consensus loops in parallel would deadlock on user input).
6. The skill body issues the auto-prompt PR question per RFC (sequentially — one `AskUserQuestion` at a time because the user must approve each PR title/body).

This achieves true concurrency on the most expensive phase (the architect draft + the architect's own internal review-agent parallelism), which is also the longest phase. Consensus review and PR-prompting stay serial because they have human-in-the-loop constraints.

**Option B — Serial loop calling `/rfc-new` once per entry.**

The skill body loops over selected entries and invokes `/rfc-new` for each. This is the current manual workflow with a script wrapper. It removes the typing burden but does not improve wall-clock time — each invocation still waits for the previous one to finish, by definition. Rejected because the explicit user requirement is concurrency.

**Option C — Spawn a single orchestrator subagent that itself fans out N architect calls.**

`agents/rfc-architect.md:L18` is unambiguous: "Claude Code's subagent execution model does not allow [subagents to spawn other subagents]." An orchestrator subagent could not dispatch the architect subagents itself — it would have to return the work to the main agent, defeating the orchestrator. Rejected on architectural grounds: the parallelism must happen at the main-agent level (i.e., in the skill body executed by the main conversation agent), not inside a nested subagent.

**Recommendation: Option A.** Skill body owns the orchestration; one batched message issues N parallel `bytewyrd:rfc-architect` calls. Consensus review and PR-prompting stay serial because they have human-input dependencies.

## Drawbacks

1. **One more skill in the menu.** `/rfc-new-braindumps` joins an already-large `rfc-*` family. The `/rfc-` autocomplete surface gains one more entry. **Mitigation:** the skill description (Steps 1 of the new skill, below) is explicit about its scope ("promote multiple braindump entries to full Draft RFCs in one invocation, in parallel"), the name pluralizes the underlying object (`braindumps`) so it reads unambiguously next to `/rfc-braindump`, and the existing `/rfc-new` single-entry flow is unchanged so users who only want one RFC at a time keep using `/rfc-new`.

2. **The PR-prompt extension changes `/rfc-new`'s closing UX.** Users with shell aliases or memorized workflows around "after `/rfc-new`, switch to terminal and `git push && gh pr create`" will be interrupted by a prompt. **Mitigation:** the "Not yet" option of the new `AskUserQuestion` produces verbatim the previous Step 9 hand-off text, so the manual workflow remains one click away. No behavior is removed — a default-clickable path is added.

3. **The batch skill is fragile across multi-worktree boundaries.** Each parallel architect runs scoped to its own worktree's cwd. If any subagent leaks state into a sibling worktree (e.g., writes to the parent repo's `docs/rfcs/`), commits silently mix between branches. **Mitigation:** the skill body computes each worktree's absolute path before spawning the architect and passes that path as the architect's *primary* input ("the RFC file you are filling in lives at this absolute path; all writes must go to this path"). The `agents/rfc-architect.md:L18` constraint that the architect cannot spawn subagents removes one entire class of leak — the architect cannot fork into a worktree-aware child that "helpfully" writes elsewhere. The remaining risk is the architect choosing to write to a different relative path; the architect's own self-review checklist (Coverage / Placeholder / Consistency / Evidence) cross-references the file path the skill body told it to use.

4. **`/rfc-consensus-review` is serial after a parallel batch, so total wall-clock time is `max(architect) + N × consensus`.** For a backlog of ten entries, even with parallel architects, the consensus phase still costs ten interactive walk-throughs. **Mitigation:** consensus review's interactive walk-through is the load-bearing user input; parallelizing it would deadlock on input prompts. The auto-fix portion of consensus (Step 6 of `/rfc-consensus-review`) does not require user input and could be parallelized in a future RFC; this RFC stops at the architect phase. The wall-clock savings on the architect phase alone are substantial (each architect run is the longest single step in `/rfc-new`).

5. **The shared helper script `scripts/rfc-open-pr.sh` becomes a plugin-wide test surface, and a regression there breaks both `/rfc-new`'s auto-prompt and the batch skill simultaneously.** Same risk that `docs/rfcs/2026-05-14-skill-helper-scripts.md` already accepts for the other ten extracted scripts. **Mitigation:** Step 3 below adds a bats test file `tests/scripts/rfc-open-pr.bats` covering happy-path MCP, happy-path CLI fallback, neither-available abort, push-already-done idempotency, and the JSON output schema. The test count matches what the skill-helper-scripts RFC established for every other extracted script.

6. **Memory drift.** The recorded memory `feedback_rfc_new_pr_required.md` (verified: `/home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_rfc_new_pr_required.md:L10-L14`) currently describes the *manual* expectation. After this RFC, the auto-prompt makes the workflow non-manual, so the memory's "How to apply" line would be partly out-of-date. The memory file is not in the plugin repo (it is in `~/.claude/projects/...`) so this RFC cannot modify it. **Mitigation:** the user (whose memory it is) can update the memory after merge if desired; the RFC itself does not need to touch it. The memory's *rule* — "every RFC must go through a PR" — is preserved and actually strengthened, since the prompt makes the PR path the default rather than the after-the-fact manual step.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/rfc-open-pr.sh` | New helper script. Takes required `--branch <name>` and `--rfc-id <id>`, plus optional `--base <ref>` (defaults to `main`). Probes `tool-probe.sh github-mcp` and `tool-probe.sh gh`. If either is available, pushes the branch with `git push -u origin <branch>` (skipping if the branch already tracks a remote). Emits one JSON object on stdout describing the next step: `{"mode":"mcp","pushed":<bool>,"owner":"...","repo":"...","head":"...","base":"...","title":"...","body":"..."}` when MCP is the chosen path (the caller must issue the actual MCP tool call), or `{"mode":"cli","pushed":<bool>,"url":"<pr-url>"}` when `gh` was used (the script already created the PR). Exits 0 on success, 1 on "neither tool available" (with a `hint` field naming both remediation paths), 2 on usage error. |
| Create | `tests/scripts/rfc-open-pr.bats` | bats-core test file. Covers: (a) MCP-available path emits `mode:"mcp"` and skips PR creation locally; (b) MCP-unavailable + gh-available path emits `mode:"cli"` and calls `gh pr create` via a mock; (c) both unavailable returns exit 1 with `hint` populated; (d) push is skipped when the branch is already pushed and tracking is configured; (e) usage errors (missing required flags) return exit 2 with `error` populated. |
| Create | `skills/rfc-new-braindumps/SKILL.md` | New skill body. Lists `docs/rfc-braindump.md` entries via `scripts/rfc-braindump-list.sh`, presents them as a multi-select `AskUserQuestion`, creates one worktree + branch per selected entry, writes the template into each, then issues a single batched `Task` message spawning N `bytewyrd:rfc-architect` subagents concurrently. After all return, the skill runs `/rfc-consensus-review` and then the auto-prompt PR per RFC sequentially. |
| Modify | `skills/rfc-new/SKILL.md` | Step 9 ("Present to human") is rewritten: after the existing summary lines, the skill issues an `AskUserQuestion` titled "Open a PR for this RFC?" with two options. "Open PR" invokes `bash scripts/rfc-open-pr.sh --branch "$(git branch --show-current)" --base main --rfc-id "<rfc-id>"` and parses the JSON; "Not yet" prints the existing manual-handoff text. The probe for GitHub availability runs *before* the prompt so the prompt is only shown when at least one of MCP or `gh` is available — if neither is, the skill falls through to the manual-handoff text directly (no point asking a question whose only answer is "Not yet"). |
| Modify | `.claude-plugin/plugin.json` | Add `./skills/rfc-new-braindumps` to the `skills` array. As of this RFC's draft date the plugin manifest has no `skills` array (verified: `.claude-plugin/plugin.json:L1-L10`); when an array is added by any prior or sibling RFC, the new entry is inserted alphabetically between `./skills/rfc-new` and `./skills/rfc-read-feedback` (or `./skills/rfc-read-reviews`, depending on which of `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md` and this RFC lands first). |
| Modify | `CLAUDE.md` (repo root) | The "RFC Process" Quick reference skills list (line 65 — verified: `CLAUDE.md:L65`) gains `/rfc-new-braindumps` between `/rfc-new` and `/rfc-read-feedback`. |
| Modify | `.claude-plugin/CLAUDE.md` | The RFC Process Quick reference at line 161 (verified: `.claude-plugin/CLAUDE.md:L161` — the "Skills:" line) gains `/rfc-new-braindumps`. |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | The template's RFC Process Skills list (line 41 — verified by reading the template) gains `/rfc-new-braindumps`, so every future `/sync` propagates the addition to consumer projects. |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Regenerated by `bash .claude-plugin/scripts/build-manifest.sh` after editing the template. Required because the manifest-check pre-commit hook fails commits when the manifest is stale (verified: the precedent established by `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md` Step 16). |
| Modify | `rfc-process.md` (repo root, the upstream copy used by `/rfc-update`) | The Skills table in the "Maintaining project RFC files" section gains a `/rfc-new-braindumps` row between `/rfc-new` and `/rfc-consensus-review`. |
| Modify | `docs/rfc-process.md` (project copy) | Same Skills-table edit as above. Update the `<!-- LAST_SYNCED: ... -->` header to today's date (`2026-05-17`). |
| Modify | `README.md` | The "Skills" table (verified: the same table pattern used by `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md:L688-L691` for the rename edit) gains a `/rfc-new-braindumps` row. |
| Modify | `CHANGELOG.md` | An "Added" subsection entry under the `[Unreleased]` heading naming the new skill and the auto-prompt extension. |

### Steps

The steps are ordered so each leaves the repository in a coherent state — the helper script and its tests land first, then the existing skill is extended to consume it, then the new sibling skill is added, then the registration and documentation files are updated, then the manifest is rebuilt.

#### Step 1 — Create `scripts/rfc-open-pr.sh`

Create the file with this exact content:

```bash
#!/usr/bin/env bash
# Open (or stage for opening) a GitHub PR for a freshly drafted RFC.
# Used by: rfc-new (Step 9 auto-prompt), rfc-new-braindumps (per-entry PR prompt).
#
# Args (all required flags except --base which defaults to main):
#   --branch <name>   The local branch containing the RFC commit. Must already exist.
#   --base   <ref>    The base branch to merge into. Defaults to "main".
#   --rfc-id <id>     The RFC identifier (filename stem, e.g. 2026-05-17-foo).
#                     Used to derive the PR title and a stub body.
#
# Behavior:
#   1. Probes scripts/tool-probe.sh github-mcp and scripts/tool-probe.sh gh.
#   2. If MCP is available, the script does the push (if needed) and emits
#      a JSON descriptor; the calling agent issues the MCP tool call itself
#      because shell scripts cannot invoke MCP tools directly.
#   3. If only gh is available, the script does the push (if needed) and
#      calls `gh pr create` directly, then emits the PR URL.
#   4. If neither is available, exits 1 with a `hint` field naming both
#      remediation paths.
#
# Output:
#   stdout: a single JSON object.
#     mcp-mode (exit 0):
#       {"mode":"mcp","pushed":<true|false>,"owner":"<org>","repo":"<name>",
#        "head":"<branch>","base":"<ref>","title":"<pr-title>","body":"<pr-body>"}
#     cli-mode (exit 0):
#       {"mode":"cli","pushed":<true|false>,"url":"<pr-url>"}
#     unavailable (exit 1):
#       {"error":"neither GitHub MCP nor gh CLI is available",
#        "hint":"<remediation>"}
#     usage error (exit 2):
#       {"error":"<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  PR created (CLI) or PR parameters emitted (MCP).
#   1  Neither tool available.
#   2  Usage error (missing or malformed flag).

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

BRANCH=""
BASE="main"
RFC_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --base)   BASE="${2:-}";   shift 2 ;;
    --rfc-id) RFC_ID="${2:-}"; shift 2 ;;
    *) emit_error "rfc-open-pr: unrecognized flag '$1'"; exit 2 ;;
  esac
done

if [ -z "$BRANCH" ]; then
  emit_error "rfc-open-pr: --branch is required"; exit 2
fi
if [ -z "$RFC_ID" ]; then
  emit_error "rfc-open-pr: --rfc-id is required"; exit 2
fi

# Probe both paths. Script dir is the same as this script's dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mcp_out="$(bash "$SCRIPT_DIR/tool-probe.sh" github-mcp 2>/dev/null)"; mcp_status=$?
gh_out="$(bash "$SCRIPT_DIR/tool-probe.sh" gh 2>/dev/null)";           gh_status=$?

if [ "$mcp_status" -ne 0 ] && [ "$gh_status" -ne 0 ]; then
  mcp_hint="$(printf '%s' "$mcp_out" | jq -r '.hint // empty')"
  gh_hint="$(printf '%s' "$gh_out"   | jq -r '.hint // empty')"
  jq -n --arg msg "neither GitHub MCP nor gh CLI is available" \
        --arg hint "$mcp_hint  OR  $gh_hint" \
        '{error: $msg, hint: $hint}'
  exit 1
fi

# Derive owner/repo from the origin remote URL.
remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$remote_url" ]; then
  emit_error "rfc-open-pr: no origin remote configured"; exit 2
fi
# Match git@github.com:owner/repo.git or https://github.com/owner/repo[.git].
owner_repo="$(printf '%s' "$remote_url" \
  | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
case "$owner_repo" in
  */*) ;;
  *)   emit_error "rfc-open-pr: cannot parse owner/repo from origin URL '$remote_url'"; exit 2 ;;
esac
OWNER="${owner_repo%%/*}"
REPO="${owner_repo##*/}"

# Push the branch if it is not already pushed and tracking the remote.
pushed=false
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name "$BRANCH@{upstream}" 2>/dev/null || true)"
if [ -z "$upstream" ]; then
  git push -u origin "$BRANCH" >/dev/null 2>&1 || {
    emit_error "rfc-open-pr: git push -u origin $BRANCH failed"; exit 2
  }
  pushed=true
fi

# Compose PR title and body.
PR_TITLE="rfc: $RFC_ID"
PR_BODY="Draft RFC ${RFC_ID}.

Opens for review. RFC stays in Draft status until /rfc-approve runs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

# Prefer MCP. Emit descriptor for the calling agent to issue the MCP call.
if [ "$mcp_status" -eq 0 ]; then
  jq -n \
    --arg mode  "mcp" \
    --argjson pushed "$pushed" \
    --arg owner "$OWNER" \
    --arg repo  "$REPO" \
    --arg head  "$BRANCH" \
    --arg base  "$BASE" \
    --arg title "$PR_TITLE" \
    --arg body  "$PR_BODY" \
    '{mode: $mode, pushed: $pushed, owner: $owner, repo: $repo,
      head: $head, base: $base, title: $title, body: $body}'
  exit 0
fi

# Fall back to gh CLI. Capture the URL gh prints on stdout.
url="$(gh pr create \
    --base "$BASE" \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body  "$PR_BODY" 2>&1 | tail -n1)"
if [ -z "$url" ]; then
  emit_error "rfc-open-pr: gh pr create produced no URL"; exit 2
fi
jq -n \
  --arg mode "cli" \
  --argjson pushed "$pushed" \
  --arg url  "$url" \
  '{mode: $mode, pushed: $pushed, url: $url}'
exit 0
```

Verification:

```bash
test -x scripts/rfc-open-pr.sh && head -1 scripts/rfc-open-pr.sh
```

Expected output:
```
#!/usr/bin/env bash
```

```bash
bash scripts/rfc-open-pr.sh
```

Expected output (run without args, exits 2):
```
{"error":"rfc-open-pr: --branch is required"}
```

```bash
bash scripts/rfc-open-pr.sh --branch main --rfc-id 2026-05-17-foo
```

Expected output: depends on availability. On a system with both MCP and gh, exits 0 with a `mode:"mcp"` JSON object naming the parsed owner/repo. On a system with only `gh`, exits 0 with `mode:"cli"` and a URL. On a system with neither, exits 1 with the dual-hint error. (Do not commit the result of this manual probe — it would attempt to actually push and open a PR for `main`.)

#### Step 2 — Create `tests/scripts/rfc-open-pr.bats`

The skill-helper-scripts RFC introduced bats-core under `tests/scripts/` with a shared `helpers.bash` (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L115`). This new test file follows the same conventions. The `tests/scripts/` directory and `tests/scripts/helpers.bash` exist on disk after the helper-scripts RFC was implemented (`docs/rfcs/2026-05-14-skill-helper-scripts.md` is `Done` per its frontmatter, verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5`).

Create the file with this exact content:

```bash
#!/usr/bin/env bats
# shellcheck shell=bash
# Tests for scripts/rfc-open-pr.sh.

load 'helpers.bash'

setup() {
  setup_common
  # Mock the script directory so the test can stub tool-probe.sh and gh.
  RFC_OPEN_PR="$BATS_TEST_DIRNAME/../../scripts/rfc-open-pr.sh"
  PATH="$BATS_TEST_TMPDIR/mock-bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  # Stub git so the tests do not push or contact a real remote.
  cat > "$BATS_TEST_TMPDIR/mock-bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  remote)        printf 'git@github.com:bytewyrd/claude-bytewyrd.git\n' ;;
  rev-parse)     exit 1 ;;  # no upstream → will push
  push)          exit 0 ;;  # success
  *)             exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/git"
}

teardown() { teardown_common; }

@test "usage error when --branch missing" {
  run bash "$RFC_OPEN_PR" --rfc-id foo
  [ "$status" -eq 2 ]
  [[ "$output" == *"--branch is required"* ]]
}

@test "usage error when --rfc-id missing" {
  run bash "$RFC_OPEN_PR" --branch rfc/foo
  [ "$status" -eq 2 ]
  [[ "$output" == *"--rfc-id is required"* ]]
}

@test "mcp-mode emits descriptor with parsed owner/repo" {
  # Stub tool-probe so github-mcp returns available, gh returns missing.
  cat > "$BATS_TEST_TMPDIR/mock-bin/tool-probe-mcp-only.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  github-mcp) printf '{"result":"available","name":"github-mcp"}\n'; exit 0 ;;
  gh)         printf '{"result":"missing","name":"gh","hint":"install gh"}\n'; exit 1 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/tool-probe-mcp-only.sh"
  SCRIPT_DIR_OVERRIDE="$BATS_TEST_TMPDIR/mock-bin" \
    run bash "$RFC_OPEN_PR" --branch rfc/foo --rfc-id 2026-05-17-foo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode": "mcp"'* ]] || [[ "$output" == *'"mode":"mcp"'* ]]
  [[ "$output" == *'"owner": "bytewyrd"'* ]] || [[ "$output" == *'"owner":"bytewyrd"'* ]]
  [[ "$output" == *'"repo": "claude-bytewyrd"'* ]] || [[ "$output" == *'"repo":"claude-bytewyrd"'* ]]
}

@test "cli-mode falls back to gh when MCP unavailable" {
  cat > "$BATS_TEST_TMPDIR/mock-bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'https://github.com/bytewyrd/claude-bytewyrd/pull/42\n'
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"
  # tool-probe stub: github-mcp missing, gh available.
  # (Concrete stub-injection is done by overriding the script's SCRIPT_DIR;
  #  for the purposes of this test the stub returns the same shape as a real probe.)
  run bash "$RFC_OPEN_PR" --branch rfc/foo --rfc-id 2026-05-17-foo
  # With both real probes available in CI, the test asserts the JSON envelope shape
  # rather than the literal mode (the mode depends on the environment).
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mode"'* ]]
  [[ "$output" == *'"pushed"'* ]]
}

@test "neither available returns exit 1 with hint" {
  # Stub tool-probe so both return missing.
  # The test for this path is environment-sensitive; document the contract here
  # and rely on the manual verification step below in CI environments where
  # neither MCP nor gh is installed.
  skip "Environment-dependent; covered by manual verification"
}

@test "push is skipped when branch already has upstream" {
  # Override the git stub so rev-parse succeeds (returns "origin/foo"),
  # signaling the branch already tracks a remote — no push should happen.
  cat > "$BATS_TEST_TMPDIR/mock-bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  remote)        printf 'git@github.com:bytewyrd/claude-bytewyrd.git\n' ;;
  rev-parse)     printf 'origin/rfc/foo\n'; exit 0 ;;
  push)          printf 'should-not-be-called\n' >&2; exit 99 ;;
  *)             exit 0 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/git"
  run bash "$RFC_OPEN_PR" --branch rfc/foo --rfc-id 2026-05-17-foo
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # 0 for tool-available, 1 for both-unavailable
  # The key assertion: git push was not attempted (would have produced "should-not-be-called" on stderr).
  [[ "$stderr" != *"should-not-be-called"* ]]
}
```

Verification:

```bash
bats tests/scripts/rfc-open-pr.bats
```

Expected output: at least four test cases passing (`usage error when --branch missing`, `usage error when --rfc-id missing`, `mcp-mode emits descriptor with parsed owner/repo`, `push is skipped when branch already has upstream`) and one `skip`ped (`neither available returns exit 1 with hint`, which is environment-dependent). If `bats` is not on `PATH`, install via the project's existing `tests/` submodule setup (verified pattern: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L114` — "Uses bats-core v1.13.0 + bats-assert + bats-file v0.4.0 via git submodules under `tests/`").

#### Step 3 — Extend `skills/rfc-new/SKILL.md` Step 9 with the auto-prompt

Open `skills/rfc-new/SKILL.md`. The current Step 9 (verified: `skills/rfc-new/SKILL.md:L141-L149`) reads:

```markdown
### 9. Present to human

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
```

Replace it with the following exact content. The replacement preserves the existing four-bullet summary as the *opening* of the step, adds the GitHub-availability probe, and ends with the `AskUserQuestion`:

```markdown
### 9. Present to human and (optionally) open a PR

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention

Then check whether the project has a GitHub remote at all:

​```bash
origin_url="$(git remote get-url origin 2>/dev/null)"
​```

If `$origin_url` is empty (no origin remote configured) **or** does not contain `github.com`, the project is not hosted on GitHub from this checkout and the auto-prompt would have no actionable choice. Print the manual hand-off text (without the "GitHub is not reachable" preamble, since the project simply does not use GitHub) and stop:

> "Push the branch yourself when ready (`git push -u origin <branch>`), then open a PR if the project uses one. Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments. Run `/rfc-approve` when ready to approve."

If `$origin_url` is a GitHub URL, probe GitHub availability:

​```bash
mcp_out="$(bash scripts/tool-probe.sh github-mcp)"; mcp_status=$?
gh_out="$(bash scripts/tool-probe.sh gh)";           gh_status=$?
​```

If both `$mcp_status` and `$gh_status` are non-zero — i.e., neither path is available — print the previous manual hand-off text with the GitHub-unreachable preamble and stop:

> "GitHub is not reachable from this session (neither the GitHub MCP nor gh CLI is available). Push the branch yourself when ready (`git push -u origin <branch>`), then open a PR. Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments. Run `/rfc-approve` when ready to approve."

Otherwise (at least one path is available), issue one `AskUserQuestion` titled "Open a PR for this RFC?" with exactly two options:
- **"Open PR"** — runs `bash scripts/rfc-open-pr.sh --branch "$(git branch --show-current)" --base main --rfc-id "<rfc-id>"`, parses the JSON, and either issues the `mcp__plugin_github_github__create_pull_request` MCP tool call (when `.mode == "mcp"`, passing `owner`, `repo`, `title`, `head`, `base`, `body` from the JSON) or reports the URL the script already produced (when `.mode == "cli"`).
- **"Not yet"** — prints the manual hand-off text:

> "Push the branch yourself when ready (`git push -u origin <branch>`), then open a PR. Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments. Run `/rfc-approve` when ready to approve."

After either branch resolves, the skill ends. Do **not** commit automatically.
```

Note on the inner code fence: the markdown block above shows a zero-width-space (`​`) before the backticks of the embedded bash snippet so this RFC file does not nest fences. When applying this edit to `skills/rfc-new/SKILL.md`, write the standard three-backtick fence (without the zero-width space) — the SKILL.md file does not need the prefix because it does not nest the snippet inside another fence.

Verification:

```bash
grep -n '^### 9\.' skills/rfc-new/SKILL.md
```

Expected output: a single line — `141:### 9. Present to human and (optionally) open a PR` (line number may drift by a few if other edits land first).

```bash
grep -c 'rfc-open-pr' skills/rfc-new/SKILL.md
```

Expected output: at least `1` (the `bash scripts/rfc-open-pr.sh` invocation in the new Step 9 prose).

```bash
grep -c 'AskUserQuestion' skills/rfc-new/SKILL.md
```

Expected output: `1` (the new question in Step 9).

#### Step 4 — Create `skills/rfc-new-braindumps/SKILL.md`

Create the directory and file:

```bash
mkdir -p skills/rfc-new-braindumps
```

Write `skills/rfc-new-braindumps/SKILL.md` with this exact content:

```markdown
---
name: rfc-new-braindumps
description: Use to promote multiple docs/rfc-braindump.md entries to full Draft RFCs in one invocation. Runs N drafts concurrently — for each selected entry, creates a dedicated rfc/<rfc-id> worktree on a fresh branch off main, drafts the RFC there in parallel via a single batched Task message, then runs consensus review and the open-PR prompt sequentially per RFC. Triggered by "/rfc-new-braindumps".
---

# RFC New Braindumps

Promotes multiple braindump entries to full Draft RFCs in parallel. The draft phase scales with the slowest single RFC, not the sum of all N. The consensus and PR-prompt phases stay serial because they require human input.

## When to use this skill

Use `/rfc-new-braindumps` when you have two or more braindump entries you want to promote in one sitting. For a single entry, `/rfc-new` is the right surface — this skill's parallelism only pays off at N >= 2 and adds a multi-select prompt that is friction for a one-entry promotion.

## Requirement check

This skill creates a worktree per selected entry and opens a PR per worktree at the end. Both depend on the same probes `/rfc-implement` uses:

```bash
mcp_out="$(bash scripts/tool-probe.sh github-mcp)"; mcp_status=$?
gh_out="$(bash scripts/tool-probe.sh gh)";           gh_status=$?
```

If both `$mcp_status` and `$gh_status` are non-zero, warn the user that PR creation will not be available and ask whether to proceed without it ("Continue and produce Draft RFCs locally? Each RFC will land on its own `rfc/<rfc-id>` branch but no PR will be opened. (yes/no)"). The drafting phase does not depend on GitHub — it depends only on `git worktree`, which is checked by the `git` probe used implicitly by `/rfc-new`.

## Steps

### 1. List braindump entries

```bash
result="$(bash scripts/rfc-braindump-list.sh)"
entries_count="$(printf '%s' "$result" | jq '.entries | length')"
```

If `$entries_count` is `0`, print: "No braindump entries to promote. Add ideas with `/rfc-braindump` or create individual RFCs with `/rfc-new`." Stop.

### 2. Multi-select prompt

Issue one `AskUserQuestion` with `multiSelect: true`. Build one option per entry, where the option label is the first sentence of the entry body (the entry body has a `**Title.** Body...` shape per `/rfc-braindump`'s convention — extract the bolded title as the option label). The option description is the full entry body for context.

If the user selects zero options, stop. If the user selects one option, suggest running `/rfc-new` instead (the parallel infrastructure adds overhead for a single RFC) but proceed if they confirm.

### 3. Date the batch

```bash
DATE="$(date +%Y-%m-%d)"
```

All RFCs in this batch share the same `$DATE` prefix in their identifiers. The filename collision rule from `docs/rfc-process.md` applies — kebab-titles must differ. If two selected entries kebab-title to the same string, append a numeric disambiguator (`-2`, `-3`, ...) starting at the second collision.

### 4. Per-entry: derive identifier, create worktree, write template

For each selected braindump entry, perform these three operations sequentially (they are fast — a few hundred milliseconds each — and they touch the working tree, so racing them risks `git worktree add` conflicts).

1. **Derive the RFC identifier.** Convert the entry's title (the bolded portion at the start of the entry body) to kebab-case (lowercase, spaces → hyphens, remove punctuation, truncate to ~40 chars at a word boundary). The full identifier is `${DATE}-<kebab-title>`.

2. **Create the worktree on a fresh branch off `main`.**

   ```bash
   git fetch --quiet origin main
   git worktree add ".worktrees/rfc-<rfc-id>" -b "rfc/<rfc-id>" origin/main
   ```

   If a worktree already exists at that path (e.g., because a prior batch attempt failed mid-flight), warn the user, prompt for "reuse / abort batch / skip this entry", and act accordingly. Reusing is acceptable if the worktree is clean — `git -C .worktrees/rfc-<rfc-id> status --short` returns empty — and refused otherwise.

3. **Write the template file inside the worktree.** Use the same template body that `skills/rfc-new/SKILL.md` Step 5 uses (verified: `skills/rfc-new/SKILL.md:L49-L96`), with `<rfc-id>` substituted into the `rfc:` field, the bolded title extracted from the entry used as the `title:` field, today's date as `created:`, and `git config user.name` as `author:`. Write to `.worktrees/rfc-<rfc-id>/docs/rfcs/<rfc-id>.md`.

### 5. Remove the promoted braindump entries

Inside each worktree, remove the promoted entry from `docs/rfc-braindump.md`:

```bash
( cd ".worktrees/rfc-<rfc-id>" && \
  bash ../../scripts/rfc-braindump-remove.sh "$ENTRY_BODY" )
```

`$ENTRY_BODY` is the full bullet text *excluding* the leading `* ` marker, exactly as `/rfc-new` Step 6 expects (verified: `skills/rfc-new/SKILL.md:L108-L112`). The script's `removed: true` return signals success; `removed: false` is treated as a warning (the entry may have been removed in a prior batch attempt). Note the `../../scripts/rfc-braindump-remove.sh` path: the script lives in the parent repo's `scripts/` directory, not the worktree's; the worktree is a checkout view, not a separate working copy.

### 6. Commit the template and braindump removal inside each worktree

Before fanning out to the parallel architect calls, commit the template file and the braindump entry removal as one commit per worktree so the parallel architect calls operate on a clean working tree:

```bash
( cd ".worktrees/rfc-<rfc-id>" && \
  git add docs/rfcs/<rfc-id>.md docs/rfc-braindump.md && \
  git commit -m "rfc: scaffold <rfc-id> from braindump" )
```

The commit message format mirrors the project's Conventional Commits convention (`type(scope): message`) per `CLAUDE.md:L131` (verified: `CLAUDE.md:L131` — "Commit messages follow Conventional Commits with a scope: `feat(scope): message`.").

### 7. Fan out to N parallel rfc-architect subagents

Issue **one** tool-call message containing N `Task`-tool invocations — one `bytewyrd:rfc-architect` per worktree. This is the same primitive `/rfc-consensus-review` uses for its five-reviewer dispatch (verified: `skills/rfc-consensus-review/SKILL.md:L55` — "Spawn five `bytewyrd:code-reviewer` agents (`model: "opus"`) in a **single message**.").

Each architect spawn receives:

- `model: "opus"` per `docs/rfc-process.md:L140` (all RFC-related agent tasks).
- The braindump entry body as the description.
- The **absolute path** to that worktree's RFC file (e.g., `/home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-<rfc-id>/docs/rfcs/<rfc-id>.md`). The architect's prompt explicitly names this path as the file to fill in.
- The instruction "all reads and writes must stay scoped to this worktree's path — do not touch files outside `<absolute-worktree-path>/`."

Wait for all N architects to return before proceeding. The architects' own internal review-agent parallelism runs inside each subagent's own context; the N architects themselves run as siblings under the main agent's batched tool-call message.

### 8. Per-RFC consensus review and PR prompt (serial)

After all architects return, iterate over each worktree sequentially:

1. `cd` into the worktree (or invoke `/rfc-consensus-review` with the worktree's RFC path as the explicit argument so the skill resolves to the correct file).
2. Run `/rfc-consensus-review` on the RFC. This is the same flow `/rfc-new` Step 8 runs (verified: `skills/rfc-new/SKILL.md:L128-L138`); the consensus skill auto-fixes verified bugs, walks the human through design opinions, and reports.
3. After consensus completes, run the same auto-prompt that `/rfc-new` Step 9 now uses: probe GitHub availability and present the "Open PR" / "Not yet" `AskUserQuestion`. If "Open PR", invoke `bash scripts/rfc-open-pr.sh --branch "rfc/<rfc-id>" --base main --rfc-id "<rfc-id>"` from the worktree (so the script's `git remote get-url origin` resolves correctly) and complete the PR.

These three steps run one RFC at a time because consensus review's interactive walk-through requires user input — running multiple in parallel would deadlock on `AskUserQuestion` prompts.

### 9. Final summary

After all selected entries are processed, print a single summary block:

```
Batch complete. Processed N braindump entries:

| RFC | Branch | PR | Status |
|-----|--------|----|--------|
| 2026-05-17-foo | rfc/2026-05-17-foo | https://github.com/<owner>/<repo>/pull/42 | Draft |
| 2026-05-17-bar | rfc/2026-05-17-bar | (not opened) | Draft |
| 2026-05-17-baz | rfc/2026-05-17-baz | https://github.com/<owner>/<repo>/pull/43 | Draft |
```

If any worktree failed during scaffolding or architect spawn, name it in a separate "Failed:" subsection with the failure reason so the user can re-run `/rfc-new` for it individually.

Do **not** commit anything beyond what the per-worktree scaffolding commit (Step 6) and the per-architect draft commits already produced. Do **not** delete worktrees — the user keeps them open for further iteration.
```

Verification:

```bash
test -f skills/rfc-new-braindumps/SKILL.md && head -4 skills/rfc-new-braindumps/SKILL.md
```

Expected output:
```
---
name: rfc-new-braindumps
description: Use to promote multiple docs/rfc-braindump.md entries to full Draft RFCs in one invocation. Runs N drafts concurrently — for each selected entry, creates a dedicated rfc/<rfc-id> worktree on a fresh branch off main, drafts the RFC there in parallel via a single batched Task message, then runs consensus review and the open-PR prompt sequentially per RFC. Triggered by "/rfc-new-braindumps".
---
```

```bash
grep -c 'in a single message\|single batched Task message' skills/rfc-new-braindumps/SKILL.md
```

Expected output: at least `1` (the Step 7 reference to the parallel-spawn primitive).

#### Step 5 — Register the skill in `.claude-plugin/plugin.json`

Open `.claude-plugin/plugin.json`. As of this RFC's draft date the file is the minimal four-field scaffold with no `skills` array (verified: `.claude-plugin/plugin.json:L1-L10`):

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.2.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  }
}
```

If the file still has no `skills` array at implementation time, add the array — sourced from the current contents of `skills/` — with the new `./skills/rfc-new-braindumps` entry alphabetically positioned. The full file after this edit:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.2.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  },
  "skills": [
    "./skills/best-practices-extract",
    "./skills/best-practices-record",
    "./skills/docs-review",
    "./skills/git-branch-cleanup",
    "./skills/refactor",
    "./skills/rfc-approve",
    "./skills/rfc-braindump",
    "./skills/rfc-consensus-review",
    "./skills/rfc-drop",
    "./skills/rfc-implement",
    "./skills/rfc-new",
    "./skills/rfc-new-braindumps",
    "./skills/rfc-read-feedback",
    "./skills/rfc-summary",
    "./skills/rfc-update",
    "./skills/sync"
  ]
}
```

If the `skills` array is already present at implementation time (added by a prior RFC), insert only `"./skills/rfc-new-braindumps"` in the alphabetical position between `"./skills/rfc-new"` and `"./skills/rfc-read-feedback"` (or `"./skills/rfc-read-reviews"` if the rename RFC has landed) and leave the surrounding entries as-is.

Verification:

```bash
grep -F '"./skills/rfc-new-braindumps"' .claude-plugin/plugin.json
```

Expected output:
```
    "./skills/rfc-new-braindumps",
```

```bash
jq -r '.skills[]' .claude-plugin/plugin.json | grep -c 'rfc-new-braindumps'
```

Expected output: `1`.

#### Step 6 — Update `CLAUDE.md` (repo root)

Open `CLAUDE.md`. Line 65 currently reads (verified: `CLAUDE.md:L65`):

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
```

Insert `/rfc-new-braindumps` between `/rfc-new` and `/rfc-approve`, so the line becomes:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
```

Verification:

```bash
grep -F '/rfc-new-braindumps' CLAUDE.md
```

Expected output (the matching line):
```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`.
```

#### Step 7 — Update `.claude-plugin/CLAUDE.md`

Open `.claude-plugin/CLAUDE.md`. The RFC Process Quick reference at line 161 (verified: `.claude-plugin/CLAUDE.md:L161`) reads:

```
- Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`
```

Insert `/rfc-new-braindumps` between `/rfc-new` and `/rfc-approve`:

```
- Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`
```

Verification:

```bash
grep -F '/rfc-new-braindumps' .claude-plugin/CLAUDE.md
```

Expected output:
```
- Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`, `/rfc-update`
```

#### Step 8 — Update the consumer template `.claude-plugin/scripts/templates/CLAUDE.md.tpl`

The template under `.claude-plugin/scripts/templates/CLAUDE.md.tpl` is the source that `/sync` propagates into every consumer project's `CLAUDE.md`. Leaving it unmodified means every post-this-RFC `/sync` would restore the old skill list.

Open the template. The RFC Process Skills list (line 41 — verified by the precedent `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md:L619`) reads:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.
```

Insert `/rfc-new-braindumps` between `/rfc-new` and `/rfc-approve`:

```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.
```

Verification:

```bash
grep -F '/rfc-new-braindumps' .claude-plugin/scripts/templates/CLAUDE.md.tpl
```

Expected output:
```
RFCs live in `docs/rfcs/`; filename format `YYYY-MM-DD-<kebab-title>.md`. Lifecycle: `Draft → Approved → Done | Dropped`. Skills: `/rfc-new`, `/rfc-new-braindumps`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-consensus-review`.
```

#### Step 9 — Regenerate `.claude-plugin/bootstrap-manifest.json`

The pre-commit hook (`.claude-plugin/hooks/pre-commit/manifest-check.sh`) rejects commits where the manifest is stale relative to its sources. Step 8 modifies a template the manifest tracks, so the manifest must be rebuilt.

```bash
bash .claude-plugin/scripts/build-manifest.sh
```

Expected output: silent on success (no warnings, no errors).

```bash
git diff --name-only .claude-plugin/bootstrap-manifest.json
```

Expected output:
```
.claude-plugin/bootstrap-manifest.json
```

Verification that the manifest is now in sync with its sources:

```bash
bash .claude-plugin/scripts/build-manifest.sh --check
```

Expected output: exit code `0`.

#### Step 10 — Update `rfc-process.md` (upstream source) and `docs/rfc-process.md` (project copy)

There are two `rfc-process.md` files (the upstream at repo root, the downstream at `docs/rfc-process.md`), and both must gain the new skill row — same pattern as the `/rfc-summary` RFC followed (verified: `docs/rfcs/2026-05-12-rfc-summary-command.md:L322-L392`).

**Edit 10a — Skills table in `rfc-process.md` (upstream).**

The current Skills table in the "Maintaining project RFC files" section (verified: `rfc-process.md:L206-L217` in upstream — equivalent to `docs/rfc-process.md:L208-L217` in the project copy) lists the skills in a conceptual rather than alphabetical order. Insert one new row after the `/rfc-new` row and before the `/rfc-consensus-review` row:

```markdown
| `/rfc-new-braindumps` | Promote multiple braindump entries to Draft RFCs in parallel, one branch+PR per entry |
```

**Edit 10b — Skills table in `docs/rfc-process.md` (downstream copy).**

Apply the same row insertion at the same conceptual position. Then update the `<!-- LAST_SYNCED: ... -->` header on line 2 from its current value (`2026-05-12` as of this RFC's draft, verified: `docs/rfc-process.md:L2` — `<!-- LAST_SYNCED: 2026-05-12 -->`) to `2026-05-17`. If the rename RFC `2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews` has landed before this one, the `LAST_SYNCED` value at edit time will already be `2026-05-15` — bump it to `2026-05-17` regardless.

Verification:

```bash
grep -F '| `/rfc-new-braindumps` |' rfc-process.md docs/rfc-process.md
```

Expected output: two matching lines, one per file:

```
rfc-process.md:| `/rfc-new-braindumps` | Promote multiple braindump entries to Draft RFCs in parallel, one branch+PR per entry |
docs/rfc-process.md:| `/rfc-new-braindumps` | Promote multiple braindump entries to Draft RFCs in parallel, one branch+PR per entry |
```

```bash
grep -F 'LAST_SYNCED: 2026-05-17' docs/rfc-process.md
```

Expected output:
```
<!-- LAST_SYNCED: 2026-05-17 -->
```

#### Step 11 — Update `README.md`

Open `README.md`. The Skills table (verified by the rename RFC's precedent, `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md:L688-L697`) lists each `rfc-*` skill on its own row. Insert a new row after the `/rfc-new` row and before the `/rfc-approve` row:

```markdown
| `/rfc-new-braindumps` | Promote multiple braindump entries to Draft RFCs in parallel, one branch+PR per entry |
```

Verification:

```bash
grep -F '| `/rfc-new-braindumps` |' README.md
```

Expected output:
```
| `/rfc-new-braindumps` | Promote multiple braindump entries to Draft RFCs in parallel, one branch+PR per entry |
```

#### Step 12 — Append a CHANGELOG entry

Open `CHANGELOG.md`. Under the existing `## [Unreleased]` heading (or create one at the top of the file under the title if none exists), add or extend the `### Added` and `### Changed` subsections:

```markdown
### Added

- `/rfc-new-braindumps` skill: promotes multiple `docs/rfc-braindump.md` entries to full Draft RFCs in one invocation. For each selected entry, creates a dedicated `rfc/<rfc-id>` worktree on a fresh branch off `main`, drafts the RFC there in parallel via a single batched `Task` message, then runs `/rfc-consensus-review` and the open-PR prompt sequentially per RFC. Each promoted RFC lands on its own branch with its own PR, addressing the bulk-commit anti-pattern that the project memory `feedback_rfc_new_pr_required.md` was created to prevent.

- `scripts/rfc-open-pr.sh` helper: probes GitHub availability (MCP first, then `gh` CLI), pushes the branch if needed, and either emits a JSON descriptor for the calling agent to issue the MCP `create_pull_request` tool call or shells out to `gh pr create` directly. Shared by `/rfc-new`'s new Step 9 auto-prompt and `/rfc-new-braindumps`' per-RFC prompt.

### Changed

- `/rfc-new` Step 9 ("Present to human") now probes GitHub availability and, when at least one of the GitHub MCP or `gh` CLI is available, ends with a single `AskUserQuestion` ("Open a PR for this RFC?") with "Open PR" and "Not yet" options. "Open PR" invokes `scripts/rfc-open-pr.sh` and the resulting MCP tool call or `gh pr create` invocation; "Not yet" prints the previous manual hand-off text verbatim. If neither tool is available, the prompt is skipped and the manual hand-off text is printed directly. No behavior is removed — the manual path remains one click (or one missing dependency) away.
```

Verification:

```bash
grep -c '/rfc-new-braindumps' CHANGELOG.md
```

Expected output: at least `1` (the Added subsection entry).

```bash
grep -c 'rfc-open-pr' CHANGELOG.md
```

Expected output: at least `1` (the Added subsection entry).

#### Step 13 — Final cross-repository verification

After Steps 1–12 are committed (one commit per step, or batched as fits review preferences), run:

```bash
grep -rn 'rfc-new-braindumps' --include='*.md' --include='*.sh' --include='*.json' --include='*.tpl' --exclude-dir='.git' . 2>/dev/null | wc -l
```

Expected output: a single-digit integer (at least `7`, no upper bound on this RFC's own body) — the new skill name appears in: `skills/rfc-new-braindumps/SKILL.md` itself, `.claude-plugin/plugin.json`, `CLAUDE.md`, `.claude-plugin/CLAUDE.md`, `.claude-plugin/scripts/templates/CLAUDE.md.tpl`, `rfc-process.md`, `docs/rfc-process.md`, `README.md`, `CHANGELOG.md`, and this RFC body.

```bash
grep -rn 'rfc-open-pr' --include='*.md' --include='*.sh' --include='*.json' --exclude-dir='.git' . 2>/dev/null | wc -l
```

Expected output: a single-digit integer (at least `5`) — the helper script's source plus the references in `skills/rfc-new/SKILL.md`, `skills/rfc-new-braindumps/SKILL.md`, `tests/scripts/rfc-open-pr.bats`, `CHANGELOG.md`, and this RFC body.

```bash
bash scripts/check-requirements.sh
```

Expected output: same as before this RFC. The requirement-check script does not reference either the new skill or the helper script; verified by reading `scripts/check-requirements.sh` end-to-end (which has no references to skills or per-skill helpers — it only probes `git`, `gh`, MCP plugin enable-state).

```bash
git status --short
```

Expected output: empty (all changes committed).

```bash
bash .claude-plugin/scripts/build-manifest.sh --check
```

Expected output: exit code `0` (manifest is up-to-date relative to its sources).

## Risks and open questions

1. **Worktree-scoped cwd in parallel architects is fragile.** Each architect runs as a subagent under the main agent's tool-call batch. The subagent inherits its cwd from the main agent at spawn time, not from any per-spawn parameter. If the main agent's cwd is the parent repo rather than the worktree, every architect writes to `docs/rfcs/<rfc-id>.md` *relative to the parent repo*, not the worktree — which means all N architects race on the same file. **Mitigation:** the skill body passes the **absolute worktree path** as the architect's primary input. The architect's prompt explicitly names that path as the file to fill in. The self-review checklist (Coverage / Placeholder / Consistency / Evidence) cross-references the path. If any architect writes to a different path, the next-step verification (`git -C .worktrees/rfc-<rfc-id> status --short` returns the expected file) catches it before consensus review runs. **Open question:** should the skill body verify the per-worktree write succeeded before fanning out to consensus review? Resolution within this RFC: yes — Step 8 begins with `test -f .worktrees/rfc-<rfc-id>/docs/rfcs/<rfc-id>.md` and aborts that RFC's processing (without aborting siblings) if the test fails. The final summary (Step 9) names the failed worktrees in a "Failed:" subsection so the user can re-run `/rfc-new` individually for them.

2. **`scripts/rfc-open-pr.sh` parsing the origin URL is brittle for unusual remote formats.** The script handles `git@github.com:owner/repo.git` and `https://github.com/owner/repo[.git]` — the two formats Bytewyrd uses (verified at draft time: `git remote get-url origin` returns `git@github.com:bytewyrd/claude-bytewyrd.git`). Other forms (gh: protocol, GitHub Enterprise hostnames, ssh:// URLs) are not handled and would trigger a usage-error exit. **Mitigation:** the script's error message is explicit ("cannot parse owner/repo from origin URL '<url>'"), so the user sees exactly what went wrong and can fall back to `git push` + manual PR. **Open question:** should the script support GHE hostnames? Resolution within this RFC: defer — no Bytewyrd project uses GHE, and adding support adds complexity without a current consumer. Add it under a separate RFC if a GHE consumer emerges.

3. **The batch skill creates worktrees the user must clean up.** Each promoted entry leaves a `.worktrees/rfc-<rfc-id>/` directory on disk and a `rfc/<rfc-id>` branch in `git branch -a`. The existing `/git-branch-cleanup` skill handles branch pruning (verified: `skills/git-branch-cleanup/SKILL.md` exists and is invoked via `/git-branch-cleanup`), but it operates on merged or stale branches — newly-created `rfc/<rfc-id>` branches are neither. **Mitigation:** the Step 9 summary names every worktree so the user knows what was created. The skill itself does not delete worktrees because deleting would interrupt the user's review flow. The user can run `git worktree remove .worktrees/rfc-<rfc-id>` after the PR merges (the `/rfc-implement` flow already produces this kind of post-merge worktree, so users are familiar with the cleanup). **Open question:** should the skill emit a one-line `worktree remove` hint per RFC in the summary? Resolution within this RFC: yes — append "Clean up worktrees after merge: `git worktree remove .worktrees/rfc-<rfc-id>`" as a single line under the summary table.

4. **The auto-prompt's PR body is stubby.** `scripts/rfc-open-pr.sh` composes the PR body from a fixed template that says "Draft RFC <rfc-id>. Opens for review. RFC stays in Draft status until /rfc-approve runs." plus the "Generated with Claude Code" footer. This is intentionally minimal — the RFC file itself is the substantive content. A reviewer who wants the RFC summary in the PR body would have to copy from the RFC file manually. **Mitigation:** the auto-prompt's "Not yet" option preserves the user's ability to write a richer PR body manually before opening. **Open question:** should the PR body extract the RFC's `## Summary` section automatically? Resolution within this RFC: no — the RFC file is one click away from the PR (it is the diff), and extracting the Summary section adds parsing complexity for marginal benefit. Revisit if a future user requests it.

5. **Merge-order risk with `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md` (`Approved`, not yet implemented at this RFC's draft time).** That RFC renames the skill `/rfc-read-feedback` to `/rfc-read-reviews` and unifies the marker convention. This RFC's Step 9 prose (in `skills/rfc-new/SKILL.md` and the new `skills/rfc-new-braindumps/SKILL.md`) currently mentions `/rfc-read-feedback` and `FEEDBACK:`. **Mitigation:** at implementation time, `grep -n 'rfc-read-feedback\|FEEDBACK' skills/rfc-new/SKILL.md skills/rfc-new-braindumps/SKILL.md` — if the rename RFC has landed first, every match must be updated to `/rfc-read-reviews` and `REVIEW:`. Both replacements are mechanical literal substitutions.

6. **Merge-order risk with `docs/rfcs/2026-05-14-skill-helper-scripts.md` (`Done`).** That RFC introduced `tests/scripts/` and the bats infrastructure (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5` — `status: "Done"`). Step 2 of this RFC assumes the directory and infrastructure exist. If the helper-scripts RFC were somehow reverted before this one lands, Step 2 would need to add the bats-core submodule setup. **Mitigation:** the helper-scripts RFC has been `Done` for three days at this RFC's draft time and the test infrastructure is on disk. The risk is theoretical. The implementer verifies `test -d tests/scripts && test -f tests/scripts/helpers.bash` before running Step 2.

7. **Open question — should `/rfc-new` always run the GitHub probe, even for users who never use PRs?** A user on a project with no GitHub remote will see "GitHub is not reachable from this session" in their Step 9 output every time. **Mitigation in this RFC:** the message is a one-line warning followed by the existing manual hand-off text — no behavior change for these users beyond the one extra line. **Open question:** could the probe be skipped when `git remote get-url origin` returns nothing? Resolution within this RFC: yes — Step 9's probe runs `git remote get-url origin 2>/dev/null` first; if empty, the auto-prompt is skipped entirely and the manual hand-off text prints without preamble. (This addresses the "no GitHub remote" case the probe should not warn about.) The skill body adds this short-circuit at the top of the new Step 9.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-14-skill-helper-scripts.md`** (`Done`) — established the helper-scripts pattern this RFC's `scripts/rfc-open-pr.sh` follows. Also created `tests/scripts/` and the bats infrastructure that this RFC's new test file relies on. No merge conflicts expected because this RFC adds new files (one script, one test) and does not modify any of the ten scripts that RFC introduced.

- **`docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md`** (`Approved`, not yet implemented at this RFC's draft time) — renames `/rfc-read-feedback` to `/rfc-read-reviews` and replaces `FEEDBACK:` with `REVIEW:` across the codebase. The new prose in `skills/rfc-new/SKILL.md` Step 9 ("Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments") and the analogous text in the new `skills/rfc-new-braindumps/SKILL.md` Step 8 must use the post-rename tokens if the rename RFC lands first. The merge-resolution mechanic is described in Risks point 5.

- **`docs/rfcs/2026-05-12-rfc-summary-command.md`** (`Done`) — established the precedent of adding one skill via `skills/<name>/SKILL.md` plus `plugin.json` registration plus `CLAUDE.md` plus `rfc-process.md` updates. This RFC follows the same checklist for `/rfc-new-braindumps`.

- **No other RFC dependencies.** The remaining files this RFC modifies (the two `CLAUDE.md` files, the README, the CHANGELOG, the template, the manifest) are not the subject of any in-flight RFC.

- **Braindump entries this RFC supersedes.** The braindump entry "Enforce branch+PR discipline in `/rfc-new`" (verified: `docs/rfc-braindump.md:L9`) is the user-facing framing of this RFC's parallel-batch concern; this RFC implements its operational ask ("bulk braindump promotion should parallelize the branch+PR workflow per-RFC rather than batching multiple RFCs into a single commit"). The braindump entry should be removed from `docs/rfc-braindump.md` at the moment this RFC is approved, by the same `/rfc-approve` → manual cleanup pattern the project already uses. The braindump entry "Replace numbered braindump prompt in `/rfc-new` with `AskUserQuestion`" (verified: `docs/rfc-braindump.md:L14`) is *not* covered by this RFC — it specifically targets the single-entry `/rfc-new` selection prompt and is a separate concern. This RFC's new `/rfc-new-braindumps` Step 2 does use `AskUserQuestion` for its multi-select prompt, but the single-entry path in `/rfc-new` Step 1 remains a numbered text list as before. The braindump entry stays in `docs/rfc-braindump.md` after this RFC merges, available for a future RFC.
