#!/usr/bin/env bash
# Deterministic gate for a production orb release. Run it before tagging.
#
# Usage: scripts/dev/release-preflight.sh X.Y.Z
#
# Checks, in order (every failure is reported; the script exits non-zero once):
#   1. on main, clean tree, in sync with origin
#   2. tag vX.Y.Z does not already exist (orb versions are immutable)
#   3. CHANGELOG.md has a dated `## [X.Y.Z]` section and link refs
#   4. every documented orb pin (README, wiki, src/examples) reads X.Y.Z
#   5. the latest main pipeline is green
#   6. make lint test validate verify-diagrams pass
set -euo pipefail

VERSION="${1:?usage: release-preflight.sh X.Y.Z}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "FAIL: '$VERSION' is not X.Y.Z" >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
status=0
fail() { echo "FAIL: $*" >&2; status=1; }
ok() { echo "ok:   $*"; }

[[ "$(git branch --show-current)" == "main" ]] || fail "not on main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is dirty"
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main"
if [[ $status -eq 0 ]]; then
    ok "on a clean main, in sync with origin"
fi

if git rev-parse --verify --quiet "refs/tags/v${VERSION}" >/dev/null ||
    git ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null 2>&1; then
    fail "tag v${VERSION} already exists — orb versions are immutable, bump the patch"
else
    ok "tag v${VERSION} is free"
fi

if grep -qE "^## \[${VERSION}\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md; then
    ok "CHANGELOG.md has a dated [${VERSION}] section"
else
    fail "CHANGELOG.md has no dated '## [${VERSION}] - YYYY-MM-DD' section"
fi
grep -q "^\[${VERSION}\]: " CHANGELOG.md || fail "CHANGELOG.md is missing the [${VERSION}] link reference"

stale="$(grep -rn "kevnm67/telegram-notify@[0-9]" README.md wiki src/examples |
    grep -v "@${VERSION}" || true)"
if [[ -n "$stale" ]]; then
    fail "orb pins still point at another version:"
    printf '  %s\n' "$stale" >&2
else
    ok "every documented orb pin reads @${VERSION}"
fi

if command -v gh >/dev/null; then
    sha="$(git rev-parse origin/main)"
    state="$(gh api "repos/kevnm67/telegram-notify/commits/${sha}/status" -q .state 2>/dev/null || echo unknown)"
    if [[ "$state" == "success" ]]; then
        ok "main pipeline is green"
    else
        fail "main commit status is '${state}', not success"
    fi
fi

make lint test validate verify-diagrams >/dev/null || fail "make lint test validate verify-diagrams failed — rerun it directly"
if [[ $status -eq 0 ]]; then
    ok "local gates pass"
fi

if [[ $status -eq 0 ]]; then
    echo
    echo "Preflight clean. Release with:"
    echo "  git tag v${VERSION} && git push origin v${VERSION}"
fi
exit $status
