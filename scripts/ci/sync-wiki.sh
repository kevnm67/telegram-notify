#!/usr/bin/env bash
# Push wiki/*.md plus rendered architecture diagrams to the GitHub wiki repo.
# Images are committed into the wiki repo itself (flat) so pages render
# regardless of repository visibility.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_SLUG="${REPO_SLUG:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
WIKI_DIR="${REPO_ROOT}/.wiki-tmp"
WIKI_URL="https://github.com/${REPO_SLUG}.wiki.git"
# --token-auth: clone/push with GH_TOKEN (GitHub Actions) instead of local credentials.
if [[ "${1:-}" == "--token-auth" ]]; then
    WIKI_URL="https://x-access-token:${GH_TOKEN:?GH_TOKEN required}@github.com/${REPO_SLUG}.wiki.git"
fi

rm -rf "$WIKI_DIR"
if ! git clone --quiet "$WIKI_URL" "$WIKI_DIR"; then
    echo "wiki repo not initialised yet — create the first page in the GitHub UI" >&2
    exit 0
fi
cp "${REPO_ROOT}"/wiki/*.md "$WIKI_DIR/"
cp "${REPO_ROOT}"/docs/architecture/*.svg "${REPO_ROOT}"/docs/architecture/*.png "$WIKI_DIR/" 2>/dev/null || true

cd "$WIKI_DIR"
if [[ -z "$(git config user.email)" ]]; then
    git config user.email "ci@github.com"
    git config user.name "GitHub Actions"
fi
git add -A
if git diff --cached --quiet; then
    echo "wiki already up to date"
else
    git commit --quiet -m "docs: sync wiki from main"
    git push --quiet
    echo "wiki updated: https://github.com/${REPO_SLUG}/wiki"
fi
