---
rfc: "2026-05-17-worktrunk-integration-for-worktree-workflows"
title: "Tight worktrunk integration for worktree workflows"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Replace every `git worktree add | list | remove` invocation the Bytewyrd plugin currently documents or runs with the `wt` CLI shipped by `worktrunk` (verified: shell — `wt --version` returns `wt 0.49.0` on the author's machine; Context7/Exa: `worktrunk.dev` docs synced into `/home/divoxx/.claude/plugins/marketplaces/worktrunk/docs/content/`), and add a project-level `.config/wt.toml` so worktree lifecycle hooks (commit-message generation, dependency install, lint/test gates) live in the same place every contributor's `wt switch` and `wt merge` runs already consult. Concretely: `CLAUDE.md` Session-start and Step-2 workflow, `skills/git-branch-cleanup/SKILL.md` worktree-removal logic, and `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` all switch from raw `git worktree …` to `wt switch -c`, `wt list`, and `wt remove`; `scripts/check-requirements.sh` gains a hard probe for the `wt` binary that exits with status 2 when it is missing; `/sync` Step 5 creates `.config/wt.toml` from a new template under `.claude-plugin/scripts/templates/wt.toml.tpl` and registers it as a manifest artifact so re-runs are diff-checked like every other plugin-managed file. The `wt` dependency is *hard* — every documented workflow is a single `wt`-form command. The one exception is merging the default branch into a feature branch (e.g., `git merge origin/main` to pull new commits from `main` into the in-progress worktree), which remains raw git because `wt merge` operates only on the rebase / squash / fast-forward merge-into-default-branch direction and has no equivalent for the opposite direction.

## Should we do this?

**Yes.** The plugin currently documents one workflow (`git worktree add .worktrees/<branch> -b <branch>` in `CLAUDE.md:L120` and `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L31` — verified) and silently expects another (the user already runs `wt switch -c` because the author's `~/.config/worktrunk/config.toml` is configured with `worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"` — verified). That drift has two costs: contributors who follow the documented commands literally end up with worktrees at the same path `wt` would produce (the manual `.worktrees/<branch>` convention happens to match the user's worktrunk template), but they get none of the lifecycle benefits — no pre-start install step, no pre-merge lint/test gate, no LLM-generated commit messages, no `wt list` overview when juggling parallel agents. The plugin's `.claude-plugin/CLAUDE.md:L126` already says "Use the `/worktrunk` skill to create an isolated worktree + branch" (verified) — so the official prescription has moved on, but the *project* `CLAUDE.md` (the file every consumer reads) still says the opposite. This RFC closes that gap.

The cost is one new manifest artifact (`wt.toml`), one new hard-dependency probe in `scripts/check-requirements.sh`, four small skill / template edits (`CLAUDE.md.tpl`, `CONTRIBUTING.md.tpl`, `git-branch-cleanup/SKILL.md`, `BEST_PRACTICES.md.tpl`), and updates to the plugin's own `CLAUDE.md` so the dogfood matches the prescription. The benefit accrues to every project on every `wt switch`: dependency install on worktree creation, commit-message generation on `wt merge`, optional lint/test gates before merge, and `wt list` as a single command that replaces the `git worktree list + git branch --show-current + git log --oneline -5` triple the Session-start checklist currently runs (`.claude-plugin/CLAUDE.md:L86,L95` — verified). The hard-dependency posture means every documented workflow is a single `wt`-form command — no dual-path branches in skill bodies, no decision-matrix fallback columns, no parallel documentation forms in prose. The plugin makes `wt` part of the baseline toolchain the same way it already requires `git`.

The alternative — keep the status quo, where the project's `CLAUDE.md` documents `git worktree add` but the official prescription is `/worktrunk` — guarantees that drift between documentation and practice continues, that new contributors take the longer path, and that the project-level hooks (`pre-start`, `pre-merge`) are never authored because no skill creates the file that holds them.

## Current state

### The two-workflow split

The plugin today carries two distinct worktree workflows in different files:

1. **The `CLAUDE.md` / `CONTRIBUTING.md.tpl` workflow uses raw `git worktree` commands.** `CLAUDE.md:L118-L120` (verified) lists Session-start as `git worktree list && git branch --show-current` followed by `git worktree add .worktrees/<branch> -b <branch>` for new work. `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl:L28-L32` (verified) is identical for the contributor-onboarding docs that `/sync` writes into every consumer project's `docs/CONTRIBUTING.md`. `skills/git-branch-cleanup/SKILL.md:L21,L66,L69` (verified) uses `git worktree list` to enumerate active worktrees and `git worktree remove --force "$worktree"` to delete them. `BEST_PRACTICES.md.tpl:L36` (verified) says "Run `git fetch --all` at the start of every session before creating branches or worktrees" — no mention of `wt`.

2. **The `.claude-plugin/CLAUDE.md` workflow uses worktrunk.** `.claude-plugin/CLAUDE.md:L126` (verified) says "Use the `/worktrunk` skill to create an isolated worktree + branch for this task." `.claude-plugin/CLAUDE.md:L88,L98-L99` (verified) Session-start uses `git worktree list` (still raw git) but the next-step prescription is to switch to `/worktrunk`.

The split has spread because `/sync` writes `docs/CONTRIBUTING.md` from `CONTRIBUTING.md.tpl` and `CLAUDE.md` (the project root version) from `CLAUDE.md.tpl` — both templates still use the old `git worktree add` examples — so every project synced today gets the raw-git documentation by default. The author's own machine sidesteps this by running `wt switch -c` directly (because `~/.config/worktrunk/config.toml` is configured), but a fresh contributor reading the project's own `docs/CONTRIBUTING.md` sees the old workflow.

### What worktrunk does today on this machine

`wt --version` returns `wt 0.49.0` (verified). The user's `~/.config/worktrunk/config.toml` has `worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"` set (verified — the file was read), which means `wt switch -c rfc/foo` produces a worktree at `<repo_root>/.worktrees/rfc-foo`. This is the *same* path the plugin's `.gitignore.tpl:L2` (verified — line entry is `.worktrees/`) already excludes, and the same path `skills/sync/SKILL.md:L460-L461` (verified) creates as part of Step 5: "Create the directory if absent (worktrunk places worktrees at `.worktrees/<branch-sanitized>`)". So the *layout* is already aligned with worktrunk's defaults; what is missing is the *use* of worktrunk's commands.

The project does **not** currently have a `.config/wt.toml` (verified — `ls .config/` returns "No project wt.toml"). This means there are no project-level hooks, no `pre-merge` lint/test gate, no `post-start` install. The single user-config file at `~/.config/worktrunk/config.toml` carries only the `worktree-path` template; no `commit.generation`, no hooks (verified — file was read).

### What `wt` provides that raw `git worktree` does not

The relevant capabilities from `worktrunk.dev` docs (all from the marketplace mirror at `/home/divoxx/.claude/plugins/marketplaces/worktrunk/docs/content/`):

- **`wt switch -c <branch>` creates a branch and worktree in one command** (Exa: `docs/content/switch.md` "Creating worktrees" section). Equivalent raw-git: `git worktree add -b <branch> <path> && cd <path>` — two commands plus an explicit `<path>` derived from the branch name. The `wt` form reads the path template from `~/.config/worktrunk/config.toml` so the developer never types the path.

- **`wt switch -c <branch> -x claude -- '<task>'` creates the worktree and launches Claude with the task as the first argument** (Exa: `docs/content/switch.md` `--execute` flag). This is the parallel-agent pattern the plugin's `CLAUDE.md:L139` ("Each parallel agent needs its own worktree", verified) already recommends, made into a single command.

- **`wt list` returns a table with status (uncommitted changes, ahead/behind, remote sync, CI status)** (Exa: `docs/content/list.md`). Raw equivalent: a combination of `git worktree list`, per-worktree `git status`, `git rev-list --left-right --count main...branch`, and `gh pr status` — none of which `git-branch-cleanup`'s current logic does.

- **`wt remove [branch]` removes the worktree and, by default, also deletes the branch when it is merged or its content is integrated into the default branch** (Exa: `docs/content/remove.md` "Branch cleanup" section). Raw equivalent: `git worktree remove <path> && git branch -d <branch>` plus the explicit merged-into-main check that `git-branch-cleanup` currently does by hand (`skills/git-branch-cleanup/SKILL.md:L46-L48` — verified).

- **`wt merge` runs the merge target's pre-merge hooks, squashes commits, rebases, merges fast-forward, removes the worktree, and runs post-merge hooks** (Exa: `docs/content/merge.md` "Pipeline" section). Raw equivalent: `git checkout main && git merge --squash <branch> && git commit && git push && git branch -d <branch> && git worktree remove`. This is precisely the pattern the plugin's `CLAUDE.md` PR-process implicitly assumes but never automates.

- **Project hooks at `.config/wt.toml` apply to every developer on the team** (Exa: `docs/content/config.md` "Project Configuration" section). User hooks (in `~/.config/worktrunk/config.toml`) apply only to the developer's machine.

- **The hook lifecycle (Exa: `docs/content/hook.md` "Hook Types" section): `pre-switch → (create worktree) → pre-start → post-start (background) / post-switch (background)`; on merge: `pre-commit → post-commit (background) → pre-merge → (merge) → pre-remove → post-remove (background) + post-merge (background)`.** This is the canonical sequence — the plugin's hook design (RFC `2026-05-12-user-scope-plugin-installation` `Done`, verified) puts plugin-shipped Claude Code hooks on `SessionStart` and `SubagentStop`, which fire at *Claude-session* boundaries, not at *worktree-lifecycle* boundaries. The two hook systems are orthogonal: Claude Code hooks fire when a session starts; worktrunk hooks fire when a worktree starts. Both are needed.

- **The `wt` binary requires a one-time shell-integration install (`wt config shell install`)** so that the shell wrapper can `cd` into a newly-created worktree (Exa: `docs/content/config.md` "Shell Integration" section). Without shell integration, `wt switch` prints the target directory but cannot `cd` into it (the user has to copy/paste). This is a manual user-local step the plugin cannot auto-apply.

- **Worktrunk approval gates**: the first time a project's `.config/wt.toml` runs a hook command, `wt` asks the developer to approve the command list (Exa: `docs/content/hook.md` "Security" section, "Project commands require approval on first run"). Approvals are stored in `~/.config/worktrunk/approvals.toml`. `wt --yes` skips the prompt (for CI). This means a project that ships `.config/wt.toml` with `pre-merge.test = "cargo test"` will, on a fresh clone, prompt the developer once before the first `wt merge` runs.

- **The worktrunk Claude Code plugin exists at `worktrunk@worktrunk`** (Exa: `docs/content/claude-code.md` "Installation" section). It provides a `/worktrunk` skill (configuration guidance) plus activity-tracking hooks that set 🤖 / 💬 markers on the branch in `wt list`. This plugin is **separate from this RFC's scope** — the integration this RFC proposes is at the *plugin-prescription* level (we tell users to run `wt switch -c` instead of `git worktree add`), not at the *plugin-bundling* level (we do not require `worktrunk@worktrunk` to be installed in every project). The Claude Code plugin is an orthogonal install the user can choose; the CLI binary is what the workflow depends on.

### What the `check-requirements.sh` hook checks today

`scripts/check-requirements.sh:L97-L100` (verified) hard-fails when `git` is not on PATH. Lines L160-L161 (verified) soft-warns when `gh` is not on PATH. There is no probe for `wt`. The same file's `BYTEWYRD_SKIP_WARN=<id>` mechanism (verified: L29, L46-L50) suppresses individual warnings by ID, with documented suppressible IDs at L198 (`github`, `context7`, `code-review`, `exa`, `firefox-devtools`, `gh-cli`).

### Existing manifest artifacts the new design will sit beside

`/sync` reads `.claude-plugin/bootstrap-manifest.json` and applies each artifact per its extension strategy (verified: `.claude-plugin/bootstrap-manifest.json` — file read, includes 12 artifacts spanning `whole`, `region`, `section`, and `structured` strategies). The new `.config/wt.toml` artifact follows the `structured` extension strategy with an empty `owned_paths` list — the plugin owns only the `bootstrap-content-version` marker on line 1; the project owns the entire body. Decision 3 below explains why the v1 stub uses empty `owned_paths` rather than claiming ownership of specific hook tables.

## Analysis / Options

Five coupled decisions: (1) hard vs. soft dependency on `wt`; (2) which commands switch from raw git to `wt` and which stay raw; (3) the shape and contents of the new project `.config/wt.toml`; (4) how `/sync` and the requirement-check hook surface the dependency; (5) the shape of `git-branch-cleanup`'s execution path under the hard-dependency posture.

### Decision 1 — Hard or soft dependency on `wt`?

**Option A — Hard dependency: `wt` must be on PATH; `scripts/check-requirements.sh` exits with status 2 when missing; every skill body and every documented workflow uses `wt` directly with no `git worktree …` fallback. Recommended.**

The plugin treats `wt` as part of its baseline toolchain — the same posture it already takes for `git`. Every skill body uses `wt` directly. Every prose-level workflow in `CLAUDE.md` and `CONTRIBUTING.md` documents a single `wt`-form command. There are no dual-path branches in skill bodies and no fallback columns in the decision matrix. The check-requirements hook exits with status 2 when `wt` is missing, with a clear install hint pointing at https://worktrunk.dev and a reminder to run `wt config shell install` once after install. The hard-dependency posture buys two structural simplifications worth more than the soft-dep posture's flexibility: skill bodies are half the length they would otherwise be (only one execution path), and documentation reads in a single voice (no "primary / fallback" branching that readers have to mentally collapse). The one operation that does *not* go through `wt` is merging the default branch into a feature branch (`git merge origin/main` to pick up new commits from `main` into the in-progress worktree) — `wt merge` is the *feature-branch → default-branch* direction only (rebase, squash, fast-forward into main), so the opposite direction stays raw git. This is the only exception; every other documented operation is `wt`-only.

**Option B — Soft dependency: every workflow has a `git worktree …` fallback documented inline; `scripts/check-requirements.sh` warns once per session when `wt` is missing; skills detect the binary at call time and choose between `wt`-style and `git`-style commands.**

Rejected. The structural cost is real and recurring: every skill body needs a `command -v wt` probe and two parallel execution paths; every documentation block needs a "primary / fallback" framing; the decision matrix needs a fallback column; readers must mentally collapse two forms every time they read the workflow. Soft-dep is appropriate for *features* the plugin layers on top of an already-functional baseline (e.g., `gh` for GitHub-specific operations, Exa for web search) — operations that can be performed differently or skipped entirely. Worktree creation is not in that category: it is the entry point to every feature-branch session, and the plugin already prescribes a specific convention (`.worktrees/<branch>`) that worktrunk encodes natively. Promoting `wt` to a hard dependency aligns the prescription with the toolchain. Contributors on machines without `wt` install it from https://worktrunk.dev the same way they install `git` — the install path is documented, one-line, and a one-time cost.

**Option C — Auto-install: the requirement-check hook installs `wt` via `cargo install worktrunk` or `brew install worktrunk` when missing.**

Rejected. The plugin does not auto-install any other tool (verified — `check-requirements.sh` only emits install hints, never runs the installer). Auto-installing toolchain binaries from a `SessionStart` hook is an anti-pattern: it requires elevated trust, takes minutes (cargo compiles), and breaks reproducibility (a session that "just works" on one machine but quietly built `wt` from source on first run is harder to debug). The install-hint approach (Option A) keeps the user in control.

**Recommendation: Option A.** Hard dependency. `scripts/check-requirements.sh` exits with status 2 when `wt` is missing. Skill bodies use `wt` directly with no fallback. The single exception is the `git merge origin/main` step (pulling main into a feature branch), which stays raw git because `wt merge` does not support that direction.

### Decision 2 — Which commands switch from raw git to `wt`, and which stay raw?

The plugin executes / documents eight distinct worktree-related operations today. Each is decided independently:

**(a) Listing worktrees** — `git worktree list` (today, in CLAUDE.md Session-start and in `git-branch-cleanup`). **Switch to `wt list`**; `wt list` returns a richer table (status, ahead/behind, CI) than `git worktree list` (path only).

**(b) Creating a worktree + branch** — `git worktree add .worktrees/<branch> -b <branch>` (today, in CLAUDE.md Step 2 and CONTRIBUTING.md.tpl). **Switch to `wt switch -c <branch>`**. The path is computed from the user's `worktree-path` template — the developer no longer types it.

**(c) Creating a worktree and launching Claude with a task** — not currently scripted; new capability. `wt switch -c <branch> -x claude -- '<task>'` is the worktrunk pattern (Exa: `docs/content/switch.md`). The plugin's `/rfc-implement` skill could, in a future iteration, use this to dispatch a `feature-engineer` agent in a fresh worktree — out of scope for this RFC (just documented).

**(d) Removing a worktree** — `git worktree remove --force <path>` (today, in `git-branch-cleanup`). **Switch to `wt remove <branch>`**. `wt remove` runs `pre-remove` and `post-remove` hooks (Exa: `docs/content/remove.md` "Hooks" section) and conditionally deletes the branch if it is merged. The plugin's `git-branch-cleanup` skill invokes `wt remove --yes <branch>` non-interactively; the `--yes` flag bypasses the first-run hook approval prompt (Exa: `docs/content/hook.md` "Security" section) and `wt remove` only deletes the local branch when its six built-in heuristics agree the branch is integrated into main.

**Note on `wt merge`** — `wt merge` is the worktrunk command for merging a feature branch into the default branch. This RFC adds `.config/wt.toml` (which `wt merge` would consult for `pre-merge` and `post-merge` hooks) but does *not* prescribe `wt merge` as the plugin's standard merge path; merges in Bytewyrd projects happen via GitHub PRs (a workflow `wt merge` does not currently model end-to-end). Documenting the file is independent of documenting the command: the file is also consulted by `wt switch -c` (`pre-switch`, `pre-start`) and `wt remove` (`pre-remove`), both of which the plugin *does* prescribe. Developers who want to use `wt merge` locally (e.g., for solo-author projects without PRs) can do so; the `.config/wt.toml` is ready for it, but the plugin's documented PR-driven workflow still applies.

**(e) Determining whether a branch is merged into main** — `git log --oneline main..origin/branch-name | wc -l` (today, in `git-branch-cleanup:L46-L48`). `wt remove` does this check internally with six heuristics (same-commit, ancestor, no-added-changes, trees-match, merge-adds-nothing, patch-id-match — Exa: `docs/content/remove.md` "Branch cleanup" section), which is strictly more thorough than the single-check `git log` form. **Switch to delegating the merge-detection to `wt remove`** (i.e., the skill calls `wt remove` and trusts it to skip the branch deletion when not merged).

**(f) Removing a branch on the remote after merge** — `git push origin --delete <branch>` (today, in `git-branch-cleanup`). `wt remove` does not push branch deletes to the remote (it operates on local state). **Keep raw `git push origin --delete`** — the operation has no worktrunk equivalent.

**(g) Fetching from remote before any branch / worktree work** — `git fetch --all` (today, in `BEST_PRACTICES.md.tpl:L36`). `wt` does not provide a `git fetch` wrapper. **Keep `git fetch --all`** — the operation has no worktrunk equivalent.

**(h) Pulling main into a feature branch (sync-with-main mid-development)** — `git merge origin/main` from inside the feature worktree. `wt merge` operates only in the feature-branch → default-branch direction (rebase, squash, fast-forward into main, with hooks + worktree removal — Exa: `docs/content/merge.md`); it has no inverse for pulling default into feature. **Keep raw `git merge origin/main`** when the developer wants to pick up new commits from `main` into the in-progress feature worktree. The Bytewyrd convention is `git fetch && git merge origin/main` — explicit merge over `git rebase`, no squash, so a contributor can always tell where a feature branch diverged. This is the only documented operation that stays raw git despite having a `wt`-named neighbor.

The decision matrix:

| Operation | Command | Note |
|-----------|---------|------|
| (a) List worktrees | `wt list` | Returns richer status (ahead/behind, CI) than `git worktree list` |
| (b) Create worktree + branch | `wt switch -c <branch>` | Path template lives in user config — developer does not type the path |
| (c) Create + launch agent | `wt switch -c <branch> -x claude -- '<task>'` | Documented but not currently scripted by any skill |
| (d) Remove worktree | `wt remove <branch>` | Runs `pre-remove`/`post-remove` hooks; deletes the local branch when integrated |
| (e) Merge-detection | (delegated to `wt remove`) | Six heuristics; strictly more thorough than `git log --oneline main..origin/branch` |
| (f) Delete remote branch | `git push origin --delete <branch>` | No worktrunk equivalent |
| (g) Fetch from remote | `git fetch --all` | No worktrunk equivalent |
| (h) Pull main into feature branch | `git merge origin/main` | `wt merge` is feature→main direction only; no inverse exists |

### Decision 3 — What does the new project `.config/wt.toml` contain?

This is the highest-leverage decision: the file is shipped by `/sync` into every consumer project, so its default contents define the convention every Bytewyrd project inherits.

**Option A — Empty-stub `.config/wt.toml` with commented-out examples (recommended).**

Ship a file that documents the available hook types as commented-out examples (so developers know what's possible) but defines no actual hooks by default. The project owner uncomments and edits hooks as needed. Concrete template content (the marker on line 1 is inserted by `/sync` at render time per the TOML marker-insertion rule at `skills/sync/SKILL.md:L435` — verified; the template file itself does not carry the marker, matching `mise.toml.tpl` and `.gitignore.tpl`):

```toml
# Worktrunk project hooks. Shared with the team via git.
# See https://worktrunk.dev/hook/ for the full hook reference.
#
# Hook execution order on `wt switch -c`:  pre-switch → pre-start → post-start (bg)
# Hook execution order on `wt merge`:       pre-commit → pre-merge → pre-remove → post-merge (bg)
#
# Uncomment and edit the blocks below as needed. Empty file = no project hooks.

# Install dependencies when creating a worktree (blocks until complete).
# [pre-start]
# install = "<your install command, e.g. bun install / cargo build / uv sync>"

# Validate before merging (blocks the merge if any fail).
# [pre-merge]
# lint = "<your lint command>"
# test = "<your test command>"

# Per-worktree dev server URL surfaced in `wt list`.
# [list]
# url = "http://localhost:{{ branch | hash_port }}"
```

The `{{ branch | hash_port }}` expression in the commented `[list]` example is worktrunk's own template syntax (Exa: `docs/content/list.md` describes `hash_port` as a worktrunk template filter) — it is shown inert inside a TOML comment as a copy-paste hint for the developer who later uncomments the block. `/sync` does not expand template expressions inside TOML comments — its template renderer substitutes only `<placeholder>` (angle-bracket) tokens, not `{{ }}` (verified: `skills/sync/SKILL.md:L431` documents the rule as "for each `<placeholder>` token, substitute the corresponding value from `project_inputs`"). The manifest entry's `templated: false` is additional reinforcement: non-templated artifacts are read directly from the source file with no rendering pass at all. Either guard alone is sufficient; both together close the question definitively.

The rendered file (what a consumer project sees after `/sync`) prepends the marker:

```toml
# bootstrap-content-version: bytewyrd/.config/wt.toml@v1:<sha12>

# Worktrunk project hooks. Shared with the team via git.
... (rest of body as above)
```

The plugin owns the `bootstrap-content-version` marker on line 1 (so re-sync can diff the file); the project owns every other line. The `structured` extension strategy with `owned_paths: []` (empty) means re-syncing the file leaves the body untouched: the iteration over `owned_paths` is zero-length, so no TOML path is replaced (the existing `mise.toml` artifact with `owned_paths: ["tools[]:union"]` iterates over exactly one path; empty is the limit case). The marker on line 1 may be updated if the plugin's template changes, but the body is not. If a future plugin update adds an opinionated default hook — e.g., a universal `pre-commit` formatter check — it can be added to `owned_paths` at that time.

Rationale: a project that runs `/sync` today and gets `.config/wt.toml` immediately can run `wt switch -c rfc/foo` and see no hook output (because nothing is configured), which is the expected silent baseline. The commented-out examples are scaffolding for the next time the project owner wants to add a hook — they do not have to re-read the worktrunk docs.

**Option B — Opinionated defaults: a `pre-merge` hook that runs language-specific test commands.**

`/sync` Step 3 already detects languages and writes per-language quality-gate commands in `settings.json` (verified — `skills/sync/SKILL.md` references quality-gate commands at L594-L597 for Rust, JS/TS, Go, Python). The same commands could go into `.config/wt.toml`'s `pre-merge` section, so `wt merge` would run them automatically.

Rejected as the default because:

- The quality-gate command in `settings.json` runs as a Claude Code `PreToolUse` hook on `Bash(git push:*)` (verified — skills/sync/SKILL.md references the hook chain). The same commands in `pre-merge` would duplicate the gate: `wt merge` would run `cargo test`, then on the subsequent push the PreToolUse hook would run `cargo test` again. The duplication is wasteful and confusing.
- Worktrunk's "first-run approval prompt" (Exa: `docs/content/hook.md` "Security" section) means every consumer project that runs `wt merge` for the first time on a freshly-cloned repo would see an interactive approval prompt. For a CI runner without `--yes`, that is a hang. For a developer, it is a confusing first-encounter.
- The set of *worktree-lifecycle*-specific hooks the plugin would want (run-once-per-worktree-creation install, run-once-per-merge test) overlaps but is not identical to the set of *every-push* hooks already in `settings.json`. Conflating them by pre-populating both would lock in a wrong choice.

The opinionated-defaults path stays open as a future RFC after real usage patterns emerge.

**Option C — Per-language pre-populated hooks: `/sync` Step 3 language detection drives the contents of `.config/wt.toml`'s `pre-start` and `pre-merge` blocks.**

Same arguments as Option B, plus an extra complication: language detection in `/sync` is project-specific and run-time-derived; encoding the result statically into `.config/wt.toml` would mean re-running `/sync` every time the project's language set changes (a project that adds a Python tool to a Rust project would re-sync to get the Python hooks). The static encoding is brittle.

Rejected.

**Recommendation: Option A.** Empty stub with commented examples. The commented form means a developer reading the file sees the available knobs immediately; the empty body means a fresh consumer project gets the file with no surprise hook executions on first use.

### Decision 4 — How do `/sync` and the requirement-check hook surface the dependency?

**Option A — `/sync` creates `.config/wt.toml` unconditionally; `check-requirements.sh` adds a hard probe for `wt` that exits with status 2 when missing. Recommended.**

Given the hard-dependency posture from Decision 1, `.config/wt.toml` is required infrastructure — the canonical location worktrunk reads for project-level hooks (Exa: `docs/content/config.md` confirms `.config/wt.toml` is the only project-config path worktrunk reads). Every consumer project of the plugin runs `wt switch -c`, `wt remove`, and (eventually) `wt merge`, and each of those invocations consults `.config/wt.toml` for project-level pre-start / pre-merge / pre-remove hooks. The file is the team-shared point of attachment for those hooks; without it, every contributor would need to author project-level hooks ad-hoc or coordinate via prose.

The file's *body* is empty by default (commented-out examples only — see Decision 3), so on a fresh consumer project running `/sync` produces a `.config/wt.toml` with the marker on line 1, the explanatory header, and zero active hooks. That is not a contradiction with the "required infrastructure" framing: the *file* is required (it is the named hook-attachment point worktrunk reads, and the marker on line 1 is how `/sync` tracks the artifact across re-runs), but the *contents* are project-owned — the empty-body default just means most consumer projects start with no hooks and add them as they accrete patterns. The same shape applies to the existing `mise.toml` artifact (verified: bootstrap-manifest.json:L193-L196 with `owned_paths: ["tools[]:union"]`): the file is plugin-managed and always present, but the per-project tool list inside it is project-owned. `.config/wt.toml` is the same shape with an empty `owned_paths` — the plugin owns the marker and the file's existence; the project owns every hook table.

Concrete `check-requirements.sh` addition (matching the hard-fail pattern at L97-L100 for `git`):

```bash
# Hard requirement: worktrunk on PATH (the Bytewyrd worktree workflow depends on it).
if ! command -v wt >/dev/null 2>&1; then
  echo "[error] worktrunk (wt) not on PATH." >&2
  echo "  Fix: install worktrunk from https://worktrunk.dev/, then run 'wt config shell install' once for cd integration." >&2
  exit 2
fi
```

The probe goes *before* any soft-warning probes (i.e., before L141 in the current file, in the hard-fail block alongside the existing `git` check). It does not participate in `BYTEWYRD_SKIP_WARN` — the hard-fail block has no suppression mechanism today, consistent with the `git` precedent.

**Option B — `/sync` creates `.config/wt.toml` only when `command -v wt` succeeds.**

Rejected because the file is meant to be team-shared: gating its creation on a single developer's toolchain breaks the team-share invariant. A developer running `/sync` on machine A — even one whose `wt` install is in progress — should produce a file that a teammate on machine B can use. With Decision 1 making `wt` a hard dependency, this is moot in practice (the requirement-check hook fails before `/sync` runs), but the principle stands: the file is shared infrastructure and should not be conditional on per-machine toolchain state.

**Option C — `/sync` adds a Step 8 report row that says "Run `wt config shell install` after install" if `wt` is detected.**

Useful but separate from this RFC. The current `/sync` Step 8 report includes a list of follow-up tasks (verified — `skills/sync/SKILL.md` ~L752). Adding a one-line nudge ("If you haven't run `wt config shell install`, do it now to enable directory-changing for `wt switch`") is a small additive note rather than a separate option. **Adopted as part of Option A** — the report row is the user-facing surface.

**Recommendation: Option A** with the Option C nudge folded in. `/sync` always creates `.config/wt.toml`; the check-requirements hook hard-fails when `wt` is missing; the Step 8 report adds a follow-up note for shell-integration.

### Decision 5 — What does `git-branch-cleanup` do?

**Option A — Single-path `wt`-only skill body: use `wt list --format=json` for enumeration and `wt remove --yes <branch>` for the per-branch delete cascade. Recommended.**

With Decision 1 making `wt` a hard dependency, the skill body has one execution path. `wt list --format=json` (Exa: `docs/content/list.md` "JSON output" section) returns structured per-worktree data including `main_state` (one of `is_main`, `same_commit`, `integrated`, `diverged`, `ahead`, `behind`, `orphan`, `empty`, `would_conflict`), `integration_reason`, `working_tree.modified`, and CI status. The plugin's `git-branch-cleanup` currently classifies branches manually using a combination of `git branch -v`, `git worktree list`, `git branch -r`, and `gh pr list` (verified — `skills/git-branch-cleanup/SKILL.md:L18-L31`). `wt list --format=json` collapses those into one call.

The classification rules in `git-branch-cleanup:L33-L43` (verified) map directly to `wt list --format=json` fields:

| Existing rule | `wt list --format=json` equivalent |
|---------------|-------------------------------------|
| Local branch with `[gone]` | `.remote` field absent + `kind == "branch"` |
| Local branch, no remote, PR is merged | `.main_state == "integrated"` + `.kind == "branch"` |
| Remote branch, PR merged, 0 commits ahead of main | `.main_state == "integrated"` + `.remote.ahead == 0` |
| Branch has worktree + branch is being deleted | `.kind == "worktree"` (use `wt remove <branch>` not `git worktree remove`) |

For the per-branch delete cascade: `wt remove --yes <branch>` handles both the worktree removal and the local-branch deletion in one call (it deletes the local branch only when integrated, per worktrunk's six-check default — Exa: `docs/content/remove.md` "Branch cleanup" section). The remote-branch deletion stays raw `git push origin --delete <branch>` (Decision 2 (f); no worktrunk equivalent).

**Option B — Two-path skill body with a `command -v wt` probe at the top.**

Rejected. With Decision 1's hard-dependency posture, the probe always succeeds (the requirement-check hook fails earlier if `wt` is missing), so the second path is unreachable code. The decision tree's "what if `wt` is absent" branch was the lone reason this skill carried two execution paths; remove it and the skill body halves in length.

**Option C — `git-branch-cleanup` becomes a thin wrapper around `wt remove` (no classification logic at all).**

Rejected because `wt remove <branch>` removes a *specific* branch — it does not enumerate stale branches and ask the user to confirm them in batch. The plugin's `git-branch-cleanup` exists precisely to do the *enumeration + plan + confirm + execute* loop; collapsing it into a one-shot `wt remove` per branch would still require the enumeration and confirmation. The classification logic stays; the executable form changes.

**Recommendation: Option A.** Single-path `wt`-only body using `wt list --format=json` for enumeration and `wt remove --yes <branch>` + `git push origin --delete <branch>` for the per-branch delete cascade.

## Drawbacks

- **Adds a new `wt.toml` template, a new manifest artifact, and a new hard-dependency probe.** The structural addition is one template file (`.claude-plugin/scripts/templates/wt.toml.tpl`) plus one entry in `.claude-plugin/bootstrap-manifest.json`. The check-requirements probe is ~5 lines of shell. The skill / template edits are localized. **Mitigation:** the additions follow existing patterns (the `mise.toml` artifact uses the same `structured` extension strategy with `tools[]:union` — verified: bootstrap-manifest.json:L193-L195; the `git` hard-fail probe in `check-requirements.sh` is the exact shape the new `wt` probe takes).

- **Hard dependency excludes machines without `wt`.** A contributor with a fresh checkout of a Bytewyrd-managed project must install worktrunk before `/sync` runs cleanly — the plugin's `SessionStart` hook exits with status 2 when `wt` is not on PATH. This is friction at first-touch. **Mitigation:** the install path is one command (Exa: `docs/content/_index.md` Install section — Homebrew, Cargo, winget, pacman), the install hint is printed by the failed probe with the URL https://worktrunk.dev, and the same posture already applies to `git` (which the probe also hard-fails on). The plugin treats `wt` as a baseline toolchain component, not an enhancement; first-touch friction is the cost of having a single supported workflow rather than two diverging ones.

- **`.config/wt.toml` adds a new top-level directory to consumer projects (`.config/`).** Projects that already use `.config/` for other purposes (e.g., `.config/nvim/`, `.config/git/`) will see the directory grow. Most projects do not currently have `.config/`. **Mitigation:** the path `.config/wt.toml` is the canonical worktrunk location (Exa: `docs/content/config.md` confirms this is the only project-config path worktrunk reads). No alternative location exists. The directory addition is small and the file is the only entry.

- **Worktrunk's first-run approval prompt is interactive.** A consumer project that adds a `pre-merge` hook to `.config/wt.toml` will, on first `wt merge` after clone, prompt the developer to approve the hook commands. In a CI environment without `--yes`, this is a hang. **Mitigation:** the empty-stub `.config/wt.toml` (Decision 3, Option A) ships with no active hooks, so the approval prompt does not fire on a fresh clone. When a project owner uncomments and adds a hook, the prompt fires once on the next merge and is then remembered (Exa: `docs/content/hook.md` confirms approvals persist in `~/.config/worktrunk/approvals.toml`). The README / Best Practices addition this RFC adds includes a one-line note about the prompt so developers are not surprised.

- **Worktrunk version skew.** A consumer project committed to `.config/wt.toml` with a hook syntax valid in worktrunk 0.49 may break on a developer running worktrunk 0.31 (verified — the CHANGELOG.md mirror shows breaking hook-template-variable changes between 0.31 and 0.32). **Mitigation:** the empty-stub default uses no template variables (all examples are commented out and only invoked by the developer who uncomments them), so the default file is version-stable. The check-requirements probe could be extended later to enforce a minimum version, but is out of scope for this RFC.

- **Shell-integration is per-machine and not auto-applied.** `wt config shell install` writes to the developer's shell-rc file; the plugin cannot run that command on the developer's behalf. Without shell integration, `wt switch` prints the target path but cannot `cd` into it (the developer must paste). **Mitigation:** the Step 8 report's follow-up note (Decision 4) explicitly names `wt config shell install` as a one-time setup. The check-requirements probe could test for shell integration (e.g., by checking the developer's shell-rc), but is out of scope.

- **Cannot run `wt` inside the Claude Code sandbox without an excludedCommands entry.** Worktrunk's hook approval prompt requires TTY (Exa: `docs/content/hook.md` shows interactive `[y/N]` prompt). Inside the Claude Code sandbox, TTY may not be available; even without the approval prompt, `wt`'s shell-integration directives (the side channel that triggers `cd`) require shell-wrapper cooperation that may not flow through the sandbox. **Mitigation:** users invoke `wt` directly from their terminal, not from inside a Claude Code skill or agent. The skills this RFC modifies (`git-branch-cleanup`) call `wt list --format=json` (non-interactive, no TTY required) and `wt remove --yes "$branch"` (with the explicit `--yes` flag to bypass the hook-approval prompt; `wt remove` deletes the local branch only when it confirms the branch is integrated into main, per its six-check default). Interactive operations stay in the developer's terminal. (The plugin does not currently spawn `wt switch -c` from any skill; that pattern is documented for the human to run.)

- **The worktrunk Claude Code plugin (`worktrunk@worktrunk`) is *not* a dependency of this RFC.** Some readers will assume this RFC requires the Claude Code plugin; it does not. The integration is at the CLI level only. **Mitigation:** Decision 1 and the README addition make this distinction explicit.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.claude-plugin/scripts/templates/wt.toml.tpl` | New template: the empty-stub `.config/wt.toml` content described in Decision 3, Option A. Contains the header comments and commented-out hook examples in the body; the `bootstrap-content-version` marker is inserted at line 1 by `/sync` at render time (per the TOML marker-insertion rule at `skills/sync/SKILL.md:L435`), matching the convention of `mise.toml.tpl` and `.gitignore.tpl`. |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Add one new artifact entry for `bytewyrd/.config/wt.toml@v1` pointing at the new template, with `extension_strategy: "structured"`, `owned_paths: []` (empty — the plugin only owns the marker line; project owns every other line), and `templated: false`. The `sha256` field (not `template_sha`, because `templated: false`) is computed by `.claude-plugin/scripts/build-manifest.sh` and committed alongside the manifest edit. |
| Modify | `scripts/check-requirements.sh` | Add a hard probe for `wt` on PATH in the hard-fail block alongside the existing `git` check (around L97-L100). Exits with status 2 when missing. No suppressible-ID entry — hard-fail probes do not participate in `BYTEWYRD_SKIP_WARN`. |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | Add a new `## Workflow` section (currently absent — verified) with Session-start and Step-2 guidance using `wt switch -c`. The section is owned by the plugin and re-syncs via the existing `section` extension strategy. The plugin's bootstrap-manifest entry for `CLAUDE.md@v1` adds `## Workflow` to `owned_sections`. |
| Modify | `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl` | Replace lines 28-32 (the raw `git worktree add` block) with the `wt switch -c <branch-name>` form. |
| Modify | `.claude-plugin/scripts/templates/BEST_PRACTICES.md.tpl` | Append a one-line entry to the existing `## Workflow` section noting that the plugin uses worktrunk (`wt`) for worktree creation and that project-level hooks live in `.config/wt.toml`. |
| Modify | `skills/git-branch-cleanup/SKILL.md` | Rewrite Step 1 (Gather State) to use `wt list --format=json` for enumeration. Rewrite Step 4 (Execute) to call `wt remove --yes <branch>` followed by `git push origin --delete <branch>` for remote-branch removal. Keep the classification table (Step 2) and plan presentation (Step 3) unchanged — those are tool-independent. No `command -v wt` probe at the top of the skill body: `wt` is guaranteed by the requirement-check hook. |
| Modify | `CLAUDE.md` (plugin's own, repo root) | Replace lines 118-120 (Session-start workflow) with the `wt list` / `wt switch -c` form. |
| Modify | `.claude-plugin/CLAUDE.md` | Replace L86 (`git worktree list`) with `wt list`. Replace L99 (`git log --oneline -5`) with the `wt list --full` form. Replace L126 (`Use the /worktrunk skill to create...`) with the explicit `wt switch -c <branch>` command. |
| Modify | `skills/sync/SKILL.md` | Add one row to the Step 8 report table for `.config/wt.toml`. Append a follow-up note in the Step 8 reminder list: "Run `wt config shell install` once to enable directory switching for `wt switch`." Add one note to Step 5's manifest-application paragraph mentioning that re-running `/sync` on an existing `.config/wt.toml` will only touch the `bootstrap-content-version` marker line (the body is project-owned). |

No files are deleted. The worktrunk CLI is not added to `mise.toml`; users install it via cargo / brew / their distribution package manager (Exa: `docs/content/_index.md` Install section lists Homebrew, Cargo, winget, pacman). The check-requirements probe surfaces the install hint when it's missing.

### Steps

The steps are ordered so each intermediate commit leaves the repository in a coherent state. Each step is independently committable and reviewable; later steps assume earlier steps' artifacts exist but never assume later steps have run.

#### Step 1 — Create the new template file

Write `.claude-plugin/scripts/templates/wt.toml.tpl` with the full file content below. The template file itself does **not** carry the `bootstrap-content-version` marker — `/sync` inserts the marker at render time per the existing marker-insertion rule documented at `skills/sync/SKILL.md:L433-L438` for TOML files (verified: `skills/sync/SKILL.md:L435` confirms the rule: "TOML (`.toml`): insert `# bootstrap-content-version: <upstream_key>:<sha12>` as line 1, followed by a blank line, then the file content"). This matches the convention of the existing `mise.toml.tpl` and `.gitignore.tpl` templates, which also start with their first content line (verified: both templates were read; neither contains a marker line in the source):

```toml
# Worktrunk project hooks. Shared with the team via git.
# See https://worktrunk.dev/hook/ for the full hook reference.
#
# Hook execution order on `wt switch -c`:  pre-switch → pre-start → post-start (bg)
# Hook execution order on `wt merge`:       pre-commit → pre-merge → pre-remove → post-merge (bg)
#
# Uncomment and edit the blocks below as needed. Empty file = no project hooks.

# Install dependencies when creating a worktree (blocks until complete).
# [pre-start]
# install = "<your install command, e.g. bun install / cargo build / uv sync>"

# Validate before merging (blocks the merge if any fail).
# [pre-merge]
# lint = "<your lint command>"
# test = "<your test command>"

# Per-worktree dev server URL surfaced in `wt list`.
# [list]
# url = "http://localhost:{{ branch | hash_port }}"
```

The rendered file (what consumer projects see) has these two extra lines prepended by `/sync`:

```toml
# bootstrap-content-version: bytewyrd/.config/wt.toml@v1:<sha12>

# Worktrunk project hooks. Shared with the team via git.
... (rest of content as above)
```

Verification — the template parses cleanly as TOML (every commented-out block is a TOML comment, so the parsed result is an empty document, which is valid TOML):

```bash
python3 -c 'import tomllib; tomllib.load(open(".claude-plugin/scripts/templates/wt.toml.tpl", "rb")); print("OK")'
```

Expected output:

```
OK
```

#### Step 2 — Register the new manifest artifact

Edit `.claude-plugin/bootstrap-manifest.json` and add a new entry to the `artifacts` array, in alphabetical order by `upstream_key`. The entry goes after the `bytewyrd/.claude/settings.local.json@v1` entry and before the `bytewyrd/.github/PULL_REQUEST_TEMPLATE.md@v1` entry. The exact JSON (the field is `sha256` because `templated: false` — verified against existing non-templated entries like `bytewyrd/.claude/settings.local.json@v1` at `.claude-plugin/bootstrap-manifest.json:L34-L47` which uses `sha256`):

```json
{
  "upstream_key": "bytewyrd/.config/wt.toml@v1",
  "source": ".claude-plugin/scripts/templates/wt.toml.tpl",
  "target": ".config/wt.toml",
  "sha256": "",
  "extension_strategy": "structured",
  "owned_paths": [],
  "templated": false
}
```

The `sha256` is left as `""`; it is computed by the build script.

Then run the manifest builder:

```bash
.claude-plugin/scripts/build-manifest.sh
```

Expected output (the script reports which entries changed):

```
Manifest updated: 1 entry's hash recomputed.
  - bytewyrd/.config/wt.toml@v1 → sha256: <new-sha256>
```

(The hash is a hex string of length 64. The exact value is determined by the file content from Step 1; the verification here is structural: one new line in the output naming the new artifact, no errors.)

#### Step 3 — Add the worktrunk probe to `scripts/check-requirements.sh`

Edit `scripts/check-requirements.sh`. Insert the following block immediately after the existing `git` hard-fail probe at L97-L100 (current content: `if ! command -v git >/dev/null 2>&1; then echo "..." >&2; exit 2; fi`). The insertion goes between that closing `fi` and the next probe block.

```bash
# Hard requirement: worktrunk on PATH (the Bytewyrd worktree workflow depends on it).
if ! command -v wt >/dev/null 2>&1; then
  echo "[error] worktrunk (wt) not on PATH." >&2
  echo "  Fix: install worktrunk from https://worktrunk.dev/, then run 'wt config shell install' once for cd integration." >&2
  exit 2
fi
```

The suppressible-IDs line at L198 does not change — `worktrunk` is a hard-fail probe with no `BYTEWYRD_SKIP_WARN` entry, consistent with the `git` precedent.

Verification — run the hook script directly with `wt` artificially removed from PATH:

```bash
env -i PATH=/usr/bin:/bin HOME="$HOME" bash scripts/check-requirements.sh
echo "Exit code: $?"
```

Expected output:

```
[error] worktrunk (wt) not on PATH.
  Fix: install worktrunk from https://worktrunk.dev/, then run 'wt config shell install' once for cd integration.
Exit code: 2
```

With `wt` on PATH, the hook script exits 0 (assuming no other hard-fail or warning conditions are active).

#### Step 4 — Add a `## Workflow` section to `CLAUDE.md.tpl`

Edit `.claude-plugin/scripts/templates/CLAUDE.md.tpl`. Insert a new H2 section between the existing `## Tool Usage` section (line 30) and the existing `## RFC Process` section (line 34). The new section's full body (the outer fence below uses four backticks so the inner ```bash``` triple-backtick fence is preserved verbatim — the actual template file uses standard three-backtick fences):

````markdown
## Workflow

### Session start

1. Run `wt list` and `git branch --show-current`. Surface active feature-branch worktrees and ask: resume or start new?
2. Run `git fetch --all` before creating branches or worktrees.

### Starting new work

On `main` with new work, create an isolated worktree + branch:

```bash
wt switch -c <branch-name>
```

`wt switch -c` creates the branch from the default branch (`main`/`master`) and switches to the new worktree. The worktree path comes from `~/.config/worktrunk/config.toml`'s `worktree-path` template; the Bytewyrd convention is `{{ repo_path }}/.worktrees/{{ branch | sanitize }}` — where `sanitize` replaces `/` with `-` — so the resulting path is `.worktrees/<sanitized-branch-name>`. Project-level hooks in `.config/wt.toml` (pre-start install, pre-merge lint/test) run automatically.

### Pulling main into a feature branch

To pick up new commits from `main` into the in-progress feature worktree (the only documented worktree operation that stays raw git — `wt merge` is feature-branch → default-branch direction only, with no inverse):

```bash
git fetch
git merge origin/main
```

Each parallel agent needs its own worktree. Sub-agents share the parent worktree.

Never start long-running processes — ask the user to run in a separate terminal.

**Always write to the current working directory** — if invoked from a worktree, write there. Never use `git rev-parse --git-common-dir` to find the "main" repo root and redirect writes to it. A worktree is the intended branch context; files written there are committed on the branch and reviewed via PR.
````

Now update the `CLAUDE.md@v1` manifest entry to add `## Workflow` to its `owned_sections`. Open `.claude-plugin/bootstrap-manifest.json` and find the `bytewyrd/CLAUDE.md@v1` entry (verified — currently spans lines 80-106 and lists `owned_sections` at L85-L96). Add `"## Workflow"` to the array, placing it alphabetically between `"## Tool Usage"` (current L89) and the next entry. The updated `owned_sections` array:

```json
"owned_sections": [
  "## Toolchain",
  "## File structure",
  "## Agent delegation",
  "## Tool Usage",
  "## Workflow",
  "## RFC Process",
  "## Evidence-Based Development",
  "## Model Usage Optimization",
  "## Claude Code Sandbox — Container Tool Compatibility",
  "## Security",
  "## Conventions"
]
```

Re-run `.claude-plugin/scripts/build-manifest.sh` to recompute the `template_sha` for `bytewyrd/CLAUDE.md@v1` after the template body grew. Expected output line:

```
  - bytewyrd/CLAUDE.md@v1 → template_sha: <new-sha256>
```

Verification — the template renders cleanly (no unresolved placeholders) by simulating a sync run with empty inputs:

```bash
grep -E '<[A-Z_]+>' .claude-plugin/scripts/templates/CLAUDE.md.tpl
```

Expected output: only the existing placeholders (`<project_name>`, `<description>`, `<project_slug>`, `<LANGUAGE_TOOLCHAIN_SECTION>`, `<AGENT_TABLE_ROWS>`, `<TOOL_USAGE_SECTION>`) — no new placeholders introduced by the workflow section.

#### Step 5 — Update `CONTRIBUTING.md.tpl`

Edit `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl`. Replace the current lines 26-34 (the "Development Workflow" section with the raw `git worktree add` block) with the `wt`-only block below. The outer fences below use four backticks so the inner ```bash``` triple-backtick fences are preserved verbatim — the actual `.tpl` file uses standard three-backtick fences.

For reference, the current lines (verbatim per `Read`) are:

````markdown
## Development Workflow

All work happens on feature branches. Use the [git worktree](https://git-scm.com/docs/git-worktree) workflow for parallel tasks:

```bash
git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
# work here
```

See `CLAUDE.md` for agent delegation guidance.
````

Replace with (verbatim):

````markdown
## Development Workflow

All work happens on feature branches. The plugin uses [worktrunk](https://worktrunk.dev/) (`wt`) to manage git worktrees for parallel tasks; `wt` is a baseline toolchain dependency (the plugin's `SessionStart` hook hard-fails when it is not on PATH).

```bash
wt switch -c <branch-name>
```

`wt switch -c` creates the branch from the default branch and switches to the new worktree at `.worktrees/<sanitized-branch-name>` (where `/` in the branch name is replaced with `-`, per the user's `~/.config/worktrunk/config.toml` `worktree-path` template). Project-level hooks in `.config/wt.toml` (pre-start install, pre-merge lint/test) run automatically; the file ships with commented-out examples and is empty by default.

To pull new commits from `main` into an in-progress feature worktree, use raw git — `wt merge` is the feature-branch → default-branch direction only and has no inverse:

```bash
git fetch
git merge origin/main
```

See `CLAUDE.md` for agent delegation guidance.
````

Re-run `.claude-plugin/scripts/build-manifest.sh` to recompute `bytewyrd/docs/CONTRIBUTING.md@v1`'s `sha256` (the template is non-templated; the manifest entry uses `sha256`, not `template_sha` — verified). Expected output line:

```
  - bytewyrd/docs/CONTRIBUTING.md@v1 → sha256: <new-sha256>
```

#### Step 6 — Update `BEST_PRACTICES.md.tpl`

Edit `.claude-plugin/scripts/templates/BEST_PRACTICES.md.tpl`. Find the existing `## Workflow` section's last bullet (line L36 is the existing `git fetch --all` entry — verified). Append one new bullet immediately after it:

```markdown
- _Workflow_: Use `wt switch -c <branch>` (worktrunk) to create worktrees. The worktree lands at `.worktrees/<sanitized-branch>` (the path comes from the user's `~/.config/worktrunk/config.toml` `worktree-path` template). Project-level hooks live in `.config/wt.toml` (created by `/sync` as an empty stub with commented examples). The only worktree operation that stays raw git is pulling main into a feature branch (`git fetch && git merge origin/main`) — `wt merge` is feature→main direction only.
```

Re-run `.claude-plugin/scripts/build-manifest.sh`. Expected output line:

```
  - bytewyrd/docs/BEST_PRACTICES.md@v1 → template_sha: <new-sha256>
```

#### Step 7 — Rewrite `skills/git-branch-cleanup/SKILL.md` for `wt`-only execution

The current skill body has four steps. The rewrite keeps the same four steps; Steps 1 and 4 are rewritten to use `wt list --format=json` + `wt remove --yes`. Step 2 (Classify Each Branch) and Step 3 (Present a Plan) stay unchanged. No `command -v wt` probe at the top of the skill body — `wt` is guaranteed by the requirement-check hook.

Full replacement content (the entire SKILL.md after the YAML frontmatter and `# Git Branch Cleanup` heading; the outer fence below uses four backticks so the inner ```bash``` triple-backtick fences are preserved verbatim — the actual SKILL.md file uses standard three-backtick fences):

````markdown
## Overview

Systematically identify and remove stale branches across local, remote, and worktrees by combining git state with GitHub PR status. Always present a plan before deleting anything.

The skill uses [worktrunk](https://worktrunk.dev/) (`wt`) for enumeration and removal — `wt list --format=json` returns one structured table covering both worktrees and branches with integration state, and `wt remove --yes` handles the worktree + local-branch delete cascade with six built-in merge-detection heuristics. Worktrunk is a baseline plugin dependency; the requirement-check hook guarantees `wt` is on PATH when this skill runs.

## Steps

### 1. Gather State

One call returns everything Step 2 needs to classify:

```bash
git fetch --prune
wt list --format=json --branches --remotes
```

The output JSON is an array of entries with the fields documented at https://worktrunk.dev/list/#json-output — relevant fields:
- `.branch` — branch name (null for detached HEAD)
- `.kind` — `"worktree"` or `"branch"` (the latter is a branch without a worktree)
- `.path` — worktree path (absent when `.kind == "branch"`)
- `.main_state` — `"is_main"`, `"same_commit"`, `"integrated"`, `"diverged"`, `"ahead"`, `"behind"`, `"orphan"`, `"empty"`, or `"would_conflict"`
- `.remote` — `{ name, branch, ahead, behind }` or absent when no upstream
- `.ci.status` — `"passed"`, `"running"`, `"failed"`, `"conflicts"`, `"no-ci"`, `"error"` (with `--full` only)

Cross-check with GitHub PR status — `wt list`'s CI status is informational; the PR-merged check is still authoritative for "should this be deleted":

```bash
gh pr list --state merged --limit 30 --json number,title,headRefName
gh pr list --state open --json number,title,headRefName
```

### 2. Classify Each Branch

| Condition | Action |
|-----------|--------|
| Local branch with `.remote` absent + `.kind == "branch"` (formerly `[gone]`) | Delete local |
| `.main_state == "integrated"` + `.kind == "branch"` (PR merged, no worktree) | Delete local |
| Local branch, no remote, no PR | Delete local (confirm intent) |
| `.main_state == "integrated"` + `.remote.ahead == 0` (PR merged, 0 commits ahead of main) | Delete remote |
| Remote branch, no local, no open PR, old | Delete remote |
| `.kind == "worktree"` + branch is being deleted | `wt remove` handles the order automatically |
| Branch has open PR | Keep |
| `.main_state == "is_main"` (default branch) | Keep |

For the "integrated" state, `wt` collapses six heuristics — same-commit, ancestor, no-added-changes, trees-match, merge-adds-nothing, patch-id-match — into one field. See https://worktrunk.dev/remove/#branch-cleanup for the heuristics' definitions.

### 3. Present a Plan

Before deleting anything, show a table:

| Branch | Location | Reason |
|--------|----------|--------|
| `foo/bar` | local | remote absent — remote deleted |
| `origin/old-feature` | remote | merged PR #12, 0 commits ahead of main |

Ask for confirmation, then execute.

### 4. Execute

`wt remove --yes <branch>` operates on local state — it removes the worktree (if any) and deletes the local branch (when integrated, per worktrunk's six-check default — see https://worktrunk.dev/remove/#branch-cleanup). The `--yes` flag skips the first-run hook approval prompt. For a remote-only branch (no local branch, no worktree — appears as a remote in `wt list --format=json --remotes`), skip `wt remove` and call only `git push origin --delete` because there is nothing local for `wt remove` to act on.

```bash
# Case 1 — branch exists locally (with or without a worktree):
# Remove worktree (if any) + delete local branch when integrated (one call):
wt remove --yes "$branch"

# Case 1b — local branch exists but is not yet integrated, and the user
# explicitly confirmed force-delete:
wt remove --yes --force-delete "$branch"

# Case 2 — remote-only branch (no local, classified as "Delete remote" in Step 2):
# Skip wt remove; the remote operation has no worktrunk equivalent.
git push origin --delete "$branch"

# Case 3 — branch existed both locally and remotely, both should go:
wt remove --yes "$branch"
git push origin --delete "$branch"
```

## Common Mistakes

- Deleting a branch with an open PR — always check the open PR list first.
- Calling `wt remove` without `--yes` in a script context — `wt` will prompt for hook approval on the first run per project and hang waiting for stdin.
- Trusting `.main_state == "integrated"` alone for a remote branch deletion without cross-checking the PR state — a force-pushed branch can appear `integrated` if the diff was preserved while history was rewritten; the PR-merged check from `gh pr list` is the authoritative confirmation.
````

Verification — the skill body parses cleanly as Markdown (no unclosed code fences):

```bash
awk '/^```/ {n++} END {if (n%2 != 0) {print "UNCLOSED FENCE"; exit 1} else print "OK"}' skills/git-branch-cleanup/SKILL.md
```

Expected output:

```
OK
```

#### Step 8 — Update the plugin's own `CLAUDE.md` and `.claude-plugin/CLAUDE.md`

Edit the plugin's own root `CLAUDE.md` (the file consumers see when browsing the plugin repo). Replace lines 118-120 (verbatim per `Read`):

```markdown
1. Run `git worktree list` and `git branch --show-current`. Surface active feature-branch worktrees and ask: resume or start new?
2. Run `git fetch --all` before creating branches or worktrees.
3. On `main` with new work: `git worktree add .worktrees/<branch> -b <branch>`.
```

With (verbatim):

```markdown
1. Run `wt list` and `git branch --show-current`. Surface active feature-branch worktrees and ask: resume or start new?
2. Run `git fetch --all` before creating branches or worktrees.
3. On `main` with new work, create an isolated worktree + branch with `wt switch -c <branch-name>`. The worktree lands at `.worktrees/<sanitized-branch>` (where `/` in the branch name is replaced with `-`, per the user's `worktree-path` template). Project hooks in `.config/wt.toml` (pre-start, pre-merge) run automatically.
4. To pull main into the feature worktree mid-development, use raw git (`wt merge` is feature→main direction only): `git fetch && git merge origin/main`.
```

Edit `.claude-plugin/CLAUDE.md`. Replace line 86 (verbatim: `git worktree list`) with:

```
wt list
```

Replace line 99 (verbatim: `- Summary of recent commits (`git log --oneline -5` in the worktree)`) with:

```
- Summary of recent commits (`git log --oneline -5` in the worktree) — `wt list --full` includes a per-branch LLM summary when configured
```

Replace line 126 (verbatim: `2. Use the `/worktrunk` skill to create an isolated worktree + branch for this task.`) with:

```
2. Create an isolated worktree + branch with `wt switch -c <branch-name>` — the path comes from the user's `~/.config/worktrunk/config.toml` `worktree-path` template (Bytewyrd convention: `{{ repo_path }}/.worktrees/{{ branch | sanitize }}`, where `sanitize` replaces `/` with `-`). The `/worktrunk` skill (from the `worktrunk@worktrunk` Claude Code plugin) provides configuration guidance for hooks and templates — install it via `claude plugin install worktrunk@worktrunk` if you want in-session help, but the CLI `wt` is what the workflow depends on.
```

Verification — the file is well-formed Markdown:

```bash
awk '/^```/ {n++} END {if (n%2 != 0) {print "UNCLOSED FENCE in CLAUDE.md"; exit 1}; print "CLAUDE.md OK"}' CLAUDE.md
awk '/^```/ {n++} END {if (n%2 != 0) {print "UNCLOSED FENCE in .claude-plugin/CLAUDE.md"; exit 1}; print ".claude-plugin/CLAUDE.md OK"}' .claude-plugin/CLAUDE.md
```

Expected output:

```
CLAUDE.md OK
.claude-plugin/CLAUDE.md OK
```

#### Step 9 — Update `skills/sync/SKILL.md`

Edit `skills/sync/SKILL.md`. Three additions:

(a) Step 8 report table — add one new row immediately after the `.worktrees/` row (verified: line 718 in the current file is `| .worktrees/ | created / already exists |`). The new row:

```markdown
| `.config/wt.toml` | added / fast-forward applied / unchanged / local-only edit preserved / unchanged (legacy marker added) — empty stub by default; project owns body |
```

(b) Step 8 follow-up reminder list — at the very end of the file (the bullet list of follow-up tasks per `skills/sync/SKILL.md:L753-L755`), append one new bullet:

```markdown
- Run `wt config shell install` once to enable directory switching for `wt switch` (one-time per shell-rc). The `.config/wt.toml` file ships empty by default; uncomment example hooks in the file to enable pre-start install or pre-merge lint/test gates.
```

(c) Step 5 — locate the existing `Non-manifest items` section (verified: line 458) and within it the existing two `### .worktrees/` headings (verified: lines 460, 484). The new `.config/wt.toml` is a *manifest* item, so it does not need a section under Non-manifest items — it is handled by the existing manifest-driven flow at the start of Step 5. However, the new artifact's empty body and `owned_paths: []` are unusual enough to warrant a brief note. Append a paragraph to the existing "Template-based artifact rendering" section (verified: line ~540), in the table of templates (verified: line 544 onwards), adding one row:

```markdown
| `wt.toml.tpl` | `bytewyrd/.config/wt.toml@v1` | Non-templated; structured strategy with empty `owned_paths` (plugin owns marker line only; project owns body) |
```

This row goes alphabetically by `upstream_key` — between the `.gitignore.tpl` row and the `bootstrap-versions.json.tpl` row in the existing table (verified — the table currently spans rows for `CLAUDE.md.tpl`, `README.md.tpl`, `BEST_PRACTICES.md.tpl`, `CONTRIBUTING.md.tpl`, `ARCHITECTURE.md.tpl`, `settings.json.tpl`, `settings.local.json.tpl`, `mise.toml.tpl`, `.gitignore.tpl`, `ci.yml.tpl`, `PULL_REQUEST_TEMPLATE.md.tpl`, `.bootstrap-versions.json.tpl`).

Verification — confirm the manifest table now lists the new row by line count:

```bash
grep -c 'wt.toml.tpl' skills/sync/SKILL.md
```

Expected output:

```
1
```

(One mention in the manifest table; the artifact gets no separate Non-manifest section because it is a manifest item.)

### Sanity check: re-running `/sync` on this very plugin

After all steps land, run `/sync` from the plugin's own repo root. Because the plugin is its own dogfood:

- `.config/wt.toml` does not exist today (verified) → `/sync` classifies it as `add` and writes the empty-stub content. Report row: `added`.
- The plugin's `CLAUDE.md` and `.claude-plugin/CLAUDE.md` are not synced via `/sync` (they live in the plugin repo, not in a consumer project) — they were edited directly in Step 8.
- The new `wt.toml.tpl`, the `BEST_PRACTICES.md.tpl` addition, the `CONTRIBUTING.md.tpl` rewrite, the `CLAUDE.md.tpl` workflow section, and the new `bootstrap-manifest.json` entry (plus the `owned_sections` update for `CLAUDE.md@v1`) are all template-source / manifest edits that produce new SHAs in the manifest. The pre-commit hook (`manifest-check.sh`) blocks the commit if the manifest is stale (verified: `.claude-plugin/CLAUDE.md` Architecture section L191-L203). So Step 2's and Step 4's manual `build-manifest.sh` invocations are the moments the manifest is brought in line with the template edits; without those, the commit will fail.

Re-running `/sync` after the manifest is in sync produces no fast-forward updates (the plugin's own `.config/wt.toml` was added on first run; on second run it is `unchanged` because the marker matches).

### Verification

After implementing, run these checks. Each maps to a decision in the analysis.

1. **`git-branch-cleanup` Step 1 calls `wt list --format=json`**. With `wt` on PATH, run `/git-branch-cleanup` against a repo with one merged branch (no worktree), one stale local branch (`[gone]` upstream), and one active branch with an open PR. Verify Step 1's output is the JSON array from `wt list --format=json --branches --remotes`. Verify the classification table in Step 2 correctly identifies each branch's state from the `.main_state`, `.kind`, and `.remote` fields.

2. **`/sync` creates `.config/wt.toml` on a fresh consumer project**. In a fresh repo (no `.config/` directory present), run `/sync`. Verify `.config/wt.toml` is created with the marker on line 1 and the commented-out hook examples in the body. Re-run `/sync` immediately. Verify the file is reported as `unchanged` in the Step 8 report and the file is not rewritten (`md5sum .config/wt.toml` matches across the two runs).

3. **`/sync` does not stomp on project-owned hooks**. In a fresh repo, run `/sync`. Edit `.config/wt.toml` to add `[pre-merge]\ntest = "cargo test"`. Re-run `/sync`. Verify the file is reported as `local-only edit preserved` (the plugin owns no `owned_paths` so the user edit is preserved). Verify the `[pre-merge]` block is still in the file. Verify the marker line is unchanged (no marker bump, since the plugin's content did not change).

4. **`check-requirements.sh` hard-fails when `wt` is missing**. With `wt` not on PATH, run `env -i PATH=/usr/bin:/bin HOME=$HOME bash scripts/check-requirements.sh; echo "Exit: $?"`. Verify the output contains a line matching `\[error\] worktrunk \(wt\) not on PATH` on stderr and the exit code is `2`. With `wt` back on PATH, verify the same script exits `0` and produces no `worktrunk`-related output.

5. **`check-requirements.sh` runs cleanly when `wt` is present**. With `wt` on PATH and no other hard-fail conditions active (run in a known-clean environment where `git` is also present), verify `bash scripts/check-requirements.sh; echo "Exit: $?"` exits `0`. (Soft-warning conditions like missing `gh` or unconfigured Exa may still produce stderr lines but do not affect the exit code.)

6. **Re-running `/sync` after editing a template advances the manifest**. Edit `.claude-plugin/scripts/templates/wt.toml.tpl` (e.g., add a blank comment line at the bottom). Run `.claude-plugin/scripts/build-manifest.sh`. Verify the `bytewyrd/.config/wt.toml@v1` entry's `sha256` value changes. Run `/sync` in a fresh consumer project. Verify the file is created with the new content. Run `/sync` in an existing consumer project that already has `.config/wt.toml` from a prior version. Verify the file is reported as `fast_forward` and the new comment line is added; no project-owned content is lost.

7. **Pre-commit manifest hook blocks stale-manifest commits**. Edit any template (`wt.toml.tpl`, `CLAUDE.md.tpl`, `CONTRIBUTING.md.tpl`, or `BEST_PRACTICES.md.tpl`) without running `build-manifest.sh`. Attempt `git commit -m "test"`. Verify the commit is rejected with the manifest-check error (per `.claude-plugin/CLAUDE.md` L201-L203 — verified). Run `.claude-plugin/scripts/build-manifest.sh` and retry the commit. Verify the commit succeeds.

8. **`CLAUDE.md.tpl`'s `## Workflow` section renders correctly**. Manually run the template rendering for a fresh project: simulate `/sync` Step 4 on a hypothetical project with name `Sample` and one detected language (Rust). Verify the rendered `CLAUDE.md` contains a `## Workflow` heading with the single-form `wt switch -c <branch-name>` block (no fallback column or alternative form), and the section is placed between `## Tool Usage` and `## RFC Process`. Verify the `Pulling main into a feature branch` subsection documents `git fetch && git merge origin/main` as the only documented worktree operation that stays raw git.

9. **The empty-stub `wt.toml` does not trigger worktrunk's approval prompt**. With `wt` on PATH and a fresh consumer project's `.config/wt.toml` (the empty-stub from `/sync`), run `wt switch -c test/foo` from the project root. Verify no approval prompt appears (the file has no active hooks; worktrunk's prompt only fires when project hooks are configured per Exa: `docs/content/hook.md` "Security" section). Verify the worktree is created at `<repo_root>/.worktrees/test-foo` (the path matches the user's `worktree-path` template). Clean up with `wt remove --yes test/foo`.

10. **`wt switch -c` lands at the expected `.worktrees/<sanitized-branch>` path**. In a sample repo with the user's `~/.config/worktrunk/config.toml` `worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"` (the Bytewyrd convention), run `wt switch -c test/a`. Verify the worktree path is `<repo>/.worktrees/test-a` (`/` in the branch name is replaced with `-`). Verify the branch was created from `main` (or the configured default branch). Clean up with `wt remove --yes test/a`.

11. **`.config/wt.toml` re-sync does not lose the marker even after the plugin updates the marker schema**. The marker is `# bootstrap-content-version: bytewyrd/.config/wt.toml@v1:<sha12>` on line 1. If a future plugin update bumps to `@v2`, the legacy `@v1` marker should be classified as `conflict_legacy` by `/sync` Step 4 and the user offered the standard "Adopt plugin and add marker" resolution (per `skills/sync/SKILL.md:L411` — verified). Verify this manually by editing the marker on line 1 to `@v0` (a fake older version) and re-running `/sync`; verify the legacy-marker conflict path runs.

12. **The plugin's own `CLAUDE.md` and `.claude-plugin/CLAUDE.md` no longer recommend `git worktree add`**. Run `grep -rn 'git worktree add' CLAUDE.md .claude-plugin/CLAUDE.md`. Verify the command does not appear in either file as a recommended worktree-creation form. The only acceptable surviving mention is inside a verbatim "current content" quotation in this RFC's Implementation Spec text, which is not under those filenames.

13. **`git merge origin/main` is the only raw-git command documented in the worktree workflow**. Run `grep -rn 'git worktree\|git merge origin' CLAUDE.md .claude-plugin/CLAUDE.md .claude-plugin/scripts/templates/CLAUDE.md.tpl .claude-plugin/scripts/templates/CONTRIBUTING.md.tpl .claude-plugin/scripts/templates/BEST_PRACTICES.md.tpl skills/git-branch-cleanup/SKILL.md 2>/dev/null`. Verify every `git worktree` match is absent (no recommended form remains in any of these files; pre-RFC quotations only live in this RFC, which is not in the grep paths). Verify `git merge origin/main` appears in the plugin's own `CLAUDE.md`, in `CLAUDE.md.tpl`, in `CONTRIBUTING.md.tpl`, and in `BEST_PRACTICES.md.tpl` as the documented form for the "pull main into feature branch" operation.

If any verification step fails, the failure points to one of: (a) the template edit produced malformed Markdown / TOML (Steps 1 / 4 / 5 / 6 — fixed by re-reading the file and correcting), (b) the manifest entry has the wrong `extension_strategy` or `owned_paths` (Step 2 — fixed by re-running `build-manifest.sh` and inspecting), (c) the probe in `check-requirements.sh` is shadowed by an earlier `exit 2` (Step 3 — fixed by inspecting the script around L97-L100 where the new probe sits next to the `git` probe), (d) the skill body's commands still reference raw `git worktree` (Step 7 — fixed by re-reading the skill and confirming every `git worktree` mention was replaced), or (e) the plugin's own files were missed during the dogfood edit (Step 8 — fixed by re-grepping for `git worktree add` and confirming all callsites use `wt switch -c`).

## Risks and open questions

- **Risk: worktrunk's hook approval mechanism is unfamiliar to most contributors.** A developer who clones a project for the first time and runs `wt merge` will see an interactive `[y/N]` prompt for every hook command, with no advance warning. **Mitigation:** the empty-stub `.config/wt.toml` (Decision 3) has no active hooks, so the default experience is silent. When a project owner uncomments a hook, the README/CONTRIBUTING.md edits include the note "Worktrunk asks once to approve each new hook command." **Open question:** should the plugin pre-populate `~/.config/worktrunk/approvals.toml` somehow? No — that file is per-developer and outside the project; no automation should touch it. The acceptance is per-developer-per-project and that is the design.

- **Risk: A project owner authors a `pre-merge` hook that fails on a contributor's clean clone (e.g., a missing build artifact).** Without `--no-verify`, the `wt merge` will block. **Mitigation:** worktrunk has `--no-verify` to skip hooks (Exa: `docs/content/hook.md` "Security" section), so a stuck contributor has an escape hatch. The plugin's documentation does not need to call this out — it is upstream worktrunk behavior.

- **Risk: `wt remove` with `--yes` and a project hook silently runs hooks on every cleanup.** A `pre-remove` hook that has side effects (e.g., archive logs) would fire every time the cleanup skill calls `wt remove --yes`. **Mitigation:** the empty-stub `.config/wt.toml` has no `pre-remove` hook by default; the only way side effects fire is if the project owner intentionally added one, in which case the side effect is desired. The cleanup skill could pass `--no-verify` to skip hooks but that would also skip the legitimate side effects the project owner wanted. **Resolution within this RFC:** keep `--yes` and run hooks (which is the worktrunk default). A future RFC can add a `--no-verify` flag to `git-branch-cleanup` if needed.

- **Risk: The `.config/` directory may collide with other tools that read `.config/`.** Some tools (e.g., a project-local `.config/git/`) treat `.config/` as their own namespace. **Mitigation:** worktrunk's project-config path is canonically `.config/wt.toml` (Exa: `docs/content/config.md`), one file in one location. The directory is shared but the file's name is unambiguous; no collision is possible at the file level. Projects that already have `.config/` see one new file alongside whatever else lives there.

- **Risk: Version skew between the developer's `wt` and a project's `.config/wt.toml`.** A hook block written against worktrunk 0.49's template-variable set may not work on a developer with worktrunk 0.31 (the CHANGELOG mirror shows breaking template-variable changes between 0.31 and 0.32 — verified). Under the hard-dep posture (Decision 1), the requirement-check hook only asserts `wt` exists on PATH — it does not assert a minimum version. So a contributor with an outdated `wt` install passes the hard-fail check but then sees a per-command failure (`wt switch -c` errors when expanding the template, or `wt merge` errors when running a hook with a newer template variable) — a more confusing failure mode than the up-front "wt not installed" message. **Mitigation:** the empty-stub default uses no template variables (the commented examples reference `{{ branch | hash_port }}` but only as commented examples; they only matter when the user uncomments them), so the default file is version-stable for every supported worktrunk version. Adding a minimum-version assertion to the hard-fail probe (e.g., `wt --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'` then a `printf '%s\n%s' | sort -V | head` check) is captured as a follow-up RFC (see "Relationship to other RFCs" below) rather than included here, because the version floor depends on which template variables and hook keys the plugin's shipped `.config/wt.toml` content uses — and that surface is empty in v1.

- **Open question: Should `/sync` write per-language `pre-start` install hooks?** Decision 3 rejected this for the v1 stub. The follow-up question: after some real usage, will every consumer project's `.config/wt.toml` end up with the same one-line `pre-start.install = "..."`? If yes, the v2 stub could pre-populate per the detected language. **Resolution within this RFC:** capture as a follow-up; the empty-stub ships first; usage patterns inform the v2 update.

- **Open question: Should `/git-branch-cleanup` be renamed to `/branch-cleanup` (dropping the `git-` prefix) since its sole execution path is now `wt`-driven?** The current name says "git" but the skill body is `wt`-only. **Resolution within this RFC:** keep the name; renaming is a separate concern (it would break user aliases and require a CHANGELOG note, and is unrelated to the worktrunk integration). A future RFC can rename if the convention shifts.

- **Open question: Should the plugin ship a `wt`-aware variant of `/rfc-implement` that creates the implementation worktree with `wt switch -c <implementation-branch> -x claude -- '<rfc-task-prompt>'` in a single command?** This is the most powerful pattern worktrunk enables (Exa: `docs/content/tips-patterns.md` "Alias for new worktree + agent" section). **Resolution within this RFC:** out of scope. The pattern is documented in `CLAUDE.md.tpl` and `CONTRIBUTING.md.tpl` for the human to use; the skill-level automation is a separate RFC.

- **Open question: Should this RFC also recommend the `worktrunk@worktrunk` Claude Code plugin as an installed companion?** Adding it to the requirement-check hook's recommended-plugins list (alongside `github@claude-plugins-official`, `context7@claude-plugins-official`, `code-review@claude-plugins-official`) would surface the install hint. **Resolution within this RFC:** no. The Claude Code plugin is *additional* (activity tracking + configuration guidance skill); the CLI binary is what the workflow depends on. Pushing developers toward the plugin every session would be noise for those who only want the CLI. The README addition (Best Practices entry) mentions the plugin as an optional add-on.

- **Risk: The plugin's own `CLAUDE.md` (lines 118-120) and the synced template `CLAUDE.md.tpl` produce slightly different content.** The plugin's `CLAUDE.md` has its own three-step Session-start list embedded in the larger `## Workflow` section (verified — `CLAUDE.md:L114-L142` is the full section, much longer than the new template's `## Workflow` section). The template `CLAUDE.md.tpl` does not currently have a `## Workflow` section at all (verified). Adding a `## Workflow` section to the template (Step 4) creates a new owned section that did not exist; the existing plugin `CLAUDE.md` will see no change from a `/sync` perspective because `/sync` is never run against the plugin's own `CLAUDE.md`. **Mitigation:** the plugin's `CLAUDE.md` is edited manually in Step 8 to mirror the template's Session-start guidance; the template change in Step 4 is for consumer projects. There is no consumer-project drift, but the plugin's own `CLAUDE.md` and the template's `## Workflow` body are not byte-identical (the plugin's version covers more topics — parallel agents, write-to-cwd rule, etc., which are appropriate for the plugin maintainer audience but redundant for a fresh consumer project).

## Relationship to other RFCs

- **`2026-05-12-user-scope-plugin-installation`** (status: `Done`) — established `scripts/check-requirements.sh` as the single hook that runs on `SessionStart`. The hook has two probe classes: hard-fail probes (no suppression, exit 2 on miss — currently only `git`) and soft-warning probes (suppressible via `BYTEWYRD_SKIP_WARN=<id>`, exit 0 with stderr message — currently `github`, `context7`, `code-review`, `exa`, `firefox-devtools`, `gh-cli`). This RFC extends the hard-fail class with one new probe (`wt`), matching the `git` precedent.

- **`2026-05-14-sync-per-file-extension-strategies`** (status: `Done`) — defined the `structured` / `section` / `region` / `whole` extension strategies that the manifest uses. This RFC uses `structured` with empty `owned_paths` for `.config/wt.toml` — a configuration the strategy supports today (per the existing `mise.toml` entry's `owned_paths: ["tools[]:union"]` pattern, verified: bootstrap-manifest.json:L193-L196, with `tools` being a *single* owned path; the new entry having `owned_paths: []` is the limit case). The Step 5 / Step 7 logic in `skills/sync/SKILL.md` handles empty `owned_paths` correctly because the `structured` strategy iterates over `owned_paths` — an empty list iterates zero times, leaving the entire file body intact.

- **`2026-05-12-sync-enforce-github-branch-auto-delete`** (status: `Approved`) — adds the `/github-verify` skill that `/sync` Step 6 calls. This RFC's worktrunk integration does not touch Step 6; the two RFCs are independent and merge cleanly. They share the pattern of "use the GitHub remote / a CLI tool to enforce a convention" but operate on different tools (`gh` vs. `wt`).

- **`commit-commands:clean_gone` skill** (from the companion `commit-commands` plugin) — removes branches marked `[gone]` and their worktrees. This skill is independent of `git-branch-cleanup` (which lives in this plugin). This RFC's `wt`-only rewrite of `git-branch-cleanup` does not affect `clean_gone`; both can run side-by-side. The two skills could converge in a future RFC if their classifications diverge in practice, but they are conceptually different (`clean_gone` is single-shot per-branch; `git-branch-cleanup` is plan-and-batch).

- **Future RFC — `wt`-aware `/rfc-implement`** (Open question above) — would have `/rfc-implement` spawn the `feature-engineer` agent in a fresh worktree created via `wt switch -c <impl-branch> -x claude -- '<rfc-content>'`. The pattern is documented in this RFC's `CLAUDE.md.tpl` but not yet automated. With `wt` already a hard dependency (per Decision 1), the future RFC is a single-path implementation: one `wt switch -c -x` invocation and an explicit failure if `wt` is somehow absent (which should be impossible given the requirement-check hook). No fallback path needed.

- **Future RFC — minimum worktrunk version enforcement** (Open question above) — would extend the hard-fail probe to assert `wt --version` returns at least some pinned floor (e.g., `0.49`). The infrastructure exists in `check-requirements.sh` (the hard-fail mechanism); the version-comparison logic is small but adds complexity. Captured as a follow-up.

- **Future RFC — Worktrunk Claude Code plugin (`worktrunk@worktrunk`) as a recommended companion** (Open question above) — would add `worktrunk@worktrunk` to the recommended-plugins list in `check-requirements.sh` (alongside `github`, `context7`, `code-review`). The activity-tracking benefit (🤖/💬 markers in `wt list`) is valuable for users running multiple parallel agents but adds noise for users who just want the CLI. This RFC takes the conservative path; a future RFC can promote the plugin.
