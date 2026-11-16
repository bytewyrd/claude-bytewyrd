---
name: drift
description: Read-only drift check for a bytewyrd repo. Compares scaffold's seed files with the plugin's current templates and lists leftover 0.2.x artifacts with one-line fixes. Never edits files.
---
Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" drift` (add `--strict` to treat warnings as drift) and show the output verbatim. Do not edit files in this skill. The `fix:` lines are for the user to review and run; do not run them. Exit 0 = ok, 2 = drift, 1 = could not run, including no Python 3.11 or newer.
Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.
