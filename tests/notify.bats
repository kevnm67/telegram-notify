#!/usr/bin/env bats
# Unit tests for src/scripts/notify.sh — run with `make test`.

load test_helper/common

setup() {
    common_setup
}

# --- helpers -----------------------------------------------------------------

@test "tn_html_escape escapes &, < and >" {
    result="$(tn_html_escape 'a & b <c> "d"')"
    [ "$result" = 'a &amp; b &lt;c&gt; "d"' ]
}

@test "tn_truncate leaves short text untouched" {
    result="$(tn_truncate "hello" 10)"
    [ "$result" = "hello" ]
}

@test "tn_truncate cuts long text and appends an ellipsis" {
    result="$(tn_truncate "abcdefghij" 5)"
    [ "$result" = "abcd…" ]
}

@test "tn_strip_ansi removes colour codes" {
    result="$(printf 'ok \033[31mred\033[0m done' | tn_strip_ansi)"
    [ "$result" = "ok red done" ]
}

# --- status resolution -------------------------------------------------------

@test "tn_resolve_status honours explicit failure/success events" {
    TELEGRAM_NOTIFY_EVENT=failure
    [ "$(tn_resolve_status)" = "failure" ]
    TELEGRAM_NOTIFY_EVENT=success
    [ "$(tn_resolve_status)" = "success" ]
}

@test "tn_resolve_status with event=always reads the failure marker" {
    TELEGRAM_NOTIFY_EVENT=always
    [ "$(tn_resolve_status)" = "success" ]
    touch "${TMPDIR}/telegram_notify_job_failed"
    [ "$(tn_resolve_status)" = "failure" ]
}

@test "tn_resolve_status treats unknown events as failure" {
    TELEGRAM_NOTIFY_EVENT=bogus
    [ "$(tn_resolve_status 2>/dev/null)" = "failure" ]
}

@test "record_failure.sh creates the marker file" {
    run bash "${REPO_ROOT}/src/scripts/record_failure.sh"
    [ "$status" -eq 0 ]
    [ -f "${TMPDIR}/telegram_notify_job_failed" ]
}

# --- error output fetch ------------------------------------------------------

@test "tn_fetch_error_output is a no-op without CIRCLE_TOKEN" {
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ -z "$result" ]
    ! grep -q 'api/v1.1' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output is a no-op without CIRCLE_BUILD_NUM" {
    export CIRCLE_TOKEN=abc
    unset CIRCLE_BUILD_NUM
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ -z "$result" ]
    ! grep -q 'api/v1.1' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output picks the failed action and returns its last lines" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":false,"output_url":"https://x/step-output/ok"}]},{"actions":[{"failed":true,"status":"failed","output_url":"https:\/\/x\/step-output\/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"line1\nline2\n\u001b[31mline3\u001b[0m\n"}]'
    TELEGRAM_NOTIFY_MAX_LINES=2
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ "$result" = $'line2\nline3' ]
    grep -q 'Circle-Token: abc' "$MOCK_CURL_LOG"
    grep -q 'https://x/step-output/bad' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output uses the configured vcs type and API base" {
    export CIRCLE_TOKEN=abc
    export TELEGRAM_NOTIFY_VCS_TYPE=bitbucket
    export TELEGRAM_NOTIFY_CIRCLECI_API_BASE=http://localhost:1/api/v1.1
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[]}'
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ -z "$result" ]
    grep -q 'http://localhost:1/api/v1.1/project/bitbucket/kevnm67/telegram-notify/42' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output tolerates API failures" {
    export CIRCLE_TOKEN=abc
    export MOCK_CURL_EXIT=7
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ -z "$result" ]
}

@test "tn_fetch_error_output tolerates step download failures" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/unexpected"}]}]}'
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ -z "$result" ]
}

@test "tn_find_failed_output_url normalises escaped slashes" {
    result="$(tn_find_failed_output_url <<<'{"steps":[{"actions":[{"failed":true,"output_url":"https:\/\/a\/2"}]}]}')"
    [ "$result" = "https://a/2" ]
}

@test "tn_find_failed_output_url returns nothing when no action failed" {
    result="$(tn_find_failed_output_url <<<'{"steps":[{"actions":[{"failed":false,"output_url":"https://a/1"}]}]}')"
    [ -z "$result" ]
}

@test "tn_extract_messages concatenates message fields" {
    result="$(tn_extract_messages <<<'[{"message":"a\n"},{"message":"b"}]')"
    [ "$result" = $'a\nb' ]
}

# --- message rendering -------------------------------------------------------

@test "failure message contains headline, escaped fields and links" {
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *"🔴 <b>CI Failure</b>"* ]]
    [[ "$msg" == *"<b>Repository:</b> telegram-notify"* ]]
    [[ "$msg" == *"feat/&lt;scary&gt;&amp;branch"* ]]
    [[ "$msg" == *"<b>Job:</b> unit_tests"* ]]
    [[ "$msg" == *"<code>01234567</code>"* ]]
    [[ "$msg" == *"<b>Triggered by:</b> kevin"* ]]
    [[ "$msg" == *'<a href="https://circleci.com/gh/kevnm67/telegram-notify/42">View Build</a>'* ]]
    [[ "$msg" == *'https://app.circleci.com/pipelines/workflows/wf-123'* ]]
    [[ "$msg" != *"Error Output"* ]]
}

@test "success message uses the success headline" {
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"✅ <b>CI Success</b>"* ]]
    [[ "$msg" != *"🔴"* ]]
}

@test "error output is HTML-escaped inside a <pre> block and truncated" {
    long="$(head -c 5000 /dev/zero | tr '\0' 'x')"
    msg="$(tn_build_message failure "boom <tag> & ${long}")"
    [[ "$msg" == *"❌ <b>Error Output:</b>"* ]]
    [[ "$msg" == *"<pre>boom &lt;tag&gt; &amp; xxxx"* ]]
    [[ "$msg" == *"…</pre>"* ]]
    [ "${#msg}" -lt 4096 ]
}

@test "include_links=false omits links" {
    TELEGRAM_NOTIFY_INCLUDE_LINKS=false
    msg="$(tn_build_message failure "")"
    [[ "$msg" != *"View Build"* ]]
}

@test "custom message and mentions are appended verbatim" {
    TELEGRAM_NOTIFY_CUSTOM_MESSAGE='<i>deploy gate</i>'
    TELEGRAM_NOTIFY_MENTIONS='@alice @bob'
    msg="$(tn_build_message failure "")"
    [[ "$msg" == $'🔴 <b>CI Failure</b>\n<i>deploy gate</i>\n\n📁'* ]]
    [[ "$msg" == *$'\n\n@alice @bob' ]]
}

@test "branch falls back to CIRCLE_TAG and unknown" {
    unset CIRCLE_BRANCH
    export CIRCLE_TAG=v1.2.3
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"<b>Branch:</b> v1.2.3"* ]]
    unset CIRCLE_TAG CIRCLE_USERNAME
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"<b>Branch:</b> unknown"* ]]
    [[ "$msg" != *"Triggered by"* ]]
}

# --- sending -----------------------------------------------------------------

@test "tn_send_message fails without a bot token" {
    unset TELEGRAM_BOT_TOKEN
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TELEGRAM_BOT_TOKEN is not set"* ]]
    [ ! -s "$MOCK_CURL_LOG" ]
}

@test "tn_send_message reads the token from a custom env var name" {
    unset TELEGRAM_BOT_TOKEN
    export OTHER_TOKEN="999:other"
    TELEGRAM_NOTIFY_BOT_TOKEN_VAR=OTHER_TOKEN
    run tn_send_message "hi"
    [ "$status" -eq 0 ]
    grep -q 'https://api.telegram.org/bot999:other/sendMessage' "$MOCK_CURL_LOG"
}

@test "tn_send_message fails without a chat id" {
    TELEGRAM_NOTIFY_CHAT_ID=""
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"chat_id is empty"* ]]
}

@test "tn_send_message falls back to TELEGRAM_CHAT_ID" {
    TELEGRAM_NOTIFY_CHAT_ID=""
    export TELEGRAM_CHAT_ID="777"
    run tn_send_message "hi"
    [ "$status" -eq 0 ]
    grep -q -- '--data-urlencode chat_id=777' "$MOCK_CURL_LOG"
}

@test "tn_send_message posts url-encoded form fields" {
    TELEGRAM_NOTIFY_SILENT=true
    TELEGRAM_NOTIFY_THREAD_ID=55
    TELEGRAM_NOTIFY_API_BASE=http://localhost:8089
    run tn_send_message $'multi\nline "text"'
    [ "$status" -eq 0 ]
    log="$(cat "$MOCK_CURL_LOG")"
    [[ "$log" == *"http://localhost:8089/bot123:test-token/sendMessage"* ]]
    [[ "$log" == *"--data-urlencode chat_id=-100999"* ]]
    [[ "$log" == *$'--data-urlencode text=multi\nline "text"'* ]]
    [[ "$log" == *"--data-urlencode parse_mode=HTML"* ]]
    [[ "$log" == *"--data-urlencode disable_web_page_preview=true"* ]]
    [[ "$log" == *"--data-urlencode disable_notification=true"* ]]
    [[ "$log" == *"--data-urlencode message_thread_id=55"* ]]
}

@test "tn_send_message omits optional fields by default" {
    run tn_send_message "hi"
    ! grep -q 'disable_notification' "$MOCK_CURL_LOG"
    ! grep -q 'message_thread_id' "$MOCK_CURL_LOG"
}

@test "tn_send_message reports non-200 responses" {
    export MOCK_HTTP_CODE=400
    export MOCK_TELEGRAM_BODY='{"ok":false,"description":"Bad Request: chat not found"}'
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"http=400"* ]]
    [[ "$output" == *"chat not found"* ]]
}

@test "tn_send_message reports ok:false with HTTP 200" {
    export MOCK_TELEGRAM_BODY='{"ok":false}'
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
}

@test "tn_send_message reports curl transport errors" {
    export MOCK_CURL_EXIT=6
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"curl rc=6"* ]]
}

@test "dry run prints the message and skips the API" {
    TELEGRAM_NOTIFY_DRY_RUN=true
    run tn_send_message "hello <b>there</b>"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry run"* ]]
    [[ "$output" == *"hello <b>there</b>"* ]]
    [ ! -s "$MOCK_CURL_LOG" ]
}

# --- end-to-end through main -------------------------------------------------

@test "main sends a failure notification and exits 0" {
    run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"Notification sent (failure)"* ]]
    [[ "$(last_sent_text)" == *"🔴 <b>CI Failure</b>"* ]]
}

@test "main with event=success sends the success message" {
    export TELEGRAM_NOTIFY_EVENT=success
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"✅ <b>CI Success</b>"* ]]
}

@test "main with event=always reports failure when the marker exists" {
    export TELEGRAM_NOTIFY_EVENT=always
    touch "${TMPDIR}/telegram_notify_job_failed"
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"🔴 <b>CI Failure</b>"* ]]
}

@test "main includes fetched error output on failure" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/step-output/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"make: *** [build] Error 1\n"}]'
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"<pre>make: *** [build] Error 1</pre>"* ]]
}

@test "main never fails the build on delivery errors by default" {
    export MOCK_HTTP_CODE=500
    run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail_on_error is false"* ]]
}

@test "main exits 1 on delivery errors when fail_on_error=true" {
    export MOCK_HTTP_CODE=500
    export TELEGRAM_NOTIFY_FAIL_ON_ERROR=true
    run_script
    [ "$status" -eq 1 ]
}

@test "main truncates the final message to Telegram's limit" {
    TELEGRAM_NOTIFY_CUSTOM_MESSAGE="$(head -c 6000 /dev/zero | tr '\0' 'y')"
    export TELEGRAM_NOTIFY_CUSTOM_MESSAGE
    run_script
    [ "$status" -eq 0 ]
    text="$(last_sent_text)"
    [ "${#text}" -le 4096 ]
}
