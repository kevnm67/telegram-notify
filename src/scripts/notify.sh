#!/usr/bin/env bash
# telegram-notify orb — shared notification script.
#
# All inputs arrive as TELEGRAM_NOTIFY_* environment variables (set by the
# orb command from its parameters) plus CircleCI's built-in CIRCLE_* vars.
# The script is failure-safe by design: it exits 0 even when the message
# cannot be delivered, unless TELEGRAM_NOTIFY_FAIL_ON_ERROR is true.
#
# Compatibility: bash >= 3.2 (macOS), curl required; jq / python3 used when
# present for JSON work, with graceful degradation otherwise.
#
# Source this file with TELEGRAM_NOTIFY_NO_MAIN=1 to load the functions
# without running main (used by the bats test-suite).
set +e
set -uo pipefail
# bash >= 5.2 expands "&" in ${var//pat/rep} to the match; keep replacements literal.
shopt -u patsub_replacement 2>/dev/null || true

readonly TN_TAG="[telegram-notify]"
readonly TN_TELEGRAM_MAX_CHARS=4096
readonly TN_ERROR_BLOCK_MAX_CHARS=3000
readonly TN_CURL_TIMEOUT=20
TN_MARKER_FILE="${TMPDIR:-/tmp}/telegram_notify_job_failed"
TN_RAW_LOG_FILE=""
: "${TELEGRAM_NOTIFY_MENTIONS:=}"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

tn_log() {
    echo "${TN_TAG} $*" >&2
}

# CircleCI renders boolean parameters as 1/0 in `environment:`; accept both.
tn_is_true() {
    case "${1:-}" in
    true | TRUE | True | 1 | yes | on) return 0 ;;
    *) return 1 ;;
    esac
}

tn_has() {
    command -v "$1" >/dev/null 2>&1
}

# Escape the three characters Telegram's HTML parse mode treats specially.
tn_html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

# Escape a string for embedding inside a JSON string literal.
tn_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
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
    # LC_ALL=C: in UTF-8 locales GNU sed treats the raw ESC byte and the
    # bracket ranges as multibyte text and never matches.
    LC_ALL=C sed -E $'s#\x1B\\[[0-9;?]*[ -/]*[@-~]##g'
}

# Format milliseconds as "1h 02m", "2m 13s" or "850ms".
tn_format_duration_ms() {
    local ms="${1:-0}"
    [[ "$ms" =~ ^[0-9]+$ ]] || { printf ''; return 0; }
    local s=$((ms / 1000))
    if ((s >= 3600)); then
        printf '%dh %02dm' $((s / 3600)) $(((s % 3600) / 60))
    elif ((s >= 60)); then
        printf '%dm %02ds' $((s / 60)) $((s % 60))
    elif ((s >= 1)); then
        printf '%ds' "$s"
    else
        printf '%dms' "$ms"
    fi
}

# Read a JSON value by jq path ($2) from stdin; python3 fallback uses the same
# dotted path ($3 optional python expression overrides). Prints nothing on failure.
tn_json_get() {
    local jq_filter="$1" py_path="${2:-}"
    if tn_has jq; then
        jq -r "$jq_filter // empty" 2>/dev/null
    elif tn_has python3 && [[ -n "$py_path" ]]; then
        python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        if key == "":
            continue
        data = data[int(key)] if isinstance(data, list) else data[key]
    if data is None:
        sys.exit(0)
    print(data if not isinstance(data, (dict, list)) else json.dumps(data))
except Exception:
    pass
' "$py_path" 2>/dev/null
    elif [[ -n "$py_path" ]]; then
        # Last resort: first occurrence of the final key (number, string or bool).
        local key="${py_path##*.}"
        grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\(\"[^\"]*\"\|[-0-9.]\+\|true\|false\)" 2>/dev/null | head -n 1 |
            sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*//; s/^"//; s/"$//'
    fi
}

# Resolve the VCS web URL for the repository (https://github.com/org/repo).
tn_repo_web_url() {
    local url="${CIRCLE_REPOSITORY_URL:-}"
    if [[ -z "$url" ]]; then
        local host="github.com"
        [[ "${TELEGRAM_NOTIFY_VCS_TYPE:-github}" == "bitbucket" ]] && host="bitbucket.org"
        [[ -n "${CIRCLE_PROJECT_USERNAME:-}" && -n "${CIRCLE_PROJECT_REPONAME:-}" ]] &&
            url="https://${host}/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
    fi
    url="${url%.git}"
    case "$url" in
    git@*:*)
        url="${url#git@}"
        url="https://${url%%:*}/${url#*:}"
        ;;
    ssh://git@*)
        url="${url#ssh://git@}"
        url="https://${url}"
        ;;
    esac
    printf '%s' "$url"
}

tn_commit_url() {
    local base
    base=$(tn_repo_web_url)
    [[ -z "$base" || -z "${CIRCLE_SHA1:-}" ]] && return 0
    if [[ "${TELEGRAM_NOTIFY_VCS_TYPE:-github}" == "bitbucket" ]]; then
        printf '%s/commits/%s' "$base" "$CIRCLE_SHA1"
    else
        printf '%s/commit/%s' "$base" "$CIRCLE_SHA1"
    fi
}

tn_branch_url() {
    local base
    base=$(tn_repo_web_url)
    [[ -z "$base" ]] && return 0
    if [[ -n "${CIRCLE_TAG:-}" ]]; then
        if [[ "${TELEGRAM_NOTIFY_VCS_TYPE:-github}" == "bitbucket" ]]; then
            printf '%s/src/%s' "$base" "$CIRCLE_TAG"
        else
            printf '%s/releases/tag/%s' "$base" "$CIRCLE_TAG"
        fi
    elif [[ -n "${CIRCLE_BRANCH:-}" ]]; then
        if [[ "${TELEGRAM_NOTIFY_VCS_TYPE:-github}" == "bitbucket" ]]; then
            printf '%s/branch/%s' "$base" "$CIRCLE_BRANCH"
        else
            printf '%s/tree/%s' "$base" "$CIRCLE_BRANCH"
        fi
    fi
}

# "<a href=URL>label</a>" when a URL is available, else the escaped label.
tn_link() {
    local label="$1" url="${2:-}"
    if [[ -n "$url" ]]; then
        printf '<a href="%s">%s</a>' "$(tn_html_escape "$url")" "$(tn_html_escape "$label")"
    else
        tn_html_escape "$label"
    fi
}

# ---------------------------------------------------------------------------
# Status, filters
# ---------------------------------------------------------------------------

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

# Return 0 when $2 matches any comma-separated anchored ERE in $1.
tn_matches_any() {
    local patterns="$1" value="$2" pattern
    local IFS=','
    for pattern in $patterns; do
        pattern="${pattern# }"
        pattern="${pattern% }"
        [[ -z "$pattern" ]] && continue
        if printf '%s\n' "$value" | grep -Eq "^${pattern}\$"; then
            return 0
        fi
    done
    return 1
}

# Decide whether branch_pattern / tag_pattern / invert_match allow sending.
# Prints a reason and returns 1 when the notification must be skipped.
tn_should_send() {
    local branch_pattern="${TELEGRAM_NOTIFY_BRANCH_PATTERN:-}"
    local tag_pattern="${TELEGRAM_NOTIFY_TAG_PATTERN:-}"
    [[ -z "$branch_pattern" && -z "$tag_pattern" ]] && return 0

    local matched=false
    if [[ -n "${CIRCLE_TAG:-}" && -n "$tag_pattern" ]]; then
        tn_matches_any "$tag_pattern" "$CIRCLE_TAG" && matched=true
    elif [[ -z "${CIRCLE_TAG:-}" && -n "$branch_pattern" ]]; then
        tn_matches_any "$branch_pattern" "${CIRCLE_BRANCH:-}" && matched=true
    fi

    if tn_is_true "${TELEGRAM_NOTIFY_INVERT_MATCH:-false}"; then
        if [[ "$matched" == true ]]; then
            printf 'ref matches pattern and invert_match is set'
            return 1
        fi
        return 0
    fi
    if [[ "$matched" == false ]]; then
        printf 'ref does not match branch_pattern/tag_pattern'
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# CircleCI API access
# ---------------------------------------------------------------------------

tn_circle_token() {
    local token_var="${TELEGRAM_NOTIFY_CIRCLE_TOKEN_VAR:-CIRCLE_TOKEN}"
    printf '%s' "${!token_var:-}"
}

tn_project_slug() {
    local vcs="${TELEGRAM_NOTIFY_VCS_TYPE:-github}"
    local short="gh"
    [[ "$vcs" == "bitbucket" ]] && short="bb"
    printf '%s/%s/%s' "$short" "${CIRCLE_PROJECT_USERNAME:-}" "${CIRCLE_PROJECT_REPONAME:-}"
}

# GET a CircleCI API v2 path ($1, relative to /api/v2). Prints the body.
tn_circle_api_v2() {
    local path="$1" token
    token=$(tn_circle_token)
    [[ -z "$token" ]] && return 1
    local base="${TELEGRAM_NOTIFY_CIRCLECI_API_V2_BASE:-https://circleci.com/api/v2}"
    curl -sS --max-time "$TN_CURL_TIMEOUT" -H "Circle-Token: ${token}" -H "Accept: application/json" "${base}${path}"
}

# Pick the output_url of the failed action from a v1.1 build payload (stdin).
tn_find_failed_output_url() {
    local url=""
    if tn_has jq; then
        url=$(jq -r '[.steps[]?.actions[]?
            | select(.failed == true or .status == "failed" or .status == "timedout")
            | .output_url // empty] | first // empty' 2>/dev/null)
    else
        # Without jq: split into one object per line, keep failed actions only.
        url=$(tr '{' '\n' | grep -E '"failed":[[:space:]]*true|"status":[[:space:]]*"(failed|timedout)"' |
            grep -o '"output_url":"[^"]*"' | tail -n 1 | sed 's/"output_url":"//; s/"$//')
    fi
    printf '%s' "$url" | sed 's#\\/#/#g'
}

# Turn a step-output payload ([{"message": "..."}...], stdin) into plain text.
tn_extract_messages() {
    if tn_has jq; then
        jq -j '.[]?.message // empty' 2>/dev/null
    elif tn_has python3; then
        python3 -c 'import json,sys; print("".join(m.get("message","") for m in json.load(sys.stdin)))' 2>/dev/null
    else
        grep -o '"message":"[^"]*"' | sed 's/"message":"//; s/"$//' |
            awk '{ gsub(/\\r\\n|\\n/, "\n"); gsub(/\\t/, "\t"); gsub(/\\u001[bB]/, "\033"); gsub(/\\\//, "/"); printf "%s", $0 }'
    fi
}

# Fetch the failed step's output via the CircleCI API. Prints the trailing
# max_lines (raw, unescaped) and stores the full text in $TN_RAW_LOG_FILE.
tn_fetch_error_output() {
    local token
    token=$(tn_circle_token)
    if [[ -z "$token" ]]; then
        tn_log "${TELEGRAM_NOTIFY_CIRCLE_TOKEN_VAR:-CIRCLE_TOKEN} is not set; sending without error output"
        return 0
    fi
    if [[ -z "${CIRCLE_BUILD_NUM:-}" ]]; then
        tn_log "CIRCLE_BUILD_NUM is not set; sending without error output"
        return 0
    fi

    local api_base="${TELEGRAM_NOTIFY_CIRCLECI_API_BASE:-https://circleci.com/api/v1.1}"
    local url="${api_base}/project/${TELEGRAM_NOTIFY_VCS_TYPE:-github}/${CIRCLE_PROJECT_USERNAME:-}/${CIRCLE_PROJECT_REPONAME:-}/${CIRCLE_BUILD_NUM}"
    local build_json
    if ! build_json=$(curl -sS --max-time "$TN_CURL_TIMEOUT" -H "Circle-Token: ${token}" "$url"); then
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
    if ! raw=$(curl -sS --max-time "$TN_CURL_TIMEOUT" "$output_url"); then
        tn_log "Could not download step output; sending without error output"
        return 0
    fi

    local text
    text=$(tn_extract_messages <<<"$raw" | tn_strip_ansi)
    if [[ -n "$text" ]]; then
        TN_RAW_LOG_FILE="${TMPDIR:-/tmp}/telegram_notify_failed_step.log"
        printf '%s\n' "$text" >"$TN_RAW_LOG_FILE"
    fi
    printf '%s' "$text" | tail -n "${TELEGRAM_NOTIFY_MAX_LINES:-50}"
}

# Job duration (ms) and PR number/url from the v2 job details endpoint.
# Prints "duration_ms" or nothing.
tn_fetch_job_duration_ms() {
    [[ -z "${CIRCLE_BUILD_NUM:-}" ]] && return 0
    local body
    body=$(tn_circle_api_v2 "/project/$(tn_project_slug)/job/${CIRCLE_BUILD_NUM}") || return 0
    local ms
    ms=$(tn_json_get '.duration' 'duration' <<<"$body")
    [[ "$ms" =~ ^[0-9]+$ ]] && printf '%s' "$ms"
}

# ---------------------------------------------------------------------------
# Template sections
# ---------------------------------------------------------------------------

# test_summary: counts + failed tests from /project/{slug}/{job}/tests.
tn_section_test_summary() {
    [[ -z "${CIRCLE_BUILD_NUM:-}" ]] && return 0
    local body
    if ! body=$(tn_circle_api_v2 "/project/$(tn_project_slug)/${CIRCLE_BUILD_NUM}/tests"); then
        tn_log "test_summary: CIRCLE_TOKEN missing or API unavailable; section skipped"
        return 0
    fi
    local max_failed="${TELEGRAM_NOTIFY_MAX_FAILED_TESTS:-5}"
    local summary=""
    if tn_has jq; then
        summary=$(jq -r --argjson max "$max_failed" '
            .items as $t
            | ($t | length) as $total
            | ([$t[] | select(.result == "success")] | length) as $pass
            | ([$t[] | select(.result == "failure" or .result == "error")] | length) as $fail
            | ([$t[] | select(.result == "skipped")] | length) as $skip
            | ([$t[] | .run_time // 0] | add // 0) as $runtime
            | "\($total)\t\($pass)\t\($fail)\t\($skip)\t\($runtime)",
              ([$t[] | select(.result == "failure" or .result == "error")][:$max][]
               | "F\t\(.classname // "")\t\(.name // "")\t\((.message // "") | split("\n")[0])")
        ' <<<"$body" 2>/dev/null)
    elif tn_has python3; then
        summary=$(python3 -c '
import json, sys
items = json.load(sys.stdin).get("items", [])
fails = [t for t in items if t.get("result") in ("failure", "error")]
print("%d\t%d\t%d\t%d\t%s" % (len(items), sum(1 for t in items if t.get("result") == "success"), len(fails),
      sum(1 for t in items if t.get("result") == "skipped"), sum(float(t.get("run_time") or 0) for t in items)))
for t in fails[: int(sys.argv[1])]:
    print("F\t%s\t%s\t%s" % (t.get("classname") or "", t.get("name") or "", (t.get("message") or "").split("\n")[0]))
' "$max_failed" <<<"$body" 2>/dev/null)
    else
        tn_log "test_summary needs jq or python3; section skipped"
        return 0
    fi
    [[ -z "$summary" ]] && return 0

    local header
    header=$(printf '%s\n' "$summary" | head -n 1)
    local total pass fail skip runtime
    IFS=$'\t' read -r total pass fail skip runtime <<<"$header"
    [[ "${total:-0}" == "0" ]] && {
        tn_log "test_summary: no test results recorded for this job (store_test_results before notifying)"
        return 0
    }
    local runtime_fmt
    runtime_fmt=$(printf '%.1fs' "${runtime:-0}" 2>/dev/null || printf '%ss' "$runtime")
    local icon="✅"
    ((fail > 0)) && icon="❌"
    local section
    section="🧪 <b>Tests:</b> ${icon} ${pass} passed · ${fail} failed · ${skip} skipped · ${total} total · ⏱ ${runtime_fmt}"
    local line class name msg shown=0
    while IFS=$'\t' read -r line class name msg; do
        [[ "$line" != "F" ]] && continue
        shown=$((shown + 1))
        section+=$'\n'"  • <code>$(tn_html_escape "$(tn_truncate "${class:+${class} › }${name}" 120)")</code>"
        [[ -n "$msg" ]] && section+=" — $(tn_html_escape "$(tn_truncate "$msg" 160)")"
    done <<<"$summary"
    if ((fail > shown)); then
        section+=$'\n'"  • … and $((fail - shown)) more"
    fi
    printf '%s' "$section"
}

# insights: workflow summary metrics + flaky test count.
tn_section_insights() {
    local window="${TELEGRAM_NOTIFY_INSIGHTS_WINDOW:-last-30-days}"
    local wf_name="${TELEGRAM_NOTIFY_WORKFLOW_NAME:-}"
    if [[ -z "$wf_name" && -n "${CIRCLE_WORKFLOW_ID:-}" ]]; then
        wf_name=$(tn_circle_api_v2 "/workflow/${CIRCLE_WORKFLOW_ID}" | tn_json_get '.name' 'name')
    fi
    if [[ -z "$wf_name" ]]; then
        tn_log "insights: could not resolve workflow name (needs CIRCLE_TOKEN or workflow_name); section skipped"
        return 0
    fi
    local branch_q=""
    [[ -n "${CIRCLE_BRANCH:-}" ]] && branch_q="&branch=${CIRCLE_BRANCH}"
    local body
    if ! body=$(tn_circle_api_v2 "/insights/$(tn_project_slug)/workflows/${wf_name}/summary?reporting-window=${window}${branch_q}"); then
        tn_log "insights: API unavailable; section skipped"
        return 0
    fi
    local success_rate p95 mttr total failed throughput
    success_rate=$(tn_json_get '.metrics.success_rate' 'metrics.success_rate' <<<"$body")
    p95=$(tn_json_get '.metrics.duration_metrics.p95' 'metrics.duration_metrics.p95' <<<"$body")
    mttr=$(tn_json_get '.metrics.mttr' 'metrics.mttr' <<<"$body")
    total=$(tn_json_get '.metrics.total_runs' 'metrics.total_runs' <<<"$body")
    failed=$(tn_json_get '.metrics.failed_runs' 'metrics.failed_runs' <<<"$body")
    throughput=$(tn_json_get '.metrics.throughput' 'metrics.throughput' <<<"$body")
    if [[ -z "$success_rate" && -z "$total" ]]; then
        tn_log "insights: no metrics returned for workflow '${wf_name}' (${window}); section skipped"
        return 0
    fi
    local flaky
    flaky=$(tn_circle_api_v2 "/insights/$(tn_project_slug)/flaky-tests" | tn_json_get '.total_flaky_tests' 'total_flaky_tests')

    local rate_pct=""
    [[ -n "$success_rate" ]] && rate_pct=$(awk -v r="$success_rate" 'BEGIN { printf "%.0f%%", r * 100 }')
    local p95_fmt="" mttr_fmt=""
    [[ "$p95" =~ ^[0-9]+(\.[0-9]+)?$ ]] && p95_fmt=$(tn_format_duration_ms "$(awk -v s="$p95" 'BEGIN { printf "%d", s * 1000 }')")
    [[ "$mttr" =~ ^[0-9]+(\.[0-9]+)?$ ]] && mttr_fmt=$(tn_format_duration_ms "$(awk -v s="$mttr" 'BEGIN { printf "%d", s * 1000 }')")

    local section
    section="📈 <b>Insights</b> <i>($(tn_html_escape "$wf_name") · ${window//-/ })</i>"
    [[ -n "$rate_pct" ]] && section+=$'\n'"  • Success rate: <b>${rate_pct}</b>${total:+ (${failed:-0}/${total} failed)}"
    [[ -n "$p95_fmt" ]] && section+=$'\n'"  • Duration p95: ${p95_fmt}"
    [[ -n "$mttr_fmt" && "$mttr" != "0" ]] && section+=$'\n'"  • MTTR: ${mttr_fmt}"
    [[ -n "$throughput" ]] && section+=$'\n'"  • Throughput: $(awk -v t="$throughput" 'BEGIN { printf "%.1f", t }') runs/day"
    [[ -n "$flaky" ]] && section+=$'\n'"  • Flaky tests: ${flaky}"
    printf '%s' "$section"
}

# ai_summary: ask Claude for a summary, likely fix and a copy-paste prompt.
tn_section_ai_summary() {
    local error_output="$1"
    local key_var="${TELEGRAM_NOTIFY_ANTHROPIC_KEY_VAR:-ANTHROPIC_API_KEY}"
    local key="${!key_var:-}"
    if [[ -z "$key" ]]; then
        tn_log "ai_summary: ${key_var} is not set; section skipped"
        return 0
    fi
    if [[ -z "$error_output" ]]; then
        tn_log "ai_summary: no error output to analyse; section skipped"
        return 0
    fi
    if ! tn_has jq && ! tn_has python3; then
        tn_log "ai_summary needs jq or python3 to parse the response; section skipped"
        return 0
    fi

    local model="${TELEGRAM_NOTIFY_AI_MODEL:-claude-opus-5}"
    local max_tokens="${TELEGRAM_NOTIFY_AI_MAX_TOKENS:-700}"
    local context="Repository: ${CIRCLE_PROJECT_REPONAME:-unknown}, branch: ${CIRCLE_BRANCH:-${CIRCLE_TAG:-unknown}}, job: ${CIRCLE_JOB:-unknown}."
    local system="You are a senior CI engineer. You receive the tail of a failed CircleCI step. Reply in plain text with exactly three labelled sections and nothing else:
SUMMARY: two sentences max on what failed and the most likely root cause.
FIX: one to three short lines describing the most likely fix.
PROMPT: a single self-contained instruction (3-5 lines) a developer can paste into an AI coding assistant to fix this, quoting the key error text. Do not use markdown."
    local user="${context}

Failed step output (last lines):
${error_output}"
    local body
    body=$(printf '{"model":"%s","max_tokens":%s,"system":"%s","messages":[{"role":"user","content":"%s"}]}' \
        "$(tn_json_escape "$model")" "$max_tokens" "$(tn_json_escape "$system")" "$(tn_json_escape "$user")")

    local api="${TELEGRAM_NOTIFY_ANTHROPIC_API_BASE:-https://api.anthropic.com}"
    local response
    if ! response=$(curl -sS --max-time "${TELEGRAM_NOTIFY_AI_TIMEOUT:-60}" -X POST "${api}/v1/messages" \
        -H "Content-Type: application/json" -H "x-api-key: ${key}" -H "anthropic-version: 2023-06-01" \
        --data-binary "$body"); then
        tn_log "ai_summary: Anthropic API request failed; section skipped"
        return 0
    fi
    local text
    if tn_has jq; then
        text=$(jq -r '[.content[]? | select(.type == "text") | .text] | join("\n")' <<<"$response" 2>/dev/null)
    else
        text=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(b.get("text","") for b in d.get("content",[]) if b.get("type")=="text"))' <<<"$response" 2>/dev/null)
    fi
    if [[ -z "$text" ]]; then
        tn_log "ai_summary: empty or error response: $(tn_truncate "$response" 200)"
        return 0
    fi

    local summary fix prompt
    summary=$(printf '%s\n' "$text" | awk '/^SUMMARY:/{f=1; sub(/^SUMMARY:[ ]*/, ""); } /^FIX:/{f=0} f' | sed '/^$/d')
    fix=$(printf '%s\n' "$text" | awk '/^FIX:/{f=1; sub(/^FIX:[ ]*/, ""); } /^PROMPT:/{f=0} f' | sed '/^$/d')
    prompt=$(printf '%s\n' "$text" | awk '/^PROMPT:/{f=1; sub(/^PROMPT:[ ]*/, ""); } f' | sed '/^$/d')
    [[ -z "$summary" ]] && summary="$text"

    local section
    section="🤖 <b>AI analysis</b> <i>($(tn_html_escape "$model"))</i>"$'\n'"$(tn_html_escape "$(tn_truncate "$summary" 600)")"
    [[ -n "$fix" ]] && section+=$'\n\n'"🛠 <b>Likely fix:</b>"$'\n'"$(tn_html_escape "$(tn_truncate "$fix" 500)")"
    [[ -n "$prompt" ]] && section+=$'\n\n'"📋 <b>Prompt to fix (copy):</b>"$'\n'"<pre>$(tn_html_escape "$(tn_truncate "$prompt" 700)")</pre>"
    printf '%s' "$section"
}

# deploy: tagged release card.
tn_section_deploy() {
    local version="${CIRCLE_TAG:-${TELEGRAM_NOTIFY_DEPLOY_VERSION:-}}"
    local env_name="${TELEGRAM_NOTIFY_DEPLOY_ENVIRONMENT:-}"
    local section="🚀 <b>Deployed</b>"
    [[ -n "$version" ]] && section+=" $(tn_link "$version" "$(tn_branch_url)")"
    [[ -n "$env_name" ]] && section+=" → <b>$(tn_html_escape "$env_name")</b>"
    printf '%s' "$section"
}

# custom: render TELEGRAM_NOTIFY_CUSTOM_BODY replacing {{VAR}} with escaped env values.
tn_render_custom() {
    local body="$1" out="" rest="$1" name value
    while [[ "$rest" =~ \{\{([A-Za-z_][A-Za-z0-9_]*)\}\} ]]; do
        name="${BASH_REMATCH[1]}"
        value="${!name:-}"
        out+="${rest%%"${BASH_REMATCH[0]}"*}$(tn_html_escape "$value")"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    out+="$rest"
    printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Message assembly
# ---------------------------------------------------------------------------

# Metadata block shared by all templates.
tn_meta_block() {
    local repo branch_label job commit_short actor block
    repo=$(tn_link "${CIRCLE_PROJECT_REPONAME:-unknown}" "$(tn_repo_web_url)")
    branch_label="${CIRCLE_BRANCH:-${CIRCLE_TAG:-unknown}}"
    job=$(tn_link "${CIRCLE_JOB:-unknown}" "${CIRCLE_BUILD_URL:-}")
    commit_short="${CIRCLE_SHA1:-unknown}"
    commit_short="${commit_short:0:8}"
    actor=$(tn_html_escape "${CIRCLE_USERNAME:-}")

    block="📁 <b>Repository:</b> ${repo}"
    if [[ -n "${CIRCLE_TAG:-}" ]]; then
        block+=$'\n'"🏷 <b>Tag:</b> $(tn_link "$branch_label" "$(tn_branch_url)")"
    else
        block+=$'\n'"🌿 <b>Branch:</b> $(tn_link "$branch_label" "$(tn_branch_url)")"
    fi
    block+=$'\n'"⚙️ <b>Job:</b> ${job}"
    block+=$'\n'"📝 <b>Commit:</b> <code>$(tn_html_escape "$commit_short")</code>"
    if [[ -n "${CIRCLE_PULL_REQUEST:-}" ]]; then
        local pr_num="${CIRCLE_PR_NUMBER:-${CIRCLE_PULL_REQUEST##*/}}"
        block+=" · $(tn_link "PR #${pr_num}" "$CIRCLE_PULL_REQUEST")"
    fi
    [[ -n "$actor" ]] && block+=$'\n'"👤 <b>Triggered by:</b> ${actor}"
    if [[ -n "${TN_DURATION_MS:-}" ]]; then
        block+=$'\n'"⏱ <b>Duration:</b> $(tn_format_duration_ms "$TN_DURATION_MS")"
    fi
    printf '%s' "$block"
}

# Text links footer (used when buttons are disabled).
tn_links_line() {
    [[ -z "${CIRCLE_BUILD_URL:-}" ]] && return 0
    local line
    line="🔗 <a href=\"${CIRCLE_BUILD_URL}\">View Build</a>"
    [[ -n "${CIRCLE_WORKFLOW_ID:-}" ]] && line+=" | <a href=\"https://app.circleci.com/pipelines/workflows/${CIRCLE_WORKFLOW_ID}\">View Workflow</a>"
    [[ -n "${CIRCLE_PULL_REQUEST:-}" ]] && line+=" | <a href=\"${CIRCLE_PULL_REQUEST}\">Pull Request</a>"
    printf '%s' "$line"
}

# Inline keyboard JSON for reply_markup (one row of URL buttons), or nothing.
tn_inline_keyboard() {
    local buttons=""
    tn_add_button() {
        [[ -z "$2" ]] && return 0
        [[ -n "$buttons" ]] && buttons+=","
        buttons+=$(printf '{"text":"%s","url":"%s"}' "$(tn_json_escape "$1")" "$(tn_json_escape "$2")")
    }
    tn_add_button "🔎 View build" "${CIRCLE_BUILD_URL:-}"
    [[ -n "${CIRCLE_WORKFLOW_ID:-}" ]] && tn_add_button "🧭 Workflow" "https://app.circleci.com/pipelines/workflows/${CIRCLE_WORKFLOW_ID}"
    tn_add_button "🔀 Pull request" "${CIRCLE_PULL_REQUEST:-}"
    [[ -z "$buttons" ]] && return 0
    printf '{"inline_keyboard":[[%s]]}' "$buttons"
}

# Build the HTML message for $1 (failure|success) with optional raw error output $2.
tn_build_message() {
    local status="$1" error_output="${2:-}"
    local template="${TELEGRAM_NOTIFY_TEMPLATE:-basic}"
    local message

    if [[ "$template" == "custom" && -n "${TELEGRAM_NOTIFY_CUSTOM_BODY:-}" ]]; then
        message=$(tn_render_custom "$TELEGRAM_NOTIFY_CUSTOM_BODY")
        [[ -n "${TELEGRAM_NOTIFY_MENTIONS:-}" ]] && message+=$'\n\n'"${TELEGRAM_NOTIFY_MENTIONS}"
        printf '%s' "$message"
        return 0
    fi

    if [[ "$status" == "failure" ]]; then
        message="🔴 <b>CI Failure</b>"
    elif [[ "$template" == "deploy" ]]; then
        message="🚀 <b>Release</b>"
    else
        message="✅ <b>CI Success</b>"
    fi
    [[ -n "${TELEGRAM_NOTIFY_CUSTOM_MESSAGE:-}" ]] && message+=$'\n'"${TELEGRAM_NOTIFY_CUSTOM_MESSAGE}"
    message+=$'\n\n'"$(tn_meta_block)"

    local section=""
    case "$template" in
    test_summary) section=$(tn_section_test_summary) ;;
    insights) section=$(tn_section_insights) ;;
    ai_summary) [[ "$status" == "failure" ]] && section=$(tn_section_ai_summary "$error_output") ;;
    deploy) section=$(tn_section_deploy) ;;
    esac
    [[ -n "$section" ]] && message+=$'\n\n'"$section"

    local footer=""
    if tn_is_true "${TELEGRAM_NOTIFY_INCLUDE_LINKS:-true}" && ! tn_is_true "${TELEGRAM_NOTIFY_BUTTONS:-true}"; then
        footer=$(tn_links_line)
    fi
    [[ -n "${TELEGRAM_NOTIFY_MENTIONS:-}" ]] && footer+="${footer:+$'\n\n'}${TELEGRAM_NOTIFY_MENTIONS}"

    if [[ -n "$error_output" ]]; then
        # Size the block so the finished message (with footer) stays under
        # Telegram's limit; the final safety truncation must never slice a tag.
        local block budget=$TN_ERROR_BLOCK_MAX_CHARS
        local overhead=$((${#message} + ${#footer} + 100))
        if ((TN_TELEGRAM_MAX_CHARS - overhead < budget)); then
            budget=$((TN_TELEGRAM_MAX_CHARS - overhead))
        fi
        ((budget < 0)) && budget=0
        if ((budget > 0)); then
            block=$(tn_truncate "$error_output" "$budget")
            message+=$'\n\n'"❌ <b>Error Output:</b>"$'\n'"<pre>$(tn_html_escape "$block")</pre>"
        fi
    fi
    [[ -n "$footer" ]] && message+=$'\n\n'"$footer"
    printf '%s' "$message"
}

# ---------------------------------------------------------------------------
# Telegram delivery
# ---------------------------------------------------------------------------

tn_bot_token() {
    local token_var="${TELEGRAM_NOTIFY_BOT_TOKEN_VAR:-TELEGRAM_BOT_TOKEN}"
    printf '%s' "${!token_var:-}"
}

tn_chat_id() {
    local chat_id="${TELEGRAM_NOTIFY_CHAT_ID:-}"
    printf '%s' "${chat_id:-${TELEGRAM_CHAT_ID:-}}"
}

# Run a Telegram Bot API call: $1 method, remaining args are curl data flags.
# Prints the response body; returns non-zero unless HTTP 200 + "ok":true.
tn_telegram_call() {
    local method="$1"
    shift
    local api_base="${TELEGRAM_NOTIFY_API_BASE:-https://api.telegram.org}"
    local body_file http_code body
    body_file=$(mktemp)
    http_code=$(curl -sS --max-time "$TN_CURL_TIMEOUT" -o "$body_file" -w '%{http_code}' -X POST \
        "${api_base}/bot$(tn_bot_token)/${method}" "$@")
    local curl_rc=$?
    body=$(cat "$body_file" 2>/dev/null)
    rm -f "$body_file"
    printf '%s' "$body"
    if [[ $curl_rc -eq 0 && "$http_code" == "200" ]] && grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' <<<"$body"; then
        return 0
    fi
    tn_log "ERROR: Telegram ${method} failed (curl rc=${curl_rc}, http=${http_code:-n/a})"
    tn_log "Response: $(tn_truncate "${body:-<empty>}" 300)"
    return 1
}

# POST the message to the Telegram Bot API. Returns non-zero on any failure.
tn_send_message() {
    local text="$1"
    local token chat_id
    token=$(tn_bot_token)
    chat_id=$(tn_chat_id)

    if tn_is_true "${TELEGRAM_NOTIFY_DRY_RUN:-false}"; then
        tn_log "dry run — message not sent:"
        printf '%s\n' "$text"
        local kb
        kb=$(tn_inline_keyboard)
        [[ -n "$kb" ]] && tn_is_true "${TELEGRAM_NOTIFY_BUTTONS:-true}" && tn_log "dry run — buttons: ${kb}"
        return 0
    fi
    if [[ -z "$token" ]]; then
        tn_log "ERROR: ${TELEGRAM_NOTIFY_BOT_TOKEN_VAR:-TELEGRAM_BOT_TOKEN} is not set; cannot send notification"
        return 1
    fi
    if [[ -z "$chat_id" ]]; then
        tn_log "ERROR: chat_id is empty and TELEGRAM_CHAT_ID is not set; cannot send notification"
        return 1
    fi

    local args=(
        --data-urlencode "chat_id=${chat_id}"
        --data-urlencode "text=${text}"
        --data-urlencode "parse_mode=HTML"
        --data-urlencode "disable_web_page_preview=true"
    )
    tn_is_true "${TELEGRAM_NOTIFY_SILENT:-false}" && args+=(--data-urlencode "disable_notification=true")
    [[ -n "${TELEGRAM_NOTIFY_THREAD_ID:-}" ]] && args+=(--data-urlencode "message_thread_id=${TELEGRAM_NOTIFY_THREAD_ID}")
    if tn_is_true "${TELEGRAM_NOTIFY_BUTTONS:-true}" && tn_is_true "${TELEGRAM_NOTIFY_INCLUDE_LINKS:-true}"; then
        local kb
        kb=$(tn_inline_keyboard)
        [[ -n "$kb" ]] && args+=(--data-urlencode "reply_markup=${kb}")
    fi

    local response
    response=$(tn_telegram_call sendMessage "${args[@]}") || return 1
    TN_LAST_MESSAGE_ID=$(tn_json_get '.result.message_id' 'result.message_id' <<<"$response")
    return 0
}

# Upload the full failed-step log as a document (attach_log).
tn_send_log_document() {
    [[ -z "$TN_RAW_LOG_FILE" || ! -s "$TN_RAW_LOG_FILE" ]] && return 0
    local chat_id
    chat_id=$(tn_chat_id)
    local name="${CIRCLE_JOB:-job}-${CIRCLE_BUILD_NUM:-0}-failed-step.log"
    local args=(
        -F "chat_id=${chat_id}"
        -F "document=@${TN_RAW_LOG_FILE};filename=${name}"
        -F "caption=Full output of the failed step in ${CIRCLE_JOB:-job} #${CIRCLE_BUILD_NUM:-?}"
        -F "disable_notification=true"
    )
    [[ -n "${TELEGRAM_NOTIFY_THREAD_ID:-}" ]] && args+=(-F "message_thread_id=${TELEGRAM_NOTIFY_THREAD_ID}")
    [[ -n "${TN_LAST_MESSAGE_ID:-}" ]] && args+=(-F "reply_parameters={\"message_id\":${TN_LAST_MESSAGE_ID}}")
    if tn_is_true "${TELEGRAM_NOTIFY_DRY_RUN:-false}"; then
        tn_log "dry run — would attach $(wc -c <"$TN_RAW_LOG_FILE" | tr -d ' ') bytes as ${name}"
        return 0
    fi
    tn_telegram_call sendDocument "${args[@]}" >/dev/null && tn_log "Attached ${name}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

main() {
    tn_log "Preparing ${TELEGRAM_NOTIFY_EVENT:-failure} notification (template: ${TELEGRAM_NOTIFY_TEMPLATE:-basic})"
    local skip_reason
    if ! skip_reason=$(tn_should_send); then
        tn_log "Skipped: ${skip_reason}"
        exit 0
    fi

    local status error_output="" message
    status=$(tn_resolve_status)
    rm -f "${TMPDIR:-/tmp}/telegram_notify_failed_step.log"
    if [[ "$status" == "failure" ]]; then
        error_output=$(tn_fetch_error_output)
        # The fetch ran in a subshell; pick up the log it left behind for attach_log.
        [[ -s "${TMPDIR:-/tmp}/telegram_notify_failed_step.log" ]] && TN_RAW_LOG_FILE="${TMPDIR:-/tmp}/telegram_notify_failed_step.log"
    fi
    TN_DURATION_MS=""
    if tn_is_true "${TELEGRAM_NOTIFY_INCLUDE_DURATION:-true}"; then
        TN_DURATION_MS=$(tn_fetch_job_duration_ms)
    fi
    message=$(tn_build_message "$status" "$error_output")
    message=$(tn_truncate "$message" "$TN_TELEGRAM_MAX_CHARS")

    TN_LAST_MESSAGE_ID=""
    if tn_send_message "$message"; then
        tn_log "Notification sent (${status})"
        if [[ "$status" == "failure" ]] && tn_is_true "${TELEGRAM_NOTIFY_ATTACH_LOG:-false}"; then
            tn_send_log_document
        fi
        exit 0
    fi
    if tn_is_true "${TELEGRAM_NOTIFY_FAIL_ON_ERROR:-false}"; then
        tn_log "Notification failed and fail_on_error is true"
        exit 1
    fi
    tn_log "Notification failed; continuing because fail_on_error is false"
    exit 0
}

if [[ -z "${TELEGRAM_NOTIFY_NO_MAIN:-}" ]]; then
    main "$@"
fi
