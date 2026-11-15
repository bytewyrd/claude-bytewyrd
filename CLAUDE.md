<!-- bytewyrd:scaffold v1 tpl=CLAUDE.md:96fff00d5f06 plugin=bbef72e2bec6 -->
@AGENTS.md

## Claude Code

- The bytewyrd plugin loads this workflow's conventions at session start. It needs Python 3.11 or newer on `PATH`, or in `BYTEWYRD_PYTHON`. Install it once per machine:
  `claude plugin marketplace add anthropics/claude-plugins-official`, then
  `claude plugin marketplace add bytewyrd/claude-bytewyrd`, then `claude plugin install bytewyrd@bytewyrd`.
  Install its dependencies explicitly too, so updates keep them resolved: `claude plugin install github@claude-plugins-official`, and the same for `context7` and `code-review`.
- Plugin skills are namespaced, for example `/bytewyrd:rfc-new` and `/bytewyrd:drift`.
- Open decisions are asked with AskUserQuestion.
