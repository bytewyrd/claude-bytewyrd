---
rfc: "2026-11-18-design-only-rfcs"
title: "Design-only RFCs"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-11-18"
drop_reason: ~
---

## Problem

An RFC today doubles as "the implementation spec that agents follow": file tables and exact code [1]. RFCs run long, a median body of 9,013 words across the 24 in `docs/rfcs/`, and plans age while they wait: three approved in May 2026 are unimplemented [2]. After implementation, `/docs-review` runs only when the user types it and stops for approval [3]; a SubagentStop hook writes a sentinel, and the compact hook then reminds Claude to ask for a review [4, 5].

**Scope.** Writing, reviewing and implementing RFCs, and `/docs-review`. #118's other planned RFCs keep the workflow (lifecycle, approve and drop, Done, `implemented_by`) and the reviewer layout [6]. `2026-05-12-post-approval-discretionary-revisions` stays Approved until this RFC's implementation lands; then the user drops it with `/rfc-drop`, giving this RFC as the `drop_reason` [7]. The new checks absorb the cleanup PR's `/rfc-implement` markers item [6].

## Trade-offs

**Doing it**
- Gains: shorter RFCs, quicker to write, review and triage; plans written against current code; after the plan, review in the PR; one decision log.
- Costs:
  - Wherever bytewyrd is enabled, so is superpowers [8]; every session loads all of `using-superpowers` [9, 10], whose rules compete with bytewyrd's ("even a 1% chance"; brainstorm first) and yield only to user instructions such as CLAUDE.md [11].
  - superpowers' skill texts change whenever the official marketplace moves its pin [12].
  - No agent reviews the plan, and docs fixes reach the PR unapproved.
  - Migration: the process doc, seven skills, five agents, hooks, helpers, rules, install and contributor docs, and nine guide pages [13], the last through the new docs step.
  - Two RFC formats share `docs/rfcs/`.

**Not doing it**
- Gains: no new dependency or session context; plans stay under the five-reviewer consensus [14]; docs edits are approved first; no migration.
- Costs: RFC size, review load, aging plans and the reminder loop stay.

## Design

### Format

Sections, after today's frontmatter:

```markdown
## Problem       what it addresses, current state, scope, related RFCs
## Trade-offs    doing it vs not, both sides, no recommendation
## Design        contracts and key changes, then acceptance criteria, and rollback if a revert can't undo it
## Security      only for auth, secrets, permissions, user data or external integrations
## Decision log  every decision made while writing
## References    sources for the [n] markers
```

- **Design is not a plan**: no file list or steps; code only to pin a contract. Acceptance criteria are behavioural and testable.
- **No open decisions** replaces no-placeholders: each choice is logged or left to the plan. While writing, an open question is the line `<!-- OPEN Qn -->` under its log entry, and a helper reports such lines at line starts in the Decision log, outside code fences, as `rfc-feedback-list` does for `FEEDBACK:` [15].
- **Citations**: claims carry `[n]`, and References entry n names the source. `rfc-architect`'s inline `(verified: …)`, `(Context7: …)` and `(Exa: …)` citations become markers, their forms moving into the entries alongside `GitHub:` and `measured:`. A source keeps its number. `[UNVERIFIED — what was tried]` stays inline and unnumbered, and a load-bearing one is a cost in Trade-offs [16]. Every claim is still checked in the session.
- **Size**: Problem through Security aim for about 1,500 words and stay within 2,000, counted with `awk '/^---$/{c++; next} c>=2' FILE | sed '/^## Decision log$/,$d' | wc -w`; past that, split the RFC or leave detail to the plan. The Decision log and References aren't counted, but each log entry stays short: a one-line decision, the alternatives, and one to three sentences of reasoning. No appendices; risks go in Trade-offs.
- **Formats**: an RFC with a `## Summary` heading is old-format, as all 24 today are [17]. Format checks skip old RFCs, so an amended one keeps its format; `/rfc-approve` shows the first paragraph of `## Problem`, or an old RFC's `## Summary` [18].

Entries sit under their date, keep their numbers, and may name a decision briefly when the Design states it; a reversal is a new entry naming what it supersedes:

```markdown
### YYYY-MM-DD
**Dn. <the decision>** (user | agent)
Alternatives: <option>; <option>. Why: <one to three sentences>.
```

Self-review checks the sections, the counted size, testable acceptance criteria, nothing left open, consistent names, short log entries, a marker on every claim and a References entry for every marker. The `rfc-process` skill's process doc is the only statement of these rules: `rfc-architect` drops its own section list and citation format [16], and `/rfc-new`'s template keeps only the frontmatter and section headings [19].

### Writing

- `rfc-architect` decides what the request, code or earlier decisions settle, logging it as the agent's, and asks only what nothing settles and would change what gets built: 2–4 options, trade-offs, a recommendation, and an open-question line holding the entry's place.
- `/rfc-new` asks up to four per AskUserQuestion call [20], resumes the same `rfc-architect` with SendMessage [21], and starts review once the helper finds none. A `/rfc-read-feedback` or `/rfc-consensus-review` pass that leaves an open question runs the same loop.
- Reviewers judge the design, not file lists, steps or code: `code-reviewer`'s completeness test becomes decisions left open or contracts missing [22], and `security-engineer` looks for a Security section [23]. Design findings the user rules on are logged, here and in `/rfc-read-feedback`.

### Implementing

- **Checks**: Approved, with no open-question line or `FEEDBACK:` marker, replacing the placeholder scan [24]; on the default branch, stop and give the worktree command.
- **Plan**: `superpowers:writing-plans` writes `docs/rfcs/<rfc-id>.plan.md` with the RFC as its Spec [25]. The developer approves it, the only in-session approval, and picks subagent-driven or native execution. Execution keeps superpowers' model choices: cheap models for mechanical tasks, the most capable for the final review, the session's own when native [26, 27]. The process doc's Opus rule now covers only writing and reviewing RFCs, and its inline-work rule only writing, reviewing and updating them [1]. `feature-engineer` no longer implements RFCs [28].
- **Run rules**: the plan's Global Constraints, which bind every task [25], carry the RFC's contracts, the base branch and four rules: stay in this checkout [29]; halt on work that would contradict the RFC; a failing baseline stops the run before Task 1 and is reported; end after the final review and final message, without the finishing skill. Otherwise only the executors' safety stops halt them [26].
- **Finish**: `/rfc-implement` appends the executor's rulings and deferred minors to the plan file, runs `/docs-review`, pushes, and opens the PR through the GitHub MCP, as today [24]. The PR description lists rulings, deferred minors and open docs findings. Rulings stay within the approved plan and the RFC, never overriding the boundary.

**Plans aren't RFCs**: `rfc-resolve`'s guesses and identifiers, `rfc-summary` and the repository's frontmatter test skip names ending in `.plan.md` [30–32], and the frontmatter helpers reject them; the rule that `rfc` equals the filename stem [1] covers RFCs only. A later implementing PR gets `<rfc-id>.<n>.plan.md`.

**Boundary**: the RFC fixes scope, contracts and logged decisions; the plan decides the rest. Work that would contradict the RFC stops until the RFC is amended with a superseding entry, returns to Draft and is approved again with `/rfc-approve`, as scaffold-and-drift was [6]. `/rfc-implement` then revises the existing plan for the developer's approval; if task numbers change, it first clears the plan's execution workspace.

### Docs review

- `/docs-review` drops `disable-model-invocation`, which blocks Claude's call unless the user names the skill [33].
- **Where**: only in a repository whose `docs/guide/` holds at least one Markdown file, so a bare `.gitkeep` doesn't count.
- **Triggers**: the end of `/rfc-implement`, and any implemented change before its PR is ready to merge, stated in the skill's description and a new always-on rule (rules 3 and 6 total 1,282 of the test's 2,000 characters [34, 35]):

  ```text
  6. Docs: in repositories whose docs/guide/ holds Markdown pages, run the docs-review skill on the branch's changes once a change is implemented, before its pull request is ready to merge.
  ```

- **No gate**: the docs-agent drops its approval step, its allow-list widens to all of `docs/guide/**` [36], and it applies each finding as its own commit [3]. Automatic runs list missing pages and unsettled findings in the PR description; they don't create pages.
- **Default branch**: it stops and gives the worktree command, as `/rfc-implement` does; with no PR, unsettled findings go to its final report.
- **Scope**: automatic runs take the branch's diff against its base. In `/docs-review` and `/refactor`, an RFC identifier means all its plans' files, or its Design as free text before there's a plan; old RFCs keep their file table [3, 37].
- **Retired**: both reminder hooks, their sentinel and the step that clears it [3, 4].

### superpowers

`.claude-plugin/plugin.json` adds `"superpowers@claude-plugins-official"` to `dependencies`, and every install list names it, the seeded `CLAUDE.md` template included [38]; bytewyrd's marketplace already allows that marketplace [39]. Subagents such as `rfc-architect` ignore `using-superpowers` [11]. Always-on rule 3 grows from 140 to 266 characters [35]:

```text
3. Design: repositories with a docs/rfcs/ directory use RFCs, not superpowers' brainstorming, for changes that need design (rfc-new skill), and implement an approved RFC with the rfc-implement skill, which plans with writing-plans (process in the rfc-process skill).
```

The seeded `CLAUDE.md` template [38] and this repository's `CLAUDE.md` gain one line, since superpowers takes its locations from the user's preference [25, 40]:

```text
- superpowers keeps its own specs and plans in ~/.claude/superpowers/<project>/, <project> being the repository root's absolute path with each character other than a letter or digit turned into -; docs/ holds only RFCs and their plans. With docs/rfcs/, start design with /bytewyrd:rfc-new, not superpowers' brainstorming.
```

Before their first `/rfc-implement` run, adopters change any user-level instruction that forbids `writing-plans` in RFC repositories or keeps an RFC's implementation plan out of `docs/rfcs/`, while superpowers' own specs and plans stay outside the repository; the guide gets an upgrade note saying so.

### Acceptance criteria

1. `/rfc-new` presents Drafts in this format: Problem through Security within 2,000 words, acceptance criteria in Design, no open-question line, and a References entry per `[n]`.
2. Open questions reach the user through AskUserQuestion before the Draft, and are logged as user decisions.
3. `/rfc-implement` writes `docs/rfcs/<rfc-id>.plan.md` and, once it's approved, opens a PR without another prompt unless a safety stop or the boundary halts it.
4. The RFC tools and the frontmatter test skip `.plan.md` files; the frontmatter helpers reject them.
5. `/docs-review` and `/refactor` scope a new-format RFC's identifier to its plans' files, or to its Design before there is a plan.
6. Claude starts `/docs-review` at the end of `/rfc-implement` where `docs/guide/` holds Markdown, and not elsewhere; it commits each finding separately, unprompted, and lists missing pages instead of creating them.
7. `hooks/hooks.json` has no docs reminder; `tests/py/test_hooks.py` passes with rules 3 and 6.
8. `.claude-plugin/plugin.json` lists `superpowers@claude-plugins-official`, and the install-check CI job's install into a clean HOME also installs superpowers, with no plugin errors [41].
9. For an old-format RFC, `/rfc-approve` shows its `## Summary`, and RFC-identifier scopes use its file table.
10. The open-question helper reports such a line in the Decision log and ignores the same text in prose or code fences.
11. The seeded `CLAUDE.md` template and this repository's `CLAUDE.md` carry the superpowers line, and a `writing-plans` run for work that isn't an RFC saves under `~/.claude/superpowers/<project>/`.

**Rollback**: reverting the PR leaves superpowers installed. Adopters who don't use it on its own run `claude plugin uninstall superpowers@claude-plugins-official`, since `claude plugin prune` removes only auto-installed copies [42]. Reverting the seeded `CLAUDE.md` line is another `template-changed` drift [43]. New-format RFCs and `.plan.md` files, which old tools misread, stay; move the plans out of `docs/rfcs/`.

## Security

superpowers is third-party code on every adopter's machine: a SessionStart hook in every session [10], outside the sandbox like all hooks [5], and helper scripts during execution [27], pinned by the official marketplace to one commit [12]. Ungated docs edits reverse #116's gate on `/docs-review` [44]; the `docs/guide/` guard, the docs-agent's boundary and the PR review bound them. No secrets, permissions or user data change.

## Decision log

### 2026-11-18

**D1. Four parts; Trade-offs make no recommendation; Design holds no plan** (user)
Alternatives: today's structure. Why: faster iteration, shorter reading, quicker triage and feedback.

**D2. Every decision is logged; questions are asked before the RFC is final** (user)
Alternatives: a "Risks and open questions" section. Why: a finished RFC leaves nothing open.

**D3. The developer reviews and approves a `writing-plans` plan in the session before any code; then agents work alone to an open PR, stopping only at the RFC/plan boundary** (user)
Alternatives: the RFC carries the plan; no in-session plan review, with the plan reviewed in the PR next to the code. Why: the plan stays the one in-session review. After it, "Agents should work independently as much as possible all the way to pushing changes up to a PR for my review."

**D4. superpowers is a declared dependency** (user)
Alternatives: `writing-plans` if installed, else plan mode; plan mode only; bytewyrd's own step. Why: always available, one plan format, accepting `using-superpowers`' rules in every session.

**D5. Its own RFC, the first in the new format** (user)
Alternatives: a direct PR; part of the RFC-workflow revision. Why: #118's later RFCs follow its format.

**D6. Plans live at `docs/rfcs/<rfc-id>.plan.md`, committed in the implementing PR** (user)
Alternatives: `docs/superpowers/plans/`; a `plans/` folder; outside the repository. Why: found from the RFC's id and reviewed with the code.

**D7. superpowers' handoff runs the plan, subagent-driven or native as the developer picks; `feature-engineer` doesn't** (user)
Alternatives: `feature-engineer` runs the plan; always subagent-driven. Why: one flow for every plan, with a ledger and rulings built in.

**D8. `[n]` markers and an end References list; a source keeps its number; claims are still checked in the session** (user)
Alternatives: inline citations; citing only load-bearing claims. Why: claims read cleanly and still point to sources.

**D9. Testable acceptance criteria always; rollback only when a revert wouldn't undo the change** (user)
Alternatives: both always; neither. Why: criteria give the plan and the PR review a target; most changes revert with their PR.

**D10. Claude runs `/docs-review`, ungated, at the end of `/rfc-implement` and before any PR is ready; reminders retire; in this RFC** (user)
Alternatives: user-run and gated, with reminders; a separate RFC. Why: the user's work-independently principle; PR review, one commit per finding and the docs-agent's boundary keep it safe.

**D11. Problem through Security aim for about 1,500 words and stay within 2,000; the Decision log and References aren't counted, but each entry stays short** (user)
Alternatives: counting the whole body, with this RFC as an exception; cutting this RFC to 2,000. Why: the budget is for the part read to triage.

**D12. `2026-05-12-post-approval-discretionary-revisions` is dropped once this RFC's implementation lands, and stays Approved until then** (user)
Alternatives: leaving it to #118's RFC-workflow revision. Why: the RFC/plan boundary makes its section unnecessary.

**D13. Execution keeps superpowers' model choices; the Opus rule covers only writing and reviewing RFCs** (user)
Alternatives: an Opus floor for every executor subagent. Why: cheaper runs, since the approved plan carries the design.

**D14. superpowers keeps its own specs and plans outside the repository, and only RFCs and their plans go under `docs/`, in every seeded repository; a `CLAUDE.md` line says so and starts design in RFC repositories with `/rfc-new`** (user)
Alternatives: keeping `docs/superpowers/` for small work; the plugin rule alone. Why: in the user's words, "for small things, superpower should store outside of the repository"; read as covering every seeded repository, not only RFC ones.

**D15. The other format rules** (agent)
Alternatives: no-placeholders for Design; Security inside Design; a Related RFCs section; appendices; per-agent copies; rule-bearing template comments [19]; rewriting old RFCs. Why: completeness now means decisions; a Security section adds security reviewers [1]; scaffold-and-drift's spec appendix alone is about 11,000 words [2]; copies drift [16]; old RFCs are records.

**D16. Questions go through `/rfc-new`; reviewers, `code-reviewer` and `security-engineer` included, judge the design; rulings are logged** (agent)
Alternatives: guessing; waiting for `FEEDBACK:` markers; redesigning review now. Why: subagents can't ask the user [21]; the lens-review RFC owns review, and a completeness test hunting for gaps "the implementor will have to invent" [22] would ask for the plan back.

**D17. The RFC/plan boundary** (agent)
Alternatives: an approved plan overrides the RFC; any departure needs approval again. Why: approval keeps its meaning without re-approving code-level choices, and `post-approval-discretionary-revisions` needs no section.

**D18. No worktree is created, and `/rfc-implement` and `/docs-review` stop on the default branch; the executor ends before finishing, and `/rfc-implement` records the rulings, runs `/docs-review`, pushes and opens the PR** (agent)
Alternatives: superpowers creates a worktree; answering the finishing menu up front; the executor pushing; rulings only in the PR. Why: the finishing skill always waits for an answer [45], and its local merge deletes `.worktrees/` worktrees, where developers make theirs [46]; rulings outlive the run only in a committed file [27].

**D19. Rules 3 and 6, the description as a second trigger, and superpowers in every install list** (agent)
Alternatives: the seeded `AGENTS.md` line alone [47]; the description alone; bytewyrd's install pulling superpowers in. Why: scaffold seeds `AGENTS.md` only where missing [48]; descriptions apply only when a task calls for them [33]; install lists keep updates resolved [38], at one `template-changed` drift per seeded repository [43].

**D20. The docs and refactor scopes; only the docs reminder retires** (agent)
Alternatives: the implementing diff for RFC identifiers; the Design's names; also dropping `state-touch` and the sh fallback (#118). Why: plans always map their files [25]; `/refactor` runs before any diff exists; `state-touch` and the fallback still serve the 0.2.x PreCompact sentinel [49, 50] and drift's legacy fix [43].

**D21. Plans are told apart by `.plan.md`, and later PRs get `<rfc-id>.<n>.plan.md`** (agent)
Alternatives: by their missing RFC frontmatter; one plan file per RFC. Why: a name check needs no read; the `*.md` glob catches plans, and a plan sorts right after its RFC, where `rfc-resolve` guesses [30, 51]. Each PR's plan stays next to its code.

**D22. A number per source, with its lines in the entry; `[UNVERIFIED]` stays inline, and a load-bearing one is a Trade-offs cost** (agent)
Alternatives: a number per claim; unverified notes in References; a risks section, as `rfc-architect` asks today [16]. Why: numbers stay stable, uncertainty stays visible at the claim, and Trade-offs is where costs now live.

**D23. The docs step runs only where `docs/guide/` holds a Markdown file** (agent)
Alternatives: every repository; any `docs/guide/` directory. Why: bytewyrd reaches every project at user scope [52], and outside a docs tree documentation-writer owns new docs [36]; a bare `.gitkeep` holds no pages.

**D24. Automatic runs list missing pages instead of creating them** (agent)
Alternatives: creating them, as Phase 6 does today [3]. Why: a whole new page deserves a request, not an unreviewed side effect.

**D25. The run rules live in the plan's Global Constraints** (agent)
Alternatives: instructions in `/rfc-implement` alone. Why: executors read the plan for every task, and a file survives compaction where conversation memory doesn't [27].

**D26. After a boundary stop, the existing plan is revised, and its workspace cleared when task numbers change** (agent)
Alternatives: a fresh plan; keeping the workspace. Why: a ledger naming the plan skips tasks marked complete [53], so renumbered tasks could be skipped.

**D27. Formats are told apart by `## Summary`** (agent)
Alternatives: `## Problem`, which one old RFC has [17]; a frontmatter field. Why: all 24 old RFCs have the heading, and the new format has none.

**D28. The open-question marker is the line `<!-- OPEN Qn -->`, found by a helper at line starts in the Decision log, outside code fences** (agent)
Alternatives: any occurrence in the file; a visible word marker. Why: anchoring lets an RFC describe the marker, as this one does, without tripping its own check, and a comment stays hidden when rendered.

**D29. The docs-agent's allow-list widens to all of `docs/guide/**`** (agent)
Alternatives: today's list, which leaves out pages such as `concepts.md` [36]. Why: on 2026-11-15 the user decided that pages for users belong in `docs/guide/` and that the docs-agent should cover them [6]; this absorbs #118's pending item.

**D30. The rule against inline RFC work narrows to writing, reviewing and updating RFCs** (agent)
Alternatives: keeping it, which rules out native execution. Why: the user's executor decision includes native, inline execution [1].

**D31. superpowers' outside location is `~/.claude/superpowers/<project>/`, named as Claude Code names project directories** (agent)
Alternatives: the author's description, which strips the leading `/`; a git-ignored folder in the repository. Why: Claude Code's naming, every character other than a letter or digit becomes `-` [54], matches the author's own example; outside the repository nothing gets committed by accident.

## References

1. verified: `skills/rfc-process/references/rfc-process.md` L14, L78, L106, L110–L128, L134, L136
2. measured: `awk '/^---$/{c++; next} c>=2' FILE | wc -w` over `docs/rfcs/*.md`, scaffold-and-drift's implementation-spec appendix taken between its `## Appendix B` and `## Appendix C` headings; statuses read from each RFC's frontmatter
3. verified: `skills/docs-review/SKILL.md` L5, L52–L60, L82, L87, L91–L99, L136, L153, L155
4. verified: `hooks/hooks.json`
5. verified: `CLAUDE.md` L40, L42
6. GitHub: bytewyrd/claude-bytewyrd#118
7. verified: `skills/rfc-drop/SKILL.md` L4, L39, L57–L60
8. Exa: https://code.claude.com/docs/en/plugins/manifest-reference
9. GitHub: obra/superpowers@22f0b46 `hooks/session-start`
10. GitHub: obra/superpowers@22f0b46 `hooks/hooks.json`
11. GitHub: obra/superpowers@22f0b46 `skills/using-superpowers/SKILL.md`
12. GitHub: anthropics/claude-plugins-official@main `.claude-plugin/marketplace.json`, fetched raw on 2026-11-18
13. measured: `grep -rlis` over `docs/guide/` for the implementation spec, the docs reminders and the docs-review gate: nine pages
14. verified: `skills/rfc-consensus-review/SKILL.md` L58, L64
15. verified: `scripts/bytewyrd/commands/rfc_feedback_list.py` L3–L5, L23
16. verified: `agents/rfc-architect.md` L50–L59, L154–L190
17. measured: `grep -l` over `docs/rfcs/*.md`: all 24 have `## Summary`, one also has `## Problem`, none has `## Decision log`
18. verified: `skills/rfc-approve/SKILL.md` L55
19. verified: `skills/rfc-new/SKILL.md` L60–L108
20. Exa: https://code.claude.com/docs/en/agent-sdk/user-input
21. Exa: https://code.claude.com/docs/en/sub-agents
22. verified: `agents/code-reviewer.md` L60
23. verified: `agents/security-engineer.md` L80
24. verified: `skills/rfc-implement/SKILL.md` L12, L45–L47
25. GitHub: obra/superpowers@22f0b46 `skills/writing-plans/SKILL.md`
26. GitHub: obra/superpowers@22f0b46 `skills/subagent-driven-development/SKILL.md`
27. GitHub: obra/superpowers@22f0b46 `skills/executing-plans/SKILL.md`
28. verified: `agents/feature-engineer.md` L71
29. GitHub: obra/superpowers@22f0b46 `skills/using-git-worktrees/SKILL.md`
30. verified: `scripts/bytewyrd/commands/rfc_resolve.py` L30–L62, L76–L81
31. verified: `scripts/bytewyrd/commands/rfc_summary.py` L27–L32
32. verified: `tests/py/test_frontmatter.py` L336
33. Exa: https://code.claude.com/docs/en/skills
34. verified: `tests/py/test_hooks.py` L86–L92
35. measured: the always-on context's length in Python, before and after rules 3 and 6
36. verified: `agents/docs-agent.md` L14–L31, L59, L85
37. verified: `skills/refactor/SKILL.md` L78
38. verified: `templates/scaffold/CLAUDE.md.tpl` L8
39. verified: `.claude-plugin/marketplace.json` L7
40. GitHub: obra/superpowers@22f0b46 `skills/brainstorming/SKILL.md`
41. verified: `.github/workflows/ci.yml` L406–L441
42. Exa: https://code.claude.com/docs/en/plugins/cli-reference
43. verified: `scripts/bytewyrd/commands/drift.py` L86, L228–L230
44. verified: `CHANGELOG.md` L47
45. GitHub: obra/superpowers@22f0b46 `skills/finishing-a-development-branch/SKILL.md`
46. verified: `docs/CONTRIBUTING.md` L77
47. verified: `templates/scaffold/AGENTS.md.tpl` L17
48. verified: `AGENTS.md` L32
49. verified: `skills/best-practices-extract/SKILL.md` L276
50. verified: `scripts/bw`
51. measured: Python's `sorted()` puts `<id>.plan.md` right after `<id>.md`
52. verified: `docs/guide/installation.md` L3
53. GitHub: obra/superpowers@22f0b46 `skills/subagent-driven-development/references/resuming.md`
54. Exa: https://code.claude.com/docs/en/claude-directory
