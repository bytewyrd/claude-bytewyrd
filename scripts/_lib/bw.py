"""Shared functions for the bw commands (scripts/bw).

Nothing here exits the process: functions return values or raise, and each
command's main() decides the exit code. Detection reads repo files from the
index, through blob(); the seed files themselves are read from the work tree,
through read_text(). Every repo-derived string that scaffold and drift print
goes through quote(); the JSON helpers print theirs through jq_dumps().

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import argparse
import errno
import fnmatch
import functools
import hashlib
import json
import os
import posixpath
import re
import stat as stat_module
import subprocess
import sys
import tomllib
from typing import NamedTuple

# The language ids. Each has a .github/workflows/lang-ci-<id>.yml and a
# lang-ci-fixture-<id> job in ci.yml; tests/py/test_bw.py checks both.
LANGUAGES = ("go", "js", "python", "ruby", "rust")

# Manifest basenames and their language.
MANIFESTS = {
    "go.mod": "go",
    "package.json": "js",
    "pyproject.toml": "python",
    "setup.py": "python",
    "Cargo.toml": "rust",
    "Gemfile": "ruby",
}

# The plugin root: the parent of scripts/, found from this file.
PLUGIN_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

STAMP_RE = re.compile(
    r"^(<!-- |# )bytewyrd:scaffold v1 tpl=([A-Za-z0-9._-]+):([0-9a-f]{12}) plugin=([0-9a-f]{12}|unknown)( -->)?$"
)

MAX_BLOB = 1 << 20  # blob() reads index entries of at most 1 MiB


class BwError(Exception):
    """A failure a command reports as one line, without a traceback."""


class _Bad:
    """The type of BAD, read_stamp()'s result for a stamp that doesn't parse."""

    __slots__ = ()

    def __repr__(self):
        return "BAD"


BAD = _Bad()


class Entry(NamedTuple):
    """One index entry, as `git ls-files -s -z` lists it."""

    mode: str
    oid: str
    stage: int
    path: str


class Component(NamedTuple):
    """One caller job: a (language, directory) that detection keeps."""

    language: str
    directory: str
    job_id: str
    manifests: tuple


class Skip(NamedTuple):
    """A manifest that gets no caller job, with the reason as printed."""

    path: str
    reason: str


class Parser(argparse.ArgumentParser):
    """An ArgumentParser whose usage errors exit 1: argparse's 2 would read as drift."""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))


# --- git ---------------------------------------------------------------------


def _git(cwd, *args, input=None):
    """Run git (with -C CWD unless CWD is None); BwError if git can't start."""
    cmd = ["git"] + (["-C", cwd] if cwd is not None else []) + list(args)
    io = {"input": input} if input is not None else {"stdin": subprocess.DEVNULL}
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **io)
    except OSError as e:
        raise BwError("cannot run git: %s" % (e.strerror or e)) from e


def _line(data):
    """Bytes of one line of git output, without its final newline, as a str."""
    if data.endswith(b"\n"):
        data = data[:-1]
    return os.fsdecode(data)


def root():
    """The top level of the work tree that contains the current directory."""
    proc = _git(None, "rev-parse", "--show-toplevel")
    if proc.returncode != 0 or not proc.stdout.strip():
        raise BwError("not inside a git work tree")
    return _line(proc.stdout)


def project_name(root):
    """The project's name: the basename of the parent of the git common dir.

    In a linked worktree the top level is the worktree's own directory, while
    the common dir belongs to the main repository, so this names the project
    rather than the checkout. Falls back to the basename of ROOT.
    """
    fallback = os.path.basename(os.path.normpath(root))
    try:
        proc = _git(root, "rev-parse", "--git-common-dir")
    except BwError:
        return fallback
    if proc.returncode != 0 or not proc.stdout.strip():
        return fallback
    common = os.path.abspath(os.path.join(root, _line(proc.stdout)))
    return os.path.basename(os.path.dirname(common)) or fallback


def tracked(root):
    """The index entries of ROOT, as Entry(mode, oid, stage, path) tuples."""
    proc = _git(root, "ls-files", "-s", "-z")
    if proc.returncode != 0:
        raise BwError("git ls-files failed")
    entries = []
    for record in proc.stdout.split(b"\0"):
        if not record:
            continue
        meta, _, path = record.partition(b"\t")
        mode, oid, stage = meta.split(b" ")
        entries.append(Entry(mode.decode("ascii"), oid.decode("ascii"), int(stage), os.fsdecode(path)))
    return entries


def blob(root, entry):
    """The bytes of a regular stage-0 entry of at most 1 MiB, else None."""
    if entry.stage != 0 or entry.mode not in ("100644", "100755"):
        return None
    try:
        size = _git(root, "cat-file", "-s", entry.oid)
        if size.returncode != 0 or int(size.stdout) > MAX_BLOB:
            return None
        data = _git(root, "cat-file", "blob", entry.oid)
    except (BwError, ValueError):
        return None
    if data.returncode != 0 or len(data.stdout) > MAX_BLOB:
        return None
    return data.stdout


def dirty(root):
    """True when `git status --porcelain` prints anything for ROOT.

    --no-optional-locks keeps git from refreshing the index on the way, so a
    dry run writes nothing, not even .git/index.
    """
    proc = _git(root, "--no-optional-locks", "status", "--porcelain")
    if proc.returncode != 0:
        raise BwError("git status failed")
    return bool(proc.stdout)


# --- hashes, stamps and the plugin commit ------------------------------------


def file_hash(path):
    """The first 12 hex digits of the sha256 of PATH's bytes, CRs removed."""
    with open(path, "rb") as f:
        data = f.read()
    return hashlib.sha256(data.replace(b"\r", b"")).hexdigest()[:12]


def plugin_sha(plugin_dir):
    """The installed plugin commit, as 12 hex digits, or "unknown".

    A marketplace install lives in a directory named by its commit; a git
    checkout is asked for HEAD, but only when PLUGIN_DIR is its top level.
    """
    name = os.path.basename(os.path.normpath(plugin_dir))
    if re.fullmatch(r"[0-9a-f]{12,40}", name):
        return name[:12]
    try:
        top = _git(plugin_dir, "rev-parse", "--show-toplevel")
        if top.returncode != 0 or os.path.realpath(_line(top.stdout)) != os.path.realpath(plugin_dir):
            return "unknown"
        head = _git(plugin_dir, "rev-parse", "HEAD")
    except BwError:
        return "unknown"
    sha = _line(head.stdout) if head.returncode == 0 else ""
    return sha[:12] if re.fullmatch(r"[0-9a-f]{40,64}", sha) else "unknown"


def stamp(kind, tpl, digest, sha):
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


def read_stamp(path):
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

_JOB_TAG = "@@job@@ "


def _languages_line(comps):
    if not comps:
        return "none"
    items = [c.language if c.directory == "." else "%s in %s/" % (c.language, c.directory) for c in comps]
    text = ", ".join(items[:10])
    if len(items) > 10:
        text += ", and %d more; see .github/workflows/ci.yml" % (len(items) - 10)
    return text


def render(tpl, comps, name):
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
            raise BwError("the template's @@job@@ block needs at least one component")
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
    kept = []
    for line in lines:
        for tag in LANGUAGES + ("none",):
            prefix = "@@%s@@ " % tag
            if line.startswith(prefix):
                if tag in present or (tag == "none" and not comps):
                    kept.append(line[len(prefix) :])
                break
        else:
            kept.append(line)

    text = "\n".join(kept).replace("@@languages@@", _languages_line(comps))
    if "@@" in text.replace("@@project_name@@", ""):
        raise BwError("the template has a placeholder that render() doesn't know")
    return text.replace("@@project_name@@", name)


# --- files -------------------------------------------------------------------


def exists(directory, name):
    """True when DIRECTORY/NAME exists, even as a dangling symlink, or an
    entry of DIRECTORY equals NAME ignoring case."""
    return find_entry(directory, name) is not None


def find_entry(directory, name):
    """The entry of DIRECTORY that exists() finds for NAME: NAME itself, else
    the first entry, in sorted order, that equals NAME ignoring case; None
    when there is neither."""
    if os.path.lexists(os.path.join(directory, name)):
        return name
    try:
        entries = sorted(os.listdir(directory))
    except OSError:
        return None
    folded = name.casefold()
    return next((entry for entry in entries if entry.casefold() == folded), None)


def pr_template(root):
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


def symlinked_dir(root, rel):
    """The first directory on the way to REL (under ROOT) that is a symlink, or None."""
    parts = rel.split("/")[:-1]
    for i in range(1, len(parts) + 1):
        sub = "/".join(parts[:i])
        if os.path.islink(os.path.join(root, sub)):
            return sub
    return None


def create(path, text):
    """Create PATH holding TEXT. Raises FileExistsError for any existing path,
    symlinks included, writing nothing there; a failed write removes the file."""
    f = open(path, "x", encoding="utf-8", newline="\n")
    try:
        f.write(text)
        f.close()
    except BaseException:
        try:
            f.close()
        except Exception:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass
        raise


MAX_TEXT = 8 << 20  # read_text() reads work-tree files of at most 8 MiB


def read_text(path):
    """PATH's text, with every CR removed, decoded as UTF-8 with surrogateescape.

    None when PATH is missing or, symlinks followed, is not a regular file (a
    directory, a device, a FIFO), or is over 8 MiB: a seed path that points at
    /dev/zero or a pipe is never read. Other errors, such as EACCES, raise
    OSError.
    """
    try:
        st = os.stat(path)
    except OSError as e:
        if e.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            return None
        raise
    if not stat_module.S_ISREG(st.st_mode):
        return None
    # O_NONBLOCK: should PATH become a FIFO after the stat, opening it can't hang.
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOCTTY", 0))
    try:
        if not stat_module.S_ISREG(os.fstat(fd).st_mode):
            return None
        chunks, size = [], 0
        while size <= MAX_TEXT:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
    finally:
        os.close(fd)
    if size > MAX_TEXT:
        return None
    return b"".join(chunks).replace(b"\r", b"").decode("utf-8", "surrogateescape")


# --- quoting -----------------------------------------------------------------

_SAFE = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-")
_C_ESCAPES = {7: "\\a", 8: "\\b", 9: "\\t", 10: "\\n", 11: "\\v", 12: "\\f", 13: "\\r", 34: '\\"', 92: "\\\\"}


def quote(s):
    """S when it is non-empty and every character is in [A-Za-z0-9._/-];
    otherwise git's C-style quoting of its bytes. The result is ASCII."""
    if s and all(c in _SAFE for c in s):
        return s
    try:
        data = os.fsencode(s)
    except UnicodeError:  # a lone surrogate that surrogateescape didn't make
        data = s.encode("utf-8", "surrogatepass")
    out = ['"']
    for b in data:
        if b in _C_ESCAPES:
            out.append(_C_ESCAPES[b])
        elif b < 0x20 or b > 0x7E:
            out.append("\\%03o" % b)
        else:
            out.append(chr(b))
    out.append('"')
    return "".join(out)


def attr_line(path):
    """A .gitattributes line whose root-anchored pattern opts out exactly PATH."""
    escaped = "".join("\\" + c if c in "\\*?[" else c for c in path)
    return quote("/" + escaped) + " -bytewyrd-ci"


def describe(e):
    """A one-line description of the exception E for an error message: the
    text as it is when it is printable ASCII, else quote() of it."""
    if isinstance(e, BwError):
        text = str(e)
    elif isinstance(e, OSError) and e.strerror:
        text = e.strerror
        if isinstance(e.filename, (str, bytes)):
            text += ": " + os.fsdecode(e.filename)
    else:
        text = "%s: %s" % (type(e).__name__, e) if str(e) else type(e).__name__
    return text if text.isascii() and text.isprintable() else quote(text)


# --- detection ---------------------------------------------------------------

REASON_NAME = "directory name not allowed (letters, digits, '.', '_' and '-', at most 64 characters)"
REASON_RAKEFILE = "no Rakefile (the ruby job runs bundle exec rake)"
REASON_PYPROJECT = "no pyproject.toml with [project] (the python job runs uv sync)"
REASON_VALUE = "bytewyrd-ci has a value; use bytewyrd-ci or -bytewyrd-ci"
REASON_OPTED_OUT = "opted out by -bytewyrd-ci"


def reason_taken(job_id, directory):
    """The reason for a group whose job id DIRECTORY's group already holds."""
    return "job id %s is taken by %s" % (quote(job_id), quote(directory))


def skip_fix(path, reason):
    """The fix line for a Skip(PATH, REASON), or None for an opt-out."""
    if reason == REASON_OPTED_OUT:
        return None
    if reason == REASON_VALUE:
        return "set bytewyrd-ci or -bytewyrd-ci for this path in .gitattributes"
    line = attr_line(path)
    if reason == REASON_RAKEFILE:
        return "add a Rakefile whose default task runs the tests, or mark the manifest: " + line
    if reason == REASON_PYPROJECT:
        return "add a pyproject.toml with a [project] table, or mark the manifest: " + line
    return "rename the directory, or mark the manifest: " + line  # REASON_NAME and reason_taken()


_RAKEFILES = ("rakefile", "Rakefile", "rakefile.rb", "Rakefile.rb")
_OUT_OF_SCOPE = frozenset(
    "node_modules vendor third_party testdata test tests spec e2e fixture fixtures "
    "example examples sample samples template templates".split()
)
_DIRECTORY_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*")


def dir_matches(pattern, directory):
    """True when the workspace PATTERN matches DIRECTORY, segment by segment.

    A leading "./" and a trailing "/" are stripped from PATTERN. Each segment
    matches under fnmatch.fnmatchcase, so "*" never crosses a "/", and a "**"
    segment matches any number of segments, none included.
    """
    if pattern.startswith("./"):
        pattern = pattern[2:]
    if pattern.endswith("/"):
        pattern = pattern[:-1]
    pat = pattern.split("/")
    seg = directory.split("/")
    # after[j]: pat[i + 1:] matches seg[j:]; built from the last segment back.
    after = [False] * len(seg) + [True]
    for p in reversed(pat):
        here = [False] * (len(seg) + 1)
        if p == "**":
            tail = False
            for j in range(len(seg), -1, -1):
                tail = tail or after[j]
                here[j] = tail
        else:
            for j in range(len(seg)):
                here[j] = after[j + 1] and fnmatch.fnmatchcase(seg[j], p)
        after = here
    return after[0]


def _matches_any(patterns, directory):
    return any(dir_matches(p, directory) for p in patterns)


def _str_list(value):
    return isinstance(value, list) and all(isinstance(v, str) for v in value)


def _load(root, entry, parse):
    """PARSE applied to an index entry's text, or None when it declares nothing."""
    data = blob(root, entry) if entry is not None else None
    if data is None:
        return None
    try:
        return parse(data.decode("utf-8"))
    except (OSError, ValueError, RecursionError):  # UnicodeDecodeError and both parsers' errors are ValueErrors
        return None


def _js_workspaces(root, entry):
    """The workspace patterns of a package.json, or None."""
    doc = _load(root, entry, json.loads)
    if not isinstance(doc, dict) or "workspaces" not in doc:
        return None
    patterns = doc["workspaces"]
    if isinstance(patterns, dict):
        patterns = patterns.get("packages")
    return patterns if _str_list(patterns) else None


def _toml_workspace(doc, *keys):
    """The (members, exclude) of the table at KEYS in DOC: None when the table
    is absent, False when its shape is wrong."""
    table = doc
    for key in keys:
        table = table.get(key) if isinstance(table, dict) else None
    if not isinstance(table, dict):
        return None
    members, exclude = table.get("members", []), table.get("exclude", [])
    if not (_str_list(members) and _str_list(exclude)):
        return False
    return members, exclude


def _pyproject(root, entry):
    """(counts, workspace) of a pyproject.toml: whether it has [project] or
    [tool.uv.workspace], and that workspace's (members, exclude) or None. A
    wrong-shaped workspace means the file declares nothing."""
    doc = _load(root, entry, tomllib.loads)
    if not isinstance(doc, dict):
        return False, None
    workspace = _toml_workspace(doc, "tool", "uv", "workspace")
    if workspace is False:
        return False, None
    return workspace is not None or isinstance(doc.get("project"), dict), workspace


def _cargo_workspace(root, entry):
    """The (members, exclude) of a Cargo.toml's [workspace] table, or None."""
    doc = _load(root, entry, tomllib.loads)
    if not isinstance(doc, dict):
        return None
    workspace = _toml_workspace(doc, "workspace")
    return workspace or None


def _under(directory, prefix):
    """True when DIRECTORY is PREFIX or lies under it, comparing whole segments."""
    want = [s for s in prefix.split("/") if s not in ("", ".")]
    return directory.split("/")[: len(want)] == want


def _in_default_scope(directory):
    if directory == ".":
        return True
    segments = directory.split("/")
    return len(segments) <= 2 and not any(
        s.startswith((".", "_")) or s.lower() in _OUT_OF_SCOPE for s in segments
    )


def _attributes(root, paths):
    """The bytewyrd-ci attribute of each path, from one git check-attr run."""
    if not paths:
        return {}
    stdin = b"".join(os.fsencode(p) + b"\0" for p in paths)
    proc = _git(root, "check-attr", "--cached", "--stdin", "-z", "bytewyrd-ci", input=stdin)
    if proc.returncode != 0:
        raise BwError("git check-attr failed")
    fields = proc.stdout.split(b"\0")
    return {os.fsdecode(fields[i]): os.fsdecode(fields[i + 2]) for i in range(0, len(fields) - 2, 3)}


def _directory(path):
    return posixpath.dirname(path) or "."


def _join(directory, name):
    return name if directory == "." else directory + "/" + name


def _job_id(language, directory):
    if directory == ".":
        return language
    return language + "-" + directory.lower().replace("/", "-").replace(".", "-")


# The root manifest whose workspace a root job covers. go and ruby have none:
# a root ./... never includes another module, and a root rake runs the root's
# own suite.
_WORKSPACE_MANIFESTS = (("js", "package.json"), ("python", "pyproject.toml"), ("rust", "Cargo.toml"))


def _covered(root, language, manifest, nested, by_path):
    """The directories of NESTED that LANGUAGE's root job covers, given the
    index entry MANIFEST of the root manifest that declares the workspace."""
    if language == "js":
        patterns = _js_workspaces(root, manifest)
        if patterns is None:
            return set()
        include = [p for p in patterns if not p.startswith("!")]
        exclude = [p[1:] for p in patterns if p.startswith("!")]
        return {d for d in nested if _matches_any(include, d) and not _matches_any(exclude, d)}
    if language == "python":
        workspace = _pyproject(root, manifest)[1]
        if workspace is None:
            return set()
        members, exclude = workspace
        return {d for d in nested if _matches_any(members, d) and not _matches_any(exclude, d)}
    workspace = _cargo_workspace(root, manifest)
    if workspace is None:
        return set()
    exclude = workspace[1]
    # Every nested crate is a member or fails in place, except one under an
    # exclude path or with its own [workspace], which builds standalone.
    return {
        d
        for d in nested
        if not any(_under(d, e) for e in exclude) and _cargo_workspace(root, by_path.get(_join(d, "Cargo.toml"))) is None
    }


def detect(root):
    """The components and skipped manifests of the repo at ROOT.

    Returns (COMPS, SKIPPED): COMPS lists Component(language, directory,
    job_id, manifests) sorted by language, then directory; SKIPPED lists
    Skip(path, reason) in path order. Only index entries are read.
    """
    by_path = {}
    for entry in tracked(root):  # an unmerged path has up to three entries; it counts once
        by_path.setdefault(entry.path, entry)

    candidates = sorted(p for p in by_path if posixpath.basename(p) in MANIFESTS)
    attrs = _attributes(root, candidates)

    skipped = []
    groups = {}  # (language, directory) -> manifests
    forced = set()  # groups with a manifest whose bytewyrd-ci is set
    for path in candidates:
        base = posixpath.basename(path)
        if base == "pyproject.toml" and not _pyproject(root, by_path[path])[0]:
            continue  # neither [project] nor [tool.uv.workspace]: not a manifest
        language, directory = MANIFESTS[base], _directory(path)
        value = attrs.get(path, "unspecified")
        if value == "unset":
            skipped.append(Skip(path, REASON_OPTED_OUT))
            continue
        if value not in ("set", "unspecified"):
            skipped.append(Skip(path, REASON_VALUE))
            continue
        groups.setdefault((language, directory), []).append(path)
        if value == "set":
            forced.add((language, directory))

    # Default scope: the root and shallow directories outside vendored,
    # fixture, example, test and template trees, unless a manifest is set.
    groups = {k: v for k, v in groups.items() if k in forced or _in_default_scope(k[1])}

    # Root workspaces: a root job drops the nested manifests it covers. A root
    # group without its workspace manifest yields no component (a python root
    # with only setup.py fails validation), so it covers nothing.
    for language, manifest in _WORKSPACE_MANIFESTS:
        if manifest not in groups.get((language, "."), ()):
            continue
        nested = [d for (lang, d) in groups if lang == language and d != "." and (lang, d) not in forced]
        for directory in _covered(root, language, by_path[manifest], nested, by_path):
            del groups[(language, directory)]

    # Validation, in sorted order, so the first directory keeps a shared job id.
    comps = []
    holders = {}  # job id -> directory
    for language, directory in sorted(groups):
        manifests = tuple(sorted(groups[(language, directory)]))
        reason = None
        if directory != "." and not (len(directory) <= 64 and _DIRECTORY_RE.fullmatch(directory)):
            reason = REASON_NAME
        elif language == "ruby" and not any(_join(directory, r) in by_path for r in _RAKEFILES):
            reason = REASON_RAKEFILE
        elif language == "python" and not any(posixpath.basename(p) == "pyproject.toml" for p in manifests):
            reason = REASON_PYPROJECT
        else:
            job_id = _job_id(language, directory)
            if job_id in holders:
                reason = reason_taken(job_id, holders[job_id])
            else:
                holders[job_id] = directory
                comps.append(Component(language, directory, job_id, manifests))
        if reason is not None:
            skipped.extend(Skip(p, reason) for p in manifests)

    comps.sort(key=lambda c: (c.language, c.directory))
    skipped.sort(key=lambda s: s.path)
    return comps, skipped


# --- seed targets (scaffold and drift) ---------------------------------------

TEMPLATE_DIR = os.path.join(PLUGIN_DIR, "templates", "scaffold")
CI_NOOP = "ci-noop.yml"
CI_CALLER = "ci-caller.yml"
TEMPLATES = ("AGENTS.md", "CLAUDE.md", "PULL_REQUEST_TEMPLATE.md", CI_NOOP, CI_CALLER)


class Target(NamedTuple):
    """A seed target: its root-relative path, its stamp kind ("md" or "yml")
    and its template, which is None for ci.yml: template_for() picks that one
    from the components."""

    path: str
    kind: str
    template: object


AGENTS_MD = Target("AGENTS.md", "md", "AGENTS.md")
CLAUDE_MD = Target("CLAUDE.md", "md", "CLAUDE.md")
PR_TEMPLATE = Target(".github/PULL_REQUEST_TEMPLATE.md", "md", "PULL_REQUEST_TEMPLATE.md")
CI_YML = Target(".github/workflows/ci.yml", "yml", None)
TARGETS = (AGENTS_MD, CLAUDE_MD, PR_TEMPLATE, CI_YML)


def template_for(target, comps):
    """The template scaffold seeds TARGET from: for ci.yml, the no-op job
    when COMPS is empty, else the language caller."""
    if target.template is not None:
        return target.template
    return CI_CALLER if comps else CI_NOOP


def fits(target, name):
    """True when NAME is a template that TARGET's stamp may name: one of the
    plugin's templates of TARGET's kind."""
    return name in TEMPLATES and name.endswith("." + target.kind)


def read_template(name):
    """The text of the plugin's template NAME and its file_hash(). Raises
    BwError when the template can't be read or isn't UTF-8."""
    path = os.path.join(TEMPLATE_DIR, name + ".tpl")
    try:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8")
        return text, file_hash(path)
    except (OSError, ValueError) as e:
        raise BwError("cannot read template %s: %s" % (quote(name), describe(e))) from e


def workflow_exists(root):
    """True when ROOT's .github/workflows/ holds any *.yml or *.yaml entry."""
    try:
        names = os.listdir(os.path.join(root, ".github", "workflows"))
    except OSError:
        return False
    return any(name.endswith((".yml", ".yaml")) for name in names)


def lacks_import(root):
    """True when ROOT's CLAUDE.md is a readable file, not AGENTS.md itself,
    with no line "@AGENTS.md", so Claude Code won't read AGENTS.md."""
    claude = os.path.join(root, "CLAUDE.md")
    if os.path.realpath(claude) == os.path.realpath(os.path.join(root, "AGENTS.md")):
        return False  # a symlink to AGENTS.md, or the other way round
    text = read_text(claude)
    return text is not None and "@AGENTS.md" not in text.split("\n")


# --- frontmatter -------------------------------------------------------------

# The fields rfc-frontmatter prints, in its order.
FRONTMATTER_FIELDS = ("rfc", "title", "author", "status", "created", "drop_reason")

MAX_FRONTMATTER = 64 << 10  # load_frontmatter() refuses a longer block

# The delimiter line; the closing one may end the file without a newline.
_DELIMITER = b"---\n"

# Values a field reads as "": YAML's ~ and null, which stay strings under
# FrontmatterLoader (the empty value is "" already).
_NULLS = ("~", "null")


class _Alias(Exception):
    """FrontmatterLoader's refusal of an alias, which starts at MARK."""

    def __init__(self, mark):
        super().__init__(mark)
        self.mark = mark


@functools.cache
def _yaml():
    """The yaml module and FrontmatterLoader, imported and built on first use.

    Only load_frontmatter() parses YAML, so no other command pays for the
    import. Run through scripts/bw, yaml is the vendored scripts/_vendor/yaml.
    """
    import yaml

    class FrontmatterLoader(yaml.SafeLoader):
        """A SafeLoader with no implicit resolvers, so every plain scalar stays
        the string as written (2026-11-09, yes, 12, ~). Its composer refuses
        aliases: a few hundred bytes of them can expand to hundreds of
        megabytes [R55]."""

        yaml_implicit_resolvers = {}

        def compose_node(self, parent, index):
            if self.check_event(yaml.AliasEvent):
                raise _Alias(self.peek_event().start_mark)
            return super().compose_node(parent, index)

    return yaml, FrontmatterLoader


def __getattr__(name):
    # bw.FrontmatterLoader, built on first access like everything in _yaml().
    if name == "FrontmatterLoader":
        return _yaml()[1]
    raise AttributeError("module %r has no attribute %r" % (__name__, name))


def _frontmatter_block(name):
    """The bytes between NAME's first line, which must be "---", and the next
    "---" line. Raises BwError as load_frontmatter() describes."""
    try:
        st = os.stat(name)
    except OSError as e:
        raise BwError("file not found: %s" % name) from e
    if not stat_module.S_ISREG(st.st_mode):
        raise BwError("file not found: %s" % name)
    try:
        # O_NONBLOCK: should NAME become a FIFO after the stat, opening it can't hang.
        fd = os.open(name, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_NOCTTY", 0))
    except OSError as e:
        raise BwError("cannot read %s: %s" % (name, e.strerror or e)) from e
    try:
        with os.fdopen(fd, "rb") as f:
            if not stat_module.S_ISREG(os.fstat(f.fileno()).st_mode):
                raise BwError("file not found: %s" % name)
            if f.readline(len(_DELIMITER)) not in (_DELIMITER, _DELIMITER[:-1]):
                raise BwError("%s does not begin with a YAML frontmatter delimiter" % name)
            lines, size = [], 0
            while True:
                # A line longer than the limit comes back in pieces, and the
                # first piece already takes the block over it.
                line = f.readline(MAX_FRONTMATTER + 1)
                if not line:
                    raise BwError("%s has no closing frontmatter delimiter" % name)
                if line in (_DELIMITER, _DELIMITER[:-1]):
                    return b"".join(lines)
                size += len(line)
                if size > MAX_FRONTMATTER:
                    raise BwError("%s: frontmatter is over 64 KiB" % name)
                lines.append(line)
    except OSError as e:
        raise BwError("cannot read %s: %s" % (name, e.strerror or e)) from e


def _not_a_string(value):
    """How load_frontmatter() names a field value that is not a string."""
    if isinstance(value, list):
        return "a list"
    if isinstance(value, (dict, set)):
        return "a mapping"
    return "a tagged %s" % type(value).__name__  # !!int 12, !!timestamp 2026-11-09, ...


def load_frontmatter(path):
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
    block is over 64 KiB, not UTF-8, not valid YAML, uses an alias, nests too
    deeply or is not a mapping, or gives one of the six fields a list, a
    mapping or an explicitly tagged non-string value.

    Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, B2 "Frontmatter
    parsing".
    """
    name = os.fspath(path)
    block = _frontmatter_block(name)
    try:
        text = block.decode("utf-8")
    except UnicodeDecodeError as e:
        raise BwError("%s: frontmatter is not valid UTF-8" % name) from e
    yaml, loader = _yaml()
    # Line numbers: the block starts on the file's line 2, and marks count from 0.
    try:
        data = yaml.load(text, Loader=loader)
    except _Alias as e:
        raise BwError("%s:%d: frontmatter may not use an alias" % (name, e.mark.line + 2)) from e
    except RecursionError as e:
        raise BwError("%s: frontmatter nests too deeply" % name) from e
    except yaml.YAMLError as e:
        problem = ", ".join(p for p in (getattr(e, "context", None), getattr(e, "problem", None)) if p)
        problem = problem or str(e).split("\n")[0]
        mark = getattr(e, "problem_mark", None)
        where = name if mark is None else "%s:%d" % (name, mark.line + 2)
        raise BwError("%s: frontmatter is not valid YAML (%s)" % (where, problem)) from e
    if data is None:  # an empty block, or only comments
        data = {}
    if not isinstance(data, dict):
        raise BwError("%s: frontmatter is not a mapping of key: value pairs" % name)
    fields = {}
    for key in FRONTMATTER_FIELDS:
        value = data.get(key)
        if value is None:  # missing, or an explicit !!null
            value = ""
        elif not isinstance(value, str):
            raise BwError("%s: %s is %s, not a string" % (name, key, _not_a_string(value)))
        elif value in _NULLS:
            value = ""
        fields[key] = value
    return fields


# --- JSON output (the class-B helpers) ---------------------------------------
#
# The JSON helpers (rfc-* and tool-probe) print one object on stdout as jq
# printed it before their port, and the skills parse it with jq [R51].

# Lone surrogates that are not os.fsdecode()'s U+DC80..U+DCFF escape of a
# byte; a YAML escape such as "\ud800" makes one.
_LONE_SURROGATE = re.compile("[\ud800-\udc7f\udd00-\udfff]")


def jq_string(s):
    """S as valid Unicode, as jq holds a string, so encoding it can't raise
    UnicodeEncodeError [R80].

    The bytes that os.fsdecode() keeps as surrogate escapes, in an argument,
    path or directory that isn't UTF-8, are decoded as UTF-8 with U+FFFD for
    each invalid sequence, as jq did with --arg; any other lone surrogate
    becomes U+FFFD too. (Python replaces each maximal invalid subpart, as
    Unicode recommends, so for an overlong or out-of-range sequence it can
    give more U+FFFD than jq, and it never drops the bytes that follow a
    sequence cut short near the end of a string, as jq does.)
    """
    try:
        s.encode("utf-8")
        return s
    except UnicodeEncodeError:
        pass
    s = _LONE_SURROGATE.sub("\ufffd", s)
    return s.encode("utf-8", "surrogateescape").decode("utf-8", "replace")


def _jq_strings(value):
    if isinstance(value, str):
        return jq_string(value)
    if isinstance(value, dict):
        return {jq_string(k): _jq_strings(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jq_strings(v) for v in value]
    return value


def jq_dumps(value):
    """VALUE as jq prints it, with its final newline: two-space indents,
    keys in insertion order, raw UTF-8, and json's escapes plus \\u007f for
    DEL, the one character jq escapes and json doesn't. Every string, keys
    included, goes through jq_string()."""
    text = json.dumps(_jq_strings(value), indent=2, ensure_ascii=False)
    return text.replace("\x7f", "\\u007f") + "\n"


def emit(value):
    """Print jq_dumps(VALUE) on stdout, as UTF-8 whatever the locale."""
    data = jq_dumps(value).encode("utf-8")
    sys.stdout.flush()
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


# Ports of scripts/_lib/common.bash's functions of the same names, with the
# same JSON [R51].


def emit_error(message):
    """Print {"error": MESSAGE}."""
    emit({"error": message})


def emit_available(name):
    """Print {"result": "available", "name": NAME}."""
    emit({"result": "available", "name": name})


def emit_missing(name, hint):
    """Print {"result": "missing", "name": NAME, "hint": HINT}."""
    emit({"result": "missing", "name": name, "hint": hint})


def emit_unauth(name, hint):
    """Print {"result": "unauthenticated", "name": NAME, "hint": HINT}."""
    emit({"result": "unauthenticated", "name": name, "hint": hint})


def json_main(name, run, argv):
    """The main() of the JSON helper NAME: the exit code of RUN(ARGV).

    An exception from RUN is printed as {"error": "NAME: ..."} with exit 2,
    the helpers' code for an error, so a failure such as an unwritable file
    never ends in a traceback and exit 1, which means "missing" or "not
    found" for some helpers [R62]. When stdout itself fails, the rest of it
    goes to /dev/null, so the exit can't fail on it again.
    """
    try:
        return run(argv)
    except Exception as e:
        try:
            emit_error("%s: %s" % (name, describe(e)))
        except Exception:
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
            except Exception:
                pass
        return 2


# Input, read as the bash scripts read it.


def split_lines(data):
    """DATA's lines as awk and grep read them: split at each newline, a last
    line without one still a line, and no line at all in b""."""
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    return lines


def pwd():
    """The current directory as bash's pwd prints it: $PWD when that is an
    absolute, normalized path to the current directory, so a directory reached
    through a symlink keeps that name; else os.getcwd()."""
    path = os.environ.get("PWD", "")
    if path.startswith("/") and posixpath.normpath(path) == path:
        try:
            if os.path.samefile(path, "."):
                return path
        except OSError:
            pass
    return os.getcwd()
