# Shared setup for the bats suite.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

common_setup() {
    export PATH="${REPO_ROOT}/tests/test_helper/mock_bin:${PATH}"
    export MOCK_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
    : >"$MOCK_CURL_LOG"
    export TMPDIR="${BATS_TEST_TMPDIR}"

    # Deterministic CircleCI environment.
    export CIRCLE_PROJECT_USERNAME="kevnm67"
    export CIRCLE_PROJECT_REPONAME="telegram-notify"
    export CIRCLE_BRANCH="feat/<scary>&branch"
    export CIRCLE_JOB="unit_tests"
    export CIRCLE_BUILD_NUM="42"
    export CIRCLE_BUILD_URL="https://circleci.com/gh/kevnm67/telegram-notify/42"
    export CIRCLE_WORKFLOW_ID="wf-123"
    export CIRCLE_SHA1="0123456789abcdef"
    export CIRCLE_USERNAME="kevin"

    export TELEGRAM_BOT_TOKEN="123:test-token"
    export TELEGRAM_NOTIFY_CHAT_ID="-100999"
    export TELEGRAM_NOTIFY_EVENT="failure"
    unset CIRCLE_TOKEN TELEGRAM_CHAT_ID TELEGRAM_NOTIFY_CUSTOM_MESSAGE \
        TELEGRAM_NOTIFY_MENTIONS TELEGRAM_NOTIFY_THREAD_ID TELEGRAM_NOTIFY_SILENT \
        TELEGRAM_NOTIFY_DRY_RUN TELEGRAM_NOTIFY_FAIL_ON_ERROR TELEGRAM_NOTIFY_INCLUDE_LINKS \
        TELEGRAM_NOTIFY_VCS_TYPE TELEGRAM_NOTIFY_CIRCLECI_API_BASE TELEGRAM_NOTIFY_API_BASE \
        TELEGRAM_NOTIFY_BOT_TOKEN_VAR TELEGRAM_NOTIFY_MAX_LINES \
        MOCK_HTTP_CODE MOCK_TELEGRAM_BODY MOCK_CURL_EXIT MOCK_CIRCLE_BUILD_JSON MOCK_STEP_OUTPUT
    rm -f "${TMPDIR}/telegram_notify_job_failed"

    export TELEGRAM_NOTIFY_NO_MAIN=1
    # shellcheck source=../../src/scripts/notify.sh
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/src/scripts/notify.sh"
}

# Extract the "text=" form field of the last sendMessage call from the mock log.
last_sent_text() {
    python3 - "$MOCK_CURL_LOG" <<'PY'
import sys
log = open(sys.argv[1], encoding="utf-8").read()
start = log.rfind("--data-urlencode text=")
if start < 0:
    sys.exit(0)
start += len("--data-urlencode text=")
end = log.find(" --data-urlencode parse_mode=HTML", start)
print(log[start:end if end >= 0 else None], end="")
PY
}

run_script() {
    run env -u TELEGRAM_NOTIFY_NO_MAIN bash "${REPO_ROOT}/src/scripts/notify.sh"
}
