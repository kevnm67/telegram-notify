#!/usr/bin/env bash
# Runs `when: on_fail` ahead of an `event: always` notification so the
# final `when: always` step can tell whether the job actually failed.
set -euo pipefail
touch "${TMPDIR:-/tmp}/telegram_notify_job_failed"
echo "[telegram-notify] recorded job failure"
