# @@project_name@@

Guidance for people and coding agents working in this repository. Keep it under 100 lines; put detail in docs/.

@@any@@ ## Project facts
@@any@@
@@any@@ - Languages (run each one's commands in its directory): @@languages@@
@@go@@ - Go: build `go build ./...`, test `go test ./...`
@@js@@ - JavaScript/TypeScript: install `bun install`, test `bun test --pass-with-no-tests`
@@python@@ - Python: install `uv sync --all-packages`, test `uv run pytest`
@@ruby@@ - Ruby: install `bundle install`, test `bundle exec rake`; CI reads the Ruby version from `.ruby-version`, `.tool-versions` or `mise.toml`
@@rust@@ - Rust: build `cargo build --workspace`, test `cargo test --workspace`, lint `cargo clippy --workspace`
@@any@@
## Workflow

This repository follows the bytewyrd workflow: https://github.com/bytewyrd/claude-bytewyrd
- Changes that need design start as an RFC in `docs/rfcs/`. Process: https://github.com/bytewyrd/claude-bytewyrd/blob/main/skills/rfc-process/references/rfc-process.md
- Working conventions: https://github.com/bytewyrd/claude-bytewyrd/blob/main/hooks/always-on-rules.json
- Project-specific learnings go in `docs/BEST_PRACTICES.md`.
