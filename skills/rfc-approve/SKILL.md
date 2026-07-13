---
name: rfc-approve
description: Use to approve a Draft RFC. Updates status to Approved and commits. This is a human-invoked skill — only humans approve RFCs. Triggered by "/rfc-approve [RFC number or filename]".
---

# RFC Approve

Approves a Draft RFC. Only humans invoke this skill — agents write and review, humans approve.

## Steps

### 1. Identify the RFC

Resolve the target RFC using the helper script. The script handles the argument-vs-heuristic logic; the agent surfaces the candidate label to the user. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-resolve.sh" "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

`$RFC_PATH` is the resolved absolute path; `$label` is a one-line summary such as `RFC 2026-05-12-foo (unique modified file)`. Show `$label` and ask "Use this RFC? (yes/no)" — accept blank as yes. If the user declines, ask "Which RFC?" and re-run with their answer as `$ARG`. If the script exited non-zero, `result` will contain `{"error":"..."}` — extract with `jq -r .error` and show it. `$RFC_PATH` is used by subsequent steps to identify the file being acted on.

### 2. Verify status

Read the frontmatter:

```bash
fm="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-frontmatter.sh" "$RFC_PATH")"
status="$(printf '%s' "$fm" | jq -r .status)"
drop_reason="$(printf '%s' "$fm" | jq -r .drop_reason)"
```

If `$status` is not `Draft`:
- `Approved` → "Already approved."
- `Done` → "Already done."
- `Dropped` → "This RFC was dropped: $drop_reason."

Stop in any of these cases.

### 3. Display summary for confirmation

Show:
```
RFC <identifier> — <title>
Status: Draft → Approved
Author: <author>
Created: <date>

Summary: <first paragraph of ## Summary section>

Approve? (yes/no)
```

Wait for explicit confirmation.

### 4. Update status

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-set-status.sh" "$RFC_PATH" Approved)"
old="$(printf '%s' "$result" | jq -r .old_status)"
new="$(printf '%s' "$result" | jq -r .new_status)"
```

The script validates the new status and rewrites the frontmatter in place. Use `$old` and `$new` in the agent's running log (e.g., `rfc-set-status: <path>: Draft -> Approved`).

### 5. Commit

```bash
git add "$RFC_PATH"
git commit -m "rfc: approve RFC <identifier> — <title>"
```

Report: "RFC <identifier> approved and committed. Use `/rfc-implement` to begin implementation."
