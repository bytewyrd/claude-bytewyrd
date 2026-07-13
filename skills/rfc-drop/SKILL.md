---
name: rfc-drop
description: Use to drop an RFC that will not be implemented. Sets status to Dropped, records the reason, and commits. Triggered by "/rfc-drop [RFC number or filename] [reason]".
---

# RFC Drop

Marks an RFC as Dropped with a recorded reason. Dropped RFCs are permanent historical record — files and numbers are never reused or deleted.

## Steps

### 1. Identify the RFC and reason

Resolve the target RFC. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-resolve.sh" "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

(Same confirmation flow as rfc-approve: show `$label`, ask the user to confirm. On non-zero exit, parse `.error` from `$result` and show it. `$RFC_PATH` carries the resolved absolute path into the steps below.)

If the drop reason is not provided, ask: "Why is this RFC being dropped? (one sentence)"

### 2. Read and verify status

```bash
fm="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-frontmatter.sh" "$RFC_PATH")"
status="$(printf '%s' "$fm" | jq -r .status)"
drop_reason="$(printf '%s' "$fm" | jq -r .drop_reason)"
```

If `$status` is `Done` → "This RFC is already done — it cannot be dropped." If `Dropped` → "Already dropped: $drop_reason." Stop in either case. Only `Draft` and `Approved` RFCs can be dropped.

### 3. Confirm

Show:
```
RFC <identifier> — <title>
Status: <current status> → Dropped
Reason: <drop reason>

Drop this RFC? (yes/no)
```

Wait for confirmation.

### 4. Update frontmatter

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-set-status.sh" "$RFC_PATH" Dropped "$REASON")"
```

The script writes `status: "Dropped"` and `drop_reason: "<REASON>"` atomically. If `$REASON` is empty the script exits 2 with `{"error":"..."}` on stdout — extract via `jq -r .error` and re-prompt for a reason.

### 5. Commit

```bash
git add "$RFC_PATH"
git commit -m "rfc: drop RFC <identifier> — <reason>"
```

Report: "RFC <identifier> dropped and committed. The file is preserved as historical record."
