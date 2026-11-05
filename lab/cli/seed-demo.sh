#!/bin/bash
# Create Lab 4's demo repo (cli/ws/local/ai-found-cves) from cli/seed/ if it isn't there yet.
# It has to be its own git repo: `mod build` reads its git metadata, and `lab4.sh reset` restores it with git.
# Safe to run again: an existing demo repo is left alone.
#   ./seed-demo.sh            create it if missing
#   ./seed-demo.sh --dry-run  say what would happen, change nothing
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SEED="$HERE/seed/ai-found-cves"
DEMO="$HERE/ws/local/ai-found-cves"
if [ -d "$DEMO/.git" ]; then
  exit 0
fi
if [ -e "$DEMO" ]; then
  echo "seed-demo: $DEMO exists but isn't a git repo; move it aside and rerun" >&2
  exit 1
fi
if [ "${1:-}" = "--dry-run" ]; then
  echo "would create $DEMO from $SEED and commit it"
  exit 0
fi
mkdir -p "$(dirname "$DEMO")"
cp -r "$SEED" "$DEMO"
git -C "$DEMO" init -q -b main
git -C "$DEMO" add -A
git -C "$DEMO" -c user.name=lab -c user.email=lab@localhost commit -q -m "AI-found CVE demo"
echo "created Lab 4 demo repo: $DEMO"
