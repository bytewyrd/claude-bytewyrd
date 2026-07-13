---
name: rfc-implement
description: Use to begin implementing an Approved RFC. Spawns a feature-engineer agent with the RFC as primary input and marks the RFC as Done when complete. Triggered by "/rfc-implement [RFC number or filename]".
---

# RFC Implement

## Requirement check

This skill creates a pull request at the end of implementation. PR creation uses the GitHub MCP when available, falling back to the `gh` CLI:

```bash
mcp_out="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/tool-probe.sh" github-mcp)"; mcp_status=$?
gh_out="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/tool-probe.sh" gh)";           gh_status=$?
mcp_result="$(printf '%s' "$mcp_out" | jq -r .result)"
gh_result="$(printf '%s' "$gh_out"  | jq -r .result)"
```

- `mcp_status=0` (i.e. `$mcp_result` = `available`) → use the `mcp__plugin_github_github__create_pull_request` MCP tool. Print: `Using GitHub MCP for PR creation.`
- `mcp_status!=0 && gh_status=0` → fall back to `gh pr create`. Print: `GitHub MCP not enabled — using gh CLI for PR creation.`
- both nonzero → abort PR creation with: `Cannot create PR: neither GitHub MCP nor gh CLI is available. Fix: install github@claude-plugins-official OR install gh CLI and run gh auth login.` (Use `printf '%s' "$gh_out" | jq -r .hint` and the matching hint from `$mcp_out` to phrase the remediation precisely.)

`$gh_result` carries one of `available`, `missing`, or `unauthenticated`; use it when the message text needs to distinguish "gh not installed" from "gh not logged in." The implementation itself (code edits, commit, push) completes regardless of which PR-creation path is taken.

Implements an Approved RFC by spawning a `feature-engineer` agent and marking the RFC `Done` when complete.

## Steps

### 1. Identify the RFC

Resolve the target RFC using the helper script. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-resolve.sh" "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

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
