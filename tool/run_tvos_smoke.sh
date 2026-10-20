#!/usr/bin/env bash
# tvOS end-to-end smoke: builds DemoAppTvOS, launches it on an Apple TV simulator with
# --cx-smoke (which fires every menu action without the remote), then asks the
# schema-validator to check every log of that session.
#
# Passes only when the validator holds logs for the session, every log batch was
# accepted, every log carries the tvOS identity, and the session covers each type in
# REQUIRED_TYPES — so a payload the `tv` schema rejects, a log sent as mobile, or a tvOS
# instrumentation that silently stops sending, fails.
#
# Reads PROXY_URL from Example/envs.swift (CI generates it in setup-demo-app).
#
# CI knobs (all optional):
#   CX_TVOS_SIM_UDID      simulator to use; defaults to an Apple TV on the runtime matching
#                         the selected Xcode's tvOS SDK (else the newest one not newer than
#                         it — a runtime newer than the SDK fails at launch).
#   CX_TVOS_DERIVED_DATA  DerivedData path; defaults to a temp dir.
#   CX_TVOS_WAIT_SECONDS  how long to poll the validator for the session (default 120).
#
# Exit codes:
#   0 — every log valid and every required type present
#   1 — the validator rejected a log, or a log lacks the tvOS identity
#   2 — infra failure (no simulator, build, launch, validator unreachable or holding no
#       logs for the session — e.g. a cold-starting validator that dropped the uploads),
#       or a required type is missing while every log that arrived was accepted

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/Example"
DERIVED_DATA="${CX_TVOS_DERIVED_DATA:-${TMPDIR:-/tmp}/cx-tvos-smoke-dd}"
WAIT_SECONDS="${CX_TVOS_WAIT_SECONDS:-120}"
XCODE_LOG="${TMPDIR:-/tmp}/cx-tvos-smoke-xcode.log"
APP_LOG="${TMPDIR:-/tmp}/cx-tvos-smoke-app.log"
RESULT_JSON="${TMPDIR:-/tmp}/cx-tvos-smoke-validate.json"
BUNDLE_ID="com.coralogix.DemoAppTvOS"
# mobile-vitals carries tv_vitals_context; the demo's cold-start detector emits one per launch.
REQUIRED_TYPES=(network-request error log mobile-vitals user-interaction)

infra() { echo "::error::tvOS smoke infra failure: $*" >&2; exit 2; }

# A result left by an earlier run must never be judged as this session's.
rm -f "$RESULT_JSON"

PROXY_URL=$(sed -nE 's/^[[:space:]]*case PROXY_URL = "([^"]+)".*/\1/p' "$EXAMPLE_DIR/envs.swift" 2>/dev/null)
[ -n "$PROXY_URL" ] || infra "no PROXY_URL in Example/envs.swift"

UDID="${CX_TVOS_SIM_UDID:-}"
if [ -z "$UDID" ]; then
  SDK_VERSION=$(xcrun --sdk appletvsimulator --show-sdk-version 2>/dev/null)
  [ -n "$SDK_VERSION" ] || infra "the selected Xcode has no tvOS Simulator SDK"
  PICK=$(xcrun simctl list devices available -j | jq -r \
    --argjson sdk "[$(echo "$SDK_VERSION" | tr '.' ',')]" '
    .devices | to_entries
    | map(select(.key | test("tvOS-[0-9-]+$"))
          | {v: (.key | capture("tvOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber)),
             tv: (.value | map(select(.name | startswith("Apple TV"))))})
    | map(select((.tv | length) > 0 and .v <= $sdk))
    | sort_by(.v) | last // empty
    | "\(.v | map(tostring) | join(".")) \(.tv[0].udid)"')
  [ -n "$PICK" ] || infra "no Apple TV simulator on a runtime <= tvOS SDK $SDK_VERSION"
  RUNTIME=${PICK% *}; UDID=${PICK#* }
  [ "$RUNTIME" = "$SDK_VERSION" ] \
    || echo "::warning::no tvOS $SDK_VERSION runtime (the SDK's); using tvOS $RUNTIME"
fi
echo "Apple TV simulator: $UDID"

echo "Building DemoAppTvOS…"
xcodebuild build \
  -workspace "$EXAMPLE_DIR/DemoApp.xcworkspace" \
  -scheme DemoAppTvOS \
  -destination "platform=tvOS Simulator,id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  COMPILER_INDEX_STORE_ENABLE=NO > "$XCODE_LOG" 2>&1 \
  || { grep -E "error:" "$XCODE_LOG" | sort -u | head -20 >&2; infra "build failed (log: $XCODE_LOG)"; }

APP=$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -name DemoAppTvOS.app -path '*appletvsimulator*' | head -1)
[ -n "$APP" ] || infra "built app not found under $DERIVED_DATA"

# The validator is a free-tier host that sleeps when idle, and the app uploads ~2s after
# launch. Wake it first, so a cold start can't drop the session's first batches.
VALIDATOR_UP=0
for _ in $(seq 1 18); do
  curl -s -o /dev/null --max-time 10 "$PROXY_URL/validate/warmup" && { VALIDATOR_UP=1; break; }
  sleep 5
done
[ "$VALIDATOR_UP" -eq 1 ] || infra "validator at $PROXY_URL did not respond within 90s"

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || infra "simulator did not boot"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP" || infra "install failed"

: > "$APP_LOG"
xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" --cx-smoke > "$APP_LOG" 2>&1 &
LAUNCH_PID=$!
trap 'kill $LAUNCH_PID 2>/dev/null; xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1' EXIT

SESSION_ID=""
for _ in $(seq 1 60); do
  SESSION_ID=$(grep -oE "CX_SESSION_ID=[0-9a-f-]{36}" "$APP_LOG" | head -1 | cut -d= -f2)
  [ -n "$SESSION_ID" ] && grep -q "CX_SMOKE_ACTIONS_SENT" "$APP_LOG" && break
  sleep 1
done
[ -n "$SESSION_ID" ] || { tail -20 "$APP_LOG" >&2; infra "app never reported a session id"; }
grep -q "CX_SMOKE_ACTIONS_SENT" "$APP_LOG" \
  || { tail -20 "$APP_LOG" >&2; infra "app never finished the smoke actions"; }
echo "Session: $SESSION_ID"

# Poll until every required type has arrived AND the log count has held for two more
# polls: batches keep flushing after the first ones, and the whole session is judged.
REQ_JSON=$(printf '%s\n' "${REQUIRED_TYPES[@]}" | jq -R . | jq -s .)
DEADLINE=$(( $(date +%s) + WAIT_SECONDS ))
LAST_COUNT=-1
STABLE_POLLS=0
while :; do
  if curl -sf --max-time 30 "$PROXY_URL/validate/$SESSION_ID" -o "$RESULT_JSON.tmp" \
     && jq -e 'type == "array"' "$RESULT_JSON.tmp" >/dev/null 2>&1; then
    mv "$RESULT_JSON.tmp" "$RESULT_JSON"
    MISSING=$(jq -r --argjson req "$REQ_JSON" '
      [.[].logs[]?.text.cx_rum.event_context.type] as $seen
      | $req - $seen | join(" ")' "$RESULT_JSON")
    COUNT=$(jq '[.[].logs[]?] | length' "$RESULT_JSON")
    if [ -z "$MISSING" ] && [ "$COUNT" -eq "$LAST_COUNT" ]; then
      STABLE_POLLS=$((STABLE_POLLS + 1))
    else
      STABLE_POLLS=0
    fi
    LAST_COUNT=$COUNT
    [ "$STABLE_POLLS" -ge 2 ] && break
  fi
  [ "$(date +%s)" -ge "$DEADLINE" ] && break
  sleep 5
done

[ -s "$RESULT_JSON" ] || infra "validator returned nothing usable for $PROXY_URL/validate/$SESSION_ID"

BATCHES=$(jq 'length' "$RESULT_JSON")
LOGS=$(jq '[.[].logs[]?] | length' "$RESULT_JSON")
# Zero logs means nothing reached the validator at all (down, cold start, network) —
# infrastructure, not a schema verdict. A partial session still gets judged below.
[ "$LOGS" -gt 0 ] || infra "validator holds no logs for session $SESSION_ID"
echo "Validator holds $LOGS logs in $BATCHES batches; types: $(jq -r '[.[].logs[]?.text.cx_rum.event_context.type] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$RESULT_JSON")"

FAILED=0
REJECTED=$(jq -r '.[] | select(.validationResult.statusCode != 200) | .validationResult.message | if type == "array" then .[] else . end' "$RESULT_JSON")
if [ -n "$REJECTED" ]; then
  echo "::error::schema-validator rejected tvOS logs:"
  echo "$REJECTED" | sed 's/^/  /'
  FAILED=1
fi
# Every log must carry the tvOS identity end to end, independent of what the validator's
# schema happens to allow: the platform, the SDK object's os, and the device os.
NOT_TV=$(jq -r '[.[].logs[]?.text.cx_rum
  | select(.platform != "tv" or .tv_sdk.os != "tvos" or .device_context.os != "tvos"
           or has("mobile_sdk") or has("mobile_vitals_context"))
  | .event_context.type] | join(" ")' "$RESULT_JSON")
if [ -n "$NOT_TV" ]; then
  echo "::error::logs without the tvOS identity (platform tv, tv_sdk/device os tvos, no mobile_* keys): $NOT_TV"
  FAILED=1
fi
if [ -n "${MISSING:-}" ]; then
  MISSING_MSG="no '$MISSING' event reached the validator within ${WAIT_SECONDS}s"
  # Everything that did arrive was accepted, so a gap is more likely a dropped batch
  # (cold validator, timed-out upload) than a schema verdict: let the workflow retry.
  [ "$FAILED" -eq 0 ] && infra "$MISSING_MSG"
  echo "::error::$MISSING_MSG"
fi

[ "$FAILED" -eq 0 ] && echo "✅ tvOS session $SESSION_ID passed schema validation"
exit "$FAILED"
