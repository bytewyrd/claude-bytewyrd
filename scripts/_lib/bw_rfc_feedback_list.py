r"""bw rfc-feedback-list FILE: list the FEEDBACK: markers in an RFC.

A marker is a line that the bash script's grep '^\s*[-*>]*\s*FEEDBACK:'
matched: optional whitespace, any run of '-', '*' and '>', optional
whitespace, then FEEDBACK:. Whitespace is ASCII's, as \s is in the C locale.
Lines are counted from 1 as grep counted them, so a last line without a
newline is one. A marker's text is its line up to the first tab, decoded as
UTF-8 with U+FFFD for any invalid sequence: the bash script split grep's
output at tabs, so the text of a tab-indented marker is "".

It prints {"markers": [{"line": N, "text": "..."}, ...]} and exits 0. With no
FILE or an empty one, a FILE that is not a regular file, or a failed read, it
prints {"error": "..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os
import re

import bw

MARKER = re.compile(rb"\s*[-*>]*\s*FEEDBACK:")  # for bytes, \s is [ \t\n\r\f\v]
# The bash script's wording, with the command named as scripts/bw runs it.
USAGE = "usage: bw rfc-feedback-list <path-to-rfc.md>"


def markers(data):
    """The markers in a file whose bytes are DATA."""
    found = []
    for n, line in enumerate(bw.split_lines(data), 1):
        if MARKER.match(line):
            found.append({"line": n, "text": line.decode("utf-8", "replace").partition("\t")[0]})
    return found


def run(argv):
    path = argv[0] if argv else ""
    if not path:
        bw.emit_error(USAGE)
        return 2
    if not os.path.isfile(path):
        bw.emit_error("rfc-feedback-list: file not found: %s" % path)
        return 2
    with open(path, "rb") as f:
        data = f.read()
    bw.emit({"markers": markers(data)})
    return 0


def main(argv):
    return bw.json_main("rfc-feedback-list", run, argv)
