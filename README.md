# Official Coralogix SDK for iOS.

## The Coralogix RUM Mobile SDK is a library (Swift package) for iOS

The SDK provides mobile Telemetry instrumentation that captures:

1. HTTP requests, using URLSession instrumentation
2. Unhandled exceptions (NSException, NSError, Error)
3. Custom Logs ()
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
                                        sampleRate: 100)
```

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
- Industry comparison: Apple recommends 250ms, Firebase uses 400ms, Sentry/Coralogix use 700ms (aligned with ANR)

### Session Recording
See the [Session Recording Guide](SessionReplay/Sources/Docs/README.md) for installation steps and examples.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
