"""Tests for bw.load_frontmatter() (RFC 2026-11-09-scaffold-and-drift, B2
"Frontmatter parsing"): one fixture per row of B2's conversion table, the
errors that rfc-frontmatter reports with exit 2, and every RFC under
docs/rfcs/, which must parse, and which rfc-frontmatter must print as
load_frontmatter() reads it.

The cases run in this process, with scripts/_lib and scripts/_vendor at the
front of sys.path as bw_main.py puts them, so load_frontmatter() imports the
vendored PyYAML; test_vendor.py checks that import under the launcher's flags.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "scripts" / "_lib"
VENDOR = REPO / "scripts" / "_vendor"
sys.path[0:0] = [str(LIB), str(VENDOR)]

import bw  # noqa: E402

IS_ROOT = hasattr(os, "geteuid") and os.geteuid() == 0
FIELDS = ("rfc", "title", "author", "status", "created", "drop_reason")
EMPTY = dict.fromkeys(FIELDS, "")


@pytest.fixture(autouse=True)
def in_tmp(tmp_path, monkeypatch):
    """Run in TMP_PATH, so files and messages use short relative names."""
    monkeypatch.chdir(tmp_path)


def write(name, text):
    with open(name, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return name


def load(block, name="x.md"):
    """load_frontmatter() of a file holding BLOCK between "---" lines, then a body."""
    return bw.load_frontmatter(write(name, "---\n" + block + "---\n\n## Summary\n"))


def error(block, name="x.md"):
    """The BwError message load_frontmatter() raises for BLOCK."""
    with pytest.raises(bw.BwError) as e:
        load(block, name)
    return str(e.value)


def every_field(value):
    """A block that gives each of the six fields VALUE, written after "key:"."""
    return "".join("%s:%s\n" % (key, " " + value if value else "") for key in FIELDS)


# --- the result --------------------------------------------------------------


def test_the_six_fields_in_rfc_frontmatter_s_order():
    block = 'rfc: "a"\ntitle: "T"\nauthor: "A"\nstatus: "Draft"\ncreated: "2026-01-01"\ndrop_reason: ~\n'
    got = load(block)
    assert list(got) == list(FIELDS) == list(bw.FRONTMATTER_FIELDS)
    assert got == {"rfc": "a", "title": "T", "author": "A", "status": "Draft", "created": "2026-01-01", "drop_reason": ""}


def test_a_missing_field_is_empty_and_other_keys_may_hold_anything():
    got = load("rfc: x\nimplemented_by: [a, b]\nreviewers:\n  sec: {name: y}\nnotes: !!binary aGk=\n")
    assert got == dict(EMPTY, rfc="x")


@pytest.mark.parametrize("block", ["", "# only a comment\n", "\n\n"])
def test_an_empty_block_gives_six_empty_fields(block):
    assert load(block) == EMPTY


def test_only_the_lines_between_the_first_two_delimiters_count():
    text = "---\nrfc: a\n---\nstatus: Done\n---\ntitle: [unparsed\n"
    assert bw.load_frontmatter(write("x.md", text)) == dict(EMPTY, rfc="a")


def test_the_closing_delimiter_may_end_the_file():
    assert bw.load_frontmatter(write("x.md", "---\nrfc: a\n---")) == dict(EMPTY, rfc="a")


def test_a_later_key_wins_as_in_rfc_frontmatter_sh():
    assert load("rfc: a\nrfc: b\n")["rfc"] == "b"


def test_path_may_be_a_path_object():
    write("x.md", "---\nrfc: a\n---\n")
    assert bw.load_frontmatter(Path("x.md"))["rfc"] == "a"


# --- B2's conversion table, row by row -----------------------------------------


@pytest.mark.parametrize(
    "value, want",
    [
        # Plain scalars are the text as written: FrontmatterLoader has no
        # implicit resolvers, so nothing becomes a date, bool or int.
        ("2026-11-09", "2026-11-09"),
        ("yes", "yes"),
        ("12", "12"),
        # A plain scalar holding ", which bash deleted.
        ('Plain "title"', 'Plain "title"'),
        # ~, null and an empty value, in every field; bash did this for
        # drop_reason's ~ only.
        ("~", ""),
        ("null", ""),
        ("", ""),
        # Double-quoted values are YAML-unescaped. bash undid only \" and \\,
        # and kept other escapes, such as \t, as written.
        (r'"a \"b\""', 'a "b"'),
        (r'"C:\\temp\\new"', "C:\\temp\\new"),
        (r'"a\tb"', "a\tb"),
        # Single-quoted values are YAML-unquoted; bash kept the quotes.
        ("'it''s'", "it's"),
        # A trailing comment is dropped; bash kept it and deleted the quotes.
        ('"Draft" # still a draft', "Draft"),
        ("Draft # still a draft", "Draft"),
    ],
)
def test_conversion(value, want):
    assert load(every_field(value)) == dict.fromkeys(FIELDS, want)


@pytest.mark.parametrize(
    "block, kind",
    [
        ("title: [a, b]\n", "a list"),
        ("title:\n  - a\n  - b\n", "a list"),
        ("title: {a: b}\n", "a mapping"),
        ("title:\n  a: b\n", "a mapping"),
        ("title: !!set {a, b}\n", "a mapping"),
    ],
)
def test_a_list_or_mapping_is_an_error(block, kind):
    assert error(block) == "x.md: title is %s, not a string" % kind


def test_invalid_yaml_such_as_an_unquoted_colon_is_an_error():
    assert error('rfc: "a"\ntitle: RFC: x\n') == "x.md:3: frontmatter is not valid YAML (mapping values are not allowed here)"


def test_an_alias_is_an_error_and_an_anchor_alone_is_not():
    assert error("rfc: &a x\ntitle: *a\n") == "x.md:3: frontmatter may not use an alias"
    assert load("rfc: &a x\n")["rfc"] == "x"


def test_aliases_that_would_expand_are_refused_before_they_grow():
    # Each line holds nine of the line before, so the last would expand to
    # 9**9 strings if the first alias were let through.
    lines = ['a: &a ["lol","lol","lol","lol","lol","lol","lol","lol","lol"]']
    for prev, cur in zip("abcdefgh", "bcdefghi"):
        lines.append("%s: &%s [%s]" % (cur, cur, ",".join(["*" + prev] * 9)))
    assert error("\n".join(lines) + "\n") == "x.md:3: frontmatter may not use an alias"


def test_a_block_of_64_kib_parses_and_one_byte_more_is_an_error():
    head = 'rfc: "a"\n'
    pad = bw.MAX_FRONTMATTER - len(head) - len("#\n")
    block = head + "#" + "x" * pad + "\n"
    assert len(block.encode()) == bw.MAX_FRONTMATTER == 64 * 1024
    assert load(block)["rfc"] == "a"
    assert error(head + "#" + "x" * (pad + 1) + "\n") == "x.md: frontmatter is over 64 KiB"


def test_one_line_over_64_kib_is_an_error():
    assert error("title: " + "x" * bw.MAX_FRONTMATTER + "\n") == "x.md: frontmatter is over 64 KiB"


# --- other errors -----------------------------------------------------------------


@pytest.mark.parametrize(
    "block",
    [
        "created: !!timestamp 2026-11-09\n",
        "created: !!int 12\n",
        "created: !!bool yes\n",
    ],
)
def test_an_explicitly_tagged_non_string_field_is_an_error(block):
    # B2's table has no row for explicit tags: a field must still be a string.
    assert error(block).startswith("x.md: created is a tagged ")


def test_explicit_str_and_null_tags_are_strings():
    assert load("rfc: !!str 12\ntitle: !!null ''\n") == dict(EMPTY, rfc="12")


def test_a_python_tag_is_refused_without_running_anything():
    marker = Path("ran").resolve()
    message = error('x: !!python/object/apply:os.system ["touch %s"]\n' % marker)
    assert message.startswith("x.md:2: frontmatter is not valid YAML (could not determine a constructor for the tag ")
    assert not marker.exists()


def test_deep_nesting_is_an_error():
    assert error("title: " + "[" * 5000 + "]" * 5000 + "\n") == "x.md: frontmatter nests too deeply"


@pytest.mark.parametrize("block", ["- a\n- b\n", "just text\n"])
def test_a_block_that_is_not_a_mapping_is_an_error(block):
    assert error(block) == "x.md: frontmatter is not a mapping of key: value pairs"


def test_a_block_that_is_not_utf_8_is_an_error():
    with open("x.md", "wb") as f:
        f.write(b"---\ntitle: caf\xe9\n---\n")
    with pytest.raises(bw.BwError, match=r"^x\.md: frontmatter is not valid UTF-8$"):
        bw.load_frontmatter("x.md")


def test_a_body_that_is_not_utf_8_is_never_read():
    with open("x.md", "wb") as f:
        f.write(b"---\nrfc: a\n---\n\xff\xfe\n")
    assert bw.load_frontmatter("x.md")["rfc"] == "a"


@pytest.mark.parametrize(
    "text",
    [
        "# Just a markdown file\n\nNo frontmatter.\n",
        "\n---\nrfc: a\n---\n",
        "--- \nrfc: a\n---\n",
        "----\nrfc: a\n----\n",
        "\ufeff---\nrfc: a\n---\n",
        # A CRLF file, which rfc-frontmatter.sh also refuses: its first line is "---\r".
        "---\r\nrfc: a\r\n---\r\n",
        "",
    ],
)
def test_line_1_must_be_the_delimiter(text):
    with pytest.raises(bw.BwError) as e:
        bw.load_frontmatter(write("x.md", text))
    assert str(e.value) == "x.md does not begin with a YAML frontmatter delimiter"


@pytest.mark.parametrize("text", ["---\nrfc: a\n", "---\n", "---"])
def test_a_block_with_no_closing_delimiter_is_an_error(text):
    with pytest.raises(bw.BwError) as e:
        bw.load_frontmatter(write("x.md", text))
    assert str(e.value) == "x.md has no closing frontmatter delimiter"


def test_what_is_not_a_regular_file_is_not_found_and_never_read():
    os.mkdir("dir")
    os.mkfifo("fifo")
    os.symlink("/dev/zero", "zero")
    os.symlink("missing", "dangling")
    write("file", "x")
    for name in ("dir", "fifo", "zero", "dangling", "absent", "file/below"):
        with pytest.raises(bw.BwError) as e:
            bw.load_frontmatter(name)
        assert str(e.value) == "file not found: %s" % name


def test_a_symlink_to_an_rfc_is_followed():
    write("real.md", "---\nrfc: a\n---\n")
    os.symlink("real.md", "link.md")
    assert bw.load_frontmatter("link.md")["rfc"] == "a"


@pytest.mark.skipif(IS_ROOT, reason="root reads any file")
def test_an_unreadable_file_is_an_error():
    write("x.md", "---\nrfc: a\n---\n")
    os.chmod("x.md", 0)
    with pytest.raises(bw.BwError, match=r"^cannot read x\.md: Permission denied$"):
        bw.load_frontmatter("x.md")


# --- the loader ----------------------------------------------------------------


def test_frontmatter_loader_is_a_safe_loader_with_no_implicit_resolvers():
    loader = bw.FrontmatterLoader  # built, and yaml imported, on first access
    yaml = sys.modules["yaml"]
    assert issubclass(loader, yaml.SafeLoader)
    assert loader.yaml_implicit_resolvers == {}
    assert yaml.SafeLoader.yaml_implicit_resolvers  # the parent keeps its own


def test_these_cases_ran_the_vendored_pyyaml():
    load("rfc: a\n")
    assert Path(sys.modules["yaml"].__file__).parent == VENDOR / "yaml"


# --- the RFCs in this repository --------------------------------------------------

RFCS = sorted((REPO / "docs" / "rfcs").glob("*.md"))


def test_docs_rfcs_holds_the_rfcs():
    assert len(RFCS) >= 24


@pytest.mark.parametrize("rfc", RFCS, ids=lambda p: p.name)
def test_each_rfc_parses_and_rfc_frontmatter_prints_what_load_frontmatter_reads(rfc):
    fields = bw.load_frontmatter(rfc)
    assert list(fields) == list(FIELDS)
    proc = subprocess.run(
        [sys.executable, "-I", "-S", "-B", str(LIB / "bw_main.py"), "rfc-frontmatter", str(rfc)],
        capture_output=True,
    )
    assert (proc.returncode, proc.stdout, proc.stderr) == (0, bw.jq_dumps(fields).encode("utf-8"), b"")
