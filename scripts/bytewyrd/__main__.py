"""Check the interpreter, then dispatch one bw command to its module.

scripts/bw runs this file as `python -I -S -B bytewyrd/__main__.py NAME
[ARGS...]`. NAME selects scripts/bytewyrd/commands/<name>.py (hyphens as
underscores), whose main(argv) returns the exit code.

This file must stay parseable by old Python 3 interpreters, so that one which
runs it directly still reaches the version check below: no f-strings, walrus,
match statements or annotations here. Code that needs 3.11 lives in the
modules it imports.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import json
import os
import sys

# Keep these lists in step with the case statement in scripts/bw.
CLASS_A = ("scaffold", "drift", "state-touch", "compact-reminder")
CLASS_B = (
    "rfc-braindump-append",
    "rfc-braindump-list",
    "rfc-braindump-remove",
    "rfc-feedback-list",
    "rfc-frontmatter",
    "rfc-resolve",
    "rfc-set-status",
    "rfc-summary",
    "tool-probe",
)

NEEDS_PYTHON = "bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)"


def cannot_run(name, message):
    """Report that NAME cannot run, using its class's exit contract.

    Class A prints one stderr line and returns 1. Class B prints a JSON error
    object on stderr and returns 2, because exit 1 already means "missing" or
    "not found" for those helpers.
    """
    if name in CLASS_B:
        sys.stderr.write(json.dumps({"error": message}, separators=(",", ":")) + "\n")
        return 2
    sys.stderr.write(message + "\n")
    return 1


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("bw: usage: bw NAME [ARGS...]\n")
        return 1
    name = argv[1]
    if name not in CLASS_A and name not in CLASS_B:
        sys.stderr.write("bw: unknown command: " + name + "\n")
        return 1
    if sys.version_info < (3, 11):
        return cannot_run(name, NEEDS_PYTHON)

    import importlib

    scripts = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vendor = os.path.join(scripts, "_vendor")
    sys.path[0:0] = [scripts, vendor]
    module_name = "bytewyrd.commands." + name.replace("-", "_")
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError as e:
        if e.name != module_name:
            raise
        return cannot_run(name, "bytewyrd: " + name + " is not available in this copy of the plugin")
    return module.main(argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
