---
rfc: "2026-05-14-skill-helper-scripts"
title: "Skill Helper Scripts"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-14"
drop_reason: ~
---

## Summary

Extract all deterministic bash and parsing logic from skill `SKILL.md` files into a library of plugin-internal helper scripts under `scripts/` (alongside the existing `scripts/check-requirements.sh`). Skills currently describe RFC-file resolution, frontmatter-parsing, status-mutation, tool-availability probing, braindump management, feedback extraction, and other deterministic shell operations in prose; agents must read the prose and reconstruct the bash on every invocation. By moving every deterministic part into invocable scripts with stable, machine-readable contracts, skills shrink to a single `bash scripts/<name>.sh <args>` line plus the result-handling that is actually skill-specific. Each script is also covered by a bats-core unit test so regressions are caught before they silently break skill invocations. All scripts emit a single JSON object on stdout — both result data and user-facing messages are fields in the same object — so callers decide what to display rather than being forced to redirect stderr. `jq` is a hard dependency, checked at script startup. The result is fewer tokens per skill invocation, faster wall-clock execution, consistent output the user can recognize across skills, and a test-gated surface for plugin-internal automation.

## Should we do this?

**Yes.** Ten deterministic patterns are identified across the plugin's skill files — bash and `awk` logic where given the same inputs the script produces the same outputs without agent reasoning. Each pattern is mechanical, already specified verbatim in skill prose, and benefits from a stable stdout contract whether or not it appears in more than one skill. The cost is one focused implementation pass; the ongoing benefit is paid every time an agent invokes any of the affected skills. Adding a bats unit test per script ensures that a future change to a script is caught before it silently breaks every skill that calls it.

The extraction criterion is **determinism, not reuse**: a pattern earns extraction when it is an input-output stable shell operation with no agent reasoning embedded. Trivial one-liners (e.g., `date +%Y-%m-%d`, `test -f <path>`) that provide no multi-step contract are kept inline. This RFC does **not** propose a general-purpose scripting framework — scripts are strictly scoped to the plugin's internal operation, and their location under `scripts/` mirrors the sole existing precedent (`scripts/check-requirements.sh`).

## Current state

The plugin ships exactly one helper script today: `scripts/check-requirements.sh` (verified: `ls scripts/` returns the single file), invoked by the `SessionStart` hook in `hooks/hooks.json` via the resolution snippet at hooks.json:32 (verified: `hooks/hooks.json:32`). Every other piece of repeatable logic lives inline in skill prose.

### Deterministic logic in skill prose

Ten deterministic patterns are identified across skill files. Each entry names the pattern, the source file(s) that contain it, and why it qualifies for extraction.

**P1 — RFC file resolution.** Five skills open with the same `git diff --name-only HEAD -- docs/rfcs/ && git status --short docs/rfcs/` invocation followed by ~10 lines of resolution prose (argument → modified file → most-recent file → confirmation prompt). Verified across: `skills/rfc-approve/SKILL.md:16` (verified: `skills/rfc-approve/SKILL.md:L16`), `skills/rfc-drop/SKILL.md:16` (verified: `skills/rfc-drop/SKILL.md:L16`), `skills/rfc-consensus-review/SKILL.md:33` (verified: `skills/rfc-consensus-review/SKILL.md:L33`), `skills/rfc-read-feedback/SKILL.md:26` (verified: `skills/rfc-read-feedback/SKILL.md:L26`), `skills/rfc-implement/SKILL.md:27` (verified: `skills/rfc-implement/SKILL.md:L27`).

**P2 — RFC frontmatter parser.** The `awk` pipeline that walks the `---`-bounded YAML block and extracts `rfc`, `title`, `author`, `status`, `created` (and now `drop_reason`) appears verbatim in `skills/rfc-summary/SKILL.md:41-53` (verified: `skills/rfc-summary/SKILL.md:L41`). The same logic is described in prose in `skills/rfc-approve/SKILL.md:24` and `skills/rfc-drop/SKILL.md:24` for the status-check step.

**P3 — RFC status mutator.** Each of `rfc-approve`, `rfc-drop`, and `rfc-implement` flips the `status:` field in YAML frontmatter (and `rfc-drop` also sets `drop_reason:`). The skills describe the edit in prose at `skills/rfc-approve/SKILL.md:49` (verified: `skills/rfc-approve/SKILL.md:L49`), `skills/rfc-drop/SKILL.md:45-49` (verified: `skills/rfc-drop/SKILL.md:L45`), `skills/rfc-implement/SKILL.md:60` (verified: `skills/rfc-implement/SKILL.md:L60`). Agents must reconstruct the `sed` / `Edit` invocation each time.

**P4 — Tool availability probe.** Four skills independently probe whether `gh`, the GitHub MCP companion plugin, and/or the `code-review` companion plugin are present. Verified: `skills/best-practices-extract/SKILL.md:12` (verified: `skills/best-practices-extract/SKILL.md:L12`), `skills/rfc-implement/SKILL.md:12-14` (verified: `skills/rfc-implement/SKILL.md:L12`), `skills/refactor/SKILL.md:13-14` (verified: `skills/refactor/SKILL.md:L13`). Each skill repeats the same `grep -q '"<plugin-id>"[[:space:]]*:[[:space:]]*true' ~/.claude/settings.json .claude/settings.json` snippet, with slightly different wording in the "not enabled" message.

**P5 — RFC summary pipeline.** The full enumerate-parse-sort-group pipeline lives in `skills/rfc-summary/SKILL.md:39-54` (verified: `skills/rfc-summary/SKILL.md:L39`). Useful in `rfc-consensus-review` context-building too, but currently not reused.

**P6 — Braindump entry removal.** Removing a specific bullet from `docs/rfc-braindump.md` after promotion is described in prose at `skills/rfc-new/SKILL.md:109` (verified: `skills/rfc-new/SKILL.md:L109`). The agent must construct the `sed` / `Edit` call from prose every time.

**P7 — FEEDBACK: comment extraction.** Extracting and counting `FEEDBACK:` markers is described at `skills/rfc-read-feedback/SKILL.md:36-40` (verified: `skills/rfc-read-feedback/SKILL.md:L36`). The current grep is one line, but the surrounding "if none found, report" / "count + list with line numbers" logic is repeated in prose.

**P8 — Legacy RFC detection.** Finding files still on the legacy `NNN-` naming scheme lives at `skills/rfc-update/SKILL.md:64` (verified: `skills/rfc-update/SKILL.md:L64`). A one-line `ls | grep`, but it is the natural pair to P5 and worth co-locating.

**P9 — Braindump entry append.** `skills/rfc-braindump/SKILL.md:48` describes appending a new `* `-prefixed bullet to `docs/rfc-braindump.md`, including a file-creation guard that writes the standard header when the file does not yet exist. This is the write-side counterpart to P6 (removal). Both are single-purpose file-mutation operations on the same file and belong in the same script family. Currently described in prose; agents must reconstruct the file-creation check and `Write`/append operation each invocation.

**P10 — Braindump entry list.** `skills/rfc-new/SKILL.md:16-27` lists existing `* `-prefixed bullets from `docs/rfc-braindump.md` as numbered, tab-separated rows so the user can pick one to promote. The parsing is deterministic shell: `grep` for bullet lines, number them, emit one row per bullet. Currently described in prose, requiring the agent to reconstruct the grep-and-number pass per invocation and risking off-by-one or format drift when the prompt is presented.

### Why this is a problem

Each deterministic pattern left in prose costs three things every time a skill runs:

1. **Token budget.** The agent reads ~10–60 lines of prose per pattern. Across the ten patterns and the skills that contain them, this is several hundred lines of repeated context loaded into every RFC-related invocation.
2. **Reconstruction time.** The agent must convert the prose back into bash, choosing how to combine `git diff` / `git status` output, how to escape arguments, how to handle edge cases. This work is identical every time, and the wrong reconstruction produces drift between skills.
3. **Output drift.** Without a single source of truth, the format an agent produces varies between invocations. The user sees subtly different output depending on which skill ran — and there is no test suite to catch regressions.

The existing `scripts/check-requirements.sh` proves the pattern works: it is invoked from `hooks/hooks.json:32` with a robust `$CLAUDE_PLUGIN_ROOT` fallback chain, runs `set -u`, emits machine-readable JSON for the harness and human-readable text for the terminal, and uses exit code 2 for hard failures per Bash builtin convention (Exa: https://www.gnu.org/s/bash/manual/html_node/Exit-Status.html — "All of the Bash builtins return an exit status of zero if they succeed and a non-zero status on failure ... All builtins return an exit status of 2 to indicate incorrect usage"). The same conventions apply to skill helper scripts.

## Analysis / Options

Three approaches were considered. Only one survives the constraints.

### Option A — Stay inline (status quo)

Keep the prose in skills; do nothing. This is the cheapest option in implementation cost but the most expensive in ongoing token spend and the only one that allows the ten patterns to keep drifting. Rejected: the cost trend is monotonic and worse over time as new skills inherit the same prose.

### Option B — Shell helper scripts under `scripts/`

Create one bash script per pattern in `scripts/`, invoked by the agent as `bash scripts/<name>.sh <args>`. Each script reads stdin or arguments, performs the deterministic work, and emits a single JSON object on stdout — both result data and user-facing messages live as fields in the same object, with stderr reserved for unexpected shell-level failures only. The skill replaces ~10–60 lines of prose with one line: "Run `bash scripts/<name>.sh <args>` and parse the returned JSON for the next step."

Bash is the right choice because:
- Every pattern is shell-shaped: file finding, awk parsing, grep probing, sed/edit mutation. None requires data structures bash handles poorly.
- The existing `scripts/check-requirements.sh` is bash; using the same toolchain avoids a second language dependency.
- Bash strict mode (`set -euo pipefail`) catches the classes of bugs that script-level reuse would otherwise multiply across skills (Exa: https://linuxiq.org/shell-scripting-practical-notes-from-production/ — "`set -e` makes the shell exit on the first command that returns non-zero ... `set -u` makes unset variables an error instead of silently expanding to the empty string ... `set -o pipefail` makes a pipeline fail if any stage fails, not just the last one").
- All current consumer environments ship bash (the SessionStart hook already executes it; see `hooks/hooks.json:32`).

### Option C — Rewrite skills to call out to Python or Node

A "real" scripting language gets us better data structures and easier testing. Rejected: it adds a runtime dependency that the existing tooling does not need, and the patterns being extracted do not benefit from anything Python or Node offers over `awk` + `grep` + `sed`. The plugin already runs bash unconditionally; adding a second language is a cost without a matching benefit.

### Recommended approach

**Option B.** Implement all ten deterministic patterns as bash scripts under `scripts/`, mirror the conventions established by `scripts/check-requirements.sh`, add a bats unit test per script, and rewrite the affected skill files to call them.

The "door stays open" for Option C: if a future pattern is genuinely awkward in bash (e.g., needs JSON manipulation more involved than `jq` one-liners, or needs to interact with the GitHub API directly), it can be added as a Python script alongside the bash ones without breaking this RFC's contracts. The convention this RFC establishes is "one script per pattern, stable stdout contract, exit codes per Bash convention" — it does not mandate the implementation language.

## Drawbacks

**The scripts add a layer of indirection.** A new contributor reading `skills/rfc-approve/SKILL.md` will see "run `bash scripts/rfc-resolve.sh`" rather than the resolution logic itself. The trade-off is acceptable because the resolution logic was never the interesting part of the skill — it is mechanical prelude. To mitigate: every script ships with a header comment block documenting arguments, stdout contract, and exit codes; and the bats test suite under `tests/scripts/` provides executable documentation of the expected input/output behavior.

**The scripts are now plugin-wide test surface.** A regression in `scripts/rfc-resolve.sh` breaks every RFC skill simultaneously. The primary mitigation is the bats unit test suite introduced in Step 22 — every script has at minimum a happy-path test and a usage-error test, so a breaking change is caught before it reaches skill invocations. The secondary mitigation is keeping each script small, dependency-light, and validated at input boundaries.

**Bash strict mode has known caveats.** `set -e` does not propagate out of functions called inside `if`, `while`, `&&`, `||`, or `!` contexts (Exa: https://linuxiq.org/shell-scripting-practical-notes-from-production/ — "Bash's errexit does not trigger inside commands whose exit status is being tested"). The scripts in this RFC are short enough that this caveat does not bite in practice, but contributors must be aware of it when extending them.

**Scripts cannot be conditionally available.** Unlike the requirement-check hook which gracefully degrades when `$CLAUDE_PLUGIN_ROOT` is absent (hooks.json:32 falls back to `~/.claude/plugins/cache/*/bytewyrd/`), a skill that calls `bash scripts/rfc-resolve.sh` is hard-bound to the plugin being installed where the skill expects. Mitigated for the current scope by the fact that every RFC-related skill runs with `pwd` = project root and invokes scripts via the relative `scripts/<name>.sh` path. `scripts/rfc-summary.sh` additionally locates its sibling `rfc-frontmatter.sh` via `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`, which is sufficient for inter-script lookups. The path-survivability question is captured under "Risks and open questions" and a shared helper (e.g. `scripts/_lib/resolve-plugin-root.sh`) can be added in a future RFC if a skill ever needs to call a script from outside the project root.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/rfc-resolve.sh` | Pattern P1. Resolves an RFC identifier or filename to an absolute path; falls back to the unique modified RFC; falls back to the most recently dated RFC. Emits a JSON object on stdout with `path` and `label` fields (the label string is what the agent surfaces in its confirmation prompt). |
| Create | `scripts/rfc-frontmatter.sh` | Pattern P2. Reads a single RFC file and emits a JSON object on stdout with `rfc`, `title`, `author`, `status`, `created`, `drop_reason` fields. Implements the bounded-awk parser previously inline in `rfc-summary`. |
| Create | `scripts/rfc-set-status.sh` | Pattern P3. Mutates the `status:` field (and optionally `drop_reason:`) in a single RFC file in place. Validates the new status against the canonical lifecycle states. Emits a JSON object on stdout with `file`, `old_status`, `new_status`. |
| Create | `scripts/rfc-summary.sh` | Pattern P5. Iterates `docs/rfcs/*.md`, applies `rfc-frontmatter.sh` to each, emits a JSON object on stdout with `rfcs` (array of frontmatter objects sorted by `created` then `rfc`) and `warnings` (array of per-file warning strings). Pure data — rendering stays in the skill. |
| Create | `scripts/rfc-braindump-remove.sh` | Pattern P6. Removes a single `* `-prefixed bullet line from `docs/rfc-braindump.md` whose body equals the provided argument string. Emits a JSON object on stdout with `removed` (boolean) and `file`. |
| Create | `scripts/rfc-feedback-list.sh` | Pattern P7. Reads the given file and emits a JSON object on stdout with `markers` (array of `{line, text}` objects). Exits 0 on zero or more findings — finding-count is signaled by the array length, not the exit code. |
| Create | `scripts/rfc-legacy-detect.sh` | Pattern P8. Emits a JSON object on stdout with `legacy_files` (array of paths whose basename matches `[0-9]{3}-`). Exits 0 whether or not any are found. |
| Create | `scripts/tool-probe.sh` | Pattern P4. Single-purpose probe: given a tool name (`gh`, `git`, `jq`, `github-mcp`, `code-review-mcp`, etc.), emits a JSON object on stdout with `result` (`available`, `missing`, or `unauthenticated`), `name`, and `hint` (remediation one-liner). Exit 0 if available, 1 if not. |
| Create | `scripts/rfc-braindump-append.sh` | Pattern P9. Appends a `* <body>` bullet to `docs/rfc-braindump.md`, creating the file with the standard header if absent. Emits a JSON object on stdout with `appended`, `file`, `created_file`. |
| Create | `scripts/rfc-braindump-list.sh` | Pattern P10. Reads `docs/rfc-braindump.md` and emits a JSON object on stdout with `entries` (array of `{n, body}` objects in file order). Used by `rfc-new` step 1 to list entries for user selection. |
| Create | `tests/scripts/` | Directory containing one `.bats` test file per script. Uses bats-core v1.13.0 + bats-assert + bats-file v0.4.0 via git submodules under `tests/`. |
| Create | `tests/scripts/helpers.bash` | Shared test helpers: `setup_common` / `teardown_common` with temp dir management, `create_rfc_fixture`, `create_braindump_fixture`, and other fixture factories. |
| Create | `tests/scripts/rfc-resolve.bats` | Tests for `scripts/rfc-resolve.sh`. |
| Create | `tests/scripts/rfc-frontmatter.bats` | Tests for `scripts/rfc-frontmatter.sh`. |
| Create | `tests/scripts/rfc-set-status.bats` | Tests for `scripts/rfc-set-status.sh`. |
| Create | `tests/scripts/rfc-summary.bats` | Tests for `scripts/rfc-summary.sh`. |
| Create | `tests/scripts/rfc-braindump-remove.bats` | Tests for `scripts/rfc-braindump-remove.sh`. |
| Create | `tests/scripts/rfc-braindump-append.bats` | Tests for `scripts/rfc-braindump-append.sh`. |
| Create | `tests/scripts/rfc-braindump-list.bats` | Tests for `scripts/rfc-braindump-list.sh`. |
| Create | `tests/scripts/rfc-feedback-list.bats` | Tests for `scripts/rfc-feedback-list.sh`. |
| Create | `tests/scripts/rfc-legacy-detect.bats` | Tests for `scripts/rfc-legacy-detect.sh`. |
| Create | `tests/scripts/tool-probe.bats` | Tests for `scripts/tool-probe.sh`. |
| Modify | `skills/rfc-approve/SKILL.md` | Replace the inline P1, P2, P3 prose in steps 1, 2, 4 with `bash scripts/rfc-resolve.sh`, `bash scripts/rfc-frontmatter.sh`, `bash scripts/rfc-set-status.sh` invocations. |
| Modify | `skills/rfc-drop/SKILL.md` | Replace inline P1, P2, P3 prose in steps 1, 2, 4 with the same three scripts. |
| Modify | `skills/rfc-implement/SKILL.md` | Replace inline P1, P3, and P4 (`tool-probe.sh github-mcp` and `tool-probe.sh gh`) in the Requirement check and steps 1, 5. |
| Modify | `skills/rfc-consensus-review/SKILL.md` | Replace inline P1 in step 1. |
| Modify | `skills/rfc-read-feedback/SKILL.md` | Replace inline P1 in step 1 and P7 in step 2. |
| Modify | `skills/rfc-summary/SKILL.md` | Replace inline P2 + P5 (the `for f in docs/rfcs/*.md; do … done | sort` block) in steps 2 and 3 with `bash scripts/rfc-summary.sh`. |
| Modify | `skills/rfc-update/SKILL.md` | Replace inline P8 in step 3 with `bash scripts/rfc-legacy-detect.sh`. |
| Modify | `skills/rfc-new/SKILL.md` | Replace inline P6 prose in step 6 with `bash scripts/rfc-braindump-remove.sh`; replace step 1 braindump listing prose with `bash scripts/rfc-braindump-list.sh` (P10). |
| Modify | `skills/rfc-braindump/SKILL.md` | Replace inline step 4 append prose with `bash scripts/rfc-braindump-append.sh` (P9). |
| Modify | `skills/best-practices-extract/SKILL.md` | Replace inline P4 (`gh` probe) in the Requirement check with `bash scripts/tool-probe.sh gh`. |
| Modify | `skills/refactor/SKILL.md` | Replace inline P4 (`code-review` plugin probe) in the Requirement check with `bash scripts/tool-probe.sh code-review-mcp`. |

Total: ten new standalone scripts, eleven skill files modified, ten bats test files plus shared helpers. No changes to `.claude-plugin/bootstrap-manifest.json` are required — the manifest tracks consumer-distributed artifacts (`/sync` outputs), not plugin-internal scripts. Verified against `.claude-plugin/bootstrap-manifest.json`: every entry's `source` field begins with `.claude-plugin/scripts/templates/`, and every `target` field is a path inside the consumer's repo (verified: `.claude-plugin/bootstrap-manifest.json:L5,L13,L37`).

### Conventions inherited from `scripts/check-requirements.sh`

Every new script obeys the contract established by the one existing script (verified: `scripts/check-requirements.sh:L1-L8`):

1. **Shebang.** `#!/usr/bin/env bash` on line 1.
2. **Header comment.** A short comment block describing what the script does, who invokes it, and where the output goes — same shape as `scripts/check-requirements.sh:L2-L5`.
3. **Strict mode.** `set -u` at minimum. Scripts that pipe data add `set -o pipefail` so a failed `awk` or `grep` in the pipeline does not silently produce a "success" exit (Exa: https://linuxiq.org/shell-scripting-practical-notes-from-production/ — "`set -o pipefail` makes a pipeline fail if any stage fails, not just the last one").
4. **Exit codes.** `0` for success. `1` for a recoverable "I checked and the answer is no" (used by `tool-probe.sh` when a tool is absent — the caller decides what to do). `2` for a hard error: wrong arguments, missing required file, malformed frontmatter that the script cannot parse. The `2`-as-misuse convention matches Bash's own builtins (Exa: https://www.gnu.org/s/bash/manual/html_node/Exit-Status.html).
5. **Output channels.** All structured output — both machine-readable results and user-facing messages — is emitted as a single JSON object on stdout. Stderr is reserved for unexpected shell-level failures only (e.g. a `set -u` variable-unset error; a missing `jq` binary). Skills and agents parse stdout with `jq -r`; they choose which fields to surface. This eliminates the stdout/stderr interleaving ambiguity: a caller expecting "missing" as a normal fallback reads `.hint` from the JSON object and shows or suppresses it based on context, rather than redirecting stderr.
6. **No `cd`.** Scripts run with the caller's working directory; paths are interpreted relative to it. This matches how `hooks/hooks.json:32` invokes `check-requirements.sh` and keeps the scripts usable from any worktree.
7. **Pure stdin/argv.** Scripts read inputs from arguments or stdin. They do not read shell variables (other than `$CLAUDE_PLUGIN_ROOT` via the sourced helper) and they do not require environment setup beyond what bash provides by default.
8. **No long-running work.** Every script returns in well under a second on any reasonable input. None spawns long-running processes (per the global "Never start long-running processes" rule in user `CLAUDE.md`).
9. **jq dependency.** `jq` is required on `PATH`. Every script checks for `jq` at startup:
   ```bash
   command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }
   ```
   The error goes to stdout as a static JSON string (safe without jq). `tool-probe.sh jq` is the canonical presence test for skills that need to surface a clear message before running. `jq` ships in all major Linux distros and macOS Homebrew; the session-start requirement hook should probe for it alongside `git` and `gh`.

### Steps

#### Step 1 — Create `scripts/rfc-resolve.sh` (P1)

The most-used script. Takes zero or one argument; resolves to a single absolute RFC path on stdout.

Write `scripts/rfc-resolve.sh`:

```bash
#!/usr/bin/env bash
# Resolve an RFC identifier or basename to a single RFC path.
# Used by: rfc-approve, rfc-drop, rfc-consensus-review, rfc-implement, rfc-read-feedback.
#
# Args:
#   $1  Optional. RFC identifier (e.g. 2026-05-14-foo) or basename (2026-05-14-foo.md).
#       If omitted, resolution falls back to: unique modified RFC -> most recent file.
#       RFC filenames follow YYYY-MM-DD-<kebab>.md by convention — no spaces.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"path": "<absolute-path>", "label": "<human-label e.g. RFC 2026-05-14-foo (unique modified file)>"}
#     not-found (exit 1):
#       {"error": "<message>"}
#     usage error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Resolved successfully.
#   1  No RFC found matching the given argument; no modified or existing files to fall back on.
#   2  Usage error (e.g. argument given but contains a path separator that is not a docs/rfcs/ path).

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

# Validate cwd contains docs/rfcs.
if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "rfc-resolve: no docs/rfcs/ directory in $(pwd); run from project root" \
    '{error: $msg}'
  exit 2
fi

# Helper: given a stem (filename without .md), check whether docs/rfcs/<stem>.md exists.
find_by_stem() {
  local stem="$1"
  local f="docs/rfcs/${stem}.md"
  [ -f "$f" ] && printf '%s\n' "$f"
}

emit_result() {
  local path="$1" label="$2"
  jq -n --arg path "$path" --arg label "$label" '{path: $path, label: $label}'
}

emit_error() {
  local msg="$1"
  jq -n --arg msg "$msg" '{error: $msg}'
}

# Case 1: explicit argument.
if [ "${1:-}" != "" ]; then
  arg="$1"
  # Strip an optional leading "docs/rfcs/" prefix and trailing ".md".
  arg="${arg#docs/rfcs/}"
  arg="${arg%.md}"
  # Disallow path separators in the cleaned value — only basenames allowed.
  case "$arg" in
    */*) emit_error "rfc-resolve: identifier must not contain '/' (got: $1)"; exit 2 ;;
  esac
  resolved="$(find_by_stem "$arg" || true)"
  if [ -z "$resolved" ]; then
    emit_error "rfc-resolve: no RFC found at docs/rfcs/${arg}.md"
    exit 1
  fi
  abs="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
  emit_result "$abs" "RFC $arg (matched argument)"
  exit 0
fi

# Case 2: heuristic — exactly one modified RFC.
# Parse `git status --short` carefully:
#   - skip rows whose status indicates deletion (D in column 1 or column 2)
#   - for renames "R  old -> new", extract the new path (after " -> ")
#   - otherwise strip the two-char status+space prefix
# RFC filenames have no spaces by convention (YYYY-MM-DD-<kebab>.md).
# Uses index()+substr() for POSIX awk compatibility (no 3-arg match()).
modified=()
while IFS= read -r line; do
  [ -n "$line" ] && modified+=("$line")
done < <(
  git status --short -- docs/rfcs/ 2>/dev/null \
    | awk '
        # Skip deletions: status D in column 1 (staged delete) or column 2 (working-tree delete).
        /^D/ || /^.D/ { next }
        # For renames "R  old -> new", extract the new path (after " -> ").
        / -> / {
          n = index($0, " -> ")
          if (n > 0) { path = substr($0, n + 4); if (path ~ /\.md$/) print path }
          next
        }
        # Normal case: strip two-char status+space prefix, take rest.
        { sub(/^.. /, ""); if ($0 ~ /\.md$/) print $0 }
      ' \
    | sort -u
)
if [ "${#modified[@]}" -eq 1 ]; then
  resolved="${modified[0]}"
  if [ ! -f "$resolved" ]; then
    emit_error "rfc-resolve: modified file $resolved no longer exists"
    exit 1
  fi
  abs="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
  stem="$(basename "${resolved%.md}")"
  emit_result "$abs" "RFC $stem (unique modified file)"
  exit 0
fi

# Case 3: fall back to the most recently dated file (lex sort because filenames lead with YYYY-MM-DD).
latest="$(ls -1 docs/rfcs/*.md 2>/dev/null | sort | tail -n1)"
if [ -z "$latest" ] || [ ! -f "$latest" ]; then
  emit_error "rfc-resolve: no RFC files under docs/rfcs/"
  exit 1
fi
abs="$(cd "$(dirname "$latest")" && pwd)/$(basename "$latest")"
stem="$(basename "${latest%.md}")"
emit_result "$abs" "RFC $stem (most recently dated file)"
exit 0
```

Make executable: `chmod 755 scripts/rfc-resolve.sh`.

Verification:

```bash
$ bash scripts/rfc-resolve.sh 2026-05-12-rfc-summary-command | jq .
{
  "path": "/home/<user>/code/bytewyrd/claude-bytewyrd/docs/rfcs/2026-05-12-rfc-summary-command.md",
  "label": "RFC 2026-05-12-rfc-summary-command (matched argument)"
}

$ bash scripts/rfc-resolve.sh | jq .
{
  "path": "/home/<user>/code/bytewyrd/claude-bytewyrd/docs/rfcs/2026-05-14-skill-helper-scripts.md",
  "label": "RFC 2026-05-14-skill-helper-scripts (unique modified file)"
}

$ bash scripts/rfc-resolve.sh does-not-exist; echo "exit=$?"
{"error":"rfc-resolve: no RFC found at docs/rfcs/does-not-exist.md"}
exit=1

$ bash scripts/rfc-resolve.sh 'foo/bar'; echo "exit=$?"
{"error":"rfc-resolve: identifier must not contain '/' (got: foo/bar)"}
exit=2
```

#### Step 2 — Create `scripts/rfc-frontmatter.sh` (P2)

Reads a single RFC file and emits a JSON object with one key per frontmatter field.

Write `scripts/rfc-frontmatter.sh`:

```bash
#!/usr/bin/env bash
# Parse YAML frontmatter of an RFC file and emit a JSON object with field values.
# Used by: rfc-summary, rfc-approve, rfc-drop, rfc-consensus-review, rfc-implement, rfc-read-feedback.
#
# Args:
#   $1  Required. Path to an RFC file (.md). The first '---' line must be on line 1.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"rfc": "...", "title": "...", "author": "...", "status": "...",
#        "created": "...", "drop_reason": ""}
#       Keys parsed: rfc, title, author, status, created, drop_reason.
#       Missing fields are emitted as "" (empty string), so the consumer can always
#       count on a fixed set of keys. drop_reason is "" when the YAML value was `~`.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Parsed successfully (any subset of fields may have been present).
#   2  Usage error or file missing or no frontmatter found.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-frontmatter.sh <path-to-rfc.md>"
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  emit_error "rfc-frontmatter: file not found: $file"
  exit 2
fi

# Confirm the file opens with a frontmatter block.
if ! head -n1 "$file" | grep -q '^---$'; then
  emit_error "rfc-frontmatter: $file does not begin with a YAML frontmatter delimiter"
  exit 2
fi

# Parse fields into newline-separated key=value pairs, then convert to JSON via jq.
parsed="$(awk '
  BEGIN { fm = 0; rfc=""; title=""; author=""; status=""; created=""; drop_reason="" }
  /^---$/ { fm++; if (fm == 2) exit; next }
  fm == 1 {
    if ($1 == "rfc:")         { sub(/^rfc: */, "");         gsub(/"/, ""); rfc = $0 }
    else if ($1 == "title:")  { sub(/^title: */, "");       gsub(/"/, ""); title = $0 }
    else if ($1 == "author:") { sub(/^author: */, "");      gsub(/"/, ""); author = $0 }
    else if ($1 == "status:") { sub(/^status: */, "");      gsub(/"/, ""); status = $0 }
    else if ($1 == "created:"){ sub(/^created: */, "");     gsub(/"/, ""); created = $0 }
    else if ($1 == "drop_reason:") { sub(/^drop_reason: */, ""); gsub(/"/, ""); drop_reason = $0 }
  }
  END {
    # drop_reason: "~" is the canonical "unset" sentinel — normalize to empty.
    if (drop_reason == "~") drop_reason = ""
    printf "%s\n%s\n%s\n%s\n%s\n%s\n", rfc, title, author, status, created, drop_reason
  }
' "$file")"

# Split parsed output into individual fields. Using mapfile for safety.
mapfile -t fields <<< "$parsed"
jq -n \
  --arg rfc         "${fields[0]:-}" \
  --arg title       "${fields[1]:-}" \
  --arg author      "${fields[2]:-}" \
  --arg status      "${fields[3]:-}" \
  --arg created     "${fields[4]:-}" \
  --arg drop_reason "${fields[5]:-}" \
  '{rfc: $rfc, title: $title, author: $author, status: $status, created: $created, drop_reason: $drop_reason}'
```

Make executable: `chmod 755 scripts/rfc-frontmatter.sh`.

Verification:

```bash
$ bash scripts/rfc-frontmatter.sh docs/rfcs/2026-05-14-skill-helper-scripts.md | jq .
{
  "rfc": "2026-05-14-skill-helper-scripts",
  "title": "Skill Helper Scripts",
  "author": "Rodrigo Kochenburger",
  "status": "Draft",
  "created": "2026-05-14",
  "drop_reason": ""
}
```

#### Step 3 — Create `scripts/rfc-set-status.sh` (P3)

Mutates the `status:` line (and optionally `drop_reason:` when transitioning to `Dropped`). Validates the new status against the canonical lifecycle.

Write `scripts/rfc-set-status.sh`:

```bash
#!/usr/bin/env bash
# Set the status (and optionally drop_reason) of an RFC's frontmatter in place.
# Used by: rfc-approve, rfc-drop, rfc-implement.
#
# Args:
#   $1  Required. Path to an RFC file (.md).
#   $2  Required. New status. Must be one of: Draft, Approved, Done, Dropped.
#   $3  Optional. Drop reason (one-sentence string). Required when $2 = "Dropped"; rejected otherwise.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"file": "...", "old_status": "Draft", "new_status": "Approved"}
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Success.
#   2  Usage error, invalid status value, drop_reason missing when transitioning to Dropped,
#      drop_reason provided when status != Dropped, file missing, or no status line found.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  emit_error "usage: rfc-set-status.sh <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"
  exit 2
fi
file="$1"
new_status="$2"
drop_reason="${3:-}"

case "$new_status" in
  Draft|Approved|Done|Dropped) ;;
  *) emit_error "rfc-set-status: invalid status '$new_status' (allowed: Draft, Approved, Done, Dropped)"; exit 2 ;;
esac

if [ "$new_status" = "Dropped" ] && [ -z "$drop_reason" ]; then
  emit_error "rfc-set-status: drop_reason is required when status=Dropped"
  exit 2
fi
if [ "$new_status" != "Dropped" ] && [ -n "$drop_reason" ]; then
  emit_error "rfc-set-status: drop_reason is only allowed when status=Dropped"
  exit 2
fi

if [ ! -f "$file" ]; then
  emit_error "rfc-set-status: file not found: $file"
  exit 2
fi

# Confirm the file opens with frontmatter and has a status line inside the first block.
old_status="$(awk '
  BEGIN { fm = 0 }
  /^---$/ { fm++; if (fm == 2) exit }
  fm == 1 && $1 == "status:" { sub(/^status: */, ""); gsub(/"/, ""); print; exit }
' "$file")"

if [ -z "$old_status" ]; then
  emit_error "rfc-set-status: $file has no 'status:' line in its frontmatter"
  exit 2
fi

# Escape drop_reason for safe embedding in a YAML double-quoted string.
# Order matters: escape backslashes first, then double quotes.
escaped_reason="${drop_reason//\\/\\\\}"   # \ -> \\
escaped_reason="${escaped_reason//\"/\\\"}"  # " -> \"
# Reject newlines — YAML double-quoted scalars cannot contain raw newlines safely
# without folding, and a single-line drop_reason is the documented contract.
case "$escaped_reason" in
  *$'\n'*) emit_error "rfc-set-status: drop_reason must not contain newlines"; exit 2 ;;
esac

# Use awk to rewrite the 'status:' line inside the first frontmatter block.
# If the new status is Dropped:
#   - rewrite an existing 'drop_reason:' line if present
#   - otherwise inject 'drop_reason: "..."' immediately before the closing '---'
# If the new status is not Dropped: rewrite an existing drop_reason to '~'.
# This avoids touching any later occurrence inside the document body.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -v new_status="$new_status" -v drop_reason="$escaped_reason" '
  BEGIN { fm = 0; wrote_dr = 0 }
  /^---$/ {
    fm++
    # Before closing delimiter, inject drop_reason if not already written.
    if (fm == 2 && new_status == "Dropped" && !wrote_dr) {
      print "drop_reason: \"" drop_reason "\""
      wrote_dr = 1
    }
    print; next
  }
  fm == 1 && $1 == "status:" { print "status: \"" new_status "\""; next }
  fm == 1 && $1 == "drop_reason:" {
    if (new_status == "Dropped") { print "drop_reason: \"" drop_reason "\"" }
    else                          { print "drop_reason: ~" }
    wrote_dr = 1
    next
  }
  { print }
' "$file" > "$tmp"

cat "$tmp" > "$file"
rm -f "$tmp"
trap - EXIT

jq -n --arg file "$file" --arg old "$old_status" --arg new "$new_status" \
  '{file: $file, old_status: $old, new_status: $new}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-set-status.sh`.

Verification (run inside a worktree where the change can be reverted):

```bash
$ bash scripts/rfc-frontmatter.sh docs/rfcs/2026-05-14-skill-helper-scripts.md | jq -r .status
Draft

$ bash scripts/rfc-set-status.sh docs/rfcs/2026-05-14-skill-helper-scripts.md Approved | jq .
{
  "file": "docs/rfcs/2026-05-14-skill-helper-scripts.md",
  "old_status": "Draft",
  "new_status": "Approved"
}

$ bash scripts/rfc-frontmatter.sh docs/rfcs/2026-05-14-skill-helper-scripts.md | jq -r .status
Approved

$ git checkout docs/rfcs/2026-05-14-skill-helper-scripts.md   # revert the test mutation
```

#### Step 4 — Create `scripts/rfc-summary.sh` (P5)

Pure data emitter for the summary view. Iterates `docs/rfcs/*.md`, parses each via `rfc-frontmatter.sh`, and emits a JSON object with a sorted `rfcs` array and a `warnings` array.

Write `scripts/rfc-summary.sh`:

```bash
#!/usr/bin/env bash
# Emit a JSON object listing every RFC's frontmatter, sorted by created then rfc.
# Used by: rfc-summary.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"rfcs": [{"status": "...", "created": "...", "rfc": "...", "title": "...", "author": "..."}],
#        "warnings": ["<per-file warning text>"]}
#       `rfcs` is sorted ascending by `created` then `rfc`.
#       `warnings` is an empty array when all files parse cleanly. Exit 0 even when warnings are present.
#     error (exit 2 — no docs/rfcs/ dir):
#       {"error": "no docs/rfcs/ directory in <cwd>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Iteration completed (zero or more rows produced; warnings may be present).
#   2  docs/rfcs/ does not exist.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTMATTER_SH="$SCRIPT_DIR/rfc-frontmatter.sh"

if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "no docs/rfcs/ directory in $(pwd)" '{error: $msg}'
  exit 2
fi

# Accumulators: one JSON object per row, one string per warning.
rows_json=()
warnings=()

for f in docs/rfcs/*.md; do
  [ -f "$f" ] || continue
  # rfc-frontmatter exits 2 on a file that has no frontmatter; tolerate that here
  # and record a per-file warning rather than aborting the whole listing.
  if ! out="$(bash "$FRONTMATTER_SH" "$f" 2>/dev/null)"; then
    warnings+=("Warning: $f — frontmatter unparseable; skipping.")
    continue
  fi
  # Extract each field via jq -r.
  rfc="$(printf '%s' "$out"     | jq -r .rfc)"
  title="$(printf '%s' "$out"   | jq -r .title)"
  author="$(printf '%s' "$out"  | jq -r .author)"
  status="$(printf '%s' "$out"  | jq -r .status)"
  created="$(printf '%s' "$out" | jq -r .created)"
  if [ -z "$rfc" ] || [ -z "$status" ]; then
    warnings+=("Warning: $f — frontmatter incomplete; skipping.")
    continue
  fi
  case "$status" in
    Draft|Approved|Done|Dropped) ;;
    *) warnings+=("Warning: $f — unrecognized status \"$status\"; skipping."); continue ;;
  esac
  row="$(jq -n \
    --arg status "$status" --arg created "$created" --arg rfc "$rfc" \
    --arg title "$title"   --arg author  "$author" \
    '{status: $status, created: $created, rfc: $rfc, title: $title, author: $author}')"
  rows_json+=("$row")
done

# Combine rows into a JSON array, sort by (created, rfc), then assemble final object.
rows_array="$(
  if [ "${#rows_json[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${rows_json[@]}" | jq -s 'sort_by(.created, .rfc)'
  fi
)"

warnings_array="$(
  if [ "${#warnings[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .
  fi
)"

jq -n --argjson rfcs "$rows_array" --argjson warnings "$warnings_array" \
  '{rfcs: $rfcs, warnings: $warnings}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-summary.sh`.

Verification:

```bash
$ bash scripts/rfc-summary.sh | jq '.rfcs[:3]'
[
  {
    "status": "Done",
    "created": "2026-05-09",
    "rfc": "2026-05-09-best-practices-content-and-tooling",
    "title": "Best Practices Content and Tooling",
    "author": "Rodrigo Kochenburger"
  },
  {
    "status": "Done",
    "created": "2026-05-10",
    "rfc": "2026-05-10-agents-diff-skill",
    "title": "Agents Diff Skill",
    "author": "Rodrigo Kochenburger"
  },
  {
    "status": "Draft",
    "created": "2026-05-10",
    "rfc": "2026-05-10-audit-rework-agent-definitions",
    "title": "Audit Rework Agent Definitions",
    "author": "Rodrigo Kochenburger"
  }
]

$ bash scripts/rfc-summary.sh | jq '.warnings'
[]
```

(Actual statuses and titles reflect the real `docs/rfcs/` contents at the moment of run. The exact output depends on `docs/rfcs/` state — the verification is that the script emits one element per file in `.rfcs`, sorted by `created` then `rfc`, with `.warnings` capturing any per-file parse issues.)

#### Step 5 — Create `scripts/rfc-braindump-remove.sh` (P6)

Removes a single matching bullet from `docs/rfc-braindump.md`.

Write `scripts/rfc-braindump-remove.sh`:

```bash
#!/usr/bin/env bash
# Remove a single bullet entry from docs/rfc-braindump.md whose body matches the argument.
# Used by: rfc-new (after promoting a braindump entry to a full RFC).
#
# Args:
#   $1  Required. The full bullet body to match, *excluding* the leading "* " marker.
#       Whitespace is matched literally; the script does not strip.
#
# Output:
#   stdout: a single JSON object.
#     removed (exit 0):
#       {"removed": true, "file": "docs/rfc-braindump.md"}
#     not found (exit 1):
#       {"removed": false, "file": "docs/rfc-braindump.md"}
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  One entry removed.
#   1  Zero entries matched (no-op).
#   2  Usage error or docs/rfc-braindump.md missing.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-braindump-remove.sh <full-bullet-body-without-leading-star-space>"
  exit 2
fi
body="$1"
file="docs/rfc-braindump.md"

if [ ! -f "$file" ]; then
  emit_error "rfc-braindump-remove: $file not found"
  exit 2
fi

# Compose the exact line to match: "* <body>".
target="* $body"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# awk consumes the line equal to $target exactly once; subsequent matches (if any) are kept.
removed=0
awk -v target="$target" '
  BEGIN { done = 0 }
  {
    if (!done && $0 == target) { done = 1; next }
    print
  }
  END { exit (done ? 0 : 1) }
' "$file" > "$tmp" && removed=1 || removed=0

if [ "$removed" -eq 0 ]; then
  rm -f "$tmp"
  trap - EXIT
  jq -n --arg file "$file" '{removed: false, file: $file}'
  exit 1
fi

cat "$tmp" > "$file"
rm -f "$tmp"
trap - EXIT
jq -n --arg file "$file" '{removed: true, file: $file}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-braindump-remove.sh`.

Verification (using a temporary copy to avoid touching the real braindump):

```bash
$ cat > /tmp/test-braindump.md <<'EOF'
# RFC Braindump

* **Foo.** First entry.
* **Bar.** Second entry to remove.
* **Baz.** Third entry.
EOF
$ (cd /tmp && mkdir -p docs && cp test-braindump.md docs/rfc-braindump.md \
   && bash "$OLDPWD/scripts/rfc-braindump-remove.sh" '**Bar.** Second entry to remove.' | jq . \
   && cat docs/rfc-braindump.md)
{
  "removed": true,
  "file": "docs/rfc-braindump.md"
}
# RFC Braindump
#
# * **Foo.** First entry.
# * **Baz.** Third entry.
```

#### Step 6 — Create `scripts/rfc-feedback-list.sh` (P7)

Lists every `FEEDBACK:` marker line as a JSON array of `{line, text}` objects.

Write `scripts/rfc-feedback-list.sh`:

```bash
#!/usr/bin/env bash
# List every "FEEDBACK:" marker line in an RFC file as a JSON array of {line, text} objects.
# Used by: rfc-read-feedback.
#
# Args:
#   $1  Required. Path to an RFC file (.md).
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"markers": [{"line": 3, "text": "FEEDBACK: Add a step for X."}, ...]}
#       Empty array when no markers found. `text` is the full line including the
#       `FEEDBACK:` prefix.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Listing completed (zero or more markers found).
#   2  Usage error or file missing.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-feedback-list.sh <path-to-rfc.md>"
  exit 2
fi
file="$1"
if [ ! -f "$file" ]; then
  emit_error "rfc-feedback-list: file not found: $file"
  exit 2
fi

# Collect (line, text) tuples. grep prints "<lineno>:<line>"; split on the first colon.
# `|| true` so a zero-match grep does not propagate exit 1.
markers_json="$(
  grep -n '^FEEDBACK:' "$file" 2>/dev/null \
    | awk -F: '{
        n = $1
        # Reconstruct the line text by stripping the leading "<lineno>:".
        sub(/^[0-9]+:/, "")
        printf "%s\t%s\n", n, $0
      }' \
    | jq -R -s 'split("\n") | map(select(length > 0)) | map(
        split("\t") | {line: (.[0] | tonumber), text: .[1]}
      )' \
    || printf '[]'
)"

# If grep matched nothing, markers_json may be the empty array string already; ensure it is valid JSON.
if [ -z "$markers_json" ]; then
  markers_json='[]'
fi

jq -n --argjson markers "$markers_json" '{markers: $markers}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-feedback-list.sh`.

Verification:

```bash
$ printf '%s\n' \
  '## Summary' \
  'Some body text.' \
  'FEEDBACK: Add a step for X.' \
  '## Other section' \
  'FEEDBACK: This needs Y.' \
  > /tmp/test-feedback.md
$ bash scripts/rfc-feedback-list.sh /tmp/test-feedback.md | jq .
{
  "markers": [
    {"line": 3, "text": "FEEDBACK: Add a step for X."},
    {"line": 5, "text": "FEEDBACK: This needs Y."}
  ]
}
$ bash scripts/rfc-feedback-list.sh /tmp/test-feedback.md | jq '.markers | length'
2
```

#### Step 7 — Create `scripts/rfc-legacy-detect.sh` (P8)

Prints every `docs/rfcs/*.md` whose basename matches the legacy `NNN-` prefix.

Write `scripts/rfc-legacy-detect.sh`:

```bash
#!/usr/bin/env bash
# Emit a JSON object listing every RFC file under docs/rfcs/ whose basename matches the legacy NNN- prefix.
# Used by: rfc-update.
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"legacy_files": ["docs/rfcs/001-foo.md", ...]}
#       Empty array when no legacy files found.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Iteration completed.
#   2  docs/rfcs/ does not exist.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

if [ ! -d docs/rfcs ]; then
  jq -n --arg msg "rfc-legacy-detect: no docs/rfcs/ directory in $(pwd)" '{error: $msg}'
  exit 2
fi

# Collect paths whose basename starts with three digits followed by a hyphen.
# The basename test is necessary because docs/rfcs may itself contain digits in its path.
legacy=()
for f in docs/rfcs/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  case "$base" in
    [0-9][0-9][0-9]-*) legacy+=("$f") ;;
  esac
done

legacy_array="$(
  if [ "${#legacy[@]}" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "${legacy[@]}" | jq -R . | jq -s .
  fi
)"

jq -n --argjson legacy_files "$legacy_array" '{legacy_files: $legacy_files}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-legacy-detect.sh`.

Verification:

```bash
$ bash scripts/rfc-legacy-detect.sh | jq .
{
  "legacy_files": []
}

$ # Simulate a legacy file:
$ touch docs/rfcs/001-legacy-example.md
$ bash scripts/rfc-legacy-detect.sh | jq .
{
  "legacy_files": [
    "docs/rfcs/001-legacy-example.md"
  ]
}
$ rm docs/rfcs/001-legacy-example.md
```

#### Step 8 — Create `scripts/tool-probe.sh` (P4)

Single-purpose tool/plugin presence probe.

Write `scripts/tool-probe.sh`:

```bash
#!/usr/bin/env bash
# Probe whether a named tool or companion plugin is available.
# Used by: best-practices-extract, rfc-implement, refactor.
#
# Args:
#   $1  Required. Probe name. Recognized names:
#         gh                    -> command -v gh, plus `gh auth status`
#         git                   -> command -v git
#         jq                    -> command -v jq
#         github-mcp            -> grep enabledPlugins entry for github@claude-plugins-official
#         context7-mcp          -> grep enabledPlugins entry for context7@claude-plugins-official
#         code-review-mcp       -> grep enabledPlugins entry for code-review@claude-plugins-official
#
# Output:
#   stdout: a single JSON object.
#     available (exit 0):
#       {"result": "available", "name": "<probe-name>"}
#     missing (exit 1):
#       {"result": "missing", "name": "<probe-name>", "hint": "<remediation one-liner>"}
#     unauthenticated — gh only (exit 1):
#       {"result": "unauthenticated", "name": "gh", "hint": "gh CLI present but not authenticated. Run: gh auth login."}
#     usage error (exit 2):
#       {"error": "unrecognized probe name '<name>'"}
#   The `hint` field replaces what was previously on stderr. Callers show it or
#   suppress it based on context.
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Tool is available (and, for gh, authenticated).
#   1  Tool is missing or, for gh, present but not authenticated.
#   2  Usage error (unrecognized probe name).

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_available() {
  jq -n --arg name "$1" '{result: "available", name: $name}'
}

emit_missing() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "missing", name: $name, hint: $hint}'
}

emit_unauth() {
  jq -n --arg name "$1" --arg hint "$2" '{result: "unauthenticated", name: $name, hint: $hint}'
}

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: tool-probe.sh <gh|git|jq|github-mcp|context7-mcp|code-review-mcp>"
  exit 2
fi
name="$1"

# Helper: search project then user settings for an enabledPlugins entry.
# Precedence matches check-requirements.sh: project-false beats user-true (a project
# can explicitly disable a plugin even if the user has it enabled globally).
plugin_enabled() {
  local id="$1"
  local user_settings="$HOME/.claude/settings.json"
  local proj_settings=".claude/settings.json"
  # Project-level explicit false takes priority.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*false" "$proj_settings"; then return 1; fi
  # Project-level true.
  if [ -f "$proj_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$proj_settings"; then return 0; fi
  # User-level true (no project override).
  if [ -f "$user_settings" ] && grep -q "\"$id\"[[:space:]]*:[[:space:]]*true" "$user_settings"; then return 0; fi
  return 1
}

case "$name" in
  gh)
    if ! command -v gh >/dev/null 2>&1; then
      emit_missing "$name" "gh CLI not on PATH. Install: https://cli.github.com."
      exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
      emit_unauth "$name" "gh CLI present but not authenticated. Run: gh auth login."
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  git)
    if ! command -v git >/dev/null 2>&1; then
      emit_missing "$name" "git not on PATH. Install: https://git-scm.com/downloads."
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  jq)
    # By the time we reach here, `jq` is present (the startup guard above would
    # have exited otherwise). Report available; the missing-branch exists in
    # documentation form to keep the probe contract consistent.
    if ! command -v jq >/dev/null 2>&1; then
      # Static JSON string — safe without jq.
      printf '{"result":"missing","name":"jq","hint":"Install jq: https://stedolan.github.io/jq/download/"}\n'
      exit 1
    fi
    emit_available "$name"
    exit 0
    ;;
  github-mcp)
    if plugin_enabled "github@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "github@claude-plugins-official not enabled. Run: claude plugin install github@claude-plugins-official."
    exit 1
    ;;
  context7-mcp)
    if plugin_enabled "context7@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "context7@claude-plugins-official not enabled. Run: claude plugin install context7@claude-plugins-official."
    exit 1
    ;;
  code-review-mcp)
    if plugin_enabled "code-review@claude-plugins-official"; then
      emit_available "$name"; exit 0
    fi
    emit_missing "$name" "code-review@claude-plugins-official not enabled. Run: claude plugin install code-review@claude-plugins-official."
    exit 1
    ;;
  *)
    emit_error "unrecognized probe name '$name'"
    exit 2
    ;;
esac
```

Make executable: `chmod 755 scripts/tool-probe.sh`.

Verification:

```bash
$ bash scripts/tool-probe.sh gh | jq .; echo "exit=$?"
{
  "result": "available",
  "name": "gh"
}
exit=0

$ bash scripts/tool-probe.sh jq | jq .; echo "exit=$?"
{
  "result": "available",
  "name": "jq"
}
exit=0

$ bash scripts/tool-probe.sh nonsense; echo "exit=$?"
{"error":"unrecognized probe name 'nonsense'"}
exit=2
```

#### Step 9 — Create `scripts/rfc-braindump-append.sh` (P9)

Write-side counterpart to P6. Appends a bullet entry to `docs/rfc-braindump.md`, creating the file with the standard header if absent.

Write `scripts/rfc-braindump-append.sh`:

```bash
#!/usr/bin/env bash
# Append a bullet entry to docs/rfc-braindump.md.
# Creates the file with the standard header if absent.
# Used by: rfc-braindump (step 4).
#
# Args:
#   $1  Required. The full bullet body, *excluding* the leading "* " marker.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0):
#       {"appended": true, "file": "docs/rfc-braindump.md", "created_file": <true|false>}
#       `created_file` is true when the file did not previously exist.
#     error (exit 2):
#       {"error": "<message>"}
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Entry appended.
#   2  Usage error.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

emit_error() {
  jq -n --arg msg "$1" '{error: $msg}'
}

if [ "${1:-}" = "" ]; then
  emit_error "usage: rfc-braindump-append.sh <full-bullet-body-without-leading-star-space>"
  exit 2
fi
body="$1"
file="docs/rfc-braindump.md"

created_file=false
if [ ! -f "$file" ]; then
  printf '# RFC Braindump\n\nPotential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.\n\n' > "$file"
  created_file=true
fi

printf '* %s\n' "$body" >> "$file"

jq -n --arg file "$file" --argjson created "$created_file" \
  '{appended: true, file: $file, created_file: $created}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-braindump-append.sh`.

Verification:

```bash
$ bash scripts/rfc-braindump-append.sh '**Foo.** First braindump entry.' | jq .
{
  "appended": true,
  "file": "docs/rfc-braindump.md",
  "created_file": false
}

$ tail -1 docs/rfc-braindump.md
* **Foo.** First braindump entry.
```

#### Step 10 — Create `scripts/rfc-braindump-list.sh` (P10)

Lists every `* `-prefixed bullet from `docs/rfc-braindump.md` as a JSON array of numbered `{n, body}` objects for `rfc-new` step 1.

Write `scripts/rfc-braindump-list.sh`:

```bash
#!/usr/bin/env bash
# List bullet entries from docs/rfc-braindump.md as a JSON array of {n, body} objects.
# Used by: rfc-new (step 1 braindump selection).
#
# Args: none.
#
# Output:
#   stdout: a single JSON object.
#     success (exit 0 always):
#       {"entries": [{"n": 1, "body": "<body-without-leading-star-space>"}, ...]}
#       Empty array when file absent or no bullet entries.
#   stderr: empty under normal operation.
#
# Exit codes:
#   0  Listing completed (zero or more entries).
#   (never exits non-zero — absence of entries is not an error)

set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '{"error":"jq not found on PATH"}\n'; exit 2; }

file="docs/rfc-braindump.md"

if [ ! -f "$file" ]; then
  jq -n '{entries: []}'
  exit 0
fi

# Collect bodies in file order.
bodies=()
while IFS= read -r line; do
  case "$line" in
    '* '*)
      body="${line#\* }"
      bodies+=("$body")
      ;;
  esac
done < "$file"

entries_array="$(
  if [ "${#bodies[@]}" -eq 0 ]; then
    printf '[]'
  else
    # Use jq to build the array with 1-based indices.
    printf '%s\n' "${bodies[@]}" \
      | jq -R . \
      | jq -s 'to_entries | map({n: (.key + 1), body: .value})'
  fi
)"

jq -n --argjson entries "$entries_array" '{entries: $entries}'
exit 0
```

Make executable: `chmod 755 scripts/rfc-braindump-list.sh`.

Verification:

```bash
$ bash scripts/rfc-braindump-list.sh | jq .
{
  "entries": [
    {"n": 1, "body": "**Foo.** First braindump entry."},
    {"n": 2, "body": "**Bar.** Second braindump entry."}
  ]
}

$ bash scripts/rfc-braindump-list.sh | jq '.entries | length'
2
```

#### Step 11 — Update `skills/rfc-approve/SKILL.md`

Read the current file (verified: `skills/rfc-approve/SKILL.md:L1-L58`). The current step 1 (lines 14-20) describes the resolution heuristic in prose; step 2 (lines 22-30) describes the status check; step 4 (line 49) describes the status mutation; step 5 (lines 53-55) describes the commit.

Replace step 1 prose with:

```markdown
### 1. Identify the RFC

Resolve the target RFC using the helper script. The script handles the argument-vs-heuristic logic; the agent surfaces the candidate label to the user. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash scripts/rfc-resolve.sh "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

`$RFC_PATH` is the resolved absolute path; `$label` is a one-line summary such as `RFC 2026-05-12-foo (unique modified file)`. Show `$label` and ask "Use this RFC? (yes/no)" — accept blank as yes. If the user declines, ask "Which RFC?" and re-run with their answer as `$ARG`. If the script exited non-zero, `result` will contain `{"error":"..."}` — extract with `jq -r .error` and show it. `$RFC_PATH` is used by subsequent steps to identify the file being acted on.
```

Replace step 2 prose with:

```markdown
### 2. Verify status

Read the frontmatter:

```bash
fm="$(bash scripts/rfc-frontmatter.sh "$RFC_PATH")"
status="$(printf '%s' "$fm" | jq -r .status)"
drop_reason="$(printf '%s' "$fm" | jq -r .drop_reason)"
```

If `$status` is not `Draft`:
- `Approved` → "Already approved."
- `Done` → "Already done."
- `Dropped` → "This RFC was dropped: $drop_reason."

Stop in any of these cases.
```

Replace step 4 prose with:

```markdown
### 4. Update status

```bash
result="$(bash scripts/rfc-set-status.sh "$RFC_PATH" Approved)"
old="$(printf '%s' "$result" | jq -r .old_status)"
new="$(printf '%s' "$result" | jq -r .new_status)"
```

The script validates the new status and rewrites the frontmatter in place. Use `$old` and `$new` in the agent's running log (e.g., `rfc-set-status: <path>: Draft -> Approved`).
```

Step 5 (commit) stays as-is. Step 3 (display summary for confirmation) also stays as-is — that prompt is skill-specific, not generic.

#### Step 12 — Update `skills/rfc-drop/SKILL.md`

Same surgery as `rfc-approve`, with the status-mutation call passing `Dropped` and the drop reason:

```markdown
### 1. Identify the RFC and reason

Resolve the target RFC. `$ARG` is the user-supplied identifier from the skill's argument, if any; omit it to let the script use the heuristic fallbacks.

```bash
result="$(bash scripts/rfc-resolve.sh "${ARG:-}")"
RFC_PATH="$(printf '%s' "$result" | jq -r .path)"
label="$(printf '%s' "$result" | jq -r .label)"
```

(Same confirmation flow as rfc-approve: show `$label`, ask the user to confirm. On non-zero exit, parse `.error` from `$result` and show it. `$RFC_PATH` carries the resolved absolute path into the steps below.)

If the drop reason is not provided, ask: "Why is this RFC being dropped? (one sentence)"

### 2. Read and verify status

```bash
fm="$(bash scripts/rfc-frontmatter.sh "$RFC_PATH")"
status="$(printf '%s' "$fm" | jq -r .status)"
drop_reason="$(printf '%s' "$fm" | jq -r .drop_reason)"
```

If `$status` is `Done` → "This RFC is already done — it cannot be dropped." If `Dropped` → "Already dropped: $drop_reason." Stop in either case.

### 4. Update frontmatter

```bash
result="$(bash scripts/rfc-set-status.sh "$RFC_PATH" Dropped "$REASON")"
```

The script writes `status: "Dropped"` and `drop_reason: "<REASON>"` atomically. If `$REASON` is empty the script exits 2 with `{"error":"..."}` on stdout — extract via `jq -r .error` and re-prompt for a reason.
```

Step 3 (confirm dialog) and step 5 (commit) stay as-is.

#### Step 13 — Update `skills/rfc-implement/SKILL.md`

The Requirement check block (lines 9-17) describes the GitHub MCP / gh probe in prose. Replace with two `tool-probe.sh` calls:

```markdown
## Requirement check

This skill creates a pull request at the end of implementation. PR creation uses the GitHub MCP when available, falling back to the `gh` CLI:

```bash
mcp_out="$(bash scripts/tool-probe.sh github-mcp)"; mcp_status=$?
gh_out="$(bash scripts/tool-probe.sh gh)";           gh_status=$?
mcp_result="$(printf '%s' "$mcp_out" | jq -r .result)"
gh_result="$(printf '%s' "$gh_out"  | jq -r .result)"
```

- `mcp_status=0` (i.e. `$mcp_result` = `available`) → use the `mcp__plugin_github_github__create_pull_request` MCP tool. Print: `Using GitHub MCP for PR creation.`
- `mcp_status!=0 && gh_status=0` → fall back to `gh pr create`. Print: `GitHub MCP not enabled — using gh CLI for PR creation.`
- both nonzero → abort PR creation with: `Cannot create PR: neither GitHub MCP nor gh CLI is available. Fix: install github@claude-plugins-official OR install gh CLI and run gh auth login.` (Use `printf '%s' "$gh_out" | jq -r .hint` and the matching hint from `$mcp_out` to phrase the remediation precisely.)

`$gh_result` carries one of `available`, `missing`, or `unauthenticated`; use it when the message text needs to distinguish "gh not installed" from "gh not logged in." The implementation itself (code edits, commit, push) completes regardless of which PR-creation path is taken.
```

Replace step 1 (lines 23-31) with the same `rfc-resolve.sh` pattern as `rfc-approve` (capture stdout into `result`, then `jq -r .path` into `$RFC_PATH` and `jq -r .label` into `$label`). Replace step 5 (lines 57-61) with:

```markdown
### 5. Mark Done after merge

After the PR is merged:

```bash
result="$(bash scripts/rfc-set-status.sh "$RFC_PATH" Done)"
git add "$RFC_PATH"
git commit -m "rfc: mark $(basename "${RFC_PATH%.md}") done"
```

`$result` is the JSON object `{"file": "...", "old_status": "Approved", "new_status": "Done"}` — extract fields with `jq -r` if the agent wants to surface the transition in its log. Report: "RFC <identifier> marked as Done."
```

#### Step 14 — Update `skills/rfc-consensus-review/SKILL.md`

Step 1 (lines 31-37) describes resolution. Replace with the `rfc-resolve.sh` call (same shape as `rfc-approve` step 1 — capture stdout into `result`, extract `$RFC_PATH` via `jq -r .path` and `$label` via `jq -r .label`). All other steps stay as-is — consensus review's main work is agent dispatch and synthesis, which is not script-shaped.

#### Step 15 — Update `skills/rfc-read-feedback/SKILL.md`

Step 1 (lines 23-30) → `rfc-resolve.sh` (same `result` / `jq -r .path` / `jq -r .label` capture as `rfc-approve`). Step 2 (lines 32-40) → `rfc-feedback-list.sh`:

```markdown
### 2. Find all FEEDBACK: markers

```bash
result="$(bash scripts/rfc-feedback-list.sh "$RFC_PATH")"
count="$(printf '%s' "$result" | jq '.markers | length')"
```

`$result` is the JSON object `{"markers": [{"line": N, "text": "FEEDBACK: ..."}]}`. If `$count` equals 0: report **"No FEEDBACK: markers found in <filename>."** and stop. Otherwise iterate `printf '%s' "$result" | jq -r '.markers[] | "\(.line)\t\(.text)"'` to display rows to the user for step 3.
```

Step 3, 4, 5 stay as-is.

#### Step 16 — Update `skills/rfc-summary/SKILL.md`

Steps 2 and 3 (lines 26-56) describe the full enumerate/parse/sort pipeline in prose plus a 16-line awk-and-shell block. Replace with:

```markdown
### 2. Enumerate, parse, and sort

```bash
result="$(bash scripts/rfc-summary.sh)"
```

`$result` is a JSON object `{"rfcs": [...], "warnings": [...]}`. Extract:

```bash
rfcs="$(printf '%s' "$result" | jq -c '.rfcs')"
warnings="$(printf '%s' "$result" | jq -r '.warnings[]?')"
```

`$rfcs` is a JSON array sorted ascending by `created` then by `rfc` identifier. Iterate it with `printf '%s' "$rfcs" | jq -c '.[]'` to grab each row as an object for step 3's grouping. Print any per-file `$warnings` (incomplete frontmatter, unrecognized status) so the user sees them before the rendered summary. Exit code 2 only if `docs/rfcs/` does not exist — in that case `$result` contains `{"error":"..."}` (extract via `jq -r .error`) and step 1's "no RFC directory" message is shown.
```

Step 1 (pre-flight directory check), step 3's grouping/rendering logic (Approved / Draft / Other) and step 4 (Markdown rendering) remain in the skill — those are presentation concerns, not data extraction.

#### Step 17 — Update `skills/rfc-update/SKILL.md`

Step 3 (lines 62-66) has a one-line legacy detection `ls | grep`. Replace with:

```markdown
### 3. Migrate legacy NNN-named RFCs (if present)

```bash
result="$(bash scripts/rfc-legacy-detect.sh)"
legacy_count="$(printf '%s' "$result" | jq '.legacy_files | length')"
```

If `$legacy_count` is greater than 0, iterate the paths with `printf '%s' "$result" | jq -r '.legacy_files[]'` and offer to migrate (existing prose unchanged). If `$legacy_count` is 0, skip and continue.
```

#### Step 18 — Update `skills/rfc-new/SKILL.md`

**Step 1 (braindump listing) — P10.** Replace the prose "If no argument is provided, check whether `docs/rfc-braindump.md` exists and contains bullet entries…" with:

```markdown
### 1. Get description

If an argument is provided, use it as the description and proceed to Step 2.

If no argument is provided:

```bash
result="$(bash scripts/rfc-braindump-list.sh)"
entries_count="$(printf '%s' "$result" | jq '.entries | length')"
```

If `$entries_count` is greater than 0, iterate with `printf '%s' "$result" | jq -r '.entries[] | "\(.n)\t\(.body)"'` to present them as a numbered list and ask "Pick a number to promote, or describe a new RFC." If the user picks a number `N`, use `printf '%s' "$result" | jq -r --argjson n "$N" '.entries[] | select(.n == $n) | .body'` as the description. If they type something else, use that as the description.

If `$entries_count` is 0 (no braindump file or no entries), ask: "What is this RFC about?"
```

**Step 6 (braindump removal) — P6.** Replace the existing prose with:

```markdown
### 6. Remove promoted braindump entry

If the description came from a `docs/rfc-braindump.md` entry (the user selected a number in Step 1), remove that bullet:

```bash
result="$(bash scripts/rfc-braindump-remove.sh "$SELECTED_ENTRY_BODY")"
removed="$(printf '%s' "$result" | jq -r .removed)"
```

Where `$SELECTED_ENTRY_BODY` is the full bullet text *excluding* the leading `* ` marker (e.g., `**Foo.** First entry.`). If `$removed` is `false` (script exited 1), treat as a warning, not an error — the entry may have been removed already. If the description was typed directly by the user (not selected from the braindump list), skip this step.
```

#### Step 19 — Update `skills/rfc-braindump/SKILL.md`

Step 4 (lines 40-51) describes appending to `docs/rfc-braindump.md` in prose. Replace with:

```markdown
### 4. Append to `docs/rfc-braindump.md`

```bash
result="$(bash scripts/rfc-braindump-append.sh "$ENTRY_BODY")"
created_file="$(printf '%s' "$result" | jq -r .created_file)"
```

Where `$ENTRY_BODY` is the formatted bullet text from Step 3 (*excluding* the leading `* ` marker), e.g., `**Title.** Paragraph text.`. The script creates the file with the standard header if absent — `$created_file` is `true` in that case, useful when the agent wants to surface "created docs/rfc-braindump.md" in its running log alongside the standard "appended" message.
```

Step 5 (confirmation) stays as-is — that is skill-specific presentation logic.

#### Step 20 — Update `skills/best-practices-extract/SKILL.md`

The Requirement check (lines 9-17) probes for `gh`. Replace with:

```markdown
## Requirement check

This skill optionally enriches its output with PR context from the GitHub CLI. The CLI is a soft dependency:

```bash
result="$(bash scripts/tool-probe.sh gh)"; gh_status=$?
gh_result="$(printf '%s' "$result" | jq -r .result)"
```

- `gh_status=0` (and `$gh_result` = `available`) → use `gh` for PR context as designed.
- `gh_status=1` and `$gh_result` = `missing` → print exactly: `gh CLI not on PATH — extracting without PR context.` and continue. (Use `printf '%s' "$result" | jq -r .hint` if a longer remediation hint is needed.)
- `gh_status=1` and `$gh_result` = `unauthenticated` → print exactly: `gh CLI not logged in — extracting without PR context.` and continue.

The skill must not fail or block on this missing dependency; it must produce its primary output regardless.
```

#### Step 21 — Update `skills/refactor/SKILL.md`

The Requirement check (lines 9-17) probes for the `code-review` plugin. Replace with:

```markdown
## Requirement check

This skill optionally invokes the `/review` slash command (from the `code-review@claude-plugins-official` plugin) for a pre-pass before refactoring:

```bash
result="$(bash scripts/tool-probe.sh code-review-mcp)"; status=$?
cr_result="$(printf '%s' "$result" | jq -r .result)"
```

- `status=0` (and `$cr_result` = `available`) → run the pre-pass as designed.
- `status=1` (and `$cr_result` = `missing`) → print exactly: `code-review@claude-plugins-official not enabled — running /refactor without pre-pass review.` and proceed directly to the analysis phase. (`printf '%s' "$result" | jq -r .hint` returns the install hint if the agent wants a longer message.)

The refactor must produce its primary output (the analysis + plan + approval gate + apply phases) regardless of whether the pre-pass ran.
```

#### Step 22 — Add bats-core testing infrastructure

Install bats-core and its companion libraries as git submodules pinned to known-good versions:

```bash
git submodule add https://github.com/bats-core/bats-core     tests/bats-core
git submodule add https://github.com/bats-core/bats-support   tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert    tests/test_helper/bats-assert
git submodule add https://github.com/bats-core/bats-file      tests/test_helper/bats-file

cd tests/bats-core                  && git checkout v1.13.0 && cd -
cd tests/test_helper/bats-support   && git checkout v0.3.0  && cd -
cd tests/test_helper/bats-assert    && git checkout v2.2.4  && cd -
cd tests/test_helper/bats-file      && git checkout v0.4.0  && cd -
```

Run the tests with:

```bash
tests/bats-core/bin/bats tests/scripts/
```

Write `tests/scripts/helpers.bash` (sourced by all test files):

```bash
# Shared helpers for tests/scripts/*.bats.
# Load in setup() via: load "helpers"
#
# Each test runs with CWD = TEST_TMPDIR (an isolated temp project root).
# Scripts use relative paths (docs/rfcs/, docs/rfc-braindump.md) and will
# find them inside TEST_TMPDIR, never inside the real project.
#
# SCRIPT_ROOT is set to the real project root so test files can reference
# scripts/ via absolute path: bash "$SCRIPT_ROOT/scripts/rfc-resolve.sh"

setup_common() {
  load "../../test_helper/bats-support/load"
  load "../../test_helper/bats-assert/load"
  load "../../test_helper/bats-file/load"
  # bats-file is now loaded; temp_make is available.
  TEST_TMPDIR="$(temp_make --prefix 'rfc-scripts-test-')"
  export TEST_TMPDIR
  # Absolute path to real project scripts/.
  SCRIPT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SCRIPT_ROOT
  # Pre-create the docs/ hierarchy so scripts don't fail on missing dirs.
  mkdir -p "$TEST_TMPDIR/docs/rfcs"
  # Run all scripts with CWD = TEST_TMPDIR so they see the fixture tree.
  cd "$TEST_TMPDIR"
}

teardown_common() {
  cd "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}" || cd / || true
  temp_del "$TEST_TMPDIR"
}

# Create a minimal docs/rfcs/<name>.md fixture in the current directory.
# Usage: create_rfc_fixture <stem> [status] [drop_reason]
# drop_reason is a raw drop_reason text (any YAML-significant characters are
# safely escaped). Pass "~" (the default) to emit the YAML-null sentinel.
create_rfc_fixture() {
  local name="$1" status="${2:-Draft}" drop_reason_raw="${3:-~}"
  local dr_yaml
  if [ "$drop_reason_raw" = "~" ]; then
    dr_yaml="~"
  else
    local escaped="${drop_reason_raw//\"/\\\"}"
    dr_yaml="\"$escaped\""
  fi
  mkdir -p docs/rfcs
  cat > "docs/rfcs/${name}.md" <<EOF
---
rfc: "$name"
title: "Test RFC"
author: "Test User"
status: "$status"
created: "2026-01-01"
drop_reason: $dr_yaml
---

## Summary

Test summary paragraph.
EOF
}

# Create a docs/rfc-braindump.md fixture in the current directory.
# Usage: create_braindump_fixture <body1> [<body2> ...]
create_braindump_fixture() {
  mkdir -p docs
  printf '# RFC Braindump\n\nPotential RFC ideas.\n\n' > docs/rfc-braindump.md
  for body in "$@"; do
    printf '* %s\n' "$body" >> docs/rfc-braindump.md
  done
}
```

Write one test file per script. Each test file follows this pattern (example: `tests/scripts/rfc-frontmatter.bats`):

```bash
#!/usr/bin/env bats
# Tests for scripts/rfc-frontmatter.sh

setup() {
  load "helpers"
  setup_common   # sets SCRIPT_ROOT, TEST_TMPDIR; cds to TEST_TMPDIR
  SCRIPT="$SCRIPT_ROOT/scripts/rfc-frontmatter.sh"
  create_rfc_fixture 2026-01-01-test-rfc
  FIXTURE="docs/rfcs/2026-01-01-test-rfc.md"
}

teardown() {
  teardown_common
}

@test "emits JSON with all six fields" {
  run bash "$SCRIPT" "$FIXTURE"
  assert_success
  assert_equal "$(echo "$output" | jq -r .rfc)"    "2026-01-01-test-rfc"
  assert_equal "$(echo "$output" | jq -r .title)"  "Test RFC"
  assert_equal "$(echo "$output" | jq -r .author)" "Test User"
  assert_equal "$(echo "$output" | jq -r .status)" "Draft"
  assert_equal "$(echo "$output" | jq -r .created)" "2026-01-01"
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "normalizes drop_reason ~ to empty string" {
  create_rfc_fixture 2026-01-01-tilde Draft "~"
  run bash "$SCRIPT" "docs/rfcs/2026-01-01-tilde.md"
  assert_success
  assert_equal "$(echo "$output" | jq -r .drop_reason)" ""
}

@test "exits 2 on missing file — error field present" {
  run bash "$SCRIPT" "docs/rfcs/does-not-exist.md"
  assert_failure 2
  assert_equal "$(echo "$output" | jq -r .error | cut -c1-3)" "rfc"  # starts with "rfc-"
}

@test "exits 2 with no arguments — error field present" {
  run bash "$SCRIPT"
  assert_failure 2
  run bash -c "echo '$output' | jq -e .error"
  assert_success
}
```

All assertions use `jq -r .<field>` to extract fields from the JSON output. Every test file must cover at minimum:
- **Happy path** — correct input produces the expected JSON output (assert via `jq -r .<field>` per field).
- **Usage error (exit 2)** — missing required argument, file not found, or invalid argument value. Assert `.error` is present in stdout via `jq -e .error`.
- **"Not found" / no-op (exit 1)** — for scripts that distinguish "checked and the answer is no" from hard errors (e.g., `rfc-braindump-remove.sh` with no matching entry, `tool-probe.sh` when tool is absent). Assert the JSON has the documented "no-op" shape (e.g., `{"removed": false}` or `{"result": "missing"}`).
- **Edge case** — at least one per script: empty braindump file, RFC with all-default `drop_reason: ~`, zero FEEDBACK markers, etc.

Coverage requirements per script:

| Script | Required additional cases |
|--------|--------------------------|
| `rfc-resolve.sh` | explicit arg (match), explicit arg (no match → exit 1), arg with `/` (→ exit 2), no arg + 1 modified RFC (heuristic), no arg + 0 modified RFCs (fallback to latest), no RFC files at all (→ exit 1) |
| `rfc-frontmatter.sh` | (covered by example above) |
| `rfc-set-status.sh` | Draft→Approved, Approved→Done, Draft→Dropped (with reason), Dropped without reason (→ exit 2), drop_reason with non-Dropped status (→ exit 2), inject drop_reason when field absent |
| `rfc-summary.sh` | empty docs/rfcs/ (0 rows), single RFC, multiple RFCs sorted correctly, RFC with unrecognized status (warn + skip), RFC with empty `rfc` field (warn + skip) |
| `rfc-braindump-remove.sh` | exact match removed, no match (→ exit 1), only-first-match removed when duplicates |
| `rfc-braindump-append.sh` | append to existing file, create file with header when absent, multiple appends accumulate |
| `rfc-braindump-list.sh` | absent file (0 lines), file with entries numbered correctly, file with header lines skipped |
| `rfc-feedback-list.sh` | zero markers (0 lines, exit 0), two markers (correct lineno+text), non-`FEEDBACK:` lines not emitted |
| `rfc-legacy-detect.sh` | no legacy files (0 lines), one legacy, mixed legacy+modern (only legacy emitted) |
| `tool-probe.sh` | `gh` available (exit 0, `.result == "available"`), `gh` missing (exit 1, `.result == "missing"`, `.hint` non-empty), `jq` available (exit 0, `.result == "available"`), unrecognized name (exit 2, `.error` present), `github-mcp` with project-false override (exit 1, `.result == "missing"`) |

Verification:

```bash
$ tests/bats-core/bin/bats tests/scripts/
 ✓ rfc-frontmatter: emits JSON with all six fields
 ✓ rfc-frontmatter: normalizes drop_reason ~ to empty string
 ...
 ✓ tool-probe: github-mcp with project-false override returns missing

50 tests, 0 failures
```

The exact count will grow as cases are added; the table above is the minimum bar.

#### Step 23 — Run tests and verify end-to-end

**First, run the bats suite:**

```bash
tests/bats-core/bin/bats tests/scripts/
```

All tests must pass before proceeding to the smoke test below. Any failing test indicates a script regression introduced during implementation — fix the script, not the test (the tests are the spec).

**Then run a manual smoke test** of one skill that touches every script (RFC lifecycle):

1. `bash scripts/rfc-resolve.sh | jq .` (no arg) — should pick up this RFC as the unique modified file and print a `{"path": "...", "label": "..."}` object.
2. `RFC_PATH="$(bash scripts/rfc-resolve.sh | jq -r .path)" && bash scripts/rfc-frontmatter.sh "$RFC_PATH" | jq -r .status` — should print `Draft`.
3. Create a temporary scratch RFC: `cp docs/rfcs/2026-05-14-skill-helper-scripts.md docs/rfcs/2099-01-01-scratch.md`.
4. `bash scripts/rfc-set-status.sh docs/rfcs/2099-01-01-scratch.md Approved | jq .` — should print a `{"file": "...", "old_status": "Draft", "new_status": "Approved"}` object.
5. `bash scripts/rfc-summary.sh | jq '.rfcs[] | select(.rfc == "2099-01-01-scratch")'` — should show the scratch RFC under Approved.
6. `rm docs/rfcs/2099-01-01-scratch.md` — clean up.
7. `bash scripts/tool-probe.sh gh | jq -r .result` — should print `available` (or `missing` / `unauthenticated` if gh is not installed/logged in; use `jq -r .hint` to see the remediation).
8. `bash scripts/tool-probe.sh jq | jq -r .result` — should print `available` (this RFC's hard dependency check).
9. `bash scripts/rfc-braindump-list.sh | jq '.entries[:3]'` — should list the first three braindump entries.
10. `bash scripts/rfc-braindump-append.sh '**Smoke test entry.** Created during implementation verification.' | jq -r .appended && bash scripts/rfc-braindump-remove.sh '**Smoke test entry.** Created during implementation verification.' | jq -r .removed` — round-trip: both should print `true`.

## Risks and open questions

**Risk: script drift from skill prose.** If a script's behavior changes (e.g., `rfc-resolve.sh` learns a new fallback) and the skill files are not updated, the user-facing description of the skill diverges from what the script actually does. Mitigation: every script's header comment is treated as the source of truth for its contract, and the skill files quote the script's documented behavior rather than re-describing it. Reviews touching either side are expected to check the other. This is a process risk, not a technical one — there is no automation to prevent it.

**Risk: scripts shadow logic that would otherwise be reasoned about.** When an agent reads "run `bash scripts/rfc-resolve.sh`," it may stop reasoning about edge cases the resolver handles, which is mostly good but occasionally bad — e.g., when the agent should notice a malformed argument and ask the user before invoking the script. Mitigation: the scripts fail loudly (exit 2 with a clear `{"error":"..."}` JSON object on stdout) when given bad input, so the agent surfaces the failure rather than silently producing wrong output.

**Risk: bash strict-mode gotchas in the scripts themselves.** `set -e` does not behave as expected inside `if`, `while`, `&&`, `||`, or `!` contexts (Exa: https://linuxiq.org/shell-scripting-practical-notes-from-production/). Mitigation: the scripts are short (each fits on a single screen), use `set -uo pipefail` (deliberately omitting `-e` where pipelines and `|| true` are load-bearing — `rfc-feedback-list.sh` is the clear example), and have verification snippets in this RFC that demonstrate exit codes for the expected cases.

**Risk: `jq` as a hard dependency.** Every script now requires `jq` on `PATH`; if it is absent, all ten scripts exit 2 immediately. `jq` ships in most Linux distributions (Debian/Ubuntu: `apt install jq`; Fedora: `dnf install jq`) and is trivially installed on macOS via `brew install jq`, but it is not a standard POSIX utility. Mitigation: `tool-probe.sh jq` gives skills a one-line presence check; the session-start hook should surface a warning when jq is missing so users see it before their first RFC skill invocation rather than inside one. Adding `jq` to `scripts/check-requirements.sh` is the right follow-up to make this enforcement automatic.

**Risk: test fixtures drift from real-world RFC frontmatter.** The bats tests create minimal `create_rfc_fixture` output that matches the current frontmatter schema. If a future RFC adds a new frontmatter field, the fixture may not exercise it, and `rfc-frontmatter.sh` may silently emit an empty value instead of the real content. Mitigation: update `helpers.bash` whenever the frontmatter schema changes, and add a test case that covers the new field. The `rfc-process.md` "Required YAML frontmatter" section is the authoritative schema; treat any change there as a trigger to review `helpers.bash`.

**Open question: should `scripts/` be added to the bootstrap manifest?** Verified `against .claude-plugin/bootstrap-manifest.json:L1-L100`: the manifest tracks consumer-distributed artifacts only (every `source` is under `.claude-plugin/scripts/templates/`, every `target` is a consumer-repo path). Plugin-internal scripts under `scripts/` are *not* distributed to consumers — they live with the plugin checkout and skills invoke them via `bash scripts/<name>.sh`. The answer is therefore "no": these scripts ship as part of the plugin, like `scripts/check-requirements.sh` does today, and `/sync` does not need to know about them. This is recorded here so the question does not have to be re-litigated when the manifest is next reviewed.

**Open question: should skills invoke scripts via a path that survives reorganization?** The skill prose says `bash scripts/<name>.sh`, which assumes the caller's working directory is the project root. For the RFC skills this is always true (they operate on `docs/rfcs/` in the same root). If a future skill needs to invoke a script from elsewhere, the pattern is to source `scripts/_lib/resolve-plugin-root.sh` first and use `$BW_PLUGIN_ROOT/scripts/<name>.sh`. This RFC does not change current skill invocations because they all already run with `pwd` = project root.

**Open question: pre-commit linting.** Should `shellcheck` (Exa: https://www.shellcheck.net/) be added to a pre-commit hook to catch bash issues in the new scripts, complementing the bats unit tests? Out of scope for this RFC, but a natural follow-up. The existing `.claude-plugin/hooks/pre-commit/` directory is the right home for it (verified: `.claude-plugin/hooks/pre-commit` exists in the tree). A CI step running `tests/bats-core/bin/bats tests/scripts/` would complement shellcheck for behavioral coverage.

## Relationship to other RFCs

**Depends on:** none. The existing `scripts/check-requirements.sh` and `hooks/hooks.json` are the only pre-existing artifacts this RFC builds on; both are stable.

**Conflicts with:** none.

**Adjacent:** 2026-05-12-rfc-summary-command (already shipped, status=Done — added the `rfc-summary` skill that this RFC simplifies). 2026-05-12-evidence-based-research-rfc-architect (status=Done — established the citation conventions used in this RFC's evidence audit).

**Enables (future):** any future RFC that wants to add a new automation script for skills — the conventions established here (script location, naming, header comment shape, stdout contract, exit code semantics, bash strict-mode posture) are the template. Specifically, a CI job that runs `shellcheck scripts/*.sh` becomes trivial once this RFC lands, and a future RFC that wires the rfc-* scripts into the SessionStart requirement check has a clear starting point.
