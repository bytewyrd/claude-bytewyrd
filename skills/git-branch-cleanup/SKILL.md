---
name: git-branch-cleanup
description: Use when the user asks to clean up, prune, or delete stale git branches — covers local branches with no remote, branches for merged PRs, abandoned remote branches, and worktrees for deleted branches. Triggered by words like "prune", "clean up branches", "delete stale branches".
disable-model-invocation: true
---

# Git Branch Cleanup

## Overview

Systematically identify and remove stale branches across local, remote, and worktrees by combining git state with GitHub PR status. Always present a plan before deleting anything. Approving the plan covers safe deletions only: `git branch -D` and `git worktree remove --force` throw work away, so each one needs its own confirmation (step 4).

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

- Any `OPEN` PR → keep the branch.
- `MERGED` → the branch is a deletion candidate.
- Only `CLOSED` (not merged) → keep it unless the user says the work is abandoned.
- An empty result means "no PR" only when `gh` exited 0. If `gh` fails (auth, network, wrong repository), stop and report that; never read a failure as "no PR".

### 2. Classify Each Branch

| Condition | Action |
|-----------|--------|
| Local branch with `[gone]` | Delete local (`-d` first, see step 4) |
| Local branch, no remote, PR is merged | Delete local (`-d` first) |
| Local branch, no remote, no PR | Ask the user: it may hold unmerged work (`-d` first; `-D` only on a per-branch yes) |
| Remote branch, PR merged, 0 commits ahead of main | Delete remote |
| Remote branch, no local, no open PR, old | Delete remote |
| Branch has worktree + branch is being deleted | Remove worktree first |
| Branch has open PR | Keep |
| `main` / default branch | Keep |

**Check if remote branch is merged:**
```bash
git log --oneline main..origin/branch-name | wc -l
# 0 = fully merged into main
```

### 3. Present a Plan

Before deleting anything, show a table:

| Branch | Location | Reason |
|--------|----------|--------|
| `foo/bar` | local | [gone] — remote deleted |
| `origin/old-feature` | remote | merged PR #12, 0 commits ahead of main |

Ask for confirmation, then execute. The plan approves the safe deletions in step 4 (`git worktree remove`, `git branch -d`, `git push origin --delete`). It does not approve `git branch -D` or `git worktree remove --force`.

### 4. Execute

Do these in order for each branch.

**1. Remove its worktree, if it has one.** Git refuses to delete a branch that a worktree has checked out.

```bash
worktree=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p}')
root=$(git rev-parse --show-toplevel)
if [ -n "$worktree" ] && [ "$worktree" != "$root" ]; then
  git worktree remove "$worktree"   # refuses if it has modified or untracked files
fi
```

If git refuses, show `git -C "$worktree" status --short` and ask the user about that one worktree by name. Only on an explicit yes for it: `git worktree remove --force "$worktree"`.

**2. Delete the local branch the safe way.**

```bash
git branch -d "$branch"   # refuses unless the branch is fully merged
```

If git refuses, show what would be lost: `git log --oneline "$branch" --not --remotes` lists the commits that exist on no remote. Ask the user about that one branch by name, with that list. Only on an explicit yes for it: `git branch -D "$branch"`. A squash-merged PR looks unmerged to git, so a `MERGED` PR does not replace this question.

**3. Delete the remote branch** (covered by the approved plan).

```bash
git push origin --delete "$branch"
```

## Common Mistakes

- Deleting a branch with an open PR — check each branch's PR status individually (a bulk `gh pr list` stops at 30 results)
- Forgetting to remove the worktree before deleting the branch — git will error
- Treating "no remote tracking" as definitely safe to delete — confirm with the per-branch PR query and `git log "$branch" --not --remotes`
- Reaching for `git branch -D` or `git worktree remove --force` first — try `git branch -d` and plain `git worktree remove`, and escalate only with a per-branch yes
- Reading a failed `gh` call as "no PR" — an empty result counts only when `gh` succeeded
