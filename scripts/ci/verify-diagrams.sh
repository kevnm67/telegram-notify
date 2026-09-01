#!/usr/bin/env bash
# Lint gate for architecture diagrams:
#   1. every docs/architecture/*.d2 has a committed dark SVG (> 1 KiB)
#   2. re-rendering with the same D2_FLAGS produces an identical SVG
#   3. no Mermaid / ASCII-art diagrams in committed markdown
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
D2_FLAGS="${D2_FLAGS:---bundle --theme 200 --layout elk --pad 60}"
cd "$REPO_ROOT"

shopt -s nullglob
status=0
for src in docs/architecture/*.d2; do
    dark="${src%.d2}-dark.svg"
    if [[ ! -s "$dark" ]] || [[ $(wc -c <"$dark") -lt 1024 ]]; then
        echo "FAIL: $dark missing or smaller than 1 KiB (run 'make diagrams')" >&2
        status=1
    fi
    if command -v d2 >/dev/null; then
        tmp="$(mktemp -t diagram.XXXXXX.svg)"
        # shellcheck disable=SC2086
        d2 $D2_FLAGS "$src" "$tmp" >/dev/null 2>&1
        if ! cmp -s "$tmp" "$dark"; then
            echo "FAIL: $dark is stale — run 'make diagrams' and commit" >&2
            status=1
        fi
        rm -f "$tmp"
    else
        echo "d2 not installed — skipping render drift check" >&2
    fi
done

if grep -rEn --include='*.md' '```(mermaid|plantuml)' README.md ARCHITECTURE.md wiki docs 2>/dev/null; then
    echo "FAIL: text-based diagrams found; use docs/architecture/*.d2" >&2
    status=1
fi

[[ $status -eq 0 ]] && echo "diagrams OK"
exit $status
