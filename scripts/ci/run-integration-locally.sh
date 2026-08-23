#!/usr/bin/env bash
# Run the same template checks as the CI integration jobs on a developer machine.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
export CIRCLE_PROJECT_USERNAME="${CIRCLE_PROJECT_USERNAME:-kevnm67}" CIRCLE_PROJECT_REPONAME="${CIRCLE_PROJECT_REPONAME:-demo}"
export CIRCLE_BUILD_NUM=7 CIRCLE_JOB=integration_test_templates CIRCLE_BUILD_URL=https://circleci.com/gh/demo/7
export CIRCLE_WORKFLOW_ID=wf-local CIRCLE_BRANCH=main CIRCLE_SHA1=abcdef1234567 CIRCLE_USERNAME=dev
export TELEGRAM_BOT_TOKEN="000:local" TELEGRAM_CHAT_ID="1" MOCK_TELEGRAM_LOG="$WORK/mock.jsonl" STUB_ROOT="$WORK/stub"
cleanup() {
    pkill -f "mock-telegram-server.py" 2>/dev/null || true
    pkill -f "server.py $WORK/stub" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

python3 "$REPO_ROOT/scripts/ci/mock-telegram-server.py" >/dev/null 2>&1 &
"$REPO_ROOT/scripts/ci/stub-circleci-api.sh" >/dev/null 2>&1 &
sleep 2
cd "$REPO_ROOT"
./scripts/ci/simulate-failure-notification.sh basic TELEGRAM_NOTIFY_ATTACH_LOG=true >/dev/null 2>&1
./scripts/ci/assert-integration-templates.sh basic | tail -1
for t in test_summary insights ai_summary; do
    ./scripts/ci/simulate-failure-notification.sh "$t" >/dev/null 2>&1
    printf '%s: ' "$t"
    ./scripts/ci/assert-integration-templates.sh "$t" | tail -1
done
TELEGRAM_NOTIFY_EVENT=success TELEGRAM_NOTIFY_TEMPLATE=custom TELEGRAM_NOTIFY_BUTTONS=false \
    TELEGRAM_NOTIFY_CUSTOM_BODY='<b>{{CIRCLE_JOB}}</b> on {{CIRCLE_BRANCH}} {{NOT_SET_VAR}}' \
    TELEGRAM_NOTIFY_API_BASE=http://127.0.0.1:8089 bash src/scripts/notify.sh >/dev/null 2>&1
./scripts/ci/assert-integration-templates.sh custom | tail -1
TELEGRAM_NOTIFY_EVENT=success TELEGRAM_NOTIFY_BRANCH_PATTERN='never-.*' \
    TELEGRAM_NOTIFY_API_BASE=http://127.0.0.1:8089 bash src/scripts/notify.sh >/dev/null 2>&1
printf 'filtered: '
./scripts/ci/assert-integration-templates.sh filtered | tail -1
echo "integration: all templates OK"
