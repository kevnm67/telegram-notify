#!/usr/bin/env bash
# Integration helper: run notify.sh in failure mode against the stubbed
# CircleCI / Anthropic APIs (scripts/ci/stub-circleci-api.sh) so the full
# error-output + template paths run without failing the CI job.
# Usage: simulate-failure-notification.sh [template] [extra VAR=value ...]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="${1:-basic}"
shift || true

timeout 30 bash -c 'until curl -s -o /dev/null http://127.0.0.1:8090/; do sleep 1; done'
timeout 30 bash -c 'until curl -s -o /dev/null http://127.0.0.1:8091/; do sleep 1; done'

env CIRCLE_TOKEN="stub-token" \
    ANTHROPIC_API_KEY="stub-key" \
    TELEGRAM_NOTIFY_EVENT=failure \
    TELEGRAM_NOTIFY_TEMPLATE="$TEMPLATE" \
    TELEGRAM_NOTIFY_CIRCLECI_API_BASE="http://127.0.0.1:8090/api/v1.1" \
    TELEGRAM_NOTIFY_CIRCLECI_API_V2_BASE="http://127.0.0.1:8090/api/v2" \
    TELEGRAM_NOTIFY_ANTHROPIC_API_BASE="http://127.0.0.1:8091" \
    TELEGRAM_NOTIFY_API_BASE="http://127.0.0.1:8089" \
    TELEGRAM_NOTIFY_FAIL_ON_ERROR=true \
    TELEGRAM_NOTIFY_MAX_LINES=3 \
    "$@" \
    bash "${REPO_ROOT}/src/scripts/notify.sh"
