"""The B3 fix for legacy-settings-hooks: the 0.2.x hook entries go, and the file too if it becomes {}."""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _port  # noqa: E402

SETTINGS = ".claude/settings.json"
MARKERS = (
    "precompact-extraction-done",
    "Post-commit: does this change component structure",
    "Session ending: (1) /best-practices-extract",
    "Consider running /sync",
)


def before(port):
    settings = json.loads(port.read(SETTINGS))
    hooks = settings.get("hooks", {})
    for event in list(hooks):
        kept = [entry for entry in hooks[event] if not any(m in json.dumps(entry, ensure_ascii=False) for m in MARKERS)]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        settings.pop("hooks", None)
    if settings:
        port.write(SETTINGS, json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
    else:
        port.remove(SETTINGS)


_port.main(before)
