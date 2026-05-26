#!/usr/bin/env bash
# Native-iOS session-replay leak harness end-to-end runner.
#
# Boots the host-side mock proxy server, runs the XCUITest in
# Example/DemoAppUITests (which launches DemoAppSwift with
# --leak-harness so it shows LeakHarnessViewController and scrolls a
# UITableView of magenta sentinels under maskAllTexts), kills the
# server, scans captured frames for magenta pixels, exits with the
# leak count.
#
# Self-contained — vendored tools under tool/leak-harness/. Sentinel
# format and pixel-detection contract are normative in
# docs/session-replay-shared.md in the cx-flutter-plugin repo; the
# implementation is copied here so this repo runs without depending on
# any sibling-repo layout.
#
# Exit codes:
#   0 — no leaks
#   1 — at least one frame leaked
#   2 — infra failure (server start, no frames, test build/run, etc.)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$REPO_ROOT/tool/leak-harness"
EXAMPLE_DIR="$REPO_ROOT/Example"
LOG_FILE="${TMPDIR:-/tmp}/cx-leak-harness-ios-server.log"
XCODE_LOG="${TMPDIR:-/tmp}/cx-leak-harness-ios-xcode.log"
APP_LOG="${TMPDIR:-/tmp}/cx-leak-harness-ios-app.log"

# Pick the destination simulator. Resolve the booted sim's UDID so
# xcodebuild reuses it instead of cloning a fresh one (Xcode 16+
# clones by default when -destination matches only by name). Override
# the whole string via CX_IOS_DESTINATION, or pick a specific UDID
# via CX_IOS_SIM_UDID.
if [ -n "${CX_IOS_DESTINATION:-}" ]; then
  IOS_DESTINATION="$CX_IOS_DESTINATION"
elif [ -n "${CX_IOS_SIM_UDID:-}" ]; then
  IOS_DESTINATION="platform=iOS Simulator,id=$CX_IOS_SIM_UDID"
else
  BOOTED_UDID=$(xcrun simctl list devices booted 2>/dev/null | grep "Booted" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\) \(Booted\).*/\1/')
  if [ -n "$BOOTED_UDID" ]; then
    IOS_DESTINATION="platform=iOS Simulator,id=$BOOTED_UDID"
    echo "[leak-harness] Using booted simulator UDID: $BOOTED_UDID"
  else
    echo "[leak-harness] FATAL: no booted simulator. Boot one with:" >&2
    echo "  flutter emulators --launch apple_ios_simulator" >&2
    echo "Or override with CX_IOS_SIM_UDID=<udid> or CX_IOS_DESTINATION='platform=iOS Simulator,...'" >&2
    exit 2
  fi
fi

if [ ! -d "$HARNESS_DIR" ]; then
  echo "[leak-harness] FATAL: vendored harness not found at $HARNESS_DIR" >&2
  exit 2
fi

# Ensure Dart deps are installed
if [ ! -d "$HARNESS_DIR/.dart_tool" ]; then
  echo "[leak-harness] First-run pub get…"
  (cd "$HARNESS_DIR" && dart pub get) || exit 2
fi

# ── 1. Start mock server ────────────────────────────────────────────────────
SERVER_PID=""
LOG_STREAM_PID=""
cleanup() {
  if [ -n "${LOG_STREAM_PID:-}" ]; then
    kill -TERM "$LOG_STREAM_PID" 2>/dev/null || true
  fi
  if [ -n "${SERVER_PID:-}" ]; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

rm -f "$LOG_FILE"
cd "$HARNESS_DIR"
dart run mock_upload_server.dart 0 > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 40); do
  if grep -q '^\[mock-upload\] ready' "$LOG_FILE" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
if ! grep -q '^\[mock-upload\] ready' "$LOG_FILE" 2>/dev/null; then
  echo "[leak-harness] FATAL: mock server failed to start within 20s" >&2
  tail -40 "$LOG_FILE" >&2
  exit 2
fi

PORT=$(grep '^CX_MOCK_PORT=' "$LOG_FILE" | head -1 | sed 's/^CX_MOCK_PORT=//')
DIR=$(grep '^CX_MOCK_DIR=' "$LOG_FILE" | head -1 | sed 's/^CX_MOCK_DIR=//')
echo "[leak-harness] mock server: port=$PORT dir=$DIR"

# ── 2. Run the XCUITest ─────────────────────────────────────────────────────
# CX_MOCK_PORT is exported so the test process sees it in
# ProcessInfo.environment, then propagates it via XCUIApplication.launchEnvironment.
cd "$EXAMPLE_DIR"

# ── 2a. Capture app NSLog output via the system log ─────────────────────────
# Extract booted UDID so we can stream the sim's log regardless of how
# IOS_DESTINATION was set.
SIM_UDID=$(xcrun simctl list devices booted 2>/dev/null \
  | grep "Booted" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]+)\) \(Booted\).*/\1/')
rm -f "$APP_LOG"
if [ -n "$SIM_UDID" ]; then
  xcrun simctl spawn "$SIM_UDID" log stream \
    --predicate 'process == "DemoAppSwift"' \
    --level debug 2>/dev/null > "$APP_LOG" &
  LOG_STREAM_PID=$!
  echo "[leak-harness] app log stream: PID=$LOG_STREAM_PID → $APP_LOG"
fi

echo "[leak-harness] Running XCUITest on ${IOS_DESTINATION}..."
rm -f "$XCODE_LOG"
CX_MOCK_PORT="$PORT" TEST_RUNNER_CX_MOCK_PORT="$PORT" xcodebuild \
  -workspace DemoApp.xcworkspace \
  -scheme DemoAppSwift \
  -sdk iphonesimulator \
  -destination "$IOS_DESTINATION" \
  -only-testing:DemoAppUITests/SessionReplayLeakUITests \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  test 2>&1 | tee "$XCODE_LOG" | tail -50
TEST_EXIT=${PIPESTATUS[0]}
echo "[leak-harness] xcodebuild test exit=$TEST_EXIT"

# ── 3. Stop server + scan ───────────────────────────────────────────────────
kill -TERM "$LOG_STREAM_PID" 2>/dev/null || true
LOG_STREAM_PID=""
kill -TERM "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

FRAME_COUNT=$(ls "$DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ')
echo "[leak-harness] captured $FRAME_COUNT frame(s) in $DIR"

if [ "$FRAME_COUNT" -eq 0 ]; then
  echo "[leak-harness] WARNING: 0 frames — harness can't gate without samples" >&2
  echo "[leak-harness] Inspect $LOG_FILE for upload-server traffic"
  exit 2
fi

cd "$HARNESS_DIR"
set +e
dart run pixel_scanner.dart "$DIR"
SCAN_EXIT=$?
set -e

echo ""
echo "[leak-harness] native-iOS summary: dest=$IOS_DESTINATION frames=$FRAME_COUNT scan-exit=$SCAN_EXIT"
echo "[leak-harness] frames dir kept at: $DIR"
echo "[leak-harness] re-scan with: dart run $HARNESS_DIR/pixel_scanner.dart $DIR"
echo "[leak-harness] xcode log (SR-perf): grep '\[SR-perf\]' $XCODE_LOG"
echo "[leak-harness] app log  (SR-perf): grep 'SR-perf' $APP_LOG"

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "[leak-harness] FAIL: xcodebuild exited $TEST_EXIT" >&2
  exit "$TEST_EXIT"
fi
exit $SCAN_EXIT
