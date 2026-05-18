---
rfc: "2026-05-17-replace-braindump-prompt-with-ask-user-question"
title: "Replace numbered braindump prompt in /rfc-new with AskUserQuestion"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

When `/rfc-new` is invoked without an argument, it currently prints braindump entries as a numbered text list and asks the user to type a number — an interaction that is both error-prone and slower than clicking. This RFC replaces that numbered-list prompt with an `AskUserQuestion` call so each braindump entry surfaces as a native clickable option in the Claude Code UI, with the entry title as the label and the full entry text as the description. The change is scoped strictly to the no-argument path of Step 1 in `skills/rfc-new/SKILL.md`; explicit-argument invocations bypass Step 1 entirely and are unaffected. Because `AskUserQuestion` is limited to 4 options per question and 4 questions per call (Exa: `https://code.claude.com/docs/en/agent-sdk/user-input`), the implementation paginates across multiple questions when the braindump has more than 3 entries, with a "Create new RFC from scratch" escape hatch occupying the fourth slot on the first question.

## Should we do this?

**Yes.** The current flow asks users to type a number from a printed list — a text-based interaction in an environment designed for point-and-click. Typing the wrong number selects the wrong RFC idea. The `AskUserQuestion` UI renders each option with a label and a description field visible at a glance, reducing both the chance of mis-selection and the time spent reading the terminal output to recall which number was which. The cost is a rewrite of roughly twenty lines in `skills/rfc-new/SKILL.md`; the upside is a materially better first interaction for a skill that users invoke at the start of every new RFC. The pagination design addresses the hard constraint (`AskUserQuestion` accepts at most 4 options per question, verified below) without imposing an artificial cap on the braindump size.

## Current state

`skills/rfc-new/SKILL.md` Step 1 implements the no-argument path as follows (verified: `skills/rfc-new/SKILL.md:L14-L23`):

```
If no argument is provided:

  result="$(bash scripts/rfc-braindump-list.sh)"
  entries_count="$(printf '%s' "$result" | jq '.entries | length')"

If $entries_count is greater than 0, iterate with
  printf '%s' "$result" | jq -r '.entries[] | "\(.n)\t\(.body)"'
to present them as a numbered list and ask
  "Pick a number to promote, or describe a new RFC."
If the user picks a number N, use
  printf '%s' "$result" | jq -r --argjson n "$N" '.entries[] | select(.n == $n) | .body'
as the description. If they type something else, use that as the description.
```

`scripts/rfc-braindump-list.sh` reads `docs/rfc-braindump.md`, extracts every `* …` bullet, and emits a JSON object `{"entries": [{"n": 1, "body": "<text-without-leading-star-space>"}, …]}` (verified: `scripts/rfc-braindump-list.sh:L23-L52`). An absent file or an empty file yields `{"entries": []}`.

The downstream Step 6 removes the selected entry from the braindump file only when the description came from a braindump selection — identified by the user having picked a number, not by having typed new text (verified: `skills/rfc-new/SKILL.md:L103-L112`). This tracking requirement carries over unchanged into the new design: the skill must still know whether the chosen description came from the braindump so it can remove the entry.

**What is broken:**

1. **Typing a number is error-prone.** With 8–10 entries in the braindump, mistyping `3` when intending `8` silently starts an RFC on the wrong idea. The user has no confirmation screen.
2. **Descriptions are truncated.** The numbered list prints the full body text, which often wraps across terminal lines, making it hard to scan entries at a glance. The `AskUserQuestion` UI renders label and description in distinct visual slots designed for this use case.
3. **The escape hatch ("describe a new RFC") requires the user to type prose**, interrupting the click-based flow.

## Analysis / Options

The only meaningful design question is how to handle pagination when the braindump has more than 3 entries. The `AskUserQuestion` constraint is hard: exactly 2–4 options per question, 1–4 questions per call (Exa: `https://code.claude.com/docs/en/agent-sdk/user-input`). With 1 slot reserved for the "Create new RFC from scratch" escape hatch on the first question, the first question holds at most 3 braindump entries. Subsequent questions (up to 3 more in the same call) can each hold 4 braindump entries. A single `AskUserQuestion` call therefore covers at most 3 + (3 × 4) = 15 entries. The current braindump has 9 entries (verified: `docs/rfc-braindump.md`), which fits within one call.

Two pagination strategies are worth comparing.

### Option A — Single call with fixed slots (recommended)

Always issue a single `AskUserQuestion` call with as many questions as the braindump requires, up to the 4-question maximum. The first question always includes the "Create new RFC from scratch" escape hatch as one of its options. Questions 2–4 (if needed) carry only braindump entries (up to 4 per question). If the braindump has more than 15 entries, show the first 15 and append a note that the remainder are accessible via the braindump file directly.

**Slot layout:**

| Question | Slots | Content |
|----------|-------|---------|
| Q1 | 1–3 | First 3 braindump entries |
| Q1 | 4 | "Create new RFC from scratch" escape hatch |
| Q2 | 1–4 | Entries 4–7 (if present) |
| Q3 | 1–4 | Entries 8–11 (if present) |
| Q4 | 1–4 | Entries 12–15 (if present) |

When the braindump has 3 or fewer entries, only Q1 is emitted; the escape hatch fills the remaining slot(s) so `AskUserQuestion`'s minimum of 2 options per question is always satisfied even with 1 braindump entry.

**Why this is preferred:** The user sees all relevant entries in a single interaction. Requiring the user to answer "show more" before seeing later entries (the alternative below) adds friction for what is structurally a single decision.

**Why the escape hatch lives only in Q1:** Placing it in every question would consume a slot on each page and reduce per-page entry density. Placing it only in Q1 keeps later questions dense and relies on the user understanding that Q1 is the "also, skip to new" page — which is semantically correct since Q1 appears first.

### Option B — Multi-call pagination ("show more")

Issue one question at a time. If the user picks a "Show more entries" option, issue another `AskUserQuestion` call for the next page. Continue until the user selects an entry or the escape hatch.

This avoids the 15-entry ceiling per invocation but introduces a "show more" affordance that does not map naturally to how braindumps are used — users scan the full list before deciding, not page through results. It also requires the skill to carry state (which page we are on) across multiple `AskUserQuestion` calls, which is harder to reason about and test. Rejected: more complexity, worse UX for the common case.

## Drawbacks

1. **15-entry ceiling per invocation.** A braindump with more than 15 entries will have the tail silently truncated in the UI, with a note appended. In practice the braindump is regularly pruned by promoting entries; a 15-entry hard cap has never been hit in the project's history. If the braindump grows beyond 15, the user can still access entries 16+ by running `bash scripts/rfc-braindump-list.sh | jq '.entries[] | select(.n > 15)'` or by opening the file directly.

2. **The escape hatch is only on Q1.** If the user's desired new RFC idea is not in the braindump, they must use the option on Q1. This is always visible since Q1 is the first and (for small braindumps) only question. It becomes slightly less obvious when the braindump is large enough to span multiple questions, since Q2–Q4 have no escape hatch. The description of the Q1 escape hatch option explicitly says "not listed above or below" to signal its role across all pages.

3. **`AskUserQuestion` is not available in subagents.** The skill runs in the main conversation context, not a subagent, so this limitation does not apply here (Exa: `https://code.claude.com/docs/en/agent-sdk/user-input`). Recorded for clarity.

4. **`AskUserQuestion` does not provide an automatic free-text input slot.** The SDK docs state that free-text capability must be explicitly implemented by the application — it is not a built-in affordance (Exa: `https://code.claude.com/docs/en/agent-sdk/user-input`). This RFC does not require a separate free-text slot because the "Create new RFC from scratch" escape hatch on Q1 already covers the "describe a new idea not in the braindump" path: the user selects the escape hatch and then answers a plain-text follow-up question. The concern about a user typing a legacy braindump number no longer applies — there is no text input field, and the numbered-list prompt is gone entirely, so users have no visual cue prompting them to type a number.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `skills/rfc-new/SKILL.md` | Rewrite Step 1's no-argument branch to use `AskUserQuestion`. All other steps are unchanged. |

No new scripts, no new agents, no changes to `scripts/rfc-braindump-list.sh`, `scripts/rfc-braindump-remove.sh`, or any other file.

### Steps

#### Step 1 — Rewrite the no-argument branch of Step 1 in `skills/rfc-new/SKILL.md`

Open `skills/rfc-new/SKILL.md`. Locate the `### 1. Get description` section (lines 12–26). The section currently reads (verified: `skills/rfc-new/SKILL.md:L12-L26`):

```
### 1. Get description

If an argument is provided, use it as the description and proceed to Step 2.

If no argument is provided:

  result="$(bash scripts/rfc-braindump-list.sh)"
  entries_count="$(printf '%s' "$result" | jq '.entries | length')"

If $entries_count is greater than 0, iterate with `printf '%s' "$result" | jq -r '.entries[] | "\(.n)\t\(.body)"'` to present them as a numbered list and ask "Pick a number to promote, or describe a new RFC." If the user picks a number N, use `printf '%s' "$result" | jq -r --argjson n "$N" '.entries[] | select(.n == $n) | .body'` as the description. If they type something else, use that as the description.

If $entries_count is 0 (no braindump file or no entries), ask: "What is this RFC about?"
```

Replace the entire `### 1. Get description` block with the following content (everything from the `### 1. Get description` heading through the final blank line before `### 2. Scope check`):

```markdown
### 1. Get description

If an argument is provided, use it as the description and proceed to Step 2. Track
`selected_from_braindump = false` for Step 6.

If no argument is provided:

```bash
result="$(bash scripts/rfc-braindump-list.sh)"
entries_count="$(printf '%s' "$result" | jq '.entries | length')"
```

**Case A — no braindump entries (`$entries_count` is 0):**

Ask: "What is this RFC about?" and use the user's response as the description. Track
`selected_from_braindump = false`.

**Case B — braindump has entries (`$entries_count` is greater than 0):**

Extract up to 15 entries from the JSON result:

```bash
printf '%s' "$result" | jq -r '.entries[:15][] | "\(.n)\t\(.body)"'
```

Build an `AskUserQuestion` call using the following slot layout. Each braindump entry
becomes one option: the first sentence of `.body` (up to 60 characters, truncated at
the last word boundary before the limit and appended with `…` if truncated) is the
`label`; the full `.body` text is the `description`. The escape hatch option is always:

```
label: "Create new RFC from scratch"
description: "None of the braindump entries below (or on other pages) match — describe a new RFC idea instead."
```

Slot layout:

- **Question 1** — up to 3 braindump entries (entries 1–3) + the escape hatch option as
  the 4th option. If the braindump has only 1 or 2 entries, still place the escape hatch
  in the last slot (questions require at least 2 options, and the escape hatch always
  counts as one).
- **Question 2** — entries 4–7, if present (up to 4 options, no escape hatch).
- **Question 3** — entries 8–11, if present (up to 4 options, no escape hatch).
- **Question 4** — entries 12–15, if present (up to 4 options, no escape hatch).

Use `multiSelect: false` for every question — the user selects exactly one entry to
promote. Set `header` for each question to `"Braindump"` (max 12 characters).

If `$entries_count` is greater than 15, append this note before issuing the
`AskUserQuestion` call (as plain text in the conversation, not inside the tool call):

> "Your braindump has N entries; showing the first 15. To promote entries 16 and beyond,
> open `docs/rfc-braindump.md` and copy the idea text, then re-run `/rfc-new <description>`."

Issue the `AskUserQuestion` call with all applicable questions (1 to 4) in a single
invocation.

**AskUserQuestion response schema:**

When `AskUserQuestion` returns, the response is an `answers` object keyed by the `question`
field text of each question, with each value being the `label` of the selected option
(Exa: `https://code.claude.com/docs/en/agent-sdk/user-input`). The user answers each question
independently; since `multiSelect: false` is used, each value is a single label string. For
example, if Q1 is `"Which braindump entry should become an RFC?"` and the user selects the
escape hatch:

```json
{
  "answers": {
    "Which braindump entry should become an RFC?": "Create new RFC from scratch",
    "Which braindump entry? (continued, 4–7)": "<label of whichever Q2 option user picked>"
  }
}
```

The user picks one option per question. To map the returned label back to a braindump entry:

1. Before issuing the call, build a label-to-entry lookup table from the in-memory JSON:
   `label_to_entry = { truncated_label_text: entry_object }` for every braindump option
   across all questions.
2. When the answer comes back, iterate over `answers` values. The first value that is a key
   in `label_to_entry` is the selected braindump entry. The first value that equals the escape
   hatch label is the escape hatch selection.
3. Only one question's answer will be actionable per invocation (the user selects an entry
   from exactly one question); the other answers can be ignored.

**Interpreting the user's response:**

- If any returned label matches the **escape hatch option** (`"Create new RFC from scratch"`):
  ask a follow-up plain-text question "What is this RFC about?" and use the response as
  the description. Track `selected_from_braindump = false`.

- If any returned label matches a **braindump entry option** (found in `label_to_entry`):
  use the full `.body` text of the matched entry as the description. Track
  `selected_from_braindump = true` and record `selected_entry_body` as that full `.body`
  text (used in Step 6 to remove the entry from the file).
```

Verification:

```bash
grep -n 'numbered list\|Pick a number' skills/rfc-new/SKILL.md
```

Expected output: no matches (exit code 1). The old numbered-list prompt is gone.

```bash
grep -c 'AskUserQuestion' skills/rfc-new/SKILL.md
```

Expected output: at least `1` (the new Step 1 body references `AskUserQuestion`).

```bash
grep -c 'selected_from_braindump' skills/rfc-new/SKILL.md
```

Expected output: at least `5` — one in the explicit-argument fast path (Step 1, argument
provided branch), one in Case A (`selected_from_braindump = false`), one in Case B escape-hatch
path, one in Case B free-text path, and at least one in Step 6 (the gate condition). Four
assignments + one reference in Step 6 = minimum 5 occurrences.

```bash
grep -c 'escape hatch' skills/rfc-new/SKILL.md
```

Expected output: at least `2` (the slot-layout description and the "Interpreting"
response handling).

#### Step 2 — Verify Step 6 references `selected_from_braindump`

Step 6 of `skills/rfc-new/SKILL.md` currently reads (verified: `skills/rfc-new/SKILL.md:L103-L112`):

```
### 6. Remove promoted braindump entry

If the description came from a `docs/rfc-braindump.md` entry (the user selected a number
in Step 1), remove that bullet:

  result="$(bash scripts/rfc-braindump-remove.sh "$SELECTED_ENTRY_BODY")"
  ...

Where $SELECTED_ENTRY_BODY is the full bullet text excluding the leading `* ` marker.
If the description was typed directly by the user (not selected from the braindump list),
skip this step.
```

Update Step 6's gate condition to reference the `selected_from_braindump` variable defined in Step 1, replacing the parenthetical "(the user selected a number in Step 1)" with "(Step 1 set `selected_from_braindump = true`)". The variable `$SELECTED_ENTRY_BODY` maps directly to `selected_entry_body` set in Step 1's Case B response handling. The rest of Step 6 is unchanged.

The updated gate sentence reads:

```
If the description came from a `docs/rfc-braindump.md` entry (Step 1 set
`selected_from_braindump = true`), remove that bullet:
```

And the `$SELECTED_ENTRY_BODY` reference is updated to `$selected_entry_body` (lowercase, matching the variable name assigned in Step 1).

Verification:

```bash
grep -n 'selected_from_braindump\|selected_entry_body' skills/rfc-new/SKILL.md
```

Expected output: lines in Step 1 (the fast path, Case A, Case B, and free-text branches)
and Step 6 (the gate condition and the script argument). At least 5 lines total.

```bash
grep -c 'selected a number' skills/rfc-new/SKILL.md
```

Expected output: `0` — the old phrasing referencing a numbered selection is removed.

#### Step 3 — Smoke test against the current braindump

After editing `skills/rfc-new/SKILL.md`, manually trace the slot layout against the current `docs/rfc-braindump.md` to confirm the question structure is correct.

Run:

```bash
printf '%s' "$(bash scripts/rfc-braindump-list.sh)" | jq '.entries | length'
```

At the time this RFC was drafted, the output is `9` (verified: `docs/rfc-braindump.md`
— 9 bullet entries). The expected slot assignment for 9 entries:

- **Question 1:** entries 1, 2, 3 + escape hatch (4 options total).
- **Question 2:** entries 4, 5, 6, 7 (4 options).
- **Question 3:** entries 8, 9 (2 options — meets the 2-option minimum).
- **Question 4:** not emitted (no entries 10–15).

Confirm the label truncation for entry 1:

```bash
printf '%s' "$(bash scripts/rfc-braindump-list.sh)" | jq -r '.entries[0].body' | cut -c1-60
```

Expected output: the first 60 characters of the first entry's body. The full body of
entry 1 begins with `**Modular Plugin Feature Toggles.**` (verified: `docs/rfc-braindump.md`).
At 60 characters that truncates to `**Modular Plugin Feature Toggles.** Restructure th`; the
label would be `**Modular Plugin Feature Toggles.** Restructure th…` (truncated at last word boundary before 60 chars: `**Modular Plugin Feature Toggles.** Restructure…`).

No file is written by this step. It is a manual verification that the implementer runs
to confirm their understanding of the braindump's current state before finishing the edit.

## Risks and open questions

1. **Braindump grows beyond 15 entries before `/rfc-new` is next updated.** The 15-entry ceiling is documented and the skill emits a user-visible note when it applies. The user can still access tail entries via `/rfc-new <description>` with the text pasted from the braindump file. No data is lost — the braindump file is unchanged; only the UI view is capped.

2. **Legacy habit of typing a number no longer applies.** The new flow presents clickable options only — there is no text field where a user would type `3` and expect entry 3. A user who tries to type in the `AskUserQuestion` UI receives no input box; they must select one of the structured options. This risk was relevant when a free-text fallback was considered part of the design; it does not apply in the current spec since all user interaction flows through option selection or the escape-hatch follow-up question.

3. **Label truncation may cut mid-word.** The spec says truncate at the last word boundary before 60 characters. Entries whose first sentence is a single unbroken token longer than 60 characters (e.g., a long URL or a camelCase identifier) would be truncated at the 60-character hard limit with no word-boundary fallback. In practice, all current braindump entries begin with a `**Title.**` bold span followed by prose; the first word boundary appears well within 60 characters.

4. **`multiSelect: false` is required.** The user must select exactly one entry to promote per `/rfc-new` invocation. Using `multiSelect: true` would allow selecting multiple braindump entries at once, which would conflict with Step 2's scope check (which acts on a single description) and Step 6's single-entry removal. The spec hard-codes `multiSelect: false`.

5. **`AskUserQuestion` not available in subagents.** This skill runs in the main conversation, not a subagent, so the limitation does not apply. The limitation is documented here for completeness in case a future refactor moves the braindump selection into a spawned agent — such a move would require switching back to a plain-text prompt for the selection step.

## Relationship to other RFCs

- **`docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md`** (`Approved`) — modifies `skills/rfc-new/SKILL.md` Step 9 (the "Present to human" closing tips). This RFC modifies Step 1 and Step 6. The two modifications are in disjoint sections of the same file; they can be applied in either order without conflict.

- No other RFC currently modifies `skills/rfc-new/SKILL.md` Step 1 or Step 6.
