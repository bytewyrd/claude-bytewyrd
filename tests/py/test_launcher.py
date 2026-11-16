"""Tests for scripts/bw, the POSIX-sh launcher (RFC 2026-11-09-scaffold-and-drift, B2 and B4):
which interpreter it picks, the per-class exit contracts when no Python 3.11 or newer is found,
the plain-sh PreCompact sentinel, NAME checks, and the -I -S -B flags that keep a venv's .pth
files and bytecode out.

Every case runs the real `sh scripts/bw ...` as a child process. The interpreter-selection cases
put stub interpreters (the Stubs kit in conftest.py) on a PATH that holds nothing else, so the
stub log shows which candidates the launcher asked and which one it ran. Output is compared as
the bytes the child wrote, trailing newlines included.
"""

import json
import os
import shutil
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
BW = REPO / "scripts" / "bw"
MAIN = REPO / "scripts" / "bytewyrd" / "__main__.py"

NEEDS = b"bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)"
# What the launcher passes to the interpreter it picks, before NAME and ARGS.
EXEC = ("-I", "-S", "-B", str(MAIN))

CLASS_A = [
    ("scaffold",),
    ("scaffold", "--apply"),
    ("drift",),
    ("drift", "--strict"),
    ("compact-reminder",),
    ("state-touch",),
    ("state-touch", "last-feature-engineer-stop"),
    ("state-touch", "--rm", "last-feature-engineer-stop"),
    ("state-touch", "--rm", "precompact-extraction-done"),
    ("state-touch", "precompact-extraction-done", "extra"),
]
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
VERSIONED = ("python3.15", "python3.14", "python3.13", "python3.12", "python3.11")

# The two setups in which no interpreter qualifies, and what each one's log holds after a command:
# the old setup asks $BYTEWYRD_PYTHON, then python3.
SETUPS = ["none", "old"]
ASKED = {"none": "", "old": "custom report\npython3 report\n"}


def ran(name, *argv):
    """What the stub NAME prints when it is run: "ran NAME", then each argument on its own line."""
    return os.fsencode("".join(line + "\n" for line in ("ran " + name, *argv)))


# --- interpreter selection ---------------------------------------------------


def test_launcher_takes_bytewyrd_python_when_it_reports_3_11_and_passes_name_and_args_through(stubs, run_bw):
    custom = stubs.python(stubs.root / "custom", "custom", "new")
    stubs.python(stubs.bin, "python3.15", "new")
    got = run_bw("drift", "--strict", "two words", "", env=stubs.env(python=custom))
    # The empty last argument shows as an empty last line: it is passed on, not dropped.
    assert got == (0, ran("custom", *EXEC, "drift", "--strict", "two words", ""), b"")
    assert stubs.logged() == "custom report\ncustom exec\n"


def test_launcher_skips_bytewyrd_python_when_it_reports_3_9_then_takes_the_highest_versioned_name(stubs, run_bw):
    custom = stubs.python(stubs.root / "custom", "custom", "old")
    for name in ("python3.11", "python3.13", "python3"):
        stubs.python(stubs.bin, name, "new")
    got = run_bw("scaffold", env=stubs.env(python=custom))
    assert got == (0, ran("python3.13", *EXEC, "scaffold"), b"")
    assert stubs.logged() == "custom report\npython3.13 exec\n"


@pytest.mark.parametrize("value", ["unset", "empty", "unrunnable"])
def test_launcher_falls_through_to_path_when_bytewyrd_python_is_unset_empty_or_unrunnable(value, stubs, run_bw):
    stubs.python(stubs.bin, "python3.12", "new")
    python = {"unset": None, "empty": "", "unrunnable": stubs.root / "no-such-python"}[value]
    got = run_bw("drift", env=stubs.env(python=python))
    assert got == (0, ran("python3.12", *EXEC, "drift"), b"")
    assert stubs.logged() == "python3.12 exec\n"


@pytest.mark.parametrize("want", VERSIONED)
def test_launcher_takes_the_highest_versioned_name_trusted_without_asking(want, stubs, run_bw):
    # Each versioned stub would report 3.9 if asked; trusted by name, it never is. The stubs above
    # WANT are left out, which is what removing each winner in turn would leave.
    for name in VERSIONED[VERSIONED.index(want) :]:
        stubs.python(stubs.bin, name, "old")
    stubs.python(stubs.bin, "python3", "new")
    got = run_bw("compact-reminder", env=stubs.env())
    assert got == (0, ran(want, *EXEC, "compact-reminder"), b"")
    assert stubs.logged() == want + " exec\n"


def test_launcher_takes_python3_last_and_asks_it(stubs, run_bw):
    stubs.python(stubs.bin, "python3", "new")
    got = run_bw("compact-reminder", env=stubs.env())
    assert got == (0, ran("python3", *EXEC, "compact-reminder"), b"")
    assert stubs.logged() == "python3 report\npython3 exec\n"


def test_launcher_does_not_use_a_python3_that_reports_3_9(stubs, run_bw):
    stubs.python(stubs.bin, "python3", "old")
    assert run_bw("drift", env=stubs.env()) == (1, b"", NEEDS + b"\n")
    assert stubs.logged() == "python3 report\n"


# --- without Python 3.11 or newer --------------------------------------------


@pytest.mark.parametrize("argv", CLASS_A, ids=" ".join)
@pytest.mark.parametrize("setup", SETUPS)
def test_launcher_without_python_3_11_exits_1_with_one_stderr_line_for_each_class_a_command(
    setup, argv, stubs, run_bw, project
):
    assert run_bw(*argv, env=stubs.without_python(setup)) == (1, b"", NEEDS + b"\n")
    assert stubs.logged() == ASKED[setup]
    assert list(project.iterdir()) == [], "a class-A command wrote into the project without Python"


@pytest.mark.parametrize("name", CLASS_B)
@pytest.mark.parametrize("setup", SETUPS)
def test_launcher_without_python_3_11_exits_2_with_a_json_error_for_each_class_b_command(setup, name, stubs, run_bw):
    got = run_bw(name, "some-arg", env=stubs.without_python(setup))
    assert got == (2, b"", b'{"error":"' + NEEDS + b'"}\n')
    assert json.loads(got.stderr) == {"error": NEEDS.decode()}
    assert stubs.logged() == ASKED[setup]


@pytest.mark.parametrize("setup", SETUPS)
def test_launcher_without_python_3_11_still_writes_the_precompact_sentinel(setup, stubs, run_bw, project):
    env = stubs.without_python(setup)
    state = project / ".bytewyrd"
    assert run_bw("state-touch", "precompact-extraction-done", env=env) == (0, b"", b"")
    assert (state / "precompact-extraction-done").is_file()
    # Plain sh writes no .gitignore; repos still on 0.2.x have the seeded one.
    assert os.listdir(state) == ["precompact-extraction-done"]
    # Again, now that .bytewyrd and the sentinel exist.
    assert run_bw("state-touch", "precompact-extraction-done", env=env) == (0, b"", b"")
    assert os.listdir(state) == ["precompact-extraction-done"]


@pytest.mark.parametrize("target", ["directory", "dangling"])
@pytest.mark.parametrize("setup", SETUPS)
def test_launcher_without_python_3_11_refuses_to_write_the_sentinel_through_a_symlinked_bytewyrd(
    setup, target, stubs, run_bw, project, outside
):
    os.symlink(outside if target == "directory" else outside / "dangling", project / ".bytewyrd")
    got = run_bw("state-touch", "precompact-extraction-done", env=stubs.without_python(setup))
    assert got == (0, b"", b"state-touch: .bytewyrd is a symlink; refusing to write through it\n")
    assert os.listdir(outside) == []


@pytest.mark.parametrize("target", ["victim", "new"])
@pytest.mark.parametrize("setup", SETUPS)
def test_launcher_without_python_3_11_refuses_to_write_the_sentinel_through_a_symlink(
    setup, target, stubs, run_bw, project, outside
):
    (project / ".bytewyrd").mkdir()
    (outside / "victim").write_bytes(b"keep\n")
    os.symlink(outside / target, project / ".bytewyrd" / "precompact-extraction-done")
    got = run_bw("state-touch", "precompact-extraction-done", env=stubs.without_python(setup))
    message = b"state-touch: .bytewyrd/precompact-extraction-done is a symlink; refusing to write through it\n"
    assert got == (0, b"", message)
    assert (outside / "victim").read_bytes() == b"keep\n"
    assert os.listdir(outside) == ["victim"]


# --- NAME checks -------------------------------------------------------------

UNKNOWN_NAMES = [
    pytest.param("nope", id="nope"),
    pytest.param("../x", id="parent-path"),
    pytest.param("main", id="main"),
    pytest.param("__main__", id="dunder-main"),
    # bats' $stderr loses trailing blanks, so it could only test 'scaffold x' for 'scaffold '; both run here.
    pytest.param("scaffold x", id="scaffold-x"),
    pytest.param("scaffold ", id="scaffold-trailing-space"),
    pytest.param("Drift", id="drift-capitalized"),
    pytest.param("rfc-legacy-detect", id="rfc-legacy-detect"),
    pytest.param("", id="empty"),
]


@pytest.mark.parametrize("name", UNKNOWN_NAMES)
def test_launcher_rejects_an_unknown_name_before_any_interpreter_starts(name, stubs, run_bw):
    stubs.python(stubs.bin, "python3.15", "new")
    assert run_bw(name, env=stubs.env()) == (1, b"", b"bw: unknown command: " + name.encode() + b"\n")
    assert stubs.logged() == ""


def test_launcher_without_a_name_prints_the_usage_line_and_exits_1(stubs, run_bw):
    stubs.python(stubs.bin, "python3.15", "new")
    assert run_bw(env=stubs.env()) == (1, b"", b"bw: usage: bw NAME [ARGS...]\n")
    assert stubs.logged() == ""


# --- -I -S -B ----------------------------------------------------------------


def test_launcher_with_a_venv_interpreter_runs_no_pth_file_and_writes_no_pycache(tmp_path, run_child, run_bw, bw_env):
    venv = tmp_path / "venv"
    assert run_child([sys.executable, "-m", "venv", "--without-pip", venv]).returncode == 0
    venv_py = venv / "bin" / "python"
    got = run_child([venv_py, "-c", 'import sysconfig; print(sysconfig.get_paths()["purelib"])'])
    assert got.returncode == 0
    site = Path(os.fsdecode(got.stdout.rstrip(b"\n")))
    marker = tmp_path / "pth-ran"
    (site / "bw-marker.pth").write_text('import os; open("%s", "w").close()\n' % marker)
    # The marker works: a plain start of the venv's interpreter runs the .pth.
    assert run_child([venv_py, "-c", "pass"]).returncode == 0
    assert marker.is_file()
    marker.unlink()

    # Run a copy of the scripts, without __pycache__/, so bytecode that pytest wrote into the real
    # scripts/bytewyrd can't hide a new one.
    package = REPO / "scripts" / "bytewyrd"
    scripts = tmp_path / "plugin" / "scripts"
    (scripts / "bytewyrd" / "commands").mkdir(parents=True)
    shutil.copy(BW, scripts / "bw")
    for pattern in ("*.py", "commands/*.py"):
        for source in package.glob(pattern):
            shutil.copy(source, scripts / "bytewyrd" / source.relative_to(package))
    env = {**bw_env, "BYTEWYRD_PYTHON": str(venv_py)}
    launcher = scripts / "bw"
    assert run_bw("state-touch", "last-feature-engineer-stop", env=env, launcher=launcher) == (0, b"", b"")
    got = run_bw("compact-reminder", env=env, launcher=launcher)
    assert (got.returncode, got.stderr) == (0, b"")
    assert b"Ask the user to run /docs-review" in got.stdout
    assert not marker.exists()
    assert list((tmp_path / "plugin").rglob("__pycache__")) == []


# --- the launcher and the helpers --------------------------------------------


@pytest.mark.parametrize("name", CLASS_B)
def test_launcher_runs_each_class_b_name_as_the_bootstrap_does(name, tmp_path, project, run_bw, run_child, bw_env):
    # The helpers' own behaviour is pinned in test_json_helpers.py, in this process and through the
    # bootstrap; this keeps the launcher-to-helper path covered, for every NAME it lets through.
    (project / "docs" / "rfcs").mkdir(parents=True)
    # rfc-resolve runs git, which must not find a repository above the temporary directory.
    env = {
        **bw_env,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CEILING_DIRECTORIES": str(tmp_path.parent),
    }
    launched = run_bw(name, env=env)
    direct = run_child([sys.executable, "-I", "-S", "-B", MAIN, name], env=env)
    assert launched == direct
    # Both could fail the same way; a helper that ran has written to a stream and not crashed.
    assert launched.stdout or launched.stderr
    assert b"Traceback" not in launched.stderr
