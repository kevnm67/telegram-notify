#!/usr/bin/env bash
# Per-template assertions for the integration jobs. Each call inspects the
# mock Telegram log and then truncates it so the next template starts clean.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PATH="${MOCK_TELEGRAM_LOG:-/tmp/telegram-mock.jsonl}"
A="${HERE}/assert-mock-received.sh"

case "${1:?template}" in
basic)
    # message + attached document (the document is the last call)
    "$A" --count 2 --field method=sendDocument --field-contains filename=failed-step.log
    python3 - "$LOG_PATH" <<'PY'
import json, sys
first = json.loads(open(sys.argv[1]).readline())
text = first["text"]
for needle in ("CI Failure", "Error Output", "&lt;simulated&gt; build error", "Duration:</b> 2m 13s", '<a href="https://github.com/'):
    assert needle in text, "missing: %s\n%s" % (needle, text)
assert "inline_keyboard" in first.get("reply_markup", ""), "buttons missing"
print("basic: PASS")
PY
    ;;
test_summary)
    "$A" --count 1 --contains "🧪 <b>Tests:</b> ❌ 1 passed · 1 failed · 1 skipped · 3 total" \
        --contains "suite.Login › rejects &lt;empty&gt; password" --contains "AssertionError: expected 401" \
        --contains "Error Output"
    ;;
insights)
    "$A" --count 1 --contains "📈 <b>Insights</b> <i>(live_test · last 30 days)</i>" \
        --contains "Success rate: <b>94%</b> (1/16 failed)" --contains "Duration p95: 4m 05s" \
        --contains "MTTR: 12m 34s" --contains "Flaky tests: 2"
    ;;
ai_summary)
    "$A" --count 1 --contains "🤖 <b>AI analysis</b>" --contains "aborted make." \
        --contains "🛠 <b>Likely fix:</b>" --contains "📋 <b>Prompt to fix (copy):</b>" \
        --contains "<pre>In this repo the CircleCI job failed" --contains "&lt;simulated&gt;"
    ;;
custom)
    "$A" --count 1 --contains "<b>integration_test_templates</b> on " --field parse_mode=HTML
    python3 - "$LOG_PATH" <<'PY'
import json, sys
last = json.loads(open(sys.argv[1]).readlines()[-1])
assert "reply_markup" not in last, "buttons should be off"
assert "{{" not in last["text"], "unreplaced placeholder"
print("custom: PASS")
PY
    ;;
filtered)
    "$A" --count 0
    ;;
*)
    echo "unknown template $1" >&2
    exit 2
    ;;
esac
: >"$LOG_PATH"
