#!/usr/bin/env bash
# tvOS end-to-end smoke: builds DemoAppTvOS, launches it on an Apple TV simulator with
# --cx-smoke (which fires every menu action without the remote), then asks the
# schema-validator to check every log of that session.
#
# Passes only when the validator holds logs for the session, every log batch was
# accepted, and the session covers each type in REQUIRED_TYPES — so a payload the
# `tv` schema rejects, or a tvOS instrumentation that silently stops sending, fails.
#
# Reads PROXY_URL from Example/envs.swift (CI generates it in setup-demo-app).
#
# CI knobs (all optional):
#   CX_TVOS_SIM_UDID      simulator to use; defaults to the first available Apple TV
#                         on the newest installed tvOS runtime.
#   CX_TVOS_DERIVED_DATA  DerivedData path; defaults to a temp dir.
#   CX_TVOS_WAIT_SECONDS  how long to poll the validator for the session (default 120).
#
# Exit codes:
#   0 — every log valid and every required type present
#   1 — the validator rejected a log, or a required type is missing
#   2 — infra failure (no simulator, build, launch, validator unreachable)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/Example"
DERIVED_DATA="${CX_TVOS_DERIVED_DATA:-${TMPDIR:-/tmp}/cx-tvos-smoke-dd}"
WAIT_SECONDS="${CX_TVOS_WAIT_SECONDS:-120}"
XCODE_LOG="${TMPDIR:-/tmp}/cx-tvos-smoke-xcode.log"
APP_LOG="${TMPDIR:-/tmp}/cx-tvos-smoke-app.log"
RESULT_JSON="${TMPDIR:-/tmp}/cx-tvos-smoke-validate.json"
BUNDLE_ID="com.coralogix.DemoAppTvOS"
REQUIRED_TYPES=(network-request error log)

infra() { echo "::error::tvOS smoke infra failure: $*" >&2; exit 2; }

PROXY_URL=$(sed -nE 's/^[[:space:]]*case PROXY_URL = "([^"]+)".*/\1/p' "$EXAMPLE_DIR/envs.swift" 2>/dev/null)
[ -n "$PROXY_URL" ] || infra "no PROXY_URL in Example/envs.swift"

UDID="${CX_TVOS_SIM_UDID:-}"
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices available -j | jq -r '
    .devices | to_entries
    | map(select(.key | test("tvOS")))
    | sort_by(.key | capture("tvOS-(?<v>[0-9-]+)").v | split("-") | map(tonumber))
    | reverse | map(.value[]) | map(select(.name | startswith("Apple TV")))
    | first | .udid // empty')
fi
[ -n "$UDID" ] || infra "no available Apple TV simulator"
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
echo "Session: $SESSION_ID"

# Poll until every required type has reached the validator, then judge the whole session.
DEADLINE=$(( $(date +%s) + WAIT_SECONDS ))
while :; do
  if curl -sf --max-time 30 "$PROXY_URL/validate/$SESSION_ID" -o "$RESULT_JSON" \
     && jq -e 'type == "array"' "$RESULT_JSON" >/dev/null 2>&1; then
    MISSING=$(jq -r --argjson req "$(printf '%s\n' "${REQUIRED_TYPES[@]}" | jq -R . | jq -s .)" '
      [.[].logs[]?.text.cx_rum.event_context.type] as $seen
      | $req - $seen | join(" ")' "$RESULT_JSON")
    [ -z "$MISSING" ] && break
  fi
  [ "$(date +%s)" -ge "$DEADLINE" ] && break
  sleep 5
done

[ -s "$RESULT_JSON" ] && jq -e 'type == "array"' "$RESULT_JSON" >/dev/null 2>&1 \
  || infra "validator returned nothing usable for $PROXY_URL/validate/$SESSION_ID"

BATCHES=$(jq 'length' "$RESULT_JSON")
LOGS=$(jq '[.[].logs[]?] | length' "$RESULT_JSON")
echo "Validator holds $LOGS logs in $BATCHES batches; types: $(jq -r '[.[].logs[]?.text.cx_rum.event_context.type] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$RESULT_JSON")"

FAILED=0
REJECTED=$(jq -r '.[] | select(.validationResult.statusCode != 200) | .validationResult.message | if type == "array" then .[] else . end' "$RESULT_JSON")
if [ -n "$REJECTED" ]; then
  echo "::error::schema-validator rejected tvOS logs:"
  echo "$REJECTED" | sed 's/^/  /'
  FAILED=1
fi
if [ -n "${MISSING:-}" ]; then
  echo "::error::no '$MISSING' event reached the validator within ${WAIT_SECONDS}s"
  FAILED=1
fi

[ "$FAILED" -eq 0 ] && echo "✅ tvOS session $SESSION_ID passed schema validation"
exit "$FAILED"
