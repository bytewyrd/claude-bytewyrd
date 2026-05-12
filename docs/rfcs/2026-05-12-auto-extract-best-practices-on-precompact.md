---
rfc: "2026-05-12-auto-extract-best-practices-on-precompact"
title: "Auto-Run /best-practices-extract on PreCompact"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Change the bytewyrd plugin's `PreCompact` hook from an advisory reminder ("consider running `/best-practices-extract`") into an enforced extraction gate: the hook blocks compaction via `{"decision": "block"}`, injects a strongly-worded `additionalContext` system reminder that instructs the live session's Claude to run `/best-practices-extract` immediately, and uses a sentinel file (`.bytewyrd/precompact-extraction-done`) as the release condition so the next compaction trigger goes through without re-blocking. The user retains the existing veto inside the extraction skill (the "Add any? (1, 2, 3, generalizable, project-specific, all, none)" prompt) — the human still decides *which* learnings to keep, but the extraction step itself stops being optional. The implementation is one edited entry in `.claude/settings.json` plus a small "release the block" instruction added to `skills/best-practices-extract/SKILL.md`. No new files, no new skills, no marker maintenance burden.

## Should we do this?

**Yes.** The current `PreCompact` hook prints an advisory line; the live agent typically ignores it because the reminder reads as a suggestion rather than a mandate, and because the imminent compaction event creates a "the user just wants their context back" pressure that biases the agent toward yielding rather than doing extra work. The result is the failure mode the braindump names directly: extraction is opt-in, the human has to remember to type `/best-practices-extract`, and most sessions compact without any extraction at all — non-obvious learnings are wiped at exactly the moment they were most valuable.

The mechanism this RFC uses (block compaction + inject system reminder + release via sentinel file) is documented and supported by Claude Code v2.1.105 and later (released 2026-04-13). It does **not** require a new feature, an MCP server, or any modification to Claude Code itself; it is a configuration change to one existing hook plus three lines added to one existing skill. The cost of the change is small enough that "should we do this" reduces to "should the extraction step be mandatory before compaction"; the answer is yes because (a) the human still gates *what* is captured at the per-item prompt inside the skill, so this RFC does not remove human control — it only removes the option to skip the step entirely; and (b) the entire purpose of `/best-practices-extract` is to run before context loss, and a hook that fires before context loss but does not actually trigger the extraction is just observability theater. If the extraction is not worth running automatically, the right move is to delete the skill; the right move is not to keep a hook that fires-but-does-not-act.

## Current state

The plugin's `PreCompact` hook is wired in `.claude/settings.json` to print one advisory line. The `/best-practices-extract` skill is fully built, has a deliberate user-approval gate per candidate, and is documented to run "automatically: `PreCompact` hook fires before conversation compaction." That documentation is currently aspirational — the hook does not actually fire the skill.

**What exists today:**

- `.claude/settings.json` (lines 13–22) — the `PreCompact` hook entry. Today it is:

  ```json
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
        }
      ]
    }
  ]
  ```

  The hook prints to stdout. Claude Code surfaces this output in the hook log, but plain stdout from a command hook is **not** injected into the live agent's context as a system reminder — that requires the `additionalContext` field in structured JSON output (see Direction 1 in the Analysis section). The current advisory `echo` is observability-only: the live agent does not see it as an in-context prompt. No matcher is set, so the hook fires for both automatic and manual (`/compact`) triggers — that part is correct and is preserved by this RFC.

- `skills/best-practices-extract/SKILL.md` (130 lines) — the skill itself. The body is well-factored: an extraction pass that scans the conversation, a triage step that classifies candidates as generalizable vs project-specific, a mandatory-filter pass, a lift pass (strip identifiers, add domain prefix), a user-confirmation prompt (`Add any? (1, 2, 3, generalizable, project-specific, all, none)`), and a write step that appends approved entries to `docs/BEST_PRACTICES.md`. The "When to Run" section at the bottom explicitly names the `PreCompact` hook as the automatic trigger — but again, the wiring described there is not what the current hook does. The skill is the right shape for an automatic invocation; only the trigger is broken.

- `docs/BEST_PRACTICES.md` — the project-local destination for approved entries. The file exists and contains real entries from prior sessions, so the skill is being invoked manually with some regularity. The `Stop` hook (`.claude/settings.json` lines 53–66) also reminds the agent to run `/best-practices-extract` at session end — that reminder is a separate code path, equally advisory, and is **not** modified by this RFC (session-end reminders sit at a different decision point than imminent context loss).

- `~/.claude/BEST_PRACTICES.md` — the user-global destination, written by the separate `/best-practices-record` skill (not by `/best-practices-extract`). This RFC does not change `/best-practices-record`; the global file remains a deliberate, cross-project decision per the skill's own design.

- Claude Code v2.1.105 (released 2026-04-13) — added blocking support for `PreCompact` hooks: a hook may return `{"decision": "block"}` (or exit with code 2) to veto the compaction event. The plugin's `engines.claude_code` constraint (no such field exists today; the plugin's `plugin.json` has `version`, `name`, `description`, `author` only) implicitly supports the latest stable Claude Code; the project assumes a recent enough Claude Code in the same way the existing hook system assumes it. Documented behavior when blocking: if compaction was triggered proactively (before the context limit), Claude Code skips it and the conversation continues; if compaction was triggered to recover from a context-limit error already returned by the API, the underlying error surfaces and the request fails. The block-then-release pattern handles both cases — the release-condition sentinel ensures the next trigger goes through, capping the window-exhaustion risk at one extra exchange.

- `additionalContext` injection — the documented mechanism for command hooks to inject text the live agent will read on its next model request. The text appears as a system reminder in the conversation (the same `<system-reminder>` wrapping users see for date changes, MCP server instructions, etc.) at the point the hook fired. The 10,000-character cap is far above what this RFC needs (the reminder is two short paragraphs). The Anthropic docs warn that text framed as out-of-band system commands ("YOU MUST do X") can trigger prompt-injection defenses; the recommended framing is factual statements that establish what is true and what action is expected. This RFC's reminder text is written in that style — see Step 1 below for the exact wording.

**What is broken:**

1. **The hook fires but does not trigger the skill.** The current `echo` reminder is observability-only. The braindump's framing is precise: "the PreCompact hook only prints a reminder, leaving extraction as an opt-in user action."
2. **The live-session constraint that defeated earlier attempts is documented but not addressed.** A hook is a shell command; it cannot natively invoke a `/`-prefixed skill, and a spawned `claude` process started from inside the hook would lack the live session's history (and therefore could not perform the extraction the skill is designed for). The braindump names this constraint exactly and lists three directions to explore. This RFC's analysis evaluates each direction concretely, recommends one, and shows the exact change.
3. **Documentation drift.** `skills/best-practices-extract/SKILL.md` claims the `PreCompact` hook automatically triggers it. The hook does not. Either the hook becomes what the skill claims (this RFC) or the skill's "When to Run" text needs to be corrected to say "automatically: not yet wired; advisory reminder only." The first option is what the braindump asks for and is the only option that actually serves users.
4. **Compaction proceeds without extraction by default.** The most expensive and least recoverable failure mode in the plugin: a session that produced real architectural insight compacts, the live history is gone, and the agent's only memory of "we decided X for reason Y" is the summarized narrative — which generally does not preserve the level of detail that makes a best-practice entry useful.

## Analysis / Options

The braindump lists three directions; all three must be evaluated against the constraint that hooks are shell commands and a spawned `claude` lacks the live session's conversation history. The analysis below names each direction, shows what it would look like concretely, and recommends one.

### Direction 1 — Strongly imperative reminder

**Shape.** Keep the hook as a command hook, but replace the polite `echo` with a longer, system-reminder-shaped text that establishes (a) that extraction has not happened, (b) that compaction is imminent, and (c) that running `/best-practices-extract` is the expected next action. The hook returns JSON with `additionalContext` set to the reminder text, which Claude Code wraps in a `<system-reminder>` tag and injects into the live agent's context on its next model request.

**What it would look like.** A hook entry like:

```json
{
  "type": "command",
  "command": "cat <<'JSON'\n{\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is imminent. The /best-practices-extract skill has not yet run in this session; if it had, the file .bytewyrd/precompact-extraction-done would exist. Run /best-practices-extract now — this is a mandatory step of the compaction flow, not a suggestion. The skill itself preserves the human-approval prompt for each candidate.\"},\"continue\":true}\nJSON"
}
```

The text is written in the factual-statement style Anthropic recommends (rather than as out-of-band imperatives that risk triggering prompt-injection defenses).

**Strengths.** Zero new files. Reuses the existing hook infrastructure. The reminder appears in the live session's context exactly when needed; the live agent's tool set is intact, so it can run the skill itself with full access to the session's history.

**Weakness.** Without compaction blocking, the reminder competes with the compaction event for the agent's next action. Anthropic's docs describe `additionalContext` as appearing in the conversation "at the point where the hook fired"; for `PreCompact` specifically, the compaction event is the very next thing that happens, and an agent that received the reminder may not act on it before yielding — exactly the failure mode the GitHub issue at `anthropics/claude-code#17237` describes for the analogous `SessionStart(compact)` injection ("Claude ignores the SessionStart output. The compaction summary momentum wins."). The reminder alone is necessary but not sufficient. This weakness is eliminated by the block in Direction 3 — once compaction is vetoed, the agent has no pending compaction action to complete; the `additionalContext` reminder becomes the primary signal for the agent's next turn.

### Direction 2 — In-session skill triggering from a hook

**Shape.** Find a Claude Code mechanism that lets a hook directly invoke a skill in the live session, with access to the live session's conversation history. The braindump's wording suggests this is the question to investigate: "any Claude Code mechanism allowing hooks to trigger in-session skill execution with conversation context."

**What it would look like.** The mechanisms Claude Code exposes for hooks are:

- `type: "command"` — runs a shell command. The shell command cannot reach back into the live session's tool surface (it has no client connection; its only IPC is stdin/stdout/exit code). Cannot invoke a slash command. Cannot read the conversation transcript directly except via `$CLAUDE_TRANSCRIPT_PATH`, which is a path to a JSON log file — readable, but the *agent* doing the extraction would need access to the live tool set, not just the historical transcript.
- `type: "prompt"` — calls a separate model (a fresh Claude instance) with the prompt text and the hook's JSON input. The fresh model has no access to the live session's conversation history or tool surface; it is a single-turn evaluation that returns a JSON decision. This matches the braindump's constraint precisely — "a spawned `claude` lacks the live session's history" — and means a prompt-based hook cannot perform the extraction.
- `type: "agent"` (in newer Claude Code versions per the AgentPatterns reference) — spawns a subagent with tool access. Same constraint: the subagent does not inherit the live session's conversation; it starts fresh.

There is no documented mechanism that lets a hook reach back into the live session and directly invoke a skill. Per Claude Code's documented hook surface, command hooks communicate through stdout, stderr, and exit codes only; they cannot trigger `/` commands or tool calls.

**Strengths.** If such a mechanism existed, it would close the loop perfectly — the hook *would* be the extraction trigger, not just a reminder of it.

**Weakness.** The mechanism does not exist as of Claude Code's documented hook surface in 2026-05. Direction 2 in its pure form is blocked at the platform level. It can be approximated by combining `additionalContext` injection (Direction 1) with compaction blocking (Direction 3) so the live agent itself becomes the executor — but that approximation is exactly what the recommendation below uses, so calling it "Direction 2" understates what it actually is.

### Direction 3 — Restructure extraction as a first-class step of compaction

**Shape.** Use Claude Code v2.1.105's `PreCompact` blocking capability to make extraction a non-optional phase of the compaction flow. The hook returns `{"decision": "block"}` to veto the imminent compaction, injects `additionalContext` instructing the live agent to run `/best-practices-extract`, and uses a sentinel file as the release condition. After the skill completes, it writes the sentinel file; the next compaction trigger fires the hook again, the hook sees the sentinel and allows compaction through. The veto-then-release pattern makes extraction a true gate rather than a suggestion.

**What it would look like.** A hook entry like:

```json
{
  "type": "command",
  "command": "if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; cat <<'JSON'\n{\"continue\":true}\nJSON\nelse mkdir -p .bytewyrd; cat <<'JSON'\n{\"decision\":\"block\",\"reason\":\"...\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"...\"}}\nJSON\nfi"
}
```

The sentinel lives at `.bytewyrd/precompact-extraction-done`. On first fire (sentinel absent), the hook blocks compaction and injects the reminder. The live agent runs `/best-practices-extract`; the skill's apply step (at the very end, after writing to `docs/BEST_PRACTICES.md`) creates the sentinel file with `mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done`. The user (or the agent) then triggers the next compaction (manually with `/compact`, or by continuing the conversation until the auto-threshold fires again); the hook fires, sees the sentinel, deletes it, and allows compaction.

**Strengths.** Extraction is a true gate — there is no path that compacts without first prompting the live agent to extract. The mechanism is documented and supported. The pattern is small (one hook entry, one sentinel-write line added to the skill). The user retains per-candidate veto inside the skill, so the "human decides which learnings to keep" property is preserved; only the "human decides whether to extract at all" decision is removed (which is the explicit braindump goal).

**Weakness.** The sentinel file is project-local state — it sits in `.bytewyrd/`, which is gitignored. If the user reboots the editor mid-session and the working tree was wiped (or the worktree was switched), the sentinel disappears and the hook re-blocks on the next compaction. This is an acceptable failure mode: re-running extraction once after a worktree switch is cheap (the second invocation finds nothing new and exits with "Nothing new to capture this session"), and is significantly better than the current failure mode (extraction never happens at all). Indefinite blocking via a bug (e.g., the skill ran but did not write the sentinel) is bounded — the user can `rm .bytewyrd/precompact-extraction-done` or set the sentinel manually to force compaction through.

### Recommendation — combine Direction 1 and Direction 3

The recommendation is to combine the strongly-imperative reminder (Direction 1) with the block-and-release pattern (Direction 3). Direction 2 is blocked at the platform level; the closest approximation to "trigger the skill from the hook" is to make the live agent the executor by (a) blocking compaction so the agent has time to act, and (b) injecting a reminder that establishes the extraction as the expected next action. The combination is:

- The hook blocks compaction (`decision: "block"`) on first fire.
- The hook injects `additionalContext` instructing the live agent to run `/best-practices-extract`.
- The skill writes a sentinel file (`.bytewyrd/precompact-extraction-done`) as the last step of its apply phase.
- On the next compaction trigger, the hook sees the sentinel, deletes it, and allows compaction through.

This serves all three directions the braindump named: the reminder is strongly imperative (Direction 1); the live agent — with full access to the session's history and tool surface — is what actually runs the skill, which is the practical realization of Direction 2 ("in-session skill execution"); and the block-and-release pattern restructures extraction into a first-class phase of the compaction flow (Direction 3). It uses only documented, supported Claude Code mechanisms; it is small (one edited hook entry, three added lines to one skill); and it preserves the per-candidate human-approval discipline that makes the skill trustworthy.

## Drawbacks

- **Indefinite block risk if the skill never writes the sentinel.** The block-and-release pattern depends on the skill writing `.bytewyrd/precompact-extraction-done` at the end of every successful run. If a bug, a skill update, or a user intervention causes the sentinel never to be written, the hook re-blocks every compaction trigger until the user manually creates the file. **Mitigation:** (a) Step 2 of the implementation adds the sentinel-write as an unconditional last step of the skill's apply phase, including the "Nothing new to capture this session" exit path — the sentinel is written even when no entries were added, because the skill *did* run; (b) the hook's `reason` field tells the user exactly how to bypass the block manually (`touch .bytewyrd/precompact-extraction-done && /compact`); (c) the verification step in the implementation spec confirms the sentinel-write is on every exit path.

- **Sentinel survives across `/clear`.** If the user runs `/clear` to reset the session, the conversation is gone but the project-local sentinel file is not — and the next compaction trigger will see a stale sentinel and let compaction through without extraction. The "freshness window" is one compaction event per sentinel write. **Mitigation:** the `SessionStart` hook added in Step 1 (`rm -f "${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done"`) eliminates the stale-sentinel failure mode: on every new session start, the sentinel is deleted, so the gate begins clean regardless of what the prior session did or did not write. `/clear` followed by opening a new session still satisfies this guarantee — the sentinel is gone when the new session fires `SessionStart`.

- **Compaction in API-error recovery mode fails the in-flight request.** Per the AgentPatterns reference: if auto-compaction was triggered to recover from a context-limit error already returned by the API, blocking the compaction surfaces that error and fails the in-flight request. **Mitigation:** this is rare (auto-compaction normally fires proactively, before the context limit, not as error recovery) and is detectable by the user (the failing request returns a recognizable error). The user's recourse is `touch .bytewyrd/precompact-extraction-done && /compact` (or just re-running the failed request after the next manual compaction). The mitigation cost is one extra command in the failure mode; the value is extraction-by-default in the common case. Accepted trade-off.

- **Reminder framing must avoid prompt-injection defense triggers.** Anthropic's docs warn that `additionalContext` text framed as out-of-band system commands ("YOU MUST run X") can trigger Claude's prompt-injection defenses, which causes Claude to surface the text to the user instead of treating it as context — the exact opposite of what this RFC needs. **Mitigation:** the reminder text is written as factual statements that establish state and expectations ("Compaction is blocked until best-practices extraction runs. The `/best-practices-extract` skill is the expected next action..."), not as imperatives at the agent. Step 1's exact wording is reviewed for this property; consensus-review reviewers should specifically check for prompt-injection-defense-triggering phrasing.

- **The skill becomes harder to skip when the user genuinely has no learnings to capture.** A short session with no insight value still triggers the block-and-extract flow before compaction. The skill itself handles this case — its "If nothing passes triage and filtering, say so — 'Nothing new to capture this session.' Do not pad" instruction means the worst case is one extra agent turn that exits with no writes. The sentinel is written either way, so the next compaction passes through. The cost is one minor agent turn; the value is zero false negatives (no session compacts without first asking "is there anything to capture?"). **Mitigation:** none needed — the skill's own no-op path is the mitigation.

- **Worktree-local sentinel does not coordinate across worktrees.** If a user runs `/best-practices-extract` in one worktree of a project, the sentinel lives at `<worktree>/.bytewyrd/precompact-extraction-done`. A sibling worktree compacting does not see the sentinel and will re-block. **Mitigation:** by design. The skill's effects (writes to `docs/BEST_PRACTICES.md`) are also worktree-local until merged. Each worktree is its own session context with its own learnings; a sibling worktree that compacts should run its own extraction with its own conversation history. The per-worktree sentinel correctly models this.

- **`PreCompact` hook framing must not block manual `/compact` invocations the user explicitly wanted.** If the user explicitly invokes `/compact` after deciding "I have no learnings to extract this session and I want compaction to proceed," blocking the first attempt is surprising. **Mitigation:** the `reason` field in the JSON output is shown to the user when `decision: "block"` is returned. The reason text explicitly names the bypass: "Compaction blocked: best-practices extraction has not run this session. Run `/best-practices-extract` (the skill handles the no-op case), or bypass with `touch .bytewyrd/precompact-extraction-done` then re-run `/compact`." The bypass is documented at the moment the user encounters the block, not buried in a doc the user has to find.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `.claude/settings.json` | Replace the existing one-line `echo` `PreCompact` hook entry with a multi-line shell command that checks the sentinel file, returns `{"continue": true}` (and deletes the sentinel) when present, or returns `{"decision": "block", "reason": "...", "hookSpecificOutput": {"hookEventName": "PreCompact", "additionalContext": "..."}}` when absent. Hook fires for both `auto` and `manual` triggers (no `matcher` specified). Also add a `SessionStart` hook entry that deletes the sentinel on every session start, ensuring a clean gate state for each new session. |
| Modify | `skills/best-practices-extract/SKILL.md` | Add a final unconditional step ("Mark extraction done") to the apply phase that writes the sentinel file (`mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done`). The step runs on every successful exit path, including the "Nothing new to capture this session" no-op path. Update the "When to Run" section to reflect that the `PreCompact` hook now enforces the gate, not just prints a reminder. |
| Modify | `.gitignore` (project root) | Add `.bytewyrd/` to gitignore if not already present. The sentinel file and any future bytewyrd-local state belongs there; it is not part of the project's committed history. |
| Modify | `docs/BEST_PRACTICES.md` (optional, project-specific entry) | Add one project-specific best-practice entry capturing the "PreCompact blocks compaction until extraction runs; release condition is `.bytewyrd/precompact-extraction-done`; bypass is `touch <sentinel> && /compact`" mechanism, so future agents working on this plugin understand the contract without re-reading this RFC. |

No new files. No new skills. No new agents. No new dependencies.

### Steps

#### Step 1 — Modify `.claude/settings.json` (replace the `PreCompact` entry)

The current `PreCompact` entry (`.claude/settings.json` lines 13–22) is:

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "echo 'PreCompact: context is about to be compacted — run /best-practices-extract now to preserve non-obvious learnings before they are lost.'"
      }
    ]
  }
]
```

Replace the entire `PreCompact` entry with the block-and-release form below. The replacement preserves the existing structure (one matcher-less rule with one hook handler) and uses a single shell command that emits JSON to stdout — the canonical way command hooks return structured output per the Claude Code hook reference.

```json
"PreCompact": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf '%s\\n' '{\"continue\":true}'; else mkdir -p .bytewyrd; printf '%s\\n' '{\"decision\":\"block\",\"reason\":\"Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is blocked until /best-practices-extract runs in this session. The sentinel file .bytewyrd/precompact-extraction-done does not exist, which means extraction has not yet completed. The expected next action is to invoke /best-practices-extract; the skill itself preserves the per-candidate human-approval prompt, so this gate does not write anything without confirmation. When the skill completes (including the no-op path where nothing passes triage), it creates the sentinel file and the next compaction trigger will be allowed through. To bypass without extraction, the user can run: touch .bytewyrd/precompact-extraction-done then /compact.\"}}'; fi"
      }
    ]
  }
]
```

The shell command does three things:

1. **If sentinel present (extraction already ran this session)** — `rm -f .bytewyrd/precompact-extraction-done` deletes it (so the *next* compaction also enforces extraction; each compaction event is independently gated), then `printf` emits `{"continue":true}` which is the documented Claude Code output for "let the event proceed normally."
2. **If sentinel absent (extraction has not yet run)** — `mkdir -p .bytewyrd` ensures the directory exists for the upcoming skill-write, then `printf` emits the block JSON with three top-level fields: `decision: "block"` (vetoes the compaction per Claude Code v2.1.105's documented `PreCompact` decision control), `reason` (shown to the user when block is returned; names the bypass explicitly), and `hookSpecificOutput.additionalContext` (the system reminder injected into the live agent's context; phrased as factual statements per Anthropic's `additionalContext` framing guidance).
3. **No `matcher` field** — the hook fires for both `auto` and `manual` triggers. The existing hook had no matcher; this preserves that behavior. The user's explicit `/compact` invocation is also gated, which is intentional (the bypass is named in `reason`).

The `printf '%s\n'` pattern is chosen over `echo` for portable single-line JSON output that does not interpret backslash escapes inside the JSON string. Inside JSON-in-JSON, the literal `\\n` in the command string (escaped JSON `\n`) is what reaches the shell; `printf '%s\n'` prints the JSON exactly as-is followed by a single newline. The hook's output is a single line of JSON, which is what Claude Code's hook reference shows for the canonical block-decision return.

The full `.claude/settings.json` after this step (the `PreCompact` block is replaced and a sentinel-delete entry is added to `SessionStart`; `PostToolUse`, `Stop`, and the `enabledPlugins` / `extraKnownMarketplaces` blocks are unchanged):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f docs/BEST_PRACTICES.md ] && [ -f skills/sync/SKILL.md ]; then PROJECT_VER=$(grep -m1 'bootstrap-content-version:' docs/BEST_PRACTICES.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); PLUGIN_VER=$(grep -m1 'bootstrap-content-version:' skills/sync/SKILL.md 2>/dev/null | sed -E 's/.*bootstrap-content-version: ([^ ]+).*/\\1/'); if [ -n \"$PLUGIN_VER\" ] && [ \"$PROJECT_VER\" != \"$PLUGIN_VER\" ]; then echo \"SessionStart: bootstrap content has new entries (project=$PROJECT_VER, plugin=$PLUGIN_VER). Consider running /sync to refresh docs/BEST_PRACTICES.md.\"; fi; fi"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "rm -f \"${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done\""
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf '%s\\n' '{\"continue\":true}'; else mkdir -p .bytewyrd; printf '%s\\n' '{\"decision\":\"block\",\"reason\":\"Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is blocked until /best-practices-extract runs in this session. The sentinel file .bytewyrd/precompact-extraction-done does not exist, which means extraction has not yet completed. The expected next action is to invoke /best-practices-extract; the skill itself preserves the per-candidate human-approval prompt, so this gate does not write anything without confirmation. When the skill completes (including the no-op path where nothing passes triage), it creates the sentinel file and the next compaction trigger will be allowed through. To bypass without extraction, the user can run: touch .bytewyrd/precompact-extraction-done then /compact.\"}}'; fi"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'",
            "if": "Bash(git commit*)"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__push_files",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      },
      {
        "matcher": "mcp__plugin_github_github__create_or_update_file",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; user-facing behavior or install method → README.md; product scope, audience, or core model → docs/project-brief.md? Update before pushing if so.'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session ending: (1) /best-practices-extract — if non-obvious learnings were not yet captured. (2) ARCHITECTURE.md — if a component was added/removed, renamed, or data flow changed. (3) CONTRIBUTING.md — if dev workflow, quality gate, or prerequisites changed. (4) README.md — if user-facing behavior or install method changed. (5) docs/project-brief.md — if product scope, audience, or core model changed.'"
          },
          {
            "type": "command",
            "command": "if [ -f .claude-plugin/plugin.json ] && grep -q '\"name\": \"bytewyrd\"' .claude-plugin/plugin.json 2>/dev/null && [ -s \"$HOME/.claude/BEST_PRACTICES.md\" ]; then echo 'Session ending (plugin checkout): ~/.claude/BEST_PRACTICES.md has pending entries — consider running /best-practices-sync to promote vetted entries into sync content.'; fi"
          }
        ]
      }
    ]
  },
  "enabledPlugins": {
    "github@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "bytewyrd@bytewyrd": true
  },
  "extraKnownMarketplaces": {
    "bytewyrd": {
      "source": {
        "source": "github",
        "repo": "bytewyrd/claude-bytewyrd"
      }
    }
  }
}
```

#### Step 2 — Modify `skills/best-practices-extract/SKILL.md`

Two changes:

**Change 2a — Add a final "Mark extraction done" subsection.** Insert this new section between the existing `## Post-Write Check` section and the existing `## When to Run` section:

````markdown
## Mark Extraction Done (Required — Last Step)

After every invocation of this skill, regardless of whether any entries were added, run:

```bash
mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done
```

This writes the sentinel file the `PreCompact` hook uses as its release condition. The sentinel signals "extraction has run in this session" — the next compaction trigger will be allowed through without re-blocking.

The sentinel-write runs on **every normally-completing exit path**:

- After approved entries are written to `docs/BEST_PRACTICES.md`.
- After the user declined all candidates (`none`).
- After the skill exited with "Nothing new to capture this session" because nothing passed triage and filtering.
- After any partial-success path (e.g., one entry approved, one declined).

The only cases where the sentinel is **not** written are: a hard failure of the skill itself (e.g., the disk is full when writing `docs/BEST_PRACTICES.md`), or session termination mid-execution before the final step is reached. In either case, the next compaction will re-block, which is the correct behavior — the user re-runs the skill.

Do not skip this step "because nothing was written." The skill ran; the gate is satisfied; the sentinel records that. Skipping the sentinel leaves the `PreCompact` hook in an unresolved-block state and the user has to bypass manually.
````

**Change 2b — Update the "When to Run" section.** The current section reads:

```markdown
## When to Run

- **Automatically:** `PreCompact` hook fires before conversation compaction (configured in `.claude/settings.json`)
- **Manually:** Invoke this skill at any time, especially before ending a long design/feature session
- **Branch completion:** Natural checkpoint in the `finishing-a-development-branch` workflow
```

Replace it with:

```markdown
## When to Run

- **Automatically and enforced:** The `PreCompact` hook in `.claude/settings.json` blocks compaction until this skill runs. On the first compaction trigger of a session, the hook returns `{"decision": "block"}` and injects a system reminder instructing the agent to invoke `/best-practices-extract`. The skill then runs, the user approves or declines per-candidate, the skill writes the sentinel file at `.bytewyrd/precompact-extraction-done`, and the next compaction trigger is allowed through. The block-and-release pattern makes extraction a true gate rather than a suggestion.
- **Manually:** Invoke this skill at any time, especially before ending a long design/feature session — running it manually also writes the sentinel, so the next automatic compaction passes through cleanly.
- **Branch completion:** Natural checkpoint in the `finishing-a-development-branch` workflow.
- **Bypass:** To compact without extraction (e.g., the session has no learnings worth capturing and the user wants to skip the gate), run `touch .bytewyrd/precompact-extraction-done` then `/compact`. The bypass is documented in the hook's `reason` field, surfaced to the user at the moment the block is encountered.
```

#### Step 3 — Modify `.gitignore` (project root)

Add `.bytewyrd/` to gitignore if not already present. The sentinel file is project-local state, not committed history.

Run the conditional add:

```bash
grep -q '^\.bytewyrd/' .gitignore 2>/dev/null || printf '\n# bytewyrd plugin local state (PreCompact sentinel, etc.)\n.bytewyrd/\n' >> .gitignore
```

If `.gitignore` does not exist yet (greenfield project), create it with the same body:

```bash
test -f .gitignore || printf '# bytewyrd plugin local state (PreCompact sentinel, etc.)\n.bytewyrd/\n' > .gitignore
```

The `.bytewyrd/` directory pattern (trailing slash) excludes the directory and all its contents. The sentinel file (`.bytewyrd/precompact-extraction-done`) is empty (created with `: > file`); it carries no project-meaningful content beyond its presence, so excluding it from version control is safe.

#### Step 4 — (Optional but recommended) Add a project-specific entry to `docs/BEST_PRACTICES.md`

Append the following entry to the `## Project-Specific` section of `docs/BEST_PRACTICES.md` (create the section if it does not exist, using the introductory text from the `best-practices-extract` skill's Write Format section):

```markdown
- **[2026-05-12]** _Project-Specific_: The `PreCompact` hook blocks compaction until `/best-practices-extract` runs; release condition is the sentinel file `.bytewyrd/precompact-extraction-done`, written by the skill's final step. Bypass: `touch .bytewyrd/precompact-extraction-done` then `/compact`.
```

This documents the contract for future agents working on this plugin so they understand the hook's behavior without re-reading this RFC.

#### Step 5 — Verification

Run these checks in order. Each check has an explicit expected output. If any check fails, the issue and likely cause are documented inline.

1. **Settings file is valid JSON:**

   ```bash
   python3 -m json.tool .claude/settings.json > /dev/null && echo ok
   ```

   Expected output: `ok`

   *Failure cause:* JSON-in-JSON escaping error in the shell command string. Re-check that every `\"` in the JSON value is paired and every backslash in the printf argument (e.g., `\\n` becoming literal `\n`) survives the surrounding JSON escape.

2. **`PreCompact` hook contains the block-decision logic:**

   ```bash
   grep -F '.bytewyrd/precompact-extraction-done' .claude/settings.json
   ```

   Expected output (one match — the line in the `PreCompact` hook):

   ```
           "command": "if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf '%s\\n' '{\"continue\":true}'; else mkdir -p .bytewyrd; printf '%s\\n' '{\"decision\":\"block\",\"reason\":\"Compaction blocked: /best-practices-extract has not run this session. Run /best-practices-extract (the skill handles the no-op case and is the expected next action), or bypass with: touch .bytewyrd/precompact-extraction-done then re-run /compact.\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"Compaction is blocked until /best-practices-extract runs in this session. The sentinel file .bytewyrd/precompact-extraction-done does not exist, which means extraction has not yet completed. The expected next action is to invoke /best-practices-extract; the skill itself preserves the per-candidate human-approval prompt, so this gate does not write anything without confirmation. When the skill completes (including the no-op path where nothing passes triage), it creates the sentinel file and the next compaction trigger will be allowed through. To bypass without extraction, the user can run: touch .bytewyrd/precompact-extraction-done then /compact.\"}}'; fi"
   ```

   *Failure cause:* the file was modified manually after Step 1 and the marker string was edited. Re-run Step 1 verbatim.

3. **Skill file contains the sentinel-write instruction:**

   ```bash
   grep -F 'mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done' skills/best-practices-extract/SKILL.md
   ```

   Expected output (one match):

   ```
   mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done
   ```

   *Failure cause:* the new `## Mark Extraction Done` section was added but the bash snippet was reformatted. Re-check that the exact one-liner is present.

4. **Skill file's "When to Run" section reflects the enforced gate:**

   ```bash
   grep -F 'Automatically and enforced:' skills/best-practices-extract/SKILL.md
   ```

   Expected output:

   ```
   - **Automatically and enforced:** The `PreCompact` hook in `.claude/settings.json` blocks compaction until this skill runs. On the first compaction trigger of a session, the hook returns `{"decision": "block"}` and injects a system reminder instructing the agent to invoke `/best-practices-extract`. The skill then runs, the user approves or declines per-candidate, the skill writes the sentinel file at `.bytewyrd/precompact-extraction-done`, and the next compaction trigger is allowed through. The block-and-release pattern makes extraction a true gate rather than a suggestion.
   ```

5. **`.gitignore` excludes the sentinel directory:**

   ```bash
   grep -q '^\.bytewyrd/$' .gitignore && echo ok
   ```

   Expected output: `ok`

   *Failure cause:* the pattern was added without the trailing slash or with a leading wildcard. The exact pattern must be `.bytewyrd/` (directory match).

6. **Smoke test — block path (sentinel absent):**

   Manually delete the sentinel if it exists, then invoke the hook command in isolation to confirm the block JSON is emitted:

   ```bash
   rm -f .bytewyrd/precompact-extraction-done
   sh -c 'if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf "%s\n" "{\"continue\":true}"; else mkdir -p .bytewyrd; printf "%s\n" "{\"decision\":\"block\",\"reason\":\"...truncated for verification...\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"...truncated for verification...\"}}"; fi'
   ```

   Expected output: a single line of JSON starting with `{"decision":"block"` and ending with `}`. The line must parse as JSON:

   ```bash
   sh -c '...same command as above...' | python3 -m json.tool > /dev/null && echo ok
   ```

   Expected: `ok`

7. **Smoke test — release path (sentinel present):**

   Create the sentinel, then invoke the hook command in isolation to confirm the release JSON is emitted and the sentinel is deleted:

   ```bash
   mkdir -p .bytewyrd && : > .bytewyrd/precompact-extraction-done
   sh -c 'if [ -f .bytewyrd/precompact-extraction-done ]; then rm -f .bytewyrd/precompact-extraction-done; printf "%s\n" "{\"continue\":true}"; else mkdir -p .bytewyrd; printf "%s\n" "{\"decision\":\"block\",\"reason\":\"...\",\"hookSpecificOutput\":{\"hookEventName\":\"PreCompact\",\"additionalContext\":\"...\"}}"; fi'
   ```

   Expected output:

   ```
   {"continue":true}
   ```

   And confirm the sentinel is gone:

   ```bash
   test ! -f .bytewyrd/precompact-extraction-done && echo ok
   ```

   Expected: `ok`

8. **Manual end-to-end smoke test (in Claude Code, after the changes land):**

   - Start a new Claude Code session in the plugin's checkout.
   - Have a substantive conversation that produces at least one extractable learning (a design decision, a discovered pitfall, etc.).
   - Run `/compact` manually. Confirm the agent encounters the `decision: "block"` response, surfaces the block reason in its next turn, and proposes running `/best-practices-extract` as the next action (the `additionalContext` reminder is what drives this).
   - Approve the agent's proposal to run `/best-practices-extract`. The skill runs, presents candidates, asks for per-candidate approval, writes approved entries to `docs/BEST_PRACTICES.md`, and writes the sentinel file at `.bytewyrd/precompact-extraction-done`.
   - Run `/compact` again. Confirm compaction proceeds normally this time; verify the sentinel was deleted by the hook on its way through.
   - Start a fresh session. Run `/compact` immediately (no learnings, empty session). Confirm the hook blocks, the agent runs `/best-practices-extract`, the skill reports "Nothing new to capture this session," and the sentinel is still written (verifying the no-op path also satisfies the gate).
   - Test the bypass: in a new session, run `touch .bytewyrd/precompact-extraction-done` then `/compact`. Confirm compaction proceeds without running the skill (the user-initiated bypass works).

   If any of these steps fails, the likely causes (in order) are:
   - **Claude Code version too old.** The block decision was added in v2.1.105 (2026-04-13). Run `claude --version` and confirm. If older, the block is silently ignored and only the `additionalContext` reminder fires (which is still an improvement over the current advisory `echo`, but does not enforce the gate).
   - **JSON-in-JSON escaping error in the hook command.** The hook outputs invalid JSON, Claude Code logs a parse error in `--verbose` mode, and the block is silently dropped. Inspect the actual stdout of the hook by adding `tee /tmp/hook-out.log` between the `printf` and the end of the pipe.
   - **Sentinel-write step in the skill was skipped on an exit path.** Re-check Step 2's "every successful exit path" wording — including the "Nothing new to capture this session" path — and grep for the sentinel-write line in the skill file.
   - **`.bytewyrd/` was committed to the repo.** Step 3 should have excluded it; if a sentinel file leaks into a commit, future fresh clones will see a stale sentinel and the first compaction skips the gate. Run `git ls-files .bytewyrd/` to confirm no tracked files.

## Risks and open questions

- **Risk: Claude Code version requirement is implicit.** The block-decision behavior requires Claude Code v2.1.105 or later. The plugin's `plugin.json` does not currently declare a Claude Code version constraint. **Mitigation:** add a one-line note to the plugin's README (or to `CLAUDE.md`'s "Workflow" section) stating "Requires Claude Code v2.1.105+ for the PreCompact extraction gate; earlier versions silently fall back to advisory-only behavior, which is no worse than the pre-RFC state." Adding a hard `engines.claude_code` field in `plugin.json` is a separate decision and out of scope here — the gate's downside-of-too-old-a-Claude-Code is silent fallback to the old behavior, not a broken plugin.

- **Risk: agent ignores the system reminder even with the block in place.** The block holds compaction, but the live agent has to actually invoke `/best-practices-extract` in response to the `additionalContext` reminder. If the agent's pattern is "user asked for compaction, the system says blocked, I tell the user it's blocked and ask what they want next," the agent may not autonomously invoke the skill — the user has to type `/best-practices-extract` themselves. That is still strictly better than the current state (no block, agent ignores the reminder, compaction proceeds), but it falls short of "extraction runs automatically without the user typing the skill name." **Mitigation:** the `additionalContext` text explicitly names the expected next action ("The expected next action is to invoke /best-practices-extract"). Future iterations could refine the wording based on observed agent behavior — for instance, if the agent consistently waits for user confirmation rather than acting on the reminder, the text could be revised to a more decisive framing. Consensus-review reviewers should evaluate the reminder wording specifically for "does this read like a clear next-action signal to a live agent."

- **Risk: prompt-injection-defense triggering.** Anthropic's docs explicitly warn that `additionalContext` text framed as out-of-band system commands can trigger Claude's prompt-injection defenses, causing Claude to surface the text to the user as suspicious content rather than acting on it. **Mitigation:** the reminder is phrased as factual statements ("Compaction is blocked until ... runs"; "The sentinel file ... does not exist"; "The expected next action is...") rather than direct imperatives ("YOU MUST run /best-practices-extract"). This is the framing Anthropic's docs explicitly recommend for `additionalContext`. The consensus review should specifically verify the wording does not read as out-of-band system commands.

- **Risk: false-positive block on session restart in the same project.** If the user closes Claude Code mid-session (after extraction ran and the sentinel was written) and reopens later in the same project, the sentinel persists on disk. A subsequent `/compact` in the new session sees the sentinel and lets compaction through without re-running extraction — but the new session may have its own new learnings worth capturing. **Mitigation:** The `SessionStart` sentinel-delete hook (added in Step 1) eliminates this failure mode. On every new session start, `rm -f "${CLAUDE_PROJECT_DIR:-$PWD}/.bytewyrd/precompact-extraction-done"` runs unconditionally, so no stale sentinel from a prior session can carry forward into the new session. The first compaction in any new session will always block and enforce extraction.

- **Open question: should the `Stop` hook also write the sentinel?** The `Stop` hook fires when Claude finishes responding (i.e., at the end of every turn). It currently prints a session-end checklist that includes "run /best-practices-extract if non-obvious learnings were not yet captured." If `Stop` is interpreted as "session ending," and the user did run `/best-practices-extract` during the session, the sentinel is already written; no change needed. If the user did *not* run it, the sentinel is absent — but the next compaction will then block, which is the desired behavior. So `Stop` should **not** write the sentinel; doing so would let users skip the gate by simply ending the session before compaction. **Resolution within this RFC:** do not modify the `Stop` hook. The current advisory reminder there is the right shape for end-of-session; the `PreCompact` gate is what enforces the extraction.

- **Open question: does the gate need to coordinate with `/best-practices-record`?** `/best-practices-record` writes to `~/.claude/BEST_PRACTICES.md` (the user-global pool) and is a separate skill from `/best-practices-extract`. The braindump and this RFC are scoped to the per-session extraction step; promotion to the global pool is an orthogonal cross-project decision per the existing skill design. **Resolution within this RFC:** out of scope. The gate enforces project-local extraction only. If a future RFC argues for gating compaction on global-pool decisions, that is its own design conversation.

- **Open question: how does this interact with `/clear`?** `/clear` resets the conversation but does not delete project-local files. After `/clear`, the sentinel may still be present from a pre-`/clear` extraction. The next compaction in the fresh-cleared session would then pass through without re-running extraction. **Resolution within this RFC:** the `SessionStart` sentinel-delete hook (Step 1) addresses this: when the user opens a new session after `/clear`, the `SessionStart` hook removes the stale sentinel unconditionally, restoring the gate to clean state. The first compaction in that new session will block and enforce extraction.

- **Open question: should there be a global `~/.claude/settings.json` version of this hook for projects without the bytewyrd plugin?** The hook lives in the plugin's project-level `.claude/settings.json` because it expects `.bytewyrd/` as the sentinel directory and depends on the bytewyrd plugin's `/best-practices-extract` skill being available. A global version would have to choose a global sentinel path (e.g., `~/.claude-precompact-done`) and a global extraction skill — which exists today (`/best-practices-extract` is plugin-provided when the plugin is enabled globally). **Resolution within this RFC:** out of scope. This RFC ships the gate inside the bytewyrd plugin's own checkout, where the contract is fully under the plugin's control. A future RFC can extend the gate to a global form if there is demand.

## Relationship to other RFCs

- **`2026-05-09-best-practices-content-and-tooling`** (status presumed Done per the file's age — it predates the plugin's `Stop` hook reminder text that already references `/best-practices-extract`). Established the `docs/BEST_PRACTICES.md` destination, the per-session extraction flow, and the relationship to `~/.claude/BEST_PRACTICES.md` (global pool). This RFC builds directly on that foundation — the gate is meaningful only because the extraction skill behind it is already designed and dogfooded.
- **`2026-05-10-best-practice-extraction-principles`** — established the principles the extraction skill applies (triage, lift, audience portability). This RFC does not change those principles; it only changes the trigger from advisory to enforced. The per-candidate human-approval prompt that those principles depend on is explicitly preserved.
- **`2026-05-12-unify-best-practices-destinations`** (status: Draft) — proposes unifying where `/best-practices-extract` and `/best-practices-record` write to. If that RFC lands, the sentinel-write line in this RFC's Step 2 stays unchanged; the destination of approved entries is independent of the gate. The two RFCs are orthogonal and can land in either order.
- **`2026-05-12-drop-dates-from-best-practices`** (status: Draft) — proposes changing the date-prefix format in best-practices entries. Same orthogonality: this RFC writes `[YYYY-MM-DD]` in its one optional project-specific entry (Step 4), which would be updated to whatever format that RFC settles on. No structural conflict.
- **Future RFC: global `PreCompact` extraction gate (not yet drafted).** The "Open question" above about a global version of this hook is a candidate for a follow-up RFC if real-world use suggests it. The mechanism is identical (block + `additionalContext` + sentinel); only the file paths and the skill name change. The current RFC's mechanism is reusable as-is.
