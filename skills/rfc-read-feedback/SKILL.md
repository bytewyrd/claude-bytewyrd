---
name: rfc-read-feedback
description: Use to address inline FEEDBACK: comments that humans have added to an RFC file. Spawns rfc-architect to incorporate each comment, removes the markers, and runs the self-review checklist. Triggered by "/rfc-read-feedback [RFC number or filename]".
---

# RFC Read Feedback

Reads all `FEEDBACK:` markers in an RFC, dispatches `rfc-architect` to address them, removes the markers, and runs the self-review checklist.

## FEEDBACK: marker format

Humans add feedback directly in the RFC file as lines starting with `FEEDBACK:`:

```
FEEDBACK: The implementation spec doesn't cover the authentication failure case. Please add a step for it.
```

A marker applies to the content immediately above it in the same section. Markers may appear anywhere in the document body (not in frontmatter).

## Steps

### 1. Identify the RFC

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: RFC-NNN — `docs/rfcs/NNN-title.md`]" — accept a blank response as confirmation of the default.

Read the matching `docs/rfcs/NNN-*.md` file.

### 2. Find all FEEDBACK: markers

Search for lines starting with `FEEDBACK:`:

```bash
grep -n "^FEEDBACK:" docs/rfcs/<filename>
```

If none found: report **"No FEEDBACK: markers found in <filename>."** and stop.

### 3. Display for human confirmation

List the found comments with their line numbers:

```
Found N FEEDBACK: comment(s) in <filename>:

Line 42: FEEDBACK: The implementation spec doesn't cover authentication failures.
Line 67: FEEDBACK: Option B should be dropped — it's identical to Option A except for naming.

Address these? (yes/no)
```

Wait for confirmation before proceeding.

### 4. Spawn rfc-architect to address the comments

Spawn a `rfc-architect` agent (`model: "opus"`) with:
- The full RFC content
- The list of `FEEDBACK:` comments and their line numbers
- Instruction: address each comment by updating the relevant section, then remove the `FEEDBACK:` line; do not add new `FEEDBACK:` lines; follow the no-placeholders rule

After incorporating feedback, the agent runs the self-review checklist:
1. **Coverage** — every requirement pointed to an implementation spec section?
2. **Placeholder scan** — any prohibited patterns present?
3. **Consistency** — type names, signatures, paths match across sections?

### 5. Write and report

Write the updated RFC. Report a brief summary per comment:

```
Addressed 2 FEEDBACK: comments:
- Line 42: Added "Error handling" step to the implementation spec covering auth failures (401 response, token invalidation).
- Line 67: Removed Option B; folded the naming note into Option A as a variant.
```

Do **not** change `status`. Do **not** commit automatically.
