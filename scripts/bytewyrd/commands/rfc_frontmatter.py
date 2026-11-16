"""bw rfc-frontmatter FILE: print an RFC's six frontmatter fields as JSON.

It prints {"rfc": ..., "title": ..., "author": ..., "status": ..., "created":
..., "drop_reason": ...}, the strings that frontmatter.load_frontmatter() reads from
FILE, and exits 0. With no FILE or an empty one, or when load_frontmatter()
fails, it prints {"error": "..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2
("Frontmatter parsing" and "Ports").
"""

from bytewyrd import cli, frontmatter, jsonout

# The bash script's wording, with the command named as scripts/bw runs it.
USAGE: str = "usage: bw rfc-frontmatter <path-to-rfc.md>"


def run(argv: list[str]) -> int:
    path = argv[0] if argv else ""
    if not path:
        jsonout.emit_error(USAGE)
        return 2
    try:
        fields = frontmatter.load_frontmatter(path)
    except cli.BwError as e:
        jsonout.emit_error("rfc-frontmatter: " + str(e))
        return 2
    jsonout.emit(fields)
    return 0


def main(argv: list[str]) -> int:
    return jsonout.json_main("rfc-frontmatter", run, argv)
