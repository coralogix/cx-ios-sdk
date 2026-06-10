---
description: Verify a code change does what it's supposed to by running the demo app in the iOS simulator and observing behavior. Use after a substantive change, before declaring "done".
argument-hint: <description of what to verify>
---

You are verifying an iOS SDK change end-to-end by running the demo app and observing real behavior. **Verification is runtime observation** — building and running tests is CI's job, not yours here. The evidence is what you see when the SDK is actually executing in the simulator.

## Don't substitute for the real surface

- **Don't just run `xcodebuild test`.** Tests are author-supplied evidence; CI runs them. Re-running them here proves you can run CI, not that the change works at the user-visible surface.
- **Don't import-and-call SDK functions in isolation.** That's a unit test you wrote. The SDK runs inside a host app — go there.
- **Do build the demo app, install it in the iOS simulator, launch it, drive the affected codepath, capture evidence.**

## Find the change

```bash
git log --oneline @{u}..        # commits on this branch (if upstream set)
git diff @{u}.. --stat          # full range
git diff origin/HEAD... --stat  # no upstream: committed vs base
git diff HEAD --stat            # uncommitted: working tree vs HEAD
gh pr diff                      # if in a PR context
```

Read the diff. State the commit count. The user's `$ARGUMENTS` describes what to verify — if it disagrees with the diff, that's a finding.

## Pick a surface

For the iOS SDK, the runtime surfaces are:

| Change reaches | Surface | How to drive |
|---|---|---|
| OTel span generation / export | The proxy URL the demo posts to | Run `DemoAppSwift` or `DemoAppSwiftUI` with `proxyUrl: Envs.PROXY_URL.rawValue` and capture the SDK's debug log via `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.coralogix.rum"'` |
| UI instrumentation (taps, gestures, swizzling) | Demo app UI | Tap / scroll / navigate in the simulator |
| ANR / crash / lifecycle | Demo app process state | Force-quit, background, send memory warning via `xcrun simctl notify_post booted Memory:1` |
| Network instrumentation | Demo app's network calls | Trigger the "Network instrumentation" demo screen, observe outgoing spans |
| SessionReplay | Demo app's rendered UI | Enable SR in options, drive through screens, observe SR payloads in console |

If the change is library-only (e.g. an internal helper with no observable surface), say so and **SKIP** rather than running tests as a substitute.

## Get a handle

```bash
# 1. Boot simulator
xcrun simctl boot "iPhone 17" 2>&1

# 2. Build
cd /Users/tomer.haryoffi/Development/cx-ios-sdk/Example
xcodebuild -workspace DemoApp.xcworkspace -scheme DemoAppSwift -destination "platform=iOS Simulator,name=iPhone 17" -configuration Debug build

# 3. Locate the .app
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -name DemoAppSwift.app -path '*iphonesimulator*' | head -1)"

# 4. Bundle ID
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")

# 5. Start log capture (in background) — narrow by subsystem
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.coralogix.rum"' --style ndjson --level debug > /tmp/cx-verify.log &
LOG_PID=$!

# 6. Install + launch
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted "$BUNDLE_ID"
```

If any of those steps fail, report **BLOCKED** with the exact stopping point.

## Drive the change

Smallest path that makes the changed code execute. Use:
- `xcrun simctl io booted screenshot /tmp/cx-step-N.png` to capture screen state at each step.
- `xcrun simctl io booted screenshot --type=png /tmp/file.png` for after a tap.
- For programmatic taps: `osascript` with `System Events` works marginally for the Simulator window, but iOS touch events are not reliably scriptable without `idb`. If you need to drive UI deeply and `idb` isn't available, say so in findings.

After each step, capture what you observed. Quote the relevant lines from `/tmp/cx-verify.log`. Watch for:
- `[SpanUploader] Backend rejected upload with HTTP …` — blocker
- `[SpanUploader] Network error: …` — flag
- `📤 Sending to Coralogix:` with the payload structure (may be truncated by os_log's 1012-byte buffer — note this if you can't see the full payload)
- Any `🟥` error-level entries

## Probe adjacents

Once the claim verifies, push on it. At least one `🔍` probe:
- Pass an empty / extreme value where the change reads input
- Force-quit and relaunch — does state restore correctly?
- Background and re-foreground the app
- Trigger a memory warning
- Tap rapidly / swipe at the boundary

A passed probe is still a step: `🔍 force-quit + relaunch → view_number restored to 2 as expected, no stale data`.

## Capture and clean up

After driving and probing:
```bash
kill $LOG_PID 2>/dev/null
xcrun simctl terminate booted "$BUNDLE_ID"
```

Keep the log file and any screenshots — they're evidence.

## Report

Use this exact format:

```
## Verification: <one-line what changed>

**Verdict:** PASS | FAIL | BLOCKED | SKIP

**Claim:** <what it's supposed to do — from the diff / args / PR description; note any mismatch>

**Method:** <how you got a handle — cold start or via a /run-* skill; what you built and launched>

### Steps

1. ✅/❌/⚠️/🔍 <what you did to the running app> → <what you observed>
   <evidence: pane capture, response body, screenshot path, log line>

**Screenshot:** </tmp/cx-…png>

### Findings
- ⚠️ <important issue worth interrupting the reviewer for>
- 🔍 <probe result, even if passed>
- <smaller notes / pre-existing breakage / env quirks>
```

**Verdicts:**
- **PASS** — you ran the app, the change did what it should at its surface. Not: tests pass.
- **FAIL** — you ran it and it doesn't. Or the claim disagrees with what the diff says.
- **BLOCKED** — couldn't reach a state where the change is observable (build broke, simulator stuck, missing env). Say exactly where it stopped.
- **SKIP** — no runtime surface exists (e.g. internal helper with no caller wired up yet). One line why.

When in doubt, FAIL. False PASS ships broken code; false FAIL costs one more human look.
