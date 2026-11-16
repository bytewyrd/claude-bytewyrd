"""What every bw command shares: BwError, the failure a command reports as one
line; Parser, whose usage errors exit 1; and quote() and describe(), which
make repo-derived strings and exceptions safe to print.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import argparse
import os
import sys


class BwError(Exception):
    """A failure a command reports as one line, without a traceback."""


class Parser(argparse.ArgumentParser):
    """An ArgumentParser whose usage errors exit 1: argparse's 2 would read as drift."""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))


# --- quoting -----------------------------------------------------------------

_SAFE = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-")
_C_ESCAPES = {7: "\\a", 8: "\\b", 9: "\\t", 10: "\\n", 11: "\\v", 12: "\\f", 13: "\\r", 34: '\\"', 92: "\\\\"}


def quote(s):
    """S when it is non-empty and every character is in [A-Za-z0-9._/-];
    otherwise git's C-style quoting of its bytes. The result is ASCII."""
    if s and all(c in _SAFE for c in s):
        return s
    try:
        data = os.fsencode(s)
    except UnicodeError:  # a lone surrogate that surrogateescape didn't make
        data = s.encode("utf-8", "surrogatepass")
    out = ['"']
    for b in data:
        if b in _C_ESCAPES:
            out.append(_C_ESCAPES[b])
        elif b < 0x20 or b > 0x7E:
            out.append("\\%03o" % b)
        else:
            out.append(chr(b))
    out.append('"')
    return "".join(out)


def describe(e):
    """A one-line description of the exception E for an error message: the
    text as it is when it is printable ASCII, else quote() of it."""
    if isinstance(e, BwError):
        text = str(e)
    elif isinstance(e, OSError) and e.strerror:
        text = e.strerror
        if isinstance(e.filename, (str, bytes)):
            text += ": " + os.fsdecode(e.filename)
    else:
        text = "%s: %s" % (type(e).__name__, e) if str(e) else type(e).__name__
    return text if text.isascii() and text.isprintable() else quote(text)
