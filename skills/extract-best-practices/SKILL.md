---
name: extract-best-practices
description: Use when a session contained design decisions, architectural choices, discovered pitfalls, or established patterns worth preserving — triggered automatically before compaction, manually at any time, or at the end of a development branch.
---

# Extract Best Practices

## Overview

Selectively extract non-obvious learnings from a session and append them to the project's
`BEST_PRACTICES.md`. Quality over quantity — the value is in the filter, not the writing.

## Extraction Pass

Scan the conversation for:
- Design decisions that are non-obvious from reading the code
- Architectural constraints that affect future decisions
- Patterns confirmed as "the right way" for this project
- Pitfalls, anti-patterns, or failed approaches discovered
- Stack/domain-specific gotchas (EVE API, Rust async, Vue reactivity edge cases, etc.)

## Mandatory Filters

**Skip if any of the following are true:**
- Already documented in `CLAUDE.md`, `BEST_PRACTICES.md`, or a code comment
- Technology behavior that belongs in library docs, not project conventions (K8s quirks, serde edge cases, API semantics — look these up, don't memorize them here)
- One-off (environment setup, temporary workaround, single-use debugging step)
- Inferrable by reading the code for 5 minutes
- Would still be true if this project changed frameworks or libraries

**The core test:** Does this rule describe _how this project is built_, not _how a technology works_?

- "Use `thiserror` in lib crates, `anyhow` in binaries" → project convention, keep
- "K8s HPA with an empty metrics block is accepted but never scales" → library behavior, skip
- "HPA and `spec.replicas` fight — don't set both" → K8s documentation, skip

**Keep only if:** a developer joining this project specifically would benefit from reading this — not a developer joining any Rust/K8s/JS project.

If nothing passes the filter, say so — "Nothing new to capture this session." Do not pad.

## Generalization Step (Before Presenting Candidates)

For each candidate, ask: **"What is the general principle here, stripped of names, file paths, and implementation details that will change?"**

Rewrite the candidate to express the rule in terms of the _pattern_ — not the specific instance. If an example is necessary to make the rule concrete, make it self-contained (don't reference project-specific names).

The generalized statement must also include enough context to be understood by someone without knowledge of the project or session. Name the technology, layer, or domain the rule applies to so it's self-contained when read in isolation months later.

| Too specific | Too abstract | Good |
|---|---|---|
| "`DetailOverlay` passes compact state via `provide` so slot content can inject it" | "Use provide/inject for state sharing" | "Vue: when a wrapper component renders arbitrary slot content and needs to share state with it, use `provide`/`inject` — slot content has no prop access to its wrapper" |
| "`run_all` calls seeds directly because `impl Future` is incompatible with `dyn Trait`" | "Watch out for trait object issues in Rust" | "Rust: traits with `async fn` / `impl Future` returns can't become `dyn Trait` without boxing. For a small fixed set of impls, explicit dispatch is cleaner than forcing `async-trait`" |

If the rule can't be stated without referencing something project-specific, it's not a best practice — it's a code comment. Skip it.

## User Confirmation (Always Required)

Present candidates as a numbered list with category and one-line context:

```
Found 2 candidates:

1. [Design System] Use `C.*` constants via inline styles for dynamic colors; CSS custom
   props (`--c-*`) only in `<style scoped>` for static values.

2. [Pitfall] `DetailOverlay` handles animation and backdrop — don't reimplement these
   in individual overlay components.

Add any? (1, 2, both, none)
```

Never write to `BEST_PRACTICES.md` without explicit user approval on specific items.

## Write Format

Append approved items under the appropriate section in `BEST_PRACTICES.md`:

```markdown
- **[YYYY-MM-DD]** _[Category]_: Concise statement. One or two sentences max.
```

Categories: `Design System`, `Architecture`, `Overlays`, `Stores`, `Workflow`, `Pitfall`

Create the section header if it doesn't exist yet.

## Post-Write Check

Verify the project's root `CLAUDE.md` references `BEST_PRACTICES.md`. If not, add:

```
For accumulated session learnings, see [BEST_PRACTICES.md](BEST_PRACTICES.md).
```

## When to Run

- **Automatically:** `PreCompact` hook fires before conversation compaction (configured in `.claude/settings.json`)
- **Manually:** Invoke this skill at any time, especially before ending a long design/feature session
- **Branch completion:** Natural checkpoint in the `finishing-a-development-branch` workflow

## Red Flags — Stop and Reconsider

- You're about to write more than 2 items from one session → you're being too permissive
- The entry describes how a library or external system works → it's a learning, not a practice; skip
- Entry is longer than 2 sentences → consolidate or skip
- Entry could appear in any project's best practices → too generic, skip
- You're adding without asking the user → violation
