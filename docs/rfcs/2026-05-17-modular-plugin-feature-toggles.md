---
rfc: "2026-05-17-modular-plugin-feature-toggles"
title: "Modular Plugin Feature Toggles"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-17"
drop_reason: ~
---

## Summary

Restructure the plugin so its skills and agents are partitioned into a small **core** group that ships unconditionally and a set of **optional feature groups** (currently `rfc-workflow`, `refactor`, `best-practices`, `docs-review`) that consumer projects opt into during `/sync`. Toggle state is persisted in a per-project `.bytewyrd/features.json` file written and re-applied by `/sync`. Because Claude Code does not allow a plugin's consumer to remove individual skills or agents from the plugin's own checkout — the manifest's `skills`/`agents` fields are author-side, not consumer-side (Exa: https://code.claude.com/docs/en/plugins-reference) — each optional skill enforces its own toggle at runtime: a four-line bash probe at the top of the skill body reads `.bytewyrd/features.json` via the new `scripts/feature-toggle.sh` helper and, when the feature is off, prints a one-line "feature disabled" message naming the toggle and exits cleanly. Cross-feature references (e.g., `/refactor` is documented inside `docs/CONTRIBUTING.md`'s workflow section) are guarded by the same probe pattern: a section that mentions an optional skill carries a `feature-aware` note explaining how to enable the group, so a project that disabled the group does not see a broken cross-reference treated as fact. Feature group boundaries are declared in a new `feature-groups.json` manifest at the plugin root (peer of `.claude-plugin/bootstrap-manifest.json`), enumerating which skill IDs, agent IDs, manifest artifacts, and `CLAUDE.md` sections belong to each group; the manifest is the single source of truth used by `/sync`, the in-skill probe helper, and the docs-aware sections of the bootstrapped files.

## Should we do this?

**Yes.** The current plugin is all-or-nothing: enabling it imports every skill (`/rfc-new`, `/rfc-implement`, `/refactor`, `/best-practices-extract`, etc.) and every operating convention (Conventional Commits, RFC-process enforcement, the `## Workflow` section of `CLAUDE.md` declaring `/rfc-new` as the canonical design path) into every project the user opens. For a project that does not use the RFC process — a quick prototype, a documentation-only repo, a team that uses a different design-doc workflow — the imports are pure noise: the slash command list is cluttered, the `CLAUDE.md` instructs the agent to "use the RFC process for changes requiring design decisions" (verified: CLAUDE.md:L122) and to run `/rfc-new` even when no such process exists in the project, and the plugin's `SessionStart` hook nudges about missing companion plugins that the project doesn't need. The cost of opt-in toggles is small (one new manifest file, one new helper script, a `/sync` step that runs once per project per plugin-version bump, and a ~4-line probe added to each optional skill); the payoff is real adoption flexibility — a team can install the plugin once at user scope (per `2026-05-12-user-scope-plugin-installation` — verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L97) and then per-project decide whether they want RFC discipline, refactor scaffolding, best-practices extraction, or just the bare-minimum hooks and conventions that every Bytewyrd repo benefits from.

The alternative is shipping multiple plugins (`bytewyrd-core`, `bytewyrd-rfc`, `bytewyrd-refactor`) and asking consumers to install only what they want. That path is structurally worse for this codebase: every cross-skill reference in the current plugin is by `bytewyrd:<skill>` namespace (verified: skills/rfc-new/SKILL.md, skills/refactor/SKILL.md, skills/docs-review/SKILL.md, skills/rfc-consensus-review/SKILL.md, skills/rfc-read-feedback/SKILL.md, skills/rfc-implement/SKILL.md), so splitting the plugin would require renaming every cross-reference (`bytewyrd:rfc-architect` becomes either `bytewyrd-rfc:rfc-architect` or some marketplace-coordinated identifier), or accepting that disabling one sub-plugin silently breaks every reference into it from another sub-plugin. Multi-plugin distribution also collides with two known Claude Code issues: `marketplace.json` `plugins[].skills` filter is ignored on shared source roots (Exa: https://github.com/anthropics/claude-code/issues/53426) and skill duplication appears across sibling plugins from the same marketplace source (Exa: https://github.com/anthropics/claude-code/issues/21148). Toggling within a single plugin sidesteps all of that.

## Current state

### What the plugin ships today

`.claude-plugin/plugin.json` declares only `name`, `description`, `version`, `author` (verified: .claude-plugin/plugin.json:L1-L9) — no `skills`/`agents`/`commands`/`hooks` component-path fields. Per the Claude Code plugin reference (Exa: https://code.claude.com/docs/en/plugins-reference), in the absence of those fields Claude Code auto-discovers components from the default locations: every directory under `skills/` whose entry is a `SKILL.md` becomes a skill, every `.md` file under `agents/` becomes an agent definition, and `hooks/hooks.json` (verified: hooks/hooks.json:L1-L38) becomes the plugin's hook contributions. Auto-discovery is unconditional — a consumer who enables `bytewyrd@bytewyrd` inherits every component the plugin's checkout contains.

The current skill set (verified by listing `skills/` in the working directory): `best-practices-extract`, `best-practices-record`, `docs-review`, `git-branch-cleanup`, `refactor`, `rfc-approve`, `rfc-braindump`, `rfc-consensus-review`, `rfc-drop`, `rfc-implement`, `rfc-new`, `rfc-read-feedback`, `rfc-summary`, `rfc-update`, `sync` — fifteen skills, all exported unconditionally.

The current agent set (verified by listing `agents/`) is 48 files. Most are general-purpose engineering specialists (`rust-engineer`, `python-pro`, `terraform-engineer`, `kubernetes-specialist`, etc.) whose presence in the plugin is documented as the source of Bytewyrd's "specialized agent over inline implementation" convention (verified: CLAUDE.md:L20-L31 — the Agent delegation table). A small subset are tightly coupled to specific skills: `rfc-architect` is spawned by every `/rfc-*` skill (verified: skills/rfc-new/SKILL.md:L7 `bytewyrd:rfc-architect`, skills/rfc-read-feedback/SKILL.md, skills/rfc-consensus-review/SKILL.md); `refactoring-specialist` is spawned exclusively by `/refactor` (verified: skills/refactor/SKILL.md:L40 `bytewyrd:refactoring-specialist`); `docs-agent` is spawned exclusively by `/docs-review` (verified: skills/docs-review/SKILL.md `bytewyrd:docs-agent`); `claude-agent-author` is referenced by `docs/CONTRIBUTING.md`-equivalent docs but has no direct skill front door.

### How the plugin currently writes project files

`/sync` is the canonical project-setup skill (verified: skills/sync/SKILL.md:L1). It reads `.claude-plugin/bootstrap-manifest.json` (verified: .claude-plugin/bootstrap-manifest.json:L1-L203), classifies each artifact via a three-way diff between plugin canonical, project local, and last-synced ancestor (verified: skills/sync/SKILL.md:L283-L341), and applies the appropriate extension strategy per artifact. Today every artifact is applied unconditionally — the manifest has no concept of "this artifact only matters if feature group X is enabled."

Two manifest artifacts carry plugin-feature-specific content that a consumer who has disabled the corresponding feature should not receive:

- `bytewyrd/docs/rfc-process.md@v1` (verified: .claude-plugin/bootstrap-manifest.json:L180-L187, source `rfc-process.md`, target `docs/rfc-process.md`) — only meaningful when `rfc-workflow` is enabled. A project with `rfc-workflow=false` should not have a `docs/rfc-process.md` created.
- `bytewyrd/CLAUDE.md@v1` (verified: .claude-plugin/bootstrap-manifest.json:L80-L106) — uses `extension_strategy: "section"` with ten `owned_sections`, several of which are feature-coupled: `## RFC Process` (verified: .claude-plugin/scripts/templates/CLAUDE.md.tpl:L34-L41) reads "RFCs live in `docs/rfcs/`; ... Skills: `/rfc-new`, `/rfc-approve`, ..." which is content a non-RFC project should not have written into its `CLAUDE.md`.

The remaining manifest artifacts (`README.md`, `docs/ARCHITECTURE.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md`, `.github/workflows/ci.yml`, `.gitignore`, `mise.toml`, `.claude/settings.json`, `.claude/settings.local.json`, `.github/PULL_REQUEST_TEMPLATE.md`, `.claude/.bootstrap-versions.json`) are feature-agnostic — every Bytewyrd project gets them regardless of which optional features are enabled. They form the natural core.

### How cross-skill references work today

Skill bodies and agent prompts reference other skills and agents by namespace-prefixed identifier: `bytewyrd:rfc-architect`, `bytewyrd:refactoring-specialist`, `bytewyrd:docs-agent`, `bytewyrd:code-reviewer`. Per the Claude Code skills reference (Exa: https://docs.anthropic.com/en/docs/claude-code/skills), plugin skills are invoked with the namespace prefix `plugin-name:skill-name`. The bodies also reference other slash commands by name: `/refactor` is named inside `docs/CONTRIBUTING.md`-equivalent guidance, `/rfc-new` appears in the `## Workflow` section of `CLAUDE.md` as the documented way to handle design changes (verified: CLAUDE.md:L122-L128, project's CLAUDE.md verified inline).

The same is true of bootstrapped files written into consumer projects:

- The `CLAUDE.md.tpl` template (verified: .claude-plugin/scripts/templates/CLAUDE.md.tpl:L34-L41) ships the `## RFC Process` section verbatim, telling the consuming agent to "Use RFC skills for all design and implementation work" — a sentence whose truth depends on whether `rfc-workflow` is enabled in the project.
- The shipped `docs/CONTRIBUTING.md` template (verified by reading the file at `.claude-plugin/scripts/templates/CONTRIBUTING.md.tpl`) and `docs/ARCHITECTURE.md` template each contain references to plugin-shipped skills.

### Constraints from the Claude Code plugin system

The plugin reference (Exa: https://code.claude.com/docs/en/plugins-reference) is explicit about three rules that constrain any toggle design:

- **`skills` field in `plugin.json` is additive** — listing custom skill directories does not remove the default `skills/` directory from auto-discovery. A skill physically present under `skills/` is always discovered.
- **`commands` and `agents` fields are replacing** — listing custom paths replaces the default directory scan. But this only helps the plugin author at build time; the consumer cannot edit the plugin's own `plugin.json` per project.
- **No per-project skill disable mechanism in `.claude/settings.json`.** The `enabledPlugins` block (verified: settings docs at Exa: https://docs.claude.com/en/docs/claude-code/settings) toggles entire plugins on/off but does not address sub-plugin granularity. There is no `disabledSkills` or `enabledSkills` field that a project's `.claude/settings.json` can use to suppress a specific plugin skill.

The SKILL.md frontmatter does include `disable-model-invocation: true` (verified: Exa: https://docs.anthropic.com/en/docs/claude-code/skills) which prevents Claude from auto-loading a skill but still lets users invoke it via `/name`. This is a plugin-author-side switch baked into the SKILL.md file shipped with the plugin — it is not a per-project knob.

These constraints mean **consumers cannot suppress a plugin's components by editing project files** — the suppression has to be enforced inside the skill body, which the consumer's project files can read and respond to. That is the mechanism this RFC builds: every optional skill self-checks the project's `.bytewyrd/features.json` at the top of its body and exits with a one-line "feature disabled" message when its feature group is off.

### Prior art in the codebase

The `scripts/tool-probe.sh` helper (verified: scripts/tool-probe.sh:L1-L102) already establishes the pattern of skills calling a shared bash helper at the top of their body, parsing a single-line JSON response, and short-circuiting on a `missing` result. Three skills use it today: `best-practices-extract` (verified: skills/best-practices-extract/SKILL.md:L12-L21), `refactor` (verified: skills/refactor/SKILL.md:L11-L21), and `rfc-implement` (per `2026-05-12-user-scope-plugin-installation`). The same probe-and-exit pattern is the natural shape for the feature-toggle check; the new helper this RFC adds (`scripts/feature-toggle.sh`) is the feature-toggle analog.

The `2026-05-12-user-scope-plugin-installation` RFC (verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L880) already anticipated this RFC's interaction surface: "the requirement check needs to be aware of toggle state so it doesn't warn about a missing dependency the user has explicitly disabled — but that integration is small (the check reads the toggle state from wherever the toggles RFC chooses to store it)." That note pins the integration point: `scripts/check-requirements.sh` (verified: scripts/check-requirements.sh exists in the working directory; full inline content reproduced in the user-scope-plugin-installation RFC, lines L213-L420) reads `.bytewyrd/features.json` and skips warnings for companion plugins that only matter to disabled features.

The `2026-05-14-sync-per-file-extension-strategies` RFC (verified: docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md — status Approved) relocates the sync sidecar to `.bytewyrd/.bootstrap-versions.json` and adds `.gitignore` rules that ignore `.bytewyrd/*` except the sidecar. That sets the precedent for `.bytewyrd/` as the plugin's project-state directory; this RFC puts `features.json` next to the sidecar and extends the `.gitignore` carve-out to track it.

## Analysis / Options

The design has four coupled decisions:

1. **Decomposition** — how to draw the boundary between core and optional features.
2. **Enforcement mechanism** — how a feature toggle actually causes a skill to behave differently.
3. **State storage and lifecycle** — where toggle state lives and when it is read or rewritten.
4. **`/sync` interaction model** — when the user is prompted about toggles and how re-runs handle prior choices.

### Decision 1 — Decomposition: which features qualify as core, which as optional

**Recommendation: a four-group taxonomy.** The plugin's components partition cleanly into one core group and four optional groups based on whether the consumer's value from the component depends on adopting an opinionated workflow:

- **`core` (always installed, not toggleable):** every component whose value is independent of a specific workflow choice. This includes:
  - The `/sync` skill itself — without it, the plugin cannot bootstrap a project at all.
  - The `/git-branch-cleanup` skill — generic git hygiene, useful in every project.
  - The `SessionStart` requirement-check hook (verified: hooks/hooks.json:L18-L36) — surfaces missing companion plugins regardless of workflow choices.
  - The `SubagentStop` reminder on `feature-engineer` (verified: hooks/hooks.json:L3-L17) — surfaces only when `feature-engineer` is invoked, which is feature-agnostic.
  - All general-purpose engineering agents in `agents/` (`rust-engineer`, `python-pro`, `terraform-engineer`, etc., and the foundational `feature-engineer`, `code-reviewer`, `debugger`, `documentation-writer`, `claude-agent-author`) — referenced by the always-shipped `CLAUDE.md` Agent delegation table and useful to every project.
  - The feature-agnostic manifest artifacts: `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `docs/BEST_PRACTICES.md`, `.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, `.gitignore`, `mise.toml`, `.claude/settings.json`, `.claude/settings.local.json`, `.claude/.bootstrap-versions.json`, plus the `CLAUDE.md` core sections (`## Toolchain`, `## File structure`, `## Agent delegation`, `## Tool Usage`, `## Evidence-Based Development`, `## Model Usage Optimization`, `## Claude Code Sandbox — Container Tool Compatibility`, `## Security`, `## Conventions`).

- **`rfc-workflow` (optional):**
  - Skills: `rfc-new`, `rfc-approve`, `rfc-implement`, `rfc-drop`, `rfc-braindump`, `rfc-read-feedback`, `rfc-summary`, `rfc-consensus-review`, `rfc-update`.
  - Agents: `rfc-architect` (used exclusively by `rfc-*` skills — verified: agents/rfc-architect.md:L4 `model: opus` and the description listing `/rfc-new`, `/rfc-consensus-review`, `/rfc-read-feedback` as its only callers).
  - Manifest artifact: `bytewyrd/docs/rfc-process.md@v1`.
  - `CLAUDE.md` section: `## RFC Process` (verified: .claude-plugin/scripts/templates/CLAUDE.md.tpl:L34-L41 — the section that names the `/rfc-*` skills as the canonical design workflow).
  - Companion plugins that matter only here: `github@claude-plugins-official` is used by `/rfc-implement` for PR creation (verified: skills/rfc-implement/SKILL.md probe section), but it is also used by other workflows so it does not gate exclusively on this group.

- **`refactor` (optional):**
  - Skills: `refactor`.
  - Agents: `refactoring-specialist` (used exclusively by `/refactor` — verified: skills/refactor/SKILL.md:L40 `bytewyrd:refactoring-specialist`).
  - No `CLAUDE.md` section is exclusively the `refactor` group's — the `### Considering /refactor` subsection of the `## Workflow` section is added by the user-scope-plugin-installation RFC, lives inside the larger `## Workflow` section, and is the natural place for the `feature-aware` annotation pattern (described in Decision 4).
  - Companion plugins: `code-review@claude-plugins-official` is used by `/refactor` as a soft pre-pass (verified: skills/refactor/SKILL.md:L11-L21).

- **`best-practices` (optional):**
  - Skills: `best-practices-extract`, `best-practices-record`.
  - Agents: none (the skills run inline; `feature-engineer` is core and is the agent these skills invoke).
  - `CLAUDE.md` section: none exclusively, but the `## Workflow → Session end` subsection (added by user-scope-plugin-installation) references `/best-practices-extract` and gets the `feature-aware` treatment.
  - The plugin-local `best-practices-sync` skill (verified: .claude/skills/best-practices-sync/) is not exported and is unaffected.

- **`docs-review` (optional):**
  - Skills: `docs-review`.
  - Agents: `docs-agent` (used exclusively by `/docs-review` — verified: skills/docs-review/SKILL.md `bytewyrd:docs-agent`).
  - `CLAUDE.md` section: none exclusively; the `### Considering /docs-review` subsection of `## Workflow` is the cross-reference point.
  - Companion plugins: none specific.
  - Hooks: the `SessionStart` `compact` matcher in `hooks/hooks.json:L19-L26` (verified) prints a post-compact reminder about `/docs-review`; this is feature-coupled but is left in the core hook bundle (the body is a single bash one-liner with no side effects when the feature is disabled — the user simply ignores the reminder).

**Why this exact taxonomy.** Each optional group corresponds to a workflow a team can plausibly choose to skip without breaking the rest of the plugin: a project can do refactor passes without RFCs, or use RFCs without the `refactor` skill, or extract best-practices without RFCs, or audit user-facing docs without any of the other workflows. Conversely, every component in `core` has demonstrable value in every project that uses the plugin at all — there is no project that benefits from installing the plugin but does not benefit from `/sync` or from the `## Tool Usage` and `## Security` sections of `CLAUDE.md`. Drawing the line elsewhere (e.g., making `git-branch-cleanup` optional, or splitting RFC skills into `rfc-authoring` and `rfc-execution`) would either add toggles for components with no realistic opt-out demand or fragment a workflow whose pieces are useless individually.

**Alternative rejected — finer granularity.** A taxonomy with one toggle per skill (15 toggles instead of 4) was considered. Rejected: most skills do not have an independent value proposition (a project that wants `/rfc-new` always wants `/rfc-approve` and `/rfc-implement` too — the RFC lifecycle does not work with any of them missing); the cardinality of choices the user has to make at `/sync` time grows linearly and the AskUserQuestion prompt becomes unwieldy; the per-skill probe code in each SKILL.md is identical. Four groups capture every distinct adoption choice the author has heard real users articulate.

**Alternative rejected — coarser granularity.** A two-toggle taxonomy (`core` + `everything-else`) was considered. Rejected: it collapses orthogonal choices. A team that wants RFC discipline but not the `/refactor` heavy-touch workflow (or vice versa) would have no way to express that — they would either inherit both or neither.

### Decision 2 — Enforcement mechanism: how a feature toggle actually disables behavior

**Recommendation: in-skill runtime probe + manifest-aware sync + section-aware bootstrapped-file rendering.** Each component category is enforced by the mechanism appropriate to its surface:

1. **Skills.** Every optional skill carries a four-line probe at the top of its body that calls `scripts/feature-toggle.sh <feature-group>` and short-circuits if disabled:

    ```bash
    result="$(bash scripts/feature-toggle.sh rfc-workflow)"; status=$?
    if [ "$status" -ne 0 ]; then printf '%s\n' "$(printf '%s' "$result" | jq -r .message)"; exit 0; fi
    ```

   The helper script returns exit 0 (enabled) or exit 1 (disabled) with a JSON payload on stdout. When disabled, the message printed is exactly: `/<skill-name> is disabled in this project — feature group "<group>" is off. To enable, run /sync and select "<group>" in the feature-toggle prompt, or edit .bytewyrd/features.json directly.`

   The probe is at the top of the skill body (before any other side effect — script execution, agent spawn, file write) so a disabled skill never modifies project state. The exit is clean (`exit 0`) so Claude Code does not treat it as a failure.

2. **Agents.** Agents are spawned only from skills (no agent in the plugin is invoked except via a skill or via the user typing `@<agent-name>`). The skill that spawns an agent runs its probe first; if the skill exits early, the agent is never spawned. For the rare case where a user types `@rfc-architect` directly in a project that has the `rfc-workflow` feature off, the agent's prompt body opens with an optional check (added to `rfc-architect.md`, `refactoring-specialist.md`, and `docs-agent.md`) that reads the project's `.bytewyrd/features.json` and, if the corresponding feature is off, replies with a one-line "this agent's feature group is disabled in this project; enable via `/sync`" message before exiting. This is a soft guard — Claude Code still lists the agent in `@`-autocomplete because the agent file is on disk — but it ensures the agent does not perform work for a project that has opted out.

3. **Manifest artifacts.** The bootstrap manifest gains a `feature_group` field per artifact. `/sync` reads `.bytewyrd/features.json` (creating it if absent — see Decision 4) and skips artifacts whose `feature_group` is disabled in the project. Today, only `bytewyrd/docs/rfc-process.md@v1` has a non-core `feature_group` (`rfc-workflow`); future feature-coupled artifacts (none currently planned) would follow the same pattern.

4. **`CLAUDE.md` sections.** The `CLAUDE.md` artifact uses `extension_strategy: "section"` (verified: .claude-plugin/bootstrap-manifest.json:L84). The manifest entry gains a `section_feature_groups` map that pairs each owned section to its feature group (with `null` meaning core / always-shipped). When `/sync` renders `CLAUDE.md`, sections whose feature group is disabled are omitted from the rendered output (not just skipped from the merge — the section heading itself does not appear in the project's file). The plugin-side canonical hash (used by `/sync`'s extension-strategies pass) is computed from the post-omission rendered output, so a project that disables `rfc-workflow` and re-runs `/sync` does not see the omitted `## RFC Process` section re-classified as a missing-section delta.

5. **Bootstrapped templates with embedded slash-command references.** The `docs/CONTRIBUTING.md` template (`bootstrap` strategy per the per-file-extension-strategies RFC — verified: docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md Decision-2 assignment) is written once and never updated by the plugin, so consumers handle their own contents thereafter. The plugin-rendered initial body uses the same section-feature-group filter as `CLAUDE.md` when initially rendered — sections referencing disabled features are omitted at first-write time. This avoids the situation where a fresh project that disabled `rfc-workflow` ends up with a `## RFC Process` paragraph in its `CONTRIBUTING.md` that mentions skills it does not have. (For projects that enable `rfc-workflow` later, the section is the project's responsibility to add — by RFC design, `bootstrap` files are not re-touched after creation.)

6. **Hooks.** The plugin-shipped `hooks/hooks.json` contributes two hooks today (verified: hooks/hooks.json:L1-L38): `SubagentStop` on `feature-engineer` (core — always relevant) and `SessionStart` (split into a `compact`-matched docs-review reminder and an unmatched requirement-check). All three are kept in core. The docs-review reminder (`SessionStart` with `matcher: "compact"`) is a one-line `echo` whose only effect is reminding the user about `/docs-review` — a project that has `docs-review` disabled simply ignores the reminder. Putting hooks behind feature toggles is not worth the complexity for the current set; if a future hook actually performs a side-effecting action gated on a feature, the hook command itself can probe `.bytewyrd/features.json` with the same helper.

7. **Companion plugins via `check-requirements.sh`.** The `SessionStart` requirement-check hook (added by `2026-05-12-user-scope-plugin-installation` — verified: scripts/check-requirements.sh and the RFC at docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L213-L420) probes for `github@claude-plugins-official`, `context7@claude-plugins-official`, and `code-review@claude-plugins-official`. With feature toggles, the check is feature-aware: when `refactor` is disabled, the missing `code-review@claude-plugins-official` warning is suppressed (the only reason that plugin matters is `/refactor`'s pre-pass — verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L142). When `rfc-workflow` is disabled, the `github@claude-plugins-official` warning is still emitted (other workflows benefit from it). The mapping is encoded in `feature-groups.json` (the `companion_plugins` field per group); `scripts/check-requirements.sh` reads the file and applies the suppression.

**Alternative rejected — purely manifest-based suppression with no in-skill probe.** Approach: rely entirely on `/sync` to delete or hide disabled skills (e.g., by writing a project-level skill at `.claude/skills/<skill-name>/SKILL.md` that overrides the plugin's). This was rejected because (a) project-level skills and plugin-level skills live in different namespaces (project skills are invoked unprefixed; plugin skills are `bytewyrd:<name>`), so a project-level override does not actually shadow the plugin's `bytewyrd:rfc-new` invocation; (b) writing a stub SKILL.md file to a project's `.claude/skills/` directory is intrusive and surprising to consumers who do not expect `/sync` to manage `.claude/skills/`; (c) the consumer-facing slash-command list always shows the plugin's `/bytewyrd:rfc-new` regardless of what is in `.claude/skills/` — Claude Code's plugin loader does not consult project files when deciding which plugin skills to register (Exa: https://code.claude.com/docs/en/plugins-reference). The in-skill probe accepts that the skill remains *invocable* (the user can type `/bytewyrd:rfc-new` and see the disabled message) but ensures it is *behaviorally inert*. This is the honest enforcement Claude Code's current model allows.

**Alternative rejected — `disable-model-invocation: true` on optional skills.** This frontmatter setting (verified: Exa: https://docs.anthropic.com/en/docs/claude-code/skills) prevents Claude from auto-invoking a skill but still lets the user run `/name`. It is a plugin-author-time switch baked into the SKILL.md file itself — there is no consumer-side toggle. Setting `disable-model-invocation: true` unconditionally on every optional skill would (a) prevent Claude from suggesting RFC creation when the user is about to design a feature, even in projects where the user actually wants RFC discipline, and (b) silently degrade the auto-discovery affordances the skills were designed for. The frontmatter is the wrong layer for a consumer-controlled toggle.

**Alternative rejected — split the plugin into multiple plugins (one per feature group), distributed from the same marketplace.** Considered seriously. Rejected because of three concrete Claude Code constraints documented above: (i) cross-skill namespace dependencies — every `bytewyrd:<skill>` reference would need to change to `bytewyrd-<group>:<skill>` or some marketplace-resolved identifier, and there is no documented mechanism for cross-plugin skill invocation that preserves the current ergonomic syntax (Exa: https://code.claude.com/docs/en/plugins-reference); (ii) `marketplace.json plugins[].skills` filter is documented as a filter but bugs #21148 and #53426 show it is silently ignored when plugins share a source root (Exa: https://github.com/anthropics/claude-code/issues/21148, https://github.com/anthropics/claude-code/issues/53426); (iii) `git-subdir` source type, which would let sub-plugins live in subdirectories of one repo, is also bugged (Exa: https://github.com/anthropics/claude-code/issues/26357, https://github.com/anthropics/claude-code/issues/37266 — "git-subdir rejected by schema validator" and "Plugin source path field ignored for GitHub sources"). The multi-plugin path is structurally elegant but rests on Claude Code primitives that do not currently work reliably. Toggling within a single plugin sidesteps all three. The door stays open: a future RFC can revisit multi-plugin distribution once the upstream issues close.

### Decision 3 — State storage and lifecycle

**Recommendation: `.bytewyrd/features.json`, JSON object, no schema versioning, replaced wholesale on each `/sync` re-toggle.**

**File location.** `.bytewyrd/features.json` lives next to `.bytewyrd/.bootstrap-versions.json` (relocated to `.bytewyrd/` by `2026-05-14-sync-per-file-extension-strategies` — verified: docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md item 9 of "Exact manifest changes"). Same directory, same gitignore carve-out pattern: ignore `.bytewyrd/*` then negate-ignore `.bytewyrd/.bootstrap-versions.json` and `.bytewyrd/features.json` so both are tracked in git. The choice to commit the file (rather than gitignore it) is deliberate: feature-toggle choices are team decisions, not personal preferences, so they should travel with the repo.

**File format.** A minimal JSON object whose keys are feature group identifiers and whose values are booleans:

```json
{
  "rfc-workflow": true,
  "refactor": true,
  "best-practices": true,
  "docs-review": false
}
```

The file lists exactly the keys defined in `feature-groups.json` at the time `/sync` last ran. Unknown keys in `features.json` (e.g., a future group the plugin no longer defines, or a typo) are surfaced as a one-line warning in `/sync`'s Step 8 report; they are not deleted automatically — the user has to remove them. Missing keys (a group defined in the manifest but absent from `features.json`) are filled in with `false` during the `/sync` toggle prompt (Decision 4) or with `true` if the user accepts the recommended default for the group.

**No schema version field.** The file's structure is one JSON object, flat, boolean values only. A future schema change (e.g., adding `null` for "not yet decided" or per-group sub-options) is handled by re-reading the file with defensive defaults — any feature group missing or with a non-boolean value is treated as disabled (with a warning). Forward-compatibility comes from the smallness of the schema, not from explicit versioning.

**Read protocol.** Every consumer (the in-skill probe helper, `/sync`, `check-requirements.sh`) reads the file with the same defensive pattern: if the file does not exist, treat every group as disabled and surface a one-line "no .bytewyrd/features.json found — run /sync to initialize" message in the first-line message. The probe helper short-circuits the same way for "missing file" as for "feature disabled" — the practical effect on a fresh clone before `/sync` has run is that the optional skills exit cleanly with an instructive message until the user runs `/sync`.

**Write protocol.** Only `/sync` writes to `.bytewyrd/features.json`. The write is atomic: render the new content to `.bytewyrd/features.json.tmp`, validate the JSON, then rename to `.bytewyrd/features.json`. This avoids leaving the file in a partial state if `/sync` is interrupted.

**Alternative rejected — store toggle state inside `.claude/settings.json`.** The settings file already carries `enabledPlugins`; adding `bytewyrdFeatures` next to it was considered. Rejected because (a) `.claude/settings.json` is the per-developer settings file in many workflows — committing or not committing it varies by team, and toggle state needs to be team-level; (b) the plugin's `/sync` already treats `.claude/settings.json` as a `structured`-strategy artifact with explicit owned paths (verified: .claude-plugin/bootstrap-manifest.json:L16-L33), and adding a new owned path would require a manifest version bump for every consumer; (c) keeping plugin runtime state isolated under `.bytewyrd/` (per the precedent of the relocated sidecar) gives the plugin a clean namespace for any future state files without negotiating with Claude Code's settings schema.

**Alternative rejected — pure env-var driven toggles (e.g., `BYTEWYRD_FEATURES=rfc-workflow,refactor`).** Considered. Rejected because shell environment is per-developer-per-shell and does not travel with the repo. A teammate cloning the project sees no record of which features the team chose. Env vars are a fine *override* layer (a developer could set `BYTEWYRD_FEATURES_OVERRIDE=rfc-workflow=false` to disable a feature locally without committing), but not a primary storage location. This RFC does not add the override mechanism (out of scope); it is a natural future addition if real-world use shows demand.

### Decision 4 — `/sync` interaction model

**Recommendation: feature-toggle prompt fires when `.bytewyrd/features.json` is absent or when `feature-groups.json` introduces new groups since the last `/sync` run; otherwise silent re-apply.**

**First-run prompt (`.bytewyrd/features.json` absent).** `/sync` adds a new step (Step 2.5, between identity gathering and component detection — see Implementation spec below) that presents one AskUserQuestion containing one question per feature group defined in `feature-groups.json`:

> "Enable feature group `rfc-workflow`? (Adds /rfc-new, /rfc-approve, /rfc-implement, /rfc-drop, /rfc-braindump, /rfc-read-feedback, /rfc-summary, /rfc-consensus-review, /rfc-update slash commands, the rfc-architect agent, and the RFC process documentation in docs/rfc-process.md and CLAUDE.md's ## RFC Process section.)"
>
> Options: `Enable (recommended)` / `Disable`

The recommended default for each group is `true` for `rfc-workflow`, `refactor`, `best-practices`, and `docs-review` — the plugin's opinionated posture is that every team benefits from each workflow, and the toggle exists for teams that explicitly want out, not for teams discovering the plugin. Each question is one AskUserQuestion entry; the single AskUserQuestion call contains all four (one per feature group), so the user makes the choice in one screen.

**Re-run with new feature groups (manifest evolved since last `/sync`).** When `feature-groups.json` defines a group identifier that `.bytewyrd/features.json` does not list, `/sync` presents an AskUserQuestion only for the new group(s) — pre-existing toggles are preserved verbatim. This handles the future case where a new group is added (e.g., a hypothetical `release-management` group) without forcing the user to re-answer every prior toggle. The added question's text mirrors the first-run prompt; the recommended default is the same as for first-run (`Enable`).

**Re-run with no new feature groups (steady state).** Silent. `/sync` reads `.bytewyrd/features.json` once, applies all toggle-aware behaviors (manifest artifact filtering, `CLAUDE.md` section rendering, `bootstrap` initial-write filtering), and proceeds. No prompt.

**Explicit re-toggle.** A user who wants to change a prior choice can either (a) edit `.bytewyrd/features.json` directly and re-run `/sync` (the file write triggers re-classification of feature-coupled manifest artifacts, which surface as additions or removals in the diff summary), or (b) run `/sync --reconfigure-features` (a new flag this RFC adds) which forces the first-run-style prompt for every group regardless of current state. The flag is the documented path for users who want a guided re-toggle without hand-editing JSON.

**Toggle changes and existing project files.** When `/sync` detects that a feature group has flipped from disabled to enabled, it surfaces the now-relevant manifest artifacts (e.g., `docs/rfc-process.md`) as `add` classifications in the Step 4 summary; the user confirms in the Step 4a batch confirmation as for any other addition. When a group flips from enabled to disabled, `/sync` does **not** delete the artifacts the consumer already has (a project with an existing `docs/rfc-process.md` and 30 in-flight RFCs does not lose them just because they toggled `rfc-workflow=false`); instead, it surfaces a one-line note in Step 8: `docs/rfc-process.md exists but rfc-workflow is now disabled — file preserved; /sync will not update it while disabled.` This is the safe default: turning a feature off should not destroy content the team built using it.

**`CLAUDE.md` section transitions.** The exception to "do not delete" is `CLAUDE.md` sections. `CLAUDE.md` uses `section` extension strategy (verified: .claude-plugin/bootstrap-manifest.json:L84-L96), which means the plugin owns specific section bodies regardless of file age. When a feature group flips off, the corresponding owned section *is* removed from the rendered `CLAUDE.md` (the section-feature-group filter described in Decision 2 is the same filter on every render). This is consistent with how the `section` strategy already works — the plugin authoritatively shapes the listed sections — and is the right behavior because the section content is workflow guidance to the agent, not project content the user built up. The plugin's section content is omitted; if the user adds custom content to that section before the toggle flip, it is preserved (the section's body is removed *of plugin-owned content*; any user-added content the section accumulated remains, per the existing `section` strategy semantics — verified: skills/sync/SKILL.md:L338).

**Alternative rejected — fire the prompt on every `/sync` re-run.** Considered. Rejected: a user who has already answered the question has no reason to be re-asked. The pattern matches Step 2's identity gathering (which is also silent when the brief is already complete — verified: skills/sync/SKILL.md:L26-L29).

**Alternative rejected — read toggles from an env var or a CLI flag at `/sync` invocation time.** Considered. Rejected for the same reasons as Decision 3's env-var rejection — toggle state should be persisted and visible in the repo, not configured ad-hoc per-invocation.

## Drawbacks

- **The in-skill probe runs on every invocation of every optional skill.** The probe is a bash call to `scripts/feature-toggle.sh` that reads `.bytewyrd/features.json` (single open + read + `jq` parse) and exits. Worst-case latency on a warm filesystem is single-digit milliseconds. The probe runs in the skill's bash environment, which Claude Code's skill executor invokes anyway for any bash inside a skill — there is no added cold-start cost. The pattern is identical to the existing `scripts/tool-probe.sh` calls already in `best-practices-extract`, `refactor`, and `rfc-implement` (verified: skills/best-practices-extract/SKILL.md:L12, skills/refactor/SKILL.md:L13, scripts/tool-probe.sh:L1-L102), and no perf complaint has surfaced about those. **Mitigation:** none required given the precedent.

- **Optional skills remain discoverable via `/`-autocomplete and `@`-autocomplete even when disabled.** Per the Claude Code plugin reference (Exa: https://code.claude.com/docs/en/plugins-reference), a plugin's skills are always registered when the plugin is enabled; the consumer cannot un-register individual skills from the registration list. A user in a `rfc-workflow=false` project who types `/rfc` in the slash-command picker still sees `/bytewyrd:rfc-new`, `/bytewyrd:rfc-approve`, etc. listed. Invoking them produces the one-line "feature disabled" message and exits cleanly. **Mitigation:** the message names the toggle and the fix (`/sync --reconfigure-features` or edit `.bytewyrd/features.json`) so the user can act on it in one step. Future Claude Code releases may add a per-project skill-suppression mechanism (a documented feature gap per the open issue at Exa: https://github.com/anthropics/claude-code/issues/53426); when that lands, this RFC's enforcement can fold into the new mechanism without changing the toggle state file.

- **A user typing `@rfc-architect` directly in a `rfc-workflow=false` project still spawns the agent.** The agent's prompt body opens with a defensive check (described in Decision 2.2) that surfaces the same "disabled" message and exits, but this happens after the agent has already been spawned (token cost for the system prompt and initial response). **Mitigation:** the agent's opening message is short (≤2 sentences) and the agent exits before any tool calls; token cost is bounded at ~500 tokens for the worst case. The expected frequency of direct `@`-invocation of a feature-disabled agent is very low — users who disable a feature typically also stop typing its agent's name.

- **`CLAUDE.md` re-renders when a feature toggle flips.** A project that toggles `rfc-workflow` off and re-runs `/sync` sees `## RFC Process` removed from `CLAUDE.md`. This is by design (Decision 4) but means the rendered file diff in the `/sync` Step 4 summary is larger than a typical no-op run. **Mitigation:** the Step 4 summary classifies this as `fast_forward` (per the existing section-strategy semantics), and the user is asked once per `/sync` whether to apply fast-forwards (per skills/sync/SKILL.md:L383-L390 — verified). The user has the option to skip the fast-forward and keep their existing `CLAUDE.md` content if they prefer to defer.

- **`bootstrap` files written before a toggle flip keep references to disabled features.** A project that creates `docs/CONTRIBUTING.md` with `rfc-workflow=true`, then flips `rfc-workflow=false`, keeps a `CONTRIBUTING.md` that references `/rfc-new`. This is a consequence of `bootstrap` semantics (the plugin does not re-touch the file after creation — verified: docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md "Strategy 3: `bootstrap`"). **Mitigation:** the Step 8 report lists files that reference disabled features as a one-line warning: `docs/CONTRIBUTING.md may reference disabled feature 'rfc-workflow' — review and edit manually if needed.` The detection is a simple grep against a per-feature-group list of skill identifiers and section headings (e.g., for `rfc-workflow`: `/rfc-new`, `/rfc-approve`, `## RFC Process`). The grep runs in `/sync` Step 8.

- **The plugin author has to keep `feature-groups.json` in sync with the actual skill/agent files.** A new optional skill added under `skills/<name>/` must be added to a `feature-groups.json` group, or it defaults to core (the implicit fallback for un-claimed components). A new optional agent must similarly be claimed by a group, or it defaults to core. **Mitigation:** the pre-commit hook (`.claude-plugin/hooks/pre-commit/manifest-check.sh` — verified to exist) is extended to validate `feature-groups.json` against the on-disk skill and agent inventories: every skill directory under `skills/` and every agent file under `agents/` must either be claimed by a `feature-groups.json` group's `skills` or `agents` array, or appear in a new `core_skills` / `core_agents` array in `feature-groups.json` that explicitly enumerates the core set. The hook fails the commit when an un-claimed component exists, surfacing the omission before it ships to consumers. The validation adds an extra ~15 lines to the existing pre-commit script.

- **Consumers who do not re-run `/sync` after upgrading the plugin to the version that introduces toggles see no `.bytewyrd/features.json` and therefore every optional skill exits with the "disabled" message.** This is a real one-time regression for active users on plugin upgrade. **Mitigation:** the upgrade ships with a one-paragraph migration note in `README.md` ("After upgrading to plugin version 0.3.0, run `/sync` once to initialize feature toggles — the prompt defaults every group to enabled, preserving the pre-RFC behavior") and the in-skill probe's "disabled" message includes the exact remediation (`run /sync to initialize`). A user who hits the message in a freshly upgraded project follows one instruction and is done.

- **The `check-requirements.sh` integration depends on the user-scope-plugin-installation RFC having shipped, since that RFC introduces the script.** **Mitigation:** `2026-05-12-user-scope-plugin-installation` is Done (status verified by reading the RFC frontmatter at docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L5). This RFC depends on it but the dependency is already resolved.

- **The plugin's own checkout (which dogfoods the plugin against itself) does not have a `.bytewyrd/features.json` today.** When this RFC's implementation lands in the plugin's own repo, the implementer needs to write a `.bytewyrd/features.json` that enables every group, otherwise the plugin developers will see "disabled" messages when invoking their own skills. **Mitigation:** the implementation includes the step to create the plugin's own `.bytewyrd/features.json` with every group set to `true`, and commits it to the repo. The plugin's checkout is the canonical dogfood — it must have all features enabled.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `feature-groups.json` | Plugin-root manifest declaring the four optional feature groups and the core component lists. Source of truth for which skills, agents, manifest artifacts, `CLAUDE.md` sections, and companion plugins belong to each group |
| Create | `scripts/feature-toggle.sh` | Bash helper invoked by the in-skill probe. Reads `.bytewyrd/features.json` from `$CLAUDE_PROJECT_DIR` and writes a single-line JSON result on stdout. Exit 0 if the requested group is enabled; exit 1 if disabled or missing |
| Create | `scripts/feature-groups-list.sh` | Bash helper that reads `feature-groups.json` at the plugin root and prints the list of feature group identifiers with their descriptions, recommended defaults, and core/optional flags. Used by `/sync` to drive the toggle prompt |
| Create | `.bytewyrd/features.json` | The plugin's own dogfood toggle file — every group set to `true` |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Add `feature_group` field (default `null` = core) per artifact. Set `bytewyrd/docs/rfc-process.md@v1` to `feature_group: "rfc-workflow"`. Add `section_feature_groups` map under the `bytewyrd/CLAUDE.md@v1` entry pairing `## RFC Process` to `rfc-workflow` and leaving the other nine owned sections as core (`null`) |
| Modify | `.claude-plugin/scripts/build-manifest.sh` | Preserve `feature_group` and `section_feature_groups` fields when regenerating the manifest. Currently the script preserves `upstream_key`, `source`, `target`, `extension_strategy`, `owned_sections`, `owned_paths`, `templated`, `template_inputs` (verified: .claude-plugin/scripts/build-manifest.sh:L24-L27); extend the preservation list to include the two new fields |
| Modify | `.claude-plugin/hooks/pre-commit/manifest-check.sh` | Extend to also run `feature-groups-coverage.sh --check` (new helper, see below). The hook currently runs only `build-manifest.sh --check` (verified: .claude-plugin/hooks/pre-commit/manifest-check.sh exists per docs/CLAUDE.md L160 reference; file is 183 bytes) — add the coverage check as a second invocation |
| Create | `.claude-plugin/scripts/feature-groups-coverage.sh` | Validates `feature-groups.json` against the on-disk inventory: every directory under `skills/` and every `.md` file under `agents/` is claimed by exactly one group (core or one of the optional groups). `--check` mode exits non-zero on miss; default mode prints the report |
| Modify | `skills/rfc-new/SKILL.md` | Add the in-skill feature probe as the first executable section after the frontmatter (before any other content). Same pattern as `skills/refactor/SKILL.md`'s existing `## Requirement check` section, using `feature-toggle.sh rfc-workflow` |
| Modify | `skills/rfc-approve/SKILL.md` | Add the same in-skill probe (`feature-toggle.sh rfc-workflow`) |
| Modify | `skills/rfc-implement/SKILL.md` | Add the same in-skill probe (`feature-toggle.sh rfc-workflow`) at the top, before the existing `## Requirement check` block |
| Modify | `skills/rfc-drop/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/rfc-braindump/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/rfc-read-feedback/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/rfc-summary/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/rfc-consensus-review/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/rfc-update/SKILL.md` | Add `feature-toggle.sh rfc-workflow` probe |
| Modify | `skills/refactor/SKILL.md` | Add `feature-toggle.sh refactor` probe at the top, before the existing `## Requirement check` block |
| Modify | `skills/best-practices-extract/SKILL.md` | Add `feature-toggle.sh best-practices` probe at the top, before the existing `## Requirement check` block |
| Modify | `skills/best-practices-record/SKILL.md` | Add `feature-toggle.sh best-practices` probe |
| Modify | `skills/docs-review/SKILL.md` | Add `feature-toggle.sh docs-review` probe |
| Modify | `agents/rfc-architect.md` | Add a guarded one-paragraph opening: read `.bytewyrd/features.json` from the project; if `rfc-workflow` is not `true`, the agent's first response is the standard disabled message and the agent exits |
| Modify | `agents/refactoring-specialist.md` | Add the same guarded opening for `refactor` |
| Modify | `agents/docs-agent.md` | Add the same guarded opening for `docs-review` |
| Modify | `skills/sync/SKILL.md` | Add **Step 2.5** (feature-toggle prompt) between the existing Step 2 (project identity) and Step 3 (component detection). Modify **Step 4** (compute diff) to filter manifest artifacts by `feature_group`. Modify **Step 5** (apply changes) to render `CLAUDE.md` with section-level feature filtering. Add `--reconfigure-features` flag handling. Modify **Step 8** (report) to surface toggle state, new groups, and the warning about `bootstrap` files referencing disabled features |
| Modify | `scripts/check-requirements.sh` | Read `.bytewyrd/features.json` near the top; map each REQUIRED_PLUGINS entry to its owning feature group via `feature-groups.json`; suppress the warning for a plugin whose feature group is disabled. Default to "all features enabled" if `.bytewyrd/features.json` is absent (preserves pre-RFC behavior on legacy projects) |
| Modify | `.claude-plugin/scripts/templates/.gitignore.tpl` | Add a negation entry under the `# bytewyrd:base` tagged block: `!.bytewyrd/features.json`. The block currently includes `.worktrees/`, `.claude/settings.local.json`, `.bytewyrd/*`, `!.bytewyrd/.bootstrap-versions.json` (the latter two from the per-file-extension-strategies RFC). Add the new line directly after the existing `!.bytewyrd/.bootstrap-versions.json` line |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl` | No content change to the template body itself. The template is unchanged; what changes is `/sync`'s render-time omission of feature-disabled sections per the manifest's `section_feature_groups` map. The template still ships all ten owned sections in source; `/sync` omits the ones whose group is disabled in the target project |
| Modify | `docs/ARCHITECTURE.md` | Add a new component entry under `## Components` documenting feature groups: where the manifest lives, how toggle state is stored, how skills enforce toggles at runtime |
| Modify | `docs/rfc-process.md` | No content change. The file is itself feature-coupled (only meaningful when `rfc-workflow` is enabled), but the `## Project Extensions` section in the source-of-truth (`rfc-process.md` at the plugin root) is unchanged. The feature-coupling lives in the manifest entry, not the file content |
| Modify | `README.md` | Add a one-paragraph "Feature toggles" subsection under "Installation" describing the toggle file, the four groups, the recommended defaults, and the `--reconfigure-features` flag. Add a one-line migration note for existing-project users explaining that the first `/sync` after upgrading initializes `.bytewyrd/features.json` with every group enabled |

No changes to `agents/` other than the three guarded openings noted above. No changes to the `.claude-plugin/marketplace.json` or `.claude-plugin/plugin.json` (toggles are runtime/sync-time, not packaging-time). No new MCP servers, no LSP servers.

### Steps

#### Step 1 — Create `feature-groups.json` at the plugin root

Write `/feature-groups.json` (peer of `.claude-plugin/`, `agents/`, `skills/`, `hooks/`, `scripts/`) with this exact content:

```json
{
  "core": {
    "description": "Always installed. Cannot be disabled.",
    "skills": [
      "sync",
      "git-branch-cleanup"
    ],
    "agents": [
      "feature-engineer",
      "code-reviewer",
      "debugger",
      "documentation-writer",
      "claude-agent-author",
      "ai-engineer",
      "api-designer",
      "backend-developer",
      "build-engineer",
      "cli-developer",
      "cloud-architect",
      "database-administrator",
      "database-optimizer",
      "deployment-engineer",
      "devops-engineer",
      "devops-incident-responder",
      "frontend-developer",
      "fullstack-developer",
      "golang-pro",
      "graphql-architect",
      "kubernetes-specialist",
      "llm-architect",
      "mcp-developer",
      "microservices-architect",
      "nextjs-developer",
      "penetration-tester",
      "performance-engineer",
      "platform-engineer",
      "postgres-pro",
      "prompt-engineer",
      "python-pro",
      "qa-expert",
      "rails-expert",
      "react-specialist",
      "rust-engineer",
      "security-engineer",
      "sql-pro",
      "sre-engineer",
      "terraform-engineer",
      "terragrunt-expert",
      "test-automator",
      "typescript-pro",
      "ui-designer",
      "ux-design-architect",
      "websocket-engineer"
    ]
  },
  "optional": {
    "rfc-workflow": {
      "description": "RFC-driven design and implementation workflow. Adds /rfc-* slash commands, the rfc-architect agent, the docs/rfc-process.md file, and the ## RFC Process section of CLAUDE.md.",
      "recommended_default": true,
      "skills": [
        "rfc-new",
        "rfc-approve",
        "rfc-implement",
        "rfc-drop",
        "rfc-braindump",
        "rfc-read-feedback",
        "rfc-summary",
        "rfc-consensus-review",
        "rfc-update"
      ],
      "agents": [
        "rfc-architect"
      ],
      "manifest_artifacts": [
        "bytewyrd/docs/rfc-process.md@v1"
      ],
      "claude_md_sections": [
        "## RFC Process"
      ],
      "companion_plugins": []
    },
    "refactor": {
      "description": "Deliberate refactoring pass with the /refactor skill and refactoring-specialist agent. Optional code-review@claude-plugins-official pre-pass.",
      "recommended_default": true,
      "skills": [
        "refactor"
      ],
      "agents": [
        "refactoring-specialist"
      ],
      "manifest_artifacts": [],
      "claude_md_sections": [],
      "companion_plugins": [
        "code-review@claude-plugins-official"
      ]
    },
    "best-practices": {
      "description": "Capture session learnings into docs/BEST_PRACTICES.md and optionally promote to the cross-project pool. Adds /best-practices-extract and /best-practices-record.",
      "recommended_default": true,
      "skills": [
        "best-practices-extract",
        "best-practices-record"
      ],
      "agents": [],
      "manifest_artifacts": [],
      "claude_md_sections": [],
      "companion_plugins": []
    },
    "docs-review": {
      "description": "Audit docs/guide/** for drift and coverage gaps via the /docs-review skill and docs-agent.",
      "recommended_default": true,
      "skills": [
        "docs-review"
      ],
      "agents": [
        "docs-agent"
      ],
      "manifest_artifacts": [],
      "claude_md_sections": [],
      "companion_plugins": []
    }
  }
}
```

Verify the file parses as valid JSON:

```bash
python3 -c 'import json; json.load(open("feature-groups.json"))' && echo OK
```

Expected output:
```
OK
```

#### Step 2 — Create `scripts/feature-toggle.sh`

Write `/scripts/feature-toggle.sh` with mode `0755`. Content:

```bash
#!/usr/bin/env bash
# Bytewyrd plugin: per-skill feature-toggle probe.
# Args:
#   $1  Required. Feature group identifier (e.g., "rfc-workflow", "refactor",
#       "best-practices", "docs-review").
#
# Reads CLAUDE_PROJECT_DIR/.bytewyrd/features.json. If the file is absent,
# every group is treated as disabled (the consumer has not run /sync yet).
# If the file is present and the group's value is exactly the JSON boolean
# `true`, the group is enabled (exit 0). Any other value (false, null, missing
# key, non-boolean) is treated as disabled (exit 1).
#
# Output:
#   stdout: single-line JSON.
#     enabled (exit 0):
#       {"result":"enabled","group":"<name>"}
#     disabled (exit 1):
#       {"result":"disabled","group":"<name>","message":"/<caller-script-name> is disabled in this project — feature group \"<name>\" is off. To enable, run /sync --reconfigure-features and select the group, or edit .bytewyrd/features.json directly."}
#     missing-file (exit 1):
#       {"result":"missing-file","group":"<name>","message":"/<caller-script-name> is disabled in this project — .bytewyrd/features.json is absent. Run /sync to initialize feature toggles."}
#     usage-error (exit 2):
#       {"error":"usage: feature-toggle.sh <group-identifier>"}
#
# Exit codes:
#   0  Feature is enabled.
#   1  Feature is disabled or .bytewyrd/features.json is missing.
#   2  Usage error.

set -uo pipefail

if [ "${1:-}" = "" ]; then
  printf '{"error":"usage: feature-toggle.sh <group-identifier>"}\n'
  exit 2
fi

group="$1"
proj_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
features_file="$proj_dir/.bytewyrd/features.json"

# Derive the caller's display name. Callers are skills whose body invokes this
# script; the caller name in the message is the basename of the calling script
# without the .sh suffix. Falls back to "this skill" if unavailable.
caller="${BYTEWYRD_FEATURE_PROBE_CALLER:-this skill}"

if [ ! -f "$features_file" ]; then
  printf '{"result":"missing-file","group":"%s","message":"%s is disabled in this project — .bytewyrd/features.json is absent. Run /sync to initialize feature toggles."}\n' \
    "$group" "$caller"
  exit 1
fi

# Parse the boolean for the requested group. jq returns "true", "false",
# "null", or empty for missing key. Any value other than literal "true" is
# disabled.
enabled=$(jq -r --arg g "$group" '.[$g] // false | tostring' "$features_file" 2>/dev/null)

if [ "$enabled" = "true" ]; then
  printf '{"result":"enabled","group":"%s"}\n' "$group"
  exit 0
fi

printf '{"result":"disabled","group":"%s","message":"%s is disabled in this project — feature group \\"%s\\" is off. To enable, run /sync --reconfigure-features and select the group, or edit .bytewyrd/features.json directly."}\n' \
  "$group" "$caller" "$group"
exit 1
```

Make the script executable:

```bash
chmod +x scripts/feature-toggle.sh
```

Verification from inside a project where `.bytewyrd/features.json` exists with `{"rfc-workflow": true}`:

```bash
CLAUDE_PROJECT_DIR=$(pwd) bash scripts/feature-toggle.sh rfc-workflow
echo "exit=$?"
```

Expected output:
```
{"result":"enabled","group":"rfc-workflow"}
exit=0
```

Verification with the group disabled:

```bash
echo '{"rfc-workflow": false}' > /tmp/features.json
CLAUDE_PROJECT_DIR=$(dirname /tmp/features.json) BYTEWYRD_FEATURE_PROBE_CALLER=/rfc-new bash -c 'mkdir -p .bytewyrd && cp /tmp/features.json .bytewyrd/features.json && bash scripts/feature-toggle.sh rfc-workflow'
echo "exit=$?"
```

Expected output (the leading JSON line, then the exit code on its own line):
```
{"result":"disabled","group":"rfc-workflow","message":"/rfc-new is disabled in this project — feature group \"rfc-workflow\" is off. To enable, run /sync --reconfigure-features and select the group, or edit .bytewyrd/features.json directly."}
exit=1
```

Verification with the file absent:

```bash
CLAUDE_PROJECT_DIR=/tmp/no-such-dir BYTEWYRD_FEATURE_PROBE_CALLER=/rfc-new bash scripts/feature-toggle.sh rfc-workflow
echo "exit=$?"
```

Expected output:
```
{"result":"missing-file","group":"rfc-workflow","message":"/rfc-new is disabled in this project — .bytewyrd/features.json is absent. Run /sync to initialize feature toggles."}
exit=1
```

#### Step 3 — Create `scripts/feature-groups-list.sh`

Write `/scripts/feature-groups-list.sh` with mode `0755`. Content:

```bash
#!/usr/bin/env bash
# Bytewyrd plugin: list the feature groups defined in feature-groups.json.
# Used by /sync to drive the toggle prompt and by check-requirements.sh to
# look up companion-plugin → group mappings.
#
# Args:
#   $1  Optional mode. "summary" (default) prints id + description + default.
#                      "json" prints the full optional-groups object as-is.
#                      "companion-map" prints lines "<plugin-id>\t<group-id>"
#                      for every companion plugin claimed by a group.
#
# Output (summary mode, one line per group):
#   <id>\t<recommended-default>\t<description>
#
# Reads $CLAUDE_PLUGIN_ROOT/feature-groups.json. Falls back to
# $HOME/.claude/plugins/cache/bytewyrd/bytewyrd/feature-groups.json, then
# $HOME/.claude/plugins/cache/*/bytewyrd/feature-groups.json — the same
# three-tier resolver that hooks/hooks.json uses for check-requirements.sh
# (verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md
# Step 2 / hooks/hooks.json:L29-L34).

set -uo pipefail

mode="${1:-summary}"

# Resolve plugin root.
script="${CLAUDE_PLUGIN_ROOT:-}/feature-groups.json"
if [ ! -f "$script" ]; then
  script="$HOME/.claude/plugins/cache/bytewyrd/bytewyrd/feature-groups.json"
fi
if [ ! -f "$script" ]; then
  script=$(ls -1 "$HOME"/.claude/plugins/cache/*/bytewyrd/feature-groups.json 2>/dev/null | head -n1)
fi
if [ -z "$script" ] || [ ! -f "$script" ]; then
  echo "bytewyrd: feature-groups.json not found in plugin root or cache" >&2
  exit 2
fi

case "$mode" in
  summary)
    jq -r '.optional | to_entries[] | "\(.key)\t\(.value.recommended_default)\t\(.value.description)"' "$script"
    ;;
  json)
    jq '.optional' "$script"
    ;;
  companion-map)
    jq -r '.optional | to_entries[] | .key as $g | .value.companion_plugins[]? | "\(.)\t\($g)"' "$script"
    ;;
  *)
    echo "usage: feature-groups-list.sh [summary|json|companion-map]" >&2
    exit 2
    ;;
esac
```

Verification:

```bash
CLAUDE_PLUGIN_ROOT=$(pwd) bash scripts/feature-groups-list.sh summary
```

Expected output (four lines, one per optional group, in source order):
```
rfc-workflow	true	RFC-driven design and implementation workflow. Adds /rfc-* slash commands, the rfc-architect agent, the docs/rfc-process.md file, and the ## RFC Process section of CLAUDE.md.
refactor	true	Deliberate refactoring pass with the /refactor skill and refactoring-specialist agent. Optional code-review@claude-plugins-official pre-pass.
best-practices	true	Capture session learnings into docs/BEST_PRACTICES.md and optionally promote to the cross-project pool. Adds /best-practices-extract and /best-practices-record.
docs-review	true	Audit docs/guide/** for drift and coverage gaps via the /docs-review skill and docs-agent.
```

Verification of companion-map mode:

```bash
CLAUDE_PLUGIN_ROOT=$(pwd) bash scripts/feature-groups-list.sh companion-map
```

Expected output (one line per companion plugin):
```
code-review@claude-plugins-official	refactor
```

#### Step 4 — Create the plugin's own `.bytewyrd/features.json`

Inside the plugin's checkout (so the plugin dogfoods itself with all features enabled), create `.bytewyrd/features.json`:

```bash
mkdir -p .bytewyrd
cat > .bytewyrd/features.json <<'EOF'
{
  "rfc-workflow": true,
  "refactor": true,
  "best-practices": true,
  "docs-review": true
}
EOF
```

Verification:

```bash
test -f .bytewyrd/features.json && jq -e '.["rfc-workflow"] == true and .refactor == true and .["best-practices"] == true and .["docs-review"] == true' .bytewyrd/features.json && echo OK
```

Expected output:
```
OK
```

#### Step 5 — Update `.claude-plugin/bootstrap-manifest.json`

Two changes:

**Change 5a — Add `feature_group: "rfc-workflow"` to the `bytewyrd/docs/rfc-process.md@v1` entry.**

The current entry is (verified: .claude-plugin/bootstrap-manifest.json:L179-L187):

```json
{
  "upstream_key": "bytewyrd/docs/rfc-process.md@v1",
  "source": "rfc-process.md",
  "target": "docs/rfc-process.md",
  "sha256": "8dd941ccacb352502295b58c8de67682b4e90d612d62107e128f738dec61e8e3",
  "extension_strategy": "region",
  "region_end_marker": "<!-- END_UPSTREAM_CONTENT -->",
  "templated": false
}
```

Replace with:

```json
{
  "upstream_key": "bytewyrd/docs/rfc-process.md@v1",
  "source": "rfc-process.md",
  "target": "docs/rfc-process.md",
  "sha256": "8dd941ccacb352502295b58c8de67682b4e90d612d62107e128f738dec61e8e3",
  "extension_strategy": "region",
  "region_end_marker": "<!-- END_UPSTREAM_CONTENT -->",
  "templated": false,
  "feature_group": "rfc-workflow"
}
```

(The `sha256` value is the current hash from the verified manifest; `build-manifest.sh` recomputes it on the next regeneration, so the value above is what the file should hold immediately after the edit and will be replaced by the script if the source has changed.)

**Change 5b — Add `section_feature_groups` to the `bytewyrd/CLAUDE.md@v1` entry.**

The current entry is (verified: .claude-plugin/bootstrap-manifest.json:L80-L106):

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "source": ".claude-plugin/scripts/templates/CLAUDE.md.tpl",
  "target": "CLAUDE.md",
  "template_sha": "0993a89ec9e87cfa7d01eafd93b2e307eaf16d30ab8cb085e2351e1fe0614f67",
  "extension_strategy": "section",
  "owned_sections": [
    "## Toolchain",
    "## File structure",
    "## Agent delegation",
    "## Tool Usage",
    "## RFC Process",
    "## Evidence-Based Development",
    "## Model Usage Optimization",
    "## Claude Code Sandbox — Container Tool Compatibility",
    "## Security",
    "## Conventions"
  ],
  "templated": true,
  "template_inputs": [
    "project_name",
    "description",
    "project_slug",
    "languages",
    "installed_plugins",
    "component_roots"
  ]
}
```

Replace with (adds the `section_feature_groups` field after `owned_sections`):

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "source": ".claude-plugin/scripts/templates/CLAUDE.md.tpl",
  "target": "CLAUDE.md",
  "template_sha": "0993a89ec9e87cfa7d01eafd93b2e307eaf16d30ab8cb085e2351e1fe0614f67",
  "extension_strategy": "section",
  "owned_sections": [
    "## Toolchain",
    "## File structure",
    "## Agent delegation",
    "## Tool Usage",
    "## RFC Process",
    "## Evidence-Based Development",
    "## Model Usage Optimization",
    "## Claude Code Sandbox — Container Tool Compatibility",
    "## Security",
    "## Conventions"
  ],
  "section_feature_groups": {
    "## Toolchain": null,
    "## File structure": null,
    "## Agent delegation": null,
    "## Tool Usage": null,
    "## RFC Process": "rfc-workflow",
    "## Evidence-Based Development": null,
    "## Model Usage Optimization": null,
    "## Claude Code Sandbox — Container Tool Compatibility": null,
    "## Security": null,
    "## Conventions": null
  },
  "templated": true,
  "template_inputs": [
    "project_name",
    "description",
    "project_slug",
    "languages",
    "installed_plugins",
    "component_roots"
  ]
}
```

`null` is the literal JSON null (not a string); it means "this section is core, always rendered."

Verification:

```bash
jq -e '.artifacts[] | select(.upstream_key == "bytewyrd/docs/rfc-process.md@v1") | .feature_group == "rfc-workflow"' .claude-plugin/bootstrap-manifest.json && echo OK
jq -e '.artifacts[] | select(.upstream_key == "bytewyrd/CLAUDE.md@v1") | .section_feature_groups["## RFC Process"] == "rfc-workflow" and (.section_feature_groups["## Tool Usage"] == null)' .claude-plugin/bootstrap-manifest.json && echo OK
```

Expected output (two lines):
```
OK
OK
```

#### Step 6 — Update `.claude-plugin/scripts/build-manifest.sh`

The current script preserves all artifact fields by reading each artifact as a JSON object and using `jq` to update the `sha256` or `template_sha` field (verified: .claude-plugin/scripts/build-manifest.sh:L28-L42). Because the per-artifact preservation is structural (it operates on each artifact JSON object and only mutates one field), the new `feature_group` and `section_feature_groups` fields are preserved without changes.

No code change is required for preservation. To make the contract explicit, add a comment block before the per-artifact loop. The current comment is at lines 22-26 (verified):

```bash
# Walk the existing manifest, recompute each artifact's sha256 from its source path.
# For templated artifacts (templated == true), the field name is template_sha;
# for non-templated artifacts, it is sha256. The script preserves all other fields
# (upstream_key, source, target, extension_strategy, owned_sections, owned_paths,
#  templated, template_inputs) from the existing manifest.
```

Replace with:

```bash
# Walk the existing manifest, recompute each artifact's sha256 from its source path.
# For templated artifacts (templated == true), the field name is template_sha;
# for non-templated artifacts, it is sha256. The script preserves all other fields
# (upstream_key, source, target, extension_strategy, owned_sections, owned_paths,
#  templated, template_inputs, feature_group, section_feature_groups,
#  region_end_marker) from the existing manifest.
```

This is a documentation-only change; the script's behavior is unchanged. Verification by running the script and confirming `feature_group` survives:

```bash
.claude-plugin/scripts/build-manifest.sh
jq -e '.artifacts[] | select(.upstream_key == "bytewyrd/docs/rfc-process.md@v1") | .feature_group == "rfc-workflow"' .claude-plugin/bootstrap-manifest.json && echo OK
```

Expected output:
```
Regenerated /home/divoxx/code/bytewyrd/claude-bytewyrd/.worktrees/rfc-modular-feature-toggles/.claude-plugin/bootstrap-manifest.json
OK
```

#### Step 7 — Create `.claude-plugin/scripts/feature-groups-coverage.sh`

Write the script with mode `0755`. Content:

```bash
#!/usr/bin/env bash
# Validate that every skill directory under skills/ and every agent .md file
# under agents/ is claimed by exactly one entry in feature-groups.json (either
# the core.skills/core.agents arrays or one of the optional.<group>.skills /
# optional.<group>.agents arrays).
#
# Args:
#   --check  Exit non-zero on any miss (used by the pre-commit hook).
#            Default: print the coverage report and exit 0.

set -euo pipefail

PLUGIN_ROOT="$(git rev-parse --show-toplevel)"
GROUPS="$PLUGIN_ROOT/feature-groups.json"

if [ ! -f "$GROUPS" ]; then
  echo "feature-groups.json not found at $GROUPS" >&2
  exit 2
fi

# Build the claimed-set from the manifest.
claimed_skills=$(jq -r '[.core.skills[]] + ([.optional | to_entries[] | .value.skills // []] | flatten) | sort | unique | .[]' "$GROUPS")
claimed_agents=$(jq -r '[.core.agents[]] + ([.optional | to_entries[] | .value.agents // []] | flatten) | sort | unique | .[]' "$GROUPS")

# Build the on-disk inventory.
disk_skills=$(find "$PLUGIN_ROOT/skills" -maxdepth 2 -name "SKILL.md" -exec dirname {} \; | xargs -n1 basename | sort | uniq)
disk_agents=$(find "$PLUGIN_ROOT/agents" -maxdepth 1 -name "*.md" -exec basename {} .md \; | sort | uniq)

# Compute missing-from-manifest (on-disk but not claimed).
skills_missing=$(comm -23 <(printf '%s\n' "$disk_skills") <(printf '%s\n' "$claimed_skills"))
agents_missing=$(comm -23 <(printf '%s\n' "$disk_agents") <(printf '%s\n' "$claimed_agents"))

# Compute over-claimed (in manifest but not on disk).
skills_overclaimed=$(comm -13 <(printf '%s\n' "$disk_skills") <(printf '%s\n' "$claimed_skills"))
agents_overclaimed=$(comm -13 <(printf '%s\n' "$disk_agents") <(printf '%s\n' "$claimed_agents"))

problems=0

if [ -n "$skills_missing" ]; then
  echo "Skills on disk but not claimed by any feature group:"
  printf '  - %s\n' $skills_missing
  problems=$((problems + 1))
fi
if [ -n "$agents_missing" ]; then
  echo "Agents on disk but not claimed by any feature group:"
  printf '  - %s\n' $agents_missing
  problems=$((problems + 1))
fi
if [ -n "$skills_overclaimed" ]; then
  echo "Skills claimed in feature-groups.json but not present on disk:"
  printf '  - %s\n' $skills_overclaimed
  problems=$((problems + 1))
fi
if [ -n "$agents_overclaimed" ]; then
  echo "Agents claimed in feature-groups.json but not present on disk:"
  printf '  - %s\n' $agents_overclaimed
  problems=$((problems + 1))
fi

if [ "$problems" -eq 0 ]; then
  echo "feature-groups.json coverage: OK (all skills and agents accounted for)"
fi

if [ "${1:-}" = "--check" ] && [ "$problems" -gt 0 ]; then
  exit 1
fi
exit 0
```

Verification:

```bash
.claude-plugin/scripts/feature-groups-coverage.sh
```

Expected output (when the manifest matches the on-disk inventory):
```
feature-groups.json coverage: OK (all skills and agents accounted for)
```

#### Step 8 — Update `.claude-plugin/hooks/pre-commit/manifest-check.sh`

The current script (verified to be 183 bytes per docs/CLAUDE.md L160 reference) runs `build-manifest.sh --check`. Read the current content:

```bash
cat .claude-plugin/hooks/pre-commit/manifest-check.sh
```

Expected (the current content the file already has; this is the file before this RFC's edit):

```bash
#!/usr/bin/env bash
# Pre-commit hook: regenerate the bootstrap manifest and fail if the result
# differs from what is committed.
set -euo pipefail
"$(git rev-parse --show-toplevel)/.claude-plugin/scripts/build-manifest.sh" --check
```

Replace with:

```bash
#!/usr/bin/env bash
# Pre-commit hook: (1) regenerate the bootstrap manifest and fail if the
# result differs from what is committed, and (2) validate feature-groups.json
# coverage against the on-disk inventory of skills and agents.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
"$ROOT/.claude-plugin/scripts/build-manifest.sh" --check
"$ROOT/.claude-plugin/scripts/feature-groups-coverage.sh" --check
```

Verification:

```bash
bash .claude-plugin/hooks/pre-commit/manifest-check.sh && echo OK
```

Expected output (assuming the manifest is current and the coverage is clean):
```
feature-groups.json coverage: OK (all skills and agents accounted for)
OK
```

#### Step 9 — Add the feature probe to each optional skill

For each of the thirteen optional skills, add the four-line probe at the top of the skill body (immediately after the YAML frontmatter, before any other content). Each skill uses its own caller name in the `BYTEWYRD_FEATURE_PROBE_CALLER` env var so the disabled message names the skill correctly.

The probe template (substitute `<group>` and `<skill-name>` per skill):

```markdown
## Feature toggle

This skill is part of the **`<group>`** feature group. It exits early if the group is disabled in the project.

```bash
result="$(BYTEWYRD_FEATURE_PROBE_CALLER=/<skill-name> bash scripts/feature-toggle.sh <group>)"; ft_status=$?
if [ "$ft_status" -ne 0 ]; then printf '%s\n' "$(printf '%s' "$result" | jq -r .message)"; exit 0; fi
```

```

Per-skill substitutions (group → skill list):

- `rfc-workflow` → `/rfc-new`, `/rfc-approve`, `/rfc-implement`, `/rfc-drop`, `/rfc-braindump`, `/rfc-read-feedback`, `/rfc-summary`, `/rfc-consensus-review`, `/rfc-update`
- `refactor` → `/refactor`
- `best-practices` → `/best-practices-extract`, `/best-practices-record`
- `docs-review` → `/docs-review`

For skills that already have a `## Requirement check` section (`best-practices-extract`, `refactor`, `rfc-implement` — verified above), place the new `## Feature toggle` section **before** the existing `## Requirement check`. The probe must run first because there is no point checking external tool availability for a feature the project has disabled.

For skills that do not have a `## Requirement check` section, place the `## Feature toggle` section as the first H2 below the frontmatter.

Verification (after all thirteen edits): grep for the probe pattern and confirm each skill has it exactly once:

```bash
for s in rfc-new rfc-approve rfc-implement rfc-drop rfc-braindump rfc-read-feedback rfc-summary rfc-consensus-review rfc-update refactor best-practices-extract best-practices-record docs-review; do
  count=$(grep -c "bash scripts/feature-toggle.sh" "skills/$s/SKILL.md")
  echo "$s: $count"
done
```

Expected output (thirteen lines, each ending in `: 1`):
```
rfc-new: 1
rfc-approve: 1
rfc-implement: 1
rfc-drop: 1
rfc-braindump: 1
rfc-read-feedback: 1
rfc-summary: 1
rfc-consensus-review: 1
rfc-update: 1
refactor: 1
best-practices-extract: 1
best-practices-record: 1
docs-review: 1
```

#### Step 10 — Add the agent-side guard to `rfc-architect`, `refactoring-specialist`, `docs-agent`

Each of the three agent files gains a one-paragraph guard at the top of the body (after the YAML frontmatter, before the first H2 heading). The guard text for `rfc-architect` (the other two are identical except for the group identifier and the agent name):

```markdown
## Feature toggle (agent-side guard)

You are part of the **`rfc-workflow`** feature group. Before doing anything else, read `$CLAUDE_PROJECT_DIR/.bytewyrd/features.json`. If the file is absent, or if `.["rfc-workflow"]` is not `true`, your first and only response is exactly:

> `The rfc-architect agent is part of the "rfc-workflow" feature group, which is disabled in this project. To enable, run /sync --reconfigure-features and select the group, or edit .bytewyrd/features.json directly.`

Then stop. Do not perform any other action — no tool calls, no follow-up reasoning, no clarifying questions. The skill that spawned you (a `/rfc-*` slash command) ran the same check at its own entry and exited cleanly; if you have been spawned via `@rfc-architect` autocomplete, this guard is what prevents the agent from doing work in a project that has opted out of the workflow.

If `.["rfc-workflow"]` is `true`, ignore this section and proceed to "Core responsibilities" below.
```

Per-agent substitutions:

- `agents/rfc-architect.md` — `rfc-workflow`
- `agents/refactoring-specialist.md` — `refactor`
- `agents/docs-agent.md` — `docs-review`

Verification:

```bash
for a in rfc-architect refactoring-specialist docs-agent; do
  count=$(grep -c "Feature toggle (agent-side guard)" "agents/$a.md")
  echo "$a: $count"
done
```

Expected output:
```
rfc-architect: 1
refactoring-specialist: 1
docs-agent: 1
```

#### Step 11 — Update `skills/sync/SKILL.md`

Three sub-changes:

**Change 11a — Insert Step 2.5 (feature-toggle prompt) between Step 2 and Step 3.**

After the existing Step 2 section (which ends at "Step 3 — Detect component structure" — verified: skills/sync/SKILL.md:L227-L229), insert the new Step 2.5. The full text of the new step:

```markdown
## Step 2.5 — Initialize or reconcile feature toggles

Read `.bytewyrd/features.json` (the file is gitignored except for this exact path — see the .gitignore extension below):

```bash
features_file=".bytewyrd/features.json"
if [ -f "$features_file" ]; then
  existing_features=$(jq -c '.' "$features_file")
else
  existing_features="{}"
fi
```

Read the available feature groups from the plugin's `feature-groups.json`:

```bash
mapfile -t groups < <(bash "$CLAUDE_PLUGIN_ROOT/scripts/feature-groups-list.sh" summary)
```

Each line in `groups` is `<id>\t<recommended-default>\t<description>`.

Determine which groups need a prompt:

- If `--reconfigure-features` was passed as an argument to `/sync`, prompt for **every** group.
- Otherwise, prompt only for groups whose identifier is not already a key in `existing_features`.
- If the resulting set is empty, skip the prompt entirely; the existing toggles are re-used.

For each group that needs a prompt, build one AskUserQuestion entry:

- Question text: "Enable feature group `<id>`? (`<description>`)"
- Options: `Enable (recommended)` if the group's recommended_default is `true`, otherwise `Disable (recommended)` first; the other option is the inverse.

Send all questions in a single AskUserQuestion call. Map the answers back into a `new_features` JSON object (boolean per group). Merge with `existing_features` (new answers override; pre-existing keys not in the prompt set are preserved verbatim).

Write the merged object atomically:

```bash
mkdir -p .bytewyrd
tmp=$(mktemp .bytewyrd/features.json.XXXXXX)
printf '%s\n' "$merged_features_json" | jq -S '.' > "$tmp"
mv "$tmp" .bytewyrd/features.json
```

Record `features = merged_features_json` for use by Steps 3-8.

Surface any **unknown keys** present in `existing_features` but not defined in `feature-groups.json`:

```bash
unknown=$(jq -n --argjson e "$existing_features" --argjson g "$(bash $CLAUDE_PLUGIN_ROOT/scripts/feature-groups-list.sh json)" '
  ($e | keys) - ([$g | keys[]])
')
if [ "$(printf '%s' "$unknown" | jq 'length')" -gt 0 ]; then
  echo "[warn] .bytewyrd/features.json contains unknown feature group identifiers: $unknown — these are preserved but ignored. Remove them manually if intentional."
fi
```

The warning is informational; sync continues.
```

**Change 11b — Modify Step 4 (compute diff) to filter manifest artifacts by `feature_group`.**

The current Step 4 procedure (verified: skills/sync/SKILL.md:L287-L341) iterates every artifact in the manifest. Insert a filter at the top of the iteration:

```markdown
For each artifact in the manifest:

1. **Feature-group filter (NEW).** If the artifact has a `feature_group` field whose value is a non-null string AND `features[<feature_group>]` is not `true`, skip the artifact and record it as `feature_skipped` in the Step 8 report. Skip to the next artifact.

2. **Compute `plugin_current_canonical_sha`** ... (existing step continues unchanged)
```

The `feature_skipped` outcome surfaces in the Step 8 report:

```markdown
Feature-disabled artifacts (N files, plugin not active):
  - docs/rfc-process.md  (feature group "rfc-workflow" is disabled)
```

**Change 11c — Modify Step 5 (apply changes) to render `CLAUDE.md` with section-level feature filtering.**

The current `CLAUDE.md` rendering (verified: skills/sync/SKILL.md:L443-L451 in the section-strategy `fast_forward` branch) replaces each owned section's body with the plugin's rendered body for that section. Insert a section-level filter immediately before rendering:

```markdown
**Section-level feature filter (NEW for CLAUDE.md):** Before rendering the plugin's owned sections, consult the artifact's `section_feature_groups` map. For each `owned_section`, if `section_feature_groups[<section>]` is a non-null string AND `features[<feature_group>]` is not `true`, omit the section entirely from the rendered output. The section heading and body are excluded from the plugin's contribution; any user-added content under the same heading in the existing local file is preserved verbatim (per the existing `section` strategy semantics — verified: skills/sync/SKILL.md:L338, L447).
```

The plugin-side canonical hash (used for marker insertion — verified: skills/sync/SKILL.md:L432-L434) is computed from the **post-filter** rendered output, so a project with `rfc-workflow=false` produces a deterministic hash that does not change between `/sync` runs that have the same toggle state.

**Change 11d — Add `--reconfigure-features` flag handling.**

Add a one-line note at the very top of the `/sync` skill body (after the frontmatter, before "## Interaction model"):

```markdown
The `/sync` skill accepts one optional flag:

- `--reconfigure-features` — re-prompt for every feature toggle, even ones that already have a value in `.bytewyrd/features.json`. Used to change a prior choice without hand-editing the file.
```

The flag is parsed by reading `$ARGUMENTS` (the standard skill argument variable). Add to the top of the skill body:

```bash
reconfigure_features="false"
for arg in $ARGUMENTS; do
  case "$arg" in
    --reconfigure-features) reconfigure_features="true" ;;
  esac
done
```

Step 2.5 references `$reconfigure_features` when deciding whether to prompt every group or only unknown ones.

**Change 11e — Modify Step 8 report.**

Add to the report table (per the existing Step 8 table — verified: skills/sync/SKILL.md:L702-L724):

- A row labeled `.bytewyrd/features.json` with outcome `created` / `re-applied` / `reconfigured (--reconfigure-features)` as appropriate.
- A new "Feature-disabled artifacts" subsection listing artifacts skipped by Step 4's filter.
- A new "Bootstrap files referencing disabled features" subsection produced by the grep described in Drawbacks. The detection logic:

```bash
disabled_groups=$(jq -r 'to_entries[] | select(.value != true) | .key' .bytewyrd/features.json)
for group in $disabled_groups; do
  # Pull the per-group skill list from feature-groups.json
  skills=$(jq -r --arg g "$group" '.optional[$g].skills[] // empty' "$CLAUDE_PLUGIN_ROOT/feature-groups.json")
  sections=$(jq -r --arg g "$group" '.optional[$g].claude_md_sections[] // empty' "$CLAUDE_PLUGIN_ROOT/feature-groups.json")
  for f in docs/CONTRIBUTING.md docs/ARCHITECTURE.md README.md; do
    [ -f "$f" ] || continue
    matches=$(grep -E "(/$(printf '%s|' $skills | sed 's/|$//'))" "$f" 2>/dev/null | head -3)
    [ -n "$matches" ] && echo "  $f may reference disabled feature '$group' — review and edit manually if needed."
  done
done
```

Verification of the three sync edits (after applying them): re-read `skills/sync/SKILL.md` and confirm:

```bash
grep -c "Step 2.5 — Initialize or reconcile feature toggles" skills/sync/SKILL.md
grep -c "Feature-group filter (NEW)" skills/sync/SKILL.md
grep -c "Section-level feature filter (NEW for CLAUDE.md)" skills/sync/SKILL.md
grep -c -- "--reconfigure-features" skills/sync/SKILL.md
```

Expected output (each command should print `1` or higher; the flag has multiple references):
```
1
1
1
3
```

#### Step 12 — Update `scripts/check-requirements.sh`

The current script (verified to exist in the working directory — full content reproduced in `2026-05-12-user-scope-plugin-installation` at docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L213-L420) iterates `REQUIRED_PLUGINS` and warns when each is not enabled. Add the feature-toggle filter near the top, after the `REQUIRED_PLUGINS` array declaration (verified pattern at docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L229-L233):

```bash
# --- Feature-group filtering ------------------------------------------------

# Build companion-plugin → feature-group mapping from feature-groups.json,
# then read the project's .bytewyrd/features.json. A companion plugin warning
# is suppressed if (a) the plugin appears in companion-plugins of any group,
# and (b) every group claiming it is disabled.
proj_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
features_file="$proj_dir/.bytewyrd/features.json"
if [ -f "$features_file" ]; then
  features_json=$(cat "$features_file")
else
  # No features file → pre-RFC behavior: all features assumed enabled
  features_json='{"rfc-workflow":true,"refactor":true,"best-practices":true,"docs-review":true}'
fi

# Resolve the plugin root using the same three-tier resolver as
# hooks/hooks.json (verified pattern).
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -f "$plugin_root/feature-groups.json" ]; then
  plugin_root="$HOME/.claude/plugins/cache/bytewyrd/bytewyrd"
fi
if [ ! -f "$plugin_root/feature-groups.json" ]; then
  plugin_root=$(dirname "$(ls -1 "$HOME"/.claude/plugins/cache/*/bytewyrd/feature-groups.json 2>/dev/null | head -n1)")
fi

# Build a key → array of groups claiming this plugin
companion_map=""
if [ -f "$plugin_root/feature-groups.json" ]; then
  companion_map=$(jq -r '.optional | to_entries[] | .key as $g | .value.companion_plugins[]? | "\(.)\t\($g)"' "$plugin_root/feature-groups.json")
fi

# is_feature_disabled <companion-plugin-id>
# returns 0 if the plugin is claimed by at least one group AND every claiming
# group is disabled; returns 1 otherwise.
is_feature_disabled() {
  local id="$1"
  local groups
  groups=$(printf '%s\n' "$companion_map" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')
  [ -z "$groups" ] && return 1
  local all_disabled=0
  for g in $groups; do
    local enabled
    enabled=$(printf '%s' "$features_json" | jq -r --arg g "$g" '.[$g] // false | tostring')
    if [ "$enabled" = "true" ]; then return 1; fi
  done
  return 0
}
```

Then, in the `for id in "${REQUIRED_PLUGINS[@]}"` loop (verified pattern at docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L348-L354), insert a check before the existing skip-logic:

```bash
for id in "${REQUIRED_PLUGINS[@]}"; do
  short="$(printf '%s' "$id" | sed -E 's/@.*//')"
  is_skipped "$short" && continue
  is_feature_disabled "$id" && continue   # NEW: skip if claimed only by disabled features
  if ! plugin_enabled "$id"; then
    warnings+=("[warn] $id not enabled. Fix: claude plugin install $id")
  fi
done
```

Verification: in a project with `{"refactor": false}` in `.bytewyrd/features.json`, the `code-review@claude-plugins-official` warning is suppressed (because `refactor` is the only group claiming it — see Step 1's `feature-groups.json`):

```bash
mkdir -p .bytewyrd && echo '{"rfc-workflow":true,"refactor":false,"best-practices":true,"docs-review":true}' > .bytewyrd/features.json
CLAUDE_PROJECT_DIR=$(pwd) CLAUDE_PLUGIN_ROOT=$(pwd) bash scripts/check-requirements.sh 2>&1 | grep -E 'code-review' || echo "no code-review warning (suppressed by feature toggle)"
```

Expected output:
```
no code-review warning (suppressed by feature toggle)
```

#### Step 13 — Update `.claude-plugin/scripts/templates/.gitignore.tpl`

The current template's `# bytewyrd:base` block (per `2026-05-14-sync-per-file-extension-strategies` item 10) contains:
```
.worktrees/
.claude/settings.local.json
.bytewyrd/*
!.bytewyrd/.bootstrap-versions.json
```

Add one new line immediately after the existing `!.bytewyrd/.bootstrap-versions.json` line:
```
!.bytewyrd/features.json
```

After the edit, the `# bytewyrd:base` block reads:
```
.worktrees/
.claude/settings.local.json
.bytewyrd/*
!.bytewyrd/.bootstrap-versions.json
!.bytewyrd/features.json
```

This tracks `features.json` in git (so team toggle choices travel with the repo) while keeping other `.bytewyrd/` runtime state ignored. The plugin's own checkout's `.gitignore` already inherits the same pattern via `/sync`-managed update — no separate edit there.

Verification: regenerate the plugin's own `.gitignore` and confirm the new line is present (the plugin's checkout dogfoods `/sync`):

```bash
grep -c "^!\.bytewyrd/features\.json$" .gitignore
```

Expected output:
```
1
```

#### Step 14 — Update `docs/ARCHITECTURE.md`

Add a new component entry under `## Components`. Insert directly after the existing `### Plugin manifest (.claude-plugin/)` subsection (verified: docs/ARCHITECTURE.md:L47-L50):

```markdown
### Feature groups (`feature-groups.json`, `.bytewyrd/features.json`)

**Purpose:** Partition optional plugin components into named groups that consumer projects can enable or disable per project. The plugin-root `feature-groups.json` is the source of truth for the partitioning; the per-project `.bytewyrd/features.json` records each project's toggle choices.
**Location:** `feature-groups.json` at the plugin root; `.bytewyrd/features.json` in each consumer project.
**Key interfaces:**
- `scripts/feature-toggle.sh <group>` — the per-skill probe helper. Skills call this at the top of their body and exit cleanly with a "feature disabled" message if the requested group is off.
- `scripts/feature-groups-list.sh` — driver for `/sync`'s toggle prompt and `check-requirements.sh`'s companion-plugin filter.
- `.claude-plugin/scripts/feature-groups-coverage.sh` — pre-commit validator ensuring every on-disk skill and agent is claimed by exactly one group.

Toggle state is read at runtime by every optional skill, by `/sync` when applying manifest artifacts and rendering `CLAUDE.md`, and by `check-requirements.sh` when deciding which companion-plugin warnings to surface.
```

Also add a row to the Design Decisions table (verified: docs/ARCHITECTURE.md:L62-L69):

```
| Feature toggles | Single-plugin runtime-probe model, state in .bytewyrd/features.json, manifest at feature-groups.json | Avoids multi-plugin distribution complexity (cross-skill namespace breakage, marketplace skills-filter bugs); skills remain invocable but feature-disabled skills exit cleanly; per-project state tracked in git |
```

Verification:

```bash
grep -c "### Feature groups" docs/ARCHITECTURE.md
grep -c "| Feature toggles |" docs/ARCHITECTURE.md
```

Expected output:
```
1
1
```

#### Step 15 — Update `README.md`

The plugin's `README.md` (verified to exist at the working directory root) currently documents installation. After the existing "Installation" section, add a new "Feature toggles" subsection. The text:

```markdown
## Feature toggles

The plugin's optional components are partitioned into four feature groups that you can enable or disable per project:

- **`rfc-workflow`** — RFC-driven design and implementation (`/rfc-new`, `/rfc-approve`, `/rfc-implement`, ...). Adds `docs/rfc-process.md` and the `## RFC Process` section of `CLAUDE.md`.
- **`refactor`** — deliberate refactoring passes (`/refactor`).
- **`best-practices`** — session-learning capture (`/best-practices-extract`, `/best-practices-record`).
- **`docs-review`** — user-facing-doc auditing (`/docs-review`).

The recommended default for every group is **enabled**. On the first `/sync` run in a project, you'll see a one-screen prompt asking which groups to enable. The answers are saved to `.bytewyrd/features.json` and re-applied silently on every subsequent `/sync` run.

To change your choices later, run `/sync --reconfigure-features` (or edit `.bytewyrd/features.json` directly and re-run `/sync`).

Skills whose feature group is disabled remain visible in the slash-command picker — Claude Code's plugin system does not currently support per-project skill suppression. Invoking a disabled skill prints a one-line "feature disabled" message and exits without doing anything. The check-requirements hook suppresses warnings for companion plugins claimed only by disabled groups (for example, `code-review@claude-plugins-official` is silently skipped when `refactor` is off).

**Migration note for existing projects:** if you have the plugin installed already and are upgrading to a version that introduces feature toggles, run `/sync` once. The toggle prompt fires once, defaults every group to enabled (preserving your previous experience), and writes `.bytewyrd/features.json`. Future `/sync` runs are silent.
```

Verification:

```bash
grep -c "^## Feature toggles$" README.md
```

Expected output:
```
1
```

#### Step 16 — Final verification

Run the full verification sweep after all edits:

```bash
# 1. Manifest validates
python3 -c 'import json; json.load(open("feature-groups.json"))' && echo OK
python3 -c 'import json; json.load(open(".claude-plugin/bootstrap-manifest.json"))' && echo OK

# 2. Coverage check passes
.claude-plugin/scripts/feature-groups-coverage.sh --check && echo OK

# 3. Pre-commit hook chain passes
bash .claude-plugin/hooks/pre-commit/manifest-check.sh && echo OK

# 4. Probe helper works in all three modes
mkdir -p .bytewyrd && echo '{"rfc-workflow":true,"refactor":false,"best-practices":true,"docs-review":true}' > .bytewyrd/features.json
CLAUDE_PROJECT_DIR=$(pwd) bash scripts/feature-toggle.sh rfc-workflow | jq -e '.result == "enabled"' && echo OK
CLAUDE_PROJECT_DIR=$(pwd) bash scripts/feature-toggle.sh refactor | jq -e '.result == "disabled"' && echo OK

# 5. All thirteen optional skills have the probe
for s in rfc-new rfc-approve rfc-implement rfc-drop rfc-braindump rfc-read-feedback rfc-summary rfc-consensus-review rfc-update refactor best-practices-extract best-practices-record docs-review; do
  grep -q "bash scripts/feature-toggle.sh" "skills/$s/SKILL.md" || { echo "MISSING: $s"; exit 1; }
done; echo OK

# 6. All three optional agents have the guard
for a in rfc-architect refactoring-specialist docs-agent; do
  grep -q "Feature toggle (agent-side guard)" "agents/$a.md" || { echo "MISSING: $a"; exit 1; }
done; echo OK

# 7. Sync skill has all required updates
grep -q "Step 2.5 — Initialize or reconcile feature toggles" skills/sync/SKILL.md && echo OK
grep -q "Feature-group filter (NEW)" skills/sync/SKILL.md && echo OK
grep -q "Section-level feature filter (NEW for CLAUDE.md)" skills/sync/SKILL.md && echo OK
grep -q -- "--reconfigure-features" skills/sync/SKILL.md && echo OK

# 8. Check-requirements integrates feature toggles
grep -q "is_feature_disabled" scripts/check-requirements.sh && echo OK

# 9. ARCHITECTURE.md and README.md updated
grep -q "### Feature groups" docs/ARCHITECTURE.md && echo OK
grep -q "^## Feature toggles$" README.md && echo OK

# 10. Functional smoke test: invoke the rfc-new skill body's feature probe
# directly with rfc-workflow disabled and confirm the disabled message
echo '{"rfc-workflow":false}' > .bytewyrd/features.json
CLAUDE_PROJECT_DIR=$(pwd) BYTEWYRD_FEATURE_PROBE_CALLER=/rfc-new bash scripts/feature-toggle.sh rfc-workflow | jq -r .message
# Expected: /rfc-new is disabled in this project — feature group "rfc-workflow" is off. To enable, run /sync --reconfigure-features and select the group, or edit .bytewyrd/features.json directly.
```

Each `OK` is one verification gate; the test sequence prints `OK` 14 times when every gate passes, plus the literal disabled message at the very end. After the test, restore the dogfood `.bytewyrd/features.json`:

```bash
echo '{"rfc-workflow":true,"refactor":true,"best-practices":true,"docs-review":true}' > .bytewyrd/features.json
```

## Risks and open questions

- **Risk: a user types `/bytewyrd:rfc-new` in a `rfc-workflow=false` project, sees the disabled message, and concludes the plugin is broken.** Mitigation: the disabled message names the toggle ("feature group `rfc-workflow` is off"), the fix command (`/sync --reconfigure-features`), and the alternative (edit `.bytewyrd/features.json`). The user's first reading of the message is enough to act. Resolution: accepted; document the message format and the `--reconfigure-features` flag in `README.md` (Step 15).

- **Risk: the in-skill probe depends on `jq` being present, but the requirement-check hook only warns about missing `jq` if it is configured as a hard requirement (verified: scripts/check-requirements.sh does not currently probe for `jq`).** Mitigation: `jq` is already a precondition of the existing `tool-probe.sh` helper used by three skills (verified: scripts/tool-probe.sh:L36 `require_jq`); adding a fourth helper that depends on the same precondition is a no-op for any project that has the existing helpers working. If `jq` is missing, every optional skill exits with a confusing JSON-parse error rather than a clean "feature disabled" message. Resolution: defer to a later RFC if real-world reports show this confusion. The probe could be rewritten in pure bash (a 20-line JSON parser) at the cost of removing the JSON-shape contract; the cost is high and the failure mode is narrow.

- **Risk: a user disables a feature group, then runs a skill in a different group that internally references the disabled group's slash command in its body text.** Example: `/rfc-implement` (in `rfc-workflow`) mentions `/refactor` (in `refactor`) as a follow-up tip in its post-implementation guidance. If `refactor` is disabled, the tip points at a slash command that exits with the disabled message. Mitigation: the `bootstrap files referencing disabled features` warning in Step 8 already catches this for the static docs (`docs/CONTRIBUTING.md`, etc.); skill bodies that cross-reference each other could be similarly grep-scanned, but this RFC does not implement that. Resolution: accepted as a known soft edge case. Real-world resolution is documentation — the cross-references in skill bodies are minor pointers, and the disabled message itself names the toggle the user would flip to fix.

- **Open question: should agents in `core` (e.g., `feature-engineer`, `code-reviewer`) carry any feature-aware guidance?** The core agents are always enabled, but their guidance occasionally references workflows that depend on optional groups — `code-reviewer` mentions RFC review (verified: agents/code-reviewer.md line referencing `/rfc-consensus-review` exists per agents/code-reviewer.md inspection). Resolution within this RFC: no. Core agents stay feature-agnostic in their body text; the cross-references they carry are stable identifiers (the agent could mention `/rfc-consensus-review` and the skill itself handles the disabled case if invoked). A more rigorous future RFC could add per-paragraph feature-awareness annotations to agent bodies — out of scope here.

- **Open question: should the toggle state be augmented with a `disabled_at: "<date>"` field per group to surface "this was disabled on date X" in the report?** Considered. Resolution: no. The state is meant to be a single source of truth, not an audit log; git history of `.bytewyrd/features.json` provides the audit trail. Adding timestamps complicates the schema with no clear caller demand.

- **Open question: should the `--reconfigure-features` flag accept an optional argument naming a specific group (e.g., `/sync --reconfigure-features=rfc-workflow`)?** Considered. Resolution: no, in this RFC. The flag is the explicit user-driven path; the common case is "re-toggle everything." Per-group flag handling adds parser complexity for a use case the user can already accomplish by editing the JSON and re-running `/sync`. A future RFC can add it if the hand-edit path proves too friction-heavy.

- **Open question: should there be a `bytewyrd-features` slash command for listing the current state without running full `/sync`?** Considered. Resolution: no, in this RFC. The information is `cat .bytewyrd/features.json` — a slash command for it is over-engineering. A user can also run `bash scripts/feature-groups-list.sh summary` for the available groups and their descriptions.

- **Open question: the `feature-groups.json` schema does not have an explicit version field.** Resolution: not in this RFC. The schema is small (one core entry + one optional dict; per-group: description, recommended_default, skills, agents, manifest_artifacts, claude_md_sections, companion_plugins) and forward-compatibility comes from defensive reading (Decision 3). A future RFC that needs to introduce a breaking schema change can add a version field at that point.

- **Open question: what happens when a future plugin version renames a feature group (e.g., `rfc-workflow` → `rfc`)?** Resolution: out of scope here. The cleanest path is a manifest-level alias map in `feature-groups.json` (e.g., `"aliases": {"rfc-workflow": "rfc"}`) that `/sync` consults when reading `.bytewyrd/features.json`. If a real rename happens, a follow-up RFC defines the alias mechanism then. Until then, manifest authors are advised to treat group identifiers as stable.

- **Open question: should the agent-side guard (Step 10) write to a sidecar file recording that the agent was invoked while its feature was disabled?** Useful for telemetry. Resolution: no. The plugin does not collect telemetry; adding a per-invocation log file violates the user-facing "no surprising file writes" expectation.

- **Open question: when the plugin's own `pre-commit` hook fails `feature-groups-coverage.sh --check` because a new skill was added without claiming, should the failure message include an auto-suggested edit to `feature-groups.json`?** Resolution: out of scope. The coverage script already names the unclaimed skill in its output; the maintainer adds the entry by hand. Auto-suggesting a group requires the script to guess the maintainer's intent (the skill could belong to any of the four groups, or to core), which is exactly the judgment call the human should make.

## Relationship to other RFCs

- **`2026-05-12-user-scope-plugin-installation`** (status: Done — verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L5 `status: "Done"`). This RFC's `check-requirements.sh` integration (Step 12) extends the script created by that RFC. The user-scope RFC's own "Relationship to other RFCs" section (verified: docs/rfcs/2026-05-12-user-scope-plugin-installation.md:L880) explicitly anticipated this RFC: "the requirement check needs to be aware of toggle state so it doesn't warn about a missing dependency the user has explicitly disabled — but that integration is small (the check reads the toggle state from wherever the toggles RFC chooses to store it)." Confirmed integration point: `.bytewyrd/features.json` is the toggle store; `check-requirements.sh` reads it via the `is_feature_disabled` helper.

- **`2026-05-14-sync-per-file-extension-strategies`** (status: Approved — verified: docs/rfcs/2026-05-14-sync-per-file-extension-strategies.md:L5). This RFC depends on the relocation of `.bootstrap-versions.json` to `.bytewyrd/` (item 9 of that RFC's "Exact manifest changes") and the `.gitignore` carve-out for `.bytewyrd/*` with negation of the sidecar (item 10). This RFC's `.gitignore` edit (Step 13) adds one new negation line directly after the per-file-extension-strategies one. The two RFCs do not overlap in any owned region of the manifest — per-file-extension-strategies modifies extension strategies, this RFC adds the `feature_group` / `section_feature_groups` fields, and `build-manifest.sh` preserves both sets transparently (Step 6).

- **`2026-05-10-audit-rework-agent-definitions`** (status: per-line inspection not done; the RFC introduces `docs/agent-audit-criteria.md`). The feature-group claim arrays in `feature-groups.json` (Step 1) enumerate every agent currently in `agents/`. If a future audit pass removes or renames an agent, the manifest's claim must be updated; the pre-commit hook (Step 8) surfaces the mismatch. The two RFCs are compatible; they touch the same `agents/` directory but for different concerns (audit quality vs. feature partitioning).

- **`2026-05-09-best-practices-content-and-tooling`** (status: per-line inspection not done in this draft; the RFC defines BEST_PRACTICES.md taxonomy). The `best-practices` feature group's skills (`/best-practices-extract`, `/best-practices-record`) implement the surface defined by that RFC. Disabling the group means a project does not capture session learnings via the plugin; the project's own `docs/BEST_PRACTICES.md` content is unaffected (the file is `owned-regions` strategy per `2026-05-14-sync-per-file-extension-strategies`; the plugin's bootstrap entries are still applied when the file is touched). The two RFCs compose cleanly.

- **`/sync` skill (no RFC; existing skill).** This RFC modifies `skills/sync/SKILL.md` substantially (Step 11). The modifications are additive on top of the existing diff/apply flow — Step 2.5 inserts a new step between existing Step 2 and Step 3; Step 4 gains a per-artifact filter at the top of its iteration; Step 5 gains a section-level filter inside the `section`-strategy branch. No existing semantics change; pre-RFC projects that have not initialized `.bytewyrd/features.json` see the same behavior as before because the default-fallback ("all features enabled") preserves it. The pre-RFC `bytewyrd@bytewyrd` enabledPlugins cleanup added by the user-scope-plugin-installation RFC is unaffected.

- **`/rfc-implement` skill (modified by this RFC, Step 9).** The implementation of this RFC, when it lands, will be performed by `/rfc-implement`. That skill is itself in the `rfc-workflow` group (per `feature-groups.json`'s Step 1 definition). The plugin's own checkout has `rfc-workflow=true` (Step 4), so the skill operates normally inside the plugin's own workspace; in any other project that has not enabled `rfc-workflow`, the skill exits cleanly with the disabled message, which is the correct behavior (you cannot implement an RFC in a project that has opted out of the RFC workflow).
