"""Tests for the JSON helpers' Python ports (RFC 2026-11-09-scaffold-and-drift,
B2 "Ports"): each helper's arguments, output and exit codes, down to the exact
bytes jq printed; arguments, paths and files that aren't UTF-8; the bash
behaviour each port keeps; and failures that end in a JSON error rather than a
traceback.

Most cases run a helper's main() in this process; those that need real
argument bytes run it the way scripts/bw does, through the bootstrap,
scripts/bytewyrd/__main__.py. test_launcher.py runs each helper through
scripts/bw itself.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from bytewyrd import jsonout
from bytewyrd.commands import (
    rfc_braindump_append,
    rfc_braindump_list,
    rfc_braindump_remove,
    rfc_feedback_list,
    rfc_frontmatter,
    rfc_resolve,
    rfc_set_status,
    rfc_summary,
    tool_probe,
)

REPO = Path(__file__).resolve().parents[2]
MAIN = REPO / "scripts" / "bytewyrd" / "__main__.py"

BRAINDUMP = Path("docs/rfc-braindump.md")
IS_ROOT = hasattr(os, "geteuid") and os.geteuid() == 0


@pytest.fixture(autouse=True)
def in_tmp(tmp_path, monkeypatch):
    """Run in TMP_PATH, which holds an empty docs/rfcs/, as a project root does."""
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
    cmd = [sys.executable, "-I", "-S", "-B", str(MAIN), name, *argv]
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
    assert call(rfc_braindump_append, "First entry.") == (0, appended(True), b"")
    assert call(rfc_braindump_append, "Second.") == (0, appended(False), b"")
    assert BRAINDUMP.read_bytes() == HEADER + b"* First entry.\n* Second.\n"


def test_append_adds_no_newline_before_the_bullet(call):
    # Kept from the bash script: a last line without a newline gets the bullet.
    BRAINDUMP.write_bytes(b"# H\n\n* x")
    assert call(rfc_braindump_append, "y") == (0, appended(False), b"")
    assert BRAINDUMP.read_bytes() == b"# H\n\n* x* y\n"


def test_append_writes_the_body_s_bytes_as_given():
    proc = bw_run("rfc-braindump-append", b"caf\xe9 \\ %s -- \t")
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, appended(True), b"")
    assert BRAINDUMP.read_bytes() == HEADER + b"* caf\xe9 \\ %s -- \t\n"


def test_append_through_a_dangling_symlink_creates_its_target(call):
    BRAINDUMP.symlink_to("../made.md")
    assert call(rfc_braindump_append, "x") == (0, appended(True), b"")
    assert Path("made.md").read_bytes() == HEADER + b"* x\n"


@pytest.mark.parametrize("argv", [[], [""]])
def test_append_without_a_body_is_a_usage_error(call, argv):
    usage = "usage: bw rfc-braindump-append <full-bullet-body-without-leading-star-space>"
    assert call(rfc_braindump_append, *argv) == (2, error(usage), b"")
    assert not BRAINDUMP.exists()


def test_append_reports_a_failed_write_as_a_json_error(call):
    # The bash script printed "appended": true and exited 0 here.
    shutil.rmtree("docs")
    message = "rfc-braindump-append: No such file or directory: docs/rfc-braindump.md"
    assert call(rfc_braindump_append, "x") == (2, error(message), b"")


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
    assert call(rfc_braindump_list) == (0, want, b"")


def test_list_without_a_regular_file_is_empty(call):
    assert call(rfc_braindump_list) == (0, NO_ENTRIES, b"")
    BRAINDUMP.mkdir()
    assert call(rfc_braindump_list) == (0, NO_ENTRIES, b"")


def test_list_of_a_file_without_bullets_is_empty(call):
    BRAINDUMP.write_bytes(b"# RFC Braindump\n\nNo ideas yet.\n")
    assert call(rfc_braindump_list) == (0, NO_ENTRIES, b"")


def test_list_reads_lines_as_the_bash_read_loop_did(call):
    # Kept from the bash script: a last line without a newline is not read,
    # NUL bytes are dropped, and only "* " starts a bullet.
    BRAINDUMP.write_bytes(b"* a\n*\tb\n* c\r\n* d\0e\n\0* f\n*  g\n* \n**h\n * i\n* last")
    code, out, err = call(rfc_braindump_list)
    assert (code, err) == (0, b"")
    assert bodies(out) == ["a", "c\r", "de", "f", " g", ""]


def test_list_replaces_what_isn_t_utf_8_with_u_fffd(call):
    BRAINDUMP.write_bytes(b"* caf\xe9\n* x\xffy\n* caf\xc3\xa9\n")
    code, out, _ = call(rfc_braindump_list)
    assert (code, bodies(out)) == (0, ["caf\ufffd", "x\ufffdy", "caf\xe9"])


@pytest.mark.skipif(IS_ROOT, reason="root reads any file")
def test_list_of_an_unreadable_file_is_empty_with_one_stderr_line(call):
    BRAINDUMP.write_bytes(b"* a\n")
    BRAINDUMP.chmod(0)
    message = b"rfc-braindump-list: Permission denied: docs/rfc-braindump.md\n"
    assert call(rfc_braindump_list) == (0, NO_ENTRIES, message)


# --- rfc-braindump-remove ----------------------------------------------------


def removed(flag):
    return b'{\n  "removed": %s,\n  "file": "docs/rfc-braindump.md"\n}\n' % (b"true" if flag else b"false")


def test_remove_takes_out_the_first_match_only(call):
    BRAINDUMP.write_bytes(b"# H\n\n* Duplicate.\n* Unique.\n* Duplicate.\n")
    assert call(rfc_braindump_remove, "Duplicate.") == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"# H\n\n* Unique.\n* Duplicate.\n"


def test_remove_without_a_match_leaves_the_file_alone(call):
    BRAINDUMP.write_bytes(b"* a \n* b")
    for body in ("c", "a", " b"):
        assert call(rfc_braindump_remove, body) == (1, removed(False), b"")
    assert BRAINDUMP.read_bytes() == b"* a \n* b"


def test_remove_reads_lines_as_awk_did(call):
    # Kept from the bash script: a last line without a newline matches, and
    # the rewritten file ends every line with one.
    BRAINDUMP.write_bytes(b"\n* a\n\n* last")
    assert call(rfc_braindump_remove, "last") == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"\n* a\n\n"


@pytest.mark.parametrize("body", ["C:\\temp\\x", "a\\nb", "back\\\\slash", "end\\"])
def test_remove_matches_a_body_with_backslashes_as_given(call, body):
    # The bash script's awk -v undid these escapes first, so it never matched.
    BRAINDUMP.write_bytes(b"* " + body.encode() + b"\n* other\n")
    assert call(rfc_braindump_remove, body) == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"* other\n"


def test_remove_matches_the_bytes_of_a_body_that_isn_t_utf_8():
    BRAINDUMP.write_bytes(b"* caf\xc3\xa9\n* caf\xe9\n")
    proc = bw_run("rfc-braindump-remove", b"caf\xe9")
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, removed(True), b"")
    assert BRAINDUMP.read_bytes() == b"* caf\xc3\xa9\n"


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: bw rfc-braindump-remove <full-bullet-body-without-leading-star-space>"),
        ([""], "usage: bw rfc-braindump-remove <full-bullet-body-without-leading-star-space>"),
        (["x"], "rfc-braindump-remove: docs/rfc-braindump.md not found"),
    ],
)
def test_remove_errors(call, argv, message):
    assert call(rfc_braindump_remove, *argv) == (2, error(message), b"")


@pytest.mark.skipif(IS_ROOT, reason="root writes any file")
def test_remove_reports_a_failed_write_as_a_json_error(call):
    # The bash script printed "removed": true and exited 0 here.
    BRAINDUMP.write_bytes(b"* a\n")
    BRAINDUMP.chmod(0o444)
    message = "rfc-braindump-remove: Permission denied: docs/rfc-braindump.md"
    assert call(rfc_braindump_remove, "a") == (2, error(message), b"")
    assert BRAINDUMP.read_bytes() == b"* a\n"


# --- rfc-feedback-list -------------------------------------------------------

NO_MARKERS = b'{\n  "markers": []\n}\n'


def test_feedback_list_prints_the_markers_as_jq_did(call):
    Path("f.md").write_bytes(b"## A\n\nFEEDBACK: First.\n- FEEDBACK: Second.\n")
    want = (
        b'{\n  "markers": [\n    {\n      "line": 3,\n      "text": "FEEDBACK: First."\n    },\n'
        b'    {\n      "line": 4,\n      "text": "- FEEDBACK: Second."\n    }\n  ]\n}\n'
    )
    assert call(rfc_feedback_list, "f.md") == (0, want, b"")


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
    code, out, err = call(rfc_feedback_list, "f.md")
    assert (code, json.loads(out), err) == (0, {"markers": [{"line": 2, "text": text}]}, b"")


@pytest.mark.parametrize(
    "line",
    [
        b"> - FEEDBACK: no",
        b"* *FEEDBACK: no",
        b"xFEEDBACK: no",
        b"NOTE: FEEDBACK: no",
        b"feedback: no",
        b"\xc2\xa0FEEDBACK: no",
    ],
)
def test_feedback_list_ignores(call, line):
    Path("f.md").write_bytes(line + b"\n")
    assert call(rfc_feedback_list, "f.md") == (0, NO_MARKERS, b"")


def test_feedback_list_counts_a_last_line_without_a_newline(call):
    Path("f.md").write_bytes(b"a\nFEEDBACK: last")
    code, out, _ = call(rfc_feedback_list, "f.md")
    assert json.loads(out) == {"markers": [{"line": 2, "text": "FEEDBACK: last"}]}


def test_feedback_list_decodes_each_line_on_its_own(call):
    # U+FFFD for what isn't UTF-8, and the next marker stays its own: in the
    # C locale, jq -R -s let "caf\xe9\n" swallow the newline and merged them.
    Path("f.md").write_bytes(b"FEEDBACK: caf\xe9\nFEEDBACK: ok\n")
    code, out, _ = call(rfc_feedback_list, "f.md")
    want = {"markers": [{"line": 1, "text": "FEEDBACK: caf\ufffd"}, {"line": 2, "text": "FEEDBACK: ok"}]}
    assert (code, json.loads(out)) == (0, want)


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: bw rfc-feedback-list <path-to-rfc.md>"),
        ([""], "usage: bw rfc-feedback-list <path-to-rfc.md>"),
        (["missing.md"], "rfc-feedback-list: file not found: missing.md"),
        (["docs"], "rfc-feedback-list: file not found: docs"),
    ],
)
def test_feedback_list_errors(call, argv, message):
    assert call(rfc_feedback_list, *argv) == (2, error(message), b"")


def test_feedback_list_names_a_path_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-feedback-list", b"caf\xe9.md")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "rfc-feedback-list: file not found: caf\ufffd.md"},
        b"",
    )


# --- rfc-frontmatter ---------------------------------------------------------


def test_frontmatter_prints_the_six_fields_as_jq_did(call):
    Path("x.md").write_text(
        '---\nrfc: "a"\ntitle: "T \\"q\\""\nauthor: A\nstatus: Draft\ncreated: 2026-01-01\ndrop_reason: ~\n---\n'
    )
    want = (
        b'{\n  "rfc": "a",\n  "title": "T \\"q\\"",\n  "author": "A",\n  "status": "Draft",\n'
        b'  "created": "2026-01-01",\n  "drop_reason": ""\n}\n'
    )
    assert call(rfc_frontmatter, "x.md") == (0, want, b"")


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: bw rfc-frontmatter <path-to-rfc.md>"),
        ([""], "usage: bw rfc-frontmatter <path-to-rfc.md>"),
        (["missing.md"], "rfc-frontmatter: file not found: missing.md"),
        (["docs"], "rfc-frontmatter: file not found: docs"),
    ],
)
def test_frontmatter_errors(call, argv, message):
    assert call(rfc_frontmatter, *argv) == (2, error(message), b"")


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
    assert call(rfc_frontmatter, "x.md") == (2, error("rfc-frontmatter: " + message), b"")


@pytest.mark.parametrize("value", ["!!int abc", "!!bool maybe", "!!timestamp nope", '"\\U00110000"'])
def test_frontmatter_prints_a_json_error_for_what_the_loader_can_t_build(call, value):
    # load_frontmatter() reports each as invalid YAML; test_frontmatter.py
    # pins the messages.
    Path("x.md").write_text("---\ncreated: %s\n---\n" % value)
    code, out, err = call(rfc_frontmatter, "x.md")
    assert (code, err) == (2, b"")
    assert json.loads(out)["error"].startswith("rfc-frontmatter: x.md:2: frontmatter is not valid YAML (")


def test_frontmatter_prints_a_lone_surrogate_escape_as_u_fffd(call):
    Path("x.md").write_text('---\ntitle: "a\\ud800b"\n---\n')
    code, out, _ = call(rfc_frontmatter, "x.md")
    assert (code, json.loads(out)["title"]) == (0, "a\ufffdb")


def test_frontmatter_names_a_path_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-frontmatter", b"caf\xe9.md")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "rfc-frontmatter: file not found: caf\ufffd.md"},
        b"",
    )


# --- rfc-resolve -------------------------------------------------------------


def run_git(*args):
    subprocess.run(["git", *args], check=True, capture_output=True)


@pytest.fixture
def hermetic_git(tmp_path, monkeypatch):
    """Keep the developer's git configuration and any enclosing repository out."""
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path.parent))
    for var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        monkeypatch.delenv(var, raising=False)


@pytest.fixture
def repo(hermetic_git):
    """A git repository here with three RFCs committed."""
    run_git("init", "-q")
    for name in ("2026-01-01-alpha", "2026-02-01-beta", "2026-03-01-gamma"):
        Path("docs/rfcs/%s.md" % name).write_text("---\nrfc: %s\n---\n" % name)
    run_git("add", "-A")
    run_git("-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "x")


def label(out):
    return json.loads(out)["label"]


def test_resolve_an_identifier_as_jq_did(call, repo):
    path = os.path.join(os.getcwd(), "docs/rfcs/2026-01-01-alpha.md")
    want = ('{\n  "path": "%s",\n  "label": "RFC 2026-01-01-alpha (matched argument)"\n}\n' % path).encode()
    for arg in ("2026-01-01-alpha", "2026-01-01-alpha.md", "docs/rfcs/2026-01-01-alpha.md"):
        assert call(rfc_resolve, arg) == (0, want, b"")


def test_resolve_takes_the_directory_from_pwd_as_bash_did(call, repo, tmp_path, monkeypatch):
    link = tmp_path / "via-link"
    link.symlink_to(tmp_path)
    monkeypatch.chdir(link)
    monkeypatch.setenv("PWD", str(link))
    code, out, _ = call(rfc_resolve, "2026-01-01-alpha")
    assert (code, json.loads(out)["path"]) == (0, str(link) + "/docs/rfcs/2026-01-01-alpha.md")


@pytest.mark.parametrize(
    "arg, code, message",
    [
        ("does-not-exist", 1, "rfc-resolve: no RFC found at docs/rfcs/does-not-exist.md"),
        ("2026-01-01-alpha.md.md", 1, "rfc-resolve: no RFC found at docs/rfcs/2026-01-01-alpha.md.md"),
        ("foo/bar", 2, "rfc-resolve: identifier must not contain '/' (got: foo/bar)"),
        ("docs/rfcs/a/b.md", 2, "rfc-resolve: identifier must not contain '/' (got: docs/rfcs/a/b.md)"),
    ],
)
def test_resolve_errors(call, repo, arg, code, message):
    assert call(rfc_resolve, arg) == (code, error(message), b"")


def test_resolve_without_docs_rfcs_is_an_error_before_the_argument_is_read(call):
    shutil.rmtree("docs")
    message = "rfc-resolve: no docs/rfcs/ directory in %s; run from project root" % os.getcwd()
    assert call(rfc_resolve, "a/b") == (2, error(message), b"")


def test_resolve_picks_the_only_modified_rfc(call, repo):
    with open("docs/rfcs/2026-02-01-beta.md", "a") as f:
        f.write("more\n")
    code, out, _ = call(rfc_resolve, "")
    assert (code, label(out)) == (0, "RFC 2026-02-01-beta (unique modified file)")


def test_resolve_in_a_clean_tree_falls_back_to_the_most_recently_dated_rfc(call, repo):
    path = os.path.join(os.getcwd(), "docs/rfcs/2026-03-01-gamma.md")
    want = ('{\n  "path": "%s",\n  "label": "RFC 2026-03-01-gamma (most recently dated file)"\n}\n' % path).encode()
    assert call(rfc_resolve) == (0, want, b"")


def test_resolve_reads_git_status_as_the_bash_script_s_awk_did(call, repo):
    # A deletion is skipped and a rename gives its new path.
    run_git("rm", "-q", "docs/rfcs/2026-03-01-gamma.md")
    run_git("mv", "docs/rfcs/2026-01-01-alpha.md", "docs/rfcs/2026-05-01-moved.md")
    assert label(call(rfc_resolve)[1]) == "RFC 2026-05-01-moved (unique modified file)"


def test_resolve_ignores_a_path_git_status_quotes(call, repo):
    # Untracked, so the only modified file, but quoted for its space; it
    # sorts first, so the fallback still finds gamma.
    Path("docs/rfcs/0 with space.md").write_text("x")
    assert label(call(rfc_resolve)[1]) == "RFC 2026-03-01-gamma (most recently dated file)"


def test_resolve_a_modified_path_that_is_no_longer_a_file_exits_1(call, repo):
    os.unlink("docs/rfcs/2026-02-01-beta.md")
    os.symlink("nowhere", "docs/rfcs/2026-02-01-beta.md")  # a type change, which status lists
    message = "rfc-resolve: modified file docs/rfcs/2026-02-01-beta.md no longer exists"
    assert call(rfc_resolve) == (1, error(message), b"")


def test_resolve_falls_back_to_the_last_regular_file_in_code_point_order(call, hermetic_git):
    for name in ("2026-01-01-b.md", "2026-01-01-a-z.md", "2026-01-01-B.md", ".zz.md", "zz.txt"):
        Path("docs/rfcs", name).write_text("x")
    Path("docs/rfcs/zz.md").mkdir()  # not a regular file
    code, out, _ = call(rfc_resolve)
    assert (code, label(out)) == (0, "RFC 2026-01-01-b (most recently dated file)")


def test_resolve_without_rfc_files_exits_1(call, hermetic_git):
    Path("docs/rfcs/.hidden.md").write_text("x")
    assert call(rfc_resolve) == (1, error("rfc-resolve: no RFC files under docs/rfcs/"), b"")


def test_resolve_names_an_identifier_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-resolve", b"caf\xe9")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        1,
        {"error": "rfc-resolve: no RFC found at docs/rfcs/caf\ufffd.md"},
        b"",
    )


def test_resolve_prints_a_directory_that_isn_t_utf_8_with_u_fffd(tmp_path, monkeypatch):
    project = os.path.join(os.fsencode(tmp_path), b"caf\xe9")
    try:
        os.makedirs(os.path.join(project, b"docs", b"rfcs"))
    except OSError:
        pytest.skip("this filesystem refuses a name that isn't UTF-8")
    open(os.path.join(project, b"docs", b"rfcs", b"x.md"), "w").close()
    monkeypatch.chdir(project)
    proc = bw_run("rfc-resolve", "x")
    want = jsonout.jq_string(os.fsdecode(os.getcwd())) + "/docs/rfcs/x.md"
    assert (proc.returncode, json.loads(proc.stdout)["path"], proc.stderr) == (0, want, b"")


# --- rfc-set-status ----------------------------------------------------------

RFC = "docs/rfcs/x.md"


def status_set(old, new):
    return ('{\n  "file": "docs/rfcs/x.md",\n  "old_status": "%s",\n  "new_status": "%s"\n}\n' % (old, new)).encode()


def test_set_status_rewrites_lines_as_the_bash_script_s_awk_did(call):
    # Kept from the bash script: every "status:" line in the block is
    # rewritten, indented or not, the reason goes before the closing "---",
    # later "---" lines are left alone, and every line ends with a newline.
    Path(RFC).write_bytes(
        b'---\nrfc: x\nstatus: "Draft" # c\nmeta:\n  status: indented\n---\nbody\n---\nstatus: body\n---'
    )
    assert call(rfc_set_status, RFC, "Dropped", 'say "hi" C:\\temp\\') == (0, status_set("Draft", "Dropped"), b"")
    assert Path(RFC).read_bytes() == (
        b'---\nrfc: x\nstatus: "Dropped"\nmeta:\nstatus: "Dropped"\ndrop_reason: "say \\"hi\\" C:\\\\temp\\\\"\n'
        b"---\nbody\n---\nstatus: body\n---\n"
    )


@pytest.mark.parametrize(
    "lines, status, want",
    [
        ('status: Dropped\ndrop_reason: "old"\n', "Draft", 'status: "Draft"\ndrop_reason: ~\n'),
        ('status: Dropped\ndrop_reason: "old"\n', "Dropped", 'status: "Dropped"\ndrop_reason: "new"\n'),
        ("status: Draft\ndrop_reason:\n", "Done", 'status: "Done"\ndrop_reason: ~\n'),
    ],
)
def test_set_status_rewrites_drop_reason_lines(call, lines, status, want):
    Path(RFC).write_text("---\n%s---\n" % lines)
    reason = ["new"] if status == "Dropped" else []
    assert call(rfc_set_status, RFC, status, *reason)[0] == 0
    assert Path(RFC).read_text() == "---\n%s---\n" % want


@pytest.mark.parametrize(
    "line, old", [('status: "Draft" # still a draft', "Draft"), ("status: 'Approved'", "Approved")]
)
def test_set_status_reads_the_old_status_with_load_frontmatter(call, line, old):
    # The bash script's awk dropped only the double quotes: "Draft # still a
    # draft" and "'Approved'".
    Path(RFC).write_text("---\n%s\n---\n" % line)
    code, out, _ = call(rfc_set_status, RFC, "Done")
    assert (code, json.loads(out)["old_status"]) == (0, old)


@pytest.mark.parametrize(
    "text",
    [
        "---\nstatus: ~\n---\n",
        "---\nrfc: a\n---\n",
        '---\n"status": Draft\n---\n',
        "---\nstatus : Draft\n---\n",
        "---\n{status: Draft}\n---\n",
    ],
)
def test_set_status_without_a_status_or_a_line_to_rewrite_leaves_the_file_alone(call, text):
    Path(RFC).write_text(text)
    message = "rfc-set-status: docs/rfcs/x.md has no 'status:' line in its frontmatter"
    assert call(rfc_set_status, RFC, "Approved") == (2, error(message), b"")
    assert Path(RFC).read_text() == text


def test_set_status_prints_load_frontmatter_s_error(call):
    Path(RFC).write_text("# Title\n---\nstatus: Draft\n---\n")
    message = "rfc-set-status: docs/rfcs/x.md does not begin with a YAML frontmatter delimiter"
    assert call(rfc_set_status, RFC, "Approved") == (2, error(message), b"")


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: bw rfc-set-status <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"),
        ([RFC], "usage: bw rfc-set-status <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"),
        (["", "Done"], "usage: bw rfc-set-status <path-to-rfc.md> <Draft|Approved|Done|Dropped> [<drop-reason>]"),
        (["missing.md", "done"], "rfc-set-status: invalid status 'done' (allowed: Draft, Approved, Done, Dropped)"),
        (["missing.md", "Dropped"], "rfc-set-status: drop_reason is required when status=Dropped"),
        (["missing.md", "Dropped", ""], "rfc-set-status: drop_reason is required when status=Dropped"),
        (["missing.md", "Done", "why"], "rfc-set-status: drop_reason is only allowed when status=Dropped"),
        (["missing.md", "Dropped", "a\nb"], "rfc-set-status: file not found: missing.md"),
        (
            ["docs/rfcs/none.md", "Dropped", "a\nb"],
            "rfc-set-status: docs/rfcs/none.md has no 'status:' line in its frontmatter",
        ),
        ([RFC, "Dropped", "a\nb"], "rfc-set-status: drop_reason must not contain newlines"),
    ],
)
def test_set_status_checks_in_the_bash_script_s_order(call, argv, message):
    Path(RFC).write_text("---\nstatus: Draft\n---\n")
    Path("docs/rfcs/none.md").write_text("---\nrfc: none\n---\n")
    assert call(rfc_set_status, *argv) == (2, error(message), b"")
    assert Path(RFC).read_text() == "---\nstatus: Draft\n---\n"


def test_set_status_approves_a_draft_in_place(call):
    Path(RFC).write_text('---\nrfc: "x"\nstatus: "Draft"\ndrop_reason: ~\n---\n\n## Summary\n')
    assert call(rfc_set_status, RFC, "Approved") == (0, status_set("Draft", "Approved"), b"")
    assert Path(RFC).read_text() == '---\nrfc: "x"\nstatus: "Approved"\ndrop_reason: ~\n---\n\n## Summary\n'


@pytest.mark.parametrize(
    "reason",
    [
        "Superseded by RFC 2026-02-01.",
        'Superseded by the "init" RFC.',
        "Moved to C:\\temp\\new (see \\n in the notes).",
        "Folded into the parent RFC\\",
        'Superseded by the "init" RFC; see C:\\temp\\notes, trailing\\',
        'say "hi", C:\\temp\\new, a\\nb, trailing\\',
    ],
)
def test_set_status_writes_a_reason_that_reads_back_as_given(call, reason):
    # Through rfc-frontmatter and through PyYAML's own safe loader: a \t or
    # \n typed in the reason must not read back as a tab or a newline, and a
    # trailing backslash must not escape the closing quote.
    Path(RFC).write_text('---\nrfc: "x"\nstatus: "Draft"\ndrop_reason: ~\n---\n')
    assert call(rfc_set_status, RFC, "Dropped", reason) == (0, status_set("Draft", "Dropped"), b"")
    code, out, err = call(rfc_frontmatter, RFC)
    fields = json.loads(out)
    assert (code, fields["status"], fields["drop_reason"], err) == (0, "Dropped", reason, b"")
    block = yaml.safe_load(Path(RFC).read_text().split("---\n")[1])
    assert (block["status"], block["drop_reason"]) == ("Dropped", reason)


def test_set_status_writes_a_reason_s_bytes_as_given():
    Path(RFC).write_text("---\nstatus: Draft\n---\n")
    proc = bw_run("rfc-set-status", RFC, "Dropped", b'caf\xe9 "q" \\ \r')
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, status_set("Draft", "Dropped"), b"")
    assert Path(RFC).read_bytes() == b'---\nstatus: "Dropped"\ndrop_reason: "caf\xe9 \\"q\\" \\\\ \r"\n---\n'


def test_set_status_names_a_file_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("rfc-set-status", b"caf\xe9.md", "Approved")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "rfc-set-status: file not found: caf\ufffd.md"},
        b"",
    )


@pytest.mark.skipif(IS_ROOT, reason="root writes any file")
def test_set_status_reports_a_failed_write_as_a_json_error(call):
    # The bash script printed the status change and exited 0 here.
    Path(RFC).write_text("---\nstatus: Draft\n---\n")
    Path(RFC).chmod(0o444)
    message = "rfc-set-status: Permission denied: docs/rfcs/x.md"
    assert call(rfc_set_status, RFC, "Approved") == (2, error(message), b"")
    assert Path(RFC).read_text() == "---\nstatus: Draft\n---\n"


# --- rfc-summary -------------------------------------------------------------


def write_rfc(name, block):
    Path("docs/rfcs", name).write_text("---\n%s---\n" % block)


def test_summary_prints_rows_and_warnings_as_jq_did(call):
    write_rfc("b.md", "rfc: b\ntitle: B\nauthor: A\nstatus: Done\ncreated: 2026-02-01\n")
    write_rfc("a.md", 'rfc: a\ntitle: "T"\nauthor: A\nstatus: Draft\ncreated: 2026-01-01\n')
    write_rfc("c.md", "rfc: c\nstatus: Pending\n")
    row = '    {\n      "status": "%s",\n      "created": "%s",\n      "rfc": "%s",\n      "title": "%s",\n      "author": "A"\n    }'
    want = '{\n  "rfcs": [\n%s,\n%s\n  ],\n  "warnings": [\n    "%s"\n  ]\n}\n' % (
        row % ("Draft", "2026-01-01", "a", "T"),
        row % ("Done", "2026-02-01", "b", "B"),
        'Warning: docs/rfcs/c.md — unrecognized status \\"Pending\\"; skipping.',
    )
    assert call(rfc_summary) == (0, want.encode(), b"")


def test_summary_of_no_rfcs_is_empty(call):
    assert call(rfc_summary) == (0, b'{\n  "rfcs": [],\n  "warnings": []\n}\n', b"")


def test_summary_sorts_by_created_then_rfc_and_keeps_file_order_for_ties(call):
    for name, rfc, created in (
        ("a.md", "same", "2026-01-01"),
        ("b.md", "same", "2026-01-01"),
        ("c.md", "B", "2026-01-01"),
        ("d.md", "a", "2025-12-31"),
    ):
        write_rfc(name, "rfc: %s\nstatus: Draft\ncreated: %s\ntitle: %s\n" % (rfc, created, name))
    rows = json.loads(call(rfc_summary)[1])["rfcs"]
    assert [r["title"] for r in rows] == ["d.md", "c.md", "a.md", "b.md"]


def test_summary_takes_each_field_as_jq_r_gave_it(call):
    # Kept: $(jq -r ...) dropped NUL bytes and trailing newlines.
    write_rfc(
        "a.md", 'rfc: "a\\n\\n"\nstatus: "Done\\n"\ntitle: |\n  Block\ncreated: "2026\\x00-01"\nauthor: "x\\ny"\n'
    )
    rows = json.loads(call(rfc_summary)[1])["rfcs"]
    assert rows == [{"status": "Done", "created": "2026-01", "rfc": "a", "title": "Block", "author": "x\ny"}]


def test_summary_leaves_out_with_a_warning(call):
    write_rfc("a.md", "rfc: a\n")
    write_rfc("b.md", 'rfc: "\\n"\nstatus: Draft\n')
    Path("docs/rfcs/c.md").write_text("# no frontmatter\n")
    write_rfc("d.md", "rfc: d\nstatus: Draft\ncreated: !!int abc\n")  # not valid YAML: !!int can't hold abc
    write_rfc("e.md", 'rfc: e\nstatus: "Dr\\naft"\n')
    Path("docs/rfcs/f.md").mkdir()
    write_rfc(".g.md", "rfc: g\nstatus: Draft\n")
    write_rfc("h.MD", "rfc: h\nstatus: Draft\n")
    code, out, err = call(rfc_summary)
    assert (code, err) == (0, b"")
    assert json.loads(out) == {
        "rfcs": [],
        "warnings": [
            "Warning: docs/rfcs/a.md — frontmatter incomplete; skipping.",
            "Warning: docs/rfcs/b.md — frontmatter incomplete; skipping.",
            "Warning: docs/rfcs/c.md — frontmatter unparseable; skipping.",
            "Warning: docs/rfcs/d.md — frontmatter unparseable; skipping.",
            # Kept: jq -R made one warning per line.
            'Warning: docs/rfcs/e.md — unrecognized status "Dr',
            'aft"; skipping.',
        ],
    }


def test_summary_names_a_file_that_isn_t_utf_8_with_u_fffd():
    try:
        with open(b"docs/rfcs/caf\xe9.md", "wb") as f:
            f.write(b"# no frontmatter\n")
    except OSError:
        pytest.skip("this filesystem refuses a name that isn't UTF-8")
    proc = bw_run("rfc-summary")
    want = {"rfcs": [], "warnings": ["Warning: docs/rfcs/caf\ufffd.md — frontmatter unparseable; skipping."]}
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (0, want, b"")


def test_summary_without_docs_rfcs_is_an_error_naming_the_directory(call):
    shutil.rmtree("docs")
    assert call(rfc_summary) == (2, error("no docs/rfcs/ directory in " + os.getcwd()), b"")


# --- tool-probe --------------------------------------------------------------

MISSING = {
    "gh": "gh CLI not on PATH. Install: https://cli.github.com.",
    "git": "git not on PATH. Install: https://git-scm.com/downloads.",
    "jq": "Install jq: https://stedolan.github.io/jq/download/",
}


@pytest.fixture
def bin_dir(tmp_path, monkeypatch):
    """A directory that is all of PATH, for stand-in tools."""
    directory = tmp_path / "bin"
    directory.mkdir()
    monkeypatch.setenv("PATH", str(directory))
    return directory


def stand_in(directory, name, code=0, log=None):
    """An executable DIRECTORY/NAME that exits CODE, appending its arguments to LOG."""
    script = "#!/bin/sh\n" + ('echo "$@" >>"%s"\n' % log if log else "") + "exit %d\n" % code
    (directory / name).write_text(script)
    (directory / name).chmod(0o755)


@pytest.mark.parametrize("name", ["gh", "git", "jq"])
def test_probe_of_a_missing_tool_exits_1_with_its_hint(call, bin_dir, name):
    # For jq this is new: the bash script needed jq, so it exited 2 first.
    want = '{\n  "result": "missing",\n  "name": "%s",\n  "hint": "%s"\n}\n' % (name, MISSING[name])
    assert call(tool_probe, name) == (1, want.encode(), b"")


@pytest.mark.parametrize("name", ["git", "jq"])
def test_probe_of_a_tool_on_path_is_available(call, bin_dir, name):
    stand_in(bin_dir, name, code=1)  # only gh is run
    assert call(tool_probe, name) == (0, b'{\n  "result": "available",\n  "name": "%s"\n}\n' % name.encode(), b"")


def test_probe_needs_an_executable(call, bin_dir):
    # bash's command -v also took a file without the execute bit.
    (bin_dir / "git").write_text("")
    assert call(tool_probe, "git")[0] == 1


def test_probe_of_gh_runs_gh_auth_status(call, bin_dir, tmp_path):
    log = tmp_path / "log"
    stand_in(bin_dir, "gh", code=1, log=log)
    hint = "gh CLI present but not authenticated. Run: gh auth login."
    want = '{\n  "result": "unauthenticated",\n  "name": "gh",\n  "hint": "%s"\n}\n' % hint
    assert call(tool_probe, "gh") == (1, want.encode(), b"")
    stand_in(bin_dir, "gh", code=0, log=log)
    assert call(tool_probe, "gh") == (0, b'{\n  "result": "available",\n  "name": "gh"\n}\n', b"")
    assert log.read_text() == "auth status\nauth status\n"


@pytest.mark.parametrize(
    "argv, message",
    [
        ([], "usage: bw tool-probe <gh|git|jq>"),
        ([""], "usage: bw tool-probe <gh|git|jq>"),
        (["nonsense"], "unrecognized probe name 'nonsense'"),
        (["github-mcp"], "unrecognized probe name 'github-mcp'"),
    ],
)
def test_probe_errors(call, argv, message):
    assert call(tool_probe, *argv) == (2, error(message), b"")


def test_probe_names_a_probe_that_isn_t_utf_8_with_u_fffd():
    proc = bw_run("tool-probe", b"caf\xe9")
    assert (proc.returncode, json.loads(proc.stdout), proc.stderr) == (
        2,
        {"error": "unrecognized probe name 'caf\ufffd'"},
        b"",
    )
