# Changelog

All notable changes to the Coralogix iOS RUM SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release-mechanics commits (version bumps, podspec/script tweaks, README edits) are
omitted; the focus here is user-facing behavior changes. Tickets are referenced as
`CX-XXXXX` (Jira) or `ALPH-XXXX` (legacy). Pull request numbers are in parentheses.

## [Unreleased]

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
