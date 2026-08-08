---
rfc: "2026-05-17-enforce-branch-pr-discipline-in-rfc-new"
title: "Enforce branch+PR discipline in /rfc-new"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

The `/rfc-new` skill currently writes a draft RFC directly to the working tree without enforcing that work happens on a feature branch — the human is expected to remember to create one, and bulk promotion of braindump entries to RFCs has historically been written straight to `main` in a single commit (commit `346fe6a` promoted 8 entries in one shot, with no per-RFC PR and no opportunity to reject individual drafts). This RFC makes branch creation a non-optional structural prerequisite: the skill probes the current branch before writing, refuses to proceed on `main`, creates a dedicated `rfc/<slug>` branch (via a new shared helper script), commits the draft on that branch, and then opens a PR per RFC. The braindump-promotion path forks the same enforcement: each selected entry produces one branch and one PR, never a batched commit.

## Should we do this?

**Yes.** The failure already happened on `main` (commit `346fe6a`) and the user added explicit project memory (`feedback_rfc_new_pr_required.md`) forbidding the pattern. Verbal guidance to the agent is insufficient — the very next bulk promotion under time pressure will re-incur the same shortcut unless the skill structurally refuses. The cost is small (one new helper script, a few new steps in `/rfc-new`, a test file) and the alternative — relying on agent discipline — has already proven inadequate. The companion RFC `2026-05-17-auto-prompt-pr-and-parallelize-rfc-new-braindumps` (referenced in the user's task description but not yet drafted) addresses the *PR-opening prompt* and *parallelization* of braindump promotion; this RFC addresses the upstream *branch* prerequisite that those features depend on.

## Current state

The current `/rfc-new` skill (`skills/rfc-new/SKILL.md`) has 9 steps:

1. Get description (from argument or braindump menu)
2. Scope check
3. Generate RFC identifier (today's date)
4. Derive kebab-case filename
5. Write the template file
6. Remove promoted braindump entry (if applicable)
7. Spawn `rfc-architect` to fill in the RFC
8. Run consensus review and fix loop
9. Present to human (`verified: skills/rfc-new/SKILL.md:L142-149`)

The final step ends with the literal text "Do **not** commit automatically" (`verified: skills/rfc-new/SKILL.md:L149`). Nothing in the skill body asks what branch the agent is on, nothing creates a branch, and nothing opens a PR. The human is left to do all three.

The companion `/rfc-implement` skill *does* check for GitHub tooling availability via `scripts/tool-probe.sh github-mcp` and `scripts/tool-probe.sh gh` (`verified: skills/rfc-implement/SKILL.md:L13-21`) and assumes a PR will be opened at the end, but it inherits whatever branch the agent happened to be on rather than enforcing one.

The empirical failure mode: commit `346fe6a` on `main` ("docs(rfc): promote all 8 braindump entries to full Draft RFCs", `verified: git show --stat 346fe6a`) added 5,650 lines across 8 new RFC files plus the braindump cleanup, with `Co-Authored-By: Claude Sonnet 4.6` — i.e., the agent landed all 8 directly on `main` in one shot. No PR existed for any of those 8 RFCs; they could not be rejected individually; review happened (if at all) after the fact. The user's project memory `feedback_rfc_new_pr_required.md` documents this:

> Never commit RFC files directly to the main branch. Each /rfc-new invocation must create its own branch and open a PR for review before the RFC lands on main. […] When promoting multiple braindump entries to full RFCs, they were bulk-committed directly to main in a single commit (346fe6a) instead of creating individual branches and PRs. This violated the intended workflow.

The convention `rfc/<slug>` for branch names already exists in practice — the current branch as this RFC is being drafted is `rfc/2026-05-17-enforce-branch-pr-discipline-in-rfc-new` (`verified: git symbolic-ref --short HEAD`). It just isn't enforced by the skill.

There is no separate `/rfc-new-braindumps` skill in the codebase — the braindump-promotion path is the no-argument branch of `/rfc-new` Step 1, which lists entries and prompts the user to pick one (`verified: skills/rfc-new/SKILL.md:L14-23`). "Bulk promotion" today is the human running `/rfc-new` repeatedly, picking a number each time; the `346fe6a` failure was the agent compressing those repeated invocations into one commit on `main`.

## Analysis / Options

### Option A — Enforce structurally in the skill body (recommended)

Add a new step early in `/rfc-new` — before the template file is written — that:

1. Probes the current branch via a new shared helper script `scripts/git-current-branch.sh` that returns `{"branch": "..."}` plus a JSON `protected` boolean indicating whether the branch matches a configurable list of protected names (default: `main`, `master`).
2. If `protected` is `true`, the skill **refuses to write the template** until a `rfc/<slug>` branch exists. It does not silently switch — it surfaces the situation to the human and offers two paths: (a) create the branch now via `git checkout -b rfc/<slug>`, or (b) abort and let the human position themselves.
3. After the template is written and the consensus-review loop completes, a new final step commits the draft on the `rfc/<slug>` branch, pushes it, and opens a PR (MCP-first, `gh` fallback — the pattern already used by `/rfc-implement`).

Refusal is structural: the script returns a non-zero exit code on `main`, and the skill body checks the exit code with `set -e`-style discipline already used by other steps. The agent cannot bypass it without rewriting the skill.

**Variant** — *worktree-based isolation.* Instead of `git checkout -b`, the skill could offer `git worktree add .worktrees/<slug> -b rfc/<slug>`. This is the convention documented in the user's global `CLAUDE.md` ("Step 2 — Starting new work […] Use the `using-git-worktrees` skill to create an isolated worktree + branch", `verified: ~/.claude/CLAUDE.md:L98-101`). The worktree variant is preferable when the user is mid-work on another branch (e.g., implementing a different RFC). The skill offers both and asks: "Use a worktree (recommended for parallel work) or check out the branch in-place?" This is a UX choice, not an architectural change; the structural enforcement (refusing `main`) is the same in both variants.

**Pros:** The mechanism is the skill itself. Agents that follow skill bodies (which is the norm for Bytewyrd skills) cannot land on `main` without explicit human override. The check is cheap (one `git symbolic-ref` call). The variant set covers both single-RFC and parallel-RFC ergonomics.

**Cons:** Adds two steps to `/rfc-new` (branch check + commit/PR). A determined agent could still bypass by editing files outside the skill flow — but that is true of any skill, and the goal here is to remove the *easy* path to the failure, not to make it cryptographically impossible.

### Option B — Hook-based enforcement (rejected)

A `PreToolUse` hook on `Write` could refuse any write to `docs/rfcs/*.md` from a branch matching `main`/`master`. This is broader (catches non-skill writes too) but:

- Hooks fire on every `Write` regardless of context. A human deliberately fixing a typo on `main` for a typo-only update would be blocked.
- Hook output is harder to discover and debug than skill-body messages.
- The plugin already has a `SessionStart` hook (`scripts/check-requirements.sh`) and adding another hook expands the project's hook surface for one workflow.
- The failure mode is not "Write happens unexpectedly" — it is "the skill itself orchestrates a Write on `main`." Enforcing inside the orchestrating skill is the smaller, more precise fix.

Rejected. The skill is the right enforcement point.

### Option C — Pre-commit hook in the project repo (rejected)

A Git `pre-commit` hook that refuses commits adding `docs/rfcs/*.md` files on `main` would catch the failure at commit time. But:

- Pre-commit hooks live in `.git/hooks/` by default, are not committed to the repo, and require setup per clone. The plugin would have to ship and install them via `/sync`, adding complexity.
- The hook catches the failure too late — after the agent has already done the work and is trying to commit. Refusing structurally *before* the write is cheaper.
- Pre-commit hooks can be bypassed with `git commit --no-verify`. The Claude Code agent harness forbids `--no-verify` without explicit human authorization, but an agent under pressure may still attempt it; the skill-body check is one fewer fallback path. [UNVERIFIED — searched `~/.claude/CLAUDE.md` and the project `CLAUDE.md` for explicit `--no-verify` policy and found no project-level rule; the prohibition appears in the agent's tool-use guidance rather than in repo-checked documentation, so cite as agent-harness convention rather than project rule.]

Rejected. The skill is the right enforcement point.

## Drawbacks

- **Two extra steps in the user-facing flow.** Today `/rfc-new` ends with "Present to human"; this adds "commit on branch" and "open PR." For users who want only a local draft, this is friction. Mitigation: the final commit/PR step is gated on `gh`/`github-mcp` availability via the same probe pattern `/rfc-implement` uses — if neither is present, the skill commits to the branch but skips the PR, prints a hint, and exits cleanly. The branch enforcement still applies (no commit to `main`) but the PR is best-effort.

- **Friction for the existing in-place edit pattern.** A human who is already on `rfc/<slug>` from a previous `/rfc-read-feedback` session and wants to draft a different RFC will be on a branch named for the wrong RFC. The branch-check step must handle this case: if the current branch matches `rfc/.*` but the slug differs from the new RFC's slug, the skill surfaces this and asks whether to create a new branch or stay on the current one.

- **GitHub-only assumption.** The skill assumes the project hosts on GitHub (PR via `gh` or GitHub MCP). For projects on GitLab or other hosts, the PR step is skipped (no PR-creation path is implemented for non-GitHub hosts in the plugin today; this is consistent with `/rfc-implement`'s current behavior). Branch enforcement still applies regardless of host.

- **Branch name collisions on same-day RFCs.** If two RFCs are drafted on the same day with similar titles, the slugs collide. The skill must detect an existing `rfc/<slug>` branch (local or remote) and surface the collision — same handling as the same-day RFC-identifier collision the RFC process already accepts as rare.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/git-current-branch.sh` | Probe the current branch; report whether it matches a protected name. Returns JSON `{"branch": "<name>", "protected": true\|false, "protected_names": ["main","master"]}`. |
| Create | `scripts/rfc-branch-prepare.sh` | Given an RFC slug, decide whether the current branch is acceptable, surface a structured JSON decision to the skill body, and (when the human approves) create the `rfc/<slug>` branch via either `git checkout -b` or `git worktree add`. Wraps `git-current-branch.sh`. |
| Create | `tests/scripts/git-current-branch.bats` | bats-core tests for `scripts/git-current-branch.sh`. |
| Create | `tests/scripts/rfc-branch-prepare.bats` | bats-core tests for `scripts/rfc-branch-prepare.sh`. |
| Modify | `skills/rfc-new/SKILL.md` | Insert a new step ("Prepare RFC branch") after the filename is derived (current Step 4) and before the template is written (current Step 5), renumbering the subsequent steps. Replace the present-to-human step with a combined "Present to human, commit, and open PR" step that commits the draft on the `rfc/<slug>` branch and opens a PR via MCP/`gh`. |
| Modify | `docs/rfc-process.md` (Project Extensions section only) | Add a one-paragraph Project Extension documenting the branch-per-RFC convention (`rfc/<slug>`), the protected-branch refusal, and that `/rfc-new` enforces both. Upstream content (above `END_UPSTREAM_CONTENT`) is not touched. |

### Steps

#### Step 1 — Add `scripts/_lib/common.bash` helper for protected-branch list

The protected-branch list (default `main`, `master`) is small enough that a constant in the new scripts is acceptable rather than introducing a config file. No change to `scripts/_lib/common.bash` is required for this RFC.

Decision recorded here for clarity: both new scripts declare a local bash array `PROTECTED_BRANCHES=(main master)` at the top. If a future RFC wants per-project override, that RFC can introduce a config file and update both scripts; this RFC does not.

#### Step 2 — Create `scripts/git-current-branch.sh`

Create the file with this exact content:

```bash
#!/usr/bin/env bash
# Report the current git branch and whether it is a protected branch.
# Used by: rfc-branch-prepare.sh and any future skill that must refuse to
# write to a protected branch.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"branch": "<name>", "protected": true|false, "protected_names": ["main","master"]}
#     not-a-git-repo (exit 2):
#       {"error": "<message>"}
#     detached HEAD (exit 2):
#       {"error": "detached HEAD (no current branch)"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Branch resolved successfully.
#   2  Not inside a git repo, or HEAD is detached.

set -uo pipefail
# shellcheck source=_lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib/common.bash"
require_jq

PROTECTED_BRANCHES=(main master)

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit_error "not inside a git work tree"
  exit 2
fi

branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
if [ -z "$branch" ]; then
  emit_error "detached HEAD (no current branch)"
  exit 2
fi

is_protected=false
for p in "${PROTECTED_BRANCHES[@]}"; do
  if [ "$branch" = "$p" ]; then
    is_protected=true
    break
  fi
done

jq -n \
  --arg branch "$branch" \
  --argjson protected "$is_protected" \
  --argjson names "$(printf '%s\n' "${PROTECTED_BRANCHES[@]}" | jq -R . | jq -s .)" \
  '{branch: $branch, protected: $protected, protected_names: $names}'
```

Make it executable:

```bash
chmod +x scripts/git-current-branch.sh
```

**Verification command:**

```bash
bash scripts/git-current-branch.sh
```

**Expected output (on a feature branch named `rfc/foo`):**

```json
{"branch":"rfc/foo","protected":false,"protected_names":["main","master"]}
```

**Expected output (on `main`):**

```json
{"branch":"main","protected":true,"protected_names":["main","master"]}
```

**Expected output (detached HEAD, exit code 2):**

```json
{"error":"detached HEAD (no current branch)"}
```

#### Step 3 — Create `scripts/rfc-branch-prepare.sh`

Create the file with this exact content:

```bash
#!/usr/bin/env bash
# Decide whether the current branch is acceptable for drafting an RFC with the
# given slug, and optionally create a new branch when the caller asks for it.
#
# This script has two modes:
#   1. Probe mode (default, no --create flag):
#        Inspect the current branch, decide one of three actions, and return a
#        structured JSON decision so the skill body can prompt the human. The
#        script does not mutate the repo in probe mode.
#   2. Create mode (--create=branch | --create=worktree):
#        Create the rfc/<slug> branch via the requested method. Exits non-zero
#        if creation fails or the branch already exists with a different ref.
#
# Args:
#   $1                Required. The RFC slug (e.g. 2026-05-17-foo). No leading
#                     "rfc/" prefix; the script adds it.
#   --create=<mode>   Optional. Mode is "branch" (git checkout -b) or
#                     "worktree" (git worktree add .worktrees/<slug>).
#
# Output (probe mode):
#   stdout: a single JSON object.
#     ok-current (exit 0): current branch already matches rfc/<slug>; nothing to do
#       {"action": "ok-current", "branch": "rfc/<slug>"}
#     ok-other-rfc (exit 0): current branch is some other rfc/<x>; ask the human
#       {"action": "ok-other-rfc", "current": "rfc/<x>", "wanted": "rfc/<slug>"}
#     needs-create (exit 0): on a protected branch (or a non-rfc/* branch); must create
#       {"action": "needs-create", "current": "<name>", "wanted": "rfc/<slug>", "protected": true|false}
#     conflict (exit 1): wanted branch already exists locally with a different ref
#       {"action": "conflict", "wanted": "rfc/<slug>", "error": "<message>"}
#
# Output (create mode):
#   stdout: a single JSON object.
#     created (exit 0):
#       {"action": "created", "mode": "branch|worktree", "branch": "rfc/<slug>", "path": "<absolute-path>"}
#     error (exit 1):
#       {"error": "<message>"}
#
# Exit codes:
#   0  Decision returned (probe) or branch created (create).
#   1  Conflict or creation failure.
#   2  Usage error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib/common.bash
source "$SCRIPT_DIR/_lib/common.bash"
require_jq

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-branch-prepare.sh <slug> [--create=branch|--create=worktree]"
  exit 2
fi
slug="$1"
case "$slug" in
  rfc/*) emit_error "slug must not include the rfc/ prefix (got: $slug)"; exit 2 ;;
  */*)   emit_error "slug must not contain '/' (got: $slug)"; exit 2 ;;
esac
wanted="rfc/$slug"

create_mode=""
if [ "${2:-}" != "" ]; then
  case "$2" in
    --create=branch)   create_mode="branch" ;;
    --create=worktree) create_mode="worktree" ;;
    *) emit_error "unknown flag: $2"; exit 2 ;;
  esac
fi

# Resolve current branch via the sibling helper.
probe="$(bash "$SCRIPT_DIR/git-current-branch.sh")"
probe_status=$?
if [ "$probe_status" -ne 0 ]; then
  emit_error "git-current-branch.sh failed: $(printf '%s' "$probe" | jq -r .error)"
  exit 2
fi
current="$(printf '%s' "$probe" | jq -r .branch)"
is_protected="$(printf '%s' "$probe" | jq -r .protected)"

# ---- Create mode -----------------------------------------------------------
if [ -n "$create_mode" ]; then
  # Refuse to create if the wanted branch already exists with a different ref
  # than HEAD — caller should resolve manually.
  if git show-ref --verify --quiet "refs/heads/$wanted"; then
    head_ref="$(git rev-parse HEAD)"
    branch_ref="$(git rev-parse "$wanted")"
    if [ "$head_ref" != "$branch_ref" ]; then
      jq -n --arg wanted "$wanted" --arg msg "branch $wanted already exists at a different ref; resolve manually" \
        '{action: "conflict", wanted: $wanted, error: $msg}'
      exit 1
    fi
  fi

  case "$create_mode" in
    branch)
      if ! git checkout -b "$wanted" 2>/dev/null; then
        # Branch may already exist and point at HEAD — just switch.
        if ! git checkout "$wanted" 2>/dev/null; then
          emit_error "failed to create or switch to branch $wanted"
          exit 1
        fi
      fi
      abs="$(git rev-parse --show-toplevel)"
      jq -n --arg branch "$wanted" --arg path "$abs" \
        '{action: "created", mode: "branch", branch: $branch, path: $path}'
      exit 0
      ;;
    worktree)
      wt_path=".worktrees/$slug"
      if [ -e "$wt_path" ]; then
        emit_error "worktree path $wt_path already exists"
        exit 1
      fi
      if ! git worktree add "$wt_path" -b "$wanted" 2>/dev/null; then
        # Branch may already exist; try adding without -b.
        if ! git worktree add "$wt_path" "$wanted" 2>/dev/null; then
          emit_error "failed to create worktree at $wt_path for $wanted"
          exit 1
        fi
      fi
      abs="$(cd "$wt_path" && pwd)"
      jq -n --arg branch "$wanted" --arg path "$abs" \
        '{action: "created", mode: "worktree", branch: $branch, path: $path}'
      exit 0
      ;;
  esac
fi

# ---- Probe mode ------------------------------------------------------------
# Case 1: already on the wanted branch.
if [ "$current" = "$wanted" ]; then
  jq -n --arg branch "$wanted" '{action: "ok-current", branch: $branch}'
  exit 0
fi

# Case 2: on some other rfc/* branch.
case "$current" in
  rfc/*)
    jq -n --arg current "$current" --arg wanted "$wanted" \
      '{action: "ok-other-rfc", current: $current, wanted: $wanted}'
    exit 0
    ;;
esac

# Case 3: on a protected branch or any other non-rfc/* branch — need to create.
# Pre-flight collision check: if rfc/<slug> already exists locally with a
# different ref than HEAD, surface the conflict before the skill asks the human.
if git show-ref --verify --quiet "refs/heads/$wanted"; then
  head_ref="$(git rev-parse HEAD)"
  branch_ref="$(git rev-parse "$wanted")"
  if [ "$head_ref" != "$branch_ref" ]; then
    jq -n --arg wanted "$wanted" --arg msg "branch $wanted already exists at a different ref; resolve manually" \
      '{action: "conflict", wanted: $wanted, error: $msg}'
    exit 1
  fi
fi

jq -n --arg current "$current" --arg wanted "$wanted" --argjson protected "$is_protected" \
  '{action: "needs-create", current: $current, wanted: $wanted, protected: $protected}'
exit 0
```

Make it executable:

```bash
chmod +x scripts/rfc-branch-prepare.sh
```

**Verification commands and expected outputs:**

Probe on `main`:

```bash
bash scripts/rfc-branch-prepare.sh 2026-05-17-foo
```

```json
{"action":"needs-create","current":"main","wanted":"rfc/2026-05-17-foo","protected":true}
```

Probe when already on `rfc/2026-05-17-foo`:

```json
{"action":"ok-current","branch":"rfc/2026-05-17-foo"}
```

Probe when on a different `rfc/*` branch:

```json
{"action":"ok-other-rfc","current":"rfc/2026-05-14-other","wanted":"rfc/2026-05-17-foo"}
```

Create mode (in-place):

```bash
bash scripts/rfc-branch-prepare.sh 2026-05-17-foo --create=branch
```

```json
{"action":"created","mode":"branch","branch":"rfc/2026-05-17-foo","path":"/path/to/repo"}
```

#### Step 4 — Create `tests/scripts/git-current-branch.bats`

Create the file with this exact content (using the same `helpers.bash` conventions as the existing scripts/*.bats files):

```bash
#!/usr/bin/env bats
# Tests for scripts/git-current-branch.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/git-current-branch.sh"
  # Initialize a git repo inside the temp dir so the script has something to probe.
  git init -q -b main
  git -c user.email=test@example.com -c user.name=Test commit --allow-empty -q -m init
}

teardown() {
  teardown_common
}

@test "on main — protected is true" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .branch)" "main"
  assert_equal "$(echo "$output" | jq -r .protected)" "true"
}

@test "on rfc/foo — protected is false" {
  git checkout -q -b rfc/foo
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .branch)" "rfc/foo"
  assert_equal "$(echo "$output" | jq -r .protected)" "false"
}

@test "on master — protected is true" {
  git checkout -q -b master
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(echo "$output" | jq -r .protected)" "true"
}

@test "protected_names always includes main and master" {
  run bash "$SCRIPT"
  assert_success
  names="$(echo "$output" | jq -c '.protected_names')"
  assert_equal "$names" '["main","master"]'
}

@test "detached HEAD — exits 2 with error" {
  # Detach HEAD onto the current commit.
  sha="$(git rev-parse HEAD)"
  git checkout -q "$sha"
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "not a git repo — exits 2 with error" {
  # Move outside the git dir; helpers.bash mkdir'd docs/ but TEST_TMPDIR is the repo root.
  outside="$(mktemp -d)"
  cd "$outside"
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
  rm -rf "$outside"
}
```

**Verification command:**

```bash
bats tests/scripts/git-current-branch.bats
```

**Expected output (last lines):**

```
1..6
ok 1 on main — protected is true
ok 2 on rfc/foo — protected is false
ok 3 on master — protected is true
ok 4 protected_names always includes main and master
ok 5 detached HEAD — exits 2 with error
ok 6 not a git repo — exits 2 with error
```

#### Step 5 — Create `tests/scripts/rfc-branch-prepare.bats`

Create the file with this exact content:

```bash
#!/usr/bin/env bats
# Tests for scripts/rfc-branch-prepare.sh

setup() {
  load "helpers"
  setup_common
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-branch-prepare.sh"
  git init -q -b main
  git -c user.email=test@example.com -c user.name=Test commit --allow-empty -q -m init
}

teardown() {
  teardown_common
}

# ---- Probe mode -------------------------------------------------------------

@test "probe on main — action is needs-create with protected=true" {
  run bash "$SCRIPT" 2026-05-17-foo
  assert_success
  assert_equal "$(echo "$output" | jq -r .action)" "needs-create"
  assert_equal "$(echo "$output" | jq -r .protected)" "true"
  assert_equal "$(echo "$output" | jq -r .wanted)" "rfc/2026-05-17-foo"
}

@test "probe on rfc/<slug> matching wanted — action is ok-current" {
  git checkout -q -b rfc/2026-05-17-foo
  run bash "$SCRIPT" 2026-05-17-foo
  assert_success
  assert_equal "$(echo "$output" | jq -r .action)" "ok-current"
}

@test "probe on a different rfc/<x> — action is ok-other-rfc" {
  git checkout -q -b rfc/2026-05-14-other
  run bash "$SCRIPT" 2026-05-17-foo
  assert_success
  assert_equal "$(echo "$output" | jq -r .action)" "ok-other-rfc"
  assert_equal "$(echo "$output" | jq -r .current)" "rfc/2026-05-14-other"
}

@test "probe with collision — exits 1 with conflict" {
  # Create rfc/2026-05-17-foo on a different commit than HEAD.
  git checkout -q -b rfc/2026-05-17-foo
  git -c user.email=test@example.com -c user.name=Test commit --allow-empty -q -m second
  git checkout -q main
  # Now main is at the original commit, rfc/2026-05-17-foo is one ahead.
  run bash "$SCRIPT" 2026-05-17-foo
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .action)" "conflict"
}

@test "slug with rfc/ prefix — exits 2 with usage error" {
  run bash "$SCRIPT" rfc/2026-05-17-foo
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "slug with slash — exits 2 with usage error" {
  run bash "$SCRIPT" 2026/05/17/foo
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}

@test "no argument — exits 2 with usage error" {
  run bash "$SCRIPT"
  assert_failure 2
}

# ---- Create mode ------------------------------------------------------------

@test "create=branch on main — switches to rfc/<slug>" {
  run bash "$SCRIPT" 2026-05-17-foo --create=branch
  assert_success
  assert_equal "$(echo "$output" | jq -r .action)" "created"
  assert_equal "$(echo "$output" | jq -r .mode)" "branch"
  current="$(git symbolic-ref --short HEAD)"
  assert_equal "$current" "rfc/2026-05-17-foo"
}

@test "create=worktree — creates .worktrees/<slug> directory" {
  run bash "$SCRIPT" 2026-05-17-foo --create=worktree
  assert_success
  assert_equal "$(echo "$output" | jq -r .mode)" "worktree"
  assert [ -d ".worktrees/2026-05-17-foo" ]
  # Worktree branch should be rfc/<slug>.
  branch_in_wt="$(cd .worktrees/2026-05-17-foo && git symbolic-ref --short HEAD)"
  assert_equal "$branch_in_wt" "rfc/2026-05-17-foo"
}

@test "create=branch when branch already exists at HEAD — succeeds and switches" {
  git checkout -q -b rfc/2026-05-17-foo
  git checkout -q main
  run bash "$SCRIPT" 2026-05-17-foo --create=branch
  assert_success
  current="$(git symbolic-ref --short HEAD)"
  assert_equal "$current" "rfc/2026-05-17-foo"
}

@test "create when branch exists at different ref — exits 1 with conflict" {
  git checkout -q -b rfc/2026-05-17-foo
  git -c user.email=test@example.com -c user.name=Test commit --allow-empty -q -m second
  git checkout -q main
  run bash "$SCRIPT" 2026-05-17-foo --create=branch
  assert_failure 1
  assert_equal "$(echo "$output" | jq -r .action)" "conflict"
}

@test "unknown create mode — exits 2 with usage error" {
  run bash "$SCRIPT" 2026-05-17-foo --create=potato
  assert_failure 2
}
```

**Verification command:**

```bash
bats tests/scripts/rfc-branch-prepare.bats
```

**Expected output (last lines):**

```
1..12
ok 1 probe on main — action is needs-create with protected=true
ok 2 probe on rfc/<slug> matching wanted — action is ok-current
ok 3 probe on a different rfc/<x> — action is ok-other-rfc
ok 4 probe with collision — exits 1 with conflict
ok 5 slug with rfc/ prefix — exits 2 with usage error
ok 6 slug with slash — exits 2 with usage error
ok 7 no argument — exits 2 with usage error
ok 8 create=branch on main — switches to rfc/<slug>
ok 9 create=worktree — creates .worktrees/<slug> directory
ok 10 create=branch when branch already exists at HEAD — succeeds and switches
ok 11 create when branch exists at different ref — exits 1 with conflict
ok 12 unknown create mode — exits 2 with usage error
```

#### Step 6 — Modify `skills/rfc-new/SKILL.md` — insert new "Prepare RFC branch" step

Insert the following block immediately after the existing Step 4 ("Derive filename") and before the existing Step 5 ("Write the template file"). The new step becomes Step 5 of the renumbered skill; what is currently Step 5 ("Write the template file") becomes Step 6, what is currently Step 6 ("Remove promoted braindump entry") becomes Step 7, and so on through what is currently Step 9 ("Present to human") becoming Step 10 (then replaced wholesale in Step 7 of this implementation spec).

```markdown
### 5. Prepare RFC branch

Derive the slug from the filename (the part between `docs/rfcs/` and `.md`). Probe the current branch with the new helper script:

```bash
result="$(bash scripts/rfc-branch-prepare.sh "$SLUG")"
action="$(printf '%s' "$result" | jq -r .action)"
```

Where `$SLUG` is the filename stem (e.g. `2026-05-17-enforce-branch-pr-discipline-in-rfc-new`).

Branch on `$action`:

- **`ok-current`**: the branch already matches `rfc/$SLUG`. Proceed to the next step.
- **`ok-other-rfc`**: the current branch is some other `rfc/<x>`. Ask the human: "You are on `<current>` but this RFC's branch is `rfc/<slug>`. Create a new branch for this RFC, or stay on the current one?" If they say "stay", proceed. If they say "create", continue as if `$action` were `needs-create`.
- **`needs-create`**: the current branch is protected or non-`rfc/*`. Ask the human: "Current branch is `<current>`. This skill refuses to write RFC files on protected branches. Create `rfc/<slug>` in place (`git checkout -b`), or as a worktree (`git worktree add .worktrees/<slug>`)?" Then re-invoke the script with the chosen mode:

  ```bash
  result="$(bash scripts/rfc-branch-prepare.sh "$SLUG" --create=branch)"
  # or --create=worktree
  path="$(printf '%s' "$result" | jq -r .path)"
  ```

  If the mode is `worktree`, instruct the human: "Switch to the worktree at `<path>` to continue. Re-run `/rfc-new` from inside the worktree." Stop the skill — the rest of the work must happen inside the new worktree so the file lands on the right branch.

  If the mode is `branch`, proceed to the next step.
- **`conflict`** (script exited 1): the branch already exists at a different ref. Show `$result.error` and stop. The human must resolve the conflict (delete, rename, or rebase the existing branch) and re-run `/rfc-new`.

If the script exited 2 (usage error or not in a git repo), abort the skill and show the error.

**Refusal is non-optional.** If the human declines to create a branch on the `needs-create` path, the skill stops without writing the template. There is no "write anyway" escape hatch in the skill body.
```

#### Step 7 — Modify `skills/rfc-new/SKILL.md` — update old Step 9 to old Step 10

What was Step 9 ("Present to human") becomes Step 10 (after the renumbering in Step 6 above). Replace its body with:

```markdown
### 10. Present to human, commit, and open PR

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

**Commit the draft on the `rfc/<slug>` branch:**

```bash
git add "$RFC_PATH"
git commit -m "docs(rfc): add draft RFC $SLUG"
```

Where `$RFC_PATH` is the absolute path to the RFC file written in the renumbered Step 6 ("Write the template file"), `$SLUG` is the filename stem derived in the renumbered Step 4 ("Derive filename"), and `$TITLE` (used below) is the title from the YAML frontmatter written in the renumbered Step 6.

**Probe GitHub tooling availability** (same pattern as `/rfc-implement`):

```bash
mcp_out="$(bash scripts/tool-probe.sh github-mcp)"; mcp_status=$?
gh_out="$(bash scripts/tool-probe.sh gh)";           gh_status=$?
mcp_result="$(printf '%s' "$mcp_out" | jq -r .result)"
gh_result="$(printf '%s' "$gh_out"  | jq -r .result)"
```

Branch on results:

- `mcp_status=0` → push the branch with `git push -u origin "rfc/$SLUG"` and create the PR via `mcp__plugin_github_github__create_pull_request` with title `RFC: $TITLE`, base `main`, head `rfc/$SLUG`, body `Draft RFC for review. File: docs/rfcs/$SLUG.md`. Print: `Opened PR for rfc/$SLUG using GitHub MCP.` Surface the PR URL returned by the MCP tool.
- `mcp_status!=0 && gh_status=0` → push the branch and create the PR via `gh pr create --base main --head "rfc/$SLUG" --title "RFC: $TITLE" --body "Draft RFC for review. File: docs/rfcs/$SLUG.md"`. Print: `GitHub MCP not enabled — opened PR for rfc/$SLUG using gh CLI.` Surface the PR URL printed by `gh`.
- both nonzero → print: `Branch rfc/$SLUG committed locally. Cannot open PR: neither GitHub MCP nor gh CLI is available. Fix: install github@claude-plugins-official OR install gh CLI and run gh auth login.` (Use `printf '%s' "$gh_out" | jq -r .hint` and the matching hint from `$mcp_out` to phrase the remediation precisely.) The branch enforcement still held — the commit is on `rfc/$SLUG`, not `main`. The PR is best-effort.

Do **not** merge the PR automatically. The PR stays open until the human reviews and either merges (via `/rfc-approve` follow-up or directly on GitHub) or closes it.
```

#### Step 8 — Modify `docs/rfc-process.md` (Project Extensions section)

The upstream content (lines above `<!-- END_UPSTREAM_CONTENT -->`) is not touched. Inside the `## Project Extensions` section at the end of the file, replace the placeholder `*(no project-specific extensions — the global process applies as-is)*` with this paragraph:

```markdown
**Branch-per-RFC convention.** Every RFC drafted via `/rfc-new` is committed on a dedicated `rfc/<slug>` branch and surfaced as a pull request before landing on `main`. The skill enforces this structurally: `scripts/git-current-branch.sh` probes the current branch and `scripts/rfc-branch-prepare.sh` refuses to let the skill write RFC files on protected branches (`main`, `master`). Bulk braindump promotion (running `/rfc-new` multiple times for queued braindump entries) produces one branch and one PR per RFC — never a single batched commit. The enforcement is non-optional within the skill: there is no "draft to main anyway" path. To draft a quick-edit fix to an existing RFC outside the skill flow (e.g. fixing a typo), the human is on their own; this convention governs new RFC creation, not arbitrary edits.
```

#### Step 9 — Run the full test suite to confirm no regressions

```bash
bats tests/scripts/
```

**Expected output (last line):**

```
... ok N
N total tests, 0 failures
```

(The new test files add 6 + 12 = 18 tests; the existing files contribute the rest. Both new test files must pass; no existing tests should change behavior.)

#### Step 10 — Verify `/rfc-new` end-to-end on a sandbox slug

Manual smoke test the human runs after the implementation lands:

```bash
git checkout main
/rfc-new "test branch enforcement smoke test"
# Expected: skill stops at Step 5 and asks whether to create a branch.
# Choose "create as branch in place".
# Expected: rfc/<today>-test-branch-enforcement-smoke-test branch is created.
# Expected: template is written into docs/rfcs/<today>-test-branch-enforcement-smoke-test.md.
# Expected: rfc-architect runs, consensus review runs.
# Expected: final step commits to the branch, pushes, and opens a PR.
# Cleanup: close the PR, delete the branch and the test RFC file.
```

This step is operational, not part of the implementation diff — it confirms the integration works end-to-end.

## Risks and open questions

- **Risk: `git push -u origin` requires network and credentials.** If the push fails (network down, no remote write permission, no `origin` remote configured), the commit is still on the local `rfc/<slug>` branch but no PR can be opened. The skill should detect the push failure and print: `Local commit succeeded on rfc/$SLUG, but push to origin failed. Push manually and open a PR with: git push -u origin rfc/$SLUG && gh pr create --base main --head rfc/$SLUG`. Implementation detail: wrap the push in a check that surfaces the failure non-fatally.

- **Risk: `git checkout -b` on a dirty working tree could surprise the human.** If the human has uncommitted changes when the skill creates the branch, those changes follow them onto the new branch. Mitigation: before calling `--create=branch`, the skill can check `git status --porcelain` and warn: "Uncommitted changes will follow you to the new branch. Continue, stash, or abort?" This is a UX refinement; the structural enforcement is unchanged.

- **Risk: same-day RFC slug collision.** If two RFCs are drafted on the same day with similar enough titles to produce the same slug, the `rfc/<slug>` branch already exists. The script returns `conflict` (exit 1) and the human must resolve. This is the same handling the RFC process already accepts for same-day RFC identifier collisions (`verified: docs/rfc-process.md:L72`: "Same-day collisions are avoided in practice by topics being different."). No special handling needed beyond surfacing the conflict.

- **Risk: the `Refusal is non-optional` posture is too rigid.** A human in a non-GitHub project or doing emergency work on `main` might want to override. **Decision:** the skill does not provide an override flag. The agent's failure mode is "compress everything into one commit"; an override flag re-introduces that path. A human who genuinely needs to bypass the enforcement can edit `docs/rfcs/<slug>.md` directly without running the skill — that is acceptable because it is an explicit human action, not an agent shortcut.

- **Open question: should the `/rfc-new` no-argument braindump-selection loop change?** The current flow lists entries and prompts the user to pick one number, which produces one RFC per invocation. The user's task description mentions "bulk braindump promotion should parallelize the branch+PR workflow per-RFC rather than batching multiple RFCs into a single commit." Today's flow already produces one RFC per invocation, so the failure was the agent compressing repeated invocations into one commit — that is exactly what this RFC fixes structurally (each invocation now produces its own branch and PR). The *parallelization* of bulk braindump promotion (running multiple `/rfc-new` invocations concurrently) is scoped to the companion RFC `2026-05-17-auto-prompt-pr-and-parallelize-rfc-new-braindumps`. This RFC's enforcement is the prerequisite that makes parallelization safe — without it, parallel invocations could all land on `main`.

- **Open question: should there be a `--worktree`/`--in-place` argument to `/rfc-new` so the human pre-chooses?** Today the choice is a prompt inside Step 5. Pre-choosing via skill argument would reduce one round-trip when the human already knows. **Decision:** out of scope for this RFC; the prompt is the simpler initial design. A follow-up can add the argument once the pattern proves out.

- **Open question: should `protected_names` be configurable via a `.bytewyrd/` config file?** Today the list is hard-coded to `main`, `master`. Projects with non-standard default branches (e.g. `trunk`, `develop`) would need to update the script. **Decision:** hard-coded for v1. The script declares the array at the top so it is one-line edit. If a real project surfaces a need, a follow-up RFC introduces a config file and the two scripts read from it.

## Relationship to other RFCs

- **`2026-05-17-auto-prompt-pr-and-parallelize-rfc-new-braindumps`** (companion RFC mentioned in the user's task description; not yet drafted at the time of this RFC). That RFC addresses (a) auto-prompting for PR creation rather than always opening one, and (b) parallelizing bulk braindump promotion. This RFC is the structural prerequisite: it makes branch-per-RFC non-optional, so the companion RFC's parallelization cannot accidentally re-introduce the `346fe6a` failure mode by spawning N parallel agents that all write to `main`. If the companion RFC lands first, it should defer to this RFC for the branch enforcement and only add the auto-prompt logic on top.

- **`2026-05-12-sync-enforce-github-branch-auto-delete`** (existing RFC). Addresses post-merge branch cleanup. Complementary: this RFC creates the `rfc/<slug>` branches; that RFC ensures they are deleted automatically after merge.

- **`2026-05-14-skill-helper-scripts`** (existing RFC, Done). Established the `scripts/_lib/common.bash` pattern and the JSON-output convention used by the two new scripts introduced here. This RFC extends that pattern; no conflict.

- No other RFCs in the Draft or Approved set conflict with the new branch enforcement.
