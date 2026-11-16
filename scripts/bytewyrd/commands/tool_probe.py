"""bw tool-probe NAME: say whether the tool NAME, one of gh, git and jq, is available.

A tool is available when an executable NAME is on PATH; gh must also pass
`gh auth status`.

It prints {"result": "available", "name": NAME} and exits 0, or exits 1 after
{"result": "missing", "name": NAME, "hint": ...} or, for a gh that is not
logged in, {"result": "unauthenticated", "name": "gh", "hint": ...}. Without
NAME, or for any other NAME, it prints {"error": "..."} and exits 2.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import shutil
import subprocess

from bytewyrd import jsonout

# Each probe's hint when its tool is missing.
MISSING = {
    "gh": "gh CLI not on PATH. Install: https://cli.github.com.",
    "git": "git not on PATH. Install: https://git-scm.com/downloads.",
    "jq": "Install jq: https://stedolan.github.io/jq/download/",
}
UNAUTHENTICATED = "gh CLI present but not authenticated. Run: gh auth login."
# The bash script's wording, with the command named as scripts/bw runs it.
USAGE = "usage: bw tool-probe <gh|git|jq>"


def logged_in(gh):
    """True when `gh auth status`, run from the path GH, exits 0."""
    try:
        proc = subprocess.run([gh, "auth", "status"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        return False
    return proc.returncode == 0


def run(argv):
    name = argv[0] if argv else ""
    if not name:
        jsonout.emit_error(USAGE)
        return 2
    if name not in MISSING:
        jsonout.emit_error("unrecognized probe name '%s'" % name)
        return 2
    path = shutil.which(name)
    if path is None:
        jsonout.emit_missing(name, MISSING[name])
        return 1
    if name == "gh" and not logged_in(path):
        jsonout.emit_unauth(name, UNAUTHENTICATED)
        return 1
    jsonout.emit_available(name)
    return 0


def main(argv):
    return jsonout.json_main("tool-probe", run, argv)
