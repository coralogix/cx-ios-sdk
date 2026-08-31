# Changelog

All notable changes to the Coralogix iOS RUM SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release-mechanics commits (version bumps, podspec/script tweaks, README edits) are
omitted; the focus here is user-facing behavior changes. Tickets are referenced as
`CX-XXXXX` (Jira) or `ALPH-XXXX` (legacy). Pull request numbers are in parentheses.

## [2.18.0] - 2026-08-31

### Added
- `SessionReplay.shared.captureEvent(properties:completion:)` — a completion-based variant of the manual capture call that reports whether a frame actually shipped. The existing synchronous overload returns before the frame is encoded, so its `.success` means "the capture started"; the completion runs once and fails with `skippingEvent` when the frame was dropped as a duplicate, or when Dart had no frame for that moment.

### Changed
- **Session Replay no longer substitutes an earlier frame when Flutter has no frame to give.** When the Dart bitmap provider answers with no bitmap, the whole capture is dropped and the next one proceeds — matching the Android SDK, which drops a frame its provider does not deliver. Previously the SDK composited the last frame Dart had delivered, so a gated or coalesced tick re-uploaded stale pixels under a fresh timestamp: the frame count looked healthy while the replay showed a frozen screen, and a tap marker could be drawn onto a frame whose mask rects no longer matched what was on screen.
- `flutterViewBitmapProvider` now receives `isClick` and `tapTimestampMs` alongside `viewId` and `frameId`, so Dart can hold a tap capture for the next committed frame or answer with no frame when the tap is already too old to draw honestly. Same inputs the Android provider receives. Flutter apps get this through a plugin update; apps that supply their own provider closure need to widen its signature.
- A screenshot event is now emitted only for a frame that actually shipped, and error, navigation and user-interaction events carry `screenshot_id` / `page` only when their frame shipped. Previously every capture stamped its span before the frame was known to exist, so a dropped or deduplicated frame left an event pointing at an image the backend never received — and, because the screenshot index was handed back for reuse, at whichever frame took that index next. The events themselves are unaffected: an interaction or error is still reported when its frame is dropped, just without screenshot attributes, as on Android.

- Spans that carry a screenshot — error, navigation, user-interaction, ANR and screenshot events — now end once the capture resolves rather than immediately, so their end time includes the encode (and, on Flutter, the Dart round-trip). Start times, and therefore RUM attribution, are unchanged: session, user and view are frozen onto the span when it is created. Consumers reading raw `SpanData` through `tracesExporter` will see longer durations on these spans, and a Flutter provider that never answers leaves its span unsent.

### Fixed
- **Captures requested off the main thread now produce a frame instead of being dropped.** Both capture paths walk UIKit before anything else — the native one renders the window hierarchy, the Flutter one locates the FlutterView before asking Dart for pixels — so a capture requested from a background thread failed those main-thread guards and dropped without ever rendering. ANR events are built on the watchdog thread and `reportError` can be called from any thread, so those events silently carried no screenshot. The capture is now moved to the main thread instead.
- **A recording that starts after Session Replay is initialised is no longer unplayable.** Every capture reserves a screenshot slot (`page` / `segmentIndex`) before it runs, and a capture rejected before it reached the encoder kept its slot instead of giving it back. Captures attempted while Session Replay was initialised but not yet recording — or while the SDK was idle, or sampled out — therefore consumed slots that no image ever filled, and the recording began at a page and segment the player had no frames for: every upload returned success and the replay was still broken. Rejected captures now return their slot, so a recording always begins at the first slot no matter how many captures preceded it. Reverting the first slot of a page also steps back to the previous page correctly, instead of stopping at page 1 and stranding the counter a page ahead of the frames that shipped.

## [2.17.0] - 2026-08-26

### Changed
- **Action required if you use `maskText` or `maskAllImages` on UIKit views to keep sensitive text out of user-interaction events.** Session replay's pixel policy no longer redacts interaction text or sets `interaction_context.is_masked_element`. Text that these options previously withheld from `target_element_inner_text` will now be reported in full. To keep withholding it, move the rule to `shouldSendText`, which is evaluated per interaction and returns `false` to redact:

  ```swift
  shouldSendText: { view, text in
      // Previously covered by maskText: ["\\d{3}-\\d{2}-\\d{4}"]
      text.range(of: "\\d{3}-\\d{2}-\\d{4}", options: .regularExpression) == nil
  }
  ```

  This affects **UIKit views only** (`UILabel`, `UITextField`, `UITextView`, `UINavigationBar` titles, `UIImageView`), which are the ones the pixel policy reported geometry for. Text inside SwiftUI content is masked by the OCR and Vision stages, which report no geometry, so it never set the flag and was never redacted in interaction events — nothing changes there, and no action is needed. Note also that `shouldSendText` receives whatever the SDK can read from the touched view, which for SwiftUI content is its `accessibilityLabel` at best, so a rule moved there may not see SwiftUI text at all.

  `shouldSendText` covers **native interactions only** — clicks, scrolls and swipes alike, since it is consulted while the SDK reads the touched view. Interactions reported through `setUserInteraction` from React Native or Flutter never reach it, because their text arrives already resolved in the bridge payload. For those, either have the wrapper send `is_masked: true` for the interaction (Flutter's plugin already does this for taps, so Flutter apps masking in Dart are unaffected), or redact in `beforeSend`, which runs on every path:

  ```swift
  beforeSend: { cxRum in
      var event = cxRum
      if var interaction = event["interaction_context"] as? [String: Any],
         let text = interaction["target_element_inner_text"] as? String,
         text.range(of: "\\d{3}-\\d{2}-\\d{4}", options: .regularExpression) != nil {
          interaction["target_element_inner_text"] = "***"
          event["interaction_context"] = interaction
      }
      return event
  }
  ```

  `cxMask`, SwiftUI `.cxMask()`, password fields and fields with a sensitive `textContentType` are unaffected — they still redact to `***` and still set the flag. Session replay itself is unaffected: these options mask pixels in the recording exactly as before.
- `is_masked_element` and inner-text redaction now reflect deliberate masking alone, matching the Android and Flutter SDKs. The pixel policy decides which pixels a frame hides, which is a different question from whether text may leave the device. Previously, with a wrapper's default `maskAllTexts`, a tap on almost any text reported as masked and shipped `***`.
- The replay's tap marker is unchanged: it is still suppressed over pixels the frame hid, including policy-masked ones. Flag and marker can now legitimately disagree for policy-masked content, as they already do on Android and Flutter.
- Interaction masking no longer depends on session replay being initialized; the verdict resolves from the view hierarchy alone.

## [2.16.0] - 2026-08-18

### Changed
- Sessions not selected by `sessionSampleRate` now keep sending the `traceparent` header on outgoing requests, so distributed traces still correlate with your backend, while none of their events are reported.
- `excludeFromSampling` no longer re-enables an instrumentation you switched off in `instrumentations`, and has no effect on sessions that are sampled in.
- `instrumentations: [.network: false]` now suppresses the `traceparent` header as well as `network-request` events, whatever `traceParentInHeader` is set to.
- `instrumentations: [.network: false]` now also suppresses network events reported from Flutter and React Native through `setNetworkRequestContext`, which previously ignored the setting; leave network instrumentation enabled to keep receiving them.

### Fixed
- Sessions not selected by `sessionSampleRate` now report the SDK initialization event, which was previously missing.

## [2.15.1] - 2026-08-10

### Fixed
- Network requests reported from Flutter and React Native now carry the HTTP reason phrase in `network_request_context.status_text` (e.g. `"OK"`, `"Not Found"`); previously it was always empty on iOS while Android populated it.

## [2.15.0] - 2026-08-09

### Added
- Every user-interaction event now carries `interaction_context.is_masked_element` (always present, boolean): the SDK's own observation that the interaction targeted content session replay masked. `false` also covers "could not resolve" — a hybrid payload with no coordinates, or no frame geometry to test the point against — so the flag under-reports rather than over-reports. Read it in `beforeSend` to implement policies stricter than the default redaction: drop the event, blank the coordinates, or rewrite the target.
- `setUserInteraction` accepts an optional `is_masked` boolean — an authoritative masking verdict from a hybrid wrapper that owns its own masking (the Flutter plugin sets it). It overrides the SDK's geometry resolution and drives both the flag and inner-text redaction.
- `FlutterViewBitmap` gained `maskRects` — the rectangles Dart masked in the delivered bitmap, in Flutter-view-local points. They merge into the captured frame's mask geometry, so tap markers over masked Flutter content are now suppressed on the same terms as native masks. A reused stale bitmap carries the rects of its own frame, never a newer frame's.

### Fixed
- Network requests reported from Flutter and React Native now carry their real measured duration; previously every such request was exported with a constant duration of 1 ms.
- Interactions reported through the hybrid bridge (`setUserInteraction` — React Native, Flutter) are now redacted on the same terms as native taps. Previously the bridge payload's `target_element_inner_text` was copied verbatim, so a masked element's real text shipped in the clear: the redaction only ran on the swizzled native-touch path, which emits no span in hybrid mode. Only the inner text is redacted — identity fields and coordinates are reported as-is (web-SDK parity) — and the masking is resolved from the payload's coordinates against the same frame geometry that suppresses the replay's tap marker, so the metadata cannot contradict the pixels.
- Native tap redaction now also tests the tap point against the frame's mask geometry, closing two documented gaps: text of UIKit views masked by `maskText`/`maskAllImages`, and text under a SwiftUI `.cxMask()` overlay (a sibling, not an ancestor, so the view-tree walk could not see it). Both previously shipped their real text while their pixels and tap marker were masked.

## [2.14.0] - 2026-08-06

### Added
- Buffered spans are now automatically flushed when the app enters the background, ensuring telemetry is uploaded before process suspension. Uses `UIApplication.beginBackgroundTask` to extend the background time window and guarantee completion before the app is terminated.

## [2.13.3] - 2026-08-05

### Fixed
- `setUserContext` now promotes the next exported event to a snapshot event, so the session's user information refreshes immediately instead of waiting for the next error, navigation, or one-minute interval — matching the browser SDK's behavior.
- Masking now applies to everything inside a masked view, not just the view it was set on. Masking a container is enough to cover its contents, including individually tappable subviews.
- Tapping inside a masked area no longer draws a tap marker in session replays, so a recording of a masked keypad no longer reveals which keys were pressed. The frame is still recorded, and interaction events still carry their touch coordinates.
- User interaction events now report `***` for the text of any view inside a masked area. Previously only the masked view itself was redacted, so a tap on a key inside a masked keypad sent the key's label in clear.

### Changed
- Redacted `target_element_inner_text` is now reported as `***` rather than omitted, matching the Android SDK. This affects views rejected by `shouldSendText`, password fields, and fields with a sensitive `textContentType`, which previously sent no `target_element_inner_text` at all.

## [2.13.2] - 2026-07-30

### Fixed
- Fixed events being dropped during a session change when per-session sampling is in use.

## [2.13.1] - 2026-07-28

### Added
- The hybrid `reportError(message:stackTrace:…)` (React Native) and `reportError(message:obfuscatedStackTrace:…)` (Flutter) overloads now accept an optional `labels` dictionary, so a handled error reported through a hybrid bridge can carry per-event labels in the same call — bringing them in line with the native `error:` / `NSError` / `exception:` overloads. Labels are also preserved for crash events recovered on the next launch.

## [2.13.0] - 2026-07-28

### Added
- Every event now carries `session_context.isSessionSampledIn` (read-only, also mirrored on `instrumentation_data.otelSpan.attributes`): `false` marks events that reached export only via `excludeFromSampling` while the session itself was sampled out. Lets a `beforeSend` callback keep just crashes/ANRs (or any subset) at low session sample rates without reflecting into SDK internals. The decision is stamped on each span at creation, so events buffered across a session rotation keep the sampling decision of the session they belong to.

## [2.12.0] - 2026-07-26

### Added
- `reportError` now accepts optional `data` and `labels` on the `error:`, `NSError`, and `exception:` overloads, so a handled error can carry structured data and per-event labels in a single call instead of a separate `log()`. `data` attaches to the error event and `labels` merge into the event's labels.

## [2.11.2] - 2026-07-22

### Fixed
- Session Replay no longer leaks navigation-bar titles that should be masked, or a thin edge of screen content, during screen transitions on iOS 18.5.

## [2.11.1] - 2026-07-20

### Fixed
- Session Replay no longer renders Flutter content as a solid black rectangle when a masked frame isn't ready yet (e.g. at app launch); it reuses the last captured frame, or skips that frame until one is available.

## [2.11.0] - 2026-07-20

### Added
- `CoralogixRum.flush(completion:)` — forces an immediate export of queued telemetry and calls the completion once the upload attempt finishes, so a crash can be delivered before the process terminates.

### Fixed
- Crash events reported through the hybrid (React Native / Flutter) bridge are now written to disk before upload and re-sent on the next launch when delivery was not confirmed, so a crash is no longer lost if the process dies before its network upload completes.
- Crash events upload directly instead of taking the hybrid `beforeSend` round trip to JS and back, so a dying process is not racing the extra native→JS→native hop.
- The pending crash report is purged (and re-sent stored events removed) only after their upload is confirmed, so an unconfirmed crash from an earlier launch is no longer dropped when a later crash succeeds.

## [2.10.4] - 2026-07-16

### Fixed
- Events now report the screen that was on-screen when they occurred, instead of whatever screen happened to be active up to two seconds later when the batch was exported. Previously the view name (and view number / page URL) were read from the live view state at export time, so events that fired around a screen transition — logs, user interactions, mobile vitals, custom measurements, errors, and network requests — were frequently tagged with an empty or wrong view. The active view is now frozen onto each event the moment it is recorded.
- Crash reports again carry the screen the app was on when it crashed. A crash is recorded on the following launch, where no view has appeared yet, so it now recovers the crash-time screen from the previous session instead of reporting an empty view.

## [2.10.3] - 2026-07-14

### Fixed
- On the hybrid (Flutter / React Native) path, a network request's RUM span now carries the same trace ID that was injected into its outgoing `traceparent` header, so the mobile request correlates with its backend trace. Previously iOS only applied the reported trace/span IDs when a global custom span was active and dropped the per-request IDs otherwise, leaving ordinary requests on a separate, unstitchable trace (Android already applied them).

## [2.10.2] - 2026-07-13

### Fixed
- Crash reports are now attributed to the session active at the time of the crash (not the next app launch's session), and use the actual crash timestamp instead of the relaunch time.

## [2.10.1] - 2026-07-09

### Fixed
- The `traceparent` sent on an outgoing request now always shares the same trace as the network span the SDK reports for it, so RUM spans correlate with their backend traces instead of landing on a separate, unstitchable trace.

## [2.10.0] - 2026-07-05

### Added
- `createNewSession()` on `CoralogixRum` — force-starts a fresh RUM session on demand (e.g. on user logout) without a full `shutdown()` + `init()`. Issues a new session ID and resets the per-session state (views, error/click counters, snapshot throttle, Session Replay) — the same reset the automatic idle / max-age rotation performs.

## [2.9.2] - 2026-06-24

### Fixed
- On the hybrid (React Native / Flutter) path, a `beforeSend` edit to an editable `cx_rum` field (e.g. redacting `session_context.user_email`, or rewriting `labels`) was reflected in `text.cx_rum` but not in `instrumentation_data.otelSpan.attributes`: the encoded spans were uploaded verbatim after the callback, so the tracing mirror stayed stale and a redacted value still leaked through tracing. The OTEL attributes are now rebuilt from the edited `cx_rum` before upload — the same rebuild the native single-event path performs — so both destinations carry identical values.

## [2.9.1] - 2026-06-16

### Fixed
- Cold Start AVG reported multi-hour values. Prewarmed launches (iOS spawns the process in the background ahead of user intent, flagged by `ActivePrewarm`) and other background launches (push/fetch/location) were measured from kernel process birth time and counted as cold starts. Prewarmed launches are now skipped, and any cold-start duration beyond a 60s ceiling is dropped as a background-launch artifact.

## [2.9.0] - 2026-06-15

### Added
- Session Replay now emits a one-shot init log capturing its configuration when recording starts, so the active Session Replay settings are visible in the backend.

## [2.8.0] - 2026-06-11

### Fixed
- SwiftUI text and images were not masked in session replay (BUGV2-6045): the synchronous UIView walk cannot see inside SwiftUI hosting views. Interim fix: restored the Vision-based `TextScanner` (OCR) and `ImageScanner` `maskAll` (rectangle detection) pipeline stages, scoped to captures whose scene contains a SwiftUI hosting view (`URLEntry.containsSwiftUIContent`). UIKit and Flutter capture paths are unchanged. Note: OCR masking is probabilistic (e.g. rows clipped at the viewport edge mid-scroll escape recognition) — a deterministic class-name-matching approach is planned follow-up (see `docs/swiftui-masking-investigation.md`).
- Session replay mask-skew bug (BUGV2-6045): during scroll animations, mask rects drifted 16–80+ px behind the text they covered. Root cause: `drawHierarchy` captured the presentation layer while mask rects were read from the model layer — the two diverge during `CAAnimation`. Fix: native-window capture now uses `layer.render(in:)` (model layer) and collects mask rects synchronously in the same render pass. Leak rate: 47% of frames → 0.
- Flutter content appeared as a transparent hole in session-replay frames. Fix: new `flutterViewBitmapProvider` requests a pre-masked RGBA8888 bitmap from the Flutter plugin's Dart rasteriser, which captures and masks in a single synchronous frame slice. Flutter leak rate: 77% → 0.
- Session replay capture timer silently never fired when initialised via Flutter's background MethodChannel task queue (background threads have no run loop). Fix: all `SessionReplay` entry points now dispatch to `DispatchQueue.main`.
- Session replay click frames were not detected on iOS 26: `getClickPoint` cast tap coordinates with `as? Double`, which no longer succeeds for a boxed `CGFloat` on iOS 26. Fix: coordinates are now coerced from any numeric boxing (`Double`/`CGFloat`/`Int`/`NSNumber`).

### Added
- `SessionReplayOptions.flutterViewBitmapProvider: FlutterViewBitmapProvider?` — callback for Flutter hosts to supply pre-masked frame bitmaps per capture.
- Native-iOS session-replay leak harness (`tool/leak-harness/`, `tool/run_leak_harness.sh`) for CI leak validation (BUGV2-6045).

## [2.7.0] - 2026-06-02

### Added
- `customAttributes: [String: Any]?` parameter on `reportError(message:, stackTrace:, ...)` and `reportError(message:, obfuscatedStackTrace:, ...)` overloads. Custom attributes now ride alongside the parsed stack frames on the emitted error event instead of being mutually exclusive with the stack trace (CX-44438, #TBD)

## [2.6.4] - 2026-05-12

### Added
- Hybrid SDK path honors `excludeFromSampling` (CX-40203, #201)

### Changed
- Document `excludeFromSampling` in README (CX-40204, #202)

## [2.6.3] - 2026-05-11

### Added
- `ExcludableInstrumentation` enum and `excludeFromSampling` SDK option (CX-40199, #193)
- Per-session sampling reroll with init-flow decoupling (CX-40200, #194)
- Per-span sampling filter in `CoralogixExporter` (CX-40201, #195)
- `LogSamplingDecouplingTests` + demo-app test harness (CX-40202, #197)
- SwiftUI E2E UI tests + `DemoAppSwiftUIUITests` target (CX-39993, #192)
- SwiftUI swipe detection + full UI rebuild of `DemoAppSwiftUI` (CX-33282, #191)

### Fixed
- Session Replay scroll lag (#199)

## [2.6.2] - 2026-04-28

### Fixed
- Flutter scroll freeze — use `afterScreenUpdates: false` (#190)

## [2.6.1] - 2026-04-26

### Fixed
- `tracesExporter` `instrumentation_data` payload and `TracesExporterViewController` per-span table UI (#189)

## [2.6.0] - 2026-04-23

### Fixed
- Custom Spans API hardening + network span 422 fix (CX-39134, #188)
- CocoaPods publish hardened against CDN propagation delays (#187)

## [2.5.1] - 2026-04-16

### Fixed
- Removed all `assert`/`precondition`/`fatalError` from SDK code (an SDK must not crash the host app) + swizzle test isolation (CX-37986, #186)
- Global span registry; added CX-36931 network tests (CX-37986, #185)

## [2.5.0] - 2026-04-14

### Added
- Traces Exporter (OTLP JSON) with callback and DemoApp validation (#184)
- Global span trace propagation and `ignoredInstruments` for auto spans (CX-35954/CX-35955, #183)
- Custom Spans API, OTel context, and RUM/Tracing parity with the Browser SDK (CX-35951, #181)
- `US3` domain to `CoralogixDomain` enum (#180)

### Fixed
- Preserve `telemetry.sdk.*` attributes in the OTel Resource (#182)
- Use `pod trunk info` instead of `pod search` for availability check (#179)

## [2.4.1] - 2026-03-29

### Fixed
- `traceparent` header capture in the React Native / Flutter hybrid network path (#178)

## [2.4.0] - 2026-03-26

### Added
- Flutter obfuscated errors + error metadata (`arch`, `build_id`, `stack_trace_type`) (#177)

## [2.3.3] - 2026-03-22

### Fixed
- Forward request/response headers and payload in Flutter hybrid network path (#176)

## [2.3.2] - 2026-03-22

### Changed
- `Span` made `Equatable` / record events made `Hashable` (#175)

## [2.3.1] - 2026-03-22

### Changed
- `Span` made `Hashable`; publish-pods script + Jira MCP tooling (#174)

## [2.3.0] - 2026-03-18

### Added
- Request/response body capture, hybrid severity fix, tap x/y rounding (CX-33235, #169)
- Response body capture with content-type stringification and 1024-char limit (CX-33234, #168)

### Changed
- Unified `beforeSendCallBack` behavior across SDKs (CX-32889, #171)

### Fixed
- React Native response body capture + URLSession race fixes (#173)
- `beforeSend` error count when severity changes (BUGV2-5379, #172)
- Preserve request in `requestMap` for network header capture; `SDKSampler` move (#166)

## [2.2.0] - 2026-03-09

### Added
- Hybrid platform support: `setUserInteraction`, `setNetworkRequestContext`, session-replay decoupling (#165)
- Enrich `instrumentation_data.otelSpan` with `cx_rum.*` structured attributes (#164)
- `NetworkCaptureRule` model + `networkExtraConfig` SDK option (CX-33230, #159)
- Capture-rule fields on `NetworkRequestContext` (CX-33232, #163)
- `resolveConfigForUrl(_:configs:)` API (CX-33231, #162)
- `shouldSendText` and `resolveTargetName` delegates for user-action events (CX-32583, #160)
- E2E tests for scroll, swipe, and `resolveTargetName` user-interaction events (CX-32754, #161)
- `UISwipeGestureRecognizer` swipe detection (CX-32582, #158)
- Extended interaction schema with scroll detection and PII-safe text (CX-32580/CX-32581, #157)
- Process MetricKit hang diagnostics as error events (CX-31668, #156)
- Allow clearing user context by passing `nil` to `setUserContext` (#144)

### Changed
- Decouple ANR from Mobile Vitals and report as error events (#146)
- Document 700ms frozen-frame threshold rationale (CX-31665, #152)

### Removed
- Unused mobile-vitals sample-rate configuration (CX-31659, #149)

### Fixed
- Accurate cold-start measurement via `sysctl`; remove swizzle dependency (CX-31662, #155)
- Report warm start for Flutter and React Native apps (CX-31661, #154)
- Include zero-count windows in frame statistics for accurate percentiles (CX-31666, #153)
- Remove 100% cap from memory utilization (CX-31664, #151)
- Remove CPU 100% cap to detect multi-core saturation (CX-31663, #150)

## [2.1.0] - 2026-02-12

### Changed
- Eliminate delegate class scanning; migrate to industry-standard swizzling for multi-SDK compatibility (#145)

## [2.0.0] - 2026-02-05

### Added
- Flutter session-recording masking support (#143)

### Fixed
- Sync severity from `beforeSend` callback to `CxSpan` (#142)

## [1.5.3] - 2026-01-21

### Fixed
- Negative-duration bug; mark session id and session creation date correctly (CX-4620, #140)
- Podspec update scripts

## [1.5.2] - 2026-01-05

### Added
- ANR detection wired into the scheme (CX-26496, #137)

## [1.5.1] - 2025-12-23

### Changed
- Adopt `async`/`await` in internal APIs (CX-25861, #133)

## [1.5.0] - 2025-12-03

### Added
- Masking bridge widget (ALPH-22252, #130)

## [1.4.0] - 2025-11-09

### Added
- iOS mask-view for the native SDK (ALPH-15201, #128)

## [1.3.2] - 2025-11-03

### Fixed
- Missing session-replay function (ALPH-1234, #127)

## [1.3.1] - 2025-10-30

### Fixed
- Session-replay segment-index bug (ALPH-1234, #126)

## [1.3.0] - 2025-10-26

### Added
- Screenshot change-detection filter for iOS Session Replay (ALPH-2515, #124)
- Mobile-vitals options (ALPH-2754, #122)

### Changed
- README clarity and typo fixes (#123)

## [1.2.6] - 2025-09-28

### Added
- Emit Navigation events (ALPH-2546, #120)
- Custom-measurement API (#119)
- Custom log labels (ALPH-2257, #115)
- Send internal-init event (ALPH-2654, #114)

### Changed
- Refactor mobile vitals (ALPH-2704, #117)
- Session reset uses a closure instead of `NotificationCenter` (#118)

### Fixed
- Idle bug (#116)

## [1.2.5] - 2025-09-04

### Changed
- Automate CocoaPods release pipeline (ALPH-6671, #107, #108, #109, #110, #111, #112, #113)

## [1.2.3] - 2025-09-01

### Changed
- Bump `PLCrashReporter` dependency (#106)

## [1.2.2] - 2025-08-31

### Fixed
- User-agent string (#105)
- React Native integration fixes (ALPH-1234, #104)

## [1.2.1] - 2025-08-26

### Fixed
- Broken `spanid` and `traceid` (#103)
- App freeze on main thread (#102)

## [1.2.0] - 2025-08-25

### Added
- Persistent anonymous fingerprinting (ALPH-2644, #101)
- Unified Mobile Vitals reporting API (#99)
- Slow / freeze frame detection + tests (ALPH-2588, #98)
- Memory detector (ALPH-2550, #97)
- Native iOS CPU tracking (ALPH-2579, #96)
- Missing metrics and logics (ALPH-1234, #100)

## [1.1.3] - 2025-08-11

### Fixed
- App crash in `NSMutableURLRequest` ObjC bridging (ALPH-2631, #95)

## [1.1.2] - 2025-07-30

### Changed
- Externalize `PLCrashReporter` from the main RUM module (ALPH-2488, #94)

### Fixed
- iOS schema issues (ALPH-2530, #93)
- Remove duplicate swizzle code that sent multiple clicks (#92)
- `sessionId` now lowercase (ALPH-2523, #91)
- `ignoreUrl` now works with regex (ALPH-2519, #90)
- URLSession instrumentation deadlock (#89)
- Crash in `URLSessionInstrumentation.injectIntoNSURLSessionCreateTaskWithParameterMethod` (ALPH-2507, #87)

## [1.1.1] - 2025-07-17

### Fixed
- Several crashes (ALPH-2498, #84)

## [1.1.0] - 2025-07-10

### Changed
- New idle-logic refactor (ALPH-2468, #79)

## [1.0.27] - 2025-07-02

### Added
- `isManual` flag (ALPH-2429, #78)
- Snapshot context on all severity-5 events (ALPH-2424, #76)

### Fixed
- Crash in `BatchWorker` / `NetworkStatus` class (ALPH-2423, #75)

## [1.0.26] - 2025-06-26

### Added
- `traceparent` header injection (native) (ALPH-2296, #74)

### Fixed
- When using a proxy URL, the exporter now removes the span correctly (ALPH-2148, #72)

## [1.0.25] - 2025-06-24

### Added
- `traceparent` header option on `CoralogixOptions` (ALPH-2295, #71)
- Proxy URL support (native) (ALPH-2292, #70)

### Fixed
- Crash in `SessionMetaDataManager` (ALPH-2914, #69)

## [1.0.24] - 2025-06-22

### Fixed
- Change duration, add undefined-text handling, repair broken tests (ALPH-2388, #67)
- Images skipped during session recording (ALPH-2360, #65)

## [1.0.23] - 2025-06-05

### Added
- Flutter support for cold / warm mobile vitals (ALPH-1234, #62)

### Fixed
- Initialize `segmentIndex` when page is incremented (ALPH-2286, #61)
- Broken SwiftUI example project (#60)

## [1.0.22] - 2025-05-25

### Added
- Session Replay click events (ALPH-1885, #57)

### Changed
- Disable swizzling option (ALPH-2246, #58)

## [1.0.21] - 2025-05-08

### Added
- Screenshot events in session recording (ALPH-2159, #52)

### Fixed
- Crash in `URLSessionInstrumentation` (ALPH-2218, #53)

## [1.0.20] - 2025-04-24

### Added
- Session Replay merged into the main module (ALPH-2183, #49)

### Fixed
- Crash in URLSession instrumentation (ALPH-2195, #51)

## [1.0.19] - 2025-04-14

### Added
- `beforeSend` logic + example project

## [1.0.18] - 2025-04-03

### Changed
- Roll back OpenTelemetry to 1.9.0 (ALPH-2154, #47)

### Fixed
- DANZ duration bug — now in milliseconds (ALPH-2151, #46)
- Crash in "xploretechnologey" path (ALPH-2148, #45)

## [1.0.17] - 2025-03-27

### Fixed
- `ignoreUrl` and `ignoreError` API behavior (#44)

## [1.0.16] - 2025-03-16

### Added
- Missing API functions (ALPH-2128, #43)

### Fixed
- Network requests not captured in some cases (ALPH-2128, #43)

## [1.0.15] - 2025-03-06

### Added
- New public API functions (ALPH-2214, #42)

## [1.0.14] - 2025-02-24

### Changed
- Switch library to static linkage (#40)

## [1.0.13] - 2025-02-04

### Fixed
- Crash in `UICollectionView` swizzle (#39)

## [1.0.12] - 2024-11-19

### Added
- Lifecycle events (ALPH-1623, #36)
- Daily metrics log reporting (ALPH-1625, #35)
- `beforeSend` logic (ALPH-1622, #34)
- Instrumentation config (ALPH-1567, #31)
- AP3 environment support (#32)
- Performance — mobile vitals (ALPH-1463, #30)

### Changed
- Skip collecting IP data (ALPH-1570, #33)

### Fixed
- Flutter gap, lifecycle bugs, and Flutter stuck-trace bug (ALPH-1759, #37)

## [1.0.11] - 2024-08-28

### Fixed
- iOS 13 compatibility (Xcode 15.0.1) (#28)

## [1.0.10] - 2024-08-27

### Added
- Basic tvOS support (ALPH-1506, #25)
- `samplerRate` option on `CoralogixOptions` (#24)
- RUM user actions (ALPH-1285, #21)
- Traces support (ALPH-1375, #20)

### Changed
- Flatten error context (#23)

### Fixed
- Wrong Swift tools version — now 5.9 (#26)
- Telephony info handling (#22)

## [1.0.8] - 2024-07-07

### Added
- Native enhancements for Flutter capabilities (ALPH-1137, #14)

## [1.0.6] - 2024-06-23

### Added
- CocoaPods podspec (#12)

## [1.0.5] - 2024-06-20

### Added
- OpenTelemetry API/SDK + `PLCrashReporter` as XCFrameworks (#9)
- Session-snapshot logic (ALPH-1187, #10)
- OpenTelemetry SDK/API integration (ALPH-1187, #11)

## [1.0.4] - 2024-05-26

### Added
- ViewController extraction for Swift UIKit (#6)
- ViewController extraction for SwiftUI (ALPH-1085, #5)
- `DeviceState` and `DeviceContext` (ALPH-1112, #4)

## [1.0.0] - 2024-05-02

### Added
- Initial release of the Coralogix iOS RUM SDK
