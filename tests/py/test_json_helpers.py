"""Tests for the JSON helpers' Python ports (RFC 2026-11-09-scaffold-and-drift,
B2 "Ports"). Each helper's bats file, tests/scripts/<name>.bats, pins its
arguments, output and exit codes; the cases here pin what bats doesn't: the
exact bytes jq printed, arguments, paths and files that aren't UTF-8, the bash
behaviour each port keeps, and failures that end in a JSON error rather than
a traceback.

Most cases run a helper's main() in this process; those that need real
argument bytes run it the way scripts/bw does, through bw_main.py.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "scripts" / "_lib"
VENDOR = REPO / "scripts" / "_vendor"
sys.path[0:0] = [str(LIB), str(VENDOR)]

import bw  # noqa: E402
import bw_rfc_braindump_append  # noqa: E402

BRAINDUMP = Path("docs/rfc-braindump.md")


@pytest.fixture(autouse=True)
def in_tmp(tmp_path, monkeypatch):
    """Run in TMP_PATH, which holds docs/rfcs/ as the bats fixtures' does."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / "docs" / "rfcs").mkdir(parents=True)


@pytest.fixture
def call(capsysbinary):
    """call(MODULE, *ARGV): MODULE.main(ARGV) in this process, as (exit code,
    stdout bytes, stderr bytes)."""

    def call(module, *argv):
        code = module.main(list(argv))
        out, err = capsysbinary.readouterr()
        return code, out, err

    return call


def bw_run(name, *argv, env=None):
    """Run the helper NAME as scripts/bw runs it, with ARGV as given (bytes
    included), in the current directory."""
    cmd = [sys.executable, "-I", "-S", "-B", str(LIB / "bw_main.py"), name, *argv]
    return subprocess.run(cmd, capture_output=True, env=env)


def escaped(raw):
    """RAW as os.fsdecode() holds bytes that aren't UTF-8, in any locale."""
    return raw.decode("utf-8", "surrogateescape")


def error(message):
    return ('{\n  "error": %s\n}\n' % json.dumps(message, ensure_ascii=False)).encode()


# --- rfc-braindump-append ----------------------------------------------------

HEADER = b"# RFC Braindump\n\nPotential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.\n\n"


def appended(created):
    return b'{\n  "appended": true,\n  "file": "docs/rfc-braindump.md",\n  "created_file": %s\n}\n' % (
        b"true" if created else b"false"
    )


def test_append_creates_the_file_with_its_header(call):
    assert call(bw_rfc_braindump_append, "First entry.") == (0, appended(True), b"")
    assert call(bw_rfc_braindump_append, "Second.") == (0, appended(False), b"")
    assert BRAINDUMP.read_bytes() == HEADER + b"* First entry.\n* Second.\n"


def test_append_adds_no_newline_before_the_bullet(call):
    # Kept from the bash script: a last line without a newline gets the bullet.
    BRAINDUMP.write_bytes(b"# H\n\n* x")
    assert call(bw_rfc_braindump_append, "y") == (0, appended(False), b"")
    assert BRAINDUMP.read_bytes() == b"# H\n\n* x* y\n"


def test_append_writes_the_body_s_bytes_as_given():
    proc = bw_run("rfc-braindump-append", b"caf\xe9 \\ %s -- \t")
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, appended(True), b"")
    assert BRAINDUMP.read_bytes() == HEADER + b"* caf\xe9 \\ %s -- \t\n"


def test_append_through_a_dangling_symlink_creates_its_target(call):
    BRAINDUMP.symlink_to("../made.md")
    assert call(bw_rfc_braindump_append, "x") == (0, appended(True), b"")
    assert Path("made.md").read_bytes() == HEADER + b"* x\n"


@pytest.mark.parametrize("argv", [[], [""]])
def test_append_without_a_body_is_a_usage_error(call, argv):
    usage = "usage: rfc-braindump-append.sh <full-bullet-body-without-leading-star-space>"
    assert call(bw_rfc_braindump_append, *argv) == (2, error(usage), b"")
    assert not BRAINDUMP.exists()


def test_append_reports_a_failed_write_as_a_json_error(call):
    # The bash script printed "appended": true and exited 0 here.
    shutil.rmtree("docs")
    message = "rfc-braindump-append: No such file or directory: docs/rfc-braindump.md"
    assert call(bw_rfc_braindump_append, "x") == (2, error(message), b"")
