#!/usr/bin/env bats
# Tests for the CI lint helpers in .github/scripts/:
#   lint-frontmatter.py — strict-YAML lint for agent and skill frontmatter
#   check-links.py      — relative Markdown link check
#
# Each test writes fixtures into TEST_TMPDIR (the CWD) and runs the script
# against them, so the real repository content is never involved.

setup() {
  load "helpers"
  setup_common
  LINT_FM="$SCRIPT_ROOT/.github/scripts/lint-frontmatter.py"
  CHECK_LINKS="$SCRIPT_ROOT/.github/scripts/check-links.py"
}

teardown() {
  teardown_common
}

_require_pyyaml() {
  python3 -c 'import yaml' 2>/dev/null || skip "python3 with PyYAML is required by lint-frontmatter.py"
}

# --- lint-frontmatter.py ----------------------------------------------------

@test "frontmatter: folded block description with ': ' and ' #' passes" {
  _require_pyyaml
  printf -- '---\nname: a\ndescription: >-\n  Use it. Examples: <example>x: y</example> under ## Heading.\nmodel: opus\n---\nbody\n' > a.md
  run python3 "$LINT_FM" a.md
  assert_success
  assert_output --partial "1 file(s) checked, 0 failed"
}

@test "frontmatter: plain description containing ': ' fails with its line number" {
  _require_pyyaml
  printf -- '---\nname: a\ndescription: Use it. Examples: <example>Context: x</example>\n---\n' > a.md
  run python3 "$LINT_FM" a.md
  assert_failure 1
  assert_output --partial "a.md:3: frontmatter is not valid YAML (mapping values are not allowed here)"
}

@test "frontmatter: plain value truncated by ' #' fails" {
  _require_pyyaml
  printf -- '---\nname: a\ndescription: Entries stay under ## Project-Specific.\n---\n' > a.md
  run python3 "$LINT_FM" a.md
  assert_failure 1
  assert_output --partial 'a.md:3: "description" is followed by " #..."'
}

@test "frontmatter: quoted value containing ' #' and a full-line comment pass" {
  _require_pyyaml
  printf -- '---\n# a comment line\nname: a\ndescription: "Entries stay under ## Project-Specific."\n---\n' > a.md
  run python3 "$LINT_FM" a.md
  assert_success
}

@test "frontmatter: missing frontmatter, missing closing fence, and missing description fail" {
  _require_pyyaml
  printf 'no frontmatter\n' > none.md
  printf -- '---\nname: a\ndescription: x\n' > open.md
  printf -- '---\nname: a\n---\n' > nodesc.md
  run python3 "$LINT_FM" none.md open.md nodesc.md
  assert_failure 1
  assert_output --partial 'none.md:1: missing frontmatter'
  assert_output --partial 'open.md:1: frontmatter has no closing "---" line'
  assert_output --partial 'nodesc.md:2: "description" must be a non-empty string'
  assert_output --partial "3 file(s) checked, 3 failed"
}

# --- check-links.py ---------------------------------------------------------

@test "links: an existing relative target (with or without #anchor) passes" {
  mkdir -p docs
  printf '# x\n' > docs/target.md
  printf 'See [t](target.md) and [t2](target.md#x) and [dir](../docs/).\n' > docs/source.md
  run python3 "$CHECK_LINKS" docs/source.md
  assert_success
  assert_output --partial "0 broken link(s)"
}

@test "links: a broken relative target fails with file, line, and resolved path" {
  mkdir -p docs
  printf 'line one\nSee [rfc](docs/rfc-process.md).\n' > docs/CONTRIBUTING.md
  run python3 "$CHECK_LINKS" docs/CONTRIBUTING.md
  assert_failure 1
  assert_output --partial "docs/CONTRIBUTING.md:2: broken relative link docs/rfc-process.md (resolves to docs/docs/rfc-process.md"
}

@test "links: code fences, inline code, HTML comments, and URLs are ignored" {
  cat > a.md <<'EOF'
```markdown
[fenced](missing-1.md)
```
Inline `[code](missing-2.md)` span.
<!-- [comment](missing-3.md) -->
[web](https://example.com/missing-4.md) and [mail](mailto:x@example.com) and [anchor](#top).
EOF
  run python3 "$CHECK_LINKS" a.md
  assert_success
}

@test "links: broken reference definitions and images are reported" {
  printf '![img](missing.png)\n\n[ref]: missing-ref.md\n' > a.md
  run python3 "$CHECK_LINKS" a.md
  assert_failure 1
  assert_output --partial "a.md:1: broken relative link missing.png"
  assert_output --partial "a.md:3: broken relative link missing-ref.md"
}

@test "links: a root-relative target resolves against the working directory" {
  mkdir -p docs sub
  printf 'x\n' > docs/target.md
  printf '[ok](/docs/target.md) [bad](/docs/missing.md)\n' > sub/a.md
  run python3 "$CHECK_LINKS" sub/a.md
  assert_failure 1
  assert_output --partial "broken relative link /docs/missing.md"
  refute_output --partial "/docs/target.md"
}

@test "links: with no arguments only tracked *.md files are checked" {
  git init -q .
  printf '[bad](nowhere.md)\n' > tracked.md
  printf '[bad](nowhere.md)\n' > untracked.md
  printf '[bad](nowhere.md)\n' > template.md.tpl
  git add tracked.md template.md.tpl
  run python3 "$CHECK_LINKS"
  assert_failure 1
  assert_output --partial "tracked.md:1:"
  refute_output --partial "untracked.md"
  refute_output --partial "template.md.tpl"
  assert_output --partial "1 file(s) checked, 1 broken link(s)"
}
