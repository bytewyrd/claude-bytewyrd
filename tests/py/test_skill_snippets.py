"""Tests for the Step 2 snippet of /rfc-approve and /rfc-drop, which reads the
RFC's frontmatter with

    fm="$(sh "${CLAUDE_PLUGIN_ROOT}/scripts/bw" rfc-frontmatter "$RFC_PATH")" || { printf '%s\\n' "$fm"; exit 1; }

The helper reports a missing file as JSON on stdout. The launcher reports a
missing Python 3.11 or newer on stderr. In both cases the snippet must stop
and show the error instead of carrying on with an empty status. Each case
runs the snippet as SKILL.md holds it, under bash, through the real launcher.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SKILLS = ("rfc-approve", "rfc-drop")
NEEDS = "bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)"


def step_2_snippet(skill):
    """The fenced bash block in skills/SKILL/SKILL.md that runs rfc-frontmatter."""
    text = (REPO / "skills" / skill / "SKILL.md").read_text()
    for block in re.findall(r"^```bash\n(.*?)^```$", text, re.M | re.S):
        if '/scripts/bw" rfc-frontmatter ' in block:
            return block
    raise AssertionError("no Step 2 snippet in skills/%s/SKILL.md" % skill)


def run_snippet(skill, cwd, env):
    return subprocess.run([shutil.which("bash"), "-c", step_2_snippet(skill)], cwd=cwd, env=env, capture_output=True)


@pytest.mark.parametrize("skill", SKILLS)
def test_step_2_stops_on_a_json_error_and_shows_it(skill, tmp_path):
    rfc = tmp_path / "docs" / "rfcs" / "missing.md"
    env = {
        "PATH": os.environ.get("PATH", os.defpath),
        "BYTEWYRD_PYTHON": sys.executable,
        "CLAUDE_PLUGIN_ROOT": str(REPO),
        "RFC_PATH": str(rfc),
    }
    proc = run_snippet(skill, tmp_path, env)
    error = '{\n  "error": %s\n}\n' % json.dumps("rfc-frontmatter: file not found: %s" % rfc, ensure_ascii=False)
    assert (proc.returncode, proc.stdout, proc.stderr) == (1, error.encode(), b"")


@pytest.mark.parametrize("skill", SKILLS)
def test_step_2_stops_when_the_launcher_finds_no_python(skill, tmp_path):
    # PATH holds only sh, so the launcher finds no interpreter and puts its
    # JSON error on stderr. $fm is then empty, and the snippet prints only
    # the newline after it.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "sh").symlink_to(shutil.which("sh"))
    env = {"PATH": str(bin_dir), "CLAUDE_PLUGIN_ROOT": str(REPO), "RFC_PATH": "x.md"}
    proc = run_snippet(skill, tmp_path, env)
    assert (proc.returncode, proc.stdout, proc.stderr) == (1, b"\n", ('{"error":"%s"}\n' % NEEDS).encode())
