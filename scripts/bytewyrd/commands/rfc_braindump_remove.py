"""bw rfc-braindump-remove BODY: remove the bullet "* BODY" from docs/rfc-braindump.md.

It works in the current directory. The first line that equals "* BODY", byte
for byte, is removed and later ones stay. Lines are read as the bash script's
awk read them, so a last line without a newline counts, and the rewritten
file ends every line with one. BODY is compared as given: the bash script
passed it through `awk -v`, which undid its backslash escapes first, so a
body holding a backslash never matched there.

It prints {"removed": true, "file": "docs/rfc-braindump.md"} and exits 0 when
it removed a line, or {"removed": false, ...} and exits 1, leaving the file
as it was, when no line matched. With no BODY or an empty one, no regular
file docs/rfc-braindump.md, or a failed read or write, it prints {"error":
"..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os

from bytewyrd import fs, jsonout

FILE = "docs/rfc-braindump.md"
# The bash script's wording, with the command named as scripts/bw runs it.
USAGE = "usage: bw rfc-braindump-remove <full-bullet-body-without-leading-star-space>"


def run(argv):
    body = argv[0] if argv else ""
    if not body:
        jsonout.emit_error(USAGE)
        return 2
    if not os.path.isfile(FILE):
        jsonout.emit_error("rfc-braindump-remove: %s not found" % FILE)
        return 2
    with open(FILE, "rb") as f:
        lines = fs.split_lines(f.read())
    target = b"* " + os.fsencode(body)
    if target not in lines:
        jsonout.emit({"removed": False, "file": FILE})
        return 1
    lines.remove(target)  # the first match only
    with open(FILE, "wb") as f:
        f.write(b"".join(line + b"\n" for line in lines))
    jsonout.emit({"removed": True, "file": FILE})
    return 0


def main(argv):
    return jsonout.json_main("rfc-braindump-remove", run, argv)
