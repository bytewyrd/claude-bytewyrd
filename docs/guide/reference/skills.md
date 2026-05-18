# Skills reference

Every slash-command skill exported by the `claude-bytewyrd` plugin. Each row's description comes from the skill's own `SKILL.md` frontmatter — to update an entry, edit the source skill file, not this page.

Skills can be invoked as `/skill-name` (or `/bytewyrd:skill-name` when there's a naming collision with another plugin).

| Skill | Description |
|-------|-------------|
| `/best-practices-extract` | Use at the end of a meaningful session to extract non-obvious learnings into the project's `docs/BEST_PRACTICES.md`. Generalizable entries can optionally be promoted to the global cross-project pool (`~/.claude/BEST_PRACTICES.md`) via a single bulk-checkbox prompt in the same approval flow. |
| `/best-practices-record` | Use when the user wants to capture a single best practice into the global cross-project pool at `~/.claude/BEST_PRACTICES.md` — typically after seeing a pattern repeat across projects. |
| `/docs-review` | Run a scoped documentation review against the codebase. Spawns the `docs-agent` subagent on Sonnet with a seven-phase protocol that audits `docs/guide/**` for drift (broken examples, stale references, workflow drift) and coverage gaps against the current code. |
| `/git-branch-cleanup` | Clean up, prune, or delete stale git branches — local branches with no remote, branches for merged PRs, abandoned remote branches, and worktrees for deleted branches. |
| `/refactor` | Run a deliberate refactoring pass on a scoped set of files. Spawns the `refactoring-specialist` subagent on Opus with `max` effort and a six-phase protocol (pre-flight → analyze → characterization tests → plan → approval gate → apply → report). Not for tiny renames. |
| `/rfc-approve` | Approve a Draft RFC. Updates status to Approved and commits. This is the only step humans alone perform — agents draft and review, humans approve. |
| `/rfc-braindump` | Capture a quick RFC idea or potential RFC candidate without creating a full RFC. |
| `/rfc-consensus-review` | Spawn 5 parallel independent reviewer agents on an RFC, synthesize findings by consensus, verify factual claims, auto-fix verified bugs, then walk the human through design decisions one-by-one with RFC context. Critical = 4-5/5 reviewers; Moderate = 3/5; Minor = 1-2/5. |
| `/rfc-drop` | Drop an RFC that will not be implemented. Sets status to Dropped, records the reason, and commits. |
| `/rfc-implement` | Begin implementing an Approved RFC. Spawns a `feature-engineer` agent with the RFC as primary input and marks the RFC `Done` when complete. |
| `/rfc-new` | Create a new RFC. Generates a date-based identifier, creates the file from template, spawns `rfc-architect` to fill it in, runs review agents, runs consensus review, fixes critical findings, and presents the finished Draft to the human. |
| `/rfc-read-feedback` | Address inline `FEEDBACK:` comments that humans have added to an RFC file. Spawns `rfc-architect` to incorporate each comment, removes the markers, and runs the self-review checklist. |
| `/rfc-summary` | List active RFCs at a glance — every RFC currently in Draft or Approved status, grouped by status with identifier, title, author, and creation date. Filters out Done and Dropped. Read-only, runs inline (no agent spawn). |
| `/sync` | Set up or refresh a project repository with all standard conventions — idempotent, safe to re-run whenever the plugin updates. |

## How skills are discovered

The Claude Code plugin system reads `skills/<name>/SKILL.md` at the plugin root and exposes each one as `/skill-name`. The skill body is the prompt the main agent reads when the skill is invoked. Some skills spawn specialist subagents (see the [Agents reference](agents.md)); others run inline against the main agent.

To author a new skill, see [Add a new skill to the plugin](../contributing/add-a-skill.md).
