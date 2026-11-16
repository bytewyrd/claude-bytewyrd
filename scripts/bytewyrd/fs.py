"""Work-tree files: whether a seed target exists, creating one without
following a symlink, and reading one as drift does; plus the input helpers
that read files and the current directory as the bash scripts did.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import errno
import os
import posixpath
import stat as stat_module


def exists(directory, name):
    """True when DIRECTORY/NAME exists, even as a dangling symlink, or an
    entry of DIRECTORY equals NAME ignoring case."""
    return find_entry(directory, name) is not None


def find_entry(directory, name):
    """The entry of DIRECTORY that exists() finds for NAME: NAME itself, else
    the first entry, in sorted order, that equals NAME ignoring case; None
    when there is neither."""
    if os.path.lexists(os.path.join(directory, name)):
        return name
    try:
        entries = sorted(os.listdir(directory))
    except OSError:
        return None
    folded = name.casefold()
    return next((entry for entry in entries if entry.casefold() == folded), None)


def symlinked_dir(root, rel):
    """The first directory on the way to REL (under ROOT) that is a symlink, or None."""
    parts = rel.split("/")[:-1]
    for i in range(1, len(parts) + 1):
        sub = "/".join(parts[:i])
        if os.path.islink(os.path.join(root, sub)):
            return sub
    return None


def create(path, text):
    """Create PATH holding TEXT. Raises FileExistsError for any existing path,
    symlinks included, writing nothing there; a failed write removes the file."""
    f = open(path, "x", encoding="utf-8", newline="\n")
    try:
        f.write(text)
        f.close()
    except BaseException:
        try:
            f.close()
        except Exception:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass
        raise


MAX_TEXT = 8 << 20  # read_text() reads work-tree files of at most 8 MiB


def read_text(path):
    """PATH's text, with every CR removed, decoded as UTF-8 with surrogateescape.

    None when PATH is missing or, symlinks followed, is not a regular file (a
    directory, a device, a FIFO), or is over 8 MiB: a seed path that points at
    /dev/zero or a pipe is never read. Other errors, such as EACCES, raise
    OSError.
    """
    try:
        st = os.stat(path)
    except OSError as e:
        if e.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            return None
        raise
    if not stat_module.S_ISREG(st.st_mode):
        return None
    # O_NONBLOCK: should PATH become a FIFO after the stat, opening it can't hang.
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOCTTY", 0))
    try:
        if not stat_module.S_ISREG(os.fstat(fd).st_mode):
            return None
        chunks, size = [], 0
        while size <= MAX_TEXT:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
    finally:
        os.close(fd)
    if size > MAX_TEXT:
        return None
    return b"".join(chunks).replace(b"\r", b"").decode("utf-8", "surrogateescape")


# Input, read as the bash scripts read it.


def split_lines(data):
    """DATA's lines as awk and grep read them: split at each newline, a last
    line without one still a line, and no line at all in b""."""
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    return lines


def pwd():
    """The current directory as bash's pwd prints it: $PWD when that is an
    absolute, normalized path to the current directory, so a directory reached
    through a symlink keeps that name; else os.getcwd()."""
    path = os.environ.get("PWD", "")
    if path.startswith("/") and posixpath.normpath(path) == path:
        try:
            if os.path.samefile(path, "."):
                return path
        except OSError:
            pass
    return os.getcwd()
