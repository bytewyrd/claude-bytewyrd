---
name: agents-update
description: Use inside the bytewyrd-workflow plugin's checkout to sync the local agents/ directory with the latest upstream versions from VoltAgent/awesome-claude-code-subagents. Shows a diff of what changed, lets you approve updates, and downloads approved files.
---

# Update Agents from Upstream

## Overview

Sync the `agents/` directory in this plugin with the latest agent definitions from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents). The upstream repository is the authoritative source for all agent definitions bundled in this plugin.

This skill is plugin-local: it only makes sense inside the bytewyrd-workflow checkout. If `agents/` does not exist at the current working directory, stop with: "agents-update only runs inside the bytewyrd-workflow plugin checkout. cd into the plugin repo and try again."

## Step 1 — Fetch the upstream file tree

Use a single GitHub Trees API call to enumerate all agent files without hitting per-directory rate limits:

```bash
curl -s "https://api.github.com/repos/VoltAgent/awesome-claude-code-subagents/git/trees/main?recursive=1" \
  | python3 -c "
import json, sys
tree = json.load(sys.stdin)['tree']
for item in tree:
    if item['path'].startswith('categories/') and item['path'].endswith('.md') and item['type'] == 'blob':
        parts = item['path'].split('/')
        if len(parts) == 3:
            print(parts[2])  # just the filename: agent-name.md
"
```

This gives the canonical list of agent filenames as they exist upstream. If the API call fails (rate limit, network), stop and report the error — do not proceed with partial data.

## Step 2 — Compare with local agents

For each upstream agent filename:
- If the file exists locally in `agents/`, fetch the upstream content and diff it against the local file.
- If the file does not exist locally, mark it as **new**.

For each local file in `agents/`:
- If it does not appear in the upstream list, mark it as **removed upstream** (do not delete automatically).

Use this raw URL pattern to fetch upstream content:
```
https://raw.githubusercontent.com/VoltAgent/awesome-claude-code-subagents/main/categories/{category}/{agent-name}.md
```

To find the category for a given agent filename, look it up in the tree response (the `path` field gives `categories/{category}/{agent-name}.md`).

## Step 3 — Report findings

Print a summary before asking for approval:

```
Upstream: 118 agents across 14 categories
Local:    113 agents in agents/

Changes:
  Modified (upstream differs from local):
    - feature-engineer.md
    - python-pro.md
    - rust-engineer.md

  New upstream (not in local agents/):
    + php-laravel-pro.md
    + vue-expert.md

  Removed upstream (still in local agents/):
    ~ old-agent.md  ← present locally but no longer in upstream

Update which? (all / modified / new / none, or comma-separated names)
```

Default recommendation: `all` — updates and new agents both. Removed agents are reported but never deleted automatically; the user removes them manually.

## Step 4 — Download approved updates

For each approved agent:
1. Fetch the raw content from GitHub.
2. Write it to `agents/{agent-name}.md`, overwriting if it exists or creating if new.
3. Confirm each write.

Download agents one at a time (not in parallel) to avoid GitHub rate limits. Add a short pause (`sleep 0.2`) between requests if fetching more than 10 files.

## Step 5 — Report

Print:

```
Updated: 3 agents
  ✓ feature-engineer.md
  ✓ python-pro.md
  ✓ rust-engineer.md

Added: 2 agents
  ✓ php-laravel-pro.md
  ✓ vue-expert.md

Skipped (removed upstream — delete manually if desired):
  ~ old-agent.md

Run `git diff agents/` to review changes before committing.
```

The skill never commits. Review and commit are the user's call.

## Red Flags — Stop and Reconsider

- GitHub API returns a truncated tree (`truncated: true`) → stop and tell the user the tree was truncated; the skill cannot proceed safely without the full list.
- Any file download returns non-200 → skip that file, report the failure, continue with others.
- Upstream agent count drops by more than 10% in a single run → warn the user before proceeding; a large removal may indicate a restructure in the upstream repo.
