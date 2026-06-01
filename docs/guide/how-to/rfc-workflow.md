# RFC workflow — skill command reference

The plugin ships eight skills that cover the complete RFC lifecycle, from quick idea capture through implementation and archival. Each section below is a task recipe — one skill, one job.

For the full RFC process (when to write an RFC, what makes a good one, how review cycles work from the outside), see [docs/guide/how-to/rfc-process.md](rfc-process.md).

---

## Capture a quick idea

**Skill:** `/rfc-braindump <idea>`

Use this when you have a raw thought that is not yet ready to become a full RFC. The skill uses an Opus agent with extended thinking to distill your idea into a tightly-written paragraph entry and appends it to `docs/rfc-braindump.md`.

Nothing is designed at this stage — the braindump is a lightweight parking lot. Ideas stay there until you are ready to promote one to a full RFC with `/rfc-new`.

```
/bytewyrd:rfc-braindump Add a --dry-run flag to the sync skill so teams can preview changes before applying
```

The skill asks one clarifying question if your idea is too vague, then confirms the entry added.

---

## Create a new RFC

**Skill:** `/rfc-new <description>`

Creates a new RFC, runs agent review, runs consensus review, fixes any critical findings, and presents a finished Draft for your review.

If you do not pass a description, the skill lists any existing braindump entries so you can promote one directly.

```
/bytewyrd:rfc-new Add a --dry-run flag to the sync skill
```

What happens under the hood (you do not need to manage this):

1. A dated file is created at `docs/rfcs/YYYY-MM-DD-<kebab-title>.md` with status `Draft`.
2. The `rfc-architect` agent (Opus) fills in the full RFC from your description and project context.
3. Domain-specific review agents run in parallel and feed back to `rfc-architect`.
4. `/rfc-consensus-review` runs: five independent reviewers synthesize findings. Verified bugs are auto-fixed; design opinions are walked through with you interactively.
5. The RFC is presented to you in `Draft` status.

The RFC is not approved until you explicitly run `/rfc-approve`.

---

## Incorporate inline feedback comments

**Skill:** `/rfc-read-feedback [RFC]`

After reviewing a Draft RFC, add `FEEDBACK:` comments directly in the RFC file, then run this skill. The `rfc-architect` agent addresses each comment, removes the markers, and runs the self-review checklist.

Format for an inline feedback comment:

```markdown
## Implementation spec

The proposed step order does not handle the rollback case.
FEEDBACK: Please add a rollback step after step 3 that reverts the database migration if the deploy fails.
```

Then invoke:

```
/bytewyrd:rfc-read-feedback 2026-05-10-my-rfc
```

The skill resolves the RFC by name, date prefix, or defaults to the most recently modified RFC if no argument is given.

---

## Run consensus review

**Skill:** `/rfc-consensus-review [RFC]`

Spawns five independent reviewer agents, synthesizes their findings by consensus, verifies factual claims, auto-fixes all verified bugs, and walks you through design opinions one at a time.

```
/bytewyrd:rfc-consensus-review 2026-05-10-my-rfc
```

Consensus tiers:

| Consensus | Label |
|-----------|-------|
| 4-5 of 5 reviewers agree | Critical |
| 3 of 5 reviewers agree | Moderate |
| 1-2 of 5 reviewers agree | Minor |

- **Bugs** (verified wrong): auto-fixed without asking.
- **Design opinions** (Critical or Moderate): presented to you interactively, one at a time.
- **Minor opinions / nits**: skipped unless you request them.

`/rfc-new` runs this automatically. Use it standalone when you add significant new content to a Draft or want a fresh review pass after addressing feedback.

---

## Approve an RFC

**Skill:** `/rfc-approve [RFC]`

Marks a Draft RFC as Approved and commits the status change. Only humans invoke this skill — agents write and review, humans approve.

```
/bytewyrd:rfc-approve 2026-05-10-my-rfc
```

The skill confirms the RFC and its summary, waits for your explicit confirmation, updates `status: "Approved"` in the frontmatter, and commits. After approval, run `/rfc-implement` to begin implementation.

---

## Implement an RFC

**Skill:** `/rfc-implement [RFC]`

Begins implementing an Approved RFC by spawning a `feature-engineer` agent (Opus) with the full RFC as its spec. The agent follows the implementation spec exactly; it does not redesign.

```
/bytewyrd:rfc-implement 2026-05-10-my-rfc
```

The skill checks that the RFC is in `Approved` status and scans the spec for any unresolved `REVIEW:` markers or placeholder language before spawning the agent. If the spec is ambiguous, it surfaces the gap — update the RFC rather than letting the agent guess.

After the PR is merged, the skill marks the RFC `Done` and commits.

---

## Track in-flight RFCs

**Skill:** `/rfc-summary`

Lists every RFC currently in `Draft` or `Approved` status, grouped by status, oldest first. Done and Dropped RFCs are filtered out — this is a standup-style snapshot of active work.

```
/bytewyrd:rfc-summary
```

No arguments. Read-only; no files are modified.

---

## Drop an RFC

**Skill:** `/rfc-drop [RFC] [reason]`

Marks an RFC as Dropped and records the reason. Dropped RFCs are permanent historical record — files are never deleted or reused.

```
/bytewyrd:rfc-drop 2026-05-10-my-rfc "Superseded by 2026-06-01-better-approach"
```

Only `Draft` and `Approved` RFCs can be dropped. `Done` RFCs cannot be dropped — they are already complete.

---

## Related

- [In-depth RFC process guide](rfc-process.md) — when to write an RFC, what makes a strong RFC, how to interpret the review cycle.
