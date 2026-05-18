---
rfc: "2026-05-17-standardize-on-merge-commits"
title: "Standardize on merge commits and enforce at the repo layer"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Establish a single, documented git integration policy across every Bytewyrd project: merge commits — not rebase or squash — for both PR merges and `main`-into-feature-branch updates. Wire the policy into the plugin's own `CLAUDE.md`, `CLAUDE.md.tpl`, `CONTRIBUTING.md.tpl`, the `feature-engineer` and `rfc-architect` agent prompts (the two agents that perform branch integration during `/rfc-implement` and `/rfc-read-feedback`), and a new `/github-verify` skill that probes each repository's GitHub merge-strategy settings and offers to set them per policy. The result is consistent behavior whether the merge happens in the terminal, through `/commit-push-pr`, through `/rfc-implement`, or via a contributor clicking the GitHub UI.

## Should we do this?

**Yes.** The user already documented the policy in personal memory after a failed push caused by a rebase-on-shared-branch (`verified: /home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_git_merge_over_rebase.md`), but the policy lives only in that memory file — it is not in `CLAUDE.md` (verified: CLAUDE.md L173), the `CLAUDE.md.tpl` shipped to consumer projects (verified: .claude-plugin/scripts/templates/CLAUDE.md.tpl L90-94), or the agent prompts that perform merges on the user's behalf. Worse, the rendered `CONTRIBUTING.md` literally says "Squash merge to keep history clean" (verified: docs/CONTRIBUTING.md:L100) and the template that produces it carries the same instruction (verified: .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L64), so every new project synced today gets the opposite policy in writing. Codifying the rule plus belt-and-suspenders repo-side enforcement closes the gap.

## Current state

Three layers each carry their own piece of integration policy, and they disagree.

**Layer 1 — project conventions (text).** `CLAUDE.md` (the live one in this repo) and the synced template at `.claude-plugin/scripts/templates/CLAUDE.md.tpl` say nothing about merge vs rebase vs squash. The only relevant guidance is "Commit messages follow Conventional Commits" (verified: CLAUDE.md:L177, .claude-plugin/scripts/templates/CLAUDE.md.tpl:L92). `CONTRIBUTING.md`'s "Pull Request Process" section ends with the line `4. Squash merge to keep history clean` (verified: docs/CONTRIBUTING.md:L100) and the template that produces it for new projects has the identical line (verified: .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L64). The user's recorded preference is the opposite (verified: /home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_git_merge_over_rebase.md).

**Layer 2 — agent behavior.** The `feature-engineer` agent's Project-Specific Guidance section (verified: agents/feature-engineer.md:L65-72) covers the RFC process but has no integration-strategy guidance. The agent is the one that runs `/rfc-implement` end-to-end including the PR merge step (verified: skills/rfc-implement/SKILL.md:L58-66 — it spawns the agent with the RFC as input; the agent decides the merge mechanics). `rfc-architect` (this agent) is responsible for `/rfc-read-feedback`, which can require pulling `main` into a Draft branch (verified: skills/rfc-read-feedback exists per the `Skill` list and is described in docs/rfc-process.md:L165). Neither agent's prompt says "merge, not rebase."

**Layer 3 — upstream `commit-commands` plugin.** The `commit-push-pr` command lives in the `claude-plugins-official` marketplace, not this repo (verified by absence — `find /home/divoxx/code/bytewyrd/claude-bytewyrd/skills -name commit-push-pr` returns nothing; the actual file is at `/home/divoxx/.claude/plugins/marketplaces/claude-plugins-official/plugins/commit-commands/commands/commit-push-pr.md`). Its body simply says "Create a pull request using `gh pr create`" with no merge-strategy guidance (verified: that file, L17). We cannot modify it; we can only shape Claude's behavior around it through `CLAUDE.md`-level conventions and through what the agent that *consumes* the resulting PR is told to do.

**Layer 4 — repository-side enforcement.** This repo's own GitHub settings currently allow all three merge strategies (verified live in-session: `gh repo view bytewyrd/claude-bytewyrd --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` returned `{"deleteBranchOnMerge":false,"mergeCommitAllowed":true,"name":"claude-bytewyrd","rebaseMergeAllowed":true,"squashMergeAllowed":true}`). A contributor — human or agent — clicking "Squash and merge" in the GitHub UI silently bypasses every layer of in-repo policy.

**The pre-commit hook layer is intact and not relevant.** The plugin's `.claude-plugin/hooks/pre-commit/manifest-check.sh` only validates `bootstrap-manifest.json` freshness (verified: that file is 5 lines and just calls `build-manifest.sh --check`). There is no client-side guard on integration strategy, nor should there be — strategy enforcement belongs on the server side where it cannot be bypassed by a developer with a fast local commit.

## Analysis / Options

**Option A — Document the policy in `CLAUDE.md` and agent prompts only.** Add a `## Git Integration Policy` section to `CLAUDE.md` and `CLAUDE.md.tpl`, fix `CONTRIBUTING.md` and its template, and add a paragraph to the `feature-engineer` and `rfc-architect` agent prompts. Cheap, immediate. Weakness: a contributor in the GitHub UI can still pick squash or rebase from the merge dropdown; the policy is honor-system on the server side.

**Option B — Document + ship `/github-verify` for one-time setup, no continuous enforcement.** Same as A plus a manual `/github-verify` skill that the developer runs once per repo to read the current merge settings via `gh api repos/{owner}/{repo}` and offers (with one confirmation prompt) to set them to "merge only" via `gh repo edit --enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false` (verified: `gh repo edit --help` in-session output lists `--enable-merge-commit`, `--enable-rebase-merge`, `--enable-squash-merge` flags with the documented "use `--<flag>=false` to toggle off" syntax). Closes the GitHub-UI loophole at setup time. Weakness: settings drift — a project owner who changes the GitHub settings later (or a new repo that nobody ran `/github-verify` against) reopens the loophole silently.

**Option C — Document + `/github-verify` for setup AND drift detection on every session.** Option B's setup flow, plus a probe in `scripts/check-requirements.sh` (the existing `SessionStart` hook) that warns at session start if the current repo's GitHub merge settings allow squash or rebase. Catches drift. Weakness: adds a network round-trip to every session start (`gh api repos/{owner}/{repo}`) which slows session start in offline contexts and creates a class of "I'm offline, sue me" false-positive warnings. The existing hook already deliberately uses local file inspection only, not network calls (verified: scripts/check-requirements.sh L97-160 — every probe is a `command -v`, a `grep` on a local JSON, or a path test; no network).

**Option D — Document + `/github-verify` for setup + `/sync` re-checks once per `/sync` run.** Option B plus piggy-backing on `/sync` (which the user runs intentionally and already takes some seconds for diff computation) to re-check GitHub merge settings if a `github.com` remote is configured. `/sync` already calls `gh repo view --json name,description` (verified: skills/sync/SKILL.md L62-67), so adding two more JSON fields to that existing call has near-zero incremental cost. Drift gets surfaced the next time a maintainer runs `/sync`, which is the natural cadence for project-level convention updates. No new per-session network call; no false positives in offline sessions.

**Recommendation: Option D.** It closes the GitHub-UI loophole at setup time and detects drift on the natural cadence (`/sync`), without paying the per-session-start network cost of Option C. The hook stays purely local; the network probe runs only when the user has already chosen to do `/sync` work.

## Drawbacks

**The "merge always" policy bloats history with merge bubbles.** A squash-merge workflow produces a flat, single-commit-per-PR history that is easier to bisect and easier to read in `git log --oneline`. The merge-commit workflow produces a graph with one merge bubble per integration plus N branch commits per PR. The trade-off is intentional — preserving the conflict-resolution history and the per-commit attribution of work-in-progress is worth more to this project than `git log --oneline` aesthetics — but it is a real cost, and it shows up in (a) larger history walks, (b) `git blame` traversing more commits to find the actual author of a line, and (c) more visual noise in tools that render the commit graph.

**Rebase remains acceptable in narrow cases, which is a hedge that contributors can over-apply.** The policy permits rebase for "interactive cleanup of local-only commits before a PR" (verified: /home/divoxx/.claude/projects/-home-divoxx-code-bytewyrd-claude-bytewyrd/memory/feedback_git_merge_over_rebase.md). That carve-out exists for good reason — squashing three "oops typo" commits into one is genuinely useful — but it requires contributors to keep the "local-only" condition top of mind. An agent or contributor who rebases a branch that *has* been pushed (even to a long-forgotten draft branch) destroys shared history. The mitigation is the agent-prompt language plus the user's existing "confirm before rebasing shared branch" rule; there is no mechanical enforcement.

**`/github-verify` only works against GitHub.** Projects hosted on other forges (GitLab, Codeberg, Forgejo, Bitbucket) get the documentation half of the policy but not the repo-side enforcement. The plugin's existing `/sync` flow already gates GitHub-specific behavior on `has_github` (verified: skills/sync/SKILL.md L56-58, L658-679 — every `gh`-using step checks the remote first). We follow the same pattern: `/github-verify` is a no-op on non-GitHub repos with a clear message.

**Repo-setting changes require admin permissions.** The `gh repo edit` calls that flip merge strategies require the authenticated user to have admin access on the repository. For a contributor without admin (typical in larger orgs), `/github-verify` can read the settings (verified: any auth'd user can `gh repo view --json mergeCommitAllowed,...`) but cannot fix drift. The skill must detect this case and instruct the contributor to ask an admin. The remediation is to surface the missing-permission case as a discrete outcome category in the report, not to silently fail.

**The hook ecosystem this proposal does not touch.** This RFC does not add a client-side pre-push hook to refuse rebase pushes, and intentionally so. Client-side hooks are advisory (any `git push --no-verify` bypasses them) and would create false positives in the legitimate "rebase local-only commits before first push" path. Server-side enforcement is the only place a strategy ban actually binds; the layer-4 fix below is the durable answer.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `CLAUDE.md` | Add `## Git Integration Policy` section under `## Conventions` block (this repo's live file) |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | Same addition, so every project synced by `/sync` carries the policy text |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Add `"## Git Integration Policy"` to `bytewyrd/CLAUDE.md@v1` `owned_sections`; refresh `template_sha` |
| Modify | `docs/CONTRIBUTING.md` | Replace the "Squash merge to keep history clean" line with the merge-only policy (this repo's live file) |
| Modify | `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` | Same replacement for every synced project |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Refresh `sha256` for `bytewyrd/docs/CONTRIBUTING.md@v1` (its `extension_strategy` is `whole`, no owned_sections to extend) |
| Modify | `agents/feature-engineer.md` | Add Git Integration Policy paragraph to the Project-Specific Guidance section; update audit log footer |
| Modify | `agents/rfc-architect.md` | Add Git Integration Policy paragraph to the Project context section (since this agent performs the `/rfc-read-feedback` merge step); update audit log footer |
| Create | `skills/github-verify/SKILL.md` | New skill that reads and optionally fixes a repo's GitHub merge-strategy settings |
| Modify | `scripts/tool-probe.sh` | Add a `merge-policy` probe name that reports the current repo's GitHub merge settings as JSON (used by `/github-verify` and the `/sync` extension) |
| Modify | `skills/sync/SKILL.md` | Extend Step 6 (GitHub repository metadata) to also probe and report merge-strategy drift |

No `hooks/` changes. No `scripts/check-requirements.sh` changes (rejected per Option C analysis above).

### Steps

#### Step 1 — Define the canonical policy text

Use this exact text as the source of truth. Every file below will paste from this block verbatim (or a near-verbatim adaptation for the agent-prompt voice).

```markdown
## Git Integration Policy

**Default: merge commits, always.** Both directions:

- **PR → main**: `git merge --no-ff` (or the GitHub UI's "Create a merge commit" button). Never "Squash and merge" or "Rebase and merge".
- **main → feature branch**: `git merge origin/main` to integrate upstream changes. Never `git rebase origin/main` once the feature branch has been pushed.

**Why:** merge commits preserve the conflict-resolution history, the per-commit attribution of work-in-progress, and the integrity of every checkout already on the branch. Rebasing a shared branch rewrites history that other clones (and other agents' worktrees) depend on; a forced push to fix it is the kind of operation that loses work.

**Rebase is acceptable in two narrow cases:**

1. Interactive cleanup of local-only commits before the first push — squashing "oops typo" commits into one, reordering, fixing commit messages. Once the branch has been pushed, this carve-out no longer applies.
2. Branch-update workflows on a branch that has only one developer (and zero agents) actively working on it. If there is any doubt about whether someone else has the branch checked out, default to merge and ask.

**For anything else, always merge.** When in doubt, merge.

The repository-side enforcement layer is `/github-verify`, which sets the GitHub repo's allowed merge strategies to "merge commit only" so that the GitHub UI offers no other option. `/sync` re-checks this on every run and warns if the settings have drifted.
```

This block is the canonical text. Sub-steps below paste it (or paraphrase it for the agent-prompt voice) into the right files.

#### Step 2 — Add the policy section to `CLAUDE.md`

`CLAUDE.md` (verified: this repo's live file) currently ends its `## Conventions` section at line 179 with the line `For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).` Insert the canonical block from Step 1 immediately after the `## Conventions` H2 block, as a new H2 `## Git Integration Policy`.

Concretely — use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/CLAUDE.md`
- `old_string`:
  ```
  ## Conventions

  Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

  For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
  ```
- `new_string`:
  ```
  ## Conventions

  Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

  For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).

  ## Git Integration Policy

  **Default: merge commits, always.** Both directions:

  - **PR → main**: `git merge --no-ff` (or the GitHub UI's "Create a merge commit" button). Never "Squash and merge" or "Rebase and merge".
  - **main → feature branch**: `git merge origin/main` to integrate upstream changes. Never `git rebase origin/main` once the feature branch has been pushed.

  **Why:** merge commits preserve the conflict-resolution history, the per-commit attribution of work-in-progress, and the integrity of every checkout already on the branch. Rebasing a shared branch rewrites history that other clones (and other agents' worktrees) depend on; a forced push to fix it is the kind of operation that loses work.

  **Rebase is acceptable in two narrow cases:**

  1. Interactive cleanup of local-only commits before the first push — squashing "oops typo" commits into one, reordering, fixing commit messages. Once the branch has been pushed, this carve-out no longer applies.
  2. Branch-update workflows on a branch that has only one developer (and zero agents) actively working on it. If there is any doubt about whether someone else has the branch checked out, default to merge and ask.

  **For anything else, always merge.** When in doubt, merge.

  The repository-side enforcement layer is `/github-verify`, which sets the GitHub repo's allowed merge strategies to "merge commit only" so that the GitHub UI offers no other option. `/sync` re-checks this on every run and warns if the settings have drifted.
  ```

Expected outcome: `CLAUDE.md` grows by ~21 lines; running `git diff CLAUDE.md` shows only the additions (no other line changes).

#### Step 3 — Add the policy section to `CLAUDE.md.tpl`

`CLAUDE.md.tpl` (verified: .claude-plugin/scripts/templates/CLAUDE.md.tpl L90-94) currently ends with the same `## Conventions` section. Apply the same insertion.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/.claude-plugin/scripts/templates/CLAUDE.md.tpl`
- `old_string`:
  ```
  ## Conventions

  Commit messages follow Conventional Commits with a scope: `feat(scope): message`.

  For accumulated session learnings, see [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md).
  ```
- `new_string`: identical to Step 2's `new_string` (the canonical block is project-independent).

Expected outcome: the template now ends one section later.

#### Step 4 — Register the new owned section in the bootstrap manifest

`/sync` knows which sections of `CLAUDE.md` are "plugin-owned" (rewritable on update) via the `owned_sections` array in `.claude-plugin/bootstrap-manifest.json`'s `bytewyrd/CLAUDE.md@v1` entry (verified: .claude-plugin/bootstrap-manifest.json:L85-96). Without adding `"## Git Integration Policy"` here, a re-run of `/sync` on a project that has been previously synced will NOT carry the new section forward — `/sync` would leave the section as a "user-owned" untouched region, which means consumer projects never see the policy.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/.claude-plugin/bootstrap-manifest.json`
- `old_string`:
  ```
        "owned_sections": [
          "## Toolchain",
          "## File structure",
          "## Agent delegation",
          "## Tool Usage",
          "## RFC Process",
          "## Evidence-Based Development",
          "## Model Usage Optimization",
          "## Claude Code Sandbox — Container Tool Compatibility",
          "## Security",
          "## Conventions"
        ],
  ```
- `new_string`:
  ```
        "owned_sections": [
          "## Toolchain",
          "## File structure",
          "## Agent delegation",
          "## Tool Usage",
          "## RFC Process",
          "## Evidence-Based Development",
          "## Model Usage Optimization",
          "## Claude Code Sandbox — Container Tool Compatibility",
          "## Security",
          "## Conventions",
          "## Git Integration Policy"
        ],
  ```

Then refresh the manifest's `template_sha` field by running this after all template edits in Steps 3 and 6 are complete (the script hashes all template sources in a single pass):

```bash
bash /home/divoxx/code/bytewyrd/claude-bytewyrd/.claude-plugin/scripts/build-manifest.sh
```

Expected stdout (verified: build-manifest.sh L54-55 — the script prints one line after writing):

```
Regenerated .claude-plugin/bootstrap-manifest.json
```

Verify by:

```bash
bash /home/divoxx/code/bytewyrd/claude-bytewyrd/.claude-plugin/scripts/build-manifest.sh --check
```

Expected stdout: empty (zero exit code). If the script exits non-zero, the manifest is stale and the pre-commit hook (verified: .claude-plugin/hooks/pre-commit/manifest-check.sh) will reject the commit.

Note: run this script only after Steps 3 and 6 are both complete. Running it between those steps will update `CLAUDE.md.tpl`'s `template_sha` correctly but leave `CONTRIBUTING.md.tpl`'s `sha256` stale until Step 6 is done, causing the pre-commit hook to reject the commit if a commit is attempted between steps.

#### Step 5 — Replace the squash-merge line in `CONTRIBUTING.md`

The Pull Request Process section (verified: docs/CONTRIBUTING.md:L95-100) currently reads:

```
1. Open a PR against `main`
2. CI must pass
3. One approval required for merge
4. Squash merge to keep history clean
```

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/docs/CONTRIBUTING.md`
- `old_string`:
  ```
  1. Open a PR against `main`
  2. CI must pass
  3. One approval required for merge
  4. Squash merge to keep history clean
  ```
- `new_string`:
  ```
  1. Open a PR against `main`
  2. CI must pass
  3. One approval required for merge
  4. Merge using "Create a merge commit" — never "Squash and merge" or "Rebase and merge". See [`CLAUDE.md`](../CLAUDE.md) §"Git Integration Policy" for the why and the narrow rebase-acceptable cases.
  ```

Expected outcome: line 100 changes; no other lines move.

#### Step 6 — Replace the squash-merge line in `CONTRIBUTING.md.tpl`

`CONTRIBUTING.md.tpl` (verified: .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L58-64) has the same Pull Request Process block. Apply the identical replacement.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl`
- `old_string`:
  ```
  1. Open a PR against `main`
  2. CI must pass
  3. One approval required for merge
  4. Squash merge to keep history clean
  ```
- `new_string`:
  ```
  1. Open a PR against `main`
  2. CI must pass
  3. One approval required for merge
  4. Merge using "Create a merge commit" — never "Squash and merge" or "Rebase and merge". See [`CLAUDE.md`](../CLAUDE.md) §"Git Integration Policy" for the why and the narrow rebase-acceptable cases.
  ```

The template's `extension_strategy` is `whole` (verified: .claude-plugin/bootstrap-manifest.json:L173-178). Step 4's `build-manifest.sh` run also refreshes the `sha256` for this template; no separate manifest edit is needed.

#### Step 7 — Add the Git Integration Policy paragraph to `agents/feature-engineer.md`

`feature-engineer` is the agent that runs `/rfc-implement` and therefore performs the eventual PR merge (verified: agents/feature-engineer.md L65-72 documents the agent's Project-Specific Guidance; skills/rfc-implement/SKILL.md:L58-66 shows the skill spawns this agent with the RFC as input and the agent owns the implementation including the merge). Add a fifth bullet to the numbered Project-Specific Guidance list.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/agents/feature-engineer.md`
- `old_string`:
  ```
  **Project-Specific Guidance (Bytewyrd plugin):**

  When the project has been set up with `/sync`, an RFC process governs design and implementation work. Before implementing anything non-trivial:

  1. **Check for `docs/rfc-process.md`** in the project root. If it exists, the project uses the RFC process — read that file (it is self-contained and includes any project extensions).
  2. **If implementing an Approved RFC**, the entry point is the `/rfc-implement` skill. Treat the RFC as the source of truth for the implementation spec: do not redesign and do not extend scope. If any part of the spec is ambiguous, stop and recommend the user run `/rfc-read-feedback` or revise the RFC via the `rfc-architect` agent before resuming.
  3. **If the requested change requires design decisions** (new component, cross-cutting refactor, public API change) and the project uses RFCs, recommend the user run `/rfc-new` first rather than implementing directly.
  4. **If `docs/rfc-process.md` is absent**, the RFC workflow does not apply — proceed with the standard implementation approach described above.
  ```
- `new_string`:
  ```
  **Project-Specific Guidance (Bytewyrd plugin):**

  When the project has been set up with `/sync`, an RFC process governs design and implementation work. Before implementing anything non-trivial:

  1. **Check for `docs/rfc-process.md`** in the project root. If it exists, the project uses the RFC process — read that file (it is self-contained and includes any project extensions).
  2. **If implementing an Approved RFC**, the entry point is the `/rfc-implement` skill. Treat the RFC as the source of truth for the implementation spec: do not redesign and do not extend scope. If any part of the spec is ambiguous, stop and recommend the user run `/rfc-read-feedback` or revise the RFC via the `rfc-architect` agent before resuming.
  3. **If the requested change requires design decisions** (new component, cross-cutting refactor, public API change) and the project uses RFCs, recommend the user run `/rfc-new` first rather than implementing directly.
  4. **If `docs/rfc-process.md` is absent**, the RFC workflow does not apply — proceed with the standard implementation approach described above.
  5. **Git Integration Policy** — when integrating branches (pulling `main` into your feature branch, or merging the feature PR back to `main`), always use `git merge` and never `git rebase` on a branch that has been pushed. When opening the PR, the merge method on GitHub must be "Create a merge commit" — never "Squash and merge" or "Rebase and merge". Rebase is acceptable only for interactive cleanup of local-only commits before the first push. See the project's `CLAUDE.md` §"Git Integration Policy" for the full rule and the rationale.
  ```

Then update the audit log footer to record this revision. Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/agents/feature-engineer.md`
- `old_string`:
  ```
  <!-- Audit log -->
  <!-- 2026-05-12: criteria v1, audited by claude-agent-author; pinned model: opus in frontmatter (H3) so standalone invocations default correctly while /rfc-implement continues to spawn opus explicitly; added Project-Specific Guidance section referencing docs/rfc-process.md and /rfc-implement to satisfy H7 for this Tier 1 agent on the active-delegation hot path; appended this audit footer (H5); verified no tools: field present so all-tools inheritance applies (H1); verified existing Anthropic-style description with two <example> blocks satisfies H2 for an actively-delegated Tier 1 agent; verified no cross-subagent coordination claims (H4) or context-manager/MCP-comms prose (H4a); preserved all existing customizations including the cyan color (S2), the SOLID/DRY/TDD engineering philosophy, and the worked example trigger blocks. -->
  ```
- `new_string`:
  ```
  <!-- Audit log -->
  <!-- 2026-05-12: criteria v1, audited by claude-agent-author; pinned model: opus in frontmatter (H3) so standalone invocations default correctly while /rfc-implement continues to spawn opus explicitly; added Project-Specific Guidance section referencing docs/rfc-process.md and /rfc-implement to satisfy H7 for this Tier 1 agent on the active-delegation hot path; appended this audit footer (H5); verified no tools: field present so all-tools inheritance applies (H1); verified existing Anthropic-style description with two <example> blocks satisfies H2 for an actively-delegated Tier 1 agent; verified no cross-subagent coordination claims (H4) or context-manager/MCP-comms prose (H4a); preserved all existing customizations including the cyan color (S2), the SOLID/DRY/TDD engineering philosophy, and the worked example trigger blocks. -->
  <!-- 2026-05-17: appended Git Integration Policy bullet (#5) to Project-Specific Guidance per RFC 2026-05-17-standardize-on-merge-commits; criteria unchanged at v1. -->
  ```

#### Step 8 — Add the Git Integration Policy paragraph to `agents/rfc-architect.md`

`rfc-architect` is the agent that runs `/rfc-read-feedback` and is sometimes required to pull `main` into the Draft branch when feedback addresses a conflict with concurrent work. Read the existing agent file to find the Project context section.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/agents/rfc-architect.md`
- `old_string`:
  ```
  You do not spawn other subagents yourself — Claude Code's subagent execution model does not allow it. The skill body that invoked you handles all cross-agent orchestration. Your job is to draft, revise, and self-review the RFC.
  ```
- `new_string`:
  ```
  You do not spawn other subagents yourself — Claude Code's subagent execution model does not allow it. The skill body that invoked you handles all cross-agent orchestration. Your job is to draft, revise, and self-review the RFC.

  **Git Integration Policy.** When `/rfc-read-feedback` requires pulling `main` into the Draft RFC's branch — for example, if a feedback comment fixes a section that depends on a now-merged change — always use `git merge origin/main`, never `git rebase origin/main`, once the RFC's branch has been pushed. The branch is shared with the human reviewer and the consensus-review agents; rebasing rewrites history those clones depend on. Rebase is acceptable only for interactive cleanup of local-only commits before the first push. See the project's `CLAUDE.md` §"Git Integration Policy" for the full rule.
  ```

Then update the audit log footer. Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/agents/rfc-architect.md`
- `old_string`:
  ```
  <!-- Audit log -->
  <!-- 2026-05-12: criteria v1, audited by claude-agent-author; pinned model: opus (H3 — Tier 1 agent on the /rfc-new and /rfc-consensus-review hot path); removed aspirational tools: field that included LS and NotebookRead (not Claude Code primitives in v1) so the agent now inherits the full toolset per H1; added a "Project context: the Bytewyrd RFC process" section that names docs/rfc-process.md and the three skills (/rfc-new, /rfc-consensus-review, /rfc-read-feedback) the agent participates in (H7), and explicitly states that the agent does not spawn other subagents — the invoking skill body handles orchestration (H4 clarification); preserved the entire Evidence-Based Research Discipline, Claim Inventory, Verification Protocol, and Citation Format / [UNVERIFIED] Marker sections from the prior local customization (RFC H content) verbatim; retained color: blue (S2) and Anthropic-style description with two <example> blocks (H2). -->
  ```
- `new_string`:
  ```
  <!-- Audit log -->
  <!-- 2026-05-12: criteria v1, audited by claude-agent-author; pinned model: opus (H3 — Tier 1 agent on the /rfc-new and /rfc-consensus-review hot path); removed aspirational tools: field that included LS and NotebookRead (not Claude Code primitives in v1) so the agent now inherits the full toolset per H1; added a "Project context: the Bytewyrd RFC process" section that names docs/rfc-process.md and the three skills (/rfc-new, /rfc-consensus-review, /rfc-read-feedback) the agent participates in (H7), and explicitly states that the agent does not spawn other subagents — the invoking skill body handles orchestration (H4 clarification); preserved the entire Evidence-Based Research Discipline, Claim Inventory, Verification Protocol, and Citation Format / [UNVERIFIED] Marker sections from the prior local customization (RFC H content) verbatim; retained color: blue (S2) and Anthropic-style description with two <example> blocks (H2). -->
  <!-- 2026-05-17: appended Git Integration Policy paragraph to the "Project context: the Bytewyrd RFC process" section per RFC 2026-05-17-standardize-on-merge-commits; criteria unchanged at v1. -->
  ```

#### Step 9 — Add a `merge-policy` probe to `scripts/tool-probe.sh`

`tool-probe.sh` exists and uses the `_lib/common.bash` `emit_*` helpers (verified: scripts/tool-probe.sh L33-36 source the common file; scripts/_lib/common.bash:L24-35 define the helpers). Add a new probe case that returns the current repo's GitHub merge-strategy settings as JSON, or an error object explaining why it could not.

The probe contract:

```
$ bash scripts/tool-probe.sh merge-policy
```

Stdout when the repo has a `github.com` remote and `gh` is authenticated:

```json
{"result":"checked","name":"merge-policy","mergeCommitAllowed":true,"squashMergeAllowed":false,"rebaseMergeAllowed":false}
```

Stdout when there is no `github.com` remote:

```json
{"result":"not-applicable","name":"merge-policy","hint":"no github.com remote configured"}
```

Stdout when `gh` is missing:

```json
{"result":"missing","name":"merge-policy","hint":"gh CLI not on PATH. Install: https://cli.github.com."}
```

Stdout when `gh` is present but unauthenticated:

```json
{"result":"unauthenticated","name":"merge-policy","hint":"gh CLI present but not authenticated. Run: gh auth login."}
```

Stdout when `gh` is authenticated but the user lacks admin permission to read settings (the API returns the read-allowed subset for any auth'd user — verified live: `gh repo view bytewyrd/claude-bytewyrd --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` succeeded for a non-owner-equivalent call returning all three fields; this case is included for forward compatibility):

```json
{"result":"forbidden","name":"merge-policy","hint":"gh CLI authenticated but the API call returned 403; admin permission required to read merge settings"}
```

Exit codes mirror the existing probes (verified: scripts/tool-probe.sh L28-31):
- `0` for `checked`, `not-applicable`
- `1` for `missing`, `unauthenticated`, `forbidden`
- `2` for usage errors

Implementation: add a new `merge-policy)` case to the `case "$name" in` block at scripts/tool-probe.sh:L44 (just before the closing `*)` default case at L98). Pseudocode of the new branch:

```bash
  merge-policy)
    if ! command -v gh >/dev/null 2>&1; then
      emit_missing "$name" "gh CLI not on PATH. Install: https://cli.github.com."
      exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
      emit_unauth "$name" "gh CLI present but not authenticated. Run: gh auth login."
      exit 1
    fi
    remote_url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -z "$remote_url" ] || ! printf '%s' "$remote_url" | grep -q 'github\.com'; then
      jq -n --arg name "$name" '{result:"not-applicable", name:$name, hint:"no github.com remote configured"}'
      exit 0
    fi
    # gh repo view (no slug arg) defaults to the current repo's remote.
    if ! settings_json="$(gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed 2>/dev/null)"; then
      jq -n --arg name "$name" '{result:"forbidden", name:$name, hint:"gh repo view returned non-zero; admin permission may be required to read merge settings"}'
      exit 1
    fi
    printf '%s' "$settings_json" | jq --arg name "$name" '. + {result:"checked", name:$name}'
    exit 0
    ;;
```

Verify with:

```bash
bash /home/divoxx/code/bytewyrd/claude-bytewyrd/scripts/tool-probe.sh merge-policy
```

Expected stdout (from this repo right now, given Step 11 has not yet flipped its own settings):

```json
{"mergeCommitAllowed":true,"squashMergeAllowed":true,"rebaseMergeAllowed":true,"result":"checked","name":"merge-policy"}
```

(Field order is jq-dependent; do not pin order in the test.)

#### Step 10 — Create the `/github-verify` skill

Create the file with the structure documented below. Match the shape of existing skills (verified: skills/rfc-summary/SKILL.md as a representative model — frontmatter, `# Title`, one paragraph overview, numbered `### N.` steps, fenced bash blocks).

Use the `Write` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/skills/github-verify/SKILL.md`
- `content`:

```markdown
---
name: github-verify
description: Use to verify and optionally fix a GitHub repository's allowed merge strategies. Reads the current `mergeCommitAllowed`, `squashMergeAllowed`, and `rebaseMergeAllowed` settings, compares them against the Bytewyrd policy (merge commits only), and offers a single-confirmation prompt to flip the squash and rebase strategies to disabled via `gh repo edit`. Triggered by "/github-verify".
---

# GitHub Verify

Reads a GitHub repository's allowed merge strategies and, if they diverge from the Bytewyrd merge-commits-only policy, offers to update them via `gh repo edit`. Read-only by default; mutation requires one explicit confirmation.

## Why this exists

The project's `CLAUDE.md` §"Git Integration Policy" mandates merge commits for every PR and bans squash and rebase merges. That policy is honor-system at the text level — a contributor in the GitHub UI can pick "Squash and merge" or "Rebase and merge" from the dropdown and silently bypass it. `/github-verify` closes the loophole by setting the GitHub repository's allowed merge strategies so that the UI offers only "Create a merge commit". The skill is also called from `/sync` (via the `merge-policy` probe) to surface drift the next time a maintainer runs sync.

## Steps

### 1. Requirement check

`/github-verify` needs the `gh` CLI authenticated and the repo to have a `github.com` remote. Probe via the shared `merge-policy` probe:

\`\`\`bash
result="$(bash scripts/tool-probe.sh merge-policy)"; probe_status=$?
probe_result="$(printf '%s' "$result" | jq -r .result)"
\`\`\`

Handle each `probe_result`:

- `not-applicable` → print: "This repo has no `github.com` remote. `/github-verify` only applies to GitHub-hosted repos. Skipping." Stop with exit 0.
- `missing` → print: "`/github-verify` requires the gh CLI. Install: https://cli.github.com." Stop with exit 1.
- `unauthenticated` → print: "`/github-verify` requires gh to be logged in. Run: `gh auth login`." Stop with exit 1.
- `forbidden` → print: "Cannot read merge settings on this repo — you need admin permission. Ask a repo admin to run `/github-verify`, or run `gh repo edit --enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false` themselves." Stop with exit 1.
- `checked` → continue to Step 2.

### 2. Compare against policy

Extract the three booleans from `$result`:

\`\`\`bash
merge_ok="$(printf '%s' "$result" | jq -r .mergeCommitAllowed)"
squash_ok="$(printf '%s' "$result" | jq -r .squashMergeAllowed)"
rebase_ok="$(printf '%s' "$result" | jq -r .rebaseMergeAllowed)"
\`\`\`

Compute a `drift` flag:

- Compliant (no drift): `merge_ok=true` AND `squash_ok=false` AND `rebase_ok=false`.
- Non-compliant (drift): any other combination.

If compliant, print the success line and stop:

> "GitHub merge settings on `<owner>/<repo>` match the Bytewyrd policy: merge=allowed, squash=disabled, rebase=disabled. No changes needed."

Extract `<owner>/<repo>` from the remote URL with:

\`\`\`bash
remote_slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
\`\`\`

If non-compliant, proceed to Step 3.

### 3. Present the drift and ask once

Render a three-row diff so the user sees what is current and what the skill proposes to change:

\`\`\`
Repo: <owner>/<repo>

Current settings:
  mergeCommitAllowed   : <merge_ok>
  squashMergeAllowed   : <squash_ok>
  rebaseMergeAllowed   : <rebase_ok>

Proposed (Bytewyrd policy):
  mergeCommitAllowed   : true
  squashMergeAllowed   : false
  rebaseMergeAllowed   : false
\`\`\`

Then ask one AskUserQuestion:

**"Apply the proposed merge-strategy settings to `<owner>/<repo>`?"**

- Option 1: `Yes — flip squash and rebase to disabled, leave merge enabled`
- Option 2: `No — keep current settings`

If the user picks `No`, print:

> "Skipped. Re-run `/github-verify` any time, or update settings manually at: https://github.com/`<owner>/<repo>`/settings"

Stop with exit 0.

If the user picks `Yes`, proceed to Step 4.

### 4. Apply via `gh repo edit`

Run a single `gh repo edit` invocation that flips both non-policy strategies to false and asserts merge is true (even if it already was — the call is idempotent):

\`\`\`bash
gh repo edit --enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false
\`\`\`

Expected stdout: empty on success. Exit code 0 on success.

If the exit code is non-zero, print the actual stderr verbatim plus:

> "Could not apply settings. Most common cause: you need admin permission on this repo to change merge strategies. Ask a repo admin to run this skill, or fix the permission and try again."

Stop with exit 1.

On success, re-probe to confirm:

\`\`\`bash
result_after="$(bash scripts/tool-probe.sh merge-policy)"
\`\`\`

Extract the new values and print a confirmation line:

> "Updated `<owner>/<repo>`: merge=true, squash=false, rebase=false. The GitHub UI will now only offer 'Create a merge commit'."

Stop with exit 0.

## Constraints

- **Single-prompt UX.** The skill asks exactly one question (Step 3) and then either applies or skips. No multi-step confirmation tree.
- **No commits.** This skill does not modify any file in the repo. It only calls GitHub APIs via `gh`.
```

Expected outcome: the new skill is automatically discovered by Claude Code on next session (skills under `skills/` are auto-discovered; verified via the existing `## Skills` table in skills/sync/SKILL.md L213-225 which enumerates the same convention). The skill name will be `bytewyrd:github-verify` per the plugin's `bytewyrd:` namespace (verified: docs/BEST_PRACTICES.md L119).

#### Step 11 — Extend `skills/sync/SKILL.md` Step 6 to surface drift

Step 6 of `/sync` (verified: skills/sync/SKILL.md:L658-679) currently updates the GitHub repo description via `gh repo edit --description`. Extend it to also probe merge-strategy compliance and print a warning if it has drifted.

Use the `Edit` tool with:

- `file_path`: `/home/divoxx/code/bytewyrd/claude-bytewyrd/skills/sync/SKILL.md`
- `old_string`:
  ```
  If `gh` is not available or the remote is not yet set up, note it in the Step 8 report and move on.

  The `description` value is sourced from `docs/project-brief.md`, ensuring local files and the remote stay aligned. When `description` is `""`, no `gh repo edit --description` call is made.
  ---
  ```
- `new_string`:
  ```
  If `gh` is not available or the remote is not yet set up, note it in the Step 8 report and move on.

  The `description` value is sourced from `docs/project-brief.md`, ensuring local files and the remote stay aligned. When `description` is `""`, no `gh repo edit --description` call is made.

  **Merge-strategy drift check.** After the description update (or as a standalone step when `description` is empty), probe the repo's allowed merge strategies via:

  ```bash
  policy="$(bash scripts/tool-probe.sh merge-policy)"
  ```

  Branch on `policy`'s `.result` field:

  - `checked` and the three booleans match `(merge=true, squash=false, rebase=false)` — silent; record `merge strategy: compliant` in the Step 8 report.
  - `checked` and the three booleans diverge from policy — append a warning to the Step 8 report: `GitHub merge strategies drift from policy (current: merge=<m>, squash=<s>, rebase=<r>). Fix: run /github-verify`. Do not auto-fix; `/sync` does not interactively update settings.
  - `not-applicable` — silent; record `merge strategy: not applicable (no github.com remote)` in the Step 8 report.
  - `missing` or `unauthenticated` — append to the Step 8 report: `merge strategy: skipped (gh missing or not logged in)`. Do not surface as a warning; `/sync` already tolerates a missing `gh` for the description step.
  - `forbidden` — append a warning: `merge strategy: could not read (admin permission required). Ask a repo admin to run /github-verify`.
  ---
  ```

Expected outcome: a future `/sync` run on this repo will print a warning during its Step 8 report (until `/github-verify` is run on the repo), because the current settings have all three strategies enabled (verified live above).

#### Step 12 — Self-bootstrap: run `/github-verify` against this repo

After the steps above land and the PR is merged, run `/github-verify` once against `bytewyrd/claude-bytewyrd` itself to bring this repo into compliance. Expected interaction:

```
Repo: bytewyrd/claude-bytewyrd

Current settings:
  mergeCommitAllowed   : true
  squashMergeAllowed   : true
  rebaseMergeAllowed   : true

Proposed (Bytewyrd policy):
  mergeCommitAllowed   : true
  squashMergeAllowed   : false
  rebaseMergeAllowed   : false

Apply the proposed merge-strategy settings to bytewyrd/claude-bytewyrd? [Yes / No]
```

User answers `Yes`. Then verify:

```bash
gh repo view bytewyrd/claude-bytewyrd --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
```

Expected stdout:

```json
{"mergeCommitAllowed":true,"squashMergeAllowed":false,"rebaseMergeAllowed":false}
```

This step is NOT part of the PR — it is the post-merge bootstrap that closes the GitHub-UI loophole on the plugin's own repo.

## Risks and open questions

**Risk: existing PRs with squash-merge-trained reviewers.** Reviewers who have grown used to "Squash and merge" may instinctively click "Create a merge commit" without noticing the difference, but the inverse is also true — they may click out of habit on a different repo (a consumer of this plugin) that has not yet run `/github-verify`. The mitigation is the documentation layer: `CLAUDE.md` and `CONTRIBUTING.md` both explicitly name the wrong choices ("never 'Squash and merge' or 'Rebase and merge'"), so a reviewer who is paying attention to either document sees the warning. We accept the residual risk for repos that have neither run `/github-verify` nor read the docs.

**Risk: `gh repo edit` permission errors at scale.** Most contributors do not have admin on the repos they work in. `/github-verify`'s "drift detected — fix" path is reachable only by admins; for everyone else the skill exits with a clear "ask an admin" message (Step 1's `forbidden` branch). This is by design — we do not want a non-admin contributor to be silently confused about why the skill stopped working. Open question: should we surface the drift as a warning in `/sync` regardless of admin? Yes — the warning is informational; a non-admin who sees it can forward it to whoever can fix it.

**Risk: `gh repo view --json` field names diverge from `gh api` field names.** Verified: `gh repo view --json mergeCommitAllowed,...` returns camelCase (`mergeCommitAllowed`); `gh api repos/{owner}/{repo}` returns snake_case (`allow_merge_commit`). The probe uses `gh repo view --json` consistently so the two cases never mix. If a future `gh` release renames the JSON fields, the probe breaks and `/sync` will start printing the `merge strategy: skipped` line (because the `gh repo view` call will fail). That failure mode is loud enough; no further mitigation is needed.

**Open question: handling of non-GitHub forges.** Currently `not-applicable` is treated as "silent success" because most non-GitHub projects in scope still benefit from the documentation-layer policy. If a future Bytewyrd-supported forge (GitLab, Forgejo) gains the same kind of repo-side merge-strategy setting, the probe and skill should grow per-forge branches. Out of scope for this RFC; revisit when the first non-GitHub project surfaces the need.

**Open question: should the `CLAUDE.md` policy section also forbid `git push --force`?** Force-pushing to a branch that someone else has checked out is the second-order consequence of the rebase ban — if you can't rebase a shared branch, you also can't force-push to it. The policy text does not currently say so explicitly. Decision: leave it implicit for the first iteration; if the next session shows a force-push incident, add a "never force-push to a shared branch" sentence to the policy in a follow-up RFC.

**Open question: do we need a CI guard?** A GitHub Actions workflow could check, on PR open, whether the PR's commit ancestry includes a force-push (`git log --pretty=fuller` includes the committer-vs-author divergence that a rebase introduces). This would catch the case where a contributor rebased locally then push-forced before opening the PR. Decided out of scope for this RFC — the documentation + repo-settings + agent-prompt layers cover the routine case, and CI guards add maintenance cost that should be paid only if the routine case proves insufficient.

## Relationship to other RFCs

This RFC has no direct dependencies on other RFCs. It touches three files that have also been touched by recent RFCs:

- `skills/sync/SKILL.md` was the subject of `2026-05-14-sync-per-file-extension-strategies` (referenced in recent commit log per the merge of PR #92). This RFC extends Step 6 of `/sync` additively; the existing manifest-driven diff/apply flow is untouched. No conflict.
- `.claude-plugin/bootstrap-manifest.json`'s `owned_sections` array was last extended by the same `2026-05-14-sync-per-file-extension-strategies` RFC. This RFC appends one new entry; no entries are removed or reordered. No conflict.
- `agents/feature-engineer.md` was last audited under `agents/agent-audit-criteria.md` v1. This RFC appends a fifth bullet to its Project-Specific Guidance and adds a new audit-log line dated `2026-05-17`; the criteria version is not changed and no other section of the agent prompt is touched. No conflict.

If `2026-05-14-sync-per-file-extension-strategies` or any other RFC currently in Draft expands the same `owned_sections` array or rewrites the same Step 6 of `/sync`, this RFC's diff must be re-applied (via `git merge` into the updated branch, per its own policy) after that one merges. Order of implementation: any in-flight RFC that touches the same lines should land first; this one is small enough to resolve a textual merge conflict in either order.
