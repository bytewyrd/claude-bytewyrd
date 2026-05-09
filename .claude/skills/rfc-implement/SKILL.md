---
name: rfc-implement
description: Use to begin implementing an Approved RFC. Spawns a feature-engineer agent with the RFC as primary input and marks the RFC as Done when complete. Triggered by "/rfc-implement [RFC number or filename]".
---

# RFC Implement

Implements an Approved RFC by spawning a `feature-engineer` agent and marking the RFC `Done` when complete.

## Steps

### 1. Identify the RFC

If an RFC number or filename is provided as argument, use it. Otherwise:

1. Run `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/`. If exactly one RFC file appears as modified or staged, treat it as the candidate.
2. If none or multiple are modified, list files in `docs/rfcs/` sorted by name and take the last (most recently dated) as the candidate.
3. Ask: "Which RFC? [default: RFC-NNN — `docs/rfcs/NNN-title.md`]" — accept a blank response as confirmation of the default.

Read the matching `docs/rfcs/NNN-*.md` file in full.

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

### 4. Spawn feature-engineer agent

Spawn a `feature-engineer` or `feature-dev:feature-dev` agent (`model: "opus"`) with:
- The full RFC content as primary input
- The instruction to follow the implementation spec exactly — not redesign, not extend scope
- If the spec is ambiguous on any point: stop, update the RFC via `rfc-architect` + `/rfc-reviews`, get it re-approved, then resume

Do **not** start implementation if the spec has gaps. Fix the RFC first.

### 5. Mark Done after merge

After implementation is complete and the PR is merged, update the RFC:
- Change `status: "Approved"` to `status: "Done"`
- Commit: `"rfc: mark RFC-NNN done — <title>"`

Report: "RFC-NNN marked as Done."
