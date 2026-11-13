#!/usr/bin/env python3
"""Strict-YAML lint for agent and skill frontmatter.

Usage: lint-frontmatter.py FILE...

Each FILE must start with a `---` frontmatter block that parses with
PyYAML's safe_load into a mapping with non-empty string `name` and
`description` values.

Two failure classes this exists to catch:

* Values that are not valid YAML, such as a plain `description:` with
  `: ` inside it ("mapping values are not allowed here"). Claude Code
  loads these only through a fallback that re-quotes the line, so any
  other YAML consumer sees a broken file.
* A plain scalar followed by ` #...`. YAML reads the rest of the line as
  a comment and silently drops it, so the value is truncated without an
  error.

Write long or punctuation-heavy values as a folded block scalar:

    description: >-
      Use this agent when ... Examples: <example>...</example>

Exit status: 0 when every file passes, 1 otherwise.
"""

import os
import sys

import yaml

REQUIRED_STRING_KEYS = ("name", "description")
HINT = 'write the value as a folded block scalar ("key: >-" with the text indented on the next line) or quote it'


def frontmatter(text):
    """Return (frontmatter_text, first_line_number) or raise ValueError."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        raise ValueError('missing frontmatter: the file must start with a "---" line')
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return "\n".join(lines[1:i]) + "\n", 2
    raise ValueError('frontmatter has no closing "---" line')


def trailing_comments(node, fm_lines):
    """Yield (line_index, key) for plain scalars followed by a comment."""
    if isinstance(node, yaml.MappingNode):
        for key_node, value_node in node.value:
            if isinstance(value_node, yaml.ScalarNode):
                if value_node.style is None and value_node.value != "":
                    end = value_node.end_mark
                    rest = fm_lines[end.line][end.column:] if end.line < len(fm_lines) else ""
                    if rest.lstrip().startswith("#"):
                        yield end.line, key_node.value
            else:
                yield from trailing_comments(value_node, fm_lines)
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            yield from trailing_comments(item, fm_lines)


def lint(path):
    """Return a list of (line_number, message) problems for one file."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return [(1, f"cannot read file: {exc}")]
    try:
        fm, first_line = frontmatter(text)
    except ValueError as exc:
        return [(1, str(exc))]

    try:
        node = yaml.compose(fm, Loader=yaml.SafeLoader)
        data = yaml.safe_load(fm)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        line = first_line + mark.line if mark is not None else first_line
        problem = getattr(exc, "problem", None) or str(exc).splitlines()[0]
        return [(line, f"frontmatter is not valid YAML ({problem}); {HINT}")]

    if not isinstance(data, dict):
        return [(first_line, "frontmatter must be a YAML mapping of key: value pairs")]

    problems = []
    for key in REQUIRED_STRING_KEYS:
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            problems.append((first_line, f'"{key}" must be a non-empty string'))

    fm_lines = fm.split("\n")
    for line_index, key in trailing_comments(node, fm_lines):
        problems.append(
            (
                first_line + line_index,
                f'"{key}" is followed by " #...", which YAML treats as a comment and drops from the value; {HINT}',
            )
        )
    return problems


def main(paths):
    if not paths:
        print("usage: lint-frontmatter.py FILE...", file=sys.stderr)
        return 2
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    failed = 0
    for path in paths:
        problems = lint(path)
        if problems:
            failed += 1
        for line, message in problems:
            print(f"{path}:{line}: {message}")
            if annotate:
                print(f"::error file={path},line={line}::{message}")
    print(f"frontmatter lint: {len(paths)} file(s) checked, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
