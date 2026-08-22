#!/usr/bin/env bash
# telegram-notify orb — shared notification script.
#
# All inputs arrive as TELEGRAM_NOTIFY_* environment variables (set by the
# orb command from its parameters) plus CircleCI's built-in CIRCLE_* vars.
# The script is failure-safe by design: it exits 0 even when the message
# cannot be delivered, unless TELEGRAM_NOTIFY_FAIL_ON_ERROR=true.
#
# Source this file with TELEGRAM_NOTIFY_NO_MAIN=1 to load the functions
# without running main (used by the bats test-suite).
set +e
set -uo pipefail

readonly TN_TAG="[telegram-notify]"
readonly TN_TELEGRAM_MAX_CHARS=4096
readonly TN_ERROR_BLOCK_MAX_CHARS=3000
TN_MARKER_FILE="${TMPDIR:-/tmp}/telegram_notify_job_failed"

tn_log() {
    echo "${TN_TAG} $*" >&2
}

# Escape the three characters Telegram's HTML parse mode treats specially.
tn_html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

# Truncate $1 to at most $2 characters, marking the cut with an ellipsis.
tn_truncate() {
    local text="$1" max="$2"
    if ((${#text} > max)); then
        printf '%s…' "${text:0:$((max - 1))}"
    else
        printf '%s' "$text"
    fi
}

tn_strip_ansi() {
    sed -E $'s/\x1B\\[[0-9;?]*[ -\\/]*[@-~]//g'
}

# Resolve the job outcome this message should describe.
tn_resolve_status() {
    case "${TELEGRAM_NOTIFY_EVENT:-failure}" in
    failure | success)
        echo "${TELEGRAM_NOTIFY_EVENT:-failure}"
        ;;
    always)
        if [[ -f "$TN_MARKER_FILE" ]]; then
            echo failure
        else
            echo success
        fi
        ;;
    *)
        tn_log "Unknown event '${TELEGRAM_NOTIFY_EVENT}', treating as failure"
        echo failure
        ;;
    esac
}

# Pick the output_url of the failed action from a v1.1 build payload (stdin).
tn_find_failed_output_url() {
    local url=""
    if command -v jq >/dev/null 2>&1; then
        url=$(jq -r '[.steps[]?.actions[]?
            | select(.failed == true or .status == "failed" or .status == "timedout")
            | .output_url // empty] | first // empty' 2>/dev/null)
    else
        # Without jq: the failed action is the last one that produced output.
        url=$(grep -o '"output_url":"[^"]*"' | tail -n 1 | sed 's/"output_url":"//; s/"$//')
    fi
    printf '%s' "${url//\\\//\/}"
}

# Turn a step-output payload ([{"message": "..."}...], stdin) into plain text.
tn_extract_messages() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.[]?.message // empty' 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys; print("".join(m.get("message","") for m in json.load(sys.stdin)))' 2>/dev/null
    else
        grep -o '"message":"[^"]*"' | sed 's/"message":"//; s/"$//; s/\\r\\n/\n/g; s/\\n/\n/g; s/\\"/"/g; s/\\\//\//g'
    fi
}

# Fetch the trailing lines of the failed step's output via the CircleCI API.
# Prints raw (unescaped) text, or nothing when unavailable.
tn_fetch_error_output() {
    local token_var="${TELEGRAM_NOTIFY_CIRCLE_TOKEN_VAR:-CIRCLE_TOKEN}"
    local token="${!token_var:-}"
    if [[ -z "$token" ]]; then
        tn_log "${token_var} is not set; sending without error output"
        return 0
    fi
    if [[ -z "${CIRCLE_BUILD_NUM:-}" ]]; then
        tn_log "CIRCLE_BUILD_NUM is not set; sending without error output"
        return 0
    fi

    local api_base="${TELEGRAM_NOTIFY_CIRCLECI_API_BASE:-https://circleci.com/api/v1.1}"
    local url="${api_base}/project/${TELEGRAM_NOTIFY_VCS_TYPE:-github}/${CIRCLE_PROJECT_USERNAME:-}/${CIRCLE_PROJECT_REPONAME:-}/${CIRCLE_BUILD_NUM}"
    local build_json
    if ! build_json=$(curl -sS --max-time 20 -H "Circle-Token: ${token}" "$url"); then
        tn_log "CircleCI API request failed; sending without error output"
        return 0
    fi

    local output_url
    output_url=$(tn_find_failed_output_url <<<"$build_json")
    if [[ -z "$output_url" ]]; then
        tn_log "No failed step output found in build ${CIRCLE_BUILD_NUM}"
        return 0
    fi

    local raw
    if ! raw=$(curl -sS --max-time 20 "$output_url"); then
        tn_log "Could not download step output; sending without error output"
        return 0
    fi

    tn_extract_messages <<<"$raw" | tn_strip_ansi | tail -n "${TELEGRAM_NOTIFY_MAX_LINES:-50}"
}

# Build the HTML message for $1 (failure|success) with optional raw error output $2.
tn_build_message() {
    local status="$1" error_output="${2:-}"
    local repo branch job commit_short actor message
    repo=$(tn_html_escape "${CIRCLE_PROJECT_REPONAME:-unknown}")
    branch=$(tn_html_escape "${CIRCLE_BRANCH:-${CIRCLE_TAG:-unknown}}")
    job=$(tn_html_escape "${CIRCLE_JOB:-unknown}")
    commit_short="${CIRCLE_SHA1:-unknown}"
    commit_short=$(tn_html_escape "${commit_short:0:8}")
    actor=$(tn_html_escape "${CIRCLE_USERNAME:-}")

    if [[ "$status" == "failure" ]]; then
        message="🔴 <b>CI Failure</b>"
    else
        message="✅ <b>CI Success</b>"
    fi

    if [[ -n "${TELEGRAM_NOTIFY_CUSTOM_MESSAGE:-}" ]]; then
        message+=$'\n'"${TELEGRAM_NOTIFY_CUSTOM_MESSAGE}"
    fi

    message+=$'\n\n'"📁 <b>Repository:</b> ${repo}"
    message+=$'\n'"🌿 <b>Branch:</b> ${branch}"
    message+=$'\n'"⚙️ <b>Job:</b> ${job}"
    message+=$'\n'"📝 <b>Commit:</b> <code>${commit_short}</code>"
    if [[ -n "$actor" ]]; then
        message+=$'\n'"👤 <b>Triggered by:</b> ${actor}"
    fi

    if [[ -n "$error_output" ]]; then
        local block
        block=$(tn_truncate "$error_output" "$TN_ERROR_BLOCK_MAX_CHARS")
        message+=$'\n\n'"❌ <b>Error Output:</b>"$'\n'"<pre>$(tn_html_escape "$block")</pre>"
    fi

    if [[ "${TELEGRAM_NOTIFY_INCLUDE_LINKS:-true}" == "true" && -n "${CIRCLE_BUILD_URL:-}" ]]; then
        message+=$'\n\n'"🔗 <a href=\"${CIRCLE_BUILD_URL}\">View Build</a>"
        if [[ -n "${CIRCLE_WORKFLOW_ID:-}" ]]; then
            message+=" | <a href=\"https://app.circleci.com/pipelines/workflows/${CIRCLE_WORKFLOW_ID}\">View Workflow</a>"
        fi
    fi

    if [[ -n "${TELEGRAM_NOTIFY_MENTIONS:-}" ]]; then
        message+=$'\n\n'"${TELEGRAM_NOTIFY_MENTIONS}"
    fi

    printf '%s' "$message"
}

# POST the message to the Telegram Bot API. Returns non-zero on any failure.
tn_send_message() {
    local text="$1"
    local token_var="${TELEGRAM_NOTIFY_BOT_TOKEN_VAR:-TELEGRAM_BOT_TOKEN}"
    local token="${!token_var:-}"
    local chat_id="${TELEGRAM_NOTIFY_CHAT_ID:-}"
    chat_id="${chat_id:-${TELEGRAM_CHAT_ID:-}}"

    if [[ "${TELEGRAM_NOTIFY_DRY_RUN:-false}" == "true" ]]; then
        tn_log "dry run — message not sent:"
        printf '%s\n' "$text"
        return 0
    fi
    if [[ -z "$token" ]]; then
        tn_log "ERROR: ${token_var} is not set; cannot send notification"
        return 1
    fi
    if [[ -z "$chat_id" ]]; then
        tn_log "ERROR: chat_id is empty and TELEGRAM_CHAT_ID is not set; cannot send notification"
        return 1
    fi

    local api_base="${TELEGRAM_NOTIFY_API_BASE:-https://api.telegram.org}"
    local body_file
    body_file=$(mktemp)
    local args=(
        -sS --max-time 20 -o "$body_file" -w '%{http_code}' -X POST
        "${api_base}/bot${token}/sendMessage"
        --data-urlencode "chat_id=${chat_id}"
        --data-urlencode "text=${text}"
        --data-urlencode "parse_mode=HTML"
        --data-urlencode "disable_web_page_preview=true"
    )
    if [[ "${TELEGRAM_NOTIFY_SILENT:-false}" == "true" ]]; then
        args+=(--data-urlencode "disable_notification=true")
    fi
    if [[ -n "${TELEGRAM_NOTIFY_THREAD_ID:-}" ]]; then
        args+=(--data-urlencode "message_thread_id=${TELEGRAM_NOTIFY_THREAD_ID}")
    fi

    local http_code body
    http_code=$(curl "${args[@]}")
    local curl_rc=$?
    body=$(cat "$body_file" 2>/dev/null)
    rm -f "$body_file"

    if [[ $curl_rc -eq 0 && "$http_code" == "200" ]] && grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' <<<"$body"; then
        return 0
    fi
    tn_log "ERROR: Telegram API call failed (curl rc=${curl_rc}, http=${http_code:-n/a})"
    tn_log "Response: $(tn_truncate "${body:-<empty>}" 300)"
    return 1
}

main() {
    tn_log "Preparing ${TELEGRAM_NOTIFY_EVENT:-failure} notification"
    local status error_output="" message
    status=$(tn_resolve_status)
    if [[ "$status" == "failure" ]]; then
        error_output=$(tn_fetch_error_output)
    fi
    message=$(tn_build_message "$status" "$error_output")
    message=$(tn_truncate "$message" "$TN_TELEGRAM_MAX_CHARS")

    if tn_send_message "$message"; then
        tn_log "Notification sent (${status})"
        exit 0
    fi
    if [[ "${TELEGRAM_NOTIFY_FAIL_ON_ERROR:-false}" == "true" ]]; then
        tn_log "Notification failed and fail_on_error is true"
        exit 1
    fi
    tn_log "Notification failed; continuing because fail_on_error is false"
    exit 0
}

if [[ -z "${TELEGRAM_NOTIFY_NO_MAIN:-}" ]]; then
    main "$@"
fi
