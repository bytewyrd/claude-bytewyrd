"""The B3 fix for legacy-gitignore: the header and the # bytewyrd: tag lines go, the patterns stay."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _port  # noqa: E402


def before(port):
    port.keep_lines(".gitignore", lambda n, line: not line.startswith(("# bootstrap-content-version:", "# bytewyrd:")))


_port.main(before)
