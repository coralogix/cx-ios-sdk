# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Coralogix RUM SDK for iOS — an OpenTelemetry-based Real User Monitoring SDK that auto-instruments iOS apps (network, errors, user actions, crashes, ANR, mobile vitals, session replay). Distributed via SPM and CocoaPods. Min iOS 13.0, Swift 5.9.

## Build & Test Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run tests via Xcode (matches CI)
xcodebuild test -scheme Coralogix-Package -destination "platform=iOS Simulator,name=iPhone 16,OS=18.0"

# Lint CocoaPods specs (order matters)
pod lib lint CoralogixInternal.podspec
pod lib lint SessionReplay.podspec --include-podspecs=CoralogixInternal.podspec
pod lib lint Coralogix.podspec --include-podspecs=CoralogixInternal.podspec

# Build xcframeworks for distribution
./build.sh

# Interactive CocoaPods publish (lint + trunk push)
./lint_and_push_cocoapods.sh
```

CI runs on macOS 14 with Xcode 16.x. Three test targets: `CoralogixRumTests`, `CoralogixInternalTests`, `SessionReplayTests`.

## Architecture

### Three Targets

| Target | Role |
|--------|------|
| `Coralogix/Sources/` | Main public SDK — all instrumentation, export, and public API |
| `CoralogixInternal/Sources/` | Shared base library — `SdkManager` singleton, `Keys`, `Log`, utilities |
| `SessionReplay/Sources/` | Optional screen recording module with privacy scanning pipeline |

`CoralogixInternal` is a dependency of both `Coralogix` and `SessionReplay`. Both products register themselves with `SdkManager` on init so they can coordinate.

### Core Flow

1. **`CoralogixRum.init()`** — validates sample rate (exits early if not sampled), creates `CoralogixExporter`, `TracerProvider`, `BatchSpanProcessor`, then calls each `initialize*Instrumentation()` function based on the options passed.
2. **Instrumentation modules** — each is an `extension` on `CoralogixRum` (files in `Instrumentation/`). They swizzle system methods or register observers to produce OTel spans.
3. **`CoralogixExporter`** — implements OTel `SpanExporter`. Batches spans (50 spans / 2s), converts via `SpanDataToOtlpConverter`, applies the `beforeSend` callback, then PODs JSON to the Coralogix endpoint via `SpanUploader`.
4. **`tracesExporter` callback** — optional secondary export hook; called with raw `Data` so consumers can forward spans to Jaeger/Zipkin/etc.

### Key Classes

- **`CoralogixRum`** — orchestrator; owns all instrumentation references and the `CoralogixExporter`
- **`CoralogixExporterOptions`** — all SDK configuration; passed at init and stored on the exporter
- **`SessionManager`** — session lifecycle, idle detection, session ID rotation
- **`ViewManager`** — current view/screen name, used as RUM context on every span
- **`NetworkManager`** — network reachability state (not HTTP requests)
- **`MetricsManager`** — aggregates mobile vitals (FPS via `CADisplayLink`, CPU, memory)
- **`CoralogixCustomGlobalSpanRegistry`** — global span context for custom spans (mirrors browser SDK's `window.__globalSpan__`)
- **`SdkManager`** (singleton in `CoralogixInternal`) — registry shared by both products

### Instrumentation Pattern

Each instrumentation file is an `extension CoralogixRum` with a single `initialize*Instrumentation()` method. Network and user-action instrumentations store `currentInstance` and relevant options as **static properties** — this is intentional because swizzling happens once globally but the SDK can be re-initialized; statics ensure the live closures always reach the current options.

### Span Attribute Keys

All span attribute key strings live in `CoralogixInternal/Sources/Keys.swift`. When adding new attributes, define the key there.

### Context Model

Events carry context structs from `Coralogix/Sources/Model/Contexts/` (e.g., `DeviceContext`, `SessionContext`, `ErrorContext`, `InteractionContext`, `ViewContext`). Each context struct is encoded into span attributes by a corresponding builder in `Coralogix/Sources/Model/`.

## Rules

- **Never use `assert`, `precondition`, or `fatalError` in SDK code.** An SDK must never crash the host app. Use early returns or `Log.e(...)` instead. (Commit `7d59641` was entirely dedicated to removing these.)

- **Swizzling tests must restore original implementations in `tearDown`.** Swizzled state leaks between tests if not cleaned up — this caused a full test-isolation fix in `7d59641`.

- **Do not "fix" static properties on instrumentation classes.** `currentInstance`, `currentNetworkOptions`, etc. on `NetworkInstrumentation` and `UserActionsInstrumentation` are intentionally `static` — swizzling is global and these statics ensure SDK re-initialization reaches the current options.

- **iOS 13.0 minimum — guard any newer APIs with `#available`.** Code compiles fine but crashes at runtime on iOS 13 without availability checks.

- **All span attribute key strings belong in `CoralogixInternal/Sources/Keys.swift`.** No inline string literals for attribute keys anywhere else.

- **Protect all shared mutable state with `NSLock` or a serial `DispatchQueue`.** Follow the existing pattern — don't introduce unguarded shared state.

## Distribution

Three podspecs must be published in order (`CoralogixInternal` → `SessionReplay` + `Coralogix`) with CDN propagation waits between steps. The `lint_and_push_cocoapods.sh` script handles this interactively. Version numbers must be kept in sync across `Package.swift`, all three `.podspec` files, and the `CoralogixRum` source constant.
