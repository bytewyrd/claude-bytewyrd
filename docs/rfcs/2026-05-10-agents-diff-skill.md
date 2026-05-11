---
rfc: "2026-05-10-agents-diff-skill"
title: "/agents-diff: Upstream vs Local Diff for Vendored Agent Definitions"
author: "Rodrigo Kochenburger"
status: "Draft"
created: "2026-05-10"
drop_reason: ~
---

## Summary

Add a plugin-local `/agents-diff` skill that fetches the current contents of every agent file from `VoltAgent/awesome-claude-code-subagents` (the upstream library the local `agents/` directory was originally vendored from) and presents a per-file unified diff against the local copies — without applying any changes. The skill is read-only by design: it restores the visibility into upstream evolution that was lost when `/agents-update` was removed in RFC `2026-05-10-refactor-command`, while preserving the new ownership posture that the local copies are authoritative and never auto-overwritten. A maintainer who wants to incorporate an upstream improvement does so manually, file by file, after reviewing the diff.

## Should we do this?

**Yes.** RFC `2026-05-10-refactor-command` made local ownership of `agents/` a permanent posture by removing `/agents-update`, but it also created a discoverability gap that the same RFC explicitly flagged as a follow-up: "if a future RFC wants a more structured 'see what's changed upstream' workflow, it can add a read-only diff command (`/agents-diff` or similar) that surfaces changes without overwriting." Without that surface, the only way a maintainer learns about upstream improvements is by clicking through 140+ files in the GitHub UI by hand, which means in practice they never do. The braindump entry that spawned this RFC frames the same need from the maintainer side: "no easy way to know when interesting upstream improvements exist." A read-only diff command is cheap (one plugin-local skill, no plugin.json registration, no agent changes, no destructive operations) and resolves the gap with the safety profile the previous RFC's decision requires — view-only, the maintainer ports changes manually. Cost is one single `SKILL.md` (~300 lines including embedded shell) plus a one-line braindump removal; payoff is making upstream evolution visible without giving up local ownership.

## Current state

`agents/` is a permanent local copy of the agent definitions originally vendored from `VoltAgent/awesome-claude-code-subagents` (MIT). RFC `2026-05-10-refactor-command` removed the `/agents-update` skill that previously synced this directory from upstream, on the rationale that the sync mechanism would silently revert local customizations. The trade-off was explicit: local ownership is permanent, and upstream improvements must be brought in manually on a case-by-case basis.

**What exists today:**

- `agents/` — 46 agent definition files (`*.md`), each with YAML frontmatter (`name`, `description`, optional `tools`, optional `color`) followed by the agent's system prompt. The local copies are the source of truth for any agent shipped by this plugin.
- `.claude/skills/agents-update/SKILL.md` — has been deleted as specified by RFC `2026-05-10-refactor-command` (status: Done). The prior auto-sync workflow it defined (fetch the upstream tree via the GitHub Trees API, diff filenames, prompt for which files to overwrite, then download the approved files to `agents/`) is no longer available. `/agents-diff` is being designed as the read-only replacement for the visibility that workflow provided, with no overwrite step.
- Upstream repository: `https://github.com/VoltAgent/awesome-claude-code-subagents`. Agent files live under `categories/<category>/<agent-name>.md` (e.g., `categories/02-language-specialists/python-pro.md`). The repository's default branch is `main`. License is MIT, which permits the use, modification, and redistribution this plugin already relies on.
- `.claude/skills/` directory — already established as the location for plugin-local maintenance skills that are not exported to plugin consumers (the `best-practices-sync` skill lives here). The directory is not registered in `.claude-plugin/plugin.json`; Claude Code discovers skills in `.claude/skills/` automatically when invoked inside the checkout.

**What is broken or missing:**

1. **No upstream visibility.** A maintainer has no way to know which local agent files have diverged from their upstream counterparts (whether because the local copy was customized or because upstream evolved), which agents are new upstream and could be considered for adoption, or which previously-vendored agents have been removed upstream. The information exists — it is one HTTP fetch away — but there is no command that surfaces it.
2. **No safe diff workflow.** The only command that previously touched upstream (`/agents-update`) was destructive: it overwrote local files after a yes/no approval. RFC `2026-05-10-refactor-command` removed it precisely because that destructiveness is incompatible with local-ownership semantics. The plugin currently has no read-only counterpart that surfaces the same information without the mutation.
3. **Lost institutional knowledge.** The fetch and tree-walk patterns in the now-deleted skill encoded operational details (Trees API endpoint, raw content URL pattern, category lookup, rate-limit avoidance) that would otherwise need to be rediscovered when building any future upstream-visibility skill. `/agents-diff` is the natural place to re-host that knowledge in a non-destructive form.

The plugin's other plugin-local skill (`best-practices-sync`) demonstrates the precedent for this RFC's chosen location: a `SKILL.md` under `.claude/skills/<skill-name>/` that documents an in-checkout maintenance workflow.

## Analysis / Options

There are four coupled decisions: where the skill lives, how it fetches upstream content, what the diff output looks like, and how it handles partial-failure and rate-limit cases.

### Decision 1 — Where does `/agents-diff` live?

**Option A — Plugin-local under `.claude/skills/agents-diff/SKILL.md` (recommended).**
The skill is a maintainer-only operation against the plugin's own checkout. It has no value for plugin consumers (who do not have an `agents/` directory in their own projects to compare against). The existing `/agents-update` lives at `.claude/skills/agents-update/`, and `best-practices-sync` lives at `.claude/skills/best-practices-sync/` — the same pattern. Discovery is automatic: Claude Code surfaces skills in `.claude/skills/` when run inside the checkout, with no `plugin.json` registration required.

**Option B — Exported plugin skill under `skills/agents-diff/SKILL.md` and registered in `plugin.json`.**
Exposes the skill to every project that installs the bytewyrd plugin. Rejected because the skill has no value outside the plugin's own checkout — a consumer project has no `agents/` directory to compare. Shipping the skill to consumers would create a `/agents-diff` autocomplete entry that fails on first use with "no `agents/` directory found here," which is friction for no benefit.

**Recommendation: Option A.** Plugin-local placement matches the same-shape sibling (`agents-update` was there; `best-practices-sync` is there). No `plugin.json` edit needed. The skill enforces its "plugin checkout only" precondition with an early exit if `agents/` is absent at the working directory.

### Decision 2 — How does the skill fetch upstream content?

**Option A — GitHub Trees API for enumeration, raw.githubusercontent.com for per-file content (recommended).**
Two HTTP endpoints, both unauthenticated for public repos, both already used by the removed `/agents-update` skill:

1. `GET https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents/git/trees/main?recursive=1` — returns the full file tree in a single response, including every agent file's `path` (relative to repo root). One call enumerates everything; the response includes a `truncated` boolean that signals if the tree was too large to return fully (verified at time of writing: upstream returns 206 total tree entries, of which 154 are `.md` files under `categories/` — well below the documented 100,000-file / 7 MB Trees API limit, so truncation is not expected — but the skill must check the field and abort safely if it is ever true).
2. `GET https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/<path>` — returns the raw file content for a single path. One call per file. The raw endpoint is served by GitHub's content CDN and is significantly more rate-limit-tolerant than the Contents API, but it is not unlimited; the skill must serialize requests (no parallel fetch) and pause briefly between requests to stay polite.

This is the same fetch pattern the removed `/agents-update` skill used and that is documented as the correct approach in GitHub's REST API docs. No authentication is needed for public-repo read; the skill explicitly does not accept a `GITHUB_TOKEN` (no auth means no risk of leaking credentials into the diff output or logs).

**Option B — `git clone` of the upstream repo to a temporary directory, then local `git diff`.**
Heavier — clones ~5 MB of repo data each run (history, non-agent files, examples, docs). Slower than per-file raw fetch for the small number of files in `agents/`. The advantage (use `git diff` directly instead of constructing diffs in-skill) is real but not large; the cleanup step (`rm -rf` the temp clone) is one more thing that can fail and leave debris. Rejected on weight grounds: the Trees-plus-raw pattern is leaner and already proven in this codebase.

**Option C — GitHub Contents API (`GET /repos/{owner}/{repo}/contents/{path}`).**
Returns base64-encoded file content per request. Each call counts against the standard 60-request-per-hour unauthenticated REST API rate limit. The Trees+raw pattern only spends one or two of those 60 requests (the Trees API call and the optional commits API call); the per-file raw fetches go through raw.githubusercontent.com, which has its own, more generous limits. At 46 local agents whose content the skill needs to compare, switching to Contents API would consume 46 of the 60 hourly REST calls on every run, leaving almost no headroom for retries or for the maintainer running the skill twice in an hour. Rejected on rate-limit grounds.

**Recommendation: Option A.** Same fetch pattern as the removed `/agents-update` skill, well within rate limits, no authentication required, no on-disk clone to manage. The skill's "no destructive operations" property pairs naturally with not asking for credentials.

### Decision 3 — What does the diff output look like?

**Option A — Per-file unified diff using `diff -u`, grouped by change category, with a summary header (recommended).**
The skill writes each upstream file to a temporary directory (under `$TMPDIR`, which the sandbox guarantees writable) using the local filename, then runs `diff -u agents/<file> "$TMPDIR/upstream/<file>"` per file. The output is:

```
upstream: VoltAgent/awesome-claude-code-subagents @ main (commit <abbrev sha>)
fetched: 2026-05-10 14:32 UTC

Summary
-------
  144 agent files upstream, 46 files local
   12 modified (local differs from upstream)
   98 new upstream (not in local agents/)
    0 removed upstream (still in local agents/)
   34 identical

Modified files (12)
===================

--- a/agents/python-pro.md          2026-05-10 14:32:01.000000000 +0000
+++ b/.diff-tmp/upstream/python-pro.md  2026-05-10 14:32:01.000000000 +0000
@@ -1,5 +1,5 @@
 ---
 name: python-pro
-description: Old description text...
+description: Updated description text...
 ...

[... per-file diffs continue ...]

New upstream files (98)
=======================

+ accessibility-tester.md                 (categories/04-quality-security)
+ chaos-engineer.md                       (categories/04-quality-security)
[... full list, one filename per line, with upstream category path ...]

Removed upstream files (0)
==========================

(none — every local file has an upstream counterpart in this example)

Identical files (34) — names omitted for brevity. Run with --verbose to list.
```

Unified-diff format is the standard format every code reviewer can read; grouping by category (modified / new / removed / identical) makes it scannable; the summary header sets expectations before the diffs scroll past. Upstream commit SHA in the header makes the output reproducible — re-running the skill against the same upstream commit produces the same output.

**Option B — Side-by-side diff using `diff -y` or `sdiff`.**
Readable for narrow files, unreadable for the wide multi-line YAML and prose blocks that agent files contain. Most terminals are not wide enough to render side-by-side diffs of full agent files without wrapping. Rejected on readability grounds.

**Option C — JSON output (structured: `{modified: [...], new: [...], removed: [...]}`).**
Useful if the skill were feeding another tool, but the skill's audience is a human maintainer reading the diff in their terminal. JSON would force the maintainer to render it themselves. Rejected — the consumer is a human, not a pipeline.

**Recommendation: Option A.** Unified diff is the readable default; the grouped summary plus per-file diffs balance scannable overview with full detail.

### Decision 4 — Partial failures, rate limits, and truncation

**Option A — Strict on tree fetch, lenient on per-file content (recommended).**
The Trees API call is the entry point; if it fails (network down, GitHub 5xx, response indicates truncation), the skill cannot proceed and must abort with a clear error. For per-file fetches, the skill continues on individual failures but records them in a "failed to fetch" section of the report so the maintainer knows which files were not included in the diff. This matches the safety property "the skill never silently produces an incomplete diff that looks complete."

Rate-limit policy:
- Fetch files serially, never in parallel.
- Pause 200 ms between per-file fetches (`sleep 0.2`) — same backoff the removed `/agents-update` used, sufficient for the raw CDN's rate limits in practice.
- If any single fetch returns HTTP 429 or a `rate-limit` header indicates near-exhaustion, abort and report the partial result; do not retry blindly. The maintainer reruns after the rate-limit window resets.

Truncation policy:
- If the Trees API response includes `"truncated": true`, abort with: "Upstream tree response was truncated; the diff cannot be produced safely without the full file list. Re-run later or open an issue if this persists."

**Option B — Lenient on tree fetch (retry with backoff), lenient on per-file content.**
Adds complexity (retry-with-jitter loop, exhaustion thresholds) for a case (Trees API failure) that is rare and where the right response — surface the error and stop — is already simple. Rejected on simplicity grounds.

**Option C — Strict on all fetches (any single per-file failure aborts the run).**
Too brittle for the long-tail case where one file in a hundred fails transiently. Rejected because the maintainer would just re-run the skill, and the deterministic behavior is to make per-file failures visible without blocking the overall report.

**Recommendation: Option A.** The skill's job is to produce a usable diff or to make the failure obvious; lenient per-file handling with a clear "failed" section preserves that contract.

## Drawbacks

- **Manual port is the same friction the removed `/agents-update` automated away.** A maintainer who sees a useful upstream change still has to hand-copy the change into the local file. **Mitigation:** that friction is intentional, per RFC `2026-05-10-refactor-command`'s decision to make ownership of `agents/` explicit and to prevent silent regressions of local customizations. The diff is the surface; the port is the deliberate act. If the friction proves too high in practice, a future RFC could add a per-file `/agents-port <agent-name>` skill that overwrites a single named file from upstream (still explicit, still per-file), but that is a follow-up if and when the manual workflow becomes a real bottleneck.

- **Maintaining a separate workflow for upstream visibility.** This is a second skill in the upstream-relationship space, distinct from but adjacent to the original `/agents-update`. **Mitigation:** the operational footprint is small (one single `SKILL.md` (~300 lines including embedded shell), no `plugin.json` edit, no `agents/` modifications, no new agent files). The skill is plugin-local and only runs when the maintainer invokes it; it does not cost anything when not in use.

- **The skill's output can grow large.** With ~46 local agents and ~144 upstream agent files (verified at time of writing — upstream has 154 `.md` files under `categories/`, of which 10 are category-level README files the skill filters out), a worst-case run could produce dozens of per-file diffs and a ~100-item "new upstream" list. **Mitigation:** the output is grouped by change category with the summary header first, so the maintainer can see counts before scrolling through detail. The skill defers listing identical-file names by default (the count is shown, but the file names are only printed in `--verbose` mode); modified-file diffs are unavoidable because they are the point of the skill. If the diff output becomes unwieldy in practice, a `--category modified` filter could be added in a follow-up.

- **No version pinning of "upstream."** The skill always fetches `main`, so re-running on different days can produce different output as upstream evolves. **Mitigation:** the output includes the upstream commit SHA, so any report can be tied back to a specific upstream state for cross-referencing. If a maintainer wants to compare against a pinned upstream version (e.g., a release tag), that's a follow-up — for now, `main` is the simplest and matches the same default the removed `/agents-update` used.

- **No authentication, so the skill is subject to public rate limits.** **Mitigation:** the per-file pause and serial-fetch policy keep usage well within unauthenticated raw-CDN limits for the current agent counts. If the agent count grows to a point where it strains rate limits, optional `GITHUB_TOKEN` support could be added in a follow-up; for now, the skill is simpler without it and does not need to handle credential storage.

## Implementation spec

### File structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.claude/skills/agents-diff/SKILL.md` | New plugin-local skill: fetches upstream tree via GitHub Trees API, fetches per-file content from raw.githubusercontent.com, compares against local `agents/`, prints a unified diff grouped by modified/new/removed/identical categories. Read-only — no `agents/` modifications, no `plugin.json` registration |

No new agent files. No `plugin.json` changes. No edits to existing skills. No hook changes. No changes to `agents/`.

### Steps

#### Step 1 — Create `.claude/skills/agents-diff/SKILL.md`

Create the directory and write the file with this exact content:

````markdown
---
name: agents-diff
description: Use inside the bytewyrd plugin's checkout to show a read-only diff between the local agents/ directory and the current upstream copies at VoltAgent/awesome-claude-code-subagents. Fetches the upstream tree, fetches per-file content, and prints a grouped unified diff (modified / new upstream / removed upstream / identical). Never writes to agents/ — the maintainer decides what (if anything) to port manually.
argument-hint: "[--verbose]"
---

# Diff Local Agents Against Upstream

## Overview

Show what has changed between this plugin's locally-owned `agents/` directory and the current upstream copies at [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents). The skill is read-only: it produces a diff report for human review, then stops. Any port of upstream changes is done manually by the maintainer.

This skill is plugin-local: it only makes sense inside the bytewyrd checkout. If `agents/` does not exist at the current working directory, stop with: "agents-diff only runs inside the bytewyrd plugin checkout. cd into the plugin repo and try again."

The skill replaces the visibility that the removed `/agents-update` skill provided. It does not replace the destructive overwrite step — by design — per RFC `2026-05-10-refactor-command`'s decision that `agents/` is locally owned.

## Step 1 — Pre-flight

Verify the working directory is the plugin checkout:

```bash
test -d agents || { echo "agents-diff only runs inside the bytewyrd plugin checkout. cd into the plugin repo and try again."; exit 1; }
```

Create a temporary working directory. Use `$TMPDIR` when set (the sandbox guarantees this), fall back to `/tmp`. The `mktemp -d` form with trailing `X`'s works on both GNU and BSD `mktemp`:

```bash
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/agents-diff.XXXXXX")"
mkdir -p "$WORKDIR/upstream"
echo "WORKDIR=$WORKDIR"  # printed so Claude captures the path for later steps
```

**Shell state caveat.** Each Bash tool invocation is a fresh shell — environment variables do not persist between calls. To preserve `WORKDIR` across the steps below, Claude has two equivalent strategies; either is acceptable:

1. **Concatenate within one Bash call.** Run all steps that share `WORKDIR` as a single multi-command Bash invocation (commands joined with `&&` or newlines inside one tool call). This is the simplest pattern for short runs.
2. **Inline the absolute path.** After Step 1 prints `WORKDIR=/tmp/agents-diff.XXXXXX`, Claude captures that literal path from the tool output and substitutes it for `"$WORKDIR"` in every later block when invoking subsequent Bash calls.

Both produce identical results. The skill text below uses `"$WORKDIR/..."` as shorthand throughout; expansion to the literal absolute path (strategy 2) or shell-variable persistence within one call (strategy 1) is an invocation detail.

Clean up at the end with `rm -rf "$WORKDIR"` (Step 8).

## Step 2 — Fetch the upstream file tree and the head commit SHA

Use a single GitHub Trees API call to enumerate all upstream agent files, and a second call to capture the current `main` commit SHA for the report header:

```bash
TREE_JSON="$(curl -sf -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents/git/trees/main?recursive=1')" || {
    echo "ERROR: failed to fetch upstream tree (curl exit $?). Check network and re-run." >&2
    exit 2
}

# Fetch the head commit SHA for the report header. Failure here is non-fatal —
# fall back to the tree SHA from the tree response, or "unknown" as a last resort.
HEAD_SHA="$(curl -sf -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents/commits/main' \
    2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'][:7])" 2>/dev/null || \
    echo "$TREE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sha','unknown')[:7])" 2>/dev/null || \
    echo 'unknown')"
```

`curl -sf` causes curl to exit non-zero on HTTP 4xx/5xx (the `-f` flag) while still suppressing the progress bar (`-s`). The Trees API call is mandatory; failure aborts. The commits API call is optional (for the report header); failure falls back to the tree SHA, then to `"unknown"`.

Validate the tree response and extract agent file paths:

```bash
if [ -z "$TREE_JSON" ]; then
    echo "ERROR: failed to fetch upstream tree from GitHub (empty response). Check network and re-run." >&2
    exit 2
fi

echo "$TREE_JSON" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    sys.stderr.write(f'ERROR: upstream tree response was not valid JSON: {e}. The fetch may have failed or hit a rate limit.\n')
    sys.exit(2)
if data.get('truncated'):
    sys.stderr.write('ERROR: upstream tree response was truncated; cannot produce a safe diff. Re-run later or open an issue if this persists.\n')
    sys.exit(2)
if 'tree' not in data:
    # GitHub returns {'message': 'Not Found', ...} or similar on error
    msg = data.get('message', 'no tree field in response')
    sys.stderr.write(f'ERROR: GitHub Trees API did not return a tree: {msg}\n')
    sys.exit(2)
for item in data['tree']:
    path = item['path']
    if not (path.startswith('categories/') and path.endswith('.md') and item['type'] == 'blob'):
        continue
    parts = path.split('/')
    if len(parts) != 3:
        continue
    # Skip README.md files — they are category-level docs, not agent definitions
    if parts[2].lower() == 'readme.md':
        continue
    # Print: <filename>\t<full-upstream-path>
    print(f'{parts[2]}\t{path}')
" > "$WORKDIR/upstream-list.tsv"
```

The README.md exclusion is critical: upstream places one `README.md` per category folder (e.g., `categories/01-core-development/README.md`) at the same depth as agent files. Without the filter, those 10 README files would be misclassified as new upstream agents. The exclusion is case-insensitive (`parts[2].lower() == 'readme.md'`) to be defensive against future casing inconsistencies.

If the tree call fails (network down, HTTP 5xx, empty response, truncation, non-JSON response, missing `tree` field), stop with a clear error message. Do not proceed with partial data.

`upstream-list.tsv` now has one line per upstream agent: `<filename>\t<categories/.../filename.md>`. This is the canonical upstream inventory; every later step reads from it.

## Step 3 — Categorize files (modified / new / removed / identical decision deferred to step 5)

Build three lists:

- **Both:** filenames that exist both locally (in `agents/`) and upstream. These need per-file fetch + diff to determine modified vs identical.
- **New upstream:** filenames in upstream but not in `agents/`. No fetch needed for the diff (they are listed by name only in the report).
- **Removed upstream:** filenames in `agents/` but not in upstream. No fetch needed.

```bash
# Local filenames. Use ls + grep instead of `find -printf` for BSD-find portability
# (macOS find does not support -printf). The agents/ directory has no subdirectories,
# so ls is sufficient and well-defined here.
(cd agents && ls -1 *.md 2>/dev/null) | LC_ALL=C sort > "$WORKDIR/local-list.txt"

# Upstream filenames (first column of TSV)
cut -f1 "$WORKDIR/upstream-list.tsv" | LC_ALL=C sort > "$WORKDIR/upstream-names.txt"

# Duplicate-basename guard: abort if upstream has two agent files with the same basename
# in different category folders. The awk lookup in Step 4 only returns the first match,
# so a duplicate would silently drop the second file from the diff.
dupes="$(cut -f1 "$WORKDIR/upstream-list.tsv" | LC_ALL=C sort | uniq -d)"
if [ -n "$dupes" ]; then
    echo "ERROR: upstream contains duplicate agent basenames. The diff cannot be produced safely." >&2
    echo "Duplicates found:" >&2
    while IFS= read -r dup; do
        grep -F "$dup" "$WORKDIR/upstream-list.tsv" | awk -F'\t' '{print "  " $1 "  (" $2 ")"}' >&2
    done <<< "$dupes"
    exit 2
fi

# Set operations. `comm` requires sorted input; LC_ALL=C ensures byte-ordering
# consistency between the sort and comm passes.
LC_ALL=C comm -12 "$WORKDIR/local-list.txt" "$WORKDIR/upstream-names.txt" > "$WORKDIR/both.txt"
LC_ALL=C comm -13 "$WORKDIR/local-list.txt" "$WORKDIR/upstream-names.txt" > "$WORKDIR/new-upstream.txt"
LC_ALL=C comm -23 "$WORKDIR/local-list.txt" "$WORKDIR/upstream-names.txt" > "$WORKDIR/removed-upstream.txt"
```

The `LC_ALL=C` calls on both `sort` and `comm` are required for correctness on systems where the default locale produces a different collation order than C (e.g., some macOS configurations). Without it, `comm` can incorrectly classify files as missing when they are actually present, because the two inputs were sorted with different rules.

## Step 4 — Fetch upstream content for files in `both.txt`

For each filename in `both.txt`, look up its upstream path in `upstream-list.tsv` and fetch the raw content. Serial fetch, 200 ms pause between requests, never in parallel. The curl call uses `--max-time 30` to prevent hung connections from stalling the skill indefinitely:

```bash
> "$WORKDIR/fetch-failures.txt"  # truncate / create the failures log

while IFS= read -r filename; do
    upstream_path="$(awk -F'\t' -v fn="$filename" '$1 == fn { print $2; exit }' "$WORKDIR/upstream-list.tsv")"

    # Defensive: if the lookup unexpectedly produced no path, record it and skip.
    if [ -z "$upstream_path" ]; then
        printf '%s\t%s\n' "$filename" "no-upstream-path" >> "$WORKDIR/fetch-failures.txt"
        continue
    fi

    url="https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/${upstream_path}"

    http_code="$(curl -s --max-time 30 -o "$WORKDIR/upstream/$filename" -w '%{http_code}' "$url")"

    if [ "$http_code" = "429" ]; then
        echo "ERROR: hit rate limit (HTTP 429) while fetching $filename. Aborting; re-run later." >&2
        exit 3
    fi

    if [ "$http_code" != "200" ]; then
        # Use printf (not echo) so the tab between filename and code is a real \t,
        # not the literal two-character string "\t" — the report-printing step
        # depends on tab-separated fields when reading this file back.
        printf '%s\t%s\n' "$filename" "$http_code" >> "$WORKDIR/fetch-failures.txt"
        rm -f "$WORKDIR/upstream/$filename"
    fi

    # Curl can report HTTP 200 (the header arrived successfully) but then the
    # connection drops mid-transfer, leaving an empty or partial file on disk.
    # Treat a zero-byte response as a fetch failure and remove the empty file
    # so Step 5's cmp does not classify it as a (false-positive) modification.
    # The failure code "200-empty" is what the report's "Failed to fetch"
    # section will display for these cases.
    if [ "$http_code" = "200" ] && [ ! -s "$WORKDIR/upstream/$filename" ]; then
        printf '%s\t%s\n' "$filename" "200-empty" >> "$WORKDIR/fetch-failures.txt"
        rm -f "$WORKDIR/upstream/$filename"
    fi

    sleep 0.2
done < "$WORKDIR/both.txt"
```

After this loop, `"$WORKDIR/upstream/"` contains one file per successfully-fetched upstream agent, and `"$WORKDIR/fetch-failures.txt"` lists any files that failed (one `<filename>\t<http_code>` per line). Zero-byte responses (curl returned HTTP 200 but the transfer produced an empty file — typically a connection reset after headers arrived) are recorded with the synthetic code `200-empty` in the failures log; the report's "Failed to fetch" section may show this code alongside genuine HTTP error codes.

## Step 5 — Classify modified vs identical, and build per-file diffs

For each filename in `both.txt` that was successfully fetched (i.e., present in `"$WORKDIR/upstream/"`), compare the local and upstream contents. Use `cmp` for the identity check (fast, byte-exact); use `diff -u` only for the files that actually differ.

```bash
> "$WORKDIR/modified.txt"
> "$WORKDIR/identical.txt"
> "$WORKDIR/diffs.txt"

while IFS= read -r filename; do
    if [ ! -f "$WORKDIR/upstream/$filename" ]; then
        continue  # fetch failed; already in fetch-failures.txt
    fi

    if cmp -s "agents/$filename" "$WORKDIR/upstream/$filename"; then
        echo "$filename" >> "$WORKDIR/identical.txt"
    else
        echo "$filename" >> "$WORKDIR/modified.txt"
        {
            diff -u --label "a/agents/$filename" --label "b/upstream/$filename" \
                "agents/$filename" "$WORKDIR/upstream/$filename"
            echo  # trailing blank line separator
        } >> "$WORKDIR/diffs.txt"
    fi
done < "$WORKDIR/both.txt"
```

After this step:
- `"$WORKDIR/modified.txt"` — one filename per line, each one differs from upstream.
- `"$WORKDIR/identical.txt"` — one filename per line, byte-identical to upstream.
- `"$WORKDIR/diffs.txt"` — concatenated unified diffs for all modified files.

## Step 6 — Print the grouped report

Print to standard output, in this order. The format is structured but plain text; the consumer is a human reading the terminal:

```bash
# Counts
upstream_count="$(wc -l < "$WORKDIR/upstream-names.txt" | tr -d ' ')"
local_count="$(wc -l < "$WORKDIR/local-list.txt" | tr -d ' ')"
modified_count="$(wc -l < "$WORKDIR/modified.txt" | tr -d ' ')"
new_count="$(wc -l < "$WORKDIR/new-upstream.txt" | tr -d ' ')"
removed_count="$(wc -l < "$WORKDIR/removed-upstream.txt" | tr -d ' ')"
identical_count="$(wc -l < "$WORKDIR/identical.txt" | tr -d ' ')"
failed_count="$(wc -l < "$WORKDIR/fetch-failures.txt" | tr -d ' ')"
fetched_at="$(date -u '+%Y-%m-%d %H:%M UTC')"

# 25% failure warning (per Red Flags). If more than a quarter of the per-file
# fetches failed, prepend a prominent warning so the maintainer knows the
# modified-vs-identical classification may be incomplete.
if [ "$failed_count" -gt 0 ] && [ "$( (cd agents && ls -1 *.md 2>/dev/null) | wc -l | tr -d ' ')" -gt 0 ]; then
    both_count="$(wc -l < "$WORKDIR/both.txt" | tr -d ' ')"
    if [ "$both_count" -gt 0 ] && [ "$((failed_count * 4))" -gt "$both_count" ]; then
        echo "Warning: ${failed_count}/${both_count} per-file fetches failed; the modified-vs-identical classification may be incomplete."
        echo
    fi
fi
```

Then print the report header and summary. The "Failed to fetch" line in the summary is only emitted when at least one fetch failed:

```bash
echo "upstream: VoltAgent/awesome-claude-code-subagents @ main (commit ${HEAD_SHA})"
echo "fetched: ${fetched_at}"
echo
echo "Summary"
echo "-------"
echo "  ${upstream_count} files upstream, ${local_count} files local"
echo "   ${modified_count} modified (local differs from upstream)"
echo "   ${new_count} new upstream (not in local agents/)"
echo "   ${removed_count} removed upstream (still in local agents/)"
echo "   ${identical_count} identical"

if [ "$failed_count" -gt 0 ]; then
    echo "   ${failed_count} failed to fetch"
fi
```

The full structure of the rendered report is:

```
upstream: VoltAgent/awesome-claude-code-subagents @ main (commit <HEAD_SHA>)
fetched: <fetched_at>

Summary
-------
  <upstream_count> files upstream, <local_count> files local
   <modified_count> modified (local differs from upstream)
   <new_count> new upstream (not in local agents/)
   <removed_count> removed upstream (still in local agents/)
   <identical_count> identical
   <failed_count> failed to fetch  ← only printed if failed_count > 0

Modified files (<modified_count>)
=================================

<contents of $WORKDIR/diffs.txt>

New upstream files (<new_count>)
================================

+ <filename>   (<upstream-path-without-filename>)
... one line per file in new-upstream.txt, sorted ...

Removed upstream files (<removed_count>)
========================================

~ <filename>   (still in local agents/, no longer in upstream)
... one line per file in removed-upstream.txt, sorted ...

Identical files (<identical_count>) — names omitted. Run with --verbose to list.

Failed to fetch (<failed_count>)
================================

! <filename>   (HTTP <code>)
... only printed if failed_count > 0 ...
```

For the "new upstream" lines, look up each filename's upstream directory in `upstream-list.tsv`:

```bash
while IFS= read -r filename; do
    upstream_path="$(awk -F'\t' -v fn="$filename" '$1 == fn { print $2; exit }' "$WORKDIR/upstream-list.tsv")"
    upstream_dir="$(dirname "$upstream_path")"
    printf '+ %-40s (%s)\n' "$filename" "$upstream_dir"
done < "$WORKDIR/new-upstream.txt"
```

For removed upstream:

```bash
while IFS= read -r filename; do
    printf '~ %-40s (still in local agents/, no longer in upstream)\n' "$filename"
done < "$WORKDIR/removed-upstream.txt"
```

For failed fetches, the section header and loop are guarded so no empty section is emitted when every fetch succeeded:

```bash
if [ "$failed_count" -gt 0 ]; then
    echo ""
    echo "Failed to fetch ($failed_count)"
    echo "================================"
    echo ""
    while IFS=$'\t' read -r filename code; do
        printf '! %-40s (HTTP %s)\n' "$filename" "$code"
    done < "$WORKDIR/fetch-failures.txt"
fi
```

## Step 7 — `--verbose` mode (optional)

The skill checks the invocation arguments for `--verbose`. The arguments are available via the `$ARGUMENTS` token that Claude Code substitutes into the skill body at invocation time:

```bash
VERBOSE=0
case " $ARGUMENTS " in
    *' --verbose '*|*' -v '*)
        VERBOSE=1
        ;;
esac
```

The leading and trailing spaces in the case pattern (and around `$ARGUMENTS`) ensure exact-token matching — `--verbose-something` does not match. The skill recognizes `--verbose` and the short form `-v`.

When `VERBOSE=1`, the "Identical files" section in Step 6 lists filenames (one per line, sorted) after the count line, instead of the "names omitted" placeholder:

```bash
if [ "$VERBOSE" = "1" ]; then
    echo
    LC_ALL=C sort "$WORKDIR/identical.txt"
fi
```

All other sections of the report are unchanged. If `--verbose` is not present, the report omits identical filenames and prints the existing "Run with --verbose to list" placeholder.

## Step 8 — Cleanup

After printing the report:

```bash
rm -rf "$WORKDIR"
```

The skill produces no on-disk artifacts outside `$TMPDIR`. `agents/` is never touched.

## Red Flags — Stop and Reconsider

- **GitHub Trees API returns `truncated: true`** → stop and report; the skill cannot produce a safe diff without the full list. The agent file count is well below the documented Trees API limit, so this is not expected — but if it ever happens, abort rather than silently producing a partial diff.
- **Trees API call fails entirely (HTTP 5xx, network error, empty response)** → stop; do not attempt per-file fetches without the canonical list.
- **Any per-file fetch returns HTTP 429** → abort the run, surface the rate-limit error, do not retry blindly. The maintainer reruns after the rate-limit window resets.
- **More than 25% of per-file fetches fail** → the report is still printed (the diffs that did fetch are still useful), but include a prominent warning before the Summary: "Warning: <N>/<M> per-file fetches failed; the modified-vs-identical classification may be incomplete." 25% is a heuristic; the skill prints the warning, the maintainer decides whether to act on a partial report.
- **`agents/` directory missing from the working directory** → handled in Step 1 (pre-flight); skill exits with the "plugin checkout only" message.
- **`$TMPDIR` unwritable** → `mktemp` will fail with a clear shell error; the skill propagates that error without further work. Sandbox guarantees `$TMPDIR` writability, but checking lets the error message be clear in non-sandbox environments.
````

The skill's audience is a maintainer running it inside the plugin checkout. The output is structured for terminal reading, not for piping to another tool.

#### Step 2 — Verification

After Step 1, run these checks. Each is a single command with an expected output line.

1. **Skill file exists and parses (frontmatter present):**

   ```bash
   test -f .claude/skills/agents-diff/SKILL.md && head -3 .claude/skills/agents-diff/SKILL.md
   ```

   Expected output:

   ```
   ---
   name: agents-diff
   description: Use inside the bytewyrd plugin's checkout to show a read-only diff between the local agents/ directory and the current upstream copies at VoltAgent/awesome-claude-code-subagents. Fetches the upstream tree, fetches per-file content, and prints a grouped unified diff (modified / new upstream / removed upstream / identical). Never writes to agents/ — the maintainer decides what (if anything) to port manually.
   ```

2. **Skill is NOT registered in plugin.json (plugin-local skill, not exported):**

   ```bash
   grep -c 'agents-diff' .claude-plugin/plugin.json
   ```

   Expected output: `0`

3. **`agents/` directory is unchanged by writing the skill:**

   ```bash
   git diff --stat agents/
   ```

   Expected output: empty (no changes to `agents/`).

4. **Manual smoke test (run the skill end to end):**

   - From the plugin checkout root, invoke `/agents-diff` via the skill mechanism.
   - Expected: the skill emits the report described in Step 6 of the skill body. Check the two count identities that must hold:
     - `modified + identical + failed == both` (every file that appears in both upstream and local is classified into exactly one of those three buckets, including failed fetches).
     - `both + new_upstream == upstream_count` and `both + removed_upstream == local_count` (set-cover identities: `both` is the intersection; `new_upstream` and `removed_upstream` are the two exclusive halves).
   - Confirm the upstream commit SHA in the report header is a 7-character hex string (or the literal `unknown` if the optional commits-API call failed).
   - Run `/agents-diff --verbose` and confirm the identical-files section lists filenames one per line.
   - Run the skill from a directory that does not contain `agents/` and confirm it exits with the "plugin checkout only" message.

5. **Manual smoke test with network failure (optional):**

   - Disable network temporarily; invoke `/agents-diff`; confirm the skill exits with a clear error message (curl will fail on the Trees API call in Step 2; the skill's check should propagate that as a stop condition).
   - This case is rare in practice; if the maintainer cannot easily simulate it, skipping this check is acceptable.

   If checks 1–4 pass, the skill is correctly installed. The smoke tests in check 4 are the meaningful end-to-end verification.

## Risks and open questions

- **Risk: upstream restructure (e.g., directory layout changes from `categories/<n>-<name>/` to something else).** The skill hardcodes the prefix `categories/` and the three-segment path shape (`categories/<category>/<filename>.md`) in Step 2. If upstream restructures, the skill will report "0 upstream files found" or similar misleading output. **Mitigation:** the Trees API response is the canonical source; if the prefix changes, the skill produces an obviously-broken report (e.g., "0 files upstream") rather than silently producing a wrong-but-plausible one. A maintainer noticing the broken output adjusts the prefix check. A more general path-detection heuristic ("any `.md` file at depth 3 under `categories/`") is the same logic; a future RFC can broaden the matcher if upstream's structure becomes more variable.

- **Risk: rate limits change.** GitHub's per-IP rate limits for unauthenticated requests are well-documented, but the raw CDN's are not formally guaranteed. **Mitigation:** the skill's serial-fetch + 200 ms pause matches what the prior `/agents-update` used without issue. If real-world use shows the limits have tightened, an optional `--token <github-token>` argument can be added in a follow-up. For now, no credentials means no credential-handling risk.

- **Open question: does `--verbose` belong in the first version, or in a follow-up?** Argued either way. Including it now is one extra branch in Step 6 (a few lines) and removes the cliff where a user wonders "where are the identical-file names?" Excluding it keeps the first version smaller. **Resolution within this RFC:** include it now — the cost is trivial (a one-line conditional) and it makes the "Identical files (<count>) — names omitted" note actionable. If the maintainer never uses it, that's fine; it costs nothing when unused.

- **Open question: should the skill cache the upstream tree between runs?** A maintainer who reruns `/agents-diff` minutes apart re-fetches the same data. **Resolution within this RFC:** no caching. The cost of refetching the tree (one HTTP call) is negligible, and a cache would introduce staleness bugs (the report's "fetched at" timestamp would mislead). Refetching every run is the simplest correct behavior.

- **Open question: should the skill diff agent prompt bodies semantically (e.g., ignoring whitespace, ignoring frontmatter reordering)?** **Resolution within this RFC:** no. `diff -u` byte-comparison is the right default; semantic diff would invent a notion of "meaningful change" that the maintainer should be the one to apply. If a whitespace-only change is shown in the diff, the maintainer sees that it's whitespace-only and moves on — a few seconds of human judgment.

- **Relationship to RFC `2026-05-10-refactor-command`'s deletion of `/agents-update`.** That deletion is complete: `.claude/skills/agents-update/` no longer exists in the working tree, the RFC's status is Done, and there is no coexistence to manage. No coordination is required between the two RFCs — `/agents-diff` lands on a tree where `/agents-update` is already gone.

- **Open question: does this skill need a hook (e.g., to remind the maintainer to run `/agents-diff` periodically)?** **Resolution within this RFC:** no. Reminders for "you might want to check upstream this week" are noise without a clear trigger condition. The skill is run when the maintainer wants to know; that's the right cadence.

## Relationship to other RFCs

- **2026-05-10-refactor-command** (status: Done) — this RFC is the direct follow-up that RFC explicitly anticipated. RFC `2026-05-10-refactor-command` removed `/agents-update` to lock in local ownership of `agents/` (the deletion has already landed), and its "open questions" section concludes: "If a future RFC wants a more structured 'see what's changed upstream' workflow, it can add a read-only diff command (`/agents-diff` or similar) that surfaces changes without overwriting." This RFC delivers exactly that. The two RFCs are complementary, not conflicting: `/agents-diff` does not restore any auto-overwrite behavior, and the local-ownership posture remains intact.
- **`/agents-update` (removed)** — the prior auto-sync skill, deleted as specified by RFC `2026-05-10-refactor-command`. This RFC reuses the same fetch pattern (GitHub Trees API + raw CDN), but inverts the safety profile: `/agents-update` ended in a file write; `/agents-diff` ends in a report.
- **`/sync` and `/best-practices-sync`** — sibling plugin-local maintenance skills under `.claude/skills/`. This RFC follows the same placement convention but is not coupled to either: `/agents-diff` does not call them, and they do not call it.
- **Potential future `/agents-port <agent-name>`** — a per-file overwrite skill that would be a deliberate companion to `/agents-diff` (review with the diff, port with `/agents-port`). Not proposed in this RFC; mentioned as the natural next step if real-world use shows the manual port step is a recurring friction. Any such follow-up RFC would need to re-litigate the local-ownership boundary that `2026-05-10-refactor-command` established, with a per-file scope rather than the wholesale-overwrite scope that was rejected.
