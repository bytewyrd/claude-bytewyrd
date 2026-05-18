# Run a deliberate refactoring pass

`/refactor` runs a structured, behavior-preserving refactoring pass on a scoped set of files. It spawns the `refactoring-specialist` agent (Opus, max effort), which analyzes the code, adds characterization tests, proposes a plan, and waits for your approval before touching anything.

---

## When to use it

Use `/refactor` when:

- **The code you are about to extend has thin test coverage.** Adding characterization tests now protects both the refactor and the subsequent feature work. Refactor first, then implement.
- **A structural smell will be amplified by the upcoming feature.** A fat conditional or a long method becomes harder to extend correctly. Refactoring before adding the feature gives the new code a clean place to land.
- **A PR you are about to merge has deferred cleanup.** Use `/refactor` against the PR's changed files to address structural debt before the code is on `main`.

**Do not use `/refactor` for tiny renames.** A single variable or method rename does not need the six-phase protocol — just edit the file. The approval gate adds more friction than the reasoning is worth for one-line changes.

---

## Scope hint syntax

Pass a scope hint describing what to refactor:

```
/bytewyrd:refactor scripts/check-requirements.sh
```

The scope hint can be:

| Form | What it resolves to |
|------|---------------------|
| A file path | That file |
| A directory path | All files in that directory |
| A PR or branch reference | Files changed relative to `main` |
| An RFC identifier | Files listed in the RFC's file structure table |
| Free-text description (`the validation logic in user creation`) | Grep-located matching files; the agent asks if multiple candidates exist |

Include any non-obvious context the agent needs:

```
/bytewyrd:refactor src/auth/ — this module has a known circular dependency with src/session/; do not break that further
```

The `refactoring-specialist` agent does not see the parent conversation. Anything it needs to know must be in the scope hint.

---

## What you see at each phase

### Pre-flight and analysis

The agent resolves the scope to a concrete file list, discovers the test command, reads every file in scope, and identifies code smells. No files are modified.

### Characterization tests

Before any structural change, the agent writes tests that lock in the current behavior. These are committed separately so the refactor commits can be reviewed against a known-green baseline.

If the scope already has comprehensive test coverage, this phase is skipped.

### The plan

The agent presents a numbered list of refactoring steps. Each step is small enough that the test suite is green after it. Example:

```
Refactoring plan for scripts/check-requirements.sh:

1. Extract method — move probe logic into separate check_github() function
   Files: scripts/check-requirements.sh
   Risk: low — no callers outside this file
   Reversal: inline the function body

2. Introduce parameter object — bundle warning ID + message + fix into a struct
   Files: scripts/check-requirements.sh
   Risk: low — internal to the script
   Reversal: expand back to positional arguments
```

### The approval gate

The agent stops here and waits for your response before making any changes to the codebase:

- `apply all` — apply every step in order
- `apply 1, 3` — apply only the listed steps
- `cancel` — stop; the characterization tests stay committed (a standalone improvement) but no structural changes are made

If you request changes ("merge steps 1 and 2", "skip step 3"), the agent revises and re-presents the plan.

### Apply

For each approved step:

1. The change is applied.
2. The test suite runs. If a characterization test fails, the agent reverts and surfaces the failure — the test is the spec, not the code.
3. The step is committed: `refactor(<scope>): <step description>`.

### Report

After all approved steps, the agent returns a structured report: scope, test command, characterization tests added, steps applied with commit SHAs, any deferred behavior changes, and recommended follow-ups.

---

## When NOT to use `/refactor`

- **Bug fixes** — a fix is a behavior change, not a refactor. Use the feature-engineer agent or an RFC.
- **Greenfield code** — there is no existing behavior to preserve and no tests to anchor. Use the feature-engineer agent.
- **Cross-cutting architectural changes** across unbounded scope — write an RFC first with `/rfc-new`. The implementation phase can then invoke `/refactor` against each bounded subset.

---

## Related

- [Reference: Skills](../reference/skills.md) — full skill description for `/refactor`.
- [How to run a documentation review](docs-review.md) — a parallel skill with a similar approval-gate pattern.
