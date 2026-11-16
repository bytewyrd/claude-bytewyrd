"""Tests for `bw state-touch [--rm] [NAME]`, the only writer into .bytewyrd/ (RFC
2026-11-09-scaffold-and-drift, B2 and B4): a symlinked .bytewyrd or NAME leaves the outside
directory unchanged, --rm removes only a regular file, and once running it always exits 0.
tests/py/test_bw.py swaps .bytewyrd for a symlink after it is opened.

Every case runs `sh scripts/bw state-touch ...` as a child process, in an empty project directory,
with BYTEWYRD_PYTHON the interpreter that runs pytest. Output is compared as the bytes the child
wrote, trailing newlines included.
"""

import os
import time

import pytest

SYMLINKED_DIR = b"state-touch: .bytewyrd is a symlink; refusing to write through it\n"


def local_midnight_ns(year):
    """The mtime, in nanoseconds, that `touch -t YEAR01010000` sets: January 1st, 00:00 local time."""
    return int(time.mktime((year, 1, 1, 0, 0, 0, 0, 0, -1))) * 10**9


def set_mtime(path, year):
    """Set PATH's mtime to January 1st of YEAR, as local_midnight_ns() gives it."""
    ns = local_midnight_ns(year)
    os.utime(path, ns=(ns, ns))


@pytest.fixture
def touch(run_bw):
    """touch(*ARGS): `bw state-touch ARGS` in the project directory."""

    def touch(*args):
        return run_bw("state-touch", *args)

    return touch


def test_state_touch_creates_the_name_and_a_gitignore_holding_a_star(touch, project):
    assert touch("last-feature-engineer-stop") == (0, b"", b"")
    state = project / ".bytewyrd"
    assert (state / "last-feature-engineer-stop").is_file()
    assert (state / ".gitignore").read_bytes() == b"*\n"


def test_state_touch_again_moves_the_mtime_forward_and_leaves_an_existing_gitignore_alone(touch, project):
    state = project / ".bytewyrd"
    state.mkdir()
    (state / ".gitignore").write_bytes(b"custom\n")
    sentinel = state / "precompact-extraction-done"
    sentinel.touch()
    set_mtime(sentinel, 2000)
    assert touch("precompact-extraction-done") == (0, b"", b"")
    assert sentinel.stat().st_mtime_ns > local_midnight_ns(2001), "mtime did not move"
    assert (state / ".gitignore").read_bytes() == b"custom\n"


def test_state_touch_with_no_name_adds_the_gitignore_to_an_existing_dir_and_nothing_else(touch, project):
    state = project / ".bytewyrd"
    state.mkdir()
    (state / "plugin-version").write_bytes(b"x\n")
    assert touch() == (0, b"", b"")
    assert (state / ".gitignore").read_bytes() == b"*\n"
    assert sorted(os.listdir(state)) == [".gitignore", "plugin-version"]
    assert (state / "plugin-version").read_bytes() == b"x\n"


@pytest.mark.parametrize(
    "args",
    [("last-feature-engineer-stop",), ("--rm", "last-feature-engineer-stop"), ()],
    ids=["touch", "rm", "no-name"],
)
def test_state_touch_with_a_symlinked_bytewyrd_leaves_the_outside_directory_unchanged(args, touch, project, outside):
    os.symlink(outside, project / ".bytewyrd")
    (outside / "last-feature-engineer-stop").write_bytes(b"keep\n")
    assert touch(*args) == (0, b"", SYMLINKED_DIR)
    assert os.listdir(outside) == ["last-feature-engineer-stop"]
    assert (outside / "last-feature-engineer-stop").read_bytes() == b"keep\n"


def test_state_touch_refuses_a_dangling_bytewyrd_symlink_and_its_target_never_appears(touch, project, outside):
    os.symlink(outside / "made", project / ".bytewyrd")
    assert touch("last-feature-engineer-stop") == (0, b"", SYMLINKED_DIR)
    assert os.listdir(outside) == []


@pytest.mark.parametrize("name", ["last-feature-engineer-stop", "precompact-extraction-done"])
def test_state_touch_with_a_symlinked_name_leaves_its_target_unchanged(name, touch, project, outside):
    state = project / ".bytewyrd"
    state.mkdir()
    victim = outside / "victim"
    victim.write_bytes(b"keep\n")
    set_mtime(victim, 2000)
    os.symlink(victim, state / "last-feature-engineer-stop")
    os.symlink(outside / "new", state / "precompact-extraction-done")
    message = b"state-touch: .bytewyrd/%s is a symlink; refusing to write through it\n" % name.encode()
    assert touch(name) == (0, b"", message)
    assert victim.read_bytes() == b"keep\n"
    assert victim.stat().st_mtime_ns == local_midnight_ns(2000), "the symlink's target was touched"
    assert os.listdir(outside) == ["victim"]


def test_state_touch_rm_removes_a_regular_file(touch, project):
    state = project / ".bytewyrd"
    state.mkdir()
    (state / "last-feature-engineer-stop").touch()
    assert touch("--rm", "last-feature-engineer-stop") == (0, b"", b"")
    assert not os.path.lexists(state / "last-feature-engineer-stop")


def test_state_touch_rm_leaves_a_symlink_and_its_target_in_place(touch, project, outside):
    state = project / ".bytewyrd"
    state.mkdir()
    (outside / "victim").write_bytes(b"keep\n")
    os.symlink(outside / "victim", state / "a-link")
    message = b"state-touch: .bytewyrd/a-link is a symlink; refusing to remove it\n"
    assert touch("--rm", "a-link") == (0, b"", message)
    assert os.path.islink(state / "a-link")
    assert (outside / "victim").read_bytes() == b"keep\n"


def test_state_touch_rm_leaves_a_directory_in_place(touch, project):
    state = project / ".bytewyrd"
    (state / "a-dir").mkdir(parents=True)
    message = b"state-touch: .bytewyrd/a-dir is not a regular file; refusing to remove it\n"
    assert touch("--rm", "a-dir") == (0, b"", message)
    assert (state / "a-dir").is_dir()


def test_state_touch_rm_of_an_absent_name_is_quiet(touch):
    assert touch("--rm", "last-feature-engineer-stop") == (0, b"", b"")


@pytest.mark.parametrize(
    "name",
    ["../x", ".gitignore", "A", "a/b", "a b", "..", ""],
    ids=["parent-path", "dotfile", "uppercase", "slash", "space", "dotdot", "empty"],
)
def test_state_touch_with_an_invalid_name_writes_nothing_and_still_exits_0(name, touch, project, outside):
    got = touch(name)
    assert (got.returncode, got.stdout) == (0, b"")
    # One line, which says what was refused.
    assert got.stderr.startswith(b"state-touch: invalid name ")
    assert got.stderr.endswith(b"\n") and got.stderr.count(b"\n") == 1
    assert os.listdir(project) == [] and os.listdir(outside) == []


def test_state_touch_with_a_usage_error_prints_the_usage_and_still_exits_0(touch, project):
    usage = b"usage: bw state-touch [-h] [--rm] [name]\nbw state-touch: error: unrecognized arguments: --bogus\n"
    assert touch("--bogus") == (0, b"", usage)
    assert os.listdir(project) == []
