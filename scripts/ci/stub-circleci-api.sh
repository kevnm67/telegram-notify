#!/usr/bin/env bash
# Serve canned CircleCI v1.1/v2 and Anthropic API responses for integration
# tests (static files via python3 http.server). Usage: start in the
# background, then point the orb at:
#   TELEGRAM_NOTIFY_CIRCLECI_API_BASE=http://127.0.0.1:8090/api/v1.1
#   TELEGRAM_NOTIFY_CIRCLECI_API_V2_BASE=http://127.0.0.1:8090/api/v2
#   TELEGRAM_NOTIFY_ANTHROPIC_API_BASE=http://127.0.0.1:8091
set -euo pipefail

PORT="${STUB_PORT:-8090}"
ROOT="${STUB_ROOT:-/tmp/circleci-stub}"
ORG="${CIRCLE_PROJECT_USERNAME:-org}"
REPO="${CIRCLE_PROJECT_REPONAME:-repo}"
NUM="${CIRCLE_BUILD_NUM:-1}"

rm -rf "$ROOT"
v1="$ROOT/api/v1.1/project/github/${ORG}/${REPO}"
v2="$ROOT/api/v2/project/gh/${ORG}/${REPO}"
mkdir -p "$v1" "$v2/job" "$v2/${NUM}" "$ROOT/api/v2/workflow" "$ROOT/api/v2/insights/gh/${ORG}/${REPO}/workflows/live_test"

cat >"$v1/${NUM}" <<JSON
{"steps":[{"actions":[{"failed":true,"status":"failed","output_url":"http://127.0.0.1:${PORT}/step-output.json"}]}]}
JSON
cat >"$ROOT/step-output.json" <<'JSON'
[{"message":"compiling...\nerror: <simulated> build error\nmake: *** [all] Error 1\n"}]
JSON
cat >"$v2/job/${NUM}" <<'JSON'
{"duration":133000,"status":"failed"}
JSON
cat >"$v2/${NUM}/tests" <<'JSON'
{"items":[
 {"classname":"suite.Login","name":"accepts valid password","result":"success","run_time":0.4,"message":""},
 {"classname":"suite.Login","name":"rejects <empty> password","result":"failure","run_time":0.9,"message":"AssertionError: expected 401\ngot 200"},
 {"classname":"suite.Cart","name":"totals","result":"skipped","run_time":0,"message":""}
],"next_page_token":null}
JSON
cat >"$ROOT/api/v2/workflow/${CIRCLE_WORKFLOW_ID:-wf}" <<'JSON'
{"name":"live_test"}
JSON
cat >"$ROOT/api/v2/insights/gh/${ORG}/${REPO}/workflows/live_test/summary" <<'JSON'
{"metrics":{"success_rate":0.9375,"total_runs":16,"failed_runs":1,"mttr":754,"throughput":2.3,"duration_metrics":{"p95":245.5}}}
JSON
cat >"$ROOT/api/v2/insights/gh/${ORG}/${REPO}/flaky-tests" <<'JSON'
{"total_flaky_tests":2,"flaky_tests":[]}
JSON
mkdir -p "$ROOT/v1"
cat >"$ROOT/v1/messages" <<'JSON'
{"content":[{"type":"text","text":"SUMMARY: The build failed because <simulated> build error aborted make.\nFIX: Fix the simulated error in the Makefile target all.\nPROMPT: In this repo the CircleCI job failed with 'error: <simulated> build error' during make all; find the cause and fix it, then add a regression test."}]}
JSON

# python http.server only answers GET; the stub proxies POST/queries to GET paths.
cat >"$ROOT/server.py" <<'PY'
import os, sys
from http.server import SimpleHTTPRequestHandler, HTTPServer
class H(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        return SimpleHTTPRequestHandler.translate_path(self, path.split("?")[0])
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.do_GET()
    def log_message(self, fmt, *args):
        sys.stderr.write("[stub %s] %s\n" % (os.environ.get("STUB_PORT", "?"), fmt % args))
os.chdir(sys.argv[1])
HTTPServer(("127.0.0.1", int(sys.argv[2])), H).serve_forever()
PY
echo "[stub] serving ${ROOT} on :${PORT} (and :$((PORT + 1)) for Anthropic)"
python3 "$ROOT/server.py" "$ROOT" "$PORT" &
STUB_PORT=$((PORT + 1)) python3 "$ROOT/server.py" "$ROOT" "$((PORT + 1))" &
wait
