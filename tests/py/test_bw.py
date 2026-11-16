"""Tests for scripts/bytewyrd (RFC 2026-11-09-scaffold-and-drift, B2, B4 and
B5): the shared modules and detection, the bootstrap's checks and dispatch,
and the scaffold, drift, state-touch and compact-reminder commands.

Detection cases build real throwaway git repositories, with the developer's
git configuration kept out (see hermetic_git). tests/e2e/test_consumer_sim.py
runs scaffold and drift end to end; the cases here cover their parts.
"""

import ast
import hashlib
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
import warnings
from pathlib import Path

import pytest

from bytewyrd import __main__ as bootstrap
from bytewyrd import cli, detect, fs, git, jsonout, seed
from bytewyrd.commands import compact_reminder, drift, scaffold, state_touch

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts"
PACKAGE = SCRIPTS / "bytewyrd"
MAIN = PACKAGE / "__main__.py"

# --- helpers -----------------------------------------------------------------


@pytest.fixture(autouse=True)
def hermetic_git(monkeypatch):
    """Keep the developer's git configuration and repository out of every git
    call, both the fixtures' and the package's."""
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    for var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        monkeypatch.delenv(var, raising=False)


def run_git(cwd, *args, input=None):
    """Run git in CWD and return its stdout; fail the test if git fails."""
    proc = subprocess.run(["git", "-C", os.fspath(cwd), *args], input=input, capture_output=True)
    if proc.returncode != 0:
        raise AssertionError("git %s: %s" % (" ".join(args), proc.stderr.decode(errors="replace")))
    return proc.stdout


def write(repo, rel, content=""):
    """Write REL under REPO; REL may hold surrogate-escaped (non-UTF-8) bytes."""
    path = os.path.join(os.fsencode(repo), os.fsencode(rel))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(content if isinstance(content, bytes) else content.encode())


def commit(repo, add_all=True):
    if add_all:
        run_git(repo, "add", "-A")
    run_git(
        repo, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-q", "--allow-empty", "-m", "x"
    )


def make_repo(path, files, attributes=None):
    """A git repository at PATH with FILES ({path: content}) committed."""
    path.mkdir(parents=True)
    run_git(path, "init", "-q")
    for rel, content in files.items():
        write(path, rel, content)
    if attributes is not None:
        write(path, ".gitattributes", attributes)
    commit(path)
    return path


def add_gitlink(repo, path):
    """Add a gitlink (mode 160000) at PATH to REPO's index and commit it."""
    run_git(repo, "update-index", "--add", "--cacheinfo", "160000,%s,%s" % ("1" * 40, path))
    commit(repo, add_all=False)


def jobs(repo):
    return [c.job_id for c in detect.detect(str(repo))[0]]


def creatable(tmp_path, name):
    """True when this filesystem accepts NAME as a directory name."""
    try:
        path = os.path.join(os.fsencode(tmp_path), os.fsencode(name))
        os.mkdir(path)
        os.rmdir(path)
        return True
    except (OSError, UnicodeError):
        return False


PROJECT = '[project]\nname = "x"\nversion = "0"\n'
CRATE = '[package]\nname = "x"\nversion = "0.1.0"\n'

# --- ids and platform checks -------------------------------------------------


def test_language_ids_equal_the_lang_ci_workflow_files():
    names = sorted(p.name for p in (REPO / ".github" / "workflows").iterdir() if p.name.startswith("lang-ci"))
    ids = []
    for name in names:
        m = re.fullmatch(r"lang-ci-([a-z0-9]+)\.yml", name)
        assert m, "%s is not named lang-ci-<id>.yml" % name
        ids.append(m.group(1))
    assert ids == sorted(detect.LANGUAGES)


def test_language_ids_equal_the_lang_ci_fixture_jobs():
    lines = (REPO / ".github" / "workflows" / "ci.yml").read_text().splitlines()
    ids = [m.group(1) for m in (re.fullmatch(r"  lang-ci-fixture-([a-z0-9]+):", line) for line in lines) if m]
    assert sorted(ids) == sorted(detect.LANGUAGES)


def test_manifest_languages_are_language_ids():
    assert set(detect.MANIFESTS.values()) == set(detect.LANGUAGES)


def test_language_ids_equal_the_agents_template_tags():
    lines = (REPO / "templates" / "scaffold" / "AGENTS.md.tpl").read_text().splitlines()
    tags = [m.group(1) for m in (re.match(r"@@([a-z0-9_]+)@@ ", line) for line in lines) if m]
    assert sorted(t for t in tags if t not in ("none", "job")) == sorted(detect.LANGUAGES)


def test_dir_fd_and_no_follow_calls_are_supported_here():
    # state-touch works through a directory descriptor; this runs on each CI platform.
    for fn in (os.open, os.mkdir, os.stat, os.utime, os.unlink):
        assert fn in os.supports_dir_fd, fn.__name__
    assert os.utime in os.supports_follow_symlinks


def test_plugin_dir_is_the_parent_of_scripts():
    assert Path(seed.PLUGIN_DIR) == REPO


# --- the bootstrap, __main__.py ----------------------------------------------


def run_main(argv, monkeypatch, version=None):
    with monkeypatch.context() as m:
        m.setattr(sys, "path", list(sys.path))
        if version is not None:
            m.setattr(sys, "version_info", version)
        return bootstrap.main(argv)


PY310 = (3, 10, 14, "final", 0)


@pytest.mark.parametrize("name", bootstrap.CLASS_A)
def test_bootstrap_on_python_3_10_exits_1_for_class_a(name, monkeypatch, capsys):
    assert run_main(["__main__.py", name, "arg"], monkeypatch, PY310) == 1
    out, err = capsys.readouterr()
    assert (out, err) == ("", bootstrap.NEEDS_PYTHON + "\n")


@pytest.mark.parametrize("name", bootstrap.CLASS_B)
def test_bootstrap_on_python_3_10_exits_2_with_json_for_class_b(name, monkeypatch, capsys):
    assert run_main(["__main__.py", name, "arg"], monkeypatch, PY310) == 2
    out, err = capsys.readouterr()
    assert out == ""
    assert err == '{"error":"%s"}\n' % bootstrap.NEEDS_PYTHON
    assert json.loads(err) == {"error": bootstrap.NEEDS_PYTHON}


@pytest.mark.parametrize(
    "argv, message",
    [
        (["__main__.py"], "bw: usage: bw NAME [ARGS...]\n"),
        (["__main__.py", "nope"], "bw: unknown command: nope\n"),
        (["__main__.py", "../x"], "bw: unknown command: ../x\n"),
        (["__main__.py", "main"], "bw: unknown command: main\n"),
    ],
)
def test_bootstrap_rejects_unknown_names_on_any_version(argv, message, monkeypatch, capsys):
    for version in (None, PY310):
        assert run_main(argv, monkeypatch, version) == 1
        assert capsys.readouterr() == ("", message)


def test_bootstrap_reports_a_missing_module_by_class(monkeypatch, capsys):
    monkeypatch.setattr(bootstrap, "CLASS_A", bootstrap.CLASS_A + ("zz-absent-a",))
    monkeypatch.setattr(bootstrap, "CLASS_B", bootstrap.CLASS_B + ("zz-absent-b",))
    assert run_main(["__main__.py", "zz-absent-a"], monkeypatch) == 1
    assert capsys.readouterr().err == "bytewyrd: zz-absent-a is not available in this copy of the plugin\n"
    assert run_main(["__main__.py", "zz-absent-b"], monkeypatch) == 2
    assert json.loads(capsys.readouterr().err) == {
        "error": "bytewyrd: zz-absent-b is not available in this copy of the plugin"
    }


def test_bootstrap_puts_scripts_and_vendor_first_and_returns_the_command_exit(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    with monkeypatch.context() as m:
        m.setattr(sys, "path", ["elsewhere"])
        assert bootstrap.main(["__main__.py", "compact-reminder"]) == 0
        assert sys.path == [str(SCRIPTS), str(SCRIPTS / "_vendor"), "elsewhere"]


def test_bootstrap_dispatches_under_the_launcher_flags(tmp_path):
    cmd = [sys.executable, "-I", "-S", "-B", str(MAIN), "compact-reminder"]
    proc = subprocess.run(cmd, cwd=tmp_path, capture_output=True, text=True)
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, "", "")
    (tmp_path / ".bytewyrd").mkdir()
    (tmp_path / ".bytewyrd" / "last-feature-engineer-stop").touch()
    proc = subprocess.run(cmd, cwd=tmp_path, capture_output=True, text=True)
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, compact_reminder.TEXT + "\n", "")


# The package's __init__.py runs before the bootstrap's version check when
# Python runs the package (python -m bytewyrd), so it stays old-syntax-safe too.
@pytest.mark.parametrize("name", ["__main__.py", "__init__.py"])
def test_the_bootstrap_and_the_package_init_parse_as_old_python_3(name):
    source = (PACKAGE / name).read_text()
    tree = ast.parse(source, feature_version=(3, 7))  # rejects walrus and match
    for node in ast.walk(tree):
        assert not isinstance(node, (ast.JoinedStr, ast.AnnAssign)), "f-string or annotation at line %d" % node.lineno
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            assert node.returns is None, node.name
            args = node.args
            for arg in args.posonlyargs + args.args + args.kwonlyargs + [args.vararg, args.kwarg]:
                assert arg is None or arg.annotation is None, node.name


def test_launcher_and_bootstrap_agree_on_classes_and_message():
    text = (REPO / "scripts" / "bw").read_text()
    # shfmt indents case items (switch_case_indent in .editorconfig).
    class_a = re.search(r"^[ \t]*(scaffold \| .*)\) class=A ;;$", text, re.M).group(1)
    class_b = re.search(r"^[ \t]*(rfc-.*)\) class=B ;;$", text, re.M).group(1)
    assert tuple(class_a.split(" | ")) == bootstrap.CLASS_A
    assert tuple(class_b.split(" | ")) == bootstrap.CLASS_B
    assert "msg='%s'" % bootstrap.NEEDS_PYTHON in text


def test_each_class_b_name_has_its_python_port():
    for name in bootstrap.CLASS_B:
        assert (PACKAGE / "commands" / (name.replace("-", "_") + ".py")).is_file(), name


# --- quote() and attr_line() -------------------------------------------------


@pytest.mark.parametrize(
    "s, want",
    [
        ("go.mod", "go.mod"),
        ("apps/web-1_x.y", "apps/web-1_x.y"),
        ("", '""'),
        ("bad dir", '"bad dir"'),
        ("a\tb\nc", '"a\\tb\\nc"'),
        ("\a\b\v\f\r", '"\\a\\b\\v\\f\\r"'),
        ('q"uote', '"q\\"uote"'),
        ("back\\slash", '"back\\\\slash"'),
        ("\x1b[2J", '"\\033[2J"'),
        ("\x00\x7f", '"\\000\\177"'),
        ("café", '"caf\\303\\251"'),
        (os.fsdecode(b"lat\xe9"), '"lat\\351"'),
        ("w\n::warning::x", '"w\\n::warning::x"'),
        ("a:b@c~", '"a:b@c~"'),
    ],
)
def test_quote(s, want):
    assert cli.quote(s) == want


def test_quote_output_is_ascii_without_control_characters():
    for s in ("\ud800", "é\udce9\x1b", " x", "".join(map(chr, range(0, 300)))):
        q = cli.quote(s)
        assert q.isascii() and all(0x20 <= ord(c) <= 0x7E for c in q), repr(q)


@pytest.mark.parametrize("name", ["tab\there", 'q"uote', "back\\slash", "esc\x1bx", "café", "del\x7f"])
def test_quote_escapes_like_git(tmp_path, name):
    if not creatable(tmp_path, name):
        pytest.skip("this filesystem refuses %r" % name)
    repo = make_repo(tmp_path / "r", {name: "x"})
    # core.quotePath, on by default, makes git C-quote these names the same way.
    assert run_git(repo, "ls-files").decode("ascii") == cli.quote(name) + "\n"


@pytest.mark.parametrize(
    "path, want",
    [
        ("go.mod", "/go.mod -bytewyrd-ci"),
        ("web/package.json", "/web/package.json -bytewyrd-ci"),
        ("bad dir/go.mod", '"/bad dir/go.mod" -bytewyrd-ci'),
        ("a[1]/go.mod", '"/a\\\\[1]/go.mod" -bytewyrd-ci'),
        ("st*r/q?/go.mod", '"/st\\\\*r/q\\\\?/go.mod" -bytewyrd-ci'),
        ("back\\slash/go.mod", '"/back\\\\\\\\slash/go.mod" -bytewyrd-ci'),
        ("#x/go.mod", '"/#x/go.mod" -bytewyrd-ci'),
    ],
)
def test_attr_line(path, want):
    assert detect.attr_line(path) == want


ATTR_NAMES = [
    "bad dir",
    "#x",
    "!x",
    "a[1]",
    "st*r",
    "q?x",
    "back\\slash",
    'q"uote',
    "café",
    os.fsdecode(b"lat\xe9"),
    "new\nline",
    "esc\x1bx",
]
# Paths that an unescaped or unanchored pattern for one of ATTR_NAMES would also match.
ATTR_DECOYS = [
    "go.mod",
    "svc/go.mod",
    "a1/go.mod",
    "stXr/go.mod",
    "qyx/go.mod",
    "x/go.mod",
    "bad/go.mod",
    "back/go.mod",
]


def test_each_attr_line_opts_out_exactly_its_manifest(tmp_path):
    names = [n for n in ATTR_NAMES if creatable(tmp_path, n)]
    assert {"bad dir", "#x", "a[1]", "st*r", "back\\slash"} <= set(names)
    paths = [n + "/go.mod" for n in names]
    lines = "".join(detect.attr_line(p) + "\n" for p in paths)
    repo = make_repo(tmp_path / "r", {p: "module x\n" for p in paths + ATTR_DECOYS}, attributes=lines.encode("ascii"))
    stdin = b"".join(os.fsencode(p) + b"\0" for p in paths + ATTR_DECOYS)
    out = run_git(repo, "check-attr", "--cached", "--stdin", "-z", "bytewyrd-ci", input=stdin)
    fields = out.split(b"\0")
    got = {os.fsdecode(fields[i]): fields[i + 2].decode() for i in range(0, len(fields) - 2, 3)}
    assert got == {**{p: "unset" for p in paths}, **{p: "unspecified" for p in ATTR_DECOYS}}


def test_a_root_go_mod_attr_line_keeps_go_svc(tmp_path):
    # [R79]: an unanchored "go.mod -bytewyrd-ci" would unset svc/go.mod too.
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n", "svc/go.mod": "module y\n"})
    assert jobs(repo) == ["go", "go-svc"]
    write(repo, ".gitattributes", detect.attr_line("go.mod") + "\n")
    commit(repo)
    comps, skipped = detect.detect(str(repo))
    assert comps == [detect.Component("go", "svc", "go-svc", ("svc/go.mod",))]
    assert skipped == [("go.mod", detect.REASON_OPTED_OUT)]
    write(repo, ".gitattributes", "go.mod -bytewyrd-ci\n")
    commit(repo)
    assert jobs(repo) == []


# --- dir_matches() -----------------------------------------------------------


@pytest.mark.parametrize(
    "pattern, directory, want",
    [
        ("packages/*", "packages/a", True),
        ("packages/*", "packages/a/b", False),
        ("packages/*", "packages", False),
        ("./packages/*/", "packages/a", True),
        ("*", "a", True),
        ("*", "a/b", False),  # whole-path fnmatch would say True [R76]
        ("Web", "web", False),
        ("w?b", "web", True),
        ("[ab]x", "bx", True),
        ("[!ab]x", "bx", False),
        ("packages/**", "packages", True),
        ("packages/**", "packages/a/b/c", True),
        ("**", "a/b", True),
        ("**/a", "a", True),
        ("**/a", "x/y/a", True),
        ("a/**/b", "a/b", True),
        ("a/**/b", "a/x/y/b", True),
        ("a/**/b", "a/x/c", False),
        ("libs/*-ext", "libs/x-ext", True),
        ("", "a", False),
        (".", "a", False),
    ],
)
def test_dir_matches(pattern, directory, want):
    assert detect.dir_matches(pattern, directory) is want


def test_dir_matches_is_quick_on_many_double_stars():
    start = time.monotonic()
    assert not detect.dir_matches("/".join(["**"] * 400 + ["z"]), "/".join(["a"] * 60))
    assert time.monotonic() - start < 5


# --- detection: manifests, overrides, scope and validation -------------------


def test_detection_scope_and_overrides(tmp_path):
    # As consumer-sim's S28, plus the other excluded names and a two-segment directory.
    files = {
        p: "{}" if p.endswith("package.json") else "module x\n"
        for p in [
            "test/fixtures/app/package.json",
            "examples/demo/go.mod",
            "testdata/x/go.mod",
            ".github/actions/a/package.json",
            "_old/go.mod",
            "a/b/c/go.mod",
            "docs/package.json",
            "web/package.json",
            "deep/one/two/go.mod",
            "apps/api/go.mod",
            "node_modules/x/package.json",
            "Vendor/go.mod",
            "third_party/go.mod",
            "TESTS/go.mod",
            "spec/go.mod",
            "e2e/go.mod",
            "fixture/go.mod",
            "example/go.mod",
            "sample/go.mod",
            "samples/go.mod",
            "template/go.mod",
            "templates/go.mod",
            "ok/fixtures/go.mod",
        ]
    }
    repo = make_repo(tmp_path / "r", files, attributes="web/package.json -bytewyrd-ci\ndeep/** bytewyrd-ci\n")
    comps, skipped = detect.detect(str(repo))
    assert [c.job_id for c in comps] == ["go-apps-api", "go-deep-one-two", "js-docs"]
    assert skipped == [("web/package.json", detect.REASON_OPTED_OUT)]


def test_detection_validates_directories_and_job_ids(tmp_path):
    long_ok, long_bad = "d" * 64, "e" * 65
    files = {
        "bad dir/go.mod": "",
        "-x/go.mod": "",
        "a.b/go.mod": "",
        "a/b/go.mod": "",
        "x-y/package.json": "{}",
        "x.y/package.json": "{}",
        long_ok + "/go.mod": "",
        long_bad + "/go.mod": "",
    }
    odd = [
        n
        for n in ("w\n::warning::x/go.mod", "\x1b[2J/go.mod", "web\n/package.json")
        if creatable(tmp_path, n.split("/")[0])
    ]
    files.update({n: "{}" if n.endswith(".json") else "" for n in odd})
    repo = make_repo(tmp_path / "r", files)
    comps, skipped = detect.detect(str(repo))
    assert comps == [
        detect.Component("go", "a.b", "go-a-b", ("a.b/go.mod",)),
        detect.Component("go", long_ok, "go-" + long_ok, (long_ok + "/go.mod",)),
        detect.Component("js", "x-y", "js-x-y", ("x-y/package.json",)),
    ]
    want = {
        "bad dir/go.mod": detect.REASON_NAME,
        "-x/go.mod": detect.REASON_NAME,
        long_bad + "/go.mod": detect.REASON_NAME,
        "a/b/go.mod": "job id go-a-b is taken by a.b",
        "x.y/package.json": "job id js-x-y is taken by x-y",
        **{n: detect.REASON_NAME for n in odd},
    }
    assert dict(skipped) == want
    assert [s.path for s in skipped] == sorted(want)


def test_detection_reads_attribute_values_macros_and_only_the_index(tmp_path):
    files = {d + "/go.mod": "" for d in ("v", "q", "s", "u", "plain")}
    attributes = (
        "[attr]quiet -bytewyrd-ci\n"
        "/v/go.mod bytewyrd-ci=false\n"
        "/q/** quiet\n"
        "/s/go.mod bytewyrd-ci\n"
        "/u/go.mod -bytewyrd-ci\n"
    )
    repo = make_repo(tmp_path / "r", files, attributes=attributes)
    comps, skipped = detect.detect(str(repo))
    assert [c.job_id for c in comps] == ["go-plain", "go-s"]
    assert skipped == [
        ("q/go.mod", detect.REASON_OPTED_OUT),
        ("u/go.mod", detect.REASON_OPTED_OUT),
        ("v/go.mod", detect.REASON_VALUE),
    ]
    # An unstaged .gitattributes edit changes nothing: check-attr reads the index.
    write(repo, ".gitattributes", "/plain/go.mod -bytewyrd-ci\n")
    assert detect.detect(str(repo)) == (comps, skipped)


def test_detection_python_needs_a_counted_pyproject(tmp_path):
    # As consumer-sim's S39, for its Python directories.
    files = {
        "tool/pyproject.toml": "[tool.ruff]\nline-length = 100\n",
        "legacy/setup.py": "",
        "both/pyproject.toml": PROJECT + '[dependency-groups]\ndev = ["pytest"]\n',
        "both/setup.py": "",
        "nopy/pyproject.toml": PROJECT,
        "virtual/pyproject.toml": "[tool.uv.workspace]\nmembers = []\n",
    }
    comps, skipped = detect.detect(str(make_repo(tmp_path / "r", files)))
    assert comps == [
        detect.Component("python", "both", "python-both", ("both/pyproject.toml", "both/setup.py")),
        detect.Component("python", "nopy", "python-nopy", ("nopy/pyproject.toml",)),
        detect.Component("python", "virtual", "python-virtual", ("virtual/pyproject.toml",)),
    ]
    assert skipped == [("legacy/setup.py", detect.REASON_PYPROJECT)]


def test_detection_ruby_needs_a_tracked_rakefile(tmp_path):
    files = dict.fromkeys(
        ["Gemfile", "a/Gemfile", "a/Rakefile", "b/Gemfile", "b/rakefile.rb", "c/Gemfile", "c/RAKEFILE"], ""
    )
    comps, skipped = detect.detect(str(make_repo(tmp_path / "r", files)))
    assert [c.job_id for c in comps] == ["ruby-a", "ruby-b"]
    assert skipped == [("Gemfile", detect.REASON_RAKEFILE), ("c/Gemfile", detect.REASON_RAKEFILE)]


def test_detection_counts_an_unmerged_manifest_once(tmp_path):
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n"})
    oid = run_git(repo, "rev-parse", ":go.mod").decode().strip()
    info = "0 %s\tgo.mod\n" % ("0" * 40) + "".join("100644 %s %d\tgo.mod\n" % (oid, s) for s in (1, 2, 3))
    run_git(repo, "update-index", "--index-info", input=info.encode())
    assert [e.stage for e in git.tracked(str(repo))] == [1, 2, 3]
    assert jobs(repo) == ["go"]


def test_detection_never_counts_a_submodule_s_files(tmp_path):
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n"})
    add_gitlink(repo, "sub")
    assert jobs(repo) == ["go"]


def test_detection_result_shapes_and_order(tmp_path):
    files = {"z/go.mod": "", "go.mod": "", "web/package.json": "{}", "Cargo.toml": CRATE, "Gemfile": ""}
    comps, skipped = detect.detect(str(make_repo(tmp_path / "r", files)))
    assert [(c.language, c.directory) for c in comps] == [("go", "."), ("go", "z"), ("js", "web"), ("rust", ".")]
    assert all(isinstance(c, tuple) and len(c) == 4 for c in comps)
    assert skipped == [detect.Skip("Gemfile", detect.REASON_RAKEFILE)] and len(skipped[0]) == 2


# --- detection: root workspaces ----------------------------------------------


def test_js_root_workspaces_drop_matching_members(tmp_path):
    files = {
        "package.json": json.dumps({"workspaces": ["packages/*", "!packages/skip"]}),
        "packages/a/package.json": "{}",
        "packages/skip/package.json": "{}",
        "site/package.json": "{}",
    }
    assert jobs(make_repo(tmp_path / "r", files)) == ["js", "js-packages-skip", "js-site"]


def test_js_root_workspaces_object_form(tmp_path):
    files = {
        "package.json": json.dumps({"workspaces": {"packages": ["packages/*"], "nohoist": ["x"]}}),
        "packages/a/package.json": "{}",
    }
    assert jobs(make_repo(tmp_path / "r", files)) == ["js"]


@pytest.mark.parametrize(
    "workspaces",
    [[1, "packages/*"], "packages/*", {"nohoist": ["packages/*"]}, {"packages": "packages/*"}, None, {}],
)
def test_js_wrong_shaped_workspaces_declare_nothing(tmp_path, workspaces):
    files = {"package.json": json.dumps({"workspaces": workspaces}), "packages/a/package.json": "{}"}
    assert jobs(make_repo(tmp_path / "r", files)) == ["js", "js-packages-a"]


def test_js_an_opted_out_root_or_a_set_member_keeps_the_member(tmp_path):
    files = {
        "package.json": json.dumps({"workspaces": ["packages/*"]}),
        "packages/a/package.json": "{}",
        "packages/b/package.json": "{}",
    }
    comps, skipped = detect.detect(str(make_repo(tmp_path / "out", files, attributes="/package.json -bytewyrd-ci\n")))
    assert [c.job_id for c in comps] == ["js-packages-a", "js-packages-b"]
    assert skipped == [("package.json", detect.REASON_OPTED_OUT)]
    repo = make_repo(tmp_path / "set", files, attributes="/packages/b/package.json bytewyrd-ci\n")
    assert jobs(repo) == ["js", "js-packages-b"]


def test_python_root_workspace_drops_members_but_not_excluded_ones(tmp_path):
    files = {
        "pyproject.toml": '[tool.uv.workspace]\nmembers = ["libs/*"]\nexclude = ["libs/solo"]\n',
        "libs/m/pyproject.toml": PROJECT,
        "libs/solo/pyproject.toml": PROJECT,
        "tools/x/pyproject.toml": PROJECT,
    }
    assert jobs(make_repo(tmp_path / "r", files)) == ["python", "python-libs-solo", "python-tools-x"]


def test_python_without_a_root_workspace_keeps_nested_projects(tmp_path):
    files = {"pyproject.toml": PROJECT, "libs/m/pyproject.toml": PROJECT}
    assert jobs(make_repo(tmp_path / "r", files)) == ["python", "python-libs-m"]


def test_python_a_wrong_shaped_workspace_makes_the_file_declare_nothing(tmp_path):
    # Even its [project] table: the whole file declares nothing (B2, Reading).
    files = {"pyproject.toml": PROJECT + '[tool.uv.workspace]\nmembers = "libs/*"\n', "libs/m/pyproject.toml": PROJECT}
    assert jobs(make_repo(tmp_path / "r", files)) == ["python-libs-m"]


def test_python_a_root_with_only_setup_py_yields_no_workspace(tmp_path):
    files = {"setup.py": "", "libs/m/pyproject.toml": PROJECT}
    comps, skipped = detect.detect(str(make_repo(tmp_path / "r", files)))
    assert [c.job_id for c in comps] == ["python-libs-m"]
    assert skipped == [("setup.py", detect.REASON_PYPROJECT)]


def test_rust_root_workspace_drops_nested_crates_unless_excluded_or_self_rooted(tmp_path):
    files = {
        "Cargo.toml": '[workspace]\nmembers = ["crates/*"]\nexclude = ["tools"]\n',
        "crates/c/Cargo.toml": CRATE,
        "lone/Cargo.toml": CRATE,  # neither member nor excluded: fails in place [R71]
        "tools/gen/Cargo.toml": CRATE,  # under the "tools" prefix
        "toolsx/y/Cargo.toml": CRATE,  # a prefix covers whole segments only
        "other/Cargo.toml": CRATE + "[workspace]\n",
    }
    assert jobs(make_repo(tmp_path / "r", files)) == ["rust", "rust-other", "rust-tools-gen"]


def test_rust_exclude_is_a_prefix_not_a_glob(tmp_path):
    files = {"Cargo.toml": '[workspace]\nexclude = ["tool*"]\n', "tools/gen/Cargo.toml": CRATE}
    assert jobs(make_repo(tmp_path / "r", files)) == ["rust"]


@pytest.mark.parametrize(
    "root",
    [
        CRATE,  # a root package without [workspace]: nested crates build standalone
        '[workspace]\nmembers = "crates/*"\n',  # wrong shape, as consumer-sim's S37
        b"[workspace]\n# \xff\n",  # not UTF-8, as S36
        "[workspace\n",  # not TOML
        "workspace = 1\n",
    ],
)
def test_rust_roots_that_declare_no_workspace_keep_nested_crates(tmp_path, root):
    files = {"Cargo.toml": root, "crates/c/Cargo.toml": CRATE}
    assert jobs(make_repo(tmp_path / "r", files)) == ["rust", "rust-crates-c"]


def test_go_and_ruby_roots_drop_nothing(tmp_path):
    files = {
        "go.mod": "module x\n",
        "go.work": "go 1.27\nuse (\n\t.\n\t./svc\n)\n",
        "svc/go.mod": "module y\n",
        "Gemfile": "",
        "Rakefile": "",
        "app/Gemfile": "",
        "app/Rakefile": "",
    }
    assert jobs(make_repo(tmp_path / "r", files)) == ["go", "go-svc", "ruby", "ruby-app"]


def test_every_root_workspace_rule_at_once(tmp_path):
    # As consumer-sim's S26.
    files = {
        "package.json": json.dumps({"workspaces": ["packages/*"]}),
        "pyproject.toml": '[tool.uv.workspace]\nmembers = ["libs/*"]\nexclude = ["libs/solo"]\n',
        "Cargo.toml": '[workspace]\nmembers = ["crates/*"]\nexclude = ["tools"]\n',
        "go.mod": "module x\n",
        "go.work": "use . ./svc\n",
        "packages/a/package.json": "{}",
        "site/package.json": "{}",
        "libs/m/pyproject.toml": PROJECT,
        "libs/solo/pyproject.toml": PROJECT,
        "crates/c/Cargo.toml": CRATE,
        "tools/gen/Cargo.toml": CRATE,
        "svc/go.mod": "module y\n",
    }
    assert jobs(make_repo(tmp_path / "r", files)) == [
        "go",
        "go-svc",
        "js",
        "js-site",
        "python",
        "python-libs-solo",
        "rust",
        "rust-tools-gen",
    ]


# --- detection: reading through blob() ---------------------------------------


WORKSPACES = {"workspaces": ["packages/*"]}


@pytest.mark.parametrize(
    "root",
    [
        b" " * (2 << 20) + json.dumps(WORKSPACES).encode(),  # over 1 MiB, as S33
        b'{"workspaces": ["packages/*"], "x": ' + b"[" * 200000 + b"]" * 200000 + b"}",  # as S34
        b'{"workspaces": ["packages/*"], "n": ' + b"7" * 5000 + b"}",  # as S35
        b'{"workspaces": ["packages/*"], "x": "\xff"}',  # not UTF-8
        b"[]",
        b"{",
    ],
    ids=["2MiB", "deep", "5000-digits", "not-utf8", "not-an-object", "not-json"],
)
def test_unreadable_package_json_declares_no_workspace(tmp_path, root):
    files = {"package.json": root, "packages/a/package.json": "{}"}
    assert jobs(make_repo(tmp_path / "r", files)) == ["js", "js-packages-a"]


def test_a_symlinked_root_manifest_counts_but_is_never_read(tmp_path):
    # As consumer-sim's S31: a committed package.json symlink to /dev/zero.
    repo = tmp_path / "r"
    repo.mkdir()
    run_git(repo, "init", "-q")
    os.symlink("/dev/zero", repo / "package.json")
    write(repo, "packages/a/package.json", "{}")
    commit(repo)
    assert jobs(repo) == ["js", "js-packages-a"]


def test_a_gitlink_at_a_manifest_path_counts_and_declares_nothing(tmp_path):
    # As consumer-sim's S32.
    repo = make_repo(tmp_path / "r", {"crates/c/Cargo.toml": CRATE})
    add_gitlink(repo, "Cargo.toml")
    assert jobs(repo) == ["rust", "rust-crates-c"]


# --- tracked() and blob() ----------------------------------------------------


def test_tracked_lists_each_index_entry(tmp_path):
    names = [n for n in ("tab\there", "new\nline") if creatable(tmp_path, n)]
    repo = make_repo(tmp_path / "r", {"a.txt": "a", **{n: "x" for n in names}})
    os.symlink("a.txt", repo / "link")
    write(repo, "run.sh", "#!/bin/sh\n")
    os.chmod(repo / "run.sh", 0o755)
    commit(repo)
    add_gitlink(repo, "sub")
    entries = {e.path: e for e in git.tracked(str(repo))}
    modes = {"a.txt": "100644", "link": "120000", "run.sh": "100755", "sub": "160000"}
    assert {p: e.mode for p, e in entries.items()} == {**modes, **dict.fromkeys(names, "100644")}
    assert all(e.stage == 0 and re.fullmatch(r"[0-9a-f]{40,64}", e.oid) for e in entries.values())


def test_tracked_decodes_paths_with_fsdecode(tmp_path):
    name = os.fsdecode(b"caf\xe9.txt")
    if not creatable(tmp_path, name):
        pytest.skip("this filesystem refuses non-UTF-8 names")
    repo = make_repo(tmp_path / "r", {name: "x"})
    assert [e.path for e in git.tracked(str(repo))] == [name]


def test_tracked_outside_a_repo_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    (tmp_path / "plain").mkdir()
    with pytest.raises(cli.BwError):
        git.tracked(str(tmp_path / "plain"))


def test_blob_returns_regular_stage_0_entries_up_to_1_mib(tmp_path):
    files = {"small": b"abc", "exact": b"y" * (1 << 20), "big": b"z" * ((1 << 20) + 1), "run.sh": b"#!/bin/sh\n"}
    repo = make_repo(tmp_path / "r", files)
    os.chmod(repo / "run.sh", 0o755)
    os.symlink("small", repo / "link")
    commit(repo)
    add_gitlink(repo, "sub")
    root = str(repo)
    entries = {e.path: e for e in git.tracked(root)}
    assert git.blob(root, entries["small"]) == b"abc"
    assert git.blob(root, entries["exact"]) == b"y" * (1 << 20)
    assert git.blob(root, entries["run.sh"]) == b"#!/bin/sh\n"
    assert git.blob(root, entries["big"]) is None
    assert git.blob(root, entries["link"]) is None
    assert git.blob(root, entries["sub"]) is None
    assert git.blob(root, entries["small"]._replace(stage=2)) is None
    assert git.blob(root, git.Entry("100644", "0" * 40, 0, "missing")) is None
    assert git.blob(str(tmp_path / "nowhere"), entries["small"]) is None


# --- render() ----------------------------------------------------------------

PIN = "0123456789abcdef0123456789abcdef01234567"
CALLER = (
    "name: CI\n"
    "permissions:\n"
    "  contents: read\n"
    "jobs:\n"
    "@@job@@   @@job_id@@:\n"
    "@@job@@     uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-@@job_language@@.yml@" + PIN + "\n"
    "@@job@@     with:\n"
    '@@job@@       directory: "@@job_directory@@"\n'
)
AGENTS = (
    "# @@project_name@@\n"
    "\n"
    "- Languages: @@languages@@\n"
    "@@go@@ - Go: go test ./...\n"
    "@@js@@ - JS: bun test\n"
    "@@python@@ - Python: uv run pytest\n"
    "@@ruby@@ - Ruby: bundle exec rake\n"
    "@@rust@@ - Rust: cargo test --workspace\n"
    "@@none@@ - No language markers found.\n"
    "end\n"
)
GO = detect.Component("go", ".", "go", ("go.mod",))
WEB = detect.Component("js", "web", "js-web", ("web/package.json",))


def test_render_repeats_the_job_block_per_component():
    assert seed.render(CALLER, [GO, WEB], "p") == (
        "name: CI\n"
        "permissions:\n"
        "  contents: read\n"
        "jobs:\n"
        "  go:\n"
        "    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@" + PIN + "\n"
        "    with:\n"
        '      directory: "."\n'
        "  js-web:\n"
        "    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-js.yml@" + PIN + "\n"
        "    with:\n"
        '      directory: "web"\n'
    )


def test_render_gathers_the_job_lines_where_the_first_stood():
    assert (
        seed.render("jobs:\n@@job@@ - @@job_id@@\nmiddle\n@@job@@   end\n", [GO], "p") == "jobs:\n- go\n  end\nmiddle\n"
    )


def test_render_keeps_tagged_lines_for_present_languages():
    assert seed.render(AGENTS, [GO, WEB], "proj") == (
        "# proj\n\n- Languages: go, js in web/\n- Go: go test ./...\n- JS: bun test\nend\n"
    )


def test_render_keeps_the_none_line_only_without_components():
    assert seed.render(AGENTS, [], "proj") == "# proj\n\n- Languages: none\n- No language markers found.\nend\n"


@pytest.mark.parametrize(
    "count, suffix",
    [
        (10, ""),
        (11, ", and 1 more; see .github/workflows/ci.yml"),
        (12, ", and 2 more; see .github/workflows/ci.yml"),
    ],
)
def test_render_caps_the_languages_line_at_ten_components(count, suffix):
    comps = [detect.Component("go", "d%02d" % i, "go-d%02d" % i, ("d%02d/go.mod" % i,)) for i in range(count)]
    first_ten = ", ".join("go in d%02d/" % i for i in range(min(count, 10)))
    assert seed.render("@@languages@@", comps, "p") == first_ten + suffix


def test_render_values_are_literal():
    name = r"we&ird\name \1 \g<0> {0} %s @@languages@@ @@job_id@@ @@"
    assert seed.render("# @@project_name@@\n@@languages@@\n", [GO], name) == "# " + name + "\ngo\n"


def test_render_strips_crs():
    assert seed.render("a\r\n@@go@@ b\r\n@@js@@ c\r\n", [GO], "p") == "a\nb\n"


@pytest.mark.parametrize(
    "tpl", ["@@unknown@@\n", "@@job_id@@ outside the block\n", "@@java@@ - Java\n", "a @@languages\n"]
)
def test_render_raises_when_a_placeholder_is_left(tpl):
    with pytest.raises(cli.BwError):
        seed.render(tpl, [GO], "p")


def test_render_never_renders_a_zero_job_caller():
    with pytest.raises(cli.BwError):
        seed.render(CALLER, [], "p")


# --- stamps and hashes -------------------------------------------------------


def test_stamp_forms():
    md = seed.stamp("md", "AGENTS.md", "0123456789ab", "unknown")
    assert md == "<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789ab plugin=unknown -->"
    yml = seed.stamp("yml", "ci-caller.yml", "0123456789ab", "abcdef012345")
    assert yml == "# bytewyrd:scaffold v1 tpl=ci-caller.yml:0123456789ab plugin=abcdef012345"


@pytest.mark.parametrize(
    "args",
    [
        ("txt", "a", "0123456789ab", "unknown"),
        ("md", "a b", "0123456789ab", "unknown"),
        ("md", "a", "0123456789a", "unknown"),
        ("md", "a", "0123456789ab", "UNKNOWN"),
    ],
)
def test_stamp_refuses_what_read_stamp_could_not_parse(args):
    with pytest.raises(ValueError):
        seed.stamp(*args)


@pytest.mark.parametrize("kind", ["md", "yml"])
@pytest.mark.parametrize("newline", ["\n", "\r\n"])
def test_read_stamp_round_trips(tmp_path, kind, newline):
    path = tmp_path / "f"
    line = seed.stamp(kind, "PULL_REQUEST_TEMPLATE.md", "abcdef012345", "unknown")
    path.write_bytes((line + newline + "body" + newline).encode())
    assert seed.read_stamp(str(path)) == ("PULL_REQUEST_TEMPLATE.md", "abcdef012345", "unknown")


@pytest.mark.parametrize(
    "first, want",
    [
        ("", None),
        ("# bootstrap-content-version: bytewyrd/CLAUDE.md@0:0", None),
        ("# just a heading", None),
        ("<!-- bytewyrd:scaffold v2 tpl=AGENTS.md:0123456789ab plugin=unknown -->", seed.BAD),
        ("<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789a plugin=unknown -->", seed.BAD),
        ("<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789ab plugin=unknown --> x", seed.BAD),
        ("# bytewyrd:scaffold v1 tpl=ci.yml:0123456789ab", seed.BAD),
        ("x bytewyrd:scaffold", seed.BAD),
    ],
)
def test_read_stamp_none_and_bad(tmp_path, first, want):
    path = tmp_path / "f"
    path.write_text(first + "\nsecond line # bytewyrd:scaffold v1 tpl=a:0123456789ab plugin=unknown\n")
    assert seed.read_stamp(str(path)) is want


def test_bad_is_a_named_singleton():
    assert repr(seed.BAD) == "BAD" and seed.BAD is not None


def test_file_hash_ignores_crs(tmp_path):
    (tmp_path / "lf").write_bytes(b"line1\nline2\n")
    (tmp_path / "crlf").write_bytes(b"line1\r\nline2\r\n")
    want = hashlib.sha256(b"line1\nline2\n").hexdigest()[:12]
    assert seed.file_hash(str(tmp_path / "lf")) == seed.file_hash(str(tmp_path / "crlf")) == want
    (tmp_path / "abc").write_bytes(b"abc")
    assert seed.file_hash(str(tmp_path / "abc")) == "ba7816bf8f01"  # sha256("abc")


def test_plugin_sha_from_a_cache_directory_name(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    cases = [
        ("a" * 40, "a" * 12),
        ("0123456789ab", "0123456789ab"),
        ("0123456789a", "unknown"),
        ("0123456789AB", "unknown"),
        ("a" * 41, "unknown"),
        ("plugin", "unknown"),
    ]
    # Each case gets its own parent directory: on a case-insensitive file system
    # (macOS's default APFS), 0123456789ab and 0123456789AB are one name.
    for i, (name, want) in enumerate(cases):
        path = tmp_path / str(i) / name
        path.mkdir(parents=True)
        assert seed.plugin_sha(str(path)) == want, name


def test_plugin_sha_from_a_git_checkout(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    repo = make_repo(tmp_path / "plugin", {"sub/x": "1"})
    head = run_git(repo, "rev-parse", "HEAD").decode().strip()
    assert seed.plugin_sha(str(repo)) == head[:12]
    assert seed.plugin_sha(str(repo / "sub")) == "unknown"  # not the checkout's top level
    (tmp_path / "fresh").mkdir()
    run_git(tmp_path / "fresh", "init", "-q")
    assert seed.plugin_sha(str(tmp_path / "fresh")) == "unknown"  # no commit yet


# --- root() and project_name() -----------------------------------------------


def test_root_from_a_subdirectory(tmp_path, monkeypatch):
    repo = make_repo(tmp_path / "r", {"a/b/x": ""})
    monkeypatch.chdir(repo / "a" / "b")
    assert os.path.realpath(git.root()) == os.path.realpath(repo)


def test_root_outside_a_work_tree_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    (tmp_path / "plain").mkdir()
    monkeypatch.chdir(tmp_path / "plain")
    with pytest.raises(cli.BwError, match="not inside a git work tree"):
        git.root()
    repo = make_repo(tmp_path / "r", {})
    monkeypatch.chdir(repo / ".git")
    with pytest.raises(cli.BwError, match="not inside a git work tree"):
        git.root()


def test_root_without_git_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    with pytest.raises(cli.BwError, match="cannot run git"):
        git.root()


def test_project_name(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    repo = make_repo(tmp_path / "we&ird\\name", {})
    assert git.project_name(str(repo)) == "we&ird\\name"
    # The parent of the common git dir names the project, wherever ROOT is.
    (tmp_path / "proj").mkdir()
    run_git(
        tmp_path, "init", "-q", "--separate-git-dir", str(tmp_path / "proj" / "store.git"), str(tmp_path / "checkout")
    )
    assert git.project_name(str(tmp_path / "checkout")) == "proj"
    (tmp_path / "plain").mkdir()
    assert git.project_name(str(tmp_path / "plain")) == "plain"


# --- files -------------------------------------------------------------------


def test_exists(tmp_path):
    d = str(tmp_path)
    (tmp_path / "agents.md").write_text("x")
    os.symlink("nowhere", tmp_path / "CLAUDE.md")
    (tmp_path / "README.md").mkdir()
    assert fs.exists(d, "AGENTS.md")  # a case variant
    assert fs.exists(d, "CLAUDE.md")  # a dangling symlink
    assert fs.exists(d, "README.md")  # a directory
    assert not fs.exists(d, "OTHER.md")
    assert not fs.exists(str(tmp_path / "missing"), "AGENTS.md")


@pytest.mark.parametrize(
    "rel, found",
    [
        ("pull_request_template.md", "pull_request_template.md"),
        ("docs/PULL_REQUEST_TEMPLATE.md", "docs/PULL_REQUEST_TEMPLATE.md"),
        (".github/Pull_Request_Template.txt", ".github/Pull_Request_Template.txt"),
        (".github/PULL_REQUEST_TEMPLATE/feature.md", ".github/PULL_REQUEST_TEMPLATE"),
    ],
)
def test_pr_template_finds(tmp_path, rel, found):
    write(tmp_path, rel, "x")
    assert seed.pr_template(str(tmp_path)) == found


def test_pr_template_ignores_other_names_and_places(tmp_path):
    for rel in (
        "pull_request_template",  # a file: only a directory may have the bare name
        "src/pull_request_template.md",
        ".github/pull-request-template.md",
        "docs/pull_request_templates.md",
    ):
        write(tmp_path, rel, "x")
    assert seed.pr_template(str(tmp_path)) is None


def test_pr_template_looks_in_root_then_docs_then_github(tmp_path):
    write(tmp_path, ".github/pull_request_template.md", "x")
    write(tmp_path, "docs/pull_request_template.md", "x")
    assert seed.pr_template(str(tmp_path)) == "docs/pull_request_template.md"
    write(tmp_path, "PULL_REQUEST_TEMPLATE.md", "x")
    assert seed.pr_template(str(tmp_path)) == "PULL_REQUEST_TEMPLATE.md"


def test_symlinked_dir(tmp_path):
    root = str(tmp_path)
    assert fs.symlinked_dir(root, ".github/workflows/ci.yml") is None
    assert fs.symlinked_dir(root, "AGENTS.md") is None
    (tmp_path / "outside").mkdir()
    os.symlink(tmp_path / "outside", tmp_path / ".github")
    assert fs.symlinked_dir(root, ".github/workflows/ci.yml") == ".github"
    os.unlink(tmp_path / ".github")
    (tmp_path / ".github").mkdir()
    os.symlink(tmp_path / "outside", tmp_path / ".github" / "workflows")
    assert fs.symlinked_dir(root, ".github/workflows/ci.yml") == ".github/workflows"
    assert fs.symlinked_dir(root, ".github/PULL_REQUEST_TEMPLATE.md") is None


def test_create_writes_lf_text(tmp_path):
    fs.create(str(tmp_path / "f"), "a\nb\n")
    assert (tmp_path / "f").read_bytes() == b"a\nb\n"


def test_create_never_writes_over_or_through_anything(tmp_path):
    (tmp_path / "file").write_text("keep")
    os.symlink(tmp_path / "target", tmp_path / "dangling")
    (tmp_path / "dir").mkdir()
    for name in ("file", "dangling", "dir"):
        with pytest.raises(FileExistsError):
            fs.create(str(tmp_path / name), "new")
    assert (tmp_path / "file").read_text() == "keep"
    assert not os.path.lexists(tmp_path / "target")


def test_create_leaves_nothing_when_the_write_fails(tmp_path):
    with pytest.raises(UnicodeEncodeError):
        fs.create(str(tmp_path / "f"), "x\ud800")
    assert not os.path.lexists(tmp_path / "f")


def test_parser_usage_errors_exit_1(capsys):
    parser = cli.Parser(prog="bw x")
    parser.add_argument("--flag", action="store_true")
    with pytest.raises(SystemExit) as e:
        parser.parse_args(["--nope"])
    assert e.value.code == 1
    err = capsys.readouterr().err
    assert err == "usage: bw x [-h] [--flag]\nbw x: error: unrecognized arguments: --nope\n"


def test_skip_fix_lines():
    path = "a b/go.mod"
    mark = ", or mark the manifest: " + detect.attr_line(path)
    assert detect.skip_fix(path, detect.REASON_NAME) == "rename the directory" + mark
    assert detect.skip_fix(path, detect.reason_taken("go-a-b", "a.b")) == "rename the directory" + mark
    assert detect.skip_fix(path, detect.REASON_RAKEFILE) == "add a Rakefile whose default task runs the tests" + mark
    assert detect.skip_fix(path, detect.REASON_PYPROJECT) == "add a pyproject.toml with a [project] table" + mark
    assert (
        detect.skip_fix(path, detect.REASON_VALUE) == "set bytewyrd-ci or -bytewyrd-ci for this path in .gitattributes"
    )
    assert detect.skip_fix(path, detect.REASON_OPTED_OUT) is None


def test_reason_taken_quotes_its_values():
    assert detect.reason_taken("go-a-b", "a.b") == "job id go-a-b is taken by a.b"


# --- state-touch -------------------------------------------------------------


def test_state_touch_writes_where_it_opened_even_after_a_swap(tmp_path, monkeypatch):
    repo, outside = tmp_path / "repo", tmp_path / "outside"
    repo.mkdir()
    outside.mkdir()
    monkeypatch.chdir(repo)
    opened = state_touch.open_state_dir

    def open_then_swap():
        fd = opened()
        os.rename(".bytewyrd", "moved")
        os.symlink(outside, ".bytewyrd")
        return fd

    monkeypatch.setattr(state_touch, "open_state_dir", open_then_swap)
    assert state_touch.main(["last-feature-engineer-stop"]) == 0
    assert list(outside.iterdir()) == []
    assert sorted(p.name for p in (repo / "moved").iterdir()) == [".gitignore", "last-feature-engineer-stop"]

    # --rm after a swap removes from the directory it opened, not the outside one.
    os.unlink(repo / ".bytewyrd")
    os.rename(repo / "moved", repo / ".bytewyrd")
    (outside / "last-feature-engineer-stop").write_text("keep")
    assert state_touch.main(["--rm", "last-feature-engineer-stop"]) == 0
    assert (outside / "last-feature-engineer-stop").read_text() == "keep"
    assert sorted(p.name for p in (repo / "moved").iterdir()) == [".gitignore"]


@pytest.mark.parametrize("error", [RuntimeError("boom"), OSError(5, "Input/output error"), KeyboardInterrupt()])
def test_state_touch_always_exits_0(error, monkeypatch, capsys):
    def fail(argv):
        raise error

    monkeypatch.setattr(state_touch, "run", fail)
    assert state_touch.main(["x"]) == 0
    assert capsys.readouterr().err.count("\n") == 1


# --- compact-reminder --------------------------------------------------------


def test_compact_reminder_text():
    # hooks/hooks.json's compact reminder at ae97f77, asking the user to run
    # /docs-review instead of "Consider running /docs-review" [R77].
    assert compact_reminder.TEXT == (
        "Post-compact reminder: a feature-engineer agent finished in the last 24 hours and "
        "/docs-review may not yet have run. Ask the user to run /docs-review against the implemented files."
    )


def test_compact_reminder_prints_only_while_the_sentinel_is_under_a_day_old(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    remind = compact_reminder.TEXT + "\n"
    assert compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")
    (tmp_path / ".bytewyrd").mkdir()
    sentinel = tmp_path / ".bytewyrd" / "last-feature-engineer-stop"
    sentinel.touch()
    for age, want in [(0, remind), (86000, remind), (86401, ""), (-60, remind)]:
        mtime = time.time() - age
        os.utime(sentinel, (mtime, mtime))
        assert compact_reminder.main([]) == 0
        assert capsys.readouterr() == (want, ""), age
    sentinel.unlink()
    (tmp_path / "fresh").touch()
    os.symlink(tmp_path / "fresh", sentinel)  # never a sentinel state-touch wrote
    assert compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")
    sentinel.unlink()
    sentinel.mkdir()
    assert compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")


def test_compact_reminder_always_exits_0(monkeypatch, capsys):
    monkeypatch.setattr(compact_reminder, "due", lambda: 1 / 0)
    assert compact_reminder.main([]) == 0
    assert compact_reminder.main(["--bogus"]) == 0
    assert "usage: bw compact-reminder" in capsys.readouterr().err


# --- seed targets ------------------------------------------------------------

ROOT_TEMPLATES = REPO / "templates" / "scaffold"
IS_ROOT = hasattr(os, "geteuid") and os.geteuid() == 0


def test_targets_and_their_templates():
    assert [t.path for t in seed.TARGETS] == [
        "AGENTS.md",
        "CLAUDE.md",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/workflows/ci.yml",
    ]
    assert [seed.template_for(t, []) for t in seed.TARGETS] == list(seed.TEMPLATES[:3]) + ["ci-noop.yml"]
    assert seed.template_for(seed.CI_YML, [GO]) == "ci-caller.yml"
    for name in seed.TEMPLATES:
        text, digest = seed.read_template(name)
        assert digest == seed.file_hash(str(ROOT_TEMPLATES / (name + ".tpl")))
        assert "\r" not in text and "CLAUDE_PLUGIN_ROOT" not in text


def test_fits_takes_only_templates_of_the_target_s_kind():
    assert seed.fits(seed.CLAUDE_MD, "AGENTS.md")  # a CLAUDE.md that is a symlink to AGENTS.md
    assert seed.fits(seed.CI_YML, "ci-noop.yml") and seed.fits(seed.CI_YML, "ci-caller.yml")
    assert not seed.fits(seed.CI_YML, "AGENTS.md")
    assert not seed.fits(seed.AGENTS_MD, "ci-caller.yml")
    assert not seed.fits(seed.AGENTS_MD, "README.md")


def test_read_template_raises_bw_error(tmp_path, monkeypatch):
    monkeypatch.setattr(seed, "TEMPLATE_DIR", str(tmp_path))
    with pytest.raises(cli.BwError, match=r"^cannot read template AGENTS\.md: No such file"):
        seed.read_template("AGENTS.md")
    (tmp_path / "AGENTS.md.tpl").write_bytes(b"\xff")
    with pytest.raises(cli.BwError, match=r"^cannot read template AGENTS\.md: UnicodeDecodeError"):
        seed.read_template("AGENTS.md")


CALLER_PIN_LINE = (
    r"^@@job@@     uses: bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-@@job_language@@\.yml@([0-9a-f]{40})$"
)


def test_the_caller_template_has_one_uses_line_of_the_pinned_shape():
    # The same shape as the history job's pin checks (B4).
    text = (ROOT_TEMPLATES / "ci-caller.yml.tpl").read_text()
    assert text.count("uses:") == 1
    assert len(re.findall(CALLER_PIN_LINE, text, re.M)) == 1


def test_the_noop_fixture_workflow_is_the_noop_render_from_line_2():
    # AC-8; consumer-sim's S22 checks the same through scaffold itself.
    fixture = (REPO / ".github" / "workflows" / "scaffold-noop-fixture.yml").read_text()
    text, _ = seed.read_template("ci-noop.yml")
    assert fixture.split("\n", 1)[1] == seed.render(text, [], "any")


def test_find_entry(tmp_path):
    d = str(tmp_path)
    (tmp_path / "b.md").write_text("x")
    os.symlink("nowhere", tmp_path / "CLAUDE.md")
    assert fs.find_entry(d, "b.md") == "b.md"
    assert fs.find_entry(d, "B.MD") in ("b.md", "B.MD")  # B.MD on a case-insensitive filesystem
    assert fs.find_entry(d, "CLAUDE.md") == "CLAUDE.md"  # a dangling symlink
    assert fs.find_entry(d, "other.md") is None
    assert fs.find_entry(str(tmp_path / "missing"), "b.md") is None


def test_read_text_strips_crs_and_keeps_undecodable_bytes(tmp_path):
    (tmp_path / "f").write_bytes(b"a\r\nb\xff\r\n")
    os.symlink("f", tmp_path / "link")
    for name in ("f", "link"):
        assert fs.read_text(str(tmp_path / name)) == "a\nb\udcff\n"
    (tmp_path / "exact").write_bytes(b"y" * fs.MAX_TEXT)
    assert len(fs.read_text(str(tmp_path / "exact"))) == fs.MAX_TEXT


def test_read_text_never_reads_what_is_not_a_regular_file(tmp_path):
    (tmp_path / "dir").mkdir()
    os.mkfifo(tmp_path / "fifo")
    os.symlink("/dev/zero", tmp_path / "zero")
    os.symlink("missing", tmp_path / "dangling")
    os.symlink("loop", tmp_path / "loop")
    (tmp_path / "big").write_bytes(b"x" * (fs.MAX_TEXT + 1))
    (tmp_path / "file").write_text("x")
    for name in ("dir", "fifo", "zero", "dangling", "loop", "big", "absent", "file/below"):
        assert fs.read_text(str(tmp_path / name)) is None, name


@pytest.mark.skipif(IS_ROOT, reason="root reads any file")
def test_read_text_raises_for_other_errors(tmp_path):
    path = tmp_path / "f"
    path.write_text("x")
    path.chmod(0)
    try:
        with pytest.raises(PermissionError):
            fs.read_text(str(path))
    finally:
        path.chmod(0o644)


def test_workflow_exists(tmp_path):
    root = str(tmp_path)
    assert not seed.workflow_exists(root)
    workflows = tmp_path / ".github" / "workflows"
    workflows.mkdir(parents=True)
    (workflows / "notes.txt").write_text("x")
    (workflows / "build.YML").write_text("x")  # *.yml and *.yaml as written
    assert not seed.workflow_exists(root)
    (workflows / "release.yaml").write_text("x")
    assert seed.workflow_exists(root)


def test_lacks_import(tmp_path):
    root = str(tmp_path)
    claude, agents = tmp_path / "CLAUDE.md", tmp_path / "AGENTS.md"
    assert not seed.lacks_import(root)  # no CLAUDE.md
    claude.write_bytes(b"<!-- stamp -->\r\n@AGENTS.md\r\n")
    assert not seed.lacks_import(root)
    claude.write_text("see @AGENTS.md\n  @AGENTS.md\n")
    assert seed.lacks_import(root)
    claude.unlink()
    agents.write_text("# x\n")
    os.symlink("AGENTS.md", claude)  # CLAUDE.md is AGENTS.md
    assert not seed.lacks_import(root)
    claude.unlink()
    agents.unlink()
    claude.write_text("# x\n")
    os.symlink("CLAUDE.md", agents)  # and the other way round
    assert not seed.lacks_import(root)
    agents.unlink()
    claude.unlink()
    claude.mkdir()
    assert not seed.lacks_import(root)


def test_dirty_leaves_the_index_alone(tmp_path):
    repo = make_repo(tmp_path / "r", {"a": "1"})
    root, index = str(repo), repo / ".git" / "index"
    assert not git.dirty(root)
    os.utime(repo / "a", (0, 0))  # a stat change that a refreshing git status would write back
    before = index.stat().st_mtime_ns, index.read_bytes()
    assert not git.dirty(root)
    assert (index.stat().st_mtime_ns, index.read_bytes()) == before
    write(repo, "b", "x")
    assert git.dirty(root)
    run_git(repo, "add", "b")
    assert git.dirty(root)


def test_dirty_raises_outside_a_repo(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    with pytest.raises(cli.BwError, match="git status failed"):
        git.dirty(str(tmp_path))


@pytest.mark.parametrize(
    "error, want",
    [
        (cli.BwError("not inside a git work tree"), "not inside a git work tree"),
        (PermissionError(13, "Permission denied", "/x/y"), "Permission denied: /x/y"),
        (OSError(5, "Input/output error"), "Input/output error"),
        (KeyError("k"), "KeyError: 'k'"),
        (KeyboardInterrupt(), "KeyboardInterrupt"),
        (cli.BwError("bad\nname"), '"bad\\nname"'),
    ],
)
def test_describe(error, want):
    assert cli.describe(error) == want


# --- JSON output (the class-B helpers) ---------------------------------------
# The helpers' outputs as jq printed them before their port, byte for byte.


@pytest.mark.parametrize(
    "value, want",
    [
        ({"error": "x"}, '{\n  "error": "x"\n}\n'),
        (
            {"appended": True, "file": "docs/rfc-braindump.md", "created_file": False},
            '{\n  "appended": true,\n  "file": "docs/rfc-braindump.md",\n  "created_file": false\n}\n',
        ),
        ({"entries": []}, '{\n  "entries": []\n}\n'),
        (
            {"markers": [{"line": 3, "text": "FEEDBACK: x"}]},
            '{\n  "markers": [\n    {\n      "line": 3,\n      "text": "FEEDBACK: x"\n    }\n  ]\n}\n',
        ),
        ({"rfcs": [], "warnings": ["a", "b"]}, '{\n  "rfcs": [],\n  "warnings": [\n    "a",\n    "b"\n  ]\n}\n'),
    ],
)
def test_jq_dumps_prints_what_jq_printed(value, want):
    assert jsonout.jq_dumps(value) == want


def test_jq_dumps_escapes_as_jq_does():
    # json's escapes, raw UTF-8, and \u007f for DEL, which json leaves raw.
    s = '"\\/\b\f\n\r\t\x00\x01\x1f\x7f é — 😀 \u2028'
    want = '"\\"\\\\/\\b\\f\\n\\r\\t\\u0000\\u0001\\u001f\\u007f é — 😀 \u2028"'
    assert jsonout.jq_dumps({"s": s}) == '{\n  "s": %s\n}\n' % want


def test_jq_dumps_matches_jq_itself(tmp_path):
    jq = shutil.which("jq")
    if jq is None:
        if os.environ.get("CI"):
            pytest.fail("jq is not on PATH, and CI must not skip")
        pytest.skip("jq is not on PATH")
    s = "".join(map(chr, range(0, 0xD800))) + "\ue000\ufffd\U0001f600\U0010ffff"
    (tmp_path / "s.txt").write_bytes(s.encode("utf-8"))
    program = "{s: $s, n: 12, t: true, f: false, l: [], o: {}, a: [{k: $s}, 1]}"
    want = subprocess.run(
        [jq, "-n", "--rawfile", "s", str(tmp_path / "s.txt"), program], capture_output=True, check=True
    )
    value = {"s": s, "n": 12, "t": True, "f": False, "l": [], "o": {}, "a": [{"k": s}, 1]}
    assert jsonout.jq_dumps(value).encode("utf-8") == want.stdout


def escaped(raw):
    """RAW as os.fsdecode() holds bytes that aren't UTF-8, in any locale."""
    return raw.decode("utf-8", "surrogateescape")


@pytest.mark.parametrize(
    "raw, want",
    [
        (b"caf\xe9", "caf\ufffd"),
        (b"caf\xe9 au lait", "caf\ufffd au lait"),
        (b"a\xffb\xfe", "a\ufffdb\ufffd"),
        (b"\xe2\x82", "\ufffd"),  # one sequence cut short: one U+FFFD
        (b"\xe2\x82A", "\ufffdA"),
        (b"caf\xc3\xa9 \xe9", "café \ufffd"),
    ],
)
def test_jq_string_decodes_escaped_bytes_with_u_fffd_as_jq_did(raw, want):
    assert jsonout.jq_string(escaped(raw)) == want


def test_jq_string_replaces_any_other_lone_surrogate():
    # As a YAML "\ud800" escape makes; os.fsdecode() never does.
    assert jsonout.jq_string("a\ud800b\udbff\udc00\udd00\udfff") == "a\ufffdb\ufffd\ufffd\ufffd\ufffd"


def test_jq_string_returns_valid_text_as_it_is():
    s = "plain é — 😀 \x00\x7f"
    assert jsonout.jq_string(s) is s


def test_jq_dumps_cleans_keys_and_nested_strings():
    value = {escaped(b"k\xe9"): [escaped(b"v\xe9"), {"x": "\ud800"}], "n": None}
    assert (
        jsonout.jq_dumps(value)
        == '{\n  "k\ufffd": [\n    "v\ufffd",\n    {\n      "x": "\ufffd"\n    }\n  ],\n  "n": null\n}\n'
    )


def test_emit_prints_on_stdout(capsysbinary):
    jsonout.emit({"a": "é\x7f", "b": escaped(b"caf\xe9")})
    assert capsysbinary.readouterr() == ('{\n  "a": "é\\u007f",\n  "b": "caf\ufffd"\n}\n'.encode(), b"")


def test_emit_writes_utf_8_to_a_stdout_of_another_encoding(monkeypatch):
    buffer = io.BytesIO()
    monkeypatch.setattr(sys, "stdout", io.TextIOWrapper(buffer, encoding="latin-1"))
    jsonout.emit({"a": "é — 😀"})
    assert buffer.getvalue() == '{\n  "a": "é — 😀"\n}\n'.encode("utf-8")


def test_emit_error(capsysbinary):
    # common.bats: .error is the argument, and there is no other key.
    jsonout.emit_error("something went wrong")
    assert capsysbinary.readouterr() == (b'{\n  "error": "something went wrong"\n}\n', b"")


def test_json_main_returns_the_command_s_exit_code(capsys):
    assert jsonout.json_main("x", lambda argv: len(argv), ["a", "b", "c"]) == 3
    assert capsys.readouterr() == ("", "")


@pytest.mark.parametrize(
    "error, message",
    [
        (PermissionError(13, "Permission denied", "docs/x.md"), "rfc-x: Permission denied: docs/x.md"),
        (ValueError("bad value"), "rfc-x: ValueError: bad value"),
        (cli.BwError("one line"), "rfc-x: one line"),
    ],
)
def test_json_main_prints_an_exception_as_a_json_error_with_exit_2(error, message, capsys):
    def run(argv):
        raise error

    assert jsonout.json_main("rfc-x", run, []) == 2
    out, err = capsys.readouterr()
    assert (json.loads(out), err) == ({"error": message}, "")


def test_json_main_lets_keyboard_interrupt_through():
    def run(argv):
        raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        jsonout.json_main("x", run, [])


def test_json_main_sends_a_failing_stdout_to_dev_null(tmp_path, monkeypatch):
    fd = os.open(tmp_path / "out", os.O_WRONLY | os.O_CREAT)

    class Broken:
        buffer = property(lambda self: self)

        def flush(self):
            pass

        def write(self, data):
            raise BrokenPipeError(32, "Broken pipe")

        def fileno(self):
            return fd

    monkeypatch.setattr(sys, "stdout", Broken())
    try:
        assert jsonout.json_main("x", lambda argv: jsonout.emit({}), []) == 2
        assert os.path.samestat(os.fstat(fd), os.stat(os.devnull))
    finally:
        os.close(fd)


def test_a_helper_with_stdout_closed_exits_2_without_a_traceback(tmp_path):
    cmd = [sys.executable, "-I", "-S", "-B", str(MAIN), "rfc-braindump-append"]
    proc = subprocess.run(cmd, cwd=tmp_path, stderr=subprocess.PIPE, preexec_fn=lambda: os.close(1))
    assert (proc.returncode, proc.stderr) == (2, b"")


@pytest.mark.parametrize(
    "data, want",
    [
        (b"", []),
        (b"\n", [b""]),
        (b"a", [b"a"]),
        (b"a\n", [b"a"]),
        (b"a\nb", [b"a", b"b"]),
        (b"a\n\n", [b"a", b""]),
        (b"a\r\n\0\n", [b"a\r", b"\0"]),
    ],
)
def test_split_lines_splits_as_awk_and_grep_read_lines(data, want):
    assert fs.split_lines(data) == want


@pytest.mark.parametrize("path", sorted(PACKAGE.rglob("*.py")), ids=lambda p: str(p.relative_to(PACKAGE)))
def test_each_module_compiles_without_a_warning(path):
    # Under the launcher's -B, every run compiles each module it imports, so
    # a warning, such as one for an invalid escape, would reach stderr.
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        compile(path.read_text(encoding="utf-8"), str(path), "exec")


def test_pwd_is_pwd_when_it_names_the_current_directory(tmp_path, monkeypatch):
    link = tmp_path / "link"
    link.symlink_to(tmp_path)
    monkeypatch.chdir(link)
    monkeypatch.setenv("PWD", str(link))
    assert fs.pwd() == str(link) != os.getcwd()


@pytest.mark.parametrize(
    "value", [None, "", "link", "{link}/", "{link}/.", "{tmp}/link/../link", "{tmp}//link", "{other}", "{tmp}/gone"]
)
def test_pwd_is_getcwd_otherwise(tmp_path, monkeypatch, value):
    (tmp_path / "link").symlink_to(tmp_path)
    (tmp_path / "other").mkdir()
    monkeypatch.chdir(tmp_path / "link")
    if value is None:
        monkeypatch.delenv("PWD", raising=False)
    else:
        link = str(tmp_path / "link")
        monkeypatch.setenv("PWD", value.format(tmp=tmp_path, link=link, other=tmp_path / "other"))
    assert fs.pwd() == os.getcwd()


def test_emit_available(capsysbinary):
    jsonout.emit_available("gh")
    assert capsysbinary.readouterr() == (b'{\n  "result": "available",\n  "name": "gh"\n}\n', b"")


def test_emit_missing(capsysbinary):
    jsonout.emit_missing("gh", "install gh first")
    want = b'{\n  "result": "missing",\n  "name": "gh",\n  "hint": "install gh first"\n}\n'
    assert capsysbinary.readouterr() == (want, b"")


def test_emit_unauth(capsysbinary):
    jsonout.emit_unauth("gh", "run gh auth login")
    want = b'{\n  "result": "unauthenticated",\n  "name": "gh",\n  "hint": "run gh auth login"\n}\n'
    assert capsysbinary.readouterr() == (want, b"")


# --- scaffold ----------------------------------------------------------------


def call(module, cwd, argv, monkeypatch, capsys):
    """Run MODULE's main(ARGV) in CWD; return (exit code, stdout, stderr)."""
    monkeypatch.chdir(cwd)
    code = module.main(list(argv))
    out, err = capsys.readouterr()
    return code, out, err


def fresh_repo(path):
    path.mkdir(parents=True)
    run_git(path, "init", "-q")
    return path


def header(repo):
    return "bytewyrd scaffold: " + cli.quote(os.path.realpath(repo))


def test_scaffold_dry_run_lists_the_targets_and_writes_nothing(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "r")
    assert call(scaffold, repo, [], monkeypatch, capsys) == (
        0,
        header(repo) + "\n"
        "would create  AGENTS.md\n"
        "would create  CLAUDE.md\n"
        "would create  .github/PULL_REQUEST_TEMPLATE.md\n"
        "would create  .github/workflows/ci.yml\n"
        "dry run: 4 to create, 0 skipped; re-run with --apply to write\n",
        "",
    )
    assert os.listdir(repo) == [".git"]


def test_scaffold_apply_writes_the_stamp_and_the_render(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "proj")
    code, out, err = call(scaffold, repo, ["--apply"], monkeypatch, capsys)
    assert (code, err) == (0, "")
    assert out.splitlines()[1:] == ["created  " + t.path for t in seed.TARGETS] + ["applied: 4 created, 0 skipped"]
    sha = seed.plugin_sha(seed.PLUGIN_DIR)
    for target in seed.TARGETS:
        name = seed.template_for(target, [])
        text, digest = seed.read_template(name)
        assert (repo / target.path).read_text() == seed.stamp(target.kind, name, digest, sha) + "\n" + seed.render(
            text, [], "proj"
        )
    assert (repo / "AGENTS.md").read_text().split("\n")[1] == "# proj"


def test_scaffold_skips_existing_targets_and_their_stand_ins(tmp_path, monkeypatch, capsys):
    files = {
        "agents.md": "mine\n",
        "CLAUDE.md": "@AGENTS.md\n",
        "docs/Pull_Request_Template.md": "x\n",
        ".github/workflows/build.yaml": "x\n",
    }
    repo = make_repo(tmp_path / "r", files)
    assert call(scaffold, repo, ["--apply"], monkeypatch, capsys) == (
        0,
        header(repo) + "\n"
        "skip  AGENTS.md  (exists; scaffold never overwrites)\n"
        "skip  CLAUDE.md  (exists; scaffold never overwrites)\n"
        "skip  .github/PULL_REQUEST_TEMPLATE.md  (pull request template found: docs/Pull_Request_Template.md)\n"
        "skip  .github/workflows/ci.yml  (another workflow exists)\n"
        "applied: 0 created, 4 skipped\n",
        "",
    )
    assert (repo / "agents.md").read_text() == "mine\n"


def test_scaffold_notes_a_claude_md_without_the_import(tmp_path, monkeypatch, capsys):
    repo = make_repo(tmp_path / "r", {"CLAUDE.md": "# mine\n"})
    code, out, err = call(scaffold, repo, ["--apply"], monkeypatch, capsys)
    assert (code, err) == (0, "")
    assert scaffold.NOTE_IMPORT in out.splitlines()
    assert (repo / "CLAUDE.md").read_text() == "# mine\n"


@pytest.mark.parametrize("argv", [[], ["--apply"]])
def test_scaffold_refuses_a_symlinked_directory_on_a_target_s_path(tmp_path, monkeypatch, capsys, argv):
    repo, outside = fresh_repo(tmp_path / "r"), tmp_path / "outside"
    outside.mkdir()
    (repo / ".github").mkdir()
    os.symlink(outside, repo / ".github" / "workflows")
    message = "scaffold: .github/workflows is a symlink; refusing to write through it\n"
    assert call(scaffold, repo, argv, monkeypatch, capsys) == (1, "", message)
    assert sorted(os.listdir(repo)) == [".git", ".github"] and os.listdir(outside) == []


def test_scaffold_apply_refuses_a_dirty_tree_unless_allowed(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "r")
    write(repo, "untracked", "x")
    assert call(scaffold, repo, ["--apply"], monkeypatch, capsys) == (3, "", scaffold.REFUSE_DIRTY + "\n")
    assert sorted(os.listdir(repo)) == [".git", "untracked"]
    code, out, err = call(scaffold, repo, [], monkeypatch, capsys)
    assert (code, err) == (0, "") and out.splitlines()[-2] == scaffold.NOTE_DIRTY
    code, out, err = call(scaffold, repo, ["--apply", "--allow-dirty"], monkeypatch, capsys)
    assert (code, err) == (0, "") and out.splitlines()[-1] == "applied: 4 created, 0 skipped"


def failing_create(monkeypatch, fail_on):
    real, calls = fs.create, []

    def create(path, text):
        calls.append(path)
        if len(calls) == fail_on:
            raise PermissionError(13, "Permission denied", path)
        real(path, text)

    monkeypatch.setattr(fs, "create", create)


def test_scaffold_removes_what_it_created_when_a_write_fails(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "r")
    failing_create(monkeypatch, fail_on=4)
    assert call(scaffold, repo, ["--apply"], monkeypatch, capsys) == (
        1,
        "",
        "scaffold: cannot create .github/workflows/ci.yml: Permission denied\n"
        "scaffold: failed; removed: AGENTS.md CLAUDE.md .github/PULL_REQUEST_TEMPLATE.md\n",
    )
    assert os.listdir(repo) == [".git"]  # .github/ and .github/workflows/, which it made, are gone too


def test_scaffold_lists_the_files_it_could_not_remove(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "r")
    failing_create(monkeypatch, fail_on=2)

    def unlink(path, *args, **kwargs):
        raise PermissionError(13, "Permission denied", path)

    with monkeypatch.context() as m:
        m.setattr(scaffold.os, "unlink", unlink)
        code, out, err = call(scaffold, repo, ["--apply"], monkeypatch, capsys)
    assert (code, out) == (1, "")
    assert err == (
        "scaffold: cannot create CLAUDE.md: Permission denied\n"
        "scaffold: failed; remove these, then re-run: rm -- AGENTS.md\n"
    )


def test_scaffold_reports_an_unexpected_error_in_one_line(tmp_path, monkeypatch, capsys):
    repo = fresh_repo(tmp_path / "r")
    monkeypatch.setattr(scaffold, "ci_notes", lambda *args: {}["boom"])
    assert call(scaffold, repo, ["--apply"], monkeypatch, capsys) == (1, "", "scaffold: KeyError: 'boom'\n")
    assert os.listdir(repo) == [".git"]


def check_usage_errors_and_outside_a_work_tree(module, prog, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    plain = tmp_path / "plain"
    plain.mkdir()
    assert call(module, plain, [], monkeypatch, capsys) == (1, "", prog + ": not inside a git work tree\n")
    code, out, err = call(module, plain, ["--nope"], monkeypatch, capsys)
    assert (code, out) == (1, "") and err.startswith("usage: bw " + prog)
    code, out, err = call(module, plain, ["--help"], monkeypatch, capsys)
    assert (code, err) == (0, "") and out.startswith("usage: bw " + prog)


def test_scaffold_usage_errors_and_outside_a_work_tree_exit_1(tmp_path, monkeypatch, capsys):
    check_usage_errors_and_outside_a_work_tree(scaffold, "scaffold", tmp_path, monkeypatch, capsys)


@pytest.mark.parametrize(
    "files, gives",
    [
        ({}, False),
        ({".ruby-version": "3.3.6\n"}, True),
        ({".ruby-version": " \n\t\n"}, False),
        ({".ruby-version": b"\xff3.3\n"}, False),  # not UTF-8: declares nothing
        ({".tool-versions": "nodejs 24.0.0\nruby 3.3.6\n"}, True),
        ({".tool-versions": "nodejs 24.0.0\n"}, False),
        ({".tool-versions": "  ruby 3.3.6\n"}, True),  # setup-ruby trims the file before splitting it
        ({".tool-versions": "x\n  ruby 3.3.6\n"}, False),
        ({"mise.toml": '[tools]\nruby = "3.3"  # pinned\n'}, True),
        ({"mise.toml": "[tools]\n  ruby='3.3'\n"}, True),
        ({"mise.toml": "[tools]\nruby = 3.3\n"}, False),
        ({".tool-versions": "nodejs 24\n", "mise.toml": 'ruby = "3.3"\n'}, False),  # the first file decides
    ],
)
def test_gives_ruby_version(tmp_path, files, gives):
    repo = make_repo(tmp_path / "r", {**{"app/" + k: v for k, v in files.items()}, "app/Gemfile": ""})
    by_path = {e.path: e for e in git.tracked(str(repo))}
    assert scaffold.gives_ruby_version(str(repo), by_path, "app") is gives


def test_lockfile_platforms():
    lock = (
        "GEM\n  remote: https://rubygems.org/\n  specs:\n    rake (13.2.1)\n\n"
        "PLATFORMS\n  arm64-darwin-24\n  x86_64-linux\n\nDEPENDENCIES\n  rake\n"
    )
    assert scaffold.lockfile_platforms(lock) == ["arm64-darwin-24", "x86_64-linux"]
    assert scaffold.lockfile_platforms("PLATFORMS\r\n  ruby\r\nDEPENDENCIES\n") == ["ruby"]
    assert scaffold.lockfile_platforms("GEM\n  specs:\n") is None


@pytest.mark.parametrize(
    "text, want",
    [
        ('[dependency-groups]\ndev = ["pytest>=8"]\n', True),
        ("[dependency-groups]\ntest = [\"PyTest[testing] ; python_version >= '3.11'\"]\n", True),
        ('[dependency-groups]\ndev = ["pytest-cov", {include-group = "x"}]\n', False),
        ('[project.optional-dependencies]\ntest = ["pytest"]\n', False),
        ('[dependency-groups]\ndev = "pytest"\n', False),
        ("[dependency-groups\n", False),
    ],
)
def test_lists_pytest(text, want):
    assert scaffold.lists_pytest(text) is want


def test_ci_notes(tmp_path):
    files = {
        "examples/x/go.mod": "",  # out of the default scope: no note at all
        "bad dir/go.mod": "",
        "py/pyproject.toml": PROJECT,
        "rb/Gemfile": "",
        "rb/Rakefile": "",
        "rb/Gemfile.lock": "PLATFORMS\n  arm64-darwin-24\n",
        "rb/pnpm-lock.yaml": "",
        "ok/Gemfile": "",
        "ok/Rakefile": "",
        "ok/.ruby-version": "3.3.6\n",
        "ok/Gemfile.lock": "PLATFORMS\n  ruby\n",
    }
    repo = str(make_repo(tmp_path / "r", files))
    comps, skipped = detect.detect(repo)
    assert scaffold.ci_notes(repo, comps, skipped) == [
        'note: no CI job for "bad dir/go.mod": ' + detect.REASON_NAME,
        scaffold.NOTE_PYTEST % "py/pyproject.toml",
        scaffold.NOTE_RUBY_VERSION % "rb",
        scaffold.NOTE_PLATFORM % "rb/Gemfile.lock",
        scaffold.NOTE_PNPM % "rb",
    ]


# --- drift -------------------------------------------------------------------


def run_drift(repo, monkeypatch, capsys, *argv):
    """drift's (exit code, stdout lines); stderr must be empty."""
    code, out, err = call(drift, repo, argv, monkeypatch, capsys)
    assert err == ""
    return code, out.splitlines()


def seeded(path, monkeypatch, capsys, files=None):
    """A repo with FILES committed, then scaffold's files applied and committed."""
    repo = make_repo(path, files or {})
    assert call(scaffold, repo, ["--apply"], monkeypatch, capsys)[0] == 0
    commit(repo)
    return repo


def codes(lines):
    """The (severity, path, code) of each coded finding line."""
    found = []
    for line in lines:
        m = re.match(r"(ok|info|warn|drift)  (.+?)  ([a-z-]+): ", line)
        if m:
            found.append(m.groups())
    return found


DRIFT_LINE = re.compile(r"(ok  |info  |warn  |drift  |  |result: )")


def check_drift_lines(lines):
    """Each line starts with a documented prefix and is printable ASCII, but
    for diff lines, whose text may be any printable UTF-8."""
    for line in lines:
        assert DRIFT_LINE.match(line), line
        assert all(ord(c) >= 0x20 and ord(c) != 0x7F for c in line), line


def test_drift_usage_errors_and_outside_a_work_tree_exit_1(tmp_path, monkeypatch, capsys):
    check_usage_errors_and_outside_a_work_tree(drift, "drift", tmp_path, monkeypatch, capsys)


def test_caller_pin_reads_the_template_s_one_pin():
    text = (ROOT_TEMPLATES / "ci-caller.yml.tpl").read_text()
    assert drift.caller_pin(text) == re.search(CALLER_PIN_LINE, text, re.M).group(1)
    line = next(x for x in text.split("\n") if "uses:" in x)
    shifted = text.replace(line, line.replace("@@job@@     ", "@@job@@ "))
    for bad in (text.replace(line + "\n", ""), text + line + "\n", shifted):
        with pytest.raises(cli.BwError, match="no single pinned"):
            drift.caller_pin(bad)


def test_drift_on_a_freshly_seeded_repo(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    assert run_drift(repo, monkeypatch, capsys) == (
        0,
        [
            "ok  AGENTS.md",
            "ok  CLAUDE.md",
            "ok  .github/PULL_REQUEST_TEMPLATE.md",
            "ok  .github/workflows/ci.yml",
            "result: 4 ok, 0 info, 0 warn, 0 drift (exit 0)",
        ],
    )


def test_drift_exits_1_when_a_check_raises(tmp_path, monkeypatch, capsys):
    # AC-11: an exception before the footer exits 1, with no partial output.
    repo = seeded(tmp_path / "r", monkeypatch, capsys)

    def boom(ctx):
        raise RuntimeError("boom")

    monkeypatch.setattr(drift, "check_legacy", boom)
    assert call(drift, repo, [], monkeypatch, capsys) == (1, "", "drift: RuntimeError: boom\n")


def test_drift_exits_1_for_an_unreadable_template(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    monkeypatch.setattr(seed, "TEMPLATE_DIR", str(tmp_path / "nowhere"))
    code, out, err = call(drift, repo, [], monkeypatch, capsys)
    assert (code, out) == (1, "") and err.startswith("drift: cannot read template AGENTS.md: No such file")


def test_drift_reports_missing_targets(tmp_path, monkeypatch, capsys):
    repo = make_repo(tmp_path / "r", {})
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0
    assert lines == [
        "warn  AGENTS.md  missing: " + drift.MISSING["AGENTS.md"],
        "  fix: run scaffold --apply",
        "warn  CLAUDE.md  missing: " + drift.MISSING["CLAUDE.md"],
        "  fix: run scaffold --apply",
        "warn  .github/PULL_REQUEST_TEMPLATE.md  missing: " + drift.MISSING[".github/PULL_REQUEST_TEMPLATE.md"],
        "  fix: run scaffold --apply",
        "warn  .github/workflows/ci.yml  missing: " + drift.MISSING[".github/workflows/ci.yml"],
        "  fix: run scaffold --apply",
        "result: 0 ok, 0 info, 4 warn, 0 drift (exit 0)",
    ]
    assert run_drift(repo, monkeypatch, capsys, "--strict")[0] == 2
    write(repo, "docs/PULL_REQUEST_TEMPLATE/a.md", "x")
    write(repo, ".github/workflows/x.yml", "x")
    left = codes(run_drift(repo, monkeypatch, capsys)[1])
    assert left == [("warn", "AGENTS.md", "missing"), ("warn", "CLAUDE.md", "missing")]


def test_drift_template_changed_prints_the_diff_and_the_stamp_that_restores_0(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    templates = tmp_path / "templates"
    templates.mkdir()
    for name in seed.TEMPLATES:
        (templates / (name + ".tpl")).write_bytes((ROOT_TEMPLATES / (name + ".tpl")).read_bytes())
    tpl = templates / "AGENTS.md.tpl"
    tpl.write_text(tpl.read_text().replace("## Workflow", "## Working here") + "- One more line.\n")
    monkeypatch.setattr(seed, "TEMPLATE_DIR", str(templates))
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2
    i = lines.index(next(line for line in lines if line.startswith("drift  AGENTS.md  template-changed: ")))
    new = seed.stamp("md", "AGENTS.md", seed.file_hash(str(tpl)), seed.plugin_sha(seed.PLUGIN_DIR))
    assert lines[i + 1] == "  fix: apply the diff, then replace line 1 with: " + new
    assert lines[i + 2 : i + 4] == ["  --- a/AGENTS.md", "  +++ b/AGENTS.md"]
    body = lines[i + 4 : lines.index("ok  CLAUDE.md")]
    assert "  -## Workflow" in body and "  +## Working here" in body and "  +- One more line." in body
    check_drift_lines(lines)
    agents = repo / "AGENTS.md"
    agents.write_text(new + "\n" + agents.read_text().split("\n", 1)[1])
    assert run_drift(repo, monkeypatch, capsys)[0] == 0


@pytest.mark.parametrize(
    "first, detail",
    [
        ("<!-- bytewyrd:scaffold v2 tpl=AGENTS.md:0123456789ab plugin=unknown -->", "does not parse"),
        ("<!-- bytewyrd:scaffold v1 tpl=README.md:0123456789ab plugin=unknown -->", "names README.md"),
        ("<!-- bytewyrd:scaffold v1 tpl=ci-caller.yml:0123456789ab plugin=unknown -->", "names ci-caller.yml"),
    ],
)
def test_drift_bad_stamp(tmp_path, monkeypatch, capsys, first, detail):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    agents = repo / "AGENTS.md"
    agents.write_text(first + "\n" + agents.read_text().split("\n", 1)[1])
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2 and codes(lines) == [("drift", "AGENTS.md", "bad-stamp")]
    assert detail in lines[0]
    text, digest = seed.read_template("AGENTS.md")
    current = seed.stamp("md", "AGENTS.md", digest, seed.plugin_sha(seed.PLUGIN_DIR))
    assert lines[1] == "  fix: replace line 1 with: %s after reviewing the diff" % current
    assert lines[2] == "ok  CLAUDE.md"  # the body matches the render, so the diff is empty


def test_drift_bad_stamp_on_ci_yml_diffs_against_the_template_scaffold_picks(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys, {"go.mod": "module x\n"})
    ci = repo / ".github" / "workflows" / "ci.yml"
    first = "<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789ab plugin=unknown -->"
    ci.write_text(first + "\n" + ci.read_text().split("\n", 1)[1])
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2 and codes(lines) == [("drift", ".github/workflows/ci.yml", "bad-stamp")]
    assert "tpl=ci-caller.yml:" in lines[lines.index(next(x for x in lines if "bad-stamp" in x)) + 1]


def test_drift_unstamped_targets_are_info(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    (repo / "AGENTS.md").write_text("# my own\n")
    pr = repo / ".github" / "PULL_REQUEST_TEMPLATE.md"
    pr.unlink()
    pr.mkdir()
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0
    assert lines[0] == "info  AGENTS.md  unstamped: line 1 has no scaffold stamp, so drift compares it with no template"
    assert "info  .github/PULL_REQUEST_TEMPLATE.md  unstamped: not a regular file that drift can read" in lines


def test_drift_no_import(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    claude = repo / "CLAUDE.md"
    claude.write_text(claude.read_text().replace("@AGENTS.md\n", ""))
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2 and codes(lines) == [("drift", "CLAUDE.md", "no-import")]
    assert "  fix: add the line @AGENTS.md to CLAUDE.md" in lines
    claude.unlink()
    os.symlink("AGENTS.md", claude)  # CLAUDE.md is AGENTS.md: nothing to import, and its stamp is AGENTS.md's
    assert run_drift(repo, monkeypatch, capsys) == (
        0,
        [
            "ok  AGENTS.md",
            "ok  CLAUDE.md",
            "ok  .github/PULL_REQUEST_TEMPLATE.md",
            "ok  .github/workflows/ci.yml",
            "result: 4 ok, 0 info, 0 warn, 0 drift (exit 0)",
        ],
    )


@pytest.mark.parametrize("over", [None, "AGENTS.md", "CLAUDE.md"])
def test_drift_too_long_by_lines(tmp_path, monkeypatch, capsys, over):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    for name, limit in (("AGENTS.md", 100), ("CLAUDE.md", 200)):
        path = repo / name
        text = path.read_text()
        path.write_text(text + "x\n" * (limit - drift.line_count(text) + (name == over)))
        assert drift.line_count(path.read_text()) == limit + (name == over)
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0 and codes(lines) == ([] if over is None else [("warn", over, "too-long")])


def test_line_count():
    assert [drift.line_count(t) for t in ("", "a", "a\n", "a\nb", "a\n\n")] == [0, 1, 1, 2, 2]


def test_drift_too_long_by_characters(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    agents = repo / "AGENTS.md"
    text = agents.read_text()
    agents.write_text(text + "x" * (8000 - len(text)))
    assert codes(run_drift(repo, monkeypatch, capsys)[1]) == []
    agents.write_text(text + "x" * (8001 - len(text)))
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert codes(lines) == [("warn", "AGENTS.md", "too-long")] and "8001 characters" in lines[1]


@pytest.mark.parametrize(
    "line",
    [
        "<!-- bootstrap-content-version: bytewyrd/CLAUDE.md@6cbeb80b:61f9b5c01dba -->",
        "<!--bootstrap-content-version: x:0123456789ab -->",
        "# bootstrap-content-version: bytewyrd/mise.toml@ebf354bf:e3b0c44298fc",
        "#\tbootstrap-content-version: x",
        "<!-- Managed by the Bytewyrd plugin. /sync refreshes the plugin-owned sections -->",
        "<!-- Managed by the Bytewyrd plugin — do not customize. This file is overwritten on every /sync. -->",
        "<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project -->",
    ],
)
def test_legacy_lines_finds_the_0_2_headers_and_banners(line):
    for n in (1, 2, 3):
        assert drift.legacy_lines("\n" * (n - 1) + line + "\nbody\n") == [n]
    assert drift.legacy_lines("a\nb\nc\n" + line + "\n") == []  # line 4 is out of reach


@pytest.mark.parametrize(
    "line",
    [
        "# bytewyrd:scaffold v1 tpl=ci-noop.yml:0123456789ab plugin=unknown",
        "  <!-- bootstrap-content-version: indented -->",
        "<!-- managed by the Bytewyrd plugin -->",
        "Managed by the Bytewyrd plugin.",
        "# bytewyrd:base",
    ],
)
def test_legacy_lines_ignores_other_lines(line):
    assert drift.legacy_lines(line + "\n") == []


def test_drift_lists_every_0_2_artifact(tmp_path, monkeypatch, capsys):
    header = "<!-- bootstrap-content-version: bytewyrd/%s@1:0123456789ab -->\n"
    banner = "<!-- Bootstrapped by the Bytewyrd plugin. This file is now owned by this project -->\n"
    files = {
        "CLAUDE.md": header % "CLAUDE.md" + banner + "# app\n",
        ".github/PULL_REQUEST_TEMPLATE.md": header % "PR" + "## Summary\n",
        ".github/workflows/ci.yml": "# bootstrap-content-version: bytewyrd/ci.yml@1:0123456789ab\nname: CI\n",
        "README.md": '<div align="center">\n' + header % "README.md" + "</div>\n",
        "docs/ARCHITECTURE.md": banner + "# Architecture\n",
        "docs/BEST_PRACTICES.md": header % "BP" + banner + "## Pitfall\n",
        "docs/CONTRIBUTING.md": "# Contributing\n\n" + header % "C",
        "mise.toml": "# bootstrap-content-version: bytewyrd/mise.toml@1:0123456789ab\n[tools]\n",
        ".gitignore": "# bootstrap-content-version: x@1:0123456789ab\n# bytewyrd:base\n.x/\n\n# bytewyrd:js\n",
        "docs/rfc-process.md": "# RFC Process\n",
        ".claude/settings.json": '{"hooks": {"Stop": [{"hooks": [{"command": "echo Consider running /sync"}]}]}}\n',
        ".bytewyrd/.bootstrap-versions.json": "{}\n",
        ".claude/.bootstrap-versions.json": "{}\n",
        ".bytewyrd/plugin-version": "0.2.0\n",
    }
    repo = make_repo(tmp_path / "r", files)
    os.symlink("nowhere", repo / ".bytewyrd" / "docs-agent-version")  # a dangling one counts too
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2
    assert codes(lines) == [
        ("warn", "AGENTS.md", "missing"),
        ("drift", "CLAUDE.md", "legacy-header"),
        ("drift", ".github/PULL_REQUEST_TEMPLATE.md", "legacy-header"),
        ("drift", ".github/workflows/ci.yml", "legacy-header"),
        ("drift", "README.md", "legacy-header"),
        ("drift", "docs/ARCHITECTURE.md", "legacy-header"),
        ("drift", "docs/BEST_PRACTICES.md", "legacy-header"),
        ("drift", "docs/CONTRIBUTING.md", "legacy-header"),
        ("drift", "mise.toml", "legacy-header"),
        ("drift", ".gitignore", "legacy-gitignore"),
        ("drift", "docs/rfc-process.md", "legacy-rfc-process-copy"),
        ("drift", ".claude/settings.json", "legacy-settings-hooks"),
        ("drift", ".bytewyrd/.bootstrap-versions.json", "legacy-sidecar"),
        ("drift", ".claude/.bootstrap-versions.json", "legacy-sidecar"),
        ("drift", ".bytewyrd/plugin-version", "legacy-state"),
        ("drift", ".bytewyrd/docs-agent-version", "legacy-state"),
    ]
    check_drift_lines(lines)
    text = "\n".join(lines)
    assert "legacy-header: a 0.2.x /sync header or banner on lines 1 and 2" in text
    assert "README.md  legacy-header: a 0.2.x /sync header or banner on line 2" in text
    assert "  fix: delete line 1 so the repo's own file stays; drift then reports it as unstamped" in text
    assert "legacy-gitignore: a 0.2.x /sync header or # bytewyrd: tag on lines 1, 2 and 5" in text
    assert "  fix: git mv CLAUDE.md CLAUDE.legacy.md; once every fix is committed, run scaffold --apply" in text


@pytest.mark.parametrize("marker", drift.SETTINGS_MARKERS)
def test_drift_settings_hooks_markers(tmp_path, monkeypatch, capsys, marker):
    repo = seeded(tmp_path / "r", monkeypatch, capsys, {".claude/settings.json": json.dumps({"x": "a " + marker})})
    assert codes(run_drift(repo, monkeypatch, capsys)[1]) == [
        ("drift", ".claude/settings.json", "legacy-settings-hooks")
    ]


def test_drift_ignores_a_settings_json_without_0_2_hooks(tmp_path, monkeypatch, capsys):
    settings = {"enabledPlugins": {"github@claude-plugins-official": True}, "extraKnownMarketplaces": {}}
    repo = seeded(tmp_path / "r", monkeypatch, capsys, {".claude/settings.json": json.dumps(settings)})
    assert run_drift(repo, monkeypatch, capsys)[0] == 0


# --- drift: caller checks ----------------------------------------------------


@pytest.mark.parametrize(
    "rest, want",
    [
        (" a/b@c", "a/b@c"),
        ('  "a/b@c"  ', "a/b@c"),
        (" 'a/b@c' # v1", "a/b@c"),
        (' "a/b@c"\t# v1', "a/b@c"),
        (" a#b", "a#b"),
        (" \"a'", "\"a'"),
        (' "', '"'),
        ("", ""),
    ],
)
def test_uses_value(rest, want):
    assert drift.uses_value(rest) == want


@pytest.mark.parametrize(
    "value, name",
    [
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@main", "lang-ci-go.yml"),
        ("evil/x/.github/workflows/lang-ci-go.yml@feature/x", "lang-ci-go.yml"),
        ("./.github/workflows/x.yml", "x.yml"),
        ("lang-ci.yml", "lang-ci.yml"),
    ],
)
def test_workflow_name(value, name):
    assert drift.workflow_name(value) == name


def test_job_blocks():
    lines = (
        "# stamp\nname: CI\non:\n  push:\njobs:\n"
        "  go:\n    uses: a\n\n# a note\n    with:\n"
        "  js-web: # comment\n    uses: b\n"
        "  - not: a job\n"
        "env:\n  ignored:\n    uses: c\n"
    ).split("\n")
    blocks = drift.job_blocks(lines)
    assert [(b.job_id, b.start, b.body) for b in blocks] == [("go", 5, (6, 7, 8, 9)), ("js-web", 10, (11, 12))]


@pytest.mark.parametrize(
    "value, language, want",
    [
        (PIN.replace("0", "1"), "go", None),
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@main", "ruby", "main"),
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@main", None, "main"),
        ("evil/x/.github/workflows/lang-ci-ruby.yml@main", "ruby", None),
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@" + PIN, "ruby", None),
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-java.yml@v1", None, "v1"),
        ("bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@a b", "ruby", '"a b"'),
    ],
)
def test_pin_fixes(value, language, want):
    pin = "f" * 40
    fixes = drift.pin_fixes(value, language, pin)
    named = language or re.search(r"lang-ci-(\w+)\.yml", value).group(1)
    assert fixes[-1] == "set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-%s.yml@%s" % (named, pin)
    if want is None:
        assert len(fixes) == 1
    else:
        assert fixes[0] == "review https://github.com/bytewyrd/claude-bytewyrd/compare/%s...%s" % (want, pin)


def test_pin_fixes_for_a_value_that_names_no_id():
    assert drift.pin_fixes("x/lang-ci.yml@v1", None, "f" * 40) == (
        "set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-<id>.yml@" + "f" * 40,
    )


def caller_repo(path, monkeypatch, capsys):
    """A seeded, committed repo with root go and ruby components, and its ci.yml path and pin."""
    repo = seeded(path, monkeypatch, capsys, {"go.mod": "module x\n", "Gemfile": "", "Rakefile": ""})
    ci = repo / ".github" / "workflows" / "ci.yml"
    return repo, ci, drift.caller_pin(seed.read_template("ci-caller.yml")[0])


def test_drift_pin_changed_one_finding_per_distinct_value_in_file_order(tmp_path, monkeypatch, capsys):
    repo, ci, pin = caller_repo(tmp_path / "r", monkeypatch, capsys)
    assert run_drift(repo, monkeypatch, capsys)[0] == 0
    good = ci.read_text()
    evil = "evil/x/.github/workflows/lang-ci-go.yml@main"
    ci.write_text(
        good.replace("lang-ci-go.yml@" + pin, "lang-ci-go.yml@main  # tag").replace(
            "lang-ci-ruby.yml@" + pin, "lang-ci-ruby.yml@main"
        )
        + "  extra:\n    uses: '%s'\n  more:\n    uses: %s\n" % (evil, evil)
        + "  mine:\n    uses: ./.github/workflows/mine.yml\n"
    )
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2
    pinned = [line for line in lines if "pin-changed" in line]
    finding = 'drift  .github/workflows/ci.yml  pin-changed: line %d uses "%s"'
    assert pinned == [
        finding % (12, "bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@main"),
        finding % (16, "bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@main"),
        finding % (20, evil),
    ]
    i = lines.index(pinned[0])
    assert lines[i + 1 : i + 3] == [
        "  fix: review https://github.com/bytewyrd/claude-bytewyrd/compare/main...%s" % pin,
        "  fix: set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@%s" % pin,
    ]
    j = lines.index(pinned[2])
    assert lines[j + 1] == "  fix: set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@%s" % pin
    check_drift_lines(lines)


def test_drift_pin_changed_for_a_component_job_without_uses(tmp_path, monkeypatch, capsys):
    repo, ci, pin = caller_repo(tmp_path / "r", monkeypatch, capsys)
    call_line = "    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@%s\n" % pin
    ci.write_text(ci.read_text().replace(call_line, ""))
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2
    i = lines.index("drift  .github/workflows/ci.yml  pin-changed: job ruby has no uses: line")
    assert lines[i + 1] == "  fix: set this uses: to " + call_line.strip()[len("uses: ") :]


def test_drift_finds_a_component_s_block_by_id_and_directory(tmp_path, monkeypatch, capsys):
    repo, ci, pin = caller_repo(tmp_path / "r", monkeypatch, capsys)
    good = ci.read_text()
    noted = good.replace("  ruby:\n", "  # the ruby job\n  ruby:  # ours\n")
    ci.write_text(noted.replace('directory: "."\n', 'directory: "." \n', 1))
    assert run_drift(repo, monkeypatch, capsys)[0] == 0  # comments and trailing blanks don't hide a block
    ci.write_text(good.replace('      directory: "."\n', '      directory: "./"\n', 1))
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0 and codes(lines) == [("warn", ".github/workflows/ci.yml", "ci-variant")]
    i = lines.index("warn  .github/workflows/ci.yml  ci-variant: no job block for go (job id go)")
    assert lines[i + 1 :] == [
        "  fix: add this job under jobs:, or mark the directory's manifests:",
        "  fix: /go.mod -bytewyrd-ci",
        "    go:",
        "      uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-go.yml@" + pin,
        "      with:",
        '        directory: "."',
        "result: 4 ok, 0 info, 1 warn, 0 drift (exit 0)",
    ]


def test_drift_ci_variant_when_the_components_change(tmp_path, monkeypatch, capsys):
    repo, ci, pin = caller_repo(tmp_path / "r", monkeypatch, capsys)
    run_git(repo, "rm", "-q", "go.mod", "Gemfile", "Rakefile")
    commit(repo, add_all=False)
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0
    assert lines[3:5] == [
        "warn  .github/workflows/ci.yml  ci-variant: the stamp names ci-caller.yml, and scaffold now picks ci-noop.yml"
        " for this repo's components",
        "  fix: " + drift.FIX_CI_VARIANT,
    ]
    assert run_drift(repo, monkeypatch, capsys, "--strict")[0] == 2


def test_drift_ci_skipped_appears_only_with_the_caller(tmp_path, monkeypatch, capsys):
    files = {"go.mod": "module x\n", "bad dir/go.mod": "", "web/package.json": "{}"}
    repo = seeded(tmp_path / "r", monkeypatch, capsys, {**files, ".gitattributes": "/web/package.json -bytewyrd-ci\n"})
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 0
    assert lines[4:8] == [
        'info  "bad dir/go.mod"  ci-skipped: ' + detect.REASON_NAME,
        '  fix: rename the directory, or mark the manifest: "/bad dir/go.mod" -bytewyrd-ci',
        "info  web/package.json  ci-skipped: opted out by -bytewyrd-ci",
        "result: 4 ok, 2 info, 0 warn, 0 drift (exit 0)",
    ]
    noop = seeded(tmp_path / "n", monkeypatch, capsys, {"bad dir/go.mod": ""})
    assert codes(run_drift(noop, monkeypatch, capsys)[1]) == []


def test_drift_quotes_diff_lines_with_control_characters(tmp_path, monkeypatch, capsys):
    repo = seeded(tmp_path / "r", monkeypatch, capsys)
    agents = repo / "AGENTS.md"
    body = agents.read_bytes().split(b"\n", 1)[1]
    odd = b"tab\there\nesc\x1b[2J\nlatin \xe9\nfine \xc3\xa9\n"
    agents.write_bytes(b"<!-- bytewyrd:scaffold v0 -->\n" + body + odd)
    code, lines = run_drift(repo, monkeypatch, capsys)
    assert code == 2
    assert '  -"tab\\there"' in lines
    assert '  -"esc\\033[2J"' in lines
    assert '  -"latin \\351"' in lines
    assert "  -fine é" in lines
    check_drift_lines(lines)
