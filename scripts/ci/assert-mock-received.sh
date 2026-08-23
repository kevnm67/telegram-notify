#!/usr/bin/env bash
# Assert what the mock Telegram server received during an integration test.
#
# Usage:
#   assert-mock-received.sh [--count N] [--contains TEXT]... [--field key=value]... [--field-contains key=substr]...
# Counts every recorded call (sendMessage and sendDocument); --contains/--field inspect the last one.
set -euo pipefail

LOG_PATH="${MOCK_TELEGRAM_LOG:-/tmp/telegram-mock.jsonl}"
EXPECT_COUNT=""
CONTAINS=()
FIELDS=()
FIELD_CONTAINS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
    --count)
        EXPECT_COUNT="$2"
        shift
        ;;
    --contains)
        CONTAINS+=("$2")
        shift
        ;;
    --field)
        FIELDS+=("$2")
        shift
        ;;
    --field-contains)
        FIELD_CONTAINS+=("$2")
        shift
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 2
        ;;
    esac
    shift
done

touch "$LOG_PATH"
actual_count=$(wc -l <"$LOG_PATH" | tr -d ' ')
echo "mock log (${actual_count} message(s)):"
cat "$LOG_PATH"

if [[ -n "$EXPECT_COUNT" && "$actual_count" != "$EXPECT_COUNT" ]]; then
    echo "FAIL: expected ${EXPECT_COUNT} message(s), got ${actual_count}" >&2
    exit 1
fi

last_field() {
    tail -n 1 "$LOG_PATH" | python3 -c 'import json,sys; line=sys.stdin.read().strip(); print(json.loads(line).get(sys.argv[1],"") if line else "")' "$1"
}

last_text=$(last_field text)
for needle in "${CONTAINS[@]}"; do
    if [[ "$last_text" != *"$needle"* ]]; then
        echo "FAIL: last message does not contain: ${needle}" >&2
        exit 1
    fi
done

for kv in "${FIELDS[@]}"; do
    key="${kv%%=*}"
    want="${kv#*=}"
    got=$(last_field "$key")
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: field ${key}: expected '${want}', got '${got}'" >&2
        exit 1
    fi
done
for kv in "${FIELD_CONTAINS[@]}"; do
    key="${kv%%=*}"
    want="${kv#*=}"
    got=$(last_field "$key")
    if [[ "$got" != *"$want"* ]]; then
        echo "FAIL: field ${key}: expected to contain '${want}', got '${got}'" >&2
        exit 1
    fi
done
echo "PASS"
