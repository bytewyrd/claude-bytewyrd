#!/usr/bin/env bats
# Consistency tests for the real bootstrap-manifest.json against the real
# templates. Unlike the other sync-*.bats files (which drive scripts against
# isolated fixtures), these validate the plugin's shipped manifest data.

setup() {
  load "helpers"
  setup_common
  MANIFEST="$SCRIPT_ROOT/bootstrap-manifest.json"
  CLAUDE_TPL="$SCRIPT_ROOT/templates/CLAUDE.md.tpl"
}

teardown() {
  teardown_common
}

# Return the sorted, unique set of `## ` headings for a jq expression selecting
# fields on the CLAUDE.md artifact.
_claude_sections() {
  jq -r ".artifacts[] | select(.target==\"CLAUDE.md\") | $1[]" "$MANIFEST" | sort -u
}

@test "CLAUDE.md: every template heading is categorized (owned or project-owned)" {
  # Guard against the fix-#5 bug class: a section added to templates/CLAUDE.md.tpl
  # but forgotten in the manifest (as ## Auto Mode and ## Git both were). Every
  # `## ` heading must be accounted for — either plugin-owned (owned_sections,
  # re-merged on each /sync) or deliberately project-owned (project_owned_sections,
  # written once from language/structure detection then never touched again; see
  # commit ad12f3b for ## Toolchain / ## File structure).
  local headings categorized uncategorized
  headings="$(grep '^## ' "$CLAUDE_TPL" | sort -u)"
  categorized="$(_claude_sections '((.owned_sections // []) + (.project_owned_sections // []))')"
  uncategorized="$(comm -23 <(printf '%s\n' "$headings") <(printf '%s\n' "$categorized"))"
  [ -z "$uncategorized" ] \
    || fail "template heading(s) not in owned_sections or project_owned_sections: $(echo $uncategorized)"
}

@test "CLAUDE.md: ## Git is plugin-owned (git conventions propagate to consumers)" {
  _claude_sections '.owned_sections' | grep -qx '## Git' \
    || fail "## Git must be in CLAUDE.md owned_sections — it is plugin policy that should reach every consumer"
}

@test "CLAUDE.md: owned and project-owned are disjoint and all reference real template headings" {
  local owned project_owned overlap h
  owned="$(_claude_sections '.owned_sections')"
  project_owned="$(_claude_sections '(.project_owned_sections // [])')"
  # No heading may be both owned and project-owned.
  overlap="$(comm -12 <(printf '%s\n' "$owned") <(printf '%s\n' "$project_owned"))"
  [ -z "$overlap" ] || fail "section(s) in both owned_sections and project_owned_sections: $(echo $overlap)"
  # Every categorized section must actually be a heading in the template.
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    grep -qxF "$h" "$CLAUDE_TPL" || fail "categorized section is not a heading in the template: $h"
  done < <(printf '%s\n%s\n' "$owned" "$project_owned")
}
