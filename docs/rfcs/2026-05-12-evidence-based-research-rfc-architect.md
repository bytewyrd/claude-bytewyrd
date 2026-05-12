---
rfc: "2026-05-12-evidence-based-research-rfc-architect"
title: "Enforce Evidence-Based Research for rfc-architect"
author: "Rodrigo Kochenburger"
status: "Approved"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Rewrite `agents/rfc-architect.md` to encode mandatory evidence-based research as a hard discipline rather than implicit good-engineering hygiene. Every external fact an RFC asserts — API signatures, library behavior, tool capabilities, CLI flag names, file path conventions, version-specific defaults, claimed-vs-real availability of a feature — must be backed by a primary source fetched in-session via Context7 or Exa, or it must be explicitly tagged as unverified in the RFC text. The agent's existing implicit "use your knowledge" stance is replaced with a four-part protocol: (1) extract a Claim Inventory before drafting, (2) verify every external claim with Context7 (libraries) or Exa (everything else) and record the source URL or doc reference, (3) tag any claim that resists verification with an explicit `[UNVERIFIED]` marker, and (4) add an "Evidence Audit" line item to the existing self-review checklist that fails the draft if any `[UNVERIFIED]` markers reach the human reviewer without an accompanying note explaining why verification was attempted but failed. The CLAUDE.md "Evidence-Based Development" guidance is referenced inline in the agent's prompt so it travels with the agent rather than only existing as project-level convention. The change is one file, four documented sub-changes, no plugin-manifest impact and no skill changes.

## Should we do this?

**Yes.** The current `rfc-architect.md` describes itself as an Expert Software Engineer with "deep expertise in system design" and instructs the agent to design solutions, document them, and consider trade-offs — but says nothing about *where the technical facts in the RFC must come from*. The implicit assumption is that the agent's training knowledge is good enough. That assumption breaks down in three concrete ways already observed in this repo:

1. **Verified case in this repo.** The RFC `2026-05-10-claude-agent-author-agent` was written specifically because vendored agents in `agents/` shipped with aspirational tool lists (`ast-grep`, `semgrep`, `langchain`, `aws-cli`) that look plausible to training knowledge but are not actually Claude Code tools — exactly the failure mode this RFC is trying to prevent in *RFC* drafting. The agent-author RFC's prompt body explicitly enumerates the verified tool name list and forbids guessing; `rfc-architect` deserves the same discipline at the RFC-drafting layer, one level up.

2. **Verified case in this repo.** The recently-recorded `docs/BEST_PRACTICES.md` entry `[2026-05-11] _Claude Code_: LLM reviewers in consensus-review workflows frequently hallucinate bugs that contradict the source text. Verify each finding against the specific document section before classifying it as a bug — reviewer confidence labels do not substitute for direct verification.` is evidence that the same class of hallucination problem exists in the *review* stage of the RFC process. The fix for review-time hallucination is direct-source verification; the fix for draft-time hallucination is the same primitive, applied earlier in the pipeline.

3. **Cost asymmetry.** A wrong API claim or fabricated CLI flag in an RFC propagates: review agents read it and reason from it, the human reads it and approves on its strength, `/rfc-implement` spawns `feature-engineer` with the RFC as primary input and the feature engineer tries to implement against a fact that does not exist. The cost of detection moves later and later in the pipeline. A draft-time verification step is one Exa call per claim — single-digit seconds, no human cost — and it catches the fault at the cheapest possible point.

The cost of *not* doing this is ongoing: every RFC drafted has the latent risk of containing fabricated facts, and the only mitigation today is the consensus-review pass, which the best-practices entry above says is itself unreliable for the same class of problem. The cost of doing this is one prompt edit and a self-review-checklist amendment. The asymmetry is obvious.

## Current state

`agents/rfc-architect.md` is 64 lines, all prompt body, plus a YAML frontmatter block. The frontmatter declares:

- `name: rfc-architect`
- a `description:` paragraph with `<example>` blocks describing when to invoke the agent (caching layer, distributed auth)
- `tools: Glob, Grep, LS, ExitPlanMode, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, Write` — note: this is an allowlist that includes `WebFetch` and `WebSearch` but does **not** include `mcp__exa__web_search_exa`, `mcp__exa__crawling_exa`, or `mcp__plugin_context7_context7__resolve-library-id` / `mcp__plugin_context7_context7__query-docs`. Per CLAUDE.md's "Tool Usage" section, Exa is the default web tool and Context7 is mandatory before writing code against an external library. The agent's current tool allowlist therefore *cannot* perform the verification this RFC requires — it can only reach for `WebFetch` and `WebSearch`, which CLAUDE.md explicitly says should not be used when Exa is available. The tools field must be widened (or omitted, which inherits the full set) for the evidence discipline to be enforceable.
- `color: blue`

The prompt body declares the agent's role ("You are an Expert Software Engineer and RFC Architect") and walks through six labeled sections:

1. **Core responsibilities** — Problem Analysis & Decomposition, Architectural Integration.
2. **RFC Creation Process** — five-step process (Requirements Gathering, Current State Analysis, Solution Design, Implementation Planning, Documentation).
3. **RFC Structure Standards** — lists section headers (Summary, Motivation, Detailed Design, Implementation Plan, Alternatives Considered, Risks & Mitigation, Testing Strategy, Migration Plan, Future Considerations). *Note: this list is out of date relative to `docs/rfc-process.md`, which prescribes Summary / Should we do this? / Current state / Analysis or Options / Drawbacks / Implementation spec / Risks and open questions / Relationship to other RFCs. The agent's prompt has not been re-synced with the process document. This RFC scopes that out as a separate concern — see "Risks and open questions" — and focuses only on the evidence-discipline gap.*
4. **File Management** — where to save RFCs, filename conventions.
5. **Quality Standards** — audience awareness, diagrams, anticipating challenges.
6. **Collaboration Approach** — actively seek input, present options, explain reasoning, plan for iterative refinement.

Nowhere in the prompt does the word "verify", "primary source", "Exa", "Context7", "evidence", or "citation" appear. The closest is "anticipate implementation challenges and edge cases" in Quality Standards — a posture, not a verification protocol.

The project's existing evidence guidance lives in **CLAUDE.md, "Evidence-Based Development" section** (lines 63–73 of the project file, which mirrors the same section in `~/.claude/CLAUDE.md`):

> Every claim, diagnosis, and recommendation must be grounded in evidence — not assumption, intuition, or training knowledge.
> [...]
> **Training knowledge is a search query, not a source of truth.** For any external API, cloud service, library, or tool — look it up with Exa or Context7 before asserting behavior. If no authoritative source is found, say so explicitly.

This guidance applies project-wide to every agent and every main-context session. The agent file inherits it implicitly because Claude reads CLAUDE.md at session start. However, the agent's prompt body — which is what its subagent context sees explicitly — does not reference it, restate it, or operationalize it. An agent that follows its own prompt to the letter has no instruction to verify.

The project's existing **self-review checklist** for `rfc-architect` lives in `docs/rfc-process.md`, Step 4 of "Writing a new RFC":

> 4. `rfc-architect` runs the **self-review checklist**:
>    - **Coverage** — skim every requirement; can each be pointed to a section of the implementation spec? List and fill any gaps.
>    - **Placeholder scan** — search for any prohibited pattern from the "No placeholders" list above; fix each one.
>    - **Consistency** — do all type names, function signatures, file paths, and interface names used in later steps match what was defined in earlier steps?

The checklist does not include an evidence audit step. A draft with `[UNVERIFIED]` markers — or worse, a draft with confidently-stated unverified facts — passes the checklist trivially because the checklist does not look for them.

## Analysis / Options

There are three coupled decisions: where the discipline is encoded (agent prompt vs. process doc vs. both), how strict the verification gate is (advisory vs. blocking), and how the self-review checklist surfaces failures.

### Decision 1 — Where the evidence discipline is encoded

**Option A — Encode the protocol in `agents/rfc-architect.md` only, and reference CLAUDE.md by quote (recommended).**
The agent file is what the subagent's context window sees. Encoding the protocol directly in the prompt means the agent reads its own discipline at every invocation — no inference required. The prompt also restates the CLAUDE.md "Training knowledge is a search query" line verbatim with attribution, so an operator inspecting the agent's behavior can trace the rule back to the project-level convention.

**Option B — Encode the protocol in `docs/rfc-process.md` only, and let the agent inherit it.**
Rejected. Process docs describe the workflow ("the agent does X, then Y, then Z"); they do not steer the agent's reasoning at runtime. A change to `rfc-process.md` ships in the doc but does not enter the agent's prompt context until either the agent reads the doc as part of its job (slow, optional) or the prompt is changed to point at it. The reliable place to change an agent's behavior is its prompt.

**Option C — Encode in both: prompt for runtime behavior, process doc for workflow visibility (variant of A).**
The agent prompt gets the protocol body; `rfc-process.md` gets a fourth Evidence Audit bullet added to the Step 4 self-review checklist. That bullet is self-contained and points to the agent file for the full protocol, so the workflow document remains accurate without needing a separate subsection.

**Recommendation: Option C (the practical form of Option A).** The agent prompt is the load-bearing change; the process doc gets a thin pointer so the workflow document stays accurate. The cost is two files modified instead of one, both edits small. The value is that someone reading `rfc-process.md` (the canonical place a human looks for "what does the RFC process actually do") sees the Evidence Audit step alongside the existing Coverage / Placeholder / Consistency steps.

### Decision 2 — How strict the verification gate is

**Option A — Hard gate: every external claim must be verified or marked `[UNVERIFIED]`; the self-review checklist treats any `[UNVERIFIED]` marker as a draft defect that must be either resolved (verification succeeds, marker removed) or explained (verification attempted but failed, with a one-line note next to the marker).**
The marker is visible to the human reviewer and to the consensus-review pass. The discipline is enforceable because the marker is text that can be searched for.

**Option B — Soft gate: agent is *instructed* to verify but no explicit marker or audit step.**
Rejected. The existing CLAUDE.md guidance is already a soft gate ("look it up with Exa or Context7"), and the evidence in "Should we do this?" shows soft gates do not change outcomes reliably. The marker mechanism is what converts an aspiration into a checkable artifact.

**Option C — Variable strictness: hard gate for external facts (APIs, tools, library behavior), soft gate for "claims about the project's own state" (current code, file paths, existing conventions).**
Project-internal claims are verifiable by reading the codebase; the agent already has Read/Grep/Glob and is expected to use them. The hard gate is specifically for *external* claims where training knowledge is the failure mode.

**Recommendation: Option C.** The protocol distinguishes external claims (verify via Context7/Exa or tag `[UNVERIFIED]`) from internal claims (verify by reading the repo). Both are hard gates in different ways: external claims require an external source; internal claims require a `Read`/`Grep` reference. The audit step in the self-review checklist treats both the same — any unverified-and-unexplained claim is a defect.

### Decision 3 — How the self-review checklist surfaces failures

**Option A — Add an "Evidence Audit" step to the checklist that runs as a final pass: scan the entire draft for `[UNVERIFIED]` markers and for assertion-shaped sentences ("X supports Y", "tool Z does W") that lack an in-line source reference, and produce a list of suspect claims (recommended).**
The audit step produces a checklist itself, surfaced to the agent before the draft is shown to the human. Findings are either resolved (verify and remove the suspicion) or accepted (add `[UNVERIFIED]` plus a one-line "verification attempted, [source] did not cover this" explanation). The audit's output is captured in a brief evidence-audit summary at the end of the draft, deleted before the RFC is finalized but visible to the agent and to the human if the draft is surfaced mid-process.

**Option B — No structured audit; rely on the agent following the protocol during drafting.**
Rejected for the same reason Option B in Decision 2 was rejected. A protocol without a checkable artifact does not survive the next session.

**Option C — Embed evidence audit into the existing Consistency step rather than adding a fourth step.**
Possible, but Consistency is about cross-reference integrity (type names match across sections), which is a different cognitive operation than evidence verification. Combining them dilutes both. The cost of adding a fourth checklist step is trivial.

**Recommendation: Option A.** The fourth checklist step ("Evidence Audit") is the load-bearing artifact. The audit step's deliverable is structured (list of claims, each either verified-with-source or marked-and-explained), which gives the consensus-review pass downstream a concrete thing to spot-check rather than a general "did the agent verify?" question.

### Decision 4 — How verification is recorded

**Option A — In-line citation next to the claim (recommended).**
The first time a claim appears, it is followed by a parenthetical source reference: `Context7 'cargo-make' v0.37`, `Exa: https://docs.example.com/v2/api#widget`, or for internal claims `verified: agents/feature-engineer.md L42`. Subsequent uses of the same claim within the same RFC do not need to re-cite — they reference the same source by implication. The in-line form keeps the cost cheap and the discipline visible.

**Option B — End-of-RFC sources section.**
Rejected. End-of-document citations are easy to skip (the reader and the agent both); they also lose the per-claim mapping that makes the audit step possible.

**Option C — No structured citation; verification is implicit if the agent fetched the page.**
Rejected. The whole point is making the verification artifact checkable. "I read it" without a citation is not a verifiable artifact.

**Recommendation: Option A.** Citations are in-line, terse, and travel with the claim. The format is documented in the agent prompt's protocol section so the agent produces consistent output across drafts.

## Drawbacks

- **Drafting slows down for fact-heavy RFCs.** Every external claim costs at least one Exa or Context7 call. An RFC that spans an unfamiliar SDK or a multi-tool workflow may issue 20–50 verification calls during drafting. **Mitigation:** the calls are cheap, parallelizable, and pay back the first time they catch a hallucination (which, per the best-practices entry on review-time hallucinations, happens often enough to be worth catching). The drafting slowdown is also a forcing function — an RFC that depends on 50 external claims may itself be too broad and should be split per the scope-check rule in `rfc-process.md`.

- **The `[UNVERIFIED]` marker is opt-in for the agent.** A confidently-wrong claim that the agent fails to recognize as needing verification will not be marked at all. **Mitigation:** the audit step's "scan for assertion-shaped sentences that lack an in-line source reference" pass is the second line of defense — it looks for sentence structure (e.g., "X supports Y", "Z does W") rather than just for the literal marker. The mitigation is imperfect; an agent that fails to recognize an assertion as external is also likely to fail to flag it in the audit pass. The combined error rate is lower than either step alone, which is the goal.

- **Citation noise.** Every paragraph that asserts external facts ends up sprinkled with parenthetical citations. Some readers will find this distracting. **Mitigation:** the citation format is terse (`Context7: <lib> v<X>` or a single URL fragment), and citations only appear at the first claim — repeated claims reference by implication. The marginal noise is comparable to academic prose conventions and is cheaper than the alternative (no auditability).

- **The agent's existing `tools:` allowlist is too narrow.** As noted in "Current state", the current allowlist excludes the Exa and Context7 MCP tools. The protocol cannot be followed without widening the allowlist. **Mitigation:** Step 1 of the Implementation spec explicitly widens the allowlist. This is a necessary scoped consequence of the RFC.

- **Two-pass discipline (Claim Inventory before drafting) adds a structured step the agent may skip if the prompt is misread.** **Mitigation:** the prompt opens the new section with imperative ("First, before drafting, ..."), and the self-review checklist's Evidence Audit step references the Claim Inventory and treats its absence as a draft defect. Defense in depth.

- **Stale-source risk.** A verification done at 09:00 against `docs.example.com/v2/api` may not reflect a 14:00 doc update on the same day. **Mitigation:** the citation format includes the URL (for Exa fetches) or the library version (for Context7), which lets a reviewer re-verify at review time if doubts arise. The protocol does not require the agent to re-verify on every session, only at draft time; review-time staleness is the human reviewer's problem to surface.

- **The RFC's prescription is itself a claim about agent behavior that should be evidence-based.** This RFC is asserting that the protocol will reduce hallucination rates. **Mitigation:** the "Should we do this?" section grounds the assertion in two verified cases in this repo (RFC `2026-05-10-claude-agent-author-agent` and the BEST_PRACTICES entry on review-time hallucination) plus the cost-asymmetry argument. The mitigation does not include a controlled experiment because none is feasible at this scale; the assertion is evidence-supported, not evidence-proven.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `agents/rfc-architect.md` | Widen `tools:` allowlist to include Exa and Context7 MCP tools; add four new prompt sections (`## Evidence-Based Research Discipline`, `## Claim Inventory (Before Drafting)`, `## Verification Protocol`, `## Citation Format and the \`[UNVERIFIED]\` Marker`); replace step 5 of the RFC Creation Process with an extended step 5 and add a new step 6 (`Self-review`) containing four checklist items (Coverage, Placeholder scan, Consistency, Evidence Audit). |
| Modify | `docs/rfc-process.md` | Add a fourth bullet (`Evidence Audit`) to the `rfc-architect` self-review checklist in Step 4 of "Writing a new RFC". The new bullet is self-contained and points at the agent file for the full protocol; no new subsection is added to the "Agent rules" section. |

No skill changes. No `.claude-plugin/plugin.json` changes (agents are auto-discovered). No hook changes. No edits to any other agent file. No edits to CLAUDE.md (the existing "Evidence-Based Development" section is referenced from the agent prompt, not rewritten).

### Steps

#### Step 1 — Widen the `tools:` allowlist on `agents/rfc-architect.md`

The current frontmatter `tools:` field (line 4 of `agents/rfc-architect.md`) is:

```
tools: Glob, Grep, LS, ExitPlanMode, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, Write
```

Replace it with:

```
tools: Glob, Grep, LS, ExitPlanMode, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, Write, mcp__exa__web_search_exa, mcp__exa__crawling_exa, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs
```

Rationale: the agent's verification protocol (Step 3 below) requires Exa and Context7. Without these names on the allowlist, the agent cannot call them — Claude Code's `tools:` field is an allowlist, not an aspiration (see the `claude-agent-author` RFC for the verified semantics of this field). `WebFetch` and `WebSearch` are kept on the list as fallback paths even though CLAUDE.md says to prefer Exa, because the agent prompt itself will tell the agent to prefer Exa; an explicit allowlist that omits the fallbacks is more brittle than one that lets the agent reach for them if Exa is briefly unavailable.

No other field in the frontmatter changes. The `name`, `description`, and `color` fields are kept verbatim.

#### Step 2 — Add the `## Evidence-Based Research Discipline` section to the agent prompt

After the line `**Collaboration Approach:**` block ends (currently line 61: `- Plan for iterative refinement based on feedback`) and before the final paragraph (`You think systematically about software evolution, always considering how today's decisions impact tomorrow's possibilities. Your RFCs serve as both technical specifications and historical records of architectural reasoning.`), insert this exact content as a new top-level section:

````markdown
## Evidence-Based Research Discipline

Every external technical claim in an RFC you draft must be backed by a primary source you fetched in-session, or it must be explicitly marked `[UNVERIFIED]` with a one-line note explaining what you attempted and why verification failed. Training knowledge is not an acceptable source for any claim about an external API, library API or behavior, tool capability, CLI flag, command syntax, file path convention, version-specific default, or anything else that a real system documents authoritatively somewhere on the web.

This discipline mirrors and operationalizes the project-level guidance in `CLAUDE.md`:

> Every claim, diagnosis, and recommendation must be grounded in evidence — not assumption, intuition, or training knowledge.
> [...]
> **Training knowledge is a search query, not a source of truth.** For any external API, cloud service, library, or tool — look it up with Exa or Context7 before asserting behavior. If no authoritative source is found, say so explicitly.

The CLAUDE.md guidance is a posture. The protocol below is how you turn that posture into a checkable artifact in every RFC you produce.

### Two classes of claim

**External claims** — facts about anything outside the project repository: third-party APIs, library behaviors, CLI tools, cloud services, language features, runtime defaults, configuration knobs, vendor documentation, RFC and standard-document semantics. These are verified by fetching a primary source via Context7 (for libraries, frameworks, SDKs, CLI tools) or Exa (for everything else — error messages, release notes, blog posts, GitHub issues, standards documents). The fetch must be in-session: a citation that says "Context7 'tokio' v1.40" must correspond to a Context7 call you made while drafting this RFC, not a memory of what Context7 returned in a previous session.

**Internal claims** — facts about the project repository itself: existing files, current code structure, line numbers, function signatures, previous RFC contents, in-tree convention. These are verified by reading the actual file via `Read`, `Grep`, or `Glob`. A citation that says "verified: agents/feature-engineer.md L42" must correspond to a Read or Grep call you made in this session against that file.

Both classes are hard gates. The difference is the verification mechanism.

### The cheap path is the right path

Most external claims resolve in a single Context7 or Exa call. Verification cost per claim is single-digit seconds and a small number of tokens. The cost of *not* verifying — a fabricated CLI flag that survives review, gets approved, and lands in front of `feature-engineer` during `/rfc-implement` — is one full implementation attempt against a fact that does not exist. The asymmetry is the reason this protocol exists; the cheap path is the right path.
````

#### Step 3 — Add the `## Claim Inventory (Before Drafting)` section

Insert this section immediately after the `## Evidence-Based Research Discipline` section added in Step 2:

````markdown
## Claim Inventory (Before Drafting)

Before you write the body of an RFC, list the external claims and internal claims the RFC will rely on. This is a private working artifact — it does not appear in the final RFC text — but it is what your verification protocol consumes.

For the user-provided description of the proposed RFC, identify every assertion of the form "X does Y", "tool Z supports W", "library L has feature F", "file `path/to/thing` exists and contains G", "the existing agent A is configured with B", etc. Each assertion becomes one row of the inventory:

```
Claim                                          | Class    | Source plan
---------------------------------------------- | -------- | -----------------------------------------------
tokio 1.40 supports cancellation tokens         | External | Context7: tokio v1.40
The `feature-engineer` agent uses model: opus  | Internal | Read agents/feature-engineer.md
Anthropic's tool-use API allows nested calls   | External | Exa: https://docs.anthropic.com/...tool-use
```

If your description involves a comparative analysis (Option A vs Option B vs Option C), the inventory must include the capability claims for every option, not only the recommended one. Inaccurate claims about a rejected option produce a wrong rejection rationale, which is just as harmful as an inaccurate claim about the recommended option.

The inventory is not exhaustive. You will discover more claims while drafting. When you do, add them to the inventory and verify them before writing them down in the RFC text.

The inventory itself does not need to be perfect at this stage — its purpose is to surface the verification work *before* you accidentally embed an unverified claim in prose. A claim you forgot in the inventory but caught while drafting is still verified by Step 4 below; the inventory is the proactive scan, the drafting-time check is the reactive one.
````

#### Step 4 — Add the `## Verification Protocol` section

Insert this section immediately after the `## Claim Inventory (Before Drafting)` section added in Step 3:

````markdown
## Verification Protocol

For each claim in the inventory (and for each new claim that surfaces during drafting):

1. **Select the source mechanism.**
   - Library / framework / SDK / CLI tool docs → Context7 (`mcp__plugin_context7_context7__resolve-library-id` then `mcp__plugin_context7_context7__query-docs`).
   - Everything else web-reachable (vendor docs, error messages, release notes, GitHub issues, standards documents) → Exa (`mcp__exa__web_search_exa` for a search, `mcp__exa__crawling_exa` for a known URL).
   - Project-internal facts → `Read`, `Grep`, or `Glob` against the file in the repo.
   - `WebFetch` and `WebSearch` are fallbacks only — use them when Exa is unreachable. Prefer Exa otherwise, as instructed in `CLAUDE.md` ("Use Exa as the default for any web lookup. Do not use `WebSearch` unless Exa is unavailable.").

2. **Fetch and read the source.** Do not skim or pattern-match a heading and infer the rest. Read the section of the doc that addresses the specific claim. If the doc does not address the claim directly, that is itself a finding — the claim is not yet verified.

3. **Record the citation.** Capture the source as a terse identifier:
   - Context7: `Context7: <library-id> v<version-if-pinned>` (e.g. `Context7: tokio v1.40`).
   - Exa fetch: `Exa: <fetched-URL>` (the actual URL the fetch returned, not the search query).
   - Exa search: when a search returned multiple sources and you read one, cite that one's URL, not the search.
   - Internal: `verified: <relative-path>[:Lnnn]` (e.g. `verified: agents/feature-engineer.md:L42`).

4. **Decide one of three outcomes:**
   - **Verified** — the source supports the claim as stated. Write the claim with its citation in-line (see "Citation Format" below).
   - **Refuted** — the source contradicts the claim. Update the claim to match the source (or drop the claim if it is no longer relevant) and verify the corrected version.
   - **Inconclusive** — the source does not directly address the claim, or no source could be found within reasonable effort. The claim must either be (a) replaced with one that is verifiable, (b) dropped from the RFC, or (c) marked `[UNVERIFIED]` with a one-line note explaining what you searched for and why it was inconclusive.

5. **Do not assert a claim you have not run through this protocol.** If, while drafting, you notice yourself about to write a sentence that asserts an external fact you have not verified in this session, stop, run the protocol on that claim, then continue.

### Internal claims are claims

Do not skip verification for "obvious" repo-internal facts. The cost of a `Read` is small; the cost of a wrong line-number citation or a misremembered field name in a file structure table is a chain of downstream confusion. The verification step is the same shape for internal claims as for external ones: read the source, capture the citation, decide the outcome.
````

#### Step 5 — Add the `` ## Citation Format and the `[UNVERIFIED]` Marker `` section

Insert this section immediately after the `## Verification Protocol` section added in Step 4:

````markdown
## Citation Format and the `[UNVERIFIED]` Marker

### Citation format

The first time a verified claim appears in the RFC body, follow the claim with a parenthetical citation in one of these forms:

- `(Context7: tokio v1.40)` — library docs via Context7.
- `(Exa: https://docs.anthropic.com/en/api/tool-use)` — web doc fetched via Exa.
- `(verified: agents/feature-engineer.md:L42)` — repo file read via `Read` / `Grep`.

Subsequent mentions of the same claim within the same RFC do not need to re-cite. Citations live in the section that first introduces the claim — not in a separate sources block at the end of the document. End-of-document citation lists are easy to skip and break the per-claim auditability this protocol depends on.

When a claim is supported by multiple sources (a primary doc plus a corroborating release note, say), cite the strongest source — the one closest to the authoritative voice. Listing two URLs side-by-side is acceptable when the second meaningfully adds (e.g., a vendor doc plus a community thread that explains an undocumented edge case) but it is not required.

### The `[UNVERIFIED]` marker

When verification fails — the search returned nothing useful, the doc page is paywalled, the library does not document the behavior, the fact is too recent to be in published docs — mark the claim explicitly:

```
The widget supports cancellation tokens [UNVERIFIED — Exa search 'widget cancellation token'
returned no authoritative source; vendor docs do not document the cancellation API].
```

The marker is a square-bracketed `[UNVERIFIED]` token followed by a dash and a one-line explanation of (a) what verification you attempted and (b) why it was inconclusive. The explanation is not optional — a bare `[UNVERIFIED]` marker without context fails the Evidence Audit step in self-review.

The marker is visible to the human reviewer and to the consensus-review pass. It surfaces uncertainty rather than hiding it. An RFC with three honest `[UNVERIFIED]` markers and one solid recommendation is more useful than an RFC with no markers and three undetected hallucinations.

### When to fall back to `[UNVERIFIED]`

The marker is a last resort, not a convenience. Before using it, ask:

- Did I try the right source mechanism? (Context7 for libraries, Exa for everything else, Read for repo facts.)
- Did I read the actual section of the doc that addresses the claim, or did I scan a heading and infer?
- Is the claim load-bearing for the RFC? If the recommendation rests on it, the claim must be verified or the recommendation must change.
- Can I rephrase the claim to remove the unverifiable part? ("Tool X is fast" is unverifiable in general; "Tool X documents a target of P95 < 50ms for operation Y" is verifiable.)

If after all four questions the claim is still inconclusive *and* the RFC genuinely depends on it, mark it `[UNVERIFIED]` and include a "Risks and open questions" entry naming the dependency explicitly.
````

#### Step 6 — Extend the implicit self-review checklist in the agent prompt

The agent prompt does not currently contain a literal self-review checklist (that lives in `docs/rfc-process.md`). However, the prompt's "RFC Creation Process" section step 5 says "Documentation: Create comprehensive RFCs following standard structure" — a thin instruction that is the closest analog to a final-pass checklist.

Replace step 5 of the **RFC Creation Process** block (currently a single line: `5. **Documentation**: Create comprehensive RFCs following standard structure`) with:

````markdown
5. **Documentation**: Create comprehensive RFCs following standard structure (see `docs/rfc-process.md` for the canonical section list).
6. **Self-review** (mandatory before surfacing the draft to review agents):
   - **Coverage** — every requirement in the user's description can be pointed to a section of the implementation spec. List and fill any gaps.
   - **Placeholder scan** — no "TBD", "TODO", "implement later", "fill in details", "similar to the above", or unspecific-handling phrases survive in the draft.
   - **Consistency** — type names, function signatures, file paths, and interface names used in later steps match what was defined in earlier steps.
   - **Evidence Audit** — every external claim has an in-line citation (`Context7: ...`, `Exa: ...`) or is explicitly marked `[UNVERIFIED]` with a one-line note. Every internal claim has a `verified: <path>` citation. Scan the draft for assertion-shaped sentences that lack either a citation or a marker; for each, either verify and cite, or mark and explain. The audit's output is a brief list of (claim → citation-or-marker) appended to your working notes, used by you to confirm the draft is clean before you proceed.

If the Evidence Audit produces any unresolved findings (claims that are neither verified nor marked), do not surface the draft. Resolve the findings first.
````

This adds a literal "Self-review" step (step 6) to the existing 5-step process. The Evidence Audit is the load-bearing item; Coverage / Placeholder scan / Consistency are pulled in from `docs/rfc-process.md`'s Step 4 self-review checklist (verified: docs/rfc-process.md:L149-L153 — see "Current state" above where the checklist is quoted in full) so the agent's prompt is consistent with the process document.

#### Step 7 — Update `docs/rfc-process.md`

`docs/rfc-process.md`, Step 4 of "Writing a new RFC", currently contains a three-item self-review checklist (Coverage / Placeholder scan / Consistency). Add a fourth item between Consistency and the line that follows (`5. \`/rfc-consensus-review\` runs: ...`). The diff is:

Before (current content of Step 4):
```markdown
4. `rfc-architect` runs the **self-review checklist**:
   - **Coverage** — skim every requirement; can each be pointed to a section of the implementation spec? List and fill any gaps.
   - **Placeholder scan** — search for any prohibited pattern from the "No placeholders" list above; fix each one.
   - **Consistency** — do all type names, function signatures, file paths, and interface names used in later steps match what was defined in earlier steps?
```

After (with the new fourth bullet inserted at the end of the list):
```markdown
4. `rfc-architect` runs the **self-review checklist**:
   - **Coverage** — skim every requirement; can each be pointed to a section of the implementation spec? List and fill any gaps.
   - **Placeholder scan** — search for any prohibited pattern from the "No placeholders" list above; fix each one.
   - **Consistency** — do all type names, function signatures, file paths, and interface names used in later steps match what was defined in earlier steps?
   - **Evidence Audit** — every external claim in the draft has an in-line citation (`Context7: <library> v<version>`, `Exa: <URL>`) or is explicitly marked `[UNVERIFIED]` with a one-line note explaining what verification was attempted and why it was inconclusive. Every internal claim has a `verified: <path>[:Lnnn]` citation. The protocol the agent follows for verification and citation lives in `agents/rfc-architect.md` (sections "Evidence-Based Research Discipline" through "Citation Format and the `[UNVERIFIED]` Marker"). Any unresolved finding from this audit blocks surfacing the draft.
```

No other change to `docs/rfc-process.md`. The lifecycle, file format, and agent rules sections are unchanged. The "Agent rules" section retains its existing structure; no new subsection is added there because the bullet above is self-contained and points at the agent file for the full protocol.

#### Step 8 — Verification

After Steps 1–7, run these checks to confirm the changes landed as specified:

1. **Agent file widened tool allowlist:**
   ```bash
   grep -E '^tools:' agents/rfc-architect.md
   ```
   Expected output:
   ```
   tools: Glob, Grep, LS, ExitPlanMode, Read, NotebookRead, WebFetch, TodoWrite, WebSearch, Write, mcp__exa__web_search_exa, mcp__exa__crawling_exa, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs
   ```

2. **All four new prompt sections present in agent file:**
   ```bash
   grep -nE '^## (Evidence-Based Research Discipline|Claim Inventory \(Before Drafting\)|Verification Protocol|Citation Format and the \`\[UNVERIFIED\]\` Marker)$' agents/rfc-architect.md
   ```
   Expected output: four matching lines, in the order the sections were inserted:
   ```
   <N1>:## Evidence-Based Research Discipline
   <N2>:## Claim Inventory (Before Drafting)
   <N3>:## Verification Protocol
   <N4>:## Citation Format and the `[UNVERIFIED]` Marker
   ```
   (The literal `<N1>` etc. are line numbers grep emits; their values depend on prior content and are not checked.)

3. **Self-review step added to RFC Creation Process:**
   ```bash
   grep -n 'Self-review' agents/rfc-architect.md
   ```
   Expected output: one line matching `6. **Self-review**`.

4. **Evidence Audit step present in agent self-review:**
   ```bash
   grep -n 'Evidence Audit' agents/rfc-architect.md docs/rfc-process.md
   ```
   Expected output: at least one match in each file.

5. **The CLAUDE.md quote is present in the agent file:**
   ```bash
   grep -F 'Training knowledge is a search query, not a source of truth.' agents/rfc-architect.md
   ```
   Expected output: one matching line (the verbatim quote inside the Evidence-Based Research Discipline section).

6. **Process doc fourth bullet is in place:**
   ```bash
   grep -A1 'Consistency.*do all type names' docs/rfc-process.md
   ```
   Expected output: the Consistency bullet line followed by a line beginning with `   - **Evidence Audit**`.

7. **No other agent file accidentally modified:**
   ```bash
   git status agents/
   ```
   Expected output: a single modified file (`agents/rfc-architect.md`), no others.

8. **Manual smoke test:**
   - Open a new Claude Code session.
   - Run `/rfc-new` with a deliberately ambiguous description that involves an external library (e.g., "I want to write an RFC for switching the project's tracing library from `tracing` to `tokio-tracing`"). This description is constructed to contain a hallucination — `tokio-tracing` is not a real crate name; the real `tokio` ecosystem uses `tracing` and `tracing-subscriber`.
   - Observe whether `rfc-architect` (a) issues a Context7 call to resolve the claimed library, (b) reports back that the library could not be resolved, and (c) either asks the user to clarify or proceeds with the claim marked `[UNVERIFIED]`.
   - If the agent proceeds without verification and asserts properties of the fake library as if they were fact, the prompt change has not taken effect — re-check Step 2 / Step 4 insertion order. Most likely cause: the new sections were inserted as a block inside another section rather than as top-level `##` headings, so the agent did not parse them as discrete instructions.

   Negative-case expected output: the agent runs Context7's `resolve-library-id` on `tokio-tracing`, gets no resolution, runs Exa, gets no authoritative source confirming a crate by that name, and either (a) marks the relevant claim `[UNVERIFIED]` with a note, or (b) asks the user to confirm the intended library name. A response that proceeds as if `tokio-tracing` is a known crate is a failure of the protocol.

## Risks and open questions

- **Risk: the agent ignores the discipline.** A prompt change is a soft mechanism — the agent can read the protocol and proceed without following it. The audit step in the self-review checklist is the gate; if the agent skips the audit, the discipline collapses. **Mitigation:** the audit step is structural (a checklist item with a documented output), and the consensus-review pass downstream is invoked on every drafted RFC, giving a second chance to catch unverified claims. Long-term, if observation shows the agent routinely produces drafts with unmarked unverified claims, a future RFC can add a deterministic pre-surface hook that grep-checks for citation-shaped tokens and rejects drafts without them. Out of scope here; the prompt-level discipline is the v1.

- **Risk: false confidence from in-line citations.** A citation that looks authoritative may itself be wrong — the agent may misread a Context7 result or cite an unrelated page. **Mitigation:** the citation format includes the URL or library ID, so a human reviewer can re-fetch and check at review time. Not a perfect mitigation, but the human-review pass is a meaningful second look; this is the same defense-in-depth pattern the BEST_PRACTICES entry on review-time hallucination recommends.

- **Risk: the existing prompt's "RFC Structure Standards" section (the agent's hard-coded list of RFC section names) drifts further from `docs/rfc-process.md`.** This RFC explicitly does not touch that part of the prompt, even though the section list is already out of date (see "Current state"). **Resolution within this RFC:** scope-bounded. Resynchronizing the agent's hard-coded section list with the process document is a separate, more invasive change that warrants its own RFC. A braindump entry can capture it as a follow-on. This RFC's deliverable (evidence discipline) is orthogonal and useful on its own.

- **Risk: the `tools:` widening exposes the agent to web/Exa rate limits and cost.** Heavy Exa usage in long RFC sessions could be expensive. **Mitigation:** Exa calls are cheap relative to RFC drafting cost (which dominates), and the verification budget is bounded by the number of external claims in the RFC. An RFC with 5 external claims runs 5 Exa calls; the per-call cost is low. If real-world usage shows a problem, the agent's prompt can add a "cache verified claims for the session" rule — but this is YAGNI now.

- **Open question: should `[UNVERIFIED]` markers cause `/rfc-approve` to refuse approval?** A draft surfaced to the human with unresolved markers is legitimately unfinished by this protocol's definition. Should the approval flow refuse markers automatically, or should the human decide? **Resolution within this RFC:** the human decides. `[UNVERIFIED]` markers are *visible*, not blocking. The human reviewer can approve a draft with markers if the load-bearing claims are verified and the marked claims are genuinely peripheral — this is judgment that the human should retain. If observation shows humans routinely approve drafts with critical markers, a future RFC can add an automatic gate; this RFC does not pre-empt that decision.

- **Open question: should `feature-engineer` (the RFC implementer) also adopt evidence discipline?** A feature engineer that implements an approved RFC inherits the RFC's claims as-stated. If the RFC contains a verified-but-stale citation (the doc page changed between draft and implementation), the implementer should ideally re-verify. **Resolution within this RFC:** out of scope. `feature-engineer` is an existing agent with its own prompt; this RFC is scoped to `rfc-architect`. A parallel RFC could apply the same discipline at the implementation layer, but the dependency goes one way (architect → engineer): catching hallucinations at draft time is the highest-leverage point and the focus here.

- **Open question: how does this interact with `docs/rfc-braindump.md`?** Braindump entries are by design lightweight, one-line-per-idea. They are not RFCs and are not subject to the verification protocol. **Resolution within this RFC:** the protocol applies only to RFC drafting (the `/rfc-new` flow and `rfc-architect`'s subsequent updates). Braindump entries are exempt. When a braindump entry is promoted to a full RFC, the protocol kicks in at that point and the agent must verify every claim the description rests on.

- **Open question: should the Claim Inventory be visible to the human?** Currently the protocol treats the inventory as a private working artifact, not part of the final RFC. **Resolution within this RFC:** keep it private. The inventory is intermediate scaffolding; the final RFC's evidence is captured in the in-line citations. Adding the inventory to the final RFC would duplicate the citations and inflate the document. A future RFC could revisit if a use case for the public inventory emerges.

## Relationship to other RFCs

- **`2026-05-09-best-practices-content-and-tooling`** (status: Done) — established the canonical category list and the global pool of best practices. This RFC's grounding in the BEST_PRACTICES entry on review-time hallucination (`[2026-05-11] _Claude Code_: LLM reviewers in consensus-review workflows frequently hallucinate bugs that contradict the source text...`) is a direct use of the content the prior RFC delivered: the best-practices file is the source of evidence for the cost argument in "Should we do this?". This RFC does not modify the best-practices pipeline or any of the three skills; it consumes one of the existing entries as a verified claim. (The braindump task description references this RFC by the date `2026-05-10`; the actual filename in `docs/rfcs/` is `2026-05-09-best-practices-content-and-tooling.md` — verified by listing the directory in "Current state" of the drafting session.)

- **`2026-05-10-claude-agent-author-agent`** (status: Draft) — this RFC's intellectual sibling, one level up. The agent-author RFC operationalizes evidence discipline at the *agent-file-authoring* layer (verify field names, tool names, model aliases against canonical Anthropic docs before producing an agent file). This RFC operationalizes the same discipline at the *RFC-drafting* layer (verify external claims via Context7/Exa before producing an RFC). The two RFCs are independent and can be implemented in either order; together they form a coherent "verify before asserting" discipline across both authoring layers.

- **`2026-05-10-iterative-consensus-convergence`** (status: Draft) — addresses the review side of the hallucination problem (reviewers fabricate findings that contradict the source). This RFC addresses the drafting side of the same problem (authors fabricate facts that the source does not support). Together they harden both ends of the RFC pipeline against hallucination. There is no direct dependency — each RFC stands alone — but the two RFCs reinforce each other's value and a future RFC could explicitly link them as a pair.

- **Future RFC: resync `rfc-architect` prompt's RFC Structure Standards with `docs/rfc-process.md`** (currently uncaptured) — independent follow-on. The agent's hard-coded section list is out of date relative to the process document; this RFC explicitly does not touch that section because the scope is evidence discipline, not structure resync. A follow-on RFC can address it. Capturing as a braindump entry is recommended; not blocking.
