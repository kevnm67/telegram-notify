#!/usr/bin/env bash
# Used by the manually-triggered live_test workflow to exercise notify_failure
# against the real Telegram API with realistic multi-line error output.
set -euo pipefail
echo "compiling widgets..."
echo "linking <core> & <ui>"
printf '\033[31merror:\033[0m widget.c:42: undefined reference to `frobnicate'"'"'\n'
echo "make: *** [all] Error 1"
exit 1
