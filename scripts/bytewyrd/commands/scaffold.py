"""bw scaffold [--apply] [--allow-dirty]: seed the files a repo lacks.

AGENTS.md, CLAUDE.md, .github/PULL_REQUEST_TEMPLATE.md and
.github/workflows/ci.yml are each created only when missing, at the top of the
work tree, with a stamp on line 1 naming the template and the plugin commit.
ci.yml calls this repo's lang-ci-<id>.yml per detected component, or holds a
no-op job when there are none. Without --apply nothing is written.

Nothing is ever overwritten or written through a symlink: preflight refuses a
symlinked directory on the way to a target, and files are created exclusively.
With --apply a dirty tree is refused unless --allow-dirty is given.

Exit 0 when done, 3 for a dirty tree under --apply, and 1 for anything else; a
failure first deletes the files this run created.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import os
import re
import sys
import tomllib
from typing import NamedTuple, cast

from bytewyrd import cli, detect, fs, git, seed

NOTE_IMPORT: str = "note: CLAUDE.md has no '@AGENTS.md' line; Claude Code will not read AGENTS.md until you add one"
NOTE_DIRTY: str = "note: working tree is dirty; --apply will refuse without --allow-dirty"
NOTE_SKIPPED: str = "note: no CI job for %s: %s"
NOTE_RUBY_VERSION: str = (
    "note: %s gives setup-ruby no Ruby version; add .ruby-version, or a ruby line to .tool-versions or mise.toml"
)
NOTE_PLATFORM: str = "note: %s lacks the CI runner's platform; run bundle lock --add-platform x86_64-linux"
NOTE_PNPM: str = (
    "note: %s has pnpm-lock.yaml, and the ruby CI job has no pnpm; "
    "a Rails test:prepare that builds JavaScript fails there"
)
NOTE_PYTEST: str = "note: %s lists pytest in no dependency group; the python CI job runs uv run pytest"

SKIP_EXISTS: str = "exists; scaffold never overwrites"
SKIP_PR_TEMPLATE: str = "pull request template found: %s"
SKIP_WORKFLOW: str = "another workflow exists"

REFUSE_SYMLINK: str = "scaffold: %s is a symlink; refusing to write through it"
REFUSE_DIRTY: str = "scaffold: working tree is dirty; commit first or pass --allow-dirty"

# setup-ruby takes an unset ruby-version from the first of these files that
# exists in its working directory: .ruby-version whole, the others by the
# first line that matches its pattern (ruby/setup-ruby v1.338.0, index.js).
_RUBY_VERSION_FILES: tuple[tuple[str, re.Pattern[str] | None], ...] = (
    (".ruby-version", None),
    (".tool-versions", re.compile(r"^ruby\s+(\S+)")),
    ("mise.toml", re.compile(r"""^\s*ruby\s*=\s*['"]([^'"]+)['"]\s*(?:#.*)?$""")),
)
# A Gemfile.lock platform that installs on the ubuntu-latest runner.
_RUNNER_PLATFORMS: frozenset[str] = frozenset(("ruby", "x86_64-linux"))
# A dependency-group entry's name: what precedes any version, extra or marker.
_REQUIREMENT_NAME: re.Pattern[str] = re.compile(r"\s*([A-Za-z0-9._-]+)")


class Refusal(Exception):
    """Preflight's refusal: MESSAGE goes to stderr and the exit code is CODE."""

    def __init__(self, message: str, code: int) -> None:
        super().__init__(message)
        self.message = message
        self.code = code


class Step(NamedTuple):
    """What scaffold does for one target: create it from TEMPLATE, or skip it
    for the reason SKIP (exactly one of the two is set)."""

    target: seed.Target
    template: str | None
    skip: str | None


class Run:
    """The work tree and what this run created in it, for the clean-up on failure."""

    def __init__(self) -> None:
        self.root: str | None = None
        self.files: list[str] = []  # root-relative paths, in creation order
        self.dirs: list[str] = []  # absolute paths, outermost first


# --- planning ----------------------------------------------------------------


def plan(root: str, comps: list[detect.Component]) -> list[Step]:
    """One Step per target, in the target table's order."""
    steps: list[Step] = []
    for target in seed.TARGETS:
        parent, base = os.path.split(target.path)
        if fs.exists(os.path.join(root, parent), base):
            steps.append(Step(target, None, SKIP_EXISTS))
            continue
        if target is seed.PR_TEMPLATE:
            found = seed.pr_template(root)
            if found is not None:
                steps.append(Step(target, None, SKIP_PR_TEMPLATE % cli.quote(found)))
                continue
        if target is seed.CI_YML and seed.workflow_exists(root):
            steps.append(Step(target, None, SKIP_WORKFLOW))
            continue
        steps.append(Step(target, seed.template_for(target, comps), None))
    return steps


def seed_text(target: seed.Target, template: str, comps: list[detect.Component], name: str, sha: str) -> str:
    """The text scaffold writes for TARGET: the stamp, then the rendered template."""
    text, digest = seed.read_template(template)
    return seed.stamp(target.kind, template, digest, sha) + "\n" + seed.render(text, comps, name)


# --- the CI notes ------------------------------------------------------------


def _join(directory: str, name: str) -> str:
    return name if directory == "." else directory + "/" + name


def _index_text(root: str, entry: git.Entry | None) -> str | None:
    """An index entry's text, or None when it declares nothing (B2, Reading)."""
    data = git.blob(root, entry) if entry is not None else None
    if data is None:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def gives_ruby_version(root: str, by_path: dict[str, git.Entry], directory: str) -> bool:
    """True when setup-ruby, run in DIRECTORY, finds a Ruby version there."""
    for name, pattern in _RUBY_VERSION_FILES:
        entry = by_path.get(_join(directory, name))
        if entry is None:
            continue
        text = _index_text(root, entry)
        if text is None:
            return False
        text = text.strip()
        if pattern is None:
            return text != ""
        return any(pattern.match(line) for line in re.split(r"\r?\n", text))
    return False


def lockfile_platforms(text: str) -> list[str] | None:
    """The platforms a Gemfile.lock's PLATFORMS section lists, or None without one."""
    lines = text.replace("\r", "").split("\n")
    if "PLATFORMS" not in lines:
        return None
    platforms: list[str] = []
    for line in lines[lines.index("PLATFORMS") + 1 :]:
        if not line.startswith(" "):
            break
        platforms.append(line.strip())
    return platforms


def lists_pytest(text: str) -> bool:
    """True when a pyproject.toml's [dependency-groups] has an entry named pytest."""
    try:
        doc = tomllib.loads(text)
    except (ValueError, RecursionError):
        return False
    groups = doc.get("dependency-groups")
    if not isinstance(groups, dict):
        return False
    for entries in groups.values():
        if not isinstance(entries, list):
            continue
        for item in entries:
            m = _REQUIREMENT_NAME.match(item) if isinstance(item, str) else None
            if m and m.group(1).lower() == "pytest":
                return True
    return False


def ci_notes(root: str, comps: list[detect.Component], skipped: list[detect.Skip]) -> list[str]:
    """The notes printed with a new ci.yml: why each SKIPPED manifest gets no
    job, then what each Ruby or Python component's lang-ci job will miss."""
    notes = [NOTE_SKIPPED % (cli.quote(s.path), s.reason) for s in skipped]
    if not any(c.language in ("python", "ruby") for c in comps):
        return notes
    by_path: dict[str, git.Entry] = {}
    for entry in git.tracked(root):
        by_path.setdefault(entry.path, entry)
    for c in comps:
        if c.language == "python":
            pyproject = _join(c.directory, "pyproject.toml")
            text = _index_text(root, by_path.get(pyproject))
            if text is None or not lists_pytest(text):
                notes.append(NOTE_PYTEST % cli.quote(pyproject))
        elif c.language == "ruby":
            if not gives_ruby_version(root, by_path, c.directory):
                notes.append(NOTE_RUBY_VERSION % cli.quote(c.directory))
            lockfile = _join(c.directory, "Gemfile.lock")
            text = _index_text(root, by_path.get(lockfile))
            platforms = lockfile_platforms(text) if text is not None else None
            if platforms is not None and not _RUNNER_PLATFORMS.intersection(platforms):
                notes.append(NOTE_PLATFORM % cli.quote(lockfile))
            if _join(c.directory, "pnpm-lock.yaml") in by_path:
                notes.append(NOTE_PNPM % cli.quote(c.directory))
    return notes


# --- writing -----------------------------------------------------------------


def write(root: str, rel: str, text: str, run: Run) -> None:
    """Create ROOT/REL holding TEXT, recording what was created in RUN."""
    path = os.path.join(root, rel)
    parent = os.path.dirname(path)
    absent: list[str] = []  # the directories makedirs is about to make, innermost first
    here = parent
    while not os.path.lexists(here):
        absent.append(here)
        here = os.path.dirname(here)
    try:
        try:
            os.makedirs(parent, exist_ok=True)
        finally:
            run.dirs.extend(made for made in reversed(absent) if os.path.isdir(made))
        fs.create(path, text)
    except OSError as e:
        raise cli.BwError("cannot create %s: %s" % (cli.quote(rel), e.strerror or cli.describe(e))) from e
    run.files.append(rel)


def clean_up(root: str, run: Run) -> list[str]:
    """Delete RUN's files, then any directory it made that is left empty.
    Returns the files that could not be deleted."""
    left: list[str] = []
    for rel in reversed(run.files):
        try:
            os.unlink(os.path.join(root, rel))
        except FileNotFoundError:
            pass
        except OSError:
            left.append(rel)
    for d in reversed(run.dirs):
        try:
            os.rmdir(d)
        except OSError:
            pass
    return list(reversed(left))


# --- the command -------------------------------------------------------------


def scaffold(argv: list[str], run: Run) -> int:
    parser = cli.Parser(
        prog="bw scaffold",
        description="Seed AGENTS.md, CLAUDE.md, a pull request template and a CI workflow, each only if missing.",
    )
    parser.add_argument("--apply", action="store_true", help="write the files; without it, only report")
    parser.add_argument("--allow-dirty", action="store_true", help="with --apply, write even when the tree is dirty")
    args = parser.parse_args(argv)

    root = git.root()
    run.root = root
    comps, skipped = detect.detect(root)
    steps = plan(root, comps)
    creating = [s for s in steps if s.template is not None]

    # Preflight, which writes nothing: symlinks, the texts to write, a dirty tree.
    for step in creating:
        hit = fs.symlinked_dir(root, step.target.path)
        if hit is not None:
            raise Refusal(REFUSE_SYMLINK % cli.quote(hit), 1)
    name, sha = git.project_name(root), seed.plugin_sha(seed.PLUGIN_DIR)
    # creating holds only the steps whose template is set.
    texts = {s.target.path: seed_text(s.target, cast(str, s.template), comps, name, sha) for s in creating}
    dirty = False
    if not args.apply:
        dirty = git.dirty(root)
    elif not args.allow_dirty and git.dirty(root):
        raise Refusal(REFUSE_DIRTY, 3)

    notes: list[str] = []
    if any(s.target is seed.CLAUDE_MD and s.skip is not None for s in steps) and seed.lacks_import(root):
        notes.append(NOTE_IMPORT)
    if any(s.target is seed.CI_YML for s in creating):
        notes.extend(ci_notes(root, comps, skipped))
    if dirty:
        notes.append(NOTE_DIRTY)

    out = ["bytewyrd scaffold: " + cli.quote(root)]
    for step in steps:
        path = cli.quote(step.target.path)
        if step.skip is not None:
            out.append("skip  %s  (%s)" % (path, step.skip))
        elif args.apply:
            write(root, step.target.path, texts[step.target.path], run)
            out.append("created  " + path)
        else:
            out.append("would create  " + path)
    out.extend(notes)
    counts = (len(creating), len(steps) - len(creating))
    if args.apply:
        out.append("applied: %d created, %d skipped" % counts)
    else:
        out.append("dry run: %d to create, %d skipped; re-run with --apply to write" % counts)
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
    return 0


def _err(line: str) -> None:
    try:
        sys.stderr.write(line + "\n")
        sys.stderr.flush()
    except BaseException:
        pass


def main(argv: list[str]) -> int:
    run = Run()
    try:
        return scaffold(argv, run)
    except SystemExit as e:
        code = e.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    except Refusal as e:
        _err(e.message)
        return e.code
    except BaseException as e:
        # write() records a file only after scaffold() has set run.root.
        left = clean_up(cast(str, run.root), run) if run.files else []
        _err("scaffold: " + cli.describe(e))
        if left:
            _err("scaffold: failed; remove these, then re-run: rm -- " + " ".join(map(cli.quote, left)))
        elif run.files:
            _err("scaffold: failed; removed: " + " ".join(map(cli.quote, run.files)))
        return 1
