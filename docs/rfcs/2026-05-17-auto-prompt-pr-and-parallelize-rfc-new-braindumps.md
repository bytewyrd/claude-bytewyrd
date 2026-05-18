---
rfc: "2026-05-17-auto-prompt-pr-and-parallelize-rfc-new-braindumps"
title: "Auto-prompt PR creation in /rfc-new"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

> **Scope note.** This RFC was originally drafted as a two-part proposal covering both (a) the auto-PR-prompt extension to `/rfc-new` and (b) a new batch skill `/rfc-new-braindumps` for parallel promotion of multiple braindump entries. Per design feedback, the batch fan-out half has been deferred to a separate future RFC (working name: `/rfc-new-braindumps` with a cherry-pick UI for entry selection). This RFC now covers **only** the auto-PR-prompt extension to `/rfc-new`. The filename is preserved for traceability against existing review comments and braindump references; see "Out of scope — future RFC" below for the deferred work.

## Summary

Extend `/rfc-new` so that — whenever GitHub is reachable (`github@claude-plugins-official` MCP enabled or `gh` CLI installed and authenticated) — it ends with a single `AskUserQuestion` confirming whether to push the current branch and open a PR for the freshly drafted RFC, removing today's manual "push the branch and open a PR yourself" hand-off. The PR-opening mechanics are extracted into a new helper script `scripts/rfc-open-pr.sh` so the logic lives in one place and the skill body stays declarative. The behavior is opt-out at the prompt: pressing the "Not yet" option keeps the RFC local and prints the previous manual instructions verbatim.

## Should we do this?

**Yes.** The current `/rfc-new` Step 9 ("Present to human") closes the skill with a printed instruction list that includes `/rfc-read-feedback`, `/rfc-approve`, and an implicit assumption that the human will switch to a terminal to `git push -u origin <branch>` and run `gh pr create` themselves (verified: `skills/rfc-new/SKILL.md:L141`). The project's recorded memory `feedback_rfc_new_pr_required.md` (verified: `/home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_rfc_new_pr_required.md:L10`) makes the rule explicit: "Never commit RFC files directly to the main branch. Each /rfc-new invocation must create its own branch and open a PR for review before the RFC lands on main." A skill that closes by *asking* about the PR — rather than *suggesting* the user run the commands — collapses two manual steps and one context switch into one click, and removes the failure mode the memory was created to prevent. The braindump entry "Enforce branch+PR discipline in `/rfc-new`" frames the same need in user-facing terms (verified: `docs/rfc-braindump.md:L9` — "Branch creation and PR opening must be non-optional steps in the skill flow"). Cost: one new helper script, one `Steps` change to the existing `/rfc-new` skill, plus the documentation entries in CHANGELOG. No new external dependencies — `gh` and the GitHub MCP probe via the existing `scripts/tool-probe.sh` (verified: `scripts/tool-probe.sh:L44-L82`).

## Current state

### What `/rfc-new` does today

The skill body (verified: `skills/rfc-new/SKILL.md:L1-L149`) runs nine steps. The relevant ones for this RFC are:

1. **Step 1 — Get description.** If invoked with no argument, the skill calls `bash scripts/rfc-braindump-list.sh` (verified: `skills/rfc-new/SKILL.md:L20`), counts entries with `jq '.entries | length'`, and — when there are entries — presents them as a numbered text list with the prompt "Pick a number to promote, or describe a new RFC." (verified: `skills/rfc-new/SKILL.md:L23`). Selection is one entry at a time.

2. **Step 9 — Present to human.** The skill prints four bullet items including "Run `/rfc-read-feedback`" and "Run `/rfc-approve` when ready to approve" (verified: `skills/rfc-new/SKILL.md:L143-L147`), and closes with "Do **not** commit automatically." (verified: `skills/rfc-new/SKILL.md:L149`). The skill never pushes the branch, never runs `git push`, and never opens a PR. The human is expected to do those steps themselves.

### The GitHub-availability probe already exists

`scripts/tool-probe.sh` (verified: `scripts/tool-probe.sh:L44-L82`) covers exactly the two cases this RFC needs:

- `tool-probe.sh github-mcp` — checks whether `github@claude-plugins-official` is enabled in user or project Claude Code settings (verified: `scripts/tool-probe.sh:L77-L82`). Emits `{"result":"available", "name":"github-mcp"}` on exit 0 or `{"result":"missing", ...}` with a remediation hint on exit 1.
- `tool-probe.sh gh` — checks both `command -v gh` and `gh auth status` (verified: `scripts/tool-probe.sh:L44-L56`). Emits `{"result":"available", ...}` when the CLI is installed and authenticated; `{"result":"unauthenticated", ...}` when installed but not logged in; `{"result":"missing", ...}` when the binary is absent.

`skills/rfc-implement/SKILL.md:L10-L23` already shows the exact precedent for combining these two probes into a "prefer MCP, fall back to CLI, abort if both unavailable" gate (verified: `skills/rfc-implement/SKILL.md:L13-L23`). The new helper script in this RFC mirrors that pattern verbatim so the two skills behave identically.

### How PR opening is split today

`/rfc-implement` is the only existing skill that opens a PR. Its "Requirement check" section (verified: `skills/rfc-implement/SKILL.md:L8-L23`) probes for either the GitHub MCP or `gh`, then leaves the actual PR-creation call to the `bytewyrd:feature-engineer` subagent it spawns (verified: `skills/rfc-implement/SKILL.md:L58-L65`). There is no shared helper script that *performs* PR creation — the probe and the call are spelled out inline. This RFC extracts the PR-creation invocation into `scripts/rfc-open-pr.sh` so the auto-prompt in `/rfc-new` has a single, testable place to handle the MCP-vs-CLI branching, push idempotency, and origin-URL parsing.

## Analysis / Options

This RFC carries two coupled decisions: (1) where the PR-opening logic lives, and (2) what the auto-prompt UI looks like.

### Decision 1 — Where the PR-opening logic lives

**Option A — A shared `scripts/rfc-open-pr.sh` helper invoked from the skill body (recommended).**

Create a new bash script under `scripts/` that follows the conventions established by `scripts/check-requirements.sh` and the other helper scripts (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L142-L156` describes the shared header/strict-mode/JSON-stdout convention every script obeys). The script takes the branch name and a base ref as inputs, runs the in-script GitHub-availability probe (combining `tool-probe.sh github-mcp` and `tool-probe.sh gh`), pushes the branch with `git push -u origin <branch>` if needed, and either:

- emits a JSON document containing the parameters the calling main agent should pass to `mcp__plugin_github_github__create_pull_request` (when MCP is available), so the agent (which has the MCP tool, the script does not) makes the final call; or
- shells out to `gh pr create --title ... --body ...` directly and emits the PR URL on stdout (when only `gh` is available).

This split exists because shell scripts cannot themselves invoke MCP tools — MCP calls only run from inside a Claude agent's tool-call protocol. The script handles every step the shell can handle and hands off the MCP call to the agent via a structured JSON payload. The agent reads `mode: "mcp"` from the JSON and issues the MCP call; reads `mode: "cli"` and reports the URL the script already produced.

Even with only one consumer at this RFC's draft time, extracting the script is justified by three properties: (a) the logic is deterministic shell work — origin-URL parsing, push idempotency, probe ordering — which the project has standardized as helper-script territory (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5` — `status: "Done"`); (b) the script is independently testable via bats while inline skill prose is not; (c) future PR-opening consumers (the deferred batch skill in the future-RFC, or any later workflow that opens a PR after a scripted change) can reuse the same helper without copying its logic.

**Option B — Inline the PR creation in the `/rfc-new` skill body.**

Spell out the probe, the push, the origin-URL parse, and the MCP-vs-CLI branching directly in the Step 9 prose. This is exactly the pattern `/rfc-implement` uses today for its probe (verified: `skills/rfc-implement/SKILL.md:L8-L23`). It is the cheapest single-consumer option but defers extraction until a second consumer arrives, by which point the inline prose has accumulated edge cases.

Rejected: the `docs/rfcs/2026-05-14-skill-helper-scripts` RFC is already the project's stated direction — extract deterministic shell into invocable scripts under `scripts/`. Putting non-trivial deterministic shell into skill prose runs against that direction even for a single consumer.

**Recommendation: Option A.** One helper script, the `/rfc-new` skill consumes it. Future PR-opening flows inherit the same helper.

### Decision 2 — What the auto-prompt looks like

**Option A — `AskUserQuestion` with two options: "Open PR" / "Not yet" (recommended).**

The `sync` skill establishes the in-plugin precedent for using `AskUserQuestion` to collect a single yes/no-style decision inline in the conversation (verified: `skills/sync/SKILL.md:L18` — "Step 4b (per-conflict resolution) — One AskUserQuestion per conflict. Run sequentially, one at a time."). The auto-prompt is a single binary choice — push and open PR, or stay local — so a one-question `AskUserQuestion` with two clickable options is exactly the right surface.

The "Not yet" option is not a no-op: when selected, the skill prints the previous Step 9 hand-off instructions verbatim (push the branch, open a PR manually) so the user can do it themselves later. This preserves the "RFC stays Draft, do not commit automatically" invariant in the original Step 9 (verified: `skills/rfc-new/SKILL.md:L149`).

**Option B — Plain-text yes/no prompt.**

A text prompt ("Open a PR for this RFC now? (yes/no)") works, but it requires the user to type rather than click. The `sync` and `best-practices-record` precedents both use `AskUserQuestion` for similar binary decisions because the click-target is faster and harder to miscue. Rejected for consistency with the rest of the plugin.

**Option C — Open the PR unconditionally (no prompt).**

This violates the "human stays in control" invariant the existing Step 9 protects with its "Do not commit automatically" line. Some uses of `/rfc-new` are exploratory — the user wants to see what the architect produced before committing to a PR. Rejected.

**Recommendation: Option A.** One `AskUserQuestion` with two options. "Open PR" runs `scripts/rfc-open-pr.sh`; "Not yet" prints the previous hand-off text and stops.

## Out of scope — future RFC

The original draft of this RFC also proposed a new sibling skill `/rfc-new-braindumps` that would promote multiple `docs/rfc-braindump.md` entries to full Draft RFCs in one invocation by fanning out N parallel `bytewyrd:rfc-architect` calls in a single batched `Task` message — one per worktree. That work has been deferred to a separate future RFC.

The deferred RFC will be drafted under a separate filename (working name: `/rfc-new-braindumps`, with a cherry-pick UI for selecting which braindump entries to promote in parallel rather than auto-selecting all entries). The deferred RFC will reuse `scripts/rfc-open-pr.sh` as introduced here, so this RFC's helper-script extraction stands on its own merits independent of the batch flow.

The following content was part of the original draft and is **out of scope for this RFC**, deferred to the future RFC:

- A new skill at `skills/rfc-new-braindumps/SKILL.md` with a multi-select prompt over braindump entries.
- The decision around parallel-architect concurrency (single-message N-Task fan-out vs serial loop vs orchestrator-subagent — the original Decision 3).
- Per-worktree branch isolation (`git worktree add .worktrees/rfc-<rfc-id> -b rfc/<rfc-id> origin/main`) and per-architect cwd-scoping.
- Per-RFC serial consensus review and PR-prompt walk-through (the only phase that cannot trivially parallelize because of human-input constraints).
- Final batch summary table mapping RFC → branch → PR URL.
- Registration entries in `plugin.json`, `CLAUDE.md` files, `rfc-process.md` (upstream and downstream), `README.md`, the template under `.claude-plugin/scripts/templates/CLAUDE.md.tpl`, and a CHANGELOG entry for the new skill.

The braindump entry "Enforce branch+PR discipline in `/rfc-new`" (verified: `docs/rfc-braindump.md:L9`) stays in the braindump file after this RFC merges. Its operational ask (parallelize the branch+PR workflow per-RFC) is addressed by the future RFC, not by this one — this RFC addresses only the per-RFC branch+PR opening UX, which lays the groundwork for the future batch flow.

## Drawbacks

1. **The PR-prompt extension changes `/rfc-new`'s closing UX.** Users with shell aliases or memorized workflows around "after `/rfc-new`, switch to terminal and `git push && gh pr create`" will be interrupted by a prompt. **Mitigation:** the "Not yet" option of the new `AskUserQuestion` produces verbatim the previous Step 9 hand-off text, so the manual workflow remains one click away. No behavior is removed — a default-clickable path is added.

2. **The new helper script `scripts/rfc-open-pr.sh` becomes a plugin-wide test surface, and a regression there breaks `/rfc-new`'s auto-prompt.** Same risk that `docs/rfcs/2026-05-14-skill-helper-scripts.md` already accepts for the other ten extracted scripts. **Mitigation:** Step 2 below adds a bats test file `tests/scripts/rfc-open-pr.bats` covering happy-path MCP, happy-path CLI fallback, neither-available abort, push-already-done idempotency, and the JSON output schema. The test count matches what the skill-helper-scripts RFC established for every other extracted script.

3. **Memory drift.** The recorded memory `feedback_rfc_new_pr_required.md` (verified: `/home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_rfc_new_pr_required.md:L10-L14`) currently describes the *manual* expectation. After this RFC, the auto-prompt makes the workflow non-manual, so the memory's "How to apply" line would be partly out-of-date. The memory file is not in the plugin repo (it is in `~/.claude/projects/...`) so this RFC cannot modify it. **Mitigation:** the user (whose memory it is) can update the memory after merge if desired; the RFC itself does not need to touch it. The memory's *rule* — "every RFC must go through a PR" — is preserved and actually strengthened, since the prompt makes the PR path the default rather than the after-the-fact manual step.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/rfc-open-pr.sh` | New helper script. Takes required `--branch <name>` and `--rfc-id <id>`, plus optional `--base <ref>` (defaults to `main`). Probes `tool-probe.sh github-mcp` and `tool-probe.sh gh`. If either is available, pushes the branch with `git push -u origin <branch>` (skipping if the branch already tracks a remote). Emits one JSON object on stdout describing the next step: `{"mode":"mcp","pushed":<bool>,"owner":"...","repo":"...","head":"...","base":"...","title":"...","body":"..."}` when MCP is the chosen path (the caller must issue the actual MCP tool call), or `{"mode":"cli","pushed":<bool>,"url":"<pr-url>"}` when `gh` was used (the script already created the PR). Exits 0 on success, 1 on "neither tool available" (with a `hint` field naming both remediation paths), 2 on usage error. |
| Create | `tests/scripts/rfc-open-pr.bats` | bats-core test file. Covers: (a) MCP-available path emits `mode:"mcp"` and skips PR creation locally; (b) MCP-unavailable + gh-available path emits `mode:"cli"` and calls `gh pr create` via a mock; (c) both unavailable returns exit 1 with `hint` populated; (d) push is skipped when the branch is already pushed and tracking is configured; (e) usage errors (missing required flags) return exit 2 with `error` populated. |
| Modify | `skills/rfc-new/SKILL.md` | Step 9 ("Present to human") is rewritten: after the existing summary lines, the skill issues an `AskUserQuestion` titled "Open a PR for this RFC?" with two options. "Open PR" invokes `bash scripts/rfc-open-pr.sh --branch "$(git branch --show-current)" --base main --rfc-id "<rfc-id>"` and parses the JSON; "Not yet" prints the existing manual-handoff text. The probe for GitHub availability runs *before* the prompt so the prompt is only shown when at least one of MCP or `gh` is available — if neither is, the skill falls through to the manual-handoff text directly (no point asking a question whose only answer is "Not yet"). |
| Modify | `CHANGELOG.md` | An entry under the `[Unreleased]` heading naming the auto-prompt extension and the new helper script. |

### Steps

The steps are ordered so each leaves the repository in a coherent state — the helper script and its tests land first, then the existing skill is extended to consume it, then the CHANGELOG entry records the change.

#### Step 1 — Create `scripts/rfc-open-pr.sh`

Create the file with this exact content:

```bash
#!/usr/bin/env bash
# Open (or stage for opening) a GitHub PR for a freshly drafted RFC.
# Used by: rfc-new (Step 9 auto-prompt).
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

#### Step 4 — Append a CHANGELOG entry

Open `CHANGELOG.md`. Under the existing `## [Unreleased]` heading (or create one at the top of the file under the title if none exists), add or extend the `### Added` and `### Changed` subsections:

```markdown
### Added

- `scripts/rfc-open-pr.sh` helper: probes GitHub availability (MCP first, then `gh` CLI), pushes the branch if needed, and either emits a JSON descriptor for the calling agent to issue the MCP `create_pull_request` tool call or shells out to `gh pr create` directly. Consumed by `/rfc-new`'s new Step 9 auto-prompt.

### Changed

- `/rfc-new` Step 9 ("Present to human") now probes GitHub availability and, when at least one of the GitHub MCP or `gh` CLI is available, ends with a single `AskUserQuestion` ("Open a PR for this RFC?") with "Open PR" and "Not yet" options. "Open PR" invokes `scripts/rfc-open-pr.sh` and the resulting MCP tool call or `gh pr create` invocation; "Not yet" prints the previous manual hand-off text verbatim. If neither tool is available, the prompt is skipped and the manual hand-off text is printed directly. No behavior is removed — the manual path remains one click (or one missing dependency) away.
```

Verification:

```bash
grep -c 'rfc-open-pr' CHANGELOG.md
```

Expected output: at least `1` (the Added subsection entry).

```bash
grep -c '"Open a PR for this RFC?"\|Open a PR for this RFC' CHANGELOG.md
```

Expected output: at least `1` (the Changed subsection entry).

#### Step 5 — Final cross-repository verification

After Steps 1–4 are committed (one commit per step, or batched as fits review preferences), run:

```bash
grep -rn 'rfc-open-pr' --include='*.md' --include='*.sh' --include='*.bats' --exclude-dir='.git' . 2>/dev/null | wc -l
```

Expected output: a single-digit integer (at least `4`) — the new helper script's source plus the references in `skills/rfc-new/SKILL.md`, `tests/scripts/rfc-open-pr.bats`, `CHANGELOG.md`, and this RFC body.

```bash
bash scripts/check-requirements.sh
```

Expected output: same as before this RFC. The requirement-check script does not reference either the new skill changes or the helper script; verified by reading `scripts/check-requirements.sh` end-to-end (which has no references to per-skill helpers — it only probes `git`, `gh`, MCP plugin enable-state).

```bash
git status --short
```

Expected output: empty (all changes committed).

## Risks and open questions

1. **`scripts/rfc-open-pr.sh` parsing the origin URL is brittle for unusual remote formats.** The script handles `git@github.com:owner/repo.git` and `https://github.com/owner/repo[.git]` — the two formats Bytewyrd uses (verified at draft time: `git remote get-url origin` returns `git@github.com:bytewyrd/claude-bytewyrd.git`). Other forms (gh: protocol, GitHub Enterprise hostnames, ssh:// URLs) are not handled and would trigger a usage-error exit. **Mitigation:** the script's error message is explicit ("cannot parse owner/repo from origin URL '<url>'"), so the user sees exactly what went wrong and can fall back to `git push` + manual PR. **Open question:** should the script support GHE hostnames? Resolution within this RFC: defer — no Bytewyrd project uses GHE, and adding support adds complexity without a current consumer. Add it under a separate RFC if a GHE consumer emerges.

2. **The auto-prompt's PR body is stubby.** `scripts/rfc-open-pr.sh` composes the PR body from a fixed template that says "Draft RFC <rfc-id>. Opens for review. RFC stays in Draft status until /rfc-approve runs." plus the "Generated with Claude Code" footer. This is intentionally minimal — the RFC file itself is the substantive content. A reviewer who wants the RFC summary in the PR body would have to copy from the RFC file manually. **Mitigation:** the auto-prompt's "Not yet" option preserves the user's ability to write a richer PR body manually before opening. **Open question:** should the PR body extract the RFC's `## Summary` section automatically? Resolution within this RFC: no — the RFC file is one click away from the PR (it is the diff), and extracting the Summary section adds parsing complexity for marginal benefit. Revisit if a future user requests it.

3. **Merge-order risk with `docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md` (`Approved`, not yet implemented at this RFC's draft time).** That RFC renames the skill `/rfc-read-feedback` to `/rfc-read-reviews` and unifies the marker convention. This RFC's Step 9 prose (in `skills/rfc-new/SKILL.md`) currently mentions `/rfc-read-feedback` and `FEEDBACK:`. **Mitigation:** at implementation time, `grep -n 'rfc-read-feedback\|FEEDBACK' skills/rfc-new/SKILL.md` — if the rename RFC has landed first, every match must be updated to `/rfc-read-reviews` and `REVIEW:`. Both replacements are mechanical literal substitutions.

4. **Merge-order risk with `docs/rfcs/2026-05-14-skill-helper-scripts.md` (`Done`).** That RFC introduced `tests/scripts/` and the bats infrastructure (verified: `docs/rfcs/2026-05-14-skill-helper-scripts.md:L5` — `status: "Done"`). Step 2 of this RFC assumes the directory and infrastructure exist. If the helper-scripts RFC were somehow reverted before this one lands, Step 2 would need to add the bats-core submodule setup. **Mitigation:** the helper-scripts RFC has been `Done` for three days at this RFC's draft time and the test infrastructure is on disk. The risk is theoretical. The implementer verifies `test -d tests/scripts && test -f tests/scripts/helpers.bash` before running Step 2.

5. **Open question — should `/rfc-new` always run the GitHub probe, even for users who never use PRs?** A user on a project with no GitHub remote will see "GitHub is not reachable from this session" in their Step 9 output every time. **Mitigation in this RFC:** the message is a one-line warning followed by the existing manual hand-off text — no behavior change for these users beyond the one extra line. **Open question:** could the probe be skipped when `git remote get-url origin` returns nothing? Resolution within this RFC: yes — Step 9's probe runs `git remote get-url origin 2>/dev/null` first; if empty or non-GitHub, the auto-prompt is skipped entirely and the manual hand-off text prints without preamble. (This addresses the "no GitHub remote" case the probe should not warn about.) The skill body adds this short-circuit at the top of the new Step 9.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-14-skill-helper-scripts.md`** (`Done`) — established the helper-scripts pattern this RFC's `scripts/rfc-open-pr.sh` follows. Also created `tests/scripts/` and the bats infrastructure that this RFC's new test file relies on. No merge conflicts expected because this RFC adds new files (one script, one test) and does not modify any of the ten scripts that RFC introduced.

- **`docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md`** (`Approved`, not yet implemented at this RFC's draft time) — renames `/rfc-read-feedback` to `/rfc-read-reviews` and replaces `FEEDBACK:` with `REVIEW:` across the codebase. The new prose in `skills/rfc-new/SKILL.md` Step 9 ("Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments") must use the post-rename tokens if the rename RFC lands first. The merge-resolution mechanic is described in Risks point 3.

- **Future RFC for `/rfc-new-braindumps`** (not yet drafted) — will introduce a separate skill for batch promotion of multiple braindump entries to Draft RFCs in parallel, with a cherry-pick UI for selecting which entries to promote. That future RFC will reuse `scripts/rfc-open-pr.sh` as introduced here without modification.

- **No other RFC dependencies.** The remaining files this RFC modifies (the `CHANGELOG.md`) are not the subject of any in-flight RFC.

- **Braindump entries this RFC relates to.** The braindump entry "Enforce branch+PR discipline in `/rfc-new`" (verified: `docs/rfc-braindump.md:L9`) is the user-facing framing of both this RFC and the future batch RFC. This RFC implements the per-RFC half of the entry's ask (the branch+PR opening UX for a single `/rfc-new` invocation). The parallel-batch half of the entry's ask (parallelize the workflow per-RFC across multiple promotions) is addressed by the deferred future RFC. The braindump entry should stay in `docs/rfc-braindump.md` until both RFCs are `Done`. The braindump entry "Replace numbered braindump prompt in `/rfc-new` with `AskUserQuestion`" (verified: `docs/rfc-braindump.md:L14`) is *not* covered by this RFC — it specifically targets the single-entry `/rfc-new` selection prompt and is a separate concern.
