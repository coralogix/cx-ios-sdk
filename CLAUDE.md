# cx-ios-sdk

@.claude/rules/CODING_STANDARDS.md

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

The review rules in `AGENTS.md` apply **while writing code**, not only at PR time — read it and follow it as you work.

- **Never use `assert`, `precondition`, or `fatalError` in SDK code.** An SDK must never crash the host app. Use early returns or `Log.e(...)` instead. (Commit `7d59641` was entirely dedicated to removing these.)

- **Swizzling tests must restore original implementations in `tearDown`.** Swizzled state leaks between tests if not cleaned up — this caused a full test-isolation fix in `7d59641`.

- **Do not "fix" static properties on instrumentation classes.** `currentInstance`, `currentNetworkOptions`, etc. on `NetworkInstrumentation` and `UserActionsInstrumentation` are intentionally `static` — swizzling is global and these statics ensure SDK re-initialization reaches the current options.

- **iOS 13.0 minimum — guard any newer APIs with `#available`.** Code compiles fine but crashes at runtime on iOS 13 without availability checks.

- **All span attribute key strings belong in `CoralogixInternal/Sources/Keys.swift`.** No inline string literals for attribute keys anywhere else.

- **Protect all shared mutable state with `NSLock` or a serial `DispatchQueue`.** Follow the existing pattern — don't introduce unguarded shared state.

- **Demo-app changes must land in both `Example/DemoAppSwift` (UIKit) and `Example/DemoAppSwiftUI` (SwiftUI).** When adding a new screen, section, or interactive control to one demo app, mirror it in the other so feature parity holds across both targets and the UI tests (`DemoAppUITests`, `DemoAppSwiftUIUITests`) stay symmetrical.

## Skills available

Invoke via `Skill` tool (or the user's `/<name>` slash command). Use the right tool for the job rather than reimplementing.

| Skill | When to use |
|---|---|
| `/implement` | New Jira ticket — fetch details, plan, branch, then stop for review before commit |
| `/pr-review` | Review a PR / feature branch end-to-end before opening |
| `/code-review` | Lighter diff-level review for correctness bugs and reuse/simplification (effort tunable low/medium/high) |
| `/simplify` | Quality pass on the current diff — reuse, simplification, efficiency. Quality only, not bug-hunting (use `/code-review` for that) |
| `/fix-issues` | Work through PR-review findings one at a time, stopping for approval between each |
| `/commitAndNext` | Inside `/fix-issues`, commit the current fix and advance to the next finding |
| `/verify` | Verify a change by actually running the demo app + observing behaviour. Use after a substantive change, before declaring "done" |
| `/bump-version` | Bump SDK version using the project's existing script (keeps the three `.podspec` files and `Global.sdk` in sync — do NOT hand-edit) |
| `/release-notes-sdk` | Summarise what changed between two version tags, formatted for a Slack post |
| `/Clean-After-Merged` | After a branch is merged: switch to `master`, pull, delete the local branch |

When the user invokes a skill they expect that skill's flow — don't substitute a manual workflow.

## Before opening a PR (`gh pr create`)

Run all six checks below. When they all pass, signal completion by running:

```bash
touch $(git rev-parse --show-toplevel)/.claude/.pr-checks-done
```

Then create the PR. The hook will verify the signal before allowing `gh pr create`.

---

### 1. Code review (`/pr-review`)

Run the `/pr-review` skill and read the full output. Block if any of these are found:
- Broken or missing functionality
- Security issues

Minor style feedback is **not** a blocker.

---

### 2. Jira ticket

Extract the ticket ID from the branch name (e.g. `CX-44687` from `feat/CX-44687-product-analytics-fields`).
Fetch the ticket via the Atlassian MCP and verify:
- The changes in this PR actually solve what the ticket describes
- No ticket requirements are left unaddressed

Block if the changes don't match the ticket.

---

### 3. Test coverage

Review what changed in this branch and verify:
- New public functions / classes have corresponding unit tests in the appropriate test target (`CoralogixRumTests`, `CoralogixInternalTests`, `SessionReplayTests`)
- New SDK behaviours have integration tests where appropriate
- All affected suites pass: `xcodebuild test -scheme Coralogix-Package -destination "platform=iOS Simulator,name=iPhone 17"` (or the currently-installed simulator)

Block if meaningful new code has no test coverage.

---

### 4. Version sync

iOS distributes through CocoaPods AND has an in-source SDK-version constant — **four files must move together**:

- `Coralogix.podspec`
- `CoralogixInternal.podspec`
- `SessionReplay.podspec`
- `CoralogixInternal/Sources/Utils.swift` (`Global.sdk` enum case)

Classify the changes on this branch:

- **Breaking API change** (removed/renamed public API, changed behaviour) → **major** bump required (e.g. `2.x.x → 3.0.0`)
- **New feature or new public API** → **minor** bump required (e.g. `2.7.x → 2.8.0`)
- **Bug fix or internal change only** → **patch** bump appropriate (e.g. `2.7.0 → 2.7.1`)

Use `/bump-version` — do **not** hand-edit. Block if:

- The version was not incremented at all for a non-trivial change
- A new feature was merged without at least a minor bump
- A breaking change was merged without a major bump
- The four files disagree on the version string

---

### 5. CHANGELOG

For `CHANGELOG.md` at the repo root:

- The current SDK version must have an entry
- The entry accurately describes the changes in this PR (not a placeholder)

Block if `CHANGELOG.md` is missing the version entry or the entry doesn't reflect the actual changes.

---

### 6. README

For `README.md` at the repo root:

- New public API is documented
- Removed or changed API is updated or removed
- Installation instructions reference the current version

Block if the README doesn't reflect the current state of the SDK.

## Distribution

Three podspecs must be published in order (`CoralogixInternal` → `SessionReplay` + `Coralogix`) with CDN propagation waits between steps. The `lint_and_push_cocoapods.sh` script handles this interactively. Version numbers must be kept in sync across all three `.podspec` files and the `CoralogixRum` source constant (`Global.sdk` in `CoralogixInternal/Sources/Utils.swift`). `Package.swift` has no version string — SPM versioning is driven by git tags.
