"""bw rfc-braindump-list: list the bullets of docs/rfc-braindump.md.

It works in the current directory and reads the file's lines as the bash
script's `while IFS= read -r line` loop did: a last line without a newline
is not read, and NUL bytes are dropped. Each line that starts with "* " is an
entry, whose body is the rest of the line, decoded as UTF-8 with U+FFFD for
any invalid sequence, as jq -R did.

It prints {"entries": [{"n": 1, "body": "..."}, ...]}, numbered from 1 in
file order, and exits 0. When the file is missing or not a regular file, the
list is empty; when it can't be read, the list is empty too, and one stderr
line says why.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os
import sys

from bytewyrd import cli, jsonout

FILE: str = "docs/rfc-braindump.md"


def entries(data: bytes) -> list[dict[str, int | str]]:
    """The entries of a braindump file whose bytes are DATA."""
    lines = data.split(b"\n")[:-1]  # what follows the last newline is never read
    bodies = [line[2:] for line in (raw.replace(b"\0", b"") for raw in lines) if line.startswith(b"* ")]
    return [{"n": n, "body": body.decode("utf-8", "replace")} for n, body in enumerate(bodies, 1)]


def run(argv: list[str]) -> int:
    data = b""
    if os.path.isfile(FILE):
        try:
            with open(FILE, "rb") as f:
                data = f.read()
        except OSError as e:
            sys.stderr.write("rfc-braindump-list: %s\n" % cli.describe(e))
            sys.stderr.flush()
    jsonout.emit({"entries": entries(data)})
    return 0


def main(argv: list[str]) -> int:
    return jsonout.json_main("rfc-braindump-list", run, argv)
