---
name: rfc-drop
description: Use to drop an RFC that will not be implemented. Sets status to Dropped, records the reason, and commits. Triggered by "/rfc-drop [RFC number or filename] [reason]".
---

# RFC Drop

Marks an RFC as Dropped with a recorded reason. Dropped RFCs are permanent historical record — files and numbers are never reused or deleted.

## Steps

### 1. Identify the RFC and reason

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: RFC-NNN — `docs/rfcs/NNN-title.md`]" — accept a blank response as confirmation of the default.

If the drop reason is not provided, ask: "Why is this RFC being dropped? (one sentence)"

### 2. Read and verify status

Read the RFC file. Check `status`:
- `Done` → "This RFC is already done — it cannot be dropped."
- `Dropped` → "Already dropped: <drop_reason>."

Stop in either case. Only `Draft` and `Approved` RFCs can be dropped.

### 3. Confirm

Show:
```
RFC NNN — <title>
Status: <current status> → Dropped
Reason: <drop reason>

Drop this RFC? (yes/no)
```

Wait for confirmation.

### 4. Update frontmatter

Set:
```yaml
status: "Dropped"
drop_reason: "<reason>"
```

### 5. Commit

```bash
git add docs/rfcs/<filename>
git commit -m "rfc: drop RFC-NNN — <reason>"
```

Report: "RFC-NNN dropped and committed. The file is preserved as historical record."
