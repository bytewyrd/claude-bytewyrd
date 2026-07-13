---
name: rfc-consensus-review
description: Spawns 5 parallel independent reviewer agents on an RFC, synthesizes findings by consensus, verifies factual claims, auto-fixes all verified bugs, then walks the human through design decisions one-by-one with RFC context. Critical = 4-5/5 reviewers; Moderate = 3/5; Minor = 1-2/5. Triggered by "/rfc-consensus-review [RFC number or filename]".
---

# RFC Consensus Review

Spawns five independent reviewer agents, synthesizes findings by consensus, verifies factual claims, auto-fixes all verified bugs, then walks the human through design decisions one-by-one with inline RFC context. Nits are skipped unless the human requests them.

## Consensus tiers

| Consensus | Label |
|-----------|-------|
| 4-5 reviewers | **Critical** |
| 3 reviewers | **Moderate** |
| 1-2 reviewers | **Minor** |

## Finding types

| Type | Meaning | Default action |
|------|---------|----------------|
| `bug` | Verified wrong — confirmed against code/docs | Auto-fix (no confirmation needed) |
| `needs-research` | Factual claim not yet verified | Research first, then re-classify |
| `design` | Correct but debatable design preference | Walk through interactively, one at a time |
| `nit` | Style/clarity only, no correctness impact | Skip unless human requests |

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

### 2. Build previously-addressed context

If this is a repeat invocation in an iteration loop, the caller provides a brief list of topics already fixed in prior rounds. Collect this before spawning reviewers.

Format:
> **Already addressed in prior iterations — do not re-raise unless the fix was incomplete or introduced a new problem.** If you believe a prior fix got something wrong, say specifically what changed and why it's still broken. Do not simply repeat the original concern.
> Topics: [comma-separated list of fixed topics, e.g. "billing-admin fallback comment wording", "validation >= 1 on kill_switch_amount", "requirements-dev.txt runtime deps"]

If no prior context exists, omit this block entirely.

### 3. Spawn 5 parallel reviewer agents

Spawn five `bytewyrd:code-reviewer` agents (`model: "opus"`) in a **single message**. Do not ask for human confirmation first.

Each agent receives the full RFC text and this prompt:

> [Insert previously-addressed block from Step 2, if any]
>
> Review this RFC for correctness, completeness, and design quality. For each finding provide:
> - **Category**: `correctness` | `completeness` | `design` | `clarity`
> - **Severity**: `critical` | `moderate` | `minor`
> - **Confidence**: `high` (you verified against code or docs) | `medium` (strong inference) | `low` (speculation)
> - **Type**: `bug` (definitively wrong or broken) | `opinion` (defensible but you'd do it differently) | `nit` (style/naming only)
> - **Location**: section name, or "general"
> - **Issue**: what is wrong or missing (1–3 sentences)
> - **Fix**: the specific change needed (1–3 sentences)
>
> Only flag things you are reasonably confident about. Include `low`-confidence findings only when the potential impact is high (e.g. a silent failure in production). Skip pure style preferences unless they cause genuine confusion. Do not summarize or praise the RFC. If you find no problems, say "No findings."

### 4. Main-agent synthesis and verification

Once all five agents return:

**4a. Group findings.** Group findings that describe the same underlying issue — same root problem in the same part of the RFC, even if worded differently. For each group record:
- Count (N/5)
- Clearest issue description from any reviewer
- Best-described fix from any reviewer
- Highest severity assigned
- Confidence spread across reviewers (e.g. "2 high, 2 medium, 1 low")

**4b. Verify and classify.** For each group, independently determine its type — do not rely solely on what reviewers labeled it.

- Read the relevant RFC section.
- For any finding that makes a factual claim about GCP behavior, provider semantics, library behavior, or code execution: verify it. Fetch the relevant doc page, grep the code, or read the file. This is mandatory when reviewer confidence is mixed or low, or when the claim is the sole basis for a Critical/Moderate classification.
- Classify as `bug` (verified wrong), `needs-research` (plausible but unconfirmed after reading the RFC), `design` (RFC is defensible; this is a preference), or `nit` (clarity only).
- If verification shows the RFC is already correct, close as `false-positive`. Note the evidence so it can be added to the previously-addressed context for the next iteration.

**4c. Complete any remaining research.** For each `needs-research` finding: fetch docs or read code now. Re-classify as `bug`, `false-positive`, or `design`.

### 5. Apply consensus tiers

Map each group to an action using both count and type:

| Consensus | Type | Action |
|-----------|------|--------|
| Any tier | `bug` | Auto-fix — no confirmation needed |
| Critical (4-5/5) | `design` or `nit` | Walk through interactively |
| Moderate (3/5) | `design` | Walk through interactively |
| Minor (1-2/5) | `design` or `nit` | Skip (offer to walk through if human wants) |

### 6. Auto-fix all verified bugs

Without asking for confirmation, spawn a `bytewyrd:rfc-architect` agent (`model: "opus"`) with:
- The RFC content
- The complete list of verified bugs grouped by tier (Critical → Moderate → Minor)
- Instruction: fix every bug in the list, run the self-review checklist after, do not change status, do not commit

Run the reflow script after prose changes (see memory for the script).

Then print a brief changelog:

```
Auto-fixed N verified bugs:
• [Critical 3/5] Deploy script — added `set -o pipefail;` to bash subshell
• [Moderate 2/5] ResourceRef — added struct definition and from_doc constructor
• ...
```

### 7. Walk through design opinions interactively

For each design finding (highest consensus first), present it one at a time:

```
Design opinion (N/5 reviewers) — <location>

RFC currently says:
  <relevant excerpt, 3-8 lines>

Concern: <issue in 1-2 sentences>
Suggested change: <fix in 1-2 sentences>

Address this? (yes / no / skip all remaining)
```

Wait for a response before presenting the next item. Apply confirmed fixes immediately (via direct edit or a targeted `bytewyrd:rfc-architect` call if the change is non-trivial). If the human says "skip all remaining", stop the loop.

### 8. Final report

After all fixes and decisions:

```
Consensus review complete.
• N bugs auto-fixed
• N design opinions addressed, N skipped
• N nits available on request
• N findings closed as false-positive

RFC is ready. Run /rfc-approve when satisfied.
```

Do **not** change `status`. Do **not** commit automatically.

### 9. Caller protocol

Behavior is the same whether invoked standalone or from `/rfc-new`: auto-fix all verified bugs (Step 6), walk through design opinions interactively (Step 7), then report (Step 8). There is no "return findings to caller" mode — the walk-through always happens here, in the main conversation, so the human never needs to re-invoke the skill to see design opinions.
