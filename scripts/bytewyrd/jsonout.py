"""JSON output for the class-B helpers (rfc-* and tool-probe), which print one
object on stdout as jq printed it before their port; the skills parse it
with jq [R51].

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import json
import os
import re
import sys
from collections.abc import Callable

from bytewyrd import cli

# Lone surrogates that are not os.fsdecode()'s U+DC80..U+DCFF escape of a
# byte; a YAML escape such as "\ud800" makes one.
_LONE_SURROGATE: re.Pattern[str] = re.compile("[\ud800-\udc7f\udd00-\udfff]")


def jq_string(s: str) -> str:
    """S as valid Unicode, as jq holds a string, so encoding it can't raise
    UnicodeEncodeError [R80].

    The bytes that os.fsdecode() keeps as surrogate escapes, in an argument,
    path or directory that isn't UTF-8, are decoded as UTF-8 with U+FFFD for
    each invalid sequence, as jq did with --arg; any other lone surrogate
    becomes U+FFFD too. (Python replaces each maximal invalid subpart, as
    Unicode recommends, so for an overlong or out-of-range sequence it can
    give more U+FFFD than jq, and it never drops the bytes that follow a
    sequence cut short near the end of a string, as jq does.)
    """
    try:
        s.encode("utf-8")
        return s
    except UnicodeEncodeError:
        pass
    s = _LONE_SURROGATE.sub("\ufffd", s)
    return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def _jq_strings(value: object) -> object:
    if isinstance(value, str):
        return jq_string(value)
    if isinstance(value, dict):
        return {jq_string(k): _jq_strings(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jq_strings(v) for v in value]
    return value


def jq_dumps(value: object) -> str:
    """VALUE as jq prints it, with its final newline: two-space indents,
    keys in insertion order, raw UTF-8, and json's escapes plus \\u007f for
    DEL, the one character jq escapes and json doesn't. Every string, keys
    included, goes through jq_string()."""
    text = json.dumps(_jq_strings(value), indent=2, ensure_ascii=False)
    return text.replace("\x7f", "\\u007f") + "\n"


def emit(value: object) -> None:
    """Print jq_dumps(VALUE) on stdout, as UTF-8 whatever the locale."""
    data = jq_dumps(value).encode("utf-8")
    sys.stdout.flush()
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


# Ports of common.bash's functions of the same names, with the same JSON [R51].


def emit_error(message: str) -> None:
    """Print {"error": MESSAGE}."""
    emit({"error": message})


def emit_available(name: str) -> None:
    """Print {"result": "available", "name": NAME}."""
    emit({"result": "available", "name": name})


def emit_missing(name: str, hint: str) -> None:
    """Print {"result": "missing", "name": NAME, "hint": HINT}."""
    emit({"result": "missing", "name": name, "hint": hint})


def emit_unauth(name: str, hint: str) -> None:
    """Print {"result": "unauthenticated", "name": NAME, "hint": HINT}."""
    emit({"result": "unauthenticated", "name": name, "hint": hint})


def json_main(name: str, run: Callable[[list[str]], int], argv: list[str]) -> int:
    """The main() of the JSON helper NAME: the exit code of RUN(ARGV).

    An exception from RUN is printed as {"error": "NAME: ..."} with exit 2,
    the helpers' code for an error, so a failure such as an unwritable file
    never ends in a traceback and exit 1, which means "missing" or "not
    found" for some helpers [R62]. When stdout itself fails, the rest of it
    goes to /dev/null, so the exit can't fail on it again.
    """
    try:
        return run(argv)
    except Exception as e:
        try:
            emit_error("%s: %s" % (name, cli.describe(e)))
        except Exception:
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
            except Exception:
                pass
        return 2
