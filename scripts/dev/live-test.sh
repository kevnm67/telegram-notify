#!/usr/bin/env bash
# Trigger the live_test workflow and report every Telegram step's output.
#
# The pipeline runs the *published* kevnm67/telegram-notify@dev:alpha orb against
# the real Telegram, CircleCI and Anthropic APIs (context ci_notify), so it only
# proves anything once main has published a dev version.
#
# Usage: scripts/dev/live-test.sh [branch]     (branch defaults to main)
#
# The API token is read into a variable and passed to curl through `--config -`
# on stdin: it never appears in argv (visible in `ps`), in a file, or in output.
set -euo pipefail

BRANCH="${1:-main}"
SLUG="gh/kevnm67/telegram-notify"
POLL_SECONDS=15
MAX_POLLS=60

CIRCLE_TOKEN="${CIRCLE_TOKEN:-}"
if [[ -z "$CIRCLE_TOKEN" && -r "${HOME}/.circleci/cli.yml" ]]; then
    CIRCLE_TOKEN="$(sed -n 's/^token:[[:space:]]*//p' "${HOME}/.circleci/cli.yml" | head -1)"
fi
if [[ -z "$CIRCLE_TOKEN" ]]; then
    echo "No CircleCI API token: set CIRCLE_TOKEN or run 'circleci setup'." >&2
    exit 1
fi

# curl reading its options from stdin keeps the token out of the process table.
api() {
    local method="$1" path="$2" body="${3:-}"
    local escaped_token="${CIRCLE_TOKEN//\\/\\\\}"
    escaped_token="${escaped_token//\"/\\\"}"
    {
        printf 'header = "Circle-Token: %s"\n' "$escaped_token"
        printf 'header = "Content-Type: application/json"\n'
        printf 'request = "%s"\n' "$method"
        printf 'silent\nshow-error\nfail\n'
        [[ -n "$body" ]] && printf 'data = "%s"\n' "${body//\"/\\\"}"
        printf 'url = "https://circleci.com/api/v2/%s"\n' "$path"
    } | curl --config -
}

echo "Triggering live_test on ${BRANCH}…"
pipeline="$(api POST "project/${SLUG}/pipeline" \
    "{\"branch\":\"${BRANCH}\",\"parameters\":{\"live_test\":true}}")"
pipeline_id="$(printf '%s' "$pipeline" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
pipeline_num="$(printf '%s' "$pipeline" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')"
[[ -n "$pipeline_id" ]] || { echo "Could not read pipeline id from the trigger response." >&2; exit 1; }
echo "  pipeline ${pipeline_num}: https://app.circleci.com/pipelines/${SLUG}/${pipeline_num}"

for ((i = 0; i < MAX_POLLS; i++)); do
    wf="$(api GET "pipeline/${pipeline_id}/workflow")"
    status="$(printf '%s' "$wf" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    wf_id="$(printf '%s' "$wf" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    case "$status" in
        running | on_hold | "") sleep "$POLL_SECONDS" ;;
        *) break ;;
    esac
done
echo "Workflow ${wf_id:-?} finished: ${status:-unknown}"

jobs="$(api GET "workflow/${wf_id}/job")"
# One job number per line, in declaration order.
printf '%s' "$jobs" | tr ',' '\n' | sed -n 's/.*"job_number"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' |
    while read -r num; do
        echo
        echo "── job ${num} ──────────────────────────────────────────"
        build="$(api GET "../v1.1/project/github/kevnm67/telegram-notify/${num}")"
        printf '%s' "$build" | tr '{' '\n' |
            sed -n 's/.*"output_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            while read -r url; do
                # output_url is pre-signed; it carries no credentials of ours.
                curl -sS "$url" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\(.*\)"[^"]*$/\1/p' |
                    grep -i 'telegram\|Skipped:\|sendMessage' || true
            done
    done

echo
echo "Verify the messages landed in the ci_notify chat, then report pass/fail per template."
