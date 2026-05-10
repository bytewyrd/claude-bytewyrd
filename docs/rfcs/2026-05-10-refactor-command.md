---
rfc: "2026-05-10-refactor-command"
title: "/refactor Command for Explicit Refactoring Subagent"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add a `/refactor` slash command (implemented as a plugin skill) that spawns a dedicated refactoring subagent running on Opus with `effort: max`. The skill runs `context: fork` against the existing `refactoring-specialist` agent so refactoring work happens in an isolated context window driven by a structured, multi-phase prompt rather than the parent conversation. The main agent — or the user — invokes `/refactor` with a scope hint (recent PR diff, files about to be touched by an in-flight RFC implementation, a specific module path) and the subagent produces a refactoring plan first, applies safe transformations only after approval, and reports back what changed and what tests now cover. The intent is to make refactoring a first-class, deliberately-invoked step rather than something that gets tacked onto feature work, while keeping the heavyweight model and `max` effort reserved for genuine refactor passes.

## Should we do this?

**Yes.** Refactoring quality is bimodal: ad-hoc cleanup tacked onto a feature commit consistently misses the structural problems that motivated the cleanup in the first place, while a deliberate "today I am refactoring" pass — with characterization tests, small steps, and behavior-preservation checks — produces lasting improvements. The plugin already ships the `refactoring-specialist` agent (vendored from VoltAgent), but it has no skill front door, no opinionated trigger, and no documented protocol for "main agent decided this code needs work before we touch it for a feature." A thin skill wrapper that (1) makes the trigger one keystroke (`/refactor`), (2) pins Opus + `max` effort exactly when needed (and *only* when needed), (3) forks into the specialist's own context so the parent conversation isn't flooded with characterization-test noise, and (4) enforces a plan-then-apply protocol with explicit user approval before mutations is the missing piece that turns the existing agent into a usable workflow. Cost is one new skill file plus one plugin-manifest edit; payoff is making refactoring an option the main agent actually reaches for during feature planning instead of an afterthought during code review.

## Current state

The plugin currently exposes refactoring capability through one piece — the `refactoring-specialist` agent at `agents/refactoring-specialist.md` — and that piece is invoked only when the main agent independently decides to delegate to it. There is no slash command, no opinionated trigger surface, and no protocol governing how a refactoring pass should be scoped, planned, or applied.

**What exists today:**

- `agents/refactoring-specialist.md` — a 293-line agent definition vendored from VoltAgent's `awesome-claude-code-subagents` library. It has comprehensive domain coverage (smell detection catalog, refactoring catalog, advanced patterns, safety practices, automated refactoring with `ast-grep` / `semgrep`, test-driven refactoring, performance refactoring, architecture refactoring, code metrics, legacy-code handling). Its `tools:` field lists `ast-grep, semgrep, eslint, prettier, jscodeshift` — an aspirational set that does not match the tools Claude Code actually surfaces in this plugin's environment. The agent has no `model:` or `effort:` fields, so it inherits whatever the parent session is using — typically Sonnet at the default effort, which is the wrong default for a structural refactoring pass that needs deep reasoning about cross-cutting changes.
- `agents/code-reviewer.md` — adjacent agent for code review, also vendored from the same upstream. Used today as the default reviewer in the RFC consensus pipeline.
- `agents/feature-engineer.md` — the agent that implements approved RFCs. It practices TDD and SOLID but does not own the "refactor before touching this code" workflow as a distinct phase.
- `skills/` — twelve skills exist today, all noun-first by convention (`best-practices-extract`, `best-practices-record`, `git-branch-cleanup`, `rfc-approve`, `rfc-braindump`, `rfc-consensus-review`, `rfc-drop`, `rfc-implement`, `rfc-new`, `rfc-read-feedback`, `rfc-update`, `sync`). None target refactoring. None spawn a subagent via `context: fork` (the closest pattern is `rfc-consensus-review`, which spawns five `code-reviewer` agents in parallel via the Task tool from inside the main conversation).
- `.claude-plugin/plugin.json` — registers the twelve skills under `skills:`. No registration for any refactoring entry point.
- `CLAUDE.md` "Agent delegation" table maps task → agent. The current row for refactoring-adjacent work routes through `feature-engineer` for new features and `code-reviewer` for reviews; there is no explicit "refactoring → refactoring-specialist" row, even though that agent is shipped in the plugin. The Model Usage Optimization section says `opus` is for "complex multi-step problem solving, ambiguous or novel tasks where the problem space itself is unclear" — refactoring fits that bucket but has no skill-level opinion forcing the upgrade.
- `README.md` — install and usage entry point. Does not currently document any version requirement related to forked subagents (`context: fork` is a Claude Code v2.1.117+ feature, currently flagged experimental).

**What is broken or missing:**

1. **No discovery surface.** A user (or the main agent) reading the available `/`-commands sees `/rfc-new`, `/rfc-implement`, etc., but nothing that names refactoring. The agent file exists but there is no UX path that says "run a refactoring pass." Without a slash command, the agent only gets used when the main conversation's heuristics happen to match the agent's autoload `description` — unreliable.
2. **No opinionated model/effort pinning.** Refactoring needs Opus + high or max effort. The current agent inherits whatever model the session is on, which is typically Sonnet during feature work. This silently downgrades the quality of refactoring proposals to "things Sonnet noticed in two paragraphs of context" rather than "structural improvements Opus reasoned through with extended thinking on the full module."
3. **No context isolation.** When refactoring is folded into a feature session, the parent conversation accumulates characterization-test output, candidate refactor diffs, and rollback discussion — context that is irrelevant once the refactor is done. A subagent context that returns only the structured summary keeps the parent conversation focused on the feature.
4. **No phase discipline.** The vendored agent's prompt describes a workflow ("Code Analysis → Implementation Phase → Code Excellence") but does not enforce a "produce plan, get approval, then apply" gate. Without the gate, a `/refactor` invocation can immediately start mutating files, which is the opposite of what a deliberate refactoring pass requires.
5. **No proactive trigger guidance.** The current architecture has nothing that nudges the main agent to consider running a refactoring pass *before* a feature implementation begins. The braindump entry calls this out explicitly: refactoring should be something the main agent can pre-emptively invoke when it would be beneficial — e.g., "the area I'm about to touch has thin test coverage, let me run `/refactor` to add characterization tests first" or "the module I'm about to extend has a fat conditional that the new behavior will make worse, let me refactor that first." Today there is no skill or convention for this.

The plugin's other workflow skills demonstrate the pattern this RFC follows: opinionated, small-surface skills that pin model/effort, fork into a specialist agent's context, and enforce a multi-step protocol. `/refactor` fills the same shape for refactoring work.

## Analysis / Options

There are three coupled decisions: how to expose the refactoring entry point, how to govern when the heavyweight model gets used, and how to enforce the plan-before-apply protocol.

### Decision 1 — How is `/refactor` implemented?

**Option A — Skill with `context: fork` against `refactoring-specialist` (recommended).**
Add `skills/refactor/SKILL.md` with `context: fork`, `agent: refactoring-specialist`, `model: opus`, `effort: max`, `disable-model-invocation: true`. The skill body is the structured refactoring protocol (analysis → characterization tests → plan → approval gate → apply → report). Claude Code injects the skill body as the prompt that drives the forked subagent, which uses the `refactoring-specialist` agent definition as its system prompt.

**Option B — Skill that uses the Task tool to spawn `refactoring-specialist`.**
The skill body runs in the main conversation and uses the Task tool to invoke the `refactoring-specialist` agent with a constructed prompt. This is the pattern used by `rfc-consensus-review`. It works but has two costs: (1) the protocol prompt and the agent's response live in the parent context window — the very thing we want to keep out — and (2) the model/effort settings come from the Task invocation, which is more verbose and easier to forget than skill frontmatter.

**Option C — Slash command file under `commands/` (legacy path).**
Custom commands in `.claude/commands/` and skills are now unified — both produce a `/<name>` invocation. The skills path supports `model:`, `effort:`, and `context: fork`; the commands path is simpler but does not support those fields. Since we explicitly need model/effort pinning and context forking, this option is rejected.

**Recommendation: Option A.** `context: fork` is the documented mechanism for "skill content drives a subagent in its own context." It directly supports model and effort overrides via skill frontmatter. The parent conversation receives only the subagent's final summary (the structured report), which keeps the feature-implementation context clean. The agent file already exists and does not need to change for this RFC except for one orthogonal cleanup (see Decision 5).

The skill frontmatter combination this RFC pins is:

```yaml
context: fork
agent: refactoring-specialist
model: opus
effort: max
disable-model-invocation: true
```

`disable-model-invocation: true` makes `/refactor` a deliberately user-invoked (or main-agent-invoked) action rather than something Claude triggers automatically based on description matching. The combination of "expensive model" and "mutates code" should never be auto-loaded.

### Decision 2 — How is the scope passed to the subagent?

**Option A — Free-form `$ARGUMENTS` passed through to the subagent (recommended).**
The skill accepts a free-form scope argument: `/refactor recent PR changes`, `/refactor files about to be modified by RFC 2026-05-10-frobnicate`, `/refactor src/auth/`. The skill body uses `$ARGUMENTS` as the scope hint and lets the subagent's analysis phase resolve it (`git diff`, RFC implementation spec lookup, glob expansion). This handles the three scope shapes the braindump calls out (recent PR code, code about to be touched by an RFC, ad-hoc) without needing structured arguments.

**Option B — Named positional arguments (e.g., `<scope-kind> <scope-target>`).**
More precise — `/refactor pr 1234`, `/refactor rfc 2026-05-10-frobnicate`, `/refactor path src/auth/` — but adds friction at the call site, requires the user (or main agent) to remember the kind taxonomy, and constrains future scope shapes (a fourth kind needs a new positional slot or a flag parser).

**Option C — Interactive scope question.**
The skill always asks the user "what scope?" before doing any work. Pure friction; the main agent often already knows the scope and is invoking `/refactor` precisely because it has decided what to refactor.

**Recommendation: Option A.** The subagent's first phase is "resolve the scope hint into a concrete file set." This works whether the input is a path, a PR reference, an RFC reference, or a free-text description like "the validation logic in the user-creation flow." If the scope is ambiguous, the analysis phase asks one targeted question (via the subagent returning a question to the parent) before proceeding. Argument hint shown in autocomplete: `[scope-hint]`.

### Decision 3 — Plan-before-apply protocol

**Option A — Mandatory plan-then-approval-then-apply (recommended).**
The skill body forces a six-phase protocol: (0) pre-flight (resolve scope, discover the test command); (1) analyze and produce a refactoring plan with concrete proposals; (2) characterization tests — write or extend tests so the current behavior is locked in; (3) present the plan to the parent (the main agent or user) and require explicit approval before any mutation; (4) apply the approved plan in small, individually verifiable steps with the test suite green between each; (5) report what changed, what tests now exist, and what was deliberately not touched. This makes the gate impossible to skip even when the invoker is the main agent (which would otherwise be tempted to barrel through to mutations).

**Option B — Plan-and-apply in one shot, with rollback hint.**
Skip the approval gate; trust the model to produce safe transformations and rely on git to roll back. Cheaper interaction-wise but loses the deliberate-decision property that motivates the whole skill. Refactors that the parent disagrees with consume the parent's review effort *after* the mutations have happened, which is the worst place to discover disagreement.

**Option C — Plan only; never apply.**
The subagent produces a plan and stops; applying the plan is left to a separate skill or to the main agent. Maximally safe but doubles the surface area (the skill is now half a workflow) and removes the value of having Opus + `max` effort drive the actual application — the part where careful reasoning about each step matters most.

**Recommendation: Option A.** The plan-then-approval-then-apply gate is the discipline that distinguishes a deliberate refactoring pass from ad-hoc cleanup. Characterization tests *before* mutation is non-negotiable: refactoring-specialist's own checklist makes this explicit ("Zero behavior changes verified"), and verifying behavior is impossible without a test that captures it. The six-phase protocol is what the skill body enforces; the agent definition supplies the domain knowledge that fills out each phase.

### Decision 4 — How does the main agent learn to use `/refactor` proactively?

**Option A — Document in `CLAUDE.md` with a one-line trigger heuristic and an entry in the Agent delegation table (recommended).**
The plugin's `CLAUDE.md` ships with Bytewyrd projects (it's the seed for project `CLAUDE.md`s). Adding a "Refactoring (deliberate)" row to the Agent delegation table and a short "When to consider /refactor" paragraph in the workflow section gives the main agent a documented prompt to consider `/refactor` before starting work that touches existing code. Since the plugin's `CLAUDE.md` is the source of truth for the agent's behavior in any Bytewyrd project, adding the heuristic there propagates naturally.

**Option B — Auto-invoke heuristics.**
Have the skill be auto-invokable (drop `disable-model-invocation: true`) so Claude can decide to trigger refactoring on its own when it senses a smell. Rejected: the combination of expensive model, `max` effort, and code mutation is too costly to delegate to model autonomy. False positives (Claude refactors code that does not need it) are expensive in tokens and in churn.

**Option C — No documentation; rely on the skill's existence.**
Users discover `/refactor` via the `/` menu and the main agent never proactively suggests it. Rejected: the braindump explicitly calls out the proactive case ("expand test coverage on areas about to change, or to improve architecture ahead of a new feature"); a skill that only fires on user typing leaves that case on the table.

**Recommendation: Option A.** The CLAUDE.md updates are the discoverability mechanism. The skill body itself remains user/main-agent-invoked; the documentation tells the main agent *when* to consider invoking it.

### Decision 5 — How is the unavailable `tools:` claim on `refactoring-specialist` cleaned up?

**Option A — Remove the field entirely; rely on tool inheritance (recommended).**
The current `tools: ast-grep, semgrep, eslint, prettier, jscodeshift` line on the vendored agent silently restricts the subagent to a tool set Claude Code does not surface in this plugin's environment. Per the Claude Code subagent docs ("Tools the subagent can use. Inherits all tools if omitted"), removing the field gives the subagent the standard tool set the rest of the plugin's agents inherit — Read, Grep, Glob, Edit, Write, Bash, TodoWrite, etc. — which is what is actually needed to read and edit source files.

**Option B — Replace the list with the explicit-correct list (`Read, Grep, Glob, Edit, Write, Bash, TodoWrite`).**
More explicit but more brittle: any future tool added by Claude Code that this skill needs would silently not be available until the list is updated. The subagent docs explicitly recommend omission for "all tools" semantics.

**Option C — Leave the field; have the skill body work around the absent tools.**
Rejected: the subagent cannot edit files at all without `Edit`/`Write` in the inherited tool set, so this is non-viable.

**Recommendation: Option A.** Removal is the upstream-default form (many sibling agents in the same VoltAgent library have no `tools:` field). The diff against upstream is minimal — just a removal — making future re-syncs easier to merge.

## Drawbacks

- **Cost.** A `/refactor` invocation runs Opus at `effort: max` over a forked subagent that may take many turns (analysis, characterization tests, plan, apply, verify). The token spend per invocation is high. **Mitigation:** the skill is `disable-model-invocation: true`, so it only runs when explicitly triggered. The CLAUDE.md heuristic frames `/refactor` as "deliberate, before-touching-this-code" work — not something to run on every PR. Users and the main agent retain full control over when the cost is paid.

- **`max` effort can over-think and produce diminishing returns.** The model-config docs explicitly warn that `max` "may show diminishing returns and is prone to overthinking" and recommend testing before adopting broadly. **Mitigation:** the protocol's plan-then-approval gate is a forcing function for the user to evaluate whether the analysis and plan are proportionate to the scope. If `max` overthinks a small scope, the user can cancel before the apply phase and the wasted reasoning is bounded to the analysis turn. The frontmatter value is also straightforward to dial down to `xhigh` in a follow-up if real-world use shows `max` is consistently overkill — that change is one line in `skills/refactor/SKILL.md`.

- **Forked subagent loses parent conversation context.** The forked subagent does not see the parent conversation's history. Any context the main agent has built up about the codebase ("we discovered earlier that this module has a circular dep with X") is not visible to the refactoring-specialist. **Mitigation:** the scope hint passed in `$ARGUMENTS` is the primary channel for context; the main agent is responsible for including any non-obvious context in the hint. The skill body documents this: "Scope hint must include any non-obvious context from the parent conversation that the refactoring pass needs (e.g., 'this module has a known circular dep with X — do not break that further')."

- **`refactoring-specialist` agent's `tools:` field claims tools that are not present in this environment.** The vendored agent lists `ast-grep, semgrep, eslint, prettier, jscodeshift`. If those tools are absent, the agent inherits the parent's tool list (per the subagent docs: "Inherits all tools if omitted") only when the field is omitted — a non-empty list silently restricts the subagent to those listed tools. **Mitigation:** the RFC explicitly calls out updating the `tools:` field on `refactoring-specialist` to remove the unavailable entries and rely on Claude Code's default tool inheritance, which gives the subagent the same standard tools (Read, Grep, Glob, Edit, Write, Bash, etc.) the rest of the plugin's agents use. This is a one-line change but is essential for the skill to work; without it, the subagent cannot edit files. The change is captured in the implementation spec.

- **The agent file is vendored from upstream (`VoltAgent/awesome-claude-code-subagents`).** Editing the `tools:` field on the agent file means the next vendor-update run pulls the upstream version and silently re-introduces the wrong tool list. **Mitigation:** the implementation spec routes the model/effort settings entirely through the *skill* frontmatter (which overrides the agent's defaults during the forked invocation), and changes the agent's `tools:` field to be empty (omitted) — relying on inheritance. An empty/omitted `tools:` field is the upstream default for many agents in the same library, so the local diff against upstream is minimal: just removing a stale claim. If the next vendor-update re-adds the original `tools:` list, the verification step in this RFC's Step 6 catches it (`grep -c '^tools:' agents/refactoring-specialist.md` → expects `0`); a follow-up RFC can introduce a vendor-patch mechanism (overlay file that merges on top of the upstream pull) if this regression starts happening in practice. Logged as an open question.

- **No automated way to know whether the refactor improved the code.** The skill reports "what changed" but does not run a metrics comparison (cyclomatic complexity before/after, duplicated-block count delta). **Mitigation:** the report is structured but qualitative; the user and the test suite are the gate. A future RFC can add an optional metrics capture step (`tokei` or similar) and fold it into the report. Out of scope here.

- **Approval gate adds round-trip latency.** The six-phase protocol forces a stop-and-confirm between plan and apply. For genuinely tiny refactors (rename one variable across three files), this is friction that an "auto-apply small refactors" mode would eliminate. **Mitigation:** for tiny refactors, the user/main agent should not be invoking `/refactor` at all — they should just edit the files. `/refactor`'s positioning is "deliberate refactoring pass, large enough to warrant Opus + max"; the gate's value is in proportion to scope, and the scope where it adds friction is the scope where the skill is the wrong tool.

- **`context: fork` is currently flagged experimental in Claude Code (v2.1.117+).** The forked-subagent feature requires `CLAUDE_CODE_FORK_SUBAGENT=1` to enable, and behavior may change in future releases per the docs. **Mitigation:** the README update in this RFC documents the version requirement and the env-var flag. If the experimental flag is dropped before the plugin's next major release, the README note becomes a no-op. If the feature is removed or changed, this RFC's implementation needs revision — but that is true of any feature that depends on an experimental flag, and the plugin's audience is small enough that a single follow-up RFC can absorb the change.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `skills/refactor/SKILL.md` | New skill: spawns a forked subagent against the `refactoring-specialist` agent with Opus + `max` effort; enforces the pre-flight → analysis → characterization tests → plan → approval → apply → report protocol; accepts a free-form scope hint via `$ARGUMENTS` |
| Modify | `agents/refactoring-specialist.md` | Remove the unavailable `tools:` claim (`ast-grep, semgrep, eslint, prettier, jscodeshift`) so the subagent inherits the standard tool set. No other changes |
| Modify | `.claude-plugin/plugin.json` | Add `./skills/refactor` to the `skills` array (alphabetically positioned) |
| Modify | `CLAUDE.md` (plugin root) | (1) Add a "Refactoring (deliberate)" row to the Agent delegation table pointing to `refactoring-specialist`. (2) Add a short "Considering /refactor" subsection in the Workflow section explaining the proactive trigger heuristic |
| Modify | `README.md` (plugin root) | Add one paragraph to the install/usage section noting the `context: fork` version requirement (Claude Code v2.1.117 or later) and the `CLAUDE_CODE_FORK_SUBAGENT=1` environment variable that enables forked subagents |

No new agent files. No hook changes. No changes to existing skills. The vendored upstream agent file changes by exactly one line (removing the `tools:` field).

### Steps

#### Step 1 — Create `skills/refactor/SKILL.md`

Create the file with this exact content:

````markdown
---
name: refactor
description: Run a deliberate refactoring pass on a scoped set of files using the refactoring-specialist agent on Opus with max effort. Use when about to extend code that has thin test coverage, when a structural smell will be amplified by an upcoming feature, when reviewing a recent PR for cleanup before merge, or any time refactoring should be a first-class step rather than tacked-on cleanup. Not for tiny renames — for those, just edit the files.
context: fork
agent: refactoring-specialist
model: opus
effort: max
disable-model-invocation: true
argument-hint: "[scope-hint]"
---

# /refactor — Deliberate Refactoring Pass

You are running as the `refactoring-specialist` subagent in a forked context. Your system prompt (the agent definition) gives you the domain knowledge — code-smell detection, refactoring catalog, safety practices, test-driven refactoring, code metrics. This skill body is the *protocol* you follow for this specific invocation.

## Scope

The invocation passed this scope hint:

```
$ARGUMENTS
```

If the scope hint is empty, ask the parent (the agent or user that invoked you) one targeted question: "What scope should this refactoring pass cover? (a path, a PR reference, an RFC implementation, or a free-text description like 'the validation logic in user creation')." Do not proceed without a scope.

The scope hint must also carry any non-obvious context from the parent conversation that the refactoring pass needs (e.g., "this module has a known circular dep with X — do not break that further"). The forked context does not see the parent's history; if the parent expects you to know something they discovered, they include it in the hint.

## Protocol — six phases

### Phase 0 — Pre-flight (resolve scope, discover test command)

**Resolve the scope.** If the scope hint references something that requires resolution (e.g., "recent PR changes", "files about to be touched by RFC 2026-05-10-frobnicate", "the auth module"), resolve it concretely before phase 1:

- **PR / branch references:** `git diff --name-only main...HEAD` (or against the named branch) to enumerate modified files.
- **RFC references:** read the named RFC file from `docs/rfcs/`, extract the file structure table, and use the listed paths as the scope.
- **Path references:** glob the path; expand to a concrete file list.
- **Free-text descriptions:** use Grep to locate the relevant code; if multiple candidate locations exist, list them and ask the parent which to target.

**Discover the test command.** Refactoring is behavior-preserving; that is verifiable only if the test suite can be run. Inspect the project for the canonical test invocation:

- `package.json` `scripts.test` field — `bun test` / `npm test` / `pnpm test` typically
- `Makefile` `test:` target — `make test`
- `Justfile` `test` recipe — `just test`
- `Cargo.toml` presence — `cargo test`
- `go.mod` presence — `go test ./...`
- `pyproject.toml` / `setup.py` — typically `pytest` or `python -m pytest`
- `Gemfile` — `bundle exec rspec` or `bundle exec rake test`

Pick the first match. If multiple plausible commands exist, ask the parent: "I see candidates X, Y, Z for the test command — which is the canonical one to run between refactoring steps?" If no test command is discoverable, ask the parent what command to use; do not invent one.

Record the resolved scope and the test command. Both are needed in later phases.

### Phase 1 — Analysis (no mutations)

1. Read every file in the resolved scope.
2. Run static analysis using whatever tools the environment surfaces (typically Grep for pattern detection; do not assume specialist refactoring tools like `ast-grep` are present unless you can verify their availability with a short Bash check).
3. Identify code smells using the agent's smell catalog: long methods, large classes/files, long parameter lists, divergent change, shotgun surgery, feature envy, data clumps, primitive obsession, and any language-specific smells.
4. Measure complexity informally: count cyclomatic branches in the largest functions, identify duplication, identify modules with too many responsibilities.
5. Check existing test coverage for the scope: enumerate test files that target the scope, identify which behaviors have characterization coverage and which do not.

Produce an analysis summary. Do not write to any file in the scope yet.

### Phase 2 — Characterization tests

Refactoring is behavior-preserving by definition. Behavior preservation requires tests that lock in the current behavior before any structural change. For every behavior in the scope that does not already have test coverage:

1. Write a characterization test that exercises the current behavior, including the parts you intend to keep and the parts you intend to refactor.
2. Run the test suite (using the command discovered in phase 0) and confirm the new tests pass against the *current* code. If a new test fails on current code, the test does not yet capture the current behavior — fix the test, not the code (the code's behavior is, by definition, the spec at this point).
3. Commit the new tests as a separate commit so the refactor commits can be reviewed against a known-green baseline. Use a Conventional Commits message: `test(<scope>): add characterization tests for <area>`, where `<scope>` is a short identifier for the affected component or module (e.g., `auth`, `parser`, `payments`) and `<area>` names what the tests cover.

If the scope already has comprehensive test coverage, note that in your report and skip to phase 3.

If you cannot write characterization tests (the code is so coupled to side effects that a test is impossible without a refactor first), the standard pre-step is **seam introduction** (Feathers, *Working Effectively With Legacy Code*): identify the smallest possible change that gives the code a testable seam — extract a parameter, introduce a wrapper at a method boundary, replace a `new` with a factory call. If a seam-introduction step is itself behavior-preserving and small enough to verify by inspection, propose it as step 0 of the refactoring plan and let the parent approve it before you write the first characterization test against it.

If even seam introduction is not possible without changing behavior, say so explicitly and stop. Do not refactor untested code that resists testing — that is a separate, harder problem and outside this skill's scope. Surface the obstruction to the parent.

### Phase 3 — Plan

Produce a concrete refactoring plan as a numbered list. Each item is a single refactoring step (extract method, inline variable, introduce parameter object, replace conditional with polymorphism, rename, etc.) — small enough that the test suite is green after each step and large enough to be meaningful on its own.

Format:

```
Refactoring plan for <scope>:

1. <refactoring name> — <one-line description>
   Files: <files affected>
   Risk: <low | medium | high> — <why>
   Reversal: <one-line rollback note>

2. <refactoring name> — <one-line description>
   ...
```

Order the steps so the test suite is green after each one. Group related steps when they cannot be cleanly separated (e.g., "extract method then rename — must be applied together to keep callers compiling"); call out the grouping in the description and number the bundled steps as `1a, 1b, 1c` so the parent can still approve or skip the group as a unit.

Skip any "improvement" that is a behavior change in disguise — refactoring is, by Fowler's definition, behavior-preserving; behavior changes are *rewrites*, which belong in a feature change or RFC. If you find one, list it under a separate "Behavior changes deferred" heading at the end of the plan with a one-line note that this needs to be done as a separate feature change, not a refactor.

### Phase 4 — Approval gate (mandatory)

Return the plan to the parent and stop. The parent (the main agent or the user) reviews the plan and decides which steps to apply. Do not proceed to phase 5 until the parent responds with one of:

- `apply all` — proceed with every step in order
- `apply 1, 3, 5` — proceed with the listed step numbers in order (grouped steps like `1a, 1b` apply together when the group number is listed)
- `cancel` — stop; the characterization tests from phase 2 stay committed (they are a standalone improvement) and proceed to phase 6 to report

If the parent asks clarifying questions, answer them. If the parent requests changes to the plan ("merge steps 2 and 3", "skip step 4", "add a step that does X"), revise the numbered list and re-present the full updated plan, then wait for a new approval response. Do not start applying based on partial approval mixed with revision requests.

This gate is non-negotiable. Even if the invoker is the main agent (which may be tempted to skip review), the gate is what makes the difference between a deliberate refactor and ad-hoc mutation.

### Phase 5 — Apply

For each approved step, in the order the parent listed them:

1. Apply the change.
2. Run the test suite (using the command from phase 0). Three outcomes:
   - **All tests pass** — proceed to step 3.
   - **A characterization test fails** — your refactor changed observable behavior. Revert this step's changes and surface the failing test to the parent: "Step N broke characterization test X. The refactor changed behavior; reverting and pausing." Do not attempt to fix the test by adjusting expectations — the test is the spec.
   - **A non-characterization test fails (a pre-existing test that was depending on the implementation detail you just changed)** — this is the legitimate "test was coupled to implementation, not behavior" case. Stop, surface the failure to the parent with the failing test name and the implementation detail it was coupled to, and wait for the parent to decide: revert the refactor, or update the test to depend on behavior instead of implementation. Do not unilaterally rewrite tests.
3. Commit the step. Use a Conventional Commits message: `refactor(<scope>): <step description>`, where `<scope>` is the same short component identifier used in phase 2 — one commit per approved step (or per approved group, when steps were bundled as `1a, 1b, 1c`).
4. Move to the next approved step.

If a step turns out to be larger or riskier than the plan estimated (the apply phase reveals coupling not visible in analysis), stop and re-present the revised step to the parent before continuing.

### Phase 6 — Report

After all approved steps are applied (or after `cancel` was received), return a structured report to the parent:

```
Refactoring pass complete.

Scope: <files in scope>
Test command: <command from phase 0>
Characterization tests added: <count and a brief list>
Steps applied: <numbered list with one-line description and commit SHA>
Steps skipped: <list with reason>
Behavior changes deferred: <list, or "none">
Test suite status: <pass | fail with details>

Recommended follow-up: <one or two sentences, or "none">
```

Do not edit the report after returning it. The parent decides what to do with the recommended follow-ups.

## Constraints

- **Behavior preservation is the contract.** A "refactor" that changes user-visible behavior is a misuse of this skill. If you find a behavior bug during analysis, surface it in the plan under "Behavior changes deferred" — do not fix it as part of the refactor pass.
- **One commit per step (or per approved group).** Bundling unrelated steps into one commit destroys reviewability and breaks `git bisect`. Grouped steps (`1a, 1b, 1c`) commit together because they are a single semantic operation that cannot be split without leaving the tree in a broken state.
- **No new files in `docs/`.** This skill does not write reports, summaries, or analysis files to `docs/`. The structured report in phase 6 is the only output channel.
- **Respect the scope.** Do not "while I'm here" refactor files outside the resolved scope. If you spot a smell in adjacent code, mention it in the recommended follow-up; do not touch it.
- **Trust the parent on tooling.** Do not start long-running processes (test watchers, dev servers); ask the parent to run them in a separate terminal if needed. Tests run on demand via single invocations of the command discovered in phase 0.

## When this skill is *not* the right tool

- **Tiny renames** (one variable, one method) — just edit the files. The plan-and-approve gate adds more friction than the rename's reasoning is worth.
- **Bug fixes** — a fix is a behavior change; use feature-engineer or an RFC instead.
- **Greenfield code** — no existing behavior to preserve, no characterization tests to anchor; you want feature-engineer for fresh implementation, not refactoring-specialist.
- **Cross-cutting architectural changes** that span unbounded scope (e.g., "introduce hexagonal architecture across the whole codebase") — write an RFC first via `/rfc-new`; the RFC implementation phase can then invoke `/refactor` against each subset.
````

The skill is `disable-model-invocation: true` so it only runs when invoked explicitly. The skill is `user-invocable` (default `true`) so users can type `/refactor`. The `argument-hint` shows up in the autocomplete menu so users see the expected scope-hint shape.

#### Step 2 — Update `agents/refactoring-specialist.md`

Edit the frontmatter of `agents/refactoring-specialist.md`. The current frontmatter (lines 1–5) is:

```
---
name: refactoring-specialist
description: Expert refactoring specialist mastering safe code transformation techniques and design pattern application. Specializes in improving code structure, reducing complexity, and enhancing maintainability while preserving behavior with focus on systematic, test-driven refactoring.
tools: ast-grep, semgrep, eslint, prettier, jscodeshift
---
```

Remove the `tools:` line entirely so the frontmatter becomes:

```
---
name: refactoring-specialist
description: Expert refactoring specialist mastering safe code transformation techniques and design pattern application. Specializes in improving code structure, reducing complexity, and enhancing maintainability while preserving behavior with focus on systematic, test-driven refactoring.
---
```

Per the Claude Code subagent docs ("Tools the subagent can use. Inherits all tools if omitted"), removing the field gives the subagent the standard tool set the rest of the plugin's agents inherit (Read, Grep, Glob, Edit, Write, Bash, TodoWrite, etc.). The aspirational tool list (`ast-grep`, `semgrep`, `eslint`, `prettier`, `jscodeshift`) is removed because Claude Code does not surface those as named tools in this plugin's environment — listing them silently restricts the subagent to a tool set that does not exist, which would prevent the subagent from making any edits at all.

The body of the file (line 6 onward) is unchanged. Do not edit the system-prompt content; only the frontmatter `tools:` line is removed.

This change is the only modification this RFC makes to a vendored agent file. The risk that a future vendor-update reverts the change is logged in the Drawbacks section and tracked as an open question (see "Risks and open questions").

#### Step 3 — Register the skill in `.claude-plugin/plugin.json`

Open `.claude-plugin/plugin.json`. The current `skills` array is:

```json
"skills": [
  "./skills/best-practices-extract",
  "./skills/best-practices-record",
  "./skills/sync",
  "./skills/git-branch-cleanup",
  "./skills/rfc-approve",
  "./skills/rfc-braindump",
  "./skills/rfc-consensus-review",
  "./skills/rfc-drop",
  "./skills/rfc-implement",

  "./skills/rfc-new",
  "./skills/rfc-read-feedback",
  "./skills/rfc-update"
]
```

Insert `"./skills/refactor"` between `"./skills/git-branch-cleanup"` and `"./skills/rfc-approve"` (alphabetical: `refactor` sorts after `git-branch-cleanup` and before `rfc-approve` because `refa` < `rfc-`). Also remove the stray blank line between `rfc-implement` and `rfc-new` for cleanliness; this is a no-op JSON change. The full file after this step becomes:

```json
{
  "name": "bytewyrd",
  "description": "Opinionated Claude Code workflow for Bytewyrd projects and teams: skills, agents, hooks, and operating principles for evidence-based development with RFC-driven design.",
  "version": "0.1.0",
  "author": {
    "name": "Bytewyrd",
    "email": "divoxx@gmail.com"
  },
  "hooks": "./.claude-plugin/hooks/hooks.json",
  "skills": [
    "./skills/best-practices-extract",
    "./skills/best-practices-record",
    "./skills/sync",
    "./skills/git-branch-cleanup",
    "./skills/refactor",
    "./skills/rfc-approve",
    "./skills/rfc-braindump",
    "./skills/rfc-consensus-review",
    "./skills/rfc-drop",
    "./skills/rfc-implement",
    "./skills/rfc-new",
    "./skills/rfc-read-feedback",
    "./skills/rfc-update"
  ]
}
```

(The current order of the existing entries — `sync` appearing before `git-branch-cleanup` — is preserved as-is. This RFC does not re-sort the existing entries; alphabetizing the full list is a separate concern that can be a no-op cleanup PR if desired.)

#### Step 4 — Update `CLAUDE.md`

Two changes to `/home/divoxx/code/bytewyrd/claude-bytewyrd-workflow/CLAUDE.md`:

**Change 4a — Agent delegation table.**

The current table is:

```markdown
| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
| Architecture / RFCs | rfc-architect |
| Documentation | documentation-writer |
| Debugging | debugger |
```

Add a row for refactoring after the "Code reviews" row, so the order goes "build → review → refactor → architect → docs → debug":

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

The `(via /refactor)` annotation tells the reader that the entry point is the skill, not direct agent delegation.

**Change 4b — Workflow section.**

Insert a new subsection in the "Workflow" block, between `### During work` and `### Session end`:

```markdown
### Considering /refactor

Before extending or modifying existing code, consider whether a deliberate refactoring pass would make the upcoming change cleaner. Run `/refactor <scope-hint>` when:

- The area you are about to touch has thin test coverage, and adding characterization tests now will protect both the refactor and the subsequent feature work.
- A structural smell (long method, fat conditional, primitive obsession, divergent change) will be amplified by the upcoming feature; refactor first so the new code has a clean place to land.
- A recent PR you are about to merge has cleanup that was deferred because the diff was already large.

`/refactor` runs the `refactoring-specialist` agent on Opus with `max` effort in a forked context. It is deliberately expensive and gated — use it for genuine refactoring passes, not for tiny renames (just edit the files for those).

The skill enforces a six-phase protocol: pre-flight (resolve scope, discover test command) → analyze → characterization tests → plan → **approval gate** → apply → report. The approval gate stops the subagent before any mutation; review the plan, approve specific steps, and the subagent applies them one commit at a time.
```

The placement (between `### During work` and `### Session end`) matches the existing flow: workflow guidance for things that happen mid-session, before the wrap-up. The subsection heading uses `###` to match the level of `### During work` / `### Session end` siblings.

#### Step 5 — Update `README.md`

Add the following paragraph to `README.md` in the install/usage section, immediately before the "Configuration" or "Customization" section (whichever comes first), or at the end of the install section if neither exists. The exact insertion point is wherever version requirements would naturally live alongside other prerequisites:

```markdown
### Version requirements

The `/refactor` skill uses Claude Code's forked-subagent feature (`context: fork`), which requires **Claude Code v2.1.117 or later** and is currently flagged experimental. Enable it by setting `CLAUDE_CODE_FORK_SUBAGENT=1` in your shell environment before starting Claude Code:

```bash
export CLAUDE_CODE_FORK_SUBAGENT=1
```

Add the export to your shell profile (`.bashrc`, `.zshrc`, etc.) to persist it across sessions. Other plugin skills do not depend on this flag and work without it.
```

If the README does not have an obvious section for prerequisites, add a `### Version requirements` subsection at the end of the existing install instructions. The exact placement within the README can be chosen at implementation time; the constraint is that it appears alongside the install instructions, not buried in an appendix.

#### Step 6 — Verification

After all changes, run these checks:

1. **Skill file exists and parses:**

   ```bash
   test -f skills/refactor/SKILL.md && head -10 skills/refactor/SKILL.md
   ```

   Expected output (the first 10 lines, including the frontmatter):

   ```
   ---
   name: refactor
   description: Run a deliberate refactoring pass on a scoped set of files using the refactoring-specialist agent on Opus with max effort. Use when about to extend code that has thin test coverage, when a structural smell will be amplified by an upcoming feature, when reviewing a recent PR for cleanup before merge, or any time refactoring should be a first-class step rather than tacked-on cleanup. Not for tiny renames — for those, just edit the files.
   context: fork
   agent: refactoring-specialist
   model: opus
   effort: max
   disable-model-invocation: true
   argument-hint: "[scope-hint]"
   ---
   ```

2. **Skill is registered in plugin.json:**

   ```bash
   grep -F '"./skills/refactor"' .claude-plugin/plugin.json
   ```

   Expected output:

   ```
       "./skills/refactor",
   ```

3. **Refactoring-specialist agent no longer claims unavailable tools:**

   ```bash
   grep -c '^tools:' agents/refactoring-specialist.md
   ```

   Expected output: `0`

4. **Refactoring-specialist agent body is unchanged:**

   ```bash
   grep -c 'Refactoring excellence checklist' agents/refactoring-specialist.md
   ```

   Expected output: `1` (the body content marker is still present — the edit only touched the frontmatter).

5. **CLAUDE.md table includes the refactoring row:**

   ```bash
   grep -F 'Refactoring (deliberate)' CLAUDE.md
   ```

   Expected output:

   ```
   | Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
   ```

6. **CLAUDE.md workflow section includes the /refactor guidance:**

   ```bash
   grep -F '### Considering /refactor' CLAUDE.md
   ```

   Expected output:

   ```
   ### Considering /refactor
   ```

7. **README documents the version requirement:**

   ```bash
   grep -F 'CLAUDE_CODE_FORK_SUBAGENT' README.md
   ```

   Expected output:

   ```
   export CLAUDE_CODE_FORK_SUBAGENT=1
   ```

   (Or any line containing the env-var name; the exact form depends on how the README phrases it.)

8. **Manual smoke test (after `claude plugin update bytewyrd`, with Claude Code restarted and `CLAUDE_CODE_FORK_SUBAGENT=1` exported):**

   - Type `/` in Claude Code; confirm `/refactor` appears in the autocomplete menu with the `[scope-hint]` argument hint.
   - Type `/refactor src/auth/` (or any path) and confirm the skill enters phase 0 of the protocol (pre-flight: discovers test command and resolves scope), then phase 1 (analysis), runs in a forked context (no parent-context noise during analysis), and uses Opus + `max` effort (visible in the status line as "with max effort").
   - Confirm the approval gate fires: after the plan is presented, the subagent stops and waits for `apply all`, `apply <list>`, or `cancel`.
   - Approve `apply all` (or a subset) and confirm each approved step is applied as a separate commit with a `refactor(<scope>):` Conventional Commits message.
   - Confirm the report (phase 6) lists every applied step with its commit SHA.

   If any of these steps fail, the issue is most likely (in order): (a) `tools:` field still present on the agent (subagent cannot edit), (b) `disable-model-invocation: true` typo (skill not invokable), (c) `context: fork` not honored (older Claude Code version, missing env var, or feature has been removed), (d) the test command from phase 0 doesn't match what the project actually uses (subagent should have asked rather than guessed).

## Risks and open questions

- **Risk: a future vendor-update reverts the `tools:` removal on `refactoring-specialist`.** The agents directory is vendored from `VoltAgent/awesome-claude-code-subagents`. If a vendor-update re-syncs the upstream version, the unavailable `tools:` list comes back and the skill silently breaks. **Mitigation:** the verification command in Step 6 (`grep -c '^tools:' agents/refactoring-specialist.md` → expects `0`) catches a regression on the next CI run or manual smoke test. A follow-up RFC can introduce a vendor-patch mechanism (overlay file that merges on top of the upstream pull) if this regression starts happening in practice; out of scope here.

- **Risk: `context: fork` requires Claude Code v2.1.117 or later (forked subagents are still flagged experimental).** Users on older versions will see `/refactor` either fail or run in the parent context (depending on how Claude Code degrades). **Mitigation:** Step 5 of this RFC adds the version requirement and the `CLAUDE_CODE_FORK_SUBAGENT=1` flag note to the README. This is the only documentation channel for first-time users.

- **Risk: `effort: max` may not be honored on Opus 4.6 or older.** Per the model-config docs, `max` is supported on Opus 4.7 and on Opus 4.6/Sonnet 4.6. If a user is pinned to an older Opus version, Claude Code "falls back to the highest supported level at or below the one you set" — degrading to `high` rather than failing. **Mitigation:** acceptable degradation. The skill's effectiveness is reduced but not broken on older models. No code change needed.

- **Open question: should the skill require characterization tests *before* the analysis phase, or after?** The current protocol sequences analysis → characterization tests → plan, on the theory that the analysis discovers what behaviors need locking in. The alternative (tests first, then analyze) produces a tighter test-first discipline but means writing tests for code the subagent has not yet read in detail. **Resolution within this RFC:** keep analysis first. The analysis phase is bounded (read-only; no mutations) and the characterization tests in phase 2 benefit from the analysis output. If real-world use shows the analysis phase is missing behaviors that characterization tests would have caught, swap the order in a follow-up.

- **Open question: should the skill refuse to run if the working tree is dirty?** A refactoring pass interleaves new commits with the user's uncommitted changes, which can be confusing. **Resolution within this RFC:** don't add the gate. The subagent's commits are scoped (characterization-test commit, then per-step refactor commits) and the user can `git stash` before running if they want isolation. Adding a dirty-tree gate is friction that the user can already self-impose; not the skill's job to enforce.

- **Open question: how does `/refactor` interact with `/rfc-implement`?** When `/rfc-implement` is running, it spawns a `feature-engineer` agent that follows the RFC's implementation spec. If the spec area has refactoring needs, should the feature-engineer pause and recommend `/refactor`, or should the user have run `/refactor` before approving the RFC? **Resolution within this RFC:** the RFC author runs `/refactor` against the RFC's file structure scope *before* `/rfc-approve` if they expect the implementation to benefit from a clean baseline. The CLAUDE.md "Considering /refactor" subsection mentions this case. The `/rfc-implement` skill is not modified by this RFC — feature-engineer continues to implement the spec as-is, not redesign or refactor.

- **Risk: parent context loss on the forked subagent.** Mentioned in Drawbacks. Mitigation is encoded in the skill body's Scope section: the scope hint must include any non-obvious context from the parent conversation. If real-world use shows this is consistently insufficient, a follow-up could add a structured context-passthrough mechanism (e.g., the parent emits a compact context summary that the skill prepends to `$ARGUMENTS`). Out of scope here.

- **Risk: phase 0's test-command discovery may pick the wrong command in repos with multiple test runners.** A monorepo with both `cargo test` (Rust subcrate) and `bun test` (TS subcrate) will pick whichever ordering rule matches first. **Mitigation:** the discovery step explicitly asks the parent when "multiple plausible commands exist." If the heuristic mis-ranks them in a real repo and runs the wrong command silently, the answer is to add the multi-candidate ask earlier in the heuristic — a one-line skill-body change, not an RFC-level concern.

## Relationship to other RFCs

None. This RFC is self-contained — it touches `skills/refactor/` (new), `agents/refactoring-specialist.md` (one-line edit), `.claude-plugin/plugin.json` (one-line addition), `CLAUDE.md` (table row + workflow subsection), and `README.md` (one-paragraph version-requirement note). No open RFC depends on or conflicts with this one.

The closest adjacencies are:

- **2026-05-09-best-practices-content-and-tooling** (status: Done) — established the verb-suffix naming convention (`best-practices-extract`, `best-practices-record`, `best-practices-sync`) for noun-first skill families. This RFC introduces a single-skill name (`refactor`) that does not yet have a family; if a `refactor-foo`/`refactor-bar` family emerges, the same convention applies.
- **`/rfc-implement` skill** — invokes `feature-engineer` to implement an approved RFC. `/refactor` is a sibling concept (deliberately invoked, model-pinned, multi-phase) but operates on existing code rather than implementing new specs. The two skills do not conflict; they are orthogonal entry points for different kinds of work.
