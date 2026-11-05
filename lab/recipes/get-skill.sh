#!/bin/bash
# Copy Moderne's create-recipe skill for Claude Code into .claude/skills/ from your own Moderne CLI install.
# The skill is Moderne's and isn't redistributed in this repo. The CLI puts it in its home, which for this course is
# the `moderne-lab-home` Docker volume (Lab 2). Read it before you use it.
#   ./get-skill.sh            copy it
#   ./get-skill.sh --dry-run  say what would be copied, change nothing
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=.claude/marketplaces/moderne/moderne/skills/create-recipe/SKILL.md
DEST="$HERE/.claude/skills/create-recipe"
docker volume inspect moderne-lab-home >/dev/null 2>&1 \
  || { echo "no moderne-lab-home volume yet: do Lab 2 (cli/lab2.sh) first" >&2; exit 1; }
if [ "${1:-}" = "--dry-run" ]; then
  echo "would copy moderne-lab-home:/$SRC to $DEST/SKILL.md"
  exit 0
fi
mkdir -p "$DEST"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v moderne-lab-home:/h:ro -v "$DEST":/out \
  maven:3.9-eclipse-temurin-21 sh -c "test -f /h/$SRC && cp /h/$SRC /out/SKILL.md" \
  || { echo "skill not found in moderne-lab-home: run 'mod --version' in the Lab 2 container, then retry" >&2; exit 1; }
echo "copied: $DEST/SKILL.md"
