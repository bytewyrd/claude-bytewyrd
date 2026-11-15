"""Tests for the vendored PyYAML (RFC 2026-11-09-scaffold-and-drift, B2
"Vendored PyYAML"): a command imports scripts/_vendor/yaml/, PyYAML 6.0.3,
without its C extension, also when another PyYAML is installed; and only
load_frontmatter() imports it. CI's lint job checks the copy against the
sdist itself.
"""

import ast
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "scripts" / "_lib"
VENDOR = REPO / "scripts" / "_vendor"

# Runs bw_main.py's path setup through main(), with a command that prints
# nothing in an empty directory, then imports yaml as load_frontmatter() does.
PROBE = """
import json, sys
sys.path.insert(0, sys.argv[1])
import bw_main
assert bw_main.main(["bw_main.py", "compact-reminder"]) == 0
import yaml
print(json.dumps([yaml.__file__, yaml.__version__, yaml.__with_libyaml__]))
"""

WANT = [str(VENDOR / "yaml" / "__init__.py"), "6.0.3", False]


def probe(flags, cwd):
    proc = subprocess.run(
        [sys.executable, *flags, "-c", PROBE, str(LIB)], cwd=cwd, capture_output=True, encoding="utf-8"
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def test_the_launcher_s_flags_import_the_vendored_copy_without_libyaml(tmp_path):
    assert probe(["-I", "-S", "-B"], tmp_path) == WANT


def test_the_vendored_copy_wins_over_an_installed_pyyaml(tmp_path):
    # Without -S, site-packages is on sys.path, with the PyYAML that CI's test
    # job installs with pip.
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


def test_no_command_imports_yaml_until_it_reads_frontmatter(tmp_path):
    (tmp_path / "x.md").write_text("---\nrfc: a\n---\n")
    modules = sorted(p.stem for p in LIB.glob("bw*.py"))
    assert {"bw", "bw_main", "bw_scaffold", "bw_drift", "bw_state_touch", "bw_compact_reminder"} <= set(modules)
    code = (
        "import importlib, sys; sys.path[0:0] = sys.argv[1:3]; "
        "[importlib.import_module(m) for m in sys.argv[3:]]; "
        "print('yaml' in sys.modules); import bw; bw.load_frontmatter('x.md'); print('yaml' in sys.modules)"
    )
    proc = subprocess.run(
        [sys.executable, "-I", "-S", "-B", "-c", code, str(LIB), str(VENDOR), *modules],
        cwd=tmp_path,
        capture_output=True,
        encoding="utf-8",
    )
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, "False\nTrue\n", "")


def test_only_bw_py_imports_yaml_and_only_inside_a_function():
    for path in sorted(LIB.glob("*.py")):
        tree = ast.parse(path.read_text(), str(path))
        top_level = set(tree.body)
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            else:
                continue
            if any(name == "yaml" or name.startswith("yaml.") for name in names):
                assert path.name == "bw.py", "%s imports yaml at line %d" % (path.name, node.lineno)
                assert node not in top_level, "bw.py imports yaml at module level, line %d" % node.lineno
