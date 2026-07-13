# Official Coralogix SDK for iOS.

## The Coralogix RUM Mobile SDK is a library (Swift package) for iOS

The SDK provides mobile Telemetry instrumentation that captures:

1. HTTP requests, using URLSession instrumentation
2. Unhandled exceptions (NSException, NSError, Error)
3. Custom Logs
4. Crashes - using PLCrashReporter
5. Page navigation (Swift use swizzling / SwiftUI use modifier)
6. User Actions (Clicks - UI elements)
7. ANR (Application Not Responding) detection
8. Mobile Vitals (FPS, CPU, Memory, Cold Start, Warm Start, Slow/Frozen Frames)

## Requirements

Coralogix RUM agent for iOS supports iOS 13 and higher.

## Installation

The integration requires minimal effort with a few lines of code.
To install this package,

import `git@github.com:coralogix/cx-ios-sdk` in SPM.

Remember to call this as early in your application life cycle as possible.
Ideally in ```applicationDidFinishLaunching in your AppDelegate```

  

```swift

import UIKit
import Coralogix

  

@main

class AppDelegate: UIResponder, UIApplicationDelegate {

var coralogixRum: CoralogixRum?

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let domain = CoralogixDomain.US2
    let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY")
    self.coralogixRum = CoralogixRum(options: options)
    return true
}

````

Or if you are using ```swiftUI```

```swift

import SwiftUI
import Coralogix

@main

struct DemoAppApp: App {
    @State private var coralogixRum: CoralogixRum
    init() {
        let domain = CoralogixDomain.US2
        let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY")
        self.coralogixRum = CoralogixRum(options: options)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(coralogixRum: $coralogixRum)
        }
    }
}
```
### Instrumentations
Turn on/off specific instrumentation, default to true. Each instrumentation is responsible for which data the SDK will track and collect for you.
```swift
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY",
                                           instrumentations: [.mobileVitals: true,
                                                              .custom: true,
                                                              .errors: true,
                                                              .network: true,
                                                              .userActions: false,
                                                              .anr: true,
                                                              .lifeCycle: false])
```

### Ignore Errors
The ignoreErrors option allows you to exclude errors that meet specific criteria. This option accepts a set of strings and regular expressions to match against the event's error message. Use regular expressions for exact matching as strings remove partial matches.
```swift
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        ignoreErrors: []) //[".*errorcode=.*", "Im cusom Error"]
```

### Ignore Urls
The ignoreUrls option allows you to exclude network requests that meet specific criteria. This options accepts a set of strings and regular expressions to match against the event's network url. Use regular expressions for exact matching as strings remove partial matches.

```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        ignoreUrls: []) //[".*\\.il$","https://www.coralogix.com/academy"])
```

### Label Providers
Provide labels based on url or event
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        labels: ["item" : "item_number_5", "itemPrice" : 1000]) 
```

### CollectIPData
Determines whether the SDK should collect the user's IP address and corresponding geolocation data. Defaults to true.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        collectIPData: true)
```

### Sample Rate
Number between 0-100 as a percentage of SDK sessions should be initialized.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        sessionSampleRate: 100)
```

### Crash Stack Trace Limits
Bound the size of a native crash report so it stays within the backend's ingestion limit (crash logs above the limit are truncated by the pipeline and can be corrupted).

- `maxStackTraceFramesPerThread` (default `20`) — maximum frames kept per thread. When a thread has more, its stack is truncated **middle-out**: the top frames (the crash site and its immediate callers) and the bottom frames (the entry point) are kept, and the middle is dropped. This keeps deep and recursive stacks useful instead of showing one repeated frame.

If a report is still too large, the SDK automatically reduces the number of threads it includes — always keeping the thread that crashed — until it fits under the ingestion limit. Thread order is never changed; only the volume of frames and threads is reduced. Hybrid (Flutter / React Native) crash paths are unaffected — those SDKs apply their own limits.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        maxStackTraceFramesPerThread: 20)
```

### Excluding Instrumentations from Session Sampling
Opt specific event categories out of the `sessionSampleRate` gate so they always export, even from sessions that are otherwise sampled out. Useful when you want a low session sample rate for general telemetry but still need every log and error captured.

In the example below, only 10% of sessions are sampled in for the full event stream; the remaining 90% of sessions still export `.logs` and `.errors`, but every other category is dropped.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        sessionSampleRate: 10,
                                        excludeFromSampling: [.logs, .errors])
```

Accepted `ExcludableInstrumentation` cases:
- `.errors`
- `.logs`
- `.network`
- `.userInteractions`
- `.mobileVitals`
- `.customSpan`
- `.customMeasurement`

**Back-compat:** The default is an empty set — `sessionSampleRate` gates the entire SDK exactly as before. Add categories to `excludeFromSampling` to let them bypass the gate.

Parity note: the Coralogix Browser SDK exposes the same option with matching semantics.

### Before Send
Enable event access and modification before sending to Coralogix, supporting content modification.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        beforeSend: { cxRum in
            var editableCxRum = cxRum
            if var sessionContext = editableCxRum["session_context"] as? [String: Any] {
                sessionContext["user_email"] = "john.doe@coralogix.com"
                editableCxRum["session_context"] = sessionContext
            }
            return editableCxRum
        })
```
, and event discarding
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        beforeSend: { cxRum in
            var editableCxRum = cxRum
            if var viewContext = editableCxRum["view_context"] as? [String: Any], 
                      let view = viewContext["view"] {
                if view == "DetailsViewController" {
                    return nil
                }
            }
        })
```
### Mobile Vitals
Turn on/off specific Mobile Vitals, default to all trues. Each Mobile Vitals is responsible for which data the SDK will track and collect for you.
Note: ANR is controlled separately via the `instrumentations` option, not as a mobile vital.
```swift
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY",
                                           mobileVitals: [.cpuDetector: true,
                                                          .warmDetector: true,
                                                          .coldDetector: true,
                                                          .slowFrozenFramesDetector: true,
                                                          .memoryDetector: true,
                                                          .renderingDetector: true])
```

#### Mobile Vitals Sampling Intervals

Mobile vitals are sampled at fixed, battery-optimized intervals:

- **FPS**: Continuous per-frame tracking via CADisplayLink (~60Hz) with 1-second aggregation/reporting
- **CPU**: 1 second
- **Memory**: 1 second

These intervals are optimized for battery efficiency while capturing all important performance trends. The 1-second sampling provides accurate statistics (min/max/avg/p95) for monitoring without excessive battery drain.

> **Note:** Prior to v2.2.0, the SDK exposed (non-functional) configuration parameters for these intervals. These have been removed as they were never actually used.

#### Understanding Mobile Vitals Metrics

**Memory Utilization:**
- Calculated as: `(app footprint / total device physical RAM) × 100%`
- Example: 500MB footprint on 6GB device = 8.3%
- Note: iOS reserves 1-2GB for system processes, so practical app maximum is typically 70-80%
- Apps exceeding ~80% utilization risk receiving memory warnings from iOS and may be terminated if memory pressure continues
- The SDK reports utilization relative to total device capacity (matching iOS Instruments behavior)
- **Edge case:** Values >100% are theoretically impossible but the cap was removed to surface measurement anomalies. If you observe >100% readings, treat them as flags for investigation (likely indicating measurement timing issues, device reporting quirks, or transient OS behavior) rather than literal memory usage

**Slow and Frozen Frames:**
- **Slow frames**: Frame render time exceeds expected budget + 3% tolerance (e.g., >17.2ms on 60Hz display)
- **Frozen frames**: Frame render time >= 700ms (causes perceivable UI freeze)
- The 700ms frozen frame threshold aligns with ANR detection, providing consistent "unresponsive UI" definition across the SDK
- Thresholds automatically adapt to display refresh rate (60Hz standard, 120Hz ProMotion)
- Industry thresholds range from 250ms (very sensitive) to 700ms (severe freezes only); 700ms aligns with ANR

### Enable Swizzling
Controls whether the SDK automatically swizzles system methods for instrumentation (e.g. `NSURLSession`, view-controller lifecycle). Enabled by default. Set to `false` only if another library conflicts with Coralogix's swizzling.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        enableSwizzling: false)
```

### Network Header & Payload Capture
Use `networkExtraConfig` to opt-in to capturing request/response headers and bodies for specific URLs. By default no headers or payloads are captured.

Each `NetworkCaptureRule` matches requests by a **case-insensitive substring** of the absolute URL or by a **regex pattern**, and lets you allowlist which headers to forward and whether to capture bodies.
```swift
// Build regex patterns separately so the throwing init is handled cleanly.
// For known-good literal patterns you can use try! at development time;
// for patterns loaded from config use try? and check for nil before adding the rule.
let ordersPattern = try! NSRegularExpression(pattern: #"checkout/orders/\d+"#)

let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        networkExtraConfig: [
                                            // Capture Authorization header and response body for all /api/ requests
                                            NetworkCaptureRule(url: "/api/",
                                                               reqHeaders: ["Authorization", "X-Request-ID"],
                                                               resHeaders: ["Content-Type"],
                                                               collectResPayload: true),
                                            // Capture full request and response for URLs matching a regex
                                            NetworkCaptureRule(urlPattern: ordersPattern,
                                                               collectReqPayload: true,
                                                               collectResPayload: true)
                                        ])
```

> **Note:** Only allowlist URLs and header names you are comfortable logging. Avoid capturing `Authorization` or other sensitive headers unless intentional. Body and header capture should not be used for endpoints that return or send PII or secrets. Request and response bodies over 1024 characters are **dropped** (not truncated) and do not appear in RUM.

### User Action Text Redaction (`shouldSendText`)
Called before `target_element_inner_text` is recorded for a tapped view. Return `false` to suppress text capture for sensitive views (e.g. fields showing account numbers or personal data) without disabling text capture globally.

This closure is called on the **main thread** only when the SDK would otherwise record text. Keep it fast and non-blocking.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        shouldSendText: { view, text in
                                            // Suppress text for any view tagged as sensitive
                                            return view.accessibilityIdentifier != "sensitiveLabel"
                                        })
```

### Custom Target Element Name (`resolveTargetName`)
Override the `target_element` field in user action events with a business-friendly name instead of the raw UIKit class name. Return `nil` to fall back to the default class name (e.g. `"UIButton"`).

> **Note:** `resolveTargetName` only affects `target_element`. The `element_classes` field always contains the real UIKit class name (e.g. `"UIButton"`) regardless of what the closure returns, so existing analytics queries and backwards-compatible dashboards that filter on `element_classes` continue to work unchanged.

This closure is called on the **main thread** on every tap event. Keep it fast and non-blocking.
```swift
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        resolveTargetName: { view in
                                            switch view.accessibilityIdentifier {
                                            case "loginButton":   return "Login Button"
                                            case "checkoutBtn":   return "Checkout"
                                            case "addToCartBtn":  return "Add to Cart"
                                            default:              return nil // use UIKit class name
                                            }
                                        })
```

### Session Recording
See the [Session Recording Guide](SessionReplay/Sources/Docs/README.md) for installation steps and examples.

### Error Reporting
Report handled errors, caught exceptions, or custom error messages manually — this is separate from the automatic crash / unhandled-exception capture. Each call produces an error event in RUM.
```swift
// An NSException you caught
coralogixRum.reportError(exception: someNSException)

// A Swift Error / NSError
do {
    try riskyOperation()
} catch {
    coralogixRum.reportError(error: error)
}

// A custom message with optional structured data
coralogixRum.reportError(message: "Checkout failed",
                         data: ["cart_size": 3, "reason": "timeout"])
```

### User Context
Attach the current user's identity to every subsequent event. Call it after sign-in; pass a new `UserContext` to replace it (e.g. on account switch), and an empty context to clear it on sign-out.
```swift
coralogixRum.setUserContext(
    userContext: UserContext(userId: "user-123",
                             userName: "Jane Doe",
                             userEmail: "jane.doe@example.com",
                             userMetadata: ["plan": "premium", "role": "admin"])
)
```

### New Session on Logout
Force-start a fresh RUM session on demand — typically on user logout — without a full `shutdown()` + `init()`. A new session ID is issued and the per-session state (views, error/click counters, snapshot throttle, Session Replay) resets, exactly like the automatic idle / max-age rotation.
```swift
// e.g. when the user logs out
coralogixRum.createNewSession()
```
On a logout → login flow, pair it with `setUserContext` for the new user. The current view carries into the new session automatically (as view #0), so events keep their view context without any extra call.

### Custom Logs
Send a structured log at a chosen severity, with optional structured `data` and `labels`.
```swift
coralogixRum.log(severity: .info,
                 message: "User completed onboarding",
                 data: ["step_count": 4],
                 labels: ["flow": "onboarding"])
```
Severity levels: `.debug`, `.verbose`, `.info`, `.warn`, `.error`, `.critical`.

### Custom Spans
Create your own OpenTelemetry spans to trace app-specific work (e.g. a checkout flow) with full control over attributes, events, and status. The custom tracer requires `traceParentInHeader` to be enabled in the options.
```swift
// 1. Enable the custom tracer in your options
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        traceParentInHeader: ["enable": true])

// 2. Open a global span, then child spans under it
guard let tracer = coralogixRum.getCustomTracer() else { return }
guard let global = tracer.startGlobalSpan(name: "checkout.flow",
                                          labels: ["screen": "cart"]) else { return }

let child = global.startCustomSpan(name: "checkout.authorize")
child.setAttribute(key: "step", value: "authorize")
child.addEvent(name: "authorized")
child.setStatus(.ok)
child.endSpan()

global.endSpan()
```
**Notes:**
- `getCustomTracer()` returns `nil` unless `traceParentInHeader: ["enable": true]` is set.
- While a global span is open it becomes OpenTelemetry's active context, so auto-instrumentation (e.g. `URLSession`) shares the same `traceId` until you call `endSpan()`.
- Only one global span may be open at a time — a second `startGlobalSpan` returns `nil` until the first one ends.
- Use `getCustomTracer(ignoredInstruments: [.networkRequests, .errors])` to exclude specific auto-instruments from the span's trace.

### Custom Measurement
Report a one-off numeric measurement (e.g. a computed score or payload size) as a `custom-measurement` event. To time a span of work instead, use [Custom Time Measurement](#custom-time-measurement).
```swift
coralogixRum.sendCustomMeasurement(name: "image_load_score", value: 43.0)
```

### Manual View & Application Context
Override the automatically-tracked screen name, or update the reported application name / version at runtime.
```swift
// Set the current screen/view name manually (useful for custom navigation)
coralogixRum.setView(name: "CheckoutScreen")

// Update the application name / version reported on subsequent events
coralogixRum.setApplicationContext(application: "MyApp", version: "2.5.0")
```

### Custom Time Measurement
Time arbitrary spans of work in your app code with `startTimeMeasure(name:labels:)` and `endTimeMeasure(name:)`. Use this when you need to measure something the SDK can't auto-instrument — checkout flows, custom render passes, asset loading, etc. The duration is reported as a `custom-measurement` span (milliseconds).

```swift
coralogixRum.startTimeMeasure(name: "checkout", labels: ["cart_size": 3])
performCheckoutFlow()
coralogixRum.endTimeMeasure(name: "checkout")
```

**Parameters:**

| Method | Parameter | Type | Notes |
|---|---|---|---|
| `startTimeMeasure` | `name` | `String` | Unique identifier. Empty / whitespace-only keys are ignored. A duplicate `start` for an in-flight name is also ignored (first wins). |
| `startTimeMeasure` | `labels` | `[String: Any]?` | Optional labels attached at start; merged with SDK-level `labels` at `end`. Start labels win on key collision. |
| `endTimeMeasure` | `name` | `String` | Must match a prior `start`. No-op when the key was never started, was already ended, or the session has gone idle. |

**Pair `start` / `end` like `lock` / `unlock`.** The SDK keeps in-flight measurements in memory and does not impose a cap; an unbalanced caller will accumulate state until the next session-idle reset (15 min of inactivity). The `defer` idiom makes pairing automatic:

```swift
coralogixRum.startTimeMeasure(name: "checkout")
defer { coralogixRum.endTimeMeasure(name: "checkout") }
try performCheckout()
```

**Notes:**
- **Monotonic clock.** Durations use `DispatchTime.now().uptimeNanoseconds`, so wall-clock changes (NTP step, manual time adjustments) cannot produce negative durations.
- **Trimmed keys.** Leading and trailing whitespace is stripped; `"k "` and `"k"` resolve to the same entry.

Parity note: the Coralogix Browser SDK exposes the same `startTimeMeasure` / `endTimeMeasure` surface with matching semantics.

## Example Apps

The repository includes two fully-featured demo apps under `Example/`:

| App | Target | Description |
|-----|--------|-------------|
| `DemoAppSwift` | UIKit | Reference implementation — all instrumentation scenarios |
| `DemoAppSwiftUI` | SwiftUI | SwiftUI port — same scenarios, native SwiftUI patterns |

Both apps cover: Network instrumentation, Error instrumentation, SDK functions, Custom spans, User Actions (tap/scroll/swipe), Session Replay, Traces Exporter, Schema Validation, Mask UI, and Clock.

**To run locally:**
1. Open `Example/DemoApp.xcworkspace` in Xcode.
2. Select the `DemoAppSwift` or `DemoAppSwiftUI` scheme.
3. Fill in your credentials in `Example/Shared/Envs.swift` (API key, proxy URL).
4. Run on a simulator or device.

**E2E UI tests** (requires a running validation proxy):
```bash
# UIKit
xcodebuild test \
  -workspace Example/DemoApp.xcworkspace \
  -scheme DemoAppSwift \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -only-testing:DemoAppUITests

# SwiftUI
xcodebuild test \
  -workspace Example/DemoApp.xcworkspace \
  -scheme DemoAppSwiftUI \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  -only-testing:DemoAppSwiftUIUITests
```

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
