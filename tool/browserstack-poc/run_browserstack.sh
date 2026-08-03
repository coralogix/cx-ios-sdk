#!/usr/bin/env bash
#
# BrowserStack App Automate (XCUITest) POC runner.
#
# Uploads a pre-built app + test-suite, triggers an XCUITest run, polls until
# it finishes, and prints phase timings so we can compare real-device
# execution against the existing simulator CI (.github/workflows/ui-tests.yml).
#
# Usage:  run_browserstack.sh <app.ipa> <tests.ipa>
#
# Required env:
#   BROWSERSTACK_USERNAME, BROWSERSTACK_ACCESS_KEY
# Optional env:
#   BS_DEVICES  JSON array of devices (default '["iPhone 15-17"]')
#   BS_SHARDS   integer > 0 to split the suite across N parallel devices.
#               0 / unset  = single-device serial run.
#
set -euo pipefail

APP_IPA="${1:?app ipa path required}"
TEST_IPA="${2:?test-suite ipa path required}"
: "${BROWSERSTACK_USERNAME:?set BROWSERSTACK_USERNAME}"
: "${BROWSERSTACK_ACCESS_KEY:?set BROWSERSTACK_ACCESS_KEY}"

AUTH=(-u "${BROWSERSTACK_USERNAME}:${BROWSERSTACK_ACCESS_KEY}")
BASE="https://api-cloud.browserstack.com/app-automate/xcuitest/v2"
DEVICES_JSON="${BS_DEVICES:-[\"iPhone 15-17\"]}"

now() { date +%s; }

echo "::group::Upload app under test"
APP_URL=$(curl -s "${AUTH[@]}" -X POST "$BASE/app" -F "file=@${APP_IPA}" | tee /dev/stderr | jq -r '.app_url')
echo "::endgroup::"
[ "$APP_URL" != "null" ] && [ -n "$APP_URL" ] || { echo "❌ app upload failed"; exit 1; }

echo "::group::Upload test suite"
TEST_URL=$(curl -s "${AUTH[@]}" -X POST "$BASE/test-suite" -F "file=@${TEST_IPA}" | tee /dev/stderr | jq -r '.test_suite_url // .test_url')
echo "::endgroup::"
[ "$TEST_URL" != "null" ] && [ -n "$TEST_URL" ] || { echo "❌ test-suite upload failed"; exit 1; }

# Base payload: single-device serial run of the whole DemoAppUITests target.
PAYLOAD=$(jq -n \
  --arg app "$APP_URL" \
  --arg ts "$TEST_URL" \
  --argjson devices "$DEVICES_JSON" \
  '{app:$app, testSuite:$ts, devices:$devices, deviceLogs:true}')

# Optional sharding: isolate the slow SessionReplayLeakUITests on its own shard
# so the fast classes finish in parallel — this is the whole speed thesis.
if [ "${BS_SHARDS:-0}" -gt 0 ]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --argjson n "${BS_SHARDS}" '. + {shards:{numberOfShards:$n, mapping:[
    {name:"leak",    strategy:"only-testing", values:["DemoAppUITests/SessionReplayLeakUITests"]},
    {name:"network", strategy:"only-testing", values:["DemoAppUITests/NetworkInstrumentationUITests"]},
    {name:"actions", strategy:"only-testing", values:["DemoAppUITests/UserInteractionUITests"]},
    {name:"smoke",   strategy:"only-testing", values:["DemoAppUITests/DemoAppUITests"]}
  ]}}')
fi

echo "::group::Trigger build"
echo "Payload: $PAYLOAD"
SUBMIT=$(now)
RESP=$(curl -s "${AUTH[@]}" -X POST "$BASE/build" -H "Content-Type: application/json" -d "$PAYLOAD")
echo "Response: $RESP"
echo "::endgroup::"

BUILD_ID=$(echo "$RESP" | jq -r '.build_id // .buildId // empty')
[ -n "$BUILD_ID" ] || { echo "❌ no build id in response — cannot proceed"; exit 1; }
echo "🔗 Dashboard: https://app-automate.browserstack.com/builds/$BUILD_ID"

FIRST_RUNNING=""
STATUS="queued"
while :; do
  sleep 15
  ST=$(curl -s "${AUTH[@]}" "$BASE/builds/$BUILD_ID")
  STATUS=$(echo "$ST" | jq -r '.status // "unknown"')
  ELAPSED=$(( $(now) - SUBMIT ))
  echo "[${ELAPSED}s] status=$STATUS"
  if [ "$STATUS" = "running" ] && [ -z "$FIRST_RUNNING" ]; then FIRST_RUNNING=$(now); fi
  case "$STATUS" in
    queued|running) ;;                # keep polling
    *) break ;;                       # done / passed / failed / error / timedout
  esac
done
END=$(now)

echo "===================== TIMING ====================="
echo "  devices        : $DEVICES_JSON"
echo "  shards         : ${BS_SHARDS:-0}"
echo "  queue+setup    : $(( ${FIRST_RUNNING:-$END} - SUBMIT ))s   (submit -> first 'running')"
echo "  execution      : $(( END - ${FIRST_RUNNING:-$SUBMIT} ))s   (running -> finish)"
echo "  TOTAL wall     : $(( END - SUBMIT ))s   (submit -> finish)"
echo "  final status   : $STATUS"
echo "=================================================="
echo "$ST" | jq '{status, duration, devices}' 2>/dev/null || true

# Surface failures to the CI job, but the POC's real output is the timing above.
case "$STATUS" in
  passed|done) exit 0 ;;
  *) echo "⚠️  build did not pass (status=$STATUS) — inspect the dashboard link above"; exit 1 ;;
esac