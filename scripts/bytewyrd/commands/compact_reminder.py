"""bw compact-reminder: the SessionStart `compact` hook's /docs-review reminder.

It works in the current directory. While .bytewyrd/last-feature-engineer-stop,
which the SubagentStop hook touches, is a regular file under a day old, it
prints the reminder; otherwise it prints nothing. It always exits 0.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import os
import stat
import sys
import time

from bytewyrd import cli

SENTINEL = os.path.join(".bytewyrd", "last-feature-engineer-stop")
MAX_AGE = 86400  # seconds
TEXT = (
    "Post-compact reminder: a feature-engineer agent finished in the last 24 hours and "
    "/docs-review may not yet have run. Ask the user to run /docs-review against the "
    "implemented files."
)


def due():
    """True while the sentinel is a regular file whose mtime is under a day old."""
    try:
        st = os.lstat(SENTINEL)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and time.time() - st.st_mtime < MAX_AGE


def main(argv):
    try:
        cli.Parser(
            prog="bw compact-reminder", description="Print the /docs-review reminder when it is due."
        ).parse_args(argv)
        if due():
            sys.stdout.write(TEXT + "\n")
    except BaseException:
        pass  # SystemExit included: argparse has already printed its usage or help
    try:
        sys.stdout.flush()
    except BaseException:
        # A flush that fails now fails again at exit, which then exits 120;
        # send what is left to /dev/null instead.
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except BaseException:
            pass
    return 0
