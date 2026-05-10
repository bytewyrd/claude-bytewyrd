---
name: best-practices-record
description: Use when the user wants to capture a single best practice into the global cross-project pool at ~/.claude/BEST_PRACTICES.md — typically after seeing a pattern repeat across projects, or learning a stack-level lesson that future projects should ship with from day one.
---

# Record Best Practice

## Overview

Append a single, user-confirmed best-practice entry to the **global** `~/.claude/BEST_PRACTICES.md`. This file is the cross-project pool — it accumulates lessons that future projects should ship with from day one. Entries from here are reviewed and pulled into the plugin's `sync/SKILL.md` via `/best-practices-sync`; once promoted, they are removed from the global file by the sync skill.

This is the counterpart to `/best-practices-extract`:

| Skill | Scope | Source | Target |
|---|---|---|---|
| `/best-practices-extract` | Project-specific | Current session | `docs/BEST_PRACTICES.md` (in the project) |
| `/best-practices-record` | Cross-project | User-supplied statement | `~/.claude/BEST_PRACTICES.md` (global) |

If the rule describes how a single project is built, prefer `/best-practices-extract`. If the rule describes how a *technology, stack, or engineering practice* should be applied — and would be true for any future project using that stack — use this skill.

## Inputs

The user invokes this skill with a single sentence or short paragraph stating the practice. If the invocation lacks the practice text, ask: "What is the best practice to record?" — wait for the answer before proceeding.

## Categorization Step

Determine the section the entry belongs in. The global file uses the same section headers as `sync/SKILL.md`. The categorization also decides whether the entry will eventually land in a *general* (always-emitted) sync section, or a *stack-specific* (detection-gated) section — this matters for promotion: stack-specific entries only ship to projects that use the matching tooling.

| Header | Kind | Use for |
|---|---|---|
| `Testing` | General | TDD, testing pyramids, what to mock, integration vs unit boundaries |
| `Architecture` | General | SOLID, dependency direction, hexagonal/onion layering, module boundaries, public-API discipline, cross-cutting structural patterns (tracing, config, lifecycle) |
| `Documentation` | General | Docs-first practices, README/CONTRIBUTING/ARCHITECTURE scope, comment discipline |
| `Security` | General | Secret handling, input validation, dependency hygiene, privilege boundaries |
| `Error Handling` | General | Error types, panics vs returned errors, retry policy, failure observability |
| `Workflow` | General | Cross-project dev practices (commits, PRs, branches, CI gates) |
| `Pitfall` | General | Cross-project gotchas (tooling, sandbox, environment) |
| `Claude Code` | General | Working with the Claude Code agent across projects |
| `<Language>` | Stack-specific | Language-specific rules: `Rust`, `Go`, `JavaScript / TypeScript`, `Svelte`, `Python`, `Ruby`, `Rails` |
| `<Stack>` | Stack-specific | Stack-specific rules: `Kubernetes / CUE / kapply`, `Terraform / Terragrunt` |

If you cannot map the user's statement to one of the above, propose a new header — but only when nothing existing fits. Adding sections inflates the table of contents; reuse over invent.

When the entry would have gone under a hypothetical `Design` or `Boundaries` header, route it to `Architecture` instead — both are architectural concerns and bootstrap consolidates them under one header. Tracing, config, and lifecycle entries also live under `Architecture`.

## Confirmation Step (Always Required)

Present the entry as it will be written and ask for confirmation:

```
About to append to ~/.claude/BEST_PRACTICES.md under "## <header>":

- **[YYYY-MM-DD]** _<header>_: <user's statement, lightly edited for the standard format>.

Proceed? (yes / edit / cancel)
```

`yes` → write. `edit` → ask for the corrected text and re-confirm. `cancel` → stop, write nothing.

## Write Format

Format matches `best-practices-extract`:

```markdown
- **[YYYY-MM-DD]** _<Category>_: One or two sentences max.
```

`YYYY-MM-DD` is today's date. The italic category label uses a canonical abbreviated form for each section header — never the verbatim header text. Use this table:

| Section header | Italic label to use |
|---|---|
| `## Testing` | `_Testing_` |
| `## Architecture` | `_Architecture_` |
| `## Documentation` | `_Documentation_` |
| `## Security` | `_Security_` |
| `## Error Handling` | `_Error Handling_` |
| `## Workflow` | `_Workflow_` |
| `## Pitfall` | `_Pitfall_` |
| `## Claude Code` | `_Claude Code_` |
| `## Rust` | `_Rust_` |
| `## Go` | `_Go_` |
| `## JavaScript / TypeScript` | `_JS/TS_` |
| `## Svelte` | `_Svelte_` |
| `## Python` | `_Python_` |
| `## Ruby` | `_Ruby_` |
| `## Rails` | `_Rails_` |
| `## Kubernetes / CUE / kapply` | `_K8s_`, `_K8s/CUE_`, or `_kapply_` (use `_K8s_` for general Kubernetes best-practices — scheduling, security, probes, namespaces; use `_K8s/CUE_` for CUE-schema and manifest-rendering topics; use `_kapply_` for kapply-tool-specific behavior) |
| `## Terraform / Terragrunt` | `_Terraform_` or `_Terragrunt_` (use the specific tool the entry applies to) |

Using the verbatim header (e.g., `_JavaScript / TypeScript_`) instead of the canonical abbreviation (`_JS/TS_`) breaks the dedup logic in `best-practices-sync` — the existing sync entries use the abbreviated forms.

## File Bootstrap

If `~/.claude/BEST_PRACTICES.md` does not exist, create it with this header before appending:

```markdown
# Global Best Practices

Cross-project accumulator. Entries here are candidates for promotion into the bytewyrd plugin's sync content via `/best-practices-sync`. Once promoted, sync removes them from this file.

Format: **[YYYY-MM-DD]** _Category_: Concise statement (1–2 sentences max).
```

If the target section header (`## <Category>`) does not exist, append it (with a blank line before) before writing the entry.

## Red Flags — Stop and Reconsider

- The statement is more than 2 sentences → ask the user to compress it before recording.
- The statement is project-specific ("our deploy script does X") → suggest `/best-practices-extract` instead.
- The statement is a library quirk ("the K8s HPA controller does X") → that's library documentation; suggest looking it up via Context7 / Exa instead of recording.
- A near-duplicate already exists under the target section → present the existing entry and ask whether to replace, append, or skip.
