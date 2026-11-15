# CX-54776 — Flush on background should add snapshot context (Mobile)

Epic CX-54776 · children: CX-54778 iOS · CX-54779 Android · CX-54780 Flutter · CX-54781 React Native.

> "We forgot to add snapshot context to one of the events when we are triggering flush when the app is going into the background."

Plan reviewed by three independent agents (iOS + hybrid, Android + hybrid, parity + release); this is the
revised version.

## Scope: only the background event

Only the event emitted **when the app goes to background** is forced to carry a snapshot — the mobile
equivalent of the browser's `visibilitychange → hidden`. Other life-cycle events (`appDidFinishLaunching`,
`appDidBecomeActiveNotification`, `appWillTerminateNotification`, `appDidReceiveMemoryWarningNotification`)
keep the normal rules (error / navigation / 1-minute throttle / pending `setUserContext`). A test pins this.

## Reference — browser SDK

- `CoralogixDOMInstrumentation.ts`: on `visibilitychange` with `document.hidden`, create a `dom` span, then `flush()`.
  The span is enqueued before the flush, so it ships in it.
- `CoralogixSnapshotSpanProcessor.ts`: a `dom` span always gets a snapshot, regardless of the 60 s throttle,
  and resets the snapshot timestamp (restarts the throttle).
- Gated by the DOM instrumentation toggle (on by default); sampling / idle gates still apply.

## Current state

| Platform | Background event | Snapshot today |
|---|---|---|
| Browser | `dom` span (`visibility_state: hidden`) | always |
| iOS 2.23.0 | `life-cycle` span, `event_name = appDidEnterBackgroundNotification` (if `.lifeCycle` installed), then `flush()` in a background task | only if throttle expired / token pending — **the bug** |
| Android 2.27.1 | none — `BackgroundFlushScheduler.onStop` only flushes | whatever span is first in the batch, usually none |
| RN 0.18.0 / Flutter 0.21.0 | no own code — native handles background, flush and snapshot | inherits native |

## iOS — CX-54778 (2.23.0 → 2.23.1)

Change (`Coralogix/Sources/Model/CxRumBuilder.swift`):
- In `build()`, compute `isBackgroundEvent` once: `eventContext.type == .lifeCycle` and
  `LifeCycleContext(otel:).lifeCycleType == Keys.appDidEnterBackgroundNotification.rawValue`.
- Pass it into `buildSnapshotContextIfNeeded` (like `pendingTrigger`) and OR it into the trigger condition.
  Stamps `lastSnapshotEventTime` (browser parity); does not touch the error counter.
- Live session only. Retired-session path stays error / navigation only.
- No new Keys, no wire change, no new event. Hybrid covered automatically (native notification fires in the host process).

Tests (`Tests/CoralogixRumTests`, component · unit):
1. Background life-cycle span inside the throttle window → snapshot present, counters correct, `lastSnapshotEventTime` updated.
2. Other life-cycle types inside the window → no snapshot.
3. Seeded non-zero error count unchanged by the forced snapshot.
4. Pending `setUserContext` token + background span → token consumed once, identity override applied, `consumedSnapshotTrigger` set.
5. Background span on a retired session → no forced snapshot.
6. End-to-end: capturing `SpanUploading` mock; set `lastSnapshotEventTime = Date()` and drain init first (otherwise the
   nil throttle passes the test without the fix); post `didEnterBackgroundNotification` → encoded event has
   `isSnapshotEvent` + `snapshot_context`. Control: `didBecomeActiveNotification` → none.
7. Hybrid: `mobileSDK = .flutter / .reactNative` + `beforeSendCallBack` → batch handed to the callback contains the snapshot.
   Restore `CoralogixRum.mobileSDK` in `tearDown`.

Unchanged, by design (pre-existing, browser parity): no background snapshot when `.lifeCycle` is off, the session
is idle, or sampled out; a `beforeSend` drop of the event loses the snapshot and still stamps the throttle.

Release: `/bump-version` 2.23.1, one CHANGELOG line, no README change. Must reach CocoaPods trunk before 2026-12-02.

## Android — CX-54779 (2.27.1 → 2.27.2, from origin/master)

Dedicated background span, not a "snapshot next event" token (all three reviewers: the token lands on the first
foreground event / next session, breaks the `setUserContext` restore slot, is lost on the hybrid `beforeSend` path).
- `BackgroundFlushScheduler.onStop`, before `flushNow()`: `LifecycleInstrumentation.reportAppBackgrounded()` when
  installed. Never in `SDKManager.flush()` (FlushWorker, RN fatal flush).
- `SnapshotManager.resolveSnapshotEvent`: `isAppBackgroundEvent()` is a natural trigger — bypasses throttle, stamps it,
  no error-count change, bypasses the empty-state guard (iOS has none).
- `life_cycle_context.event_name` value: open — reuse iOS `appDidEnterBackgroundNotification` (recommended) or Android-style name.
- Tests: `SnapshotManagerTest`, `BackgroundFlushSchedulerTest` (emit before flush; none when Lifecycle off; plain flush emits nothing), instrumented `LifecycleInstrumentedTest`, hybrid via `sendEditedSpans`, idle drop.

## React Native — CX-54781 / Flutter — CX-54780 (after native releases)

- No bridge / JS / Dart change.
- RN: `scripts/bump-ios-sdk.sh 2.23.1` + Android pin 2.26.0 → 2.27.2 (brings in 2.27.0 default URL masking → open: 0.19.0 vs 0.18.1). Jest: snapshot fields survive `beforeSend`.
- Flutter: `scripts/bump_ios_sdk.sh` + `scripts/bump_version.sh` (0.21.1), Android pin → 2.27.2. Test: `applyEditable` restores `snapshotContext`.
- E2E in both example apps, with and without `beforeSend`.

## Known limitation → separate follow-up

Hybrid with a JS/Dart `beforeSend`: native flush completes when the batch is handed to the callback, so the background
task ends before `sendBeforeSendData`; the background batch can be delayed or lost. Pre-existing on both platforms.

## Sequencing

1. iOS (this branch) → Android.
2. Native releases (iOS gated on the CocoaPods trunk push).
3. RN and Flutter pin bumps.
