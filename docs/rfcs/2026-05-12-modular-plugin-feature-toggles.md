---
rfc: "2026-05-12-modular-plugin-feature-toggles"
title: "Modular Plugin Feature Toggles"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-12"
drop_reason: ~
---

## Summary

Restructure the bytewyrd plugin so it ships as a set of opt-in **features** that consumers can enable or disable during `/sync`. A small **core** set (project-brief, evidence-based-development guidance, agent delegation table, CLAUDE.md scaffolding) is always installed because the rest of the plugin depends on it. Everything else — the RFC workflow, the `/refactor` flow, the best-practices extract/record/sync trio, the git-branch-cleanup skill, the GitHub artifacts (PR template, issue templates, CI workflow), and the language-specific best-practice and tooling blocks — becomes opt-in. The set of enabled features is stored as a single `features` block in `.claude/settings.json` (versioned with the rest of the project's Claude Code config). `/sync` reads that block on every run; on first run, when no block is present, it asks the user via one `AskUserQuestion` with one question per optional feature; on re-runs, it skips the prompt entirely and re-applies the stored set, only re-prompting when the plugin has introduced a *new* optional feature the user has not yet seen. Each feature declares its boundaries via a `feature:` field in the SKILL.md frontmatter (for skills) and a single `features/<id>.toml` manifest (for non-skill artifacts), so the diff/apply engine can include or exclude artifacts cleanly. Features cannot cross-reference each other except through documented soft handles (string identifiers checked at runtime, never imports); a feature whose handles are unsatisfied logs one warning at session start and disables itself for that session.

## Should we do this?

**Yes.** The current plugin is structurally all-or-nothing: a consumer who runs `/sync` inherits every skill, every agent delegation row, every best-practice entry, the full RFC workflow, the post-commit hooks, the CI workflow, the GitHub templates, and the PreCompact / Stop reminders. This is by design — the plugin encodes one opinionated way of working — but it is at odds with the actual range of projects that adopt it. Several real consumer patterns the plugin should serve are not served well today:

- **Projects that do not want the RFC process.** A small CLI tool or a personal experiment does not need `docs/rfcs/`, `docs/rfc-process.md`, or the `/rfc-*` slash commands cluttering its workflow. Today, the only way to opt out is to delete the files after `/sync` writes them — which the next `/sync` re-creates.
- **Projects that do not want `/refactor`.** The skill spawns an Opus-with-max-effort agent and is deliberately expensive; teams on tight quota budgets may want to keep the skill off entirely rather than rely on discipline to avoid invoking it.
- **Projects with a different best-practices model.** A team that already has an internal pattern for capturing learnings does not want `docs/BEST_PRACTICES.md` and the `/best-practices-*` skills duplicating it; today both are added unconditionally.
- **Projects without GitHub.** A repo hosted on GitLab or Forgejo gets every `.github/` artifact silently skipped at apply time, but the artifact templates are still embedded in the plugin and the `enabledPlugins` block still references the GitHub MCP plugin. The skip is a side effect of `has_github = false`, not an explicit opt-out.

The cost of doing this is a meaningful re-architecture: every artifact must declare which feature it belongs to, the bootstrap manifest (from RFC `2026-05-10-sync-interactive-diff`) gains a `feature` field on every entry, `/sync`'s flow gains a feature-selection step, and skills must be filter-aware in how they reference each other (the `/refactor` skill mentioning `/best-practices-extract`, for example, must degrade gracefully when extract is disabled). The alternative — telling consumers "fork the plugin and remove what you don't want" or "delete files after `/sync`" — produces fragmentation and lost upgrades, the same problem RFC `2026-05-10-sync-interactive-diff` set out to solve for plugin-content updates. Both problems share a root cause (the plugin has no way to express "this part of me is optional") and benefit from a single shared mechanism.

Doing it now, while the project is still small (15 skills, ~30 agent files, one consumer-facing `/sync` flow), keeps the migration surface manageable. Every month the plugin ships more artifacts; every month the cost of retrofitting feature boundaries grows.

## Current state

The plugin currently has no notion of "feature." Every artifact under `skills/`, `agents/`, `.claude-plugin/`, and the files written by `skills/sync/SKILL.md` is treated as a single monolithic deliverable. The relevant surfaces today are:

**Skills directory (`skills/`).** Thirteen skills, every one always loaded:

| Skill | Slash command | Always enabled today |
|---|---|---|
| `sync` | `/sync` | yes (entry point) |
| `best-practices-extract` | `/best-practices-extract` | yes |
| `best-practices-record` | `/best-practices-record` | yes |
| `git-branch-cleanup` | `/git-branch-cleanup` (and trigger words) | yes |
| `refactor` | `/refactor` | yes |
| `rfc-approve` | `/rfc-approve` | yes |
| `rfc-braindump` | `/rfc-braindump` | yes |
| `rfc-consensus-review` | `/rfc-consensus-review` | yes |
| `rfc-drop` | `/rfc-drop` | yes |
| `rfc-implement` | `/rfc-implement` | yes |
| `rfc-new` | `/rfc-new` | yes |
| `rfc-read-feedback` | `/rfc-read-feedback` | yes |
| `rfc-update` | `/rfc-update` | yes |
| (plugin-local) `best-practices-sync` | — | yes (maintainer-only, lives under `.claude/skills/`) |

Skills are discovered by Claude Code by walking the `skills/` directory in the plugin root; the consumer has no per-skill on/off switch except by removing or renaming the skill directory in the plugin checkout (which a user-scope or marketplace install does not permit).

**Agents directory (`agents/`).** ~30 agent definition files. Each is referenced by name from the `Task` tool when delegated. Some skills explicitly invoke specific agents (`refactor` → `refactoring-specialist`; `rfc-new` → `rfc-architect` + review agents; `rfc-consensus-review` → five reviewers; `rfc-implement` → `feature-engineer`). The agent definitions themselves are static — they do not branch on which features are enabled.

**Files written by `/sync`.** The current sync flow writes (or considers writing) these artifacts, all unconditionally:

- `CLAUDE.md` — contains an Agent delegation table, an RFC Process section, a Tool Usage section, an Evidence-Based Development section, a Model Usage Optimization section, a Claude Code Sandbox section, a Security section, and a Conventions section. The RFC Process section is hard-coded into the template; there is no toggle.
- `docs/BEST_PRACTICES.md` — base pre-populated entries plus universal additions (Testing, Documentation, Security, Error Handling), Architecture additions, language-specific additions (Rust, JS/TS, Python, Go, Svelte, Ruby, Rails, Kubernetes/CUE/kapply, Terraform/Terragrunt), and the user-owned `## Project-Specific` section. All universal and language additions ship unconditionally on relevant detection; there is no way to opt out of best-practices accumulation entirely.
- `docs/rfc-process.md` — the full RFC process document, written verbatim with a `## Project Extensions` placeholder. Written unconditionally; the only way to "opt out" today is to ignore the file.
- `docs/rfcs/.gitkeep` — placeholder for the RFCs directory; created unconditionally.
- `docs/CONTRIBUTING.md` — references the RFC process explicitly ("Significant changes go through the RFC process. See docs/rfc-process.md").
- `.claude/settings.json` — contains the `enabledPlugins` block, the `extraKnownMarketplaces` block, and four hooks: PreCompact (best-practices reminder), PostToolUse (post-commit doc reminder, three matchers), Stop (session-end checklist mentioning `/best-practices-extract`), PreToolUse (pre-push quality gate). The PreCompact and Stop hooks explicitly mention `/best-practices-extract`.
- `.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md` — written when `has_github = true`; not user-toggleable.
- `mise.toml`, `rust-toolchain.toml`, `.gitignore` — toolchain and language artifacts; not toggleable beyond the language detection that gates them.

**Plugin-level config (`.claude-plugin/plugin.json`).** Currently four fields (`name`, `description`, `version`, `author`). No notion of feature catalogue.

**Bootstrap manifest (proposed by RFC `2026-05-10-sync-interactive-diff`, status: Draft).** That RFC introduces `.claude-plugin/bootstrap-manifest.json` enumerating every plugin-managed artifact with an `upstream_key`, `source`, `target`, `extension_strategy`, `owned_sections` / `owned_paths`, `templated`, and `template_inputs`. It does **not** include any per-artifact feature tag — every artifact is unconditionally synced once the consumer's `project_inputs` match. This RFC extends that schema with a `feature` field.

**Cross-references between skills today.** A scan of `skills/*/SKILL.md` and `.claude-plugin/CLAUDE.md` shows the following inter-feature references — each is a place that must degrade gracefully when the referenced feature is disabled:

| From | To | How |
|---|---|---|
| `skills/sync/SKILL.md` | `docs/BEST_PRACTICES.md` and all language additions | Writes the file with prepopulated entries |
| `skills/sync/SKILL.md` | `docs/rfc-process.md` | Writes the file from upstream template |
| `skills/sync/SKILL.md` | `docs/rfcs/.gitkeep` | Creates the directory |
| `skills/sync/SKILL.md` | `CLAUDE.md` (RFC Process section) | Embeds the RFC pointer |
| `skills/sync/SKILL.md` | `CLAUDE.md` (Agent delegation table) | Embeds rfc-architect, refactoring-specialist references |
| `skills/sync/SKILL.md` | `.claude/settings.json` (PreCompact, Stop hooks) | Hook bodies mention `/best-practices-extract` |
| `skills/rfc-*` | `docs/rfc-process.md` | Read the file for process rules |
| `skills/rfc-implement/SKILL.md` | `feature-engineer` agent | Spawned by name |
| `skills/refactor/SKILL.md` | `refactoring-specialist` agent | Spawned by name |
| `skills/refactor/SKILL.md` (in description) | `/best-practices-extract` | Mentioned as a typical follow-up |
| `skills/best-practices-record` | `~/.claude/BEST_PRACTICES.md` | Writes the global file |
| `skills/best-practices-extract` | `docs/BEST_PRACTICES.md` | Writes the project file |
| `.claude/skills/best-practices-sync` | `skills/sync/SKILL.md` | Edits the plugin's sync content |

The current "disable a part of the plugin" workaround is to delete the artifact after `/sync` writes it. RFC `2026-05-10-sync-interactive-diff` (Draft) makes deletion stickier (the conflict-resolution flow can mark a file as "keep local-absent") but does not introduce a structural notion of feature absence — every consumer's bootstrap manifest still lists every artifact, just with possibly-absent local files.

**What this means for the user, today:** there is no path from "I do not use the RFC process for this project" to a clean install without RFC artifacts. The closest workaround is to `/rfc-drop` every RFC and ignore the `docs/rfcs/` directory — which leaves the RFC artifacts present, the slash commands enabled, the `docs/rfc-process.md` file in the tree, and the CLAUDE.md RFC pointer telling the next contributor (or agent) "use the RFC process." Both the human contributor and any agent reading `CLAUDE.md` see contradictory signals.

## Analysis / Options

Four coupled decisions: (1) which feature set the plugin ships, (2) where the toggle state lives, (3) how features declare their boundaries (so the diff/apply engine can include/exclude their artifacts), and (4) how `/sync` surfaces the choice to the user.

### Decision 1 — Which features are core vs. optional?

A feature is *core* when every other feature, or every consumer use of the plugin, structurally depends on it. A feature is *optional* when a reasonable consumer might not want it and removing it does not break anything else when handled per the boundary rules.

The split below is the recommendation. The criteria are spelled out so future additions inherit the same logic.

**Core features (always enabled, never prompted, no feature toggle in settings):**

| Feature id | What it ships | Why core |
|---|---|---|
| `core-identity` | `docs/project-brief.md` (template + identity-extraction logic), `CLAUDE.md` (the file itself + the H1, description paragraph, file structure, model usage section), `README.md` skeleton, `.gitignore` base entries, `.worktrees/` directory | Every other feature reads `project_name` / `description` from the brief or writes prose into `CLAUDE.md`. Disabling this disables `/sync` itself. |
| `core-claude-config` | `.claude/settings.json` minimal (`extraKnownMarketplaces` for bytewyrd, `enabledPlugins["bytewyrd@bytewyrd"]`), `.claude/settings.local.json` minimal (web permissions, git permissions, exa permissions, firefox-devtools permissions) | Required for the plugin to function. Removing it removes the plugin itself. |
| `core-evidence-based` | `CLAUDE.md` `## Evidence-Based Development` section, `CLAUDE.md` `## Tool Usage` section (Exa, Context7, Firefox MCP blocks) | This is the foundational operating principle of the plugin; every agent and skill assumes it. |
| `core-agent-delegation` | `CLAUDE.md` `## Agent delegation` table (the table itself, even if rows are subsetted per enabled features), `agents/feature-engineer.md`, `agents/code-reviewer.md`, `agents/debugger.md`, `agents/documentation-writer.md` | These four agents are referenced by name from every other feature's skills; they are the minimum set required for "spawn a specialized agent" to work at all. |
| `core-conventions` | `CLAUDE.md` `## Conventions` section (Conventional Commits with scope), `CLAUDE.md` `## Security` section | Operational baseline expected by every other feature. |

**Optional features (default enabled where they correspond to today's behavior, prompted on first install only):**

| Feature id | What it ships | Default | Rationale for being optional |
|---|---|---|---|
| `rfc-workflow` | `skills/rfc-new`, `skills/rfc-approve`, `skills/rfc-implement`, `skills/rfc-drop`, `skills/rfc-update`, `skills/rfc-read-feedback`, `skills/rfc-braindump`, `skills/rfc-consensus-review`, `agents/rfc-architect.md`, `docs/rfc-process.md`, `docs/rfcs/.gitkeep`, `CLAUDE.md` `## RFC Process` section, `docs/CONTRIBUTING.md` RFC section, agent-delegation table row "Architecture / RFCs" | enabled | Several smaller projects do not need the RFC overhead. |
| `refactor-workflow` | `skills/refactor`, `agents/refactoring-specialist.md`, agent-delegation table row "Refactoring (deliberate)" | enabled | The skill burns Opus tokens; teams on tight budgets may want it off. |
| `best-practices` | `skills/best-practices-extract`, `skills/best-practices-record`, `.claude/skills/best-practices-sync` (plugin-local, only in plugin checkout), `docs/BEST_PRACTICES.md` (base + universal + language additions + `## Project-Specific`), `.claude/settings.json` PreCompact and Stop hook entries that mention `/best-practices-extract`, agent-delegation row "Best practices" (added in this RFC) | enabled | Teams with their own learnings model do not need this; project-only or extraction-only variants are non-goals for this RFC. |
| `git-branch-cleanup` | `skills/git-branch-cleanup` | enabled | Niche utility; many users do not invoke it. |
| `github-artifacts` | `.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/*.md`, GitHub repo description update via `gh repo edit`, `.claude/settings.json` `enabledPlugins["github@claude-plugins-official"]` (gated by `installed` check) | enabled when `has_github = true`; disabled otherwise | Non-GitHub repos should not see `.github/` artifacts; GitHub repos may still opt out (e.g., the team uses a different CI). |
| `commit-doc-reminders` | `.claude/settings.json` PostToolUse hook (post-commit doc reminders for three matchers) | enabled | Some teams prefer quieter sessions and find the reminders noisy. |
| `prepush-quality-gate` | `.claude/settings.json` PreToolUse hook (pre-push fmt/lint/test gate) | enabled when at least one language with a standard gate is detected; disabled otherwise | Some projects run gates in CI only and prefer the local push to be fast. |
| `language-bp-blocks` | All language-specific best-practices additions in `docs/BEST_PRACTICES.md` (Rust, JS/TS, Python, Go, Svelte, Ruby, Rails, K8s/CUE, Terraform) | enabled (gated per detected language); disabled means only universal block ships | A consumer that wants the bare `## Pitfall`/`## Workflow`/`## Architecture`/Universal blocks can skip the language additions. Depends on `best-practices` being enabled (sub-feature). |
| `language-toolchain` | `mise.toml` (non-Rust), `rust-toolchain.toml` (Rust), language-specific `.gitignore` entries, language-specific `permissions.allow` entries in `settings.local.json` | enabled | Some consumers manage toolchain through other tools (asdf, nvm, manual) and do not want mise or rust-toolchain.toml committed. |

**Option A — The split above, with nine optional features (recommended).**

The nine optional features map to the actual axes of variation observed today (RFC vs no RFC, refactor vs no refactor, best practices vs no best practices, GitHub vs non-GitHub, hooks vs no hooks, language-specific best-practice blocks vs no language blocks, language toolchain vs no toolchain). The core set is intentionally minimal: anything that another feature references unconditionally, or anything that the plugin's identity depends on, is core.

**Option B — Make every skill its own feature (~14 toggles).**

Every skill, every agent, every hook entry is independently toggleable. Maximum granularity but maximum prompt count on first install — and most of the granularity is meaningless because skills cluster naturally (the eight `/rfc-*` skills are useful only together; the two best-practices skills share a destination).

Rejected because the first-install prompt becomes a wall of 14+ questions for a benefit (decomposed RFC vs decomposed best-practices vs decomposed git-branch-cleanup) no real consumer has expressed.

**Option C — A coarser "starter | full" preset model.**

Two predefined feature bundles: `starter` (core only) and `full` (core + every optional feature). The user picks one; future presets can be added.

Rejected because it forces every consumer into one of two boxes. A consumer who wants "RFC workflow but no best-practices" or "everything except `/refactor`" has to either pick `full` and accept the unwanted feature or pick `starter` and miss several wanted features. The presets become a substitute for the actual decision the user needs to make.

**Recommendation: Option A.** The nine-toggle set captures the real axes of variation; the core set is small enough that it never needs reasoning about. If usage shows that two toggles are virtually never separately chosen (e.g., `refactor-workflow` and `best-practices` are always toggled together), a future RFC can merge them — easier than splitting a coarse-grained design after the fact.

### Decision 2 — Where is the toggle state stored?

**Option A — A `features` block in `.claude/settings.json` (recommended).**

`.claude/settings.json` is already the project's Claude Code config, already written by `/sync`, already in version control. Adding a top-level `features` key keeps all sync-relevant state in one file. Schema:

```json
{
  "extraKnownMarketplaces": { ... },
  "enabledPlugins": { ... },
  "features": {
    "bytewyrd": {
      "manifest_version": "2026-05-12",
      "enabled": [
        "rfc-workflow",
        "refactor-workflow",
        "best-practices",
        "git-branch-cleanup",
        "github-artifacts",
        "commit-doc-reminders",
        "prepush-quality-gate",
        "language-bp-blocks",
        "language-toolchain"
      ],
      "disabled": []
    }
  },
  "hooks": { ... }
}
```

- The keys under `features` are *plugin names* (only `bytewyrd` today). This keeps the design forward-compatible with other plugins shipping their own feature catalogues.
- `manifest_version` is the date-stamped version of the plugin's feature catalogue (`bytewyrd@2026-05-12` etc.) used to detect "the plugin added a new feature since last sync." When the consumer's stored `manifest_version` is older than the plugin's current catalogue, `/sync` prompts only for the *new* features (additions to `enabled` + additions to `disabled` are the diff; existing enabled and disabled members are preserved).
- `enabled` and `disabled` together must cover every feature in the current plugin catalogue. A feature that is in neither list (because it is brand new) triggers the "new feature, ask" flow.
- An empty `features` block (or missing block) on first run triggers the "first-install, ask all" flow.

This is the **single source of truth** for "what does this project want enabled"; every other piece of config (the manifest, the diff engine, the hook table builder) reads from it.

**Option B — A separate `.claude/bytewyrd-features.json` file.**

Sidecar file dedicated to the plugin's feature state. Avoids putting plugin-specific config in the more general `settings.json`.

Rejected because it adds a file that the diff engine must also track, that the user must also know about, and that may go out of sync with `settings.json`'s `enabledPlugins`. Storing the choice in `settings.json` (where the user already expects to find Claude Code configuration) is friendlier and reuses an existing tracked artifact.

**Option C — Encode features in `enabledPlugins` (sub-key syntax).**

`enabledPlugins` already exists as a map of plugin id → boolean. Extend the value to be either a boolean (today's behavior) or an object with per-feature toggles:

```json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": {
      "rfc-workflow": true,
      "refactor-workflow": false,
      ...
    }
  }
}
```

Rejected because `enabledPlugins` is a Claude Code-owned schema field, not a bytewyrd-owned one. Claude Code may reject or silently ignore non-boolean values (the SDK docs treat `enabledPlugins` values as `boolean | "always" | "never"`); coupling the bytewyrd feature state to a foreign-system schema risks the plugin's config becoming invalid on a Claude Code version bump. The dedicated `features` block is bytewyrd-owned by design.

**Recommendation: Option A.** A top-level `features.<plugin-name>` block keeps the state in the file the user already edits, in a namespace owned by the plugin, with a `manifest_version` that makes "new features added since last sync" detectable. The interaction with `enabledPlugins["bytewyrd@bytewyrd"]` is one-directional: if the plugin itself is not enabled (the consumer removed bytewyrd entirely), the `features` block becomes inert; if the plugin is enabled, `/sync` reads the `features` block to decide what to write.

### Decision 3 — How do features declare their boundaries?

A feature must declare which artifacts (skills, agents, sections of `CLAUDE.md`, hook entries in `settings.json`, file templates, etc.) belong to it. The declaration must be machine-readable so the diff engine can include or exclude artifacts cleanly.

**Option A — Per-artifact `feature:` field in the bootstrap manifest, plus `feature:` frontmatter on skills (recommended).**

Every entry in `.claude-plugin/bootstrap-manifest.json` (introduced by RFC `2026-05-10-sync-interactive-diff`) gains a `feature` field whose value is one of the core or optional feature ids. Example:

```json
{
  "upstream_key": "bytewyrd/docs/rfc-process.md@v1",
  "feature": "rfc-workflow",
  "source": ".claude-plugin/scripts/templates/docs/rfc-process.md.tpl",
  "target": "docs/rfc-process.md",
  "extension_strategy": "region",
  ...
}
```

Skills (`skills/*/SKILL.md`) gain an optional `feature:` field in the YAML frontmatter:

```yaml
---
name: rfc-new
description: ...
feature: rfc-workflow
---
```

Skills without a `feature:` field are assumed to be `feature: core` (always loaded). This is consistent with the conservative-default principle: a skill that does not declare a feature continues to ship.

Claude Code discovers skills by walking `skills/`; to make a skill conditionally available we need a runtime gate. Two complementary mechanisms (both required because they cover different paths):

1. **Sync-time exclusion.** `/sync` reads the consumer's `features` block; for any plugin-shipped skill whose `feature:` frontmatter value is not in `enabled`, the skill's bootstrap-manifest entry for any consumer-side artifact it writes is filtered out of the diff and apply phase. This handles the "files this skill wants to write to the consumer's repo" case (the RFC skills writing `docs/rfc-process.md`, `docs/rfcs/.gitkeep`, etc.).
2. **Runtime gate.** Each plugin-shipped skill that belongs to an optional feature begins its body with a small preamble that checks the consumer's `features` block before doing real work. If the feature is disabled, the skill prints "This skill is part of the `<feature-id>` feature, which is disabled for this project. Run `/sync` to re-enable." and exits. This handles the "the skill is still on disk but the user invoked it anyway" case.

Non-skill artifacts (agents, sections in `CLAUDE.md`, hook entries in `settings.json`) are tagged in the bootstrap manifest only — they have no runtime; sync-time filtering is sufficient.

For `CLAUDE.md` and `docs/BEST_PRACTICES.md`, which use `extension_strategy: "section"` (per RFC `2026-05-10-sync-interactive-diff`), the manifest already lists `owned_sections`; each owned section gets a `feature` tag in a parallel list `section_features`:

```json
{
  "upstream_key": "bytewyrd/CLAUDE.md@v1",
  "feature": "core-identity",
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
  "section_features": [
    "core-identity",
    "core-identity",
    "core-agent-delegation",
    "core-evidence-based",
    "rfc-workflow",
    "core-evidence-based",
    "core-identity",
    "core-identity",
    "core-conventions",
    "core-conventions"
  ]
}
```

When the consumer disables `rfc-workflow`, the `## RFC Process` section is filtered out of the rendered `CLAUDE.md` (and the section_features parallel array makes the mapping unambiguous). The artifact's top-level `feature` field (`core-identity` in this case) declares the *artifact itself* as core — `CLAUDE.md` is always written regardless of which optional features are enabled — but individual sections can be tagged with optional features.

For `settings.json` hooks (already `structured` strategy with `owned_paths` like `hooks.PostToolUse[]:_meta.bytewyrd_hook_id`), each plugin-shipped hook entry carries a `_meta.bytewyrd_feature` field alongside `_meta.bytewyrd_hook_id`. The diff engine filters out hooks whose `_meta.bytewyrd_feature` is not in `enabled`.

For per-language additions to `docs/BEST_PRACTICES.md` (Rust, JS/TS, Python, etc.), each language block becomes its own section with its own feature tag (`language-bp-blocks` for all of them, gated by both `language-bp-blocks` enabled *and* the relevant `has_<language>` detection flag).

For non-skill files written by sub-features that have no skill component (`github-artifacts`, `commit-doc-reminders`, `prepush-quality-gate`), the manifest entry's `feature` field is the sole declaration.

A dedicated **features manifest** (`.claude-plugin/features.toml`) enumerates the plugin's feature catalogue with metadata: id, display name, description (shown in the AskUserQuestion prompt), default enabled/disabled, dependencies on other features, and optional handles a feature consumes from other features:

```toml
[features.rfc-workflow]
display_name = "RFC workflow"
description = "Design-before-implementation workflow with /rfc-* commands, docs/rfc-process.md, and docs/rfcs/."
default = "enabled"
provides = ["rfc-process"]
consumes = []

[features.refactor-workflow]
display_name = "Refactor workflow"
description = "/refactor command spawning refactoring-specialist agent on Opus with max effort."
default = "enabled"
provides = ["refactor"]
consumes = ["best-practices?"]  # soft handle: refactor mentions /best-practices-extract in its description; degrades gracefully if absent

[features.best-practices]
display_name = "Best practices"
description = "/best-practices-extract and /best-practices-record, docs/BEST_PRACTICES.md with universal sections."
default = "enabled"
provides = ["best-practices"]
consumes = []

[features.git-branch-cleanup]
display_name = "Git branch cleanup"
description = "/git-branch-cleanup for pruning stale local, remote, and worktree branches."
default = "enabled"
provides = []
consumes = []

[features.github-artifacts]
display_name = "GitHub artifacts"
description = ".github/workflows/ci.yml, PR template, issue templates, gh repo edit. Gated on has_github=true."
default = "enabled-if-github"  # special: enabled by default but suppressed if has_github = false
provides = []
consumes = []

[features.commit-doc-reminders]
display_name = "Commit / push doc reminders"
description = "PostToolUse hooks that prompt to update ARCHITECTURE.md / CONTRIBUTING.md / README.md after commits."
default = "enabled"
provides = []
consumes = []

[features.prepush-quality-gate]
display_name = "Pre-push quality gate"
description = "PreToolUse hook running fmt + lint + test on git push for detected languages."
default = "enabled-if-language"  # gated on detected language with a standard gate
provides = []
consumes = []

[features.language-bp-blocks]
display_name = "Language best-practice blocks"
description = "Per-language sections appended to docs/BEST_PRACTICES.md (Rust, JS/TS, Python, Go, Svelte, Ruby/Rails, K8s/CUE, Terraform)."
default = "enabled"
provides = []
consumes = ["best-practices"]  # hard: cannot exist without best-practices

[features.language-toolchain]
display_name = "Language toolchain pinning"
description = "mise.toml and rust-toolchain.toml committing language version pins. Per-language permissions in settings.local.json."
default = "enabled"
provides = []
consumes = []
```

Dependency semantics:

- `consumes = ["x"]` — hard dependency. If `x` is disabled, this feature cannot be enabled. The /sync prompt enforces this: if the user tries to enable a feature whose hard dependency is disabled, the prompt asks "Enable X too?" or rejects the selection.
- `consumes = ["x?"]` — soft dependency. The feature works fine without `x`, but it references `x` in some user-visible way (a prompt body, a description, etc.). At apply time, the diff engine substitutes a placeholder or removes the reference; at runtime, the skill checks for `x`'s presence and adjusts its prose.
- `provides = ["y"]` — declares a soft handle the feature offers. Other features can reference `y` via `consumes`; the resolver matches `provides` to `consumes`.
- `default = "enabled"` / `"disabled"` / `"enabled-if-github"` / `"enabled-if-language"` — initial value on first install. The conditional variants are evaluated against the Step 1/Step 3 detections (`has_github`, presence of any language with a standard gate).

This features manifest is the **single source of truth** for the feature catalogue. The bootstrap manifest's `feature:` fields refer to ids declared here; skills' `feature:` frontmatter refers to ids declared here; the `/sync` AskUserQuestion uses the `display_name` and `description` from here.

**Option B — Inline feature declaration in each artifact.**

Each skill's frontmatter, each agent's frontmatter, each hook entry's `_meta` block declares the feature. No central `features.toml`.

Rejected because it spreads the catalogue across 30+ files. A reader who wants to know "what features does this plugin have?" must crawl every file. Bug-prone: if two files declare the same feature id with conflicting metadata (display name, description, default), the conflict has no canonical winner. A central manifest is the only place where the catalogue can be edited once.

**Option C — Hard exclusion at the file-system level (gitignore-style exclude file).**

The consumer ships an `.bytewyrd-exclude` file with feature ids to exclude; `/sync` reads it before applying.

Rejected because it does not solve the "feature declares its own boundaries" problem — it only solves the "consumer says no to these features" problem. The boundary declaration must come from the plugin (the consumer cannot reasonably know which artifacts belong to which feature); a central plugin-owned catalogue is the right place.

**Recommendation: Option A.** The combination of (i) a top-level `feature` field on every bootstrap-manifest artifact, (ii) optional per-section / per-hook tags via the parallel arrays, (iii) `feature:` frontmatter on every skill that belongs to an optional feature, and (iv) the central `features.toml` is the smallest mechanism that decomposes the plugin's "what does the plugin ship" question along the feature axis with no ambiguity. The diff engine's filtering logic becomes a small predicate: "is this artifact's feature in the consumer's enabled set?" — and the AskUserQuestion logic reads its question set directly from `features.toml`.

### Decision 4 — How does `/sync` surface the feature menu?

The interaction must handle four cases:

1. **First install, no `features` block in `settings.json`.** Ask for every optional feature in one AskUserQuestion. Most users hit this case once.
2. **Re-run, `features` block present, plugin manifest version matches stored version.** Skip the prompt entirely. Apply the stored set.
3. **Re-run, `features` block present, plugin manifest version newer (new features were added).** Ask only about the new features in one AskUserQuestion. Don't re-prompt for previously-decided features.
4. **User explicitly wants to revisit choices.** A new sub-skill `/sync-features` (out of scope for the core RFC implementation; captured as follow-up in Risks) lets the user re-open the feature selection. For now, the user edits `.claude/settings.json` by hand or deletes the `features` block (which triggers case 1 on the next `/sync`).

**Option A — One AskUserQuestion with one question per optional feature; defaults pre-selected per the features.toml `default` field (recommended).**

Each question is a yes/no for one feature; the "suggestion" option is the default; the user can flip to the other option. Display name and description from `features.toml` populate the question header and the option labels.

This matches the existing `/sync` Step 2c pattern (one AskUserQuestion with multiple questions in one call — that step already does six questions). With nine optional features (the recommendation in Decision 1), the user sees a single AskUserQuestion with up to nine questions and answers all in one prompt (conditional features like `github-artifacts` and `prepush-quality-gate` may be silently defaulted and omitted if their conditions are not met, so the actual question count may be fewer).

For case 3 (new features added since last sync), the question set is filtered down to only the new features — typically one or two questions per plugin release.

For features with conditional defaults (`enabled-if-github`, `enabled-if-language`), `/sync` evaluates the condition before building the prompt; if the condition is false, the feature is silently set to `disabled` and is not asked.

For features with hard dependencies (`consumes = ["x"]`), `/sync` checks consistency after the user submits: if the user selected feature A but feature A depends on disabled feature B, surface a follow-up question "A requires B — enable B too, or skip A?". This is rare in practice (the recommended dependency graph has only one hard dependency: `language-bp-blocks → best-practices`).

**Option B — A wizard with one AskUserQuestion per feature.**

Each feature gets its own prompt. Maximum focus per decision but maximum friction (7+ prompts on first install).

Rejected because users tire by the third or fourth prompt and start rubber-stamping. The single-call-multiple-question pattern (already used by `/sync` Step 2c) is well-supported by AskUserQuestion and proven on the existing six-question first-run prompt.

**Option C — Auto-enable every default and only prompt when a conditional default cannot be satisfied.**

Skip the prompt entirely; consumers who want to disable features edit `settings.json` after the fact.

Rejected because the explicit prompt is the point — it makes the choice visible. A user who never sees the prompt does not know the choice was offered. The whole motivation of this RFC is to convert the implicit all-or-nothing into an explicit opt-in/opt-out.

**Recommendation: Option A.** One AskUserQuestion with one question per optional feature, defaults pre-selected per `features.toml`. Re-runs are silent unless the catalogue has new features. The user can revisit by editing `settings.json` directly (with a future `/sync-features` slash command as a convenience).

## Drawbacks

- **Larger surface to maintain.** The plugin gains `features.toml` (the catalogue), a `feature` field on every bootstrap-manifest entry, `feature:` frontmatter on every optional-feature skill, runtime feature checks at the top of every optional-feature skill body, and the new feature-prompt step in `/sync`. The plugin already gained meaningful surface from RFC `2026-05-10-sync-interactive-diff` (the bootstrap manifest itself); layering features on top doubles the metadata weight per artifact. **Mitigation:** the metadata is declarative (one line per artifact in the manifest, one line per skill in frontmatter, one TOML stanza per feature). The runtime check at the top of each skill is ~5 lines of identical pattern (read `settings.json`, check `features.bytewyrd.enabled`, exit if missing). The features.toml is small (~70 lines) and read once per `/sync` run.

- **Cross-feature references must be re-engineered.** Today, skills and templates freely reference each other (`/refactor` mentions `/best-practices-extract`, `CLAUDE.md` mentions every agent). After this RFC, every cross-feature reference must check whether the referenced feature is enabled and degrade gracefully if not. **Mitigation:** the `provides` / `consumes` graph in `features.toml` makes cross-feature handles explicit at design time. Skills consult the same `settings.json` features block at runtime and substitute or remove the reference. The cross-reference inventory (in Current state) is the migration checklist — each item is touched once, and the runtime gate centralizes the check.

- **First-install prompt is longer.** Today, `/sync` Step 2c asks 6 questions (project identity); this RFC adds Step 2d with ~7 more questions (feature selection). 13 questions on first install is not nothing. **Mitigation:** every feature question has a clear default; the user can hit "accept all defaults" by clicking through. The defaults match today's behavior (every optional feature defaults to enabled if its conditions are met), so a user who wants the current plugin behavior pays roughly the same time cost as today's six-question Step 2c. The new prompts only matter for users who want to deviate from defaults — which is exactly the audience this RFC is for.

- **Re-runs that introduce a new feature still prompt.** Every plugin release that adds an optional feature will trigger one AskUserQuestion on the next `/sync` per consumer. Some plugin releases will add a feature that ~every consumer would say "yes" to. **Mitigation:** feature additions are visible plugin events. The prompt is one question, one click. The alternative — silently auto-enabling a new feature — would mean a future plugin update could ship a behavior change (new hooks, new files) without the consumer being aware. Visibility is the right default for this kind of change.

- **Disabling a feature does not retroactively delete already-installed artifacts.** A consumer who runs `/sync` with `rfc-workflow` enabled and then re-runs `/sync` with `rfc-workflow` disabled does not get `docs/rfc-process.md` deleted. The diff/apply engine treats the previously-written file as a "local-only" artifact (the user has the file but the plugin no longer ships it for them). **Mitigation:** the report explicitly calls out "Feature `<id>` is now disabled. The following previously-installed files are still on disk: ...". The user can delete them manually. Automated deletion is unsafe (the user may have edited the files and not want them gone); the explicit list is the friendliest middle ground. A future RFC could add a `/sync-features --remove-stale` flag if user demand warrants.

- **Coupling to RFC `2026-05-10-sync-interactive-diff` (Draft).** This RFC's diff filtering depends on the bootstrap manifest format that the other RFC introduces. If the other RFC is dropped or substantially redesigned, this RFC's manifest extensions must be redone. **Mitigation:** the dependency is acknowledged in "Relationship to other RFCs" below; if `2026-05-10-sync-interactive-diff` is dropped, this RFC's scope shrinks to "feature toggles applied at file-creation time," which is implementable against the current sync skill body (with more imperative logic in the skill but no manifest). The features.toml / `feature:` frontmatter / `features` block in `settings.json` design is robust to either underlying flow.

- **Skill discovery still walks the directory.** Claude Code discovers skills by walking `skills/`; a disabled-feature skill is still on disk and could still be auto-suggested by the planner. The runtime gate at the top of the skill body prevents harmful execution, but the skill still appears in the catalogue. **Mitigation:** the runtime gate prints a clear "this skill is part of disabled feature <id>" message and exits. The planner-side visibility of disabled skills is acceptable cost — disabling a feature means "I do not want the artifacts and behavior," not "I want the skill removed from Claude Code's catalogue." Disabled skills may still be proactively suggested by Claude's planner based on context; the user who acts on the suggestion will receive the 'disabled' message. A future Claude Code API for conditional skill exposure would solve this cleanly.

- **The `manifest_version` versioning is hand-maintained.** The plugin's `features.toml` carries a `manifest_version` (the date-stamp of the catalogue); the consumer's `settings.json` `features.bytewyrd.manifest_version` records the last-seen version. A plugin maintainer who adds a new feature and forgets to bump `manifest_version` ships a release where consumers will not be prompted for the new feature. **Mitigation:** the `build-manifest.sh` script (from RFC `2026-05-10-sync-interactive-diff`) is extended to detect a feature added to `features.toml` without a corresponding `manifest_version` bump and fail the pre-commit hook. The check is exactly: if any feature in `features.toml` was added/removed/renamed since the last committed version, `manifest_version` must change.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.claude-plugin/features.toml` | The feature catalogue — one stanza per core and optional feature, with `display_name`, `description`, `default`, `consumes`, `provides`, and a top-level `manifest_version`. Single source of truth for the catalogue. |
| Modify | `.claude-plugin/bootstrap-manifest.json` | Add a `feature` field (required) to every artifact entry. For `extension_strategy: "section"` artifacts (`CLAUDE.md`, `docs/BEST_PRACTICES.md`), add a parallel `section_features` array of the same length as `owned_sections`. For `extension_strategy: "structured"` artifacts with id-keyed array paths (`settings.json` hooks), every hook entry's `_meta` block gains a `bytewyrd_feature` field. |
| Modify | `.claude-plugin/scripts/build-manifest.sh` | Add a validation pass that (a) every `feature` value referenced in the manifest exists in `features.toml`, (b) every feature id in `features.toml` is the target of at least one manifest entry, and (c) if any feature added/removed since the last committed `features.toml`, the `manifest_version` must change. Fails the pre-commit hook on violations. |
| Modify | `.claude-plugin/CLAUDE.md` | Add a "Modular features" subsection explaining the feature catalogue, the bootstrap-manifest extensions, the cross-feature dependency rules, and the maintainer workflow for adding a new feature. |
| Modify | `skills/sync/SKILL.md` | Insert Step 2d (feature selection) between Step 2c (identity collection) and Step 3 (component detection). Modify Step 5 / Step 4-apply (per RFC `2026-05-10-sync-interactive-diff`) to filter artifacts by the consumer's enabled-feature set. Modify Step 8 report to show feature status and stale-artifact warnings. |
| Modify | `skills/rfc-*/SKILL.md` (all eight RFC skills) | Add `feature: rfc-workflow` to frontmatter. Add a 5-line runtime feature check at the top of the body that reads `.claude/settings.json`, checks `features.bytewyrd.enabled` for `rfc-workflow`, and exits with a clear message if not enabled. |
| Modify | `skills/refactor/SKILL.md` | Add `feature: refactor-workflow` to frontmatter. Add the runtime feature check. Update the description text to soft-reference `/best-practices-extract` only when the `best-practices` feature is also enabled (runtime check before the description is emitted; alternative formulation if disabled). |
| Modify | `skills/best-practices-extract/SKILL.md` and `skills/best-practices-record/SKILL.md` | Add `feature: best-practices` to frontmatter. Add the runtime feature check. |
| Modify | `skills/git-branch-cleanup/SKILL.md` | Add `feature: git-branch-cleanup` to frontmatter. Add the runtime feature check. |
| Modify | `.claude/skills/best-practices-sync/SKILL.md` | Add `feature: best-practices` to frontmatter (this is a plugin-local maintainer skill — the feature check is a safety net for cases where the plugin checkout has `best-practices` disabled, which is an unusual maintainer configuration but possible). |
| Create | `.claude-plugin/scripts/templates/features/` | Directory holding the feature-specific section templates: `claude-md-rfc-process.tpl`, `claude-md-refactor-row.tpl`, `claude-md-best-practices-row.tpl`, `best-practices-extract-hook.tpl`, `commit-doc-reminder-hook.tpl`, `prepush-gate-hook.tpl`, and the per-language best-practices blocks. Sub-templates referenced from the main CLAUDE.md.tpl / BEST_PRACTICES.md.tpl / settings.json.tpl via a `<feature-include:feature-id>...</feature-include:feature-id>` block-comment pair that the renderer expands or strips based on the consumer's enabled set. |
| Modify | `.claude-plugin/scripts/templates/CLAUDE.md.tpl`, `BEST_PRACTICES.md.tpl`, `settings.json.tpl`, `docs/CONTRIBUTING.md.tpl` | Wrap every feature-specific section in `<feature-include:feature-id>...</feature-include:feature-id>` block comments. The renderer (a function in `skills/sync/SKILL.md` per RFC `2026-05-10-sync-interactive-diff`) expands these conditionally based on the consumer's enabled set. |
| Delete | (none) | No files are removed. Disabling a feature on a fresh install means the relevant artifacts are never written; disabling on a re-run leaves previously-written artifacts in place. |

### Feature catalogue schema

`.claude-plugin/features.toml`:

```toml
manifest_version = "2026-05-12"

[features.core-identity]
kind = "core"
display_name = "Core: project identity"
description = "docs/project-brief.md, CLAUDE.md skeleton, README.md skeleton, .gitignore base. Required."
default = "enabled"
provides = []
consumes = []

[features.core-claude-config]
kind = "core"
display_name = "Core: Claude Code config"
description = ".claude/settings.json and .claude/settings.local.json minimal — plugin enablement, web/git/exa/firefox permissions."
default = "enabled"
provides = []
consumes = []

[features.core-evidence-based]
kind = "core"
display_name = "Core: evidence-based development"
description = "CLAUDE.md Evidence-Based Development and Tool Usage sections."
default = "enabled"
provides = []
consumes = []

[features.core-agent-delegation]
kind = "core"
display_name = "Core: agent delegation"
description = "CLAUDE.md Agent delegation table, agents/feature-engineer, agents/code-reviewer, agents/debugger, agents/documentation-writer."
default = "enabled"
provides = ["agent-delegation"]
consumes = []

[features.core-conventions]
kind = "core"
display_name = "Core: conventions"
description = "CLAUDE.md Conventions and Security sections."
default = "enabled"
provides = []
consumes = []

[features.rfc-workflow]
kind = "optional"
display_name = "RFC workflow"
description = "Design-before-implementation via /rfc-new, /rfc-approve, /rfc-implement, /rfc-drop, /rfc-update, /rfc-read-feedback, /rfc-braindump, /rfc-consensus-review. Includes docs/rfc-process.md, docs/rfcs/, agents/rfc-architect."
default = "enabled"
provides = ["rfc-process"]
consumes = ["agent-delegation"]

[features.refactor-workflow]
kind = "optional"
display_name = "Refactor workflow"
description = "/refactor spawns refactoring-specialist agent on Opus with max effort. Deliberately expensive — for genuine refactoring passes, not tiny renames."
default = "enabled"
provides = ["refactor"]
consumes = ["agent-delegation", "best-practices?"]

[features.best-practices]
kind = "optional"
display_name = "Best practices"
description = "/best-practices-extract, /best-practices-record, docs/BEST_PRACTICES.md with universal sections (Pitfall, Workflow, Claude Code, Code Design, Code Style, Architecture, Testing, Documentation, Security, Error Handling)."
default = "enabled"
provides = ["best-practices"]
consumes = []

[features.git-branch-cleanup]
kind = "optional"
display_name = "Git branch cleanup"
description = "/git-branch-cleanup for pruning stale local branches, gone remotes, and worktrees of deleted branches."
default = "enabled"
provides = []
consumes = []

[features.github-artifacts]
kind = "optional"
display_name = "GitHub artifacts"
description = ".github/workflows/ci.yml, PR template, issue templates (story, bug, spike), and gh repo edit. Suppressed automatically on non-GitHub remotes."
default = "enabled-if-github"
provides = []
consumes = []

[features.commit-doc-reminders]
kind = "optional"
display_name = "Commit / push doc reminders"
description = "PostToolUse hook prompts to update ARCHITECTURE.md / CONTRIBUTING.md / README.md / docs/project-brief.md after git commit and after MCP push_files / create_or_update_file. Stop hook reminds at session end."
default = "enabled"
provides = []
consumes = []

[features.prepush-quality-gate]
kind = "optional"
display_name = "Pre-push quality gate"
description = "PreToolUse hook on Bash(git push*) runs fmt + lint + test for every detected language with a standard gate. Blocks push on failure."
default = "enabled-if-language"
provides = []
consumes = []

[features.language-bp-blocks]
kind = "optional"
display_name = "Language best-practices"
description = "Per-language sections appended to docs/BEST_PRACTICES.md: Rust, JS/TS, Python, Go, Svelte, Ruby, Rails, Kubernetes/CUE/kapply, Terraform/Terragrunt. Each block ships only if the language is detected."
default = "enabled"
provides = []
consumes = ["best-practices"]

[features.language-toolchain]
kind = "optional"
display_name = "Language toolchain pinning"
description = "mise.toml for non-Rust languages, rust-toolchain.toml for Rust, per-language entries in .gitignore and settings.local.json permissions."
default = "enabled"
provides = []
consumes = []
```

**Field semantics:**

- `manifest_version` (top-level) — date-stamp identifying this version of the feature catalogue. The consumer's `settings.json` records this value when the user makes choices; a future `/sync` with a higher `manifest_version` knows the catalogue has changed and prompts for new features. Format: `YYYY-MM-DD`; bumped by the maintainer when a feature is added, removed, or renamed.
- `kind` — `"core"` (always enabled, not prompted) or `"optional"` (prompted on first install or when newly added).
- `display_name` — string shown as the question header in the first-install AskUserQuestion.
- `description` — string shown as the question body / option label hint in AskUserQuestion. Should explain what the feature ships in user-visible terms.
- `default` — `"enabled"`, `"disabled"`, `"enabled-if-github"`, `"enabled-if-language"`. Conditional variants are evaluated against Step 1/Step 3 detections.
- `provides` — list of soft handles this feature offers to other features (used by `consumes` resolution). A `provides` handle should name the *capability* the feature offers, not the feature itself. Use the feature id as the handle only when the feature and the capability are synonymous (as with `best-practices`). For all other cases, pick a noun that names what the feature provides (e.g., `rfc-workflow` provides the `rfc-process` capability).
- `consumes` — list of soft (`"x?"`) or hard (`"x"`) dependencies. Hard dependencies must be satisfied for the feature to be enabled. A hard dependency whose provider has `kind = 'core'` is always considered satisfied and is not subject to the conflict-resolution prompt.

### Consumer settings schema

`.claude/settings.json` gains a top-level `features` block:

```json
{
  "extraKnownMarketplaces": { "bytewyrd": { ... } },
  "enabledPlugins": { "bytewyrd@bytewyrd": true, ... },
  "features": {
    "bytewyrd": {
      "manifest_version": "2026-05-12",
      "enabled": [
        "rfc-workflow",
        "refactor-workflow",
        "best-practices",
        "git-branch-cleanup",
        "github-artifacts",
        "commit-doc-reminders",
        "prepush-quality-gate",
        "language-bp-blocks",
        "language-toolchain"
      ],
      "disabled": []
    }
  },
  "hooks": { ... }
}
```

- `features.bytewyrd.manifest_version` — the `manifest_version` of the plugin's `features.toml` at the time the consumer last made feature choices.
- `features.bytewyrd.enabled` — sorted list of feature ids the consumer wants enabled.
- `features.bytewyrd.disabled` — sorted list of feature ids the consumer wants disabled. Used to distinguish "user said no" from "user has not yet been asked" (a feature in neither list is a new feature, triggers the prompt).

Core features (`kind = "core"`) are *not* listed in either array — they are always enabled and the catalogue treats them as implicit. This keeps the `enabled` array short and the file readable.

The schema is enforced as a `structured` artifact in the bootstrap manifest with `owned_paths: ["features.bytewyrd"]`. The diff engine treats edits inside `features.bytewyrd` as user-owned (since the user's preferences live there); plugin updates to `features.bytewyrd.manifest_version` happen via the apply phase, not the diff phase. The arrays are written sorted ascending so the file diffs cleanly across runs. `features.bytewyrd` is written as the computed output of Step 2d (the merged result of user choices plus plugin catalogue state), not from a static template value; the apply phase uses Step 2d's `features_block` directly for this path.

### Bootstrap manifest extensions

Every artifact entry in `.claude-plugin/bootstrap-manifest.json` gains:

- `feature` (required, string) — the id of the feature this artifact belongs to. Must match a feature in `features.toml`.

Artifacts with `extension_strategy: "section"` gain:

- `section_features` (required when `owned_sections` is present, array of strings, same length as `owned_sections`) — parallel array mapping each owned section to its feature id.

Artifacts with `extension_strategy: "structured"` and id-keyed array paths (e.g., `hooks.PostToolUse[]:_meta.bytewyrd_hook_id`) gain a convention: every hook entry the plugin contributes carries an additional `_meta.bytewyrd_feature` field. The diff engine filters hook entries by both `_meta.bytewyrd_hook_id` (for id-based merge per the structured strategy) *and* `_meta.bytewyrd_feature` (for feature gating). When a feature is disabled, hooks tagged with that feature are excluded from the rendered plugin set; the merge then ensures any locally-present-but-now-excluded hook is removed only if `_meta.bytewyrd_hook_id` matched and `_meta.bytewyrd_feature` is now disabled (otherwise the local entry is preserved as user-customized).

Example manifest entries:

```json
{
  "artifacts": [
    {
      "upstream_key": "bytewyrd/CLAUDE.md@v1",
      "feature": "core-identity",
      "source": ".claude-plugin/scripts/templates/CLAUDE.md.tpl",
      "target": "CLAUDE.md",
      "template_sha": "...",
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
      "section_features": [
        "core-identity",
        "core-identity",
        "core-agent-delegation",
        "core-evidence-based",
        "rfc-workflow",
        "core-evidence-based",
        "core-identity",
        "core-identity",
        "core-conventions",
        "core-conventions"
      ],
      "templated": true,
      "template_inputs": ["project_name", "description", "project_slug", "component_roots", "installed_plugins", "enabled_features"]
    },
    {
      "upstream_key": "bytewyrd/docs/rfc-process.md@v1",
      "feature": "rfc-workflow",
      "source": ".claude-plugin/scripts/templates/docs/rfc-process.md.tpl",
      "target": "docs/rfc-process.md",
      "sha256": "...",
      "extension_strategy": "region",
      "region_end_marker": "<!-- END_UPSTREAM_CONTENT -->",
      "templated": false
    },
    {
      "upstream_key": "bytewyrd/docs/rfcs/.gitkeep@v1",
      "feature": "rfc-workflow",
      "source": ".claude-plugin/scripts/templates/docs/rfcs/.gitkeep",
      "target": "docs/rfcs/.gitkeep",
      "sha256": "...",
      "extension_strategy": "whole",
      "templated": false
    },
    {
      "upstream_key": "bytewyrd/docs/BEST_PRACTICES.md@v1",
      "feature": "best-practices",
      "source": ".claude-plugin/scripts/templates/docs/BEST_PRACTICES.md.tpl",
      "target": "docs/BEST_PRACTICES.md",
      "template_sha": "...",
      "extension_strategy": "section",
      "owned_sections": [
        "## Pitfall",
        "## Workflow",
        "## Claude Code",
        "## Code Design",
        "## Code Style",
        "## Architecture",
        "## Testing",
        "## Documentation",
        "## Security",
        "## Error Handling",
        "## Rust",
        "## JavaScript / TypeScript",
        "## Python",
        "## Go",
        "## Svelte",
        "## Ruby",
        "## Rails",
        "## Kubernetes / CUE / kapply",
        "## Terraform / Terragrunt"
      ],
      "section_features": [
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "best-practices",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks",
        "language-bp-blocks"
      ],
      "templated": true,
      "template_inputs": ["project_slug", "component_roots", "has_svelte", "has_ruby", "has_rails", "has_k8s_cue", "has_terraform", "enabled_features"]
    },
    {
      "upstream_key": "bytewyrd/.claude/settings.json@v1",
      "feature": "core-claude-config",
      "source": ".claude-plugin/scripts/templates/.claude/settings.json.tpl",
      "target": ".claude/settings.json",
      "template_sha": "...",
      "extension_strategy": "structured",
      "owned_paths": [
        "extraKnownMarketplaces.bytewyrd",
        "enabledPlugins.bytewyrd@bytewyrd",
        "enabledPlugins.github@claude-plugins-official",
        "enabledPlugins.context7@claude-plugins-official",
        "enabledPlugins.code-review@claude-plugins-official",
        "features.bytewyrd",
        "hooks.PreCompact[]:_meta.bytewyrd_hook_id",
        "hooks.PostToolUse[]:_meta.bytewyrd_hook_id",
        "hooks.Stop[]:_meta.bytewyrd_hook_id",
        "hooks.PreToolUse[]:_meta.bytewyrd_hook_id"
      ],
      "templated": true,
      "template_inputs": ["installed_plugins", "component_roots", "enabled_features"]
    }
  ]
}
```

### Templates with conditional feature blocks

The template renderer (defined in `skills/sync/SKILL.md` per RFC `2026-05-10-sync-interactive-diff`) is extended to recognize a new conditional-region syntax: `<feature-include:feature-id>...</feature-include:feature-id>` (block-comment-style for Markdown; `<!--feature-include:feature-id-->...<!--/feature-include:feature-id-->` to keep HTML-comment compatibility; `# feature-include:feature-id` / `# /feature-include:feature-id` for `.gitignore` and TOML; `"_meta": { "bytewyrd_feature": "feature-id" }` for JSON hook entries).

The renderer evaluates each `feature-include` block against the consumer's `enabled_features` (passed as a template input):

- If the feature is in `enabled_features`: emit the block content, strip the delimiter comments, recurse on inner content.
- If the feature is not in `enabled_features`: emit nothing, drop the entire block including its delimiters.

Example (`CLAUDE.md.tpl` excerpt):

```markdown
## Agent delegation

| Task | Agent |
|------|-------|
| New features | feature-engineer |
| Code reviews | code-reviewer |
<!--feature-include:refactor-workflow-->
| Refactoring (deliberate) | refactoring-specialist (via `/refactor`) |
<!--/feature-include:refactor-workflow-->
<!--feature-include:rfc-workflow-->
| Architecture / RFCs | rfc-architect |
<!--/feature-include:rfc-workflow-->
| Documentation | documentation-writer |
| Debugging | debugger |
<!--feature-include:best-practices-->
| Best practices | (skills: /best-practices-extract, /best-practices-record) |
<!--/feature-include:best-practices-->
```

When `rfc-workflow` is disabled, the rendered output omits the "Architecture / RFCs" row entirely. The renderer is recursive (nested blocks resolve inner-first); blocks for disabled features are stripped before the rest of the template is processed, so any `<placeholder>` references inside a stripped block are never expanded.

Settings.json hooks use the JSON `_meta.bytewyrd_feature` field directly (no comment syntax needed). The renderer iterates the hook arrays, dropping entries whose `_meta.bytewyrd_feature` is not in `enabled_features`. Existing `_meta.bytewyrd_hook_id` ids are preserved for the structured-merge identity logic.

For the BEST_PRACTICES.md per-language additions, the existing language detection (`has_rust`, `has_js`, etc.) is already part of the template. With this RFC, the per-language blocks are *additionally* gated by `language-bp-blocks` being enabled:

```markdown
<!--feature-include:language-bp-blocks-->
<!--lang:rust-start-->
## Rust

- **[<TODAY>]** _Rust_: ...
<!--lang:rust-end-->
<!--/feature-include:language-bp-blocks-->
```

The outer `feature-include` is the user-opt-out gate; the inner `<!--lang:rust-start-->...<!--lang:rust-end-->` is the existing detection-based gate from RFC `2026-05-10-sync-interactive-diff`. Both must be satisfied for the block to render.

### Step 2d — Feature selection (insertion into `/sync`)

Insert a new sub-step in `skills/sync/SKILL.md` between Step 2c (identity collection) and Step 3 (component structure detection):

```
### 2d — Feature selection

Read .claude/settings.json (if present); parse the features.bytewyrd block:
  consumer_manifest_version = settings.features.bytewyrd.manifest_version OR None
  consumer_enabled = set(settings.features.bytewyrd.enabled) OR set()
  consumer_disabled = set(settings.features.bytewyrd.disabled) OR set()

Read $PLUGIN_ROOT/.claude-plugin/features.toml:
  plugin_manifest_version = features.manifest_version
  plugin_optional_features = [f for f in features if f.kind == "optional"]

Compute new_features = { f.id for f in plugin_optional_features
                        if f.id not in consumer_enabled
                          and f.id not in consumer_disabled }

If new_features is empty AND consumer_manifest_version == plugin_manifest_version:
    enabled_features = consumer_enabled
    Print: "Features: <list>. (manifest version <X> — no changes.)"
    Skip to Step 3.

If new_features is non-empty (first install OR new features added):
    questions = []
    For each feature in plugin_optional_features in catalogue order:
        if feature.id in consumer_enabled or feature.id in consumer_disabled:
            continue       # previously decided — do not re-prompt
        # Evaluate conditional default.
        if feature.default == "enabled":
            suggestion = "Enable"
        elif feature.default == "disabled":
            suggestion = "Disable"
        elif feature.default == "enabled-if-github":
            suggestion = "Enable" if has_github else "Disable"
        elif feature.default == "enabled-if-language":
            suggestion = "Enable" if any_language_with_standard_gate else "Disable"
        questions.append({
            id: feature.id,
            header: feature.display_name,
            body: feature.description,
            suggestion: suggestion,
            options: ["Enable", "Disable"]
        })
    answers = AskUserQuestion(questions)
    For each (feature_id, answer) in zip(questions, answers):
        if answer == "Enable":
            consumer_enabled.add(feature_id)
        else:
            consumer_disabled.add(feature_id)

# Validate hard dependencies.
# Snapshot consumer_enabled before iterating — the loop body may mutate both sets.
for each feature in list(consumer_enabled):
    for dep in feature.consumes:
        if dep ends with "?": continue  # soft, no action
        # Resolve dep to the feature that provides it.
        provider = find_feature_providing(dep)
        if provider.kind == "core": continue  # core providers are always satisfied
        if provider.id in consumer_disabled:
            # Conflict: ask one-question follow-up.
            answer = AskUserQuestion([{
                header: f"Feature `{feature.id}` requires `{provider.id}`",
                body: f"`{feature.id}` consumes `{dep}` which is provided by `{provider.id}` — currently disabled.",
                options: [f"Enable `{provider.id}` too", f"Skip `{feature.id}`"]
            }])
            if answer.startswith("Enable"):
                consumer_disabled.remove(provider.id)
                consumer_enabled.add(provider.id)
            else:
                consumer_enabled.remove(feature.id)
                consumer_disabled.add(feature.id)

# Write back to settings.json (deferred to Step 5 apply phase; only the in-memory
# state is updated here so Step 3, 4, 5 can read it).
enabled_features = consumer_enabled
features_block = {
    "manifest_version": plugin_manifest_version,
    "enabled": sorted(consumer_enabled),
    "disabled": sorted(consumer_disabled)
}
```

`enabled_features` is added to the template inputs passed into every templated artifact's renderer call (per RFC `2026-05-10-sync-interactive-diff`). The features.json block writeback happens as part of the standard `settings.json` apply path — the `features.bytewyrd` owned path is updated to `features_block` during the structured-merge phase.

### Step 5 / apply-phase changes

Per RFC `2026-05-10-sync-interactive-diff`, Step 5 ("Create core files") is replaced by Step 4-apply (after the diff/confirm flow). The feature-aware filtering operates before the diff computation:

```
# After Step 2d, before pre-flight diff:
filtered_artifacts = [
    a for a in manifest.artifacts
    if a.feature in (core_feature_ids | enabled_features)
]

# Then run the pre-flight diff procedure on filtered_artifacts only.
```

For `extension_strategy: "section"` artifacts where the artifact itself is core but some owned sections belong to optional features: the artifact is included unconditionally; the renderer (during template expansion and during the canonical-form hash computation) strips sections whose `section_features` entry is not in `enabled_features`. The diff engine compares the post-strip canonical form to the local file's post-strip canonical form, so disabling a feature does not flag every owned section as a fast-forward — only the section the renderer would now emit differently changes hash.

For `extension_strategy: "structured"` artifacts where hook entries belong to optional features: the renderer drops entries with disabled `_meta.bytewyrd_feature`; the id-based merge then removes any locally-present entries whose `_meta.bytewyrd_hook_id` matches a now-dropped plugin entry (since "plugin no longer ships this hook" is structurally equivalent to "the hook was removed from the plugin"). User-added hook entries with no `_meta.bytewyrd_hook_id` are preserved per the existing structured-merge rules.

The stale-artifact warning runs at the end of Step 4 (the report phase): for each artifact in the *full* manifest (not filtered_artifacts) where the artifact's `feature` is disabled but the target file (or owned section) exists in the consumer repo:

```
Stale artifacts from disabled features:
  Feature `rfc-workflow` is disabled, but these files exist:
    - docs/rfc-process.md
    - docs/rfcs/.gitkeep
  Feature `best-practices` is disabled, but the `## Best practices` row of
    CLAUDE.md still references it.
  Run `rm -i docs/rfc-process.md` etc. to remove them, or re-enable
    the feature with `/sync` (delete features.bytewyrd from settings.json
    and re-run).
```

The warning is informational; no file is deleted automatically.

### Runtime feature check (skill body preamble)

Every optional-feature skill begins with this preamble. The preamble is identical across skills modulo the `<feature-id>` and `<skill-name>` substitution. It is added as the first executable step in the skill body (after the YAML frontmatter and the `# <Title>` heading).

Example for `skills/rfc-new/SKILL.md`:

```markdown
## Feature check

This skill is part of the `rfc-workflow` feature. Run this check first:

```bash
SETTINGS="$(git rev-parse --show-toplevel)/.claude/settings.json"
jq -e '.features.bytewyrd.enabled // [] | index("rfc-workflow")' "$SETTINGS" >/dev/null
```

If the command exits non-zero (the feature is disabled, the `features` block is absent, or `settings.json` does not exist), reply with:

> The `rfc-workflow` feature is disabled for this project. To enable it, run `/sync` and select "Enable" when prompted for the RFC workflow.

…then stop without performing any of the steps below.
```

The check uses `jq -e` (already a hard dependency from RFC `2026-05-10-sync-interactive-diff`); the exit code is 0 if the feature is in the enabled list, non-zero otherwise. The check is cheap (single jq invocation on a small JSON file) and lives at the top of every optional-feature skill body — including `.claude/skills/best-practices-sync/SKILL.md` for symmetry, even though it is a maintainer-only skill that is rarely invoked outside the plugin checkout.

For `/sync` itself, the preamble is *not* added — `/sync` must run even when no features are enabled, because it is the only way to enable them. `/sync` belongs implicitly to `core-claude-config` (no feature gate).

### Build-manifest validation

`.claude-plugin/scripts/build-manifest.sh` (from RFC `2026-05-10-sync-interactive-diff`) is extended with three validation passes that run before writing the regenerated manifest:

1. **Every `feature` referenced in the manifest exists in `features.toml`:**
   ```bash
   manifest_features=$(jq -r '.artifacts[].feature' "$MANIFEST" | sort -u)
   manifest_section_features=$(jq -r '.artifacts[].section_features // [] | .[]' "$MANIFEST" | sort -u)
   # Extract _meta.bytewyrd_feature values from hook entries in templated structured artifacts.
   # Hook entries are not enumerated inline in the manifest — they live in the template source.
   # The validation that every hook _meta.bytewyrd_feature matches a catalogue feature id is
   # performed by a separate pass over the template source files (templates/*.json.tpl), not
   # over the rendered manifest. TODO: implement template-source hook-feature validation in
   # build-manifest.sh as part of PR 1 implementation. For now, the in-manifest feature fields
   # (artifact-level and section-level) are validated; hook-entry feature ids are validated
   # during the template-rendering step in the apply phase (unknown feature id → renderer error).
   manifest_hook_features=""  # populated by template-source scan (implementation TODO)
   catalogue=$(grep -oP '^\[features\.\K[^\]]+' "$PLUGIN_ROOT/.claude-plugin/features.toml" | sort -u)
   unknown=$(comm -23 <(printf '%s\n' "$manifest_features" "$manifest_section_features" "$manifest_hook_features" | sort -u) <(echo "$catalogue"))
   if [[ -n "$unknown" ]]; then
       echo "manifest references features not declared in features.toml: $unknown" >&2
       exit 3
   fi
   ```

2. **Every feature in `features.toml` is the target of at least one manifest entry, section, or hook:**
   ```bash
   unused=$(comm -13 <(printf '%s\n' "$manifest_features" "$manifest_section_features" "$manifest_hook_features" | sort -u) <(echo "$catalogue"))
   if [[ -n "$unused" ]]; then
       echo "features declared but not referenced by any manifest artifact: $unused" >&2
       exit 3
   fi
   ```

3. **`manifest_version` must change when the feature set changes:**
   ```bash
   prev_features=$(git show HEAD:.claude-plugin/features.toml 2>/dev/null | grep -oP '^\[features\.\K[^\]]+' | sort -u)
   prev_version=$(git show HEAD:.claude-plugin/features.toml 2>/dev/null | grep -oP '^manifest_version = "\K[^"]+')
   curr_version=$(grep -oP '^manifest_version = "\K[^"]+' "$PLUGIN_ROOT/.claude-plugin/features.toml")
   if [[ "$prev_features" != "$catalogue" && "$prev_version" == "$curr_version" ]]; then
       echo "features.toml feature set changed since HEAD but manifest_version was not bumped" >&2
       exit 3
   fi
   ```

The pre-commit hook (`.claude-plugin/hooks/pre-commit/manifest-check.sh`, from the other RFC) runs `build-manifest.sh --check`, which now includes these three validations.

### Step 8 — Report (additions)

Per RFC `2026-05-10-sync-interactive-diff`, Step 8 reports outcomes by category. With feature toggles, the report adds two sub-sections after the artifact outcomes:

```
Features (manifest version 2026-05-12):
  Enabled:  rfc-workflow, refactor-workflow, best-practices, git-branch-cleanup,
            github-artifacts, commit-doc-reminders, prepush-quality-gate,
            language-bp-blocks, language-toolchain
  Disabled: (none)

  (Re-runs apply the stored selection silently. To revisit:
   delete the `features.bytewyrd` block in .claude/settings.json and re-run /sync.)

Stale artifacts from disabled features: (none)
```

If the user disables a feature on a re-run, the section becomes:

```
Stale artifacts from disabled features:
  Feature `rfc-workflow` is now disabled. Previously installed:
    - docs/rfc-process.md
    - docs/rfcs/.gitkeep
    - CLAUDE.md (## RFC Process section — preserved unchanged; will not be updated)
  These files are not removed automatically. Run `rm -i <path>` to clean up.
```

The CLAUDE.md note reflects the fact that the renderer strips the `## RFC Process` section from the *new* canonical form, but the previously-written file still contains the section. The diff engine classifies this as "the plugin would now write fewer sections" — for `section` strategy, this is treated as `fast_forward` for the artifact as a whole (the rendered hash changes), and applying the fast-forward removes the section. If the user wants to keep the section visible, they choose `Keep local` at the conflict prompt — same path as any other section-level disagreement.

### Cross-feature soft handle resolution

The `consumes = ["x?"]` soft handle is used by two features today:

1. `refactor-workflow` consumes `best-practices?` — the `/refactor` SKILL.md description and body mention `/best-practices-extract` as a typical follow-up. When `best-practices` is disabled, the renderer strips the mention.

   In `skills/refactor/SKILL.md`, the mention is wrapped:
   ```markdown
   <!--feature-include:best-practices-->
   After applying a refactor, consider running `/best-practices-extract` to capture any
   non-obvious learnings before they fade.
   <!--/feature-include:best-practices-->
   ```
   The skill file *itself* is a template processed by the same renderer at sync time, even though it lives in the plugin checkout. The build-manifest step renders the skill body once per known-feature-set permutation and ships the rendered version per consumer — except this is impractical for skills (since skills are loaded from the plugin checkout directly, not from per-consumer rendered output).

   The practical resolution: the renderer is run **only** on consumer-target artifacts (the files under `target:`). Skill bodies in the plugin checkout are *not* per-consumer rendered. Instead, each skill body checks the consumer's `features` block at runtime (the preamble described above) and emits or omits the soft-referenced content from its own prose at execution time. For the `refactor` skill, the description that mentions `/best-practices-extract` is kept as-is in the skill body; the skill, when it runs, checks if `best-practices` is enabled and adapts its output prose accordingly.

   Concretely, `skills/refactor/SKILL.md` includes a step in its body:
   ```markdown
   ## After the refactor

   Run `git status` and verify the diff is clean.

   ```bash
   SETTINGS="$(git rev-parse --show-toplevel)/.claude/settings.json"
   if jq -e '.features.bytewyrd.enabled // [] | index("best-practices")' "$SETTINGS" >/dev/null 2>&1; then
       echo "Run /best-practices-extract if any non-obvious learnings emerged."
   fi
   ```
   ```

   This means the *skill body in the plugin checkout* is identical across consumers; the runtime adaptation happens via shell predicates inside the skill body. Soft handles are runtime concepts, hard handles are sync-time concepts.

2. `github-artifacts` consumes `github-mcp-installed?` — soft reference to the `github@claude-plugins-official` plugin being installed. The hook entries the plugin contributes for MCP-based commits (`mcp__plugin_github_github__push_files`, `mcp__plugin_github_github__create_or_update_file`) are useful only if the GitHub MCP plugin is installed; if not, the hooks fire on event matchers that will never trigger and are merely noise. The `_meta.bytewyrd_hook_id` for these entries carries `_meta.bytewyrd_consumes = "github-mcp-installed?"`; the renderer drops the entry if the consumer's `installed_plugins` (per Step 1 of `/sync`) does not include `github@claude-plugins-official`.

   This is a soft handle resolved at sync time (filtering an output artifact) rather than at runtime (in a skill body) — the convention is: if the handle's value can be known at sync time, resolve at sync time; otherwise resolve at runtime. The `_meta.bytewyrd_consumes` field on a hook entry is the sync-time path.

Hard handles (`consumes = ["x"]` without `?`) are enforced in Step 2d's validation pass; the user cannot proceed with a hard dependency unsatisfied.

### Steps

The implementation proceeds in four PRs to keep diffs reviewable. Each PR is independently testable.

1. **PR 1 — Catalogue scaffolding.** Create `.claude-plugin/features.toml` with the full catalogue. Add the three validation passes to `build-manifest.sh`. Update the bootstrap manifest to add `feature` and `section_features` fields to every artifact (initially set core artifacts to `feature: core-*` and optional artifacts to their respective ids; the apply path is not yet feature-aware). Run the pre-commit hook to confirm the manifest validates. This PR introduces the catalogue but does not change runtime behavior — every artifact still applies because the renderer ignores `enabled_features` for now.

2. **PR 2 — Renderer support for `feature-include` blocks.** Extend the template renderer in `skills/sync/SKILL.md` to recognize `<!--feature-include:...-->...<!--/feature-include:...-->` blocks and strip them when the named feature is not in `enabled_features`. Update all templates (`CLAUDE.md.tpl`, `BEST_PRACTICES.md.tpl`, `settings.json.tpl`, `docs/CONTRIBUTING.md.tpl`) to wrap feature-specific content in these blocks. The renderer is still called with `enabled_features = {all features}` (no actual filtering), so behavior is unchanged; the templates are now ready for filtering.

3. **PR 3 — Sync-time feature selection.** Insert Step 2d into `skills/sync/SKILL.md`. Wire `enabled_features` through the apply phase: the renderer receives the consumer's set; section-feature filtering, hook filtering, and `feature-include` block stripping all use the same set. Add the stale-artifact warning to Step 8. This PR makes first-install and re-run interactive feature selection work. Runtime gates in optional-feature skills are not yet in place — invoking a disabled skill still executes it; only newly-synced consumer artifacts are filtered.

4. **PR 4 — Runtime feature gates in skills.** Add the feature-check preamble to every optional-feature skill (eight RFC skills, refactor, two best-practices skills, git-branch-cleanup, plus the plugin-local `best-practices-sync`). Add `feature:` frontmatter to every optional-feature skill. After this PR, invoking a disabled skill exits with the standard message.

After PR 4, the migration is complete. Existing consumers with `features.bytewyrd` absent in `settings.json` see the first-install prompt on their next `/sync` (one AskUserQuestion with up to nine questions, all defaulting to `Enable` where conditions are met); existing behavior is preserved by default. Consumers who want to deviate can flip features.

### Verification

After PR 4, run these checks. Each is required to pass before the implementation is considered correct.

1. **Catalogue and manifest are consistent:**
   ```bash
   .claude-plugin/scripts/build-manifest.sh --check
   ```
   Expected: exit 0. Validates (a) every manifest `feature` is in the catalogue, (b) every catalogue feature is referenced, (c) `manifest_version` is current.

2. **Fresh install with all defaults — every feature enabled:**
   In an empty repo, run `/sync`. Expected: one AskUserQuestion with nine feature questions (when `has_github = true` and at least one language with a standard gate is detected — otherwise `github-artifacts` and/or `prepush-quality-gate` are silently set to disabled and omitted). Answer "Enable" to all. Expected artifacts: every file the current `/sync` writes today.

3. **Fresh install with `rfc-workflow` disabled:**
   In an empty repo, run `/sync` and answer "Disable" for the RFC workflow question. Expected:
   - `docs/rfc-process.md` is *not* created.
   - `docs/rfcs/.gitkeep` is *not* created.
   - `CLAUDE.md` is created *without* the `## RFC Process` section.
   - `docs/CONTRIBUTING.md` is created *without* the RFC section.
   - The agent delegation table in `CLAUDE.md` does *not* contain the "Architecture / RFCs" row.
   - `.claude/settings.json` has `features.bytewyrd.disabled = ["rfc-workflow"]` and `enabled` lists every other optional feature.

4. **Fresh install with `best-practices` disabled implies `language-bp-blocks` disabled:**
   In an empty repo, run `/sync` and answer "Disable" for best-practices. Expected: the hard-dependency follow-up prompt fires for `language-bp-blocks` (since it consumes `best-practices`); the user is offered "Enable best-practices too" or "Skip language-bp-blocks". After "Skip language-bp-blocks":
   - `docs/BEST_PRACTICES.md` is *not* created.
   - The PreCompact and Stop hooks in `settings.json` do *not* contain best-practices reminders.
   - `language-bp-blocks` is in `disabled` along with `best-practices`.

   Alternatively, if the user chooses "Enable best-practices too": both `best-practices` and `language-bp-blocks` appear in `enabled`; `docs/BEST_PRACTICES.md` is created.

5. **Re-run with no plugin manifest changes is silent:**
   After verification #2, immediately re-run `/sync`. Expected:
   - No AskUserQuestion is invoked for features.
   - The report shows "Features: ... (manifest version <X> — no changes.)"
   - Every artifact is `unchanged`.

6. **Re-run after a new feature is added to the catalogue:**
   Simulate a plugin update: edit `features.toml` to add a new optional feature `[features.new-thing]` with `default = "enabled"`, bump `manifest_version`, regenerate the manifest, commit. Re-run `/sync` in the consumer. Expected:
   - One AskUserQuestion fires with one question for the new feature.
   - Other features are *not* re-asked.
   - After the answer, `manifest_version` in the consumer's `settings.json` is updated to the new value.

7. **Disabling a feature on a re-run leaves files in place and warns:**
   In a consumer that ran `/sync` with `rfc-workflow` enabled, edit `settings.json` to move `rfc-workflow` from `enabled` to `disabled` and bump nothing else. Re-run `/sync`. Expected:
   - `docs/rfc-process.md` still exists (not deleted).
   - The Step 8 report includes "Stale artifacts from disabled features: ... docs/rfc-process.md ... docs/rfcs/.gitkeep ...".
   - `CLAUDE.md` is classified as a fast-forward (the rendered canonical form no longer includes the `## RFC Process` section); after approval, the section is removed from the live file.

8. **Invoking a disabled skill exits with the standard message:**
   In a consumer with `rfc-workflow` disabled, invoke `/rfc-new "test"`. Expected: the skill prints "The `rfc-workflow` feature is disabled for this project..." and stops without creating any files.

9. **Soft handle in `refactor` adapts at runtime:**
   In a consumer with `refactor-workflow` enabled and `best-practices` disabled, invoke `/refactor src/foo.rs`. Expected: the skill runs (the runtime gate passes for `refactor-workflow`); the "After the refactor" step's `jq` predicate fails (best-practices not in enabled), so the `/best-practices-extract` reminder is omitted from the skill's output.

10. **`has_github = false` automatically disables `github-artifacts`:**
    In a repo with no GitHub remote, run `/sync`. Expected: the `github-artifacts` question shows "Disable" as the suggested option (per `default = "enabled-if-github"` evaluated against `has_github = false`). If the user accepts the suggestion, no `.github/` artifacts are created and `gh repo edit` is not invoked.

11. **`build-manifest.sh` rejects an undeclared feature in the manifest:**
    Manually edit `.claude-plugin/bootstrap-manifest.json` to set `feature: "nonexistent"` on one artifact. Run `build-manifest.sh --check`. Expected: exit non-zero with "manifest references features not declared in features.toml: nonexistent".

12. **`build-manifest.sh` rejects a manifest_version that does not match a feature-set change:**
    Add a new feature `[features.test-feature]` to `features.toml` without bumping `manifest_version`. Run `build-manifest.sh --check`. Expected: exit non-zero with "features.toml feature set changed since HEAD but manifest_version was not bumped".

If any verification step fails, the failure points to one of: (a) catalogue/manifest drift (PR 1 validation), (b) renderer not stripping a feature-include block (PR 2), (c) Step 2d not piping `enabled_features` into the renderer (PR 3), or (d) skill preamble not reading the features block correctly (PR 4).

## Risks and open questions

- **Risk: a consumer's `.claude/settings.json` is hand-edited in a way that drops a previously-enabled feature without the user realizing.** The user opens `settings.json` to change a permission, makes a typo in the `features.bytewyrd.enabled` array, and on the next `/sync` the typo'd feature disappears. **Mitigation:** Step 2d's logic treats "feature in catalogue but not in enabled and not in disabled" as a "new feature, ask" trigger. A typo'd feature id is silently dropped from both lists; a typo'd entry that doesn't match any catalogue id is ignored. The user is re-prompted for the missing feature on the next `/sync`. The downside is the typo'd entry persists in the file as dead content; the build-manifest check does not detect this (the consumer's settings.json is not part of the plugin's commits).

- **Risk: a maintainer renames a feature id (e.g., `rfc-workflow` → `rfc`).** Existing consumers' `settings.json` references the old id; the new manifest references the new id; the consumer's old id is silently dropped on the next `/sync` and the user is re-prompted for the new id. The previous user intent (enabled or disabled) is lost. **Mitigation:** add an `aliases` field to feature stanzas (`aliases = ["rfc-workflow"]`); Step 2d treats an entry matching an alias as the canonical id. Captured as a follow-up; not implemented in the initial PRs because no feature has yet been renamed.

- **Risk: the runtime feature check in skills assumes `jq` is on the consumer's PATH.** `jq` is already a hard dependency from RFC `2026-05-10-sync-interactive-diff`, but a skill invoked in an environment where `jq` is missing exits with a confusing error. **Mitigation:** the standard preamble script gracefully degrades — if `jq` is not available, the skill prints "feature check failed: jq required. Run /sync to install the prerequisites." and exits. The `jq`-required precondition was already established by the other RFC, so this is not a new constraint.

- **Open question: should `core-*` features be hidden from `settings.json` entirely, or should they appear in `enabled` for completeness?** The recommendation is hidden — the user never has a choice about core features, so showing them clutters the file. The catalogue records `kind = "core"` so the build-manifest validator and the renderer know to handle them; the consumer's `settings.json` only tracks optional features.

- **Open question: does the renderer's per-consumer template rendering break the cache-friendliness of the bootstrap manifest's content hash?** The manifest's `template_sha` is the hash of the template source (per RFC `2026-05-10-sync-interactive-diff`). The rendered output depends on `enabled_features` (a per-consumer value), so the rendered SHA on the consumer's file does not equal `template_sha`. **Resolution:** the existing design already handles this — the marker on the consumer's file is the *rendered canonical SHA at write time*, computed per-consumer. The `template_sha` is the maintainer-side check that the template source changed; it is unrelated to the per-consumer marker. Adding `enabled_features` as a template input does not break the existing design; it just makes more cases produce different rendered SHAs across consumers (which is correct behavior).

- **Open question: should there be a `/sync-features` slash command for revisiting choices without running the full `/sync`?** A consumer who wants to enable or disable one feature mid-project should not need to re-run the full sync to get the prompt. **Resolution within this RFC:** out of scope. The full `/sync` is the supported entry point; a future RFC can add `/sync-features` as a thin wrapper that runs only Step 2d + the apply phase. For now, the user edits `settings.json` manually (the `features.bytewyrd` block is small and clearly named).

- **Open question: should the prompt offer a "show me what each feature ships" expand link?** The current design has the `description` string in each question, which is a one-line summary. A user who wants to know exactly which files a feature creates has to read this RFC or the catalogue. **Resolution within this RFC:** the description includes specific user-visible artifacts (file paths, command names). The trade-off between concision and detail is calibrated to one screenful per question. A "details" link would require a follow-up AskUserQuestion per feature; not worth the complexity. Users who want exhaustive detail can read `features.toml`.

- **Risk: a feature's runtime check pattern is duplicated across ~13 skills.** A bug in the pattern affects every skill. **Mitigation:** the pattern is small enough (one `jq` line + one conditional output) that a bug is unlikely; the pattern is verified by verification step 8 (invoke a disabled skill, confirm message and exit) which runs against every optional-feature skill in CI. If a future change to the pattern is needed, a sed update across the skills is straightforward.

- **Risk: a future plugin update that converts a previously-optional feature into core silently auto-enables it for existing consumers.** A consumer who had explicitly disabled `git-branch-cleanup` would suddenly find it enabled if it became `kind = "core"`. **Mitigation:** the build-manifest validator catches "feature removed from optional list" as a feature-set change requiring a `manifest_version` bump; on the next `/sync`, Step 2d re-evaluates against the new catalogue. A previously-disabled feature that is now core no longer appears in `disabled` (it is filtered out as no longer optional) — its artifacts are written. This is intentional behavior: features promoted to core are by definition required, and surfacing the change in the Step 8 report ("Feature `git-branch-cleanup` was promoted to core in plugin version 2026-06-01; its artifacts are now installed.") gives the consumer visibility.

- **Open question: how does `/sync` behave when the consumer's `features.bytewyrd` block has features in `enabled` that are no longer in the catalogue?** (E.g., a feature was removed in a plugin update.) **Resolution within this RFC:** the dropped feature is silently removed from the consumer's `enabled` list during Step 2d's writeback; the Step 8 report notes "Feature `<id>` was removed from the plugin in version `<X>`; previously-installed artifacts may remain — see <doc>." This mirrors the stale-artifact warning for user-disabled features.

## Relationship to other RFCs

- **`2026-05-10-sync-interactive-diff`** (status: Draft) — this RFC depends on the bootstrap manifest format introduced there. Every artifact's `feature` field, `section_features` array, and `_meta.bytewyrd_feature` field on hook entries plug into the manifest schema that other RFC defines. The renderer's `feature-include` block syntax is added to the template-rendering function that other RFC introduces. The Step 2d feature selection sits between the identity collection (Step 2c of the current /sync) and the diff computation (Step 4 in the post-`2026-05-10-sync-interactive-diff` flow). **If `2026-05-10-sync-interactive-diff` is dropped:** this RFC's scope reduces to "feature toggles applied at file-write time" — the diff infrastructure becomes unnecessary because the current sync's skip-if-exists path already handles "do not overwrite," and the apply path becomes a series of `if feature in enabled: write_file()` predicates. The features.toml, the `features` block in settings.json, the Step 2d flow, and the runtime gates in skills survive intact. The cost is that re-running `/sync` after disabling a feature does not flag stale files (since the diff engine that surfaces them goes away).

- **`2026-05-10-project-brief-sync-source-of-truth`** (status: Done) — established `docs/project-brief.md` as the source of truth for `project_name` and `description`, propagated by `/sync` into `CLAUDE.md` and `README.md`. This RFC's `core-identity` feature wraps that mechanism: `docs/project-brief.md` and the brief→docs propagation are part of `core-identity`, which is always enabled. The brief stays the source of truth; `enabled_features` is a *separate* template input alongside `project_name` and `description`, both flowing into the same renderer.

- **`2026-05-09-best-practices-content-and-tooling`** (status: Done) — established the `/best-practices-*` skill family naming and the structure of `docs/BEST_PRACTICES.md`. This RFC's `best-practices` feature wraps the skill family and the docs file. The `## Project-Specific` section of `docs/BEST_PRACTICES.md` (a user-owned section per that RFC) is preserved exactly — disabling `best-practices` does not affect a user who has manually retained the file (the file is left in place; the warning is logged).

- **`2026-05-10-best-practice-extraction-principles`** (status: Done) — defined the triage and lift principles used by `/best-practices-extract`. This RFC's `best-practices` feature includes those principles; disabling `best-practices` removes the extraction skill but does not remove the principles from anywhere they apply (they apply only inside the skill).

- **`2026-05-10-refactor-command`** (status: Draft) — defined the `/refactor` slash command. This RFC's `refactor-workflow` feature wraps that skill. The mention of `/best-practices-extract` in the refactor description is the soft handle described in Decision 3; resolved at runtime per the rules above.

- **`2026-05-10-claude-plugin-author-agent`** and **`2026-05-10-claude-agent-author-agent`** (both Draft) — propose author-agents for plugin and agent definitions. Neither agent is referenced by name from any current skill, so their inclusion is orthogonal to feature toggles. They are not wrapped by any feature today; if they ship as additions to the agent fleet, they remain unconditionally available (they belong to `core-agent-delegation`, sharing the catalogue position with `feature-engineer`, `code-reviewer`, etc.).

- **Future RFC — `/sync-features`** (captured in Risks above) — a thin wrapper that runs only Step 2d + the apply phase, for revisiting choices without a full `/sync`. Not in scope for this RFC; the user-facing path for revisiting choices today is "edit `.claude/settings.json` and re-run `/sync`."

- **Future RFC — feature-removal pruning** (captured in Drawbacks) — disabling a feature today does not delete previously-installed artifacts. A future RFC could add a `--remove-stale` flag that prompts to delete each stale artifact. Not in scope here because automated deletion has subtle correctness risks (the user may have edited the file, the file may be referenced from other places not yet in the manifest, etc.); the explicit warning is the conservative-correct default.
