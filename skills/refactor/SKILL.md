---
name: refactor
description: Run a deliberate refactoring pass on a scoped set of files. The skill instructs the main agent to spawn the refactoring-specialist subagent on Opus with max effort, with the six-phase protocol as the prompt. Use when about to extend code that has thin test coverage, when a structural smell will be amplified by an upcoming feature, when reviewing a recent PR for cleanup before merge, or any time refactoring should be a first-class step rather than tacked-on cleanup. Not for tiny renames — for those, just edit the files. Triggered by "/refactor [scope-hint]".
argument-hint: "[scope-hint]"
---

# /refactor — Deliberate Refactoring Pass

This skill runs in the main conversation. Its job is to spawn a `bytewyrd:refactoring-specialist` subagent with the six-phase refactoring protocol below as the prompt, then relay the subagent's questions, plan, and final report back to the user.

## Step 1 — Capture scope

The invocation passed this scope hint:

```
$ARGUMENTS
```

If the scope hint is empty, ask the parent (the user or the agent that invoked this skill) one targeted question: "What scope should this refactoring pass cover? (a path, a PR reference, an RFC implementation, or a free-text description like 'the validation logic in user creation')." Do not spawn the subagent without a scope.

The scope hint must also carry any non-obvious context from the parent conversation that the refactoring pass needs (e.g., "this module has a known circular dep with X — do not break that further"). The subagent does not see the parent's history; if the parent expects the subagent to know something they discussed earlier, they must include it in the hint.

## Step 2 — Spawn the refactoring-specialist subagent

Use the Agent tool to spawn a `bytewyrd:refactoring-specialist` agent with:

- `model: "opus"`
- `effort: "max"`
- Prompt: the entire **Refactoring protocol** section below, with the literal string `<SCOPE HINT FROM $ARGUMENTS>` in the Scope block replaced with the actual scope hint captured in Step 1

The protocol is the agent's prompt. The agent definition supplies the domain knowledge — code-smell detection, refactoring catalog, safety practices, test-driven refactoring, code metrics. The protocol below tells the agent how to apply that knowledge for this specific invocation.

The skill itself does not run the protocol — the spawned subagent does. While the subagent runs, the main agent's job is to relay any questions the subagent surfaces back to the user (especially during the Phase 4 approval gate) and to deliver the final Phase 6 report.

## Step 3 — Wait for the subagent's plan, get user approval, deliver to the subagent

The subagent will return a plan (Phase 3) and stop. Present the plan to the user verbatim and ask for one of:

- `apply all`
- `apply 1, 3, 5` (or any subset; grouped steps like `1a, 1b` apply together)
- `cancel`

Pass the user's response back to the subagent (resume the agent task with the response as input). The subagent will then apply the approved steps (Phase 5) and return the final report (Phase 6).

If the user requests changes to the plan instead of an approval ("merge steps 2 and 3", "skip step 4", "add a step that does X"), pass the request to the subagent — the subagent will revise and re-present the plan, and the approval cycle repeats.

## Step 4 — Deliver the final report

When the subagent finishes (Phase 6), present the structured report to the user verbatim. The report includes the scope, characterization tests added, applied steps with commit SHAs, deferred behavior changes, test suite status, and recommended follow-ups. The user decides what to do with the recommended follow-ups.

---

# Refactoring protocol (passed as the subagent's prompt)

You are the `refactoring-specialist` subagent for a deliberate refactoring pass. Your system prompt (the agent definition) gives you the domain knowledge — code-smell detection, refactoring catalog, safety practices, test-driven refactoring, code metrics. This protocol is what you follow for this specific invocation.

## Scope

```
<SCOPE HINT FROM $ARGUMENTS>
```

The scope hint includes any non-obvious context from the parent conversation. You do not see the parent's history; treat the scope hint as the complete brief.

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
- `Taskfile.yml` presence — `task test`
- `deno.json` / `deno.jsonc` presence — `deno test`

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
3. Commit the new tests as a separate commit so the refactor commits can be reviewed against a known-green baseline. Use a Conventional Commits message: `test(<scope>): add characterization tests for <area>`, where `<scope>` is a short identifier for the affected component or module (e.g., `auth`, `parser`, `payments`) and `<area>` names what the tests cover. If the pass spans multiple unrelated modules, use an enclosing directory or cross-cutting concern as the scope token (e.g., `user-flow`, `api-layer`) rather than a single module name.

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
- `cancel` — stop; the characterization tests from phase 2 stay committed (they are a standalone improvement) and proceed to phase 6 to report. In the report, `Steps applied` should read "none — cancelled at approval gate" and `Steps skipped` should list all plan steps with reason "user cancelled"

If the parent asks clarifying questions, answer them. If the parent requests changes to the plan ("merge steps 2 and 3", "skip step 4", "add a step that does X"), revise the numbered list and re-present the full updated plan, then wait for a new approval response. Do not start applying based on partial approval mixed with revision requests.

This gate is non-negotiable. Even if the invoker is the main agent (which may be tempted to skip review), the gate is what makes the difference between a deliberate refactor and ad-hoc mutation.

### Phase 5 — Apply

For each approved step, in the order the parent listed them:

1. Apply the change.
2. Run the test suite (using the command from phase 0). Three outcomes:
   - **All tests pass** — proceed to step 3.
   - **A characterization test fails** — your refactor changed observable behavior. Revert this step's changes and surface the failing test to the parent: "Step N broke characterization test X. The refactor changed behavior; reverting and pausing." Do not attempt to fix the test by adjusting expectations — the test is the spec.
   - **A non-characterization test fails (a pre-existing test that was depending on the implementation detail you just changed)** — this is the legitimate "test was coupled to implementation, not behavior" case. Stop, surface the failure to the parent with the failing test name and the implementation detail it was coupled to, and wait for the parent to decide: revert the refactor, or update the test to depend on behavior instead of implementation. Do not unilaterally rewrite tests.
3. Commit the step. Use a Conventional Commits message: `refactor(<scope>): <step description>`, where `<scope>` is the same short component identifier used in phase 2 (including the cross-cutting token if the pass spans multiple modules) — one commit per approved step (or per approved group, when steps were bundled as `1a, 1b, 1c`).
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
