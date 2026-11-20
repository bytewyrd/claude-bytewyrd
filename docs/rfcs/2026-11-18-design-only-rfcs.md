---
rfc: "2026-11-18-design-only-rfcs"
title: "Design-only RFCs"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-11-18"
drop_reason: ~
---

## Problem

An RFC today doubles as "[the implementation spec that agents follow][r1:L14]": [file tables][r1:L112-L119] and [exact code][r19:L88-L90] [[1](#ref-1), [19](#ref-19)]. RFCs run long, [a median body of 9,013 words across the 24 in `docs/rfcs/`][r2], and plans age while they wait: [three approved in May 2026 are unimplemented][r2] [[2](#ref-2)]. After implementation, `/docs-review` [runs only when the user types it][r3:L5] and [stops for approval][r3:L136-L142] [[3](#ref-3)]; [a SubagentStop hook writes a sentinel][r4:L3-L17], and [the compact hook reminds Claude to ask for a review][r5:L39] [[4](#ref-4), [5](#ref-5)].

**Scope.** Writing, reviewing and implementing RFCs, and `/docs-review`. [#118's other planned RFCs keep the workflow (lifecycle, approve and drop, Done, `implemented_by`) and the reviewer layout][r6] [[6](#ref-6)]. `2026-05-12-post-approval-discretionary-revisions` [stays Approved][r2:post-approval] until this RFC's implementation lands; then the user [drops it with `/rfc-drop`][r7:L39], [giving this RFC as the `drop_reason`][r7:L57-L60] [[2](#ref-2), [7](#ref-7)]. [The new checks absorb the cleanup PR's `/rfc-implement` markers item][r6] [[6](#ref-6)].

## Trade-offs

**Doing it**
- Gains: shorter RFCs, quicker to write, review and triage; plans written against current code; after the plan, review in the PR; one decision log.
- Costs:
  - [Wherever bytewyrd is enabled][r8#dependencies], [so is superpowers][r8#defaultenabled] [[8](#ref-8)]; [every session][r10:L3-L9] [loads all of `using-superpowers`][r9:L49] [[9](#ref-9), [10](#ref-10)], whose rules compete with bytewyrd's ("[even a 1% chance][r11:L11]"; [brainstorm first][r11:L30]) and [yield only to user instructions such as CLAUDE.md][r11:L65] [[11](#ref-11)].
  - superpowers' skill texts change whenever [the official marketplace moves its pin][r12:L3827-L3837] [[12](#ref-12)].
  - No agent reviews the plan, and docs fixes reach the PR unapproved.
  - Migration: the process doc, seven skills, five agents, hooks, helpers, rules, install and contributor docs, and [ten guide pages][r13] [[13](#ref-13)], the last through the new docs step.
  - Two RFC formats share `docs/rfcs/`.

**Not doing it**
- Gains: no new dependency or session context; plans stay under [the five-reviewer consensus][r14:L58-L60] [[14](#ref-14)]; docs edits are approved first; no migration.
- Costs: RFC size, review load, aging plans and the reminder loop stay.

## Design

### Format

Sections, after today's frontmatter:

```markdown
## Problem       what it addresses, current state, scope, related RFCs
## Trade-offs    doing it vs not, both sides, no recommendation
## Design        contracts and key changes, acceptance criteria, rollback if a revert can't undo it
## Security      only for auth, secrets, permissions, user data or external integrations
## Decision log  every decision made while writing
## References    sources for the [n] markers
```

- **Design is not a plan**: no file list or steps; code only to pin a contract. Acceptance criteria are behavioural and testable.
- **No open decisions** replaces no-placeholders: each choice is logged or left to the plan. While writing, an open question is the line `<!-- OPEN Qn -->` under its log entry, and a helper reports such lines in the Decision log outside code fences, [anchored at line starts like `rfc-feedback-list`'s `FEEDBACK:` match][r15:L3-L5] [[15](#ref-15)].
- **Citations**: the words stating a claim link to the lines behind it, one link per place, and its `[[n](#ref-n)]` marker to References entry n, opened by `<a name="ref-n"></a>`. Each entry links its source after its label (`verified:`, `measured:`, `GitHub:`, `Exa:`, `Context7:`): a GitHub file at the full commit SHA, with `#L<a>-L<b>` per range, after `?plain=1` in Markdown; on other hosts, a permalink where possible; a docs page at its section's anchor; a measurement's inputs, with its command; an issue, PR or comment. A source keeps its number. `[UNVERIFIED — what was tried]` [stays inline and unnumbered][r16:L170-L177], and a load-bearing one is a Trade-offs cost [[16](#ref-16)]. Claims are still checked in the session.
- **Size**: Problem through Security aim for about 1,500 words and stay within 2,000, counted with `awk '/^---$/{c++; next} c>=2' FILE | sed '/^## Decision log$/,$d' | wc -w`; past that, split the RFC or leave detail to the plan. The Decision log and References aren't counted; log entries stay short. No appendices; risks go in Trade-offs.
- **Formats**: an RFC with a `## Summary` heading is old-format, as [all 24 today are][r17] [[17](#ref-17)]. Format checks skip old RFCs, amended or not; `/rfc-approve` shows the first paragraph of `## Problem`, or [an old RFC's `## Summary`][r18:L55] [[18](#ref-18)].

Entries sit under their date, keep their numbers, and may name a decision briefly when the Design states it; a reversal is a new entry naming what it supersedes:

```markdown
### YYYY-MM-DD
**Dn. <the decision>** (user | agent)
Alternatives: <option>; <option>. Why: <one to three sentences>.
```

Self-review checks each rule above, consistent names, and the links: every claim and entry linked, links pinned to their lines or sections, and each range showing what its claim says. The `rfc-process` skill's process doc is the only statement of these rules: `rfc-architect` drops [its own section list][r16:L50-L59] and [citation format][r16:L154-L166] [[16](#ref-16)], and [`/rfc-new`'s template][r19:L64-L108] keeps only the frontmatter and section headings [[19](#ref-19)].

### Writing

- `rfc-architect` decides what the request, code or earlier decisions settle, and asks only what nothing settles and would change what gets built: 2–4 options, trade-offs, a recommendation, and an open-question line holding the entry's place.
- `/rfc-new` [asks up to four per AskUserQuestion call][r20#limitations] [[20](#ref-20)], [resumes the same `rfc-architect` with SendMessage][r21#resume-subagents] [[21](#ref-21)], and starts review once the helper finds none. A `/rfc-read-feedback` or `/rfc-consensus-review` pass that leaves an open question runs the same loop.
- Reviewers judge the design, not file lists, steps or code: [`code-reviewer`'s completeness test][r22:L60] becomes decisions left open or contracts missing [[22](#ref-22)], and `security-engineer` [looks for a Security section][r23:L80] [[23](#ref-23)]. Design findings the user rules on are logged, here and in `/rfc-read-feedback`.

### Implementing

- **Checks**: Approved, with no open-question line or `FEEDBACK:` marker, [replacing the placeholder scan][r24:L45-L47] [[24](#ref-24)]; on the default branch, stop and give the worktree command.
- **Plan**: `superpowers:writing-plans` [writes `docs/rfcs/<rfc-id>.plan.md`][r25:L16-L17] [with the RFC as its Spec][r25:L67-L68] [[25](#ref-25)]. The developer approves it, the only in-session approval, and picks subagent-driven or native execution. Execution keeps superpowers' model choices: [cheap models for mechanical tasks][r26:L144], [the most capable for the final review][r26:L148-L150], [the session's own when native][r27:L8-L10] [[26](#ref-26), [27](#ref-27)]. The process doc's [Opus rule][r1:L136] now covers only writing and reviewing RFCs, and [its inline-work rule][r1:L134] only writing, reviewing and updating them [[1](#ref-1)]. [`feature-engineer` no longer implements RFCs][r28:L71] [[28](#ref-28)].
- **Run rules**: the plan's [Global Constraints, which bind every task][r25:L70-L75] [[25](#ref-25)], carry the RFC's contracts, the base branch and four rules: [stay in this checkout][r29:L33-L45] [[29](#ref-29)]; halt on work that would contradict the RFC; a failing baseline stops the run before Task 1 and is reported; end after the final review and final message, without the finishing skill. Otherwise only [the executors' safety stops][r26:L27-L31] halt them [[26](#ref-26)].
- **Finish**: `/rfc-implement` appends the executor's rulings and deferred minors to the plan file, runs `/docs-review`, pushes, and [opens the PR through the GitHub MCP, as today][r24:L12] [[24](#ref-24)]. The PR description lists rulings, deferred minors and open docs findings. Rulings stay within the approved plan and the RFC, never overriding the boundary.

**Plans aren't RFCs**: [`rfc-resolve`'s guesses][r30:L30-L61] [and identifiers][r30:L76-L81], [`rfc-summary`][r31:L27-L33] and [the repository's frontmatter test][r32:L336] skip names ending in `.plan.md` [[30](#ref-30), [31](#ref-31), [32](#ref-32)], and the frontmatter helpers reject them; [the rule that `rfc` equals the filename stem][r1:L78] [[1](#ref-1)] covers RFCs only. A later implementing PR gets `<rfc-id>.<n>.plan.md`.

**Boundary**: the RFC fixes scope, contracts and logged decisions; the plan decides the rest. Work that would contradict the RFC stops until the RFC is amended with a superseding entry, returns to Draft and is approved again with `/rfc-approve`, [as scaffold-and-drift was][r6] [[6](#ref-6)]. `/rfc-implement` then revises the existing plan for the developer's approval; if task numbers change, it first clears the plan's execution workspace.

### Docs review

- `/docs-review` drops `disable-model-invocation`, which [blocks Claude's call unless the user names the skill][r33#control-who-invokes-a-skill] [[33](#ref-33)].
- **Where**: only in a repository whose `docs/guide/` holds at least one Markdown file.
- **Triggers**: the end of `/rfc-implement`, and any implemented change before its PR is ready to merge, stated in the skill's description and a new always-on rule:

  ```text
  6. Docs: in repositories whose docs/guide/ holds Markdown pages, run the docs-review skill on the branch's changes once a change is implemented, before its pull request is ready to merge.
  ```

- **No gate**: the docs-agent [drops its approval step][r36:L59], [its allow-list][r36:L16-L31] widens to all of `docs/guide/**` [[36](#ref-36)], and it [applies each finding as its own commit][r3:L155] [[3](#ref-3)]. Automatic runs list missing pages and unsettled findings in the PR description; they don't create pages.
- **Default branch**: it stops and gives the worktree command, as `/rfc-implement` does; with no PR, unsettled findings go to its final report.
- **Scope**: automatic runs take the branch's diff against its base. In [`/docs-review`][r3:L82] and [`/refactor`][r37:L78], an RFC identifier means all its plans' files, or its Design as free text before there's a plan; old RFCs keep their file table [[3](#ref-3), [37](#ref-37)].
- **Retired**: [both reminder hooks, their sentinel][r4:L3-L27] and [the step that clears it][r3:L52-L60] [[3](#ref-3), [4](#ref-4)].

### superpowers

`.claude-plugin/plugin.json` adds `"superpowers@claude-plugins-official"` to `dependencies`, and every install list names it, [the seeded `CLAUDE.md` template included][r38:L5-L8] [[38](#ref-38)]; bytewyrd's marketplace [already allows that marketplace][r39:L7] [[39](#ref-39)]. [Subagents such as `rfc-architect` ignore `using-superpowers`][r11:L6-L8] [[11](#ref-11)]. Always-on rule 3 becomes:

```text
3. Design: repositories with a docs/rfcs/ directory use RFCs, not superpowers' brainstorming, for changes that need design (rfc-new skill), and implement an approved RFC with the rfc-implement skill, which plans with writing-plans (process in the rfc-process skill).
```

[The seeded `CLAUDE.md` template][r38:L1-L10] [[38](#ref-38)] and this repository's `CLAUDE.md` gain one line, since superpowers [takes its locations][r25:L16-L17] [from the user's preference][r40:L245-L248] [[25](#ref-25), [40](#ref-40)]:

```text
- superpowers keeps its own specs and plans in ~/.claude/superpowers/<project>/, <project> being the repository root's absolute path with each character other than a letter or digit turned into -; docs/ holds only RFCs and their plans. With docs/rfcs/, start design with /bytewyrd:rfc-new, not superpowers' brainstorming.
```

Before their first `/rfc-implement` run, adopters change any user-level instruction that forbids `writing-plans` in RFC repositories or keeps an RFC's implementation plan out of `docs/rfcs/`, while superpowers' own specs and plans stay outside the repository; the guide's upgrade note says so.

### Acceptance criteria

1. `/rfc-new` presents Drafts in this format: Problem through Security within 2,000 words, acceptance criteria in Design, no open-question line, and every claim linked to its pinned lines and References entry.
2. Open questions reach the user through AskUserQuestion before the Draft, and are logged as user decisions.
3. `/rfc-implement` writes `docs/rfcs/<rfc-id>.plan.md` and, once it's approved, opens a PR without another prompt unless a safety stop or the boundary halts it.
4. The RFC tools and the frontmatter test skip `.plan.md` files; the frontmatter helpers reject them.
5. `/docs-review` and `/refactor` scope a new-format RFC's identifier to its plans' files, or to its Design before there is a plan.
6. Claude starts `/docs-review` at the end of `/rfc-implement` where `docs/guide/` holds Markdown, and not elsewhere; it commits each finding separately, unprompted, and lists missing pages instead of creating them.
7. `hooks/hooks.json` has no docs reminder; `tests/py/test_hooks.py` passes with rules 3 and 6.
8. `.claude-plugin/plugin.json` lists `superpowers@claude-plugins-official`, and [the install-check CI job's install into a clean HOME][r41:L414-L422] also installs superpowers, with no plugin errors [[41](#ref-41)].
9. For an old-format RFC, `/rfc-approve` shows its `## Summary`, and RFC-identifier scopes use its file table.
10. The open-question helper reports such a line in the Decision log and ignores the same text in prose or code fences.
11. The seeded `CLAUDE.md` template and this repository's `CLAUDE.md` carry the superpowers line, and a `writing-plans` run for work that isn't an RFC saves under `~/.claude/superpowers/<project>/`.

**Rollback**: reverting the PR leaves superpowers installed. Adopters who don't use it on its own run `claude plugin uninstall superpowers@claude-plugins-official`, since [`claude plugin prune` removes only auto-installed copies][r42#plugin-prune] [[42](#ref-42)]. Reverting the seeded `CLAUDE.md` line is [another `template-changed` drift][r43:L226-L230] [[43](#ref-43)]. New-format RFCs and `.plan.md` files, which old tools misread, stay; move the plans out of `docs/rfcs/`.

## Security

superpowers is third-party code on every adopter's machine: [a SessionStart hook in every session][r10:L3-L9] [[10](#ref-10)], [outside the sandbox like all hooks][r5:L42] [[5](#ref-5)], and [helper scripts during execution][r27:L173-L175] [[27](#ref-27)], [pinned by the official marketplace to one commit][r12:L3827-L3837] [[12](#ref-12)]. Ungated docs edits reverse [#116's gate on `/docs-review`][r44:L47] [[44](#ref-44)]; the `docs/guide/` guard, the docs-agent's boundary and the PR review bound them. No secrets, permissions or user data change.

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
Alternatives: a direct PR; part of the RFC-workflow revision. Why: [#118's later RFCs follow its format][r6] [[6](#ref-6)].

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
Alternatives: leaving it to [#118's RFC-workflow revision][r6] [[6](#ref-6)]. Why: the RFC/plan boundary makes its section unnecessary.

**D13. Execution keeps superpowers' model choices; the Opus rule covers only writing and reviewing RFCs** (user)
Alternatives: an Opus floor for every executor subagent. Why: cheaper runs, since the approved plan carries the design.

**D14. superpowers keeps its own specs and plans outside the repository, and only RFCs and their plans go under `docs/`, in every seeded repository; a `CLAUDE.md` line says so and starts design in RFC repositories with `/rfc-new`** (user)
Alternatives: keeping `docs/superpowers/` for small work; the plugin rule alone. Why: in the user's words, "for small things, superpower should store outside of the repository"; read as covering every seeded repository, not only RFC ones.

**D15. The other format rules** (agent)
Alternatives: no-placeholders for Design; Security inside Design; a Related RFCs section; appendices; per-agent copies; [rule-bearing template comments][r19:L84-L90] [[19](#ref-19)]; rewriting old RFCs. Why: completeness now means decisions; [a Security section adds security reviewers][r1:L106] [[1](#ref-1)]; [scaffold-and-drift's spec appendix alone is about 11,000 words][r2:appendix-b] [[2](#ref-2)]; [copies][r16:L50-L59] [drift][r1:L93-L102] [[1](#ref-1), [16](#ref-16)]; old RFCs are records.

**D16. Questions go through `/rfc-new`; reviewers, `code-reviewer` and `security-engineer` included, judge the design; rulings are logged** (agent)
Alternatives: guessing; waiting for `FEEDBACK:` markers; redesigning review now. Why: [subagents can't ask the user][r21#available-tools] [[21](#ref-21)]; [the lens-review RFC owns review][r6] [[6](#ref-6)], and [a completeness test hunting for gaps "the implementor will have to invent"][r22:L60] [[22](#ref-22)] would ask for the plan back.

**D17. The RFC/plan boundary** (agent)
Alternatives: an approved plan overrides the RFC; any departure needs approval again. Why: approval keeps its meaning without re-approving code-level choices, and `post-approval-discretionary-revisions` needs no section.

**D18. No worktree is created, and `/rfc-implement` and `/docs-review` stop on the default branch; the executor ends before finishing, and `/rfc-implement` records the rulings, runs `/docs-review`, pushes and opens the PR** (agent)
Alternatives: superpowers creates a worktree; answering the finishing menu up front; the executor pushing; rulings only in the PR. Why: [the finishing skill always waits for an answer][r45:L78-L82], and [its local merge deletes `.worktrees/` worktrees][r45:L159-L174] [[45](#ref-45)], [where developers make theirs][r46:L77] [[46](#ref-46)]; [rulings outlive the run only in a committed file][r27:L293-L304] [[27](#ref-27)].

**D19. Rules 3 and 6, the description as a second trigger, and superpowers in every install list** (agent)
Alternatives: [the seeded `AGENTS.md` line alone][r47:L17] [[47](#ref-47)]; the description alone; bytewyrd's install pulling superpowers in. Why: [scaffold seeds `AGENTS.md` only where missing][r48:L32] [[48](#ref-48)]; [descriptions apply only when a task calls for them][r33#frontmatter-reference] [[33](#ref-33)]; [install lists keep updates resolved][r38:L8] [[38](#ref-38)], at [one `template-changed` drift per seeded repository][r43:L226-L230] [[43](#ref-43)]. Both rules fit: [rule 3 grows from 140 to 266 characters, and with rule 6 the always-on context is 1,282][r35:L1] of [the 2,000 its test allows][r34:L86-L92] [[34](#ref-34), [35](#ref-35)].

**D20. The docs and refactor scopes; only the docs reminder retires** (agent)
Alternatives: the implementing diff for RFC identifiers; the Design's names; [also dropping `state-touch` and the sh fallback][r6] [[6](#ref-6)]. Why: [plans always map their files][r25:L23-L25] [[25](#ref-25)]; [`/refactor` runs before any diff exists][r5:L56] [[5](#ref-5)]; [`state-touch`][r49:L276] and [the fallback][r50:L59-L72] still serve the 0.2.x PreCompact sentinel [[49](#ref-49), [50](#ref-50)] and [drift's legacy fix][r43:L86] [[43](#ref-43)].

**D21. Plans are told apart by `.plan.md`, and later PRs get `<rfc-id>.<n>.plan.md`** (agent)
Alternatives: by their missing RFC frontmatter; one plan file per RFC. Why: a name check needs no read; [the `*.md` glob catches plans][r32:L336] [[32](#ref-32)], and [`rfc-resolve` guesses the last name in code point order][r30:L53-L61], [which is the last RFC's plan once it has one][r51] [[30](#ref-30), [51](#ref-51)]. Each PR's plan stays next to its code.

**D22. A number per source, with its lines in the entry; `[UNVERIFIED]` stays inline, and a load-bearing one is a Trade-offs cost** (agent)
Alternatives: a number per claim; unverified notes in References; [a risks section, as `rfc-architect` asks today][r16:L190] [[16](#ref-16)]. Why: numbers stay stable, uncertainty stays visible at the claim, and Trade-offs is where costs now live.

**D23. The docs step runs only where `docs/guide/` holds a Markdown file** (agent)
Alternatives: every repository; any `docs/guide/` directory. Why: [bytewyrd reaches every project at user scope][r52:L3] [[52](#ref-52)], and [outside a docs tree documentation-writer owns new docs][r36:L85] [[36](#ref-36)]; a bare `.gitkeep` holds no pages.

**D24. Automatic runs list missing pages instead of creating them** (agent)
Alternatives: [creating them, as Phase 6 does today][r3:L153] [[3](#ref-3)]. Why: a whole new page deserves a request, not an unreviewed side effect.

**D25. The run rules live in the plan's Global Constraints** (agent)
Alternatives: instructions in `/rfc-implement` alone. Why: [Global Constraints bind every task][r25:L70-L75] [[25](#ref-25)], and [a file survives compaction where conversation memory doesn't][r27:L115-L119] [[27](#ref-27)].

**D26. After a boundary stop, the existing plan is revised, and its workspace cleared when task numbers change** (agent)
Alternatives: a fresh plan; keeping the workspace. Why: [a ledger naming the plan skips tasks marked complete][r53:L6-L8] [[53](#ref-53)], so renumbered tasks could be skipped.

**D27. Formats are told apart by `## Summary`** (agent)
Alternatives: `## Problem`, [which one old RFC has, in a code fence][r17:problem]; a frontmatter field. Why: [all 24 old RFCs have the heading][r17], and the new format has none [[17](#ref-17)].

**D28. The open-question marker is the line `<!-- OPEN Qn -->`, found by a helper at line starts in the Decision log, outside code fences** (agent)
Alternatives: any occurrence in the file; a visible word marker. Why: anchoring lets an RFC describe the marker, as this one does, without tripping its own check, and a comment stays hidden when rendered.

**D29. The docs-agent's allow-list widens to all of `docs/guide/**`** (agent)
Alternatives: today's list, [which leaves out pages such as `concepts.md`][r36:L31] [[36](#ref-36)]. Why: [on 2026-11-15 the user decided that pages for users belong in `docs/guide/` and that the docs-agent should cover them][r6]; this absorbs [#118's pending item][r6] [[6](#ref-6)].

**D30. The rule against inline RFC work narrows to writing, reviewing and updating RFCs** (agent)
Alternatives: keeping it, which [rules out native execution][r1:L134] [[1](#ref-1)]. Why: the user's executor decision includes native, inline execution.

**D31. superpowers' outside location is `~/.claude/superpowers/<project>/`, named as Claude Code names project directories** (agent)
Alternatives: stripping the leading `/` and turning each other `/` into `-`; a git-ignored folder in the repository. Why: it follows [Claude Code's naming][r54#cleaned-up-automatically], in which [every character other than a letter or digit becomes `-`][r54#session-scratchpad-directory] [[54](#ref-54)]; outside the repository nothing gets committed by accident.

### 2026-11-20

**D32. Every reference is a link, and claims link to their evidence: the words stating a claim link to its lines, and `[n]` jumps to its References entry; this amends D8** (user)
Alternatives: plain-text entries, as D8 had them; the `[n]` marker as the only link, straight to the lines; `[n]` linking only to its entry. Why: in the user's words, "Parts of the RFC that state the claim should be a link to the reference"; one click reaches the evidence, and the entry still gathers a source's lines.

**D33. Links pin a commit, with `?plain=1` for Markdown; entries open with `<a name>` anchors; docs links carry a section anchor; measurements link their inputs; URLs are reference-style** (agent)
Alternatives: branch links, [whose lines move with new commits][r55#file-views-show-the-latest-version-on-a-branch] [[55](#ref-55)]; short SHAs, [which name a commit only while no other object shares the prefix][r56#_specifying_revisions] [[56](#ref-56)]; GFM footnotes, [shown as superscripts][r57#footnotes] and [numbered by first use][r58] [[57](#ref-57), [58](#ref-58)]; text fragments, [which stop matching when a page's text changes][r59#concepts_and_usage] [[59](#ref-59)]; inline URLs; a link checker beside the repository's, [which skips `https:` links][r60:L9-L11] [[60](#ref-60)]. Why: [a commit ID pins the file][r55#press-y-to-permalink-to-a-file-in-a-specific-commit], [`?plain=1` gives Markdown line anchors][r61#linking-to-markdown], and [`<a name>` anchors][r57#custom-anchors] let a hand-numbered `[n]` link to its entry [[55](#ref-55), [57](#ref-57), [61](#ref-61)]. Reference-style URLs keep the raw text readable for line comments and `FEEDBACK:` edits, and give a claim and its entry one URL; self-review reads every linked range, so a checker adds little.

## References

1. <a name="ref-1"></a>verified: [`skills/rfc-process/references/rfc-process.md`][r1] [L14][r1:L14], [L78][r1:L78], [L93–L102][r1:L93-L102], [L106][r1:L106], [L112–L119][r1:L112-L119], [L134][r1:L134], [L136][r1:L136]
2. <a name="ref-2"></a>measured: `awk '/^---$/{c++; next} c>=2' FILE | wc -w` for each RFC in [`docs/rfcs/`][r2]: 24 RFCs, median 9,013 words; [scaffold-and-drift's Appendix B, L391–L907][r2:appendix-b], 11,011 words. Approved and dated May 2026 in their frontmatter: [`2026-05-10-iterative-consensus-convergence`][r2:iterative], [`2026-05-12-post-approval-discretionary-revisions`][r2:post-approval] and [`2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews`][r2:unify], each at L5
3. <a name="ref-3"></a>verified: [`skills/docs-review/SKILL.md`][r3] [L5][r3:L5], [L52–L60][r3:L52-L60], [L82][r3:L82], [L136–L142][r3:L136-L142], [L153][r3:L153], [L155][r3:L155]
4. <a name="ref-4"></a>verified: [`hooks/hooks.json`][r4] [L3–L17][r4:L3-L17], [L3–L27][r4:L3-L27]
5. <a name="ref-5"></a>verified: [`CLAUDE.md`][r5] [L39][r5:L39], [L42][r5:L42], [L56][r5:L56]
6. <a name="ref-6"></a>GitHub: [bytewyrd/claude-bytewyrd#118][r6], the issue body as edited on 2026-11-19, with no comments: scaffold-and-drift's history; the RFCs to write or revise (design-only RFCs, agent layout and lens review, RFC workflow, reminder hooks); the cleanup PR's items; the 2026-11-15 decisions
7. <a name="ref-7"></a>verified: [`skills/rfc-drop/SKILL.md`][r7] [L39][r7:L39], [L57–L60][r7:L57-L60]
8. <a name="ref-8"></a>Exa: [Plugin manifest reference][r8], sections [dependencies][r8#dependencies] and [defaultEnabled][r8#defaultenabled]
9. <a name="ref-9"></a>GitHub: [obra/superpowers@22f0b46 `hooks/session-start`][r9] [L49][r9:L49]
10. <a name="ref-10"></a>GitHub: [obra/superpowers@22f0b46 `hooks/hooks.json`][r10] [L3–L9][r10:L3-L9]
11. <a name="ref-11"></a>GitHub: [obra/superpowers@22f0b46 `skills/using-superpowers/SKILL.md`][r11] [L6–L8][r11:L6-L8], [L11][r11:L11], [L30][r11:L30], [L65][r11:L65]
12. <a name="ref-12"></a>GitHub: [anthropics/claude-plugins-official@6d49181 `.claude-plugin/marketplace.json`][r12] [L3827–L3837][r12:L3827-L3837], the superpowers entry and its pinned commit
13. <a name="ref-13"></a>measured: `git grep -li -e 'implementation spec' -e 'file structure table' -e SubagentStop -e 'compact.reminder' -e last-feature-engineer-stop -e 'docs-review.*\(approv\|seven-phase\|auto-apply\)' -e '\(approv\|seven-phase\|auto-apply\).*docs-review' 596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4 -- docs/guide` over [`docs/guide/`][r13]: ten pages, [`concepts.md`][r13:concepts], [`contributing.md`][r13:contributing], [`how-to/docs-review.md`][r13:how-to-docs-review], [`how-to/refactor.md`][r13:how-to-refactor], [`how-to/rfc-process.md`][r13:how-to-rfc-process], [`how-to/rfc-workflow.md`][r13:how-to-rfc-workflow], [`index.md`][r13:index], [`reference/hooks.md`][r13:reference-hooks], [`reference/skills.md`][r13:reference-skills] and [`tutorials/getting-started.md`][r13:tutorials-getting-started]
14. <a name="ref-14"></a>verified: [`skills/rfc-consensus-review/SKILL.md`][r14] [L58–L60][r14:L58-L60]
15. <a name="ref-15"></a>verified: [`scripts/bytewyrd/commands/rfc_feedback_list.py`][r15] [L3–L5][r15:L3-L5]
16. <a name="ref-16"></a>verified: [`agents/rfc-architect.md`][r16] [L50–L59][r16:L50-L59], [L154–L166][r16:L154-L166], [L170–L177][r16:L170-L177], [L190][r16:L190]
17. <a name="ref-17"></a>measured: `grep -l` for `^## Summary$`, `^## Problem$` and `^## Decision log$` over the RFCs in [`docs/rfcs/`][r17]: all 24 have `## Summary`; one has `## Problem`, [in a code fence][r17:problem]; none has `## Decision log`
18. <a name="ref-18"></a>verified: [`skills/rfc-approve/SKILL.md`][r18] [L55][r18:L55]
19. <a name="ref-19"></a>verified: [`skills/rfc-new/SKILL.md`][r19] [L64–L108][r19:L64-L108], [L84–L90][r19:L84-L90], [L88–L90][r19:L88-L90]
20. <a name="ref-20"></a>Exa: [Handle approvals and user input][r20], section [Limitations][r20#limitations]
21. <a name="ref-21"></a>Exa: [Create custom subagents][r21], sections [Available tools][r21#available-tools] and [Resume subagents][r21#resume-subagents]
22. <a name="ref-22"></a>verified: [`agents/code-reviewer.md`][r22] [L60][r22:L60]
23. <a name="ref-23"></a>verified: [`agents/security-engineer.md`][r23] [L80][r23:L80]
24. <a name="ref-24"></a>verified: [`skills/rfc-implement/SKILL.md`][r24] [L12][r24:L12], [L45–L47][r24:L45-L47]
25. <a name="ref-25"></a>GitHub: [obra/superpowers@22f0b46 `skills/writing-plans/SKILL.md`][r25] [L16–L17][r25:L16-L17], [L23–L25][r25:L23-L25], [L67–L68][r25:L67-L68], [L70–L75][r25:L70-L75]
26. <a name="ref-26"></a>GitHub: [obra/superpowers@22f0b46 `skills/subagent-driven-development/SKILL.md`][r26] [L27–L31][r26:L27-L31], [L144][r26:L144], [L148–L150][r26:L148-L150]
27. <a name="ref-27"></a>GitHub: [obra/superpowers@22f0b46 `skills/executing-plans/SKILL.md`][r27] [L8–L10][r27:L8-L10], [L115–L119][r27:L115-L119], [L173–L175][r27:L173-L175], [L293–L304][r27:L293-L304]
28. <a name="ref-28"></a>verified: [`agents/feature-engineer.md`][r28] [L71][r28:L71]
29. <a name="ref-29"></a>GitHub: [obra/superpowers@22f0b46 `skills/using-git-worktrees/SKILL.md`][r29] [L33–L45][r29:L33-L45]
30. <a name="ref-30"></a>verified: [`scripts/bytewyrd/commands/rfc_resolve.py`][r30] [L30–L61][r30:L30-L61], [L53–L61][r30:L53-L61], [L76–L81][r30:L76-L81]
31. <a name="ref-31"></a>verified: [`scripts/bytewyrd/commands/rfc_summary.py`][r31] [L27–L33][r31:L27-L33]
32. <a name="ref-32"></a>verified: [`tests/py/test_frontmatter.py`][r32] [L336][r32:L336]
33. <a name="ref-33"></a>Exa: [Extend Claude with skills][r33], sections [Control who invokes a skill][r33#control-who-invokes-a-skill] and [Frontmatter reference][r33#frontmatter-reference]
34. <a name="ref-34"></a>verified: [`tests/py/test_hooks.py`][r34] [L86–L92][r34:L86-L92]
35. <a name="ref-35"></a>measured: `len()` in Python of the `additionalContext` in [`hooks/always-on-rules.json`][r35] [L1][r35:L1], before and after rule 3 is replaced and rule 6 added as Design gives them: 968 and 1,282 characters; rule 3 goes from 140 to 266, and rule 6 is 187
36. <a name="ref-36"></a>verified: [`agents/docs-agent.md`][r36] [L16–L31][r36:L16-L31], [L31][r36:L31], [L59][r36:L59], [L85][r36:L85]
37. <a name="ref-37"></a>verified: [`skills/refactor/SKILL.md`][r37] [L78][r37:L78]
38. <a name="ref-38"></a>verified: [`templates/scaffold/CLAUDE.md.tpl`][r38] [L1–L10][r38:L1-L10], [L5–L8][r38:L5-L8], [L8][r38:L8]
39. <a name="ref-39"></a>verified: [`.claude-plugin/marketplace.json`][r39] [L7][r39:L7]
40. <a name="ref-40"></a>GitHub: [obra/superpowers@22f0b46 `skills/brainstorming/SKILL.md`][r40] [L245–L248][r40:L245-L248]
41. <a name="ref-41"></a>verified: [`.github/workflows/ci.yml`][r41] [L414–L422][r41:L414-L422]
42. <a name="ref-42"></a>Exa: [Plugin commands reference][r42], section [plugin prune][r42#plugin-prune]
43. <a name="ref-43"></a>verified: [`scripts/bytewyrd/commands/drift.py`][r43] [L86][r43:L86], [L226–L230][r43:L226-L230]
44. <a name="ref-44"></a>verified: [`CHANGELOG.md`][r44] [L47][r44:L47]
45. <a name="ref-45"></a>GitHub: [obra/superpowers@22f0b46 `skills/finishing-a-development-branch/SKILL.md`][r45] [L78–L82][r45:L78-L82], [L159–L174][r45:L159-L174]
46. <a name="ref-46"></a>verified: [`docs/CONTRIBUTING.md`][r46] [L77][r46:L77]
47. <a name="ref-47"></a>verified: [`templates/scaffold/AGENTS.md.tpl`][r47] [L17][r47:L17]
48. <a name="ref-48"></a>verified: [`AGENTS.md`][r48] [L32][r48:L32]
49. <a name="ref-49"></a>verified: [`skills/best-practices-extract/SKILL.md`][r49] [L276][r49:L276]
50. <a name="ref-50"></a>verified: [`scripts/bw`][r50] [L59–L72][r50:L59-L72]
51. <a name="ref-51"></a>measured: `python3 -c "print(sorted(['x-v2.md', 'x.md', 'x.plan.md', 'x.2.plan.md']))"` prints `x-v2.md`, `x.2.plan.md`, `x.md`, `x.plan.md`, as [Python compares strings by code point][r51]
52. <a name="ref-52"></a>verified: [`docs/guide/installation.md`][r52] [L3][r52:L3]
53. <a name="ref-53"></a>GitHub: [obra/superpowers@22f0b46 `skills/subagent-driven-development/references/resuming.md`][r53] [L6–L8][r53:L6-L8]
54. <a name="ref-54"></a>Exa: [Explore the .claude directory][r54], sections [Session scratchpad directory][r54#session-scratchpad-directory] and [Cleaned up automatically][r54#cleaned-up-automatically]
55. <a name="ref-55"></a>Exa: [Getting permanent links to files][r55], sections [File views show the latest version on a branch][r55#file-views-show-the-latest-version-on-a-branch] and [Press Y to permalink to a file in a specific commit][r55#press-y-to-permalink-to-a-file-in-a-specific-commit]
56. <a name="ref-56"></a>Exa: [gitrevisions][r56], section [Specifying revisions][r56#_specifying_revisions]
57. <a name="ref-57"></a>Exa: [Basic writing and formatting syntax][r57], sections [Custom anchors][r57#custom-anchors] and [Footnotes][r57#footnotes]
58. <a name="ref-58"></a>measured: test snippets rendered by [GitHub's Markdown API][r58] (`POST https://api.github.com/markdown`): in `gfm` mode, footnotes numbered in order of first reference, as superscripts; in `gfm` and `markdown` modes, `[[7](#ref-7)]` as a bracketed link to `#ref-7`, `<a name="ref-7">` kept as `user-content-ref-7`, and reference-style links resolved
59. <a name="ref-59"></a>Exa: [Text fragments][r59] on MDN, section [Concepts and usage][r59#concepts_and_usage]
60. <a name="ref-60"></a>verified: [`.github/scripts/check-links.py`][r60] [L9–L11][r60:L9-L11]
61. <a name="ref-61"></a>Exa: [Creating a permanent link to a code snippet][r61], section [Linking to Markdown][r61#linking-to-markdown]

<!-- link definitions -->
[r1]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md
[r1:L14]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L14
[r1:L78]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L78
[r1:L93-L102]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L93-L102
[r1:L106]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L106
[r1:L112-L119]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L112-L119
[r1:L134]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L134
[r1:L136]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-process/references/rfc-process.md?plain=1#L136
[r2]: https://github.com/bytewyrd/claude-bytewyrd/tree/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs
[r2:post-approval]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs/2026-05-12-post-approval-discretionary-revisions.md?plain=1#L5
[r2:appendix-b]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs/2026-11-09-scaffold-and-drift.md?plain=1#L391-L907
[r2:iterative]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs/2026-05-10-iterative-consensus-convergence.md?plain=1#L5
[r2:unify]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs/2026-05-15-unify-rfc-review-markers-rename-rfc-read-reviews.md?plain=1#L5
[r3]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md
[r3:L5]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L5
[r3:L52-L60]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L52-L60
[r3:L82]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L82
[r3:L136-L142]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L136-L142
[r3:L153]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L153
[r3:L155]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/docs-review/SKILL.md?plain=1#L155
[r4]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/hooks/hooks.json
[r4:L3-L17]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/hooks/hooks.json#L3-L17
[r4:L3-L27]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/hooks/hooks.json#L3-L27
[r5]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CLAUDE.md
[r5:L39]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CLAUDE.md?plain=1#L39
[r5:L42]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CLAUDE.md?plain=1#L42
[r5:L56]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CLAUDE.md?plain=1#L56
[r6]: https://github.com/bytewyrd/claude-bytewyrd/issues/118
[r7]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-drop/SKILL.md
[r7:L39]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-drop/SKILL.md?plain=1#L39
[r7:L57-L60]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-drop/SKILL.md?plain=1#L57-L60
[r8]: https://code.claude.com/docs/en/plugins/manifest-reference
[r8#dependencies]: https://code.claude.com/docs/en/plugins/manifest-reference#dependencies
[r8#defaultenabled]: https://code.claude.com/docs/en/plugins/manifest-reference#defaultenabled
[r9]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/session-start
[r9:L49]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/session-start#L49
[r10]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/hooks.json
[r10:L3-L9]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/hooks.json#L3-L9
[r11]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-superpowers/SKILL.md
[r11:L6-L8]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-superpowers/SKILL.md?plain=1#L6-L8
[r11:L11]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-superpowers/SKILL.md?plain=1#L11
[r11:L30]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-superpowers/SKILL.md?plain=1#L30
[r11:L65]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-superpowers/SKILL.md?plain=1#L65
[r12]: https://github.com/anthropics/claude-plugins-official/blob/6d491811023d7af2c96a7fab274935922b29ed01/.claude-plugin/marketplace.json
[r12:L3827-L3837]: https://github.com/anthropics/claude-plugins-official/blob/6d491811023d7af2c96a7fab274935922b29ed01/.claude-plugin/marketplace.json#L3827-L3837
[r13]: https://github.com/bytewyrd/claude-bytewyrd/tree/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide
[r13:concepts]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/concepts.md
[r13:contributing]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/contributing.md
[r13:how-to-docs-review]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/how-to/docs-review.md
[r13:how-to-refactor]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/how-to/refactor.md
[r13:how-to-rfc-process]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/how-to/rfc-process.md
[r13:how-to-rfc-workflow]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/how-to/rfc-workflow.md
[r13:index]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/index.md
[r13:reference-hooks]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/reference/hooks.md
[r13:reference-skills]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/reference/skills.md
[r13:tutorials-getting-started]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/tutorials/getting-started.md
[r14]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-consensus-review/SKILL.md
[r14:L58-L60]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-consensus-review/SKILL.md?plain=1#L58-L60
[r15]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_feedback_list.py
[r15:L3-L5]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_feedback_list.py#L3-L5
[r16]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/rfc-architect.md
[r16:L50-L59]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/rfc-architect.md?plain=1#L50-L59
[r16:L154-L166]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/rfc-architect.md?plain=1#L154-L166
[r16:L170-L177]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/rfc-architect.md?plain=1#L170-L177
[r16:L190]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/rfc-architect.md?plain=1#L190
[r17]: https://github.com/bytewyrd/claude-bytewyrd/tree/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs
[r17:problem]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/rfcs/2026-05-10-project-brief-sync-source-of-truth.md?plain=1#L118
[r18]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-approve/SKILL.md
[r18:L55]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-approve/SKILL.md?plain=1#L55
[r19]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-new/SKILL.md
[r19:L64-L108]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-new/SKILL.md?plain=1#L64-L108
[r19:L84-L90]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-new/SKILL.md?plain=1#L84-L90
[r19:L88-L90]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-new/SKILL.md?plain=1#L88-L90
[r20]: https://code.claude.com/docs/en/agent-sdk/user-input
[r20#limitations]: https://code.claude.com/docs/en/agent-sdk/user-input#limitations
[r21]: https://code.claude.com/docs/en/sub-agents
[r21#resume-subagents]: https://code.claude.com/docs/en/sub-agents#resume-subagents
[r21#available-tools]: https://code.claude.com/docs/en/sub-agents#available-tools
[r22]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/code-reviewer.md
[r22:L60]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/code-reviewer.md?plain=1#L60
[r23]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/security-engineer.md
[r23:L80]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/security-engineer.md?plain=1#L80
[r24]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-implement/SKILL.md
[r24:L12]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-implement/SKILL.md?plain=1#L12
[r24:L45-L47]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/rfc-implement/SKILL.md?plain=1#L45-L47
[r25]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/writing-plans/SKILL.md
[r25:L16-L17]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/writing-plans/SKILL.md?plain=1#L16-L17
[r25:L23-L25]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/writing-plans/SKILL.md?plain=1#L23-L25
[r25:L67-L68]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/writing-plans/SKILL.md?plain=1#L67-L68
[r25:L70-L75]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/writing-plans/SKILL.md?plain=1#L70-L75
[r26]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md
[r26:L27-L31]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md?plain=1#L27-L31
[r26:L144]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md?plain=1#L144
[r26:L148-L150]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md?plain=1#L148-L150
[r27]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/executing-plans/SKILL.md
[r27:L8-L10]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/executing-plans/SKILL.md?plain=1#L8-L10
[r27:L115-L119]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/executing-plans/SKILL.md?plain=1#L115-L119
[r27:L173-L175]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/executing-plans/SKILL.md?plain=1#L173-L175
[r27:L293-L304]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/executing-plans/SKILL.md?plain=1#L293-L304
[r28]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/feature-engineer.md
[r28:L71]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/feature-engineer.md?plain=1#L71
[r29]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-git-worktrees/SKILL.md
[r29:L33-L45]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-git-worktrees/SKILL.md?plain=1#L33-L45
[r30]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_resolve.py
[r30:L30-L61]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_resolve.py#L30-L61
[r30:L53-L61]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_resolve.py#L53-L61
[r30:L76-L81]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_resolve.py#L76-L81
[r31]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_summary.py
[r31:L27-L33]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/rfc_summary.py#L27-L33
[r32]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/tests/py/test_frontmatter.py
[r32:L336]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/tests/py/test_frontmatter.py#L336
[r33]: https://code.claude.com/docs/en/skills
[r33#control-who-invokes-a-skill]: https://code.claude.com/docs/en/skills#control-who-invokes-a-skill
[r33#frontmatter-reference]: https://code.claude.com/docs/en/skills#frontmatter-reference
[r34]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/tests/py/test_hooks.py
[r34:L86-L92]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/tests/py/test_hooks.py#L86-L92
[r35]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/hooks/always-on-rules.json
[r35:L1]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/hooks/always-on-rules.json#L1
[r36]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/docs-agent.md
[r36:L16-L31]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/docs-agent.md?plain=1#L16-L31
[r36:L31]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/docs-agent.md?plain=1#L31
[r36:L59]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/docs-agent.md?plain=1#L59
[r36:L85]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/agents/docs-agent.md?plain=1#L85
[r37]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/refactor/SKILL.md
[r37:L78]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/refactor/SKILL.md?plain=1#L78
[r38]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/CLAUDE.md.tpl
[r38:L1-L10]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/CLAUDE.md.tpl#L1-L10
[r38:L5-L8]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/CLAUDE.md.tpl#L5-L8
[r38:L8]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/CLAUDE.md.tpl#L8
[r39]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.claude-plugin/marketplace.json
[r39:L7]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.claude-plugin/marketplace.json#L7
[r40]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/brainstorming/SKILL.md
[r40:L245-L248]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/brainstorming/SKILL.md?plain=1#L245-L248
[r41]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.github/workflows/ci.yml
[r41:L414-L422]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.github/workflows/ci.yml#L414-L422
[r42]: https://code.claude.com/docs/en/plugins/cli-reference
[r42#plugin-prune]: https://code.claude.com/docs/en/plugins/cli-reference#plugin-prune
[r43]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/drift.py
[r43:L86]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/drift.py#L86
[r43:L226-L230]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bytewyrd/commands/drift.py#L226-L230
[r44]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CHANGELOG.md
[r44:L47]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/CHANGELOG.md?plain=1#L47
[r45]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/finishing-a-development-branch/SKILL.md
[r45:L78-L82]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/finishing-a-development-branch/SKILL.md?plain=1#L78-L82
[r45:L159-L174]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/finishing-a-development-branch/SKILL.md?plain=1#L159-L174
[r46]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/CONTRIBUTING.md
[r46:L77]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/CONTRIBUTING.md?plain=1#L77
[r47]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/AGENTS.md.tpl
[r47:L17]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/templates/scaffold/AGENTS.md.tpl#L17
[r48]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/AGENTS.md
[r48:L32]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/AGENTS.md?plain=1#L32
[r49]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/best-practices-extract/SKILL.md
[r49:L276]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/skills/best-practices-extract/SKILL.md?plain=1#L276
[r50]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bw
[r50:L59-L72]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/scripts/bw#L59-L72
[r51]: https://docs.python.org/3/reference/expressions.html#value-comparisons
[r52]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/installation.md
[r52:L3]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/docs/guide/installation.md?plain=1#L3
[r53]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/resuming.md
[r53:L6-L8]: https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/resuming.md?plain=1#L6-L8
[r54]: https://code.claude.com/docs/en/claude-directory
[r54#cleaned-up-automatically]: https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
[r54#session-scratchpad-directory]: https://code.claude.com/docs/en/claude-directory#session-scratchpad-directory
[r55]: https://docs.github.com/en/repositories/working-with-files/using-files/getting-permanent-links-to-files
[r55#file-views-show-the-latest-version-on-a-branch]: https://docs.github.com/en/repositories/working-with-files/using-files/getting-permanent-links-to-files#file-views-show-the-latest-version-on-a-branch
[r55#press-y-to-permalink-to-a-file-in-a-specific-commit]: https://docs.github.com/en/repositories/working-with-files/using-files/getting-permanent-links-to-files#press-y-to-permalink-to-a-file-in-a-specific-commit
[r56]: https://git-scm.com/docs/gitrevisions
[r56#_specifying_revisions]: https://git-scm.com/docs/gitrevisions#_specifying_revisions
[r57]: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax
[r57#footnotes]: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes
[r57#custom-anchors]: https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#custom-anchors
[r58]: https://docs.github.com/en/rest/markdown/markdown#render-a-markdown-document
[r59]: https://developer.mozilla.org/en-US/docs/Web/URI/Reference/Fragment/Text_fragments
[r59#concepts_and_usage]: https://developer.mozilla.org/en-US/docs/Web/URI/Reference/Fragment/Text_fragments#concepts_and_usage
[r60]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.github/scripts/check-links.py
[r60:L9-L11]: https://github.com/bytewyrd/claude-bytewyrd/blob/596640fdbe45a7d0ccde09f54bb9e2615bd6cbd4/.github/scripts/check-links.py#L9-L11
[r61]: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-a-permanent-link-to-a-code-snippet
[r61#linking-to-markdown]: https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-a-permanent-link-to-a-code-snippet#linking-to-markdown
