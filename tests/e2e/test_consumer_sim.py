"""consumer-sim: scaffold and drift end to end, as a consumer repository sees
them (RFC 2026-11-09-scaffold-and-drift, B4, steps S1 to S39).

It is black-box: it runs the plugin only as `sh "$PLUGIN/scripts/bw" ...`
through subprocess and imports nothing from scripts/. PLUGIN is a copy of
$BW_PLUGIN_DIR (default: this repository) in a temporary directory named
`plugin`, without .git, so stamps read plugin=unknown; S19 runs from
$BW_PLUGIN_DIR itself.

Every step runs twice, with CLAUDE_PLUGIN_ROOT absent from the child
environment and with it set to /nonexistent. Each child gets an environment
built here, with BYTEWYRD_PYTHON set to the interpreter running pytest and
git kept away from the developer's configuration. Every drift run is checked
to leave every file of its repository as it was (S6).
"""

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

import pytest

SOURCE = Path(os.environ.get("BW_PLUGIN_DIR") or Path(__file__).resolve().parents[2]).resolve()
LEGACY = Path(__file__).resolve().parents[1] / "fixtures" / "legacy-0.2"
TARGETS = ("AGENTS.md", "CLAUDE.md", ".github/PULL_REQUEST_TEMPLATE.md", ".github/workflows/ci.yml")
LANGUAGES = ("go", "js", "python", "ruby", "rust")
STAMP = re.compile(
    r"^(<!-- |# )bytewyrd:scaffold v1 tpl=([A-Za-z0-9._-]+):([0-9a-f]{12}) plugin=([0-9a-f]{12}|unknown)( -->)?$"
)
CALL = re.compile(r"bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-([a-z]+)\.yml@([0-9a-f]{40})")
SCAFFOLD_PREFIXES = ("bytewyrd scaffold: ", "would create  ", "created  ", "skip  ", "note: ", "dry run: ", "applied: ")
DRIFT_PREFIXES = ("ok  ", "info  ", "warn  ", "drift  ", "  ", "result: ")
IS_ROOT = hasattr(os, "geteuid") and os.geteuid() == 0
COPY_SKIPS = (".git", "__pycache__", ".pytest_cache", ".worktrees")


# --- the plugin copy ---------------------------------------------------------


def _copy_ignore(directory, names):
    """Skip git and cache directories, and anything but regular files,
    directories and symlinks (such as device placeholders)."""
    skipped = set()
    for name in names:
        if name in COPY_SKIPS:
            skipped.add(name)
            continue
        try:
            mode = os.lstat(os.path.join(directory, name)).st_mode
        except OSError:
            skipped.add(name)
            continue
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode) or stat.S_ISLNK(mode)):
            skipped.add(name)
    return skipped


def copy_plugin(parent):
    plugin = parent / "plugin"
    shutil.copytree(SOURCE, plugin, symlinks=True, ignore=_copy_ignore)
    return plugin


@pytest.fixture(scope="session")
def shared_plugin(tmp_path_factory):
    """A plugin copy that no step changes."""
    return copy_plugin(tmp_path_factory.mktemp("shared"))


@pytest.fixture
def own_plugin(tmp_path):
    """A plugin copy of the test's own, for the steps that edit it."""
    return copy_plugin(tmp_path / "own")


# --- running the plugin --------------------------------------------------------


class Result(NamedTuple):
    code: int
    out: str
    err: str
    raw_out: bytes
    raw_err: bytes

    @property
    def lines(self):
        return self.out.splitlines()


def snapshot(root):
    """Every entry under ROOT, .git included, with its type, mode, size,
    mtime and content hash, without following symlinks."""
    state = {}
    base = os.fsencode(root)
    for dirpath, dirnames, filenames in os.walk(base):
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            st = os.lstat(path)
            rel = os.path.relpath(path, base)
            if stat.S_ISREG(st.st_mode):
                with open(path, "rb") as f:
                    state[rel] = ("file", st.st_mode, st.st_mtime_ns, hashlib.sha256(f.read()).hexdigest())
            elif stat.S_ISLNK(st.st_mode):
                state[rel] = ("link", os.readlink(path))
            else:
                state[rel] = ("other", st.st_mode)
    return state


def pycaches(root):
    return [d for d, names, _ in os.walk(root) if "__pycache__" in names]


class Sim:
    """One consumer-sim run: the plugin copy, the child environment and the
    throwaway repositories, all under TMP."""

    def __init__(self, plugin, variant, tmp):
        self.plugin, self.tmp = plugin, tmp
        home = tmp / "home"
        home.mkdir()
        self.env = {
            "PATH": os.environ.get("PATH", os.defpath),
            "HOME": str(home),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            # Each git commit starts automatic maintenance, which detaches and
            # takes .git/objects/maintenance.lock in the background; the lock
            # appearing or vanishing mid-snapshot fails drift's S6 check.
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "maintenance.auto",
            "GIT_CONFIG_VALUE_0": "false",
            "BYTEWYRD_PYTHON": sys.executable,
        }
        if os.environ.get("TMPDIR"):
            self.env["TMPDIR"] = os.environ["TMPDIR"]
        if variant == "nonexistent":
            self.env["CLAUDE_PLUGIN_ROOT"] = "/nonexistent"

    def bw(self, cwd, *args, plugin=None, env=None):
        launcher = os.path.join(plugin or self.plugin, "scripts", "bw")
        proc = subprocess.run(
            ["sh", launcher, *args], cwd=cwd, env=env or self.env, capture_output=True, timeout=120
        )
        decode = lambda b: b.decode("utf-8", "surrogateescape")  # noqa: E731
        return Result(proc.returncode, decode(proc.stdout), decode(proc.stderr), proc.stdout, proc.stderr)

    def scaffold(self, cwd, *args, **kwargs):
        return self.bw(cwd, "scaffold", *args, **kwargs)

    def drift(self, repo, *args, cwd=None, **kwargs):
        """drift, checking that it leaves every file of REPO as it was (S6)
        and writes no bytecode into the plugin."""
        before = snapshot(repo)
        result = self.bw(cwd or repo, "drift", *args, **kwargs)
        assert snapshot(repo) == before, "drift changed a file"
        assert pycaches(kwargs.get("plugin") or self.plugin) == []
        return result

    def git(self, cwd, *args, input=None):
        proc = subprocess.run(["git", "-C", os.fspath(cwd), *args], env=self.env, input=input, capture_output=True)
        assert proc.returncode == 0, "git %s: %s" % (" ".join(map(str, args)), proc.stderr.decode(errors="replace"))
        return proc.stdout

    def commit(self, repo):
        self.git(repo, "add", "-A")
        self.git(repo, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-q", "--allow-empty", "-m", "x")

    def repo(self, name, files=None, commit=True):
        """A new repository at TMP/NAME holding FILES ({path: text or bytes}),
        committed unless COMMIT is false."""
        repo = self.tmp / name
        repo.mkdir(parents=True)
        self.git(repo, "init", "-q")
        for rel, content in (files or {}).items():
            write(repo, rel, content)
        if commit:
            self.commit(repo)
        return repo


def write(repo, rel, content=""):
    path = os.path.join(os.fsencode(repo), os.fsencode(rel))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(content if isinstance(content, bytes) else content.encode())


@pytest.fixture(params=["unset", "nonexistent"], ids=["CLAUDE_PLUGIN_ROOT-unset", "CLAUDE_PLUGIN_ROOT-nonexistent"])
def variant(request):
    return request.param


@pytest.fixture
def sim(shared_plugin, variant, tmp_path):
    return Sim(shared_plugin, variant, tmp_path)


@pytest.fixture
def own_sim(own_plugin, variant, tmp_path):
    return Sim(own_plugin, variant, tmp_path)


# --- reading the results -----------------------------------------------------


def jobs(repo):
    """The job ids of REPO's ci.yml, in file order."""
    lines = (repo / ".github" / "workflows" / "ci.yml").read_text().split("\n")
    start = lines.index("jobs:")
    return [m.group(1) for m in (re.fullmatch(r"  ([A-Za-z0-9_-]+):", line) for line in lines[start:]) if m]


def job_block(repo, job_id):
    lines = (repo / ".github" / "workflows" / "ci.yml").read_text().split("\n")
    i = lines.index("  %s:" % job_id)
    return lines[i : i + 4]


def findings(result):
    """drift's coded findings, as "<severity>  <path>  <code>" lines."""
    found = []
    for line in result.lines:
        m = re.match(r"(ok|info|warn|drift)  (.+?)  ([a-z-]+): ", line)
        if m:
            found.append("  ".join(m.groups()))
    return found


def fix_lines(result, head):
    """The fix lines of the finding whose line starts with HEAD."""
    lines = result.lines
    i = next(n for n, line in enumerate(lines) if line.startswith(head))
    out = []
    for line in lines[i + 1 :]:
        if not line.startswith("  fix: "):
            break
        out.append(line[len("  fix: ") :])
    return out


def footer(result):
    return result.lines[-1]


def notes(result):
    return [line for line in result.lines if line.startswith("note: ")]


def check_bytes(result, prefixes):
    """No byte below 0x20 but newlines, every stdout line starts with a
    documented prefix, and stderr is empty (S29)."""
    assert result.raw_err == b""
    assert all(b >= 0x20 or b == 0x0A for b in result.raw_out)
    for line in result.out.splitlines():
        assert line.startswith(prefixes), line


def creatable(tmp, name):
    try:
        path = os.path.join(os.fsencode(tmp), os.fsencode(name))
        os.mkdir(path)
        os.rmdir(path)
        return True
    except (OSError, UnicodeError):
        return False


PROJECT = '[project]\nname = "x"\nversion = "0"\n'
CRATE = '[package]\nname = "x"\nversion = "0.1.0"\n'


# --- S1 to S11: a fresh repository, seeded and checked ------------------------


def test_s01_to_s11_and_s22_seeding_a_fresh_repo(own_sim):
    sim, repo = own_sim, own_sim.repo("fresh", commit=False)

    # S1: a dry run in a repo with no commits writes nothing.
    r = sim.scaffold(repo)
    assert r.code == 0 and r.err == ""
    assert [line for line in r.lines if line.startswith("would create  ")] == ["would create  " + t for t in TARGETS]
    assert sim.git(repo, "status", "--porcelain") == b"" and os.listdir(repo) == [".git"]

    # S2: --apply from a subdirectory writes at the top level, and nothing under .claude.
    sub = repo / "a" / "b"
    sub.mkdir(parents=True)
    r = sim.scaffold(sub, "--apply")
    assert r.code == 0 and footer(r) == "applied: 4 created, 0 skipped"
    assert all((repo / t).is_file() for t in TARGETS) and list(sub.iterdir()) == []
    assert not any(".claude" in Path(os.fsdecode(p)).parts for p in snapshot(repo))

    # S22: the no-language ci.yml equals the committed fixture from line 2 on.
    fixture = (SOURCE / ".github" / "workflows" / "scaffold-noop-fixture.yml").read_text()
    assert (repo / TARGETS[3]).read_text().split("\n", 1)[1] == fixture.split("\n", 1)[1]

    # S3: each line 1 is a stamp, plugin=unknown since the plugin copy isn't a git checkout.
    for t in TARGETS:
        m = STAMP.fullmatch((repo / t).read_text().split("\n", 1)[0])
        assert m and m.group(4) == "unknown", t

    # S4
    r = sim.drift(repo)
    assert (r.code, footer(r)) == (0, "result: 4 ok, 0 info, 0 warn, 0 drift (exit 0)")

    # S5: a second --apply after the commit creates nothing.
    sim.commit(repo)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and footer(r) == "applied: 0 created, 4 skipped"
    assert sim.git(repo, "status", "--porcelain") == b""
    assert sim.drift(repo).code == 0

    # S7: CRLF copies of the four files pass.
    originals = {t: (repo / t).read_bytes() for t in TARGETS}
    for t, data in originals.items():
        (repo / t).write_bytes(data.replace(b"\n", b"\r\n"))
    assert sim.drift(repo).code == 0
    for t, data in originals.items():
        (repo / t).write_bytes(data)

    # S8: a CRLF template hashes as its LF form.
    tpl = sim.plugin / "templates" / "scaffold" / "AGENTS.md.tpl"
    tpl_lf = tpl.read_bytes()
    tpl.write_bytes(tpl_lf.replace(b"\n", b"\r\n"))
    r = sim.drift(repo)
    assert r.code == 0 and "ok  AGENTS.md" in r.lines

    # S9: a changed template is template-changed, and the printed stamp restores exit 0.
    tpl.write_bytes(tpl.read_bytes() + b"- One more line.\r\n")
    r = sim.drift(repo)
    assert r.code == 2 and "drift  AGENTS.md  template-changed" in findings(r)
    fix = fix_lines(r, "drift  AGENTS.md  template-changed: ")[0]
    assert fix.startswith("apply the diff, then replace line 1 with: ")
    new_stamp = fix[len("apply the diff, then replace line 1 with: ") :]
    assert STAMP.fullmatch(new_stamp) and "+- One more line." in [line.strip() for line in r.lines]
    agents = repo / "AGENTS.md"
    agents.write_bytes(new_stamp.encode() + b"\n" + originals["AGENTS.md"].split(b"\n", 1)[1])
    assert sim.drift(repo).code == 0
    tpl.write_bytes(tpl_lf)
    agents.write_bytes(originals["AGENTS.md"])

    # S10: CLAUDE.md without the import.
    claude = repo / "CLAUDE.md"
    claude.write_bytes(originals["CLAUDE.md"].replace(b"@AGENTS.md\n", b""))
    r = sim.drift(repo)
    assert r.code == 2 and findings(r) == ["drift  CLAUDE.md  no-import"]
    claude.write_bytes(originals["CLAUDE.md"])

    # S11: a new go.mod makes the no-op ci.yml a variant: a warning, which --strict counts.
    write(repo, "go.mod", "module x\n")
    sim.commit(repo)
    r = sim.drift(repo)
    assert r.code == 0 and findings(r) == ["warn  .github/workflows/ci.yml  ci-variant"]
    assert sim.drift(repo, "--strict").code == 2


# --- S12 to S16: refusals and failures -----------------------------------------


def test_s12_a_dirty_tree_needs_allow_dirty(sim):
    repo = sim.repo("dirty", commit=False)
    write(repo, "untracked.txt", "x")
    before = snapshot(repo)
    r = sim.scaffold(repo, "--apply")
    assert (r.code, r.out, r.err) == (3, "", "scaffold: working tree is dirty; commit first or pass --allow-dirty\n")
    assert snapshot(repo) == before
    r = sim.scaffold(repo, "--apply", "--allow-dirty")
    assert r.code == 0 and footer(r) == "applied: 4 created, 0 skipped"


def test_s13_existing_targets_are_skipped_and_never_followed(sim):
    outside = sim.tmp / "outside"
    outside.mkdir()
    cases = {
        "lowercase": ({"agents.md": "mine\n"}, "skip  AGENTS.md  (exists; scaffold never overwrites)"),
        "directory": ({"AGENTS.md/notes.txt": "x\n"}, "skip  AGENTS.md  (exists; scaffold never overwrites)"),
        "dangling": ({}, "skip  AGENTS.md  (exists; scaffold never overwrites)"),
        "pr-template": (
            {"docs/pull_request_template.md": "x\n"},
            "skip  .github/PULL_REQUEST_TEMPLATE.md  (pull request template found: docs/pull_request_template.md)",
        ),
        "workflow": ({".github/workflows/other.yml": "x\n"}, "skip  .github/workflows/ci.yml  (another workflow exists)"),
    }
    for name, (files, skip) in cases.items():
        repo = sim.repo(name, files, commit=False)
        if name == "dangling":
            os.symlink(outside / "target.md", repo / "AGENTS.md")
        sim.commit(repo)
        r = sim.scaffold(repo, "--apply")
        assert r.code == 0 and skip in r.lines, name
        assert footer(r) == "applied: 3 created, 1 skipped", name
        assert sim.drift(repo).code == 0, name
    assert os.listdir(outside) == []  # the dangling symlink's target was never created
    assert (sim.tmp / "lowercase" / "agents.md").read_text() == "mine\n"


def test_s14_a_symlinked_github_directory_exits_1_writing_nothing(sim):
    outside = sim.tmp / "outside"
    outside.mkdir()
    repo = sim.repo("linked", commit=False)
    os.symlink(outside, repo / ".github")
    sim.commit(repo)
    before = snapshot(repo)
    r = sim.scaffold(repo, "--apply")
    assert (r.code, r.out, r.err) == (1, "", "scaffold: .github is a symlink; refusing to write through it\n")
    assert snapshot(repo) == before and os.listdir(outside) == []


@pytest.mark.skipif(IS_ROOT, reason="root writes into a mode-0555 directory")
def test_s15_a_failed_apply_removes_the_files_it_created(sim):
    repo = sim.repo("readonly", commit=False)
    github = repo / ".github"
    github.mkdir()
    github.chmod(0o555)
    try:
        r = sim.scaffold(repo, "--apply")
    finally:
        github.chmod(0o755)
    assert (r.code, r.out) == (1, "")
    assert r.err == (
        "scaffold: cannot create .github/PULL_REQUEST_TEMPLATE.md: Permission denied\n"
        "scaffold: failed; removed: AGENTS.md CLAUDE.md\n"
    )
    assert sorted(os.listdir(repo)) == [".git", ".github"] and os.listdir(github) == []


def test_s16_a_broken_drift_module_exits_1(own_sim):
    sim = own_sim
    repo = sim.repo("r")
    module = sim.plugin / "scripts" / "_lib" / "bw_drift.py"
    original = module.read_bytes()
    module.write_bytes(original + b")\n")
    try:
        r = sim.drift(repo)
    finally:
        module.write_bytes(original)
    assert r.code == 1 and r.out == ""
    assert sim.drift(repo).code == 0  # restored, it runs again


# --- S17 and S24: the caller and its pin -------------------------------------


def check_workflow_security(path):
    """S17's checks on a caller or a lang-ci file (AC-9)."""
    lines = path.read_text().split("\n")
    code = [line for line in lines if not line.lstrip().startswith("#")]
    for line in code:
        if re.match(r"\s*(- )?uses:", line):
            assert re.search(r"@[0-9a-f]{40}(\s|$)", line), line
    checkouts = sum("uses: actions/checkout@" in line for line in code)
    assert checkouts == sum(line.strip() == "persist-credentials: false" for line in code), path
    assert [line for line in code if re.match(r"\s*permissions:", line)] == ["permissions:"], path
    i = lines.index("permissions:")
    assert lines[i + 1] == "  contents: read" and not lines[i + 2].startswith(" "), path
    assert not any("secrets" in line or "pull_request_target" in line for line in code), path


def s17_repo(sim):
    repo = sim.repo("s17", {"go.mod": "module x\n", "Gemfile": "", "Rakefile": ""})
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0
    return repo


def test_s17_the_caller_pins_one_main_commit_for_every_job(sim):
    repo = s17_repo(sim)
    assert jobs(repo) == ["go", "ruby"]
    calls = {}
    for job in ("go", "ruby"):
        block = job_block(repo, job)
        m = CALL.fullmatch(block[1].strip()[len("uses: ") :])
        assert m and m.group(1) == job and block[2:] == ["    with:", '      directory: "."'], block
        calls[job] = m.group(2)
    assert calls["go"] == calls["ruby"]
    check_workflow_security(repo / ".github" / "workflows" / "ci.yml")
    for language in LANGUAGES:
        check_workflow_security(SOURCE / ".github" / "workflows" / ("lang-ci-%s.yml" % language))


def test_s24_every_other_uses_value_is_pin_changed(sim):
    repo = s17_repo(sim)
    sim.commit(repo)
    ci = repo / ".github" / "workflows" / "ci.yml"
    committed = ci.read_text()
    ruby = job_block(repo, "ruby")[1]
    pin = CALL.search(ruby).group(2)
    go_value = job_block(repo, "go")[1].strip()[len("uses: ") :]
    other = "0123456789abcdef" * 2 + "01234567"
    decoys = [
        ruby.replace(pin, other),
        "    uses: bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@main",
        "    uses: evil/x/.github/workflows/lang-ci-ruby.yml@main",
        "    uses: " + go_value,
        "    uses: ./.github/workflows/x.yml",
    ]
    for n, decoy in enumerate(decoys):
        ci.write_text(committed.replace(ruby, decoy))
        r = sim.drift(repo)
        assert r.code == 2 and "drift  .github/workflows/ci.yml  pin-changed" in findings(r), decoy
        fixes = fix_lines(r, "drift  .github/workflows/ci.yml  pin-changed: ")
        assert fixes[-1] == "set this uses: to bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-ruby.yml@" + pin
        if n == 0:
            assert fixes[0] == "review https://github.com/bytewyrd/claude-bytewyrd/compare/%s...%s" % (other, pin)
        ci.write_text(committed)
    assert sim.drift(repo).code == 0


# --- S18: the legacy 0.2.x fixtures ------------------------------------------

LEGACY_CASES = sorted(p.name for p in LEGACY.iterdir() if p.is_dir())


def test_s18_there_is_one_legacy_case_per_legacy_code():
    assert LEGACY_CASES == [
        "legacy-gitignore",
        "legacy-header",
        "legacy-rfc-process-copy",
        "legacy-settings-hooks",
        "legacy-sidecar",
        "legacy-state",
    ]


def copy_case(case, repo):
    """Copy a case's repo/ files into REPO under their real names: a leading
    "dot-" in a path segment is a ".", and each file name ends in ".in"."""
    source = LEGACY / case / "repo"
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        parts = ["." + p[len("dot-") :] if p.startswith("dot-") else p for p in path.relative_to(source).parts]
        assert parts[-1].endswith(".in"), path
        parts[-1] = parts[-1][: -len(".in")]
        write(repo, "/".join(parts), path.read_bytes())


def run_port(sim, case, phase, repo, state):
    port = LEGACY / case / "port.py"
    proc = subprocess.run(
        [sys.executable, "-I", "-B", str(port), phase, str(repo), str(state), str(sim.plugin)],
        env=sim.env,
        capture_output=True,
        timeout=120,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")


@pytest.mark.parametrize("committed", [False, True], ids=["untracked", "committed"])
@pytest.mark.parametrize("case", LEGACY_CASES)
def test_s18_a_legacy_repo_reports_its_codes_then_migrates_to_exit_0(sim, case, committed):
    repo = sim.repo(case, commit=False)
    copy_case(case, repo)
    if committed:
        sim.commit(repo)
    r = sim.drift(repo)
    assert r.code == 2
    assert findings(r) == (LEGACY / case / "expected").read_text().splitlines()
    assert all(line.startswith(DRIFT_PREFIXES) for line in r.lines)

    # The migration procedure (B4): fix, commit, scaffold --apply, port, commit, drift.
    state = sim.tmp / "state"
    state.mkdir()
    run_port(sim, case, "before", repo, state)
    sim.commit(repo)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and "created  AGENTS.md" in r.lines, r.out + r.err
    if case == "legacy-header":
        assert "created  CLAUDE.md" in r.lines
    run_port(sim, case, "after", repo, state)
    sim.commit(repo)
    r = sim.drift(repo)
    assert r.code == 0, r.out
    assert not [f for f in findings(r) if not f.split("  ")[0] == "info"], r.out  # only unstamped info is left


# --- S19 to S23 --------------------------------------------------------------


def test_s19_from_the_git_checkout_the_stamp_names_its_commit(sim):
    top = subprocess.run(["git", "-C", str(SOURCE), "rev-parse", "--show-toplevel"], env=sim.env, capture_output=True)
    if top.returncode != 0 or Path(top.stdout.decode().strip()).resolve() != SOURCE:
        pytest.skip("BW_PLUGIN_DIR is not a git checkout")
    repo = sim.repo("we&ird\\name", commit=False)
    r = sim.scaffold(repo, "--apply", plugin=SOURCE)
    assert r.code == 0, r.err
    lines = (repo / "AGENTS.md").read_text().split("\n")
    assert lines[1] == "# we&ird\\name"
    assert re.fullmatch(r"[0-9a-f]{12}", STAMP.fullmatch(lines[0]).group(4))


def test_s20_outside_a_work_tree_both_exit_1(sim):
    plain = sim.tmp / "plain"
    plain.mkdir()
    env = dict(sim.env, GIT_CEILING_DIRECTORIES=str(sim.tmp))
    assert sim.scaffold(plain, env=env).code == 1
    r = sim.bw(plain, "drift", env=env)
    assert (r.code, r.out) == (1, "")


def test_s21_state_touch_never_writes_outside_the_repo(sim):
    outside = sim.tmp / "outside"
    outside.mkdir()
    (outside / "keep").write_text("x")
    repo = sim.repo("r")
    before = snapshot(outside)
    os.symlink(outside, repo / ".bytewyrd")
    assert sim.bw(repo, "state-touch", "last-feature-engineer-stop").code == 0
    assert snapshot(outside) == before
    os.unlink(repo / ".bytewyrd")
    (repo / ".bytewyrd").mkdir()
    os.symlink(outside / "keep", repo / ".bytewyrd" / "last-feature-engineer-stop")
    assert sim.bw(repo, "state-touch", "last-feature-engineer-stop").code == 0
    assert snapshot(outside) == before


def test_s23_drift_runs_the_bytewyrd_python_it_is_given(sim):
    repo = sim.repo("r")
    log = sim.tmp / "wrapper.log"
    wrapper = sim.tmp / "wrapper"
    wrapper.write_text('#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' % (log, sys.executable))
    wrapper.chmod(0o755)
    r = sim.drift(repo, env=dict(sim.env, BYTEWYRD_PYTHON=str(wrapper)))
    assert r.code == 0
    assert any("bw_main.py drift" in line for line in log.read_text().splitlines())


# --- S25 to S39: detection, end to end ---------------------------------------


def s25_repo(sim):
    repo = sim.repo("s25", {"web/package.json": "{}", "api/go.mod": "module x\n"})
    assert sim.scaffold(repo, "--apply").code == 0
    return repo


def test_s25_subdirectory_components(sim):
    repo = s25_repo(sim)
    assert jobs(repo) == ["go-api", "js-web"]
    for job, language, directory in (("go-api", "go", "api"), ("js-web", "js", "web")):
        block = job_block(repo, job)
        assert CALL.fullmatch(block[1].strip()[len("uses: ") :]).group(1) == language
        assert block[3] == '      directory: "%s"' % directory
    agents = (repo / "AGENTS.md").read_text().split("\n")
    assert next(line for line in agents if line.startswith("- Languages found")).endswith("go in api/, js in web/")
    assert sim.drift(repo).code == 0


def test_s26_root_workspaces_cover_their_members(sim):
    files = {
        "package.json": json.dumps({"workspaces": ["packages/*"]}),
        "pyproject.toml": '[tool.uv.workspace]\nmembers = ["libs/*"]\nexclude = ["libs/solo"]\n',
        "Cargo.toml": '[workspace]\nmembers = ["crates/*"]\nexclude = ["tools"]\n',
        "go.mod": "module x\n",
        "go.work": "go 1.27\n\nuse (\n\t.\n\t./svc\n)\n",
        "packages/a/package.json": "{}",
        "site/package.json": "{}",
        "libs/m/pyproject.toml": PROJECT,
        "libs/solo/pyproject.toml": PROJECT,
        "crates/c/Cargo.toml": CRATE,
        "tools/gen/Cargo.toml": CRATE,
        "svc/go.mod": "module y\n",
    }
    repo = sim.repo("s26", files)
    assert sim.scaffold(repo, "--apply").code == 0
    assert jobs(repo) == ["go", "go-svc", "js", "js-site", "python", "python-libs-solo", "rust", "rust-tools-gen"]
    assert sim.drift(repo).code == 0


def test_s27_ruby_notes(sim):
    files = {
        "Gemfile": 'source "https://rubygems.org"\n',
        "Rakefile": "",
        "package.json": "{}",
        "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
        ".tool-versions": "nodejs 24.0.0\n",
        "Gemfile.lock": "GEM\n  remote: https://rubygems.org/\n  specs:\n\nPLATFORMS\n  arm64-darwin-24\n\nDEPENDENCIES\n",
    }
    repo = sim.repo("s27", files)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and jobs(repo) == ["js", "ruby"]
    assert any(line.startswith("- Ruby: ") for line in (repo / "AGENTS.md").read_text().split("\n"))
    assert notes(r) == [
        "note: . gives setup-ruby no Ruby version; add .ruby-version, or a ruby line to .tool-versions or mise.toml",
        "note: Gemfile.lock lacks the CI runner's platform; run bundle lock --add-platform x86_64-linux",
        "note: . has pnpm-lock.yaml, and the ruby CI job has no pnpm; "
        "a Rails test:prepare that builds JavaScript fails there",
    ]


def test_s28_default_scope_and_bytewyrd_ci_overrides(sim):
    paths = [
        "test/fixtures/app/package.json",
        "examples/demo/go.mod",
        "testdata/x/go.mod",
        ".github/actions/a/package.json",
        "_old/go.mod",
        "a/b/c/go.mod",
        "docs/package.json",
        "web/package.json",
        "deep/one/two/go.mod",
    ]
    files = {p: "{}" if p.endswith(".json") else "module x\n" for p in paths}
    files[".gitattributes"] = "web/package.json -bytewyrd-ci\ndeep/** bytewyrd-ci\n"
    repo = sim.repo("s28", files)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and jobs(repo) == ["go-deep-one-two", "js-docs"]
    assert notes(r) == ["note: no CI job for web/package.json: opted out by -bytewyrd-ci"]
    assert sim.drift(repo).code == 0


def test_s29_unusual_names_are_quoted_and_never_become_jobs(sim):
    odd = ["bad dir/go.mod", "-x/go.mod", "w\n::warning::x/go.mod", "\x1b[2J/go.mod", "web\n/package.json"]
    odd = [p for p in odd if creatable(sim.tmp, p.split("/")[0])]
    files = {p: "{}" if p.endswith(".json") else "module x\n" for p in odd + ["a.b/go.mod", "a/b/go.mod"]}
    repo = sim.repo("s29", files)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and jobs(repo) == ["go-a-b"] and job_block(repo, "go-a-b")[3] == '      directory: "a.b"'
    skipped = [line for line in notes(r) if line.startswith("note: no CI job for ")]
    assert len(skipped) == len(odd) + 1  # a/b/go.mod: job id go-a-b is taken by a.b
    check_bytes(r, SCAFFOLD_PREFIXES)
    d = sim.drift(repo)
    assert d.code == 0 and [f for f in findings(d) if f.endswith("ci-skipped")] == [
        f for f in findings(d) if f.startswith("info  ")
    ]
    assert len([f for f in findings(d) if f.endswith("  ci-skipped")]) == len(odd) + 1
    check_bytes(d, DRIFT_PREFIXES)

    # The .gitattributes line drift prints for "bad dir/go.mod" opts it out.
    head = 'info  "bad dir/go.mod"  ci-skipped: '
    fix = fix_lines(d, head)[0]
    line = fix.split("mark the manifest: ", 1)[1]
    assert line == '"/bad dir/go.mod" -bytewyrd-ci'
    write(repo, ".gitattributes", line + "\n")
    sim.commit(repo)
    d = sim.drift(repo)
    assert d.code == 0 and head + "opted out by -bytewyrd-ci" in d.lines


def test_s30_a_new_component_without_a_job_is_a_variant(sim):
    repo = s25_repo(sim)
    sim.commit(repo)
    write(repo, "cli/go.mod", "module c\n")
    sim.commit(repo)
    r = sim.drift(repo)
    head = "warn  .github/workflows/ci.yml  ci-variant: "
    assert r.code == 0 and findings(r) == ["warn  .github/workflows/ci.yml  ci-variant"]
    assert fix_lines(r, head)[1] == "/cli/go.mod -bytewyrd-ci"
    i = next(n for n, line in enumerate(r.lines) if line.startswith(head))
    assert r.lines[i + 3 : i + 7][0] == "    go-cli:" and r.lines[i + 6] == '        directory: "cli"'
    assert sim.drift(repo, "--strict").code == 2


def scaffold_and_drift(sim, repo, *args):
    r = sim.scaffold(repo, "--apply", *args)
    assert r.code == 0, r.out + r.err
    d = sim.drift(repo)
    assert d.code == 0, d.out
    return r, d


def test_s31_a_symlinked_root_manifest_is_never_read(sim):
    repo = sim.repo("s31", {"packages/a/package.json": "{}"}, commit=False)
    os.symlink("/dev/zero", repo / "package.json")
    sim.commit(repo)
    scaffold_and_drift(sim, repo)
    assert jobs(repo) == ["js", "js-packages-a"]


def test_s32_a_gitlink_at_a_manifest_path(sim):
    repo = sim.repo("s32", {"crates/c/Cargo.toml": CRATE})
    sim.git(repo, "update-index", "--add", "--cacheinfo", "160000,%s,Cargo.toml" % ("1" * 40))
    sim.git(repo, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-q", "-m", "gitlink")
    scaffold_and_drift(sim, repo, "--allow-dirty")
    assert jobs(repo) == ["rust", "rust-crates-c"]


@pytest.mark.parametrize(
    "root",
    [
        b'{"workspaces": ["packages/*"]}' + b" " * (2 << 20),  # S33: over 1 MiB
        b'{"workspaces": ["packages/*"], "x": ' + b"[" * 200000 + b"]" * 200000 + b"}",  # S34
        b'{"workspaces": ["packages/*"], "n": ' + b"7" * 5000 + b"}",  # S35
    ],
    ids=["s33-2MiB", "s34-deep", "s35-5000-digits"],
)
def test_s33_to_s35_an_unreadable_root_package_json_declares_nothing(sim, root):
    repo = sim.repo("r", {"package.json": root, "packages/a/package.json": "{}"})
    scaffold_and_drift(sim, repo)
    assert jobs(repo) == ["js", "js-packages-a"]


def test_s36_a_cargo_toml_that_is_not_utf8(sim):
    repo = sim.repo("s36", {"Cargo.toml": b"[workspace]\n# \xff\n", "crates/c/Cargo.toml": CRATE})
    scaffold_and_drift(sim, repo)
    assert jobs(repo) == ["rust", "rust-crates-c"]


def test_s37_wrong_shaped_workspaces(sim):
    files = {
        "Cargo.toml": '[workspace]\nmembers = "crates/*"\n',
        "package.json": json.dumps({"workspaces": [1, "packages/*"]}),
        "crates/c/Cargo.toml": CRATE,
        "packages/a/package.json": "{}",
    }
    repo = sim.repo("s37", files)
    scaffold_and_drift(sim, repo)
    assert jobs(repo) == ["js", "js-packages-a", "rust", "rust-crates-c"]


def test_s38_a_path_that_is_not_utf8(sim):
    name = os.fsdecode(b"caf\xe9")
    if not creatable(sim.tmp, name):
        pytest.skip("this filesystem refuses names that are not UTF-8")
    repo = sim.repo("s38", {"go.mod": "module x\n", name + ".txt": "x", name + "/go.mod": "module y\n"})
    r, d = scaffold_and_drift(sim, repo)
    assert jobs(repo) == ["go"]
    reason = "directory name not allowed (letters, digits, '.', '_' and '-', at most 64 characters)"
    assert notes(r) == ['note: no CI job for "caf\\351/go.mod": ' + reason]
    assert 'info  "caf\\351/go.mod"  ci-skipped: ' + reason in d.lines


def test_s39_ruby_needs_a_rakefile_and_python_a_project(sim):
    files = {
        "Gemfile": "",
        "app/Gemfile": "",
        "app/Rakefile": "",
        "app/.ruby-version": "3.3.6\n",
        "tool/pyproject.toml": "[tool.ruff]\nline-length = 100\n",
        "legacy/setup.py": "",
        "both/pyproject.toml": PROJECT + '[dependency-groups]\ndev = ["pytest>=9"]\n',
        "both/setup.py": "",
        "nopy/pyproject.toml": PROJECT,
    }
    repo = sim.repo("s39", files)
    r = sim.scaffold(repo, "--apply")
    assert r.code == 0 and jobs(repo) == ["python-both", "python-nopy", "ruby-app"]
    assert notes(r) == [
        "note: no CI job for Gemfile: no Rakefile (the ruby job runs bundle exec rake)",
        "note: no CI job for legacy/setup.py: no pyproject.toml with [project] (the python job runs uv sync)",
        "note: nopy/pyproject.toml lists pytest in no dependency group; the python CI job runs uv run pytest",
    ]
