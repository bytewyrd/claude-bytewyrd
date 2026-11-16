"""The work tree and its index, through the git command: the top level, the
project's name, the index entries, a blob's bytes, and whether the tree is
dirty.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import os
import subprocess
from typing import NamedTuple

from bytewyrd import cli

MAX_BLOB = 1 << 20  # blob() reads index entries of at most 1 MiB


class Entry(NamedTuple):
    """One index entry, as `git ls-files -s -z` lists it."""

    mode: str
    oid: str
    stage: int
    path: str


def _git(cwd, *args, input=None):
    """Run git (with -C CWD unless CWD is None); BwError if git can't start."""
    cmd = ["git"] + (["-C", cwd] if cwd is not None else []) + list(args)
    io = {"input": input} if input is not None else {"stdin": subprocess.DEVNULL}
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **io)
    except OSError as e:
        raise cli.BwError("cannot run git: %s" % (e.strerror or e)) from e


def _line(data):
    """Bytes of one line of git output, without its final newline, as a str."""
    if data.endswith(b"\n"):
        data = data[:-1]
    return os.fsdecode(data)


def root():
    """The top level of the work tree that contains the current directory."""
    proc = _git(None, "rev-parse", "--show-toplevel")
    if proc.returncode != 0 or not proc.stdout.strip():
        raise cli.BwError("not inside a git work tree")
    return _line(proc.stdout)


def project_name(root):
    """The project's name: the basename of the parent of the git common dir.

    In a linked worktree the top level is the worktree's own directory, while
    the common dir belongs to the main repository, so this names the project
    rather than the checkout. Falls back to the basename of ROOT.
    """
    fallback = os.path.basename(os.path.normpath(root))
    try:
        proc = _git(root, "rev-parse", "--git-common-dir")
    except cli.BwError:
        return fallback
    if proc.returncode != 0 or not proc.stdout.strip():
        return fallback
    common = os.path.abspath(os.path.join(root, _line(proc.stdout)))
    return os.path.basename(os.path.dirname(common)) or fallback


def tracked(root):
    """The index entries of ROOT, as Entry(mode, oid, stage, path) tuples."""
    proc = _git(root, "ls-files", "-s", "-z")
    if proc.returncode != 0:
        raise cli.BwError("git ls-files failed")
    entries = []
    for record in proc.stdout.split(b"\0"):
        if not record:
            continue
        meta, _, path = record.partition(b"\t")
        mode, oid, stage = meta.split(b" ")
        entries.append(Entry(mode.decode("ascii"), oid.decode("ascii"), int(stage), os.fsdecode(path)))
    return entries


def blob(root, entry):
    """The bytes of a regular stage-0 entry of at most 1 MiB, else None."""
    if entry.stage != 0 or entry.mode not in ("100644", "100755"):
        return None
    try:
        size = _git(root, "cat-file", "-s", entry.oid)
        if size.returncode != 0 or int(size.stdout) > MAX_BLOB:
            return None
        data = _git(root, "cat-file", "blob", entry.oid)
    except (cli.BwError, ValueError):
        return None
    if data.returncode != 0 or len(data.stdout) > MAX_BLOB:
        return None
    return data.stdout


def dirty(root):
    """True when `git status --porcelain` prints anything for ROOT.

    --no-optional-locks keeps git from refreshing the index on the way, so a
    dry run writes nothing, not even .git/index.
    """
    proc = _git(root, "--no-optional-locks", "status", "--porcelain")
    if proc.returncode != 0:
        raise cli.BwError("git status failed")
    return bool(proc.stdout)
