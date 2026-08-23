#!/usr/bin/env bash
# Publish docs/wiki/* to GitHub Wiki (requires wiki already initialized once on github.com).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="https://github.com/bluehive/my-makejail-lop.wiki.git"
git clone "$REPO" "$TMP/wiki" || {
  echo "Wiki clone failed. Open https://github.com/bluehive/my-makejail-lop/wiki and click 'Create the first page' once, then re-run." >&2
  exit 1
}
cp -f "$ROOT"/docs/wiki/*.md "$TMP/wiki/"
cd "$TMP/wiki"
git add -A
git diff --cached --quiet && echo "No wiki changes." && exit 0
git commit -m "docs(wiki): sync from docs/wiki"
git push origin HEAD
echo "Wiki updated: https://github.com/bluehive/my-makejail-lop/wiki"
