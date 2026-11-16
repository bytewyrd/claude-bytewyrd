"""The Python behind scripts/bw, the launcher of the plugin's commands.

scripts/bw runs __main__.py, the bootstrap, which checks the interpreter and
dispatches NAME to bytewyrd.commands.<name>. The shared modules never exit the
process: their functions return values or raise, and each command's main()
decides the exit code. Detection reads repo files from the index, through
git.blob(); the seed files themselves are read from the work tree, through
fs.read_text(). Every repo-derived string that scaffold and drift print goes
through cli.quote(); the JSON helpers print theirs through jsonout.jq_dumps().

This file holds only its docstring, so any Python 3 imports the package:
`python -m bytewyrd` imports it before the bootstrap's version check.

Contract: docs/rfcs/2026-11-09-scaffold-and-drift.md, Appendix B2.
"""
