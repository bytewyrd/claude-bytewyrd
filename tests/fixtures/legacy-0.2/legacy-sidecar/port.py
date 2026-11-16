"""The B3 fix for legacy-sidecar: both sidecars go; a .bytewyrd/ that remains gets state-touch."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _port  # noqa: E402


def before(port):
    for rel in (".bytewyrd/.bootstrap-versions.json", ".claude/.bootstrap-versions.json"):
        port.remove(rel)
    if os.path.isdir(port.path(".bytewyrd")):
        port.bw("state-touch")


_port.main(before)
