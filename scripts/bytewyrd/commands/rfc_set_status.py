r"""bw rfc-set-status FILE STATUS [REASON]: set an RFC's status in place.

STATUS is Draft, Approved, Done or Dropped. REASON, the drop_reason, is
required for Dropped, refused for any other status, and may not hold a
newline. The old status is the one frontmatter.load_frontmatter() reads.

FILE is rewritten line by line as the bash script's awk rewrote it, between
its first two "---" lines: a line whose first blank-separated field is
"status:" becomes `status: "STATUS"`, and one whose first field is
"drop_reason:" becomes `drop_reason: "REASON"` for Dropped, with each \ and
" in REASON escaped, or `drop_reason: ~` otherwise. For Dropped without a
drop_reason line, one goes just before the closing "---". Every line of the
rewritten file ends with a newline.

It prints {"file": FILE, "old_status": ..., "new_status": STATUS} and exits
0. It prints {"error": "..."} and exits 2 for a usage error, a bad STATUS or
REASON, a FILE that is not a regular file, a frontmatter that
load_frontmatter() refuses or that has no status, no status line to rewrite,
or a failed read or write.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Ports").
"""

import os
import re
from typing import cast

from bytewyrd import cli, frontmatter, fs, jsonout

STATUSES: tuple[str, ...] = ("Draft", "Approved", "Done", "Dropped")
# The bash script's wording, with the command named as scripts/bw runs it.
USAGE: str = "usage: bw rfc-set-status <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"

_FIRST_FIELD: re.Pattern[bytes] = re.compile(rb"[ \t]*([^ \t]*)")  # awk's $1, split at blanks


def rewrite(data: bytes, status: str, reason: bytes) -> tuple[bytes, int]:
    """DATA, a file's bytes, with its frontmatter's status and drop_reason
    lines rewritten for STATUS and the escaped REASON (bytes), and the number
    of status lines rewritten."""
    out: list[bytes]
    out, delimiters, wrote_reason, rewritten = [], 0, False, 0
    reason_line = b'drop_reason: "' + reason + b'"'
    for line in fs.split_lines(data):
        if line == b"---":
            delimiters += 1
            if delimiters == 2 and status == "Dropped" and not wrote_reason:
                out.append(reason_line)
                wrote_reason = True
            out.append(line)
            continue
        # _FIRST_FIELD matches every line, if only as b"".
        field = cast("re.Match[bytes]", _FIRST_FIELD.match(line)).group(1) if delimiters == 1 else None
        if field == b"status:":
            out.append(b'status: "' + status.encode() + b'"')
            rewritten += 1
        elif field == b"drop_reason:":
            out.append(reason_line if status == "Dropped" else b"drop_reason: ~")
            wrote_reason = True
        else:
            out.append(line)
    return b"".join(line + b"\n" for line in out), rewritten


def run(argv: list[str]) -> int:
    path, status, reason = (list(argv[:3]) + ["", "", ""])[:3]
    if not path or not status:
        jsonout.emit_error(USAGE)
        return 2
    if status not in STATUSES:
        jsonout.emit_error("rfc-set-status: invalid status '%s' (allowed: Draft, Approved, Done, Dropped)" % status)
        return 2
    if status == "Dropped" and not reason:
        jsonout.emit_error("rfc-set-status: drop_reason is required when status=Dropped")
        return 2
    if status != "Dropped" and reason:
        jsonout.emit_error("rfc-set-status: drop_reason is only allowed when status=Dropped")
        return 2
    if not os.path.isfile(path):
        jsonout.emit_error("rfc-set-status: file not found: %s" % path)
        return 2
    try:
        old = frontmatter.load_frontmatter(path)["status"]
    except cli.BwError as e:
        jsonout.emit_error("rfc-set-status: " + str(e))
        return 2
    no_status = "rfc-set-status: %s has no 'status:' line in its frontmatter" % path
    if not old:
        jsonout.emit_error(no_status)
        return 2
    if "\n" in reason:
        jsonout.emit_error("rfc-set-status: drop_reason must not contain newlines")
        return 2
    escaped = os.fsencode(reason).replace(b"\\", b"\\\\").replace(b'"', b'\\"')
    with open(path, "rb") as f:
        text, rewritten = rewrite(f.read(), status, escaped)
    if not rewritten:
        jsonout.emit_error(no_status)
        return 2
    with open(path, "wb") as f:
        f.write(text)
    jsonout.emit({"file": path, "old_status": old, "new_status": status})
    return 0


def main(argv: list[str]) -> int:
    return jsonout.json_main("rfc-set-status", run, argv)
