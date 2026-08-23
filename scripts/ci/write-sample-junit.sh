#!/usr/bin/env bash
# Write a small JUnit report (2 pass, 1 fail, 1 skip) so live_test_summary
# has real test metadata for the CircleCI tests API.
set -euo pipefail
out="${1:-test-results}"
mkdir -p "$out"
cat >"$out/sample.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="live.sample" tests="4" failures="1" skipped="1" time="1.9">
  <testcase classname="live.sample.Login" name="accepts valid password" time="0.4"/>
  <testcase classname="live.sample.Login" name="rejects empty password" time="0.9">
    <failure message="AssertionError: expected 401, got 200">AssertionError: expected 401, got 200
    at login_test.sh:12</failure>
  </testcase>
  <testcase classname="live.sample.Cart" name="computes totals" time="0.6"/>
  <testcase classname="live.sample.Cart" name="applies coupons" time="0">
    <skipped/>
  </testcase>
</testsuite>
XML
echo "wrote $out/sample.xml"
