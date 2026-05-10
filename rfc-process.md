# RFC Process

This document defines the RFC (Request for Comments) process for Bytewyrd projects. Projects set up with `/sync` carry a self-contained copy of this document in `docs/rfc-process.md`. See the **Maintaining project RFC files** section at the end.

---

## What is an RFC?

An RFC is a short design document written *before* implementation. It exists to:

1. Force explicit thinking about trade-offs before touching code
2. Create a searchable record of *why* decisions were made
3. Give a place to raise concerns before work starts, not after
4. Serve as the implementation spec that agents follow

RFCs are not bureaucracy — they are cheap insurance against expensive rework.

---

## When to write an RFC

**Write an RFC for:**
- New features or capabilities
- Architectural changes (module structure, data flow, infrastructure topology)
- Migrations (tooling changes, protocol upgrades, schema changes)
- Any work expected to take more than one focused session

**Skip the RFC for:**
- Bug fixes with an obvious, localized solution
- Documentation-only changes
- Minor config tweaks with no design trade-offs
- Work explicitly scoped to implement an already-approved RFC

When in doubt, write one. A short RFC is always better than no RFC.

**Scope check:** Before writing an RFC that covers multiple independent subsystems, split it into separate RFCs — one per subsystem. Each RFC should describe work that can be implemented and tested independently. If subsystems are tightly coupled and must be designed together, one RFC is fine.

---

## Braindump

Before an idea is ready for a full RFC, capture it in `docs/rfc-braindump.md` with `/rfc-braindump`. The braindump is a lightweight parking lot — one line per idea, no design required. When an idea matures, promote it to a full RFC with `/rfc-new`.

---

## RFC lifecycle

```
Draft → Approved → Done
                 ↘ Dropped
```

| Status | Meaning |
|--------|---------|
| `Draft` | Being written or under agent review; not yet human-approved |
| `Approved` | Human-approved via `/rfc-approve`; implementation may begin |
| `Done` | The work described is complete and merged |
| `Dropped` | Will not be implemented; reason recorded |

The agent pre-review loop (write → review agents → incorporate feedback → self-review) happens entirely within `Draft`. The RFC stays `Draft` until the human explicitly runs `/rfc-approve`. The human never sees a raw first draft — only the post-review, post-self-review version.

---

## File format and location

RFCs live in `docs/rfcs/` in the project repository.

**Filename:** `YYYY-MM-DD-<kebab-case-title>.md` where `YYYY-MM-DD` is the creation date (e.g., `2026-05-08-gateway-namespace.md`). Same-day collisions are avoided in practice by topics being different.

**Never delete or reuse an identifier.** Dropped RFCs keep their files permanently — they are historical record, not clutter.

### Required YAML frontmatter

Every RFC must begin with this frontmatter block:

```yaml
---
rfc: "2026-05-08-gateway-namespace"  # YYYY-MM-DD-<kebab(title)> — must equal filename stem
title: "Gateway Namespace"
author: "Full Name"
status: "Draft"         # Draft | Approved | Done | Dropped
created: "YYYY-MM-DD"
drop_reason: ~          # required if status = Dropped; one sentence explaining why
---
```

When a status transition occurs, update `status`. Timeline is traceable via git history. `drop_reason` is the only additional field — set it when `status` becomes `Dropped`, leave it `~` otherwise.

---

## RFC structure

There is no required section order, but a complete RFC generally covers:

1. **Summary** — one paragraph: what is being proposed and why
2. **Should we do this?** — explicit yes/no with rationale; makes the decision visible
3. **Current state** — what exists today that this RFC addresses
4. **Analysis / Options** — trade-offs between approaches; recommend one. If two options are operationally identical or near-identical, do not list them separately — present the shared option once and include the distinguishing note as a variant, footnote, or "door stays open" paragraph. Duplicate options add noise and make the recommendation harder to follow.
5. **Drawbacks** — honest assessment of the downsides, costs, and risks of the recommended approach. Every approach has tradeoffs; name them explicitly rather than burying them in the alternatives.
6. **Implementation spec** — enough detail for an agent to implement without guessing
7. **Risks and open questions** — what could go wrong; unresolved decisions
8. **Relationship to other RFCs** — dependencies or conflicts with other RFCs

Scale each section to its complexity. A simple RFC may compress several sections into a paragraph.

**Security Considerations** is an optional section required whenever the RFC touches authentication, authorization, secrets, user data, permissions, or external integrations. Include it after "Risks and open questions" when relevant. The security review agents (`security-engineer`, `penetration-tester`) are added automatically by the review agent selection table when this section is present or when the domain warrants it.

**When comparing tools, libraries, or platforms:** do full research on each candidate before writing the Analysis section. This means going beyond surface-level feature lists — verify actual capabilities, configuration requirements, known limitations, ergonomics, and operational complexity for each option. Claims about what a tool "can" or "cannot" do must be grounded in documentation or source evidence, not assumptions. Inaccurate capability comparisons lead to wrong recommendations and implementation surprises. If research reveals a tool can do something the RFC initially assumed it couldn't (or vice versa), the RFC must reflect the corrected finding before being finalized.

### Implementation spec requirements

**File structure first.** Before listing implementation steps, map every file that will be created or modified, with exact paths and a one-line description of each file's responsibility. This is where decomposition is decided — do it explicitly rather than discovering it mid-implementation.

```markdown
| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/auth/token.rs` | JWT encoding/decoding |
| Modify | `src/auth/mod.rs`   | Re-export token module |
```

**No placeholders.** Every step must contain what an implementer actually needs. These are spec failures — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases" (without specifics)
- "Similar to the above" (repeat the content — implementers may work out of order)
- Steps that describe *what* to do without showing *how*
- References to types, functions, or methods not defined anywhere in the spec

When the spec includes commands, include the exact command string and the expected output.

---

## Agent rules

**Always use specialized agents** when working with RFCs. Never write, review, update, or implement RFC content as the main agent (inline).

**Model:** All RFC-related agent tasks must use `model: "opus"` — the highest available model. RFC quality depends on deep reasoning. Never downgrade to a cheaper model for RFC work.

### Writing a new RFC

Use `/rfc-new` to create a new RFC. The skill handles numbering, template creation, and agent dispatch. The agent flow is:

1. `rfc-architect` agent (`model: "opus"`) fills in the RFC template from the provided description and context.
2. **Immediately** after writing, `rfc-architect` spawns the appropriate review agents in parallel — do not wait for human input.
3. `rfc-architect` incorporates review feedback and resolves conflicts by reasoning about the RFC's stated goals.
4. `rfc-architect` runs the **self-review checklist**:
   - **Coverage** — skim every requirement; can each be pointed to a section of the implementation spec? List and fill any gaps.
   - **Placeholder scan** — search for any prohibited pattern from the "No placeholders" list above; fix each one.
   - **Consistency** — do all type names, function signatures, file paths, and interface names used in later steps match what was defined in earlier steps?
5. `/rfc-consensus-review` runs: five independent reviewers in parallel, findings synthesized by consensus. Critical findings (4–5/5 reviewers) are fixed by `rfc-architect` in a second pass; consensus runs once more to verify. If critical findings remain after two passes, they are surfaced to the human alongside the RFC.
6. Present the post-consensus RFC to the human. RFC status stays `Draft`.

The human never sees a raw first draft — only the post-review, post-consensus version.

### Updating an existing RFC

Spawn a `rfc-architect` agent (`model: "opus"`). After updates, re-run the relevant review agents for changed sections, run the self-review checklist, then surface to the human.

### Addressing inline review comments

Use `/rfc-read-feedback`. Humans annotate the RFC file directly with `FEEDBACK:` markers; the skill dispatches `rfc-architect` to address each comment, remove the markers, and run the self-review checklist.

### Choosing review agents

Always include the general reviewer. Add domain-specific agents based on what the RFC touches. All review agents run at `model: "opus"`.

**Always include:**

| Concern | Agent |
|---------|-------|
| General correctness, logic, feasibility | `code-reviewer` |

**Add based on RFC domain:**

| RFC touches… | Add agent(s) |
|--------------|-------------|
| Security, auth, secrets, permissions, IAM | `security-engineer`, `penetration-tester` |
| Frontend UI, user-facing components | `frontend-developer`, `ux-design-architect` |
| React / Next.js | `react-specialist`, `nextjs-developer` |
| Infrastructure, Terraform, cloud resources | `terraform-engineer`, `cloud-architect` |
| Kubernetes, Helm, cluster config | `kubernetes-specialist` |
| Databases, schema, queries | `database-administrator`, `postgres-pro` |
| APIs, REST, GraphQL | `api-designer`, `graphql-architect` |
| Performance, scalability | `performance-engineer` |
| AI / LLM / MCP | `ai-engineer`, `llm-architect`, `mcp-developer` |
| Observability, reliability | `sre-engineer` |

Run all review agents in parallel. The `rfc-architect` agent synthesizes their outputs — conflicting feedback is resolved by reasoning about the RFC's stated goals, not by deferring to whichever reviewer was most emphatic.

### Implementing an approved RFC

Use `/rfc-implement`. The skill spawns a `feature-engineer` agent (`model: "opus"`) with the approved RFC as primary input. The agent follows the implementation spec; it does not redesign. If the spec is ambiguous, update the RFC first (via `rfc-architect` + `/rfc-read-feedback`) rather than having the implementation agent guess. When implementation is complete and merged, update `status` to `Done`.

---

## Maintaining project RFC files

Projects keep a `docs/rfc-process.md` that is a **self-contained copy** of this document, plus optional project-specific extensions in a `## Project Extensions` section at the bottom. This makes the full process visible to all contributors, not just those with the plugin installed.

**Skills:**

| Skill | Purpose |
|-------|---------|
| `/rfc-braindump` | Capture a quick RFC idea into `docs/rfc-braindump.md` |
| `/rfc-new` | Create a new RFC from template, run agent review, run consensus review, and fix critical findings |
| `/rfc-consensus-review` | Spawn 5 parallel reviewers, synthesize findings by consensus, report tiered results |
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments left by humans in an RFC |
| `/rfc-approve` | Approve a Draft RFC (human-invoked) |
| `/rfc-implement` | Begin implementing an Approved RFC |
| `/rfc-drop` | Drop an RFC with a reason |
| `/rfc-update` | Pull upstream changes into `docs/rfc-process.md` (also handled automatically by `/sync`) |
| `/sync` | Set up or refresh the full project Claude Code environment, including RFC process |

**Project extensions may add:**
- Project-specific naming conventions or directory layout
- Required reviewers or approval gates beyond the defaults
- Module paths and file references relevant to that project's RFCs
- Additional frontmatter fields
- Domain-specific default agents for the project's stack
