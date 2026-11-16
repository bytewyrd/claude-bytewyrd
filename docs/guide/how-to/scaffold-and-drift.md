# Seed and check a repository with scaffold and drift

`/bytewyrd:scaffold` seeds a repository with the files the bytewyrd workflow expects, once. `/bytewyrd:drift` checks them later. Neither edits a file you already have: scaffold only creates files that are missing, and drift only reports.

This guide covers seeding a repository, reading the drift report, and moving a repository that the 0.2.x setup command configured over to scaffold and drift.

---

## Seed a repository

You need a git repository and Python 3.11 or newer (see [Requirements](../installation.md#requirements)). Run the commands from anywhere inside the work tree: scaffold writes at its top level. `/bytewyrd:scaffold` is a user-only skill, so you run it yourself.

1. Run a dry run:

   ```
   /bytewyrd:scaffold
   ```

   It lists what it would create and writes nothing:

   ```
   bytewyrd scaffold: /path/to/myapp
   would create  AGENTS.md
   would create  CLAUDE.md
   would create  .github/PULL_REQUEST_TEMPLATE.md
   would create  .github/workflows/ci.yml
   dry run: 4 to create, 0 skipped; re-run with --apply to write
   ```

   A file that exists already is listed as `skip`, with the reason:

   ```
   skip  .github/PULL_REQUEST_TEMPLATE.md  (exists; scaffold never overwrites)
   ```

2. Commit or stash your own changes. `--apply` refuses to run on a dirty working tree and exits with code 3:

   ```
   scaffold: working tree is dirty; commit first or pass --allow-dirty
   ```

   A dry run on a dirty tree adds a `note:` that says so. Pass `--allow-dirty` when you accept that the new files will sit among your uncommitted changes.

3. Write the files:

   ```
   /bytewyrd:scaffold --apply
   ```

   ```
   bytewyrd scaffold: /path/to/myapp
   created  AGENTS.md
   created  CLAUDE.md
   created  .github/PULL_REQUEST_TEMPLATE.md
   created  .github/workflows/ci.yml
   applied: 4 created, 0 skipped
   ```

4. Review the files and commit them. From then on they belong to your project, and the plugin never edits them. If a write fails partway, scaffold deletes the files that run created and exits 1.

### What it creates

| File | What it holds | Skipped when |
|------|---------------|--------------|
| `AGENTS.md` | Guidance for people and coding agents, kept under 100 lines: the project name, a Project facts section with the languages scaffold found and their build and test commands (only when it found one), and a Workflow section that links the RFC process and the plugin's always-on rules. | The file exists. |
| `CLAUDE.md` | Imports `@AGENTS.md`, then adds Claude Code specifics, including the plugin install commands for new collaborators. | The file exists. |
| `.github/PULL_REQUEST_TEMPLATE.md` | A pull request template with Summary, Changes, Testing and Notes for Reviewers sections. | The file exists, or a template is found at the top level, in `docs/` or in `.github/`. |
| `.github/workflows/ci.yml` | One job per language and directory scaffold found, each calling this plugin's reusable workflow for that language at a pinned commit. With no language found, a single no-op job. | The file exists, or `.github/workflows/` already holds a `.yml` or `.yaml` workflow. |

Line 1 of each file is a stamp that names the template, its hash and the plugin commit: `<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:<hash> plugin=<commit> -->` in Markdown, and the same text after `# ` in the workflow. Drift reads it. Scaffold writes only at the top of the work tree, never under `.claude/`, and never through a symlink.

### Which manifests get a CI job

Scaffold looks at the manifests git tracks: `go.mod`, `package.json`, `pyproject.toml` (with a `[project]` table), `setup.py`, `Cargo.toml` and `Gemfile`. It looks at the root and at directories up to two levels deep, and skips vendored, test, fixture, example and template trees. Each language and directory it keeps gets one job, using the reusable workflow for go, js, python, ruby or rust.

A manifest that gets no job is printed as `note: no CI job for <path>: <reason>`, and the reason says how to fix it. Scaffold also prints a `note:` when a job it writes is likely to fail, for example for a Ruby directory without a Ruby version file.

To leave a manifest out on purpose, add a line such as `/tools/go.mod -bytewyrd-ci` to `.gitattributes`. Setting `bytewyrd-ci` instead includes a directory that the defaults skip. Scaffold reads `.gitattributes` from git's index, so stage or commit it first.

---

## Check a repository with drift

Run `/bytewyrd:drift` whenever you want to compare the seeded files with the plugin's current templates, for example after a plugin update. It never writes a file, and Claude can run it for you.

```
/bytewyrd:drift
```

```
ok  AGENTS.md
ok  CLAUDE.md
info  .github/PULL_REQUEST_TEMPLATE.md  unstamped: line 1 has no scaffold stamp, so drift compares it with no template
ok  .github/workflows/ci.yml
result: 3 ok, 1 info, 0 warn, 0 drift (exit 0)
```

Each line starts with a severity: `ok`, `info`, `warn` or `drift`. Except for `ok`, it continues with the path, a code and a detail. A `fix:` line follows a finding, and some findings add a diff or a job block. The last line counts each severity and gives the exit code:

- `0`: no drift. `info` and `warn` lines don't count.
- `2`: drift. With `--strict`, a `warn` line also exits 2.
- `1`: drift couldn't run, for example outside a git work tree or without Python 3.11 or newer.

### What the findings mean

| Code | Severity | What it means |
|------|----------|---------------|
| `missing` | warn | A seed file is missing. Run `scaffold --apply`. |
| `unstamped` | info | Line 1 has no scaffold stamp, so there is nothing to compare. Normal for a file you wrote yourself. |
| `template-changed` | drift | The plugin's template changed since the file was seeded. Drift prints the diff from your file to the new rendering. |
| `bad-stamp` | drift | The stamp doesn't parse, or names a template that isn't for this file. |
| `no-import` | drift | `CLAUDE.md` has no `@AGENTS.md` line, so Claude Code doesn't read `AGENTS.md`. |
| `too-long` | warn | `AGENTS.md` is over 100 lines or 8,000 characters, or `CLAUDE.md` is over 200 lines. |
| `ci-variant` | warn | The stamp on `ci.yml` names a different template from the one scaffold would pick now, or a detected language and directory has no job. |
| `pin-changed` | drift | A `uses:` line in `ci.yml` doesn't call the plugin's reusable workflow at the pinned commit. |
| `ci-skipped` | info | A manifest that gets no CI job, with the reason. |
| `legacy-*` | drift | Something the 0.2.x setup command left behind. See below. |

The `fix:` lines are for you to review and run; drift never edits a file. For `template-changed`, apply the parts of the diff you want, then replace line 1 with the stamp the fix line prints. For `pin-changed`, set the `uses:` to the call the fix line prints; it also prints a link that compares the old and new commits. Run drift again until it exits 0.

---

## Move a repository off the 0.2.x setup

The command that set projects up in 0.2.x is gone. The files it wrote stay in your repository until you remove them, and drift lists them.

1. Update the plugin and install its dependencies. Follow [Upgrading from 0.2.x](../installation.md#upgrading-from-02x).

2. Run `/bytewyrd:drift`. In a repository the old command configured, it exits 2 with `legacy-*` findings, each with a `fix:` line:

   | Code | What it found |
   |------|---------------|
   | `legacy-header` | A header or banner from the old command on line 1, 2 or 3 of a file it wrote: `CLAUDE.md`, the PR template, `ci.yml`, `README.md`, `docs/ARCHITECTURE.md`, `docs/BEST_PRACTICES.md`, `docs/CONTRIBUTING.md` or `mise.toml`. |
   | `legacy-gitignore` | The old header and `# bytewyrd:` tag lines in `.gitignore`. |
   | `legacy-rfc-process-copy` | A copy of the RFC process that the old command wrote into `docs/`. The `rfc-process` skill replaces it. |
   | `legacy-settings-hooks` | The old command's hook entries in `.claude/settings.json`, including the compaction gate. |
   | `legacy-sidecar`, `legacy-state` | Version sidecars and state files it left under `.bytewyrd/` and `.claude/`. |

3. Apply each fix yourself. Most are a deleted header line or a `git rm`:
   - For a PR template or `ci.yml` you want to keep, delete the header line. Drift then reports the file as `unstamped`.
   - For the copy of the RFC process, remove it and move any `## Project Extensions` text into `AGENTS.md`.
   - For a `CLAUDE.md` with the old header, drift prints a three-step fix: move it to `CLAUDE.legacy.md`, run `scaffold --apply` once everything else is committed, then move the sections you want to keep into `AGENTS.md` or the new `CLAUDE.md` and delete the legacy file. Follow the steps in order.

4. Commit the fixes. `scaffold --apply` needs a clean tree.

5. Run `/bytewyrd:scaffold --apply`. It creates what is missing, typically `AGENTS.md`, and `CLAUDE.md` if you moved the old one.

6. Run `/bytewyrd:drift` again. It should exit 0. `info` lines such as `unstamped` are fine.

---

## Related

- [Installation](../installation.md) — install, requirements, and upgrading from 0.2.x.
- [Concepts: scaffold and drift](../concepts.md#scaffold-and-drift) — why a seeded file belongs to your project and drift only reports.
- [Reference: Skills](../reference/skills.md) — the `/scaffold` and `/drift` entries.
