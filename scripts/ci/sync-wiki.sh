#!/usr/bin/env bash
# Push wiki/*.md plus rendered architecture diagrams to the GitHub wiki repo.
# Images are committed into the wiki repo itself (flat) so pages render
# regardless of repository visibility.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_SLUG="${REPO_SLUG:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
WIKI_DIR="${REPO_ROOT}/.wiki-tmp"

rm -rf "$WIKI_DIR"
git clone --quiet "https://github.com/${REPO_SLUG}.wiki.git" "$WIKI_DIR"
cp "${REPO_ROOT}"/wiki/*.md "$WIKI_DIR/"
cp "${REPO_ROOT}"/docs/architecture/*.svg "${REPO_ROOT}"/docs/architecture/*.png "$WIKI_DIR/" 2>/dev/null || true

cd "$WIKI_DIR"
git add -A
if git diff --cached --quiet; then
    echo "wiki already up to date"
else
    git commit --quiet -m "docs: sync wiki from main"
    git push --quiet
    echo "wiki updated: https://github.com/${REPO_SLUG}/wiki"
fi
