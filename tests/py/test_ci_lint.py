"""Tests for the CI lint helpers in .github/scripts/:

    lint-frontmatter.py  strict-YAML lint for agent and skill frontmatter
    check-links.py       relative Markdown link check

Each test writes its fixtures into a temporary directory and runs the script
there as a child process, in an environment built here, so the repository's own
agents, skills and Markdown are never involved. Both scripts print their
findings and a summary line to stdout and nothing to stderr, so each test checks
that stderr is empty and everything else against stdout. A passing run prints
only the summary line, which the tests compare whole.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LINT_FRONTMATTER = REPO / ".github" / "scripts" / "lint-frontmatter.py"
CHECK_LINKS = REPO / ".github" / "scripts" / "check-links.py"


@pytest.fixture(autouse=True)
def in_tmp(tmp_path, monkeypatch):
    """Run in TMP_PATH, so fixtures get the short relative names the scripts print."""
    monkeypatch.chdir(tmp_path)


@pytest.fixture
def env(tmp_path, tmp_path_factory):
    """The environment of every child process, built here rather than copied from the developer's."""
    env = {
        "PATH": os.environ.get("PATH", os.defpath),
        # An empty home keeps the developer's global git ignore file out of git add.
        "HOME": str(tmp_path_factory.mktemp("home")),
        # Neither the developer's nor the system's git configuration, and no repository above TMP_PATH.
        # GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_COMMON_DIR and GIT_OBJECT_DIRECTORY, which a git
        # hook can set, are left out so that git never works on the real repository. So is GITHUB_ACTIONS,
        # under which the scripts add ::error lines to their output.
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CEILING_DIRECTORIES": str(tmp_path.parent),
    }
    # Where a sandbox lets a child write.
    if os.environ.get("TMPDIR"):
        env["TMPDIR"] = os.environ["TMPDIR"]
    return env


@pytest.fixture
def run(tmp_path, env):
    """run(SCRIPT, *ARGS): SCRIPT under this interpreter in TMP_PATH, as (exit code, stdout, stderr)."""

    def run(script, *args):
        proc = subprocess.run(
            [sys.executable, str(script), *args], cwd=tmp_path, env=env, capture_output=True, timeout=60
        )
        return proc.returncode, proc.stdout.decode("utf-8", "replace"), proc.stderr.decode("utf-8", "replace")

    return run


@pytest.fixture
def git(tmp_path, env):
    """git(*ARGS) in TMP_PATH under the child environment; the test fails if git does."""

    def git(*args):
        proc = subprocess.run(["git", *args], cwd=tmp_path, env=env, capture_output=True, timeout=60)
        assert proc.returncode == 0, proc.stderr

    return git


@pytest.fixture
def require_pyyaml(tmp_path, env):
    """Skip unless the interpreter that runs the scripts can import PyYAML; under CI, fail instead."""
    # Ask a child: here, pyproject.toml's pythonpath makes `import yaml` find the vendored copy,
    # which says nothing about the interpreter lint-frontmatter.py runs under.
    probe = subprocess.run(
        [sys.executable, "-c", "import yaml"], cwd=tmp_path, env=env, capture_output=True, timeout=60
    )
    if probe.returncode != 0:
        if os.environ.get("CI"):
            pytest.fail("PyYAML is not importable by %s, and CI must not skip these tests" % sys.executable)
        pytest.skip("PyYAML is required by lint-frontmatter.py, and %s cannot import it" % sys.executable)


# --- lint-frontmatter.py -----------------------------------------------------


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_a_folded_block_description_with_a_colon_and_a_hash_passes(run):
    Path("a.md").write_text(
        "---\n"
        "name: a\n"
        "description: >-\n"
        "  Use it. Examples: <example>x: y</example> under ## Heading.\n"
        "model: opus\n"
        "---\n"
        "body\n"
    )
    assert run(LINT_FRONTMATTER, "a.md") == (0, "frontmatter lint: 1 file(s) checked, 0 failed\n", "")


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_a_plain_description_with_a_colon_fails_with_its_line_number(run):
    Path("a.md").write_text("---\nname: a\ndescription: Use it. Examples: <example>Context: x</example>\n---\n")
    code, out, err = run(LINT_FRONTMATTER, "a.md")
    assert (code, err) == (1, "")
    assert "a.md:3: frontmatter is not valid YAML (mapping values are not allowed here)" in out


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_a_plain_value_truncated_by_a_hash_fails(run):
    Path("a.md").write_text("---\nname: a\ndescription: Entries stay under ## Project-Specific.\n---\n")
    code, out, err = run(LINT_FRONTMATTER, "a.md")
    assert (code, err) == (1, "")
    assert 'a.md:3: "description" is followed by " #..."' in out


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_a_quoted_value_containing_a_hash_and_a_full_line_comment_pass(run):
    Path("a.md").write_text(
        '---\n# a comment line\nname: a\ndescription: "Entries stay under ## Project-Specific."\n---\n'
    )
    assert run(LINT_FRONTMATTER, "a.md") == (0, "frontmatter lint: 1 file(s) checked, 0 failed\n", "")


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_missing_frontmatter_missing_closing_fence_and_missing_description_fail(run):
    Path("none.md").write_text("no frontmatter\n")
    Path("open.md").write_text("---\nname: a\ndescription: x\n")
    Path("nodesc.md").write_text("---\nname: a\n---\n")
    code, out, err = run(LINT_FRONTMATTER, "none.md", "open.md", "nodesc.md")
    assert (code, err) == (1, "")
    assert "none.md:1: missing frontmatter" in out
    assert 'open.md:1: frontmatter has no closing "---" line' in out
    assert 'nodesc.md:2: "description" must be a non-empty string' in out
    assert "3 file(s) checked, 3 failed" in out


@pytest.mark.usefixtures("require_pyyaml")
def test_frontmatter_a_duplicate_key_fails_and_names_the_first_occurrence(run):
    Path("a.md").write_text("---\nname: a\ndescription: first\ndescription: second\n---\n")
    code, out, err = run(LINT_FRONTMATTER, "a.md")
    assert (code, err) == (1, "")
    assert 'a.md:4: duplicate key "description" (first on line 3)' in out


# --- check-links.py ----------------------------------------------------------


def test_links_an_existing_relative_target_passes_with_or_without_an_anchor(run):
    Path("docs").mkdir()
    Path("docs/target.md").write_text("# x\n")
    Path("docs/source.md").write_text("See [t](target.md) and [t2](target.md#x) and [dir](../docs/).\n")
    assert run(CHECK_LINKS, "docs/source.md") == (0, "link check: 1 file(s) checked, 0 broken link(s)\n", "")


def test_links_a_broken_relative_target_fails_with_file_line_and_resolved_path(run):
    Path("docs").mkdir()
    Path("docs/CONTRIBUTING.md").write_text("line one\nSee [rfc](docs/rfc-process.md).\n")
    code, out, err = run(CHECK_LINKS, "docs/CONTRIBUTING.md")
    assert (code, err) == (1, "")
    assert (
        "docs/CONTRIBUTING.md:2: broken relative link docs/rfc-process.md (resolves to docs/docs/rfc-process.md" in out
    )


def test_links_code_fences_inline_code_html_comments_and_urls_are_ignored(run):
    Path("a.md").write_text(
        "```markdown\n"
        "[fenced](missing-1.md)\n"
        "```\n"
        "Inline `[code](missing-2.md)` span.\n"
        "<!-- [comment](missing-3.md) -->\n"
        "[web](https://example.com/missing-4.md) and [mail](mailto:x@example.com) and [anchor](#top).\n"
    )
    assert run(CHECK_LINKS, "a.md") == (0, "link check: 1 file(s) checked, 0 broken link(s)\n", "")


def test_links_broken_reference_definitions_and_images_are_reported(run):
    Path("a.md").write_text("![img](missing.png)\n\n[ref]: missing-ref.md\n")
    code, out, err = run(CHECK_LINKS, "a.md")
    assert (code, err) == (1, "")
    assert "a.md:1: broken relative link missing.png" in out
    assert "a.md:3: broken relative link missing-ref.md" in out


def test_links_a_root_relative_target_resolves_against_the_working_directory(run):
    Path("docs").mkdir()
    Path("sub").mkdir()
    Path("docs/target.md").write_text("x\n")
    Path("sub/a.md").write_text("[ok](/docs/target.md) [bad](/docs/missing.md)\n")
    code, out, err = run(CHECK_LINKS, "sub/a.md")
    assert (code, err) == (1, "")
    assert "broken relative link /docs/missing.md" in out
    assert "/docs/target.md" not in out


def test_links_with_no_arguments_only_tracked_md_files_are_checked(run, git):
    git("init", "-q", ".")
    Path("tracked.md").write_text("[bad](nowhere.md)\n")
    Path("untracked.md").write_text("[bad](nowhere.md)\n")
    Path("template.md.tpl").write_text("[bad](nowhere.md)\n")
    git("add", "tracked.md", "template.md.tpl")
    code, out, err = run(CHECK_LINKS)
    assert (code, err) == (1, "")
    # Anchored: "untracked.md:1:" contains "tracked.md:1:", so a bare substring check would pass for either file.
    assert out.startswith("tracked.md:1: ")
    assert "untracked.md" not in out
    assert "template.md.tpl" not in out
    assert "1 file(s) checked, 1 broken link(s)" in out


def test_links_an_indented_fence_inside_a_list_item_is_skipped(run):
    Path("a.md").write_text("- item\n\n    ```bash\n    [x](missing.md)\n    ```\n")
    assert run(CHECK_LINKS, "a.md") == (0, "link check: 1 file(s) checked, 0 broken link(s)\n", "")


def test_links_escaped_brackets_are_not_a_link(run):
    Path("a.md").write_text(r"\[x\](missing.md) and \[y](missing2.md)" + "\n")
    assert run(CHECK_LINKS, "a.md") == (0, "link check: 1 file(s) checked, 0 broken link(s)\n", "")


def test_links_balanced_parentheses_in_a_target_are_part_of_the_path(run):
    Path("notes(1).md").write_text("x\n")
    Path("a.md").write_text("[ok](notes(1).md) [bad](notes(2).md)\n")
    code, out, err = run(CHECK_LINKS, "a.md")
    assert (code, err) == (1, "")
    assert "broken relative link notes(2).md" in out
    assert "notes(1).md" not in out


def test_links_prose_that_looks_like_a_reference_label_is_not_a_definition(run):
    Path("a.md").write_text('[Note]: this sentence is prose, not a link.\n\n[ref]: missing-ref.md "A title"\n')
    code, out, err = run(CHECK_LINKS, "a.md")
    assert (code, err) == (1, "")
    assert "a.md:3: broken relative link missing-ref.md" in out
    assert "a.md:1:" not in out
