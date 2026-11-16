"""bw state-touch [--rm] [NAME]: the only writer into .bytewyrd/.

It works in the current directory. It creates .bytewyrd if absent and opens
it with O_NOFOLLOW, then makes every later call through that descriptor, so
neither a symlinked .bytewyrd nor one swapped for a symlink mid-run can
redirect a write. It then creates .bytewyrd/.gitignore holding "*" if absent,
and touches NAME, or under --rm removes NAME when it is a regular file.

Once running it always exits 0, so no hook can fail on it; problems are
reported as one stderr line.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import os
import re
import stat
import sys

from bytewyrd import cli

STATE_DIR: str = ".bytewyrd"
NAME_RE: re.Pattern[str] = re.compile(r"[a-z0-9][a-z0-9.-]*")
_OPEN_DIR: int = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def _warn(message: str) -> None:
    sys.stderr.write("state-touch: " + message + "\n")


def _why(e: BaseException) -> str:
    return getattr(e, "strerror", None) or str(e) or type(e).__name__


def open_state_dir() -> int | None:
    """Create .bytewyrd if absent and return a no-follow descriptor for it,
    or None (after one stderr line) when that fails."""
    try:
        os.mkdir(STATE_DIR)
    except FileExistsError:
        pass
    except OSError as e:
        _warn("cannot create %s: %s" % (STATE_DIR, _why(e)))
        return None
    try:
        return os.open(STATE_DIR, _OPEN_DIR)
    except OSError as e:
        if os.path.islink(STATE_DIR):
            _warn("%s is a symlink; refusing to write through it" % STATE_DIR)
        else:
            _warn("cannot open %s: %s" % (STATE_DIR, _why(e)))
        return None


def _is_link(name: str, dir_fd: int) -> bool:
    try:
        return stat.S_ISLNK(os.stat(name, dir_fd=dir_fd, follow_symlinks=False).st_mode)
    except OSError:
        return False


def _write_gitignore(dir_fd: int) -> None:
    # Its patterns apply only within .bytewyrd/, and O_EXCL never follows a
    # symlink, so an existing file or link is left as it is.
    try:
        fd = os.open(".gitignore", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644, dir_fd=dir_fd)
    except FileExistsError:
        return
    try:
        os.write(fd, b"*\n")
    finally:
        os.close(fd)


def _touch(name: str, dir_fd: int) -> None:
    try:
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o644, dir_fd=dir_fd)
    except OSError as e:
        if _is_link(name, dir_fd):
            _warn("%s/%s is a symlink; refusing to write through it" % (STATE_DIR, name))
        else:
            _warn("cannot write %s/%s: %s" % (STATE_DIR, name, _why(e)))
        return
    os.close(fd)
    os.utime(name, dir_fd=dir_fd, follow_symlinks=False)


def _remove(name: str, dir_fd: int) -> None:
    try:
        mode = os.stat(name, dir_fd=dir_fd, follow_symlinks=False).st_mode
    except FileNotFoundError:
        return
    if stat.S_ISLNK(mode):
        _warn("%s/%s is a symlink; refusing to remove it" % (STATE_DIR, name))
    elif not stat.S_ISREG(mode):
        _warn("%s/%s is not a regular file; refusing to remove it" % (STATE_DIR, name))
    else:
        os.unlink(name, dir_fd=dir_fd)


def run(argv: list[str]) -> None:
    parser = cli.Parser(prog="bw state-touch", description="Touch, or with --rm remove, .bytewyrd/NAME.")
    parser.add_argument("--rm", action="store_true", help="remove NAME instead of touching it")
    parser.add_argument("name", nargs="?", help="a name matching [a-z0-9][a-z0-9.-]*")
    args = parser.parse_args(argv)
    if args.name is not None and not NAME_RE.fullmatch(args.name):
        _warn("invalid name %s: use lowercase letters, digits, '.' and '-'" % cli.quote(args.name))
        return
    dir_fd = open_state_dir()
    if dir_fd is None:
        return
    try:
        _write_gitignore(dir_fd)
        if args.name is not None:
            if args.rm:
                _remove(args.name, dir_fd)
            else:
                _touch(args.name, dir_fd)
    finally:
        os.close(dir_fd)


def main(argv: list[str]) -> int:
    try:
        run(argv)
    except SystemExit:
        pass  # argparse has already printed its usage or help
    except BaseException as e:
        try:
            _warn(_why(e))
        except BaseException:
            pass
    return 0
