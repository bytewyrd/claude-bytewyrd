---
name: rfc-approve
description: Use to approve a Draft RFC. Updates status to Approved and commits. This is a human-invoked skill — only humans approve RFCs. Triggered by "/rfc-approve [RFC number or filename]".
---

# RFC Approve

Approves a Draft RFC. Only humans invoke this skill — agents write and review, humans approve.

## Steps

### 1. Identify the RFC

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: RFC-NNN — `docs/rfcs/NNN-title.md`]" — accept a blank response as confirmation of the default.

Read the matching `docs/rfcs/NNN-*.md` file.

### 2. Verify status

Check `status` in the frontmatter. If it is not `Draft`:
- `Approved` → "Already approved."
- `Done` → "Already done."
- `Dropped` → "This RFC was dropped: <drop_reason>."

Stop in any of these cases.

### 3. Display summary for confirmation

Show:
```
RFC NNN — <title>
Status: Draft → Approved
Author: <author>
Created: <date>

Summary: <first paragraph of ## Summary section>

Approve? (yes/no)
```

Wait for explicit confirmation.

### 4. Update status

Change `status: "Draft"` to `status: "Approved"` in the frontmatter.

### 5. Commit

```bash
git add docs/rfcs/<filename>
git commit -m "rfc: approve RFC-NNN — <title>"
```

Report: "RFC-NNN approved and committed. Use `/rfc-implement` to begin implementation."
