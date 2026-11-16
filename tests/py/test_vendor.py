"""Tests for the vendored PyYAML (RFC 2026-11-09-scaffold-and-drift, B2
"Vendored PyYAML"): a command imports scripts/_vendor/yaml/, PyYAML 6.0.3,
without its C extension, also when another PyYAML is installed; and only
frontmatter.py imports it, so a module that doesn't import frontmatter never
loads it. CI's lint job checks the copy against the sdist itself.
"""

import ast
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts"
PACKAGE = SCRIPTS / "bytewyrd"
VENDOR = SCRIPTS / "_vendor"

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

WANT = [str(VENDOR / "yaml" / "__init__.py"), "6.0.3", False]


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


def test_the_sha256_file_names_the_sdist():
    fields = (VENDOR / "PyYAML-6.0.3.sha256").read_text().split()
    assert fields == ["d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f", "pyyaml-6.0.3.tar.gz"]


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
