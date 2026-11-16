---
rfc: "2026-11-09-scaffold-and-drift"
title: "Replace /sync with scaffold + drift"
author: "Rodrigo Kochenburger"
status: "Done"
created: "2026-11-09"
drop_reason: ~
implemented_by: ["https://github.com/bytewyrd/claude-bytewyrd/pull/115", "https://github.com/bytewyrd/claude-bytewyrd/pull/117"]
---

# Replace /sync with scaffold + drift

Tags `[R#]`/`[E#]` cite Appendix A; Appendix D records the reviews, and Appendix F the user's decisions.

## Summary

`/sync`, about 6K lines, merges plugin content into consumer files on every run [R6]. Instead, **scaffold** seeds at most four small, stamped files once; **drift** checks them read-only, with CI exit codes; and the RFC process, best-practices library and five always-on rules stay in the plugin. Scripts and hooks move to Python ≥ 3.11.

## Should we do this?

Yes. On main, `/sync` still crashes on fresh repos [R1], writes relative to its subdirectory [R3], deletes user lines in "owned" regions [R19b], writes before consent [R19c], LLM-merges CLAUDE.md unchecked [R19d] and commits hooks into consumer repos [R4]. #113 fixed a seventh defect, the empty rendered CI [R5].

Evidence favours a small always-on context [E5, E11, E12], and skills alone often go uninvoked [E13], so a seeded pointer stays.

## Current state

- Scripts need bash 4 or later [R2], but macOS ships 3.2 [E16].
- 11 skills rely on `${CLAUDE_PLUGIN_ROOT}`, unset in the Bash tool [R14, E7]. None declares `compatibility:`, and ten `mcp__` IDs ship [R14]; B3 fixes all three.
- Each repo keeps its own copy of `docs/rfc-process.md` [R16].

## Options

Rejected:

- **Fix `/sync`.** Merging into user files is the fault itself [R6].
- **Guarded copies** [E17, E20] drift [E22].
- **Tool-rewritten marker blocks** [E15] still write user files; OpenSpec dropped them [E19].
- **Pure by-reference.** A plugin can't ship CLAUDE.md context [E1], skills go uninvoked [E13], and checkout-only users get nothing [E18].

Chosen: seed once [E21], reference at runtime [E22b], and check.

## Language policy

Decided by the user on 2026-11-13; reverses dee771e [R46].

- **Rules:** Python ≥ 3.11 with the standard library and a vendored pure-Python PyYAML 6.0.3 [E54]. Nothing installs at runtime: Claude Code installs only npm and Bun packages, into cached copies [E50]. Only contributors and CI use uv and `uv.lock` (D8). bats stays the black-box CLI contract suite and port-parity harness; pytest covers Python internals.
- **Why:** `/sync` already requires python3 ≥ 3.11 for `tomllib` [R47, E51], while the bash scripts need bash 4, jq and GNU/BSD workarounds [R2, R48].
- **Cost:** the default python3 is too old on macOS [E52], Ubuntu 22.04 and RHEL 9; Ubuntu 24.04+ and Debian 12+ pass [E53]. The launcher also tries `$BYTEWYRD_PYTHON` and `python3.15`…`python3.11` (B2).
- **Failure:** with no Python 3.11+, commands exit 1 (JSON helpers 2) and hooks exit 0 (B2).

## Design

### scaffold

A Python script does all seeding; `/bytewyrd:scaffold` only runs it. **Seeds**, each only if absent:

- `AGENTS.md`: at most 100 lines of tool-neutral facts plus a workflow pointer.
- `CLAUDE.md`: `@AGENTS.md` plus Claude-only lines. Without the import, Claude ignores AGENTS.md [E4].
- `.github/PULL_REQUEST_TEMPLATE.md`, unless GitHub finds a template [E47].
- `ci.yml`, unless a workflow exists: a no-op job [E30], or a caller of this repo's per-language `lang-ci-<id>.yml` workflows, pinned to one commit SHA [E29], with a job per tracked (language, directory) that detection keeps (B2).

**Safety:** dry run unless `--apply`; never overwrites or follows symlinks; a symlinked parent directory exits 1. A dirty tree [E33] exits 3 unless `--allow-dirty`. Writes go to the top level [E32], never `.claude/`.

**Stamp:** line 1 is `bytewyrd:scaffold v1 tpl=<template>:<sha12> plugin=<sha12|unknown>`. The hash covers the CR-stripped template, so edits never move it [R19a]; `plugin=` is the installed commit [E42].

### By-reference content

- **Docs:** `skills/rfc-process/references/` and `skills/best-practices/references/<stack>.md` replace the copies; `docs/rfcs/` opts a repo in to RFCs.
- **Always-on rules:** five factual statements [E40] in `hooks/always-on-rules.json`, emitted as SessionStart `additionalContext` on `startup|clear|compact` [E14] and kept across `resume` and `fork` [E25]. CI caps them at 2,000 characters [E3] (≈ 740 tokens [E26]), and they change by reviewed PR.
- **Companions:** github, context7 and code-review from `claude-plugins-official` are hard `dependencies`, with `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]`. Install instructions add the official marketplace first, since `claude plugin` never registers it [E41].

### drift

Deterministic, read-only and LLM-free. Exits: 0 clean, 2 drift, 1 cannot run (crashes included); `--strict` counts warnings. Drift: `template-changed` (prints a diff and the new stamp), `pin-changed` (a caller `uses:` other than the template's pinned call [E63]), `bad-stamp`, `no-import`, and one `legacy-*` per known 0.2.x path (B2).

## Drawbacks

- Contributors, CI and cloud agents without the plugin lose the process and library [E18]. AGENTS.md links both.
- A missing or disabled dependency silently unloads bytewyrd, rules and drift with it [R31, E41], and none can be disabled while bytewyrd is enabled [E61].
- Template changes need human edits; consumer CI running drift must pin the plugin ref.

## Migration

Two PRs, then the apps (Appendix F):

1. **#115, merged first:** one reusable workflow per language, `lang-ci-<id>.yml`, with the multi-language changes (B1), their fixture jobs, the lint-tool pins and actionlint, and this amendment.
2. **Implementation PR**, whose commits run in this order, bats passing at each:
   - **add:** scaffold, drift, hooks (SubagentStop returns), both skills, dependencies and CI; the caller pins #115's merge commit, and `check-requirements.sh` goes.
   - **migrate:** this repo, by the B4 procedure.
   - **delete:** `/sync`, its scripts, manifest, templates and tests, and dead helpers [R58].
   - **port:** the remaining bash becomes Python under the same names, one commit each, tests unchanged [R51].
3. **Apps:** each of the three known installs then migrates in its own PR. Until then they keep working, because their hooks are self-contained shell [R63].

The RFC is Done when the implementation PR merges; #118 tracks the Apps and B1's `Later` row [R97].

## Acceptance criteria

Each is automated; B5 maps it to its check.

- **AC-1** `scaffold` exits 0 and writes nothing.
- **AC-2** `--apply` in a fresh repo, commits or none, creates exactly the missing targets, stamped, and nothing under `.claude/`.
- **AC-3** Existing targets are skipped, never followed: files, case variants, directories, dangling symlinks, recognised PR templates, any workflow.
- **AC-4** A symlinked directory on a target path exits 1, writing nothing.
- **AC-5** On a dirty tree, `--apply` exits 3 unless `--allow-dirty`.
- **AC-6** Subdirectory runs write at the top level; outside a work tree, both exit 1.
- **AC-7** A mid-apply failure exits 1 and leaves none of its files.
- **AC-8** With no languages, AGENTS.md has no Project facts section, and `ci.yml`, from line 2, names neither scaffold nor detection and equals `scaffold-noop-fixture.yml`, which passes on GitHub.
- **AC-9** The caller and every `lang-ci-<id>.yml` pin every `uses:` by SHA, set `persist-credentials: false`, request only `contents: read`, and use no `secrets:` or `pull_request_target`.
- **AC-10** Apply, commit, apply → `0 created`, a clean tree, drift exit 0.
- **AC-11** drift leaves fixtures unchanged and exits 0, 2 or 1 as specified (1 on crashes). `--strict` makes warnings exit 2.
- **AC-12** A template edit → `template-changed`, and a caller `uses:` other than the template's pinned call → `pin-changed`, both exit 2; the printed stamp restores 0.
- **AC-13** Legacy fixtures yield exactly their `legacy-*` findings. After its migration, a repo's drift exits 0.
- **AC-14** CRLF files pass, and CRLF and LF templates hash the same.
- **AC-15** consumer-sim passes with `CLAUDE_PLUGIN_ROOT` unset or `/nonexistent`, on Python 3.11 and latest 3.x, Linux and macOS.
- **AC-16** `.bytewyrd/` writes never follow symlinks, even if the directory is swapped mid-run.
- **AC-17** The `startup|clear|compact` hook emits `always-on-rules.json` within 2,000 characters. No hook calls `check-requirements`.
- **AC-18** `claude plugin validate .` exits 0 [E9], and a temp-HOME install and update show no load errors.
- **AC-19** `agents/`, `skills/`, `hooks/` and `templates/` contain no `mcp__` IDs, `docs/rfc-process.md` or `/sync`. Claude-only skills declare `compatibility:`.
- **AC-20** Without Python 3.11+, commands meet B2's exit contract, hooks exit 0 and the PreCompact sentinel is still written; with it, a venv's `.pth` never runs and no `__pycache__/` appears.
- **AC-21** Vendored PyYAML matches the sdist that `uv.lock` pins, imports with `__with_libyaml__` false, and parses only via B2's hardened loader, whose conversions fixtures pin.
- **AC-22** No port commit changes `tests/scripts/`, and bats passes at every commit of the implementation PR.
- **AC-23** Detection yields a caller job per tracked (language, directory) that B2 keeps and none for root-workspace members; each skipped or opted-out manifest gets a note instead, and unsafe manifests declare no workspace.
- **AC-24** Each language id has a `lang-ci-<id>.yml` whose one job passes on its fixture.
- **AC-25** scaffold and drift print no byte below 0x20 but newlines, and each printed `.gitattributes` line opts out exactly its manifest.
- **AC-26** Every workflow passes actionlint with shellcheck, and CI's shellcheck, shfmt and actionlint versions equal the `mise.toml` pins.

## Test plan

CI extends main's `lint`, `validate` and `test` jobs [R49], and a `lang-ci-fixture-<id>` job runs each `lang-ci-<id>.yml` on its fixture; B4 lists the commands.

## Rollback

Revert only the implementation PR, with `git revert -m 1 <sha>`. #115 stays: the `lang-ci-<id>.yml` files, like `lang-ci.yml` [R86], run only when called, callers pin them, and reverting #115 would revert this amendment too; a defect in one is fixed forward (fix, merge, bump the pin). Consumers get the revert on their next update [E42], and scaffolded AGENTS.md links to `skills/rfc-process/…` and `hooks/always-on-rules.json` then return 404. Re-landing takes `git revert <revert-sha>`, since a re-merge brings nothing back [E84].

## Security considerations

- **Trust root:** this repo's `main`. With no `version`, every commit reaches consumers on their next update [E42]. Teams can pin `bytewyrd/claude-bytewyrd#<ref>` [E43].
- **Writes:** scaffold writes four fixed paths, offline, never through symlinks; no tool writes consumer hooks. Hooks run outside the sandbox [E39], so `.bytewyrd/` writers use a no-follow directory descriptor [R60]. Substitution is literal. YAML gets only allowlisted language ids, job ids built from them [E70], and double-quoted directories that pass B2's check; directories that fail it are reported, quoted, never written. Every printed repo string is C-quoted when unusual [R79, E88].
- **Context:** the rules hook reads nothing from the repo, and rule 2 treats repo text as information. AGENTS.md, which CLAUDE.md imports, lists up to ten checked directory names.
- **Supply chain:** the allowlist trusts `claude-plugins-official` [E2]. The github dependency leads adopters to a PAT that every shell command inherits [E46, E39], and its server exposes tools such as `delete_repository` [R41]. PyYAML is pinned and checked through `uv.lock`'s sdist hash [R93], and parsed only through an alias-rejecting, size-capped loader [R55]; development tools reach only CI and contributors. Every `uses:` is SHA-pinned, inside reusable workflows too [R43]; run-time downloads are residual risk: unchecked Ruby builds, the Bundler `BUNDLED WITH` names, and Bun, the latest for subdirectory JS [E96, E98, E75].

## Decisions and risks

The user's decisions of 2026-11-13 to 2026-11-15 are in Appendix F.

Risks:

- **Uninvoked skills** [E13]: the rules and AGENTS.md name them.
- **Unknown repos on the 0.2.x PreCompact hook** [R35]: the sentinel write stays, with a plain-sh fallback, and the hook's message documents a bypass.
- **Unresolved dependencies after an update** [R57]: install docs give explicit dependency installs, and CI's update case re-adds the marketplace at the PR branch to test the move from a pre-PR install. If that can't work in CI, the gap stays open (Appendix C).
- **Root discovery is wider than membership:** root `bun test` and `pytest` also run non-member packages' tests [R66, E78, E81] (B2).

## Relationship to other RFCs

Appendix E lists them, including #113 and #116, which this RFC builds on [R49, R77].

## Appendix A — Evidence Audit

Status values:

- **Verified (pack):** confirmed by the orchestrator's brief pack on 2026-11-13.
- **Verified (ledger):** confirmed by the orchestrator while checking review findings on 2026-11-13.
- **Verified (session):** re-checked while drafting on 2026-11-13, or, for rows dated 2026-11-14 or 2026-11-15, on that day.
- **Verified (orchestrator):** run by the orchestrator on 2026-11-14 and not re-run while drafting.
- **Reproduced (reviewer):** reproduced by a lens reviewer in the re-review or the amendment review, and not re-run while drafting.

Repo `path:Lnnn` citations are against origin/main at d9ae47e, which includes PRs #113 and #116 [R49, R77], and were re-checked there on 2026-11-13. A citation of a line that #116 removed names the commit it was read at, as in `0745d32:hooks/hooks.json:L13`; rows that cite #115's head name 4d9d384, and rows dated 2026-11-15 cite #117's branch at dd91cf6.

Repo facts and local reproductions:

| ID | Claim as used | Source | Date | Status |
|---|---|---|---|---|
| R1 | A fresh repo crashes: the jq filter `(.brief_name \| if . == "" then .preflight.project_slug else . end)` indexes a string and exits 5 | `scripts/sync-apply-batch.sh:L111` | 2026-11-13 | Verified (session). Reproduced `Cannot index string with string ("preflight")`, exit 5; re-run with main@080b7a5's L111 filter, same result |
| R2 | Constructs that need bash ≥ 4: `declare -A` and `mapfile` in the sync scripts, and `mapfile` in `rfc-frontmatter.sh` | `scripts/sync-owned-regions-apply.sh:L61,L92,L97,L109,L157,L179`; `scripts/sync-render-template.sh:L66`; `scripts/rfc-frontmatter.sh:L85-L86` | 2026-11-13 | Verified (session); #116 moved the `mapfile` lines from L65-L66 |
| R3 | It writes relative to cwd: an empty repo-root argument falls back to `$PWD`, then `cd`s there | `scripts/sync-run.sh:L70`; `scripts/sync-classify-all.sh:L56,L80` | 2026-11-13 | Verified (session); holds on main |
| R4 | The consumer settings template still defines PostToolUse and Stop hooks, plus a `<PRE_TOOL_USE_HOOK>` slot, which `/sync` writes into the consumer's committed `.claude/settings.json`. #116 dropped its SessionStart and PreCompact entries (0b733dc) and removed every hook from this repo's `.claude/settings.json` (e749bd4), which now holds only `enabledPlugins` and `extraKnownMarketplaces` | `templates/settings.json.tpl:L4-L45`; `.claude/settings.json:L1-L8`; `git show 0b733dc e749bd4` | 2026-11-13 | Verified (session). Before #116 the template had SessionStart and PreCompact entries too (`0745d32:templates/settings.json.tpl:L5-L24`) |
| R5 | Before #113, the rendered CI had `jobs:` with only a comment under it, so runs failed with zero jobs, and no job ran `tests/run.sh` | `templates/ci.yml.tpl:L1-L8`; `.github/workflows/ci.yml:L1-L10` at 531de96; https://github.com/bytewyrd/claude-bytewyrd/actions/runs/29619380118 | 2026-07-17 (run) | Verified (pack). No longer reproduces on main@080b7a5: 1643d55 renders a no-op `ci` job when no language is detected, and f9442ef replaced the stub workflow with `lint`, `validate` and `test` (`git show 1643d55 f9442ef`) |
| R6 | Line counts on main: 18 `sync-*.sh` = 4,031; sync-only `_lib` = 760; `build-manifest.sh` = 63; hook = 4; `SKILL.md` = 860; `check-requirements.sh` = 266; total ≈ 6.0K. Tests: 17 sync bats files = 3,721; `bootstrap-manifest.bats` = 55 | `wc -l` on `git archive origin/main` | 2026-11-13 | Verified (session). At 531de96 the total was ≈ 5.75K; #116's deprecation guard added three `SKILL.md` lines |
| R7 | The manifest has 11 artifacts. Root `rfc-process.md` is byte-identical to `docs/rfc-process.md` | `bootstrap-manifest.json`; `cmp` | 2026-11-13 | Verified (session) |
| R8 | `_lib/common.bash` is sourced by the `rfc-*` scripts, `build-manifest.sh` and `tool-probe.sh`. `chunks`, `plugin` and `detect-languages` are sourced only by `sync-*` | `grep source scripts/*.sh` | 2026-11-13 | Verified (session) |
| R9 | `tool-probe.sh` probes gh, git, jq and three companion plugins. It has no Exa or Firefox probe | `scripts/tool-probe.sh:L6-L12` | 2026-11-13 | Verified (session) |
| R10 | `check-requirements.sh` probes three companion plugins and the `mcp__exa__` and `mcp__firefox-devtools__` prefixes. It exits 2 when git is missing or a reference is stale | `scripts/check-requirements.sh:L13-L15,L23-L24` | 2026-11-13 | Verified (pack); lines re-read |
| R11 | `hooks/hooks.json` has two SessionStart entries: the `compact` reminder (L4-L12) and the check-requirements entry (L13-L20). #116 (24aa6df) removed the third, the SubagentStop entry: matcher `(^\|:)feature-engineer$`, an `echo` reminder to consider `/docs-review`, and `mkdir -p .bytewyrd && : > .bytewyrd/last-feature-engineer-stop` | `hooks/hooks.json:L1-L23`; `0745d32:hooks/hooks.json:L3-L17` | 2026-11-13 | Verified (session) |
| R12 | The documented install commands; plugin.json has no `version` since #113 (it had `"version": "0.2.0"`); the marketplace source is `"./"` | `README.md:L9-L10`; `docs/guide/installation.md:L6-L7`; `.claude-plugin/*.json` | 2026-11-13 | Verified (session) |
| R13 | Outside `docs/rfcs/` and the files the implementation PR deletes, `/sync` appears in 32 files on main; the brief pack counted 27 with a narrower grep | `git grep -l '/sync' origin/main` with those exclusions | 2026-11-13 | Verified (session). It was 33 at 080b7a5: e749bd4 took the "Consider running /sync" hook out of `.claude/settings.json` |
| R14 | 11 skills use `${CLAUDE_PLUGIN_ROOT}`. No skill has `scripts/` or `references/`, and 0 of 14 declare `compatibility:`. There are ten `mcp__` tool IDs: `skills/rfc-implement/SKILL.md:L20`; `agents/claude-agent-author.md:L47,L90,L251`; `agents/rfc-architect.md:L130-L131`; `templates/settings.json.tpl:L17,L26` | `grep -rno 'mcp__[A-Za-z0-9_-]*' skills agents templates hooks` | 2026-11-13 | Verified (session). The grep reports 11 matches; the extra one is the bare pattern `mcp__<server>__<tool>` at `agents/claude-agent-author.md:L88` |
| R15 | Legacy marker forms: headers, banners, the `# bytewyrd:` tags and the sidecar at both locations. `<!--lang:*-->` lines are stripped at render, so they are not markers | `scripts/sync-marker-read.sh:L6-L7`; `scripts/sync-write-header.sh:L84-L86`; `templates/.gitignore.tpl:L1,L4-L5`; `skills/sync/SKILL.md:L72`; `scripts/sync-render-template.sh:L124-L145` | 2026-11-13 | Verified (session). #116 moved every `skills/sync/SKILL.md` line after L13 down by three |
| R16 | The RFC opt-in keys on `docs/rfc-process.md`. 37 files outside `skills/sync/` and `docs/rfcs/` reference it on main | `agents/feature-engineer.md:L70-L73`; `git grep -l` | 2026-11-13 | Verified (session). The pack counted 19 because it searched fewer files |
| R17 | RFC statuses and summaries. `2026-05-12-auto-extract-best-practices-on-precompact` (Done) introduced the blocking PreCompact hook. `2026-05-14-sync-per-file-extension-strategies` and `2026-05-12-sync-enforce-github-branch-auto-delete` are Dropped, each as superseded by this RFC (53181a5, f846f3c) | `docs/rfcs/*.md` | 2026-11-13 | Verified (session) |
| R18 | Open PRs #100, #101, #102 and #107 mention `/sync`; #109 was closed unmerged; #113 merged as 080b7a5 | GitHub; `gh pr view` | 2026-11-13 | Verified (pack); states re-checked in session |
| R19a | `/sync` is not idempotent. The mechanism: classification hashes the raw template, while apply stamps the rendered SHA | `skills/sync/SKILL.md:L268` | 2026-11-13 | Mechanism verified (session). End-to-end behaviour: [UNVERIFIED] — reported by the 2026-11-09 audit; not re-reproduced |
| R19b | User lines inside a `# bytewyrd:` block are deleted | `scripts/sync-apply-batch.sh:L336-L372` | 2026-11-13 | Verified (session). Running the awk program verbatim dropped a `.env` line |
| R19c | Writes happen before the "Apply these changes?" prompt | `skills/sync/SKILL.md:L70,L72` vs `:L288` | 2026-11-13 | Verified (session). Holds on main; the L109 version write now writes nothing, because plugin.json has no `version` [R12] |
| R19d | An LLM classifies item pairs and replaces items at confidence ≥ 0.5; the soundness review is "an LLM-assisted pass" | `skills/sync/SKILL.md:L440-L466,L474` | 2026-11-13 | Verified (session) |
| R20 | `.bytewyrd/` writers exist, and today only the seeded `.gitignore` hides their output | `skills/best-practices-extract/SKILL.md:L273`; `skills/docs-review/SKILL.md:L54`; `templates/.gitignore.tpl:L4`; `0745d32:hooks/hooks.json:L13` | 2026-11-13 | Verified (session). The hook writer at `0745d32:hooks/hooks.json:L13` is the SubagentStop write that #116 removed [R11] |
| R21 | rfc-architect falls back to WebSearch and WebFetch when Exa is unreachable | `agents/rfc-architect.md:L133` | 2026-11-13 | Verified (session) |
| R22 | Nine skills are Claude-only because they use AskUserQuestion, spawn subagents or use `~/.claude`: best-practices-extract, best-practices-record, docs-review, refactor, rfc-braindump, rfc-consensus-review, rfc-implement, rfc-new, rfc-read-feedback | grep over `skills/*/SKILL.md` | 2026-11-13 | Verified (session) |
| R23 | 0.2.x per-language toolchain lines and gate commands. Its CI jobs were "assembled" by the agent | `skills/sync/SKILL.md:L602-L607,L654-L658,L704-L706` | 2026-11-13 | Verified (session) |
| R24 | `claude plugin validate .` (2.1.323) passes with a warning that the root CLAUDE.md is not loaded. Without the root CLAUDE.md, a copy passes `--strict`. Removing `version` adds a warning that fails `--strict`. `dependencies`, the allowlist and the SessionStart entry pass `--strict`. A missing allowlist is not flagged. The directory checks report LICENSE_MISSING | local runs at 531de96 | 2026-11-13 | Verified (session). On main, `LICENSE` exists and `version` is gone [R49] |
| R25 | This repo's legacy artifacts on main: headers in seven files (the PR template, `ci.yml`, `CLAUDE.md`, `README.md`, `docs/BEST_PRACTICES.md`, `mise.toml`, `.gitignore`), banners in two (`CLAUDE.md`, `docs/BEST_PRACTICES.md`), both sidecars tracked, and `docs/rfc-process.md`. `.claude/settings.json` holds no 0.2.x hook, so `legacy-settings-hooks` doesn't fire here | `git grep`; `git ls-files`; `.claude/settings.json:L1-L8` | 2026-11-13 | Verified (session). Before e749bd4 the settings hooks were a legacy artifact too [R4] |
| R26 | `compute_upstream_key` is used only by manifest tooling, and `plugin_enabled` by `tool-probe.sh` | `scripts/_lib/common.bash:L61-L82,L84-L95`; `scripts/build-manifest.sh:L46`; `scripts/sync-classify.sh:L166`; `tests/scripts/helpers.bash:L33-L52` | 2026-11-13 | Verified (session) |
| R27 | Worktree-aware project-name logic | `scripts/sync-preflight.sh:L152-L154` | 2026-11-13 | Verified (session) |
| R28 | `detect-languages.bash` is 272 lines and needs python3 with tomllib | `scripts/_lib/detect-languages.bash:L22-L38` | 2026-11-13 | Verified (session) |
| R29 | Sources of the five rules | `templates/CLAUDE.md.tpl:L30-L34,L40-L47,L49-L59,L96-L104`; `CLAUDE.md:L151` | 2026-11-13 | Verified (session) |
| R30 | PR #100's RFC adds a SessionStart `compact` hook | `origin/rfc/2026-05-17-auto-rehydrate-context-after-compaction`: `docs/rfcs/2026-05-17-auto-rehydrate-context-after-compaction.md:L12` | 2026-11-13 | Verified (session) |
| R31 | A plugin with unmet `dependencies` installs with exit 0, warns "bytewyrd will not load without them", and `claude plugin list --json` shows `errors`/`errorDetails` (`dependency-unsatisfied`) | local run, Claude Code 2.1.323, scratch HOME, local marketplace | 2026-11-13 | Verified (session). OPS saw the same with a CLI-only install and with a dependency disabled in `enabledPlugins` |
| R32 | After `git rm`, `git status --porcelain` prints `D  <file>`, so the tree is dirty | local test, git 2.56.0 | 2026-11-13 | Verified (session) |
| R33 | A nested `.bytewyrd/.gitignore` with `*` hides an untracked sidecar despite the root negation. Adding `!.bootstrap-versions.json` restores it, and the nested file stays ignored | local test, git 2.56.0 | 2026-11-13 | Verified (session) |
| R34 | CLAUDE.md's ten 0.2.x `owned_sections`. Other H2s are project-owned, e.g. `## Workflow`, `## Maintaining the bootstrap manifest` | `bootstrap-manifest.json`; `CLAUDE.md:L125,L192` | 2026-11-13 | Verified (session) |
| R35 | The 0.2.x PreCompact hook blocks while the sentinel is absent. Its message documents "bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact" | `0745d32:templates/settings.json.tpl:L15-L24,L20` | 2026-11-13 | Verified (session). 0b733dc removed it from the template; apps set up earlier keep it in their own settings [R63] |
| R36 | 0.2.x CI set `working-directory` for non-root components | `skills/sync/SKILL.md:L706` | 2026-11-13 | Verified (session) |
| R37 | `docs/guide/reference/hooks.md` mentions `/sync` | `docs/guide/reference/hooks.md:L3,L67` | 2026-11-13 | Verified (session) |
| R38 | `exit` inside an EXIT trap overrides the status, including after a syntax error later in the script. noclobber refuses to write through a symlink | local tests, bash 5.3.20 | 2026-11-13 | Verified (session). The basis of the bash design that Appendix F's post-review revision replaces with R52 |
| R39 | A committed symlink at `.bytewyrd` or its target redirects or truncates writes (F1). A symlinked `.github` lets `mkdir -p` and `>` write outside the repo while porcelain stays empty (F2) | SEC reproductions, git 2.56 | 2026-11-13 | Verified (ledger) |
| R40 | A nested `go.mod` makes root `go test ./...` exit 1, and a nested `Cargo.toml` makes `cargo build` exit 101 | OPS reproductions | 2026-11-13 | Verified (ledger) |
| R41 | The GitHub MCP server exposes `merge_pull_request` and `delete_repository` | tool list observed in this drafting session | 2026-11-13 | Verified (session) |
| R42 | The best-practices library's `## Security` section covers secrets, input validation, least privilege, pinning and AuthN/AuthZ | `templates/BEST_PRACTICES.md.tpl:L102-L109` | 2026-11-13 | Verified (session) |
| R43 | A SHA-pinned reusable workflow still resolves the tag refs inside it at run time | review finding F11(b), SEC-3 | 2026-11-13 | Verified (ledger) |
| R44 | Release-tag commits: checkout v7.0.1 `3d3c42e5aac5ba805825da76410c181273ba90b1`, setup-go v7.0.0 `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e`, setup-bun v2.2.0 `0c5077e51419868618aeaa5fe8019c62421857d6`, setup-uv v10.3.3 `68559e99cc807c1eb7e9238fd43a15bba460eec2`, rust-toolchain master `683b588c487a69d01f6c6ddf40f036ff682cc2c8`. All are lightweight tags | `git ls-remote` | 2026-11-13 | Verified (session). The checkout and setup-uv SHAs also appear in uv's and setup-uv's docs |
| R45 | `git -C ROOT ls-files -- go.mod …` lists tracked root manifests only, ignoring nested and untracked ones | local test, git 2.56.0 | 2026-11-13 | Verified (session) |
| R46 | Commit dee771e (2026-05-16), "fix(sync): replace sync-summary.py with bash implementation (no Python dependency)", gave as its reason: "Python is not installed by default on macOS 12.3+ and is not a safe hard dependency for a Claude Code plugin" | `git show -s dee771e` | 2026-11-13 | Verified (session) |
| R47 | `/sync` already hard-requires python3 ≥ 3.11 and exits 1 without it, because `tomllib` canonicalizes `mise.toml`; the check's comment names "3.10 on Ubuntu 22.04 LTS" as too old. `sync-canonical.sh` and `detect-languages.bash` import `tomllib` | `scripts/sync-preflight.sh:L115-L132`; `scripts/sync-canonical.sh:L403-L417`; `scripts/_lib/detect-languages.bash:L35-L38` | 2026-11-13 | Verified (session) |
| R48 | Bash-side dependencies and workarounds: `require_jq` exits 2 without jq; `hash_string` falls back from `sha256sum` to `shasum -a 256`; the `compact` hook falls back from GNU `stat -c %Y` to BSD `stat -f %m`; all ten surviving scripts call jq | `scripts/_lib/common.bash:L12-L17,L53-L59`; `hooks/hooks.json:L9`; `grep -w jq scripts/rfc-*.sh scripts/tool-probe.sh` | 2026-11-13 | Verified (session); the hook moved from L24 when #116 removed SubagentStop |
| R49 | PR #113 (`chore/ship-it-properly`) merged on 2026-11-13 as 080b7a5. On main it adds `require_bash_major`, which exits 2 with a JSON error on stderr (`scripts/_lib/common.bash:L19-L30`), and calls `require_bash_major 4` in `rfc-frontmatter.sh:L28`, `rfc-summary.sh:L29`, `sync-owned-regions-apply.sh:L36`, `sync-preflight.sh:L113` and `sync-render-template.sh:L39`; `tests/scripts/common.bats:L63,L66` assert the `sync-preflight.sh` and `rfc-summary.sh` guards. It reformats the shell files with shfmt under a new `.editorconfig`. It adds an Apache-2.0 `LICENSE`; `THIRD_PARTY_NOTICES.md` (an intro, then per project **Source**, **License**, **Used in** and the full license text); `.github/scripts/{check-links,lint-frontmatter}.py`; and the bats files `ci-lint`, `plugin-version` (two `check-requirements` tests, then `sync-preflight` and sync-skill tests) and `rfc-skill-errors` (runs the rfc-approve and rfc-drop frontmatter snippets, including against a stand-in that fails like the bash-4 guard). It removes plugin.json's `version`. Its CI has jobs `lint`, `validate` and `test` (which runs the bats suite) on `ubuntu-26.04`, named in a comment as the required checks, with `PYTHON_VERSION` 3.13, `PYYAML_VERSION` 6.0.3 (pip-installed in `lint` and `test`), `CLAUDE_CODE_VERSION` 2.1.323 via npm, setup-python v7.1.0 `6d4fd22b20465ccc0f7354476588e8df7c9ca0e0` and setup-node v7.1.0 `949feb2413d6458794dcd2491c4babbbce0c15c1`. `lint` also parses `bootstrap-manifest.json` and runs `build-manifest.sh --check` | `git show origin/main:<path>`; `git log 531de96..origin/main`; `gh pr view 113`; `git ls-remote` for the setup-python tag | 2026-11-13 | Verified (session) |
| R50 | The braindump entry "Audit skills for deterministic-script consolidation; settle Python dependency policy" | `docs/rfc-braindump.md:L15` | 2026-11-13 | Verified (session) |
| R51 | After the delete commits the remaining bash is eight `rfc-*` helpers (they delete `rfc-legacy-detect.sh` [R58]), `tool-probe.sh` and `_lib/common.bash`. Each script's bats file sets `SCRIPT="$SCRIPT_ROOT/scripts/<name>.sh"` and runs `bash "$SCRIPT"`; `rfc-set-status.bats` also runs `rfc-frontmatter.sh` directly, and `common.bats` sources the library. Ten skills call the scripts as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` (19 calls) and parse their JSON output with jq | `ls scripts`; grep over `tests/scripts/*.bats` and `skills/*/SKILL.md` | 2026-11-13 | Verified (session) |
| R52 | On Python 3.14.10: `open(p, "x")` raises `FileExistsError` for a dangling symlink, a live symlink and a directory, creating nothing at the target; `os.path.lexists` is true for a dangling symlink; an uncaught exception exits 1, as does a syntax error in the script or in a module it imports; a `sys.version_info < (3, 11)` gate that writes to stderr and calls `sys.exit(1)` exits 1; argparse usage errors exit 2, or 1 with `error()` overridden; `difflib.unified_diff` prints `---`, `+++` and `@@` headers, then lines prefixed `-`, `+` or a space | local tests | 2026-11-13 | Verified (session) |
| R53 | Draft `2026-05-10-ci-qa-bytewyrd-github-app` ships its QA workflow as a template, `templates/github-workflows/bytewyrd-qa.yml`, that consumer projects copy into `.github/workflows/`, and the workflow invokes `anthropics/claude-code-action@v1`, a tag | `docs/rfcs/2026-05-10-ci-qa-bytewyrd-github-app.md:L12` | 2026-11-13 | Verified (session) |
| R54 | On Python 3.14.10, `-I` leaves `site` on (`sys.flags.no_site` is 0), so a `.pth` file in a venv's site-packages runs, and it ignores `PYTHONDONTWRITEBYTECODE`, so imports write `__pycache__/`. With `-I -S -B`, `no_site` is 1, the `.pth` file doesn't run and no `__pycache__/` appears | local tests with a venv `.pth` marker | 2026-11-13 | Verified (session); the re-review (SEC) saw the same |
| R55 | 289 bytes of aliased YAML load with `safe_load` into data that `json.dumps` turns into 254 MB; SEC measured 328 bytes → 25 MB. PyYAML 6.0.3's `Composer.compose_node` handles `AliasEvent` first, so a `SafeLoader` subclass that raises there rejects the document | local tests with PyYAML 6.0.3; `yaml/composer.py` | 2026-11-13 | Verified (session) |
| R56 | A `SafeLoader` subclass with no implicit resolvers keeps every plain scalar as written (`2026-11-09`, `yes`, `12`, `~`, `Plain "title"`), unquotes quoted values, drops `# comments` (`"Draft" # still a draft` gives `Draft`) and raises on an unquoted `title: RFC: x`. All 24 RFCs on main parse, and their six frontmatter fields equal the output of main's awk parser, which since 812943e undoes `\"` and `\\` [R77] but keeps `'it''s'` and `"a\tb"`'s `\t` as written. `helpers.bash`'s fixture quotes every value except a `~` `drop_reason`; #116's own fixtures don't [R78] | local tests, PyYAML 6.0.3; `tests/scripts/helpers.bash:L70-L75` | 2026-11-13 | Verified (session). The orchestrator saw the same two results |
| R57 | Updating an existing install with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `claude plugin update bytewyrd@bytewyrd` exits 0, prints "3 dependencies still unresolved…", and bytewyrd stops loading | OPS reproduction, Claude Code 2.1.325 | 2026-11-13 | Reproduced (reviewer) |
| R58 | `rfc-legacy-detect.sh` has no callers outside its own bats file. tool-probe's `github-mcp`, `context7-mcp` and `code-review-mcp` probes read `enabledPlugins` through `plugin_enabled`, which nothing else on the plugin's path uses; `skills/rfc-implement/SKILL.md:L14` and `skills/refactor/SKILL.md:L15` call two of them | `git grep` on main; `scripts/tool-probe.sh:L6-L12,L78-L94`; `scripts/_lib/common.bash:L84-L95` | 2026-11-13 | Verified (session) |
| R59 | `rfc-summary.sh` runs `rfc-frontmatter.sh` (`FRONTMATTER_SH`, L31) for each RFC and turns its failures into warnings (L46) | `scripts/rfc-summary.sh:L31,L46` | 2026-11-13 | Verified (session) |
| R60 | On Linux, `os.open(".bytewyrd", O_DIRECTORY\|O_NOFOLLOW)` refuses a symlinked directory (ENOTDIR). After opening, swapping the directory for a symlink doesn't redirect `dir_fd` operations, and `O_NOFOLLOW` refuses a symlinked file (ELOOP). `os.open`, `mkdir`, `stat`, `utime` and `unlink` are in `os.supports_dir_fd` | local tests, Python 3.14.10 | 2026-11-13 | Verified (session) |
| R61 | `tests/scripts` has 64 lines matching `scripts/[a-z-]+\.sh` at 531de96, 75 at 080b7a5 and 76 on main, where #116 added `rfc-frontmatter.bats:L89`, a direct `rfc-set-status.sh` call. 26 are in files that survive the delete commits, which remove one of them (`common.bats:L63`), so the harness commit updates 25 | `git grep -nE` | 2026-11-13 | Verified (session) |
| R62 | Helper exit codes on main: tool-probe exits 1 for a missing tool, rfc-resolve exits 1 when no RFC matches, and both exit 2 on usage errors | `scripts/tool-probe.sh:L28-L31`; `scripts/rfc-resolve.sh:L20-L23` | 2026-11-13 | Verified (session) |
| R63 | The hooks `/sync` wrote into app repos are self-contained shell. Main's template writes PostToolUse and Stop `echo` reminders and the optional PreToolUse hook, which runs the project's own `cargo`, `bun`, `go` or `uv` commands. Apps set up before 0b733dc also carry, in their own committed settings, a SessionStart entry that removes `.bytewyrd/precompact-extraction-done` and a PreCompact entry that blocks until it exists; the template change affects only later runs. None references a plugin file | `templates/settings.json.tpl:L4-L45`; `scripts/sync-compute-template-vars.sh:L72-L84`; `0745d32:templates/settings.json.tpl:L5-L24` | 2026-11-13 | Verified (session) |
| R64 | The sentinel's writer stays in `/best-practices-extract`: today at `skills/best-practices-extract/SKILL.md:L273`, then as `bw state-touch` from the add commits (B1). Only B1's `Later` row removes it | `skills/best-practices-extract/SKILL.md:L273`; B1 | 2026-11-13 | Verified (session); unchanged by #116 |
| R66 | Bun 1.3.14 with no test files: `bun test` exits 1 with `error: 0 test files matching **{.test,.spec,_test_,_spec_}.{js,ts,jsx,tsx} …`; `bun test --pass-with-no-tests` exits 0; `bun test --help` lists `--pass-with-no-tests  Exit with code 0 when no tests are found`. `bun install` with no dependencies prints "No packages! Deleted empty lockfile" and exits 0. With a root `"workspaces": ["packages/*"]`, root `bun install` locks only `packages/a`, while root `bun test` runs the tests in `packages/a` and in the non-member `tools/x` | local runs, Bun 1.3.14 | 2026-11-13 | Verified (session); the orchestrator saw the first three too |
| R67 | Before this amendment, detection was root-only by design (`languages(root)` in B2), because nested manifests broke root-level `go test ./...` and `cargo build` [R40, F11]. The caller template had one `@@<id>@@`-tagged job per language, so it could not express several directories per language | this RFC at 4d9d384: B2, Appendix C, Appendix D F11 | 2026-11-13 | Verified (session) |
| R68 | `/sync`'s detection runs plain `find . -name …` for `Cargo.toml` (skipping `*/target/*`), `package.json` (skipping `*/node_modules/*`) and `go.mod` (skipping nothing), so it counts this repo's `tests/fixtures/lang-ci/go/go.mod` as a Go component | `scripts/_lib/detect-languages.bash:L112-L114` | 2026-11-13 | Verified (session) |
| R69 | Run 43533873786 on #115's head 4d9d384: `lint`, `validate`, `test` and `lang-ci-fixture / go` succeeded, the other three `lang-ci.yml` jobs were skipped, and the run concluded `success`; `test`, the bats suite, took 68 s. The go job resolved `go 1.27` to Go 1.27.4, and setup-go warned "Restore cache failed: Dependencies file is not found in <workspace>. Supported file pattern: go.mod" | `gh run view 43533873786 --json jobs`; the log lines as the orchestrator read them | 2026-11-13 | Verified (session) for the job results and timing. The log lines are Verified (ledger): the log host was outside this session's sandbox, and E73 shows the code that prints the warning |
| R70 | go 1.27.3: with a root `go.mod` and a nested module, root `go list ./...` lists only the root module, also when a root `go.work` uses both. With a `go.work` and no root `go.mod`, root `go list ./...` and `go build ./...` exit 1 ("directory prefix . does not contain modules listed in go.work"), and both work in a member directory. `go help packages`: `...` patterns skip directories named `vendor` or `testdata`, names beginning with `_` or `.`, and directories that contain a `go.mod`, which "can only be matched by changing the working directory into module" | local runs; `go help packages` | 2026-11-13 | Verified (session) |
| R71 | cargo 1.97.0, offline: with a root package and `[workspace] members = ["crates/*"]`, `cargo build` builds only the root package, and `--workspace` adds the member. In a virtual manifest with `default-members`, plain `cargo build` builds only those. A nested crate that is neither member nor excluded fails in place with exit 101, "current package believes it's in a workspace when it's not", and the hint names `workspace.exclude` or an empty `[workspace]` table. A crate under an `exclude` entry builds standalone; `exclude` matches path prefixes (`tools` covers `tools/standalone`), not globs (`tool*` doesn't). An unlisted path dependency is a member. Under a root package without `[workspace]`, a nested crate builds standalone. `cargo test --workspace` passes in a standalone crate, and `cargo test --workspace` and `cargo clippy --workspace` cover both root and member | local runs | 2026-11-13 | Verified (session) |
| R72 | uv 0.13.4, offline: `uv sync --all-packages` exits 0 in a project with no workspace and at a virtual workspace root. At a root with `members = ["packages/*"]` and `exclude = ["packages/skip"]`, `uv sync --all-packages` locks the root and `packages/m`, and `uv sync` in the excluded `packages/skip` or in the non-member `tools/stray` creates that directory's own `.venv` and `uv.lock` and exits 0. `uv sync --help` lists `--all-packages  Sync all packages in the workspace`; `uv run --help` lists `--all-packages  Run the command with all workspace members installed` | local runs | 2026-11-13 | Verified (session) |
| R73 | git 2.56.1: for the `.gitattributes` lines `web/package.json -bytewyrd-ci`, `/a/b/c/** bytewyrd-ci` and `examples/ -bytewyrd-ci`, `git check-attr --stdin -z bytewyrd-ci` reports `unset`, `set` and `unspecified`, as NUL-separated path, attribute and value: a trailing-slash pattern doesn't reach the files inside, and `examples/**` does. `git ls-files` lists a submodule as one gitlink (mode 160000), not its files. On a detached HEAD, `git branch --show-current` prints nothing, and `git checkout -q ""` exits 128 | local runs | 2026-11-13 | Verified (session) |
| R74 | This repo tracks one language manifest, `tests/fixtures/lang-ci/go/go.mod` | `git ls-files` at 4d9d384 | 2026-11-13 | Verified (session) |
| R75 | RubyGems reports `Gem::Platform.local` as `x86_64-linux` on x86_64 glibc Linux (Ruby 3.3.13). Bundler 4.0.4's `bundle lock --help` says `--add-platform PLATFORM` adds a platform other than the local one to the lockfile | local runs | 2026-11-13 | Verified (session) |
| R76 | On Python 3.14.10, `fnmatch.fnmatchcase` is case-sensitive (`'Web'` against `'web'` is false), and its `*` also matches `/` (`'a/b'` against `'*'` is true) | local run | 2026-11-13 | Verified (session) |
| R77 | PR #116 merged on 2026-11-13 as d9ae47e. 24aa6df removed the SubagentStop entry [R11]; e749bd4 removed every hook from this repo's `.claude/settings.json`; 0b733dc dropped the template's SessionStart and PreCompact entries [R4, R63]; cb334ea put a deprecation prompt before `/sync`'s Step 1 (`skills/sync/SKILL.md:L11`); a842f13 set `disable-model-invocation: true` on docs-review, refactor, rfc-approve, rfc-drop, rfc-implement and sync. Notes at `docs/guide/reference/hooks.md:L9`, `docs/guide/concepts.md:L47` and `CLAUDE.md:L170` say SubagentStop is removed until "PR 1 of RFC `2026-11-09-scaffold-and-drift` re-adds it". 812943e makes `rfc-frontmatter.sh` drop a double-quoted value's outer quotes and undo `\\` and `\"` inside it, and delete every `"` from any other value (`scripts/rfc-frontmatter.sh:L48-L67`); `rfc-set-status.sh` escapes `\` and `"` when it writes `drop_reason` (L70-L73) | `git log 0745d32..origin/main`; `git show` per commit; `gh pr view 116` | 2026-11-13 | Verified (session) |
| R78 | #116's test `a value that is not a clean double-quoted scalar still has its quotes dropped` (`tests/scripts/rfc-frontmatter.bats:L96-L114`) asserts `Plain title` (L111) and `Draft # still a draft` (L112); B2's loader gives `Plain "title"` and `Draft`. With a stand-in `rfc-frontmatter.sh` that runs that loader, main's whole bats suite, 345 tests, passes once L111-L112 are deleted, including #116's `unescapes \" and \\ in double-quoted values` (L68-L85), `reads back exactly what rfc-set-status.sh wrote for quotes and backslashes` (L87-L94) and its four `rfc-set-status.bats` escaping tests | local run on `git archive origin/main`, PyYAML 6.0.3 | 2026-11-13 | Verified (session). The orchestrator reproduced the two values |
| R79 | git 2.56.1, `check-attr --cached --stdin -z bytewyrd-ci`: `go.mod -bytewyrd-ci` unsets every `go.mod`, `svc/go.mod` included, and `/go.mod -bytewyrd-ci` only the root one. `bad dir/go.mod -bytewyrd-ci` warns `dir/go.mod is not a valid attribute name` and unsets nothing; `#x/go.mod -bytewyrd-ci` is a comment. A line built like B2's fix lines (`/`, the path with `\`, `*`, `?` and `[` escaped, then `quote()`) unsets exactly its path for 11 names, among them `bad dir`, `#x`, `a[1]`, `st*r`, `back\slash`, `q"uote`, `caf\303\251`, the non-UTF-8 `lat\351` and names holding a newline or ESC; unescaped, `/a[1]/go.mod` unsets `a1/go.mod` instead. `/web/go.mod bytewyrd-ci=false` reports the value `false`, and a macro (`[attr]quiet -bytewyrd-ci`, `/api/** quiet`) reports `unset`. An unstaged `.gitattributes` edit changes the result without `--cached` but not with it, and `.git/info/attributes` still applies with it | local runs | 2026-11-13 | Verified (session). The orchestrator reproduced the `svc/go.mod` case, and SEC and OPS the rest |
| R80 | Python 3.14.10: `re.match` with B2's `^…$` directory pattern accepts `web\n`, and `re.fullmatch` doesn't. `json.loads` and `tomllib.loads` raise `RecursionError` at 200,000 levels of nesting; a 5,000-digit JSON number raises a plain `ValueError` (the 4,300-digit limit), not `JSONDecodeError`; `tomllib.load` on invalid UTF-8 raises `UnicodeDecodeError`, a `ValueError` subclass. `members = "crates/*"` iterates as eight one-character patterns, and `fnmatchcase` raises `TypeError` on an int. `b"lat\xe9".decode()` raises `UnicodeDecodeError`, and `os.fsdecode` gives `'lat\udce9'`, which raises `UnicodeEncodeError` when encoded as UTF-8. Reading `/dev/zero` under a 512 MiB address-space cap raises `MemoryError` within 0.2 s | local runs | 2026-11-13 | Verified (session); SEC saw the same |
| R81 | go 1.27.3: `go help build` says that, without a vendor directory, "the go command acts as if -mod=readonly were set", and a build that needs a new requirement fails (`no required module provides package …`) with `go.mod` unchanged. Under a root `go.work` that uses `.` and `./svc`, `go build ./...` in the non-member `tools/` exits 1 ("directory prefix . does not contain modules listed in go.work"); after Appendix C's GOWORK line, which sets `GOWORK=off` there and leaves `.` and `svc/` alone, all three build | local runs | 2026-11-13 | Verified (session). OPS and the orchestrator saw the same |
| R82 | uv 0.13.4, offline: on a stale `uv.lock`, `uv sync --locked` exits 1 ("The lockfile at `uv.lock` needs to be updated, but `--locked` was provided"), and plain `uv sync` rewrites the lock and exits 0. `uv run` keeps its command's exit code (5 stays 5). In a `setup.py`-only directory `uv sync` exits 2 ("No `pyproject.toml` found in current directory or any parent directory"). With a `pyproject.toml` holding only `[tool.ruff]`, `uv sync` exits 0 and `uv run pytest` exits 2 (`Failed to spawn: pytest`); one holding only `[build-system]` and `[tool.black]`, next to a `setup.py`, also syncs with no project | local runs | 2026-11-13 | Verified (session); SEC and OPS saw the first and the last two |
| R83 | Bun 1.3.14, offline, with a `file:` dependency: `bun install --frozen-lockfile` exits 0 on an in-sync `bun.lock`, and exits 1 ("lockfile had changes, but lockfile is frozen") once `package.json` changes. With only a `package-lock.json`, even one that `package.json` has outgrown, or only a v1 `yarn.lock`, both `bun install` and `bun install --frozen-lockfile` exit 0 and write `bun.lock`. With no lockfile, `--frozen-lockfile` exits 0 and writes none | local runs | 2026-11-13 | Verified (session) |
| R84 | cargo 1.97.0: `cargo build --help` lists `--locked  Assert that Cargo.lock will remain unchanged`, and `cargo test` and `cargo clippy` accept it. In the Rust fixture's layout, `cargo test --locked` exits 0 with `--workspace`, running both crates' tests, and without it, running only the root's, so the leg can't tell them apart. Ruby 3.3.13 with Bundler 4.0.4: bundle-config(1) says `deployment` is "Equivalent to setting frozen to true and path to vendor/bundle", and that `lockfile_checksums`, a CHECKSUMS section "to protect from compromised gem sources", defaults to true; `bundle lock --local` writes CHECKSUMS with no `sha256=` for gems it didn't fetch. With no Rakefile, `bundle exec rake` fails with "No Rakefile found (looking for: rakefile, Rakefile, rakefile.rb, Rakefile.rb)", and with a Gemfile that lacks rake it can't load rake; both exit 1. A deployment install of a lockfile whose PLATFORMS is only `arm64-darwin-24` exits 16: "Your bundle only supports platforms ["arm64-darwin-24"] but your local platform is x86_64-linux", naming `bundle lock --add-platform x86_64-linux`. gemfile(5): "A Gemfile is evaluated as Ruby code" | local runs | 2026-11-13 | Verified (session). OPS saw the same failures with Ruby 4.0.2 and Bundler 4.0.6, and a `sha256=` CHECKSUMS entry from a networked `bundle lock` |
| R85 | `tests/scripts/ci-lint.bats:L21-L23` and `tests/scripts/rfc-set-status.bats:L115-L117` fail, rather than skip, under `CI` when `python3 -c 'import yaml'` fails | `git show origin/main:<path>` | 2026-11-13 | Verified (session) |
| R86 | `lang-ci.yml`'s only trigger is `workflow_call`, so it runs only when a caller's job runs it | `4d9d384:.github/workflows/lang-ci.yml:L11-L12` | 2026-11-13 | Verified (session) |
| R87 | bash(1) of bash 5.3.20: under `-e`, "The shell does not exit if the command that fails is part of … any command executed in a `&&` or `\|\|` list except the command following the final `&&` or `\|\|` … or if the command's return value is being inverted with `!`". Locally, a pin check written as `test 2 = 1 && test …` let the script finish with exit 0, while the same tests on separate lines exit 1. The Appendix C `lang-ci.yml`, written to a scratch file, parses with PyYAML, its `run:` scripts pass shellcheck 0.11.0, and the B4 #115 lint passes on it and fails on each of 13 seeded defects, one per comment there plus a deleted job, an extra permission and a `pull_request_target` trigger | `/usr/share/man/man1/bash.1.bz2`; local runs | 2026-11-13 | Verified (session) |
| R88 | The five Appendix C `lang-ci-<id>.yml` sketches, the rendered caller example, the `mise.toml`, `actionlint.yaml` and `lint` fragments, and the full #115 `ci.yml` built from them parse with PyYAML 6.0.3. In a scratch tree of those files and a Ruby `Gemfile.lock` stub, the B4 #115 `lint` block, run with `bash -e`, GNU grep 3.12 and GNU sed 4.10, exits 0 under `C.UTF-8` and `en_US.UTF-8`, and exits non-zero on each of 74 seeded defects, one at a time, each at the check whose comment names it: 13 per-file defects in each of the five files, and nine others. The version-check step fails for each of the three tools when `mise.toml` disagrees. The B4 pin checks, the same commands as Appendix C's `history` steps, pass, warn and fail as B4 says in nine cases in a scratch repository. A model of B2's caller checks gives `pin-changed` for each S24 decoy. shellcheck and actionlint weren't run in this session | local runs | 2026-11-14 | Verified (session) |
| R89 | `lang-ci.yml` exists only on #115's branch: e6eb962 (2026-11-13) added it, and `origin/main` at d9ae47e has no `.github/workflows/lang-ci.yml` | `git log --diff-filter=A`; `git cat-file -e origin/main:.github/workflows/lang-ci.yml` exits 128 | 2026-11-14 | Verified (session) |
| R90 | This repo's `mise.toml` is a 0.2.x header (L1), three comment lines and an empty `[tools]` (L6), and its template says "The [tools] table is yours to maintain" (L2). `/sync` applies the file's `tools[]:union` path by keeping the local file verbatim and restamping its marker | `mise.toml:L1-L6`; `templates/mise.toml.tpl:L2`; `bootstrap-manifest.json` (the `mise.toml` entry); `scripts/sync-apply-batch.sh:L580-L590` | 2026-11-14 | Verified (session) |
| R91 | actionlint 1.7.12 on the branch's `ci.yml` reports `label "ubuntu-26.04" is unknown [runner-label]` for each of its three jobs. With shellcheck 0.11.0 on `PATH` it also reports `SC2086:info` for the `run:` blocks at `4d9d384:.github/workflows/ci.yml:L100,L106`, the two steps where `$SHELL_FILES` is unquoted under `set -f`. The branch's `lang-ci.yml` gives no finding | the orchestrator's local runs; both files are unchanged since 4d9d384 | 2026-11-14 | Verified (orchestrator) |
| R92 | uv 0.13.4, offline, in a scratch git repo whose `dev` group pins pytest 9.2.0, PyYAML 6.0.3, ruff 0.17.5, mypy 2.4.1 and types-PyYAML. (1) With no `[project]` table, `uv lock` runs CPython 3.12.11 and warns "No `requires-python` value found in the workspace. Defaulting to `>=3.12`". The group's `[tool.uv.dependency-groups] dev = { requires-python = ">=3.11" }` shows up only as `[manifest.group-requires-python]`, the lock's top-level `requires-python` stays `>=3.12`, and `uv sync --locked --python 3.11` then exits 1, since 3.11 makes the default `>=3.11`. (2) With `[project]` (`name`, `version`, `requires-python = ">=3.11"`) and `[tool.uv] package = false`, the lock records `requires-python = ">=3.11"`, and `uv sync --locked` exits 0 on CPython 3.11.17 and on 3.14.10, installing the group's 14 packages but not the project. (3) After a `pyproject.toml` change, `uv sync --locked` exits 1 with "The lockfile at `uv.lock` needs to be updated, but `--locked` was provided" and "To update the lockfile, run `uv lock`". (4) With the environment at `.venv`, `uv run --no-sync` runs `ruff check`, `ruff format --check`, `mypy --strict` and `pytest`, each exiting 0. `git status --porcelain --untracked-files=all` then lists only `__pycache__/` files, because `.venv`, `.ruff_cache`, `.mypy_cache` and `.pytest_cache` each hold a `.gitignore` of `*`; with this repo's `__pycache__/` line in `.gitignore`, it lists nothing. `uv run --help` lists `--no-sync`, "Avoid syncing the virtual environment" | local runs; `.gitignore:L5` | 2026-11-15 | Verified (session). The orchestrator's spike, with pytest 9.1.0, saw the same four results |
| R93 | `uv.lock` records PyYAML's sdist as `{ url = "https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz", hash = "sha256:d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f", size = 130960, … }`. That is E69's URL and hash, which `scripts/_vendor/PyYAML-6.0.3.sha256` also records | R92's lock; `scripts/_vendor/PyYAML-6.0.3.sha256:L1` | 2026-11-15 | Verified (session); the orchestrator's lock has the same entry |
| R94 | In a clone of #117's branch at dd91cf6, with R92's `pyproject.toml` staged at the root, `sh scripts/bw drift` still prints `result: 2 ok, 2 info, 0 warn, 0 drift (exit 0)`, and `sh scripts/bw scaffold` skips all four targets. Detection now finds a root `python` component, which changes neither result: drift compares stamps with templates, this repo's `ci.yml` is unstamped, and every target exists | local runs | 2026-11-15 | Verified (session) |
| R95 | mise 2026.11.8's `mise registry uv` lists `aqua:astral-sh/uv`, `asdf:asdf-community/asdf-uv` and `pypi:uv`, the aqua backend first | local run | 2026-11-15 | Verified (session). E111 read v2026.11.0's registry for the other three tools |
| R96 | `scripts/_lib/bw.py` at dd91cf6 has nine `# ---` sections: git (L100); hashes, stamps and the plugin commit (L189); rendering (L248); files (L306); quoting (L413); detection (L460); seed targets (L741); frontmatter (L811); and JSON output (L994). Only `bw_drift.py` and `bw_scaffold.py` use names from the stamp, rendering and seed-target sections. In each command module, at most 33% of the lines name `bw`. git 2.56.1: git-log(1) says `--follow` continues "listing the history of a file beyond renames", and git-diff(1) says "The default similarity index is 50%" | `grep -n '^# --- '`, `grep -oE '\bbw\.[A-Za-z_]+'` and `grep -cE '\bbw\b'` over `scripts/_lib/`; `man git-log`; `man git-diff` | 2026-11-15 | Verified (session) |
| R97 | Issue #118, "Tracking: scaffold + drift (#117) and the next RFCs", open since 2026-11-15, has items for the three app repos' migrations and for the Later step that drops the PreCompact sentinel once drift shows no `legacy-settings-hooks` in all four repos | the GitHub MCP's `issue_read` | 2026-11-15 | Verified (session) |

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
| E38 | GNU `env -u NAME` removes NAME | local test: GNU coreutils 9.12 | 2026-11-13 | Verified (session). No longer used: consumer-sim builds each child environment itself (Appendix D) |
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
| E50 | "When Claude Code copies a plugin into the cache, it also installs the plugin's Node.js package dependencies there". The section "covers the npm and Bun packages a plugin declares in its own `package.json`". For "a relative-path plugin loaded in place … Claude Code doesn't install the dependencies". Dependencies the install can't provide, "Python dependencies" among them, are installed "from a hook into the persistent data directory" | https://code.claude.com/docs/en/plugins/loading (Node.js package dependencies) | 2026-11-13 | Verified (session) |
| E51 | `tomllib`: "Added in version 3.11" | https://docs.python.org/3/library/tomllib.html | 2026-11-13 | Verified (session) |
| E52 | "Recent versions of macOS include a python3 command in `/usr/bin/python3` that links to a usually older and incomplete version of Python provided by and for use by the Apple development tools, Xcode or the Command Line Tools for Xcode." Secondary sources put that interpreter at 3.9.6, including on macOS 26.2 | https://docs.python.org/3/using/mac.html; https://pydevtools.com/handbook/explanation/should-i-use-homebrew-to-install-python/; https://news.ycombinator.com/item?id=46570041 | 2026-11-13 | Verified (session); the 3.9.6 figure comes from secondary sources |
| E53 | Default `python3`: Ubuntu 22.04 LTS 3.10 (3.11 also available), 24.04 LTS 3.12, 26.04 LTS 3.14.3; Debian 12 3.11.2, Debian 13 3.13.5; RHEL 9 3.9, with 3.11 (since 9.2) and 3.12 (since 9.4) installable alongside | https://ubuntu.com/developers/docs/reference/availability/python/; https://packages.ubuntu.com/python3; https://qa.debian.org/madison.php?package=python3; https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/installing_and_using_dynamic_programming_languages/index | 2026-11-13 | Verified (session) |
| E54 | PyYAML 6.0.3 is MIT-licensed ("Copyright (c) 2017-2021 Ingy döt Net", "Copyright (c) 2006-2016 Kirill Simonov") and needs Python ≥ 3.8. The package is `lib/yaml/`; the optional `yaml._yaml` extension is built from `yaml/_yaml.pyx`, "falling back to pure Python" if that fails. `yaml/__init__.py` sets `__with_libyaml__ = False` when importing `cyaml`, which imports `yaml._yaml`, fails | https://pypi.org/project/PyYAML/6.0.3/; https://github.com/yaml/pyyaml/blob/6.0.3/setup.py; https://raw.githubusercontent.com/yaml/pyyaml/6.0.3/lib/yaml/__init__.py; https://raw.githubusercontent.com/yaml/pyyaml/6.0.3/lib/yaml/cyaml.py; https://raw.githubusercontent.com/yaml/pyyaml/6.0.3/LICENSE | 2026-11-13 | Verified (session) |
| E55 | `-I`: "Run Python in isolated mode. This also implies `-E`, `-P` and `-s` options." Isolated mode "ignores all `PYTHON*` environment variables, e.g. `PYTHONPATH` and `PYTHONHOME`". Added in 3.4 | https://docs.python.org/3/using/cmdline.html#cmdoption-I | 2026-11-13 | Verified (session) |
| E56 | `ArgumentParser.error()` "prints a usage message, including the message, to `sys.stderr` and terminates the program with a status code of 2" | https://docs.python.org/3/library/argparse.html | 2026-11-13 | Verified (session); reproduced in R52 |
| E57 | setup-python's x-range `'3.x'` selects "the latest stable version of Python (for the specified major version)". Its `python-path` output gives the installed interpreter's path | https://github.com/actions/setup-python/blob/main/docs/advanced-usage.md | 2026-11-13 | Verified (session) |
| E58 | pytest 9.2.0 was released on 2026-10-27; it requires Python ≥ 3.10 and is MIT-licensed | https://pypi.org/project/pytest/; https://github.com/pytest-dev/pytest/releases | 2026-11-13 | Verified (session) |
| E59 | An organization limits Actions under Settings → Actions → General → "Policies" with "Allow OWNER, and select non-OWNER, actions and reusable workflows", whose "Allow or block specified actions and reusable workflows" list takes reusable workflows as `OWNER/REPOSITORY/PATH/FILENAME@TAG-OR-SHA`, with `*` as a wildcard | https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization | 2026-11-13 | Verified (session) |
| E60 | The commands reference lists `/init` and `/doctor` but neither `/scaffold` nor `/drift`: a full-text search of the page finds no "scaffold" or "drift" | https://code.claude.com/docs/en/commands.md | 2026-11-13 | Verified (session) |
| E61 | `claude plugin disable` fails for a plugin that "Another enabled plugin depends on" and "names the dependents to disable first"; `/plugin` refuses likewise "when another enabled plugin still needs the one you named" | https://code.claude.com/docs/en/plugins/cli-reference (plugin disable); https://code.claude.com/docs/en/plugins/install (Plugins with dependencies) | 2026-11-13 | Verified (session) |
| E62 | RHEL 9 ships Python 3.9 as `python3`; 3.11 (since 9.2) and 3.12 (since 9.4) install as `python3.11` and `python3.12`. Ubuntu 22.04's `python3.11` is a separate universe package in jammy-updates, version 3.11.0~rc1-1~22.04.1 | https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/installing_and_using_dynamic_programming_languages/assembly_installing-and-using-python_installing-and-using-dynamic-programming-languages; https://packages.ubuntu.com/jammy-updates/python3.11 | 2026-11-13 | Verified (session) |
| E63 | "a commit that exists only in a fork can be referenced via its parent's `owner/repo` slug"; zizmor applies its `impostor-commit` audit to SHA-pinned reusable workflows too | https://docs.zizmor.sh/audits/#impostor-commit; https://github.com/zizmorcore/zizmor/blob/563b7b25/crates/zizmor/src/audit/impostor_commit.rs | 2026-11-13 | Verified (session) |
| E64 | `actions/checkout` defaults: `persist-credentials: true`, and `fetch-depth: 1` ("0 indicates all history for all branches and tags") | https://github.com/actions/checkout/blob/3d3c42e5aac5ba805825da76410c181273ba90b1/action.yml | 2026-11-13 | Verified (session) |
| E65 | `on.workflow_call.inputs.<id>` needs a `type`; a string input defaults to `""`; the called workflow reads it from the `inputs` context, which `jobs.<id>.if`, `jobs.<id>.defaults.run` and `steps.with` accept. `uses: ./.github/workflows/{filename}` runs the workflow "from the same commit as the caller workflow" | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax; https://docs.github.com/en/actions/reference/workflows-and-actions/contexts; https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions | 2026-11-13 | Verified (session) |
| E66 | `-S`: "Disable the import of the module `site`"; `-B`: "Python won't try to write `.pyc` files on the import of source modules" | https://docs.python.org/3/using/cmdline.html | 2026-11-13 | Verified (session) |
| E67 | `os.supports_dir_fd` lists the functions that accept `dir_fd` "on the local platform". CPython enables `openat`, `mkdirat`, `unlinkat` and `fstatat` on macOS 10.10 and later through runtime checks | https://docs.python.org/3/library/os.html; https://github.com/python/cpython/blob/v3.12.3/Modules/posixmodule.c; https://bugs.python.org/issue43800 | 2026-11-13 | Verified (session). `utimensat` on macOS is not covered; the macOS CI job asserts it (B2) |
| E68 | GitHub's macOS 15 arm64 runner image has Bash 3.2.57, Python3 3.15.2 and Homebrew | https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md | 2026-11-13 | Verified (session) |
| E69 | PyYAML 6.0.3's sdist is `pyyaml-6.0.3.tar.gz`, sha256 `d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f`, at https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz. Under `pyyaml-6.0.3/`, `lib/yaml/` holds 17 `.py` files; the extension sources are `yaml/_yaml.pyx` and `yaml/_yaml.pxd`, outside it | https://pypi.org/pypi/PyYAML/6.0.3/json; local download, `sha256sum`, `tar -tzf` | 2026-11-13 | Verified (session) |
| E70 | A `<job_id>` "must start with a letter or `_` and contain only alphanumeric characters, `-`, or `_`", and is unique in `jobs` | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax | 2026-11-13 | Verified (session) |
| E71 | A job that calls a reusable workflow may use only `name`, `uses`, `with`, `secrets`, `strategy`, `needs`, `if`, `concurrency`, `permissions` and `cache-mode`, so it can't add `services:`. The called workflow gets `github.token`, whose permissions it can only lower | https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations | 2026-11-13 | Verified (session) |
| E72 | `jobs.<job_id>.with.<with_id>` may use the `matrix` context | https://docs.github.com/en/actions/reference/workflows-and-actions/contexts | 2026-11-13 | Verified (session). No longer used: the fixture jobs dropped their matrix (D4) |
| E73 | setup-go v7.0.0 at `b7ad1dad…`: `cache` defaults to true. Without `cache-dependency-path` it looks only for `go.mod` in `GITHUB_WORKSPACE`, else throws "Dependencies file is not found in ${workspace}. Supported file pattern: go.mod", and when caching fails it "logs a warning and continues". `cache-dependency-path` takes repo-relative paths such as `subdir/go.sum`, globs and multi-line values. `go-version-file` takes `go.mod`, `go.work`, `.go-version` or `.tool-versions`; `token` defaults to `github.token` | `action.yml`, `src/cache-restore.ts`, `README.md` and `docs/advanced-usage.md` at that commit, via `gh api` | 2026-11-13 | Verified (session) |
| E74 | setup-uv v10.3.3 at `68559e99…`: `working-directory` ("The directory to execute all commands in and look for files such as pyproject.toml") defaults to `github.workspace`, and the version file and `cache-dependency-glob` (default `**/uv.lock`, `**/pyproject.toml` and requirements and constraints patterns) resolve against it with `path.resolve` | `action.yml` and `src/utils/inputs.ts` at that commit, via `gh api` | 2026-11-13 | Verified (session) |
| E75 | setup-bun v2.2.0 at `0c5077e5…`: the Bun version comes from `bun-version`, else `bun-version-file`, else silently from `package.json` in `GITHUB_WORKSPACE` (`packageManager: bun@…` or `engines.bun`), else the latest release ("If no version specified, default is "latest""). `no-cache` covers only the Bun executable; `token` defaults to `github.token` | `action.yml`, `src/index.ts`, `src/utils.ts` and `src/action.ts` at that commit, via `gh api` | 2026-11-13 | Verified (session) |
| E76 | ruby/setup-ruby's newest release and newest tag is v1.338.0 (2026-11-06), a lightweight tag on commit `b3aaceaef7e0ee231b499e7b5f49c03fc1d32199`. At that commit: an unset `ruby-version` reads `.ruby-version`, `.tool-versions` or `mise.toml`, and without them throws "input ruby-version needs to be specified if no .ruby-version or .tool-versions file exists"; `working-directory` resolves those files and `Gemfile.lock`; `bundler-cache: true` runs `bundle install` and caches the gems, needs a `Gemfile` under `working-directory`, sets `deployment true` when a lockfile exists and otherwise writes one with `bundle lock`; `token` defaults to `github.token`; the README's usage runs `bundle exec rake`, and a short version such as `4.0` selects the latest matching release; the newest stable CRuby it lists is 4.0.9 | `gh api repos/ruby/setup-ruby/releases/latest`, `…/git/ref/tags/v1.338.0` and `…/tags`; `action.yml`, `index.js`, `README.md` and `ruby-builder-versions.json` at that commit | 2026-11-13 | Verified (session) |
| E77 | Bun v1.3.1 (2025-10-22) added `bun test --pass-with-no-tests`, which "exits with code 0 when no tests are found"; without it `bun test` "continues to exit with 1" | https://bun.com/blog/bun-v1.3.1 | 2026-11-13 | Verified (session) |
| E78 | Bun 1.3.14: `bun test` "recursively searches the working directory" for test files, ignoring `node_modules` and hidden directories, and bunfig's `[test] root` and `pathIgnorePatterns` narrow it. `workspaces` takes "full glob syntax", negative patterns included, as an array or as `workspaces.packages`, and "`bun install` will install dependencies for all workspaces" | Context7: oven-sh/bun v1.3.14 (`docs/test/index.mdx`, `docs/test/discovery.mdx`, `docs/test/configuration.mdx`, `docs/pm/workspaces.mdx`, `docs/pm/catalogs.mdx`) | 2026-11-13 | Verified (session) |
| E79 | Cargo: "All `path` dependencies residing in the workspace directory automatically become members", and `members` supports globs. With no package selected, a root package is used, and a virtual workspace uses `default-members`, or all members "as if `--workspace` were specified" | https://doc.rust-lang.org/cargo/reference/workspaces.html | 2026-11-13 | Verified (session) |
| E80 | uv 0.13.4: "By default, `uv run` and `uv sync` operate on the workspace root"; `members` and `exclude` take globs; `uv sync` syncs exactly, while `uv run` syncs inexactly and keeps extraneous packages; the `dev` group is installed by default. The workspace example's build backend is `requires = ["uv_build>=0.13.4,<0.14"]` | Context7: astral-sh/uv v0.13.4 (`docs/concepts/projects/workspaces.md`, `sync.md`, `dependencies.md`) | 2026-11-13 | Verified (session) |
| E81 | pytest 9.2.0: with no arguments, collection starts from `testpaths` if configured, else the current directory, and recurses into directories that don't match `norecursedirs` | Context7: pytest-dev/pytest v9.2.0 (`doc/en/explanation/goodpractices.rst`, `doc/en/reference/reference.rst`) | 2026-11-13 | Verified (session) |
| E82 | `git check-attr` lists each attribute as `unspecified`, `unset`, `set` or a value. `--stdin` reads the paths, and with `-z` input and output are NUL-separated | https://git-scm.com/docs/git-check-attr | 2026-11-13 | Verified (session) |
| E83 | Rails v8.1.4.1 sets `task default: :test` ("Run all tests in test folder except system ones"); rspec-rails v8.1.0 deletes `test` from the default task and sets `task default: :spec`; RubyGems v4.0.24's `bundle gem` Rakefile makes its test task the default, plus any chosen linter | `railties/lib/rails/test_unit/testing.rake:L6-L9`; `lib/rspec/rails/tasks/rspec.rake:L2-L6`; `bundler/lib/bundler/templates/newgem/Rakefile.tt`; each at its tag, via `gh api` | 2026-11-13 | Verified (session) |
| E84 | `git revert` reverts the given commits' changes "and record[s] some new commits that record them". "Reverting a merge commit declares that you will never want the tree changes brought in by the merge. As a result, later merges will only bring in tree changes introduced by commits that are not ancestors of the previously reverted merge" | https://git-scm.com/docs/git-revert | 2026-11-13 | Verified (session) |
| E85 | actions/checkout: "In a pull request trigger, `ref` is required as GitHub Actions checks out in detached HEAD mode"; checking out the pull request's head commit "instead of merge commit" needs `ref` | `README.md` at `3d3c42e5…` (v7.0.1), via `gh api` | 2026-11-13 | Verified (session) |
| E86 | Context availability: `jobs.<job_id>.timeout-minutes` takes `github, needs, strategy, matrix, vars, inputs`; `jobs.<job_id>.if` takes `github, needs, vars, inputs`; `jobs.<job_id>.steps.if` and `jobs.<job_id>.steps.env` take `inputs` among others, and `steps.if` also the `hashFiles` function | https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability | 2026-11-13 | Verified (session) |
| E87 | "GitHub ignores case when comparing strings." `format('{0}…', …)` substitutes its arguments. `hashFiles(path)` resolves `path` "relative to the `GITHUB_WORKSPACE` directory", and "If the path pattern does not match any files, this returns an empty string." "A default status check of `success()` is applied unless you include one of these functions"; to run a step regardless of failure, use `if: ${{ !cancelled() }}`. A hyphenated id dereferences with a dot, as in `steps.set-matrix.outputs.matrix` | https://docs.github.com/en/actions/reference/workflows-and-actions/expressions | 2026-11-13 | Verified (session) |
| E88 | Workflow commands "are then sent to the runner over `stdout`": among them `error`, `warning`, `group`/`endgroup` and `add-mask`. `core.getInput` is "Accessible using environment variable `INPUT_{NAME}`" | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands | 2026-11-13 | Verified (session) |
| E89 | `on.workflow_call.inputs.<input_id>.type` "must be one of: `boolean`, `number`, or `string`". An unspecified `shell` on Linux runs `bash -e {0}`, so a failing command stops the step. `jobs.<job_id>.timeout-minutes`: "Default: 360" | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax | 2026-11-13 | Verified (session) |
| E90 | gitattributes: "Lines that begin with # are ignored. Patterns that begin with a double quote are quoted in C style"; patterns follow `.gitignore` rules, where a pattern with a separator at the beginning or middle "is relative to the directory level of the particular `.gitignore` file itself", otherwise it "may also match at any level below", and a backslash (`\`) "can be used to escape any character"; `$GIT_DIR/info/attributes` has the highest precedence, and `core.attributesFile` and system files apply too. `check-attr --cached`: "Consider `.gitattributes` in the index only, ignoring the working tree." `core.quotePath`: unusual characters are quoted "by enclosing the pathname in double-quotes and escaping those characters with backslashes in the same way C escapes control characters", with octal for bytes above 0x80 | https://git-scm.com/docs/gitattributes; https://git-scm.com/docs/gitignore; https://git-scm.com/docs/git-check-attr; https://git-scm.com/docs/git-config (core.quotePath) | 2026-11-13 | Verified (session) |
| E91 | `git checkout --recurse-submodules` "will update the content of all active submodules according to the commit recorded in the superproject"; without it, "submodules working trees will not be updated" | https://git-scm.com/docs/git-checkout | 2026-11-13 | Verified (session) |
| E92 | `$` "Matches the end of the string or just before the newline at the end of the string"; `re.fullmatch` returns a match only "If the whole string matches the regular expression pattern" | https://docs.python.org/3/library/re.html (3.15.2) | 2026-11-13 | Verified (session); reproduced in R80 |
| E93 | pytest "Exit code 5: No tests were collected" | Context7: pytest-dev/pytest (`doc/en/reference/exit-codes.rst`) | 2026-11-13 | Verified (session) |
| E94 | Bun's newest release is bun-v1.4.4 (2026-10-22). At bun-v1.3.14, `docs/pm/cli/install.mdx:L393` says `--frozen-lockfile` needs a committed `bun.lock`. At bun-v1.4.4, L183: "If the project has a `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml` but no `bun.lock`, `--frozen-lockfile` migrates that lockfile in memory and installs from it. The install fails if the migrated lockfile does not match `package.json`"; and L753: an outdated Yarn v1 lockfile "is still migrated: Bun resolves the dependencies it has no entry for" | `gh api repos/oven-sh/bun/releases/latest`; `docs/pm/cli/install.mdx` at both tags, via `gh api`; Context7: oven-sh/bun bun-v1.4.2 | 2026-11-13 | Verified (session). R83 shows 1.3.14 checking only `bun.lock` |
| E95 | setup-uv v10.3.3 at `68559e99…`: `github-token`, "Used when downloading uv from GitHub releases", has `default: ${{ github.token }}` (`action.yml:L33-L37`) | `gh api` at that commit | 2026-11-13 | Verified (session) |
| E96 | setup-ruby v1.338.0 at `b3aaceae…`: an unset `ruby-version` takes the first of `.ruby-version`, `.tool-versions` and `mise.toml` that exists, reads `.tool-versions` with `/^ruby\s+(\S+)/` and `mise.toml` with `/^\s*ruby\s*=\s*['"]([^'"]+)['"]\s*(?:#.*)?$/`, and throws when the chosen file has no match (`index.js:L108-L136`). With a lockfile it sets `deployment true`, else runs `bundle lock` (`bundler.js:L181-L186`); it installs the Bundler that `BUNDLED WITH` names (L37-L46, L147) and runs `bundle install` with the action's own environment (L220). It downloads the Ruby build and untars it with no checksum (`ruby-builder.js:L70-L95`); its only hash keys the cache (`common.js:L175-L180`). `token` defaults to `github.token` on github.com (`action.yml:L47-L52`) | `gh api` at that commit | 2026-11-13 | Verified (session); SEC and OPS read the same lines |
| E97 | The runner's `hashFiles` runs `@actions/glob` from the workspace (`process.cwd()`) and skips files outside it (`src/Misc/expressionFunc/hashFiles/src/hashFiles.ts` at 8cfa104, `@actions/glob` ^0.7.0); `@actions/glob` 0.7.0 replaces a leading `.` segment with the cwd and rejects any other `.` or `..` segment (`packages/glob/src/internal-pattern.ts:L203-L225` at 0c3a9c3) | `gh api` on actions/runner and actions/toolkit | 2026-11-13 | Verified (session) |
| E98 | setup-bun v2.2.0 at `0c5077e5…`: `downloadBun` fetches the zip with `downloadTool`, extracts it and installs the binary with no hash check (`src/action.ts:L177-L193`) | `gh api` at that commit | 2026-11-13 | Verified (session); SEC read the same lines |
| E99 | railties v8.1.4.1: the default `test` task runs `rails test` (`test_unit/runner.rb:L50-L53`), which runs `test:prepare` first unless given exact test arguments (`commands/test/test_command.rb:L32,L72-L73`). jsbundling-rails v1.3.1, its newest release, adds `javascript:build` to `test:prepare`, with `javascript:install` before it, and picks bun, yarn, pnpm or npm by lockfile (`bun.lockb`, `yarn.lock`, `pnpm-lock.yaml`, `package-lock.json`), else by the first of them on `PATH` (`lib/tasks/jsbundling/build.rake:L1-L18,L49-L75`); its Bun installer sets the build script to `bun bun.config.js` (`lib/install/bun/install.rb:L21`) | `gh api` at those tags | 2026-11-13 | Verified (session); OPS read the same files |
| E100 | `ubuntu-latest` is Ubuntu 24.04, whose image lists Node.js 22.23.4, Npm 10.9.9 and Yarn 1.22.22, and neither Bun nor pnpm | actions/runner-images `README.md` and `images/ubuntu/Ubuntu2404-Readme.md` at 95e6f51, via `gh api` | 2026-11-13 | Verified (session) |
| E101 | The React Native community template's `template/Gemfile` lists cocoapods, activesupport, xcodeproj and other gems, but not rake, and `template/` has no Rakefile and no `.ruby-version` | react-native-community/template at 3c1a5b2, via `gh api` | 2026-11-13 | Verified (session); OPS saw the same |
| E102 | Claude Code loads "Relative-path plugins in a marketplace you added from a local path" in place: "Your edits to the source directory take effect at the next session start or `/reload-plugins`, and you don't need to increase the version", and such a plugin "loads its current source files at every session start, whatever its version string says". `marketplace add` with a local path makes a `directory` source that "Reads the directory in place" | https://code.claude.com/docs/en/plugins/loading (In-place and copied plugins; Versions and updates); https://code.claude.com/docs/en/plugins/cli-reference (plugin marketplace add) | 2026-11-13 | Verified (session) |
| E103 | Reusable workflows go in the repository's `.github/workflows` directory: "Subdirectories of the `workflows` directory are not supported." Of `jobs.<job_id>.uses`: "You cannot use contexts or expressions in this keyword." "Jobs using the matrix strategy can call a reusable workflow", the matrix varying its `with:` inputs | https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows | 2026-11-14 | Verified (session); the user read it first |
| E104 | "You can call a maximum of 50 unique reusable workflows from a single workflow file", nested ones included | https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations | 2026-11-14 | Verified (session); the user read it first |
| E105 | A called workflow that GitHub can't fetch fails the caller before any job runs. A reply on github/docs#35735 (2025-01-16), after which the issue was labelled "SME reviewed": "all reusable workflows are resolved when a run is queued which is before job-level `if` statements are evaluated". A run calling `hawkesj12/workflows/.github/workflows/audit.yml@5df64d38…` shows "Invalid workflow file" with "error parsing called workflow … : workflow was not found", and a local call of a file absent at the caller's commit got "failed to fetch workflow: workflow was not found" | https://github.com/github/docs/issues/35735; https://github.com/hawkesj12/job-radar/actions/runs/30666467303/workflow; https://stackoverflow.com/questions/73560884 | 2026-11-14 | Verified (session) from an issue reply, a run page and a Q&A. GitHub's docs don't describe it, the message doesn't say whether the file, the ref or access is missing, and no report isolates a missing file at a reachable 40-hex SHA |
| E106 | The allow list's `*` matches within a name: `space-org*/*` allows "all actions and reusable workflows in organizations that start with `space-org`", and `*/octocat**@*` those "in repositories that start with octocat"; `,` separates patterns | https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization | 2026-11-14 | Verified (session) |
| E107 | "Before the shell script is run, the expressions inside `${{ }}` are evaluated and then substituted with the resulting values" | https://docs.github.com/en/actions/concepts/security/script-injections | 2026-11-14 | Verified (session) |
| E108 | actionlint v1.7.12 is the latest release (2026-03-30). GitHub records `sha256:8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8` for `actionlint_1.7.12_linux_amd64.tar.gz`, whose root holds the `actionlint` binary. Its docs: `actionlint.yaml` or `actionlint.yml` "can be put in `.github` directory", and `self-hosted-runner.labels` lists extra runner labels; the known labels include `ubuntu-24.04` but not `ubuntu-26.04`; it "checks if `shellcheck` command exists in your system and uses it when it is found", on `run:` scripts in bash or sh; `-config-file PATH` and `-version` are flags | `gh api repos/rhysd/actionlint/releases/latest`; https://github.com/rhysd/actionlint/blob/main/docs/config.md; `docs/config.md`, `docs/checks.md` and `man/actionlint.1` in that archive, as the orchestrator downloaded it | 2026-11-14 | Verified (session); the orchestrator checked the digest against the release's `checksums.txt` |
| E109 | `GITHUB_PATH` "Prepends a directory to the system `PATH` variable and automatically makes it available to all subsequent actions in the current job" | https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands | 2026-11-14 | Verified (session) |
| E110 | ShellCheck directives "apply to the next shell command" (SC1123), and a comment after one needs its own `#`, as in `# shellcheck disable=SC2153 # variable not a misspelling` (SC1125). For an optional argument, SC2086's page gives "an unquoted expansion with an alternate value", `${debug:+"-x"}`. SC2155 flags `export foo="$(mycmd)"`, whose fix is `foo="$(mycmd)"` and then `export foo` | https://www.shellcheck.net/wiki/SC1123; https://www.shellcheck.net/wiki/SC1125; https://www.shellcheck.net/wiki/SC2086; https://www.shellcheck.net/wiki/SC2155 | 2026-11-14 | Verified (session) |
| E111 | mise v2026.11.0 (2026-11-03): `mise lock --platform linux-x64,macos-arm64` records, per platform, each tool's version, `url` and `checksum = "sha256:…"`; `mise install` updates an existing `mise.lock` but creates none unless the `lockfile` setting is true; `mise install --locked` "fails instead of resolving a version when the lockfile has no matching entry", and fails before downloading a recorded URL that has no checksum. The registry's `shellcheck`, `shfmt` and `actionlint` entries list `aqua:koalaman/shellcheck`, `aqua:mvdan/sh` and `aqua:rhysd/actionlint` first, and `actionlint`'s says `deprecated = "jactionlint is an actively maintained fork of actionlint with upstream fixes merged. …"` | Context7: jdx/mise v2026.11.0 (`docs/cli/lock.md`, `docs/dev-tools/mise-lock.md`, `docs/dev-tools/mise-lock-reference.md`, `docs/dev-tools/backends/packslip.md`, `release-notes/2026.10.3.md`); `registry/{shellcheck,shfmt,actionlint}.toml` at v2026.11.0, via `gh api` | 2026-11-14 | Verified (session); the user read the mise-lock and CI pages too |
| E112 | mise v2026.11.0: a `[tools]` key may be a backend identifier, quoted, as in `"aqua:BurntSushi/ripgrep" = "15"`, which installs the tool "from a specific backend". For aqua, `mise.lock` records "A URL per platform and a checksum where the release provides one or mise can compute it", and the lockfile keys a backend-qualified tool by its full name, as in `[[tools."pypi:black"]]` with `backend = "pypi:black"`. When the registry moves a tool to another backend, mise keeps the backend `mise.lock` records and warns | Context7: jdx/mise v2026.11.0 (`docs/dev-tools/backends/index.md`, `docs/dev-tools/backends/aqua.md`, `docs/dev-tools/mise-lock-reference.md`, `man/man1/mise.1`); `docs/dev-tools/mise-lock.md:L423` and `docs/dev-tools/mise-lock-reference.md:L209` at v2026.11.0, via `gh api` | 2026-11-14 | Verified (session) from the docs. mise wasn't run here, so the lock entry it writes for `"aqua:rhysd/actionlint"` wasn't seen |
| E113 | uv 0.13.4: "By default, dependency groups must be compatible with your project's `requires-python` range", and a group that needs another range sets `requires-python` in `[tool.uv.dependency-groups]` ("Group `requires-python`"). "Setting `tool.uv.package = false` will force a project package _not_ to be built and installed into the project environment" ("Project packaging") | Context7: astral-sh/uv v0.13.4 (https://github.com/astral-sh/uv/blob/0.13.4/docs/concepts/projects/dependencies.md; `docs/concepts/projects/config.md`) | 2026-11-15 | Verified (session) |
| E114 | setup-uv v10.3.3 at `68559e99…`: `version` is "The version of uv to install, e.g., `0.5.0`, `latest`, or `latest-known`. Defaults to the version in pyproject.toml or `latest`" (`action.yml:L6-L8`) | `gh api` at that commit | 2026-11-15 | Verified (session) |

## Appendix B — Implementation spec

### B1. File structure

The Phase column names where a change lands: `#115`; `add`, `migrate`, `delete`, `port` and `D7–D10`, the implementation PR's commit groups, in that order, the last for Appendix F's decisions of 2026-11-15; `Apps`, one PR per app repo after that merge; and `Later`. The delete commits leave `common.bash` and `tool-probe.sh` for the port commits [R8, R9, R26]. So that bats passes at every commit, a commit that deletes code also deletes or edits the tests that reference it: `sync-preflight.sh` goes with `common.bats:L63` [R49], the sync scripts with `helpers.bash:L33-L52` and the sync bats files [R26], the companion probes with `plugin_enabled` [R58], and, in the add commits, `check-requirements.sh` with `plugin-version.bats`'s two tests [R49]. The add and port rows name `scripts/_lib/…` paths as those commits created them; the `D7–D10` rows move them.

| Phase | Action | Path | Responsibility |
|---|---|---|---|
| #115 | Create | `.github/workflows/lang-ci-{go,js,python,ruby,rust}.yml` | One reusable workflow per language id, each with one job named by its id under a `timeout-minutes` input that defaults to 30; committed lockfiles enforced, pytest's exit 5 accepted, Bun set up for Ruby directories with a `package.json`, and Go's `GOWORK=off` for `go.work` non-members (Appendix C). They replace this branch's `lang-ci.yml`, which main never had [R89], so relative to main nothing is deleted |
| #115 | Create | `tests/fixtures/lang-ci/{js,python,ruby,rust}/` | Fixtures for the other four languages, next to the existing `go/`; the Ruby `Gemfile.lock` has a CHECKSUMS section with a `sha256=` entry (Appendix C) |
| #115 | Modify | `.github/workflows/ci.yml` | `lang-ci-fixture` becomes one `lang-ci-fixture-<id>` job per file. `lint` gains the B4 lang-ci step: exactly the five files, each with one job named by its id, no job-level `if:` and its fixture job, SHA pins, one top-level `contents: read`, no secrets or `pull_request_target`, the timeout, one SHA per action, the Rust `--workspace` flags and CHECKSUMS. It also installs actionlint 1.7.12 as it installs shellcheck and shfmt, checks all three versions against `mise.toml`, runs actionlint after the install, and gives the two `$SHELL_FILES` steps an SC2086 directive (Appendix C, B4) |
| #115 | Modify | `mise.toml` | `[tools]` gains `shellcheck = "0.11.0"`, `shfmt = "3.14.1"` and `"aqua:rhysd/actionlint" = "1.7.12"`. The header and comments stay for B3's `legacy-header` fix, which deletes only those [R90] (Appendix C) |
| #115 | Create | `mise.lock` | Generated by `mise lock --platform linux-x64,macos-arm64` [E111] |
| #115 | Create | `.github/actionlint.yaml` | Declares the `ubuntu-26.04` label, which actionlint 1.7.12 doesn't know [R91] (Appendix C) |
| #115 | Modify | `docs/CONTRIBUTING.md:L96-L100,L104-L115` | The `lint` bullets gain actionlint and the lang-ci checks. The local commands start with `mise install --locked`, so only PyYAML is left to install by hand and the CI-version note goes, and gain `actionlint` |
| #115 | Modify | `docs/rfcs/2026-11-09-scaffold-and-drift.md` | This amendment |
| add | Create | `scripts/bw` | POSIX-sh launcher (B2). Skills, hooks, tests and CI run every command through it |
| add | Create | `scripts/_lib/bw_main.py` | The single check-and-dispatch module the launcher runs (B2) |
| add | Create | `scripts/_lib/bw.py` | Shared functions (B2) |
| add | Create | `scripts/_lib/bw_scaffold.py` | Does all seeding (B2) |
| add | Create | `scripts/_lib/bw_drift.py` | Read-only drift check (B2) |
| add | Create | `scripts/_lib/bw_state_touch.py` | The only writer into `.bytewyrd/`, through a no-follow directory descriptor (B2) |
| add | Create | `scripts/_lib/bw_compact_reminder.py` | The SessionStart `compact` reminder, replacing the inline `stat` command at `hooks/hooks.json:L9` [R48] (B2) |
| add | Create | `templates/scaffold/{AGENTS.md,CLAUDE.md,PULL_REQUEST_TEMPLATE.md,ci-noop.yml}.tpl` | Seed templates (Appendix C). The PR template is copied from `templates/PULL_REQUEST_TEMPLATE.md.tpl` |
| add | Create | `templates/scaffold/ci-caller.yml.tpl` | The language caller: one job block, repeated per component and pinned to #115's merge commit (Appendix C) |
| add | Create | `skills/scaffold/SKILL.md`, `skills/drift/SKILL.md` | Thin wrappers that run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" <name>` and print its output verbatim (Appendix C) |
| add | Create | `skills/rfc-process/SKILL.md`, `skills/rfc-process/references/rfc-process.md` | Copy of root `rfc-process.md` with L3 and L196-L219 rewritten: no per-repo copy, opt-in through `docs/rfcs/`, and the `/sync` row replaced by scaffold and drift |
| add | Create | `skills/best-practices/SKILL.md`, `skills/best-practices/references/{general,rust,js-ts,python,go,svelte,ruby,rails,k8s-cue,terraform}.md` | `BEST_PRACTICES.md.tpl` split by H2, with `general.md` holding `## Pitfall` through `## Error Handling` and the `<!--lang:*-->` lines dropped. `SKILL.md` carries template L3-L27, with its L21 row repointed to `references/` |
| add | Create | `hooks/always-on-rules.json` | The rules as `additionalContext` (Appendix C) |
| add | Create | `.github/workflows/scaffold-noop-fixture.yml` | Committed output of the no-op caller (AC-8) |
| add | Create | `tests/scripts/{bw,hooks,state-touch}.bats`; `tests/py/test_bw.py`; `tests/e2e/test_consumer_sim.py`; `tests/fixtures/legacy-0.2/<case>/` | Tests (B4, B5): bats for the launcher, hook and state-touch contracts; pytest for `scripts/_lib/` and consumer-sim, which covers scaffold and drift end to end. There is one legacy case per `legacy-*` code |
| add | Modify | `hooks/hooks.json` | Today it has two entries [R11]: add the rules entry, remove check-requirements, re-add the SubagentStop entry that #116 removed, with its `echo` reminder plus `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" state-touch last-feature-engineer-stop \|\| true`, and route the `compact` reminder through the launcher (Appendix C) |
| add | Modify | `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | `dependencies` on `github`, `context7` and `code-review` from `claude-plugins-official` [R10], versioned where the dependency publishes versions, and `allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]` |
| add | Modify | `.github/workflows/ci.yml` | Extends main's workflow (Appendix C). `lint` drops #115's file-set line, which `test_bw.py` replaces (B4) |
| add | Modify | `.gitignore` | Add `__pycache__/`: pytest and direct runs write bytecode, and a dirty tree makes the migrate commits' `scaffold --apply` exit 3 [R54] |
| add | Modify | `tests/scripts/plugin-version.bats` | Delete its two `check-requirements` tests [R49] |
| add | Modify | `skills/best-practices-extract/SKILL.md` | L273 becomes `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" state-touch precompact-extraction-done` |
| add | Modify | `skills/docs-review/SKILL.md` | L54 becomes `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" state-touch --rm last-feature-engineer-stop` |
| add | Modify | `README.md:L9-L10`, `docs/guide/installation.md:L6-L7` | The install and upgrade sequence from Appendix C, with explicit dependency installs [R57], the optional `#<ref>` pin, and Python 3.11 or newer as a prerequisite |
| add | Modify | `docs/rfc-braindump.md` | Delete the L15 entry "Audit skills for deterministic-script consolidation; settle Python dependency policy" [R50]: this RFC's Language policy settles it |
| add | Modify | Rule M1 files: `agents/{ai-engineer,claude-agent-author,code-reviewer,docs-agent,documentation-writer,feature-engineer,llm-architect,mcp-developer,penetration-tester,refactoring-specialist,rfc-architect,security-engineer}.md`, `skills/{docs-review,rfc-new,rfc-summary}/SKILL.md`, `docs/agent-audit-criteria.md` | B3 |
| add | Modify | Rule M3 files: `skills/rfc-implement/SKILL.md:L20`, `agents/claude-agent-author.md:L47,L90,L251`, `agents/rfc-architect.md:L130-L131` | B3 |
| add | Modify | Rule M4 files: `skills/{best-practices-extract,best-practices-record,docs-review,refactor,rfc-braindump,rfc-consensus-review,rfc-implement,rfc-new,rfc-read-feedback}/SKILL.md` | B3 |
| add | Modify | Rule M5 files: `skills/{best-practices-extract,refactor,rfc-approve,rfc-braindump,rfc-consensus-review,rfc-drop,rfc-implement,rfc-new,rfc-read-feedback,rfc-summary}/SKILL.md` | B3 |
| add | Modify | `CLAUDE.md`, `docs/guide/reference/hooks.md`, `docs/guide/concepts.md`, `CHANGELOG.md` | Hook docs, the Python requirement and the changelog. The SubagentStop notes that say it is "Temporarily removed" go, as it is back: `docs/guide/reference/hooks.md:L9`, `docs/guide/concepts.md:L47` and the parenthesis at `CLAUDE.md:L170` [R77]. `docs/guide/**` changes go through `/docs-review` |
| add | Delete | `scripts/check-requirements.sh` | Superseded: Exa and Firefox are MCP servers [R10] that degrade at point of use [R21], and scaffold and drift exit 1 without git |
| migrate | Create/Modify/Delete | This repo's legacy artifacts [R25]; create `AGENTS.md` | The migration procedure (B4) |
| delete | Delete | `skills/sync/SKILL.md`; `scripts/sync-{apply-batch,canonical,classify-all,classify,compute-template-vars,detect-languages,find-plugin-root,item-parser,marker-read,owned-regions-apply,preflight,render-template,rfc-process-check,run,sidecar-migrate,summary,unified-diff,write-header}.sh` | `/sync` and its 18 scripts |
| delete | Delete | `scripts/_lib/{chunks,detect-languages,plugin}.bash`, `scripts/build-manifest.sh`, `hooks/pre-commit/manifest-check.sh`, `bootstrap-manifest.json`, `rfc-process.md`, `templates/*.tpl` (the 11 0.2.x templates; `templates/scaffold/` stays), `tests/scripts/sync-*.bats` (17), `tests/scripts/bootstrap-manifest.bats`, `tests/scripts/plugin-version.bats` | Sync-only code and tests |
| delete | Delete | `scripts/rfc-legacy-detect.sh`, `tests/scripts/rfc-legacy-detect.bats` | Uncalled [R58] |
| delete | Modify | `scripts/tool-probe.sh`, `tests/scripts/tool-probe.bats`, `skills/rfc-implement/SKILL.md:L14`, `skills/refactor/SKILL.md:L15` | Remove the `github-mcp`, `context7-mcp` and `code-review-mcp` probes and the two calls to them: with hard dependencies they can never report "missing" while bytewyrd loads [R58, R31] |
| delete | Modify | `scripts/_lib/common.bash` (delete L61-L95), `tests/scripts/helpers.bash` (delete L33-L52), `tests/scripts/common.bats` | Remove `compute_upstream_key` [R26] and the now-unused `plugin_enabled` [R58] with their tests, and the `sync-preflight.sh` guard assertion at `common.bats:L63` [R49] |
| delete | Modify | `.github/workflows/ci.yml` | `lint` drops the `bootstrap-manifest.json` parse and the `build-manifest.sh --check` step [R49] |
| delete | Modify | `.claude/skills/best-practices-sync/SKILL.md` | Writes to `skills/best-practices/references/<stack>.md`; the marker step is deleted |
| delete | Modify | Rule M2 files, the 27 of the 32 files in [R13] that describe current behaviour: `agents/{api-designer,docs-agent,documentation-writer,feature-engineer,frontend-developer}.md`, `skills/best-practices-extract/TRIAGE-AND-LIFT.md`, `skills/{best-practices-record,docs-review,rfc-summary}/SKILL.md`, `.claude/skills/best-practices-sync/SKILL.md`, `.github/scripts/check-links.py`, `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md`, `docs/project-brief.md`, `docs/guide/{concepts,contributing,index,installation}.md`, `docs/guide/how-to/{best-practices,docs-review,rfc-process}.md`, `docs/guide/reference/{hooks,skills}.md`, `docs/guide/tutorials/getting-started.md` | B3 (M2, and M1 where a file names `docs/rfc-process.md` [R16]). `CLAUDE.md` also drops "## Maintaining the bootstrap manifest". The other five are history (`CHANGELOG.md`, `docs/rfc-braindump.md`), a migrate fix (`mise.toml`) or delete and port edits (`common.bash`, `common.bats`) |
| port | Modify | `scripts/bw`, `scripts/rfc-summary.sh`, `tests/scripts/helpers.bash`, `tests/scripts/{rfc-braindump-append,rfc-braindump-list,rfc-braindump-remove,rfc-feedback-list,rfc-frontmatter,rfc-resolve,rfc-set-status,rfc-summary,tool-probe,rfc-skill-errors,common}.bats`, `skills/{best-practices-extract,refactor,rfc-approve,rfc-braindump,rfc-consensus-review,rfc-drop,rfc-implement,rfc-new,rfc-read-feedback,rfc-summary}/SKILL.md` | Harness commit [R51]. The launcher runs `bash <name>.sh` for a class-B name whose module doesn't exist yet. `rfc-summary.sh` runs `sh "$_LIB_DIR/bw" rfc-frontmatter` instead of `rfc-frontmatter.sh` (L31, L46) [R59]. `helpers.bash` gains `bw() { sh "$SCRIPT_ROOT/scripts/bw" "$@"; }`; each `bash "$SCRIPT"`, plus `rfc-set-status.bats`'s direct `rfc-frontmatter.sh` calls and `rfc-frontmatter.bats`'s direct `rfc-set-status.sh` call (L89), becomes `bw <name>`, and the 25 `scripts/<name>.sh` lines left in surviving tests [R61], `common.bats`'s `rfc-summary.sh` guard assertion (L66) among them, are updated or removed. `rfc-frontmatter.bats` also loses the two assertions of #116's test `a value that is not a clean double-quoted scalar still has its quotes dropped` (L111-L112), which pin bash's quote dropping; the test is renamed for what it still checks, and `test_frontmatter.py` pins the YAML results instead [R78] (U1, Appendix D). Skills' `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"` becomes `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" <name>`. `rfc-skill-errors.bats` matches the new snippet, and its stand-in becomes a `scripts/bw` that fails like the launcher |
| port | Create | `scripts/_vendor/yaml/`, `scripts/_vendor/PyYAML-LICENSE`, `scripts/_vendor/PyYAML-6.0.3.sha256`, `tests/py/test_vendor.py`, `tests/py/test_frontmatter.py` | Vendor commit: PyYAML 6.0.3, its sdist hash, and the loader and conversion tests (B2) [E54, E69] |
| port | Modify | `THIRD_PARTY_NOTICES.md` | Vendor commit: a `## PyYAML` section in the file's format. **Source:** `https://github.com/yaml/pyyaml`, tag `6.0.3`. **License:** MIT (full text below). **Used in:** `scripts/_vendor/yaml/`. Then one line saying the copy is unmodified and pure Python, and the license text. The intro's "the third-party project listed below" becomes "the third-party projects listed below" [R49] |
| port | Create | `scripts/_lib/bw_{rfc_braindump_append,rfc_braindump_list,rfc_braindump_remove,rfc_feedback_list,rfc_frontmatter,rfc_resolve,rfc_set_status,rfc_summary,tool_probe}.py` | Port commits, one per script, each keeping arguments, output and exit codes (B2) |
| port | Delete | `scripts/{rfc-braindump-append,rfc-braindump-list,rfc-braindump-remove,rfc-feedback-list,rfc-frontmatter,rfc-resolve,rfc-set-status,rfc-summary,tool-probe}.sh` | Each in its port commit, with its jq calls and any `require_bash_major` guard [R49] |
| port | Delete | `scripts/_lib/common.bash`, `tests/scripts/common.bats` | Retire commit. `bw.py` holds the ported emitters, and `tests/py/test_bw.py` covers them |
| port | Modify | `scripts/bw`, Rule M4 files, `.github/workflows/ci.yml` | Retire commit: the launcher loses its bash fallback, `compatibility:` loses "bash >= 4" (B3), and `lint`'s `SHELL_FILES` keeps `scripts/bw`, `tests/run.sh` and `tests/scripts/helpers.bash`. Skills keep parsing script output with jq [R51] |
| D7–D10 | Modify | `docs/rfcs/2026-11-09-scaffold-and-drift.md` | This amendment, which returns the RFC to Draft |
| D7–D10 | Create | `scripts/bytewyrd/{__init__,__main__}.py`, `scripts/bytewyrd/{cli,git,fs,detect,seed,frontmatter,jsonout}.py`, `scripts/bytewyrd/commands/__init__.py` | The package (D7): the bootstrap, which replaces `bw_main.py`, and the seven shared modules, which split `bw.py` (B2) |
| D7–D10 | Move | `scripts/_lib/bw_<name>.py` to `scripts/bytewyrd/commands/<name>.py`, for `compact_reminder`, `drift`, `rfc_braindump_append`, `rfc_braindump_list`, `rfc_braindump_remove`, `rfc_feedback_list`, `rfc_frontmatter`, `rfc_resolve`, `rfc_set_status`, `rfc_summary`, `scaffold`, `state_touch` and `tool_probe` | With `git mv`, then imports from the shared modules (B2) |
| D7–D10 | Modify | `scripts/bw` | Step 4 runs `bytewyrd/__main__.py` (B2) |
| D7–D10 | Delete | `scripts/_lib/` | `bw_main.py` and `bw.py`, once the package holds their code |
| D7–D10 | Create | `pyproject.toml`, `uv.lock` | Development only (D8): `[project]` with `name = "claude-bytewyrd-dev"`, `version = "0"` and `requires-python = ">=3.11"`; `[tool.uv] package = false`; one `dev` group that pins pytest, PyYAML, ruff, mypy and types-PyYAML; and the pytest, ruff and mypy settings, under which ruff skips `scripts/_vendor/`. Only `uv lock` writes `uv.lock` [R92]. The `[project]` table makes detection see a root `python` component here, which changes neither drift's nor scaffold's result [R94] |
| D7–D10 | Modify | `.github/workflows/ci.yml` | `lint`, `test`, `compat` and `history` install uv at `UV_VERSION` with `astral-sh/setup-uv` at `68559e99…`, the SHA `lang-ci-python.yml` uses [R44, E114], then run `uv sync --locked` and their commands through `uv run --no-sync`; the pip installs, `PYYAML_VERSION` and `PYTEST_VERSION` go. `lint` gains ruff and mypy steps, runs `vendor-pyyaml.py --check` in place of the `.sha256` check, checks `UV_VERSION` against `mise.toml` with the other tools, and runs the links step last, so a broken link no longer skips the steps after it (B4) |
| D7–D10 | Modify | `mise.toml`, `mise.lock` | `[tools]` gains `"aqua:astral-sh/uv" = "0.13.4"` [R95], and `mise lock --platform linux-x64,macos-arm64` regenerates the lock [E111] |
| D7–D10 | Create | `.github/scripts/vendor-pyyaml.py` | Standard library only (D9). It rebuilds `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` from the sdist that `uv.lock` pins, or, with `--check`, compares them both ways (B2) |
| D7–D10 | Delete | `scripts/_vendor/PyYAML-6.0.3.sha256` | `uv.lock` records the same hash [R93] |
| D7–D10 | Modify | `templates/scaffold/AGENTS.md.tpl`, `templates/scaffold/ci-noop.yml.tpl`, `.github/workflows/scaffold-noop-fixture.yml` | D10 (Appendix C): Project facts under `@@any@@`, with the new languages line and no `@@none@@` line. The no-op step becomes `run: exit 0` in the template and in the fixture |
| D7–D10 | Modify | `AGENTS.md` | This repo's: line 10, which says scaffold found no language, goes, and line 1 becomes the stamp that drift's `template-changed` fix line prints |
| D7–D10 | Modify | `tests/py/{test_bw,test_frontmatter,test_json_helpers,test_vendor}.py`, `tests/e2e/test_consumer_sim.py`, `tests/scripts/bw.bats` | Imports and paths follow the package, and the render and consumer-sim cases follow D10. `bw.bats`, the only bats change, takes the bootstrap's path and copies the package; its commit is not a port commit (AC-22). `test_vendor.py` drops the `.sha256` test and reads PyYAML's version from `uv.lock` (B2, B4, B5) |
| D7–D10 | Modify | `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `CHANGELOG.md` | The package, the uv setup and commands, and the PyYAML update steps (B2). Any `docs/guide/**` or `README.md` change goes through `/docs-review` |
| Apps | Create/Modify/Delete | Each app repo's legacy artifacts; create `AGENTS.md` | The migration procedure (B4), one PR per repo |
| Later | Modify | `skills/best-practices-extract/SKILL.md` | Removes the sentinel step and its PreCompact text, once drift shows no `legacy-settings-hooks` in all four known repos |

`.claude/skills/**` may be write-protected in sandboxed agent sessions. If so, the human applies those edits. This repo's `.claude/settings.json` needs none: #116 removed its hooks [R25].

### B2. Script contracts

**`scripts/bw NAME [ARGS…]`**, the launcher, is POSIX sh:

1. It finds its own directory from `$0` and checks NAME with `case`. Class A is `scaffold`, `drift`, `state-touch` and `compact-reminder`; class B is the JSON helpers that the port commits port (`rfc-*` and `tool-probe`). Any other NAME prints `bw: unknown command: NAME` and exits 1. From the harness commit until the retire commit, a class-B NAME whose `scripts/_lib/bw_<name>.py` (hyphens as underscores) doesn't exist yet runs `exec bash "<dir>/NAME.sh" "$@"`.
2. It picks an interpreter [E62]: `$BYTEWYRD_PYTHON` if set and it reports 3.11 or newer; else the first of `python3.15`, `python3.14`, `python3.13`, `python3.12` and `python3.11` on `PATH`, trusted by name; else `python3` if it reports 3.11 or newer. A report is one `-I -S -c 'import sys; sys.exit(sys.version_info < (3, 11))'` run, so most hosts start one interpreter per command. 3.15 has shipped [E68]; the list gains a name when a new CPython minor ships, and `$BYTEWYRD_PYTHON` covers it until then.
3. If none qualifies, `state-touch precompact-extraction-done` falls back to plain sh. It refuses if `.bytewyrd` or the sentinel is a symlink; otherwise it runs `mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done` and exits 0. It writes no `.gitignore`; repos still on 0.2.x have the seeded one [R20]. Every other class-A command prints `bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)` to stderr and exits 1. A class-B command prints `{"error":"bytewyrd: needs Python 3.11 or newer …"}` to stderr and exits 2, as `require_bash_major` does; exit 1 already means "missing" or "not found" for these helpers [R49, R62].
4. Otherwise it runs `exec "$py" -I -S -B "$dir/bytewyrd/__main__.py" NAME "$@"`. `-I` ignores `PYTHON*` variables and the user site directory, `-S` skips `site`, so a venv's `.pth` files never run, and `-B` writes no bytecode into the plugin [E55, E66, R54].

**`scripts/bytewyrd/__main__.py`**, the bootstrap, is the single check-and-dispatch module. It avoids newer syntax and annotations, so an older interpreter that runs it directly still reaches its version check [R52], which applies the launcher's per-class exit contract; `mypy --strict` checks the rest of the package. Otherwise it puts `scripts` and `scripts/_vendor`, found from `__file__`, at the front of `sys.path`, imports `bytewyrd.commands.<name>` (NAME with hyphens as underscores) and exits with its `main(argv)`. Code that needs 3.11 lives in the imported modules.

The plugin root is the parent of `scripts/`, found from `__file__`. No script reads `CLAUDE_PLUGIN_ROOT`.

**The shared modules** in `scripts/bytewyrd/` never exit on their own; commands decide exit codes. Each command is `scripts/bytewyrd/commands/<name>.py`, whose `main(argv)` returns the exit code.

| Module | Holds |
|---|---|
| `cli` | `BwError`, `Parser`, `quote` and `describe` |
| `git` | `root`, `project_name`, `tracked`, `blob` and `dirty` |
| `fs` | `exists`, `find_entry`, `symlinked_dir`, `create` and `read_text`, plus `split_lines` and `pwd`, which the JSON helpers use |
| `detect` | `detect`, the language ids, `attr_line`, and the SKIPPED reasons with their fix lines |
| `seed` | The targets and their templates, `render`, `file_hash`, `stamp`, `read_stamp`, `plugin_sha`, `pr_template`, `workflow_exists` and `lacks_import` |
| `frontmatter` | `load_frontmatter` and `FrontmatterLoader`. It is the only module that imports `yaml`, at module level |
| `jsonout` | jq-compatible output (`jq_string`, `jq_dumps` and `emit`), the JSON helpers' `json_main`, and the emitters `emit_error`, `emit_available`, `emit_missing` and `emit_unauth` |

Constants and types go with the functions that use them, such as `LANGUAGES` in `detect` and `TARGETS` in `seed`. Helpers that the table below doesn't list keep the behaviour they had in `bw.py`.

| Function | Contract |
|---|---|
| `root()` | Returns `git rev-parse --show-toplevel` [E32]. Raises `BwError` without git or outside a work tree |
| `project_name(root)` | The basename of the parent of `git rev-parse --git-common-dir`, resolved against ROOT, else the basename of ROOT [R27] |
| `detect(root)` | Returns COMPS and SKIPPED (Detection, below). It replaces the 272-line `detect-languages.bash` [R28] and the root-only `languages(root)` of earlier drafts [R45, R67] |
| `file_hash(path)` | `hashlib.sha256` of the bytes with every `\r` removed; returns the first 12 hex digits |
| `plugin_sha(plugin_dir)` | If the directory name matches `^[0-9a-f]{12,40}$`, its first 12 characters [E42]. Otherwise, if `git -C DIR rev-parse --show-toplevel` equals DIR, the first 12 of HEAD. Otherwise `unknown` |
| `render(tpl, comps, name)` | Strips CRs. First, the lines starting with `@@job@@ ` (tag removed) form one block, which takes the place of the first of them, repeated once per component in COMPS order with `@@job_id@@`, `@@job_language@@` and `@@job_directory@@` replaced; `job` is not a language id. Then a line starting with `@@<id>@@ ` (tag removed) stays only when a component has language `<id>`, and a line starting with `@@any@@ ` only when COMPS is not empty. A line that is only such a tag follows the same rule and renders as an empty line. Replaces `@@project_name@@`, and `@@languages@@` with the first ten components joined by `, ` (`<id>` at the root, `<id> in <dir>/` elsewhere), then `, and N more; see .github/workflows/ci.yml` when there are more. Every replacement uses `str.replace`, so values are literal. Raises `BwError` if any `@@` is left; if a `@@job@@` block meets an empty COMPS, so it never renders a zero-job caller [R5]; and if `@@languages@@` is left with an empty COMPS, so it never prints a languages line without languages |
| `stamp(kind, tpl, digest, sha)` | `md`: `<!-- bytewyrd:scaffold v1 tpl=TPL:HASH plugin=SHA -->` (an HTML comment, so it is stripped from CLAUDE.md context [E27]); `yml`: `# bytewyrd:scaffold v1 tpl=TPL:HASH plugin=SHA` |
| `read_stamp(path)` | Reads line 1 with CRs stripped and matches it against the regex below. Returns `(tpl, hash, sha)`; `None` if the line has no `bytewyrd:scaffold`; `BAD` if it has one that doesn't parse |
| `exists(dir, name)` | True when `os.path.lexists(DIR/NAME)` (true for dangling symlinks [R52]), or when an entry of DIR equals NAME case-insensitively |
| `pr_template(root)` | For each of `.`, `docs` and `.github`, the first entry whose lowercased name is `pull_request_template` (a directory) or starts with `pull_request_template.` [E47]. `None` if there is none |
| `symlinked_dir(root, rel)` | The first existing component of REL's parent chain under ROOT for which `os.path.islink` is true; `None` if there is none |
| `create(path, text)` | `open(path, "x", encoding="utf-8", newline="\n")`. Exclusive create raises `FileExistsError` for any existing path, symlinks included, and writes nothing there [R52] |
| `quote(s)` | S itself when it is non-empty and every character is in `[A-Za-z0-9._/-]`. Otherwise git's C-style quoting of `os.fsencode(S)` [E90]: `"`, each byte, `"`, with `\a`, `\b`, `\t`, `\n`, `\v`, `\f`, `\r`, `\"` and `\\` for those bytes and `\ooo` octal for any other byte below 0x20 or above 0x7e. The result is ASCII, so printing it can't raise `UnicodeEncodeError` [R80]. scaffold and drift pass every repo-derived string they print through it: ROOT, paths, directories, refs and `uses:` values |
| `attr_line(path)` | `quote("/" + P) + " -bytewyrd-ci"`, where P is PATH with each `\`, `*`, `?` and `[` escaped by a backslash: a `.gitattributes` line whose root-anchored pattern matches only PATH [R79, E90] |
| `tracked(root)` | The index entries that `git -C ROOT ls-files -s -z` lists [E37], as `(mode, oid, stage, path)` with the path decoded by `os.fsdecode` [R80] |
| `blob(root, entry)` | The bytes of a stage-0 entry of mode 100644 or 100755 whose blob `git cat-file -s` sizes at 1 MiB or less, read with `git cat-file blob`. `None` for any other entry, such as a 120000 symlink or a 160000 gitlink, for a bigger blob, and when git fails |
| `Parser` | An `argparse.ArgumentParser` whose `error()` prints the usage line and exits 1, because argparse's default of 2 [E56] would read as drift |
| `load_frontmatter(path)` | Added by the port commits: the only YAML entry point (below) |
| `emit_error`, `emit_available`, `emit_missing`, `emit_unauth` | Added by the port commits: ports of the `common.bash` functions of the same names, with the same JSON [R51] |

```
^(<!-- |# )bytewyrd:scaffold v1 tpl=([A-Za-z0-9._-]+):([0-9a-f]{12}) plugin=([0-9a-f]{12}|unknown)( -->)?$
```

**Detection.** `detect(root)` feeds both scaffold and drift. A component is a `(language, directory, job_id, manifests)` tuple, and the language ids are `go`, `js`, `python`, `ruby` and `rust`.

1. **Manifests.** `tracked(root)` lists the index; a submodule is one gitlink entry, so its files never count [R73], and an unmerged path counts once. A path whose basename is `go.mod`, `package.json`, `pyproject.toml`, `setup.py`, `Cargo.toml` or `Gemfile` is a manifest of `go`, `js`, `python`, `python`, `rust` or `ruby`, except a `pyproject.toml` with neither a `[project]` nor a `[tool.uv.workspace]` table [R82]. Manifests are grouped by (language, directory), the directory being the one that holds them (`.` at the root), so `pyproject.toml` and `setup.py` in one directory make one group.
2. **Overrides.** One `git -C ROOT check-attr --cached --stdin -z bytewyrd-ci` run reads every manifest's attribute from the committed `.gitattributes` files; `.git/info/attributes` and `core.attributesFile` still apply [E82, E90, R79]. `unset`, from a line such as `/services/legacy/** -bytewyrd-ci`, moves the manifest to SKIPPED as opted out, and so does a value, such as `bytewyrd-ci=false`, with its own reason. `set`, from a line such as `/services/billing/api/go.mod bytewyrd-ci`, makes its group skip steps 3 and 4. `unspecified` applies them. A group with no manifest left drops out. A pattern must match the file: `dir/` doesn't, `dir/**` does [R73].
3. **Default scope.** The root counts, and so does a directory of at most two segments in which no segment starts with `.` or `_` or equals, ignoring case, `node_modules`, `vendor`, `third_party`, `testdata`, `test`, `tests`, `spec`, `e2e`, `fixture`, `fixtures`, `example`, `examples`, `sample`, `samples`, `template` or `templates`. Go's own `./...` skips `.`- and `_`-prefixed names, `vendor` and `testdata` [R70]; the other names hold vendored code, fixtures, examples and test apps, such as this repo's `tests/fixtures/lang-ci/go/go.mod`, which `/sync`'s plain `find` counts [R68, R74].
4. **Root workspaces.** When a language's root manifest yields a component, its nested manifests that the root job covers are dropped (table below).
5. **Validation.** A directory other than `.` must satisfy `re.fullmatch` with `[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*` (a `^…$` match would accept `web\n` [R80, E92]) and be at most 64 characters, which rules out `..`, a leading `-`, spaces, quotes, control characters and YAML syntax. The job id is the language id at the root, else the language id, `-`, and the lowercased directory with each `/` and `.` turned into `-` (`apps/web` gives `js-apps-web`), which meets GitHub's `jobs.<job_id>` rule [E70]. A `ruby` group needs a tracked `rakefile`, `Rakefile`, `rakefile.rb` or `Rakefile.rb` in its directory, and a `python` group a counted `pyproject.toml` [R82, R84]. A group that fails any of these, or whose job id a group in another directory already holds (in sorted order), moves each of its manifests to SKIPPED.
6. **Result.** COMPS is sorted by language, then directory. SKIPPED holds `(manifest path, reason)` pairs, in path order.

| Language | Root workspace | Nested manifests dropped | Why the root job covers them |
|---|---|---|---|
| `js` | `package.json` has `workspaces`: an array, or an object with a `packages` array | Directories that match a pattern and no `!` pattern | Root `bun install` installs every workspace, and `bun test` searches the whole tree [E78, R66] |
| `python` | `pyproject.toml` has `[tool.uv.workspace]` | Directories that match `members` and no `exclude` | `uv sync --all-packages` installs every member, `uv run` keeps them, and pytest collects from the root [E80, E81, R72] |
| `rust` | `Cargo.toml` has `[workspace]` | Every nested crate except one under an `exclude` path (a prefix, not a glob) or with its own `[workspace]` table | `--workspace` builds every member, path dependencies included [E79]; any other nested crate fails in place with exit 101 [R71] |
| `go`, `ruby` | None | None | A root `./...` never includes another module, even under `go.work` [R70], and a root `rake` runs the root's own suite [E83] |

A pattern matches a directory when, after a leading `./` and a trailing `/` are stripped, their `/`-separated segments match one for one under `fnmatch.fnmatchcase`, where a `**` segment matches any number of segments; whole-path `fnmatch` would let `*` cross a `/` [R76]. Root discovery is wider than membership: root `bun test` and `pytest` also run the tests of nested non-member packages [R66, E81], so those tests run twice. A repo whose root narrows discovery (pytest `testpaths`, bunfig `[test] root` [E78]) and wants a job per member sets `bytewyrd-ci` on the member manifests.

**Reading.** Detection reads repo files only through `blob()`, from the index. `package.json` is parsed with `json`, `pyproject.toml` and `Cargo.toml` with `tomllib` [E51], and the other files line by line. A file that `blob()` doesn't return, or whose decoding or parsing raises `OSError`, `ValueError` (decode errors and the int-digits limit included), `UnicodeDecodeError` or `RecursionError` [R80], declares nothing: no workspace, no table, no Ruby version and no platforms. So does a wrong shape: `workspaces` must be a `list[str]` or `{packages: list[str]}`, and `members` and `exclude` a `list[str]`.

**SKIPPED reasons.** `<id>` and `<dir>` go through `quote()`, and `<line>` is the manifest's `attr_line()`:

| Reason, as printed | Fix line |
|---|---|
| `directory name not allowed (letters, digits, '.', '_' and '-', at most 64 characters)` | `rename the directory, or mark the manifest: <line>` |
| `job id <id> is taken by <dir>` | `rename the directory, or mark the manifest: <line>` |
| `no Rakefile (the ruby job runs bundle exec rake)` | `add a Rakefile whose default task runs the tests, or mark the manifest: <line>` |
| `no pyproject.toml with [project] (the python job runs uv sync)` | `add a pyproject.toml with a [project] table, or mark the manifest: <line>` |
| `bytewyrd-ci has a value; use bytewyrd-ci or -bytewyrd-ci` | `set bytewyrd-ci or -bytewyrd-ci for this path in .gitattributes` |
| `opted out by -bytewyrd-ci` | None |

**`scaffold [--apply] [--allow-dirty]`**

The targets, in order:

| Target | Kind | Template | Skipped when |
|---|---|---|---|
| `AGENTS.md` | md | `AGENTS.md` | `exists` |
| `CLAUDE.md` | md | `CLAUDE.md` | `exists` |
| `.github/PULL_REQUEST_TEMPLATE.md` | md | `PULL_REQUEST_TEMPLATE.md` | `exists`, or `pr_template` finds one |
| `.github/workflows/ci.yml` | yml | `ci-noop.yml` when COMPS is empty, else `ci-caller.yml` | `exists`, or `.github/workflows/` holds any `*.yml` or `*.yaml` |

Behaviour:

1. Preflight writes nothing. It resolves ROOT, so a missing git or a missing work tree exits 1. For every target to be created, it runs `symlinked_dir`; a hit exits 1.
2. With `--apply`, a dirty tree (`git status --porcelain` prints anything [E33]) exits 3.
3. Each write runs `os.makedirs(parent, exist_ok=True)`, then `create(path, stamp + "\n" + rendered)`.
4. `main()` catches every exception. It first deletes the files this run created, then exits 1 with the failure lines below. Exceptions that escape anyway, including syntax errors, also exit 1 [R52].

Output goes to stdout unless noted; columns are separated by two spaces, and every repo-derived string goes through `quote()`. The four kinds of CI note, for SKIPPED entries, Ruby, pnpm and pytest, are printed whenever scaffold creates `ci.yml`, or would, from either template. A repo whose manifests are all skipped therefore learns why it got the no-op CI, and a repo that keeps its own CI gets none:

| Situation | Output | Exit |
|---|---|---|
| Header | `bytewyrd scaffold: <ROOT>` | — |
| Each target | `would create  <path>`, `created  <path>`, `skip  <path>  (exists; scaffold never overwrites)`, `skip  <path>  (pull request template found: <found>)` or `skip  <path>  (another workflow exists)` | — |
| CLAUDE.md lacks `@AGENTS.md` | `note: CLAUDE.md has no '@AGENTS.md' line; Claude Code will not read AGENTS.md until you add one` | — |
| Each SKIPPED entry | `note: no CI job for <path>: <reason>` | — |
| A `ruby` component for which setup-ruby finds no version: the first of `.ruby-version`, `.tool-versions` and `mise.toml` in its directory is absent, empty, or has no line matching setup-ruby's pattern for it [E96] | `note: <dir> gives setup-ruby no Ruby version; add .ruby-version, or a ruby line to .tool-versions or mise.toml` | — |
| A `ruby` component whose `Gemfile.lock` has a PLATFORMS section listing neither `ruby` nor `x86_64-linux` [R84] | `note: <lockfile> lacks the CI runner's platform; run bundle lock --add-platform x86_64-linux` | — |
| A `ruby` component whose directory has `pnpm-lock.yaml` [E99, E100] | `note: <dir> has pnpm-lock.yaml, and the ruby CI job has no pnpm; a Rails test:prepare that builds JavaScript fails there` | — |
| A `python` component whose `pyproject.toml` lists pytest in no `[dependency-groups]` group (an entry's name, before any version or extra, is `pytest` ignoring case) | `note: <pyproject> lists pytest in no dependency group; the python CI job runs uv run pytest` | — |
| Dry run with a dirty tree | `note: working tree is dirty; --apply will refuse without --allow-dirty` | 0 |
| Footer | `dry run: N to create, M skipped; re-run with --apply to write`, or `applied: N created, M skipped` | 0 |
| Dirty tree with `--apply` (stderr) | `scaffold: working tree is dirty; commit first or pass --allow-dirty` | 3 |
| Symlinked directory (stderr) | `scaffold: <dir> is a symlink; refusing to write through it` | 1 |
| Any other failure (stderr) | `scaffold: <reason>`, then `scaffold: failed; removed: <paths>` or `scaffold: failed; remove these, then re-run: rm -- <paths>` | 1 |

**`drift [--strict]`**

`drift` never writes: its diffs come from `difflib.unified_diff` in memory [R52]. It strips CRs from every file it reads, and decodes them as UTF-8 with `surrogateescape`. `main()` maps any exception before the footer to exit 1.

`drift` emits one finding per row trigger, and each path is evaluated by one row only:

- Seed targets go to `legacy-header` if a header is found, otherwise to the stamp rows.
- `no-import`, `too-long`, `pin-changed`, `ci-variant` and `ci-skipped` are separate checks.

| Code | Severity | Trigger | Fix line |
|---|---|---|---|
| (none) | ok | Seed target with a v1 stamp whose hash matches the current template | — |
| `template-changed` | drift | The v1 stamp hash ≠ `file_hash` of the named template, unless `ci-variant`'s first case fires for the file | `apply the diff, then replace line 1 with: <stamp>`, followed by a unified diff (current render vs file without line 1) |
| `pin-changed` | drift | The `ci.yml` stamp names `ci-caller.yml`, and a `uses:` value differs from `bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-<id>.yml@<pin>`, `<pin>` being the current template's single pin: the value in a component's job block, `<id>` being the component's language, or any other value that names a `lang-ci` file, `<id>` being any language id. One finding per distinct value, in file order. A pull request can swap in another ref, another owner's copy, a local workflow, another language's file or an impostor commit [E63] | `set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-<id>.yml@<new>`, with the component's `<id>`, else the one the value names (`<id>` as written when it names none); when only the ref differs, preceded by `review https://github.com/bytewyrd/claude-bytewyrd/compare/<old>...<new>` |
| `bad-stamp` | drift | `read_stamp` returns `BAD` | `replace line 1 with: <current stamp> after reviewing the diff`, followed by the diff |
| `no-import` | drift | AGENTS.md and CLAUDE.md both exist, CLAUDE.md is not a symlink to AGENTS.md, and no CLAUDE.md line equals `@AGENTS.md` | `add the line @AGENTS.md to CLAUDE.md` |
| `legacy-header` | drift | A header or Managed/Bootstrapped banner [R15] in lines 1–3 of one of the 0.2.x manifest targets [R7]: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/ci.yml`, `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md`, `mise.toml` | B3 row for the path |
| `legacy-gitignore` | drift | `.gitignore` has the header or a `# bytewyrd:` tag | B3 |
| `legacy-rfc-process-copy` | drift | `docs/rfc-process.md` contains the line `# RFC Process` | B3 |
| `legacy-settings-hooks` | drift | `.claude/settings.json` contains `precompact-extraction-done`, `Post-commit: does this change component structure`, `Session ending: (1) /best-practices-extract` or `Consider running /sync` | B3 |
| `legacy-sidecar` | drift | `.bytewyrd/.bootstrap-versions.json` or `.claude/.bootstrap-versions.json` exists (one finding per path) | B3 |
| `legacy-state` | drift | `.bytewyrd/plugin-version` or `.bytewyrd/docs-agent-version` exists (one per path) | B3 |
| `ci-variant` | warn | First case: the `ci.yml` stamp names a template other than the one the target table picks for the current components (one finding). Second case: it names `ci-caller.yml`, and a component has no job block (one finding per component) | First case: `delete line 1 to keep this file as your own, or git rm it, commit and rerun scaffold --apply`. Second case: `add this job under jobs:, or mark the directory's manifests:`, then one `fix:` line per manifest with its `attr_line()`, then the component's rendered job block |
| `ci-skipped` | info | The `ci.yml` stamp names `ci-caller.yml`, and a SKIPPED entry exists: a rejected, opted-out or mis-set manifest, reported on its path with its reason | The reason's fix line (SKIPPED reasons) |
| `missing` | warn | A seed target is absent. For the PR template, `pr_template` also finds none; for `ci.yml`, no workflow exists | `run scaffold --apply` |
| `too-long` | warn | AGENTS.md is over 100 lines or 8,000 characters, or CLAUDE.md is over 200 lines [E5] | `move detail into docs/ or a skill` |
| `unstamped` | info | A seed target with neither a stamp nor a header | — |

**Caller checks.** drift reads `ci.yml` line by line, with no YAML parser. After the top-level `jobs:` line, a job block runs from a line of two spaces, an id and `:` to the next such line or top-level line. A component's job block is the one whose id is the component's job id (Detection, step 5) and which holds the line `directory: "<dir>"`, leading spaces ignored; the files take no `language` input, so the language shows only in the id and the file name. A `uses:` value is the text after `uses:`, with surrounding spaces, one pair of matching quotes and a trailing ` #` comment removed; it names a `lang-ci` file when the text after its last `/`, up to any `@`, starts with `lang-ci`. A component's job block with no `uses:` line counts as a differing value.

Output format: `<ok|info|warn|drift>  <path>[  <code>: <detail>]`, then optional `  fix: …` and diff lines indented two spaces. Paths, details and fix lines pass repo-derived strings through `quote()`, and a diff line whose text holds a control character (below 0x20, or 0x7f) or a surrogate is printed as `quote()` of that text after its prefix. Every stdout line of scaffold starts with a prefix from its output table, and every line of drift with `ok  `, `info  `, `warn  `, `drift  `, two spaces or `result: `. The footer reads `result: A ok, B info, C warn, D drift (exit E)`.

Exit codes:

- 1: git missing, outside a work tree, an unreadable template, a usage error, or any exception before the footer.
- Otherwise 2: any drift, or any warning under `--strict`.
- Otherwise 0.

A consumer CI that runs drift must pin the plugin ref, since every template commit is a `template-changed`.

**`state-touch [--rm] [NAME]`**

- NAME must match `^[a-z0-9][a-z0-9.-]*$`.
- The script works in cwd, like the writers it replaces [R20].
- It creates `.bytewyrd` with `os.mkdir` if absent, then opens it with `O_RDONLY | O_DIRECTORY | O_NOFOLLOW`. If that fails, for example because `.bytewyrd` is a symlink, it writes nothing and prints one stderr line.
- Every later call goes through that descriptor (`dir_fd=`), so swapping the directory for a symlink mid-run can't redirect it [R60]:
  1. It creates `.gitignore` with `O_WRONLY | O_CREAT | O_EXCL`, holding `*`. Patterns in that file apply only within `.bytewyrd/` [E34]. It hides an untracked sidecar from git [R33], which is why `legacy-sidecar` tests existence.
  2. It opens NAME with `O_WRONLY | O_CREAT | O_NOFOLLOW`, which refuses a symlink, then runs `os.utime(NAME, dir_fd=…, follow_symlinks=False)`.
  3. Under `--rm`, it checks NAME with `os.stat(…, follow_symlinks=False)`, refuses a symlink, and otherwise runs `os.unlink(NAME, dir_fd=…)`.
- `test_bw.py` asserts, on each CI platform, that `os.open`, `os.mkdir`, `os.stat`, `os.utime` and `os.unlink` are in `os.supports_dir_fd` and that `os.utime` is in `os.supports_follow_symlinks` [E67].
- Once running it always exits 0, because `main()` swallows every exception, so no hook can fail on it.

**`compact-reminder`**

It works in cwd. If `.bytewyrd/last-feature-engineer-stop` exists and its mtime is less than 86,400 seconds old, it prints the reminder text from `hooks/hooks.json:L9` [R48], with "Consider running /docs-review" changed to "Ask the user to run /docs-review", since #116 made that skill user-only [R77]. Otherwise it prints nothing. It always exits 0.

**Frontmatter parsing** (port commits). `load_frontmatter(path)` in `scripts/bytewyrd/frontmatter.py` is the only code that parses YAML:

- It reads the lines between the first two `---` lines and rejects a block over 64 KiB.
- It parses them with `FrontmatterLoader`, a `yaml.SafeLoader` subclass. The subclass has no implicit resolvers, so every plain scalar stays a string, and its `compose_node` raises on an alias [R55, R56].
- It returns the six fields that `rfc-frontmatter` prints, converted as below. `tests/py/test_frontmatter.py` pins each row with a fixture.

| Input | Output | Same as the bash parser? |
|---|---|---|
| Plain scalar, such as `2026-11-09`, `yes` or `12` | The text as written | Yes |
| Plain scalar holding `"`, such as `Plain "title"` | The text as written | No: bash deletes every `"` |
| `~`, `null` or an empty value | `""` | For `drop_reason` only; bash keeps `~` and `null` in other fields |
| Double-quoted value | YAML unescaping: `"a \"b\""` → `a "b"` | Yes for `\"` and `\\`, which bash undoes since 812943e [R77]; no for other escapes, such as `\t`, which bash keeps as written |
| Single-quoted value | YAML unquoting: `'it''s'` → `it's` | No: bash keeps the quotes |
| Trailing `# comment` | Dropped: `"Draft" # still a draft` → `Draft` | No: bash keeps the comment and deletes the quotes |
| List or mapping | Exit 2 with an `error` object | No: bash printed the raw text |
| Invalid YAML, such as an unquoted `title: RFC: x` | Exit 2 with an `error` object | No: bash accepted it |
| An alias, or a block over 64 KiB | Exit 2 with an `error` object | New checks |

AC-22 holds for this port: two assertions of #116's tests pin rows marked "No", and the harness commit, which is not a port commit, deletes them (B1). With them gone, the whole bats suite passes under the loader, and all 24 RFCs on main parse to the same six values as before [R56, R78]. The rows marked "No" are intended changes, which `test_frontmatter.py` covers instead of bats.

**Ports.** Each of the nine scripts keeps its arguments, stdout and stderr formats, and exit codes, as pinned by its unchanged bats file [R51]. JSON comes from the `json` module instead of jq, and RFC frontmatter from `load_frontmatter`. rfc-summary depends on rfc-frontmatter [R59], so the port commits can only be reverted together.

**Vendored PyYAML** (vendor commit):

- **Path:** `scripts/_vendor/yaml/` holds the 17 `lib/yaml/*.py` files of PyYAML 6.0.3's sdist, unmodified [E69].
- **License:** `scripts/_vendor/PyYAML-LICENSE`, the sdist's MIT `LICENSE` [E54], plus the `THIRD_PARTY_NOTICES.md` section (B1).
- **Integrity:** `uv.lock` pins PyYAML in the `dev` group and records its sdist's URL, sha256 and size: E69's URL and hash [R93] (D9). `.github/scripts/vendor-pyyaml.py`, standard library only, reads PyYAML's locked version and sdist from `uv.lock` with `tomllib`, downloads the sdist, checks its size and sha256, and rebuilds `scripts/_vendor/yaml/` and `scripts/_vendor/PyYAML-LICENSE` from the sdist's `lib/yaml/` and `LICENSE`. With `--check` it writes nothing, and fails when a file differs or exists on one side only. `lint` runs the check (B4).
- **Safe loading:** only `scripts/bytewyrd/frontmatter.py` imports `yaml`, at module level. A `lint` grep rejects `yaml.load(`, `safe_load`, `full_load`, `unsafe_load` and `Loader=` outside `scripts/bytewyrd/frontmatter.py` and `scripts/_vendor/` (B4).
- **No C extension:** `yaml/cyaml.py` imports `yaml._yaml`, which is not vendored, so `yaml.__with_libyaml__` is `False` [E54]. `tests/py/test_vendor.py` runs the interpreter with the launcher's flags and the bootstrap's path setup, and asserts that `yaml.__file__` is under `scripts/_vendor/yaml/`, `yaml.__version__` is the version `uv.lock` pins and `yaml.__with_libyaml__` is `False`. It repeats the check without `-S`, where the `dev` group's PyYAML is on the path, to show that the vendored copy still wins.
- **Updates:** in one commit, edit the PyYAML pin in `pyproject.toml`, run `uv lock`, run `vendor-pyyaml.py`, and update the version in `THIRD_PARTY_NOTICES.md`.

### B3. Text rules and migration fixes

| Rule | Change |
|---|---|
| M1 | References to `docs/rfc-process.md` as the process become "the `rfc-process` skill". The opt-in check at `agents/feature-engineer.md:L70-L73` becomes "a `docs/rfcs/` directory exists at the repository root". Ownership lists drop the entry: `agents/docs-agent.md:L30,L87`, `agents/documentation-writer.md:L61`, `skills/docs-review/SKILL.md:L184` |
| M2 | `/sync` meaning setup becomes `/bytewyrd:scaffold`, and meaning refresh or check becomes `/bytewyrd:drift`. Sentences about manifests, markers and owned regions are deleted |
| M3 | Each `mcp__` ID becomes a plain tool name: "the GitHub MCP server's `create_pull_request` tool", "Exa's search tool" or "Exa's page-fetch tool", "Context7's `resolve-library-id` and `query-docs` tools" |
| M4 | Frontmatter: `compatibility: "Claude Code only: relies on Claude Code subagents, AskUserQuestion or ~/.claude paths. Helper scripts need git, jq, bash >= 4 and python3 >= 3.11."` From the retire commit, the last sentence is `Helper scripts need git, jq and python3 >= 3.11.` These are the nine Claude-only skills [R22]; Claude Code accepts `compatibility` but doesn't act on it [E6] |
| M5 | Add after the first `${CLAUDE_PLUGIN_ROOT}` use in a SKILL.md: "Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md." |

Migration fixes, as printed by drift. These are file edits only: commit them, then run `scaffold --apply` on the clean tree (B4, migration procedure).

| Code / path | Fix |
|---|---|
| `legacy-header` on `CLAUDE.md` | Run `git mv CLAUDE.md CLAUDE.legacy.md`. After `scaffold --apply` (B4 step 4), delete from CLAUDE.legacy.md only the ten 0.2.x owned H2s [R34]. Move every other H2 to AGENTS.md, or into CLAUDE.md if it is Claude-only, then `git rm CLAUDE.legacy.md`. The owned H2s are covered as follows: Evidence-Based Development → rule 1; Auto Mode → rule 2 plus the AskUserQuestion line; RFC Process → rule 3 and the rfc-process skill; Git and Conventions → rule 4; Security → best-practices `general.md` [R42]. Agent delegation, Tool Usage, Model Usage Optimization and the Sandbox section are dropped on purpose for a lighter context [E11, E12]; a project keeps any of them as CLAUDE.md lines |
| `legacy-header` on `.github/PULL_REQUEST_TEMPLATE.md` or `.github/workflows/ci.yml` | Delete line 1 so the repo's own file stays. `drift` then reports `unstamped` (info). The ci.yml fix keeps working-directory jobs [R36] |
| `legacy-header` on `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `mise.toml` | Delete the header and banner lines |
| `legacy-header` on `docs/BEST_PRACTICES.md` | Delete the header, the banner, and the `## Pitfall` … `## Terraform / Terragrunt` sections; keep the project's own entries |
| `legacy-gitignore` | Delete the header line and every `# bytewyrd:` tag line, and keep the patterns as ordinary lines |
| `legacy-rfc-process-copy` | Run `git rm docs/rfc-process.md`, and move any `## Project Extensions` text into AGENTS.md |
| `legacy-settings-hooks` | Delete the 0.2.x hook entries, and delete the file if it becomes `{}` |
| `legacy-sidecar`, `legacy-state` | Run `git rm` on, or delete, the file. If `.bytewyrd/` remains, run `sh "$PLUGIN/scripts/bw" state-touch` |
| Plugin clones only | `rm .git/hooks/pre-commit`, since it pointed at the deleted manifest check |

### B4. Commands and expected results

**#115.** It replaces this branch's `lang-ci.yml` with the five `lang-ci-<id>.yml` files (Appendix C): committed lockfiles enforced (`--locked` for uv and cargo, `--frozen-lockfile` for a Bun lockfile), pytest's exit 5 accepted, the setup-bun step in `ruby` and the GOWORK line in `go`, and a `timeout-minutes` input in each. It adds four fixtures, the Ruby one with a CHECKSUMS section, and a `lang-ci-fixture-<id>` job per file. `lint` runs this step under `bash -e`, which exits 0 on the Appendix C files and fails on each defect the comments name:

```bash
w=.github/workflows
test "$(printf '%s\n' "$w"/lang-ci*)" = "$(printf '.github/workflows/lang-ci-%s.yml\n' go js python ruby rust)"  # a language without its file, or another lang-ci file
for f in "$w"/lang-ci-*.yml; do
  l=${f#"$w"/lang-ci-}; l=${l%.yml}
  test "$(sed '1,/^jobs:$/d' "$f" | grep -E '^  [^ #]')" = "  $l:"  # a job not named by the file's id, or a second job
  if grep -q '^    if:' "$f"; then exit 1; fi  # a job-level if:, which skips the job instead of failing it [R69]
  test "$(grep -A3 -x "  lang-ci-fixture-$l:" "$w/ci.yml")" = "$(printf '  lang-ci-fixture-%s:\n    uses: ./.github/workflows/lang-ci-%s.yml\n    with:\n      directory: tests/fixtures/lang-ci/%s' "$l" "$l" "$l")"  # no fixture job for the file
  test "$(grep -c 'uses: actions/checkout@' "$f")" = "$(grep -c 'persist-credentials: false' "$f")"  # a checkout keeps credentials
  if grep -E '^ +(- )?uses:' "$f" | grep -vqE 'uses: [^@[:space:]]+@[0-9a-f]{40}( #|$)'; then exit 1; fi  # a uses: not pinned by SHA
  test "$(grep -cE '^ *permissions:' "$f")" = 1  # a second permissions: key
  test "$(grep -A2 -x 'permissions:' "$f")" = "$(printf 'permissions:\n  contents: read\njobs:')"  # more than contents: read
  if grep -v '^ *#' "$f" | grep -qE 'secrets|pull_request_target'; then exit 1; fi  # secrets or pull_request_target
  test "$(grep -c '^    timeout-minutes: [$]{{ inputs[.]timeout-minutes }}$' "$f")" = 1  # a job without the timeout
done
test "$(grep -hoE 'uses: [^@[:space:]]+@' "$w"/lang-ci-*.yml | sort -u | wc -l)" = "$(grep -hoE 'uses: [^@[:space:]]+@[0-9a-f]{40}' "$w"/lang-ci-*.yml | sort -u | wc -l)"  # an action pinned at two SHAs
test "$(grep -cE '^ +cargo (build|test|clippy) --workspace ' "$w/lang-ci-rust.yml")" = 3  # a cargo command without --workspace, which the fixture can't detect [R84]
grep -qx CHECKSUMS tests/fixtures/lang-ci/ruby/Gemfile.lock  # no CHECKSUMS section
grep -qE '^  rake \([0-9.]+\) sha256=[0-9a-f]{64}$' tests/fixtures/lang-ci/ruby/Gemfile.lock  # a CHECKSUMS entry without its hash
```

Each check is its own command because `bash -e`, GitHub's default for `run:` [E89], doesn't stop on a failure inside an `&&` list that isn't its last command, or on a `!` command [R87]. The timeout pattern writes `$` as `[$]` because GitHub substitutes every `${{ … }}` in a `run:` script before bash runs it [E107]. The five fixture jobs pass. No job has a job-level `if:`, and the `if:` check keeps it so, since a skipped job's fixture job would still pass [R69]. One SHA per action keeps the allow list to one entry per action (Appendix C).

`lint` also installs actionlint 1.7.12 the way it installs shellcheck and shfmt, checks each of the three versions against `mise.toml` with its own `grep -qxF`, and, after the install step, runs `actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml`, which takes the pinned shellcheck from the front of `PATH` [E109] and runs it on every `run:` block [E108]. Each exits 0 (Appendix C).

**Implementation PR, final state.** CI runs these on the PR; each is followed by its expected result.

```bash
uv sync --locked                                                # exit 0: the dev group, as uv.lock pins it [R92]
uv run --no-sync tests/run.sh                                   # exit 0
uv run --no-sync pytest -q tests/py tests/e2e                   # exit 0; consumer-sim runs with CLAUDE_PLUGIN_ROOT unset and as /nonexistent
uv run --no-sync ruff check                                     # exit 0
uv run --no-sync ruff format --check                            # exit 0
uv run --no-sync mypy                                           # exit 0: --strict on the package but its bootstrap, as pyproject.toml sets it (B2)
python3 .github/scripts/vendor-pyyaml.py --check                # exit 0: scripts/_vendor matches the sdist uv.lock pins
claude plugin validate .                                        # exit 0; not --strict, which is unreliable [E36, R24]
jq -e '.allowCrossMarketplaceDependenciesOn | index("claude-plugins-official")' .claude-plugin/marketplace.json  # prints 0
jq -e '.hookSpecificOutput | .hookEventName == "SessionStart" and (.additionalContext | length) <= 2000' hooks/always-on-rules.json  # true
grep -nE 'stat -[cf]|check-requirements' hooks/hooks.json       # no output
grep -c 'deterministic-script consolidation' docs/rfc-braindump.md  # prints 0
grep -qx '__pycache__/' .gitignore                              # exit 0
for s in best-practices-extract best-practices-record docs-review refactor rfc-braindump rfc-consensus-review rfc-implement rfc-new rfc-read-feedback; do
  grep -q '^compatibility:' "skills/$s/SKILL.md" || echo "$s"; done  # no output
grep -rlE '/sync\b' docs/guide README.md CLAUDE.md agents skills hooks templates docs/ARCHITECTURE.md docs/CONTRIBUTING.md docs/BEST_PRACTICES.md docs/project-brief.md .claude/skills .github/scripts  # no output
grep -rln 'docs/rfc-process.md' agents skills hooks templates docs/guide README.md CLAUDE.md docs/ARCHITECTURE.md docs/CONTRIBUTING.md  # no output
grep -rnE 'mcp__[A-Za-z0-9]' agents skills hooks templates      # no output
grep -rnE 'github-mcp|context7-mcp|code-review-mcp' scripts skills tests/scripts  # no output
grep -rn 'CLAUDE_PLUGIN_ROOT' scripts                           # no output
grep -nE 'build-manifest|bootstrap-manifest' .github/workflows/ci.yml  # no output
test ! -e bootstrap-manifest.json && test ! -d skills/sync && test ! -e scripts/rfc-legacy-detect.sh && ! ls scripts/sync-*.sh 2>/dev/null  # exit 0
ls -d scripts/*.sh scripts/_lib scripts/_vendor/*.sha256 2>/dev/null  # no output
grep -rnE 'require_bash_major|scripts/[a-z-]+\.sh' skills hooks scripts tests/scripts  # no output
git grep -nE 'yaml\.(load|safe_load|full_load|unsafe_load)\(|Loader=' -- scripts skills hooks ':!scripts/bytewyrd/frontmatter.py' ':!scripts/_vendor'  # no output
sh scripts/bw drift                                             # exit 0: this repo is migrated; warnings are allowed
```

From the add commits on, `test_bw.py` asserts, by matching lines, that the language ids of `detect` (of `bw.py` before D7) equal the ids of the `.github/workflows/` names that start with `lang-ci`, each of which must be `lang-ci-<id>.yml`; the ids of the `lang-ci-fixture-<id>` jobs in `ci.yml`; and the `@@<id>@@` tags of `AGENTS.md.tpl` other than `any` and `job` (`none` and `job` before D10). #115's file-set line is then deleted from `lint`, and the rest of that step stays.

**Implementation PR, every commit.** The `history` job runs this with the `test` job's setup (setup-python, `uv sync --locked`, `BYTEWYRD_PYTHON`), which `ci-lint.bats` and `rfc-set-status.bats` need under `CI` [R85]; it exits 0. It syncs once, at HEAD, and keeps that `.venv/bin` first on `PATH` for every commit, since the commits before D8 have no `uv.lock`. Each commit's bats output goes to `$RUNNER_TEMP` and is printed in a group only when it fails [E88], and each checkout moves the submodules too [E91]. HEAD is restored by SHA, because a pull request's checkout is a detached merge commit [E85], where `git branch --show-current` prints nothing [R73].

```bash
base=$(git merge-base origin/main HEAD); h=$(git rev-parse HEAD); bad=0
for c in $(git rev-list --reverse "$base..HEAD"); do
  git checkout -q --recurse-submodules "$c"
  if ! tests/run.sh > "$RUNNER_TEMP/bats-$c.log" 2>&1; then
    echo "::group::bats fails at $c"; cat "$RUNNER_TEMP/bats-$c.log"; echo "::endgroup::"; bad=1
  fi
done
git checkout -q --recurse-submodules "$h"
for c in $(git rev-list --grep='^refactor(scripts): port ' "$base..HEAD"); do git diff --quiet "$c^" "$c" -- tests/scripts || { echo "::error::$c edits tests/scripts"; bad=1; }; done
exit "$bad"
```

**Pin checks**, run by the `history` job with full history [E64], after the loop and even when it fails [E87]. The template must hold exactly one `uses:` line, of the full caller shape, and its pin must have every `lang-ci-<id>.yml` that HEAD has:

```bash
tpl=templates/scaffold/ci-caller.yml.tpl
pin=$(sed -n 's|^@@job@@     uses: bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-@@job_language@@\.yml@\([0-9a-f]\{40\}\)$|\1|p' "$tpl")
test "$(grep -c 'uses:' "$tpl")" = 1   # exit 0
test "${#pin}" = 40                    # exit 0; fails for another owner, a branch or tag ref, or two pins
git merge-base --is-ancestor "$pin" origin/main  # exit 0: a main commit
for f in .github/workflows/lang-ci-*.yml; do git cat-file -e "$pin:$f"; done  # exit 0: one that has every lang-ci file
if ! git diff --quiet "$pin" HEAD -- '.github/workflows/lang-ci*'; then
  if git diff --quiet origin/main HEAD -- "$tpl"; then
    echo "::warning::the lang-ci files differ from the pinned $pin; bump the pin after this merges"
  else
    echo "::error::the new pin $pin does not match this commit's lang-ci files"; exit 1
  fi
fi
```

The last check only warns on a PR that changes a `lang-ci` file, and on `main` until the bump lands, since the bump can only follow the merge; on the PR that moves the pin, a mismatch fails. The loop and the diff cover whatever `lang-ci` files HEAD has, so a new language needs no edit here.

**bats files for the launcher, hooks and state-touch.**

- `bw.bats`:
  - With stub interpreters on a test `PATH`, the launcher takes `$BYTEWYRD_PYTHON` when it reports 3.11 or newer, skips it when it reports 3.9, then takes the highest of `python3.15` down to `python3.11`, then `python3`.
  - With no qualifying interpreter, each class-A command exits 1 with one stderr line, and each class-B command exits 2 with a JSON `error` on stderr. `state-touch precompact-extraction-done` still writes its sentinel and exits 0, and refuses a symlinked `.bytewyrd`.
  - A NAME such as `nope` or `../x` exits 1.
  - With a venv's interpreter as `$BYTEWYRD_PYTHON` and a marker-writing `.pth` file in its site-packages, a command leaves no marker and no `__pycache__/`.
- `hooks.bats`: the rules entry prints the rules JSON (plus the size check above). The `compact` reminder prints its text only while the sentinel is under a day old. Under both of `bw.bats`'s no-interpreter setups, the SubagentStop write and the `compact` reminder commands exit 0.
- `state-touch.bats`: a symlinked `.bytewyrd` or NAME leaves the outside directory unchanged, and `--rm` removes only a regular file.

**`tests/e2e/test_consumer_sim.py` (consumer-sim).**

- It is black-box: it runs only `sh "$PLUGIN/scripts/bw" <name>` through `subprocess` and imports nothing from `scripts/`.
- PLUGIN_DIR is `$BW_PLUGIN_DIR`, defaulting to the repository root. It is copied to a temp `plugin` directory without `.git`; that name is not hex, so this exercises `plugin=unknown`.
- Every step runs twice: with `CLAUDE_PLUGIN_ROOT` removed from the child environment, and with it set to `/nonexistent`.
- Every child gets `BYTEWYRD_PYTHON` set to the interpreter running pytest, so the CI matrix's Python is the one under test; S23 checks this.
- Repos are created with `git init -q`, and commits use `git -c user.name=ci -c user.email=ci@example.invalid`.

| Step | Action | Expected |
|---|---|---|
| S1 | In a fresh repo with no commits, run `scaffold` | 4 `would create` lines; exit 0; porcelain empty |
| S2 | `mkdir -p a/b && cd a/b && scaffold --apply` | `applied: 4 created, 0 skipped`; files at the repo root, none under `a/b`, no `.claude` path |
| S3 | Read line 1 of each file | Matches the B2 regex with `plugin=unknown` |
| S4 | `drift` | `result: 4 ok, 0 info, 0 warn, 0 drift (exit 0)` |
| S5 | Commit, then `scaffold --apply` | `applied: 0 created, 4 skipped`; porcelain empty; drift exits 0 |
| S6 | Hash every file before and after each drift run in S4–S39 | Identical |
| S7 | Convert the four files to CRLF, run drift, then restore them | Exit 0 |
| S8 | Convert the copied `templates/scaffold/AGENTS.md.tpl` to CRLF | `ok  AGENTS.md` |
| S9 | Append a line to that template, then paste the printed stamp into line 1 | `template-changed` with exit 2, then exit 0 |
| S10 | Delete `@AGENTS.md` from CLAUDE.md | `no-import`; exit 2 |
| S11 | Commit a root `go.mod`, run drift, then `drift --strict` | `warn … ci-variant` with exit 0, then exit 2 |
| S12 | In a new repo with an untracked file, run `scaffold --apply`, then `scaffold --apply --allow-dirty` | Exit 3 with nothing written, then exit 0 |
| S13 | New repos, one each, with: a lowercase `agents.md`; an `AGENTS.md/` directory; a dangling `AGENTS.md` symlink; `docs/pull_request_template.md`; `.github/workflows/other.yml` | Each matching target is skipped; the symlink's target is never created |
| S14 | New repo where `.github` is a symlink to a temp dir outside it; run `scaffold --apply` | Exit 1; the outside dir and the repo are unchanged |
| S15 | New repo with `.github/` at mode 0555; run `scaffold --apply` | Exit 1; `AGENTS.md` and `CLAUDE.md` are gone afterwards |
| S16 | In the copied plugin, append a line `)` to `scripts/bytewyrd/commands/drift.py`, run drift, then restore the file | Exit 1 |
| S17 | New repo with a committed root `go.mod`, `Gemfile` and `Rakefile`; run `scaffold --apply` | The caller has jobs `go` and `ruby`, with `uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@<40-hex>` and `…/lang-ci-ruby.yml@` the same 40 hex digits, each with `directory: "."`. In the caller and each `$PLUGIN_DIR/.github/workflows/lang-ci-<id>.yml`, every `uses:` matches `@[0-9a-f]{40}`, every checkout sets `persist-credentials: false`, the only `permissions:` key is the top-level one, holding only `contents: read`, and no file has `secrets` or `pull_request_target` |
| S18 | For each `tests/fixtures/legacy-0.2/<case>/`, copy it into a new repo, once untracked and once committed, then run drift. Then run the migration procedure, with the fixture's scripted port, and run drift again | Exactly the case's codes with exit 2, then exit 0 |
| S19 | New repo in a directory named `we&ird\name`; run `scaffold --apply` from the git checkout PLUGIN_DIR | AGENTS.md line 2 is `# we&ird\name`; `plugin=` holds 12 hex digits |
| S20 | In a fresh temp directory outside any repo, run `scaffold` and `drift` | Both exit 1 |
| S21 | Make `.bytewyrd` a symlink to an outside dir, then `.bytewyrd/last-feature-engineer-stop` a symlink; run `state-touch last-feature-engineer-stop` each time | Exit 0; nothing outside the repo changes |
| S22 | Diff the S2 `ci.yml` against `$PLUGIN_DIR/.github/workflows/scaffold-noop-fixture.yml` from line 2, and read the S2 `AGENTS.md` | Identical; `AGENTS.md` has no `## Project facts` line |
| S23 | Run `drift` with `BYTEWYRD_PYTHON` set to a wrapper that logs, then runs the interpreter running pytest | The log shows the wrapper ran |
| S24 | In the S17 repo, commit, then replace the `ruby` job's pin with 40 other hex digits and run `drift`. Then, from the committed S17 state each time, change that job's `uses:` to `bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@main`, to `evil/x/.github/workflows/lang-ci-ruby.yml@main`, to the `go` job's value and to the local `./.github/workflows/x.yml`, keeping its `with:` lines, and run `drift` | Each run: `pin-changed` with exit 2. The first run's fix lines hold a `compare/<old>...<new>` URL |
| S25 | New repo with committed `web/package.json` and `api/go.mod` and no root manifest; run `scaffold --apply` | Jobs `go-api` (`language: go`, `directory: "api"`) and `js-web` (`language: js`, `directory: "web"`); AGENTS.md's languages line ends with `go in api/, js in web/`; drift exits 0 |
| S26 | New repo with committed root `package.json` (`"workspaces": ["packages/*"]`), `pyproject.toml` (`[tool.uv.workspace]` with `members = ["libs/*"]` and `exclude = ["libs/solo"]`), `Cargo.toml` (virtual, `members = ["crates/*"]`, `exclude = ["tools"]`), `go.mod` and `go.work` (`use . ./svc`); plus `packages/a/package.json`, `site/package.json`, `libs/m/pyproject.toml`, `libs/solo/pyproject.toml` (both with `[project]`), `crates/c/Cargo.toml`, `tools/gen/Cargo.toml` and `svc/go.mod`; run `scaffold --apply` | Exactly the jobs `go`, `go-svc`, `js`, `js-site`, `python`, `python-libs-solo`, `rust` and `rust-tools-gen` |
| S27 | New repo with a committed root `Gemfile`, `Rakefile`, `package.json` and `pnpm-lock.yaml`, a `.tool-versions` holding only `nodejs 24.0.0`, and a `Gemfile.lock` whose PLATFORMS lists only `arm64-darwin-24`; run `scaffold --apply` | Jobs `js` and `ruby`; AGENTS.md has the Ruby line; notes name the missing Ruby version, `bundle lock --add-platform x86_64-linux` and pnpm |
| S28 | New repo with committed `test/fixtures/app/package.json`, `examples/demo/go.mod`, `testdata/x/go.mod`, `.github/actions/a/package.json`, `_old/go.mod`, `a/b/c/go.mod`, `docs/package.json`, `web/package.json` and `deep/one/two/go.mod`, and a `.gitattributes` with `web/package.json -bytewyrd-ci` and `deep/** bytewyrd-ci`; run `scaffold --apply` | Exactly the jobs `go-deep-one-two` and `js-docs`, and one `note:`, for `web/package.json`, opted out |
| S29 | New repo with committed `bad dir/go.mod`, `-x/go.mod`, `a.b/go.mod`, `a/b/go.mod`, `w⏎::warning::x/go.mod`, `ESC[2J/go.mod` and `web⏎/package.json`, where ⏎ is a newline and ESC byte 0x1b; run `scaffold --apply`, then drift. Then append the `.gitattributes` line drift printed for `bad dir/go.mod`, commit, and run drift again | One job, `go-a-b`, with `directory: "a.b"`; six `note: no CI job for …` lines; drift prints six `info … ci-skipped` lines and exits 0. No output byte is below 0x20 but `\n`, every stdout line starts with a documented prefix (B2), and stderr is empty. Then `"bad dir/go.mod"` is reported as `opted out by -bytewyrd-ci` |
| S30 | In the S25 repo, commit, then add and commit `cli/go.mod`; run drift, then `drift --strict` | `warn  .github/workflows/ci.yml  ci-variant`, whose fix lines show `/cli/go.mod -bytewyrd-ci` and a `go-cli` job block, with exit 0; then exit 2 |
| S31 | New repo with a committed root `package.json` that is a symlink to `/dev/zero` and a committed `packages/a/package.json`; run `scaffold --apply`, then drift | Both exit 0 without reading the symlink; jobs `js` and `js-packages-a` |
| S32 | New repo with a committed gitlink at `Cargo.toml` (mode 160000, added with `git update-index --add --cacheinfo`) and a committed `crates/c/Cargo.toml`; run `scaffold --apply --allow-dirty`, then drift | Both exit 0; jobs `rust` and `rust-crates-c` |
| S33 | New repo with a committed root `package.json` of 2 MiB, `{"workspaces": ["packages/*"]}` padded with spaces, and `packages/a/package.json`; run `scaffold --apply`, then drift | Both exit 0; jobs `js` and `js-packages-a` |
| S34 | As S33, but the root `package.json` is unpadded, and its `"x"` holds 200,000 nested arrays | Both exit 0; jobs `js` and `js-packages-a` |
| S35 | As S33, but the root `package.json` is unpadded, and its `"n"` is a 5,000-digit number | Both exit 0; jobs `js` and `js-packages-a` |
| S36 | New repo with a committed root `Cargo.toml` holding `[workspace]` and a comment with the byte 0xff, and `crates/c/Cargo.toml`; run `scaffold --apply`, then drift | Both exit 0; jobs `rust` and `rust-crates-c` |
| S37 | New repo with a committed root `Cargo.toml` holding `[workspace]` with `members = "crates/*"`, a root `package.json` with `"workspaces": [1, "packages/*"]`, `crates/c/Cargo.toml` and `packages/a/package.json`; run `scaffold --apply`, then drift | Both exit 0; jobs `js`, `js-packages-a`, `rust` and `rust-crates-c` |
| S38 | New repo with a committed root `go.mod`, a file named `caf` plus the byte 0xe9 plus `.txt`, and `caf`+0xe9`/go.mod`; run `scaffold --apply`, then drift | Both exit 0; job `go`; the note and the `ci-skipped` line show `"caf\351/go.mod"` |
| S39 | New repo with a committed root `Gemfile` and no Rakefile; `app/Gemfile`, `app/Rakefile` and `app/.ruby-version`; `tool/pyproject.toml` holding only `[tool.ruff]`; `legacy/setup.py`; `both/pyproject.toml`, with `[project]` and a `dev` group listing pytest, and `both/setup.py`; and `nopy/pyproject.toml` with `[project]` and no groups; run `scaffold --apply` | Exactly the jobs `python-both`, `python-nopy` and `ruby-app`; notes for `Gemfile` (no Rakefile), `legacy/setup.py` (no pyproject.toml with [project]) and `nopy/pyproject.toml` (pytest); none for `both/` or `tool/` |

**Migration procedure**: in this repo's migrate commits, and in one PR per app repo after the implementation PR merges.

1. Install the plugin's three dependencies explicitly with `claude plugin install <dep>@claude-plugins-official` [R57].
2. Run `sh "$PLUGIN/scripts/bw" drift`, where `$PLUGIN` is the implementation branch's checkout (this repo) or a checkout of `main` after its merge (apps). Expect exit 2 with `legacy-*` findings.
3. Apply each fix from B3.
4. Commit.
5. Run `scaffold --apply`, which needs the clean tree [R32]. Expect `created` for AGENTS.md, and for CLAUDE.md if it was moved.
6. Port the CLAUDE.legacy.md sections (B3), then commit.
7. Run drift. Expect exit 0 (`unstamped` info is allowed).

**Port commits**, in order:

1. Harness (B1).
2. Vendor PyYAML.
3. One port per script, each with the subject `refactor(scripts): port <name> to Python`.
4. Retire: delete `common.bash` and `common.bats`, remove the launcher's bash fallback, and update M4 and `lint`.

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
| AC-8 | S22, a `test_bw.py` case in which the no-language renders of `AGENTS.md.tpl` and `ci-noop.yml.tpl` hold neither `scaffold` nor `language`, ignoring case, plus the `scaffold-noop-fixture.yml` run on GitHub |
| AC-9 | S17, #115's `lint` step (B4), and the pin checks |
| AC-10 | S5 |
| AC-11 | S4, S6, S10, S11, S16, S30, plus a `test_bw.py` case in which a check raises |
| AC-12 | S9, S24 |
| AC-13 | S18, and the final-state `sh scripts/bw drift` in this repo |
| AC-14 | S7, S8 |
| AC-15 | CI jobs `test` and `compat` |
| AC-16 | S21, `state-touch.bats`, and a `test_bw.py` case that swaps `.bytewyrd` for a symlink after it is opened |
| AC-17 | `hooks.bats` (the entry plus the B4 jq size check) |
| AC-18 | CI jobs `validate` and `install-check` (install and update cases) |
| AC-19 | B4 greps and the compatibility loop |
| AC-20 | `bw.bats`, `hooks.bats`, and a `test_bw.py` case that runs the bootstrap with `sys.version_info` patched to 3.10 |
| AC-21 | `vendor-pyyaml.py --check` in `lint`, the B4 loader grep, `tests/py/test_vendor.py` and `tests/py/test_frontmatter.py` |
| AC-22 | The B4 every-commit commands, in the `history` job |
| AC-23 | S25–S39, plus `test_bw.py` cases for pattern matching, for each root-workspace rule, and for the ten-component cap on the languages line |
| AC-24 | The five `lang-ci-fixture-<id>` jobs, #115's `lint` step and `test_bw.py`'s id checks (B4) |
| AC-25 | S29, plus `test_bw.py` cases for `quote()` and `attr_line()`, and one that applies a root `go.mod`'s printed line next to `svc/go.mod` and keeps the `go-svc` job [R79] |
| AC-26 | `lint`'s version checks and actionlint step, from #115 (B4, Appendix C) |

## Appendix C — Template sketches

**`templates/scaffold/AGENTS.md.tpl`.** `scaffold` adds the stamp line. The tagged lines, first drawn from [R23], match the `lang-ci-<id>.yml` commands without CI's lockfile checks. The `@@any@@` lines hold the Project facts heading, its blank lines and the languages line, and render only when detection finds a language (D10).

```markdown
# @@project_name@@

Guidance for people and coding agents working in this repository. Keep it under 100 lines; put detail in docs/.

@@any@@ ## Project facts
@@any@@
@@any@@ - Languages (run each one's commands in its directory): @@languages@@
@@go@@ - Go: build `go build ./...`, test `go test ./...`
@@js@@ - JavaScript/TypeScript: install `bun install`, test `bun test --pass-with-no-tests`
@@python@@ - Python: install `uv sync --all-packages`, test `uv run pytest`
@@ruby@@ - Ruby: install `bundle install`, test `bundle exec rake`; CI reads the Ruby version from `.ruby-version`, `.tool-versions` or `mise.toml`
@@rust@@ - Rust: build `cargo build --workspace`, test `cargo test --workspace`, lint `cargo clippy --workspace`
@@any@@
## Workflow

This repository follows the bytewyrd workflow: https://github.com/bytewyrd/claude-bytewyrd
- Changes that need design start as an RFC in `docs/rfcs/`. Process: https://github.com/bytewyrd/claude-bytewyrd/blob/main/skills/rfc-process/references/rfc-process.md
- Working conventions: https://github.com/bytewyrd/claude-bytewyrd/blob/main/hooks/always-on-rules.json
- Project-specific learnings go in `docs/BEST_PRACTICES.md`.
```

**`templates/scaffold/CLAUDE.md.tpl`.** This is the install sequence for every install instruction [R12, E41]:

```markdown
@AGENTS.md

## Claude Code

- The bytewyrd plugin loads this workflow's conventions at session start. It needs Python 3.11 or newer on `PATH`, or in `BYTEWYRD_PYTHON`. Install it once per machine:
  `claude plugin marketplace add anthropics/claude-plugins-official`, then
  `claude plugin marketplace add bytewyrd/claude-bytewyrd`, then `claude plugin install bytewyrd@bytewyrd`.
  Install its dependencies explicitly too, so updates keep them resolved: `claude plugin install github@claude-plugins-official`, and the same for `context7` and `code-review`.
- Plugin skills are namespaced, for example `/bytewyrd:rfc-new` and `/bytewyrd:drift`.
- Open decisions are asked with AskUserQuestion.
```

**`templates/scaffold/ci-noop.yml.tpl`.** The triggers are taken from `templates/ci.yml.tpl:L1-L7`. Its one step, `exit 0`, names neither scaffold nor detection (D10).

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
      - run: exit 0
```

**`.github/workflows/lang-ci-<id>.yml`** (#115). Five reusable workflows, one per language id, live in this repo directly in `.github/workflows/`, since GitHub supports no subdirectory there [E103]; a caller job runs the one for its component's language. Each holds one job whose id is its language id, so a call shows as `<caller job> / <id>`, as `lang-ci-fixture / go` did [R69]. The commands match the AGENTS.md lines plus CI's lockfile checks; the pins come from [R44] and, for setup-ruby, [E76]; action usage from [E49], and the `workflow_call` and `inputs` syntax from [E65]. Every checkout sets `persist-credentials: false`, because the default is `true` [E64]. The `workflow_call` block and the checkout repeat in all five, and setup-bun is pinned in the js and ruby files; B4's `lint` step checks each file, and one SHA per action across them. [R88] records a local run of these sketches.

- **Inputs.** `directory` defaults to the repository root, and callers set it per component (B2). `timeout-minutes`, a number that defaults to 30 [E89], bounds the job: a caller job can't set one [E71], the default is 360 minutes [E89], and `inputs` is available there [E86]. There is no `language` input and no guard job: the file name picks the language, and `uses:` takes no expressions [E103], so each call is fixed in its caller. A caller of any other file, such as `lang-ci-java.yml`, fails the whole run before any job starts, because GitHub resolves every called workflow when it queues the run and reports the caller invalid: "workflow was not found" [E105].
- **Per-directory files.** setup-go looks for its cache key file only at the workspace root unless `cache-dependency-path` is set [E73], which caused #115's warning [R69]; setup-uv and setup-ruby read their version and lock files from `working-directory` [E74, E76]. setup-bun caches only its executable, and reads a Bun pin only from the root `package.json` [E75], so a subdirectory app's pin is ignored.
- **Workspaces.** `--workspace` and `--all-packages` make a root job cover the members that detection drops (B2) [R71, R72].
- **Lockfiles.** A committed lockfile is enforced: `uv sync --all-packages --locked` when `uv.lock` exists, `cargo … --locked` when `Cargo.lock` exists (passed as `${locked:+"$locked"}`, the optional-argument form SC2086's page gives, so shellcheck stays quiet [E110]), and `bun install --frozen-lockfile` when `bun.lock` or `bun.lockb` exists [R82, R83, R84]. Go builds are read-only by default [R81], and setup-ruby installs in Bundler's deployment mode, which is frozen [E96, R84]. A JS component with only an npm, Yarn or pnpm lockfile gets a plain `bun install`, which checks nothing: Bun 1.3.14 migrated an outgrown `package-lock.json` and installed [R83]. Bun 1.4.4, the latest release and so what setup-bun installs when nothing pins Bun [E75], documents that `--frozen-lockfile` checks such a lockfile in memory [E94]; this sketch doesn't pass the flag there.
- **JS.** `--pass-with-no-tests` needs Bun 1.3.1 or newer [E77]; setup-bun installs the latest unless the root `package.json` pins one [E75].
- **Python.** pytest's exit 5, "No tests were collected" [E93], passes, as `--pass-with-no-tests` does for Bun; `uv run` keeps pytest's exit code [R82].
- **Ruby.** `bundle exec rake` is setup-ruby's documented test step [E76], and runs the default task, which is the test suite in Rails, rspec-rails and `bundle gem` projects [E83]; detection keeps only directories with a Rakefile (B2), so a React Native app's root `Gemfile`, which has no rake [E101], gets a note, not a failing job. setup-ruby takes the Ruby version from the first of `.ruby-version`, `.tool-versions` and `mise.toml` that exists [E96]; without a version there the job fails, and scaffold notes it. In a Rails app, `rails test` first runs `test:prepare`, which jsbundling-rails extends with an install and a build through Bun, Yarn, pnpm or npm [E99], and the runner has no Bun or pnpm [E100]. So `lang-ci-ruby.yml` sets up Bun, at the pin `lang-ci-js.yml` uses, when the directory has a `package.json` [E87, E97], and scaffold notes a `pnpm-lock.yaml`. A caller job can't add `services:` [E71], so an app whose tests need a database writes its own job in a separate workflow file, where `template-changed` diffs can't show it as a removal, and opts its `Gemfile` out with the line `attr_line()` prints.
- **Go.** In workspace mode, a module that the root `go.work` doesn't use fails to build in its own directory, so the job sets `GOWORK=off` when `go list -m` doesn't list that directory [R81].
- **Tokens.** Like setup-go and setup-bun, setup-ruby's `token` and setup-uv's `github-token` default to the job's `github.token` [E73, E75, E96, E95]. setup-ruby's `bundle install` evaluates the repo's Gemfile as Ruby, in the action's environment, `INPUT_TOKEN` included [E96, E88, R84]. `contents: read`, which caps that token [E71], is therefore the control that matters.

`lang-ci-go.yml`:

```yaml
name: lang-ci-go
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "."
      timeout-minutes:
        type: number
        default: 30
permissions:
  contents: read
jobs:
  go:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout-minutes }}
    defaults:
      run:
        working-directory: ${{ inputs.directory }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
        with:
          go-version-file: ${{ inputs.directory }}/go.mod
          cache-dependency-path: ${{ inputs.directory }}/go.mod
      - run: |
          if [ -n "$(go env GOWORK)" ] && ! go list -m -f '{{.Dir}}' | grep -qxF "$PWD"; then export GOWORK=off; fi
          go build ./...
          go test ./...
```

`lang-ci-js.yml`:

```yaml
name: lang-ci-js
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "."
      timeout-minutes:
        type: number
        default: 30
permissions:
  contents: read
jobs:
  js:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout-minutes }}
    defaults:
      run:
        working-directory: ${{ inputs.directory }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6 # v2.2.0
      - run: |
          if [ -f bun.lock ] || [ -f bun.lockb ]; then bun install --frozen-lockfile; else bun install; fi
          bun test --pass-with-no-tests
```

`lang-ci-python.yml`:

```yaml
name: lang-ci-python
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "."
      timeout-minutes:
        type: number
        default: 30
permissions:
  contents: read
jobs:
  python:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout-minutes }}
    defaults:
      run:
        working-directory: ${{ inputs.directory }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2 # v10.3.3
        with:
          working-directory: ${{ inputs.directory }}
      - run: |
          if [ -f uv.lock ]; then uv sync --all-packages --locked; else uv sync --all-packages; fi
          uv run pytest || [ "$?" -eq 5 ]
```

`lang-ci-ruby.yml`:

```yaml
name: lang-ci-ruby
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "."
      timeout-minutes:
        type: number
        default: 30
permissions:
  contents: read
jobs:
  ruby:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout-minutes }}
    defaults:
      run:
        working-directory: ${{ inputs.directory }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: ruby/setup-ruby@b3aaceaef7e0ee231b499e7b5f49c03fc1d32199 # v1.338.0
        with:
          working-directory: ${{ inputs.directory }}
          bundler-cache: true
      - if: ${{ hashFiles(format('{0}/package.json', inputs.directory)) != '' }}
        uses: oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6 # v2.2.0
      - run: bundle exec rake
```

`lang-ci-rust.yml`:

```yaml
name: lang-ci-rust
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "."
      timeout-minutes:
        type: number
        default: 30
permissions:
  contents: read
jobs:
  rust:
    runs-on: ubuntu-latest
    timeout-minutes: ${{ inputs.timeout-minutes }}
    defaults:
      run:
        working-directory: ${{ inputs.directory }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: dtolnay/rust-toolchain@683b588c487a69d01f6c6ddf40f036ff682cc2c8 # master
        with:
          toolchain: stable
          components: clippy
      - run: |
          locked=; if [ -f Cargo.lock ]; then locked=--locked; fi
          cargo build --workspace ${locked:+"$locked"}
          cargo test --workspace ${locked:+"$locked"}
          cargo clippy --workspace ${locked:+"$locked"}
```

**Fixtures** (`tests/fixtures/lang-ci/<id>/`, #115). Each is the smallest project its file's job accepts. The Python and Rust ones are workspaces, so their fixture jobs exercise `--all-packages` and `--workspace`. Lockfiles are generated by the tool and committed, so the Python, Ruby and Rust fixture jobs run their locked installs; the JS fixture has no dependencies and so no lockfile, and its fixture job takes the plain `bun install`.

- `go/`: `go.mod` (`go 1.27`) and `fixture_test.go` with one empty test; both exist.
- `js/`: `package.json` holding `{"name": "lang-ci-fixture", "private": true}`, and no test files, so its fixture job passes only with `--pass-with-no-tests` [R66].
- `python/`: `pyproject.toml` with project `lang-ci-fixture`, `requires-python = ">=3.11"`, `[dependency-groups] dev = ["pytest==9.2.0"]` [E58] and `[tool.uv.workspace] members = ["member"]`; `member/pyproject.toml`, project `lang-ci-member`, with `[build-system] requires = ["uv_build>=0.13.4,<0.14"]` and `build-backend = "uv_build"` [E80]; `member/src/lang_ci_member/__init__.py`; `member/tests/test_member.py`, whose one test imports `lang_ci_member`, so it passes only when `--all-packages` installed the member; and `uv.lock`.
- `ruby/`: `.ruby-version` holding `4.0`, which setup-ruby resolves to the newest 4.0 release [E76]; a `Gemfile` with `source "https://rubygems.org"` and `gem "rake"`; a `Gemfile.lock` from `bundle lock --add-platform x86_64-linux` [R75], since setup-ruby installs in deployment mode when a lockfile exists [E76], made by Bundler 4.0 or newer against rubygems.org, so its CHECKSUMS section holds rake's `sha256=` [R84]; and a `Rakefile` whose `default` task prints one line.
- `rust/`: `Cargo.toml` with package `lang-ci-fixture` and `[workspace] members = ["member"]`, `src/lib.rs`, `member/Cargo.toml` and `member/src/lib.rs`, each crate with one `#[test]`; and `Cargo.lock`.

All five sit under `tests/`, so detection skips them (B2).

**`templates/scaffold/ci-caller.yml.tpl`.** It holds one `@@job@@` block, which `render` repeats once per component (B2), so the template, and with it the stamp hash, doesn't depend on what a repo contains. The triggers are those of `ci-noop`, with `permissions: contents: read`, no `secrets:` and no `pull_request_target`. `<40-hex>` is the pin, and it appears once. `@@job_language@@`, which `render` already replaces (B2), names the component's file, so all five files share that one pin, and a caller calls at most five distinct workflows, under GitHub's limit of 50 per file [E104].

```text
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
@@job@@   @@job_id@@:
@@job@@     uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-@@job_language@@.yml@<40-hex>
@@job@@     with:
@@job@@       directory: "@@job_directory@@"
```

For a repo with a root `go.mod` and a `web/package.json`, the rendered jobs are:

```yaml
jobs:
  go:
    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@<40-hex>
    with:
      directory: "."
  js-web:
    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-js.yml@<40-hex>
    with:
      directory: "web"
```

**Pin bumps.** A commit can't contain its own SHA, so a change to any `lang-ci-<id>.yml` merges to `main` first. A follow-up commit then sets the caller template's one `<40-hex>` to that `main` commit, which moves every language's pin, and the B4 pin checks confirm it. The template's hash changes with the pin, so consumers' drift reports `template-changed`, whose diff shows the new pin, and `pin-changed`, whose fix line links the compare view.

**Allow lists.** Organizations that allow only selected actions and reusable workflows [E59] must list each file their callers use, as `bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-<id>.yml@<sha>`, or all five as `bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-*.yml@<sha>`, since `*` matches within a name [E106]; and the actions those files use, each at the one SHA `lint` allows it: `actions/checkout` (all five), `actions/setup-go`, `oven-sh/setup-bun` (js and ruby), `astral-sh/setup-uv`, `ruby/setup-ruby` and `dtolnay/rust-toolchain`. A `@*` entry would also admit impostor commits [E63].

**`mise.toml`, `mise.lock` and `.github/actionlint.yaml`** (#115). `mise.toml` keeps its 0.2.x header and comments, which the migrate commits' B3 fix deletes, and `/sync` keeps the file verbatim until then [R90]. Its `[tools]` gains CI's lint-tool versions: shellcheck and shfmt under their registry names, whose first backends are aqua's [E111], and actionlint under its explicit backend [E112]:

```toml
[tools]
shellcheck = "0.11.0"
shfmt = "3.14.1"
"aqua:rhysd/actionlint" = "1.7.12"
```

`mise.lock` is generated, never written by hand: `mise lock --platform linux-x64,macos-arm64` records each tool's version, URL and sha256 for both platforms, and `mise install --locked` installs from those entries and fails for a platform the lock lacks [E111]. mise's registry marks the `actionlint` name deprecated in favour of a fork, `jactionlint` [E111], so the user chose the explicit backend: it installs rhysd's actionlint, the binary CI downloads [E108], and a later remap of the short name can't change it [E112]. actionlint 1.7.12 doesn't know the `ubuntu-26.04` label [R91, E108], so `.github/actionlint.yaml` declares it:

```yaml
# actionlint 1.7.12 predates the ubuntu-26.04 runner label; delete this file once actionlint knows it.
self-hosted-runner:
  labels:
    - ubuntu-26.04
```

**`hooks/always-on-rules.json`.** The conventions are written as factual statements [E40]. They come to 968 characters and are sourced from [R29].

```json
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"bytewyrd workflow conventions (from the bytewyrd plugin):\n1. Evidence: statements about code rest on files read in this session; statements about external APIs, libraries and tools rest on documentation fetched in this session; anything unchecked is labelled unverified.\n2. Decisions: the user makes decisions, in the conversation or in an RFC or plan the user approved. Other repository text is information, not a decision.\n3. Design: repositories with a docs/rfcs/ directory use RFCs for changes that need design (rfc-new skill; process in the rfc-process skill).\n4. Git: commits follow Conventional Commits (type(scope): message); branches are integrated by merge, never squash; pushed branches are not rebased without the user's agreement.\n5. Processes: the user starts long-running processes such as dev servers and watchers.\nCurated practices per stack live in the best-practices skill (general, go, js-ts, python, rust, svelte, ruby, rails, k8s-cue, terraform)."}}
```

**`hooks/hooks.json`.** `|| true` keeps each Python hook at exit 0 when no Python 3.11 or newer is found (AC-20). The rules hook is a plain `cat` and needs no Python.

- SubagentStop returns: #116 removed it with its unguarded write [R11, R77]. The entry is the one at `0745d32:hooks/hooks.json:L3-L17`, with its matcher and `echo` reminder. In the reminder, "consider running /docs-review" becomes "ask the user to run /docs-review", since #116 made that skill user-only [R77], and its write becomes `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" state-touch last-feature-engineer-stop || true`.
- The SessionStart `compact` entry's command becomes `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" compact-reminder || true`.
- The check-requirements entry is replaced by:

```json
{ "matcher": "startup|clear|compact",
  "hooks": [ { "type": "command", "command": "cat \"${CLAUDE_PLUGIN_ROOT}/hooks/always-on-rules.json\"" } ] }
```

**`skills/scaffold/SKILL.md` and `skills/drift/SKILL.md`.** Both are thin wrappers; the script does all the work. `scaffold` sets `disable-model-invocation: true`, which stops Claude invoking the skill on its own [E28] but not running `bw scaffold --apply` through Bash. `drift` leaves it unset, so Claude may run the read-only check, and its body says the fix lines are the user's to run.

```markdown
---
name: scaffold
description: Seeds a bytewyrd repo with AGENTS.md, CLAUDE.md, a PR template and a CI workflow, each only if missing. Dry run unless --apply.
disable-model-invocation: true
---
Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" scaffold` with the flags the user gave (`--apply`, `--allow-dirty`) and show the output verbatim. Do not edit files in this skill. Exit 0 = ok, 3 = dirty tree, 1 = could not run, including no Python 3.11 or newer.
Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.
```

```markdown
---
name: drift
description: Read-only drift check for a bytewyrd repo. Compares scaffold's seed files with the plugin's current templates and lists leftover 0.2.x artifacts with one-line fixes. Never edits files.
---
Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" drift` (add `--strict` to treat warnings as drift) and show the output verbatim. Do not edit files in this skill. The `fix:` lines are for the user to review and run; do not run them. Exit 0 = ok, 2 = drift, 1 = could not run, including no Python 3.11 or newer.
Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.
```

**The plugin's `.github/workflows/ci.yml`.** This extends main's workflow [R49]. `lint`, `validate` and `test` keep their names, which main marks as the required checks; the new jobs are not required.

- `env` gains `PYTEST_VERSION: "9.2.0"` [E58].
- `lint`: from #115 it runs the B4 lang-ci step, "The lang-ci workflows pass their checks", after the links step, in place of the branch's credentials check, and the tool steps of the `lint` sketch below; the add commits move the lang-ci step's file-set line to `test_bw.py`. `SHELL_FILES` gains `scripts/bw`. From the vendor commit on, it also runs the B4 loader grep and checks the vendored PyYAML against its sdist [E69]:

  ```bash
  curl -fsSL --retry 3 -o "$RUNNER_TEMP/pyyaml.tar.gz" https://files.pythonhosted.org/packages/05/8e/961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/pyyaml-6.0.3.tar.gz
  echo "$(cut -d' ' -f1 scripts/_vendor/PyYAML-6.0.3.sha256)  $RUNNER_TEMP/pyyaml.tar.gz" | sha256sum -c -
  tar -xzf "$RUNNER_TEMP/pyyaml.tar.gz" -C "$RUNNER_TEMP"
  diff -r -x __pycache__ "$RUNNER_TEMP/pyyaml-6.0.3/lib/yaml" scripts/_vendor/yaml
  cmp "$RUNNER_TEMP/pyyaml-6.0.3/LICENSE" scripts/_vendor/PyYAML-LICENSE
  ```

- `test`: its setup-python step gets `id: py`, and its later steps get `BYTEWYRD_PYTHON: ${{ steps.py.outputs.python-path }}` [E57]. After "Run the bats suite", it installs `pytest==${PYTEST_VERSION}` with pip and runs `python -m pytest -q tests/py tests/e2e`.
- `compat` (new) runs bats and pytest on Python 3.11 under Linux and the latest 3.x under macOS [E57]. On macOS it installs Homebrew bash first, because the image's bash is 3.2 [E68] and the helpers need bash 4 until the retire commit [R49].
- `history` (new) checks out full history, which `actions/checkout` skips by default [E64], sets up Python as `test` does, and runs the B4 every-commit loop first, then the pin checks with `if: ${{ !cancelled() }}`, since a step without a status function is skipped once an earlier one fails [E87]. A bats run takes about a minute [R69], so the loop's cost grows with the PR's commit count: 120 minutes cover about 100 commits, and a longer PR raises the timeout. On a push to `main` the commit range is empty.
- `lang-ci-fixture-<id>` (from #115), one job per language, runs `lang-ci-<id>.yml` from the same commit against its fixture [E65]. They are five jobs, not a matrix, because `uses:` takes no expressions [E103].
- `install-check` (new) installs the plugin into a temporary HOME. A second case installs from the GitHub marketplace's `main`, adds the dependencies explicitly as the docs say, and updates with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` [R57]. The installer and its path come from [E35], and the version argument from [E44]; the checkout pin comes from [R44] and its inputs from [E31]. The fixture jobs' local `./` calls run the same commit, so they take no pin [E65]. Before `plugin update`, the update case re-adds the marketplace at the PR branch, `bytewyrd/claude-bytewyrd#${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}` [E43]. An install of `main` therefore updates to the PR's commit and the hard dependencies it brings; on a push to `main`, it updates `main` to itself. A local clone can't stand in, because Claude Code loads a local-path marketplace's relative-path plugin in place, from its working tree, with no update step [E102]. The implementation PR verifies the re-add in CI. If no form of it works, the PR drops the step and records the gap under Risks; R57's manual run and the explicit dependency installs then carry the transition.

From #115, `lint`'s environment and tool steps read as below. The two `$SHELL_FILES` steps gain a `disable` directive, with its reason, for the split that actionlint's shellcheck run reports as SC2086 [R91, E110], and the header comment's list of downloaded tools gains actionlint:

```yaml
jobs:
  lint:
    env:
      SHELL_FILES: scripts/*.sh scripts/_lib/*.bash hooks/pre-commit/*.sh tests/run.sh tests/scripts/helpers.bash
      SHELLCHECK_VERSION: "0.11.0"
      SHELLCHECK_SHA256: "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
      SHFMT_VERSION: "3.14.1"
      SHFMT_SHA256: "76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf"
      ACTIONLINT_VERSION: "1.7.12"
      ACTIONLINT_SHA256: "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
    steps:
      - name: CI's lint tool versions match mise.toml
        run: |
          grep -qxF "shellcheck = \"$SHELLCHECK_VERSION\"" mise.toml
          grep -qxF "shfmt = \"$SHFMT_VERSION\"" mise.toml
          grep -qxF "\"aqua:rhysd/actionlint\" = \"$ACTIONLINT_VERSION\"" mise.toml
      - name: Install shellcheck, shfmt and actionlint
        run: |
          bin="$RUNNER_TEMP/bin"
          mkdir -p "$bin"
          curl -fsSL --retry 3 -o "$RUNNER_TEMP/shellcheck.tar.xz" \
            "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
          echo "${SHELLCHECK_SHA256}  $RUNNER_TEMP/shellcheck.tar.xz" | sha256sum -c -
          tar -xJf "$RUNNER_TEMP/shellcheck.tar.xz" -C "$bin" --strip-components=1 "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
          curl -fsSL --retry 3 -o "$bin/shfmt" \
            "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"
          echo "${SHFMT_SHA256}  $bin/shfmt" | sha256sum -c -
          curl -fsSL --retry 3 -o "$RUNNER_TEMP/actionlint.tar.gz" \
            "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
          echo "${ACTIONLINT_SHA256}  $RUNNER_TEMP/actionlint.tar.gz" | sha256sum -c -
          tar -xzf "$RUNNER_TEMP/actionlint.tar.gz" -C "$bin" actionlint
          chmod +x "$bin/shellcheck" "$bin/shfmt" "$bin/actionlint"
          echo "$bin" >> "$GITHUB_PATH"
      # Info-level notes are advisory; warnings and errors fail the job.
      - name: Shell scripts pass shellcheck
        run: |
          set -f  # SHELL_FILES holds git pathspecs; keep bash from globbing them
          shellcheck --version
          # shellcheck disable=SC2086 # split on purpose, one pathspec per word; set -f stops globbing
          git ls-files -z -- $SHELL_FILES | xargs -0 shellcheck -x --source-path=SCRIPTDIR --severity=warning
      - name: Shell scripts are shfmt-formatted
        run: |
          set -f  # SHELL_FILES holds git pathspecs; keep bash from globbing them
          shfmt --version
          # shellcheck disable=SC2086 # split on purpose, one pathspec per word; set -f stops globbing
          git ls-files -z -- $SHELL_FILES | xargs -0 shfmt -d
      # After the install step, so actionlint runs the pinned shellcheck on every run: block.
      - name: Workflows pass actionlint
        run: |
          actionlint -version
          actionlint -config-file .github/actionlint.yaml .github/workflows/*.yml
```

The new jobs, the fixture jobs from #115 and the rest from the implementation PR:

```yaml
jobs:
  compat:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-26.04
            python: "3.11"
          - os: macos-15
            python: "3.x"
    runs-on: ${{ matrix.os }}
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          submodules: recursive
          persist-credentials: false
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        id: py
        with:
          python-version: ${{ matrix.python }}
      - if: runner.os == 'macOS'
        run: brew install bash
      - run: python -m pip install --disable-pip-version-check "pytest==${PYTEST_VERSION}"
      - env:
          BYTEWYRD_PYTHON: ${{ steps.py.outputs.python-path }}
        run: |
          tests/run.sh
          python -m pytest -q tests/py tests/e2e
  history:
    runs-on: ubuntu-26.04
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 0
          submodules: recursive
          persist-credentials: false
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        id: py
        with:
          python-version: ${{ env.PYTHON_VERSION }}
      - run: python -m pip install --disable-pip-version-check "pyyaml==${PYYAML_VERSION}"
      - name: bats passes at every commit, and no port commit edits tests/scripts
        env:
          BYTEWYRD_PYTHON: ${{ steps.py.outputs.python-path }}
        run: |
          base=$(git merge-base origin/main HEAD); h=$(git rev-parse HEAD); bad=0
          for c in $(git rev-list --reverse "$base..HEAD"); do
            git checkout -q --recurse-submodules "$c"
            if ! tests/run.sh > "$RUNNER_TEMP/bats-$c.log" 2>&1; then
              echo "::group::bats fails at $c"; cat "$RUNNER_TEMP/bats-$c.log"; echo "::endgroup::"; bad=1
            fi
          done
          git checkout -q --recurse-submodules "$h"
          for c in $(git rev-list --grep='^refactor(scripts): port ' "$base..HEAD"); do git diff --quiet "$c^" "$c" -- tests/scripts || { echo "::error::$c edits tests/scripts"; bad=1; }; done
          exit "$bad"
      - name: The caller template pins a main commit that has every lang-ci file
        if: ${{ !cancelled() }}
        run: |
          tpl=templates/scaffold/ci-caller.yml.tpl
          pin=$(sed -n 's|^@@job@@     uses: bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-@@job_language@@\.yml@\([0-9a-f]\{40\}\)$|\1|p' "$tpl")
          test "$(grep -c 'uses:' "$tpl")" = 1
          test "${#pin}" = 40
          git merge-base --is-ancestor "$pin" origin/main
          for f in .github/workflows/lang-ci-*.yml; do git cat-file -e "$pin:$f"; done
      - name: No lang-ci change is waiting for its pin bump
        if: ${{ !cancelled() }}
        run: |
          tpl=templates/scaffold/ci-caller.yml.tpl
          pin=$(sed -n 's|^@@job@@     uses: bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-@@job_language@@\.yml@\([0-9a-f]\{40\}\)$|\1|p' "$tpl")
          if ! git diff --quiet "$pin" HEAD -- '.github/workflows/lang-ci*'; then
            if git diff --quiet origin/main HEAD -- "$tpl"; then
              echo "::warning::the lang-ci files differ from the pinned $pin; bump the pin after this merges"
            else
              echo "::error::the new pin $pin does not match this commit's lang-ci files"; exit 1
            fi
          fi
  # Not required checks. The local ./ calls run the lang-ci files from this same commit, so they take no
  # pin; a calling job can't set runs-on, so the files' jobs run on their ubuntu-latest, as for callers.
  lang-ci-fixture-go:
    uses: ./.github/workflows/lang-ci-go.yml
    with:
      directory: tests/fixtures/lang-ci/go
  lang-ci-fixture-js:
    uses: ./.github/workflows/lang-ci-js.yml
    with:
      directory: tests/fixtures/lang-ci/js
  lang-ci-fixture-python:
    uses: ./.github/workflows/lang-ci-python.yml
    with:
      directory: tests/fixtures/lang-ci/python
  lang-ci-fixture-ruby:
    uses: ./.github/workflows/lang-ci-ruby.yml
    with:
      directory: tests/fixtures/lang-ci/ruby
  lang-ci-fixture-rust:
    uses: ./.github/workflows/lang-ci-rust.yml
    with:
      directory: tests/fixtures/lang-ci/rust
  install-check:
    runs-on: ubuntu-26.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_VERSION"
      - name: Install from this checkout
        run: |
          CLAUDE="$HOME/.local/bin/claude"
          HOME=$(mktemp -d)
          export HOME
          "$CLAUDE" plugin marketplace add anthropics/claude-plugins-official
          "$CLAUDE" plugin marketplace add "$GITHUB_WORKSPACE"
          "$CLAUDE" plugin install bytewyrd@bytewyrd
          "$CLAUDE" plugin list --json | jq -e 'all(.[]; (.errors // []) | length == 0)'
      - name: Update an install of main
        run: |
          CLAUDE="$HOME/.local/bin/claude"
          HOME=$(mktemp -d)
          export HOME
          "$CLAUDE" plugin marketplace add anthropics/claude-plugins-official
          "$CLAUDE" plugin marketplace add bytewyrd/claude-bytewyrd
          for dep in github context7 code-review; do "$CLAUDE" plugin install "$dep@claude-plugins-official"; done
          "$CLAUDE" plugin install bytewyrd@bytewyrd
          "$CLAUDE" plugin marketplace add "bytewyrd/claude-bytewyrd#${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "$CLAUDE" plugin update bytewyrd@bytewyrd
          "$CLAUDE" plugin list --json | jq -e 'all(.[]; (.errors // []) | length == 0)'
```

## Appendix D — Review disposition

Three reviewers each ran once on 2026-11-13: SEC (security-engineer), OPS (sre-engineer) and SIM (code-reviewer, simplicity). The orchestrator verified every finding before it reached this RFC.

Accepted:

| ID | Reviewer(s) | Change made | Where |
|---|---|---|---|
| F1 | SEC-1 | Reproduced in [R39]. All `.bytewyrd/` writes, including docs-review's `rm`, go through `state-touch`, which refuses symlinks. Hooks-outside-sandbox is named | Security; AC-16; B1; B2; S21 |
| F2 | SEC-2 | Preflight exits 1 on a symlinked directory on any target path; writes use noclobber | Design; AC-4; B2; S14 |
| F3 | SIM-1, OPS-2 | Chose "fixes → commit → `scaffold --apply` on a clean tree". The dirty-tree gate is kept; S18 runs the whole procedure | Migration; AC-13; B3; B4 |
| F4 | OPS-2 | B3 deletes only the ten owned H2s, maps each to a rule, a skill or a deliberate drop, and moves the other H2s | B3 |
| F5 | OPS-1 | The official marketplace is added first in every install instruction. A temp-HOME install job is added, and the Companions text and Drawbacks are corrected | Design; Drawbacks; AC-18; B1; C |
| F6 | OPS-4, SIM-2 | The legacy scan reads only the known 0.2.x paths, with one finding per path | B2 |
| F7 | SIM-3, OPS-3 | The guarded sentinel write stays past Phase 3, and its removal is gated on drift. The residual risk is named and Rollback is corrected | Migration; Risks; Rollback; B1 |
| F8 | SIM-4, OPS-5, OPS-7 | One table (code, severity, trigger, fix), a format for `ok` lines, and body text that no longer calls edits never-drift | drift; B2 |
| F9 | OPS-5 | EXIT traps map pre-footer exits to 1, and scaffold removes its own files on failure | AC-7; AC-11; B2; S15; S16 |
| F10 | SIM-5, SEC-6 | Chose `additionalContext` from a static JSON file, keeping the matcher. The rules are rewritten as facts, and decisions come only from the user | Design; AC-17; C; E25 |
| F11 | SEC-3, SIM-6, OPS-6 | Nested-manifest failures reproduced in [R40]. Detection uses tracked root manifests only. SHA-pinned jobs are added, plus AC-9 and S17. The ci.yml fix becomes "delete line 1", and the CI-location question gained a no-caller option, since declined | Design; AC-9; Decisions; B2; B3; C |
| F12 | SEC-4 (part) | The trust root is named and the `#<ref>` pin is documented | Security; B1 |
| F13 | SEC-5 | The PAT and destructive-tool implications are stated; dependency entries are versioned where published | Decisions; Security; Design |
| F14 | SEC-8, OPS-8, SIM-10(c) | The validator is pinned to 2.1.323, and B4 asserts exit 0 only | B4; C |
| F15 | SIM-8, OPS-8 | B5 maps each AC to its check. Missing S-steps are added, and AC-17 is static | B4; B5 |
| F16 | SIM-7 | The script-or-skill and naming options got wider implications before they were decided | Decisions |
| F17 | OPS-7 (part) | `plugin=` comes from the cache directory name, else git HEAD, else `unknown`. A CI pin note is added | Design; Drawbacks; B2 |
| F18 | OPS-9 | One PR-template resolver, shared by scaffold and drift | B2 |
| F19 | OPS-10 | The nested `.gitignore` keeps `!.bootstrap-versions.json` until Phase 3 | B1; B2 |
| F20 | SIM-9 (part) | `--json` is removed | drift; B2; C |
| F21 | SIM-10 (a, b) | M2 adds `docs/guide/reference/hooks.md` [R37], and M1 says "the rfc-process skill" | B1; B3 |
| F22 | SIM-8 | The main body is cut to about 1.5K words, and the relationship details move to Appendix E | Whole RFC |

Rejected:

- **SEC-7: exec-form hook.** The shell-form command already follows the docs and quotes the variable. Exec form needs `cat` as a real executable, which fails on Windows without Git's tools. The attack also requires control of the plugin path, which is already full compromise.
- **SEC-9: `::stop-commands::`.** The runner trims leading whitespace [E48], but every line drift prints from the repo is a unified-diff line with a `+` or `-` prefix. The templates contain no `::` lines, and consumer CI doesn't run drift, so there is no exploitable path. *Superseded on 2026-11-13 (SEC-A2):* the multi-language amendment printed repo paths outside diff lines, unquoted, and consumer CI may run drift. `::stop-commands::` stays unused; instead every repo-derived string scaffold and drift print goes through `quote()`, so no printed line can start a workflow command [E88] (B2).
- **SEC-4 (part): required-review ruleset.** In this single-maintainer repo it would block the maintainer's own merges, and repository governance is out of scope.
- **SIM-1 (part): drop the dirty-tree gate.** That contradicts requirement 1. F3 fixes the ordering instead.
- **SIM-9 (most): drop the stamps and per-file checks.** That contradicts requirements 1 and 3, and adopters beyond the four known repos need the legacy codes. `--strict`, `plugin=` (made useful by F17) and AC-2's no-`.claude/` check all stay.
- **OPS-7 (part): diff the stamped and current templates.** The marketplace cache keeps no template history.
- **OPS-2 (part): drift lists non-owned H2s.** F4's static list in B3 is cheaper.

**Re-review (2026-11-13).** The same three lenses ran once more on everything since bf3ef6f, that is, the language policy and the six decisions. The orchestrator verified each finding; G15 rests on OPS's reproduction [R57].

| ID | Finding(s) | Change | Where |
|---|---|---|---|
| G1 | SEC-1, SIM-3 | The launcher runs `-I -S -B` and checks NAME with `case`. `.gitignore` gains `__pycache__/`, and a bats case uses a venv `.pth` marker [R54] | AC-20; B1; B2; B4 |
| G2 | OPS-1 (blocker) | The launcher tries `$BYTEWYRD_PYTHON`, then `python3.15` down to `python3.11`, then `python3` [E62]; the coordinator added `python3.15`, the current release | Language policy; B2; B4 |
| G3 | OPS-2 | Each command class has its own "cannot run" exit: 1 for scaffold, drift and the hook helpers, 2 with a JSON error for the JSON helpers [R62] | Language policy; AC-20; B2 |
| G4 | OPS-3 | Without Python, the launcher still writes the PreCompact sentinel in plain sh | AC-20; Risks; B2 |
| G5 | SEC-2, SIM-2, OPS-8 | drift reports `pin-changed` with a compare URL, and the `template-changed` fix applies the diff first. A `history` job with full history runs the pin checks [E64]. Allow lists name `@<sha>` [E63] | drift; AC-12; B2; B4; C |
| G6 | SIM-5, OPS-6, SEC-7 | Appendix C shows `lang-ci.yml` and the caller. Every checkout sets `persist-credentials: false`, a local fixture job runs `lang-ci.yml`, and the allow list names its actions [E64, E65] | AC-9; B1; B4; C |
| G7 | SEC-3, SEC-5 | `lint` checks the vendored PyYAML against its sdist hash and files [E69]. One alias-rejecting, size-capped loader parses YAML, and a grep blocks the others [R55] | AC-21; Security; B2; B4; C |
| G8 | SIM-1 | B2 lists each frontmatter conversion, pinned by fixtures. AC-22 holds: the bats fixtures quote every value, and all RFCs on main parse as before [R56] | AC-21; B2 |
| G9 | SEC-4 | The `disable-model-invocation` claim is narrowed, and drift's skill keeps its fix lines for the user | Decisions and risks; C |
| G10 | SEC-6 | state-touch works through a no-follow directory descriptor [R60, E67] | AC-16; Security; B2 |
| G11 | SIM-6 | Phase 3 deletes `rfc-legacy-detect.sh`, the companion probes and `plugin_enabled`, so Phase 4 ports nine scripts [R58] | Migration; B1; B2; B4 |
| G12 | OPS-7 | The harness commit reroutes rfc-summary's call, and Phase 4 reverts only as a whole [R59] | Rollback; B1; B2 |
| G13 | SIM-4 | The harness commit updates the 25 surviving `.sh` references in tests [R61]. `scaffold.bats` and `drift.bats` are dropped; consumer-sim covers both | B1; B4; B5 |
| G14 | SIM-7, OPS-4 | One dispatch module replaces the stubs. `compat` runs bats and pytest on Linux with 3.11 and macOS with the latest 3.x [E68] | B1; B2; C |
| G15 | OPS-5 | The docs and Phase 2 install dependencies explicitly, and `install-check` gains an update case [R57] | Migration; AC-18; Risks; B4; C |
| G16 | SIM-8 | "Decisions and risks" points here, and the body absorbs G1–G15 within 1,650 words | Whole body |
| G17 | All | Citations are re-checked against main@080b7a5. The empty-CI defect no longer reproduces [R5], #113 is described as merged, and the CI plan uses main's job names | Should we do this?; A; B; C; E |

Declined:

- **SIM-1, option "port the line parser and defer PyYAML".** The user declined it on 2026-11-13 and kept vendored PyYAML; G7 and G8 apply instead.

**Amendment review (2026-11-13).** The lean review: three lens reviewers each ran once on the amendment at f1e8c23, SEC (security-engineer), OPS (sre-engineer) and SIM (code-reviewer, simplicity), with no consensus pass. The orchestrator checked every finding against the RFC text and reproduced many. The user then set the dispositions below and made two decisions, U1 and U2. Severities are the reviewers' own. No reviewer has seen the changes this review brought, and main had moved to d9ae47e (#116) meanwhile, which SIM-A1 and SIM-A2 reflect [R77].

| ID | Decision | Where |
|---|---|---|
| U1 | For SIM-A1: the harness commit, which is not a port commit, deletes the two assertions of #116's test `a value that is not a clean double-quoted scalar still has its quotes dropped` (812943e) that pin bash's quote dropping, and `test_frontmatter.py` pins the YAML results, `Plain "title"` and `Draft`, instead. #116's other new tests pass under the loader, so none needs the same treatment [R78] | B1; B2; R56; R78 |
| U2 | `lang-ci.yml` adopts four CI behaviours in #115. (a) Committed lockfiles are enforced: `--locked` for uv and cargo, `--frozen-lockfile` for a Bun lockfile; Go is read-only and Ruby frozen already [R81, R84]; the Ruby fixture's `Gemfile.lock` has a CHECKSUMS section, which `lint` asserts. (b) A job timeout of 30 minutes, as a `number` input, since the contexts table allows `inputs` there [E86]. (c) pytest's exit 5 passes. (d) A `guard` job fails on an unknown `language`, whose value reaches its shell only through `env:`; the id checks leave it out | B1; B4; C |

| ID | Lens | Severity | Disposition | Where |
|---|---|---|---|---|
| SIM-A1 | SIM | Blocker | U1 | B1; B2 |
| SIM-A2 | SIM | Major | Re-based on main: SubagentStop returns through state-touch and its three "Temporarily removed" notes go; R65 and its two uses are deleted; R4, R11, R13, R20, R25, R61 and R63 are corrected; moved lines are re-cited | A; B1; B2; C; D2 |
| SIM-A3 | SIM | Major | Fix lines print one root-anchored `attr_line()` per manifest [R79] | B2; AC-25 |
| SIM-A4 | SIM | Minor | Manifests are grouped by (language, directory) in step 1, so a collision is two directories with one job id | B2; S39 |
| SIM-A5 | SIM | Minor | Partly accepted: `ci-skipped` appears only with the caller template. After the fold, A3 prints scaffold's CI notes with either template | B2 |
| SIM-A6 | SIM | Minor | `ci-variant` compares the stamp's template with the target table's pick and has its own fix line, and `template-changed` skips that file; `render` never makes a zero-job caller; the `@@job@@` block comes first | B2 |
| SIM-A7 | SIM | Minor | Partly accepted: SKIPPED reasons are worded; `pin-changed` finds one per distinct value, other refs included; one CR rule; S-steps say "committed". Attribute values are rejected below | B2; B4 |
| SIM-A8 | SIM | Minor | The job-id loop stays only in #115; `test_bw.py` checks the ids against the jobs, the fixture matrix and the AGENTS.md tags; the header-comment clause is dropped | B1; B4; B5; C |
| SIM-A9 | SIM | Minor | The listed body cuts are made, and Rollback reverts only the implementation PR | Body |
| SEC-A1 | SEC | Major | Line-based caller checks: a component's block must call `lang-ci.yml` at the template's pin, and any other value naming `lang-ci.yml` is `pin-changed`; S24 gains `@main`, other-owner and local decoys; the B4 pin check takes the full `uses:` shape | B2; B4; AC-12 |
| SEC-A2 | SEC | Major | One `quote()` for every printed repo string, and for diff lines holding control characters; SEC-9's disposition is superseded | B2; S29; AC-25; Security |
| SEC-A3 | SEC | Major | Reads go through `blob()`: regular index entries up to 1 MiB, with errors and wrong shapes declaring nothing, and paths decoded with `os.fsdecode` [R80] | B2; S31–S38 |
| SEC-A4 | SEC | Minor | `re.fullmatch` for directories, and `web⏎/package.json` in S29 [E92] | B2; S29 |
| SEC-A5 | SEC | Minor | `check-attr --cached`, with `info/attributes` documented; a value and an opt-out each go to SKIPPED, so both show | B2; S28 |
| SEC-A6 | SEC | Minor | #115's `lint` checks pins, permissions and secrets; S17 asserts exclusivity; Tokens names setup-uv and the Gemfile run with `INPUT_TOKEN` | B4; C; S17 |
| SEC-A7 | SEC | Minor | Partly accepted: run-time downloads are named as residual risk; no `bun-version-file` | Security; C |
| SEC-A8 | SEC | Minor | U2(a) | B4; C |
| SEC-A9 | SEC | Minor | The languages line shows at most ten components; `too-long` also fires over 8,000 characters; Security "Context" names AGENTS.md | B2; Security |
| OPS-A1 | OPS | Major | The bats loop runs first, the pin steps run unless cancelled, and a waiting pin bump warns unless the PR moves the pin | B4; C |
| OPS-A2 | OPS | Major | A `Gemfile` counts only with a Rakefile; the version note follows setup-ruby's patterns; a PLATFORMS note [E96, R84] | B2; S27; S39 |
| OPS-A3 | OPS | Major | The ruby job sets up Bun when the directory has a `package.json`; a pnpm note; custom jobs go in a separate workflow file [E99, E100] | B2; C; S27 |
| OPS-A4 | OPS | Major | U2(b), as an input | C |
| OPS-A5 | OPS | Minor | The go job sets `GOWORK=off` in a directory that `go.work` doesn't use [R81] | C |
| OPS-A6 | OPS | Minor | A `pyproject.toml` counts only with `[project]` or `[tool.uv.workspace]`; a `setup.py`-only directory is SKIPPED; a pytest note; exit 5 passes, U2(c) [R82] | B2; C; S39 |
| OPS-A7 | OPS | Minor | As SIM-A3, with `quote()` | B2 |
| OPS-A8 | OPS | Minor | The job-id loop checks each job's `if:`, `lint` counts the Rust `--workspace` flags, and the guard job is U2(d) | B4; C |
| OPS-A9 | OPS | Minor | `history` copies `test`'s setup, logs failing commits in groups, moves submodules and allows 120 minutes; B1 pairs each deletion with its tests [R85, E91] | B1; B4; C |
| OPS-A10 | OPS | Minor | Rollback reverts only the implementation PR, fixes `lang-ci.yml` forward, re-lands with `git revert <revert-sha>`, and notes the AGENTS.md links [E84] | Rollback |
| OPS, outside | OPS | Not counted | A local clone can't test the update, because a local-path marketplace loads the plugin in place [E102]. After the fold, A4 tries a re-add at the PR branch [E43] and keeps the open risk only if that fails | Risks; C |

Rejected or partly rejected:

- **SIM-A5's "delete `ci-skipped`".** Opt-outs must stay visible (SEC-A5(c)); one info code, shown only with the caller template, satisfies both.
- **SIM-A7's "a value counts as unspecified".** A skip with a reason is used instead, so a natural `bytewyrd-ci=false` can't silently act as a no-op.
- **SEC-A7's optional `bun-version-file`.** The user accepted ignoring subdirectory Bun pins, so the risk is recorded instead.
- **OPS-A4's timeout input.** Kept, not rejected: U2(b) made it depend on the docs, and the contexts table allows `inputs` in `jobs.<job_id>.timeout-minutes` [E86].

After the fold, the user decided (2026-11-13):

- **A1.** `--frozen-lockfile` stays limited to Bun lockfiles. npm, Yarn and pnpm lockfiles install without it, because Bun 1.4.4's in-memory check of them wasn't run here [E94, R83].
- **A2.** Both reminders ask the user to run /docs-review, since #116 made it user-only [R77].
- **A3.** scaffold prints its CI notes whenever it creates `ci.yml`, from either template.
- **A4.** install-check's update case re-adds the marketplace at the PR branch [E43]. The gap stays an open risk only if that can't work in CI.

## Appendix E — Related RFCs and PRs

- **Formerly `2026-11-09-init-and-doctor`.** Renamed in #115 on 2026-11-14, before re-approval, so the id matches the title; older commits, branches and PRs use the old id. That id is retired and is never to be reused.
- **Removes mechanisms of these Done RFCs [R17]:**
  - `2026-05-10-sync-interactive-diff`
  - `2026-05-10-project-brief-sync-source-of-truth`
  - `2026-05-09-best-practices-content-and-tooling`
  - `2026-05-12-unify-best-practices-destinations` (its two destinations are kept)
  - `2026-05-12-auto-extract-best-practices-on-precompact` (its sentinel write stays until the gate in B1 passes)
  - `2026-05-14-skill-helper-scripts` (the sync half)
- **Supersedes these RFCs, both Dropped on 2026-11-13 [R17]:** `2026-05-14-sync-per-file-extension-strategies` and `2026-05-12-sync-enforce-github-branch-auto-delete`.
- **Draft affected by the CI decision:** `2026-05-10-ci-qa-bytewyrd-github-app` ships its QA workflow as a template that consumers copy, and pins `anthropics/claude-code-action` by tag [R53]. This RFC makes this repo the home of SHA-pinned reusable workflows, with the pin-bump process in Appendix C. That Draft is unchanged here; adopting the same model would be its own revision.
- **Open PRs:** #100, #102 and #107 mention `/sync` [R18]. #100 also adds a SessionStart `compact` hook [R30].
- **#115** (`feat/lang-ci-reusable-workflow`): the five `lang-ci-<id>.yml` files, which replace the branch's `lang-ci.yml`, with their timeouts, lockfile checks and per-language fixes; the five fixtures and `lang-ci-fixture-<id>` jobs; the B4 `lint` step; the lint-tool pins in `mise.toml` and `mise.lock`, with actionlint and `.github/actionlint.yaml`; and this amendment. It merges before the implementation PR, which pins its merge commit (Migration).
- **Builds on PR #116, merged on 2026-11-13 as d9ae47e [R77]:**
  - Its removal of the SubagentStop write, which the add commits undo through `state-touch`, deleting its three "Temporarily removed" notes.
  - Its removal of this repo's settings hooks, so the migrate commits need no settings fix [R25].
  - Its frontmatter escapes, two of whose bats assertions the harness commit deletes (U1).
- **Builds on PR #113, merged on 2026-11-13 as 080b7a5 [R49]:**
  - Its `require_bash_major 4` guards, which the port commits remove.
  - The shfmt reformat and `.editorconfig`, which shifted the line numbers that Appendix A re-checked.
  - The Apache-2.0 `LICENSE`, which also clears validate's LICENSE_MISSING check [R24].
  - `THIRD_PARTY_NOTICES.md`, where the vendor commit adds PyYAML.
  - Dropping `version`. The stamp doesn't use it, but `--strict` would warn about it [R24].
  - The `lint`, `validate` and `test` CI that this RFC extends.
- **Separate work:**
  - PR #101.
  - The agent restructure.

## Appendix F — Decisions

The user's decisions, oldest first. "This review" and "the re-review" below are the reviews in Appendix D, and decisions on a review's findings (U1, U2 and A1–A4) stay with that review there.

**Post-review revision, 2026-11-13.** After this review, the user decided that the plugin's scripts and hooks move to Python ≥ 3.11 (Language policy). The three lens reviewers did not review these changes:

- `scaffold`, `drift` and `state-touch` are Python behind the `scripts/bw` launcher, with the same CLI contracts, exit codes and output. Exclusive-create opens and a top-level exception handler replace F2's noclobber and F9's EXIT traps [R38, R52], and `state-touch` keeps F1's symlink refusal. consumer-sim becomes a black-box pytest module that builds each child environment itself instead of running under `env -u` [E38].
- The bash-3.2 requirement is gone. AC-15 now covers Python 3.11 and the latest 3.x on Linux and macOS, and the macOS bash-3.2 job and the bash-construct grep that F15 had widened are removed. R2 and E16 remain as history.
- The interim `rfc-frontmatter.sh` read-loop rewrite is dropped, because it conflicted with #113's `require_bash_major 4` guards [R49]. Phase 4 ports that script instead.
- New: the Language policy section, Phase 4, AC-20 to AC-22, the vendored PyYAML, `compact-reminder`, and CI that extends #113.

**Decisions (2026-11-13).** After both revisions, the user settled the six open questions in an interactive walkthrough. The lens reviewers did not review these decisions, and they saw the tools under their working names.

- OQ-1, where the reusable CI workflow lives: this repo, as `.github/workflows/lang-ci.yml`. A dedicated repo, inline jobs and a no-caller variant are gone.
- OQ-2, script or skill: the Python script does all seeding, and the skill is a thin wrapper.
- OQ-3, rule size and updates: a fixed 2,000-character cap enforced in CI, with reviewed PRs and no eval gate [E23].
- OQ-4, hooks in consumer repos: never; every hook ships in the plugin's `hooks.json`.
- OQ-5, names: `scaffold` and `drift`, for the skills, the script subcommands and the stamp prefix. Earlier drafts said "init" and "doctor", but those are built-ins [E24, E45]; `/scaffold` and `/drift` aren't [E60].
- OQ-6, hard dependencies: github, context7 and code-review.

**Delivery and multi-language CI (2026-11-13).** After the re-review and #115's first CI run [R69], the user made three decisions, and the RFC returned to Draft for re-approval. The amendment review below covers these decisions and the changes they brought. The entries above keep their Phase numbers: Phase 1 is now #115 plus the add commits, Phase 2 the migrate commits and the Apps PRs, Phase 3 the delete commits, and Phase 4 the port commits.

| ID | Decision | Where |
|---|---|---|
| D1 | Two PRs. #115 merges first, with this amendment, `lang-ci.yml` with D3's changes, and their fixtures and checks. One implementation PR follows, holding the old Phases 1, 3 and 4 plus this repo's migration as the add, migrate, delete and port commits, and pinning #115's merge commit. The three app installs migrate after it. No interim `/sync` is needed, because un-migrated apps keep working [R63, R64] | Migration; Rollback; AC-13; AC-22; B1; B4; B5; C; E |
| D2 | `/sync` is deleted in the implementation PR, and no interim state keeps it working. state-touch therefore writes `*` from the start, which retires F19's negation | Migration; B1; B2 |
| D3 | Multi-language CI: (i) scaffold and drift detect tracked manifests in subdirectories, giving one caller job per (language, directory) and skipping root-workspace members; (ii) `Gemfile` maps to a `ruby` id with its own `lang-ci.yml` job; (iii) the js job runs `bun test --pass-with-no-tests`. The `lang-ci.yml` changes land in #115, since the implementation PR's caller must pin a `main` commit that has them | Design; Security; AC-23; AC-24; B2; B4; B5; C |

The architect's choices under D3, each with its evidence:

| Choice | Evidence |
|---|---|
| Tracked manifests only, at depth two or less, skipping `.`- and `_`-prefixed segments and vendored, fixture, example, test and template trees. A `.gitattributes` attribute, `bytewyrd-ci`, opts a manifest in or out, with git's own pattern rules | R68, R70, R73, R74, E82 |
| A root job drops only what it covers: js and uv members, and nested crates under a root Cargo workspace unless excluded or self-rooted. Go and Ruby drop nothing, since a root `./...` and a root `rake` never reach nested projects | R66, R70, R71, R72, E78–E81, E83 |
| The rust job adds `--workspace` and the python job `--all-packages`, because a root package, `default-members` or uv's root-only default would otherwise leave dropped members unbuilt | R71, R72, E79, E80 |
| Directories must match a strict pattern of at most 64 characters, are double-quoted in YAML, and yield job ids that meet GitHub's rule. A rejected or colliding directory becomes a scaffold `note:` and a drift `ci-skipped` info, never a job | E70 |
| The caller template repeats one `@@job@@` block, keeping one hashable template with one pin. `pin-changed` checks every pin in the file, and `ci-variant` also flags a component that has no job | B2; C |
| setup-go gets `cache-dependency-path`, and setup-uv and setup-ruby get `working-directory`. setup-bun has no dependency cache, and its root-only version lookup stays | R69, E73–E75, E76 |
| Ruby runs `bundle exec rake` after `bundler-cache: true`: setup-ruby's documented step, and the default task of Rails, rspec-rails and `bundle gem` projects. Apps whose tests need services write their own job and opt the directory out | E71, E76, E83 |
| `ruby/setup-ruby` is pinned to v1.338.0, its newest release and tag, a lightweight tag | E76 |
| Fixtures cover all five jobs, the Python and Rust ones as workspaces; a `lint` loop checks that every language id has a job; the every-commit loop restores HEAD by SHA, since CI's checkout is detached | R69, R73 |

The user accepted these choices on 2026-11-13, including what they imply:
- #115 changes all five `lang-ci.yml` jobs and adds four fixtures.
- A Ruby directory without `.ruby-version`, `.tool-versions` or `mise.toml` fails, with a scaffold note.
- Under a root job, nested non-member tests may run twice.
- Discovery uses the depth-two scope and its exclusion list.
- A subdirectory's Bun pin is ignored.
- The body runs to about 1.7K words.

The user also chose the lean review for this amendment.

**Per-language workflows and lint-tool pins (2026-11-14).** The user made three more decisions for #115. No reviewer has seen them or the changes below.

| ID | Decision | Where |
|---|---|---|
| D4 | `lang-ci.yml` becomes one reusable workflow per language, `lang-ci-{go,js,python,ruby,rust}.yml`, because five files are easier to maintain and extend. One commit SHA pins all five, and the caller's `uses:` names its component's file, so there is no `language` input. U2(a)–(c), the per-language fixes, the security limits, the required checks, the fixtures and the two PRs stay | Design; Migration; AC-9; AC-24; Test plan; Rollback; B1; B2; B4; B5; C; E |
| D5 | #115 pins shellcheck 0.11.0, shfmt 3.14.1 and actionlint 1.7.12 in `mise.toml`, with a generated `mise.lock`. CI keeps its own sha256-checked downloads, adds actionlint's, checks the three versions against `mise.toml`, and runs actionlint with shellcheck over the workflows | AC-26; B1; B4; B5; C |
| D6 | `mise.toml` names actionlint by its explicit backend, `"aqua:rhysd/actionlint" = "1.7.12"`, not by the short name mise's registry deprecates [E111]: it is the binary CI downloads, and a remap of the short name can't change it [E112] | B1; C |

D4 supersedes U2(d), the `guard` job, since a call of a missing file already fails [E105]; the job-id loop of SIM-A8 and OPS-A8, and OPS-A8's guard, since no job is gated. OQ-1, D1, D3, the D3 choices' `lint` loop, G6, SEC-A1 and OPS-A10 name the one `lang-ci.yml`; they now read as the five files.

The architect's choices under D4 and D5, which the user has not made:

| Choice | Evidence |
|---|---|
| Each file's one job keeps the language id, as in `lang-ci.yml`, so a call shows as `<caller job> / <id>`; each file's `name:` is `lang-ci-<id>` | R69 |
| drift finds a component's block by its job id and `directory:` line, `pin-changed` also checks every other value naming a `lang-ci` file, and S24 gains the other language's file as a decoy | B2 |
| #115's `lint` replaces the job-id loop and the guard check with: exactly the five files; each file's only job named by its id, with no job-level `if:`; its `lang-ci-fixture-<id>` job; and one SHA per action across the files. From the add commits, `test_bw.py` checks that the ids, the files, the fixture jobs and the AGENTS.md tags agree, and `lint` loses only its file-set line | R69, E103 |
| The pin checks loop over HEAD's `lang-ci-*.yml` files and diff every `lang-ci*` path | B4 |
| The lint step has no `${{`, so its timeout pattern writes `[$]{{`. The superseded block's `if:`, guard and timeout patterns had `${{ … }}`, which GitHub would have substituted before bash ran | E107 |
| Allow lists name each file callers use, or one `lang-ci-*.yml@<sha>` pattern | E59, E106 |
| `mise.lock` covers linux-x64 and macos-arm64, as the orchestrator suggested; a contributor on another platform adds it with `mise lock --platform` | E111 |
| `.github/actionlint.yaml` declares `ubuntu-26.04` under `self-hosted-runner.labels`, and actionlint gets `-config-file` instead of relying on its search | E108, R91 |
| SC2086: a commented `disable` directive in each `$SHELL_FILES` step; in the rust job, `${locked:+"$locked"}` instead of a directive | E110, R91 |
| install-check's `export HOME="$(mktemp -d)"` becomes `HOME=$(mktemp -d)` then `export HOME`, which actionlint's shellcheck run would otherwise report as SC2155 | E108, E110 |
| AC-26 records D5, and `docs/CONTRIBUTING.md` gets a B1 row, since it lists the local lint commands | B1; B5 |

**Package layout, uv and seeded text (2026-11-15).** The user made four decisions for #117, the implementation PR, and the RFC returned to Draft for re-approval. Migration now names #118, the tracking issue.

| ID | Decision | Where |
|---|---|---|
| D7 | The Python behind `scripts/bw` becomes the package `scripts/bytewyrd/`. It is typed and checked with `mypy --strict`, and linted and formatted with ruff. The runtime doesn't change: Python 3.11 or newer, the standard library and the vendored PyYAML. Nothing is installed at runtime, and users need no uv | A; B1; B2; B4; B5 |
| D8 | A development-only `pyproject.toml` and `uv.lock` pin pytest, PyYAML, ruff, mypy and types-PyYAML. Contributors and every CI job that runs these tools get them through uv: `uv sync --locked`, then `uv run --no-sync …` [R92]. uv 0.13.4 is pinned in `mise.toml` as `"aqua:astral-sh/uv"` [R95], and CI's version check covers it | Language policy; Security; A; B1; B4 |
| D9 | `uv.lock` pins the vendored PyYAML: it is the source of truth for PyYAML's version and its sdist hash [R93]. `.github/scripts/vendor-pyyaml.py`, standard library only, rebuilds `scripts/_vendor/yaml` and `PyYAML-LICENSE` from the locked sdist. With `--check` it compares them both ways, and CI's `lint` runs that check. `scripts/_vendor/PyYAML-6.0.3.sha256` is deleted | AC-21; Security; A; B1; B2; B4; B5 |
| D10 | Seeded files say nothing when nothing is found. In the user's words: "The fact that a language was not detected by the scaffold is not important for AGENTS.md or anything that comes to the project afterwards. If there is something to document, do it, otherwise just don't." AGENTS.md has a Project facts section only when a language is found, and its wording no longer says scaffold found it. With no languages, `ci.yml` is a neutral no-op job that names neither scaffold nor detection | AC-8; B1; B2; B4; B5; C |

D7 moves the `scripts/_lib/` paths that the add and port commits created; B1's earlier rows and B2's launcher step 1 keep them as the record of those commits. D8 and D9 supersede Appendix C's `ci.yml` sketches where they install pytest and PyYAML with pip, set `PYTEST_VERSION` and `PYYAML_VERSION`, check the vendored copy against the `.sha256` file, and run the links step before the lang-ci step. #117's `.github/workflows/ci.yml` is the source for those steps, and Appendix C gains no CI or `pyproject.toml` sketch, so neither file has a second copy here.

The architect's choices under D7–D10, which the user has not made:

| Choice | Detail | Rationale |
|---|---|---|
| Bootstrap | `scripts/bytewyrd/__main__.py` replaces `bw_main.py`. It stays old-syntax-safe, so its version check is reached, and the launcher runs `exec "$py" -I -S -B "$dir/bytewyrd/__main__.py" NAME "$@"` | Run as a file, like `bw_main.py`, it is the only plugin code an old interpreter parses before the version check, because the package's modules are imported only after the check passes [R52]. The launcher keeps `-I -S -B` [R54] |
| Shared modules | Seven: `cli` (`BwError`, `Parser`, `quote`, `describe`), `git`, `fs`, `detect` (with `attr_line`), `seed` (targets, templates, `render`, stamps, `plugin_sha`, `pr_template`, `workflow_exists`, `lacks_import`), `frontmatter` (the only module that imports yaml, at module level) and `jsonout` (jq-compatible output and the emitters) | They follow `bw.py`'s sections, with `seed` joining the three that only scaffold and drift use: stamps, rendering and seed targets [R96]. With yaml imported in one module, the loader grep exempts one file, and the commands that parse no frontmatter never load yaml |
| Commands | Each is `scripts/bytewyrd/commands/<name>.py`, moved with `git mv` from `scripts/_lib/bw_<name>.py` | At most a third of each command's lines name `bw`. A move that changes only those lines stays above git's default 50% similarity, so `git log --follow` reaches each command's history from before the move [R96] |
| `[project]` in `pyproject.toml` | It has `[project]` (`name = "claude-bytewyrd-dev"`, `version = "0"`, `requires-python = ">=3.11"`) and `[tool.uv] package = false` | Without `[project]`, `uv lock` takes `requires-python` from the interpreter it runs, a group's own `requires-python` doesn't change that, and `uv sync --locked` on 3.11 then fails [R92, E113]. `package = false` keeps uv from building or installing the project [E113] |
| Dependency group | One `dev` group | uv syncs `dev` by default [E80], so no command needs a group flag, and contributors and CI install the same tools [R92] |
| `@@any@@` tag | Wraps the Project facts section (Appendix C) | `render`'s tags already keep lines per language. One more tag, kept only when there is a component, drops the whole section without block syntax (B2) |
| No-op step | `run: exit 0` | It passes and says nothing. The job stays, since a workflow run is made up of one or more jobs [E30] |

No reviewer has seen D7–D10.
