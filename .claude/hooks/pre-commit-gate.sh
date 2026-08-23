#!/usr/bin/env bash
# pre-commit-gate.sh — before `git commit` / `git push`, require lint + tests to pass.
# Exit 2 blocks the tool call with the message on stderr.
set -uo pipefail
cmd="${TOOL_INPUT_COMMAND:-}"
case "$cmd" in
*"git commit"* | *"git push"*) ;;
*) exit 0 ;;
esac
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 0
fail=""
command -v shellcheck >/dev/null && ! shellcheck -x src/scripts/*.sh scripts/ci/*.sh tests/test_helper/mock_bin/curl tests/test_helper/common.bash >/dev/null 2>&1 && fail+="shellcheck "
command -v bats >/dev/null && PATH="/opt/homebrew/bin:$PATH" bats tests/ 2>&1 | grep -q '^not ok' && fail+="bats "
command -v circleci >/dev/null && ! { circleci orb pack src >/tmp/telegram-notify-orb.yml 2>/dev/null && circleci orb validate /tmp/telegram-notify-orb.yml >/dev/null 2>&1; } && fail+="orb-validate "
if [ -n "$fail" ]; then
    echo "Blocked: ${fail}failed — run 'make lint test' and fix before committing." >&2
    exit 2
fi
exit 0
