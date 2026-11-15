"""Tests for scripts/_lib (RFC 2026-11-09-scaffold-and-drift, B2, B4 and B5):
bw.py's shared functions and detection, and the state-touch and
compact-reminder commands.

Detection cases build real throwaway git repositories, with the developer's
git configuration kept out (see hermetic_git).
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "scripts" / "_lib"
sys.path.insert(0, str(LIB))

import bw  # noqa: E402
import bw_compact_reminder  # noqa: E402
import bw_state_touch  # noqa: E402

# --- helpers -----------------------------------------------------------------


@pytest.fixture(autouse=True)
def hermetic_git(monkeypatch):
    """Keep the developer's git configuration and repository out of every git
    call, both the fixtures' and bw.py's."""
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")
    for var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        monkeypatch.delenv(var, raising=False)


def git(cwd, *args, input=None):
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
        git(repo, "add", "-A")
    git(repo, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-q", "--allow-empty", "-m", "x")


def make_repo(path, files, attributes=None):
    """A git repository at PATH with FILES ({path: content}) committed."""
    path.mkdir(parents=True)
    git(path, "init", "-q")
    for rel, content in files.items():
        write(path, rel, content)
    if attributes is not None:
        write(path, ".gitattributes", attributes)
    commit(path)
    return path


def add_gitlink(repo, path):
    """Add a gitlink (mode 160000) at PATH to REPO's index and commit it."""
    git(repo, "update-index", "--add", "--cacheinfo", "160000,%s,%s" % ("1" * 40, path))
    commit(repo, add_all=False)


def jobs(repo):
    return [c.job_id for c in bw.detect(str(repo))[0]]


def creatable(tmp_path, name):
    """True when this filesystem accepts NAME as a directory name."""
    try:
        path = os.path.join(os.fsencode(tmp_path), os.fsencode(name))
        os.mkdir(path)
        os.rmdir(path)
        return True
    except (OSError, UnicodeError):
        return False


PROJECT = "[project]\nname = \"x\"\nversion = \"0\"\n"
CRATE = "[package]\nname = \"x\"\nversion = \"0.1.0\"\n"

# --- ids and platform checks -------------------------------------------------


def test_language_ids_equal_the_lang_ci_workflow_files():
    names = sorted(p.name for p in (REPO / ".github" / "workflows").iterdir() if p.name.startswith("lang-ci"))
    ids = []
    for name in names:
        m = re.fullmatch(r"lang-ci-([a-z0-9]+)\.yml", name)
        assert m, "%s is not named lang-ci-<id>.yml" % name
        ids.append(m.group(1))
    assert ids == sorted(bw.LANGUAGES)


def test_language_ids_equal_the_lang_ci_fixture_jobs():
    lines = (REPO / ".github" / "workflows" / "ci.yml").read_text().splitlines()
    ids = [m.group(1) for m in (re.fullmatch(r"  lang-ci-fixture-([a-z0-9]+):", line) for line in lines) if m]
    assert sorted(ids) == sorted(bw.LANGUAGES)


def test_manifest_languages_are_language_ids():
    assert set(bw.MANIFESTS.values()) == set(bw.LANGUAGES)


def test_dir_fd_and_no_follow_calls_are_supported_here():
    # state-touch works through a directory descriptor; this runs on each CI platform.
    for fn in (os.open, os.mkdir, os.stat, os.utime, os.unlink):
        assert fn in os.supports_dir_fd, fn.__name__
    assert os.utime in os.supports_follow_symlinks


def test_plugin_dir_is_the_parent_of_scripts():
    assert Path(bw.PLUGIN_DIR) == REPO


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
    assert bw.quote(s) == want


def test_quote_output_is_ascii_without_control_characters():
    for s in ("\ud800", "é\udce9\x1b", " x", "".join(map(chr, range(0, 300)))):
        q = bw.quote(s)
        assert q.isascii() and all(0x20 <= ord(c) <= 0x7E for c in q), repr(q)


@pytest.mark.parametrize("name", ["tab\there", 'q"uote', "back\\slash", "esc\x1bx", "café", "del\x7f"])
def test_quote_escapes_like_git(tmp_path, name):
    if not creatable(tmp_path, name):
        pytest.skip("this filesystem refuses %r" % name)
    repo = make_repo(tmp_path / "r", {name: "x"})
    # core.quotePath, on by default, makes git C-quote these names the same way.
    assert git(repo, "ls-files").decode("ascii") == bw.quote(name) + "\n"


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
    assert bw.attr_line(path) == want


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
ATTR_DECOYS = ["go.mod", "svc/go.mod", "a1/go.mod", "stXr/go.mod", "qyx/go.mod", "x/go.mod", "bad/go.mod", "back/go.mod"]


def test_each_attr_line_opts_out_exactly_its_manifest(tmp_path):
    names = [n for n in ATTR_NAMES if creatable(tmp_path, n)]
    assert {"bad dir", "#x", "a[1]", "st*r", "back\\slash"} <= set(names)
    paths = [n + "/go.mod" for n in names]
    lines = "".join(bw.attr_line(p) + "\n" for p in paths)
    repo = make_repo(tmp_path / "r", {p: "module x\n" for p in paths + ATTR_DECOYS}, attributes=lines.encode("ascii"))
    stdin = b"".join(os.fsencode(p) + b"\0" for p in paths + ATTR_DECOYS)
    out = git(repo, "check-attr", "--cached", "--stdin", "-z", "bytewyrd-ci", input=stdin)
    fields = out.split(b"\0")
    got = {os.fsdecode(fields[i]): fields[i + 2].decode() for i in range(0, len(fields) - 2, 3)}
    assert got == {**{p: "unset" for p in paths}, **{p: "unspecified" for p in ATTR_DECOYS}}


def test_a_root_go_mod_attr_line_keeps_go_svc(tmp_path):
    # [R79]: an unanchored "go.mod -bytewyrd-ci" would unset svc/go.mod too.
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n", "svc/go.mod": "module y\n"})
    assert jobs(repo) == ["go", "go-svc"]
    write(repo, ".gitattributes", bw.attr_line("go.mod") + "\n")
    commit(repo)
    comps, skipped = bw.detect(str(repo))
    assert comps == [bw.Component("go", "svc", "go-svc", ("svc/go.mod",))]
    assert skipped == [("go.mod", bw.REASON_OPTED_OUT)]
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
    assert bw.dir_matches(pattern, directory) is want


def test_dir_matches_is_quick_on_many_double_stars():
    start = time.monotonic()
    assert not bw.dir_matches("/".join(["**"] * 400 + ["z"]), "/".join(["a"] * 60))
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
    comps, skipped = bw.detect(str(repo))
    assert [c.job_id for c in comps] == ["go-apps-api", "go-deep-one-two", "js-docs"]
    assert skipped == [("web/package.json", bw.REASON_OPTED_OUT)]


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
    odd = [n for n in ("w\n::warning::x/go.mod", "\x1b[2J/go.mod", "web\n/package.json") if creatable(tmp_path, n.split("/")[0])]
    files.update({n: "{}" if n.endswith(".json") else "" for n in odd})
    repo = make_repo(tmp_path / "r", files)
    comps, skipped = bw.detect(str(repo))
    assert comps == [
        bw.Component("go", "a.b", "go-a-b", ("a.b/go.mod",)),
        bw.Component("go", long_ok, "go-" + long_ok, (long_ok + "/go.mod",)),
        bw.Component("js", "x-y", "js-x-y", ("x-y/package.json",)),
    ]
    want = {
        "bad dir/go.mod": bw.REASON_NAME,
        "-x/go.mod": bw.REASON_NAME,
        long_bad + "/go.mod": bw.REASON_NAME,
        "a/b/go.mod": "job id go-a-b is taken by a.b",
        "x.y/package.json": "job id js-x-y is taken by x-y",
        **{n: bw.REASON_NAME for n in odd},
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
    comps, skipped = bw.detect(str(repo))
    assert [c.job_id for c in comps] == ["go-plain", "go-s"]
    assert skipped == [("q/go.mod", bw.REASON_OPTED_OUT), ("u/go.mod", bw.REASON_OPTED_OUT), ("v/go.mod", bw.REASON_VALUE)]
    # An unstaged .gitattributes edit changes nothing: check-attr reads the index.
    write(repo, ".gitattributes", "/plain/go.mod -bytewyrd-ci\n")
    assert bw.detect(str(repo)) == (comps, skipped)


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
    comps, skipped = bw.detect(str(make_repo(tmp_path / "r", files)))
    assert comps == [
        bw.Component("python", "both", "python-both", ("both/pyproject.toml", "both/setup.py")),
        bw.Component("python", "nopy", "python-nopy", ("nopy/pyproject.toml",)),
        bw.Component("python", "virtual", "python-virtual", ("virtual/pyproject.toml",)),
    ]
    assert skipped == [("legacy/setup.py", bw.REASON_PYPROJECT)]


def test_detection_ruby_needs_a_tracked_rakefile(tmp_path):
    files = dict.fromkeys(["Gemfile", "a/Gemfile", "a/Rakefile", "b/Gemfile", "b/rakefile.rb", "c/Gemfile", "c/RAKEFILE"], "")
    comps, skipped = bw.detect(str(make_repo(tmp_path / "r", files)))
    assert [c.job_id for c in comps] == ["ruby-a", "ruby-b"]
    assert skipped == [("Gemfile", bw.REASON_RAKEFILE), ("c/Gemfile", bw.REASON_RAKEFILE)]


def test_detection_counts_an_unmerged_manifest_once(tmp_path):
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n"})
    oid = git(repo, "rev-parse", ":go.mod").decode().strip()
    info = "0 %s\tgo.mod\n" % ("0" * 40) + "".join("100644 %s %d\tgo.mod\n" % (oid, s) for s in (1, 2, 3))
    git(repo, "update-index", "--index-info", input=info.encode())
    assert [e.stage for e in bw.tracked(str(repo))] == [1, 2, 3]
    assert jobs(repo) == ["go"]


def test_detection_never_counts_a_submodule_s_files(tmp_path):
    repo = make_repo(tmp_path / "r", {"go.mod": "module x\n"})
    add_gitlink(repo, "sub")
    assert jobs(repo) == ["go"]


def test_detection_result_shapes_and_order(tmp_path):
    files = {"z/go.mod": "", "go.mod": "", "web/package.json": "{}", "Cargo.toml": CRATE, "Gemfile": ""}
    comps, skipped = bw.detect(str(make_repo(tmp_path / "r", files)))
    assert [(c.language, c.directory) for c in comps] == [("go", "."), ("go", "z"), ("js", "web"), ("rust", ".")]
    assert all(isinstance(c, tuple) and len(c) == 4 for c in comps)
    assert skipped == [bw.Skip("Gemfile", bw.REASON_RAKEFILE)] and len(skipped[0]) == 2


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
    comps, skipped = bw.detect(str(make_repo(tmp_path / "out", files, attributes="/package.json -bytewyrd-ci\n")))
    assert [c.job_id for c in comps] == ["js-packages-a", "js-packages-b"]
    assert skipped == [("package.json", bw.REASON_OPTED_OUT)]
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
    comps, skipped = bw.detect(str(make_repo(tmp_path / "r", files)))
    assert [c.job_id for c in comps] == ["python-libs-m"]
    assert skipped == [("setup.py", bw.REASON_PYPROJECT)]


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
    git(repo, "init", "-q")
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
    entries = {e.path: e for e in bw.tracked(str(repo))}
    modes = {"a.txt": "100644", "link": "120000", "run.sh": "100755", "sub": "160000"}
    assert {p: e.mode for p, e in entries.items()} == {**modes, **dict.fromkeys(names, "100644")}
    assert all(e.stage == 0 and re.fullmatch(r"[0-9a-f]{40,64}", e.oid) for e in entries.values())


def test_tracked_decodes_paths_with_fsdecode(tmp_path):
    name = os.fsdecode(b"caf\xe9.txt")
    if not creatable(tmp_path, name):
        pytest.skip("this filesystem refuses non-UTF-8 names")
    repo = make_repo(tmp_path / "r", {name: "x"})
    assert [e.path for e in bw.tracked(str(repo))] == [name]


def test_tracked_outside_a_repo_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    (tmp_path / "plain").mkdir()
    with pytest.raises(bw.BwError):
        bw.tracked(str(tmp_path / "plain"))


def test_blob_returns_regular_stage_0_entries_up_to_1_mib(tmp_path):
    files = {"small": b"abc", "exact": b"y" * (1 << 20), "big": b"z" * ((1 << 20) + 1), "run.sh": b"#!/bin/sh\n"}
    repo = make_repo(tmp_path / "r", files)
    os.chmod(repo / "run.sh", 0o755)
    os.symlink("small", repo / "link")
    commit(repo)
    add_gitlink(repo, "sub")
    root = str(repo)
    entries = {e.path: e for e in bw.tracked(root)}
    assert bw.blob(root, entries["small"]) == b"abc"
    assert bw.blob(root, entries["exact"]) == b"y" * (1 << 20)
    assert bw.blob(root, entries["run.sh"]) == b"#!/bin/sh\n"
    assert bw.blob(root, entries["big"]) is None
    assert bw.blob(root, entries["link"]) is None
    assert bw.blob(root, entries["sub"]) is None
    assert bw.blob(root, entries["small"]._replace(stage=2)) is None
    assert bw.blob(root, bw.Entry("100644", "0" * 40, 0, "missing")) is None
    assert bw.blob(str(tmp_path / "nowhere"), entries["small"]) is None


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
GO = bw.Component("go", ".", "go", ("go.mod",))
WEB = bw.Component("js", "web", "js-web", ("web/package.json",))


def test_render_repeats_the_job_block_per_component():
    assert bw.render(CALLER, [GO, WEB], "p") == (
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
    assert bw.render("jobs:\n@@job@@ - @@job_id@@\nmiddle\n@@job@@   end\n", [GO], "p") == "jobs:\n- go\n  end\nmiddle\n"


def test_render_keeps_tagged_lines_for_present_languages():
    assert bw.render(AGENTS, [GO, WEB], "proj") == (
        "# proj\n\n- Languages: go, js in web/\n- Go: go test ./...\n- JS: bun test\nend\n"
    )


def test_render_keeps_the_none_line_only_without_components():
    assert bw.render(AGENTS, [], "proj") == "# proj\n\n- Languages: none\n- No language markers found.\nend\n"


@pytest.mark.parametrize(
    "count, suffix",
    [
        (10, ""),
        (11, ", and 1 more; see .github/workflows/ci.yml"),
        (12, ", and 2 more; see .github/workflows/ci.yml"),
    ],
)
def test_render_caps_the_languages_line_at_ten_components(count, suffix):
    comps = [bw.Component("go", "d%02d" % i, "go-d%02d" % i, ("d%02d/go.mod" % i,)) for i in range(count)]
    first_ten = ", ".join("go in d%02d/" % i for i in range(min(count, 10)))
    assert bw.render("@@languages@@", comps, "p") == first_ten + suffix


def test_render_values_are_literal():
    name = r"we&ird\name \1 \g<0> {0} %s @@languages@@ @@job_id@@ @@"
    assert bw.render("# @@project_name@@\n@@languages@@\n", [GO], name) == "# " + name + "\ngo\n"


def test_render_strips_crs():
    assert bw.render("a\r\n@@go@@ b\r\n@@js@@ c\r\n", [GO], "p") == "a\nb\n"


@pytest.mark.parametrize("tpl", ["@@unknown@@\n", "@@job_id@@ outside the block\n", "@@java@@ - Java\n", "a @@languages\n"])
def test_render_raises_when_a_placeholder_is_left(tpl):
    with pytest.raises(bw.BwError):
        bw.render(tpl, [GO], "p")


def test_render_never_renders_a_zero_job_caller():
    with pytest.raises(bw.BwError):
        bw.render(CALLER, [], "p")


# --- stamps and hashes -------------------------------------------------------


def test_stamp_forms():
    md = bw.stamp("md", "AGENTS.md", "0123456789ab", "unknown")
    assert md == "<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789ab plugin=unknown -->"
    yml = bw.stamp("yml", "ci-caller.yml", "0123456789ab", "abcdef012345")
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
        bw.stamp(*args)


@pytest.mark.parametrize("kind", ["md", "yml"])
@pytest.mark.parametrize("newline", ["\n", "\r\n"])
def test_read_stamp_round_trips(tmp_path, kind, newline):
    path = tmp_path / "f"
    line = bw.stamp(kind, "PULL_REQUEST_TEMPLATE.md", "abcdef012345", "unknown")
    path.write_bytes((line + newline + "body" + newline).encode())
    assert bw.read_stamp(str(path)) == ("PULL_REQUEST_TEMPLATE.md", "abcdef012345", "unknown")


@pytest.mark.parametrize(
    "first, want",
    [
        ("", None),
        ("# bootstrap-content-version: bytewyrd/CLAUDE.md@0:0", None),
        ("# just a heading", None),
        ("<!-- bytewyrd:scaffold v2 tpl=AGENTS.md:0123456789ab plugin=unknown -->", bw.BAD),
        ("<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789a plugin=unknown -->", bw.BAD),
        ("<!-- bytewyrd:scaffold v1 tpl=AGENTS.md:0123456789ab plugin=unknown --> x", bw.BAD),
        ("# bytewyrd:scaffold v1 tpl=ci.yml:0123456789ab", bw.BAD),
        ("x bytewyrd:scaffold", bw.BAD),
    ],
)
def test_read_stamp_none_and_bad(tmp_path, first, want):
    path = tmp_path / "f"
    path.write_text(first + "\nsecond line # bytewyrd:scaffold v1 tpl=a:0123456789ab plugin=unknown\n")
    assert bw.read_stamp(str(path)) is want


def test_bad_is_a_named_singleton():
    assert repr(bw.BAD) == "BAD" and bw.BAD is not None


def test_file_hash_ignores_crs(tmp_path):
    (tmp_path / "lf").write_bytes(b"line1\nline2\n")
    (tmp_path / "crlf").write_bytes(b"line1\r\nline2\r\n")
    want = hashlib.sha256(b"line1\nline2\n").hexdigest()[:12]
    assert bw.file_hash(str(tmp_path / "lf")) == bw.file_hash(str(tmp_path / "crlf")) == want
    (tmp_path / "abc").write_bytes(b"abc")
    assert bw.file_hash(str(tmp_path / "abc")) == "ba7816bf8f01"  # sha256("abc")


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
    for name, want in cases:
        (tmp_path / name).mkdir()
        assert bw.plugin_sha(str(tmp_path / name)) == want, name


def test_plugin_sha_from_a_git_checkout(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    repo = make_repo(tmp_path / "plugin", {"sub/x": "1"})
    head = git(repo, "rev-parse", "HEAD").decode().strip()
    assert bw.plugin_sha(str(repo)) == head[:12]
    assert bw.plugin_sha(str(repo / "sub")) == "unknown"  # not the checkout's top level
    (tmp_path / "fresh").mkdir()
    git(tmp_path / "fresh", "init", "-q")
    assert bw.plugin_sha(str(tmp_path / "fresh")) == "unknown"  # no commit yet


# --- root() and project_name() -----------------------------------------------


def test_root_from_a_subdirectory(tmp_path, monkeypatch):
    repo = make_repo(tmp_path / "r", {"a/b/x": ""})
    monkeypatch.chdir(repo / "a" / "b")
    assert os.path.realpath(bw.root()) == os.path.realpath(repo)


def test_root_outside_a_work_tree_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    (tmp_path / "plain").mkdir()
    monkeypatch.chdir(tmp_path / "plain")
    with pytest.raises(bw.BwError, match="not inside a git work tree"):
        bw.root()
    repo = make_repo(tmp_path / "r", {})
    monkeypatch.chdir(repo / ".git")
    with pytest.raises(bw.BwError, match="not inside a git work tree"):
        bw.root()


def test_root_without_git_raises(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    with pytest.raises(bw.BwError, match="cannot run git"):
        bw.root()


def test_project_name(tmp_path, monkeypatch):
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))
    repo = make_repo(tmp_path / "we&ird\\name", {})
    assert bw.project_name(str(repo)) == "we&ird\\name"
    # The parent of the common git dir names the project, wherever ROOT is.
    (tmp_path / "proj").mkdir()
    git(tmp_path, "init", "-q", "--separate-git-dir", str(tmp_path / "proj" / "store.git"), str(tmp_path / "checkout"))
    assert bw.project_name(str(tmp_path / "checkout")) == "proj"
    (tmp_path / "plain").mkdir()
    assert bw.project_name(str(tmp_path / "plain")) == "plain"


# --- files -------------------------------------------------------------------


def test_exists(tmp_path):
    d = str(tmp_path)
    (tmp_path / "agents.md").write_text("x")
    os.symlink("nowhere", tmp_path / "CLAUDE.md")
    (tmp_path / "README.md").mkdir()
    assert bw.exists(d, "AGENTS.md")  # a case variant
    assert bw.exists(d, "CLAUDE.md")  # a dangling symlink
    assert bw.exists(d, "README.md")  # a directory
    assert not bw.exists(d, "OTHER.md")
    assert not bw.exists(str(tmp_path / "missing"), "AGENTS.md")


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
    assert bw.pr_template(str(tmp_path)) == found


def test_pr_template_ignores_other_names_and_places(tmp_path):
    for rel in (
        "pull_request_template",  # a file: only a directory may have the bare name
        "src/pull_request_template.md",
        ".github/pull-request-template.md",
        "docs/pull_request_templates.md",
    ):
        write(tmp_path, rel, "x")
    assert bw.pr_template(str(tmp_path)) is None


def test_pr_template_looks_in_root_then_docs_then_github(tmp_path):
    write(tmp_path, ".github/pull_request_template.md", "x")
    write(tmp_path, "docs/pull_request_template.md", "x")
    assert bw.pr_template(str(tmp_path)) == "docs/pull_request_template.md"
    write(tmp_path, "PULL_REQUEST_TEMPLATE.md", "x")
    assert bw.pr_template(str(tmp_path)) == "PULL_REQUEST_TEMPLATE.md"


def test_symlinked_dir(tmp_path):
    root = str(tmp_path)
    assert bw.symlinked_dir(root, ".github/workflows/ci.yml") is None
    assert bw.symlinked_dir(root, "AGENTS.md") is None
    (tmp_path / "outside").mkdir()
    os.symlink(tmp_path / "outside", tmp_path / ".github")
    assert bw.symlinked_dir(root, ".github/workflows/ci.yml") == ".github"
    os.unlink(tmp_path / ".github")
    (tmp_path / ".github").mkdir()
    os.symlink(tmp_path / "outside", tmp_path / ".github" / "workflows")
    assert bw.symlinked_dir(root, ".github/workflows/ci.yml") == ".github/workflows"
    assert bw.symlinked_dir(root, ".github/PULL_REQUEST_TEMPLATE.md") is None


def test_create_writes_lf_text(tmp_path):
    bw.create(str(tmp_path / "f"), "a\nb\n")
    assert (tmp_path / "f").read_bytes() == b"a\nb\n"


def test_create_never_writes_over_or_through_anything(tmp_path):
    (tmp_path / "file").write_text("keep")
    os.symlink(tmp_path / "target", tmp_path / "dangling")
    (tmp_path / "dir").mkdir()
    for name in ("file", "dangling", "dir"):
        with pytest.raises(FileExistsError):
            bw.create(str(tmp_path / name), "new")
    assert (tmp_path / "file").read_text() == "keep"
    assert not os.path.lexists(tmp_path / "target")


def test_create_leaves_nothing_when_the_write_fails(tmp_path):
    with pytest.raises(UnicodeEncodeError):
        bw.create(str(tmp_path / "f"), "x\ud800")
    assert not os.path.lexists(tmp_path / "f")


def test_parser_usage_errors_exit_1(capsys):
    parser = bw.Parser(prog="bw x")
    parser.add_argument("--flag", action="store_true")
    with pytest.raises(SystemExit) as e:
        parser.parse_args(["--nope"])
    assert e.value.code == 1
    err = capsys.readouterr().err
    assert err == "usage: bw x [-h] [--flag]\nbw x: error: unrecognized arguments: --nope\n"


def test_skip_fix_lines():
    path = "a b/go.mod"
    mark = ", or mark the manifest: " + bw.attr_line(path)
    assert bw.skip_fix(path, bw.REASON_NAME) == "rename the directory" + mark
    assert bw.skip_fix(path, bw.reason_taken("go-a-b", "a.b")) == "rename the directory" + mark
    assert bw.skip_fix(path, bw.REASON_RAKEFILE) == "add a Rakefile whose default task runs the tests" + mark
    assert bw.skip_fix(path, bw.REASON_PYPROJECT) == "add a pyproject.toml with a [project] table" + mark
    assert bw.skip_fix(path, bw.REASON_VALUE) == "set bytewyrd-ci or -bytewyrd-ci for this path in .gitattributes"
    assert bw.skip_fix(path, bw.REASON_OPTED_OUT) is None


def test_reason_taken_quotes_its_values():
    assert bw.reason_taken("go-a-b", "a.b") == "job id go-a-b is taken by a.b"


# --- state-touch -------------------------------------------------------------


def test_state_touch_writes_where_it_opened_even_after_a_swap(tmp_path, monkeypatch):
    repo, outside = tmp_path / "repo", tmp_path / "outside"
    repo.mkdir()
    outside.mkdir()
    monkeypatch.chdir(repo)
    opened = bw_state_touch.open_state_dir

    def open_then_swap():
        fd = opened()
        os.rename(".bytewyrd", "moved")
        os.symlink(outside, ".bytewyrd")
        return fd

    monkeypatch.setattr(bw_state_touch, "open_state_dir", open_then_swap)
    assert bw_state_touch.main(["last-feature-engineer-stop"]) == 0
    assert list(outside.iterdir()) == []
    assert sorted(p.name for p in (repo / "moved").iterdir()) == [".gitignore", "last-feature-engineer-stop"]

    # --rm after a swap removes from the directory it opened, not the outside one.
    os.unlink(repo / ".bytewyrd")
    os.rename(repo / "moved", repo / ".bytewyrd")
    (outside / "last-feature-engineer-stop").write_text("keep")
    assert bw_state_touch.main(["--rm", "last-feature-engineer-stop"]) == 0
    assert (outside / "last-feature-engineer-stop").read_text() == "keep"
    assert sorted(p.name for p in (repo / "moved").iterdir()) == [".gitignore"]


@pytest.mark.parametrize("error", [RuntimeError("boom"), OSError(5, "Input/output error"), KeyboardInterrupt()])
def test_state_touch_always_exits_0(error, monkeypatch, capsys):
    def fail(argv):
        raise error

    monkeypatch.setattr(bw_state_touch, "run", fail)
    assert bw_state_touch.main(["x"]) == 0
    assert capsys.readouterr().err.count("\n") == 1


# --- compact-reminder --------------------------------------------------------


def test_compact_reminder_text():
    # hooks/hooks.json's compact reminder at ae97f77, asking the user to run
    # /docs-review instead of "Consider running /docs-review" [R77].
    assert bw_compact_reminder.TEXT == (
        "Post-compact reminder: a feature-engineer agent finished in the last 24 hours and "
        "/docs-review may not yet have run. Ask the user to run /docs-review against the implemented files."
    )


def test_compact_reminder_prints_only_while_the_sentinel_is_under_a_day_old(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    remind = bw_compact_reminder.TEXT + "\n"
    assert bw_compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")
    (tmp_path / ".bytewyrd").mkdir()
    sentinel = tmp_path / ".bytewyrd" / "last-feature-engineer-stop"
    sentinel.touch()
    for age, want in [(0, remind), (86000, remind), (86401, ""), (-60, remind)]:
        mtime = time.time() - age
        os.utime(sentinel, (mtime, mtime))
        assert bw_compact_reminder.main([]) == 0
        assert capsys.readouterr() == (want, ""), age
    sentinel.unlink()
    (tmp_path / "fresh").touch()
    os.symlink(tmp_path / "fresh", sentinel)  # never a sentinel state-touch wrote
    assert bw_compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")
    sentinel.unlink()
    sentinel.mkdir()
    assert bw_compact_reminder.main([]) == 0
    assert capsys.readouterr() == ("", "")


def test_compact_reminder_always_exits_0(monkeypatch, capsys):
    monkeypatch.setattr(bw_compact_reminder, "due", lambda: 1 / 0)
    assert bw_compact_reminder.main([]) == 0
    assert bw_compact_reminder.main(["--bogus"]) == 0
    assert "usage: bw compact-reminder" in capsys.readouterr().err
