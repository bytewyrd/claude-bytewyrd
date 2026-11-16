"""load_frontmatter(), the only code that parses YAML: an RFC's six
rfc-frontmatter fields, read through FrontmatterLoader, a SafeLoader that
refuses aliases, from a block of at most 64 KiB.

This is the only module that imports yaml, so the commands that parse no
frontmatter never load it. Run through scripts/bw, yaml is the vendored
scripts/_vendor/yaml.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2
("Frontmatter parsing").
"""

import os
import stat as stat_module

import yaml

from bytewyrd import cli

# The fields rfc-frontmatter prints, in its order.
FRONTMATTER_FIELDS: tuple[str, ...] = ("rfc", "title", "author", "status", "created", "drop_reason")

MAX_FRONTMATTER: int = 64 << 10  # load_frontmatter() refuses a longer block

# The delimiter line; the closing one may end the file without a newline.
_DELIMITER: bytes = b"---\n"

# Values a field reads as "": YAML's ~ and null, which stay strings under
# FrontmatterLoader (the empty value is "" already).
_NULLS: tuple[str, ...] = ("~", "null")


class _Alias(Exception):
    """FrontmatterLoader's refusal of an alias, which starts at MARK."""

    def __init__(self, mark: yaml.Mark) -> None:
        super().__init__(mark)
        self.mark = mark


class FrontmatterLoader(yaml.SafeLoader):
    """A SafeLoader with no implicit resolvers, so every plain scalar stays
    the string as written (2026-11-09, yes, 12, ~). Its composer refuses
    aliases: a few hundred bytes of them can expand to hundreds of
    megabytes [R55]. A value that its explicit tag can't hold, and an
    escape past U+10FFFF, are YAML errors at their line, where
    SafeLoader lets other exceptions out."""

    yaml_implicit_resolvers = {}

    def compose_node(self, parent: yaml.Node | None, index: int) -> yaml.Node | None:
        if self.check_event(yaml.AliasEvent):
            # types-PyYAML leaves Parser.peek_event() unannotated; it returns the Event.
            raise _Alias(self.peek_event().start_mark)  # type: ignore[no-untyped-call]
        return super().compose_node(parent, index)

    def construct_object(self, node: yaml.Node, deep: bool = False) -> object:
        # SafeConstructor raises these, not a ConstructorError, for a
        # value such as !!int abc (ValueError), !!int '' (IndexError),
        # !!bool maybe (KeyError) or !!timestamp nope (AttributeError).
        try:
            return super().construct_object(node, deep)
        except (AttributeError, LookupError, ValueError) as e:
            tag = node.tag.replace("tag:yaml.org,2002:", "!!", 1)
            problem = "%r is not a valid %s" % (node.value, tag)
            raise yaml.constructor.ConstructorError(None, None, problem, node.start_mark) from e

    def scan_flow_scalar_non_spaces(self, double: bool, start_mark: yaml.Mark) -> list[str]:
        # chr() raises ValueError, not a ScannerError, for a double-quoted
        # escape of 8 hex digits past U+10FFFF.
        try:
            return super().scan_flow_scalar_non_spaces(double, start_mark)
        except ValueError as e:
            problem = "found an escape sequence past U+10FFFF"
            raise yaml.scanner.ScannerError(
                "while scanning a double-quoted scalar", start_mark, problem, self.get_mark()
            ) from e


def _frontmatter_block(name: str) -> bytes:
    """The bytes between NAME's first line, which must be "---", and the next
    "---" line. Raises BwError as load_frontmatter() describes."""
    try:
        st = os.stat(name)
    except OSError as e:
        raise cli.BwError("file not found: %s" % name) from e
    if not stat_module.S_ISREG(st.st_mode):
        raise cli.BwError("file not found: %s" % name)
    try:
        # O_NONBLOCK: should NAME become a FIFO after the stat, opening it can't hang.
        fd = os.open(name, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOCTTY", 0))
    except OSError as e:
        raise cli.BwError("cannot read %s: %s" % (name, e.strerror or e)) from e
    try:
        with os.fdopen(fd, "rb") as f:
            if not stat_module.S_ISREG(os.fstat(f.fileno()).st_mode):
                raise cli.BwError("file not found: %s" % name)
            if f.readline(len(_DELIMITER)) not in (_DELIMITER, _DELIMITER[:-1]):
                raise cli.BwError("%s does not begin with a YAML frontmatter delimiter" % name)
            lines: list[bytes]
            lines, size = [], 0
            while True:
                # A line longer than the limit comes back in pieces, and the
                # first piece already takes the block over it.
                line = f.readline(MAX_FRONTMATTER + 1)
                if not line:
                    raise cli.BwError("%s has no closing frontmatter delimiter" % name)
                if line in (_DELIMITER, _DELIMITER[:-1]):
                    return b"".join(lines)
                size += len(line)
                if size > MAX_FRONTMATTER:
                    raise cli.BwError("%s: frontmatter is over 64 KiB" % name)
                lines.append(line)
    except OSError as e:
        raise cli.BwError("cannot read %s: %s" % (name, e.strerror or e)) from e


def _not_a_string(value: object) -> str:
    """How load_frontmatter() names a field value that is not a string."""
    if isinstance(value, list):
        return "a list"
    if isinstance(value, (dict, set)):
        return "a mapping"
    return "a tagged %s" % type(value).__name__  # !!int 12, !!timestamp 2026-11-09, ...


def load_frontmatter(path: str | os.PathLike[str]) -> dict[str, str]:
    """The six rfc-frontmatter fields of the file at PATH, as a dict of
    strings in FRONTMATTER_FIELDS order. This is the only code that parses
    YAML.

    The frontmatter is the lines between line 1, which must be "---", and the
    next "---" line, at most 64 KiB, parsed with FrontmatterLoader. A plain
    value stays as written, a quoted one is unquoted and unescaped, and a
    trailing comment is dropped; a missing field, ~, null and an empty value
    give "". Other keys may hold anything the loader accepts.

    Raises BwError, with a one-line message that names PATH, when PATH is not
    a regular file or can't be read, when it has no such block, or when the
    block is over 64 KiB, not UTF-8, not valid YAML (which includes a value
    that its explicit tag can't hold, such as !!int abc), uses an alias,
    nests too deeply or is not a mapping, or gives one of the six fields a
    list, a mapping or an explicitly tagged non-string value.

    Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, B2 "Frontmatter
    parsing".
    """
    name = os.fspath(path)
    block = _frontmatter_block(name)
    try:
        text = block.decode("utf-8")
    except UnicodeDecodeError as e:
        raise cli.BwError("%s: frontmatter is not valid UTF-8" % name) from e
    # Line numbers: the block starts on the file's line 2, and marks count from 0.
    try:
        data = yaml.load(text, Loader=FrontmatterLoader)
    except _Alias as e:
        raise cli.BwError("%s:%d: frontmatter may not use an alias" % (name, e.mark.line + 2)) from e
    except RecursionError as e:
        raise cli.BwError("%s: frontmatter nests too deeply" % name) from e
    except yaml.YAMLError as e:
        problem = ", ".join(p for p in (getattr(e, "context", None), getattr(e, "problem", None)) if p)
        problem = problem or str(e).split("\n")[0]
        mark = getattr(e, "problem_mark", None)
        where = name if mark is None else "%s:%d" % (name, mark.line + 2)
        raise cli.BwError("%s: frontmatter is not valid YAML (%s)" % (where, problem)) from e
    if data is None:  # an empty block, or only comments
        data = {}
    if not isinstance(data, dict):
        raise cli.BwError("%s: frontmatter is not a mapping of key: value pairs" % name)
    fields: dict[str, str] = {}
    for key in FRONTMATTER_FIELDS:
        value = data.get(key)
        if value is None:  # missing, or an explicit !!null
            value = ""
        elif not isinstance(value, str):
            raise cli.BwError("%s: %s is %s, not a string" % (name, key, _not_a_string(value)))
        elif value in _NULLS:
            value = ""
        fields[key] = value
    return fields
