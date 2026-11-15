"""bw rfc-braindump-append BODY: add the bullet "* BODY" to docs/rfc-braindump.md.

It works in the current directory. When docs/rfc-braindump.md is not a
regular file, it is first written with the braindump's standard header. BODY
goes in as the bytes it was given, and no newline is added before it, so a
file whose last line has none gets the bullet on that line, as with the bash
script.

It prints {"appended": true, "file": "docs/rfc-braindump.md", "created_file":
BOOL}, where created_file says whether it wrote the header, and exits 0. With
no BODY or an empty one, or when the write fails, it prints {"error": "..."}
and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os

import bw

FILE = "docs/rfc-braindump.md"
HEADER = b"# RFC Braindump\n\nPotential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.\n\n"
# The bash script's wording, its name included.
USAGE = "usage: rfc-braindump-append.sh <full-bullet-body-without-leading-star-space>"


def run(argv):
    body = argv[0] if argv else ""
    if not body:
        bw.emit_error(USAGE)
        return 2
    bullet = b"* " + os.fsencode(body) + b"\n"
    created = not os.path.isfile(FILE)
    with open(FILE, "wb" if created else "ab") as f:
        f.write(HEADER + bullet if created else bullet)
    bw.emit({"appended": True, "file": FILE, "created_file": created})
    return 0


def main(argv):
    return bw.json_main("rfc-braindump-append", run, argv)
