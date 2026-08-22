#!/usr/bin/env bash
# Integration helper: run notify.sh in failure mode against a stubbed
# CircleCI v1.1 API so the full error-output path is exercised without
# actually failing the CI job. Expects the mock Telegram server on :8089.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STUB_DIR="$(mktemp -d)"
trap 'kill "${STUB_PID:-}" 2>/dev/null || true; rm -rf "$STUB_DIR"' EXIT

# Static files served as the CircleCI API: build payload + step output.
mkdir -p "${STUB_DIR}/project/github/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
cat >"${STUB_DIR}/project/github/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}/${CIRCLE_BUILD_NUM}" <<JSON
{"steps":[{"actions":[{"failed":true,"status":"failed","output_url":"http://127.0.0.1:8090/step-output.json"}]}]}
JSON
cat >"${STUB_DIR}/step-output.json" <<'JSON'
[{"message":"compiling...\nerror: <simulated> build error\nmake: *** [all] Error 1\n"}]
JSON

(cd "$STUB_DIR" && python3 -m http.server 8090 --bind 127.0.0.1 >/dev/null 2>&1) &
STUB_PID=$!
timeout 30 bash -c 'until curl -s -o /dev/null http://127.0.0.1:8090/; do sleep 1; done'

CIRCLE_TOKEN="stub-token" \
    TELEGRAM_NOTIFY_EVENT=failure \
    TELEGRAM_NOTIFY_CIRCLECI_API_BASE="http://127.0.0.1:8090" \
    TELEGRAM_NOTIFY_API_BASE="http://127.0.0.1:8089" \
    TELEGRAM_NOTIFY_FAIL_ON_ERROR=true \
    TELEGRAM_NOTIFY_MAX_LINES=3 \
    bash "${REPO_ROOT}/src/scripts/notify.sh"
