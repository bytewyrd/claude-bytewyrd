---
name: scaffold
description: Seeds a bytewyrd repo with AGENTS.md, CLAUDE.md, a PR template and a CI workflow, each only if missing. Dry run unless --apply.
disable-model-invocation: true
---
Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" scaffold` with the flags the user gave (`--apply`, `--allow-dirty`) and show the output verbatim. Do not edit files in this skill. Exit 0 = ok, 3 = dirty tree, 1 = could not run, including no Python 3.11 or newer.
Outside Claude Code, `${CLAUDE_PLUGIN_ROOT}` is not substituted; use the directory two levels above this SKILL.md.
