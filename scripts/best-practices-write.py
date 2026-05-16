#!/usr/bin/env python3
"""
Write approved best-practice entries to BEST_PRACTICES.md files.

Used by: /best-practices-extract and /best-practices-record after user approval.
Reads JSON from stdin or the first positional argument (file path).

Input JSON schema:
  {
    "project_entries": [
      {"section": "Architecture", "label": "_Architecture_", "text": "Concise principle."}
    ],
    "global_entries": [
      {"section": "Architecture", "label": "_Architecture_", "text": "Concise principle."}
    ],
    "project_file": "docs/BEST_PRACTICES.md",   // optional, defaults to docs/BEST_PRACTICES.md
    "global_file":  "/home/user/.claude/BEST_PRACTICES.md",  // optional, defaults to ~/.claude/BEST_PRACTICES.md
    "write_sentinel": true,   // write .bytewyrd/precompact-extraction-done
    "patch_claude_md": true   // add BEST_PRACTICES.md ref to CLAUDE.md if absent
  }

Output JSON:
  {
    "project_count": 2,
    "global_count": 1,
    "sentinel_written": true,
    "claude_md_patched": false,
    "errors": []
  }

Exit codes:
  0  All writes succeeded (or were skipped because the list was empty).
  1  At least one write failed (errors array will be non-empty).
"""

import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Template content
# ---------------------------------------------------------------------------

GLOBAL_FILE_HEADER = """\
# Global Best Practices

## Where do entries live, and why?

This file is the **global cross-project pool**. It accumulates engineering principles that should
ship with every future project — captured deliberately (via `/best-practices-record`) or promoted
from a project's `docs/BEST_PRACTICES.md` (via the per-entry promotion prompt in
`/best-practices-extract`). The quality bar here is intentionally higher than any project file's:
every entry must have passed the three portability questions (framework / project / audience)
defined in the shared `TRIAGE-AND-LIFT.md` procedure.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `~/.claude/BEST_PRACTICES.md` (this file) | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into `skills/sync/SKILL.md` |
| `<project>/docs/BEST_PRACTICES.md` | Per-project | Session extraction | Generalizable entries may be promoted here via `/best-practices-extract`'s prompt |
| `skills/sync/SKILL.md` (bootstrap content) | Distributed | `/best-practices-sync` from this file | Renders into every new project's starter `docs/BEST_PRACTICES.md` at `/sync` time |

Project-specific entries (those that fail any portability question) never reach this file by
design — they live only in the source project's `## Project-Specific` section.

Format: `- _Category_: Concise statement. One or two sentences max.`
"""

GLOBAL_RATIONALE_BLOCK = """\
## Where do entries live, and why?

This file is the **global cross-project pool**. It accumulates engineering principles that should
ship with every future project — captured deliberately (via `/best-practices-record`) or promoted
from a project's `docs/BEST_PRACTICES.md` (via the per-entry promotion prompt in
`/best-practices-extract`). The quality bar here is intentionally higher than any project file's:
every entry must have passed the three portability questions (framework / project / audience)
defined in the shared `TRIAGE-AND-LIFT.md` procedure.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `~/.claude/BEST_PRACTICES.md` (this file) | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into `skills/sync/SKILL.md` |
| `<project>/docs/BEST_PRACTICES.md` | Per-project | Session extraction | Generalizable entries may be promoted here via `/best-practices-extract`'s prompt |
| `skills/sync/SKILL.md` (bootstrap content) | Distributed | `/best-practices-sync` from this file | Renders into every new project's starter `docs/BEST_PRACTICES.md` at `/sync` time |

Project-specific entries (those that fail any portability question) never reach this file by
design — they live only in the source project's `## Project-Specific` section.

Format: `- _Category_: Concise statement. One or two sentences max.`
"""

PROJECT_SPECIFIC_INTRO = """\
## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see `skills/best-practices-extract/TRIAGE-AND-LIFT.md`.
"""

CLAUDE_MD_REF = "\nFor accumulated session learnings, see [BEST_PRACTICES.md](BEST_PRACTICES.md).\n"


# ---------------------------------------------------------------------------
# File manipulation
# ---------------------------------------------------------------------------

def append_to_section(content: str, section: str, label: str, text: str) -> str:
    """Append `- {label}: {text}` under `## {section}`, creating the section if absent."""
    entry_line = f"- {label}: {text}"
    section_header = f"## {section}"
    lines = content.splitlines(keepends=True)

    # Find the section
    section_idx = None
    for i, line in enumerate(lines):
        if line.rstrip('\r\n') == section_header:
            section_idx = i
            break

    if section_idx is None:
        # Section missing — append it at the end
        tail = content if content.endswith('\n') else content + '\n'
        return tail + f"\n{section_header}\n\n{entry_line}\n"

    # Find where this section ends (next ## or EOF)
    end_idx = len(lines)
    for i in range(section_idx + 1, len(lines)):
        if lines[i].startswith('## '):
            end_idx = i
            break

    # Find the last non-blank line within the section
    insert_idx = end_idx
    for i in range(end_idx - 1, section_idx, -1):
        if lines[i].strip():
            insert_idx = i + 1
            break

    new_lines = lines[:insert_idx] + [entry_line + '\n'] + lines[insert_idx:]
    return ''.join(new_lines)


def bootstrap_global_file(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(GLOBAL_FILE_HEADER, encoding='utf-8')


def backfill_global_rationale(path: Path) -> None:
    """Insert rationale block after the first H1, before the first H2."""
    content = path.read_text(encoding='utf-8')
    lines = content.splitlines(keepends=True)

    # Already present?
    if any('Where do entries live' in l for l in lines):
        return

    # Find first H1
    h1_idx = None
    for i, line in enumerate(lines):
        if line.startswith('# ') and not line.startswith('## '):
            h1_idx = i
            break

    if h1_idx is None:
        # No H1 — prepend the whole block
        path.write_text(GLOBAL_RATIONALE_BLOCK + '\n' + content, encoding='utf-8')
        return

    # Find first H2 after H1
    insert_idx = len(lines)
    for i in range(h1_idx + 1, len(lines)):
        if lines[i].startswith('## '):
            insert_idx = i
            break

    block_lines = ('\n' + GLOBAL_RATIONALE_BLOCK).splitlines(keepends=True)
    new_lines = lines[:insert_idx] + block_lines + ['\n'] + lines[insert_idx:]
    path.write_text(''.join(new_lines), encoding='utf-8')


def write_entries(file_path: Path, entries: list[dict], is_global: bool = False) -> list[str]:
    """Write entries to file_path, creating/bootstrapping as needed. Returns list of errors."""
    errors = []
    if not entries:
        return errors

    try:
        if not file_path.exists():
            if is_global:
                bootstrap_global_file(file_path)
            else:
                file_path.parent.mkdir(parents=True, exist_ok=True)
                file_path.write_text("# Best Practices\n", encoding='utf-8')
        elif is_global:
            backfill_global_rationale(file_path)

        content = file_path.read_text(encoding='utf-8')

        # Handle Project-Specific section specially (needs intro text on first creation)
        for entry in entries:
            section = entry.get('section', '')
            label = entry.get('label', '')
            text = entry.get('text', '')
            if not section or not label or not text:
                errors.append(f"Skipped malformed entry: {entry!r}")
                continue

            if section == 'Project-Specific' and f'## {section}' not in content:
                # Append intro block first
                tail = content if content.endswith('\n') else content + '\n'
                content = tail + '\n' + PROJECT_SPECIFIC_INTRO + '\n'

            content = append_to_section(content, section, label, text)

        file_path.write_text(content, encoding='utf-8')
    except OSError as e:
        errors.append(f"Failed to write {file_path}: {e}")

    return errors


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_input() -> dict:
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding='utf-8') as f:
            return json.load(f)
    return json.load(sys.stdin)


def main() -> None:
    try:
        data = load_input()
    except (json.JSONDecodeError, OSError) as e:
        print(json.dumps({"errors": [f"Input error: {e}"]}))
        sys.exit(1)

    project_file = Path(data.get('project_file', 'docs/BEST_PRACTICES.md'))
    global_file = Path(data.get('global_file', Path.home() / '.claude' / 'BEST_PRACTICES.md'))

    project_entries = data.get('project_entries', [])
    global_entries = data.get('global_entries', [])
    write_sentinel = bool(data.get('write_sentinel', False))
    patch_claude_md = bool(data.get('patch_claude_md', False))

    errors: list[str] = []

    # Write project entries
    errors += write_entries(project_file, project_entries, is_global=False)
    project_count = len(project_entries) - sum(1 for e in errors if str(project_file) in e)

    # Write global entries
    errors += write_entries(global_file, global_entries, is_global=True)
    global_count = len(global_entries) - sum(
        1 for e in errors if str(global_file) in e
    )

    # Sentinel file
    sentinel_written = False
    if write_sentinel:
        try:
            sentinel = Path('.bytewyrd') / 'precompact-extraction-done'
            sentinel.parent.mkdir(parents=True, exist_ok=True)
            sentinel.touch()
            sentinel_written = True
        except OSError as e:
            errors.append(f"Failed to write sentinel: {e}")

    # CLAUDE.md reference patch
    claude_md_patched = False
    if patch_claude_md:
        claude_path = Path('CLAUDE.md')
        try:
            if claude_path.exists():
                content = claude_path.read_text(encoding='utf-8')
                if 'BEST_PRACTICES' not in content:
                    claude_path.write_text(content.rstrip('\n') + CLAUDE_MD_REF, encoding='utf-8')
                    claude_md_patched = True
        except OSError as e:
            errors.append(f"Failed to patch CLAUDE.md: {e}")

    result = {
        'project_count': project_count,
        'global_count': global_count,
        'sentinel_written': sentinel_written,
        'claude_md_patched': claude_md_patched,
        'errors': errors,
    }
    print(json.dumps(result))
    if errors:
        sys.exit(1)


if __name__ == '__main__':
    main()
