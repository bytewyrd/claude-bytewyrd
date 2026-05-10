# Triage and Lift

Shared procedure for `best-practices-extract`, `best-practices-record`, and `best-practices-sync`. The three skills reference this file rather than duplicating the text. When this file changes, all three skills inherit the change.

## Triage — three portability questions

Apply these three questions in order to every candidate before any other action. The candidate is **generalizable** only if all three are yes.

### Question 1 — Framework portability

Would this rule still be true if the project changed languages, frameworks, or major libraries?

- "Use `Result<T, E>` over panic for recoverable errors" → if the project switched from Rust to Go, the equivalent would be "return an `error` value instead of calling `panic`" — same principle. **Yes.**
- "Use `bun install --frozen-lockfile` in CI" → the principle ("lock dependency versions in CI") survives a switch to npm or pnpm; the wording ("`bun install --frozen-lockfile`") does not. **No, in this wording**; **yes** if rewritten as the principle.
- "The `RouterConfig` struct should not call into `auth::token`" → if the project changed languages, this entry has no meaning. **No.**

### Question 2 — Project portability

Would a developer on a different project, with no knowledge of this codebase, benefit from reading this?

- "Practice TDD on pure logic — Red/Green/Refactor" → universal engineering advice. **Yes.**
- "Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code" → universal testing principle. **Yes.**
- "Our `sync` skill must read from the worktree, not from `git rev-parse --git-common-dir`" → only meaningful for the bytewyrd plugin codebase. **No.**

### Question 3 — Audience portability

Does this entry survive being read in two years, by someone with no memory of the session that produced it?

- "Validate input at the boundary, then trust it inside" → reads cleanly without context. **Yes.**
- "Use `bind:` for two-way binding in Svelte form inputs" → reads cleanly with the explicit `Svelte:` prefix. **Yes.**
- "We had to refactor `RouterConfig::from_env` to delegate auth resolution to `core::auth::resolve_token` instead" → meaningless without the session's context. **No.**

### Outcome

- **All three yes** → generalizable. Continue to the lift step.
- **Any one no** → project-specific. The originating skill decides what to do (see the per-skill instructions for routing).

## Lift — two-pass rewrite plus verification

Apply these passes only to candidates that passed triage.

### Pass 1 — Strip the instance

Remove from the candidate text:

- Project names, repo names, package names ("`bytewyrd-workflow`", "`tinywyrd`", "`eve-platform`").
- File paths ("`src/auth/token.rs`", "`skills/sync/SKILL.md`").
- Type names, function names, struct names, class names ("`RouterConfig`", "`DetailOverlay::new`", "`processOrder`").
- Module names and namespaces ("`core::k8s::target`", "`@scope/package`").
- Version numbers and tool versions specific to a single moment in time ("Rust 1.78", "Svelte 4.2.7").
- Internal vocabulary the project invented ("the resolver", "the dispatcher" — unless these are domain words a reader of any project would know).

Replace each removed identifier with the *role it played* in the principle:

- "`DetailOverlay`" → "the wrapper component"
- "`core::k8s::target`" → "the subsystem responsible for assembling the K8s target"
- "`auth::token`" → "the authentication submodule"

If after stripping, the candidate is empty or vacuous ("The component calls the module"), the original was project-specific in fact — re-triage it as project-specific and route accordingly.

### Pass 2 — Name the domain

Prepend the technology, layer, or domain the principle applies to. The prefix makes the entry self-contained when read in isolation.

| Domain | Prefix |
|---|---|
| Vue, React, Svelte component model | `Vue:` / `React:` / `Svelte:` |
| Rust async or trait system | `Rust:` (with sub-qualifier as needed: `Rust async:`) |
| Kubernetes manifests / CUE / kapply | `K8s:` / `K8s/CUE:` / `kapply:` |
| Cross-cutting architecture | `Architecture:` |
| Testing methodology | `Testing:` |
| Documentation discipline | `Documentation:` |
| Security hygiene | `Security:` |
| Error handling | `Error Handling:` |

Match the prefix to the existing section header in `~/.claude/BEST_PRACTICES.md` and `skills/sync/SKILL.md` (use the canonical abbreviated label — `_K8s_`, `_Rust_`, `_JS/TS_`, etc.) so the entry lands in the right destination section without rework.

### Verification — re-read in isolation

Read the lifted candidate one more time, with this question in mind:

> "If I encounter this entry in `~/.claude/BEST_PRACTICES.md` two years from now, with no other context, can I act on it?"

If the answer is no — the entry still references something only the originating session would know — return to Pass 1 and lift higher. If after a second pass the entry still fails, treat it as project-specific (the principle is real but you cannot extract it without losing meaning; record the instance-level statement project-locally instead).

## Worked examples

| Original (project-specific) | After Pass 1 (stripped) | After Pass 2 (named domain) | Verdict |
|---|---|---|---|
| `RouterConfig::from_env` should delegate auth resolution to `core::auth::resolve_token` | The configuration layer should delegate auth resolution to the authentication submodule | Architecture: subsystem boundaries own their domain assembly; configuration layers only resolve and forward inputs | Generalizable, lifted |
| `DetailOverlay` passes compact state via `provide` so slot content can inject it | The wrapper component shares state with slot content via `provide` / `inject` | Vue: when a wrapper component renders arbitrary slot content and needs to share state with it, use `provide` / `inject` — slot content has no prop access to its wrapper | Generalizable, lifted |
| The `bytewyrd-sync` skill should write to the worktree, not the main repo | The skill should write to the current working directory, not a parent repo root | Skill design: worktree-aware tooling must write to the cwd-derived working tree, never to a "common" repo root | Generalizable, lifted |
| The `sync.skill` reads from `~/.claude/plugins/installed_plugins.json` to detect the GitHub MCP | (after strip) The skill reads from a JSON file to detect a plugin | (after Pass 2) (still vacuous — no useful principle) | Project-specific, route to `## Project-Specific` |
