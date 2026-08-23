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
        TELEGRAM_NOTIFY_TEMPLATE TELEGRAM_NOTIFY_BUTTONS TELEGRAM_NOTIFY_INCLUDE_DURATION \
        TELEGRAM_NOTIFY_BRANCH_PATTERN TELEGRAM_NOTIFY_TAG_PATTERN TELEGRAM_NOTIFY_INVERT_MATCH \
        TELEGRAM_NOTIFY_ATTACH_LOG TELEGRAM_NOTIFY_CUSTOM_BODY TELEGRAM_NOTIFY_AI_MODEL \
        TELEGRAM_NOTIFY_INSIGHTS_WINDOW TELEGRAM_NOTIFY_WORKFLOW_NAME TELEGRAM_NOTIFY_MAX_FAILED_TESTS \
        ANTHROPIC_API_KEY CIRCLE_TAG CIRCLE_PULL_REQUEST CIRCLE_PR_NUMBER CIRCLE_REPOSITORY_URL \
        MOCK_HTTP_CODE MOCK_TELEGRAM_BODY MOCK_CURL_EXIT MOCK_CIRCLE_BUILD_JSON MOCK_STEP_OUTPUT \
        MOCK_TESTS_JSON MOCK_JOB_JSON MOCK_WORKFLOW_JSON MOCK_FLAKY_JSON MOCK_INSIGHTS_JSON \
        MOCK_ANTHROPIC_BODY MOCK_ANTHROPIC_HTTP_CODE MOCK_TELEGRAM_DOC_BODY MOCK_DOC_HTTP_CODE
    rm -f "${TMPDIR}/telegram_notify_job_failed" "${TMPDIR}/telegram_notify_failed_step.log"

    export TELEGRAM_NOTIFY_NO_MAIN=1
    # shellcheck source=../../src/scripts/notify.sh
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/src/scripts/notify.sh"
    # notify.sh runs `set +e` for its failure-safe contract; bats relies on
    # errexit to detect failed assertions, so restore it after sourcing.
    set -eE
}

# Extract the "text=" form field of the last sendMessage call from the mock log.
last_sent_text() {
    awk 'BEGIN { RS = "--data-urlencode text=" }
         NR > 1 { i = index($0, " --data-urlencode parse_mode=HTML"); last = (i ? substr($0, 1, i - 1) : $0) }
         END { printf "%s", last }' "$MOCK_CURL_LOG"
}

# Skip a test when neither jq nor python3 is available (feature needs one of them).
require_json_tool() {
    command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || skip "needs jq or python3"
}

run_script() {
    run env -u TELEGRAM_NOTIFY_NO_MAIN bash "${REPO_ROOT}/src/scripts/notify.sh"
}
