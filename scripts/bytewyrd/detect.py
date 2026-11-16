"""Detection, which feeds both scaffold and drift: a component, which gets a
caller job, for each tracked (language, directory) that it keeps, and a
reason and a fix line for each manifest that gets none. Repo files are read
only from the index, through git.blob().

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2 ("Detection").
"""

import fnmatch
import json
import os
import posixpath
import re
import tomllib
from typing import NamedTuple

from bytewyrd import cli, git

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


def attr_line(path):
    """A .gitattributes line whose root-anchored pattern opts out exactly PATH."""
    escaped = "".join("\\" + c if c in "\\*?[" else c for c in path)
    return cli.quote("/" + escaped) + " -bytewyrd-ci"


REASON_NAME = "directory name not allowed (letters, digits, '.', '_' and '-', at most 64 characters)"
REASON_RAKEFILE = "no Rakefile (the ruby job runs bundle exec rake)"
REASON_PYPROJECT = "no pyproject.toml with [project] (the python job runs uv sync)"
REASON_VALUE = "bytewyrd-ci has a value; use bytewyrd-ci or -bytewyrd-ci"
REASON_OPTED_OUT = "opted out by -bytewyrd-ci"


def reason_taken(job_id, directory):
    """The reason for a group whose job id DIRECTORY's group already holds."""
    return "job id %s is taken by %s" % (cli.quote(job_id), cli.quote(directory))


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
    data = git.blob(root, entry) if entry is not None else None
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
    return len(segments) <= 2 and not any(s.startswith((".", "_")) or s.lower() in _OUT_OF_SCOPE for s in segments)


def _attributes(root, paths):
    """The bytewyrd-ci attribute of each path, from one git check-attr run."""
    if not paths:
        return {}
    stdin = b"".join(os.fsencode(p) + b"\0" for p in paths)
    proc = git._git(root, "check-attr", "--cached", "--stdin", "-z", "bytewyrd-ci", input=stdin)
    if proc.returncode != 0:
        raise cli.BwError("git check-attr failed")
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
        if not any(_under(d, e) for e in exclude)
        and _cargo_workspace(root, by_path.get(_join(d, "Cargo.toml"))) is None
    }


def detect(root):
    """The components and skipped manifests of the repo at ROOT.

    Returns (COMPS, SKIPPED): COMPS lists Component(language, directory,
    job_id, manifests) sorted by language, then directory; SKIPPED lists
    Skip(path, reason) in path order. Only index entries are read.
    """
    by_path = {}
    for entry in git.tracked(root):  # an unmerged path has up to three entries; it counts once
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
