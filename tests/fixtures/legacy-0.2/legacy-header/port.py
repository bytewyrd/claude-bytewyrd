"""The B3 fixes for legacy-header, one per kind of 0.2.x manifest target."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _port  # noqa: E402

# CLAUDE.md's ten 0.2.x plugin-owned H2s.
OWNED = {
    "Agent delegation",
    "Auto Mode",
    "Tool Usage",
    "RFC Process",
    "Evidence-Based Development",
    "Model Usage Optimization",
    "Claude Code Sandbox — Container Tool Compatibility",
    "Security",
    "Git",
    "Conventions",
}
PLUGIN_SECTIONS = ("Pitfall", "Terraform / Terragrunt")


def before(port):
    port.move("CLAUDE.md", "CLAUDE.legacy.md")
    # The repo's own files stay; only line 1, the header, goes.
    for rel in (".github/PULL_REQUEST_TEMPLATE.md", ".github/workflows/ci.yml"):
        port.keep_lines(rel, lambda n, line: n != 1)
    for rel in ("README.md", "docs/ARCHITECTURE.md", "docs/CONTRIBUTING.md", "mise.toml", "docs/BEST_PRACTICES.md"):
        port.drop_header(rel)
    # BEST_PRACTICES.md also loses the plugin's sections, ## Pitfall through ## Terraform / Terragrunt.
    preamble, sections = _port.h2_sections(port.read("docs/BEST_PRACTICES.md"))
    titles = [s.title for s in sections]
    first, last = titles.index(PLUGIN_SECTIONS[0]), titles.index(PLUGIN_SECTIONS[1])
    port.write("docs/BEST_PRACTICES.md", preamble + "".join(s.text for s in sections[:first] + sections[last + 1 :]))


def after(port):
    # Every H2 that is not plugin-owned moves to AGENTS.md; then CLAUDE.legacy.md goes.
    _, sections = _port.h2_sections(port.read("CLAUDE.legacy.md"))
    port.append("AGENTS.md", "".join("\n" + s.text.rstrip("\n") + "\n" for s in sections if s.title not in OWNED))
    port.remove("CLAUDE.legacy.md")


_port.main(before, after)
