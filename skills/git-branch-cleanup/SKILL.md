---
name: git-branch-cleanup
description: Use when the user asks to clean up, prune, or delete stale git branches — covers local branches with no remote, branches for merged PRs, abandoned remote branches, and worktrees for deleted branches. Triggered by words like "prune", "clean up branches", "delete stale branches".
---

# Git Branch Cleanup

## Overview

Systematically identify and remove stale branches across local, remote, and worktrees by combining git state with GitHub PR status. Always present a plan before deleting anything.

## Steps

### 1. Gather State

Run these in parallel:

```bash
git fetch --prune
git branch -v        # local: [gone], untracked, current
git worktree list    # active worktrees and their branches
git branch -r        # remote tracking branches
```

Then check GitHub PR status:

```bash
gh pr list --state merged --limit 30 --json number,title,headRefName
gh pr list --state open --json number,title,headRefName
```

### 2. Classify Each Branch

| Condition | Action |
|-----------|--------|
| Local branch with `[gone]` | Delete local |
| Local branch, no remote, PR is merged | Delete local |
| Local branch, no remote, no PR | Delete local (confirm intent) |
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

Ask for confirmation, then execute.

### 4. Execute

```bash
# Remove worktree if branch has one
worktree=$(git worktree list | grep "\[$branch\]" | awk '{print $1}')
root=$(git rev-parse --show-toplevel)
if [ ! -z "$worktree" ] && [ "$worktree" != "$root" ]; then
  git worktree remove --force "$worktree"
fi

# Delete local branch
git branch -D "$branch"

# Delete remote branch
git push origin --delete "$branch"
```

## Common Mistakes

- Deleting a branch with an open PR — always check open PR list first
- Forgetting to remove the worktree before deleting the branch — git will error
- Treating "no remote tracking" as definitely safe to delete — confirm with PR history
