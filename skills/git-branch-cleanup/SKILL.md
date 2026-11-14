---
name: git-branch-cleanup
description: Clean up stale git branches and worktrees (local branches whose remote is gone, branches of merged PRs, abandoned remote branches). Triggered by "/git-branch-cleanup".
disable-model-invocation: true
---

# Git Branch Cleanup

## Overview

Systematically identify and remove stale branches across local, remote, and worktrees by combining git state with GitHub PR status. Always present a plan before deleting anything. Approving the plan covers only deletions that cannot lose work. `git branch -D`, `git worktree remove --force`, removing a worktree that holds ignored files, and deleting a remote branch that has commits missing from main all throw work away, so each one needs its own confirmation (step 4).

## Steps

### 1. Gather State

Refresh remote state first and let it finish. `[gone]` only appears in `git branch -v` after `git fetch --prune` has run, so this must not be parallel with the commands below:

```bash
git fetch --prune
```

Then run these in parallel:

```bash
git branch -v        # local: [gone], untracked, current
git worktree list    # active worktrees and their branches
git branch -r        # remote tracking branches
```

Then check GitHub PR status **one candidate branch at a time**, never from a bulk list. `gh pr list` fetches at most 30 PRs unless `--limit` says otherwise (this applies to `--state open` too), so a branch missing from a bulk list proves nothing:

```bash
gh pr list --head "$branch" --state all --json number,state,mergedAt,url
```

`$branch` is the bare branch name. Strip `origin/` from names that `git branch -r` prints: `--head` matches the name only, so `--head origin/foo` returns `[]` with exit 0 even when `foo` has an open PR.

- Any `OPEN` PR → keep the branch.
- `MERGED` → the branch is a deletion candidate.
- Only `CLOSED` (not merged) → keep it unless the user says the work is abandoned.
- An empty result means "no PR" only when `gh` exited 0 and `$branch` was the bare name. If `gh` fails (auth, network, wrong repository), stop and report that; never read a failure as "no PR".

### 2. Classify Each Branch

| Condition | Action |
|-----------|--------|
| Local branch with `[gone]` | Delete local (`-d` first, see step 4) |
| Local branch, no remote, PR is merged | Delete local (`-d` first) |
| Local branch, no remote, no PR | Ask the user: it may hold unmerged work (`-d` first; `-D` only on a per-branch yes) |
| Remote branch, PR merged, no commits missing from main | Delete remote |
| Remote branch, no local, no open PR, old | Delete remote only if it has no commits missing from main; otherwise ask the user |
| Branch has worktree + branch is being deleted | Remove worktree first |
| Branch has open PR | Keep |
| `main` / default branch | Keep |

**Check whether a remote branch holds commits that are not in main:**
```bash
git log --oneline origin/main..origin/branch-name
# empty = every commit on the branch is already in main
```

A remote branch that does have such commits may be the only copy of that work. The plan's approval does not cover it: show those commits and ask about that one branch before deleting it.

### 3. Present a Plan

Before deleting anything, show a table:

| Branch | Location | Reason |
|--------|----------|--------|
| `foo/bar` | local | [gone] — remote deleted |
| `origin/old-feature` | remote | merged PR #12, no commits missing from main |

Ask for confirmation, then execute. The plan approves only the deletions that cannot lose work: `git branch -d`, `git push origin --delete` for a branch with no commits missing from main, and `git worktree remove` for a worktree with nothing in it. It does not approve `git branch -D`, `git worktree remove --force`, or removing a worktree that holds ignored files.

### 4. Execute

Do these in order for each branch.

**1. Remove its worktree, if it has one.** Git refuses to delete a branch that a worktree has checked out.

```bash
worktree=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p}')
root=$(git rev-parse --show-toplevel)
if [ -n "$worktree" ] && [ "$worktree" != "$root" ]; then
  git -C "$worktree" status --short --ignored   # empty = nothing in it to lose
fi
```

If that printed nothing, run `git worktree remove "$worktree"`. If it printed anything, show it and ask the user about that one worktree by name. Only on an explicit yes for it: `git worktree remove --force "$worktree"`. Both checks matter: a plain `git worktree remove` refuses modified or untracked files, but it silently deletes ignored files (a `.env`, build output, `node_modules/`), and a plain `git status --short` does not list them. Only `--ignored` does, as `!!` lines.

**2. Delete the local branch the safe way.**

```bash
git branch -d "$branch"   # refuses unless the branch is fully merged
```

If git refuses, show what would be lost: `git log --oneline "$branch" --not --remotes` lists the commits that exist on no remote. Ask the user about that one branch by name, with that list. Only on an explicit yes for it: `git branch -D "$branch"`. A squash-merged PR looks unmerged to git, so a `MERGED` PR does not replace this question.

**3. Delete the remote branch.** The approved plan covers it when the branch has no commits missing from main. Otherwise delete it only on the per-branch yes from step 2's check.

```bash
git push origin --delete "$branch"
```

## Common Mistakes

- Deleting a branch with an open PR — check each branch's PR status individually (a bulk `gh pr list` stops at 30 results)
- Passing `origin/foo` to `gh pr list --head` — it needs the bare `foo`, and the prefixed form reports "no PR" with exit 0
- Forgetting to remove the worktree before deleting the branch — git will error
- Treating "no remote tracking" as definitely safe to delete — confirm with the per-branch PR query and `git log "$branch" --not --remotes`
- Treating a clean `git status --short` as proof that a worktree is empty — ignored files only show with `--ignored`, and a plain `git worktree remove` deletes them
- Deleting a remote branch because the plan was approved — if it has commits missing from main, it may be the only copy
- Reaching for `git branch -D` or `git worktree remove --force` first — try `git branch -d` and plain `git worktree remove`, and escalate only with a per-branch yes
- Reading a failed `gh` call as "no PR" — an empty result counts only when `gh` succeeded
