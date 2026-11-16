"""Tests for hooks/hooks.json (RFC 2026-11-09-scaffold-and-drift, B4, AC-17 and AC-20). Each test
runs a hook's real command string from hooks.json the way Claude Code runs a shell-form hook, with
sh -c and CLAUDE_PLUGIN_ROOT set to this repository: the rules entry prints
hooks/always-on-rules.json within the 2,000-character cap, the compact reminder prints only while
the SubagentStop sentinel is under a day old, and without Python 3.11 or newer every hook still
exits 0.

The commands run as child processes in an empty project directory, with BYTEWYRD_PYTHON the
interpreter that runs pytest, except where a case takes Python away (the Stubs kit in
conftest.py). Output is compared as the bytes the child wrote, trailing newlines included.
"""

import json
import os
import re
import shutil
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
HOOKS = REPO / "hooks" / "hooks.json"
RULES = REPO / "hooks" / "always-on-rules.json"
SH = shutil.which("sh")

FE_MATCHER = "(^|:)feature-engineer$"
RULES_MATCHER = "startup|clear|compact"
NEEDS = b"bytewyrd: needs Python 3.11 or newer (set BYTEWYRD_PYTHON or install python3.11+)"
# What the hooks print, each with the newline that ends it.
FE_REMINDER = (
    b"Post-feature-implementation: if this feature affects user-visible behavior (a new skill, an agent change, "
    b"a new CLI flag, a new workflow), ask the user to run /docs-review against the changed paths to check "
    b"whether docs/guide/** needs updates.\n"
)
COMPACT_REMINDER = (
    b"Post-compact reminder: a feature-engineer agent finished in the last 24 hours and /docs-review may not "
    b"yet have run. Ask the user to run /docs-review against the implemented files.\n"
)


def load_hooks():
    """The "hooks" table of hooks.json."""
    return json.loads(HOOKS.read_text())["hooks"]


def hook(event, matcher, index=0):
    """The command of hook INDEX in the EVENT entry whose matcher is MATCHER; fail when no entry, or
    more than one, has that matcher."""
    (entry,) = [e for e in load_hooks()[event] if e["matcher"] == matcher]
    return entry["hooks"][index]["command"]


def write_sentinel(project, mtime):
    """Create the SubagentStop sentinel, with its mtime set to MTIME, in seconds since the epoch."""
    state = project / ".bytewyrd"
    state.mkdir()
    sentinel = state / "last-feature-engineer-stop"
    sentinel.touch()
    os.utime(sentinel, (mtime, mtime))


@pytest.fixture
def run_hook(run_child, bw_env):
    """run_hook(COMMAND, env=BW_ENV): a hook's command string, run with sh -c and CLAUDE_PLUGIN_ROOT set
    to this repository."""

    def run_hook(command, env=None):
        env = {**(bw_env if env is None else env), "CLAUDE_PLUGIN_ROOT": str(REPO)}
        return run_child([SH, "-c", command], env=env)

    return run_hook


def test_hooks_json_holds_the_feature_engineer_subagent_stop_entry_and_the_compact_and_startup_session_start_entries():
    hooks = load_hooks()
    assert [(event, [entry["matcher"] for entry in entries]) for event, entries in hooks.items()] == [
        ("SubagentStop", [FE_MATCHER]),
        ("SessionStart", ["compact", RULES_MATCHER]),
    ]
    assert {h["type"] for entries in hooks.values() for entry in entries for h in entry["hooks"]} == {"command"}
    # No hook calls check-requirements or stat (AC-17, B4).
    assert re.search(r"stat -[cf]|check-requirements", HOOKS.read_text()) is None


def test_hooks_startup_clear_compact_entry_prints_the_rules_file_whose_context_fits_in_2000_characters(run_hook):
    got = run_hook(hook("SessionStart", RULES_MATCHER))
    assert got == (0, RULES.read_bytes(), b"")
    # B4's size check, on what the hook printed.
    output = json.loads(got.stdout)["hookSpecificOutput"]
    assert output["hookEventName"] == "SessionStart"
    assert len(output["additionalContext"]) <= 2000


def test_hooks_compact_entry_prints_nothing_without_a_sentinel(run_hook):
    assert run_hook(hook("SessionStart", "compact")) == (0, b"", b"")


@pytest.mark.parametrize(
    "age, due",
    [(0, True), (82800, True), (90000, False)],
    ids=["fresh", "23-hours-old", "25-hours-old"],
)
def test_hooks_compact_entry_prints_its_reminder_only_while_the_sentinel_is_under_a_day_old(
    age, due, run_hook, project
):
    write_sentinel(project, time.time() - age)
    assert run_hook(hook("SessionStart", "compact")) == (0, COMPACT_REMINDER if due else b"", b"")


def test_hooks_compact_entry_prints_nothing_for_a_sentinel_from_the_year_2000(run_hook, project):
    # touch -t 200001010000: January 1st, 00:00 local time.
    write_sentinel(project, time.mktime((2000, 1, 1, 0, 0, 0, 0, 0, -1)))
    assert run_hook(hook("SessionStart", "compact")) == (0, b"", b"")


def test_hooks_feature_engineer_entry_asks_for_docs_review_and_touches_the_sentinel_the_compact_entry_reads(
    run_hook, project
):
    assert run_hook(hook("SubagentStop", FE_MATCHER, 0)) == (0, FE_REMINDER, b"")
    assert run_hook(hook("SubagentStop", FE_MATCHER, 1)) == (0, b"", b"")
    state = project / ".bytewyrd"
    assert (state / "last-feature-engineer-stop").is_file()
    assert (state / ".gitignore").read_bytes() == b"*\n"
    assert run_hook(hook("SessionStart", "compact")) == (0, COMPACT_REMINDER, b"")


def test_hooks_subagent_stop_write_refuses_a_symlinked_bytewyrd_and_leaves_its_target_unchanged(
    run_hook, project, outside
):
    os.symlink(outside, project / ".bytewyrd")
    got = run_hook(hook("SubagentStop", FE_MATCHER, 1))
    assert got == (0, b"", b"state-touch: .bytewyrd is a symlink; refusing to write through it\n")
    assert os.listdir(outside) == []


@pytest.mark.parametrize("setup", ["none", "old"])
def test_hooks_without_python_3_11_every_command_exits_0_and_the_write_and_the_reminder_print_nothing(
    setup, run_hook, stubs, project
):
    # A fresh sentinel, so that only the missing interpreter keeps the reminder quiet.
    write_sentinel(project, time.time())
    env = stubs.without_python(setup)
    commands = [h["command"] for entries in load_hooks().values() for entry in entries for h in entry["hooks"]]
    assert commands, "hooks.json has no commands"
    for command in commands:
        got = run_hook(command, env=env)
        assert got.returncode == 0, "exit %d under the %r setup: %s" % (got.returncode, setup, command)
    for command in (hook("SubagentStop", FE_MATCHER, 1), hook("SessionStart", "compact")):
        assert run_hook(command, env=env) == (0, b"", NEEDS + b"\n")
    # The rules hook is a plain cat and needs no Python.
    assert run_hook(hook("SessionStart", RULES_MATCHER), env=env) == (0, RULES.read_bytes(), b"")
    assert os.listdir(project / ".bytewyrd") == ["last-feature-engineer-stop"]
