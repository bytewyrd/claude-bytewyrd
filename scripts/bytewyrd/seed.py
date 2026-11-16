"""Scaffold's seed targets and their templates, which drift checks too: the
stamp on a seeded file's line 1, the plugin commit it names, and render(),
which fills a template in for the detected components.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import enum
import hashlib
import os
import re
from typing import NamedTuple, TypeAlias

from bytewyrd import cli, detect, fs, git

# The plugin root: the parent of scripts/, found from this file.
PLUGIN_DIR: str = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

STAMP_RE: re.Pattern[str] = re.compile(
    r"^(<!-- |# )bytewyrd:scaffold v1 tpl=([A-Za-z0-9._-]+):([0-9a-f]{12}) plugin=([0-9a-f]{12}|unknown)( -->)?$"
)


# A stamp as read_stamp() parses it: (template, hash, plugin commit).
Stamp: TypeAlias = tuple[str, str, str]


class _Bad(enum.Enum):
    """The type of BAD, read_stamp()'s result for a stamp that doesn't parse.
    It has one member, so `stamp is BAD` narrows a stamp's type."""

    BAD = "BAD"

    def __repr__(self) -> str:
        return "BAD"

    __str__ = __repr__


BAD: _Bad = _Bad.BAD


# --- hashes, stamps and the plugin commit ------------------------------------


def file_hash(path: str) -> str:
    """The first 12 hex digits of the sha256 of PATH's bytes, CRs removed."""
    with open(path, "rb") as f:
        data = f.read()
    return hashlib.sha256(data.replace(b"\r", b"")).hexdigest()[:12]


def plugin_sha(plugin_dir: str) -> str:
    """The installed plugin commit, as 12 hex digits, or "unknown".

    A marketplace install lives in a directory named by its commit; a git
    checkout is asked for HEAD, but only when PLUGIN_DIR is its top level.
    """
    name = os.path.basename(os.path.normpath(plugin_dir))
    if re.fullmatch(r"[0-9a-f]{12,40}", name):
        return name[:12]
    try:
        top = git._git(plugin_dir, "rev-parse", "--show-toplevel")
        if top.returncode != 0 or os.path.realpath(git._line(top.stdout)) != os.path.realpath(plugin_dir):
            return "unknown"
        head = git._git(plugin_dir, "rev-parse", "HEAD")
    except cli.BwError:
        return "unknown"
    sha = git._line(head.stdout) if head.returncode == 0 else ""
    return sha[:12] if re.fullmatch(r"[0-9a-f]{40,64}", sha) else "unknown"


def stamp(kind: str, tpl: str, digest: str, sha: str) -> str:
    """Line 1 of a seeded file: KIND "md" (an HTML comment) or "yml"."""
    body = "bytewyrd:scaffold v1 tpl=%s:%s plugin=%s" % (tpl, digest, sha)
    if kind == "md":
        line = "<!-- %s -->" % body
    elif kind == "yml":
        line = "# " + body
    else:
        raise ValueError("unknown stamp kind %r" % (kind,))
    if not STAMP_RE.fullmatch(line):
        raise ValueError("stamp does not parse: %r" % (line,))
    return line


def read_stamp(path: str) -> Stamp | _Bad | None:
    """PATH's stamp as (tpl, hash, sha); None if line 1 has none; BAD if it doesn't parse."""
    with open(path, "rb") as f:
        first = f.readline()
    line = first.decode("utf-8", "surrogateescape").replace("\r", "")
    if line.endswith("\n"):
        line = line[:-1]
    if "bytewyrd:scaffold" not in line:
        return None
    m = STAMP_RE.fullmatch(line)
    if not m:
        return BAD
    return (m.group(2), m.group(3), m.group(4))


# --- rendering ---------------------------------------------------------------

_JOB_TAG: str = "@@job@@ "


def _languages_line(comps: list[detect.Component]) -> str:
    if not comps:
        return "none"
    items = [c.language if c.directory == "." else "%s in %s/" % (c.language, c.directory) for c in comps]
    text = ", ".join(items[:10])
    if len(items) > 10:
        text += ", and %d more; see .github/workflows/ci.yml" % (len(items) - 10)
    return text


def render(tpl: str, comps: list[detect.Component], name: str) -> str:
    """Render the template text TPL for components COMPS and project NAME.

    The @@job@@ lines form one block, repeated per component where the first
    of them stood. A line tagged @@<id>@@ stays only when a component has
    language <id> (or, for @@none@@, when there are none). Values are inserted
    with str.replace, so they are literal; NAME goes in last, so a name holding
    "@@" is never taken for a placeholder. Raises BwError when a placeholder
    is left, or when a @@job@@ block meets no components.
    """
    lines = tpl.replace("\r", "").split("\n")
    block = [line[len(_JOB_TAG) :] for line in lines if line.startswith(_JOB_TAG)]
    if block:
        if not comps:
            raise cli.BwError("the template's @@job@@ block needs at least one component")
        jobs = [
            line.replace("@@job_id@@", c.job_id)
            .replace("@@job_language@@", c.language)
            .replace("@@job_directory@@", c.directory)
            for c in comps
            for line in block
        ]
        first = next(i for i, line in enumerate(lines) if line.startswith(_JOB_TAG))
        lines = lines[:first] + jobs + [line for line in lines[first:] if not line.startswith(_JOB_TAG)]

    present = {c.language for c in comps}
    kept: list[str] = []
    for line in lines:
        for tag in detect.LANGUAGES + ("none",):
            prefix = "@@%s@@ " % tag
            if line.startswith(prefix):
                if tag in present or (tag == "none" and not comps):
                    kept.append(line[len(prefix) :])
                break
        else:
            kept.append(line)

    text = "\n".join(kept).replace("@@languages@@", _languages_line(comps))
    if "@@" in text.replace("@@project_name@@", ""):
        raise cli.BwError("the template has a placeholder that render() doesn't know")
    return text.replace("@@project_name@@", name)


# --- seed targets (scaffold and drift) ---------------------------------------

TEMPLATE_DIR: str = os.path.join(PLUGIN_DIR, "templates", "scaffold")
CI_NOOP: str = "ci-noop.yml"
CI_CALLER: str = "ci-caller.yml"
TEMPLATES: tuple[str, ...] = ("AGENTS.md", "CLAUDE.md", "PULL_REQUEST_TEMPLATE.md", CI_NOOP, CI_CALLER)


class Target(NamedTuple):
    """A seed target: its root-relative path, its stamp kind ("md" or "yml")
    and its template, which is None for ci.yml: template_for() picks that one
    from the components."""

    path: str
    kind: str
    template: str | None


AGENTS_MD: Target = Target("AGENTS.md", "md", "AGENTS.md")
CLAUDE_MD: Target = Target("CLAUDE.md", "md", "CLAUDE.md")
PR_TEMPLATE: Target = Target(".github/PULL_REQUEST_TEMPLATE.md", "md", "PULL_REQUEST_TEMPLATE.md")
CI_YML: Target = Target(".github/workflows/ci.yml", "yml", None)
TARGETS: tuple[Target, ...] = (AGENTS_MD, CLAUDE_MD, PR_TEMPLATE, CI_YML)


def template_for(target: Target, comps: list[detect.Component]) -> str:
    """The template scaffold seeds TARGET from: for ci.yml, the no-op job
    when COMPS is empty, else the language caller."""
    if target.template is not None:
        return target.template
    return CI_CALLER if comps else CI_NOOP


def fits(target: Target, name: str) -> bool:
    """True when NAME is a template that TARGET's stamp may name: one of the
    plugin's templates of TARGET's kind."""
    return name in TEMPLATES and name.endswith("." + target.kind)


def read_template(name: str) -> tuple[str, str]:
    """The text of the plugin's template NAME and its file_hash(). Raises
    BwError when the template can't be read or isn't UTF-8."""
    path = os.path.join(TEMPLATE_DIR, name + ".tpl")
    try:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8")
        return text, file_hash(path)
    except (OSError, ValueError) as e:
        raise cli.BwError("cannot read template %s: %s" % (cli.quote(name), cli.describe(e))) from e


def pr_template(root: str) -> str | None:
    """The root-relative path of a pull request template GitHub would use, or None."""
    for base in (".", "docs", ".github"):
        directory = os.path.join(root, base)
        try:
            entries = sorted(os.listdir(directory))
        except OSError:
            continue
        for entry in entries:
            low = entry.lower()
            if low.startswith("pull_request_template.") or (
                low == "pull_request_template" and os.path.isdir(os.path.join(directory, entry))
            ):
                return entry if base == "." else base + "/" + entry
    return None


def workflow_exists(root: str) -> bool:
    """True when ROOT's .github/workflows/ holds any *.yml or *.yaml entry."""
    try:
        names = os.listdir(os.path.join(root, ".github", "workflows"))
    except OSError:
        return False
    return any(name.endswith((".yml", ".yaml")) for name in names)


def lacks_import(root: str) -> bool:
    """True when ROOT's CLAUDE.md is a readable file, not AGENTS.md itself,
    with no line "@AGENTS.md", so Claude Code won't read AGENTS.md."""
    claude = os.path.join(root, "CLAUDE.md")
    if os.path.realpath(claude) == os.path.realpath(os.path.join(root, "AGENTS.md")):
        return False  # a symlink to AGENTS.md, or the other way round
    text = fs.read_text(claude)
    return text is not None and "@AGENTS.md" not in text.split("\n")
