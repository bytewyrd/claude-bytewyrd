---
name: rfc-new
description: Use to create a new RFC. Generates a date-based identifier, creates the file from template, spawns rfc-architect to fill it in, runs review agents, runs consensus review, fixes critical findings, and presents the finished Draft to the human. Triggered by "/rfc-new <description>".
---

# RFC New

Creates a new RFC, runs agent review, runs consensus review, fixes any critical findings, and presents a finished Draft to the human. The RFC stays in `Draft` status — it is not approved until the human runs `/rfc-approve`.

## Steps

### 1. Get description

If an argument is provided, use it as the description and proceed to Step 2.

If no argument is provided:

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-braindump-list.sh")"
entries_count="$(printf '%s' "$result" | jq '.entries | length')"
```

If `$entries_count` is greater than 0, iterate with `printf '%s' "$result" | jq -r '.entries[] | "\(.n)\t\(.body)"'` to present them as a numbered list and ask "Pick a number to promote, or describe a new RFC." If the user picks a number `N`, use `printf '%s' "$result" | jq -r --argjson n "$N" '.entries[] | select(.n == $n) | .body'` as the description. If they type something else, use that as the description.

If `$entries_count` is 0 (no braindump file or no entries), ask: "What is this RFC about?"

### 2. Scope check

If the description covers multiple clearly independent subsystems, say:
> "This sounds like it covers [X] and [Y] independently. Consider two separate RFCs — one per subsystem — so each can be implemented and reviewed on its own. Continue as one RFC, or split?"

Wait for the user's answer before proceeding.

### 3. Choose model tier

Ask the human which model should draft this RFC, via `AskUserQuestion`:

- **Opus (Recommended)** — the default for RFC work. Deep reasoning at standard cost and latency.
- **Fable** — Claude Fable 5, Anthropic's most capable model. Reach for this only on unusually hard or high-stakes RFCs — it costs more, runs longer (extended thinking is always on), can occasionally decline a request outright (`stop_reason: "refusal"`), and requires the organization to have 30-day data retention configured.

Record the answer as the model for step 8's `rfc-architect` spawn (`"opus"` or `"fable"`). This choice affects only the RFC-drafting step — review agents and `/rfc-consensus-review` (step 9) always run at `model: "opus"`, regardless of what drafted the RFC.

### 4. Generate RFC identifier

The RFC identifier is today's date: `YYYY-MM-DD`. Same-day collisions are avoided in practice by topics being different.

```bash
date +%Y-%m-%d
```

### 5. Derive filename

Convert the description to kebab-case (lowercase, spaces → hyphens, remove punctuation). Truncate to ~40 characters at a word boundary if needed.

Filename: `docs/rfcs/YYYY-MM-DD-<kebab-title>.md`

### 6. Write the template file

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

### 7. Remove promoted braindump entry

If the description came from a `docs/rfc-braindump.md` entry (the user selected a number in Step 1), remove that bullet:

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-braindump-remove.sh" "$SELECTED_ENTRY_BODY")"
removed="$(printf '%s' "$result" | jq -r .removed)"
```

Where `$SELECTED_ENTRY_BODY` is the full bullet text *excluding* the leading `* ` marker (e.g., `**Foo.** First entry.`). If `$removed` is `false` (script exited 1), treat as a warning, not an error — the entry may have been removed already. If the description was typed directly by the user (not selected from the braindump list), skip this step.

### 8. Spawn bytewyrd:rfc-architect to fill in the RFC

Spawn a `bytewyrd:rfc-architect` agent (`model: "$RFC_MODEL"`, the choice recorded in step 3) with:
- The user's description
- The path to the created RFC file
- The full project context (relevant code, existing RFCs, docs)
- Instruction: fill in the template completely, remove all `<!-- ... -->` guidance comments, follow the RFC process in `docs/rfc-process.md`, especially the no-placeholders rule and file structure mapping requirement

The `bytewyrd:rfc-architect` agent must **immediately** after writing dispatch the appropriate review agents in parallel (per the review agent selection table in `docs/rfc-process.md`), incorporate their feedback, then run the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present?
3. **Consistency** — type names, signatures, paths match across sections?

### 9. Consensus review and fix loop

After `bytewyrd:rfc-architect` completes step 8, invoke the `/rfc-consensus-review` skill on the new RFC. This runs its own reviewer agents at `model: "opus"` regardless of which model drafted the RFC in step 3.

The consensus review skill runs to completion: it auto-fixes all verified bugs, walks through any design opinions interactively with the human, and reports. Wait for it to finish — including the interactive walk-through — before proceeding to step 10.

**If verified bugs were found and fixed:**

1. Invoke `/rfc-consensus-review` a second time on the updated RFC.
2. If verified bugs still remain after the second pass, do **not** loop further — surface them to the human in step 10.

**If no verified bugs remain:** proceed directly to step 10.

### 10. Present to human

Present the RFC to the human. The RFC stays `status: Draft`. Tell the user:
- Path to the RFC file
- Summary of bugs auto-fixed across review passes
- If verified bugs remain after two fix passes, list them explicitly with a note that they need human attention
- Run `/rfc-read-feedback` to address any inline `FEEDBACK:` comments
- Run `/rfc-approve` when ready to approve

Do **not** commit automatically.
