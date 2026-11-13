---
rfc: "2026-11-09-init-and-doctor"
title: "Replace /sync with init + doctor"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-11-09"
drop_reason: ~
implemented_by: ~  # PR URL(s) of the implementation; set when status becomes Done
---

# Replace /sync with init + doctor

Tags `[R#]`/`[E#]` cite Appendix A; Appendix D records the review.

## Summary

`/sync` is about 5.75K lines that merge plugin content into consumer files on every run [R6]. It is replaced by:

- **init** seeds at most four small, stamped files, once.
- **By-reference content:** the RFC process, the best-practices library and five always-on rules stay in the plugin.
- **doctor** is a read-only drift check that reports through CI exit codes.

## Should we do this?

Yes. `/sync` has seven verified defects:

- Crashes on fresh repos [R1].
- Writes relative to its subdirectory [R3].
- Deletes user lines in "owned" regions [R19b].
- Writes before consent [R19c].
- LLM-merges CLAUDE.md with no check [R19d].
- Commits hooks into consumer repos [R4].
- Left this repo's CI without jobs [R5].

The evidence favours a small always-on context [E5, E11, E12]. Skills alone often go uninvoked [E13], so a seeded pointer stays.

## Current state

- Scripts need bash 4 or later [R2], but macOS ships 3.2 [E16].
- 11 skills rely on `${CLAUDE_PLUGIN_ROOT}`, which the Bash tool leaves unset [R14, E7]. None declares `compatibility:`, and ten `mcp__` IDs ship [R14].
- Each repo keeps its own copy of `docs/rfc-process.md` [R16].

## Options

Rejected alternatives:

- **Fix `/sync`.** Merging into user files is the fault itself [R6].
- **Guarded copies** [E17, E20]. Copies drift [E22].
- **Tool-rewritten marker blocks** [E15]. They still write user files; OpenSpec dropped them [E19].
- **Pure by-reference.** A plugin can't ship CLAUDE.md context [E1], skills go uninvoked [E13], and checkout-only users get nothing [E18].

Chosen: seed once [E21], reference at runtime [E22b], and check.

## Design

### init

**Seeds**, each only if absent:

- `AGENTS.md`: at most 100 lines of tool-neutral facts plus a workflow pointer.
- `CLAUDE.md`: `@AGENTS.md` plus Claude-only lines. Without the import, Claude ignores AGENTS.md [E4].
- `.github/PULL_REQUEST_TEMPLATE.md`, unless GitHub finds a template [E47].
- `ci.yml`, unless a workflow exists. It is a no-op job [E30], or a caller when root manifests are tracked (OQ-1).

**Safety:**

- Dry run unless `--apply`.
- Never overwrites or follows symlinks; a symlinked directory on a target's path exits 1.
- A dirty tree [E33] exits 3 unless `--allow-dirty`.
- Writes at the top level [E32], never under `.claude/` (OQ-4).

**Stamp.** Line 1 of each file is `bytewyrd:init v1 tpl=<template>:<sha12> plugin=<sha12|unknown>`.

- The hash covers the CR-stripped template, so edits never move it [R19a].
- `plugin=` is the installed commit [E42].

### By-reference content

- **Docs:** `skills/rfc-process/references/` and `skills/best-practices/references/<stack>.md` replace the copies. A `docs/rfcs/` directory opts a repo in to RFCs.
- **Always-on rules:** five factual statements [E40] in `hooks/always-on-rules.json`. SessionStart emits them as `additionalContext` on `startup|clear|compact` [E14]. They persist across `resume` and `fork` [E25].
- **Budget:** ≤ 2,000 characters [E3], ≈ 740 tokens [E26]; exact cap per OQ-3.
- **Companions:** declared as `dependencies` (OQ-6), with `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]`. Install instructions add the official marketplace first, since `claude plugin` never registers it [E41].
- **`check-requirements.sh` goes:**
  - Exa and Firefox are MCP servers [R10] and degrade at the point of use [R21].
  - Without git, init and doctor exit 1.

### doctor

Deterministic and read-only, with no LLM.

- **Exit codes:** 0 clean, 2 drift, 1 cannot run (crashes included). `--strict` counts warnings as drift.
- **Drift findings:**
  - `template-changed`, which prints a diff and the new stamp.
  - `bad-stamp`.
  - `no-import`.
  - One `legacy-*` finding per known 0.2.x path.
- Full table: B2.

### Portability

- Agent Skills layout [E6].
- `${CLAUDE_PLUGIN_ROOT}` uses document a fallback.
- Scripts self-locate via `BASH_SOURCE` [E7] and run on bash 3.2 [R2].
- No `mcp__` IDs.
- Claude-only skills declare `compatibility:` [R22].

## Drawbacks

- Contributors, CI and cloud agents without the plugin lose the process and library [E18]. AGENTS.md links both.
- A missing or disabled dependency silently unloads bytewyrd, rules and doctor with it [R31, E41]. Hard dependencies can't be disabled [E2].
- Template changes need human edits. Consumer CI running doctor must pin the plugin ref.

## Migration

1. **Add (PR 1):** init, doctor, the rules hook, both skills, dependencies and the plugin CI. Delete `check-requirements.sh`. `/sync` still works.
2. **Migrate (one PR per repo: three installs, then this repo):**
   1. Run doctor, apply the `legacy-*` fixes (B3), and commit.
   2. Run `init --apply`.
   3. Port the non-owned CLAUDE.md sections, then commit.
   4. Confirm doctor exits 0.
3. **Delete (PR 3):** remove `/sync`, its scripts, manifest, templates and tests.
   - **Keep:** `common.bash` [R8, R26], `tool-probe.sh` [R9], and the guarded sentinel write, until doctor finds no `legacy-settings-hooks`.
   - **Shrink:** `detect-languages` and preflight become about 30 lines [R27, R28].

## Acceptance criteria

Each is automated; B5 maps it to its check.

- **AC-1** `init` exits 0 and writes nothing.
- **AC-2** `--apply` in a fresh, even commit-less, repo creates exactly the missing targets, each stamped, and nothing else (nothing under `.claude/`).
- **AC-3** Existing targets are skipped and never followed: files, case variants, directories, dangling symlinks, recognised PR templates, any workflow.
- **AC-4** A symlinked directory on a target's path exits 1 and writes nothing.
- **AC-5** On a dirty tree, `--apply` exits 3 unless `--allow-dirty`.
- **AC-6** Runs from subdirectories write at the top level; outside a work tree, both scripts exit 1.
- **AC-7** A mid-apply failure exits 1 and leaves none of its files.
- **AC-8** The no-language caller equals `init-noop-fixture.yml` from line 2, and that workflow passes on GitHub.
- **AC-9** Language callers pin every `uses:` to a 40-hex SHA, request only `contents: read`, and contain no `secrets:` or `pull_request_target` (OQ-1).
- **AC-10** Apply, commit, apply → `0 created`, a clean tree, and doctor exit 0.
- **AC-11** doctor leaves fixtures unchanged and exits 0, 2 or 1 as specified (1 on crashes). `--strict` makes warnings exit 2.
- **AC-12** A template edit → `template-changed`, exit 2. The printed stamp restores 0.
- **AC-13** Legacy fixtures yield exactly their `legacy-*` findings. After Phase 2, doctor exits 0.
- **AC-14** CRLF files pass, and CRLF and LF templates hash the same.
- **AC-15** consumer-sim passes with `CLAUDE_PLUGIN_ROOT` unset or `/nonexistent`, and under macOS `/bin/bash` 3.2.
- **AC-16** `.bytewyrd/` writes never go through symlinks.
- **AC-17** The `startup|clear|compact` hook emits `always-on-rules.json` within the cap. No hook calls `check-requirements`.
- **AC-18** `claude plugin validate .` exits 0 [E9], and a temp-HOME install shows no load errors.
- **AC-19** `agents/`, `skills/`, `hooks/` and `templates/` contain no `mcp__` IDs, `docs/rfc-process.md` or `/sync`. Claude-only skills declare `compatibility:`.

## Test plan

CI runs these (B4, B5):

- The bats suite, which no job runs today [R5].
- consumer-sim on Ubuntu under `env -u CLAUDE_PLUGIN_ROOT`, and on macOS under `/bin/bash` 3.2.
- `claude plugin validate`.
- A temp-HOME install.

## Rollback

Each phase is one merge commit. Revert it with `git revert -m 1 <sha>`, newest first; consumers get it on their next update [E42]. Repo-side changes are commits, and deleted files stay in history. A revert cannot undo what consumers already ran.

## Security considerations

- **Trust root:** this repo's `main`. With no `version`, every commit reaches consumers on their next update [E42]. Teams can pin `bytewyrd/claude-bytewyrd#<ref>` [E43].
- **Writes:** init writes four fixed paths, offline, never through symlinks. Hooks run outside the sandbox [E39], so writers to `.bytewyrd/` refuse symlinks. Substitution is literal, and YAML gets only allowlisted language ids.
- **Context:** the rules hook reads nothing from the repo. Rule 2 treats repo text as information.
- **Supply chain:** the allowlist trusts `claude-plugins-official` [E2]; OQ-6 covers the PAT. Every `uses:` is SHA-pinned, inside reusable workflows too [R43], and CI requests only `contents: read`.

## Open questions and risks

For the human, with no recommendation:

- **OQ-1: Where does the reusable CI workflow live?**
  - (a) This repo: public, any caller can use it [E29]; updates need SHA bumps.
  - (b) A dedicated repo: own cadence, one more repo.
  - (c) Nowhere: init renders jobs inline; updates only via doctor.
  - (d) No caller: always the no-op, which drops AC-9 and `ci-variant`.
- **OQ-2: Is init a skill, a script, or both?**
  - Script: deterministic and fully testable.
  - Skill: richer facts, but every script-driven AC and simulation step becomes manual.
  - Both: script seeds, skill offers a reviewed AGENTS.md fill-in.
- **OQ-3: How are the rules sized and updated?** Options are a fixed cap with PR review, a cap plus a Chainguard-style eval gate [E23], or per-repo AGENTS.md additions.
- **OQ-4: Is any hook ever written into consumer repos?** Options are never, an opt-in init flag (which brings settings merging back), or a documented snippet.
- **OQ-5: Keep the names?**
  - Keep `/bytewyrd:init` and `/bytewyrd:doctor`; the bare names run Claude Code's built-ins [E24, E45]. Bare `/doctor` proposes fixes that Claude applies once you confirm, the inverse of read-only. Bare `/init` writes a CLAUDE.md. `disable-model-invocation` stops automatic selection [E28].
  - Rename: no ambiguity, but different from the chosen names.
- **OQ-6: Which companions become hard `dependencies`?** All three [R10], or github only. Either way, hard dependencies can't be disabled [E2]. github also pushes adopters toward a PAT that every shell command inherits [E46, E39], and keeps tools like `delete_repository` enabled [R41].

Risks and mitigations:

- **Uninvoked skills** [E13]: the rules and AGENTS.md name them.
- **Unreliable strict validation** [E36, R24]: CI runs non-strict and AC-19 greps instead.
- **Unknown adopters still on the 0.2.x PreCompact hook** [R35]: the sentinel write stays, and the hook's message documents a bypass.

## Relationship to other RFCs

This RFC removes mechanisms from six Done RFCs, makes two Approved ones moot, and touches PRs #100, #102 and #107 [R18]. Appendix E has the details.

## Appendix A — Evidence Audit

Status values:

- **Verified (pack):** confirmed by the orchestrator's brief pack on 2026-11-13.
- **Verified (ledger):** confirmed by the orchestrator while checking review findings on 2026-11-13.
- **Verified (session):** re-checked while drafting on 2026-11-13.

Repo facts and local reproductions:

| ID | Claim as used | Source | Date | Status |
|---|---|---|---|---|
| R1 | A fresh repo crashes: the jq filter `(.brief_name \| if . == "" then .preflight.project_slug else . end)` indexes a string and exits 5 | `scripts/sync-apply-batch.sh:L111` | 2026-11-13 | Verified (session). Reproduced `Cannot index string with string ("preflight")`, exit 5 |
| R2 | Constructs that need bash ≥ 4: `declare -A` and `mapfile` in the sync scripts, and `mapfile` in `rfc-frontmatter.sh` | `scripts/sync-owned-regions-apply.sh:L60,L91,L96,L108,L156,L178`; `scripts/sync-render-template.sh:L65`; `scripts/rfc-frontmatter.sh:L64-L65` | 2026-11-13 | Verified (session) |
| R3 | It writes relative to cwd: an empty repo-root argument falls back to `$PWD`, then `cd`s there | `scripts/sync-run.sh:L70`; `scripts/sync-classify-all.sh:L56,L79` | 2026-11-13 | Verified (session) |
| R4 | The consumer settings template defines SessionStart, PreCompact (which blocks compaction), PostToolUse and Stop hooks. This repo's settings print "Consider running /sync" | `templates/settings.json.tpl:L4-L64`; `.claude/settings.json:L2-L8` | 2026-11-13 | Verified (session) |
| R5 | The rendered CI has `jobs:` with only a comment under it, so runs fail with zero jobs. No job runs `tests/run.sh` | `templates/ci.yml.tpl:L1-L8`; `.github/workflows/ci.yml:L1-L10`; https://github.com/bytewyrd/claude-bytewyrd/actions/runs/29619380118 | 2026-07-17 (run) | Verified (pack); files re-read |
| R6 | Line counts: 18 `sync-*.sh` = 3,881; sync-only `_lib` = 696; `build-manifest.sh` = 63; hook = 4; `SKILL.md` = 847; `check-requirements.sh` = 262; total ≈ 5.75K. Tests: 17 sync bats files = 3,605; `bootstrap-manifest.bats` = 55 | `wc -l` | 2026-11-13 | Verified (session) |
| R7 | The manifest has 11 artifacts. Root `rfc-process.md` is byte-identical to `docs/rfc-process.md` | `bootstrap-manifest.json`; `cmp` | 2026-11-13 | Verified (session) |
| R8 | `_lib/common.bash` is sourced by the `rfc-*` scripts, `build-manifest.sh` and `tool-probe.sh`. `chunks`, `plugin` and `detect-languages` are sourced only by `sync-*` | `grep source scripts/*.sh` | 2026-11-13 | Verified (session) |
| R9 | `tool-probe.sh` probes gh, git, jq and three companion plugins. It has no Exa or Firefox probe | `scripts/tool-probe.sh:L6-L12` | 2026-11-13 | Verified (session) |
| R10 | `check-requirements.sh` probes three companion plugins and the `mcp__exa__` and `mcp__firefox-devtools__` prefixes. It exits 2 when git is missing or a reference is stale | `scripts/check-requirements.sh:L13-L15,L23-L24` | 2026-11-13 | Verified (pack); lines re-read |
| R11 | `hooks/hooks.json` has three entries: a SubagentStop reminder plus sentinel, a SessionStart `compact` reminder, and the check-requirements entry | `hooks/hooks.json` | 2026-11-13 | Verified (session) |
| R12 | The documented install commands; plugin.json has `"version": "0.2.0"`; the marketplace source is `"./"` | `README.md:L9-L10`; `docs/guide/installation.md:L6-L7`; `.claude-plugin/*.json` | 2026-11-13 | Verified (session) |
| R13 | `/sync` appears in 27 files | the brief pack's grep | 2026-11-13 | Verified (session) |
| R14 | 11 skills use `${CLAUDE_PLUGIN_ROOT}`. No skill has `scripts/` or `references/`, and 0 of 14 declare `compatibility:`. There are ten `mcp__` tool IDs: `skills/rfc-implement/SKILL.md:L19`; `agents/claude-agent-author.md:L46,L89,L250`; `agents/rfc-architect.md:L129-L130`; `templates/settings.json.tpl:L37,L46` | `grep -rno 'mcp__[A-Za-z0-9_-]*' skills agents templates hooks` | 2026-11-13 | Verified (session). The grep reports 11 matches; the extra one is the bare pattern `mcp__<server>__<tool>` at `agents/claude-agent-author.md:L87` |
| R15 | Legacy marker forms: headers, banners, the `# bytewyrd:` tags and the sidecar at both locations. `<!--lang:*-->` lines are stripped at render, so they are not markers | `scripts/sync-marker-read.sh:L6-L7`; `scripts/sync-write-header.sh:L84-L86`; `templates/.gitignore.tpl:L1,L4-L5`; `skills/sync/SKILL.md:L69`; `scripts/sync-render-template.sh:L123-L144` | 2026-11-13 | Verified (session) |
| R16 | The RFC opt-in keys on `docs/rfc-process.md`. 35 files outside `skills/sync/` and `docs/rfcs/` reference it | `agents/feature-engineer.md:L69-L72`; grep | 2026-11-13 | Verified (session). The pack counted 19 because it searched fewer files |
| R17 | RFC statuses and summaries. `2026-05-12-auto-extract-best-practices-on-precompact` (Done) introduced the blocking PreCompact hook | `docs/rfcs/*.md` | 2026-11-13 | Verified (session) |
| R18 | Open PRs #100, #101, #102 and #107 mention `/sync`; #109 was closed unmerged | GitHub | 2026-11-13 | Verified (pack) |
| R19a | `/sync` is not idempotent. The mechanism: classification hashes the raw template, while apply stamps the rendered SHA | `skills/sync/SKILL.md:L265` | 2026-11-13 | Mechanism verified (session). End-to-end behaviour: [UNVERIFIED] — reported by the 2026-11-09 audit; not re-reproduced |
| R19b | User lines inside a `# bytewyrd:` block are deleted | `scripts/sync-apply-batch.sh:L336-L372` | 2026-11-13 | Verified (session). Running the awk program verbatim dropped a `.env` line |
| R19c | Writes happen before the "Apply these changes?" prompt | `skills/sync/SKILL.md:L67,L69,L106` vs `:L285` | 2026-11-13 | Verified (session) |
| R19d | An LLM classifies item pairs and replaces items at confidence ≥ 0.5; the soundness review is "an LLM-assisted pass" | `skills/sync/SKILL.md:L437-L463,L471` | 2026-11-13 | Verified (session) |
| R20 | `.bytewyrd/` writers exist, and today only the seeded `.gitignore` hides their output | `hooks/hooks.json:L13`; `skills/best-practices-extract/SKILL.md:L272`; `skills/docs-review/SKILL.md:L53`; `templates/.gitignore.tpl:L4` | 2026-11-13 | Verified (session) |
| R21 | rfc-architect falls back to WebSearch and WebFetch when Exa is unreachable | `agents/rfc-architect.md:L132` | 2026-11-13 | Verified (session) |
| R22 | Nine skills are Claude-only because they use AskUserQuestion, spawn subagents or use `~/.claude`: best-practices-extract, best-practices-record, docs-review, refactor, rfc-braindump, rfc-consensus-review, rfc-implement, rfc-new, rfc-read-feedback | grep over `skills/*/SKILL.md` | 2026-11-13 | Verified (session) |
| R23 | 0.2.x per-language toolchain lines and gate commands. Its CI jobs were "assembled" by the agent | `skills/sync/SKILL.md:L599-L604,L651-L655,L701-L704` | 2026-11-13 | Verified (session) |
| R24 | `claude plugin validate .` (2.1.323) passes with a warning that the root CLAUDE.md is not loaded. Without the root CLAUDE.md, a copy passes `--strict`. Removing `version` adds a warning that fails `--strict`. `dependencies`, the allowlist and the SessionStart entry pass `--strict`. A missing allowlist is not flagged. The directory checks report LICENSE_MISSING | local runs | 2026-11-13 | Verified (session) |
| R25 | This repo's legacy artifacts: headers in seven files, banners in two, both sidecars tracked, settings hooks, and `docs/rfc-process.md` | `git grep`; `git ls-files` | 2026-11-13 | Verified (session) |
| R26 | `compute_upstream_key` is used only by manifest tooling, and `plugin_enabled` by `tool-probe.sh` | `scripts/_lib/common.bash:L48-L69,L71-L82`; `scripts/build-manifest.sh:L46`; `scripts/sync-classify.sh:L165`; `tests/scripts/helpers.bash:L33-L52` | 2026-11-13 | Verified (session) |
| R27 | Worktree-aware project-name logic | `scripts/sync-preflight.sh:L146-L148` | 2026-11-13 | Verified (session) |
| R28 | `detect-languages.bash` is 266 lines and needs python3 with tomllib | `scripts/_lib/detect-languages.bash:L22-L38` | 2026-11-13 | Verified (session) |
| R29 | Sources of the five rules | `templates/CLAUDE.md.tpl:L30-L34,L40-L47,L49-L59,L96-L104`; `CLAUDE.md:L149` | 2026-11-13 | Verified (session) |
| R30 | PR #100's RFC adds a SessionStart `compact` hook | `origin/rfc/2026-05-17-auto-rehydrate-context-after-compaction`: `docs/rfcs/2026-05-17-auto-rehydrate-context-after-compaction.md:L12` | 2026-11-13 | Verified (session) |
| R31 | A plugin with unmet `dependencies` installs with exit 0, warns "bytewyrd will not load without them", and `claude plugin list --json` shows `errors`/`errorDetails` (`dependency-unsatisfied`) | local run, Claude Code 2.1.323, scratch HOME, local marketplace | 2026-11-13 | Verified (session). OPS saw the same with a CLI-only install and with a dependency disabled in `enabledPlugins` |
| R32 | After `git rm`, `git status --porcelain` prints `D  <file>`, so the tree is dirty | local test, git 2.56.0 | 2026-11-13 | Verified (session) |
| R33 | A nested `.bytewyrd/.gitignore` with `*` hides an untracked sidecar despite the root negation. Adding `!.bootstrap-versions.json` restores it, and the nested file stays ignored | local test, git 2.56.0 | 2026-11-13 | Verified (session) |
| R34 | CLAUDE.md's ten 0.2.x `owned_sections`. Other H2s are project-owned, e.g. `## Workflow`, `## Maintaining the bootstrap manifest` | `bootstrap-manifest.json`; `CLAUDE.md:L123,L190` | 2026-11-13 | Verified (session) |
| R35 | The 0.2.x PreCompact hook blocks while the sentinel is absent. Its message documents "bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact" | `templates/settings.json.tpl:L15-L24,L20` | 2026-11-13 | Verified (session) |
| R36 | 0.2.x CI set `working-directory` for non-root components | `skills/sync/SKILL.md:L703` | 2026-11-13 | Verified (session) |
| R37 | `docs/guide/reference/hooks.md` mentions `/sync` | `docs/guide/reference/hooks.md:L3,L65` | 2026-11-13 | Verified (session) |
| R38 | `exit` inside an EXIT trap overrides the status, including after a syntax error later in the script. noclobber refuses to write through a symlink | local tests, bash 5.3.20; bash 3.2 is exercised by the macOS CI job | 2026-11-13 | Verified (session) |
| R39 | A committed symlink at `.bytewyrd` or its target redirects or truncates writes (F1). A symlinked `.github` lets `mkdir -p` and `>` write outside the repo while porcelain stays empty (F2) | SEC reproductions, git 2.56 | 2026-11-13 | Verified (ledger) |
| R40 | A nested `go.mod` makes root `go test ./...` exit 1, and a nested `Cargo.toml` makes `cargo build` exit 101 | OPS reproductions | 2026-11-13 | Verified (ledger) |
| R41 | The GitHub MCP server exposes `merge_pull_request` and `delete_repository` | tool list observed in this drafting session | 2026-11-13 | Verified (session) |
| R42 | The best-practices library's `## Security` section covers secrets, input validation, least privilege, pinning and AuthN/AuthZ | `templates/BEST_PRACTICES.md.tpl:L102-L109` | 2026-11-13 | Verified (session) |
| R43 | A SHA-pinned reusable workflow still resolves the tag refs inside it at run time | review finding F11(b), SEC-3 | 2026-11-13 | Verified (ledger) |
| R44 | Release-tag commits: checkout v7.0.1 `3d3c42e5aac5ba805825da76410c181273ba90b1`, setup-go v7.0.0 `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e`, setup-bun v2.2.0 `0c5077e51419868618aeaa5fe8019c62421857d6`, setup-uv v10.3.3 `68559e99cc807c1eb7e9238fd43a15bba460eec2`, rust-toolchain master `683b588c487a69d01f6c6ddf40f036ff682cc2c8`. All are lightweight tags | `git ls-remote` | 2026-11-13 | Verified (session). The checkout and setup-uv SHAs also appear in uv's and setup-uv's docs |
| R45 | `git -C ROOT ls-files -- go.mod …` lists tracked root manifests only, ignoring nested and untracked ones | local test, git 2.56.0 | 2026-11-13 | Verified (session) |

External sources:

| ID | Claim as used | Source | Date | Status |
|---|---|---|---|---|
| E1 | "A `CLAUDE.md` at the plugin root isn't loaded as context, and `claude plugin validate` warns when it finds one." | https://code.claude.com/docs/en/plugins/manifest-reference#standard-layout | 2026-11-13 | Verified (pack); also seen in R24 |
| E2 | `dependencies` entries are `"name@marketplace"` or `{name, marketplace, version}`. A cross-marketplace dependency needs `allowCrossMarketplaceDependenciesOn`. A missing or disabled dependency keeps the plugin disabled. Since v2.1.143, `claude plugin disable` refuses to disable a depended-on plugin. The default "prevents one marketplace from silently installing plugins from a source the user hasn't reviewed" | https://code.claude.com/docs/en/plugins/manifest-reference#dependencies; https://code.claude.com/docs/en/plugins/dependencies; https://code.claude.com/docs/en/plugins/troubleshooting | 2026-11-13 | Verified (pack); re-read in session |
| E3 | Hook output is capped at 10,000 characters. SessionStart matchers are `startup`, `resume`, `clear`, `compact` and `fork` | https://code.claude.com/docs/en/hooks#sessionstart | 2026-11-13 | Verified (pack); re-read in session |
| E4 | "By default, Claude reads `AGENTS.md` only when you have no `CLAUDE.md`…". The `@AGENTS.md` import is documented | https://code.claude.com/docs/en/memory#agents-md | 2026-11-12 | Verified (pack) |
| E5 | "target under 200 lines per CLAUDE.md file" | https://code.claude.com/docs/en/memory#write-effective-instructions | 2026-11-12 | Verified (pack) |
| E6 | A skill is a directory with `SKILL.md`, and `scripts/`, `references/` and `assets/` are optional. `compatibility` is 1–500 characters; Claude Code accepts it but doesn't act on it | https://agentskills.io/specification; https://code.claude.com/docs/en/skills | 2026-11-13 | Verified (pack); re-read in session |
| E7 | Plugin path variables "aren't present in the environment of commands Claude runs through the Bash tool". They are substituted inline in skill and agent bodies and exported to hook commands | https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables | 2026-11-13 | Verified (pack); re-read in session |
| E9 | `claude plugin validate` exits 0 on pass, 1 on fail and 2 on validator error | https://code.claude.com/docs/en/plugins/cli-reference#plugin-validate | 2026-11-13 | Verified (pack); re-read in session |
| E11 | Context files do "not generally improve task success rates, while increasing inference cost by over 20%". They help with "non-standard coding practices" | https://arxiv.org/abs/2602.11988v3 | 2026-09-29 | Verified (pack) |
| E12 | "A common myth is that you want to make these a central repository for every known practice…" (one author, Thariq Shihipar) | https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models | 2026-07-24 | Verified (pack) |
| E13 | An 8 KB AGENTS.md index scored 100%, while skills peaked at 79% even when told to use them. "In 56% of eval cases, the skill was never invoked." | https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals | 2026-01-27 | Verified (pack) |
| E14 | superpowers uses SessionStart matcher `startup\|clear\|compact` and emits `additionalContext` | https://github.com/obra/superpowers/blob/main/hooks/hooks.json (22f0b463) | 2026-11-13 | Verified (pack) |
| E15 | Next.js "updates only the content between the agent rules markers" | https://nextjs.org/docs/app/guides/ai-agents | 2026-11-13 | Verified (pack) |
| E16 | macOS ships Bash 3.2.57 | https://github.com/apple-oss-distributions/bash/blob/bash-144/version.h | 2026-11-13 | Verified (pack); confirmed through macOS 26.5 |
| E17 | Spec Kit's upgrade stops on modified files unless `--force` is given | https://github.com/github/spec-kit/blob/main/docs/upgrade.md | 2026-04-16 | Verified (pack) |
| E18 | "making a repository checkout insufficient by itself" (a counterweight) | https://github.com/github/spec-kit/issues/2612#issuecomment-5997262816 | 2026-10-05 | Verified (pack) |
| E19 | OpenSpec 1.0 stopped generating tool files; "Only the OpenSpec marker blocks are removed" | https://github.com/Fission-AI/OpenSpec/releases/tag/v1.0.0; https://github.com/Fission-AI/OpenSpec/blob/main/docs/migration-guide.md | 2026-01-26 | Verified (pack) |
| E20 | APM uses a committed lockfile and `apm audit --ci` | https://microsoft.github.io/apm/reference/lockfile-spec/ | 2026-11-13 | Verified (pack) |
| E21 | "Curated shared instructions for software teams" (Adopt): a scaffolding template is "a powerful distribution mechanism for AI guidance" | https://www.thoughtworks.com/radar/techniques/curated-shared-instructions-for-software-teams | 2026-04-15 | Verified (pack) |
| E22 | "Agent plugin marketplace" (Trial): "Copying these between repos provides no easy way to publish, discover or update them." | https://www.thoughtworks.com/radar/techniques/agent-plugin-marketplace | 2026-11-04 | Verified (pack) |
| E22b | "Anchoring coding agents to a reference application" (Trial): agents "query centralized, up-to-date information sources … at runtime" | https://www.thoughtworks.com/radar/techniques/anchoring-coding-agents-to-a-reference-application | 2026-11-04 | Verified (session) |
| E23 | Chainguard gates skill changes with PR review plus CI golden evals scored by an LLM judge. "Eval gate" is this RFC's label | https://www.chainguard.dev/unchained/this-shit-is-hard-how-ai-keeps-our-code-on-standard | 2026-06-24 | Verified (pack) |
| E24 | Plugin skills are namespaced `/plugin:skill`. A bare name works "unless another command already uses that name". `/init` is built in, and `/doctor` is a bundled skill | https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name | 2026-11-12 | Verified (pack) |
| E25 | `additionalContext` is wrapped in a system reminder. "Claude Code saves the injected text in the session transcript". SessionStart hooks run again on `resume` and `fork` | https://code.claude.com/docs/en/hooks (Add context for Claude, L1194) | 2026-11-13 | Verified (session). The hook now uses `additionalContext`, so the earlier plain-stdout gap is gone |
| E26 | A token is about 3.5 English characters on pre-4.7 models, and 4.7+ tokenizers produce about 30% more tokens: 2,000 ÷ 3.5 × 1.3 ≈ 740 | https://platform.claude.com/docs/en/about-claude/glossary | 2026-11-13 | Verified (session) |
| E27 | Block-level HTML comments in CLAUDE.md are stripped before injection | https://code.claude.com/docs/en/memory | 2026-11-13 | Verified (session) |
| E28 | `disable-model-invocation: true` stops Claude invoking a skill on its own | https://code.claude.com/docs/en/skills | 2026-11-13 | Verified (session) |
| E29 | `{owner}/{repo}/.github/workflows/{file}@{ref}` syntax. "Using the commit SHA is the safest option." Public workflows are callable from public and private repos | https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows; https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations | 2026-11-13 | Verified (session) |
| E30 | "A workflow run is made up of one or more `jobs`" | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax | 2026-11-13 | Verified (session) |
| E31 | `actions/checkout` inputs `repository`, `ref`, `path` and `submodules`. Its `allow-unsafe-pr-checkout` note warns about fork code under `pull_request_target` | https://github.com/actions/checkout/blob/main/action.yml | 2026-11-13 | Verified (session) |
| E32 | `--show-toplevel` shows "the (by default, absolute) path of the top-level directory"; also `--git-common-dir` | https://git-scm.com/docs/git-rev-parse | 2026-11-13 | Verified (session) |
| E33 | `--porcelain` "will remain stable across Git versions and regardless of user configuration" | https://git-scm.com/docs/git-status | 2026-11-13 | Verified (session) |
| E34 | `.gitignore` patterns "match relative to the location of the `.gitignore` file" | https://git-scm.com/docs/gitignore; local test | 2026-11-13 | Verified (session) |
| E35 | Native installer: `curl -fsSL https://claude.ai/install.sh \| bash`. The binary goes in `$HOME/.local/bin` | https://code.claude.com/docs/en/setup; https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/configure-claude-code | 2026-11-13 | Verified (session) |
| E36 | `validate --strict --json` reported success while skipping malformed skill and agent frontmatter. No auth is needed | https://github.com/anthropics/claude-code/issues/100078 | 2026-10-06 | Verified (session); fix status unknown |
| E37 | `git ls-files` lists the files in the index (`--cached` is the default) that match the given pathspecs | https://git-scm.com/docs/git-ls-files; R45 | 2026-11-13 | Verified (session) |
| E38 | GNU `env -u NAME` removes NAME | local test: GNU coreutils 9.12 | 2026-11-13 | Verified (session) |
| E39 | "The sandbox covers shell commands only. Claude's file tools, MCP servers, and hooks run outside it". Shell commands inherit Claude Code's environment, "including any secrets in its environment" | https://code.claude.com/docs/en/sandboxing (L11) | 2026-11-13 | Verified (session) |
| E40 | "Write the text as factual statements rather than imperative system instructions… can trigger Claude's prompt-injection defenses" (L1192). Plain stdout and `additionalContext` are each "injected as a system reminder" (L1565). The `hookSpecificOutput.additionalContext` JSON shape | https://code.claude.com/docs/en/hooks | 2026-11-13 | Verified (session) |
| E41 | "The official marketplace isn't registered on this machine yet. Claude Code normally registers it on its own the first time you start an interactive terminal session". "The `claude plugin` shell commands never register it for you". `claude plugin list --json` reports problems in `errors` | https://code.claude.com/docs/en/plugins/troubleshooting (L109) | 2026-11-13 | Verified (session) |
| E42 | The cache path is `cache/<marketplace>/<plugin>/<version>/`, and `${CLAUDE_PLUGIN_ROOT}` points there (L225). Without `version`, the version is the commit SHA: 12 characters for `github` sources, or "the commit SHA of the installed directory" for a relative path in a Git-hosted marketplace (L346-L348) | https://code.claude.com/docs/en/plugins/loading | 2026-11-13 | Verified (session) |
| E43 | "To pin a branch or tag of a GitHub or git-URL marketplace, tell users to append `#<ref>`" (L33). `marketplace add` also accepts a local directory | https://code.claude.com/docs/en/plugins/host-marketplace; https://code.claude.com/docs/en/plugins/install | 2026-11-13 | Verified (session) |
| E44 | Install a given version: `curl -fsSL https://claude.ai/install.sh \| bash -s <version>` | https://code.claude.com/docs/en/setup (L329) | 2026-11-13 | Verified (ledger) |
| E45 | `/doctor` is a "Skill" that "proposes fixes that Claude applies after you confirm" (L85). `/init` is "Initialize project with a `CLAUDE.md` guide" (L100) | https://code.claude.com/docs/en/commands | 2026-11-13 | Verified (session) |
| E46 | The github plugin's `.mcp.json` sends `"Authorization": "Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}"` | anthropics/claude-plugins-official `external_plugins/github/.mcp.json` @893173f | 2026-11-13 | Verified (ledger) |
| E47 | PR templates are recognised at the root, in `docs/` and in `.github/`, plus `PULL_REQUEST_TEMPLATE/` subdirectories in those folders. File names are not case-sensitive | https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository; https://docs.github.com/en/enterprise-server@3.14/communities/using-templates-to-encourage-useful-issues-and-pull-requests/manually-creating-a-single-issue-template-for-your-repository | 2026-11-13 | Verified (session) |
| E48 | The Actions runner trims leading whitespace before parsing workflow commands (`ActionCommand.cs` `TryParseV2`: `message.TrimStart()`) | actions/runner source | 2026-11-13 | Verified (ledger); used in Appendix D |
| E49 | Usage: `actions/setup-go` (`go-version-file: go.mod`); `oven-sh/setup-bun`; `astral-sh/setup-uv` (SHA-pinned examples); `dtolnay/rust-toolchain` (pass `toolchain:` when the rev isn't a toolchain name) | https://github.com/actions/setup-go; https://github.com/oven-sh/setup-bun; https://github.com/astral-sh/setup-uv; https://github.com/dtolnay/rust-toolchain | 2026-11-13 | Verified (session) |

## Appendix B — Implementation spec

### B1. File structure

The phase number is the PR in which the change lands.

| Phase | Action | Path | Responsibility |
|---|---|---|---|
| 1 | Create | `scripts/_lib/scaffold.bash` | Shared functions (B2) |
| 1 | Create | `scripts/init.sh` | Seeds the four files (B2). Created when OQ-2 is "script" or "both". If it is "skill", `skills/init/SKILL.md` carries this contract as prose |
| 1 | Create | `scripts/doctor.sh` | Read-only drift check (B2) |
| 1 | Create | `scripts/state-touch.sh` | The only writer into `.bytewyrd/`, and it refuses symlinks (B2) |
| 1 | Create | `templates/init/{AGENTS.md,CLAUDE.md,PULL_REQUEST_TEMPLATE.md,ci-noop.yml}.tpl` | Seed templates (Appendix C). The PR template is copied from `templates/PULL_REQUEST_TEMPLATE.md.tpl` |
| 1 | Create | `templates/init/ci-caller.yml.tpl`; with OQ-1 (a) also `.github/workflows/lang-ci.yml` | The language caller (Appendix C). Omitted with OQ-1 (d) |
| 1 | Create | `skills/doctor/SKILL.md`; `skills/init/SKILL.md` | Wrappers that print script output verbatim. Names follow OQ-5; `skills/init` follows OQ-2 |
| 1 | Create | `skills/rfc-process/SKILL.md`, `skills/rfc-process/references/rfc-process.md` | Copy of root `rfc-process.md` with L3 and L196-L219 rewritten: no per-repo copy, opt-in through `docs/rfcs/`, and the `/sync` row replaced by init and doctor |
| 1 | Create | `skills/best-practices/SKILL.md`, `skills/best-practices/references/{general,rust,js-ts,python,go,svelte,ruby,rails,k8s-cue,terraform}.md` | `BEST_PRACTICES.md.tpl` split by H2, with `general.md` holding `## Pitfall` through `## Error Handling` and the `<!--lang:*-->` lines dropped. `SKILL.md` carries template L3-L27, with its L21 row repointed to `references/` |
| 1 | Create | `hooks/always-on-rules.json` | The rules as `additionalContext` (Appendix C) |
| 1 | Create | `.github/workflows/init-noop-fixture.yml` | Committed output of the no-op caller (AC-8) |
| 1 | Create | `tests/scripts/{scaffold,init,doctor,hooks,state-touch}.bats`, `tests/e2e/consumer-sim.sh`, `tests/fixtures/legacy-0.2/<case>/` | Tests (B4, B5). There is one legacy case per `legacy-*` code |
| 1 | Modify | `hooks/hooks.json` | Today it has three entries [R11]: add the rules entry, remove check-requirements, and route the SubagentStop write through `state-touch.sh` (Appendix C) |
| 1 | Modify | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | `dependencies` per OQ-6 (versioned entries where the dependency publishes versions) and `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]` |
| 1 | Modify | `.github/workflows/ci.yml` | The plugin's CI (Appendix C) |
| 1 | Modify | `scripts/rfc-frontmatter.sh` | L64-L65: comment `# Split parsed output into fields (read loop; bash 3.2)` and `fields=(); while IFS= read -r l; do fields+=("$l"); done <<< "$parsed"` |
| 1 | Modify | `skills/best-practices-extract/SKILL.md` | L272 becomes `bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-touch.sh" precompact-extraction-done` |
| 1 | Modify | `skills/docs-review/SKILL.md` | L53 becomes `bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-touch.sh" --rm last-feature-engineer-stop` |
| 1 | Modify | `README.md:L9-L10`, `docs/guide/installation.md:L6-L7` | Install sequence from Appendix C, plus the optional `#<ref>` pin |
| 1 | Modify | Rule M1 files: `agents/{ai-engineer,claude-agent-author,code-reviewer,docs-agent,documentation-writer,feature-engineer,llm-architect,mcp-developer,penetration-tester,refactoring-specialist,rfc-architect,security-engineer}.md`, `skills/{docs-review,rfc-new,rfc-summary}/SKILL.md`, `docs/agent-audit-criteria.md` | B3 |
| 1 | Modify | Rule M3 files: `skills/rfc-implement/SKILL.md:L19`, `agents/claude-agent-author.md:L46,L89,L250`, `agents/rfc-architect.md:L129-L130` | B3 |
| 1 | Modify | Rule M4 files: `skills/{best-practices-extract,best-practices-record,docs-review,refactor,rfc-braindump,rfc-consensus-review,rfc-implement,rfc-new,rfc-read-feedback}/SKILL.md` | B3 |
| 1 | Modify | Rule M5 files: `skills/{best-practices-extract,refactor,rfc-approve,rfc-braindump,rfc-consensus-review,rfc-drop,rfc-implement,rfc-new,rfc-read-feedback,rfc-summary}/SKILL.md` | B3 |
| 1 | Modify | `CLAUDE.md`, `docs/guide/reference/hooks.md`, `CHANGELOG.md` | Hook docs and changelog. `docs/guide/**` changes go through `/docs-review` |
| 1 | Delete | `scripts/check-requirements.sh` | Superseded |
| 2 | Create/Modify/Delete | This repo's legacy artifacts [R25]; create `AGENTS.md` | Phase 2 procedure (B4) |
| 3 | Delete | `skills/sync/SKILL.md`; `scripts/sync-{apply-batch,canonical,classify-all,classify,compute-template-vars,detect-languages,find-plugin-root,item-parser,marker-read,owned-regions-apply,preflight,render-template,rfc-process-check,run,sidecar-migrate,summary,unified-diff,write-header}.sh` | `/sync` and its 18 scripts |
| 3 | Delete | `scripts/_lib/{chunks,detect-languages,plugin}.bash`, `scripts/build-manifest.sh`, `hooks/pre-commit/manifest-check.sh`, `bootstrap-manifest.json`, `rfc-process.md`, `templates/*.tpl` (the 11 0.2.x templates; `templates/init/` stays), `tests/scripts/sync-*.bats` (17), `tests/scripts/bootstrap-manifest.bats` | Sync-only code and tests |
| 3 | Modify | `scripts/_lib/common.bash` (delete L48-L69), `tests/scripts/helpers.bash` (delete L33-L52) | Remove `compute_upstream_key` [R26] |
| 3 | Modify | `scripts/state-touch.sh` | The nested `.gitignore` becomes `*` only [R33] |
| 3 | Modify | `.claude/skills/best-practices-sync/SKILL.md` | Writes to `skills/best-practices/references/<stack>.md`; the marker step is deleted |
| 3 | Modify | Rule M2 files, covering the 27 `/sync` mentions [R13] minus deleted files: `agents/{api-designer,docs-agent,documentation-writer,feature-engineer,frontend-developer}.md`, `skills/best-practices-extract/TRIAGE-AND-LIFT.md`, `skills/{best-practices-record,docs-review,rfc-summary}/SKILL.md`, `.claude/skills/best-practices-sync/SKILL.md`, `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/guide/{concepts,contributing,index,installation}.md`, `docs/guide/how-to/{best-practices,docs-review,rfc-process}.md`, `docs/guide/reference/{hooks,skills}.md`, `docs/guide/tutorials/getting-started.md` | B3. `CLAUDE.md` also drops "## Maintaining the bootstrap manifest" |
| Later | Modify | `skills/best-practices-extract/SKILL.md` | Removes the sentinel step and its PreCompact text, once doctor shows no `legacy-settings-hooks` in all four known repos |

`.claude/settings.json` and `.claude/skills/**` may be write-protected in sandboxed agent sessions. If so, the human applies those edits.

### B2. Script contracts

**`scripts/_lib/scaffold.bash`.** It is sourced, never sets `-e`, and must stay bash 3.2-safe (B4 grep). Regexes are held in variables.

| Function | Contract |
|---|---|
| `bw_root` | Prints `git rev-parse --show-toplevel`; returns 1 outside a work tree |
| `bw_project_name ROOT` | Prints `basename "$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)/.." && pwd)"`, falling back to `basename "$ROOT"` [R27] |
| `bw_languages ROOT` | Runs `git -C "$ROOT" ls-files -- go.mod package.json pyproject.toml setup.py Cargo.toml`: tracked files at the root only [E37, R45]. Maps them to `go`, `js`, `python`, `rust` and prints the result sorted |
| `bw_hash FILE` | `tr -d '\r' < FILE`, then sha256 (`sha256sum`, else `shasum -a 256`); prints the first 12 hex digits |
| `bw_plugin_sha DIR` | If `basename DIR` matches `^[0-9a-f]{12,40}$`, prints its first 12 characters [E42]. Otherwise, if `git -C DIR rev-parse --show-toplevel` equals DIR, prints the first 12 of HEAD. Otherwise prints `unknown` |
| `bw_render TPL LANGS NAME` | Strips CRs. Keeps a line starting with `@@<id>@@ ` (with the tag removed) only when `<id>` is in LANGS, or when it is `none` and LANGS is empty. Replaces `@@project_name@@` and `@@languages@@` literally with awk `index`/`substr` from `ENVIRON`. Returns 1 if any `@@` is left |
| `bw_stamp KIND TPL HASH SHA` | `md`: `<!-- bytewyrd:init v1 tpl=TPL:HASH plugin=SHA -->` (an HTML comment, so it is stripped from CLAUDE.md context [E27]); `yml`: `# bytewyrd:init v1 tpl=TPL:HASH plugin=SHA` |
| `bw_read_stamp FILE` | Reads line 1 with CRs stripped and matches it against the regex below. Prints `TPL HASH SHA`. Returns 1 if the line has no `bytewyrd:init`, and 2 if it has one that doesn't parse |
| `bw_exists DIR NAME` | True when `DIR/NAME` exists or is a symlink, or when an entry of DIR equals NAME case-insensitively |
| `bw_pr_template ROOT` | For each of `.`, `docs` and `.github`, prints the first entry whose lowercased name is `pull_request_template` (a directory) or starts with `pull_request_template.` [E47]. Returns 1 if none is found |
| `bw_symlinked_dir ROOT REL` | Prints the first existing component of REL's parent chain under ROOT that is a symlink; returns 1 if there is none |

```
^(<!-- |# )bytewyrd:init v1 tpl=([A-Za-z0-9._-]+):([0-9a-f]{12}) plugin=([0-9a-f]{12}|unknown)( -->)?$
```

The plugin root is `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`. No script reads `CLAUDE_PLUGIN_ROOT`.

**`scripts/init.sh [--apply] [--allow-dirty]`**

The targets, in order:

| Target | Kind | Template | Skipped when |
|---|---|---|---|
| `AGENTS.md` | md | `AGENTS.md` | `bw_exists` |
| `CLAUDE.md` | md | `CLAUDE.md` | `bw_exists` |
| `.github/PULL_REQUEST_TEMPLATE.md` | md | `PULL_REQUEST_TEMPLATE.md` | `bw_exists`, or `bw_pr_template` finds one |
| `.github/workflows/ci.yml` | yml | `ci-noop.yml` when there are no languages, else `ci-caller.yml` (with OQ-1 (d), always `ci-noop.yml`) | `bw_exists`, or `.github/workflows/` holds any `*.yml` or `*.yaml` |

Behaviour:

1. Preflight writes nothing. It checks that git is present, then resolves ROOT. For every target to be created, it runs `bw_symlinked_dir`; a hit exits 1.
2. With `--apply`, a dirty tree exits 3.
3. Each write runs `mkdir -p` on the parent, then `set -C; { stamp; render; } > path`.
4. An EXIT trap maps any exit before `BW_DONE=1` to exit 1 [R38]. First it deletes the files this run created, as recorded in `BW_CREATED`. If deletion fails, it prints `rm --` and the remaining paths.

Output goes to stdout unless noted; columns are separated by two spaces:

| Situation | Output | Exit |
|---|---|---|
| Header | `bytewyrd init: <ROOT>` | — |
| Each target | `would create  <path>`, `created  <path>`, `skip  <path>  (exists; init never overwrites)`, `skip  <path>  (pull request template found: <found>)` or `skip  <path>  (another workflow exists)` | — |
| CLAUDE.md lacks `@AGENTS.md` | `note: CLAUDE.md has no '@AGENTS.md' line; Claude Code will not read AGENTS.md until you add one` | — |
| Dry run with a dirty tree | `note: working tree is dirty; --apply will refuse without --allow-dirty` | 0 |
| Footer | `dry run: N to create, M skipped; re-run with --apply to write`, or `applied: N created, M skipped` | 0 |
| Dirty tree with `--apply` (stderr) | `init: working tree is dirty; commit first or pass --allow-dirty` | 3 |
| Symlinked directory (stderr) | `init: <dir> is a symlink; refusing to write through it` | 1 |
| Any other failure (stderr) | `init: <reason>`, then `init: failed; removed: <paths>` or `init: failed; remove these, then re-run: rm -- <paths>` | 1 |

**`scripts/doctor.sh [--strict]`**

doctor never writes into the repo, and its temporary files are removed by a trap. An EXIT trap maps any exit before the footer to 1.

doctor emits one finding per row trigger, and each path is evaluated by one row only:

- Seed targets go to `legacy-header` if a header is found, otherwise to the stamp rows.
- `no-import` and `too-long` are separate checks.

| Code | Severity | Trigger | Fix line |
|---|---|---|---|
| (none) | ok | Seed target with a v1 stamp whose hash matches the current template | — |
| `template-changed` | drift | The v1 stamp hash ≠ `bw_hash` of the named template | `review the diff, then replace line 1 with: <stamp>`, followed by `diff -u` (current render vs file without line 1) |
| `bad-stamp` | drift | `bw_read_stamp` returns 2 | `replace line 1 with: <current stamp> after reviewing the diff`, followed by the diff |
| `no-import` | drift | AGENTS.md and CLAUDE.md both exist, CLAUDE.md is not a symlink to AGENTS.md, and no CLAUDE.md line (CR stripped) equals `@AGENTS.md` | `add the line @AGENTS.md to CLAUDE.md` |
| `legacy-header` | drift | A header or Managed/Bootstrapped banner [R15] in lines 1–3 of one of the 0.2.x manifest targets [R7]: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md`, `mise.toml` | B3 row for the path |
| `legacy-gitignore` | drift | `.gitignore` has the header or a `# bytewyrd:` tag | B3 |
| `legacy-rfc-process-copy` | drift | `docs/rfc-process.md` contains the line `# RFC Process` | B3 |
| `legacy-settings-hooks` | drift | `.claude/settings.json` contains `precompact-extraction-done`, `Post-commit: does this change component structure`, `Session ending: (1) /best-practices-extract` or `Consider running /sync` | B3 |
| `legacy-sidecar` | drift | `.bytewyrd/.bootstrap-versions.json` or `.claude/.bootstrap-versions.json` exists (one finding per path) | B3 |
| `legacy-state` | drift | `.bytewyrd/plugin-version` or `.bytewyrd/docs-agent-version` exists (one per path) | B3 |
| `ci-variant` | warn | The `ci.yml` stamp names `ci-noop.yml` while `bw_languages` is non-empty (dropped with OQ-1 (d)) | `git rm .github/workflows/ci.yml && git commit, then init --apply` |
| `missing` | warn | A seed target is absent. For the PR template, `bw_pr_template` also fails; for `ci.yml`, no workflow exists | `run init --apply` |
| `too-long` | warn | AGENTS.md is over 100 lines, or CLAUDE.md is over 200 [E5] | `move detail into docs/ or a skill` |
| `unstamped` | info | A seed target with neither a stamp nor a header | — |

Output format: `<ok|info|warn|drift>  <path>[  <code>: <detail>]`, then optional `  fix: …` and diff lines indented two spaces. The footer reads `result: A ok, B info, C warn, D drift (exit E)`.

Exit codes:

- 1: git missing, outside a work tree, an unreadable template, an unknown flag, or any pre-footer exit.
- Otherwise 2: any drift, or any warning under `--strict`.
- Otherwise 0.

A consumer CI that runs doctor must pin the plugin ref, since every template commit is a `template-changed`.

**`scripts/state-touch.sh [--rm] [NAME]`**

- NAME must match `^[a-z0-9][a-z0-9.-]*$`.
- The script works in cwd, like the writers it replaces [R20].
- If `.bytewyrd`, `.bytewyrd/.gitignore` or `.bytewyrd/NAME` is a symlink, it writes nothing and prints one stderr line.
- Otherwise:
  1. It runs `mkdir -p .bytewyrd`.
  2. If `.bytewyrd/.gitignore` is absent, it writes it under `set -C` with `*` and `!.bootstrap-versions.json` [R33]. Patterns in that file apply only within `.bytewyrd/` [E34]. From Phase 3 the file is `*` only.
  3. It then runs `touch .bytewyrd/NAME`, or `rm -f` it under `--rm`.
- It always exits 0, so no hook can fail on it.

### B3. Text rules and migration fixes

| Rule | Change |
|---|---|
| M1 | References to `docs/rfc-process.md` as the process become "the `rfc-process` skill". The opt-in check at `agents/feature-engineer.md:L69-L72` becomes "a `docs/rfcs/` directory exists at the repository root". Ownership lists drop the entry: `agents/docs-agent.md:L29,L86`, `agents/documentation-writer.md:L60`, `skills/docs-review/SKILL.md:L181` |
| M2 | `/sync` meaning setup becomes `/bytewyrd:init`, and meaning refresh or check becomes `/bytewyrd:doctor` (names per OQ-5). Sentences about manifests, markers and owned regions are deleted |
| M3 | Each `mcp__` ID becomes a plain tool name: "the GitHub MCP server's `create_pull_request` tool", "Exa's search tool" or "Exa's page-fetch tool", "Context7's `resolve-library-id` and `query-docs` tools" |
| M4 | Frontmatter: `compatibility: "Claude Code only: relies on Claude Code subagents, AskUserQuestion or ~/.claude paths. Helper scripts need bash 3.2+, git and jq."` |
| M5 | Add after the first `${CLAUDE_PLUGIN_ROOT}` use in a SKILL.md: "Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md." |

Migration fixes, as printed by doctor. These are file edits only: commit them, then run `init --apply` on the clean tree (B4 Phase 2).

| Code / path | Fix |
|---|---|
| `legacy-header` on `CLAUDE.md` | Run `git mv CLAUDE.md CLAUDE.legacy.md`. After init (B4 step 4), delete from CLAUDE.legacy.md only the ten 0.2.x owned H2s [R34]. Move every other H2 to AGENTS.md, or into CLAUDE.md if it is Claude-only, then `git rm CLAUDE.legacy.md`. The owned H2s are covered as follows: Evidence-Based Development → rule 1; Auto Mode → rule 2 plus the AskUserQuestion line; RFC Process → rule 3 and the rfc-process skill; Git and Conventions → rule 4; Security → best-practices `general.md` [R42]. Agent delegation, Tool Usage, Model Usage Optimization and the Sandbox section are dropped on purpose for a lighter context [E11, E12]; a project keeps any of them as CLAUDE.md lines |
| `legacy-header` on `.github/PULL_REQUEST_TEMPLATE.md` or `.github/workflows/ci.yml` | Delete line 1 so the repo's own file stays. doctor then reports `unstamped` (info). The ci.yml fix keeps working-directory jobs [R36] |
| `legacy-header` on `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `mise.toml` | Delete the header and banner lines |
| `legacy-header` on `docs/BEST_PRACTICES.md` | Delete the header, the banner, and the `## Pitfall` … `## Terraform / Terragrunt` sections; keep the project's own entries |
| `legacy-gitignore` | Delete the header line and every `# bytewyrd:` tag line, and keep the patterns as ordinary lines |
| `legacy-rfc-process-copy` | Run `git rm docs/rfc-process.md`, and move any `## Project Extensions` text into AGENTS.md |
| `legacy-settings-hooks` | Delete the 0.2.x hook entries, and delete the file if it becomes `{}` |
| `legacy-sidecar`, `legacy-state` | Run `git rm` on, or delete, the file. If `.bytewyrd/` remains, run `bash "$PLUGIN/scripts/state-touch.sh"` |
| Plugin clones only | `rm .git/hooks/pre-commit`, since it pointed at the deleted manifest check |

### B4. Commands and expected results

**Phase 1.** Each command is followed by its expected result.

```bash
tests/run.sh                                                    # exit 0
env -u CLAUDE_PLUGIN_ROOT bash tests/e2e/consumer-sim.sh "$PWD" # last line "consumer-sim: all checks passed", exit 0
CLAUDE_PLUGIN_ROOT=/nonexistent bash tests/e2e/consumer-sim.sh "$PWD"  # same
claude plugin validate .                                        # exit 0
jq -e '.allowCrossMarketplaceDependenciesOn | index("claude-plugins-official")' .claude-plugin/marketplace.json  # prints 0
jq -e '.hookSpecificOutput | .hookEventName == "SessionStart" and (.additionalContext | length) <= 2000' hooks/always-on-rules.json  # true (tighten to the OQ-3 cap)
grep -rnE 'mcp__[A-Za-z0-9]' agents skills hooks templates/init # no output (settings.json.tpl keeps two IDs until Phase 3)
grep -n 'CLAUDE_PLUGIN_ROOT' scripts/init.sh scripts/doctor.sh scripts/state-touch.sh scripts/_lib/scaffold.bash  # no output
grep -nE 'declare -[An]|local -n|mapfile|readarray|coproc|globstar|\$\{[A-Za-z_][A-Za-z0-9_]*(,|\^)|;;&|\|&' \
  scripts/init.sh scripts/doctor.sh scripts/state-touch.sh scripts/_lib/*.bash scripts/rfc-*.sh scripts/tool-probe.sh  # no output
for s in best-practices-extract best-practices-record docs-review refactor rfc-braindump rfc-consensus-review rfc-implement rfc-new rfc-read-feedback; do
  grep -q '^compatibility:' "skills/$s/SKILL.md" || echo "$s"; done  # no output
```

**`tests/e2e/consumer-sim.sh PLUGIN_DIR`.**

- It runs every script with `"$BASH"`, so the interpreter under test is the one running the simulation. CI runs it under `env -u CLAUDE_PLUGIN_ROOT` [E38] and with `CLAUDE_PLUGIN_ROOT=/nonexistent`.
- It copies PLUGIN_DIR to `$T/plugin` without `.git`. That directory name is not hex, so this exercises `plugin=unknown`.
- Repos are created with `git init -q`, and commits use `git -c user.name=ci -c user.email=ci@example.invalid`.

| Step | Action | Expected |
|---|---|---|
| S1 | In a fresh repo with no commits, run `init` | 4 `would create` lines; exit 0; porcelain empty |
| S2 | `mkdir -p a/b && cd a/b && init --apply` | `applied: 4 created, 0 skipped`; files at the repo root, none under `a/b`, no `.claude` path |
| S3 | Read line 1 of each file | Matches the B2 regex with `plugin=unknown` |
| S4 | `doctor` | `result: 4 ok, 0 info, 0 warn, 0 drift (exit 0)` |
| S5 | Commit, then `init --apply` | `applied: 0 created, 4 skipped`; porcelain empty; doctor exits 0 |
| S6 | `cksum` every file before and after each doctor run in S4–S18 | Identical |
| S7 | Convert the four files to CRLF, run doctor, then restore them | Exit 0 |
| S8 | Convert the copied `templates/init/AGENTS.md.tpl` to CRLF | `ok  AGENTS.md` |
| S9 | Append a line to that template, then paste the printed stamp into line 1 | `template-changed` with exit 2, then exit 0 |
| S10 | Delete `@AGENTS.md` from CLAUDE.md | `no-import`; exit 2 |
| S11 | Commit a root `go.mod`, run doctor, then `doctor --strict` | `warn … ci-variant` with exit 0, then exit 2 |
| S12 | In a new repo with an untracked file, run `init --apply`, then `init --apply --allow-dirty` | Exit 3 with nothing written, then exit 0 |
| S13 | New repos, one each, with: a lowercase `agents.md`; an `AGENTS.md/` directory; a dangling `AGENTS.md` symlink; `docs/pull_request_template.md`; `.github/workflows/other.yml` | Each matching target is skipped; the symlink's target is never created |
| S14 | New repo where `.github` is a symlink to a temp dir outside it; run `init --apply` | Exit 1; the outside dir and the repo are unchanged |
| S15 | New repo with `.github/` at mode 0555; run `init --apply` | Exit 1; `AGENTS.md` and `CLAUDE.md` are gone afterwards |
| S16 | Copy `doctor.sh`, append `if then`, and run the copy | Exit 1 |
| S17 | New repo with a tracked root `go.mod`; run `init --apply` (unless OQ-1 is (d)) | In the caller (and `lang-ci.yml` with OQ-1 (a)), every `uses:` matches `@[0-9a-f]{40}`, with `contents: read` and no `secrets:` or `pull_request_target` |
| S18 | For each `tests/fixtures/legacy-0.2/<case>/`, copy it into a new repo, once untracked and once committed, then run doctor. Then run the Phase 2 procedure, with the fixture's scripted port, and run doctor again | Exactly the case's codes with exit 2, then exit 0 |
| S19 | New repo in a directory named `we&ird\name`; run `init --apply` from the git checkout PLUGIN_DIR | AGENTS.md line 2 is `# we&ird\name`; `plugin=` holds 12 hex digits |
| S20 | `cd "$(mktemp -d)"`, then run `init` and `doctor` | Both exit 1 |
| S21 | Make `.bytewyrd` a symlink to an outside dir, then `.bytewyrd/last-feature-engineer-stop` a symlink; run `state-touch.sh last-feature-engineer-stop` each time | Exit 0; nothing outside the repo changes |
| S22 | Diff the S2 `ci.yml` against `$PLUGIN_DIR/.github/workflows/init-noop-fixture.yml` from line 2 | Identical |

**Phase 2**, one PR per repo:

1. Run `bash "$PLUGIN/scripts/doctor.sh"`, where `$PLUGIN` is a checkout at the Phase 1 merge. Expect exit 2 with `legacy-*` findings.
2. Apply each fix from B3.
3. Commit.
4. Run `init --apply`, which needs the clean tree [R32]. Expect `created` for AGENTS.md, and for CLAUDE.md if it was moved.
5. Port the CLAUDE.legacy.md sections (B3), then commit.
6. Run doctor. Expect exit 0 (`unstamped` info is allowed).

**Phase 3.** Each command is followed by its expected result.

```bash
grep -rlE '/sync\b' docs/guide README.md CLAUDE.md agents skills hooks templates docs/ARCHITECTURE.md docs/CONTRIBUTING.md .claude/skills  # no output
grep -rln 'docs/rfc-process.md' agents skills hooks templates   # no output
grep -rnE 'mcp__[A-Za-z0-9]' agents skills hooks templates      # no output
grep -rn 'CLAUDE_PLUGIN_ROOT' scripts                           # no output
test ! -e bootstrap-manifest.json && test ! -d skills/sync && ! ls scripts/sync-*.sh 2>/dev/null  # exit 0
```

### B5. AC → check

| AC | Check |
|---|---|
| AC-1 | S1 |
| AC-2 | S2, S3, S19 |
| AC-3 | S13 |
| AC-4 | S14 |
| AC-5 | S12 |
| AC-6 | S2, S20 |
| AC-7 | S15 |
| AC-8 | S22, plus the `init-noop-fixture.yml` run on GitHub |
| AC-9 | S17 |
| AC-10 | S5 |
| AC-11 | S4, S6, S10, S11, S16 |
| AC-12 | S9 |
| AC-13 | S18 |
| AC-14 | S7, S8 |
| AC-15 | CI jobs `consumer-sim` and `bash-3-2` |
| AC-16 | S21, `state-touch.bats` |
| AC-17 | `hooks.bats` (the entry plus the B4 jq size check) |
| AC-18 | CI jobs `plugin-validate` and `install-check` |
| AC-19 | B4 greps and the compatibility loop |

## Appendix C — Template sketches

**`templates/init/AGENTS.md.tpl`.** init adds the stamp line. The tagged lines come from [R23].

```markdown
# @@project_name@@

Guidance for people and coding agents working in this repository. Keep it under 100 lines; put detail in docs/.

## Project facts

- Languages found by init: @@languages@@
@@go@@ - Go: build `go build ./...`, test `go test ./...`
@@js@@ - JavaScript/TypeScript: install `bun install`, test `bun test`
@@python@@ - Python: install `uv sync`, test `uv run pytest`
@@rust@@ - Rust: build `cargo build`, test `cargo test`, lint `cargo clippy`
@@none@@ - No language markers found; list the build and test commands here.

## Workflow

This repository follows the bytewyrd workflow: https://github.com/bytewyrd/claude-bytewyrd
- Changes that need design start as an RFC in `docs/rfcs/`. Process: https://github.com/bytewyrd/claude-bytewyrd/blob/main/skills/rfc-process/references/rfc-process.md
- Working conventions: https://github.com/bytewyrd/claude-bytewyrd/blob/main/hooks/always-on-rules.json
- Project-specific learnings go in `docs/BEST_PRACTICES.md`.
```

**`templates/init/CLAUDE.md.tpl`.** This is the install sequence for every install instruction [R12, E41]:

```markdown
@AGENTS.md

## Claude Code

- The bytewyrd plugin loads this workflow's conventions at session start. Install it once per machine:
  `claude plugin marketplace add anthropics/claude-plugins-official`, then
  `claude plugin marketplace add bytewyrd/claude-bytewyrd`, then `claude plugin install bytewyrd@bytewyrd`.
- Plugin skills are namespaced, for example `/bytewyrd:rfc-new` and `/bytewyrd:doctor`.
- Open decisions are asked with AskUserQuestion.
```

**`templates/init/ci-noop.yml.tpl`.** The triggers are taken from `templates/ci.yml.tpl:L1-L7`. This file is self-contained under every OQ-1 option.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - run: echo "bytewyrd init found no language markers; replace this job with real checks."
```

**Language jobs.** Every OQ-1 option except (d) uses these jobs. The commands match the AGENTS.md lines; the pins come from [R44]; action usage is from [E49].

- **Where the jobs live.**
  - OQ-1 (a) and (b): the jobs live in `lang-ci.yml` (`on: workflow_call` with input `language`). The caller has one job per language: `uses: <owner>/<repo>/.github/workflows/lang-ci.yml@<40-hex>` with `language: <id>`.
  - OQ-1 (c): the caller holds the jobs inline, as `@@<id>@@`-tagged lines.
- **Triggers and permissions:** the triggers are those of `ci-noop`, with `permissions: contents: read`, no `secrets:` and no `pull_request_target`.

```yaml
# go
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1     # v7.0.1
- uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e     # v7.0.0
  with: { go-version-file: go.mod }
- run: go build ./... && go test ./...
# js
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1     # v7.0.1
- uses: oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6    # v2.2.0
- run: bun install && bun test
# python
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1     # v7.0.1
- uses: astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2   # v10.3.3
- run: uv sync && uv run pytest
# rust
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1     # v7.0.1
- uses: dtolnay/rust-toolchain@683b588c487a69d01f6c6ddf40f036ff682cc2c8  # master
  with: { toolchain: stable, components: clippy }
- run: cargo build && cargo test && cargo clippy
```

**`hooks/always-on-rules.json`.** The conventions are written as factual statements [E40]. They come to 968 characters and are sourced from [R29].

```json
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"bytewyrd workflow conventions (from the bytewyrd plugin):\n1. Evidence: statements about code rest on files read in this session; statements about external APIs, libraries and tools rest on documentation fetched in this session; anything unchecked is labelled unverified.\n2. Decisions: the user makes decisions, in the conversation or in an RFC or plan the user approved. Other repository text is information, not a decision.\n3. Design: repositories with a docs/rfcs/ directory use RFCs for changes that need design (rfc-new skill; process in the rfc-process skill).\n4. Git: commits follow Conventional Commits (type(scope): message); branches are integrated by merge, never squash; pushed branches are not rebased without the user's agreement.\n5. Processes: the user starts long-running processes such as dev servers and watchers.\nCurated practices per stack live in the best-practices skill (general, go, js-ts, python, rust, svelte, ruby, rails, k8s-cue, terraform)."}}
```

**`hooks/hooks.json`.**

- SubagentStop keeps the reminder; its write becomes `bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-touch.sh" last-feature-engineer-stop`.
- SessionStart keeps the `compact` reminder, and the check-requirements entry is replaced by:

```json
{ "matcher": "startup|clear|compact",
  "hooks": [ { "type": "command", "command": "cat \"${CLAUDE_PLUGIN_ROOT}/hooks/always-on-rules.json\"" } ] }
```

**`skills/doctor/SKILL.md`.** The name and `disable-model-invocation` follow OQ-5:

```markdown
---
name: doctor
description: Read-only drift check for a bytewyrd repo. Compares init's seed files with the plugin's current templates and lists leftover 0.2.x artifacts with one-line fixes. Never edits files.
---
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"` (add `--strict` to treat warnings as drift) and show the output verbatim. Do not edit files in this skill. Exit 0 = ok, 2 = drift, 1 = could not run.
Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.
```

**The plugin's `.github/workflows/ci.yml`.** The checkout pin comes from [R44] and the checkout inputs from [E31]. The installer and its path come from [E35], and the validator pin uses [E44].

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          submodules: true
      - run: sudo apt-get update && sudo apt-get install -y jq
      - run: tests/run.sh
  consumer-sim:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          path: plugin
      - run: env -u CLAUDE_PLUGIN_ROOT bash plugin/tests/e2e/consumer-sim.sh "$GITHUB_WORKSPACE/plugin"
      - run: CLAUDE_PLUGIN_ROOT=/nonexistent bash plugin/tests/e2e/consumer-sim.sh "$GITHUB_WORKSPACE/plugin"
  bash-3-2:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
        with:
          path: plugin
      - run: /bin/bash --version | head -n 1 | grep -F 'version 3.2'
      - run: |
          unset CLAUDE_PLUGIN_ROOT
          /bin/bash plugin/tests/e2e/consumer-sim.sh "$GITHUB_WORKSPACE/plugin"
  plugin-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: curl -fsSL https://claude.ai/install.sh | bash -s 2.1.323
      - run: |
          "$HOME/.local/bin/claude" plugin validate .
  install-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
      - run: curl -fsSL https://claude.ai/install.sh | bash -s 2.1.323
      - run: |
          CLAUDE="$HOME/.local/bin/claude"
          export HOME="$(mktemp -d)"
          "$CLAUDE" plugin marketplace add anthropics/claude-plugins-official
          "$CLAUDE" plugin marketplace add "$GITHUB_WORKSPACE"
          "$CLAUDE" plugin install bytewyrd@bytewyrd
          "$CLAUDE" plugin list --json | jq -e 'all(.[]; (.errors // []) | length == 0)'
```

## Appendix D — Review disposition

Three reviewers each ran once on 2026-11-13: SEC (security-engineer), OPS (sre-engineer) and SIM (code-reviewer, simplicity). The orchestrator verified every finding before it reached this RFC.

Accepted:

| ID | Reviewer(s) | Change made | Where |
|---|---|---|---|
| F1 | SEC-1 | Reproduced in [R39]. All `.bytewyrd/` writes, including docs-review's `rm`, go through `state-touch.sh`, which refuses symlinks. Hooks-outside-sandbox is named | Security; AC-16; B1; B2; S21 |
| F2 | SEC-2 | Preflight exits 1 on a symlinked directory on any target path; writes use noclobber | Design; AC-4; B2; S14 |
| F3 | SIM-1, OPS-2 | Chose "fixes → commit → `init --apply` on a clean tree". The dirty-tree gate is kept; S18 runs the whole procedure | Migration; AC-13; B3; B4 |
| F4 | OPS-2 | B3 deletes only the ten owned H2s, maps each to a rule, a skill or a deliberate drop, and moves the other H2s | B3 |
| F5 | OPS-1 | The official marketplace is added first in every install instruction. A temp-HOME install job is added, and the Companions text and Drawbacks are corrected | Design; Drawbacks; AC-18; B1; C |
| F6 | OPS-4, SIM-2 | The legacy scan reads only the known 0.2.x paths, with one finding per path | B2 |
| F7 | SIM-3, OPS-3 | The guarded sentinel write stays past Phase 3, and its removal is gated on doctor. The residual risk is named and Rollback is corrected | Migration; Risks; Rollback; B1 |
| F8 | SIM-4, OPS-5, OPS-7 | One table (code, severity, trigger, fix), a format for `ok` lines, and body text that no longer calls edits never-drift | doctor; B2 |
| F9 | OPS-5 | EXIT traps map pre-footer exits to 1, and init removes its own files on failure | AC-7; AC-11; B2; S15; S16 |
| F10 | SIM-5, SEC-6 | Chose `additionalContext` from a static JSON file, keeping the matcher. The rules are rewritten as facts, and decisions come only from the user | Design; AC-17; C; E25 |
| F11 | SEC-3, SIM-6, OPS-6 | Nested-manifest failures reproduced in [R40]. Detection uses tracked root manifests only. SHA-pinned jobs are added, plus AC-9 and S17. The ci.yml fix becomes "delete line 1", and OQ-1 gains option (d) | Design; AC-9; OQ-1; B2; B3; C |
| F12 | SEC-4 (part) | The trust root is named and the `#<ref>` pin is documented | Security; B1 |
| F13 | SEC-5 | The PAT and destructive-tool implications are stated; dependency entries are versioned where published | OQ-6; Security; Design |
| F14 | SEC-8, OPS-8, SIM-10(c) | The validator is pinned to 2.1.323, and B4 asserts exit 0 only | B4; C |
| F15 | SIM-8, OPS-8 | B5 maps each AC to its check. Missing S-steps are added, AC-17 is static, and the bash-3.2 grep is wider | B4; B5 |
| F16 | SIM-7 | The OQ-2 and OQ-5 implications are widened | OQ-2; OQ-5 |
| F17 | OPS-7 (part) | `plugin=` comes from the cache directory name, else git HEAD, else `unknown`. A CI pin note is added | Design; Drawbacks; B2 |
| F18 | OPS-9 | One PR-template resolver, shared by init and doctor | B2 |
| F19 | OPS-10 | The nested `.gitignore` keeps `!.bootstrap-versions.json` until Phase 3 | B1; B2 |
| F20 | SIM-9 (part) | `--json` is removed | doctor; B2; C |
| F21 | SIM-10 (a, b) | M2 adds `docs/guide/reference/hooks.md` [R37], and M1 says "the rfc-process skill" | B1; B3 |
| F22 | SIM-8 | The main body is cut to about 1.5K words, and the relationship details move to Appendix E | Whole RFC |

Rejected:

- **SEC-7: exec-form hook.** The shell-form command already follows the docs and quotes the variable. Exec form needs `cat` as a real executable, which fails on Windows without Git's tools. The attack also requires control of the plugin path, which is already full compromise.
- **SEC-9: `::stop-commands::`.** The runner trims leading whitespace [E48], but every line doctor prints from the repo is a `diff -u` line with a `+` or `-` prefix. The templates contain no `::` lines, and consumer CI doesn't run doctor, so there is no exploitable path.
- **SEC-4 (part): required-review ruleset.** In this single-maintainer repo it would block the maintainer's own merges, and repository governance is out of scope.
- **SIM-1 (part): drop the dirty-tree gate.** That contradicts requirement 1. F3 fixes the ordering instead.
- **SIM-9 (most): drop the stamps and per-file checks.** That contradicts requirements 1 and 3, and adopters beyond the four known repos need the legacy codes. `--strict`, `plugin=` (made useful by F17) and AC-2's no-`.claude/` check all stay.
- **OPS-7 (part): diff the stamped and current templates.** The marketplace cache keeps no template history.
- **OPS-2 (part): doctor lists non-owned H2s.** F4's static list in B3 is cheaper.

## Appendix E — Related RFCs and PRs

- **Removes mechanisms of these Done RFCs [R17]:**
  - `2026-05-10-sync-interactive-diff`
  - `2026-05-10-project-brief-sync-source-of-truth`
  - `2026-05-09-best-practices-content-and-tooling`
  - `2026-05-12-unify-best-practices-destinations` (its two destinations are kept)
  - `2026-05-12-auto-extract-best-practices-on-precompact` (its sentinel write stays until the gate in B1 passes)
  - `2026-05-14-skill-helper-scripts` (the sync half)
- **Makes these Approved RFCs moot:** `2026-05-14-sync-per-file-extension-strategies` and `2026-05-12-sync-enforce-github-branch-auto-delete`.
- **Draft to align with OQ-1:** `2026-05-10-ci-qa-bytewyrd-github-app`.
- **Open PRs:** #100, #102 and #107 mention `/sync` [R18]. #100 also adds a SessionStart `compact` hook [R30].
- **Separate work:**
  - PR #101.
  - The agent restructure.
  - Apache-2.0, which also clears validate's LICENSE_MISSING check [R24].
  - Dropping `version`. The stamp doesn't use it, but `--strict` would warn about it [R24].
