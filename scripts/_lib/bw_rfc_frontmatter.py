"""bw rfc-frontmatter FILE: print an RFC's six frontmatter fields as JSON.

It prints {"rfc": ..., "title": ..., "author": ..., "status": ..., "created":
..., "drop_reason": ...}, the strings that bw.load_frontmatter() reads from
FILE, and exits 0. With no FILE or an empty one, or when load_frontmatter()
fails, it prints {"error": "..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2
("Frontmatter parsing" and "Ports").
"""

import bw

# The bash script's wording, its name included.
USAGE = "usage: rfc-frontmatter.sh <path-to-rfc.md>"


def run(argv):
    path = argv[0] if argv else ""
    if not path:
        bw.emit_error(USAGE)
        return 2
    try:
        fields = bw.load_frontmatter(path)
    except bw.BwError as e:
        bw.emit_error("rfc-frontmatter: " + str(e))
        return 2
    bw.emit(fields)
    return 0


def main(argv):
    return bw.json_main("rfc-frontmatter", run, argv)
