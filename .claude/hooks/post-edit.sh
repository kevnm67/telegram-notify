#!/usr/bin/env bash
# post-edit.sh — fast feedback after edits (never blocks; findings go to stderr).
#   *.sh / mock curl / *.bash  -> shellcheck the one file
#   src/scripts/* or tests/*   -> run the bats suite (~3 s)
#   src/commands/* or src/@orb -> circleci orb pack + validate
#   .circleci/*.yml            -> yamllint
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILE="${TOOL_INPUT_FILE_PATH:-}"
case "$FILE" in "$REPO_ROOT"/*) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0
report() { printf '[post-edit] %s\n' "$1" >&2; }

case "$FILE" in
*.sh | *.bash | */mock_bin/*)
    if command -v shellcheck >/dev/null; then
        out=$(shellcheck -x "$FILE" 2>&1) || { report "shellcheck: $(basename "$FILE")"; printf '%s\n' "$out" | head -30 >&2; }
    fi
    ;;
esac
case "$FILE" in
"$REPO_ROOT"/src/scripts/* | "$REPO_ROOT"/tests/*)
    if command -v bats >/dev/null; then
        out=$(cd "$REPO_ROOT" && PATH="/opt/homebrew/bin:$PATH" bats tests/ 2>&1 | grep -E '^not ok|^1\.\.') || true
        printf '%s\n' "$out" | grep -q '^not ok' && { report "bats failures:"; printf '%s\n' "$out" >&2; }
    fi
    ;;
"$REPO_ROOT"/src/commands/* | "$REPO_ROOT"/src/@orb.yml | "$REPO_ROOT"/src/examples/*)
    if command -v circleci >/dev/null; then
        (cd "$REPO_ROOT" && circleci orb pack src >/tmp/telegram-notify-orb.yml 2>&1 && circleci orb validate /tmp/telegram-notify-orb.yml >/dev/null 2>&1) ||
            report "orb pack/validate FAILED for $(basename "$FILE") — run 'make validate'"
    fi
    ;;
"$REPO_ROOT"/.circleci/*.yml)
    command -v yamllint >/dev/null && { out=$(yamllint --strict "$FILE" 2>&1) || { report "yamllint:"; printf '%s\n' "$out" >&2; }; }
    ;;
esac
exit 0
