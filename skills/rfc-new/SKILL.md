---
name: rfc-new
description: Use to create a new RFC. Generates a date-based identifier, creates the file from template, spawns rfc-architect to fill it in, runs review agents, runs consensus review, fixes critical findings, and presents the finished Draft to the human. Triggered by "/rfc-new <description>".
---

# RFC New

Creates a new RFC, runs agent review, runs consensus review, fixes any critical findings, and presents a finished Draft to the human. The RFC stays in `Draft` status — it is not approved until the human runs `/rfc-approve`.

## Steps

### 1. Get description

If an argument is provided, use it as the description and proceed to Step 2.

If no argument is provided, check whether `docs/rfc-braindump.md` exists and contains bullet entries (`* `). If it does, list the entries numbered:

```
Braindump entries available to promote:

1. Merge `Unit` into `Task` to eliminate two-step trait implementation.
2. Autonomous multi-agent software development system (replace reeve-review).

Pick a number to promote, or describe a new RFC:
```

Wait for the user's response. If they pick a number, use that entry's full text as the description. If they type something else, use that as the description.

If no braindump file exists or it has no entries, ask: "What is this RFC about?"

### 2. Scope check

If the description covers multiple clearly independent subsystems, say:
> "This sounds like it covers [X] and [Y] independently. Consider two separate RFCs — one per subsystem — so each can be implemented and reviewed on its own. Continue as one RFC, or split?"

Wait for the user's answer before proceeding.

### 3. Generate RFC identifier

The RFC identifier is today's date: `YYYY-MM-DD`. Same-day collisions are avoided in practice by topics being different.

```bash
date +%Y-%m-%d
```

### 4. Derive filename

Convert the description to kebab-case (lowercase, spaces → hyphens, remove punctuation). Truncate to ~40 characters at a word boundary if needed.

Filename: `docs/rfcs/YYYY-MM-DD-<kebab-title>.md`

### 5. Write the template file

Create `docs/rfcs/YYYY-MM-DD-<kebab-title>.md` with today's date and the RFC identifier filled in:

```markdown
---
rfc: "YYYY-MM-DD-<kebab-title>"  # must equal filename stem; kebab-title = kebab(title)
title: "<title derived from description>"
author: "<git config user.name>"
status: "Draft"
created: "<YYYY-MM-DD>"
drop_reason: ~
---

## Summary
<!-- One paragraph: what is being proposed and why. ≤5 sentences. -->

## Should we do this?
<!-- Explicit yes/no with brief rationale. Make the decision visible upfront. -->

## Current state
<!-- What exists today that this RFC addresses: what's broken, missing, or constraining. -->

## Analysis / Options
<!-- Trade-offs between approaches; recommend one.
     If two options are operationally identical, present as variants — not separate options. -->

## Implementation spec
<!-- Start with the file structure table. Then list steps.
     No placeholders: every step shows exactly what to do, with actual code and
     exact commands + expected output. -->

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `...` | ... |
| Modify | `...` | ... |

### Steps

<!-- Step-by-step. Each step: what to do + how (code block or command + expected output). -->

## Risks and open questions
<!-- What could go wrong. Unresolved decisions that need answers before or during implementation. -->

## Relationship to other RFCs
<!-- Dependencies, conflicts, or "None." -->
```

Get the author name:
```bash
git config user.name
```

### 6. Spawn rfc-architect to fill in the RFC

Spawn a `rfc-architect` agent (`model: "opus"`) with:
- The user's description
- The path to the created RFC file
- The full project context (relevant code, existing RFCs, docs)
- Instruction: fill in the template completely, remove all `<!-- ... -->` guidance comments, follow the RFC process in `docs/rfc-process.md`, especially the no-placeholders rule and file structure mapping requirement

The `rfc-architect` agent must **immediately** after writing dispatch the appropriate review agents in parallel (per the review agent selection table in `docs/rfc-process.md`), incorporate their feedback, then run the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present?
3. **Consistency** — type names, signatures, paths match across sections?

### 7. Consensus review and fix loop

After `rfc-architect` completes step 6, invoke the `/rfc-consensus-review` skill on the new RFC.

The consensus review skill runs to completion: it auto-fixes all verified bugs, walks through any design opinions interactively with the human, and reports. Wait for it to finish — including the interactive walk-through — before proceeding to step 8.

**If verified bugs were found and fixed:**

1. Invoke `/rfc-consensus-review` a second time on the updated RFC.
2. If verified bugs still remain after the second pass, do **not** loop further — surface them to the human in step 8.

**If no verified bugs remain:** proceed directly to step 8.

### 8. Present to human

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
