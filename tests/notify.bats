#!/usr/bin/env bats
# Unit tests for src/scripts/notify.sh — run with `make test`.
#
# common_setup() sources the script (TELEGRAM_NOTIFY_NO_MAIN=1), shadows curl
# with tests/test_helper/mock_bin/curl and restores errexit so every bare
# `[[ ... ]]` assertion below is enforced.

load test_helper/common

setup() {
    common_setup
}

# --- helpers -----------------------------------------------------------------

@test "tn_html_escape escapes &, < and >" {
    result="$(tn_html_escape 'a & b <c> "d"')"
    [ "$result" = 'a &amp; b &lt;c&gt; "d"' ]
}

@test "tn_json_escape escapes quotes, backslashes and control characters" {
    result="$(tn_json_escape $'he said "hi"\\ then\nnew\tline')"
    [ "$result" = 'he said \"hi\"\\ then\nnew\tline' ]
}

@test "tn_truncate leaves short text untouched and cuts long text" {
    [ "$(tn_truncate "hello" 10)" = "hello" ]
    [ "$(tn_truncate "abcdefghij" 5)" = "abcd…" ]
}

@test "tn_strip_ansi removes colour codes" {
    result="$(printf 'ok \033[31mred\033[0m done' | tn_strip_ansi)"
    [ "$result" = "ok red done" ]
}

@test "tn_format_duration_ms renders ms, s, m and h" {
    [ "$(tn_format_duration_ms 850)" = "850ms" ]
    [ "$(tn_format_duration_ms 12000)" = "12s" ]
    [ "$(tn_format_duration_ms 133000)" = "2m 13s" ]
    [ "$(tn_format_duration_ms 3725000)" = "1h 02m" ]
    [ -z "$(tn_format_duration_ms abc)" ]
}

@test "tn_is_true accepts true/1/yes and rejects everything else" {
    tn_is_true true
    tn_is_true 1
    tn_is_true yes
    ! tn_is_true false
    ! tn_is_true 0
    ! tn_is_true ""
}

@test "tn_json_get reads nested values with jq" {
    command -v jq >/dev/null || skip "jq not installed"
    [ "$(tn_json_get '.a.b' 'a.b' <<<'{"a":{"b":42}}')" = "42" ]
    [ -z "$(tn_json_get '.a.c' 'a.c' <<<'{"a":{"b":42}}')" ]
}

@test "tn_json_get grep fallback reads flat keys without jq or python3" {
    tn_has() { [[ "$1" == "jq" || "$1" == "python3" ]] && return 1; command -v "$1" >/dev/null 2>&1; }
    [ "$(tn_json_get '.duration' 'duration' <<<'{"name":"x","duration":133000,"ok":true}')" = "133000" ]
    [ "$(tn_json_get '.name' 'name' <<<'{"name":"build and test","duration":1}')" = "build and test" ]
    [ "$(tn_json_get '.result.message_id' 'result.message_id' <<<'{"ok":true,"result":{"message_id":4242}}')" = "4242" ]
    [ -z "$(tn_json_get '.missing' 'missing' <<<'{"a":1}')" ]
}

@test "tn_json_get falls back to python3 when jq is absent" {
    command -v python3 >/dev/null || skip "python3 not installed"
    tn_has() { [[ "$1" == "jq" ]] && return 1; command -v "$1" >/dev/null 2>&1; }
    [ "$(tn_json_get '.a.b' 'a.b' <<<'{"a":{"b":"x y"}}')" = "x y" ]
    [ "$(tn_json_get '.items.0.name' 'items.0.name' <<<'{"items":[{"name":"t1"}]}')" = "t1" ]
}

# --- URLs and links ----------------------------------------------------------

@test "tn_repo_web_url normalises ssh, https and falls back to org/repo" {
    CIRCLE_REPOSITORY_URL="git@github.com:kevnm67/telegram-notify.git"
    [ "$(tn_repo_web_url)" = "https://github.com/kevnm67/telegram-notify" ]
    CIRCLE_REPOSITORY_URL="https://github.com/kevnm67/telegram-notify.git"
    [ "$(tn_repo_web_url)" = "https://github.com/kevnm67/telegram-notify" ]
    CIRCLE_REPOSITORY_URL="ssh://git@bitbucket.org/team/repo.git"
    [ "$(tn_repo_web_url)" = "https://bitbucket.org/team/repo" ]
    unset CIRCLE_REPOSITORY_URL
    [ "$(tn_repo_web_url)" = "https://github.com/kevnm67/telegram-notify" ]
    TELEGRAM_NOTIFY_VCS_TYPE=bitbucket
    [ "$(tn_repo_web_url)" = "https://bitbucket.org/kevnm67/telegram-notify" ]
}

@test "commit and branch URLs follow the VCS conventions" {
    [ "$(tn_commit_url)" = "https://github.com/kevnm67/telegram-notify/commit/0123456789abcdef" ]
    [ "$(tn_branch_url)" = "https://github.com/kevnm67/telegram-notify/tree/feat/<scary>&branch" ]
    export CIRCLE_TAG=v1.2.3
    [ "$(tn_branch_url)" = "https://github.com/kevnm67/telegram-notify/releases/tag/v1.2.3" ]
    TELEGRAM_NOTIFY_VCS_TYPE=bitbucket
    [ "$(tn_commit_url)" = "https://bitbucket.org/kevnm67/telegram-notify/commits/0123456789abcdef" ]
    [ "$(tn_branch_url)" = "https://bitbucket.org/kevnm67/telegram-notify/src/v1.2.3" ]
}

@test "tn_link escapes label and href, and degrades to plain text" {
    [ "$(tn_link 'a<b' 'https://x/?a=1&b=2')" = '<a href="https://x/?a=1&amp;b=2">a&lt;b</a>' ]
    [ "$(tn_link 'a<b' '')" = 'a&lt;b' ]
}

# --- status resolution and filters -------------------------------------------

@test "tn_resolve_status honours explicit events and the always marker" {
    TELEGRAM_NOTIFY_EVENT=failure
    [ "$(tn_resolve_status)" = "failure" ]
    TELEGRAM_NOTIFY_EVENT=success
    [ "$(tn_resolve_status)" = "success" ]
    TELEGRAM_NOTIFY_EVENT=always
    [ "$(tn_resolve_status)" = "success" ]
    touch "${TMPDIR}/telegram_notify_job_failed"
    [ "$(tn_resolve_status)" = "failure" ]
    TELEGRAM_NOTIFY_EVENT=bogus
    [ "$(tn_resolve_status 2>/dev/null)" = "failure" ]
}

@test "record_failure.sh creates the marker file" {
    run bash "${REPO_ROOT}/src/scripts/record_failure.sh"
    [ "$status" -eq 0 ]
    [ -f "${TMPDIR}/telegram_notify_job_failed" ]
}

@test "tn_matches_any anchors comma-separated regexes" {
    tn_matches_any 'main,release/.*' 'main'
    tn_matches_any 'main, release/.*' 'release/1.2'
    ! tn_matches_any 'main' 'main-backup'
    ! tn_matches_any 'rel' 'release'
    ! tn_matches_any '' 'main'
}

@test "tn_should_send: no patterns always sends" {
    tn_should_send
}

@test "tn_should_send: branch_pattern gates branches" {
    TELEGRAM_NOTIFY_BRANCH_PATTERN='main,release/.*'
    run tn_should_send
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not match"* ]]
    export CIRCLE_BRANCH=release/2.0
    tn_should_send
}

@test "tn_should_send: invert_match flips the decision" {
    TELEGRAM_NOTIFY_BRANCH_PATTERN='feat/.*'
    TELEGRAM_NOTIFY_INVERT_MATCH=true
    run tn_should_send
    [ "$status" -eq 1 ]
    [[ "$output" == *"invert_match"* ]]
    export CIRCLE_BRANCH=main
    tn_should_send
}

@test "tn_should_send: tag builds use tag_pattern and ignore branch_pattern" {
    export CIRCLE_TAG=v1.0.0
    unset CIRCLE_BRANCH
    TELEGRAM_NOTIFY_BRANCH_PATTERN='main'
    TELEGRAM_NOTIFY_TAG_PATTERN='v[0-9]+\.[0-9]+\.[0-9]+'
    tn_should_send
    export CIRCLE_TAG=nightly
    run tn_should_send
    [ "$status" -eq 1 ]
}

@test "main skips silently when the branch does not match" {
    export TELEGRAM_NOTIFY_BRANCH_PATTERN='main'
    run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped: ref does not match"* ]]
    ! grep -q sendMessage "$MOCK_CURL_LOG"
}

# --- CircleCI API: error output ----------------------------------------------

@test "tn_fetch_error_output is a no-op without CIRCLE_TOKEN or CIRCLE_BUILD_NUM" {
    [ -z "$(tn_fetch_error_output 2>/dev/null)" ]
    export CIRCLE_TOKEN=abc
    unset CIRCLE_BUILD_NUM
    [ -z "$(tn_fetch_error_output 2>/dev/null)" ]
    ! grep -q 'api/v1.1' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output picks the failed action, strips ANSI and keeps max_lines" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":false,"output_url":"https://x/step-output/ok"}]},{"actions":[{"failed":true,"status":"failed","output_url":"https:\/\/x\/step-output\/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"line1\nline2\n\u001b[31mline3\u001b[0m\n"}]'
    TELEGRAM_NOTIFY_MAX_LINES=2
    result="$(tn_fetch_error_output 2>/dev/null)"
    [ "$result" = $'line2\nline3' ]
    grep -q 'Circle-Token: abc' "$MOCK_CURL_LOG"
    grep -q 'https://x/step-output/bad' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output stores the full log for attach_log" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/step-output/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"l1\nl2\nl3\n"}]'
    TELEGRAM_NOTIFY_MAX_LINES=1
    tn_fetch_error_output >/dev/null 2>&1
    [ -f "$TN_RAW_LOG_FILE" ]
    [ "$(cat "$TN_RAW_LOG_FILE")" = $'l1\nl2\nl3' ]
}

@test "tn_fetch_error_output uses the configured vcs type and API base" {
    export CIRCLE_TOKEN=abc
    export TELEGRAM_NOTIFY_VCS_TYPE=bitbucket
    export TELEGRAM_NOTIFY_CIRCLECI_API_BASE=http://localhost:1/api/v1.1
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[]}'
    [ -z "$(tn_fetch_error_output 2>/dev/null)" ]
    grep -q 'http://localhost:1/api/v1.1/project/bitbucket/kevnm67/telegram-notify/42' "$MOCK_CURL_LOG"
}

@test "tn_fetch_error_output tolerates API and download failures" {
    export CIRCLE_TOKEN=abc
    export MOCK_CURL_EXIT=7
    [ -z "$(tn_fetch_error_output 2>/dev/null)" ]
    unset MOCK_CURL_EXIT
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/unexpected"}]}]}'
    [ -z "$(tn_fetch_error_output 2>/dev/null)" ]
}

@test "tn_find_failed_output_url normalises escaped slashes and ignores passing actions" {
    [ "$(tn_find_failed_output_url <<<'{"steps":[{"actions":[{"failed":true,"output_url":"https:\/\/a\/2"}]}]}')" = "https://a/2" ]
    [ -z "$(tn_find_failed_output_url <<<'{"steps":[{"actions":[{"failed":false,"output_url":"https://a/1"}]}]}')" ]
}

@test "tn_extract_messages concatenates message fields without extra newlines" {
    [ "$(tn_extract_messages <<<'[{"message":"a\n"},{"message":"b"}]')" = $'a\nb' ]
}

@test "tn_fetch_job_duration_ms reads the v2 job endpoint" {
    export CIRCLE_TOKEN=abc
    [ "$(tn_fetch_job_duration_ms)" = "133000" ]
    grep -q 'api/v2/project/gh/kevnm67/telegram-notify/job/42' "$MOCK_CURL_LOG"
    unset CIRCLE_TOKEN
    [ -z "$(tn_fetch_job_duration_ms)" ]
}

# --- message rendering: basic template ---------------------------------------

@test "failure message links repository, branch and job and escapes values" {
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *"🔴 <b>CI Failure</b>"* ]]
    [[ "$msg" == *'<b>Repository:</b> <a href="https://github.com/kevnm67/telegram-notify">telegram-notify</a>'* ]]
    [[ "$msg" == *'tree/feat/&lt;scary&gt;&amp;branch">feat/&lt;scary&gt;&amp;branch</a>'* ]]
    [[ "$msg" == *'<b>Job:</b> <a href="https://circleci.com/gh/kevnm67/telegram-notify/42">unit_tests</a>'* ]]
    [[ "$msg" == *"<code>01234567</code>"* ]]
    [[ "$msg" == *"<b>Triggered by:</b> kevin"* ]]
    [[ "$msg" != *"Error Output"* ]]
    [[ "$msg" != *"View Build"* ]] # buttons carry the links by default
}

@test "text links appear only when buttons are disabled" {
    TELEGRAM_NOTIFY_BUTTONS=false
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *'<a href="https://circleci.com/gh/kevnm67/telegram-notify/42">View Build</a>'* ]]
    [[ "$msg" == *'https://app.circleci.com/pipelines/workflows/wf-123'* ]]
    TELEGRAM_NOTIFY_INCLUDE_LINKS=false
    msg="$(tn_build_message failure "")"
    [[ "$msg" != *"View Build"* ]]
}

@test "pull request and duration are shown when available" {
    export CIRCLE_PULL_REQUEST="https://github.com/kevnm67/telegram-notify/pull/12"
    TN_DURATION_MS=133000
    msg="$(tn_build_message success "")"
    [[ "$msg" == *'<a href="https://github.com/kevnm67/telegram-notify/pull/12">PR #12</a>'* ]]
    [[ "$msg" == *"⏱ <b>Duration:</b> 2m 13s"* ]]
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

@test "custom message and mentions are appended verbatim" {
    TELEGRAM_NOTIFY_CUSTOM_MESSAGE='<i>deploy gate</i>'
    TELEGRAM_NOTIFY_MENTIONS='@alice @bob'
    msg="$(tn_build_message failure "")"
    [[ "$msg" == $'🔴 <b>CI Failure</b>\n<i>deploy gate</i>\n\n📁'* ]]
    [[ "$msg" == *$'\n\n@alice @bob' ]]
}

@test "tag builds show a Tag line and unknown fallbacks work" {
    unset CIRCLE_BRANCH
    export CIRCLE_TAG=v1.2.3
    msg="$(tn_build_message success "")"
    [[ "$msg" == *'🏷 <b>Tag:</b> <a href="https://github.com/kevnm67/telegram-notify/releases/tag/v1.2.3">v1.2.3</a>'* ]]
    unset CIRCLE_TAG CIRCLE_USERNAME CIRCLE_PROJECT_USERNAME
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"<b>Branch:</b> unknown"* ]]
    [[ "$msg" != *"Triggered by"* ]]
}

@test "long custom message shrinks the error block so <pre> is never cut" {
    TELEGRAM_NOTIFY_CUSTOM_MESSAGE="$(head -c 2500 /dev/zero | tr '\0' 'c')"
    TELEGRAM_NOTIFY_MENTIONS="@a @b"
    long="$(head -c 5000 /dev/zero | tr '\0' 'x')"
    msg="$(tn_build_message failure "$long")"
    [ "${#msg}" -le 4096 ]
    [[ "$msg" == *"…</pre>"* ]]
    [[ "$msg" == *$'\n\n@a @b' ]]
}

@test "tn_inline_keyboard builds URL buttons and omits missing ones" {
    kb="$(tn_inline_keyboard)"
    [[ "$kb" == '{"inline_keyboard":[[{"text":"🔎 View build","url":"https://circleci.com/gh/kevnm67/telegram-notify/42"},{"text":"🧭 Workflow","url":"https://app.circleci.com/pipelines/workflows/wf-123"}]]}' ]]
    export CIRCLE_PULL_REQUEST="https://github.com/kevnm67/telegram-notify/pull/7"
    [[ "$(tn_inline_keyboard)" == *'"text":"🔀 Pull request","url":"https://github.com/kevnm67/telegram-notify/pull/7"'* ]]
    unset CIRCLE_BUILD_URL CIRCLE_WORKFLOW_ID CIRCLE_PULL_REQUEST
    [ -z "$(tn_inline_keyboard)" ]
}

# --- templates ---------------------------------------------------------------

@test "test_summary renders counts, runtime and failed tests" {
    require_json_tool
    export CIRCLE_TOKEN=abc
    export MOCK_TESTS_JSON='{"items":[
      {"classname":"suite.A","name":"passes","result":"success","run_time":0.5,"message":""},
      {"classname":"suite.B","name":"fails <badly>","result":"failure","run_time":1.25,"message":"expected 1\ngot 2"},
      {"classname":"suite.C","name":"skipped one","result":"skipped","run_time":0,"message":""}]}'
    TELEGRAM_NOTIFY_TEMPLATE=test_summary
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *"🧪 <b>Tests:</b> ❌ 1 passed · 1 failed · 1 skipped · 3 total · ⏱ 1.8s"* ]]
    [[ "$msg" == *"• <code>suite.B › fails &lt;badly&gt;</code> — expected 1"* ]]
    [[ "$msg" != *"got 2"* ]]
    grep -q 'api/v2/project/gh/kevnm67/telegram-notify/42/tests' "$MOCK_CURL_LOG"
}

@test "test_summary caps the failed list and reports the remainder" {
    require_json_tool
    export CIRCLE_TOKEN=abc
    items=""
    for i in 1 2 3 4 5 6 7; do items+="{\"classname\":\"c\",\"name\":\"t$i\",\"result\":\"failure\",\"run_time\":1,\"message\":\"\"},"; done
    export MOCK_TESTS_JSON="{\"items\":[${items%,}]}"
    TELEGRAM_NOTIFY_TEMPLATE=test_summary
    TELEGRAM_NOTIFY_MAX_FAILED_TESTS=2
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *"0 passed · 7 failed"* ]]
    [[ "$msg" == *"<code>c › t2</code>"* ]]
    [[ "$msg" != *"<code>c › t3</code>"* ]]
    [[ "$msg" == *"… and 5 more"* ]]
}

@test "test_summary is skipped without token or without results" {
    TELEGRAM_NOTIFY_TEMPLATE=test_summary
    msg="$(tn_build_message success "" 2>/dev/null)"
    [[ "$msg" != *"Tests:"* ]]
    export CIRCLE_TOKEN=abc
    export MOCK_TESTS_JSON='{"items":[]}'
    run tn_section_test_summary
    [[ "$output" != *"Tests:"* ]]
}

@test "insights renders workflow metrics and flaky count" {
    export CIRCLE_TOKEN=abc
    export MOCK_INSIGHTS_JSON='{"metrics":{"success_rate":0.9375,"total_runs":16,"failed_runs":1,"mttr":754,"throughput":2.3,"duration_metrics":{"p95":245.5}}}'
    TELEGRAM_NOTIFY_TEMPLATE=insights
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"📈 <b>Insights</b> <i>(build_and_test · last 30 days)</i>"* ]]
    [[ "$msg" == *"Success rate: <b>94%</b> (1/16 failed)"* ]]
    [[ "$msg" == *"Duration p95: 4m 05s"* ]]
    [[ "$msg" == *"MTTR: 12m 34s"* ]]
    [[ "$msg" == *"Throughput: 2.3 runs/day"* ]]
    [[ "$msg" == *"Flaky tests: 2"* ]]
    grep -q 'workflows/build_and_test/summary?reporting-window=last-30-days&branch=feat/<scary>&branch' "$MOCK_CURL_LOG"
}

@test "insights honours workflow_name and window overrides and skips on empty metrics" {
    export CIRCLE_TOKEN=abc
    export MOCK_INSIGHTS_JSON='{"metrics":{"success_rate":1,"total_runs":3}}'
    TELEGRAM_NOTIFY_TEMPLATE=insights
    TELEGRAM_NOTIFY_WORKFLOW_NAME=deploy
    TELEGRAM_NOTIFY_INSIGHTS_WINDOW=last-7-days
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"(deploy · last 7 days)"* ]]
    ! grep -q 'api/v2/workflow/' "$MOCK_CURL_LOG"
    export MOCK_INSIGHTS_JSON='{"message":"Rate Limit Exceeded"}'
    msg="$(tn_build_message success "" 2>/dev/null)"
    [[ "$msg" != *"Insights"* ]]
}

@test "ai_summary posts the log to Anthropic and renders the three sections" {
    require_json_tool
    export ANTHROPIC_API_KEY=sk-test
    TELEGRAM_NOTIFY_TEMPLATE=ai_summary
    export MOCK_ANTHROPIC_BODY='{"content":[{"type":"text","text":"SUMMARY: The build failed because <foo> is undefined.\nFIX: Define foo in config.\nPROMPT: Fix the undefined foo in build.sh\nand add a test."}]}'
    msg="$(tn_build_message failure $'make: *** [all] Error 1\nundefined "foo"')"
    [[ "$msg" == *"🤖 <b>AI analysis</b> <i>(claude-opus-5)</i>"$'\n'"The build failed because &lt;foo&gt; is undefined."* ]]
    [[ "$msg" == *"🛠 <b>Likely fix:</b>"$'\n'"Define foo in config."* ]]
    [[ "$msg" == *"📋 <b>Prompt to fix (copy):</b>"$'\n'"<pre>Fix the undefined foo in build.sh"$'\n'"and add a test.</pre>"* ]]
    [[ "$msg" == *"❌ <b>Error Output:</b>"* ]]
    grep -q 'https://api.anthropic.com/v1/messages' "$MOCK_CURL_LOG"
    grep -q 'x-api-key: sk-test' "$MOCK_CURL_LOG"
    grep -q 'anthropic-version: 2023-06-01' "$MOCK_CURL_LOG"
    grep -q '"model":"claude-opus-5"' "$MOCK_CURL_LOG"
    grep -q 'undefined \\"foo\\"' "$MOCK_CURL_LOG"
}

@test "ai_summary is skipped without a key, on success, or on API errors" {
    TELEGRAM_NOTIFY_TEMPLATE=ai_summary
    msg="$(tn_build_message failure "boom" 2>/dev/null)"
    [[ "$msg" != *"AI analysis"* ]]
    export ANTHROPIC_API_KEY=sk-test
    msg="$(tn_build_message success "" 2>/dev/null)"
    [[ "$msg" != *"AI analysis"* ]]
    ! grep -q 'v1/messages' "$MOCK_CURL_LOG"
    export MOCK_ANTHROPIC_BODY='{"type":"error","error":{"message":"invalid key"}}'
    export MOCK_ANTHROPIC_HTTP_CODE=401
    run tn_section_ai_summary "boom"
    [[ "$output" != *"AI analysis"* ]]
}

@test "ai_summary honours ai_model and ai_max_tokens" {
    require_json_tool
    export ANTHROPIC_API_KEY=sk-test
    TELEGRAM_NOTIFY_AI_MODEL=claude-haiku-4-5
    TELEGRAM_NOTIFY_AI_MAX_TOKENS=300
    tn_section_ai_summary "boom" >/dev/null 2>&1
    grep -q '"model":"claude-haiku-4-5","max_tokens":300' "$MOCK_CURL_LOG"
}

@test "deploy template renders the release card for tags" {
    unset CIRCLE_BRANCH
    export CIRCLE_TAG=v2.0.0
    TELEGRAM_NOTIFY_TEMPLATE=deploy
    TELEGRAM_NOTIFY_DEPLOY_ENVIRONMENT=production
    msg="$(tn_build_message success "")"
    [[ "$msg" == "🚀 <b>Release</b>"* ]]
    [[ "$msg" == *'🚀 <b>Deployed</b> <a href="https://github.com/kevnm67/telegram-notify/releases/tag/v2.0.0">v2.0.0</a> → <b>production</b>'* ]]
}

@test "custom template substitutes {{VAR}} placeholders with escaped values" {
    TELEGRAM_NOTIFY_TEMPLATE=custom
    TELEGRAM_NOTIFY_CUSTOM_BODY='<b>{{CIRCLE_JOB}}</b> on {{CIRCLE_BRANCH}} by {{CIRCLE_USERNAME}} {{MISSING_VAR}}!'
    TELEGRAM_NOTIFY_MENTIONS='@ops'
    msg="$(tn_build_message failure "ignored")"
    [ "$msg" = $'<b>unit_tests</b> on feat/&lt;scary&gt;&amp;branch by kevin !\n\n@ops' ]
}

@test "custom template falls back to basic when custom_body is empty" {
    TELEGRAM_NOTIFY_TEMPLATE=custom
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"✅ <b>CI Success</b>"* ]]
}

# --- sending -----------------------------------------------------------------

@test "tn_send_message fails without a bot token or chat id" {
    unset TELEGRAM_BOT_TOKEN
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TELEGRAM_BOT_TOKEN is not set"* ]]
    [ ! -s "$MOCK_CURL_LOG" ]
    export TELEGRAM_BOT_TOKEN="123:test-token"
    TELEGRAM_NOTIFY_CHAT_ID=""
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"chat_id is empty"* ]]
}

@test "tn_send_message reads token and chat id from alternate variables" {
    unset TELEGRAM_BOT_TOKEN
    export OTHER_TOKEN="999:other"
    TELEGRAM_NOTIFY_BOT_TOKEN_VAR=OTHER_TOKEN
    TELEGRAM_NOTIFY_CHAT_ID=""
    export TELEGRAM_CHAT_ID="777"
    run tn_send_message "hi"
    [ "$status" -eq 0 ]
    grep -q 'https://api.telegram.org/bot999:other/sendMessage' "$MOCK_CURL_LOG"
    grep -q -- '--data-urlencode chat_id=777' "$MOCK_CURL_LOG"
}

@test "tn_send_message posts url-encoded fields, buttons, topic and silent flags" {
    TELEGRAM_NOTIFY_SILENT=true
    TELEGRAM_NOTIFY_THREAD_ID=55
    TELEGRAM_NOTIFY_API_BASE=http://localhost:8089
    tn_send_message $'multi\nline "text"'
    log="$(cat "$MOCK_CURL_LOG")"
    [[ "$log" == *"http://localhost:8089/bot123:test-token/sendMessage"* ]]
    [[ "$log" == *"--data-urlencode chat_id=-100999"* ]]
    [[ "$log" == *$'--data-urlencode text=multi\nline "text"'* ]]
    [[ "$log" == *"--data-urlencode parse_mode=HTML"* ]]
    [[ "$log" == *"--data-urlencode disable_notification=true"* ]]
    [[ "$log" == *"--data-urlencode message_thread_id=55"* ]]
    [[ "$log" == *'--data-urlencode reply_markup={"inline_keyboard":[[{"text":"🔎 View build"'* ]]
    [ "$TN_LAST_MESSAGE_ID" = "4242" ]
}

@test "tn_send_message omits optional fields and buttons when disabled" {
    TELEGRAM_NOTIFY_BUTTONS=false
    run tn_send_message "hi"
    ! grep -q 'disable_notification' "$MOCK_CURL_LOG"
    ! grep -q 'message_thread_id' "$MOCK_CURL_LOG"
    ! grep -q 'reply_markup' "$MOCK_CURL_LOG"
}

@test "tn_send_message reports API errors, ok:false and transport failures" {
    export MOCK_HTTP_CODE=400
    export MOCK_TELEGRAM_BODY='{"ok":false,"description":"Bad Request: chat not found"}'
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"http=400"* ]]
    [[ "$output" == *"chat not found"* ]]
    unset MOCK_HTTP_CODE
    export MOCK_TELEGRAM_BODY='{"ok":false}'
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    export MOCK_CURL_EXIT=6
    run tn_send_message "hi"
    [ "$status" -eq 1 ]
    [[ "$output" == *"curl rc=6"* ]]
}

@test "dry run prints the message and buttons and skips the API" {
    TELEGRAM_NOTIFY_DRY_RUN=true
    run tn_send_message "hello <b>there</b>"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry run"* ]]
    [[ "$output" == *"hello <b>there</b>"* ]]
    [[ "$output" == *'buttons: {"inline_keyboard"'* ]]
    [ ! -s "$MOCK_CURL_LOG" ]
}

@test "tn_send_log_document uploads the stored log as a reply" {
    TN_RAW_LOG_FILE="${TMPDIR}/telegram_notify_failed_step.log"
    printf 'full log\n' >"$TN_RAW_LOG_FILE"
    TN_LAST_MESSAGE_ID=4242
    TELEGRAM_NOTIFY_THREAD_ID=9
    run tn_send_log_document
    [ "$status" -eq 0 ]
    log="$(cat "$MOCK_CURL_LOG")"
    [[ "$log" == *"/sendDocument"* ]]
    [[ "$log" == *"-F document=@${TN_RAW_LOG_FILE};filename=unit_tests-42-failed-step.log"* ]]
    [[ "$log" == *'-F reply_parameters={"message_id":4242}'* ]]
    [[ "$log" == *"-F message_thread_id=9"* ]]
    [[ "$output" == *"Attached unit_tests-42-failed-step.log"* ]]
}

@test "tn_send_log_document is a no-op without a stored log" {
    TN_RAW_LOG_FILE=""
    run tn_send_log_document
    [ "$status" -eq 0 ]
    [ ! -s "$MOCK_CURL_LOG" ]
}

# --- end-to-end through main -------------------------------------------------

@test "main sends a failure notification with buttons and exits 0" {
    run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"Notification sent (failure)"* ]]
    [[ "$(last_sent_text)" == *"🔴 <b>CI Failure</b>"* ]]
    grep -q 'reply_markup=' "$MOCK_CURL_LOG"
}

@test "main with event=success and event=always pick the right headline" {
    export TELEGRAM_NOTIFY_EVENT=success
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"✅ <b>CI Success</b>"* ]]
    export TELEGRAM_NOTIFY_EVENT=always
    touch "${TMPDIR}/telegram_notify_job_failed"
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"🔴 <b>CI Failure</b>"* ]]
}

@test "main includes fetched error output and duration on failure" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/step-output/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"make: *** [build] Error 1\n"}]'
    run_script
    [ "$status" -eq 0 ]
    text="$(last_sent_text)"
    [[ "$text" == *"<pre>make: *** [build] Error 1</pre>"* ]]
    [[ "$text" == *"⏱ <b>Duration:</b> 2m 13s"* ]]
}

@test "main with attach_log uploads the document after the message" {
    export CIRCLE_TOKEN=abc
    export TELEGRAM_NOTIFY_ATTACH_LOG=true
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/step-output/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"l1\nl2\n"}]'
    run_script
    [ "$status" -eq 0 ]
    grep -q '/sendDocument' "$MOCK_CURL_LOG"
    [[ "$output" == *"Attached unit_tests-42-failed-step.log"* ]]
}

@test "main HTML-escapes angle brackets in error output (patsub_replacement regression)" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":true,"output_url":"https://x/step-output/bad"}]}]}'
    export MOCK_STEP_OUTPUT='[{"message":"error: <simulated> & done\n"}]'
    run_script
    [ "$status" -eq 0 ]
    [[ "$(last_sent_text)" == *"<pre>error: &lt;simulated&gt; &amp; done</pre>"* ]]
}

@test "main never fails the build on delivery errors unless fail_on_error" {
    export MOCK_HTTP_CODE=500
    run_script
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail_on_error is false"* ]]
    export TELEGRAM_NOTIFY_FAIL_ON_ERROR=1
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

@test "boolean parameters accept CircleCI's 1/0 rendering" {
    TELEGRAM_NOTIFY_BUTTONS=0
    TELEGRAM_NOTIFY_INCLUDE_LINKS=0
    msg="$(tn_build_message success "")"
    [[ "$msg" != *"View Build"* ]]
    TELEGRAM_NOTIFY_INCLUDE_LINKS=1
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"View Build"* ]]
    TELEGRAM_NOTIFY_SILENT=1
    TELEGRAM_NOTIFY_DRY_RUN=0
    run tn_send_message "hi"
    [ "$status" -eq 0 ]
    grep -q 'disable_notification=true' "$MOCK_CURL_LOG"
    TELEGRAM_NOTIFY_DRY_RUN=1
    : >"$MOCK_CURL_LOG"
    run tn_send_message "hi"
    [ "$status" -eq 0 ]
    [ ! -s "$MOCK_CURL_LOG" ]
}

# --- fallback paths (python3 present, jq absent) ---------------------------

no_jq() { tn_has() { [[ "$1" == "jq" ]] && return 1; command -v "$1" >/dev/null 2>&1; }; }

@test "test_summary renders via the python3 fallback when jq is absent" {
    command -v python3 >/dev/null || skip "python3 not installed"
    no_jq
    export CIRCLE_TOKEN=abc
    export MOCK_TESTS_JSON='{"items":[{"classname":"a","name":"ok","result":"success","run_time":1},{"classname":"b","name":"bad","result":"error","run_time":2,"message":"boom\nmore"}]}'
    TELEGRAM_NOTIFY_TEMPLATE=test_summary
    msg="$(tn_build_message failure "")"
    [[ "$msg" == *"1 passed · 1 failed · 0 skipped · 2 total · ⏱ 3.0s"* ]]
    [[ "$msg" == *"<code>b › bad</code> — boom"* ]]
}

@test "ai_summary parses the response via the python3 fallback when jq is absent" {
    command -v python3 >/dev/null || skip "python3 not installed"
    no_jq
    export ANTHROPIC_API_KEY=sk-test
    section="$(tn_section_ai_summary "boom" 2>/dev/null)"
    [[ "$section" == *"mock summary"* ]]
    [[ "$section" == *"<pre>mock prompt</pre>"* ]]
}

@test "ai_summary skips without error output, without JSON tools, and on transport errors" {
    export ANTHROPIC_API_KEY=sk-test
    run tn_section_ai_summary ""
    [[ "$output" == *"no error output"* ]]
    tn_has() { [[ "$1" == "jq" || "$1" == "python3" ]] && return 1; command -v "$1" >/dev/null 2>&1; }
    run tn_section_ai_summary "boom"
    [[ "$output" == *"needs jq or python3"* ]]
    unset -f tn_has
    tn_has() { command -v "$1" >/dev/null 2>&1; }
    require_json_tool # transport-error path needs a parser present to get past the guard
    export MOCK_CURL_EXIT=28
    run tn_section_ai_summary "boom"
    [[ "$output" == *"request failed"* ]]
}

@test "insights tolerates partial metrics and a missing flaky count" {
    export CIRCLE_TOKEN=abc
    export MOCK_INSIGHTS_JSON='{"metrics":{"total_runs":4,"failed_runs":0,"duration_metrics":{}}}'
    export MOCK_FLAKY_JSON='{}'
    TELEGRAM_NOTIFY_TEMPLATE=insights
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"📈 <b>Insights</b>"* ]]
    [[ "$msg" != *"Success rate"* ]]
    [[ "$msg" != *"Flaky tests"* ]]
    [[ "$msg" != *"MTTR"* ]]
}

@test "deploy template without a tag or environment still renders a card" {
    TELEGRAM_NOTIFY_TEMPLATE=deploy
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"🚀 <b>Deployed</b>"* ]]
    TELEGRAM_NOTIFY_DEPLOY_VERSION=1.2.3
    unset CIRCLE_BRANCH
    msg="$(tn_build_message success "")"
    [[ "$msg" == *"🚀 <b>Deployed</b> 1.2.3"* ]]
}

@test "tn_send_log_document reports upload failures and honours dry_run" {
    TN_RAW_LOG_FILE="${TMPDIR}/telegram_notify_failed_step.log"
    printf 'log\n' >"$TN_RAW_LOG_FILE"
    export MOCK_DOC_HTTP_CODE=413
    export MOCK_TELEGRAM_DOC_BODY='{"ok":false,"description":"Request Entity Too Large"}'
    run tn_send_log_document
    [ "$status" -eq 1 ]
    [[ "$output" == *"sendDocument failed"* ]]
    TELEGRAM_NOTIFY_DRY_RUN=true
    : >"$MOCK_CURL_LOG"
    run tn_send_log_document
    [ "$status" -eq 0 ]
    [[ "$output" == *"would attach"* ]]
    [ ! -s "$MOCK_CURL_LOG" ]
}

@test "tn_links_line adds the pull request link and respects missing build url" {
    export CIRCLE_PULL_REQUEST="https://github.com/kevnm67/telegram-notify/pull/3"
    [[ "$(tn_links_line)" == *'<a href="https://github.com/kevnm67/telegram-notify/pull/3">Pull Request</a>'* ]]
    unset CIRCLE_BUILD_URL
    [ -z "$(tn_links_line)" ]
}

@test "tn_fetch_error_output logs when the build has no failed action" {
    export CIRCLE_TOKEN=abc
    export MOCK_CIRCLE_BUILD_JSON='{"steps":[{"actions":[{"failed":false,"output_url":"https://x/step-output/ok"}]}]}'
    run tn_fetch_error_output
    [ "$status" -eq 0 ]
    [[ "$output" == *"No failed step output found in build 42"* ]]
}

@test "main skips duration lookup when include_duration is false" {
    export CIRCLE_TOKEN=abc
    export TELEGRAM_NOTIFY_INCLUDE_DURATION=false
    export TELEGRAM_NOTIFY_EVENT=success
    run_script
    [ "$status" -eq 0 ]
    ! grep -q '/job/42' "$MOCK_CURL_LOG"
    [[ "$(last_sent_text)" != *"Duration"* ]]
}

@test "ai_summary strips control bytes from the log before building the request" {
    require_json_tool
    export ANTHROPIC_API_KEY=sk-test
    tn_section_ai_summary $'bad \x01byte\x7f here\ttab' >/dev/null 2>&1
    grep -q 'bad byte here\\ttab' "$MOCK_CURL_LOG"
    ! grep -q $'\x01' "$MOCK_CURL_LOG"
}

@test "ai_summary retries with an inline body when the file upload is rejected as invalid JSON" {
    require_json_tool
    export ANTHROPIC_API_KEY=sk-test
    export MOCK_ANTHROPIC_FIRST_BODY='{"type":"error","error":{"type":"invalid_request_error","message":"The request body is not valid JSON: unexpected character: line 1 column 1 (char 0)"}}'
    run tn_section_ai_summary "boom"
    [ "$status" -eq 0 ]
    [[ "$output" == *"retrying with an inline body"* ]]
    [[ "$output" == *"mock summary"* ]]
    [ "$(grep -c 'v1/messages' "$MOCK_CURL_LOG")" -ge 3 ] # first try + probe + retry
}
