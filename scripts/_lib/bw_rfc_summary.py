"""bw rfc-summary: list every RFC's frontmatter, sorted by created, then rfc.

It works in the current directory, which must hold docs/rfcs/. Each regular
file docs/rfcs/*.md, in code point order, is read with bw.load_frontmatter().
A field is taken as the bash script's $(jq -r ...) gave it, with NUL bytes
and trailing newlines dropped. An RFC that can't be read, has no rfc or
status, or has a status other than Draft, Approved, Done or Dropped is left
out with a warning; a warning that holds a newline becomes one per line, as
jq -R split it.

It prints {"rfcs": [{"status": ..., "created": ..., "rfc": ..., "title":
..., "author": ...}, ...], "warnings": [...]} and exits 0, warnings or not.
Without docs/rfcs/ it prints {"error": "..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os

import bw

RFCS = "docs/rfcs"
STATUSES = ("Draft", "Approved", "Done", "Dropped")
ROW = ("status", "created", "rfc", "title", "author")


def names():
    """The names docs/rfcs/*.md matches, as bash's glob does, sorted."""
    try:
        entries = os.listdir(RFCS)
    except OSError:
        return []
    return sorted(n for n in entries if n.endswith(".md") and not n.startswith("."))


def summary():
    """The rows and warnings for the RFCs under docs/rfcs/."""
    rows, warnings = [], []
    for name in names():
        path = RFCS + "/" + name
        if not os.path.isfile(path):
            continue
        try:
            fields = bw.load_frontmatter(path)
        except Exception:  # as any failure of the rfc-frontmatter call did
            warnings.append("Warning: %s — frontmatter unparseable; skipping." % path)
            continue
        row = {key: bw.jq_string(fields[key]).replace("\0", "").rstrip("\n") for key in ROW}
        if not row["rfc"] or not row["status"]:
            warnings.append("Warning: %s — frontmatter incomplete; skipping." % path)
        elif row["status"] not in STATUSES:
            warnings.append('Warning: %s — unrecognized status "%s"; skipping.' % (path, row["status"]))
        else:
            rows.append(row)
    rows.sort(key=lambda row: (row["created"], row["rfc"]))
    return rows, [line for warning in warnings for line in warning.split("\n")]


def run(argv):
    if not os.path.isdir(RFCS):
        bw.emit_error("no docs/rfcs/ directory in " + bw.pwd())
        return 2
    rows, warnings = summary()
    bw.emit({"rfcs": rows, "warnings": warnings})
    return 0


def main(argv):
    return bw.json_main("rfc-summary", run, argv)
