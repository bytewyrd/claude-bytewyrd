---
name: best-practices
description: >-
  Curated best practices per stack, one reference file each: general
  (pitfalls, workflow, Claude Code, code design and style, architecture,
  testing, documentation, security and error handling), go, js-ts, python,
  rust, svelte, ruby, rails, k8s-cue and terraform. Read general and the files
  for the stacks a task touches before designing, writing or reviewing code
  in them.
---

# Best practices

The curated entries live in `references/`, one file per stack:

| File | Sections |
|---|---|
| [references/general.md](references/general.md) | Pitfall, Workflow, Claude Code, Code Design, Code Style, Architecture, Testing, Documentation, Security, Error Handling |
| [references/go.md](references/go.md) | Go |
| [references/js-ts.md](references/js-ts.md) | JavaScript / TypeScript |
| [references/python.md](references/python.md) | Python |
| [references/rust.md](references/rust.md) | Rust |
| [references/svelte.md](references/svelte.md) | Svelte |
| [references/ruby.md](references/ruby.md) | Ruby |
| [references/rails.md](references/rails.md) | Rails |
| [references/k8s-cue.md](references/k8s-cue.md) | Kubernetes / CUE / kapply |
| [references/terraform.md](references/terraform.md) | Terraform / Terragrunt |

## Where do entries live, and why?

`docs/BEST_PRACTICES.md` is the **per-project accumulator**. It holds non-obvious learnings extracted from this
project's sessions (via `/best-practices-extract`). Both *generalizable* and *project-specific*
entries live here, separated by section:

- **Thematic sections** (`## Testing`, `## Architecture`, `## Documentation`, etc.) hold
  generalizable entries — they passed the three portability questions in `TRIAGE-AND-LIFT.md`
  and could theoretically ship to any project that uses the matching stack. They are *eligible*
  for promotion to the global pool.
- **`## Project-Specific`** holds entries that failed any portability question. They are
  valuable to this project (gotchas, internal conventions, project-name-specific quirks) but
  do not transfer. They are never promoted.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `docs/BEST_PRACTICES.md` | Per-project | Session extraction | Generalizable entries may be promoted to `~/.claude/BEST_PRACTICES.md` via `/best-practices-extract`'s per-entry prompt |
| `~/.claude/BEST_PRACTICES.md` | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into bootstrap content (plugin-author only) |
| `skills/best-practices/references/<stack>.md` (this skill, plugin-internal) | Distributed | `/best-practices-sync` from global pool | Read from this skill at runtime; projects get no copy |

Format: _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries. Generalizable entries
can be opted into the global pool via the per-entry prompt in that same flow.
