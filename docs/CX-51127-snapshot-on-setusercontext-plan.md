# CX-51127 — Send snapshot event on `setUserContext` (mobile plan)

Parent: [CX-51127](https://coralogix.atlassian.net/browse/CX-51127) — origin RUM-121 / BUGV2-6926 (RN escalation).
Platform tickets: CX-52383 (iOS), CX-52384 (Android), CX-52385 (Flutter), CX-52386 (React Native).

## How the browser SDK implemented it (reference)

The browser does **not** emit a new event when `setUserContext` is called. It arms a
one-shot flag, and the **next span of any kind** is promoted to a snapshot event:

1. `libs/browser/src/coralogix-rum.ts:663` — `setUserContext()`:
   ```ts
   getSnapshotManager().shouldTriggerSnapshotContext = true;
   attributesProcessor?.setInternalLabels({ ...; USER_CONTEXT: userContext });
   ```
2. `libs/browser/src/snapshot/snapshotManager.ts:30` — the flag, with the intent comment:
   *"This property is used to prevent inconsistencies between the snapshot data and the user data."*
   It is plain in-memory state (not persisted with the rest of the snapshot state).
3. `libs/browser/src/processors/CoralogixSnapshotSpanProcessor.ts:128-131` — consumed in
   `isSnapshotPrepared()`, which runs on **every** span's `onEnd`, alongside the other
   snapshot triggers (new view, error, recording-start, DOM event, 1-minute throttle):
   ```ts
   if (getSnapshotManager().shouldTriggerSnapshotContext) {
     shouldCreateSnapshot = true;
     getSnapshotManager().shouldTriggerSnapshotContext = false;   // one-shot
   }
   ```
   The promoted span gets `cx_rum.isSnapshotEvent = true` + `cx_rum.snapshot_context` with
   current counters. Note the flag branch does **not** refresh the 1-minute throttle
   timestamp — only "real" triggers do.

Why piggyback instead of eager emission: user data only reaches the backend on events
anyway; the backend refreshes session-level user info from snapshot events. Making the
next event a snapshot is exactly sufficient, and it avoids fabricating a synthetic
event type on the wire.

## Design decision for mobile

**Match the browser: one-shot "pending snapshot" flag, consumed by the next exported
event.** No new event type, no new wire keys — `isSnapshotEvent` / `snapshot_context`
already exist on all platforms.

Ordering nuance the browser gets for free (single-threaded JS) but mobile must handle:
**store the new user context first, then arm the flag.** If the flag is armed first, a
span racing in between becomes a snapshot carrying the *old* user data, defeating the
purpose. With context-first ordering the worst case is one non-snapshot span with new
user data, followed by the snapshot — harmless.

## iOS (CX-52383) — exact steps

Snapshot promotion on iOS lives at export time in
`CxRumBuilder.buildSnapshotContextIfNeeded` (`Coralogix/Sources/Model/CxRumBuilder.swift:138`):
returns `SnapshotContext?`; non-nil makes `CxRumPayloadBuilder.addSnapshotContext`
(`CxRumPayloadBuilder.swift:199`) set `isSnapshotEvent = true` + `snapshot_context`.
Current triggers: error severity, navigation event, 1-minute throttle
(`lastSnapshotEventTime == nil` means "expired" — used by session rotation,
`SessionManager.swift:~345`).

1. **`SessionManager`** (owns the snapshot throttle state already): add a locked
   one-shot flag next to the existing session state, using the established
   lock-guarded accessor pattern:
   ```swift
   private var _pendingSnapshotTrigger = false

   func triggerSnapshotOnNextEvent() {
       sessionLock.lock(); defer { sessionLock.unlock() }
       _pendingSnapshotTrigger = true
   }

   /// One-shot: returns true at most once per arm. Test-and-clear is atomic so
   /// concurrent span exports cannot both consume it.
   func consumePendingSnapshotTrigger() -> Bool {
       sessionLock.lock(); defer { sessionLock.unlock() }
       let pending = _pendingSnapshotTrigger
       _pendingSnapshotTrigger = false
       return pending
   }
   ```
   Clear it in the session-rotation path (`performRotationLocked`) — a fresh session
   already emits its first snapshot via `lastSnapshotEventTime = nil`, so a stale flag
   must not leak across sessions.

2. **`CoralogixRum.setUserContext`** (`Coralogix/Sources/CoralogixRum.swift:270`) —
   context first, then arm:
   ```swift
   public func setUserContext(userContext: UserContext?) {
       guard CoralogixRum.isInitialized else { return }
       self.coralogixExporter?.update(userContext: userContext)
       self.coralogixExporter?.getSessionManager().triggerSnapshotOnNextEvent()
   }
   ```

3. **`CxRumBuilder.buildSnapshotContextIfNeeded`** (`CxRumBuilder.swift:138`) — add the
   flag as a fourth trigger. Consume it **only when a snapshot will actually be built**,
   i.e. read it as part of the condition:
   ```swift
   let userContextChanged = sessionManager.consumePendingSnapshotTrigger()
   if isErrorSeverity || isNavigationEvent || oneMinuteHasPassed || userContextChanged {
       ...existing body unchanged...
   }
   ```
   (`consume...` is unconditional-read like the browser's — because when it returns
   true the branch always emits, consume-on-read == consume-on-emit. Keep
   `lastSnapshotEventTime = Date()` as-is; deviating from the browser's
   "don't refresh throttle" nuance is harmless and simpler.)

4. **No `Keys.swift` changes** — `isSnapshotEvent` / `snapshotContext` already exist
   (`Keys.swift:142,147`).

5. **Scope guard**: only `setUserContext` arms the flag — not `set(labels:)` (browser
   parity: `setLabels` does not touch the flag).

### iOS tests (`CoralogixRumTests`)

- `SessionManager`: `consumePendingSnapshotTrigger` returns false untouched; true
  exactly once after `triggerSnapshotOnNextEvent`; false again after consumption;
  cleared by session rotation.
- `CxRumBuilder`: a plain event (non-error, non-navigation, `lastSnapshotEventTime`
  recent) yields `snapshotContext == nil`; after arming the flag the same event yields
  non-nil with current counters; the following event yields nil again (one-shot).
- Integration-level: `setUserContext` → next exported payload has
  `isSnapshotEvent == true`, `snapshot_context` present, and `user_context` reflects
  the new user (positive, falsifiable assertions on the payload keys).

### Version / changelog

Behavioral fix, no public-API change → **patch** bump via `/bump-version`
(all three podspecs + `Global.sdk`), CHANGELOG entry, README untouched (no API change).

## Android (CX-52384) — exact steps

Android's promotion point is `SnapshotManager.isSnapshotEvent(attributes)`
(`library/.../internal/snapshot/SnapshotManager.kt:26`) with the same three triggers.
`setUserContext` flows `CoralogixRum → SDKManager.setUserContext → sessionManager`
(`SDKManager.kt:78`).

1. `SnapshotManager`: add `@Volatile private var pendingSnapshotTrigger = false` +
   `fun triggerSnapshotOnNextEvent()`. Consume inside `isSnapshotEvent()` as an
   additional trigger.
   **Watch the early-return**: `isSnapshotStateEmpty()` returns `false` before any
   trigger runs when all counters are zero. The pending flag must be honored even
   then (setting user context before any activity is precisely the escalation
   scenario) — check the flag **before** the empty-state guard.
2. `SDKManager.setUserContext`: store context first (existing line), then
   `SnapshotManager.triggerSnapshotOnNextEvent()`.
3. Clear the flag in `SnapshotManager.reset()` (session boundary hygiene).
4. Tests mirror iOS: one-shot semantics, empty-state bypass, payload-level
   `isSnapshotEvent`/`snapshot_context` assertion after `setUserContext`.

## Flutter (CX-52385) / React Native (CX-52386)

No plugin-side logic — verified that all four bridges call the **same public native
`setUserContext`** the flag will be armed in, so the native fix covers them with zero
plugin code changes:

- Flutter iOS: `ios/Classes/CxFlutterPlugin.swift:512` → `coralogixRum?.setUserContext(userContext:)`
- Flutter Android: `manager/FlutterPluginManager.kt:372` → `CoralogixRum.setUserContext(...)`
- RN iOS: `libs/cx-plugin/ios/CxSdk.swift:71` → `coralogixRum?.setUserContext(userContext:)`
- RN Android: `libs/cx-plugin/android/.../CxSdkModule.kt:84` → `CoralogixRum.setUserContext(...)`

The snapshot carrier also works for hybrids: all events (hybrid spans forwarded via
`sendCxSpanData`, plus natively-instrumented network/lifecycle/error events) export
through the native pipeline where the flag is consumed. Work is:

1. Bump the iOS + Android native dependencies to the fixed versions.
2. Verify end-to-end: call `setUserContext` from Dart/JS, observe the next event export
   with `isSnapshotEvent: true` + fresh `user_context` (RN: validate against the
   original RUM-121 scenario).
3. Plugin patch releases.

## Edge cases (accepted, browser parity)

- **Idle app**: if no event ever follows `setUserContext`, no snapshot is sent — but no
  event would have carried the user data either. Identical to browser behavior.
- **`beforeSend` drops the carrier event** *(iOS: closed after PR review)*: on iOS the
  consume now happens only after the session-attributes drop guard, and a native
  `beforeSend` drop re-arms the trigger (`CxRum.consumedPendingSnapshotTrigger` →
  `CxSpan.getDictionary()` drop branch), following the same compensation pattern as the
  error-counter undo. Hybrid JS `beforeSend` drops and upload failures remain
  browser-parity best-effort. Android keeps the browser-parity behavior.
- **Sampled-out session**: on iOS the export gate drops spans before conversion, so the
  flag stays armed until a sampled-in span consumes it; verify the consume happens
  after the sampling gate (it does — `CxRumBuilder` runs during conversion).
- **Repeated `setUserContext` calls**: flag is idempotent; N calls before the next event
  produce one snapshot, which is correct (the snapshot carries the latest context).
