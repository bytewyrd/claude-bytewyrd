---
rfc: "2026-05-10-documentation-agent-lifecycle-hooks"
title: "Documentation Agent with Lifecycle Hooks"
author: "Rodrigo Kochenburger"
status: "Done"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add a specialized `docs-agent` to the bytewyrd plugin that owns the user-facing documentation surface in `docs/guide/` — tutorials, how-to guides, API reference pages, and a dedicated contributor section — and wire it into the workflow via two Claude Code hooks so docs stay current automatically. The first hook fires `SubagentStop` matching `feature-engineer` (the agent spawned by `/rfc-implement`), prompting the main agent to consider invoking `/docs-review` after a feature lands; the second hook fires inside `/sync` (the plugin's existing setup/refresh skill) and compares the local `docs-agent-version` marker to the plugin's current version, kicking off a documentation review against the codebase when the agent definition has improved. The agent is bounded by a strict ownership map: it owns `docs/guide/**` and the contributor section, and it must **never** touch `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, or `docs/rfcs/**`, which already have separate owners. The skill front door is `/docs-review [scope-hint]`, modeled on the same pattern `/refactor` and `/rfc-new` use: a thin skill that spawns the specialist subagent with the protocol as its prompt.

## Should we do this?

**Yes.** Documentation drift is the single most common bug in open-source projects with active development: tutorials reference removed APIs, how-to guides assume an old CLI surface, the contributor section onboards developers into a workflow that has since changed. The bytewyrd plugin's own `docs/` tree already demonstrates the problem at a small scale — the existing `docs/guide/` directory is empty even though the project ships consumer-facing skills (`/sync`, `/rfc-new`, `/refactor`) that warrant tutorials. The plugin has a `documentation-writer.md` agent vendored from VoltAgent but no skill front door, no scoped ownership rules, and no automation to keep tutorials and references in step with the code. Adding (1) a tightly-scoped `docs-agent` definition with an explicit ownership boundary, (2) a `/docs-review` skill that spawns it with a structured protocol, and (3) two lifecycle hooks that prompt the agent at the moments docs are most likely to drift (after a feature lands; when the docs-agent definition itself improves) closes the loop. Cost is one new agent file, one new skill, two new hook entries in the plugin's hook config, and a small extension to the `/sync` skill body; payoff is a documentation surface that is actively maintained rather than passively decaying, with the same human-approval discipline that `/refactor` uses to prevent autonomous mutations.

## Current state

The plugin currently exposes documentation capability through one piece — the `documentation-writer.md` agent at `agents/documentation-writer.md` — and that piece is invoked only when the main agent independently decides to delegate to it. There is no slash command, no scoped ownership map, no protocol for "what does a documentation review actually check," and no automation that nudges the agent to run at the moments documentation is most likely to drift.

**What exists today:**

- `agents/documentation-writer.md` — a 52-line agent definition originally from VoltAgent's `awesome-claude-code-subagents` library (MIT). It covers "documentation architecture," "audience-specific writing," "documentation standards," and "quality assurance" in generic terms. Its instructions reference `README.md`, `DEVELOPMENT.md`, and a generic `docs/` directory — none of which match this plugin's actual documentation layout (which uses `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, `docs/rfcs/`, and a currently-empty `docs/guide/`). The agent has no `model:` field, so it inherits whatever the parent session is using; it has no scoped file list, so a freeform invocation can mutate any file under `docs/` — including the four files that already have separate owners.
- `docs/` directory layout in consumer projects (and dogfooded here): `ARCHITECTURE.md` (system design, owned by changes to component structure), `CONTRIBUTING.md` (dev workflow, owned by changes to setup or quality gates), `BEST_PRACTICES.md` (session learnings, owned by `/best-practices-extract` and `/best-practices-sync`), `project-brief.md` (product identity, owned by `/sync` Step 2), `rfcs/` (proposals, owned by `/rfc-*` skills), `rfc-process.md` (canonical process doc, owned by `/rfc-update` and `/sync`), `rfc-braindump.md` (ideas list, owned by `/rfc-braindump` and `/rfc-new`), and `guide/` (currently empty — the gap this RFC fills).
- `skills/` — thirteen skills exist today (`best-practices-extract`, `best-practices-record`, `git-branch-cleanup`, `rfc-approve`, `rfc-braindump`, `rfc-consensus-review`, `rfc-drop`, `rfc-implement`, `rfc-new`, `rfc-read-feedback`, `rfc-update`, `refactor`, `sync`). None target documentation. The pattern they all follow: the skill body instructs the main agent to spawn a specialist subagent via the Agent tool with a structured prompt. RFC `2026-05-10-refactor-command` (Done) added `/refactor` following the same pattern and serves as the closest precedent for the skill shape this RFC needs.
- `.claude-plugin/plugin.json` — currently a minimal metadata file (name, description, version, author). No `skills` array exists today; skills are auto-discovered from `skills/`. No `hooks` field is referenced. The plugin's hook system is currently provisioned only at the project level via `.claude/settings.json` (see below) — there is no `.claude-plugin/hooks/hooks.json` file in the plugin yet.
- `.claude/settings.json` — the plugin's own checkout uses hooks at the project level. The current hook events configured are: `SessionStart` (reminds about `/sync` when `bootstrap-content-version` differs), `PreCompact` (reminds about `/best-practices-extract`), `PostToolUse` matching `Bash(git commit*)` and two MCP file-write tools (reminds about ARCHITECTURE/CONTRIBUTING/README/project-brief updates), and `Stop` (reminds about session-end checklist plus `/best-practices-sync` when in the plugin checkout). These are echo-only reminder hooks — they print suggestions to the agent but never block or auto-execute anything. They are the template this RFC's hooks follow.
- `CLAUDE.md` "Agent delegation" table currently routes "Documentation" tasks to `documentation-writer`. There is no row for proactive documentation review or for a scoped, hook-triggered docs workflow. The Model Usage Optimization section says `sonnet` is appropriate for "routine code review (correctness, conventions, security), refactoring, implementation of well-defined tasks" — which is the right tier for documentation reviews against a defined ownership scope.
- `skills/sync/SKILL.md` — the idempotent project-setup skill. It already detects stale `bootstrap-content-version` markers in `docs/BEST_PRACTICES.md` and prompts the user to re-sync, and it reads/writes `docs/project-brief.md` as the project identity source of truth. It has a `SessionStart` hook (in `.claude/settings.json`) that fires when bootstrap content versions differ. There is no existing mechanism that detects "the docs-agent definition itself has changed" — this RFC adds that detection inside the sync flow.

**What is broken or missing:**

1. **No discovery surface for documentation work.** A user reading the `/`-commands list sees `/rfc-new`, `/refactor`, `/best-practices-extract` — nothing for documentation. The `documentation-writer` agent exists but is only invoked when the main agent's heuristics happen to match its autoload description; without a skill front door, the agent is invisible in autocomplete and underused in practice.
2. **No ownership boundary.** The existing `documentation-writer.md` has no scoped file list. A freeform invocation ("update the docs for X") can mutate any markdown file under `docs/`, including the four files that already have explicit owners (`ARCHITECTURE.md` is owned by component-structure changes, `CONTRIBUTING.md` by dev-workflow changes, `BEST_PRACTICES.md` by `/best-practices-extract`, `project-brief.md` by `/sync` Step 2). A documentation agent that overwrites these files silently violates their ownership contracts. The hooks already in `.claude/settings.json` enumerate this ownership map ("Post-commit: does this change component structure → ARCHITECTURE.md; dev workflow or quality gate → CONTRIBUTING.md; ..."); a docs-agent that does not encode the same map is bound to overstep.
3. **No protocol for "what does a documentation review check."** "Review the docs" is too vague to be actionable. A real review needs explicit checks: do the tutorials use APIs that still exist; do the how-to guides reference current CLI flags; do code examples actually compile and run against the current codebase; are there gaps where features exist but no docs do; is the contributor section consistent with the current `CONTRIBUTING.md` and dev workflow.
4. **No lifecycle automation.** The two moments documentation is most likely to drift are (a) right after a feature lands (the code changed, the docs haven't caught up yet) and (b) when the documentation tooling itself improves (the agent's definition gains a new check that may surface drift in already-shipped code). Today there is nothing that nudges the docs review at either moment. The project's `Stop` hook lists a session-end checklist that mentions ARCHITECTURE/CONTRIBUTING/README/project-brief updates but does not mention user-facing docs in `docs/guide/`, because that directory is currently empty.
5. **`docs/guide/` is empty.** The plugin's own dogfooded layout has `docs/guide/` as the intended home for user-facing tutorials and references, but it has no content. This RFC defines what goes there (and what the agent populates and maintains) so the directory becomes meaningful rather than aspirational.

The plugin's other workflow skills demonstrate the pattern this RFC follows: opinionated, small-surface skills that pin model/effort, instruct the main agent to spawn a specialist subagent via the Agent tool with a structured prompt, and scope the work explicitly via a file list. `/docs-review` fills the same shape for documentation work; the lifecycle hooks add the two moments of automatic invocation that the existing skills do not currently cover.

## Analysis / Options

There are four coupled decisions: where the agent's ownership boundary lies, how the skill front door is shaped, how the post-implement hook fires, and how `/sync` detects an improved agent definition.

### Decision 1 — What does the docs-agent own?

**Option A — Own `docs/guide/**` plus a contributor section file; never touch the four already-owned files (recommended).**
The agent owns:
- `docs/guide/tutorials/` — getting-started, end-to-end walkthroughs (user perspective)
- `docs/guide/how-to/` — task-oriented recipes (user perspective)
- `docs/guide/reference/` — API/skill/agent reference pages (auto-generated content shape, hand-curated descriptions)
- `docs/guide/contributing.md` — extended contributor onboarding (project-anatomy, "how to add a skill", "how to add an agent", "how the plugin packaging works") that complements but does not replace `docs/CONTRIBUTING.md`

The agent must **never** modify:
- `docs/ARCHITECTURE.md` — owned by changes to component structure
- `docs/CONTRIBUTING.md` — owned by changes to dev workflow or quality gates
- `docs/BEST_PRACTICES.md` — owned by `/best-practices-extract` and `/best-practices-sync`
- `docs/project-brief.md` — owned by `/sync` Step 2
- `docs/rfcs/**` — owned by `/rfc-*` skills
- `docs/rfc-process.md` — owned by `/rfc-update` and `/sync`
- `docs/rfc-braindump.md` — owned by `/rfc-braindump` and `/rfc-new`
- `README.md` (project root) — owned by changes to user-facing behavior or install method

This matches the [Diátaxis](https://diataxis.fr/) documentation framework (tutorials, how-to guides, reference, explanation), which is the closest thing to a de facto standard for "what kinds of documentation exist" in a software project. The four-quadrant split makes the agent's surface area concrete enough to enforce with a literal allow-list and reject-list in the agent's frontmatter/prompt.

**Option B — Own all of `docs/` and rely on the agent's prompt to "respect" the other owners.**
Strictly weaker than A. A prompt-level "please don't touch X" instruction is not enforceable; the agent will inevitably edit a file it was told to leave alone if the user phrases a request loosely ("the project's docs are confusing — clean them up"). The four already-owned files have separate skills, separate hooks, and separate review contexts for good reasons; a docs-agent that can touch them is one bad prompt away from clobbering session learnings or rewriting the project brief.

**Option C — Generate a new owner-distinct directory entirely (`docs/user-docs/` or similar) to sidestep the ownership question.**
Avoids the boundary question by creating a parallel surface, but loses the symmetry with `docs/guide/` (which the plugin already provisioned) and creates a second user-facing docs directory that confuses both contributors and readers. The cleaner answer is to use the directory that is already provisioned and define its scope precisely.

**Recommendation: Option A.** The four-file reject-list is short, memorable, and enforceable in the agent's allow-list. Diátaxis gives a vocabulary for the four quadrants the agent populates so contributors can extend the docs in a structured way rather than ad-hoc. The contributor section (`docs/guide/contributing.md`) is the one new file the agent introduces — it extends rather than replaces `docs/CONTRIBUTING.md` (which stays narrowly focused on prerequisites, setup, dev workflow, quality gate, PR process).

### Decision 2 — How is `/docs-review` implemented?

**Option A — Skill that instructs the main agent to spawn `docs-agent` via the Agent tool (recommended).**
Add `skills/docs-review/SKILL.md`. The skill body instructs the main agent to spawn a `bytewyrd:docs-agent` agent with `model: "sonnet"`, passing the structured documentation-review protocol (scope resolution → coverage audit → drift detection → plan → approval gate → apply → report) as the agent prompt. This is exactly the pattern `/refactor`, `/rfc-new`, and `/rfc-implement` already use. The skill itself does not declare an agent binding or a forked context; the spawning is explicit, done by the main agent via the Agent tool.

**Option B — Skill body runs in the main conversation, no subagent.**
Rejected for the same reason `/refactor` rejected it: the protocol is long (coverage audit output, drift findings, per-file plans, per-step apply logs), and running it in the parent context window wastes tokens that should be reserved for the user's actual work.

**Option C — Slash command file under `.claude/commands/` (legacy path).**
Rejected on consistency grounds — every other entry point in this plugin is a skill, not a command file.

**Recommendation: Option A.** Pinning the model is straightforward (`model: "sonnet"` in the spawn instruction). Documentation work is the canonical Sonnet use case per the plugin's Model Usage Optimization section ("routine code review, refactoring, implementation of well-defined tasks") — it does not need Opus, and pinning Sonnet keeps the per-invocation cost bounded so the hook-triggered invocations don't burn the user's quota. The skill is invocable manually (`/docs-review [scope-hint]`) and is the same target the hooks recommend to the main agent (the hooks print a suggestion; the main agent decides whether to invoke).

### Decision 3 — How does the post-`/rfc-implement` hook fire?

The braindump asked for "trigger after `/rfc-implement` completes." `/rfc-implement` is a skill that spawns a `feature-engineer` subagent; the natural completion signal is the subagent stopping.

**Option A — `SubagentStop` hook matching `feature-engineer` (recommended).**
Claude Code's `SubagentStop` event fires when any subagent completes, and supports a matcher on agent name. A hook entry like `{ "matcher": "feature-engineer", "hooks": [...] }` fires exactly when the agent spawned by `/rfc-implement` (and only that agent) finishes its turn. The hook is an echo-only reminder (matching the existing project hook style): it prints a suggestion to the main agent — "feature-engineer just finished; consider `/docs-review <implemented-RFC-files>` to check whether the new feature needs docs updates" — and lets the main agent decide whether to invoke. No autonomous mutation; just a nudge at the right moment.

This has two false-positive sources to acknowledge: (1) `feature-engineer` may be spawned outside `/rfc-implement` (via `/refactor`'s recommended-follow-ups or a manual delegation), in which case the hook still fires; (2) `feature-engineer` may finish without a successful merge (the user aborts mid-way), in which case the hook still fires. Both are acceptable — the hook is a reminder, not an action, and the suggested follow-up (`/docs-review`) is itself gated by a human-approval step inside the subagent's protocol, so a false-positive hook firing costs nothing but a printed line of text.

**Option B — `Stop` hook with a body that inspects the just-completed turn to detect "did /rfc-implement just finish."**
Rejected: `Stop` fires on every turn and has no matcher; the inspect-the-turn logic would be brittle (it would have to parse the conversation transcript to determine whether `/rfc-implement` was the trigger), and the `Stop` event documented matcher list is empty. Wrong tool.

**Option C — `UserPromptExpansion` matcher on `rfc-implement` to fire when the skill *starts*, then write a sentinel file that a later `Stop` hook checks for.**
Rejected as overcomplicated. The sentinel-file dance reinvents what `SubagentStop` matchers already provide cleanly.

**Recommendation: Option A.** `SubagentStop` matching `feature-engineer` is the documented, named mechanism for "after this specific agent finishes" and the hook body is a one-line echo, identical in shape to the existing project hooks.

**Note:** The `SubagentStop` matcher format has not been empirically verified for this project. The regex `(^|:)feature-engineer$` is designed to match both bare and plugin-namespaced agent identifiers. The verification step 10's debug probe (`echo "matched: $CLAUDE_HOOK_MATCHED"`) should be run before relying on the hook in production; if the matcher does not work as expected, fall back to the literal string `feature-engineer` and test again.

### Decision 4 — How does `/sync` detect an improved docs-agent definition and trigger a doc review?

The braindump asked for "/sync detect when the agent definition itself has improved and kick off a review of existing docs against the current codebase." `/sync` already uses a `bootstrap-content-version` marker (a `YYYY-MM-DD-<git-sha-prefix>` string embedded as an HTML comment in `docs/BEST_PRACTICES.md` and `skills/sync/SKILL.md`) to detect drift between project and plugin versions. The same mechanism extends naturally to the docs-agent.

**Option A — Embed a `docs-agent-version` marker in `agents/docs-agent.md` and have `/sync` record/compare it against a per-project marker file (recommended).**
The plugin's `agents/docs-agent.md` carries an HTML-comment marker near the top: `<!-- docs-agent-version: YYYY-MM-DD-<git-sha-prefix> -->`. The version string is updated by hand (or via a release script) whenever the agent definition changes meaningfully — same convention as `bootstrap-content-version`.

`/sync` reads the plugin's marker (from `$CLAUDE_PLUGIN_ROOT/agents/docs-agent.md`) and the project's recorded marker (from `.bytewyrd/docs-agent-version`, a tiny gitignored file under `.bytewyrd/`). If they differ — or if the project file is absent — `/sync` prints a suggestion to the main agent: "The plugin's docs-agent has improved (project=<old>, plugin=<new>). Consider running `/docs-review` to re-audit `docs/guide/**` against the current codebase." After printing the suggestion, `/sync` writes the new version to `.bytewyrd/docs-agent-version` so subsequent runs do not re-prompt until the marker changes again. The decision to actually run `/docs-review` belongs to the main agent / user; `/sync` only nudges.

`/sync` does not auto-invoke `/docs-review` because (1) the existing `/sync` is documented as silent/idempotent except for the project-brief identity prompts, and (2) auto-invoking would chain expensive subagent work onto every `/sync` run, which is exactly the cost discipline the rest of the plugin enforces.

**Option B — Hash-compare the entire agent file content rather than rely on a maintained marker.**
A SHA-256 of the agent file is more accurate than a hand-maintained marker (the marker can be forgotten), but it is also too sensitive — a typo-fix commit changes the hash without changing the agent's behavior, prompting unnecessary review work. The maintained marker is the same trade-off the plugin already makes for `bootstrap-content-version` and is the established pattern.

**Option C — Use the plugin's `version` field in `plugin.json` as the trigger.**
Triggers on every plugin version bump, including bumps that only touch unrelated files. Too noisy.

**Recommendation: Option A.** It reuses the established `*-version` marker pattern from `bootstrap-content-version`, keeps `/sync` silent-by-default, and gives the maintainer a single line to update when the docs-agent definition gains a check that warrants a re-audit of existing docs.

## Drawbacks

- **Hook firing cost.** A `SubagentStop` hook matching `feature-engineer` fires every time that agent finishes, including invocations outside `/rfc-implement` (e.g., `/refactor`'s recommended-follow-ups). The hook body is a one-line echo, so the per-fire cost is negligible — but the visible noise (a reminder line in the transcript) can become wallpaper if `feature-engineer` is spawned often. **Mitigation:** the reminder text is short and actionable ("consider `/docs-review` if the change affects user-visible behavior"). If real-world use shows the noise outweighs the value, the hook can be narrowed to fire only when `SubagentStop` is also preceded by `/rfc-implement` in the same turn — but that adds the same complexity Decision 3 Option C was rejected for, so the simple version ships first.

- **Documentation-review false positives.** A `/docs-review` invocation against a recently-implemented feature may find "drift" that is intentional — the feature deliberately removed an old API surface, and the docs that referenced it are next to be deleted in a follow-up. The agent's drift detection cannot distinguish "outdated docs that need updating" from "outdated docs that are correctly being removed in a follow-up." **Mitigation:** the agent's report tags each drift finding with severity (broken example, missing reference, stale tutorial, gap with no doc); the human-approval gate before apply lets the user accept, defer, or reject each finding individually. The default is to defer rather than auto-apply, which is the same conservative posture `/refactor` takes.

- **Empty `docs/guide/` bootstrap problem.** The agent owns `docs/guide/**`, but the directory is currently empty. The first `/docs-review` invocation will be a near-pure-greenfield write rather than a drift correction. **Mitigation:** the protocol's Phase 1 (coverage audit) enumerates what tutorials / how-to guides / reference pages *should* exist (one per shipped skill, one per consumer-relevant agent, one getting-started tutorial, one contributor-onboarding page) and the plan reflects the gap as a "create these files" plan rather than an update plan. The agent populates the directory progressively across invocations; the first run does not need to fill the entire surface.

- **The `docs/guide/contributing.md` vs `docs/CONTRIBUTING.md` split is subtle.** Both files are about contributing; the distinction (`CONTRIBUTING.md` = narrow prerequisites/setup/quality gate/PR process; `guide/contributing.md` = extended onboarding tutorial walking through plugin anatomy, how to add a skill, how to add an agent) needs to be clearly conveyed in both files so neither bleeds into the other's scope. **Mitigation:** each file opens with a header comment stating its scope ("narrow ops reference" vs "extended onboarding"), and cross-links to the other. The agent's allow-list excludes `docs/CONTRIBUTING.md`, and `docs/CONTRIBUTING.md`'s post-commit hook (the existing `PostToolUse` reminder) does not mention `docs/guide/contributing.md`, so the two stay in their lanes.

- **`/sync` marker maintenance burden.** The `docs-agent-version` marker must be hand-updated when the agent definition changes meaningfully. Forgetting to bump it means consumer projects never re-audit their docs after a substantive agent improvement. **Mitigation:** the marker convention is identical to `bootstrap-content-version`, which already has the same discipline requirement; a follow-up could add a pre-commit check that warns when `agents/docs-agent.md` is staged without the marker being touched. Out of scope here.

- **No automated way to verify code examples in tutorials still compile/run.** The agent's drift detection reads code examples from the docs and checks them against the codebase by symbol presence (grep for the function/class name); it does not actually compile or execute them. **Mitigation:** out of scope for this RFC. A future enhancement could run a quoted-examples-from-docs extractor that pipes each fenced code block through the project's toolchain (`cargo check`, `tsc --noEmit`, `python -c`, etc.) — but that requires per-language wiring and is a separate problem worth its own RFC. The agent's report can flag "example references symbol `foo()` which does not exist in current codebase" via grep alone, which catches the most common drift case.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `agents/docs-agent.md` | New specialized agent — owns `docs/guide/**` plus the contributor section; explicit reject-list for the four already-owned files; embeds `docs-agent-version` marker for `/sync` drift detection. Replaces no existing agent (the upstream-vendored `documentation-writer.md` stays where it is for the general-purpose case). |
| Create | `skills/docs-review/SKILL.md` | New skill — instructs the main agent to spawn `bytewyrd:docs-agent` via the Agent tool with `model: "sonnet"`, passing the seven-phase documentation-review protocol (scope → coverage audit → drift detection → plan → approval gate → apply → report) as the agent prompt; accepts a free-form scope hint via `$ARGUMENTS`. |
| Create | `.claude-plugin/hooks/hooks.json` | New plugin-level hook configuration. Registers two echo-only reminder hooks: `SubagentStop` matching `feature-engineer` (suggests `/docs-review` after a feature lands), and `SessionStart` with the `compact` matcher (re-suggests `/docs-review` after compaction loses doc-review context, only fires if a recent `/rfc-implement` was visible in the pre-compact transcript — implemented as a one-line shell check on a sentinel file written by the `SubagentStop` hook). |
| Modify | `.claude-plugin/plugin.json` | Add `"hooks": "./.claude-plugin/hooks/hooks.json"` to the plugin manifest so Claude Code picks up the new hook entries when the plugin is enabled. |
| Modify | `skills/sync/SKILL.md` | Add Step 1.5 ("Detect docs-agent version drift") that reads the plugin's `docs-agent-version` marker from `$CLAUDE_PLUGIN_ROOT/agents/docs-agent.md` and the project's `.bytewyrd/docs-agent-version` file, prints a one-line suggestion if they differ, then writes the new version to the project file. Update the `bootstrap-content-version` marker at the top of the file to reflect the change. |
| Modify | `CLAUDE.md` (plugin root) | (1) Replace the existing "Documentation" row in the Agent delegation table to point to `docs-agent (via /docs-review)` for scoped user-facing docs work, and add a clarifying note that `documentation-writer` remains the general-purpose docs agent for ad-hoc work. (2) Add a "Considering /docs-review" subsection in the Workflow section explaining the manual-invocation heuristic and acknowledging the hook reminders. |
| Modify | `.gitignore` | Add `.bytewyrd/` to exclusion list so sentinel file and version marker are not committed |
| Create | `docs/guide/.gitkeep` | Placeholder so the empty directory is present after this RFC merges; the first `/docs-review` invocation populates the actual content. (Deleted automatically by the agent on first run as it writes real files into the directory.) |

No other agent files modified. No changes to the existing `documentation-writer.md` (it stays as the general-purpose docs agent). No new skills other than `docs-review`. No deletions.

### Steps

#### Step 1 — Create `agents/docs-agent.md`

Create the file with this exact content:

```markdown
---
name: docs-agent
description: Bytewyrd's specialized documentation agent. Owns user-facing docs under docs/guide/** (tutorials, how-to guides, reference pages, contributor onboarding). Does NOT touch docs/ARCHITECTURE.md, docs/CONTRIBUTING.md, docs/BEST_PRACTICES.md, docs/project-brief.md, docs/rfcs/**, docs/rfc-process.md, docs/rfc-braindump.md, or README.md — those files have separate owners. Spawn via the /docs-review skill, not directly.
model: sonnet
---

<!-- docs-agent-version: 2026-05-10-initial -->
<!-- This agent is owned locally by the bytewyrd plugin. See docs/rfcs/2026-05-10-documentation-agent-lifecycle-hooks.md. -->

You are the `docs-agent` for the bytewyrd plugin — a specialized documentation agent with a strict ownership boundary. You produce and maintain user-facing documentation under `docs/guide/**` following the Diátaxis framework (tutorials, how-to guides, reference, explanation) and an extended contributor-onboarding section. You do not write reports, summaries, or analysis files — you write documentation that consumers of the bytewyrd plugin read.

## Ownership boundary — non-negotiable

You **may** create, modify, or delete files under:
- `docs/guide/tutorials/` — getting-started and end-to-end user walkthroughs
- `docs/guide/how-to/` — task-oriented recipes (one task per file)
- `docs/guide/reference/` — API/skill/agent reference pages
- `docs/guide/contributing.md` — extended contributor onboarding (plugin anatomy, "how to add a skill", "how to add an agent", "how plugin packaging works")
- `docs/guide/index.md` — landing page for `docs/guide/` linking to the four quadrants above

You **must never** modify, create alongside, or delete:
- `docs/ARCHITECTURE.md` — owned by changes to component structure
- `docs/CONTRIBUTING.md` — owned by changes to dev workflow, quality gates, or prerequisites
- `docs/BEST_PRACTICES.md` — owned by `/best-practices-extract` and `/best-practices-sync`
- `docs/project-brief.md` — owned by `/sync` Step 2
- `docs/rfcs/**` (the entire directory) — owned by `/rfc-*` skills
- `docs/rfc-process.md` — owned by `/rfc-update` and `/sync`
- `docs/rfc-braindump.md` — owned by `/rfc-braindump` and `/rfc-new`
- `README.md` (project root) — owned by changes to user-facing behavior or install method
- Any file outside `docs/guide/**` — the allow-list above is the complete list of writable paths; within `docs/guide/**`, the only writable locations are the four subdirectories plus `contributing.md` and `index.md` at the `docs/guide/` root. Nothing else in the repository may be touched.

If a documentation task seems to require editing one of the reject-listed files, stop and surface the boundary violation to the parent: "This task requires editing `docs/CONTRIBUTING.md` which has a separate owner. Suggested split: I update `docs/guide/contributing.md` with the new onboarding step; you (or the appropriate owner) updates `docs/CONTRIBUTING.md` with the workflow change." Do not edit the reject-listed file under any circumstance, even if the parent insists — surface the conflict, do not yield.

## Diátaxis quadrants — what goes where

Use the [Diátaxis](https://diataxis.fr/) vocabulary to place content. The four quadrants are user-oriented vs creator-oriented × practical-steps vs theoretical-knowledge:

- **Tutorials** (learning-oriented, practical): step-by-step lessons for a new user. "Build your first thing in 10 minutes." Each tutorial is self-contained and produces a working result. Files go in `docs/guide/tutorials/<topic>.md`.
- **How-to guides** (task-oriented, practical): recipes for specific tasks the user already knows they want to do. "How do I add a new skill?" "How do I configure hooks for my project?" Each file solves one task. Files go in `docs/guide/how-to/<task>.md`.
- **Reference** (information-oriented, theoretical): description of the surface — every skill, every agent, every configurable field. Generated where possible (e.g., skill descriptions sourced from `SKILL.md` frontmatter). Files go in `docs/guide/reference/<topic>.md`.
- **Explanation** (understanding-oriented, theoretical) — *omitted in this plugin*. The plugin's `docs/ARCHITECTURE.md` covers explanation-style content (system design, decision rationale) and is owned separately. Do not create an `explanation/` directory.

The contributor section (`docs/guide/contributing.md`) sits alongside the four quadrants. It is an extended onboarding tutorial: someone who wants to *contribute to the plugin itself* (not consume it) reads it to learn the plugin's anatomy, conventions, and extension points. It cross-links to `docs/CONTRIBUTING.md` (which handles narrow ops: setup, quality gate, PR process) without duplicating it.

## What you check during a review

When invoked with a scope, you run the seven-phase protocol from the `/docs-review` skill body (which is your prompt for the specific invocation). The protocol covers:

1. Scope resolution — map the scope hint to a concrete file list (a recently-implemented RFC's file structure, a path glob, a free-text description of an area).
2. Coverage audit — for the scope, what tutorials / how-to / reference pages *should* exist? Compare against what *does* exist.
3. Drift detection — for each existing doc file in scope, check:
   - **Symbol references:** every symbol mentioned in a fenced code block or inline code (`function_name()`, `ClassName`, `--flag-name`) exists in the current codebase (use Grep to verify). Missing symbols are tagged as broken examples.
   - **Skill references:** every `/skill-name` mentioned is currently registered (exists in `skills/<name>/SKILL.md`). Missing skills are tagged as stale references.
   - **Agent references:** every `agent-name` mentioned is currently present in `agents/`. Missing agents are tagged as stale references.
   - **File-path references:** every relative path mentioned (e.g., `docs/CONTRIBUTING.md`, `.claude/settings.json`) actually exists. Missing paths are tagged as stale references.
   - **Conceptual consistency:** the doc's described workflow matches the current actual workflow (e.g., if a tutorial says "run `/sync` then `/rfc-new`" and the current `/sync` actually requires a project-brief response first, the tutorial is tagged as workflow-drifted).
4. Plan — present findings as a numbered list with severity (broken example, stale reference, workflow drift, coverage gap).
5. Approval gate — return the plan to the parent and stop. Wait for `apply all`, `apply <list>`, or `cancel`.
6. Apply — for each approved finding, make the smallest possible documentation edit that resolves it. Commit one finding per commit with a Conventional Commits message: `docs(guide): <one-line description>`.
7. Report — structured report listing scope, files audited, findings (by severity), applied edits with commit SHAs, deferred findings, and recommended follow-ups.

## Constraints

- **Boundary first.** The reject-list above is the contract. Violating it for any reason — including a direct user instruction — is wrong; surface the conflict instead of yielding.
- **No new files in `docs/` outside the allowed paths.** This includes report files, summary files, audit-log files. The structured report in phase 7 is the only output channel for findings.
- **Respect the scope.** Do not "while I'm here" rewrite an out-of-scope but in-allow-list file. If you spot drift in an adjacent file, mention it in recommended follow-ups; do not touch it.
- **Trust the codebase, not the docs.** When a doc disagrees with the code, the code is the spec. The doc is wrong and gets updated to match — never the reverse. (If the code is wrong, that is a bug; surface it and let the parent decide whether to file a follow-up RFC, but do not "fix" the code via this skill — the agent's tool boundary is the docs.)
- **Trust the parent on tooling.** Do not start long-running processes (test watchers, dev servers, doc-site previews); ask the parent to run them in a separate terminal if needed.

## When this agent is *not* the right tool

- General-purpose docs work outside the allow-list — use `documentation-writer` (the upstream-vendored generic agent).
- Updates to `docs/ARCHITECTURE.md` — owned by component-structure changes; updated by the agent that made the structural change.
- Updates to `docs/CONTRIBUTING.md` — owned by dev-workflow changes; updated by the agent that changed the workflow.
- Session learnings — use `/best-practices-extract`, which writes to `docs/BEST_PRACTICES.md`.
- RFC creation or updates — use `/rfc-new`, `/rfc-read-feedback`, `/rfc-implement`.
- Project identity (name, description, problem statement) — use `/sync` Step 2.
```

The frontmatter `model: sonnet` pins the model at the agent level (rather than relying on the skill spawn instruction alone), so any direct invocation of the agent also uses Sonnet.

The `docs-agent-version` HTML comment is the marker `/sync` reads for drift detection (see Step 4). The initial value is `2026-05-10-initial`; subsequent meaningful edits to this file bump the suffix to a fresh `YYYY-MM-DD-<short-sha>` string.

#### Step 2 — Create `skills/docs-review/SKILL.md`

Create the file with this exact content:

````markdown
---
name: docs-review
description: Run a scoped documentation review against the codebase. The skill instructs the main agent to spawn the docs-agent subagent on Sonnet, with a seven-phase protocol that audits docs/guide/** for drift (broken examples, stale references, workflow drift) and coverage gaps against the current code. Respects strict ownership — never touches ARCHITECTURE.md, CONTRIBUTING.md, BEST_PRACTICES.md, project-brief.md, or rfcs/. Use after a feature lands, when /sync reports the docs-agent has improved, or any time the user-facing docs may be out of step with the code. Triggered by "/docs-review [scope-hint]".
argument-hint: "[scope-hint]"
---

# /docs-review — Scoped Documentation Review

This skill runs in the main conversation. Its job is to spawn a `bytewyrd:docs-agent` subagent with the seven-phase documentation-review protocol below as the prompt, then relay the subagent's questions, plan, and final report back to the user.

## Step 1 — Capture scope

The invocation passed this scope hint:

```
$ARGUMENTS
```

If the scope hint is empty, ask the parent (the user or the agent that invoked this skill) one targeted question: "What scope should this documentation review cover? Options: (a) a recently-implemented RFC by identifier (e.g., `2026-05-10-foo`); (b) a path or area (`docs/guide/tutorials/`, `the auth module`); (c) `all` to audit the full `docs/guide/**` against the current codebase." Do not spawn the subagent without a scope.

The scope hint must also carry any non-obvious context the review needs (e.g., "this feature deprecated the `--legacy-flag`, so any doc still referencing it is correctly drifting — flag for removal, not update"). The subagent does not see the parent's history; if the parent expects the subagent to know something they discussed earlier, they must include it in the hint.

## Step 2 — Spawn the docs-agent subagent

Use the Agent tool to spawn a `bytewyrd:docs-agent` agent with:

- `model: "sonnet"`
- Prompt: the entire **Documentation review protocol** section below, with the scope hint substituted into the Scope block

The protocol is the agent's prompt. The agent definition supplies the ownership boundary, the Diátaxis vocabulary, and the constraints. The protocol below tells the agent how to apply that knowledge for this specific invocation.

The skill itself does not run the protocol — the spawned subagent does. While the subagent runs, the main agent's job is to relay any questions the subagent surfaces back to the user (especially during the Phase 5 approval gate) and to deliver the final Phase 7 report.

## Step 3 — Wait for the subagent's plan, get user approval, deliver to the subagent

The subagent will return a plan (Phase 4) and stop. Present the plan to the user verbatim and ask for one of:

- `apply all`
- `apply 1, 3, 5` (or any subset; grouped findings like `1a, 1b` apply together)
- `cancel`

Pass the user's response back to the subagent (resume the agent task with the response as input). The subagent will then apply the approved findings (Phase 6) and return the final report (Phase 7).

If the user requests changes to the plan ("merge findings 2 and 3", "skip finding 4", "add a check that does X"), pass the request to the subagent — the subagent revises and re-presents the plan, and the approval cycle repeats.

## Step 4 — Deliver the final report

When the subagent finishes (Phase 7), present the structured report to the user verbatim. The report includes the scope, files audited, findings by severity, applied edits with commit SHAs, deferred findings, and recommended follow-ups. The user decides what to do with the recommended follow-ups.

After presenting the report (whether the review ran successfully or the user cancelled), delete the sentinel file if it exists:

```bash
rm -f .bytewyrd/last-feature-engineer-stop
```

This prevents the `SessionStart compact` hook from re-echoing the reminder after the review has been completed or explicitly skipped. If the user wants to dismiss the reminder manually (without running `/docs-review`), they can run `rm -f .bytewyrd/last-feature-engineer-stop` directly.

---

# Documentation review protocol (passed as the subagent's prompt)

You are the `docs-agent` for a scoped documentation review. Your system prompt (the agent definition) gives you the ownership boundary, the Diátaxis vocabulary, and the constraints. This protocol is what you follow for this specific invocation.

## Scope

```
<SCOPE HINT FROM $ARGUMENTS>
```

The scope hint includes any non-obvious context from the parent conversation. You do not see the parent's history; treat the scope hint as the complete brief.

## Protocol — seven phases

### Phase 1 — Resolve scope

Map the scope hint to a concrete file list. The hint may reference:

- **An RFC identifier** (`2026-05-10-foo`): read `docs/rfcs/2026-05-10-foo.md`, extract the file structure table from its Implementation spec, and treat those files as the *codebase* scope (the source-of-truth surface to compare docs against). The *docs* scope is `docs/guide/**` files that mention any of the codebase scope's symbols, skills, agents, paths, or concepts (use Grep across `docs/guide/`).
- **A path or area** (`docs/guide/tutorials/`, `src/auth/`): if the path is under `docs/guide/`, that is the docs scope; the codebase scope is whatever those docs reference (resolved by reading each doc file and noting referenced symbols/skills/agents/paths). If the path is under source code, the codebase scope is that path; the docs scope is `docs/guide/**` files that mention any of the path's symbols.
- **A free-text description** (`the auth module`, `everything related to /refactor`): use Grep to locate matching files in both `docs/guide/` and the codebase; list both sets explicitly before proceeding.
- **`all`**: codebase scope is the whole project tree (excluding `docs/`, `.git/`, and `.worktrees/`); docs scope is the whole of `docs/guide/**`.

Print the resolved scope (both code and docs lists) before phase 2. If the lists are empty (docs scope has no files yet — likely on the first invocation against a fresh `docs/guide/` directory), proceed to phase 2 anyway; the coverage audit will identify which files *should* exist.

### Phase 2 — Coverage audit

For the codebase scope, determine what user-facing documentation *should* exist under `docs/guide/**`:

- **Tutorials:** if the scope includes a consumer-facing feature with a clear "first-time use" workflow, a tutorial should exist (`docs/guide/tutorials/<feature-or-skill>.md`).
- **How-to guides:** for each user-facing task the scope enables (e.g., "add a custom skill", "configure hooks for my project", "drop an unwanted RFC"), a how-to guide should exist (`docs/guide/how-to/<task>.md`).
- **Reference:** for each shipped skill (file under `skills/<name>/SKILL.md`), a reference page should exist (`docs/guide/reference/skills.md` or one file per skill — the agent picks the granularity based on the project's existing convention; default to a single `skills.md` for small skill counts, one-file-per-skill when count exceeds 15). Same for agents (`docs/guide/reference/agents.md`) and hooks (`docs/guide/reference/hooks.md`).
- **Contributor section:** `docs/guide/contributing.md` should exist and cover plugin anatomy, "how to add a skill," "how to add an agent," "how plugin packaging works." This file is created or extended by every review whose scope touches a new skill or agent.
- **Index:** `docs/guide/index.md` exists and links to the four sub-areas (tutorials, how-to, reference, contributing.md). Updated whenever a new file is added under `docs/guide/**`.

Compare the *should-exist* list against the *does-exist* list (using `ls docs/guide/**/*.md`). Coverage gaps are entries from the should-exist list that have no corresponding file. Tag each gap with `coverage-gap` severity.

### Phase 3 — Drift detection

For each file in the docs scope (the *does-exist* set under `docs/guide/`), run these checks:

- **Symbol references:** scan the file for fenced code blocks and inline code spans. For each named symbol (function names, class names, CLI flags, environment variables), Grep the codebase for the symbol's definition. Missing symbols are tagged as `broken-example` severity.
- **Skill references:** for each `/skill-name` mentioned in prose or code, check that `skills/<name>/SKILL.md` exists (or `.claude/skills/<name>/SKILL.md` for plugin-local skills). Missing skills are tagged as `stale-reference` severity.
- **Agent references:** for each `agent-name` mentioned in prose or code, check that `agents/<name>.md` exists. Missing agents are tagged as `stale-reference` severity.
- **File-path references:** for each relative path mentioned (e.g., `docs/CONTRIBUTING.md`, `.claude/settings.json`, `agents/foo.md`), check that the file exists at that path. Missing paths are tagged as `stale-reference` severity.
- **Workflow drift:** read the doc's described workflow (typically the first numbered list or `## Quick start` section) and compare it to the actual current workflow inferred from the matching skill's `SKILL.md`. If the doc says "run X then Y" and the current skill says "run X, answer prompt, then Y," tag as `workflow-drift` severity.

Each finding records: file, line range (if specific), severity, what is wrong, and what the fix would be (one line).

### Phase 4 — Plan

Produce a refactoring-style plan as a numbered list. Each item is one finding:

```
Documentation review plan for <scope>:

1. <severity>: <one-line description>
   File: <path> (line <range> if applicable)
   Current: <what the doc says>
   Should be: <what the doc should say given the codebase>
   Risk: <low | medium | high> — <why; usually low for docs work>

2. <severity>: <one-line description>
   ...
```

Group related findings when they cannot be cleanly separated (e.g., "two broken examples in the same tutorial fixed by updating one shared variable name"). Number bundled findings as `1a, 1b, 1c` so the parent can approve or skip the group as a unit.

Order findings by severity (`broken-example` first, then `stale-reference`, then `workflow-drift`, then `coverage-gap`). Within a severity, order by file path alphabetically for predictable review.

If a finding is ambiguous ("the doc says `--foo`, the codebase has both `--foo` and `--foo-bar`; unclear which the doc means"), include both interpretations in the finding's `Should be:` line and let the parent decide.

### Phase 5 — Approval gate (mandatory)

Return the plan to the parent and stop. The parent (the main agent or the user) reviews the plan and decides which findings to apply. Do not proceed to phase 6 until the parent responds with one of:

- `apply all` — proceed with every finding in order
- `apply 1, 3, 5` — proceed with the listed finding numbers in order (grouped findings like `1a, 1b` apply together when the group number is listed)
- `cancel` — stop; proceed to phase 7 to report findings without applying any

If the parent asks clarifying questions, answer them. If the parent requests changes to the plan ("merge findings 2 and 3", "skip finding 4", "the broken example in finding 1 is correct — the symbol is being deprecated"), revise the numbered list and re-present, then wait for a new approval response.

This gate is non-negotiable. The agent does not auto-apply documentation changes even when the changes look mechanical.

### Phase 6 — Apply

For each approved finding, in the order the parent listed them:

1. Apply the smallest possible documentation edit that resolves the finding. Do not "while I'm here" rewrite surrounding content.
2. If the finding is a coverage gap (a file that should exist but does not), create the file with content appropriate to its Diátaxis quadrant (tutorial / how-to / reference / contributing).
3. Verify the edit by re-running the relevant check from phase 3 against the updated file. The check should now pass.
4. Commit the finding. Use a Conventional Commits message: `docs(guide): <one-line description from the plan>` — one commit per approved finding (or per approved group when findings were bundled as `1a, 1b, 1c`).
5. If `docs/guide/.gitkeep` exists and this is the first real file being committed to `docs/guide/`, include its deletion in the same commit as the first file (not a separate commit).
6. Move to the next approved finding.

If a finding turns out to be larger or riskier than the plan estimated (e.g., fixing one stale reference requires restructuring the surrounding section to maintain coherence), stop and re-present the revised finding to the parent before continuing.

### Phase 7 — Report

After all approved findings are applied (or after `cancel` was received), return a structured report:

```
Documentation review complete.

Scope (code): <files in code scope>
Scope (docs): <files in docs scope>
Files audited: <count>
Findings by severity:
  broken-example: <count> (<one-line summary>)
  stale-reference: <count> (<one-line summary>)
  workflow-drift: <count> (<one-line summary>)
  coverage-gap: <count> (<one-line summary>)
Findings applied: <numbered list with commit SHAs>
Findings deferred: <list with reason>
Recommended follow-up: <one or two sentences, or "none">
```

Do not edit the report after returning it. The parent decides what to do with the recommended follow-ups.

## Constraints (inherited from the agent definition; restated here for clarity)

- **Ownership boundary first.** Never edit `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, `docs/rfcs/**`, `docs/rfc-process.md`, `docs/rfc-braindump.md`, or `README.md`. If a finding seems to require editing one of these, surface the boundary violation in the plan with a suggested split.
- **Trust the codebase.** When code and docs disagree, the code is the spec; the doc gets updated. Never edit code from this skill.
- **One commit per finding.** Bundling unrelated findings into one commit destroys reviewability.
- **Respect the scope.** Do not audit files outside the resolved scope. Mention adjacent-scope drift in recommended follow-ups.
- **Do not start long-running processes.** Doc-site previews, watchers — ask the parent to run them in a separate terminal if needed.

## When this skill is *not* the right tool

- Updating `docs/ARCHITECTURE.md` — that file is owned by changes to component structure. The agent that made the structural change updates it.
- Updating `docs/CONTRIBUTING.md` — owned by changes to dev workflow or quality gates. The agent that made the workflow change updates it.
- Capturing a session learning — use `/best-practices-extract` (writes to `docs/BEST_PRACTICES.md`).
- Creating or updating an RFC — use `/rfc-new`, `/rfc-read-feedback`, `/rfc-implement`.
- Updating project identity (name, description, problem) — use `/sync` Step 2.
- General-purpose docs writing outside `docs/guide/**` — use the `documentation-writer` agent directly.
````

#### Step 3 — Create `.claude-plugin/hooks/hooks.json`

Create the hooks configuration with this exact content:

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
          }
        ]
      }
    ]
  }
}
```

The matcher `(^|:)feature-engineer$` is a regex (it contains `(`, `^`, `$`) so Claude Code evaluates it as a regular expression per the matcher rules ("Contains any other character" → JS regex). It matches both the bare agent name `feature-engineer` (when spawned without a plugin namespace prefix) and the plugin-namespaced form `bytewyrd:feature-engineer` (when spawned from the bytewyrd plugin's skills, as `/rfc-implement` does). This handles both invocation paths Claude Code may surface to hook matchers.

The two `SubagentStop` hook handlers fire in order: the first prints the reminder; the second touches a sentinel file (`: > path` is a portable empty-file create-or-truncate idiom that works in any POSIX shell without spawning a child process). The `SessionStart` hook (matcher `compact`) is a new pattern this RFC introduces — Claude Code's `SessionStart` event supports a `compact` matcher that fires only on the compaction-resume path; the project's existing `.claude/settings.json` uses an unmatched `SessionStart` hook (no matcher field) for bootstrap version drift, which is a different invocation path. The hook reads the sentinel's mtime portably via GNU `stat -c %Y` with a BSD `stat -f %m` fallback, validates the result is numeric by matching `^[0-9]+$`, and sets `SENTINEL_AGE` to a large value (`999999`) when the mtime is empty or non-numeric — this handles the case where both `stat` invocations fail (unsupported platform, missing file, permission error) and suppresses the reminder rather than firing a false-positive. The sentinel is gitignored (Step 6 adds `.bytewyrd/` to `.gitignore` if not already excluded).

Both hooks are echo-only. They never modify project files, never invoke skills automatically, and never block anything. They are reminders surfaced into the agent's context — the same echo-only pattern the existing `.claude/settings.json` hooks use for `git commit`, `PreCompact`, `SessionStart` (bootstrap version drift, no matcher), and `Stop` (session-end checklist). The `SessionStart` `compact` matcher is the one new mechanism this RFC introduces; it is a documented Claude Code feature, not an existing project convention.

#### Step 4 — Modify `.claude-plugin/plugin.json`

The current file is:

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

Add a `"hooks"` field pointing to the new hooks file. The full file after this step:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  },
  "hooks": "./.claude-plugin/hooks/hooks.json"
}
```

No `skills` array is added — skills are auto-discovered from `skills/` and the project does not currently use an explicit registration array (the RFC `2026-05-10-refactor-command`'s spec described an aspirational `skills` array, but the actual current `plugin.json` has none and auto-discovery works fine). If a future RFC introduces explicit registration, this RFC's `hooks` field stays unaffected.

#### Step 5 — Modify `skills/sync/SKILL.md`

Add a new step **"Step 1.5 — Detect docs-agent version drift"** between the existing Step 1 (validate environment) and Step 2 (gather project identity). The new step:

```markdown
## Step 1.5 — Detect docs-agent version drift

Read the plugin's `docs-agent-version` marker from `$CLAUDE_PLUGIN_ROOT/agents/docs-agent.md`:

```bash
PLUGIN_DOCS_VER=$(grep -m1 'docs-agent-version:' "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/agents/docs-agent.md" 2>/dev/null | sed -E 's/.*docs-agent-version: ([^ ]+).*/\1/')
```

Read the project's recorded marker from `.bytewyrd/docs-agent-version`:

```bash
PROJECT_DOCS_VER=$(cat .bytewyrd/docs-agent-version 2>/dev/null || echo "")
```

If `PLUGIN_DOCS_VER` is non-empty and differs from `PROJECT_DOCS_VER` (including the case where `PROJECT_DOCS_VER` is empty because the file does not exist yet), print this suggestion to the agent's output:

```
The plugin's docs-agent has improved (project=<PROJECT_DOCS_VER>, plugin=<PLUGIN_DOCS_VER>). Consider running /docs-review against docs/guide/** to re-audit user-facing documentation with the updated checks.
```

Then record the new version so subsequent sync runs do not re-prompt until the marker changes again. Only write the marker if `PLUGIN_DOCS_VER` is non-empty (guard with `[ -n "$PLUGIN_DOCS_VER" ]`) to prevent overwriting a valid marker with an empty string when the plugin's agent file is unreachable.

```bash
mkdir -p .bytewyrd
echo "$PLUGIN_DOCS_VER" > .bytewyrd/docs-agent-version
```

Do **not** auto-invoke `/docs-review` — `/sync` only prints the suggestion. The decision to run the review belongs to the main agent or the user.

If `PLUGIN_DOCS_VER` is empty (the plugin's `agents/docs-agent.md` does not yet exist or does not carry the marker), skip this step silently — the plugin may be on a version that predates this feature.
```

Bump the `bootstrap-content-version` marker at the top of `skills/sync/SKILL.md` from its current `2026-05-10-f7d5384` (or whatever it currently is) to a new `YYYY-MM-DD-<short-sha>` value when this RFC's PR is merged. The actual SHA suffix is filled in by the merge commit; use a placeholder of `2026-05-10-pending` during the PR and replace it just before merge.

The new step inherits the same silent-by-default discipline as the existing version-drift checks: it only prints when the markers differ, and writing the new project file silences subsequent runs until the plugin's marker changes again.

#### Step 6 — Modify `CLAUDE.md` (plugin root)

Two changes to `/home/divoxx/code/bytewyrd/claude-bytewyrd-workflow/CLAUDE.md`:

**Change 6a — Agent delegation table.**

The current table is:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Debugging | debugger |
```

Replace the "Documentation" row with two rows — one for scoped guide work (the new agent), one for ad-hoc general-purpose docs work (the existing agent). The table becomes:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
| Architecture / RFCs | rfc-architect |
| User-facing docs (`docs/guide/**`) | docs-agent (via `/docs-review`) |
| General-purpose docs (ad-hoc) | documentation-writer |
| Debugging | debugger |
```

The two rows make the split visible: `docs-agent` for the scoped, ownership-bounded surface; `documentation-writer` for anything outside that boundary (and `documentation-writer` is the vendored upstream agent — unchanged by this RFC).

**Change 6b — Workflow section.**

Insert a new subsection in the "Workflow" block, between `### During work` and `### Session end`:

```markdown
### Considering /docs-review

Run `/docs-review <scope-hint>` when:

- A `/rfc-implement` just landed user-visible changes (a new skill, an agent change, a new flag, a new workflow) — check whether `docs/guide/**` needs updates to match. (A `SubagentStop` hook on `feature-engineer` surfaces a reminder at this moment.)
- `/sync` reports the docs-agent definition has improved — re-audit `docs/guide/**` with the updated checks.
- A user reports a tutorial does not work, a how-to guide references a missing flag, or a reference page is out of date.
- Before a release — sweep `docs/guide/**` to confirm no broken examples or stale references ship to users.

`/docs-review` spawns the `docs-agent` subagent on Sonnet. It is scoped strictly to `docs/guide/**` and the contributor section — it never touches `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `docs/project-brief.md`, or anything under `docs/rfcs/`. Those files have separate owners.

The skill enforces a seven-phase protocol: resolve scope → coverage audit → drift detection → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific findings, and the subagent applies them one commit at a time.
```

Add `.bytewyrd/` to the project's `.gitignore` if it is not already excluded (the sentinel file `.bytewyrd/last-feature-engineer-stop` and the version marker `.bytewyrd/docs-agent-version` are both gitignored per the Decision 4 spec). Check with:

```bash
grep -q '^\.bytewyrd/' .gitignore || echo '.bytewyrd/' >> .gitignore
```

The directory is local-state-only — it is not part of the project's committed history.

#### Step 7 — Create `docs/guide/.gitkeep`

Create an empty file at `docs/guide/.gitkeep` so the directory is present in the committed tree:

```bash
touch docs/guide/.gitkeep
```

The first `/docs-review` invocation against this project deletes `.gitkeep` once it writes the first real file into `docs/guide/`. The agent's apply phase explicitly handles this cleanup (Phase 6 sub-step 5).

#### Step 8 — Verification

After all changes, run these checks:

1. **Agent file exists with correct frontmatter:**

   ```bash
   test -f agents/docs-agent.md && head -8 agents/docs-agent.md
   ```

   Expected output (first 8 lines):

   ```
   ---
   name: docs-agent
   description: Bytewyrd's specialized documentation agent. Owns user-facing docs under docs/guide/** (tutorials, how-to guides, reference pages, contributor onboarding). Does NOT touch docs/ARCHITECTURE.md, docs/CONTRIBUTING.md, docs/BEST_PRACTICES.md, docs/project-brief.md, docs/rfcs/**, docs/rfc-process.md, docs/rfc-braindump.md, or README.md — those files have separate owners. Spawn via the /docs-review skill, not directly.
   model: sonnet
   ---

   <!-- docs-agent-version: 2026-05-10-initial -->
   <!-- This agent is owned locally by the bytewyrd plugin. See docs/rfcs/2026-05-10-documentation-agent-lifecycle-hooks.md. -->
   ```

2. **Skill file exists with the argument hint:**

   ```bash
   test -f skills/docs-review/SKILL.md && grep -m1 '^argument-hint:' skills/docs-review/SKILL.md
   ```

   Expected output:

   ```
   argument-hint: "[scope-hint]"
   ```

3. **Hook file exists and is valid JSON:**

   ```bash
   test -f .claude-plugin/hooks/hooks.json && python3 -m json.tool .claude-plugin/hooks/hooks.json > /dev/null && echo ok
   ```

   Expected output: `ok`

4. **Plugin manifest references the hook file:**

   ```bash
   grep -F '"hooks": "./.claude-plugin/hooks/hooks.json"' .claude-plugin/plugin.json
   ```

   Expected output:

   ```
     "hooks": "./.claude-plugin/hooks/hooks.json"
   ```

5. **Sync skill has the new step:**

   ```bash
   grep -F '## Step 1.5 — Detect docs-agent version drift' skills/sync/SKILL.md
   ```

   Expected output:

   ```
   ## Step 1.5 — Detect docs-agent version drift
   ```

6. **CLAUDE.md table includes both rows:**

   ```bash
   grep -F 'docs-agent (via `/docs-review`)' CLAUDE.md
   grep -F 'General-purpose docs (ad-hoc)' CLAUDE.md
   ```

   Expected output:

   ```
   | User-facing docs (`docs/guide/**`) | docs-agent (via `/docs-review`) |
   | General-purpose docs (ad-hoc) | documentation-writer |
   ```

7. **CLAUDE.md workflow section includes the /docs-review guidance:**

   ```bash
   grep -F '### Considering /docs-review' CLAUDE.md
   ```

   Expected output:

   ```
   ### Considering /docs-review
   ```

8. **`.gitignore` excludes the sentinel directory:**

   ```bash
   grep -q '^\.bytewyrd/' .gitignore && echo ok
   ```

   Expected output: `ok`

9. **`docs/guide/.gitkeep` exists:**

   ```bash
   test -f docs/guide/.gitkeep && echo ok
   ```

   Expected output: `ok`

10. **Manual smoke test (after Claude Code restart with the updated plugin):**

    - Type `/` in Claude Code; confirm `/docs-review` appears in the autocomplete menu with the `[scope-hint]` argument hint.
    - Run `/docs-review all` against this plugin's own checkout. Confirm the docs-agent subagent spawns on Sonnet, runs phase 1 (resolve scope: codebase = full project tree excluding `docs/`/`.git/`/`.worktrees/`; docs = empty `docs/guide/**`), and phase 2 (coverage audit identifies missing tutorials/how-to/reference/contributing files), then presents the plan and waits at the approval gate.
    - Approve a small subset (e.g., `apply 1, 2` — create the index and one reference page). Confirm each approved finding lands as a separate commit with a `docs(guide):` Conventional Commits message.
    - Confirm `.gitkeep` is deleted after the first real file is created in `docs/guide/`.
    - Run `/rfc-implement` against any approved Draft RFC. Before doing so, temporarily add a debug command to the `SubagentStop` hook in `.claude-plugin/hooks/hooks.json` as the first hook entry: `{ "type": "command", "command": "echo 'hook fired at ' $(date) >> /tmp/hook-debug.log" }`. After `feature-engineer` finishes, inspect `/tmp/hook-debug.log` to confirm the hook fired. Also confirm `.bytewyrd/last-feature-engineer-stop` was created. If the log is empty, the matcher did not match — re-read Claude Code's hook documentation and adjust the matcher pattern. Remove the debug hook entry before committing.
    - Re-run `/sync`. Confirm Step 1.5 runs silently (the version is unchanged from the just-recorded value); manually bump the marker in `agents/docs-agent.md` to `2026-05-10-initial-2`, run `/sync` again, and confirm the suggestion line appears.

    If any of these steps fail, the issue is most likely (in order): (a) the agent's frontmatter `model: sonnet` is missing or mistyped (subagent falls back to whatever Sonnet alias the session uses), (b) the hook file path in `plugin.json` does not match the file's actual location (Claude Code silently ignores missing hook files), (c) the `SubagentStop` matcher regex does not match the namespaced form Claude Code surfaces (verify by adding `echo "matched: $CLAUDE_HOOK_MATCHED" >> /tmp/hook-debug.log` to the hook command and inspecting what Claude Code passed), (d) `.bytewyrd/` is not in `.gitignore` and the sentinel file accidentally got committed.

## Risks and open questions

- **Risk: hook reminder fatigue.** The `SubagentStop` hook on `feature-engineer` fires after every implementation of an approved RFC. If `/rfc-implement` is used frequently and most RFCs do not affect user-facing behavior (e.g., refactoring RFCs, internal-only changes), the reminder becomes noise. **Mitigation:** the reminder text explicitly says "if this feature affects user-visible behavior" so the main agent can decide to ignore it for internal-only changes. If real-world use shows the reminder is consistently ignored even when relevant, a follow-up could refine the trigger (e.g., a `PostToolUse` matching `mcp__plugin_github_github__create_pull_request` so the reminder fires only when the work actually lands as a PR), but that adds the complexity Decision 3 Option C avoided.

- **Risk: matcher name format unverified.** The `SubagentStop` matcher uses a regex `(^|:)feature-engineer$` to handle both bare (`feature-engineer`) and plugin-namespaced (`bytewyrd:feature-engineer`) forms because Claude Code's docs example the matcher field as "agent type" with examples like `general-purpose`, `Explore`, `Plan`, or custom agent names — without specifying how plugin namespacing surfaces. **Mitigation:** the regex form covers both candidates; if Claude Code surfaces yet another form (e.g., the file basename without an extension), the verification step 10's debug snippet (`echo "matched: $CLAUDE_HOOK_MATCHED"`) reveals it and the regex extends to a third alternative. The hook is echo-only, so a non-firing matcher costs only the loss of a reminder, not a broken workflow.

- **Risk: `docs-agent` violates its own boundary under prompt pressure.** A user who really wants the agent to update `docs/CONTRIBUTING.md` ("just fix it for me, please") may attempt to override the boundary. The agent's instructions say "surface the conflict, do not yield," but LLM agents are known to capitulate to insistent users. **Mitigation:** the agent's frontmatter description explicitly enumerates the reject-list so the boundary is visible at spawn time; the protocol's apply phase only writes to files in the allow-list (which can be enforced by structuring the protocol's apply step as "for each allowed-path file in the plan, edit it" — files outside the allow-list are not in the plan because phase 4 would have surfaced them as boundary violations in the plan presentation). A follow-up could add a `PreToolUse` hook scoped to the docs-agent that blocks `Edit|Write` on reject-listed paths, but that requires Claude Code to support agent-scoped hooks (uncertain — see Risks).

- **Open question: are agent-scoped hooks supported?** Claude Code's hooks system uses `matcher` patterns on tool names (`Edit`, `Write`) but does not document a way to scope a hook to a specific spawning agent. If they are supported, a `PreToolUse` hook with `matcher: "Edit|Write"` and an `if` condition matching the reject-listed paths could provide a defense-in-depth enforcement of the boundary on top of the agent's instruction-level enforcement. **Resolution within this RFC:** rely on instruction-level enforcement only. The reject-listed files are short and the agent's description prominently lists them; instruction adherence is the same level of trust the rest of the plugin's agents operate under. A follow-up can add a hook-based defense once the Claude Code hook scoping behavior is verified.

- **Open question: how does `/docs-review` interact with `/refactor`?** A `/refactor` invocation may rename symbols that appear in `docs/guide/**` examples — the docs are now drifted, and `/refactor`'s report should ideally mention this. The current `/refactor` skill (from RFC `2026-05-10-refactor-command`) does not invoke `/docs-review`. **Resolution within this RFC:** out of scope. A follow-up could either (a) add a recommended-follow-up to `/refactor`'s report that suggests `/docs-review` when the refactor changed any symbol that grep finds referenced in `docs/guide/`, or (b) add a `SubagentStop` hook matcher for `refactoring-specialist` (the agent `/refactor` spawns), mirroring this RFC's `feature-engineer` matcher. Both are small additions but belong in their own RFC because they touch `/refactor`'s reporting surface or add a third hook handler.

- **Risk: `.bytewyrd/last-feature-engineer-stop` sentinel lifecycle.** If a user installs the plugin into an existing project, runs nothing, then runs `/sync` for the first time, the `SessionStart compact` hook checks for a sentinel that does not exist and silently does nothing — which is the correct behavior. The sentinel is deleted by the `/docs-review` skill's Step 4 when the review completes or is cancelled, so repeated compact-resume sessions after a completed review do not re-echo. For the case where a project was actively using `/rfc-implement` and then was idle for 25+ hours, the sentinel ages out beyond the 24-hour threshold and the reminder is silently dropped — this is acceptable because the docs drift risk diminishes with time. **Mitigation:** the 24-hour threshold is tunable in the hook command (the `86400` literal); a follow-up could raise it to 7 days if real-world use shows 24 hours is too tight. Manual dismiss: `rm -f .bytewyrd/last-feature-engineer-stop`.

- **Open question: should there be a docs-agent-version field in `plugin.json` so the version is centrally managed rather than embedded in the agent file?** Centralized versioning would make bulk updates easier (one place to change), but it decouples the version from the file it describes (changes to the agent file no longer prompt the maintainer to bump the version). **Resolution within this RFC:** keep the marker embedded in the agent file. It matches the established `bootstrap-content-version` pattern and keeps the version visually adjacent to the content it tracks.

- **Risk: `stat` flag portability between GNU (Linux) and BSD (macOS).** The `SessionStart compact` hook reads the sentinel's mtime via `stat -c %Y` (GNU) with a fallback to `stat -f %m` (BSD); both forms are tried in order via `||` chaining. The result is captured into `MTIME` and validated as numeric before arithmetic. If both `stat` invocations fail on an existing file (permission denied, broken filesystem) or return a non-numeric value, `SENTINEL_AGE` is set to a large value (999999) and the reminder is suppressed rather than falsely firing. This fail-silent posture is safer than the earlier fallback-to-now behavior, which would have produced false-positive reminders. The mtime approach also avoids the `date -u -d` GNU-only parser, which was the issue in an earlier iteration of this hook.

## Relationship to other RFCs

This RFC builds on infrastructure established by prior RFCs and is sibling to in-flight ones:

- **`2026-05-10-refactor-command`** (status: Done) — established the "skill that spawns a model-pinned subagent with a structured protocol" pattern, including the plan-then-approval-then-apply gate. `/docs-review` is a direct application of that pattern to documentation work; the seven-phase protocol mirrors `/refactor`'s six-phase protocol with one extra phase (coverage audit) that has no `/refactor` analog because refactoring is bounded to existing code while documentation may require creating new files. Future work that adds new "skill spawns specialist subagent with approval gate" entry points should follow the shape both RFCs share.
- **`2026-05-10-project-brief-sync-source-of-truth`** (status: Done) — established `docs/project-brief.md` as the single source of truth for project identity, with `/sync` Step 2 as the gatekeeper. This RFC's Step 5 extends `/sync` with a new Step 1.5 (docs-agent version drift) that runs before Step 2; the two steps do not conflict (Step 1.5 is silent unless the marker differs; Step 2 only fires for identity gaps). The `bootstrap-content-version` pattern reused by Step 5 was implicitly established by the same RFC's evolution of the sync skill.
- **`2026-05-10-best-practice-extraction-principles`** (status: Done, per the file list) — established the ownership of `docs/BEST_PRACTICES.md` via `/best-practices-extract` and `/best-practices-sync`. This RFC's reject-list reinforces that ownership: `docs-agent` never touches `BEST_PRACTICES.md`. The two skills are orthogonal and do not interact.
- **`/rfc-implement` skill** — invokes `feature-engineer`. This RFC's `SubagentStop` hook on `feature-engineer` adds a downstream reminder; the existing skill is not modified. If a future RFC changes `/rfc-implement` to spawn a different agent name, this RFC's hook matcher would need to be updated correspondingly — a one-line change in `hooks.json`.
- **Future RFC: `docs-review` follow-ups (not yet drafted).** The Risks section identifies several follow-ups that belong in their own RFCs: agent-scoped hook enforcement of the reject-list; `/refactor` → `/docs-review` cross-skill recommendation; code-example execution verification (compiling examples against the codebase rather than just grepping symbols). None block this RFC; all sharpen the docs review surface incrementally.
