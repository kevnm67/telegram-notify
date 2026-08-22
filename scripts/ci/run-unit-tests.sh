#!/usr/bin/env bash
# Run the bats unit-suite for the orb scripts, optionally under kcov to
# produce Cobertura XML (coverage/bats/cobertura.xml) for qlty.
#
# Usage: ./scripts/ci/run-unit-tests.sh [--coverage] [--junit-dir <dir>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COVERAGE=false
JUNIT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
    --coverage) COVERAGE=true ;;
    --junit-dir)
        JUNIT_DIR="$2"
        shift
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 2
        ;;
    esac
    shift
done

command -v bats >/dev/null || {
    echo "bats is required (brew install bats-core, or ./scripts/ci/install-test-tools.sh)" >&2
    exit 1
}

bats_args=(--print-output-on-failure "${REPO_ROOT}/tests")
if [[ -n "$JUNIT_DIR" ]]; then
    mkdir -p "$JUNIT_DIR"
    bats_args+=(--report-formatter junit --output "$JUNIT_DIR")
fi

cd "$REPO_ROOT"
if [[ "$COVERAGE" == "true" ]]; then
    command -v kcov >/dev/null || {
        echo "kcov is required for --coverage (./scripts/ci/install-test-tools.sh)" >&2
        exit 1
    }
    rm -rf "${REPO_ROOT}/coverage"
    kcov --include-path="${REPO_ROOT}/src/scripts" --bash-parser="$(command -v bash)" \
        "${REPO_ROOT}/coverage" bats "${bats_args[@]}"
    python3 - "${REPO_ROOT}/coverage/bats/coverage.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
print(f"Total line coverage: {report['percent_covered']}%")
for entry in report.get("files", []):
    print(f"  {entry['file']}: {entry['percent_covered']}%")
PY
else
    bats "${bats_args[@]}"
fi
