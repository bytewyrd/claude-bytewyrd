---
name: rfc-implement
description: Use to begin implementing an Approved RFC. Spawns a feature-engineer agent with the RFC as primary input and marks the RFC as Done when complete. Triggered by "/rfc-implement [RFC number or filename]".
disable-model-invocation: true
compatibility: "Claude Code only: relies on Claude Code subagents, AskUserQuestion or ~/.claude paths. Helper scripts need git, jq, bash >= 4 and python3 >= 3.11."
---

# RFC Implement

## Requirement check

This skill creates a pull request at the end of implementation. Because the `github@claude-plugins-official` plugin is a hard dependency of bytewyrd, PR creation uses the GitHub MCP server's `create_pull_request` tool.

Implements an Approved RFC by spawning a `feature-engineer` agent and marking the RFC `Done` when complete.

## Steps

### 1. Identify the RFC

Resolve the target RFC using the helper script. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-resolve.sh" "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.

Show `$label` and ask "Use this RFC? (yes/no)" — accept blank as yes. If the script exited non-zero, extract `.error` from `$result` and show it.

Read the matching RFC file in full.

### 2. Verify status

If status is not `Approved`:
- `Draft` → "This RFC hasn't been approved yet. Run `/rfc-approve` first."
- `Done` → "Already implemented."
- `Dropped` → "This RFC was dropped: <drop_reason>."

Stop in any of these cases.

### 3. Check for ambiguity

Scan the implementation spec for any remaining `REVIEW:` markers or placeholder language ("TBD", "TODO", etc.). If found:
> "The implementation spec has unresolved items. Run `/rfc-reviews` or update the RFC before implementing."
Stop.

### 4. Spawn bytewyrd:feature-engineer agent

Spawn a `bytewyrd:feature-engineer` agent (`model: "opus"`) with:
- The full RFC content as primary input
- The instruction to follow the implementation spec exactly — not redesign, not extend scope
- If the spec is ambiguous on any point: stop, update the RFC via `bytewyrd:rfc-architect` + `/rfc-reviews`, get it re-approved, then resume

Do **not** start implementation if the spec has gaps. Fix the RFC first.

### 5. Mark Done after merge

After the PR is merged:

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-set-status.sh" "$RFC_PATH" Done)"
git add "$RFC_PATH"
git commit -m "rfc: mark $(basename "${RFC_PATH%.md}") done"
```

`$result` is the JSON object `{"file": "...", "old_status": "Approved", "new_status": "Done"}` — extract fields with `jq -r` if the agent wants to surface the transition in its log. Report: "RFC <identifier> marked as Done."
