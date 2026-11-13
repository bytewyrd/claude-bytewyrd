#!/usr/bin/env python3
"""Check that relative links in Markdown files point at existing paths.

Usage: check-links.py [FILE...]

Run it from the repository root. With no FILE arguments it checks every
tracked Markdown file (`git ls-files '*.md'`).

Checks inline links and images (`[text](target)`, `![alt](target)`) and
reference definitions (`[id]: target`). Links with a URL scheme
(https:, mailto:, ...) and same-page anchors (#section) are skipped, as
are fenced code blocks, inline code spans, and HTML comments. A target
is resolved against the linking file's directory (or the repository
root when it starts with "/") after dropping any "#fragment" or
"?query"; the check passes when that file or directory exists.

Templates under templates/*.tpl are not Markdown files and are never
passed in: their links resolve where /sync renders them, not here.

Exit status: 0 when every link resolves, 1 otherwise.
"""

import os
import re
import subprocess
import sys
from urllib.parse import unquote

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+)(?:(?!\1).)+?\1")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.S)
# [text](target "title") / ![alt](<target with spaces>)
INLINE_LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*(<[^>\n]*>|[^)\s]+)(?:\s+(?:\"[^\"]*\"|'[^']*'|\([^)]*\)))?\s*\)")
REFERENCE_DEF = re.compile(r"^ {0,3}\[[^\]]+\]:\s*(<[^>\n]*>|\S+)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def strip_non_prose(text):
    """Blank out code fences, code spans and HTML comments, keeping line numbers."""
    text = HTML_COMMENT.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    out, fence = [], None
    for line in text.split("\n"):
        match = FENCE.match(line)
        if fence is None and match:
            fence = match.group(1)
            out.append("")
            continue
        if fence is not None:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence) and not line.strip()[len(match.group(1)):].strip():
                fence = None
            out.append("")
            continue
        out.append(INLINE_CODE.sub("CODE", line))
    return out


def targets(lines):
    for number, line in enumerate(lines, start=1):
        for match in INLINE_LINK.finditer(line):
            yield number, match.group(1)
        match = REFERENCE_DEF.match(line)
        if match:
            yield number, match.group(1)


def broken_links(path, repo_root):
    with open(path, encoding="utf-8") as fh:
        lines = strip_non_prose(fh.read())
    for number, raw in targets(lines):
        target = raw[1:-1] if raw.startswith("<") and raw.endswith(">") else raw
        if not target or target.startswith("#") or target.startswith("//") or SCHEME.match(target):
            continue
        target = unquote(target.split("#", 1)[0].split("?", 1)[0])
        if not target:
            continue
        base = repo_root if target.startswith("/") else os.path.dirname(path)
        resolved = os.path.normpath(os.path.join(base, target.lstrip("/")))
        if not os.path.exists(resolved):
            yield number, raw, os.path.relpath(resolved, repo_root)


def main(paths):
    if not paths:
        listed = subprocess.run(["git", "ls-files", "-z", "--", "*.md"], capture_output=True, check=True)
        paths = [p for p in listed.stdout.decode("utf-8").split("\0") if p]
    repo_root = os.getcwd()
    annotate = os.environ.get("GITHUB_ACTIONS") == "true"
    broken = 0
    for path in paths:
        for number, raw, resolved in broken_links(path, repo_root):
            broken += 1
            message = f"broken relative link {raw} (resolves to {resolved}, which does not exist)"
            print(f"{path}:{number}: {message}")
            if annotate:
                print(f"::error file={path},line={number}::{message}")
    print(f"link check: {len(paths)} file(s) checked, {broken} broken link(s)")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
