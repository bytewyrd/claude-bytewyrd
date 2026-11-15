"""Helpers for the legacy fixtures' scripted ports (see README.md).

A case's port.py calls main(before, after). It runs as
`python port.py PHASE REPO STATE PLUGIN`, with PHASE "before" (the B3 fixes,
which are committed before scaffold --apply runs) or "after" (the moves that
need scaffold's AGENTS.md). Like consumer-sim, it imports nothing from
scripts/; it runs the plugin only as `sh PLUGIN/scripts/bw`.
"""

import os
import subprocess
import sys
from typing import NamedTuple

# The 0.2.x header and banner forms that the fixes delete.
LEGACY_PREFIXES = (
    "<!-- bootstrap-content-version:",
    "# bootstrap-content-version:",
    "<!-- Managed by the Bytewyrd plugin",
    "<!-- Bootstrapped by the Bytewyrd plugin",
)


class Section(NamedTuple):
    """An H2 section of a Markdown file: its title and its text, heading included."""

    title: str
    text: str


def h2_sections(text):
    """TEXT split into what precedes its first "## " heading and its H2 sections."""
    preamble, sections = [], []
    for line in text.splitlines(keepends=True):
        if line.startswith("## "):
            sections.append([line[3:].strip(), line])
        elif sections:
            sections[-1][1] += line
        else:
            preamble.append(line)
    return "".join(preamble), [Section(title, body) for title, body in sections]


class Port:
    def __init__(self, repo, state, plugin):
        self.repo, self.state, self.plugin = repo, state, plugin

    def path(self, rel):
        return os.path.join(self.repo, rel)

    def git(self, *args):
        subprocess.run(["git", "-C", self.repo, *args], check=True, capture_output=True)

    def tracked(self, rel):
        proc = subprocess.run(["git", "-C", self.repo, "ls-files", "--error-unmatch", "--", rel], capture_output=True)
        return proc.returncode == 0

    def remove(self, rel):
        """git rm REL, or delete it when it is untracked."""
        if self.tracked(rel):
            self.git("rm", "-q", "--", rel)
        else:
            os.remove(self.path(rel))

    def move(self, src, dst):
        """git mv SRC DST, or rename it when it is untracked."""
        if self.tracked(src):
            self.git("mv", "--", src, dst)
        else:
            os.rename(self.path(src), self.path(dst))

    def read(self, rel):
        with open(self.path(rel), encoding="utf-8", newline="") as f:
            return f.read()

    def write(self, rel, text):
        with open(self.path(rel), "w", encoding="utf-8", newline="") as f:
            f.write(text)

    def append(self, rel, text):
        self.write(rel, self.read(rel) + text)

    def keep_lines(self, rel, keep):
        """Rewrite REL with only the lines for which keep(number, line) is true."""
        lines = self.read(rel).splitlines(keepends=True)
        self.write(rel, "".join(line for n, line in enumerate(lines, 1) if keep(n, line)))

    def drop_header(self, rel):
        """Delete the 0.2.x header and banner lines from lines 1 to 3 of REL."""
        self.keep_lines(rel, lambda n, line: n > 3 or not line.startswith(LEGACY_PREFIXES))

    def save(self, name, text):
        with open(os.path.join(self.state, name), "w", encoding="utf-8") as f:
            f.write(text)

    def load(self, name):
        with open(os.path.join(self.state, name), encoding="utf-8") as f:
            return f.read()

    def bw(self, *args):
        subprocess.run(["sh", os.path.join(self.plugin, "scripts", "bw"), *args], cwd=self.repo, check=True)


def main(before, after=None):
    phase, repo, state, plugin = sys.argv[1:5]
    port = Port(repo, state, plugin)
    if phase == "before":
        before(port)
    elif phase == "after":
        if after is not None:
            after(port)
    else:
        sys.exit("unknown phase: " + phase)
