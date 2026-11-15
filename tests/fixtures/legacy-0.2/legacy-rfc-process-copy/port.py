"""The B3 fix for legacy-rfc-process-copy: the copy goes, and its Project Extensions move to AGENTS.md."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _port  # noqa: E402


def before(port):
    _, sections = _port.h2_sections(port.read("docs/rfc-process.md"))
    port.save("extensions", "".join(s.text for s in sections if s.title == "Project Extensions"))
    port.remove("docs/rfc-process.md")


def after(port):
    port.append("AGENTS.md", "\n" + port.load("extensions"))


_port.main(before, after)
