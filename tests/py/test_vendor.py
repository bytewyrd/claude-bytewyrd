"""Tests for the vendored PyYAML (RFC 2026-11-09-scaffold-and-drift, B2
"Vendored PyYAML"): a command imports scripts/_vendor/yaml/, the PyYAML
version that uv.lock pins, without its C extension, also when another PyYAML
is installed; and only frontmatter.py imports it, so a module that doesn't
import frontmatter never loads it. They also cover
.github/scripts/vendor-pyyaml.py with its download stubbed; CI's lint job runs
its --check against the real sdist.
"""

import ast
import hashlib
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tomllib
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts"
PACKAGE = SCRIPTS / "bytewyrd"
VENDOR = SCRIPTS / "_vendor"


def locked_pyyaml():
    """uv.lock's one pyyaml package."""
    found = [p for p in tomllib.loads((REPO / "uv.lock").read_text())["package"] if p["name"] == "pyyaml"]
    assert len(found) == 1, found
    return found[0]


LOCKED = locked_pyyaml()


def load_script(path):
    """The module of the script at PATH, whose file name is not a module name."""
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


vendor_pyyaml = load_script(REPO / ".github" / "scripts" / "vendor-pyyaml.py")

# Runs the bootstrap's path setup through main(), with a command that prints
# nothing in an empty directory, then imports yaml as frontmatter.py does.
PROBE = """
import json, sys
sys.path.insert(0, sys.argv[1])
from bytewyrd import __main__ as bootstrap
assert bootstrap.main(["__main__.py", "compact-reminder"]) == 0
import yaml
print(json.dumps([yaml.__file__, yaml.__version__, yaml.__with_libyaml__]))
"""

WANT = [str(VENDOR / "yaml" / "__init__.py"), LOCKED["version"], False]


def probe(flags, cwd):
    proc = subprocess.run(
        [sys.executable, *flags, "-c", PROBE, str(SCRIPTS)], cwd=cwd, capture_output=True, encoding="utf-8"
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def test_the_launcher_s_flags_import_the_vendored_copy_without_libyaml(tmp_path):
    assert probe(["-I", "-S", "-B"], tmp_path) == WANT


def test_the_vendored_copy_wins_over_an_installed_pyyaml(tmp_path):
    # Without -S, site-packages is on sys.path, with the PyYAML of the dev
    # group, which uv installs for CI's test job.
    installed = subprocess.run(
        [sys.executable, "-I", "-B", "-c", "import yaml; print(yaml.__file__)"],
        cwd=tmp_path,
        capture_output=True,
        encoding="utf-8",
    )
    if installed.returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("no installed PyYAML for the vendored copy to win over, and CI must not skip")
        pytest.skip("no PyYAML installed for %s" % sys.executable)
    assert VENDOR not in Path(installed.stdout.strip()).parents
    assert probe(["-I", "-B"], tmp_path) == WANT


def test_the_vendored_copy_is_17_modules_and_no_extension():
    names = sorted(p.name for p in (VENDOR / "yaml").iterdir() if p.name != "__pycache__")
    assert len(names) == 17
    assert all(name.endswith(".py") for name in names), names


def test_uv_lock_pins_the_vendored_pyyaml(tmp_path):
    version, sdist = LOCKED["version"], LOCKED["sdist"]
    assert probe(["-I", "-S", "-B"], tmp_path)[1] == version
    assert "pyyaml==" + version in tomllib.loads((REPO / "pyproject.toml").read_text())["dependency-groups"]["dev"]
    assert sdist["url"].rsplit("/", 1)[1] == "pyyaml-%s.tar.gz" % version
    assert re.fullmatch(r"sha256:[0-9a-f]{64}", sdist["hash"])
    # vendor-pyyaml.py reads the same, and finds the lock and the pin as it requires them.
    assert vendor_pyyaml.locked_sdist(REPO) == (version, sdist["url"], sdist["hash"][len("sha256:") :], sdist["size"])


def package_modules():
    """The dotted name of each module of the package, the package itself included."""
    names = []
    for path in sorted(PACKAGE.rglob("*.py")):
        parts = path.relative_to(SCRIPTS).with_suffix("").parts
        names.append(".".join(parts[:-1] if parts[-1] == "__init__" else parts))
    return names


# The modules that must never load yaml: the class-A commands, which read no
# frontmatter, and the shared modules other than frontmatter.
NO_YAML = [
    *("bytewyrd." + m for m in ("cli", "git", "fs", "detect", "seed", "jsonout")),
    *("bytewyrd.commands." + m for m in ("scaffold", "drift", "state_touch", "compact_reminder")),
]

# Imports one module, with scripts and scripts/_vendor first on sys.path as the
# bootstrap puts them, and says whether frontmatter and yaml are now loaded.
IMPORT_PROBE = """
import importlib, json, sys
sys.path[0:0] = sys.argv[1:3]
importlib.import_module(sys.argv[3])
print(json.dumps(["bytewyrd.frontmatter" in sys.modules, "yaml" in sys.modules]))
"""


def test_a_module_loads_yaml_only_when_it_imports_frontmatter(tmp_path):
    modules = package_modules()
    assert {"bytewyrd", "bytewyrd.__main__", "bytewyrd.frontmatter", *NO_YAML} <= set(modules)
    loads = {}
    for module in modules:
        proc = subprocess.run(
            [sys.executable, "-I", "-S", "-B", "-c", IMPORT_PROBE, str(SCRIPTS), str(VENDOR), module],
            cwd=tmp_path,
            capture_output=True,
            encoding="utf-8",
        )
        assert (proc.returncode, proc.stderr) == (0, ""), module
        frontmatter, yaml = json.loads(proc.stdout)
        assert yaml == frontmatter, "importing %s: frontmatter loaded %s, yaml loaded %s" % (module, frontmatter, yaml)
        loads[module] = yaml
    assert loads["bytewyrd.frontmatter"]
    assert [m for m in NO_YAML if loads[m]] == []


def test_only_frontmatter_imports_yaml():
    for path in sorted(PACKAGE.rglob("*.py")):
        tree = ast.parse(path.read_text(), str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            else:
                continue
            if any(name == "yaml" or name.startswith("yaml.") for name in names):
                rel = path.relative_to(PACKAGE)
                assert rel == Path("frontmatter.py"), "%s imports yaml at line %d" % (rel, node.lineno)


# --- vendor-pyyaml.py, with the download stubbed ------------------------------

# A made-up release, so that the real sdist can't make a test pass. Only the
# LICENSE and the files directly under lib/yaml/ are vendored.
SDIST_MEMBERS = {
    "pyyaml-9.9.9/LICENSE": b"MIT License\n",
    "pyyaml-9.9.9/README.md": b"PyYAML\n",
    "pyyaml-9.9.9/lib/yaml/__init__.py": b"__version__ = '9.9.9'\n",
    "pyyaml-9.9.9/lib/yaml/loader.py": b"# loader\n",
    "pyyaml-9.9.9/lib/yaml/sub/deep.py": b"# below lib/yaml/\n",
    "pyyaml-9.9.9/lib/_yaml/__init__.py": b"# the extension's shim\n",
    "pyyaml-9.9.9/yaml/_yaml.pyx": b"# the extension\n",
}
VENDORED = {
    "PyYAML-LICENSE": b"MIT License\n",
    "yaml/__init__.py": b"__version__ = '9.9.9'\n",
    "yaml/loader.py": b"# loader\n",
}
SDIST_URL = "https://files.pythonhosted.org/packages/ab/cd/pyyaml-9.9.9.tar.gz"


def entry(name, kind=tarfile.REGTYPE, linkname=""):
    """A tar entry with no data: an empty file, a directory, a link or a device."""
    info = tarfile.TarInfo(name)
    info.type, info.linkname = kind, linkname
    return info


def make_sdist(members=SDIST_MEMBERS, entries=()):
    """A .tar.gz holding the lib/yaml directory, MEMBERS as regular files, then ENTRIES."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.addfile(entry("pyyaml-9.9.9/lib/yaml", tarfile.DIRTYPE))
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
        for info in entries:
            tar.addfile(info)
    return buf.getvalue()


SDIST = make_sdist()


def make_repo(
    tmp_path,
    data=SDIST,
    *,
    name="pyyaml",
    registry="https://pypi.org/simple",
    url=SDIST_URL,
    digest=None,
    size=None,
    extra="",
    pins='"pyyaml==9.9.9"',
):
    """A repository whose uv.lock locks DATA as the sdist of PyYAML 9.9.9, and whose dev group pins PINS.
    Each other keyword makes uv.lock wrong in one way."""
    root = tmp_path / "repo"
    root.mkdir()
    (root / "uv.lock").write_text(
        'version = 1\nrequires-python = ">=3.11"\n\n[[package]]\nname = "%s"\nversion = "9.9.9"\n'
        'source = { registry = "%s" }\nsdist = { url = "%s", hash = "%s", size = %s }\n%s'
        % (name, registry, url, digest or "sha256:" + hashlib.sha256(data).hexdigest(), size or len(data), extra)
    )
    (root / "pyproject.toml").write_text(
        '[dependency-groups]\ndev = ["pytest==9.2.0", %s, "types-pyyaml==6.0.12.20261113"]\n' % pins
    )
    return root


def run_vendor(root, *flags, data=SDIST):
    """vendor-pyyaml.py's exit code with FLAGS on ROOT, and its downloads, which return DATA."""
    calls = []

    def fetch(url, limit):
        calls.append((url, limit))
        return data[:limit]

    return vendor_pyyaml.main(["--root", str(root), *flags], fetch=fetch), calls


def files_under(directory):
    """{relative path: bytes} of every file under DIRECTORY, hidden ones included."""
    return {p.relative_to(directory).as_posix(): p.read_bytes() for p in sorted(directory.rglob("*")) if p.is_file()}


def put(directory, files):
    for rel, data in files.items():
        (directory / rel).parent.mkdir(parents=True, exist_ok=True)
        (directory / rel).write_bytes(data)


def test_a_rebuild_writes_exactly_the_locked_files_and_the_license(tmp_path, monkeypatch, capsys):
    def never(*args, **kwargs):
        raise AssertionError("vendor-pyyaml.py extracted from the sdist")

    monkeypatch.setattr(tarfile.TarFile, "extract", never)
    monkeypatch.setattr(tarfile.TarFile, "extractall", never)
    root = make_repo(tmp_path)
    vendor = root / "scripts" / "_vendor"
    put(vendor, {"PyYAML-LICENSE": b"old\n", "yaml/stale.py": b"old\n", "yaml/__pycache__/stale.pyc": b"old"})
    assert run_vendor(root) == (0, [(SDIST_URL, len(SDIST) + 1)])
    # The stale files are gone, and so is the temporary directory.
    assert files_under(vendor) == VENDORED
    assert capsys.readouterr().out == "rebuilt scripts/_vendor from pyyaml-9.9.9.tar.gz\n"


def test_check_passes_on_a_rebuilt_copy_skips_pycache_and_writes_nothing(tmp_path, capsys):
    root = make_repo(tmp_path)
    assert run_vendor(root)[0] == 0
    put(root / "scripts" / "_vendor", {"yaml/__pycache__/loader.cpython-311.pyc": b"bytecode"})
    before = files_under(root)
    capsys.readouterr()
    assert run_vendor(root, "--check")[0] == 0
    assert files_under(root) == before
    assert capsys.readouterr() == ("scripts/_vendor matches pyyaml-9.9.9.tar.gz\n", "")


@pytest.mark.parametrize(
    "change, finding",
    [
        (lambda v: (v / "yaml" / "extra.py").write_bytes(b"x\n"), "yaml/extra.py is not in the sdist"),
        (lambda v: (v / "yaml" / "loader.py").unlink(), "yaml/loader.py is missing; the sdist has it"),
        (lambda v: (v / "yaml" / "__init__.py").write_bytes(b"x\n"), "yaml/__init__.py differs from the sdist's"),
        (lambda v: (v / "PyYAML-LICENSE").unlink(), "PyYAML-LICENSE is missing; the sdist has it"),
    ],
    ids=["extra", "missing", "changed", "no-license"],
)
def test_check_fails_on_an_extra_a_missing_and_a_changed_file(tmp_path, capsys, change, finding):
    root = make_repo(tmp_path)
    assert run_vendor(root)[0] == 0
    change(root / "scripts" / "_vendor")
    before = files_under(root)
    capsys.readouterr()
    assert run_vendor(root, "--check")[0] == 1
    assert files_under(root) == before
    assert capsys.readouterr().err.splitlines() == [
        "vendor-pyyaml: scripts/_vendor/" + finding,
        "vendor-pyyaml: run .github/scripts/vendor-pyyaml.py to rebuild from pyyaml-9.9.9.tar.gz",
    ]


@pytest.mark.parametrize("flags", [[], ["--check"]], ids=["rebuild", "check"])
@pytest.mark.parametrize(
    "served", [SDIST[:-1] + bytes([SDIST[-1] ^ 1]), SDIST[:-1], SDIST + b"\0"], ids=["sha256", "short", "long"]
)
def test_a_size_or_hash_mismatch_fails_before_anything_is_written(tmp_path, capsys, served, flags):
    root = make_repo(tmp_path)
    put(root / "scripts" / "_vendor", {"yaml/stale.py": b"old\n"})
    before = files_under(root)
    assert run_vendor(root, *flags, data=served)[0] == 1
    assert files_under(root) == before
    err = capsys.readouterr().err
    assert err.startswith("vendor-pyyaml: %s: read %d bytes, sha256 " % (SDIST_URL, len(served)))
    assert err.endswith("; uv.lock has %d, %s\n" % (len(SDIST), hashlib.sha256(SDIST).hexdigest()))


@pytest.mark.parametrize(
    "wrong",
    [
        {"name": "pyyaml-other"},
        {
            "extra": '\n[[package]]\nname = "pyyaml"\nversion = "5.4"\nsource = { registry = "https://pypi.org/simple" }\n'
        },
        {"registry": "https://test.pypi.org/simple"},
        {"url": "https://example.org/packages/ab/cd/pyyaml-9.9.9.tar.gz"},
        {"url": "https://files.pythonhosted.org/packages/ab/cd/pyyaml-9.9.8.tar.gz"},
        {"digest": "sha512:" + "0" * 128},
        {"digest": "sha256:" + "A" * 64},
        {"size": '"%d"' % len(SDIST)},
        {"pins": '"pyyaml>=9.9.9"'},
        {"pins": '"pyyaml==9.9.8"'},
        {"pins": '"pyyaml==9.9.9", "PyYAML[extra]==9.9.9"'},
        {"pins": '"pytest-yaml==1.0"'},
    ],
)
def test_a_lock_or_pin_that_is_not_as_required_fails_without_a_download(tmp_path, capsys, wrong):
    root = make_repo(tmp_path, **wrong)
    assert run_vendor(root, "--check") == (1, [])
    err = capsys.readouterr().err
    assert err.startswith("vendor-pyyaml: ") and err.count("\n") == 1


@pytest.mark.parametrize(
    "bad, reason",
    [
        (
            entry("pyyaml-9.9.9/lib/yaml/link.py", tarfile.SYMTYPE, "/etc/passwd"),
            "is not a regular file or a directory",
        ),
        (entry("pyyaml-9.9.9/lib/yaml/hard.py", tarfile.LNKTYPE, "pyyaml-9.9.9/LICENSE"), "is not a regular file"),
        (entry("pyyaml-9.9.9/null", tarfile.CHRTYPE), "is not a regular file or a directory"),
        (entry("pyyaml-9.9.9/fifo", tarfile.FIFOTYPE), "is not a regular file or a directory"),
        (entry("pyyaml-9.9.9/lib/yaml/../../../../evil.py"), "the sdist holds an unsafe path"),
        (entry("/etc/evil.py"), "the sdist holds an unsafe path"),
    ],
    ids=["symlink", "hard-link", "device", "fifo", "dot-dot", "absolute"],
)
def test_a_link_a_device_or_an_unsafe_path_fails_before_anything_is_written(tmp_path, capsys, bad, reason):
    data = make_sdist(entries=[bad])
    root = make_repo(tmp_path, data)
    put(root / "scripts" / "_vendor", {"yaml/stale.py": b"old\n"})
    before = files_under(root)
    assert run_vendor(root, data=data)[0] == 1
    assert files_under(root) == before
    err = capsys.readouterr().err
    assert err.startswith("vendor-pyyaml: ") and reason in err and repr(bad.name) in err


@pytest.mark.parametrize("missing", ["pyyaml-9.9.9/LICENSE", "pyyaml-9.9.9/lib/yaml/"])
def test_an_sdist_without_the_license_or_the_modules_fails_before_anything_is_written(tmp_path, capsys, missing):
    data = make_sdist({name: body for name, body in SDIST_MEMBERS.items() if not name.startswith(missing)})
    root = make_repo(tmp_path, data)
    assert run_vendor(root, data=data)[0] == 1
    assert not (root / "scripts").exists()
    assert "the sdist lacks pyyaml-9.9.9/LICENSE or the files of pyyaml-9.9.9/lib/yaml/" in capsys.readouterr().err
