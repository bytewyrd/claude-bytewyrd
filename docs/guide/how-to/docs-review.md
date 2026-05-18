# Run a documentation review

`/docs-review` audits `docs/guide/**` and `README.md` against the current codebase and surfaces broken examples, stale references, workflow drift, and coverage gaps. It does not auto-apply changes — it presents a plan and waits for your approval.

---

## When to run it

- **After `/rfc-implement` lands user-visible changes** — a new skill, an agent change, a new CLI flag, a new workflow. The `feature-engineer` agent does not update docs; run `/docs-review` to close that gap before the session ends.
- **Before a release** — sweep `docs/guide/**` to confirm no broken examples or stale references ship to users.
- **When `/sync` reports the docs-agent has improved** — re-audit the existing docs with the updated checks.
- **When a user reports a broken tutorial or missing flag** — run a scoped review against the affected area rather than editing blindly.

---

## Scope hint syntax

Pass a scope hint to limit the review to a relevant slice of the docs:

```
/bytewyrd:docs-review 2026-05-10-my-rfc
```

The scope hint can be:

| Form | What it does |
|------|-------------|
| RFC identifier (`2026-05-10-my-rfc`) | Reads the RFC's file structure table and audits docs that mention those symbols, skills, agents, or paths |
| A path (`docs/guide/tutorials/`, `src/auth/`) | Audits docs under that path, or docs that reference that source area |
| Free-text description (`the refactor skill`, `session-start hooks`) | Greps for matching files in both `docs/guide/` and the codebase |
| `all` | Full audit of `docs/guide/**` against the entire project tree |

You can also include non-obvious context in the hint:

```
/bytewyrd:docs-review 2026-05-10-my-rfc — this RFC removed the --legacy-flag; any doc still mentioning it is stale and should be updated, not preserved
```

The docs-agent subagent does not see the parent conversation — include anything it needs to know directly in the scope hint.

---

## How to read and approve the plan

After you invoke `/docs-review`, the agent resolves the scope, audits the docs, and returns a numbered plan. Example:

```
Documentation review plan for 2026-05-10-my-rfc:

1. broken-example: inline code block references missing function
   File: docs/guide/tutorials/getting-started.md (line 45)
   Current: `install_plugin()` called without import
   Should be: `from bytewyrd import install_plugin` on line 44
   Risk: low

2. stale-reference: /rfc-update skill no longer exists
   File: docs/guide/how-to/rfc-workflow.md (line 12)
   Current: mentions /rfc-update for updating an RFC
   Should be: remove; the current workflow uses /rfc-read-feedback
   Risk: low
```

Respond with one of:

- `apply all` — apply every finding in order
- `apply 1, 3` — apply only the listed findings
- `cancel` — see the report without applying anything

The agent will not modify any file until you respond.

---

## Severity levels

| Severity | Meaning |
|----------|---------|
| `broken-example` | A symbol in a code block (function name, flag, env var) does not exist in the codebase |
| `stale-reference` | A skill, agent, file path, or relative link mentioned in prose points to something that no longer exists |
| `workflow-drift` | The steps described in a how-to guide or tutorial no longer match the actual skill workflow |
| `coverage-gap` | A feature, skill, or workflow that should have user-facing docs does not |

---

## What docs-review will not touch

The review is strictly scoped to `docs/guide/**` and `README.md`. It never modifies:

| File | Owner |
|------|-------|
| `docs/ARCHITECTURE.md` | Agent that made the structural change |
| `docs/CONTRIBUTING.md` | Agent that changed the dev workflow |
| `docs/BEST_PRACTICES.md` | `/best-practices-extract` |
| `docs/project-brief.md` | `/sync` |
| `docs/rfcs/**` | RFC lifecycle skills (`/rfc-new`, `/rfc-implement`, etc.) |
| `docs/rfc-process.md` | `/sync` |
| `docs/rfc-braindump.md` | `/rfc-braindump` |

If a finding seems to require editing one of these files, the plan will say so and recommend the appropriate skill or agent instead.

---

## Related

- [Reference: Hooks](../reference/hooks.md) — the `SubagentStop` hook that reminds you to run `/docs-review` after a feature-engineer finishes.
- [Reference: Skills](../reference/skills.md) — full skill description for `/docs-review`.
