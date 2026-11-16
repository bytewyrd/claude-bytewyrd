"""Fixtures for the tests that run the plugin as a child process, `sh scripts/bw ...`:
test_launcher.py, test_state_touch.py and test_hooks.py (RFC 2026-11-09-scaffold-and-drift,
B2 and B4). They port tests/scripts/helpers.bash and tests/scripts/python-stubs.bash.

None of them is autouse. A child gets an environment built here from PATH, TMPDIR and a HOME
inside the test's directory, so the developer's BYTEWYRD_PYTHON and CLAUDE_PLUGIN_ROOT never
reach it; a test adds what it needs.
"""

import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

import pytest

REPO = Path(__file__).resolve().parents[2]
BW = REPO / "scripts" / "bw"
SH = shutil.which("sh")

# The launcher's version report, verbatim (B2 step 2). A stub answers only this exact argv, so the
# test fails if the launcher changes its flags.
BW_REPORT = "import sys; sys.exit(sys.version_info < (3, 11))"

STUB = """\
#!/bin/sh
if [ "$#" -eq 4 ] && [ "$1" = -I ] && [ "$2" = -S ] && [ "$3" = -c ] && [ "$4" = {report} ]; then
  echo {reported} >>{log}
  exit {code}
fi
if [ "$1" = -I ] && [ "$2" = -S ] && [ "$3" = -B ]; then
  echo {executed} >>{log}
  printf '%s\\n' {ran} "$@"
  exit 0
fi
echo {unexpected} >>{log}
exit 99
"""


class Result(NamedTuple):
    """A finished child: its exit code and the bytes it wrote to each stream, as they were."""

    returncode: int
    stdout: bytes
    stderr: bytes


def run(argv, cwd, env):
    """Run ARGV in CWD with exactly ENV, and return how it ended and what it wrote."""
    proc = subprocess.run(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=120)
    return Result(proc.returncode, proc.stdout, proc.stderr)


class Stubs:
    """Stub interpreters, for the tests that control which one scripts/bw finds.

    A stub answers the launcher's version report and logs each call in `log`, so a test can tell which
    candidates were asked and which one ran. `bin` is a PATH directory that holds only the tools the
    launcher and the hook commands use without Python (sh, mkdir and cat), as symlinks.
    """

    def __init__(self, root, base_env):
        self.root, self.base_env = root, base_env
        self.bin = root / "stub-bin"
        self.log = root / "stub.log"
        self.bin.mkdir(parents=True)
        self.log.touch()
        for tool in ("sh", "mkdir", "cat"):
            os.symlink(os.path.abspath(shutil.which(tool)), self.bin / tool)

    def python(self, directory, name, version):
        """Create the executable DIRECTORY/NAME and return its path. Asked the version report, it exits
        0 when VERSION is "new" and 1 when it is "old", and logs "NAME report". Run the way the launcher
        execs an interpreter (-I -S -B ...), it logs "NAME exec", prints "ran NAME" and then each
        argument on its own line, and exits 0. Anything else logs "NAME unexpected" and exits 99."""
        code = {"new": 0, "old": 1}[version]
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        path.write_text(
            STUB.format(
                report=shlex.quote(BW_REPORT),
                reported=shlex.quote(name + " report"),
                executed=shlex.quote(name + " exec"),
                unexpected=shlex.quote(name + " unexpected"),
                ran=shlex.quote("ran " + name),
                log=shlex.quote(str(self.log)),
                code=code,
            )
        )
        path.chmod(0o755)
        return path

    def logged(self):
        """The log's text, one line per call."""
        return self.log.read_text()

    def env(self, python=None):
        """A child environment whose PATH is `bin` alone. BYTEWYRD_PYTHON is PYTHON when that is given, even
        as "", and unset when it is None."""
        env = {**self.base_env, "PATH": str(self.bin)}
        if python is not None:
            env["BYTEWYRD_PYTHON"] = str(python)
        return env

    def without_python(self, setup):
        """The environment in which scripts/bw finds no Python 3.11 or newer, in one of two setups.

        none: PATH is `bin`, with no interpreter, and BYTEWYRD_PYTHON is unset.
        old: BYTEWYRD_PYTHON (the stub "custom"), python3, python3.10 and python all report Python 3.9,
        so each command logs "custom report" and "python3 report". The launcher never asks python3.10
        or python, so a stray run of either shows up as "ran ..." output."""
        if setup == "none":
            return self.env()
        assert setup == "old"
        custom = self.root / "stub-old" / "custom"
        if not custom.exists():
            self.python(custom.parent, "custom", "old")
            for name in ("python3", "python3.10", "python"):
                self.python(self.bin, name, "old")
        return self.env(python=custom)


@pytest.fixture
def base_env(tmp_path):
    """What a child starts from: PATH and TMPDIR as they are here, HOME inside the test's directory, and
    nothing else."""
    home = tmp_path / "home"
    home.mkdir()
    env = {"PATH": os.environ.get("PATH", os.defpath), "HOME": str(home)}
    if os.environ.get("TMPDIR"):
        env["TMPDIR"] = os.environ["TMPDIR"]
    return env


@pytest.fixture
def bw_env(base_env):
    """base_env plus BYTEWYRD_PYTHON, set to the interpreter that runs pytest, which is 3.11 or newer."""
    return {**base_env, "BYTEWYRD_PYTHON": sys.executable}


@pytest.fixture
def project(tmp_path):
    """The empty directory that children run in."""
    path = tmp_path / "project"
    path.mkdir()
    return path


@pytest.fixture
def outside(tmp_path):
    """An empty directory next to the project, for symlinks to point at and for a test to check that
    nothing was written through them."""
    path = tmp_path / "outside"
    path.mkdir()
    return path


@pytest.fixture
def run_child(project, bw_env):
    """run_child(ARGV, cwd=PROJECT, env=BW_ENV): run ARGV and return its Result."""

    def run_child(argv, *, cwd=None, env=None):
        return run([str(a) for a in argv], cwd or project, bw_env if env is None else env)

    return run_child


@pytest.fixture
def run_bw(run_child):
    """run_bw(*ARGS, cwd=PROJECT, env=BW_ENV, launcher=BW): `sh LAUNCHER ARGS`, the way the skills and
    hooks run it, as a Result."""

    def run_bw(*args, cwd=None, env=None, launcher=BW):
        return run_child([SH, launcher, *args], cwd=cwd, env=env)

    return run_bw


@pytest.fixture
def stubs(tmp_path, base_env):
    """A Stubs kit in its own directory, with an empty log."""
    return Stubs(tmp_path / "stubs", base_env)
