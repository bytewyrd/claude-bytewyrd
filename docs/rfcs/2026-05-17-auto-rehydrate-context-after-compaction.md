---
rfc: "2026-05-17-auto-rehydrate-context-after-compaction"
title: "Auto-rehydrate context after compaction"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Wire a `SessionStart` hook with the `compact` matcher (the documented Claude Code mechanism for post-compaction injection per `https://code.claude.com/docs/en/hooks-guide`, Exa: https://code.claude.com/docs/en/hooks-guide) plus a backing `scripts/rehydrate-context.sh` script that builds a deliberately small, prioritized "rehydration card" — a one-screen system reminder listing the ~3-7 highest-signal artifacts the agent was actively working on before compaction (the active RFC under `docs/rfcs/`, files modified in the last N commits, the current branch name, and project-convention pointers like `CLAUDE.md` and `docs/rfc-process.md`) — and emits that card via the hook's `additionalContext` field. The card contains **pointers** (file paths plus one-line "why this matters" annotations), not file contents — the agent decides which pointers to follow with `Read` based on the next user prompt. Selection is conservative by design: the card has a hard 8 KB budget (well under the 10,000-character `additionalContext` cap documented at `https://docs.anthropic.com/en/docs/claude-code/hooks`, Exa: https://docs.anthropic.com/en/docs/claude-code/hooks), a hard 7-item budget, and a per-item priority weight, so the worst case is a card that lists fewer items rather than one that defeats compaction by re-bloating context. Policy lives in `scripts/rehydrate-context.sh` (script-as-policy) so the rules are inspectable, testable in isolation, and editable without a Claude Code restart; the hook entry in `hooks/hooks.json` is a one-line shell invocation. The known reliability gap — multiple users report that Claude sometimes ignores `SessionStart(compact)` `additionalContext` output (GitHub issues #15174 closed-as-dup and #17237 still-open with corroborating comment, Exa: https://github.com/anthropics/claude-code/issues/17237) — is addressed by (a) framing the card as factual state rather than imperatives, (b) keeping it small enough that the agent's first user-prompt context window is not crowded out, and (c) accepting that even a partially-effective rehydration is strictly better than today's "agent wakes up with only the compaction summary."

## Should we do this?

**Yes.** Compaction is the single largest unforced context loss event in a long Claude Code session: the model wakes up holding only the summarizer's prose narrative, which routinely loses (i) the path to the file the agent was about to edit, (ii) the path to the RFC or plan the session was implementing, and (iii) the specific convention pointers (e.g., `docs/rfc-process.md`, `CLAUDE.md` agent-delegation table) the agent had loaded into context to do its work. Across the open `anthropics/claude-code` issue tracker, "compaction destroys working state" is currently represented by at least #17237 (`PreCompact`/`PostCompact` feature request, 13 reactions, open since 2026-01-10), #29890 (`Context compaction loses critical working knowledge mid-session`), #41224 (`PostCompact hook should support context injection`), and several others linked from #17237 (Exa: https://github.com/anthropics/claude-code/issues/17237) — the failure mode is well-attested and is exactly the surface this RFC targets.

The cost-benefit math is favorable. Cost: one new shell script (~200 lines, no compiled dependencies beyond `git` and `jq` which are already required by other plugin scripts, verified: scripts/_lib/common.bash:L10-15), one new hook entry in `hooks/hooks.json` (two-line addition), and one new section in `docs/BEST_PRACTICES.md` describing the card-budget contract. Benefit: every post-compaction turn starts with a one-screen, deliberately-prioritized pointer card rather than a blank slate, so the agent's next `Read` calls go to the right files instead of the wrong ones. The known reliability gap (Claude sometimes ignores the injection) caps the upside but does not invert it — a partial rehydration that lands 60% of the time is still 60 percentage points better than today's 0%.

The deliberately-conservative selection policy is what makes this safe to ship. The braindump's framing names the trap directly: "pulling everything defeats the point of compaction." This RFC enforces the trap-avoidance at three layers: (1) a hard 7-item item-count budget, (2) a hard 8 KB byte budget for the rendered card, and (3) a per-source priority weight (active RFC: weight 100, recently-modified files: weight 90, current branch: weight 50, convention pointers: weight 30) with stable tie-breaking. If the budget overflows, the lowest-weighted entries are dropped, not truncated. The card is pointers — file paths plus one-line "why this matters" annotations — not file contents, so the agent retains the option of reading the full file if and only if the upcoming user prompt actually needs it. No file is auto-loaded.

The "should we do this" question reduces to "is the rehydration card a better starting condition than the compaction summary alone." The answer is yes for any session that did substantive multi-file work, and the script's no-op exit path (when there are no candidates worth listing) ensures sessions that genuinely had no working state pay no cost beyond a single hook fire.

## Current state

The plugin already operates a hook ecosystem around compaction and session start; this RFC slots into the existing surface rather than introducing a new one.

**What exists today:**

- `hooks/hooks.json` (verified: hooks/hooks.json:L1-38) — the plugin's exported hook configuration. Two events are currently registered:
  - `SubagentStop` matching the regex `(^|:)feature-engineer$` — runs two commands: an `echo` reminder about `/docs-review` (verified: hooks/hooks.json:L9) and a sentinel-touch (`mkdir -p .bytewyrd && : > .bytewyrd/last-feature-engineer-stop`, verified: hooks/hooks.json:L13).
  - `SessionStart` with matcher `compact` — already in use for the docs-review reminder (verified: hooks/hooks.json:L19-26). The hook reads the `.bytewyrd/last-feature-engineer-stop` sentinel's mtime, and if it's less than 24 hours old echoes a reminder line. **This RFC adds a second, sibling `SessionStart(compact)` handler in the same event entry** so the rehydration card and the docs-review reminder coexist without either overwriting the other (Anthropic docs: "When several hooks return `additionalContext` for the same event, Claude receives all of the values," Exa: https://docs.anthropic.com/en/docs/claude-code/hooks).
  - `SessionStart` (no matcher) — runs `scripts/check-requirements.sh` to probe companion plugins, MCP servers, and CLI tools (verified: hooks/hooks.json:L28-35). Unrelated to compaction; unmodified by this RFC.

- The project's local `.claude/settings.json` (verified: .claude/settings.json) — augments the plugin's hooks with project-specific entries. Notably the `PreCompact` hook (verified: .claude/settings.json:L21-30) blocks compaction until `/best-practices-extract` runs, released by the sentinel file `.bytewyrd/precompact-extraction-done`. The `SessionStart` (no-matcher) handler at lines 12-19 deletes that sentinel on every new session so the gate begins clean. **This RFC's rehydration script reads but does not modify any of these existing files.** The interaction is purely additive — the rehydrate hook fires `SessionStart(compact)` (post-compaction), the existing block-and-release loop fires `PreCompact` (before compaction), and the two events do not overlap in time.

- `scripts/check-requirements.sh` (verified: scripts/check-requirements.sh:L1-202) — the canonical example of a plugin-level shell script wired into the hook system. It probes plugin/MCP/CLI requirements, emits JSON via the documented `hookSpecificOutput.additionalContext` schema (verified: scripts/check-requirements.sh:L39-41), and uses the `BYTEWYRD_SKIP_WARN` environment variable for per-requirement opt-out. The rehydration script this RFC adds follows the same shape: emits JSON to stdout, uses a small set of env-var knobs for tuning, no compiled dependencies beyond `git`/`jq`.

- `scripts/_lib/common.bash` (verified: scripts/_lib/common.bash:L1-50) — shared helpers used by `scripts/*.sh`. Provides `require_jq` (exit 2 with static JSON error if `jq` missing), `emit_error`/`emit_available`/`emit_missing`/`emit_unauth` JSON-emission helpers, and `plugin_enabled`. The rehydration script sources this file for `require_jq` and for JSON emission helpers — no duplication of the bootstrap pattern.

- `docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md` (verified: docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L1-518, status `Done`) — the closest prior art. Established the pattern of (a) using a `PreCompact` hook with `decision: "block"` plus `additionalContext` injection to enforce an extraction step before compaction, (b) sentinel-file release via `.bytewyrd/precompact-extraction-done`, and (c) `SessionStart` (no matcher) sentinel cleanup. The rehydration RFC is a sibling on the other side of compaction — it operates after compaction completes, not before it — and reuses the project's sentinel directory `.bytewyrd/` for a different file (the rehydration card's last-emit log, see Step 2).

- Documented Claude Code behavior the RFC depends on:
  - `SessionStart` hook supports a `compact` matcher that "fires after auto or manual compaction" (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks — table under "SessionStart"). The matcher is one of `startup`, `resume`, `clear`, `compact`.
  - The hook input JSON includes `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source`, `model`, and optionally `agent_type` (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks — "SessionStart" input fields).
  - The documented mechanism for injecting text into the post-compaction context is the `hookSpecificOutput.additionalContext` field, which "Claude Code wraps in a system reminder and inserts into the conversation at the point where the hook fired" (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks — "Add context for Claude" section).
  - `additionalContext` longer than 10,000 characters is offloaded to a file and Claude receives the file path with a short preview (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks — "Add context for Claude" section). The rehydration card budget of 8 KB stays comfortably under this limit; no offload path needs to be handled.
  - `PostCompact` exists as a hook event but its stdout is **not** model-visible — only verbose-mode visible (Exa: https://github.com/anthropics/claude-code/issues/41224 confirms this is the open feature gap as of 2026-03-31, with the user-doc behavior also implied by the absence of `PostCompact` from the documented `additionalContext`-supporting list at https://docs.anthropic.com/en/docs/claude-code/hooks). This is why the RFC uses `SessionStart(compact)` and not `PostCompact`.

- Session transcript layout: per the Mintlify sessions doc (Exa: https://www.mintlify.com/vineetagarwal-code/claude-code/concepts/sessions) and the Fazm blog (Exa: https://fazm.ai/blog/claude-code-previous-sessions-jsonl-transcripts), each session is persisted as an append-only JSONL file at `~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl`, where `<sanitized-cwd>` is the absolute working directory with non-alphanumeric characters replaced by `-`. Each line is a JSON object with at minimum a `type` field (`user`, `assistant`, `tool_result`, etc.) and tool-call metadata. The script reads this file via the `transcript_path` provided in the hook input rather than reconstructing the path — the path is the canonical source and survives sanitization-rule changes. **Important caveat verified by Exa**: the `transcript_path` field is sometimes reported empty for `PreCompact` (Exa: https://github.com/anthropics/claude-code/issues/13668, 2025-12-11) — the script must defend against the empty-string case for `SessionStart(compact)` too and fall back to the file-based heuristics (git history, filesystem mtime) when transcript parsing yields nothing.

**What is broken or missing:**

1. **No post-compaction rehydration of any kind.** The current state immediately after compaction is: the agent's context window contains only the compaction summary the model itself generated, the global `CLAUDE.md` (re-loaded automatically by the `getMemoryFiles` cache invalidation per the Mintlify sessions doc, Exa: https://www.mintlify.com/vineetagarwal-code/claude-code/concepts/sessions), and whatever new user prompt the user types next. The agent has no automatic signal about which file it was about to edit, which RFC it was implementing, or which branch it was on. The agent's first post-compaction `Read` calls are guesses driven by the user's next prompt; if the user types "continue" or "keep going," the agent has no anchor for what "continue" means.

2. **The known `SessionStart(compact)` injection-reliability gap is unaddressed.** Per GitHub issue #15174 (closed-as-duplicate of #13650, Exa: https://github.com/anthropics/claude-code/issues/15174, 2025-12-23): "The hook does execute — Claude Code reads the hook file (visible in system reminders); the hook stdout is NOT injected into Claude's context after compaction." Per @ThatDragonOverThere's confirming comment on #17237 (Exa: https://github.com/anthropics/claude-code/issues/17237, 2026-02-18): "Claude ignores the SessionStart output. The compaction summary momentum wins." This RFC cannot fix the upstream bug, but it can (a) frame the card so the injection has the best chance of being attended to — factual statements, file paths, prioritized list — and (b) keep the card small enough that even if Claude only partially attends to it, the partial attention lands on the highest-priority items first.

3. **The decision "where does the policy live" is unresolved.** Three reasonable locations: (i) inline in the hook command in `hooks.json` (forces awkward shell escaping; non-testable), (ii) a settings-file knob (e.g., `bytewyrd.rehydration.maxItems` in `.claude/settings.json` — non-standard for Claude Code; no documented support for arbitrary plugin namespaces in settings, Exa search for "Claude Code settings.json custom plugin keys" returned no authoritative source [UNVERIFIED — searched docs.anthropic.com/en/docs/claude-code, found no documented schema extension for plugin-defined keys; the safe assumption is that custom keys would be ignored or warned-about by Claude Code]), or (iii) a shell script (script-as-policy: rules live in code, testable in isolation, editable without restart). This RFC picks (iii), matching the established pattern of `scripts/check-requirements.sh`.

4. **No documented "what counts as important" rule.** The braindump's open question is exactly this: "how to detect 'important' (recency, edit count, explicit pinning, plan references?)." Without a written rule, every future revision of the script reinvents the priority order. The RFC's Analysis section commits to a fixed priority schedule with stable tie-breaking, and the implementation spec encodes it as code so the rule is one place to change.

## Analysis / Options

There are four coupled decisions: the hook event the script attaches to, where the priority policy lives, what counts as a high-signal artifact (the priority schedule), and how the script bounds the card size.

### Decision 1 — Which hook event drives rehydration?

**Option A — `SessionStart` with the `compact` matcher (recommended).**
This is the documented mechanism for post-compaction context injection (Exa: https://code.claude.com/docs/en/hooks-guide — "Re-inject context after compaction" section literally names this hook+matcher pair as the supported approach). The hook input includes `transcript_path` and `cwd` so the script has the inputs it needs; the documented output channel is `hookSpecificOutput.additionalContext`. The known reliability gap (issues #15174 and #17237) is real but is the same gap any rehydration approach using documented surfaces would hit — moving to a different event does not fix it; only the upstream `PostCompact`-with-`additionalContext` feature request (#46191, open as of 2026-04-10, Exa: https://github.com/anthropics/claude-code/issues/46191) would.

**Option B — `PostCompact` hook.**
Rejected on the documented behavior. `PostCompact`'s stdout is not model-visible — only verbose-mode visible (Exa: https://github.com/anthropics/claude-code/issues/41224, 2026-03-31, open request to change this). The hook can run side effects (logging, file writes, notifications) but cannot inject context into the post-compaction conversation. Using `PostCompact` for rehydration would be observability theater: the script runs, produces output, and the model never sees it.

**Option C — `UserPromptSubmit` hook gated by a "just-compacted" flag.**
The pattern from the workaround documented in #40492 (Exa: https://github.com/anthropics/claude-code/issues/40492): `PreCompact` writes a marker timestamp, `Stop` (after compaction completes) detects the marker is recent and sets a re-inject flag, `UserPromptSubmit` reads the flag on the next user turn and emits `additionalContext` to re-inject. The trade-off: this pattern is more reliable for injection (the model does attend to `UserPromptSubmit` `additionalContext` consistently per the docs at https://docs.anthropic.com/en/docs/claude-code/hooks "Add context for Claude" — "alongside the submitted prompt"), but it introduces three coordinated hook entries and a stateful flag-file lifecycle that interacts with the existing `PreCompact` block-and-release sentinel already managed for `/best-practices-extract`. The two state machines do not naturally compose: the existing `PreCompact` hook returns `{"decision":"block"}` and aborts compaction entirely on first fire, so the proposed `PreCompact`-side timestamp write would only run on the second `PreCompact` fire (after extraction completed and the user re-triggered compaction). This timing-dependence is fragile. The complexity of three-event coordination outweighs the reliability gain unless real-world use of Option A shows the injection failure rate is high.

**Option D — A combined `SessionStart(compact)` + `UserPromptSubmit` fallback.**
The script emits the card via `SessionStart(compact)`'s `additionalContext`, and additionally writes the card text to a file `.bytewyrd/last-rehydration-card.md` with an mtime stamp. A small `UserPromptSubmit` hook checks for a recent (<5 minute) card file; if present and the user's submitted prompt is short ("continue", "keep going", anything under 20 characters), the hook re-injects the card via `UserPromptSubmit`'s `additionalContext`. This is "Option A but with a second-chance injection on the first user turn after compaction, only triggered when the user's prompt itself signals the agent needs context." The cost is one extra hook entry and one extra script (~30 lines); the benefit is recovery from the issue-#15174 failure mode for the specific case the failure mode hurts most (short follow-up prompts where the agent has nothing else to anchor on). **This is what the RFC recommends, on top of Option A's primary path** — see the Recommendation below.

**Recommendation — Option A (primary) + Option D (fallback).**
Use `SessionStart(compact)` for the primary injection path. It is the documented mechanism, requires only one new hook entry, and reuses the same `additionalContext` output the existing `SessionStart(compact)` docs-review reminder already uses. Add the Option D fallback (a `UserPromptSubmit` hook that re-injects the card when the user's first post-compaction prompt is short) as defense in depth against the documented injection-attention failure. The fallback's trigger is narrow (short prompt within 5 minutes of compaction) so it does not become a constant noise source. Option B is rejected on documented behavior; Option C as a standalone is rejected on coordination complexity with the existing `PreCompact` gate.

### Decision 2 — Where does the priority policy live?

**Option A — In a shell script (`scripts/rehydrate-context.sh`), invoked by the hook (recommended).**
"Script-as-policy" — the rules are written in shell, the budget constants (`MAX_ITEMS`, `MAX_BYTES`, weights) are at the top of the file as `readonly` variables, and the file is testable in isolation by running it from a terminal with mock environment variables. This matches `scripts/check-requirements.sh`, the established plugin pattern (verified: scripts/check-requirements.sh:L11-29). Edits to the policy take effect on the next session start with no Claude Code restart — the hook re-invokes the script each time. The hook entry in `hooks/hooks.json` is a one-line shell invocation; the policy is not entangled with hook plumbing.

**Option B — Inline in the hook command in `hooks/hooks.json`.**
Forces all logic into a single quoted shell string with escaped quotes-within-quotes-within-JSON. The existing inline `SessionStart(compact)` docs-review reminder is 8 lines of shell condensed into one JSON string (verified: hooks/hooks.json:L24). The rehydration script will be ~200 lines (parse `transcript_path`, git log call, file mtime check, priority weighting, JSON emission). Compressing 200 lines into a JSON-escaped one-liner is unmaintainable and untestable. Rejected.

**Option C — A user-facing settings file (`.claude/settings.json` plugin-specific keys).**
There is no documented mechanism for Claude Code to read arbitrary plugin-namespaced keys from `settings.json` and pass them to hooks [UNVERIFIED — searched the hooks reference and settings reference at docs.anthropic.com and code.claude.com; found no documented schema extension that would let a hook read `bytewyrd.rehydration.maxItems` from settings.json. The closest documented mechanism is environment variables in the hook's shell context, which is exactly what Option A uses]. Even if the mechanism existed, mixing policy-as-settings with policy-as-code adds two places to look for the same rule. Rejected.

**Option D — A dedicated config file (`docs/rfc-rehydrate-policy.yaml` or `.bytewyrd/rehydrate.yaml`).**
Adds a YAML or JSON parser dependency to the script (the plugin already requires `jq` per `scripts/_lib/common.bash:L10-15`, so a config file in JSON would not add a new dep — but it would add a config-file-lifecycle question: where does the file live, how is it created on `/sync`, how is it migrated across plugin versions). For a policy that fits in ~40 lines of priority weights and budget constants, the lifecycle overhead exceeds the value. Rejected.

**Recommendation — Option A.** Script-as-policy. The constants are at the top of the file with comments explaining what each one does; advanced users edit the script directly. Environment variables (`BYTEWYRD_REHYDRATE_MAX_ITEMS`, `BYTEWYRD_REHYDRATE_MAX_BYTES`, `BYTEWYRD_REHYDRATE_DEBUG`) provide per-session overrides without editing the file, matching the `BYTEWYRD_SKIP_WARN` pattern in `scripts/check-requirements.sh:L29`.

### Decision 3 — What counts as a high-signal artifact? (Priority schedule)

The braindump asks: "how to detect 'important' (recency, edit count, explicit pinning, plan references?)." Recency is the most reliable signal in a Claude Code session because Claude Code's own work pattern is bursty: a session typically touches a small set of files repeatedly. Explicit pinning would require a user-facing convention that does not exist yet. Plan references (an active RFC under `docs/rfcs/`) are detectable from the branch name pattern (RFCs are implemented on branches named `rfc/<rfc-id>`) and from the existence of a Draft or Approved RFC matching the branch. Edit count is a finer-grained version of recency; absent telemetry we approximate it with "appears in the last N git commits on the current branch."

The recommendation is a fixed priority schedule with these tiers, evaluated by the script in order:

**Tier 1 (weight 100): Active RFC.**
If the current branch matches `rfc/<rfc-id>` (e.g., `rfc/2026-05-17-auto-rehydrate-context-after-compaction`) and a file at `docs/rfcs/<rfc-id>.md` exists, list it as the highest-priority pointer with annotation "active RFC being implemented." This is the strongest signal in the plugin's RFC-driven workflow that the session has a long-lived plan.

**Tier 2 (weight 90): Files modified in the last N=3 commits on the current branch.**
`git log --name-only --pretty=format: HEAD~3..HEAD` (where `HEAD~3` is clamped to the branch's earliest commit if the branch has fewer than 3 commits) yields the file list. Dedupe and exclude paths matching the ignore-list (`.bytewyrd/**`, `node_modules/**`, `.git/**`, `dist/**`, `build/**`, files with extensions `.lock`, `.png`, `.jpg`, `.gif`, `.svg`, `.woff*`, `.pdf`). Cap at 4 entries to leave room for tiers 3-4 within the 7-item budget. The annotation is "modified in the last <N> commits" with the commit count derived from `git log --oneline HEAD~3..HEAD -- <path> | wc -l`.

**Tier 3 (weight 80): Files modified in the working tree but not yet committed.**
`git diff --name-only HEAD` and `git status --porcelain | awk '/^\?\?/{print $2}'` (for untracked files). These are the files the agent was most likely about to commit when compaction happened. Cap at 3 entries. Annotation: "uncommitted change" or "untracked (new)."

**Tier 4 (weight 50): Current branch name.**
Always include the branch name as a single line in the card (not a file pointer; a bare fact). Annotation: "current branch: `<branch-name>`." Provides anchor for the agent to ground "what was I doing."

**Tier 5 (weight 30): Convention pointers.**
A fixed list of the project's "constitution" files: `CLAUDE.md`, `docs/rfc-process.md`, `docs/CONTRIBUTING.md`. Listed only if they exist in the project. Annotation: "project conventions; read on demand." These are pointers, not contents; the agent reads them if and only if the upcoming user prompt warrants it.

**Tie-breaking within a tier:**
- Tier 2 / Tier 3: order by `git log -1 --format=%ct -- <path>` (descending; most-recently-touched first).
- Tier 5: fixed alphabetical order (`CLAUDE.md`, `docs/CONTRIBUTING.md`, `docs/rfc-process.md`).
- Tier 1 and Tier 4 are single-item tiers; no tie-break needed.

**Budget enforcement:**
- Hard cap: 7 items total in the card. If a tier's nominal count would push the total over 7, that tier's count is reduced (lowest-weight tiers truncate first). Example: if Tier 2 yields 5 modified files but Tier 1 already filled one slot and Tier 5 needs three slots, Tier 2 is capped at 3 to leave room for the convention pointers.
- Hard cap: 8 KB total rendered card size. The card is rendered in priority order; entries that would push the total above 8 KB are dropped from the bottom of the list (lowest-weight first). This is a defense against a single artifact's annotation being unexpectedly long; in practice the annotations are one short line each.
- No-op: if no artifacts pass any tier (fresh branch, no commits, no working-tree changes, no convention files), the script emits an empty `additionalContext` and exits 0. Claude Code's documented behavior is to treat empty `additionalContext` as a no-op — no injection happens (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks confirms "Multiple hooks' `additionalContext` values are concatenated" — an empty value contributes nothing).

### Decision 4 — How does the script signal "this is a low-stakes pointer, not an instruction"?

Per the documented `additionalContext` guidance (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks — "Add context for Claude" section, and the corroborating observation in #17237 comment from @ThatDragonOverThere about prompt-injection defenses), text framed as out-of-band system commands ("YOU MUST read these files") can trigger Claude's prompt-injection defenses, causing Claude to surface the text to the user as suspicious content rather than acting on it. The 2026-05-12 PreCompact RFC's drawbacks section (verified: docs/rfcs/2026-05-12-auto-extract-best-practices-on-precompact.md:L137-139) names the same rule and applies it in its reminder wording.

The rehydration card uses the same factual-statement framing:

```
Post-compaction rehydration pointers (auto-generated; read on demand):

Active RFC: docs/rfcs/2026-05-17-auto-rehydrate-context-after-compaction.md
  — RFC being implemented on this branch.

Recently modified (last 3 commits):
  scripts/rehydrate-context.sh — modified in last 2 commits.
  hooks/hooks.json — modified in last 1 commit.

Uncommitted change:
  docs/BEST_PRACTICES.md — uncommitted change.

Current branch: rfc/2026-05-17-auto-rehydrate-context-after-compaction

Project conventions (read if relevant to next task):
  CLAUDE.md, docs/CONTRIBUTING.md, docs/rfc-process.md
```

The card states what is true; the agent decides which pointers to follow based on the next user prompt. No imperatives, no "you must", no "do not." The opening line explicitly labels the card as auto-generated and as "pointers" — both signals that this is reference material, not a task.

## Drawbacks

- **The known `SessionStart(compact)` injection-reliability gap caps the upside.** Per #15174 and the corroborating comment on #17237 (Exa: https://github.com/anthropics/claude-code/issues/17237), Claude sometimes ignores the `additionalContext` returned by `SessionStart(compact)` — the model attends to the compaction summary and the user's next prompt and treats the system reminder as background. **Mitigation:** (a) the Option D `UserPromptSubmit` fallback re-injects the card when the user's first post-compaction prompt is short, capturing the failure-mode-most-harmful case (the "continue" prompt with no other anchor); (b) the card is small enough (8 KB) that even partial attention lands on the highest-priority items first; (c) the card's pointer-not-contents design means even an ignored card costs nothing beyond a few injected lines of text — there is no file-content re-load to undo.

- **Selection rules can disagree with what the user actually wanted re-loaded.** A user who was about to switch contexts entirely (jumping from RFC implementation to an unrelated bug fix) gets a card pointing at the wrong RFC. **Mitigation:** the card is pointers, not contents — if the user's next prompt is "let's switch to the bug in X," the agent's first `Read` goes to the new file regardless of what the card says. Misdirected pointers cost a few tokens of attention; they do not force the agent down a wrong path.

- **Git-history-based recency drifts when the branch is fast-forward-merged or rebased.** A rebase rewrites commit timestamps, so a branch that was just rebased onto main may report "modified in the last 3 commits" for files that have not been touched in days. **Mitigation:** working-tree state (Tier 3) is unaffected by rebase, so the most operationally-relevant tier remains accurate. The card's annotation says "in the last N commits" not "in the last hour" — the agent can reason about the temporal claim even if it is slightly off.

- **The script's policy is hard-coded; consumer projects with different conventions cannot easily change it.** Some projects do not use the `rfc/<rfc-id>` branch naming convention, and Tier 1 will produce no entries. **Mitigation:** the priority schedule degrades gracefully — a project without `rfc/`-prefixed branches still gets Tier 2-5 entries (recently-modified files, branch name, convention pointers). The hard-coded `docs/rfcs/` path is in line with the rest of the plugin (RFCs always live at `docs/rfcs/` per `docs/rfc-process.md`, verified: docs/rfc-process.md:L70-72). Consumer projects with deeply divergent conventions can edit the script in their `/sync`-managed checkout — the script-as-policy choice (Decision 2) makes this a one-file edit.

- **The rehydration card and the existing `SessionStart(compact)` docs-review reminder both fire after compaction; the agent sees two reminders.** Both are short (the docs reminder is one line, the rehydration card is ~10 lines under 8 KB). **Mitigation:** they read as complementary — the docs reminder is action-oriented ("consider running `/docs-review`"), the rehydration card is reference-oriented ("here are pointers to the work in flight"). The hooks documentation explicitly supports this composition: "When several hooks return `additionalContext` for the same event, Claude receives all of the values" (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks). The two are siblings in the same `SessionStart(compact)` event entry of `hooks/hooks.json`.

- **The `UserPromptSubmit` fallback can fire unnecessarily.** The fallback checks (a) the card file is fresh (<5 minutes old) and (b) the user's prompt is short (under 20 characters). A user who quickly types a real-but-short prompt ("fix the test") within five minutes of a compaction event gets a re-injection they did not need. **Mitigation:** the cost is small (the same 8 KB card injected again, alongside the user's actual prompt — the agent attends to both). The fallback's trigger is conservative: it does not fire on every post-compaction turn, only on the first prompt within the window. The 5-minute window is a constant at the top of the fallback script; if real-world use shows it is too wide, it can be tightened to 2 minutes.

- **`transcript_path` may be empty.** Per #13668 (Exa: https://github.com/anthropics/claude-code/issues/13668, 2025-12-11, reported for `PreCompact` but the same JSON-input mechanism is used for `SessionStart`), the `transcript_path` field is sometimes empty. The script currently does not depend on parsing the transcript for the priority schedule (it uses git history and working-tree state, both of which work without the transcript); the only feature that would benefit from the transcript is parsing recently-mentioned file paths in the user's conversation, which is a Tier-3.5 enhancement deferred to a follow-up RFC. **Mitigation:** the script guards the transcript-parse path with `[ -n "$transcript_path" ] && [ -f "$transcript_path" ]` and skips it silently when the input is empty.

- **The script requires `jq` and `git` on PATH.** Both are already required by other plugin scripts (`require_jq` in `scripts/_lib/common.bash:L10-15`, `git` probed by `scripts/check-requirements.sh:L97-100`). **Mitigation:** the script reuses the existing `require_jq` helper; if `git` is missing the script exits silently with a one-line message to the hook log, and no card is emitted (the existing `check-requirements.sh` failure path already informs the user that `git` is missing at session start).

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/rehydrate-context.sh` | The policy script. Reads the `SessionStart(compact)` hook input JSON on stdin, runs the four-tier priority schedule (active RFC → recent commits → working-tree → branch name → convention pointers), enforces the 7-item / 8 KB budgets, renders the rehydration card, and emits the hook JSON response with `hookSpecificOutput.additionalContext` set to the card text. Also writes the card to `.bytewyrd/last-rehydration-card.md` for the fallback hook's use. Idempotent. No side effects beyond writing the card file. |
| Create | `scripts/rehydrate-fallback.sh` | The `UserPromptSubmit` fallback. Reads the hook input JSON on stdin, checks (a) the card file is fresh (<5 minutes old) and (b) the user's submitted prompt is short (under 20 characters). If both, re-emits the card via `additionalContext` for `UserPromptSubmit`. Otherwise exits silently with no output. |
| Modify | `hooks/hooks.json` | Add two hook handlers: (1) a second handler under the existing `SessionStart` event's `compact`-matcher entry that invokes `scripts/rehydrate-context.sh`; (2) a new `UserPromptSubmit` event (no matcher) that invokes `scripts/rehydrate-fallback.sh`. The existing `compact` handler (docs-review reminder) is preserved unchanged. |
| Modify | `docs/BEST_PRACTICES.md` | Add one project-specific best-practice entry documenting the rehydration card's contract: lives at `.bytewyrd/last-rehydration-card.md`, refreshed by `SessionStart(compact)`, budget is 7 items / 8 KB, policy in `scripts/rehydrate-context.sh`. Future agents working on this plugin can read the contract without re-reading this RFC. |
| Modify | `docs/ARCHITECTURE.md` | Add a row to the "Components" or "Data Flow" section documenting the rehydration script as a plugin-level component, and a row to the "Design Decisions" table for the script-as-policy + script-as-fallback decision. |

No new directories. No new agents. No new skills. No changes to the consumer-facing skill surface — this RFC is plumbing inside the plugin's own hook system. The `.bytewyrd/last-rehydration-card.md` file is gitignored (the `.bytewyrd/` directory is already in `.gitignore`, verified: .gitignore:L4-5).

### Steps

#### Step 1 — Create `scripts/rehydrate-context.sh`

Create the file at `scripts/rehydrate-context.sh` with this exact content. The script is structured as: source the common library, parse hook input JSON, gather candidates per tier with budget enforcement, render the card, emit the hook response JSON.

```bash
#!/usr/bin/env bash
# Bytewyrd plugin: post-compaction rehydration card.
#
# Invoked by the SessionStart(compact) hook. Reads the hook input JSON on
# stdin, builds a prioritized one-screen pointer card listing the highest-
# signal artifacts the agent was working on, and emits the card via
# hookSpecificOutput.additionalContext. Also persists the card to
# .bytewyrd/last-rehydration-card.md for the UserPromptSubmit fallback hook.
#
# Budget: 7 items, 8 KB.
# Priority: active RFC > recent commits > working tree > branch > conventions.
#
# Environment overrides (mirror BYTEWYRD_SKIP_WARN pattern):
#   BYTEWYRD_REHYDRATE_MAX_ITEMS=<n>   override item cap (default 7)
#   BYTEWYRD_REHYDRATE_MAX_BYTES=<n>   override byte cap (default 8192)
#   BYTEWYRD_REHYDRATE_DEBUG=1         write debug trace to .bytewyrd/rehydrate.log

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_lib/common.bash"
require_jq

# --- Budget constants (overridable via environment) -------------------------

readonly MAX_ITEMS="${BYTEWYRD_REHYDRATE_MAX_ITEMS:-7}"
readonly MAX_BYTES="${BYTEWYRD_REHYDRATE_MAX_BYTES:-8192}"
readonly RECENT_COMMITS=3
readonly DEBUG="${BYTEWYRD_REHYDRATE_DEBUG:-0}"

# --- Tier weights (priority ordering) --------------------------------------

readonly W_ACTIVE_RFC=100
readonly W_RECENT_COMMIT=90
readonly W_WORKING_TREE=80
readonly W_BRANCH=50
readonly W_CONVENTION=30

# --- Ignore list for path filtering (Tier 2/3) -----------------------------

# Paths matching any of these globs are excluded from recency tiers.
readonly -a PATH_IGNORE_GLOBS=(
  ".bytewyrd/*" "node_modules/*" ".git/*" "dist/*" "build/*"
  ".worktrees/*" "target/*" "vendor/*"
)
readonly -a EXT_IGNORE=(
  "lock" "png" "jpg" "jpeg" "gif" "svg" "webp" "ico"
  "woff" "woff2" "ttf" "eot" "pdf" "zip" "tar" "gz"
)

# --- Helpers ---------------------------------------------------------------

debug() {
  [ "$DEBUG" = "1" ] || return 0
  mkdir -p .bytewyrd 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >> .bytewyrd/rehydrate.log
}

# path_excluded <path> — returns 0 if the path should be filtered out.
path_excluded() {
  local p="$1"
  # Glob check.
  local glob
  for glob in "${PATH_IGNORE_GLOBS[@]}"; do
    case "$p" in $glob) return 0 ;; esac
  done
  # Extension check.
  local ext="${p##*.}"
  if [ "$ext" != "$p" ]; then
    local ignored
    for ignored in "${EXT_IGNORE[@]}"; do
      [ "$ext" = "$ignored" ] && return 0
    done
  fi
  return 1
}

# emit_response <card-text>
# Emits the hook response JSON to stdout. Always exits 0 — the hook output
# is the only signal Claude Code reads from this script.
emit_response() {
  local card="$1"
  if [ -z "$card" ]; then
    # No-op: empty card means no candidates passed any tier. The documented
    # behavior is that an empty additionalContext contributes nothing
    # (multiple hooks' values are concatenated).
    printf '{"continue":true,"suppressOutput":true}\n'
    exit 0
  fi
  jq -n --arg ctx "$card" '{
    continue: true,
    suppressOutput: true,
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
  exit 0
}

# --- Read hook input ------------------------------------------------------

INPUT_JSON=""
if [ -t 0 ]; then
  # No stdin — script was invoked manually (testing). Use a synthetic input.
  INPUT_JSON='{"source":"compact","cwd":"'"$PWD"'","transcript_path":""}'
else
  INPUT_JSON="$(cat)"
fi

CWD="$(printf '%s' "$INPUT_JSON" | jq -r '.cwd // empty')"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT_JSON" | jq -r '.transcript_path // empty')"
SOURCE="$(printf '%s' "$INPUT_JSON" | jq -r '.source // empty')"

# Defensive: SessionStart fires for startup/resume/clear/compact; this script
# is wired with matcher=compact so $SOURCE should be "compact", but verify
# and bail silently if not (defense against future Claude Code matcher changes).
if [ "$SOURCE" != "compact" ]; then
  debug "skip: source=$SOURCE != compact"
  emit_response ""
fi

# Default cwd to PWD if missing.
if [ -z "$CWD" ]; then CWD="$PWD"; fi
cd "$CWD" 2>/dev/null || {
  debug "cd to cwd=$CWD failed; using PWD=$PWD"
  CWD="$PWD"
}

# Bail if not inside a git repo — Tier 1-4 all depend on git.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  debug "not in a git repo; emitting tier-5-only card"
  # Fall through; the tier loop produces just the convention pointers.
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
debug "branch=$BRANCH cwd=$CWD transcript=$TRANSCRIPT_PATH"

# --- Collect candidates per tier ------------------------------------------

# Each candidate is encoded as:  <weight>|<kind>|<path-or-text>|<annotation>
# Lines are stored in a tab-separated buffer that we later sort by weight
# (descending) and budget-truncate.
declare -a CANDIDATES=()

# ---- Tier 1: active RFC ---------------------------------------------------

if [ -n "$BRANCH" ] && [[ "$BRANCH" == rfc/* ]]; then
  RFC_ID="${BRANCH#rfc/}"
  RFC_PATH="docs/rfcs/${RFC_ID}.md"
  if [ -f "$RFC_PATH" ]; then
    CANDIDATES+=("${W_ACTIVE_RFC}|active-rfc|${RFC_PATH}|active RFC being implemented")
    debug "tier-1 hit: $RFC_PATH"
  else
    debug "tier-1 skip: branch=$BRANCH but $RFC_PATH not found"
  fi
fi

# ---- Tier 2: files modified in the last N commits -------------------------

# Cap Tier 2 at 4 entries (a global tier-2-only cap that is independently
# enforced by the overall MAX_ITEMS budget below).
TIER2_CAP=4
TIER2_COUNT=0
if [ -n "$BRANCH" ]; then
  # Resolve the commit range: prefer HEAD~N..HEAD, but if the branch has
  # fewer than N+1 commits, fall back to the full branch (root..HEAD).
  RANGE="HEAD~${RECENT_COMMITS}..HEAD"
  if ! git rev-parse --quiet --verify "HEAD~${RECENT_COMMITS}" >/dev/null 2>&1; then
    RANGE="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)..HEAD"
    [ "$RANGE" = "..HEAD" ] && RANGE="HEAD"
  fi
  debug "tier-2 range=$RANGE"

  # Get modified file list, ordered by most-recent commit first (via
  # git log --name-only --pretty=format:%ct, then awk-dedupe preserving
  # first-seen order).
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    path_excluded "$path" && { debug "tier-2 excluded: $path"; continue; }
    [ "$TIER2_COUNT" -ge "$TIER2_CAP" ] && break
    # Count commits touching this path in the range.
    COMMITS_TOUCHING="$(git log --oneline "$RANGE" -- "$path" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$COMMITS_TOUCHING" -eq 0 ] && COMMITS_TOUCHING=1
    CANDIDATES+=("${W_RECENT_COMMIT}|recent-commit|${path}|modified in last ${COMMITS_TOUCHING} commit(s)")
    TIER2_COUNT=$((TIER2_COUNT + 1))
    debug "tier-2 hit: $path ($COMMITS_TOUCHING commits)"
  done < <(
    git log --name-only --pretty=format: "$RANGE" 2>/dev/null \
      | awk 'NF && !seen[$0]++'
  )
fi

# ---- Tier 3: working-tree changes -----------------------------------------

TIER3_CAP=3
TIER3_COUNT=0
if [ -n "$BRANCH" ]; then
  # Tracked-but-modified.
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    path_excluded "$path" && continue
    [ "$TIER3_COUNT" -ge "$TIER3_CAP" ] && break
    CANDIDATES+=("${W_WORKING_TREE}|working-tree|${path}|uncommitted change")
    TIER3_COUNT=$((TIER3_COUNT + 1))
    debug "tier-3 hit (modified): $path"
  done < <(git diff --name-only HEAD 2>/dev/null)

  # Untracked.
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    path_excluded "$path" && continue
    [ "$TIER3_COUNT" -ge "$TIER3_CAP" ] && break
    CANDIDATES+=("${W_WORKING_TREE}|working-tree|${path}|untracked (new)")
    TIER3_COUNT=$((TIER3_COUNT + 1))
    debug "tier-3 hit (untracked): $path"
  done < <(git status --porcelain 2>/dev/null | awk '/^\?\?/{print $2}')
fi

# ---- Tier 4: branch name --------------------------------------------------

if [ -n "$BRANCH" ]; then
  CANDIDATES+=("${W_BRANCH}|branch|${BRANCH}|current branch")
  debug "tier-4 hit: $BRANCH"
fi

# ---- Tier 5: convention pointers ------------------------------------------

for f in CLAUDE.md docs/CONTRIBUTING.md docs/rfc-process.md; do
  if [ -f "$f" ]; then
    CANDIDATES+=("${W_CONVENTION}|convention|${f}|project conventions; read on demand")
    debug "tier-5 hit: $f"
  fi
done

# --- Budget-truncate -------------------------------------------------------

# Sort by weight descending, then by tier-index ascending (stable for ties
# via the implicit append order — sort -s preserves input order for equal
# keys). bsd-sort and gnu-sort both support -k and -r; use printf | sort.

SORTED="$(
  printf '%s\n' "${CANDIDATES[@]}" \
    | awk -F'|' 'NF==4 { printf "%05d\t%s\n", $1, $0 }' \
    | sort -rs -k1,1 \
    | cut -f2-
)"

# Truncate to MAX_ITEMS.
TRUNCATED="$(printf '%s\n' "$SORTED" | awk 'NF' | head -n "$MAX_ITEMS")"

# --- Render card ----------------------------------------------------------

render_card() {
  local lines="$1"
  [ -z "$lines" ] && return 0
  printf 'Post-compaction rehydration pointers (auto-generated; read on demand):\n'

  local has_tier
  # Tier 1
  has_tier="$(printf '%s\n' "$lines" | awk -F'|' '$2=="active-rfc"' | head -1)"
  if [ -n "$has_tier" ]; then
    printf '\nActive RFC:\n'
    printf '%s\n' "$lines" | awk -F'|' '$2=="active-rfc" { printf "  %s — %s\n", $3, $4 }'
  fi
  # Tier 2
  has_tier="$(printf '%s\n' "$lines" | awk -F'|' '$2=="recent-commit"' | head -1)"
  if [ -n "$has_tier" ]; then
    printf '\nRecently modified (last %d commits):\n' "$RECENT_COMMITS"
    printf '%s\n' "$lines" | awk -F'|' '$2=="recent-commit" { printf "  %s — %s\n", $3, $4 }'
  fi
  # Tier 3
  has_tier="$(printf '%s\n' "$lines" | awk -F'|' '$2=="working-tree"' | head -1)"
  if [ -n "$has_tier" ]; then
    printf '\nUncommitted working-tree changes:\n'
    printf '%s\n' "$lines" | awk -F'|' '$2=="working-tree" { printf "  %s — %s\n", $3, $4 }'
  fi
  # Tier 4
  has_tier="$(printf '%s\n' "$lines" | awk -F'|' '$2=="branch"' | head -1)"
  if [ -n "$has_tier" ]; then
    printf '\nCurrent branch: '
    printf '%s\n' "$lines" | awk -F'|' '$2=="branch" { printf "%s\n", $3 }'
  fi
  # Tier 5
  has_tier="$(printf '%s\n' "$lines" | awk -F'|' '$2=="convention"' | head -1)"
  if [ -n "$has_tier" ]; then
    printf '\nProject conventions (read if relevant to next task):\n  '
    printf '%s\n' "$lines" | awk -F'|' '$2=="convention" { printf "%s, ", $3 }' | sed 's/, $/\n/'
  fi
}

CARD="$(render_card "$TRUNCATED")"

# Byte-budget enforcement: if the rendered card exceeds MAX_BYTES, drop
# entries from the bottom (lowest-weight first) until it fits.
while [ "${#CARD}" -gt "$MAX_BYTES" ] && [ -n "$TRUNCATED" ]; do
  # Drop the last line of TRUNCATED (lowest-weight remaining).
  TRUNCATED="$(printf '%s\n' "$TRUNCATED" | head -n -1)"
  CARD="$(render_card "$TRUNCATED")"
  debug "byte-budget: shrinking; size=${#CARD}"
done

# --- Persist card for the UserPromptSubmit fallback ------------------------

if [ -n "$CARD" ]; then
  mkdir -p .bytewyrd 2>/dev/null || true
  printf '%s\n' "$CARD" > .bytewyrd/last-rehydration-card.md 2>/dev/null || true
fi

# --- Emit hook response ----------------------------------------------------

emit_response "$CARD"
```

The script's structure mirrors `scripts/check-requirements.sh`: a header comment block, configuration constants at the top, helper functions, then the linear probe-and-emit flow. The `set -u` posture is the same; `set -e` is deliberately omitted so a single missing-but-non-fatal command (e.g., `git log` failing on a fresh branch) does not abort the entire card render. The `_lib/common.bash` source line provides `require_jq` per the established pattern (verified: scripts/_lib/common.bash:L10-15).

After creating the file, make it executable:

```bash
chmod +x scripts/rehydrate-context.sh
```

Expected output: no output, exit code 0. Verify with:

```bash
test -x scripts/rehydrate-context.sh && echo ok
```

Expected output: `ok`.

#### Step 2 — Create `scripts/rehydrate-fallback.sh`

Create the file at `scripts/rehydrate-fallback.sh` with this exact content. The fallback fires on `UserPromptSubmit` (every user prompt), checks whether the conditions for re-injection are met, and either emits the card again or exits silently.

```bash
#!/usr/bin/env bash
# Bytewyrd plugin: post-compaction rehydration FALLBACK.
#
# Invoked by the UserPromptSubmit hook (no matcher). Re-injects the
# rehydration card via additionalContext when:
#   (a) .bytewyrd/last-rehydration-card.md exists and is fresh (<5 minutes), AND
#   (b) the user's submitted prompt is short (<20 characters, suggesting
#       a "continue"-style follow-up where the agent has no other anchor).
#
# Both conditions must hold. Otherwise the script exits silently with no
# additionalContext output (the user's prompt proceeds normally).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_lib/common.bash"
require_jq

readonly FRESHNESS_SECONDS="${BYTEWYRD_REHYDRATE_FALLBACK_FRESHNESS:-300}"
readonly SHORT_PROMPT_BYTES="${BYTEWYRD_REHYDRATE_FALLBACK_SHORT_BYTES:-20}"

# Read hook input.
INPUT_JSON=""
if [ -t 0 ]; then
  printf '{"continue":true,"suppressOutput":true}\n'
  exit 0
fi
INPUT_JSON="$(cat)"

PROMPT="$(printf '%s' "$INPUT_JSON" | jq -r '.prompt // empty')"
PROMPT_LEN="${#PROMPT}"

# Condition (b): short prompt.
if [ "$PROMPT_LEN" -ge "$SHORT_PROMPT_BYTES" ]; then
  printf '{"continue":true,"suppressOutput":true}\n'
  exit 0
fi

# Condition (a): card file exists and is fresh.
CARD_FILE=".bytewyrd/last-rehydration-card.md"
if [ ! -f "$CARD_FILE" ]; then
  printf '{"continue":true,"suppressOutput":true}\n'
  exit 0
fi

# Compute card age in seconds (portable: try GNU stat then BSD stat).
MTIME="$(stat -c %Y "$CARD_FILE" 2>/dev/null || stat -f %m "$CARD_FILE" 2>/dev/null || echo 0)"
case "$MTIME" in
  ''|*[!0-9]*) MTIME=0 ;;
esac
NOW="$(date -u +%s)"
AGE=$(( NOW - MTIME ))

if [ "$AGE" -gt "$FRESHNESS_SECONDS" ] || [ "$AGE" -lt 0 ]; then
  printf '{"continue":true,"suppressOutput":true}\n'
  exit 0
fi

# Both conditions met: re-emit the card via UserPromptSubmit additionalContext.
CARD="$(cat "$CARD_FILE" 2>/dev/null)"
if [ -z "$CARD" ]; then
  printf '{"continue":true,"suppressOutput":true}\n'
  exit 0
fi

# Consume the file so subsequent prompts (even within the freshness window)
# do not re-inject. The card is one-shot per compaction event.
rm -f "$CARD_FILE" 2>/dev/null || true

jq -n --arg ctx "$CARD" '{
  continue: true,
  suppressOutput: true,
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
```

The fallback is one-shot per compaction: when both conditions match and the card is re-injected, the card file is removed so subsequent short prompts within the same freshness window do not re-inject again. The next compaction event re-creates the card file via the primary script.

Make it executable:

```bash
chmod +x scripts/rehydrate-fallback.sh
```

Expected output: no output, exit code 0. Verify with:

```bash
test -x scripts/rehydrate-fallback.sh && echo ok
```

Expected output: `ok`.

#### Step 3 — Modify `hooks/hooks.json`

The current file (verified: hooks/hooks.json) has two events: `SubagentStop` (lines 3-17) and `SessionStart` (lines 18-36, with a `compact`-matcher entry at lines 20-27 and a no-matcher entry at lines 28-35).

Add two changes:
1. Append a second hook handler to the existing `compact`-matcher entry under `SessionStart`. The handler invokes `scripts/rehydrate-context.sh`.
2. Add a new top-level event entry `UserPromptSubmit` (no matcher) that invokes `scripts/rehydrate-fallback.sh`.

The full file after this step:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "(^|:)feature-engineer$",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, a new CLI flag, a new workflow), consider running /docs-review against the changed paths to check whether docs/guide/** needs updates.'"
          },
          {
            "type": "command",
            "command": "mkdir -p .bytewyrd && : > .bytewyrd/last-feature-engineer-stop"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .bytewyrd/last-feature-engineer-stop ]; then MTIME=$(stat -c %Y .bytewyrd/last-feature-engineer-stop 2>/dev/null || stat -f %m .bytewyrd/last-feature-engineer-stop 2>/dev/null); if echo \"$MTIME\" | grep -qE '^[0-9]+$'; then SENTINEL_AGE=$(( $(date -u +%s) - $MTIME )); else SENTINEL_AGE=999999; fi; if [ \"$SENTINEL_AGE\" -lt 86400 ]; then echo 'Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not yet have run. Consider running /docs-review against the implemented files.'; fi; fi"
          },
          {
            "type": "command",
            "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/rehydrate-context.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/rehydrate-context.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/rehydrate-context.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then exit 0; fi; bash \"$_bw_script\""
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/check-requirements.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/check-requirements.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/check-requirements.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then echo 'bytewyrd: check-requirements.sh not found in plugin root or cache; skipping' >&2; exit 0; fi; bash \"$_bw_script\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/rehydrate-fallback.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/rehydrate-fallback.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/rehydrate-fallback.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then exit 0; fi; bash \"$_bw_script\""
          }
        ]
      }
    ]
  }
}
```

The hook-script-resolution pattern (probe `CLAUDE_PLUGIN_ROOT/scripts/<name>.sh` first, then the user-cache locations) is copied verbatim from the existing `check-requirements.sh` resolver in the same file (verified: hooks/hooks.json:L32) and ensures the hook works whether the plugin is invoked from the dev checkout (`CLAUDE_PLUGIN_ROOT` set) or from the installed cache. The shape `bash "$_bw_script"` matches the existing call site for consistency.

#### Step 4 — Verify JSON validity and shell-script syntax

Run these checks:

1. **`hooks/hooks.json` is valid JSON:**

   ```bash
   python3 -m json.tool hooks/hooks.json > /dev/null && echo ok
   ```

   Expected output: `ok`.

2. **The two new hook entries are present in the file:**

   ```bash
   grep -F 'rehydrate-context.sh' hooks/hooks.json
   grep -F 'rehydrate-fallback.sh' hooks/hooks.json
   grep -F 'UserPromptSubmit' hooks/hooks.json
   ```

   Expected output (three lines, in this order):

   ```
               "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/rehydrate-context.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/rehydrate-context.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/rehydrate-context.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then exit 0; fi; bash \"$_bw_script\""
               "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/rehydrate-fallback.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/rehydrate-fallback.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/rehydrate-fallback.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then exit 0; fi; bash \"$_bw_script\""
       "UserPromptSubmit": [
   ```

3. **Both scripts parse as valid bash:**

   ```bash
   bash -n scripts/rehydrate-context.sh && bash -n scripts/rehydrate-fallback.sh && echo ok
   ```

   Expected output: `ok`.

4. **`shellcheck` passes on both scripts** (only if `shellcheck` is installed; non-fatal if not):

   ```bash
   command -v shellcheck >/dev/null && shellcheck scripts/rehydrate-context.sh scripts/rehydrate-fallback.sh && echo ok || echo "shellcheck not available — skipping"
   ```

   Expected output: `ok` (or `shellcheck not available — skipping`).

#### Step 5 — Smoke test the rehydration script in isolation

The script is testable from the terminal with a synthetic hook input. This verifies the priority schedule renders sensibly without needing a Claude Code session.

1. **Empty input (no transcript, no candidates beyond conventions):**

   ```bash
   printf '{"source":"compact","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh
   ```

   Expected output (a JSON object; pipe to `jq -r '.hookSpecificOutput.additionalContext'` to read just the card):

   ```bash
   printf '{"source":"compact","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh | jq -r '.hookSpecificOutput.additionalContext // empty'
   ```

   Expected output (when run from this repo's root on the `rfc/2026-05-17-auto-rehydrate-context-after-compaction` branch with this RFC file present, after at least one commit on the branch):

   ```
   Post-compaction rehydration pointers (auto-generated; read on demand):

   Active RFC:
     docs/rfcs/2026-05-17-auto-rehydrate-context-after-compaction.md — active RFC being implemented

   Recently modified (last 3 commits):
     <files; will vary by what was just committed>

   Uncommitted working-tree changes:
     <files; will vary by what is currently uncommitted>

   Current branch: rfc/2026-05-17-auto-rehydrate-context-after-compaction

   Project conventions (read if relevant to next task):
     CLAUDE.md, docs/CONTRIBUTING.md, docs/rfc-process.md
   ```

   The exact paths under "Recently modified" and "Uncommitted" depend on the branch state at run time. The key check is that the card has the four section headers (Active RFC, Recently modified, Current branch, Project conventions) at minimum, and that the total length is under 8 KB:

   ```bash
   printf '{"source":"compact","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh | jq -r '.hookSpecificOutput.additionalContext // empty' | wc -c
   ```

   Expected output: a number under `8192`.

2. **Wrong source field (defensive bail):**

   ```bash
   printf '{"source":"startup","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh | jq '.hookSpecificOutput // empty'
   ```

   Expected output: empty string (no `hookSpecificOutput` block; the script bailed early because `source != "compact"`).

3. **Card file persisted to disk:**

   ```bash
   printf '{"source":"compact","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh > /dev/null
   test -f .bytewyrd/last-rehydration-card.md && head -1 .bytewyrd/last-rehydration-card.md
   ```

   Expected output:

   ```
   Post-compaction rehydration pointers (auto-generated; read on demand):
   ```

4. **Debug-trace path is silent when `BYTEWYRD_REHYDRATE_DEBUG` is unset:**

   ```bash
   rm -f .bytewyrd/rehydrate.log
   printf '{"source":"compact","cwd":"%s","transcript_path":""}\n' "$PWD" | bash scripts/rehydrate-context.sh > /dev/null
   test -f .bytewyrd/rehydrate.log && echo "FAIL: debug log was written" || echo ok
   ```

   Expected output: `ok`.

5. **Debug-trace path writes when `BYTEWYRD_REHYDRATE_DEBUG=1`:**

   ```bash
   rm -f .bytewyrd/rehydrate.log
   BYTEWYRD_REHYDRATE_DEBUG=1 sh -c 'printf "{\"source\":\"compact\",\"cwd\":\"%s\",\"transcript_path\":\"\"}\n" "$PWD" | bash scripts/rehydrate-context.sh' > /dev/null
   test -s .bytewyrd/rehydrate.log && echo ok
   ```

   Expected output: `ok`.

#### Step 6 — Smoke test the fallback script

The fallback is invoked on every `UserPromptSubmit`. It should be silent (emit no `additionalContext`) when conditions are not met, and re-inject the card exactly once when conditions are met.

1. **Card file absent, short prompt — silent:**

   ```bash
   rm -f .bytewyrd/last-rehydration-card.md
   printf '{"prompt":"continue"}\n' | bash scripts/rehydrate-fallback.sh | jq '.hookSpecificOutput // empty'
   ```

   Expected output: empty string (the script emits `{"continue":true,"suppressOutput":true}` only).

2. **Card file present and fresh, long prompt — silent:**

   ```bash
   mkdir -p .bytewyrd && echo "test card" > .bytewyrd/last-rehydration-card.md
   printf '{"prompt":"this is a longer prompt that exceeds twenty characters"}\n' | bash scripts/rehydrate-fallback.sh | jq '.hookSpecificOutput // empty'
   ```

   Expected output: empty string.

3. **Card file present and fresh, short prompt — re-injects:**

   ```bash
   mkdir -p .bytewyrd && echo "test card content" > .bytewyrd/last-rehydration-card.md
   printf '{"prompt":"go"}\n' | bash scripts/rehydrate-fallback.sh | jq -r '.hookSpecificOutput.additionalContext // empty'
   ```

   Expected output:

   ```
   test card content
   ```

4. **Card file consumed after a successful re-injection:**

   ```bash
   # The previous command already consumed the file; check it's gone.
   test ! -f .bytewyrd/last-rehydration-card.md && echo ok
   ```

   Expected output: `ok`.

5. **Stale card file (mtime > 5 minutes ago) — silent:**

   ```bash
   mkdir -p .bytewyrd && echo "stale" > .bytewyrd/last-rehydration-card.md
   touch -d "1 hour ago" .bytewyrd/last-rehydration-card.md 2>/dev/null || touch -A -010000 .bytewyrd/last-rehydration-card.md
   printf '{"prompt":"go"}\n' | bash scripts/rehydrate-fallback.sh | jq '.hookSpecificOutput // empty'
   ```

   Expected output: empty string.

#### Step 7 — Modify `docs/BEST_PRACTICES.md`

Append the following entry to the `## Project-Specific` section of `docs/BEST_PRACTICES.md` (create the section header if it does not exist; do not invent a new format — match whatever bullet style the existing project-specific section already uses):

```markdown
- _Project-Specific_: The `SessionStart(compact)` hook invokes `scripts/rehydrate-context.sh`, which builds a 7-item / 8 KB pointer card listing the active RFC, recently-modified files, working-tree changes, current branch, and convention pointers. The card is written to `.bytewyrd/last-rehydration-card.md`. The `UserPromptSubmit` hook invokes `scripts/rehydrate-fallback.sh` which re-injects the card if the first post-compaction user prompt is short (<20 chars) and the card is fresh (<5 minutes). Both budgets are at the top of `scripts/rehydrate-context.sh` as `readonly` constants; per-session overrides via `BYTEWYRD_REHYDRATE_MAX_ITEMS`, `BYTEWYRD_REHYDRATE_MAX_BYTES`, `BYTEWYRD_REHYDRATE_DEBUG`. The card is pointers, not contents — the agent decides what to `Read`.
```

This documents the contract for future agents working on the plugin so they understand the rehydration system without re-reading this RFC.

#### Step 8 — Modify `docs/ARCHITECTURE.md`

Two changes:

**Change 8a — Add a row to the "Components" section.** Insert this new sub-section between the existing "Plugin manifest (`.claude-plugin/`)" section and the "Data Flow" section (preserving the existing structure described at verified: docs/ARCHITECTURE.md:L46-50):

```markdown
### Hook scripts (`scripts/`)

**Purpose:** Plugin-level shell scripts wired into Claude Code hooks. Each script reads hook input JSON on stdin and emits hook response JSON on stdout per the documented schema.
**Location:** `scripts/`
**Key interfaces:** Invoked by entries in `hooks/hooks.json` (the plugin-level hook configuration) and by entries in the plugin checkout's `.claude/settings.json` (project-level overrides). All scripts source `scripts/_lib/common.bash` for shared helpers (`require_jq`, JSON emission, plugin enable-state probe).

Current scripts:
- `check-requirements.sh` — `SessionStart` (no matcher); probes companion plugins, MCP servers, and CLI tools. Soft-warns on missing soft deps; hard-fails on missing `git` or stale `claude-plugins-official` references.
- `rehydrate-context.sh` — `SessionStart(compact)`; builds the post-compaction rehydration card (priority schedule: active RFC > recent commits > working tree > branch > conventions; budgets: 7 items, 8 KB).
- `rehydrate-fallback.sh` — `UserPromptSubmit`; re-injects the rehydration card when the first post-compaction user prompt is short and the card is fresh (<5 minutes).
```

**Change 8b — Add a row to the "Design Decisions" table.** Append this row to the table at verified: docs/ARCHITECTURE.md:L63-69:

```markdown
| Rehydration policy location | Shell script (`scripts/rehydrate-context.sh`) with `readonly` constants and env-var overrides | Matches the established `check-requirements.sh` pattern; rules are testable in isolation; takes effect on next session start with no Claude Code restart; avoids a settings-file schema extension Claude Code does not document |
```

These changes keep `docs/ARCHITECTURE.md` aligned with the new components per the file's own scope guidance ("A component is added, renamed, or removed", verified: docs/ARCHITECTURE.md:L5-7).

#### Step 9 — End-to-end smoke test (manual, after the changes land)

This step requires a live Claude Code session and cannot be scripted from the implementation harness. It exists to verify the hook actually fires and the card actually injects.

1. Start a new Claude Code session in the plugin's checkout on the `rfc/2026-05-17-auto-rehydrate-context-after-compaction` branch (or any branch with recent commits and uncommitted changes).
2. Have a substantive conversation that involves reading several files and modifying at least two of them. The exact content does not matter — the goal is to fill enough of the context window that compaction will fire when triggered.
3. Manually trigger compaction with `/compact`. (Per the existing `PreCompact` block-and-release pattern, this will first prompt for `/best-practices-extract` — run that skill, approve or decline candidates, then re-run `/compact` to proceed past the gate.)
4. After compaction completes, observe the next agent turn. The expected behavior: the rehydration card appears in the conversation as a `<system-reminder>` block listing the active RFC, recently-modified files, current branch, and convention pointers.
5. Type a short follow-up prompt ("continue" or "go"). If the primary injection was attended to, the agent's response references the items in the card. If the primary injection was missed (the documented #15174 failure mode), the `UserPromptSubmit` fallback should re-inject the card alongside the short prompt — verify by reading the `additionalContext` block that appears next to the short prompt in the transcript.
6. Verify the card file was created and consumed correctly:

   ```bash
   test ! -f .bytewyrd/last-rehydration-card.md && echo "ok — card consumed by fallback" \
     || echo "card still present — fallback did not fire OR primary injection succeeded and no short prompt was sent"
   ```

   Either outcome is acceptable for a smoke test; the second message just means the fallback did not need to fire.

7. If the primary injection failed (no `<system-reminder>` appeared after compaction), enable debug tracing and re-test:

   ```bash
   export BYTEWYRD_REHYDRATE_DEBUG=1
   ```

   Restart the session, repeat the compaction, then inspect `.bytewyrd/rehydrate.log`. Expected log lines: `branch=...`, `tier-1 hit: ...`, `tier-2 range=...`, `tier-X hit: ...`. If the log is empty, the hook did not fire — re-check the JSON in `hooks/hooks.json` and the `bash -n` syntax check from Step 4.

   The most likely root causes if the hook fires but no card injects (in order):
   - The `SessionStart(compact)` matcher is not surfacing in this Claude Code version (the matcher table at https://code.claude.com/docs/en/hooks-guide is the canonical reference; if the doc lists `compact` as supported and it still does not fire, the upstream bug #15174 is the explanation).
   - The script bailed out via `emit_response ""` because `$SOURCE != "compact"` — check the debug log for the `skip: source=...` line.
   - The script's `additionalContext` was returned but Claude attended to the compaction summary instead — this is the documented #15174 / #17237 failure mode. The fallback (`UserPromptSubmit`) should compensate on the next short prompt.

## Risks and open questions

- **Risk: `SessionStart(compact)` injection is silently ignored.** The known issue (#15174 closed-as-duplicate of #13650, #17237 still-open, Exa: https://github.com/anthropics/claude-code/issues/17237) is the largest single risk. The model attends to the compaction summary and the user's next prompt; the system-reminder card sometimes does not get attended to. **Mitigation:** Option D fallback (`UserPromptSubmit` re-injection on short prompts) targets the failure mode that hurts most. If real-world use shows the primary injection succeeds <30% of the time, escalate to a more aggressive fallback (re-inject on *every* post-compaction user prompt within 10 minutes, with a one-shot consumption). The mitigation knobs are constants at the top of the fallback script.

- **Risk: card-injection prompt-injection-defense triggering.** Anthropic's docs warn that `additionalContext` framed as out-of-band system commands can trigger prompt-injection defenses (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks). **Mitigation:** the card uses factual statements ("Active RFC: ..."; "Recently modified: ...") rather than imperatives ("YOU MUST read ..."). The opening line explicitly labels the card as auto-generated reference material. The consensus-review reviewers should verify the wording for any phrase that reads as a direct command rather than a fact.

- **Risk: `git log` queries are slow on large repos.** The Tier 2 query `git log --name-only --pretty=format: HEAD~3..HEAD` is O(commits × files-per-commit). On a repo with hundreds of files per commit, the query could add 100+ ms to session start. **Mitigation:** the range is bounded to the last 3 commits (constant `RECENT_COMMITS`). At 3 commits and 50 files per commit, the query runs in <50 ms on any modern disk; on the plugin's own checkout the query runs in <10 ms. If real-world use on larger repos shows a problem, the constant can be reduced to 1 or the query can be replaced with `git diff --name-only HEAD~3 HEAD` which is faster for path-only output.

- **Risk: working-tree change list includes `.bytewyrd/`-relative files when the script itself creates the card file.** The `.bytewyrd/` directory is in the ignore-list (`PATH_IGNORE_GLOBS`) and is gitignored at the repo level (verified: .gitignore:L4-5), so `git status --porcelain` does not show it. The script's `: > .bytewyrd/last-rehydration-card.md` write does not create a working-tree change. **Mitigation:** verified by the smoke test in Step 5 (smoke test 1 should not include `.bytewyrd/` paths in the rendered card).

- **Risk: the priority schedule misses an important "explicit pinning" signal.** A user who wants a specific file ALWAYS in the card cannot pin it today. **Resolution within this RFC:** out of scope. A follow-up RFC could add a `.bytewyrd/rehydrate-pin.txt` file (one path per line) read by the script as a Tier 0 (highest priority). The single-file mechanism is small enough to add later without restructuring the script. Defer.

- **Risk: the rehydration card races with `CLAUDE.md` re-load.** Per the Mintlify sessions doc (Exa: https://www.mintlify.com/vineetagarwal-code/claude-code/concepts/sessions): "The `getMemoryFiles` cache is cleared so any updated `CLAUDE.md` files are re-read into the new context." This means `CLAUDE.md` is always loaded post-compaction; listing it in Tier 5 is redundant. **Mitigation:** keep `CLAUDE.md` in Tier 5 anyway — the cost is two characters in the convention-pointers line ("CLAUDE.md, "), and the redundancy is harmless. Some consumer projects have CLAUDE.md files that exceed the auto-load threshold and only the top section is loaded; the explicit pointer reminds the agent that the full file is available.

- **Open question: should the card also include the most recent assistant tool-call list from the transcript?** The `transcript_path` is provided in the hook input and contains every assistant turn's tool calls in JSONL. Parsing the last 5 tool-call paths could give a strong "what file was the agent literally just reading" signal. **Resolution within this RFC:** deferred. The transcript-parse path has two operational complications: (a) the JSONL files can be large (tens of thousands of lines for long sessions, Exa: https://fazm.ai/blog/claude-code-previous-sessions-jsonl-transcripts), and a synchronous parse on `SessionStart` adds latency; (b) the `transcript_path` field is sometimes empty (#13668). The git-history + working-tree signals are 80% of what the transcript would give and are 100% reliable. Defer transcript parsing to a follow-up RFC with an explicit benchmark of how much accuracy improves.

- **Open question: should the `UserPromptSubmit` fallback fire on more than just short prompts?** The current trigger (`<20 characters`) targets the "continue" case. A medium-length but vague prompt ("let's keep going on this") would not fire the fallback even though the agent has no anchor. **Resolution within this RFC:** start narrow. The cost of a too-eager fallback is constant re-injection of the same card on every user turn within the freshness window, which becomes noise. If real-world use shows the short-prompt heuristic misses the failure mode often, widen to 40 characters or add a content heuristic (lowercase a-z only; no file paths; no proper nouns). Constants are at the top of the fallback script.

- **Open question: should the rehydration card include a "what to do next" recommendation?** The card lists facts; it does not say "I recommend you Read file X first." Adding a recommendation crosses the line from factual context to instruction, which (per the prompt-injection-defense risk above) can trigger defenses. **Resolution within this RFC:** keep the card factual. The agent reasons about what to read; the card just lists what is in flight.

- **Open question: does this RFC need to coordinate with the planned "Move plugin state to `.bytewyrd/` and commit version tracking" braindump entry?** That braindump entry proposes moving plugin-managed state from `.claude/` to `.bytewyrd/` and committing some of it (verified: docs/rfc-braindump.md:L12). The rehydration card file (`.bytewyrd/last-rehydration-card.md`) is ephemeral (one-shot per compaction) and should remain gitignored regardless of how that future RFC lands — the entry itself says "Only ephemeral runtime sentinels (e.g. `precompact-extraction-done`) stay gitignored." The rehydration card belongs to that ephemeral class. **Resolution within this RFC:** no coordination needed; the card file's gitignored status is correct under either current or proposed conventions.

## Relationship to other RFCs

- **`2026-05-12-auto-extract-best-practices-on-precompact`** (status: Done) — the prior `PreCompact` extraction gate. This RFC's `SessionStart(compact)` hook fires on the opposite side of compaction (post, not pre) and uses a sibling sentinel directory (`.bytewyrd/`). The two are operationally orthogonal: extraction blocks compaction until learnings are captured; rehydration injects a pointer card after compaction completes. They share the `.bytewyrd/` sentinel directory but write to different files (`precompact-extraction-done` vs `last-rehydration-card.md`). No structural conflict.
- **`2026-05-10-documentation-agent-lifecycle-hooks`** (status: Done) — established the existing `SessionStart(compact)` hook for the docs-review reminder (verified: hooks/hooks.json:L19-26). This RFC adds a second sibling handler to the same event entry; the two coexist per Anthropic's documented "multiple hooks' additionalContext values are concatenated" behavior (Exa: https://docs.anthropic.com/en/docs/claude-code/hooks). No changes required to the docs-review hook.
- **Braindump entry: "Move plugin state to `.bytewyrd/` and commit version tracking"** (verified: docs/rfc-braindump.md:L12) — a candidate future RFC. Its proposed migration of `.claude/` → `.bytewyrd/` would not affect this RFC's rehydration card location (the card belongs to the "ephemeral runtime sentinels stay gitignored" class that the braindump explicitly preserves). If the braindump is promoted to an RFC and lands, no change to the rehydration scripts is needed.
- **Upstream feature requests this RFC depends on for full reliability:** `#46191` (`additionalContext` support for `PreCompact`/`PostCompact`, Exa: https://github.com/anthropics/claude-code/issues/46191) and `#41224` (`PostCompact` stdout context injection, Exa: https://github.com/anthropics/claude-code/issues/41224). When either lands, the RFC's `SessionStart(compact)` mechanism can be supplemented or replaced by a more reliable injection point. A follow-up RFC will revisit the implementation if/when those upstream changes ship.
- **Future RFC: explicit pin-list for the rehydration card.** Mentioned in "Risks and open questions" above. Adds a `.bytewyrd/rehydrate-pin.txt` file as a Tier 0 source. Small addition; deferred until real-world use suggests it.
- **Future RFC: transcript-aware tier.** Mentioned in "Risks and open questions" above. Adds a tier between Tier 2 and Tier 3 that parses the last K tool-call paths from `transcript_path`. Adds latency and parser complexity; deferred until the value justifies the cost.
