"""bw drift [--strict]: check scaffold's seed files and list 0.2.x leftovers.

Each seed target is compared with the plugin's current template through the
stamp on its line 1; ci.yml's lang-ci calls are checked against the
template's one pinned commit; and the known 0.2.x /sync artifacts are listed,
each with the fix to apply. It is deterministic and read-only: every file is
read with CRs stripped and decoded as UTF-8 with surrogateescape, diffs are
made in memory, and nothing is ever written.

Output lines are `<ok|info|warn|drift>  <path>[  <code>: <detail>]`, then any
`  fix: ...` lines and lines indented two spaces, then the footer
`result: A ok, B info, C warn, D drift (exit E)`. Every repo-derived string
goes through quote().

Exit 0 when clean, 2 for any drift (or, with --strict, any warning), and 1
when it can't run, including any exception before the footer.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""

import difflib
import os
import posixpath
import re
import sys
from typing import NamedTuple

import bw

SEVERITIES = ("ok", "info", "warn", "drift")

# The 0.2.x manifest targets that /sync stamped with a header [R7].
LEGACY_HEADER_PATHS = (
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/workflows/ci.yml",
    "CLAUDE.md",
    "README.md",
    "docs/ARCHITECTURE.md",
    "docs/BEST_PRACTICES.md",
    "docs/CONTRIBUTING.md",
    "mise.toml",
)
SIDECARS = (".bytewyrd/.bootstrap-versions.json", ".claude/.bootstrap-versions.json")
STATE_FILES = (".bytewyrd/plugin-version", ".bytewyrd/docs-agent-version")
SETTINGS = ".claude/settings.json"
SETTINGS_MARKERS = (
    "precompact-extraction-done",
    "Post-commit: does this change component structure",
    "Session ending: (1) /best-practices-extract",
    "Consider running /sync",
)

# The 0.2.x header and banner forms [R15]: the marker that 0.2.x's
# sync-marker-read.sh read, as an HTML or a # comment, and the banners that its
# sync-write-header.sh wrote and recognized ("Managed by the Bytewyrd plugin."
# or "... plugin -", and "Bootstrapped by the Bytewyrd plugin.").
_HEADER = re.compile(r"(?:<!--|#)[ \t]*bootstrap-content-version:")
_BANNER = re.compile(r"<!-- (?:Managed|Bootstrapped) by the Bytewyrd plugin")
_TAG = "# bytewyrd:"  # a .gitignore block tag, such as "# bytewyrd:base"

# ci.yml's caller checks read lines; no YAML parser is involved.
_JOBS_LINE = re.compile(r"jobs:[ \t]*(?:#.*)?")
_JOB_LINE = re.compile(r"  ([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(?:#.*)?")
_USES_LINE = re.compile(r"[ \t]*(?:-[ \t]+)?uses:(.*)")
_COMMENT = re.compile(r"[ \t]+#.*$")
# The caller template's one uses: line, as the pin checks in CI read it.
_PIN_LINE = re.compile(
    r"@@job@@     uses: bytewyrd/claude-bytewyrd/\.github/workflows/lang-ci-@@job_language@@\.yml@([0-9a-f]{40})"
)
CALL = "bytewyrd/claude-bytewyrd/.github/workflows/lang-ci-%s.yml@%s"
COMPARE = "review https://github.com/bytewyrd/claude-bytewyrd/compare/%s...%s"

FIX_SCAFFOLD = "run scaffold --apply"
FIX_IMPORT = "add the line @AGENTS.md to CLAUDE.md"
FIX_TOO_LONG = "move detail into docs/ or a skill"
FIX_CI_VARIANT = "delete line 1 to keep this file as your own, or git rm it, commit and rerun scaffold --apply"
FIX_MISSING_JOB = "add this job under jobs:, or mark the directory's manifests:"
FIX_HEADER = "delete the header and banner lines"
FIX_BEST_PRACTICES = (
    "delete the header, the banner, and the ## Pitfall ... ## Terraform / Terragrunt sections; "
    "keep the project's own entries"
)
FIX_GITIGNORE = "delete the header line and every # bytewyrd: tag line, and keep the patterns as ordinary lines"
FIX_RFC_COPY = "git rm docs/rfc-process.md, and move any ## Project Extensions text into AGENTS.md"
FIX_SETTINGS = "delete the 0.2.x hook entries from .claude/settings.json, and delete the file if it becomes {}"
FIX_STATE = "git rm %s, or delete it if it is untracked; if .bytewyrd/ remains, run: sh %s state-touch"

# The ten 0.2.x plugin-owned H2s of CLAUDE.md [R34].
OWNED_H2S = (
    "Agent delegation, Auto Mode, Tool Usage, RFC Process, Evidence-Based Development, "
    "Model Usage Optimization, Claude Code Sandbox, Security, Git and Conventions"
)
FIX_CLAUDE_LEGACY = (
    "git mv CLAUDE.md CLAUDE.legacy.md; once every fix is committed, run scaffold --apply",
    "then delete from CLAUDE.legacy.md only its ten 0.2.x owned H2s (%s); the plugin's always-on rules, "
    "rfc-process skill and best-practices library cover them" % OWNED_H2S,
    "move every other H2 to AGENTS.md, or into CLAUDE.md if it is Claude-only, then git rm CLAUDE.legacy.md",
)

MISSING = {
    bw.AGENTS_MD.path: "no AGENTS.md at the top of the work tree",
    bw.CLAUDE_MD.path: "no CLAUDE.md at the top of the work tree",
    bw.PR_TEMPLATE.path: "no pull request template at the top level, in docs/ or in .github/",
    bw.CI_YML.path: "no workflow in .github/workflows/",
}


class Finding(NamedTuple):
    """One output entry: SEVERITY and PATH as printed, CODE ("" for ok) and
    DETAIL, then FIXES (printed as `  fix: ...`) and EXTRA lines (printed
    indented two spaces)."""

    severity: str
    path: str
    code: str = ""
    detail: str = ""
    fixes: tuple = ()
    extra: tuple = ()

    def lines(self):
        head = "%s  %s" % (self.severity, self.path)
        if self.code:
            head += "  %s: %s" % (self.code, self.detail)
        return [head] + ["  fix: " + f for f in self.fixes] + ["  " + x for x in self.extra]


class Context:
    """What every check needs: the work tree, its components, and the plugin's templates."""

    def __init__(self, root):
        self.root = root
        self.comps, self.skipped = bw.detect(root)
        self.templates = {name: bw.read_template(name) for name in bw.TEMPLATES}
        self.pin = caller_pin(self.templates[bw.CI_CALLER][0])
        self.name = bw.project_name(root)
        self.sha = bw.plugin_sha(bw.PLUGIN_DIR)

    def render(self, template):
        return bw.render(self.templates[template][0], self.comps, self.name)

    def stamp(self, target, template):
        return bw.stamp(target.kind, template, self.templates[template][1], self.sha)


def caller_pin(text):
    """The commit the caller template pins: its one uses: line's 40 hex digits."""
    pins = [m.group(1) for m in map(_PIN_LINE.fullmatch, text.replace("\r", "").split("\n")) if m]
    if len(pins) != 1:
        raise bw.BwError("template ci-caller.yml has no single pinned lang-ci uses: line")
    return pins[0]


def _where(lines):
    """Line numbers as text: "line 1", "lines 1 and 2", "lines 1, 2 and 5"."""
    if len(lines) == 1:
        return "line %d" % lines[0]
    return "lines %s and %d" % (", ".join(map(str, lines[:-1])), lines[-1])


def _unprintable(text):
    return any(ord(c) < 0x20 or ord(c) == 0x7F or 0xD800 <= ord(c) <= 0xDFFF for c in text)


def diff(rel, text, rendered):
    """The unified diff from TEXT without its line 1 to RENDERED, as lines.
    A line whose text holds a control character or a surrogate is printed as
    quote() of that text, after its one-character prefix."""
    body = text.split("\n")[1:]
    new = rendered.split("\n")
    for lines in (body, new):
        if lines and lines[-1] == "":
            lines.pop()
    out = []
    for i, line in enumerate(difflib.unified_diff(body, new, "a/" + rel, "b/" + rel, lineterm="")):
        if i < 2 or line.startswith("@@"):
            out.append(line)  # the ---/+++ headers and @@ hunk headers, built from safe text
        elif _unprintable(line[1:]):
            out.append(line[0] + bw.quote(line[1:]))
        else:
            out.append(line)
    return tuple(out)


def legacy_lines(text):
    """The numbers of lines 1 to 3 of TEXT that hold a 0.2.x header or banner."""
    return [i + 1 for i, line in enumerate(text.split("\n")[:3]) if _HEADER.match(line) or _BANNER.match(line)]


# --- seed targets ------------------------------------------------------------


def legacy_header(target_path, shown, lines):
    where = _where(lines)
    detail = "a 0.2.x /sync header or banner on " + where
    if target_path == bw.CLAUDE_MD.path:
        fixes = FIX_CLAUDE_LEGACY
    elif target_path in (bw.PR_TEMPLATE.path, bw.CI_YML.path):
        fixes = ("delete %s so the repo's own file stays; drift then reports it as unstamped" % where,)
    elif target_path == "docs/BEST_PRACTICES.md":
        fixes = (FIX_BEST_PRACTICES,)
    else:
        fixes = (FIX_HEADER,)
    return Finding("drift", shown, "legacy-header", detail, fixes)


def stamp_row(ctx, target, rel, shown, path, text):
    """The stamp row for a readable seed target with no 0.2.x header, and its stamp."""
    stamp = bw.read_stamp(path)
    if stamp is None:
        detail = "line 1 has no scaffold stamp, so drift compares it with no template"
        return [Finding("info", shown, "unstamped", detail)], None
    pick = bw.template_for(target, ctx.comps)
    if stamp is bw.BAD or not bw.fits(target, stamp[0]):
        if stamp is bw.BAD:
            detail = "line 1 has a bytewyrd:scaffold stamp that does not parse"
        else:
            detail = "the stamp names %s, which is not a template for this file" % bw.quote(stamp[0])
        fix = "replace line 1 with: %s after reviewing the diff" % ctx.stamp(target, pick)
        return [Finding("drift", shown, "bad-stamp", detail, (fix,), diff(rel, text, ctx.render(pick)))], None
    template, digest, _ = stamp
    if target is bw.CI_YML and template != pick:
        return [], stamp  # ci-variant's first case reports this file instead
    current = ctx.templates[template][1]
    if digest == current:
        return [Finding("ok", shown)], stamp
    detail = "the stamp names %s:%s, and the plugin's template is now %s:%s" % (template, digest, template, current)
    fix = "apply the diff, then replace line 1 with: " + ctx.stamp(target, template)
    return [Finding("drift", shown, "template-changed", detail, (fix,), diff(rel, text, ctx.render(template)))], stamp


def line_count(text):
    return text.count("\n") + (1 if text and not text.endswith("\n") else 0)


def too_long(target, shown, text):
    lines, chars = line_count(text), len(text)
    if target is bw.AGENTS_MD and (lines > 100 or chars > 8000):
        detail = "%d lines and %d characters; the limits are 100 lines and 8,000 characters" % (lines, chars)
    elif target is bw.CLAUDE_MD and lines > 200:
        detail = "%d lines; the limit is 200" % lines
    else:
        return []
    return [Finding("warn", shown, "too-long", detail, (FIX_TOO_LONG,))]


def check_seed(ctx, target):
    """The findings for one seed target, its row and then its separate checks,
    and the stamp its row accepted (None without one)."""
    parent, base = posixpath.split(target.path)
    directory = os.path.join(ctx.root, parent)
    entry = bw.find_entry(directory, base)
    if entry is None:
        if target is bw.PR_TEMPLATE and bw.pr_template(ctx.root) is not None:
            return [], None
        if target is bw.CI_YML and bw.workflow_exists(ctx.root):
            return [], None
        return [Finding("warn", bw.quote(target.path), "missing", MISSING[target.path], (FIX_SCAFFOLD,))], None
    rel = posixpath.join(parent, entry)
    path = os.path.join(directory, entry)
    shown = bw.quote(rel)
    text = bw.read_text(path)
    stamp = None
    header = legacy_lines(text) if text is not None and target.path in LEGACY_HEADER_PATHS else []
    if header:
        findings = [legacy_header(target.path, shown, header)]
    elif text is None:
        findings = [Finding("info", shown, "unstamped", "not a regular file that drift can read")]
    else:
        findings, stamp = stamp_row(ctx, target, rel, shown, path, text)

    if target is bw.CLAUDE_MD and bw.exists(ctx.root, bw.AGENTS_MD.path) and bw.lacks_import(ctx.root):
        detail = "no line is @AGENTS.md, so Claude Code does not read AGENTS.md"
        findings.append(Finding("drift", shown, "no-import", detail, (FIX_IMPORT,)))
    if target in (bw.AGENTS_MD, bw.CLAUDE_MD) and text is not None:
        findings.extend(too_long(target, shown, text))
    if target is bw.CI_YML and stamp is not None:
        findings.extend(caller_checks(ctx, shown, text, stamp[0]))
    return findings, stamp


# --- caller checks -----------------------------------------------------------


class Block(NamedTuple):
    """A job block of ci.yml: its id, the index of its id line, and the
    indexes of the lines under it."""

    job_id: str
    start: int
    body: tuple


def job_blocks(lines):
    """ci.yml's job blocks: after the top-level jobs: line, each runs from a
    line of two spaces, an id and ":" to the next such line or top-level line.
    Blank and comment lines end no block."""
    blocks, in_jobs, current = [], False, None
    for i, line in enumerate(lines):
        if not line.strip() or line.lstrip().startswith("#"):
            if current is not None:
                current[2].append(i)
            continue
        if not line.startswith((" ", "\t")):
            in_jobs, current = bool(_JOBS_LINE.fullmatch(line)), None
            continue
        if not in_jobs:
            continue
        m = _JOB_LINE.fullmatch(line)
        if m:
            current = (m.group(1), i, [])
            blocks.append(current)
        elif current is not None:
            current[2].append(i)
    return [Block(job_id, start, tuple(body)) for job_id, start, body in blocks]


def uses_value(rest):
    """A uses: value: the text after uses:, with a trailing " #" comment,
    surrounding spaces and one pair of matching quotes removed."""
    value = _COMMENT.sub("", rest).strip(" \t")
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def workflow_name(value):
    """The file a uses: value names: the text after its last "/", up to any "@"."""
    return value.split("@", 1)[0].rsplit("/", 1)[-1]


def pin_fixes(value, language, pin):
    """The fix lines for a uses: VALUE that should call LANGUAGE's lang-ci file
    at PIN; LANGUAGE None takes the id that VALUE names, or "<id>"."""
    if language is None:
        m = re.fullmatch(r"lang-ci-(.+)\.yml", workflow_name(value))
        language = bw.quote(m.group(1)) if m else "<id>"
    call = CALL % (language, pin)
    base, _, ref = value.partition("@")
    fixes = []
    if ref and base == call.partition("@")[0]:
        fixes.append(COMPARE % (bw.quote(ref), pin))
    fixes.append("set this uses: to " + call)
    return tuple(fixes)


def missing_job(ctx, shown, comp):
    """ci-variant's second case: COMP has no job block. The fix lines mark its
    manifests; the job block to add follows, rendered as scaffold would."""
    where = comp.language if comp.directory == "." else "%s in %s/" % (comp.language, bw.quote(comp.directory))
    detail = "no job block for %s (job id %s)" % (where, bw.quote(comp.job_id))
    fixes = (FIX_MISSING_JOB,) + tuple(bw.attr_line(m) for m in comp.manifests)
    caller = ctx.templates[bw.CI_CALLER][0].replace("\r", "").split("\n")
    job = bw.render("\n".join(line for line in caller if line.startswith("@@job@@ ")), [comp], ctx.name)
    return Finding("warn", shown, "ci-variant", detail, fixes, tuple(job.split("\n")))


def caller_checks(ctx, shown, text, template):
    """ci-variant, and for a caller-stamped ci.yml, pin-changed."""
    findings = []
    pick = bw.template_for(bw.CI_YML, ctx.comps)
    if template != pick:
        detail = "the stamp names %s, and scaffold now picks %s for this repo's components" % (template, pick)
        findings.append(Finding("warn", shown, "ci-variant", detail, (FIX_CI_VARIANT,)))
    if template != bw.CI_CALLER:
        return findings

    lines = text.split("\n")
    blocks = job_blocks(lines)
    owner = {}  # line index -> the component whose job block holds the line
    pinned = []  # (line index, finding), sorted into file order below
    for c in ctx.comps:
        want = 'directory: "%s"' % c.directory
        mine = (b for b in blocks if b.job_id == c.job_id and any(lines[j].strip() == want for j in b.body))
        block = next(mine, None)
        if block is None:
            findings.append(missing_job(ctx, shown, c))
            continue
        owner.update((j, c) for j in block.body)
        if not any(_USES_LINE.match(lines[j]) for j in block.body):
            detail = "job %s has no uses: line" % bw.quote(c.job_id)
            fixes = pin_fixes("", c.language, ctx.pin)
            pinned.append((block.start, Finding("drift", shown, "pin-changed", detail, fixes)))

    seen = set()
    for i, line in enumerate(lines):
        m = _USES_LINE.match(line)
        if not m:
            continue
        value = uses_value(m.group(1))
        c = owner.get(i)
        if c is not None:
            expected, language = {CALL % (c.language, ctx.pin)}, c.language
        elif workflow_name(value).startswith("lang-ci"):
            expected, language = {CALL % (lang, ctx.pin) for lang in bw.LANGUAGES}, None
        else:
            continue
        if value in expected or value in seen:
            continue
        seen.add(value)
        detail = "line %d uses %s" % (i + 1, bw.quote(value))
        pinned.append((i, Finding("drift", shown, "pin-changed", detail, pin_fixes(value, language, ctx.pin))))
    findings.extend(f for _, f in sorted(pinned, key=lambda p: p[0]))
    return findings


# --- 0.2.x artifacts ---------------------------------------------------------


def check_legacy(ctx):
    """The legacy-* findings for the paths that are not seed targets."""
    findings = []
    for rel in LEGACY_HEADER_PATHS:
        if rel in (t.path for t in bw.TARGETS):
            continue
        text = bw.read_text(os.path.join(ctx.root, rel))
        lines = legacy_lines(text) if text is not None else []
        if lines:
            findings.append(legacy_header(rel, bw.quote(rel), lines))

    text = bw.read_text(os.path.join(ctx.root, ".gitignore"))
    if text is not None:
        lines = [i + 1 for i, line in enumerate(text.split("\n")) if _HEADER.match(line) or line.startswith(_TAG)]
        if lines:
            detail = "a 0.2.x /sync header or # bytewyrd: tag on " + _where(lines)
            findings.append(Finding("drift", ".gitignore", "legacy-gitignore", detail, (FIX_GITIGNORE,)))

    text = bw.read_text(os.path.join(ctx.root, "docs", "rfc-process.md"))
    if text is not None and "# RFC Process" in text.split("\n"):
        detail = "a 0.2.x copy of the RFC process; the plugin's rfc-process skill replaces it"
        findings.append(Finding("drift", "docs/rfc-process.md", "legacy-rfc-process-copy", detail, (FIX_RFC_COPY,)))

    text = bw.read_text(os.path.join(ctx.root, SETTINGS))
    if text is not None and any(marker in text for marker in SETTINGS_MARKERS):
        detail = "0.2.x /sync hook entries"
        findings.append(Finding("drift", SETTINGS, "legacy-settings-hooks", detail, (FIX_SETTINGS,)))

    launcher = bw.quote(os.path.join(bw.PLUGIN_DIR, "scripts", "bw"))
    for code, paths, detail in (
        ("legacy-sidecar", SIDECARS, "the 0.2.x /sync version sidecar"),
        ("legacy-state", STATE_FILES, "a 0.2.x /sync state file"),
    ):
        for rel in paths:
            if os.path.lexists(os.path.join(ctx.root, rel)):
                findings.append(Finding("drift", rel, code, detail, (FIX_STATE % (rel, launcher),)))
    return findings


def check_skipped(ctx, ci_template):
    """ci-skipped: with a caller-stamped ci.yml, each SKIPPED manifest on its path."""
    if ci_template != bw.CI_CALLER:
        return []
    findings = []
    for s in ctx.skipped:
        fix = bw.skip_fix(s.path, s.reason)
        findings.append(Finding("info", bw.quote(s.path), "ci-skipped", s.reason, (fix,) if fix else ()))
    return findings


# --- the command -------------------------------------------------------------


def check(root):
    """Every finding for the work tree at ROOT, in output order."""
    ctx = Context(root)
    findings = []
    ci_template = None
    for target in bw.TARGETS:
        found, stamp = check_seed(ctx, target)
        findings.extend(found)
        if target is bw.CI_YML and stamp is not None:
            ci_template = stamp[0]
    findings.extend(check_legacy(ctx))
    findings.extend(check_skipped(ctx, ci_template))
    return findings


def drift(argv):
    parser = bw.Parser(prog="bw drift", description="Check scaffold's seed files and list leftover 0.2.x artifacts.")
    parser.add_argument("--strict", action="store_true", help="exit 2 for warnings too")
    args = parser.parse_args(argv)
    findings = check(bw.root())
    counts = {s: sum(f.severity == s for f in findings) for s in SEVERITIES}
    code = 2 if counts["drift"] or (args.strict and counts["warn"]) else 0
    out = [line for f in findings for line in f.lines()]
    out.append("result: %d ok, %d info, %d warn, %d drift (exit %d)" % (*(counts[s] for s in SEVERITIES), code))
    try:
        sys.stdout.reconfigure(errors="backslashreplace")
    except (AttributeError, ValueError):
        pass
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
    return code


def main(argv):
    try:
        return drift(argv)
    except SystemExit as e:
        code = e.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    except BaseException as e:
        try:
            sys.stderr.write("drift: " + bw.describe(e) + "\n")
            sys.stderr.flush()
        except BaseException:
            pass
        return 1
