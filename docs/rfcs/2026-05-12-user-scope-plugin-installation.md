---
rfc: "2026-05-12-user-scope-plugin-installation"
title: "User-Scope Plugin Installation with Requirement-Check Hooks"
author: "Rodrigo Kochenburger"
status: "Approved"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Promote the `bytewyrd` plugin to a **user-scope-first** installation model and add a plugin-provided `SessionStart` hook that runs a single requirement-check script at the start of every session. The script enumerates what the active project actually needs (companion plugins enabled, MCP servers configured, expected tooling on `PATH`, `.claude/settings.json` artefacts) and emits one combined diagnostic to the user — silent when everything is satisfied, a warning bundle when soft requirements are missing, and a hard `exit 2` failure only for the small set of conditions that genuinely make the plugin unusable (the manifest itself can't load, or the GitHub MCP is referenced in `settings.json` but isn't enabled). Skills whose useful behaviour depends on a *specific* missing requirement query the same check at invocation time and either self-skip with a one-line explanation or warn and continue. This replaces the current "install in every project" friction with one global install plus per-session, per-project verification at the moment a requirement actually matters.

## Should we do this?

**Yes.** Today, every new repository that wants the Bytewyrd workflow runs `/sync` to write `.claude/settings.json` with `bytewyrd@bytewyrd: true` in `enabledPlugins`, which forces every team member to install the plugin once per project — an action they can only complete *after* the first session in that project surfaces the install prompt, which is exactly when the friction is most visible. The plugin's own published documentation in `docs/guide/installation.md` already tells users to install with `claude plugin install bytewyrd@bytewyrd` (no scope flag — Claude Code's default is `--scope user`, per the upstream plugins-reference page), so the de-facto recommended install path is already user-scope. What is missing is the *correctness layer*: today the plugin assumes its companion plugins (`github@claude-plugins-official`, `context7@claude-plugins-official`, `code-review@claude-plugins-official`), Exa MCP, and Firefox MCP are present, and it fails opaquely when they aren't (the `mcp__plugin_github_github__*` tool calls 404, the `mcp__exa__*` calls return "tool not found", and the skills that depend on them either invent fallback paths or silently degrade). Moving to user-scope-first is correct only if there's a deterministic, per-session check that surfaces the gap *before* a skill tries to use a tool that isn't there. This RFC builds that check.

The cost is one new script (`scripts/check-requirements.sh`), one `hooks/hooks.json` entry, three small skill edits (best-practices-extract, refactor, rfc-implement — the three skills with non-trivial external-tool dependencies), and an `INSTALL.md` update; the payoff is removing per-project plugin installation friction across the team while preventing the "tool not found" failures that the friction was implicitly guarding against. Net: smaller setup tax, clearer failure mode, no loss of correctness.

## Current state

### How the plugin is installed and enabled today

The plugin currently ships with `.claude-plugin/plugin.json` declaring its identity (`name: bytewyrd`, `version: 0.1.0`) and `.claude-plugin/marketplace.json` declaring it as a single-plugin marketplace pointed at `./`. The marketplace is registered on a user's machine via `claude plugin marketplace add bytewyrd/claude-bytewyrd` (as documented in `README.md` and `docs/guide/installation.md`), after which the plugin is installed with `claude plugin install bytewyrd@bytewyrd`.

Per the Claude Code plugins-reference page (`https://code.claude.com/docs/en/plugins-reference#plugin-installation-scopes`), the `--scope` flag has four values and `user` is the default. The four scopes write to four settings files:

| Scope | Settings file | Use case |
|-------|---------------|----------|
| `user` (default) | `~/.claude/settings.json` | Personal plugins across all projects |
| `project` | `.claude/settings.json` | Team plugins shared via version control |
| `local` | `.claude/settings.local.json` | Project-specific, gitignored |
| `managed` | Managed settings | Organisation policy |

A user-scope install adds `"bytewyrd@bytewyrd": true` to `~/.claude/settings.json`'s `enabledPlugins` block and makes the plugin available in every project the user opens. This is *already supported* by Claude Code and *already* what the existing install commands do by default — the change is not "make user-scope work," it's "make user-scope the documented and supported posture, stop nudging users toward project-scope installs, and add the per-project safety net that justifies that posture."

What this RFC does *not* change about installation: `claude plugin marketplace add`, `claude plugin install`, the marketplace manifest, and the plugin manifest stay as they are.

### What `/sync` writes today and why it conflicts with user-scope-first

`skills/sync/SKILL.md` (around line 988) writes `.claude/settings.json` with:

```json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": true,
    "github@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "code-review@claude-plugins-official": true
  }
}
```

The comment in the sync skill says this is "Always include (triggers an install prompt for team members who don't have the plugin yet)" — an explicit design choice to make the project's `settings.json` carry plugin enablement so a fresh clone surfaces the install prompt. The companion plugins (`github`, `context7`, `code-review`) are conditionally included ("Include only if installed — an uninstalled `claude-plugins-official` plugin causes Claude Code to error on startup"). This is the friction the RFC removes: a user who has already installed `bytewyrd@bytewyrd` at user scope still gets the per-project install prompt because the project's `settings.json` re-asserts the enablement; a user who hasn't gets a per-project prompt every time they clone a new repo.

### What hooks the plugin ships today

`hooks/hooks.json` does not exist. Hooks today live in `.claude/settings.json` (the *project-scoped* hooks that `/sync` writes), not at plugin scope. Per `https://code.claude.com/docs/en/plugins-reference#hooks` and the upstream hooks page, a plugin can ship hooks via `hooks/hooks.json` at the plugin root, and these fire in every project where the plugin is enabled — which is exactly the surface this RFC needs to put a per-project requirement check on.

The current `hooks` section in `skills/sync/SKILL.md` (project-scoped) ships `PreCompact`, `PostToolUse(Bash, git commit*)`, `Stop`, and `PreToolUse(Bash, git push*)`. There is no `SessionStart` hook in the project-scoped template today. The `bootstrap-content-version` comment in the sync skill is a documentation marker in the SKILL.md source, not an active hook. The requirement-check this RFC adds is a plugin-shipped hook; it does not modify the project-scoped hooks `/sync` writes.

### What requirements the plugin actually has

Reading the existing skills, agents, and `CLAUDE.md` content:

| Requirement | Used by | Failure mode today when missing |
|-------------|---------|--------------------------------|
| `github@claude-plugins-official` plugin enabled | `code-review`, `rfc-new`, `rfc-implement` (PR-related operations); `CLAUDE.md` instructs "Prefer the GitHub MCP" | `mcp__plugin_github_github__*` tools return "tool not found"; skills fall back to `gh` CLI |
| `context7@claude-plugins-official` plugin enabled | All skills/agents that touch external libraries (per `CLAUDE.md` "Context7 — library documentation … Mandatory before writing code that uses an external library") | `mcp__plugin_context7_context7__*` tools fail; agent guesses from training knowledge |
| `code-review@claude-plugins-official` plugin enabled | `/review` invocation entrypoint (skill from companion plugin) | The `/review` slash command is not registered |
| Exa MCP server configured (`mcp__exa__*` tool family) | `CLAUDE.md` rule "Use Exa as the default for any web lookup"; `rfc-architect` uses for evidence-based research | `mcp__exa__web_search_exa` and `mcp__exa__crawling_exa` return "tool not found" |
| Firefox MCP server configured (`mcp__firefox-devtools__*`) | `CLAUDE.md` "Required for any frontend or UI change before reporting work done" | All `mcp__firefox-devtools__*` tools 404; visual verification step silently skipped |
| `gh` CLI on `PATH` (logged in) | `/sync` Step 1 (`gh repo view --json name,description`); fallback for GitHub operations when MCP missing | `gh repo view` exits non-zero; sync proceeds without GitHub metadata |
| `git` CLI on `PATH` | Every workflow step; `/sync` Step 1 (`git rev-parse --show-toplevel`) | The plugin cannot operate at all — this is a hard failure |
| Project's `.claude/settings.json` references plugins that aren't enabled | Project written by `/sync` before companion plugins installed | Claude Code errors on startup (per the existing `/sync` comment) |

These are the requirements the check needs to surface. The check does not need to verify the project's *code* (no linter, no typecheck, no test run); it only verifies what the *plugin itself* needs to function correctly in this project.

### How requirements are detected today

Most of the plumbing is already in `skills/sync/SKILL.md`. The relevant prior art:

- `~/.claude/plugins/installed_plugins.json` is the file `/sync` reads (around line 59) to detect installed plugins. The structure has a `plugins` object whose keys are plugin identifiers (`github@claude-plugins-official`, etc.) and whose values are arrays of scope-keyed installation records — confirmed against the Claude Code issue tracker (anthropics/claude-code#29996, the issue tracking the buggy interaction between project-scope and user-scope installs that triggered the original investigation into this file).
- Two settings files declare *enabled* state: `~/.claude/settings.json` for user-scope, and the project's `.claude/settings.json` for project-scope. Both have an `enabledPlugins: { "<plugin@marketplace>": true|false }` block; per the upstream settings docs (`https://docs.claude.com/en/docs/claude-code/settings#enabledPlugins`), project settings take precedence over user settings.
- MCP servers are declared in `~/.claude.json` (user-scope), `.mcp.json` (project-scope, shared), or `.claude/settings.local.json` (project-scope, gitignored). The check only needs to know whether the relevant `mcp__*` tools are *available* in the current session, not where they came from — but the diagnostic must be able to *point the user at* the right file to fix it.

### Why the existing PreCompact/Stop/PostToolUse hook style isn't enough

The project-scoped hooks in `skills/sync/SKILL.md` today use simple `echo` commands (e.g., the `PreCompact` hook reminds the user to run `/best-practices-extract`; the `Stop` hook reminds about documentation updates). That style works for single-message reminders but doesn't scale to the requirement-check matrix: you want one diagnostic combining results from ~6 different probes, with a structured exit policy (silent / warn / fail). A separate hook script lets the logic stay readable, testable (`bash scripts/check-requirements.sh` from the command line in a project gives the same output), and version-controllable as a single file. The hook entry in `hooks/hooks.json` is then a one-liner that invokes the script.

## Analysis / Options

The design has four coupled decisions: installation scope posture, hook surface for the check, requirement classification policy (warning vs hard failure), and per-skill behaviour when a requirement is missing.

### Decision 1 — Installation scope posture

**Option A — User-scope-first, project's `.claude/settings.json` no longer asserts `bytewyrd@bytewyrd: true`. Recommended.**
The plugin is installed once per user via `claude plugin install bytewyrd@bytewyrd` (defaults to `--scope user`); `~/.claude/settings.json` carries the `enabledPlugins` entry; the project's `.claude/settings.json` no longer references the plugin at all. `/sync` is updated to omit the `bytewyrd@bytewyrd` line from the `enabledPlugins` block it writes (and to *remove* the line from any existing `.claude/settings.json` it finds, so re-running `/sync` on a previously-synced project cleans up the legacy entry). Companion plugins are still declared in the project's `.claude/settings.json` (because they're a shared team contract — different projects can legitimately enable different companion plugins, e.g. a frontend project might enable a UI-only plugin). The requirement-check hook then runs at `SessionStart` from the plugin itself and verifies that everything is present *for this project*.

**Option B — Dual-scope: project's `.claude/settings.json` keeps `bytewyrd@bytewyrd: true`, but the install prompt is suppressed if the user already has it at user scope.**
Rejected. Claude Code does not currently distinguish "already installed at user scope" from "not installed" when resolving project-scoped `enabledPlugins` entries (anthropics/claude-code#38084 documents `/plugin enable` ignoring user-scope installs; #29996 documents the cache vs. registry confusion). A dual-scope posture inherits these bugs. It also keeps the friction this RFC is meant to eliminate.

**Option C — Project-scope-only (status quo): plugin must be installed in every project.**
Rejected. This is the friction the RFC is meant to remove.

**Option D — User-scope-first AND project's `.claude/settings.json` still lists `bytewyrd@bytewyrd` for projects that explicitly want to require it (escape hatch).**
Rejected as the *default* but kept as an *option for project maintainers who explicitly want the team-wide enforcement*. Per Claude Code's settings precedence rules ("project settings take precedence over user settings"), a project that writes `"bytewyrd@bytewyrd": true` in its `.claude/settings.json` forces the plugin to be enabled in that project regardless of user-scope state — which is a legitimate use case for teams that want to mandate the plugin. The RFC's recommendation is that `/sync` does *not* write this by default; teams that want it can add it themselves. This is documented in the new `docs/guide/installation.md` section, not enforced in code.

**Recommendation: Option A**, with Option D documented as an opt-in for teams.

### Decision 2 — Hook surface for the requirement check

**Option A — Plugin-shipped `hooks/hooks.json` with a single `SessionStart` hook calling `scripts/check-requirements.sh`. Recommended.**
`SessionStart` fires once per session (including on resume — verified against the upstream hooks page: "Runs when Claude Code starts a new session or resumes an existing session"). A single hook script keeps the logic in one place. The script reads project state, queries `~/.claude/plugins/installed_plugins.json` and the relevant settings files, and emits one combined diagnostic.

**Option B — `UserPromptSubmit` hook re-checks before every user message.**
Rejected. The check needs to fire once per session, not per turn. `UserPromptSubmit` would add latency to every prompt and is the wrong granularity — once the user has been told their MCP server is missing, repeating the warning on every prompt is noise.

**Option C — `PreToolUse` hook checks only when a skill is about to use a specific tool.**
Rejected. The plugin doesn't have a clean way to know *which* tool a skill is about to use before the user invokes it — the check needs to surface the gap *before* the user invokes the broken skill, not on the way to the broken tool. Skills also handle their own per-invocation guard separately (see Decision 4) — that's where in-skill probing lives, not in a hook.

**Option D — `Setup` hook (one-time on plugin install).**
Rejected. `Setup` fires only on `--init-only`, `--init`, or `--maintenance` print-mode invocation (per the upstream hooks page); it does not fire on normal session start. The plugin needs the check on *every* session in *every* project, because a project that was correct yesterday can be broken today (companion plugin uninstalled, MCP server config edited, `gh` removed from `PATH`). `Setup` runs too rarely.

**Recommendation: Option A.**

### Decision 3 — Requirement classification (warning vs hard failure)

**Option A — Three tiers: silent (everything ok), warning (most things missing but plugin can still operate partially), hard failure only for two conditions: (1) the project's `.claude/settings.json` references a `claude-plugins-official` plugin that isn't installed (because Claude Code itself errors on startup in that state, per the existing comment in `skills/sync/SKILL.md`), (2) the plugin manifest can't be located. Recommended.**

Default to warnings. The plugin should never block a user from working in a project just because Firefox MCP isn't configured — they may not be doing UI work. The two hard-failure cases are conditions under which Claude Code itself misbehaves (case 1) or the plugin's own files are inaccessible (case 2); warning vs failing isn't a judgment call in those cases.

**Specific classification:**

| Requirement | Tier | Why |
|-------------|------|-----|
| `git` on `PATH` | Hard fail (exit 2) | Plugin cannot do anything without git |
| Project's `.claude/settings.json` references a `claude-plugins-official` plugin that isn't installed in `installed_plugins.json` | Hard fail (exit 2) | Claude Code itself errors on startup — the hook reports the actionable fix before the error becomes visible to the user. Note: if Claude Code validates `enabledPlugins` before firing `SessionStart` hooks, the hook's hard-failure message may be superseded by Claude Code's own error — which is still actionable. The hard-failure classification remains correct; the message just may not be the first thing the user sees. |
| Plugin's own `${CLAUDE_PLUGIN_ROOT}` can't be located (script invoked outside plugin context) | Hard fail (exit 2) | Script's own dependencies are broken |
| `github@claude-plugins-official` not enabled | Warning | Skills fall back to `gh` CLI |
| `context7@claude-plugins-official` not enabled | Warning | Agents fall back to Exa, then training knowledge |
| `code-review@claude-plugins-official` not enabled | Warning | `/review` slash command unavailable, but other workflows continue |
| Exa MCP not configured (no `mcp__exa__*` tool family) | Warning | Skills note the gap but continue with WebFetch fallback |
| Firefox MCP not configured | Warning | UI verification step skipped; non-UI work proceeds |
| `gh` CLI not installed or not logged in | Warning | Only used by `/sync` Step 1 metadata pre-population; soft dependency |

**Option B — Two tiers: silent (everything ok) vs hard failure for everything missing.**
Rejected. Too aggressive. A user doing Rust backend work shouldn't have a session blocked because they haven't configured Firefox MCP. The plugin's value proposition is "useful guardrails that warn when they're degraded" — not "all-or-nothing."

**Option C — Single warning bundle, no hard failures.**
Rejected for the two known cases above (broken `claude-plugins-official` references; missing git). These are conditions where letting the session continue produces *worse* errors downstream than failing fast with a clear message.

**Recommendation: Option A.**

### Decision 4 — Per-skill behaviour when a requirement is missing

**Option A — Skills that depend on a specific missing requirement self-check at invocation time and self-skip with a one-line explanation when the dependency is missing. Recommended.**

The `SessionStart` hook surfaces the missing requirement *once*, at the start of the session. When the user then invokes (say) `/refactor` — which expects to be able to read code-review output — the skill should not silently swallow the gap; it should print a short line ("`code-review@claude-plugins-official` is not enabled in this session — `/refactor` will run without code-review pre-pass") and proceed with the parts it can do.

For skills whose *entire* purpose depends on a missing requirement (e.g., a hypothetical `/firefox-test` skill that exclusively drives Firefox MCP), the skill should print a one-line skip message and exit cleanly rather than trying to execute. Today the only skill that comes close to this category is the visual verification flow inside `CLAUDE.md`, which is a guideline rather than a slash command — so the in-skill probing is concentrated in the three skills that already make external tool calls: `best-practices-extract` (uses `gh` for PR context optionally), `refactor` (uses code-review optionally), and `rfc-implement` (uses GitHub MCP for PR creation). These three get small additions.

**Option B — No per-skill probing; rely entirely on the SessionStart message.**
Rejected. The SessionStart message scrolls off-screen quickly; users invoke skills hours into a session and don't remember which dependencies were missing. Per-skill probing is the second line of defence and keeps the failure-attribution local.

**Option C — Per-skill probing for *every* skill, even ones that don't directly use external tools.**
Rejected. Most skills don't need it. Adding a defensive probe to every skill is busywork that adds maintenance burden without benefit. The three identified skills are the ones with real external dependencies; the rest don't need the change.

**Recommendation: Option A.** Add small probes to the three skills that have real external-tool dependencies. Other skills rely on the SessionStart hook.

## Drawbacks

- **The SessionStart hook adds startup latency.** The check script reads `~/.claude/plugins/installed_plugins.json`, two settings files, and probes `PATH` for `git` and `gh`. On a warm filesystem this is sub-50ms; on a cold network filesystem (e.g., a remote-mounted home directory) it could be a noticeable fraction of a second. **Mitigation:** the script does no network calls; everything is local file reads and `command -v` PATH probes. Worst-case observed startup latency on a slow disk should still be under 200ms. If real-world use shows the latency is intolerable, the script can cache its result in `${CLAUDE_PLUGIN_DATA}/requirement-check.cache` keyed by the modification times of the inputs it reads — out of scope for this RFC, but the cache directory is documented as a future extension point.

- **The hook fires on every session even when nothing has changed.** Re-warning a user about the same missing Firefox MCP every session is repetitive. **Mitigation:** the warning text includes a one-line "to silence this warning, install Firefox MCP via `claude plugin install firefox-devtools@…` OR add `BYTEWYRD_SKIP_WARN=firefox-devtools` to your shell env" — i.e., the script honours a comma-separated `BYTEWYRD_SKIP_WARN` env var that lists requirement IDs to omit from the warning bundle. This is opt-in suppression, not silent default-off, so users still see the warning until they explicitly acknowledge it. Hard failures (Decision 3) are *not* suppressible by this mechanism.

- **`CLAUDE_PLUGIN_ROOT` is not set in `SessionStart` events in Claude Code as of the most recently confirmed bug report (anthropics/affaan-m everything-claude-code#256, reported 2026-02-20; fix released in `everything-claude-code` v1.8.0 via a fallback path resolver).** A plugin-shipped `SessionStart` hook cannot reliably reference `${CLAUDE_PLUGIN_ROOT}/scripts/check-requirements.sh` directly. **Mitigation:** the hook's command uses a portable fallback resolver written inline in `hooks/hooks.json` that locates the script via the well-known Claude Code plugin cache layout. The fallback (documented inline below in the implementation spec) tries `${CLAUDE_PLUGIN_ROOT}` first, then `~/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/check-requirements.sh`, then `~/.claude/plugins/cache/*/bytewyrd/scripts/check-requirements.sh` (glob). The Claude Code engineering team has indicated they intend to set `CLAUDE_PLUGIN_ROOT` for `SessionStart` in a future release; when that happens the fallback collapses to a no-op. The fallback is purely defensive and has no functional impact when `${CLAUDE_PLUGIN_ROOT}` is set correctly.

- **The hook output is shown in the user's terminal as a "SessionStart says:" prefix, which can be visually noisy.** Per the Claude Code hooks docs, exit-0 stdout from a `SessionStart` hook is *both* shown to the user and added to Claude's context window via `additionalContext`. The latter consumes context tokens. **Mitigation:** the script uses the JSON-output form of hook responses (per the upstream `https://docs.claude.com/en/docs/claude-code/hooks` page, fields `continue`, `suppressOutput`, `systemMessage`, and `hookSpecificOutput.additionalContext`) to (1) keep the user-visible message brief and structured, and (2) avoid injecting the full diagnostic into Claude's context — only a one-line summary goes into `additionalContext`. When everything is satisfied, the script exits 0 with no output (silent path).

- **The hook tightly couples the plugin to the specific identifiers of its companion plugins.** If `claude-plugins-official` renames `github@claude-plugins-official` to (say) `github-mcp@claude-plugins-official`, the check will spuriously warn. **Mitigation:** the script's list of required-plugin identifiers is defined at the top of the script as a single bash array, making renames a one-line change. The plugin identifiers are also documented in `skills/sync/SKILL.md` (already, around line 65) and the RFC marks both files as the places to update on a companion-plugin rename. The risk of silent miss is low because Claude Code's `installed_plugins.json` records the canonical identifier; a rename would also break the existing `/sync` install-detection step, so the failure mode would be discovered immediately.

- **Removing `bytewyrd@bytewyrd: true` from the project's `.claude/settings.json` means new team members on a fresh clone no longer get an install prompt.** This is the friction being removed, so it is by definition the intended behaviour — but it does shift the discoverability problem from "annoying repeated prompt" to "new contributor has no signal that the plugin exists at all." **Mitigation:** `/sync` is updated to *also* write a short note into `CONTRIBUTING.md` (under the "Development Setup" section) telling new contributors that the project uses the Bytewyrd plugin and pointing at the install command. The note is one line plus a fenced code block, idempotent on re-runs.

- **The SessionStart hook output is opaque to users who can't read bash.** A user staring at "GitHub MCP not enabled" with no `gh plugin install` command to copy is unhelped. **Mitigation:** every warning line in the script's output includes the *exact* command the user can run to fix it. The warning bundle is structured so a user can copy each fix command directly from the terminal output. Examples:
  - `[warn] github@claude-plugins-official not enabled. Fix: claude plugin install github@claude-plugins-official`
  - `[warn] Exa MCP server not configured. Fix: add an entry under "mcpServers" to ~/.claude.json or .mcp.json (see https://docs.exa.ai/mcp).`
  - `[fail] .claude/settings.json references "code-review@claude-plugins-official" but it is not installed. Fix: claude plugin install code-review@claude-plugins-official  OR remove the entry from .claude/settings.json's enabledPlugins block.`

- **The fallback path resolver in `hooks/hooks.json` couples to Claude Code's internal cache layout.** If Anthropic changes the layout of `~/.claude/plugins/cache/`, the fallback breaks. **Mitigation:** the fallback is purely a workaround for the open `CLAUDE_PLUGIN_ROOT`-not-set-on-`SessionStart` bug; when that bug is fixed upstream, the fallback becomes dead code (it's only reached when the env var is unset). The fallback's logic is documented inline in `hooks/hooks.json` with a comment pointing to the upstream bug. A future RFC can remove the fallback once Claude Code releases a version with the env var set; tracked as an open question below, not a blocker.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `hooks/hooks.json` | Plugin-shipped hooks. Single `SessionStart` entry invoking the requirement-check script via the env-var fallback resolver |
| Create | `scripts/check-requirements.sh` | Bash script that probes requirements, classifies results by tier, and emits the JSON-form hook response. Executable (`chmod +x`) |
| Modify | `.claude-plugin/plugin.json` | Add the `hooks` field pointing at `hooks/hooks.json` (per the upstream manifest schema; without this entry Claude Code does not auto-discover plugin-shipped hooks in all versions — explicit registration is the safest path) |
| Modify | `skills/sync/SKILL.md` | (1) Remove `bytewyrd@bytewyrd: true` from the example `enabledPlugins` block written to `.claude/settings.json` (around line 988). (2) Add a step that removes any pre-existing `bytewyrd@bytewyrd` entry from a project's `.claude/settings.json` when sync re-runs (cleanup of legacy entries). (3) Add a new step that writes/updates the "Development Setup" section of `docs/CONTRIBUTING.md` (or `CONTRIBUTING.md` at repo root) with the plugin-install hint. (4) Update the `enabledPlugins` Step 5 documentation comment to reflect the new posture |
| Modify | `skills/best-practices-extract/SKILL.md` | Add a one-paragraph "Requirement check" subsection near the top: probe for `gh` CLI before invoking it; print a one-line skip message if absent; continue without GitHub PR context |
| Modify | `skills/refactor/SKILL.md` | Add a similar one-paragraph subsection: probe for `code-review@claude-plugins-official` enabled before invoking the `/review` step; print a skip message and continue without the pre-pass if absent |
| Modify | `skills/rfc-implement/SKILL.md` | Add a similar subsection: probe for `github@claude-plugins-official` enabled before invoking GitHub MCP for PR creation; fall back to `gh` CLI if missing and print which path is being taken |
| Create | `docs/guide/installation.md` | Create the installation guide (the file does not currently exist): lead with `claude plugin install bytewyrd@bytewyrd` (user-scope by default); add a "What the plugin checks at session start" subsection describing the diagnostic; add a "Team-wide enforcement" subsection covering Decision 1's Option D escape hatch |
| Modify | `CLAUDE.md` (plugin root) | Add a one-paragraph "Requirement-check hook" subsection under the existing "Workflow" section, explaining what the hook does and how to interpret its output |
| Modify | `.claude-plugin/CLAUDE.md` | Mirror the same one-paragraph subsection (plugin-developer guidance loaded when developing in this checkout) |

No changes to `agents/`. No changes to `.mcp.json`. No changes to the marketplace manifest. No new skills.

### Steps

#### Step 1 — Create `scripts/check-requirements.sh`

Create the file with this exact content (executable, mode 0755):

```bash
#!/usr/bin/env bash
# Bytewyrd plugin: per-session requirement check.
# Probes installed plugins, MCP servers, and tool availability.
# Emits a JSON hook response per
# https://docs.claude.com/en/docs/claude-code/hooks#hook-output

set -u

# --- Configuration ----------------------------------------------------------

# Required companion plugins (enable-state probed in user + project settings).
REQUIRED_PLUGINS=(
  "github@claude-plugins-official"
  "context7@claude-plugins-official"
  "code-review@claude-plugins-official"
)

# Required MCP tool prefixes. Presence is inferred from settings files that
# declare permissions for these tools (we cannot probe the live tool list from
# inside a hook). If any "allow" entry under any settings file matches one of
# these prefixes, the MCP server is considered configured.
REQUIRED_MCP_PREFIXES=(
  "mcp__exa__"
  "mcp__firefox-devtools__"
)

# Comma-separated list of requirement IDs to skip from warning output, read
# from the environment. Hard failures cannot be skipped.
BYTEWYRD_SKIP_WARN="${BYTEWYRD_SKIP_WARN:-}"

# --- Helpers ----------------------------------------------------------------

# emit_json <continue:bool> <suppressOutput:bool> <systemMessage:string> <additionalContext:string>
emit_json() {
  local cont="$1" suppress="$2" sys_msg="$3" ctx="$4"
  # Escape backslashes and double-quotes for JSON-safe embedding.
  sys_msg="${sys_msg//\\/\\\\}"; sys_msg="${sys_msg//\"/\\\"}"; sys_msg="${sys_msg//$'\n'/\\n}"
  ctx="${ctx//\\/\\\\}"; ctx="${ctx//\"/\\\"}"; ctx="${ctx//$'\n'/\\n}"
  printf '{"continue":%s,"suppressOutput":%s,"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$cont" "$suppress" "$sys_msg" "$ctx"
}

# is_skipped <requirement_id>: returns 0 if the requirement ID is in the
# BYTEWYRD_SKIP_WARN comma-separated list.
is_skipped() {
  local id="$1"
  case ",${BYTEWYRD_SKIP_WARN}," in
    *",${id},"*) return 0 ;;
    *) return 1 ;;
  esac
}

# plugin_enabled <plugin@marketplace>: returns 0 if enabled in either user or
# project settings, 1 otherwise. Project settings take precedence.
plugin_enabled() {
  local id="$1"
  local user_settings="$HOME/.claude/settings.json"
  local proj_settings="$CLAUDE_PROJECT_DIR/.claude/settings.json"
  # We use grep rather than jq because jq is not guaranteed on PATH; the
  # check is a simple string match against the canonical JSON encoding.
  # Project setting (precedence): explicit true/false.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$proj_settings"; then return 0; fi
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*false" "$proj_settings"; then return 1; fi
  # Fall back to user setting.
  if [ -f "$user_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$user_settings"; then return 0; fi
  return 1
}

# plugin_installed <plugin@marketplace>: returns 0 if the plugin appears in
# the installed_plugins.json registry (any scope), 1 otherwise.
plugin_installed() {
  local id="$1"
  local registry="$HOME/.claude/plugins/installed_plugins.json"
  [ -f "$registry" ] && grep -q "\"$id\"" "$registry"
}

# mcp_configured <prefix>: returns 0 if any of the settings files contains
# an "allow" permission with the given tool prefix, 1 otherwise. Strict
# proxy for "this MCP server is reachable in this session."
mcp_configured() {
  local prefix="$1"
  for f in \
    "$HOME/.claude/settings.json" \
    "$CLAUDE_PROJECT_DIR/.claude/settings.json" \
    "$CLAUDE_PROJECT_DIR/.claude/settings.local.json"; do
    [ -f "$f" ] || continue
    if grep -q "\"${prefix}" "$f"; then return 0; fi
  done
  return 1
}

# --- Probes -----------------------------------------------------------------

warnings=()
failures=()

# Hard requirement: git on PATH.
if ! command -v git >/dev/null 2>&1; then
  failures+=("[fail] git is not on PATH. Fix: install git (https://git-scm.com/downloads).")
fi

# Hard requirement: CLAUDE_PROJECT_DIR set (we use it to probe project settings).
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  # Not fatal — fall back to PWD.
  CLAUDE_PROJECT_DIR="${PWD}"
fi

# Hard failure: project's .claude/settings.json references a plugin that
# isn't installed in installed_plugins.json. Claude Code itself errors at
# startup when this happens (per the existing /sync skill comment around
# line 968 of skills/sync/SKILL.md).
proj_settings="$CLAUDE_PROJECT_DIR/.claude/settings.json"
if [ -f "$proj_settings" ]; then
  while IFS= read -r enabled_id; do
    # enabled_id is a line like:   "github@claude-plugins-official": true,
    id="$(printf '%s' "$enabled_id" | sed -E 's/^[[:space:]]*"([^"]+)"[[:space:]]*:.*$/\1/')"
    [ -z "$id" ] && continue
    # Only check claude-plugins-official entries — third-party marketplaces
    # may legitimately have their own install/enable mechanisms.
    case "$id" in
      *@claude-plugins-official)
        if ! plugin_installed "$id"; then
          failures+=("[fail] .claude/settings.json references \"$id\" but it is not installed. Fix: claude plugin install $id  OR remove the entry from .claude/settings.json's enabledPlugins block.")
        fi
        ;;
    esac
  done < <(awk '/"enabledPlugins"/,/^[[:space:]]*}/' "$proj_settings" | grep -E '^[[:space:]]*"[^"]+@[^"]+"[[:space:]]*:[[:space:]]*(true|false)')
fi

# Soft requirements: companion plugins enabled.
for id in "${REQUIRED_PLUGINS[@]}"; do
  short="$(printf '%s' "$id" | sed -E 's/@.*//')"
  is_skipped "$short" && continue
  if ! plugin_enabled "$id"; then
    warnings+=("[warn] $id not enabled. Fix: claude plugin install $id")
  fi
done

# Soft requirements: MCP servers reachable via configured tool permissions.
for prefix in "${REQUIRED_MCP_PREFIXES[@]}"; do
  short="$(printf '%s' "$prefix" | sed -E 's/^mcp__//; s/__$//')"
  is_skipped "$short" && continue
  if ! mcp_configured "$prefix"; then
    case "$prefix" in
      "mcp__exa__")
        warnings+=("[warn] Exa MCP server not configured (no \"${prefix}\" permissions found). Fix: add an entry under \"mcpServers\" to ~/.claude.json or .mcp.json. See https://docs.exa.ai/reference/mcp.")
        ;;
      "mcp__firefox-devtools__")
        warnings+=("[warn] Firefox MCP server not configured (no \"${prefix}\" permissions found). Fix: install Firefox MCP. See https://github.com/mozilla/firefox-mcp.")
        ;;
      *)
        warnings+=("[warn] MCP server \"$prefix\" not configured. Fix: add the matching entry under \"mcpServers\".")
        ;;
    esac
  fi
done

# Soft requirement: gh CLI on PATH (used by /sync metadata pre-fill; not critical).
if ! is_skipped "gh-cli" && ! command -v gh >/dev/null 2>&1; then
  warnings+=("[warn] gh CLI not on PATH. Fix: install gh (https://cli.github.com). Used by /sync to read GitHub repo metadata; non-critical.")
fi

# --- Output -----------------------------------------------------------------

# Silent path: no warnings, no failures.
if [ "${#warnings[@]}" -eq 0 ] && [ "${#failures[@]}" -eq 0 ]; then
  emit_json true true "" ""
  exit 0
fi

# Failure path: print failure bundle to stderr and exit 2 (blocking).
if [ "${#failures[@]}" -gt 0 ]; then
  {
    echo "Bytewyrd plugin: requirement check FAILED."
    printf '%s\n' "${failures[@]}"
    if [ "${#warnings[@]}" -gt 0 ]; then
      echo "Also warnings (review after fixing failures):"
      printf '%s\n' "${warnings[@]}"
    fi
  } >&2
  exit 2
fi

# Warning path: print warning bundle, inject one-line summary into context,
# exit 0.
warning_count="${#warnings[@]}"
sys_msg="Bytewyrd plugin: $warning_count requirement(s) missing. See terminal for details. Suppress individual warnings with BYTEWYRD_SKIP_WARN=<id1>,<id2>."
warning_bundle="$(printf '%s\n' "${warnings[@]}")"
ctx="Bytewyrd plugin warnings active: $(printf '%s; ' "${warnings[@]}" | sed 's/; $//')"

# The systemMessage is shown to the user. The additionalContext goes to
# Claude. We also print the full bundle to stderr so a user reviewing
# transcripts can see it.
{
  echo "Bytewyrd plugin: requirement check warnings."
  printf '%s\n' "${warnings[@]}"
  echo "Suppress individual warnings with: BYTEWYRD_SKIP_WARN=<id1>,<id2>  (comma-separated)"
  echo "Suppressible IDs: github, context7, code-review, exa, firefox-devtools, gh-cli"
} >&2

emit_json true false "$sys_msg" "$ctx"
exit 0
```

Make the script executable:

```bash
chmod +x scripts/check-requirements.sh
```

Verification command (run from inside a synced project):

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash scripts/check-requirements.sh
```

Expected output when everything is satisfied:

```
{"continue":true,"suppressOutput":true,"systemMessage":"","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}
```

Expected output when (e.g.) Exa is not configured:

```
Bytewyrd plugin: requirement check warnings.
[warn] Exa MCP server not configured (no "mcp__exa__" permissions found). Fix: add an entry under "mcpServers" to ~/.claude.json or .mcp.json. See https://docs.exa.ai/reference/mcp.
Suppress individual warnings with: BYTEWYRD_SKIP_WARN=<id1>,<id2>  (comma-separated)
{"continue":true,"suppressOutput":false,"systemMessage":"Bytewyrd plugin: 1 requirement(s) missing. See terminal for details. Suppress individual warnings with BYTEWYRD_SKIP_WARN=<id1>,<id2>.","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Bytewyrd plugin warnings active: [warn] Exa MCP server not configured (no \"mcp__exa__\" permissions found). Fix: add an entry under \"mcpServers\" to ~/.claude.json or .mcp.json. See https://docs.exa.ai/reference/mcp."}}
```

#### Step 2 — Create `hooks/hooks.json`

Create the file at the plugin root (NOT inside `.claude-plugin/`, per the upstream plugins-reference directory-structure rule). Content:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "_bw_script=\"${CLAUDE_PLUGIN_ROOT:-}/scripts/check-requirements.sh\"; if [ ! -f \"$_bw_script\" ]; then _bw_script=\"$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/check-requirements.sh\"; fi; if [ ! -f \"$_bw_script\" ]; then _bw_script=$(ls -1 \"$HOME\"/.claude/plugins/cache/*/bytewyrd/scripts/check-requirements.sh 2>/dev/null | head -n1); fi; if [ -z \"$_bw_script\" ] || [ ! -f \"$_bw_script\" ]; then echo 'bytewyrd: check-requirements.sh not found in plugin root or cache; skipping' >&2; exit 0; fi; bash \"$_bw_script\""
          }
        ]
      }
    ]
  }
}
```

**Why this exact command shape:** the `CLAUDE_PLUGIN_ROOT` env var is not reliably set for `SessionStart` events as of the most-recent confirmed bug report (anthropics/affaan-m everything-claude-code#256, fix-shipped in `everything-claude-code` v1.8.0 via a fallback resolver pattern that this command mirrors). The three-step lookup is:

1. `${CLAUDE_PLUGIN_ROOT}/scripts/check-requirements.sh` — works when Claude Code sets the env var correctly.
2. `~/.claude/plugins/cache/bytewyrd/bytewyrd/scripts/check-requirements.sh` — the canonical user-scope install path when the marketplace is `bytewyrd` and the plugin is `bytewyrd`.
3. `ls -1 ~/.claude/plugins/cache/*/bytewyrd/scripts/check-requirements.sh | head -n1` — final fallback that finds the script under any marketplace cache directory.

If all three fail, the hook prints a one-line stderr message and exits 0 so the session is not blocked by the hook itself.

**Path-quoting note:** if the user's home directory contains spaces (anthropics/claude-code#5648), the variable expansions inside the command string remain quoted via the `"$_bw_script"` and `"$HOME"` patterns. The hook command runs through `/bin/sh -c` (per the upstream hooks docs), so single-line commands with proper quoting work portably.

Verification: from inside a synced project's worktree (`CLAUDE_PROJECT_DIR=$(pwd)`), invoke the same command string via `/bin/sh -c '<command>'` and confirm it produces the same output as Step 1's direct invocation.

#### Step 3 — Update `.claude-plugin/plugin.json`

Modify the manifest to register the hooks file. Current content:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  }
}
```

Add a `hooks` field after `version` (per the upstream plugin-manifest schema; the field accepts a string path relative to the plugin root):

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "hooks": "./hooks/hooks.json",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  }
}
```

The `./` prefix is required for all component path fields per the upstream manifest spec. Claude Code merges plugin-shipped hooks into the session hook list at startup; if the same event has multiple matchers from different sources (e.g., the project's own `.claude/settings.json` and the plugin's `hooks/hooks.json`), both fire.

#### Step 4 — Update `skills/sync/SKILL.md`

Four sub-changes:

**Change 4a — Remove `bytewyrd@bytewyrd: true` from the example `enabledPlugins` block.**

Around line 988, the current example reads:

```json
"enabledPlugins": {
  "bytewyrd@bytewyrd": true,
  "github@claude-plugins-official": true,
  "context7@claude-plugins-official": true,
  "code-review@claude-plugins-official": true
}
```

Replace with:

```json
"enabledPlugins": {
  "github@claude-plugins-official": true,
  "context7@claude-plugins-official": true,
  "code-review@claude-plugins-official": true
}
```

Also update the surrounding documentation (around line 962–972) to reflect the new posture. Current text:

```
Build the `enabledPlugins` object as follows:

**Always include** (triggers an install prompt for team members who don't have the plugin yet):
- `bytewyrd@bytewyrd: true`

**Include only if installed** — an uninstalled `claude-plugins-official` plugin causes Claude Code to error on startup:
- `github@claude-plugins-official`
- `context7@claude-plugins-official`
- `code-review@claude-plugins-official`

Always include `extraKnownMarketplaces` with the bytewyrd entry so Claude Code can resolve the plugin URL when prompting team members to install.
```

Replace with:

```
Build the `enabledPlugins` object as follows:

**Do NOT include `bytewyrd@bytewyrd`.** The plugin is installed at user scope (`~/.claude/settings.json`); projects do not assert plugin enablement in `.claude/settings.json`. The plugin's own `SessionStart` requirement-check hook surfaces gaps per session. (Teams that want to mandate plugin enablement at project scope can manually add `"bytewyrd@bytewyrd": true` to their `.claude/settings.json`'s `enabledPlugins` block; this is documented in `docs/guide/installation.md` but is not the default.)

**Include only if installed** — an uninstalled `claude-plugins-official` plugin causes Claude Code to error on startup. Read `~/.claude/plugins/installed_plugins.json` and include each entry only if its identifier is present in the registry:
- `github@claude-plugins-official`
- `context7@claude-plugins-official`
- `code-review@claude-plugins-official`

Always include `extraKnownMarketplaces` with the bytewyrd entry so Claude Code can resolve the plugin URL when team members need to install it.
```

**Change 4b — Add a cleanup step that removes any pre-existing `bytewyrd@bytewyrd` entry from a project's `.claude/settings.json`.**

In the Step that writes `.claude/settings.json` (around line 960), add a new sub-step BEFORE the JSON is written:

```
**Cleanup of legacy entries (always run before writing):** If the existing `.claude/settings.json` contains a `bytewyrd@bytewyrd` entry under `enabledPlugins`, remove it. This is a forward-only migration: pre-RFC projects had the entry; post-RFC projects must not. The cleanup is idempotent — re-running `/sync` on a clean post-RFC project is a no-op.
```

Implementation note for the agent running `/sync`: read the existing settings file, mutate the in-memory representation by deleting any `bytewyrd@bytewyrd` key from `enabledPlugins`, then merge with the build-up rules above. Use `jq -e 'del(.enabledPlugins["bytewyrd@bytewyrd"])'` if `jq` is available (bracket notation is required — dot notation with `@` in the key is non-portable across jq versions); otherwise hand-edit. The cleanup applies only to *user-installed* `.claude/settings.json`; do not touch `~/.claude/settings.json` (that is the user's user-scope file and not in `/sync`'s scope).

**Change 4c — Add the CONTRIBUTING.md install-hint sub-step.**

In the existing `## Development Setup` section template (around line 822), modify the structure:

Current (around line 820–828):

```markdown
# Contributing

## Prerequisites

<PREREQUISITES_SECTION — list the language runtime, relevant CLI tools (cargo, bun, go, uv), and git>

## Development Setup

```bash
git clone <repo-url>
cd <project_slug>
<INSTALL_COMMAND>
```
```

Replace with:

```markdown
# Contributing

## Prerequisites

<PREREQUISITES_SECTION — list the language runtime, relevant CLI tools (cargo, bun, go, uv), and git>

This project uses the [Bytewyrd Claude Code plugin](https://github.com/bytewyrd/claude-bytewyrd) for its dev workflow. Install once per machine (user scope; no per-project install needed):

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
```

The plugin's `SessionStart` hook will warn you if any required companion plugins or MCP servers are missing in this project — follow the printed fix command for each.

## Development Setup

```bash
git clone <repo-url>
cd <project_slug>
<INSTALL_COMMAND>
```
```

This insertion is between the `## Prerequisites` block and `## Development Setup` block. It is idempotent on re-runs: if the inserted block is already present (detected by matching the literal `claude plugin marketplace add bytewyrd/claude-bytewyrd` string), `/sync` skips re-inserting it.

**Change 4d — Update Step 1 plugin-detection table.**

Around line 60–66 in `skills/sync/SKILL.md`, the existing table reads:

```
| Plugin | Identifier | Criticality |
|--------|-----------|-------------|
| GitHub MCP | `github@claude-plugins-official` | Critical |
| Context7 | `context7@claude-plugins-official` | Recommended |
| Code Review | `code-review@claude-plugins-official` | Recommended |
```

No change to the table itself, but add the following note immediately after it:

```
The `bytewyrd@bytewyrd` plugin is NOT in this table — its installation is asserted at user scope on the developer's machine, not in the project's `.claude/settings.json`. The plugin's own `SessionStart` hook (shipped in `hooks/hooks.json`) detects whether it is enabled and surfaces a hard failure to the user if it is referenced in `.claude/settings.json` but missing from the installed-plugin registry.
```

#### Step 5 — Update `skills/best-practices-extract/SKILL.md`

Read the existing skill body to find an appropriate insertion point (the skill does not currently call `gh`, but this RFC adds an optional `gh`-enrichment path for PR context). Add a new section near the top, before the main extraction workflow:

```markdown
## Requirement check

This skill optionally enriches its output with PR context from the GitHub CLI. The CLI is a soft dependency:

1. Before invoking `gh`, run `command -v gh >/dev/null 2>&1` to verify it is on `PATH`.
2. If `gh` is missing, print exactly: `gh CLI not on PATH — extracting without PR context.` and continue with the rest of the extraction.
3. If `gh` is present but unauthenticated (`gh auth status` exits non-zero), print exactly: `gh CLI not logged in — extracting without PR context.` and continue.

The skill must not fail or block on this missing dependency; it must produce its primary output regardless.
```

Place this section directly after the skill's existing introductory paragraph and before its primary workflow steps. If the skill already has a similar guard, this RFC's addition supersedes it; do not duplicate.

#### Step 6 — Update `skills/refactor/SKILL.md`

Add a similar one-paragraph section near the top. Note: the skill does not currently invoke `/review` before refactoring — this RFC adds a pre-pass step conditioned on plugin availability.

```markdown
## Requirement check

This skill optionally invokes the `/review` slash command (from the `code-review@claude-plugins-official` plugin) for a pre-pass before refactoring. This pre-pass is added by this RFC; the companion plugin is a soft dependency:

1. Before invoking `/review`, the orchestrating agent should check whether the `code-review` plugin is enabled by inspecting the user's `~/.claude/settings.json` `enabledPlugins` block or the project's `.claude/settings.json` block. The simplest probe is: `grep -q '"code-review@claude-plugins-official"[[:space:]]*:[[:space:]]*true' ~/.claude/settings.json .claude/settings.json 2>/dev/null`.
2. If the plugin is not enabled, print exactly: `code-review@claude-plugins-official not enabled — running /refactor without pre-pass review.` and proceed directly to the analysis phase.
3. If it is enabled, run the pre-pass as designed.

The refactor must produce its primary output (the analysis + plan + approval gate + apply phases) regardless of whether the pre-pass ran.
```

Place this section directly after the skill's existing introductory paragraph and before its primary workflow steps.

#### Step 7 — Update `skills/rfc-implement/SKILL.md`

Add a similar one-paragraph section near the top:

```markdown
## Requirement check

This skill creates a pull request at the end of implementation. PR creation uses the GitHub MCP when available, falling back to the `gh` CLI:

1. Probe whether the GitHub MCP is enabled: `grep -q '"github@claude-plugins-official"[[:space:]]*:[[:space:]]*true' ~/.claude/settings.json .claude/settings.json 2>/dev/null`.
2. If enabled, use the `mcp__plugin_github_github__create_pull_request` MCP tool. Print: `Using GitHub MCP for PR creation.`
3. If not enabled, fall back to `gh pr create`. Before invoking, run `command -v gh >/dev/null 2>&1` to verify the CLI is present and `gh auth status` to verify it is logged in. Print exactly: `GitHub MCP not enabled — using gh CLI for PR creation.`
4. If neither is available, abort PR creation with: `Cannot create PR: neither GitHub MCP nor gh CLI is available. Fix: install github@claude-plugins-official OR install gh CLI and run gh auth login.`

The implementation itself (code edits, commit, push) completes regardless of which PR-creation path is taken.
```

Place this section directly after the skill's existing introductory paragraph and before its primary workflow steps.

#### Step 8 — Create `docs/guide/installation.md`

`docs/guide/installation.md` does not currently exist (`docs/guide/` is an empty directory). Create the file with the content below. If the file exists in a future state, replace the `## Installation` section with the user-scope-first version and add the two new subsections.

Create with:

```markdown
## Installation

The plugin installs at user scope by default — install once per machine, use everywhere:

\`\`\`bash
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
\`\`\`

The default scope is `user` (per Claude Code's `claude plugin install` documentation), which writes the enable-flag to `~/.claude/settings.json` and makes the plugin available in every project you open.

## What the plugin checks at session start

Every time you start a session in any project, the plugin runs a one-shot requirement check via a `SessionStart` hook. The check is silent when everything is satisfied. When something is missing, you'll see one of two outputs:

- **Warning bundle** (most common): the plugin lists each missing soft dependency (companion plugins not enabled, MCP servers not configured, optional CLI tools not on PATH) with the exact fix command for each. The session continues normally. Suppress individual warnings by exporting `BYTEWYRD_SKIP_WARN=<id1>,<id2>` in your shell — e.g., `export BYTEWYRD_SKIP_WARN=firefox-devtools,gh-cli` if you're working on a backend project and don't want UI/CLI nudges.

- **Hard failure** (rare): the plugin exits with a blocking error in one of two conditions:
  1. The project's `.claude/settings.json` references a `claude-plugins-official` plugin that is not installed (Claude Code itself would error during a tool call later — the hook surfaces this at startup with the exact fix).
  2. `git` is not on your `PATH` (the plugin cannot do anything without it).

In both cases the error message includes the exact command to fix the condition.

## Team-wide enforcement (optional)

The default posture is user-scope-first: the plugin is installed once per developer, and projects do not assert plugin enablement in their `.claude/settings.json`. If your team wants to *require* every collaborator to have the plugin installed (e.g., for a strict code-review or RFC-discipline policy), add the following to your project's `.claude/settings.json` under `enabledPlugins`:

\`\`\`json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": true
  }
}
\`\`\`

Per Claude Code's settings precedence rules, project settings override user settings — so a collaborator who hasn't installed the plugin yet will get an install prompt when they open the project. `/sync` does not write this entry by default; teams that want it must add it manually and check it into source control.
```

#### Step 9 — Update `CLAUDE.md` (plugin root) and `.claude-plugin/CLAUDE.md`

Add this subsection to the `## Workflow` section in the plugin-root `CLAUDE.md` (which has that exact heading), and to the `## Development Workflow` section in `.claude-plugin/CLAUDE.md` (which uses that heading instead). Place it AFTER the existing `### Session start` subsection in each file (or, if the order has been changed by another RFC, immediately after `### Session start` wherever it sits):

```markdown
### Requirement-check hook

The plugin ships a `SessionStart` hook (`hooks/hooks.json` → `scripts/check-requirements.sh`) that runs once per session in every project where the plugin is enabled. The hook probes:

- Companion plugin enable-state (`github@claude-plugins-official`, `context7@claude-plugins-official`, `code-review@claude-plugins-official`) via `~/.claude/settings.json` and the project's `.claude/settings.json`.
- MCP server configuration (Exa, Firefox MCP) via permission entries in user or project settings.
- `git` and `gh` CLI availability on `PATH`.
- Stale references in the project's `.claude/settings.json` pointing at uninstalled plugins.

The hook outputs nothing when everything is satisfied. It outputs a warning bundle when soft dependencies are missing (session continues). It exits with status 2 only on two conditions: missing `git`, or a stale `claude-plugins-official` reference that Claude Code itself would error on later. Individual warnings can be suppressed via `BYTEWYRD_SKIP_WARN=<id1>,<id2>` in the user's shell environment.

When you add a new skill or agent that depends on a specific external tool, decide whether to (a) add a probe to the skill body (the in-skill pattern used by `best-practices-extract`, `refactor`, and `rfc-implement`), or (b) extend `scripts/check-requirements.sh` to surface the gap at session start. Use (a) when the dependency is specific to one skill and the failure can be handled locally; use (b) when the dependency is plugin-wide and the user should know about it on day one rather than mid-task.
```

The two `CLAUDE.md` files (`/CLAUDE.md` at the plugin root, and `.claude-plugin/CLAUDE.md`) get the identical subsection so the guidance is visible both when developing in this checkout and (eventually, after the next `/sync` integration update) when consuming the plugin from another project.

#### Step 10 — Verification

After all changes, run these checks from the plugin root:

1. **The script is executable and runs cleanly:**

   ```bash
   test -x scripts/check-requirements.sh && CLAUDE_PROJECT_DIR=$(pwd) bash scripts/check-requirements.sh
   ```

   Expected output: a single line of JSON beginning with `{"continue":true,...` if the developer's local environment satisfies all requirements; otherwise a warning bundle to stderr plus the JSON. Exit code should be 0 (warnings allowed) or 2 (only when a hard failure actually applies — e.g., if the local `.claude/settings.json` lists a `claude-plugins-official` plugin that isn't installed).

2. **The hook entry parses as valid JSON:**

   ```bash
   python3 -c 'import json; json.load(open("hooks/hooks.json"))' && echo OK
   ```

   Expected output: `OK`

3. **The plugin manifest still parses and includes the `hooks` field:**

   ```bash
   python3 -c 'import json,sys; m=json.load(open(".claude-plugin/plugin.json")); sys.exit(0 if m.get("hooks")=="./hooks/hooks.json" else 1)' && echo OK
   ```

   Expected output: `OK`

4. **The sync skill no longer asserts `bytewyrd@bytewyrd` enablement:**

   ```bash
   ! grep -F '"bytewyrd@bytewyrd": true' skills/sync/SKILL.md
   ```

   Expected output: empty (the grep must return non-zero — the literal text should no longer appear in `skills/sync/SKILL.md` example blocks for `.claude/settings.json`).

   To double-check the change is in the right scope, also run:

   ```bash
   grep -F 'Do NOT include `bytewyrd@bytewyrd`' skills/sync/SKILL.md
   ```

   Expected: the line `**Do NOT include \`bytewyrd@bytewyrd\`.**` appears once.

5. **The three skill probes are present:**

   ```bash
   grep -F 'gh CLI not on PATH' skills/best-practices-extract/SKILL.md
   grep -F 'code-review@claude-plugins-official not enabled' skills/refactor/SKILL.md
   grep -F 'GitHub MCP not enabled' skills/rfc-implement/SKILL.md
   ```

   Each grep should return exactly one matching line.

6. **The installation guide includes the new subsections:**

   ```bash
   grep -F '## What the plugin checks at session start' docs/guide/installation.md
   grep -F '## Team-wide enforcement (optional)' docs/guide/installation.md
   ```

   Each grep should return exactly one matching line.

7. **Both `CLAUDE.md` files include the new subsection:**

   ```bash
   grep -F '### Requirement-check hook' CLAUDE.md
   grep -F '### Requirement-check hook' .claude-plugin/CLAUDE.md
   ```

   Each grep should return exactly one matching line.

8. **Functional smoke test:** in a freshly cloned project that has the bytewyrd plugin enabled at user scope:
   - Restart Claude Code to pick up the new hook.
   - Confirm that on session start, the hook fires once (visible in `claude --debug` output).
   - Confirm that if all requirements are satisfied, no terminal output appears.
   - Confirm that if (e.g.) you temporarily set `mv ~/.claude/settings.json{,.bak}` to hide your user-scope settings, the hook produces warning output identifying the now-missing companion plugins, the session continues, and the message includes the exact `claude plugin install` fix command.
   - Restore `~/.claude/settings.json` after the test (`mv ~/.claude/settings.json.bak ~/.claude/settings.json`).
   - Test the hard-failure path: in a throwaway project, add `"code-review@claude-plugins-official": true` to `.claude/settings.json` while it is *not* installed in `~/.claude/plugins/installed_plugins.json`. Start a session and confirm the hook exits with status 2 and prints the `Fix: claude plugin install ...` line to stderr. Remove the throwaway entry afterward.

   If any of these smoke tests fail, the most likely causes (in order) are:
   - (a) `${CLAUDE_PLUGIN_ROOT}` is unset on `SessionStart` and the fallback resolver in `hooks/hooks.json` isn't finding the script — run `claude --debug` and look for the "bytewyrd: check-requirements.sh not found" line; if present, check whether the plugin is installed in `~/.claude/plugins/cache/bytewyrd/bytewyrd/` (canonical) or some other path, and adjust the fallback glob.
   - (b) The script's `grep` probes are failing on a settings file that uses a non-standard JSON layout (e.g., a one-line minified JSON without whitespace). The probes use `[[:space:]]*` to tolerate variable whitespace; if a user has minified their settings, the probes still match because `[[:space:]]*` accepts zero whitespace.
   - (c) The hook entry in `hooks/hooks.json` is being treated as a different shell than expected. Per the upstream hooks docs, plugin-shipped hooks of type `command` run via `/bin/sh -c` on POSIX systems and `cmd.exe` on Windows. The script body in this RFC is bash-specific (it uses `command -v`, `[[:space:]]`, and `case` syntax that POSIX `sh` supports but with caveats); the hook command explicitly invokes `bash "$_bw_script"` rather than relying on the shebang to be respected, which ensures bash runs the script regardless of the shell that ran the hook entry.

## Risks and open questions

- **Risk: the bash check script silently passes a probe when grep matches in a non-`enabledPlugins` context.** Example: a permission entry like `"Bash(echo \"bytewyrd@bytewyrd\":*)"` would falsely match the plugin-enabled probe. **Mitigation:** the regex is `"<id>"[[:space:]]*:[[:space:]]*true`, which requires the colon-true-pattern characteristic of `enabledPlugins` blocks specifically; it won't match a `Bash(...)` permission line. The risk is real but the literal pattern is narrow enough that pathological false positives are unlikely. **Resolution:** accepted; document the caveat in the script comments.

- **Risk: `jq` is not on the user's PATH and the cleanup step in `/sync` (Change 4b) needs to hand-edit JSON.** **Mitigation:** the cleanup step instructs the agent to use `jq` if available; otherwise hand-edit. The agent can detect this via `command -v jq` and branch accordingly. Hand-editing is straightforward (`grep -v '"bytewyrd@bytewyrd"' settings.json` won't work because it loses the comma fixup, but the agent can read the file, mutate the JSON in memory, and write back). **Resolution:** accepted; document the two paths in the sync skill.

- **Risk: the hook fires before MCP servers are fully initialized in some Claude Code versions.** Per the upstream hooks docs, `SessionStart` fires when Claude Code starts the session, which precedes MCP server initialization in some race conditions. Our check infers MCP server presence from settings-file permission entries (not from live tool availability), so the check is independent of MCP initialization timing. **Resolution:** the inference strategy avoids the timing problem entirely; the trade-off is that a user who has the permission entry but a broken MCP server config gets a false-clean signal. The failure surfaces on the first real MCP tool call, which is acceptable — the hook's job is to surface configuration gaps, not to runtime-validate MCP servers.

- **Open question: should the hook also probe the user's MCP-server config files (`~/.claude.json`, `.mcp.json`) directly, rather than inferring from permission entries?** Doing so would catch the case where a user has the permission entry but no actual server configured. **Resolution within this RFC:** no. The permission-entry inference is simpler and catches 95% of cases (a permission entry without a matching server config is unusual — users don't usually add permissions for tools they haven't configured). Adding `~/.claude.json` parsing introduces dependency on the file's evolving schema (it is documented but not strictly versioned). A future RFC can add this if real-world use shows the permission-only inference is too lenient.

- **Open question: should `BYTEWYRD_SKIP_WARN` accept wildcards (e.g., `BYTEWYRD_SKIP_WARN=firefox-*`)?** **Resolution within this RFC:** no. Exact-match identifiers keep the suppression behaviour predictable. Users who want to suppress all MCP warnings can list them explicitly; the friction is bounded (3-4 IDs at most).

- **Open question: should the script support a `BYTEWYRD_QUIET=1` env var that silences even hard failures?** **Resolution:** no. Hard failures correspond to conditions where Claude Code itself misbehaves; suppressing them would defeat the safety purpose of the check. The two hard-failure conditions are narrow enough that they should never occur in normal use; if a user is hitting them repeatedly, the right answer is to fix the underlying config, not to suppress the warning.

- **Open question: when Claude Code's `CLAUDE_PLUGIN_ROOT` bug (everything-claude-code#256) is fixed, should we remove the fallback resolver?** **Resolution:** the fallback is purely defensive; it has no functional impact when `CLAUDE_PLUGIN_ROOT` is set correctly. Leaving it in place protects users on older Claude Code versions. It can be removed in a future RFC once a minimum supported Claude Code version is declared that has the env var set reliably — out of scope here.

- **Open question: should the plugin also ship a `Setup` hook (one-time-per-install) that produces a "welcome" message with the install + check-summary?** **Resolution:** out of scope. The hooks page documents `Setup` as one-time-per-install behaviour, and a welcome screen would be useful, but it is a polish item. The `SessionStart` check is the load-bearing piece; `Setup` is purely cosmetic in this context.

- **Open question: should `/sync` be re-run on every project to migrate away from the legacy `bytewyrd@bytewyrd: true` entry?** **Resolution:** the cleanup is forward-only and idempotent (Change 4b). Existing projects that have the entry will keep it until they re-run `/sync`; the project's `SessionStart` hook (now installed by the user-scope plugin) will surface no failure because the entry is technically valid — it just becomes redundant after the user installs the plugin at user scope. The redundancy doesn't cause any functional problem; it just wastes a line in the settings file. Users will pick up the cleanup on their next routine `/sync` re-run. The existing `bootstrap-content-version` mechanism in the plugin's `SessionStart` hook will nudge them to re-run if any other sync content has changed.

## Relationship to other RFCs

- **2026-05-12-modular-plugin-feature-toggles** (status: Draft) — proposes restructuring the plugin so consumers can enable/disable feature groups during `/sync`. That RFC's design choices (what counts as a core feature, how toggles are stored) are independent of this RFC's: this RFC changes where the plugin is *installed* and how it *verifies* per-project state, not which of its features are *active*. The two compose: a user could install at user scope (this RFC), then enable only the RFC-workflow feature group (the toggles RFC). If both RFCs ship, the requirement check needs to be aware of toggle state so it doesn't warn about a missing dependency the user has explicitly disabled — but that integration is small (the check reads the toggle state from wherever the toggles RFC chooses to store it). This RFC does not block the toggles RFC and is not blocked by it.

- **2026-05-12-auto-extract-best-practices-on-precompact** (status: Draft) — proposes making `PreCompact` actually fire `/best-practices-extract` rather than just printing a reminder. That RFC modifies project-scoped hooks written by `/sync`; this RFC modifies plugin-scoped hooks shipped in `hooks/hooks.json`. The two operate on disjoint surfaces and do not conflict.

- **2026-05-12-drop-dates-from-best-practices** (status: Draft) — purely documentation/data formatting; no overlap.

- **2026-05-12-evidence-based-research-rfc-architect** (status: Draft) — strengthens the RFC-author's research discipline; no overlap with installation or hooks.

- **2026-05-12-post-approval-discretionary-revisions** (status: Draft) — adds an RFC-template section; no overlap.

- **2026-05-12-rfc-summary-command** (status: Draft) — adds a slash command for listing in-flight RFCs; no overlap.

- **2026-05-12-sync-enforce-github-branch-auto-delete** (status: Draft) — adds another `/sync` GitHub-side enforcement; no overlap with the local hook surface.

- **2026-05-12-unify-best-practices-destinations** (status: Draft) — clarifies where best-practices entries land; no overlap.

- **`/sync` skill (no RFC; existing skill).** This RFC modifies `skills/sync/SKILL.md` in four sub-changes (Step 4). The changes are forward-compatible: re-running `/sync` on a pre-RFC project performs the cleanup automatically. Projects that have not run `/sync` since the cleanup change is committed keep their legacy `bytewyrd@bytewyrd: true` entry; the entry is now functionally redundant but not harmful. The bootstrap-content-version mechanism nudges users to re-run `/sync` to pick up the new template.

- **`/rfc-implement` skill (modified by this RFC, Step 7).** The implementation of this RFC, when it lands, will be performed by `/rfc-implement`. `/rfc-implement`'s body is one of the files being modified — the implementation agent must apply the changes to `skills/rfc-implement/SKILL.md` before completing. Bootstrapping is acyclic: the changes are mechanical edits and do not require the new probe behaviour to function during the implementation pass itself (the probe is invoked at PR-creation time, which is the last step; if the change isn't in place yet on disk, the agent simply uses the pre-RFC behaviour for that one invocation).
