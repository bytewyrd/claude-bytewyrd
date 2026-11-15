"""bw rfc-resolve [ID]: resolve an RFC identifier, or a guess, to one RFC path.

It works in the current directory, which must hold docs/rfcs/. With ID, an
identifier such as 2026-05-14-foo, optionally with a docs/rfcs/ prefix and a
.md suffix, the RFC is docs/rfcs/ID.md. Without one, it is the only RFC that
`git status --short -- docs/rfcs/` lists, read as the bash script's awk read
it: deletions are skipped, a rename gives its new path, and a quoted path,
which no longer ends in .md, is ignored. Failing that, it is the last regular
file docs/rfcs/*.md in code point order, which for YYYY-MM-DD- names is the
most recently dated.

It prints {"path": ..., "label": ...} and exits 0, where path is absolute,
from the current directory as bash's pwd prints it (bw.pwd()), and label
says how the RFC was found, such as "RFC 2026-05-14-foo (matched argument)".
It prints {"error": "..."} and exits 1 when no RFC matches, and exits 2 with
an error when docs/rfcs/ is missing or ID holds a "/".

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os
import posixpath
import subprocess

import bw

RFCS = "docs/rfcs"


def modified():
    """The .md paths that `git status --short -- docs/rfcs/` lists, without
    deletions, each once and sorted; [] when git fails or isn't there."""
    try:
        proc = subprocess.run(
            ["git", "status", "--short", "--", RFCS + "/"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
    except OSError:
        return []
    paths = set()
    for line in proc.stdout.split(b"\n"):
        if line[:1] == b"D" or line[1:2] == b"D":
            continue
        arrow = line.find(b" -> ")
        if arrow >= 0:
            path = line[arrow + 4 :]
        else:
            path = line[3:] if line[2:3] == b" " else line
        if path.endswith(b".md"):
            paths.add(os.fsdecode(path))
    return sorted(paths)


def latest():
    """The last regular file docs/rfcs/*.md in code point order, or None."""
    try:
        names = os.listdir(RFCS)
    except OSError:
        return None
    files = [RFCS + "/" + n for n in sorted(names) if n.endswith(".md") and not n.startswith(".")]
    files = [f for f in files if os.path.isfile(f)]
    return files[-1] if files else None


def found(path, how):
    stem = posixpath.basename(path.removesuffix(".md"))
    bw.emit({"path": os.path.join(bw.pwd(), path), "label": "RFC %s (%s)" % (stem, how)})
    return 0


def run(argv):
    if not os.path.isdir(RFCS):
        bw.emit_error("rfc-resolve: no docs/rfcs/ directory in %s; run from project root" % bw.pwd())
        return 2
    arg = argv[0] if argv else ""
    if arg:
        stem = arg.removeprefix(RFCS + "/").removesuffix(".md")
        if "/" in stem:
            bw.emit_error("rfc-resolve: identifier must not contain '/' (got: %s)" % arg)
            return 2
        path = "%s/%s.md" % (RFCS, stem)
        if not os.path.isfile(path):
            bw.emit_error("rfc-resolve: no RFC found at %s" % path)
            return 1
        return found(path, "matched argument")
    paths = modified()
    if len(paths) == 1:
        if not os.path.isfile(paths[0]):
            bw.emit_error("rfc-resolve: modified file %s no longer exists" % paths[0])
            return 1
        return found(paths[0], "unique modified file")
    path = latest()
    if path is None:
        bw.emit_error("rfc-resolve: no RFC files under docs/rfcs/")
        return 1
    return found(path, "most recently dated file")


def main(argv):
    return bw.json_main("rfc-resolve", run, argv)
