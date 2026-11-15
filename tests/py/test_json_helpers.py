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
import bw_rfc_braindump_list  # noqa: E402
import bw_rfc_braindump_remove  # noqa: E402
import bw_rfc_feedback_list  # noqa: E402
import bw_rfc_frontmatter  # noqa: E402

BRAINDUMP = Path("docs/rfc-braindump.md")
IS_ROOT = hasattr(os, "geteuid") and os.geteuid() == 0


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


# --- rfc-braindump-list ------------------------------------------------------

NO_ENTRIES = b'{\n  "entries": []\n}\n'


def bodies(out):
    return [e["body"] for e in json.loads(out)["entries"]]


def test_list_prints_the_bullets_as_jq_did(call):
    BRAINDUMP.write_bytes(b"# RFC Braindump\n\nIdeas.\n\n* Alpha idea.\n* Beta idea.\n")
    want = (
        b'{\n  "entries": [\n    {\n      "n": 1,\n      "body": "Alpha idea."\n    },\n'
        b'    {\n      "n": 2,\n      "body": "Beta idea."\n    }\n  ]\n}\n'
    )
    assert call(bw_rfc_braindump_list) == (0, want, b"")


def test_list_without_a_regular_file_is_empty(call):
    assert call(bw_rfc_braindump_list) == (0, NO_ENTRIES, b"")
    BRAINDUMP.mkdir()
    assert call(bw_rfc_braindump_list) == (0, NO_ENTRIES, b"")


def test_list_reads_lines_as_the_bash_read_loop_did(call):
    # Kept from the bash script: a last line without a newline is not read,
    # NUL bytes are dropped, and only "* " starts a bullet.
    BRAINDUMP.write_bytes(b"* a\n*\tb\n* c\r\n* d\0e\n\0* f\n*  g\n* \n**h\n * i\n* last")
    code, out, err = call(bw_rfc_braindump_list)
    assert (code, err) == (0, b"")
    assert bodies(out) == ["a", "c\r", "de", "f", " g", ""]


def test_list_replaces_what_isn_t_utf_8_with_u_fffd(call):
    BRAINDUMP.write_bytes(b"* caf\xe9\n* x\xffy\n* caf\xc3\xa9\n")
    code, out, _ = call(bw_rfc_braindump_list)
    assert (code, bodies(out)) == (0, ["caf\ufffd", "x\ufffdy", "caf\xe9"])


@pytest.mark.skipif(IS_ROOT, reason="root reads any file")
def test_list_of_an_unreadable_file_is_empty_with_one_stderr_line(call):
    BRAINDUMP.write_bytes(b"* a\n")
    BRAINDUMP.chmod(0)
    message = b"rfc-braindump-list: Permission denied: docs/rfc-braindump.md\n"
    assert call(bw_rfc_braindump_list) == (0, NO_ENTRIES, message)


# --- rfc-braindump-remove ----------------------------------------------------


def removed(flag):
    return b'{\n  "removed": %s,\n  "file": "docs/rfc-braindump.md"\n}\n' % (b"true" if flag else b"false")


def test_remove_takes_out_the_first_match_only(call):
    BRAINDUMP.write_bytes(b"# H\n\n* Duplicate.\n* Unique.\n* Duplicate.\n")
    assert call(bw_rfc_braindump_remove, "Duplicate.") == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"# H\n\n* Unique.\n* Duplicate.\n"


def test_remove_without_a_match_leaves_the_file_alone(call):
    BRAINDUMP.write_bytes(b"* a \n* b")
    for body in ("c", "a", " b"):
        assert call(bw_rfc_braindump_remove, body) == (1, removed(False), b"")
    assert BRAINDUMP.read_bytes() == b"* a \n* b"


def test_remove_reads_lines_as_awk_did(call):
    # Kept from the bash script: a last line without a newline matches, and
    # the rewritten file ends every line with one.
    BRAINDUMP.write_bytes(b"\n* a\n\n* last")
    assert call(bw_rfc_braindump_remove, "last") == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"\n* a\n\n"


@pytest.mark.parametrize("body", ["C:\\temp\\x", "a\\nb", "back\\\\slash", "end\\"])
def test_remove_matches_a_body_with_backslashes_as_given(call, body):
    # The bash script's awk -v undid these escapes first, so it never matched.
    BRAINDUMP.write_bytes(b"* " + body.encode() + b"\n* other\n")
    assert call(bw_rfc_braindump_remove, body) == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"* other\n"


def test_remove_matches_the_bytes_of_a_body_that_isn_t_utf_8():
    BRAINDUMP.write_bytes(b"* caf\xc3\xa9\n* caf\xe9\n")
    proc = bw_run("rfc-braindump-remove", b"caf\xe9")
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"* caf\xc3\xa9\n"


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: rfc-braindump-remove.sh <full-bullet-body-without-leading-star-space>"),
        ([""], "usage: rfc-braindump-remove.sh <full-bullet-body-without-leading-star-space>"),
        (["x"], "rfc-braindump-remove: docs/rfc-braindump.md not found"),
    ],
)
def test_remove_errors(call, argv, message):
    assert call(bw_rfc_braindump_remove, *argv) == (2, error(message), b"")


@pytest.mark.skipif(IS_ROOT, reason="root writes any file")
def test_remove_reports_a_failed_write_as_a_json_error(call):
    # The bash script printed "removed": true and exited 0 here.
    BRAINDUMP.write_bytes(b"* a\n")
    BRAINDUMP.chmod(0o444)
    message = "rfc-braindump-remove: Permission denied: docs/rfc-braindump.md"
    assert call(bw_rfc_braindump_remove, "a") == (2, error(message), b"")
    assert BRAINDUMP.read_bytes() == b"* a\n"


# --- rfc-feedback-list -------------------------------------------------------

NO_MARKERS = b'{\n  "markers": []\n}\n'


def test_feedback_list_prints_the_markers_as_jq_did(call):
    Path("f.md").write_bytes(b"## A\n\nFEEDBACK: First.\n- FEEDBACK: Second.\n")
    want = (
        b'{\n  "markers": [\n    {\n      "line": 3,\n      "text": "FEEDBACK: First."\n    },\n'
        b'    {\n      "line": 4,\n      "text": "- FEEDBACK: Second."\n    }\n  ]\n}\n'
    )
    assert call(bw_rfc_feedback_list, "f.md") == (0, want, b"")


@pytest.mark.parametrize(
    "line, text",
    [
        (b"FEEDBACK: x", "FEEDBACK: x"),
        (b"  - FEEDBACK: nested", "  - FEEDBACK: nested"),
        (b"> FEEDBACK: quoted", "> FEEDBACK: quoted"),
        (b"--*> FEEDBACK: any run of - * >", "--*> FEEDBACK: any run of - * >"),
        (b" \x0b\x0c\r* FEEDBACK: ASCII whitespace", " \x0b\x0c\r* FEEDBACK: ASCII whitespace"),
        (b"FEEDBACK:", "FEEDBACK:"),
        (b"FEEDBACK: crlf\r", "FEEDBACK: crlf\r"),
        # Kept from the bash script: the text ends at the first tab, so a
        # tab-indented marker's text is "".
        (b"FEEDBACK: a\tb", "FEEDBACK: a"),
        (b"\tFEEDBACK: tab-indented", ""),
    ],
)
def test_feedback_list_finds(call, line, text):
    Path("f.md").write_bytes(b"x\n" + line + b"\ny\n")
    code, out, err = call(bw_rfc_feedback_list, "f.md")
    assert (code, json.loads(out), err) == (0, {"markers": [{"line": 2, "text": text}]}, b"")


@pytest.mark.parametrize(
    "line",
    [b"> - FEEDBACK: no", b"* *FEEDBACK: no", b"xFEEDBACK: no", b"NOTE: FEEDBACK: no", b"feedback: no", b"\xc2\xa0FEEDBACK: no"],
)
def test_feedback_list_ignores(call, line):
    Path("f.md").write_bytes(line + b"\n")
    assert call(bw_rfc_feedback_list, "f.md") == (0, NO_MARKERS, b"")


def test_feedback_list_counts_a_last_line_without_a_newline(call):
    Path("f.md").write_bytes(b"a\nFEEDBACK: last")
    code, out, _ = call(bw_rfc_feedback_list, "f.md")
    assert json.loads(out) == {"markers": [{"line": 2, "text": "FEEDBACK: last"}]}


def test_feedback_list_decodes_each_line_on_its_own(call):
    # U+FFFD for what isn't UTF-8, and the next marker stays its own: in the
    # C locale, jq -R -s let "caf\xe9\n" swallow the newline and merged them.
    Path("f.md").write_bytes(b"FEEDBACK: caf\xe9\nFEEDBACK: ok\n")
    code, out, _ = call(bw_rfc_feedback_list, "f.md")
    want = {"markers": [{"line": 1, "text": "FEEDBACK: caf\ufffd"}, {"line": 2, "text": "FEEDBACK: ok"}]}
    assert (code, json.loads(out)) == (0, want)


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: rfc-feedback-list.sh <path-to-rfc.md>"),
        ([""], "usage: rfc-feedback-list.sh <path-to-rfc.md>"),
        (["missing.md"], "rfc-feedback-list: file not found: missing.md"),
        (["docs"], "rfc-feedback-list: file not found: docs"),
    ],
)
def test_feedback_list_errors(call, argv, message):
    assert call(bw_rfc_feedback_list, *argv) == (2, error(message), b"")


def test_feedback_list_names_a_path_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-feedback-list", b"caf\xe9.md")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "rfc-feedback-list: file not found: caf\ufffd.md"},
        b"",
    )


# --- rfc-frontmatter ---------------------------------------------------------


def test_frontmatter_prints_the_six_fields_as_jq_did(call):
    Path("x.md").write_text('---\nrfc: "a"\ntitle: "T \\"q\\""\nauthor: A\nstatus: Draft\ncreated: 2026-01-01\ndrop_reason: ~\n---\n')
    want = (
        b'{\n  "rfc": "a",\n  "title": "T \\"q\\"",\n  "author": "A",\n  "status": "Draft",\n'
        b'  "created": "2026-01-01",\n  "drop_reason": ""\n}\n'
    )
    assert call(bw_rfc_frontmatter, "x.md") == (0, want, b"")


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: rfc-frontmatter.sh <path-to-rfc.md>"),
        ([""], "usage: rfc-frontmatter.sh <path-to-rfc.md>"),
        (["missing.md"], "rfc-frontmatter: file not found: missing.md"),
        (["docs"], "rfc-frontmatter: file not found: docs"),
    ],
)
def test_frontmatter_errors(call, argv, message):
    assert call(bw_rfc_frontmatter, *argv) == (2, error(message), b"")


@pytest.mark.parametrize(
    "text, message",
    [
        ("# none\n", "x.md does not begin with a YAML frontmatter delimiter"),
        ("---\ntitle: RFC: x\n---\n", "x.md:2: frontmatter is not valid YAML (mapping values are not allowed here)"),
        ("---\ntitle: [a]\n---\n", "x.md: title is a list, not a string"),
    ],
)
def test_frontmatter_prints_load_frontmatter_s_error(call, text, message):
    Path("x.md").write_text(text)
    assert call(bw_rfc_frontmatter, "x.md") == (2, error("rfc-frontmatter: " + message), b"")


@pytest.mark.parametrize("value", ["!!int abc", "!!bool maybe", "!!timestamp nope", '"\\U00110000"'])
def test_frontmatter_prints_a_json_error_for_what_the_loader_can_t_build(call, value):
    # load_frontmatter() lets these out as ValueError, KeyError or
    # AttributeError, not BwError; json_main() still makes them an error object.
    Path("x.md").write_text("---\ncreated: %s\n---\n" % value)
    code, out, err = call(bw_rfc_frontmatter, "x.md")
    assert (code, err) == (2, b"")
    assert json.loads(out)["error"].startswith("rfc-frontmatter: ")


def test_frontmatter_prints_a_lone_surrogate_escape_as_u_fffd(call):
    Path("x.md").write_text('---\ntitle: "a\\ud800b"\n---\n')
    code, out, _ = call(bw_rfc_frontmatter, "x.md")
    assert (code, json.loads(out)["title"]) == (0, "a\ufffdb")


def test_frontmatter_names_a_path_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-frontmatter", b"caf\xe9.md")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "rfc-frontmatter: file not found: caf\ufffd.md"},
        b"",
    )
