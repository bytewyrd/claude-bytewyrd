#!/usr/bin/env bash
set -euo pipefail

# Copies RFC skills from the bytewyrd-workflow plugin (or global Claude install) into this project.
# Run from the project root: BYTEWYRD_PLUGIN_ROOT="<plugin-path>" bash /tmp/rfc-install.sh
# If BYTEWYRD_PLUGIN_ROOT is unset, falls back to ~/.claude/skills.

GLOBAL_SKILLS="${BYTEWYRD_PLUGIN_ROOT:-${HOME}/.claude}/skills"
PROJECT_SKILLS=".claude/skills"

SKILLS=(
  rfc-braindump
  rfc-install
  rfc-update
  rfc-new
  rfc-read-feedback
  rfc-approve
  rfc-implement
  rfc-drop
  rfc-consensus-review
)

echo "Copying RFC skills into ${PROJECT_SKILLS}/ ..."

for skill in "${SKILLS[@]}"; do
  src="${GLOBAL_SKILLS}/${skill}/SKILL.md"
  dst="${PROJECT_SKILLS}/${skill}/SKILL.md"

  if [ ! -f "${src}" ]; then
    echo "  SKIP  ${skill} -- not found in global install"
    continue
  fi

  mkdir -p "${PROJECT_SKILLS}/${skill}"
  cp "${src}" "${dst}"
  echo "  OK    ${skill}"
done

echo ""
echo "Done. Commit .claude/skills/ to share RFC skills with the team."
