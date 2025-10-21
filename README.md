# Official Coralogix SDK for iOS.

## The Coralogix RUM Mobile SDK is library (Swift package) for iOS

The SDK provides mobile Telemetry instrumentation that captures:

1. HTTP requests, using URLSession instrumentation
2. Unhandled exceptions (NSException, NSError, Error)
3. Custom Log ()
4. Crashes - using PLCrashReporter
5. Page navigation (Swift use swizzeling / SwiftUI use modifier)
6. User Actions (Clicks - UI elemenets)
7. Mobile Vitals (FPS, Application not responding, Cold Start, Warm Start)

## Requirements

Coralogix RUM agent for iOS supports iOS 13 and higher.

## Installation

The integration requires minimal effort with a few lines of code.
To install this package,

import `git@github.com:coralogix/cx-ios-sdk` in spm.

Remember to call this as early in your application life cycle as possible.
Ideally in ```applicationDidFinishLaunching in AppDelegate```

  

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
### Instrumentation's
Turn on/off specific instrumentation, default to all trues. Each instrumentation is responsible for which data the SDK will track and collect for you.
```
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY",
                                           instrumentations: [.navigation: true,
                                                              .mobileVitals: false,
                                                              .custom: true,
                                                              .errors: true,
                                                              .userActions: false,
                                                              .network: true,
                                                              .anr: true,
                                                              .lifeCycle: false])
```

### Ignore Errors
The ignoreErrors option allows you to exclude errors that meet specific criteria. This options accepts a set of strings and regular expressions to match against the event's error message. Use regular expressions for exact matching as strings remove partial matches.
```
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        ignoreErrors: []) //[".*errorcode=.*", "Im cusom Error"]
```

### Ignore Urls
The ignoreUrls option allows you to exclude network requests that meet specific criteria. This options accepts a set of strings and regular expressions to match against the event's network url. Use regular expressions for exact matching as strings remove partial matches.

```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        ignoreUrls: []) //[".*\\.il$","https://www.coralogix.com/academy"])
```

### Label Providers
Provide labels based on url or event
```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        labels: ["item" : "item_number_5", "itemPrice" : 1000]) 
```

### CollectIPData
Determines whether the SDK should collect the user's IP address and corresponding geolocation data. Defaults to true.
```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        collectIPData: true)
```

### Sample Rate
Number between 0-100 as a precentage of SDK should be init.
```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        sampleRate: 100)
```

### Mobile Vitals FPS Sample Rate
The timeinterval the SDK will run the FPS sampling in an hour. default is every 1 minute.
```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        mobileVitalsFPSSamplingRate: 60)
```
  
### Before Send
Enable event access and modification before sending to Coralogix, supporting content modification.
```
let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                        environment: "ENVIRONMENT",
                                        application: "APP-NAME",
                                        version: "APP-VERSION",
                                        publicKey: "API-KEY",
                                        beforeSend: { cxRum in
            var editableCxRum = cxRum
            if var sessionContext = editableCxRum["session_context"] as? [String: Any] {
                sessionContext["user_email"] = "jone.dow@coralogix.com"
                editableCxRum["session_context"] = sessionContext
            }
            return editableCxRum
        })
```
, and event discarding
```
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
### Mobile Vitals's
Turn on/off specific Mobile Vitals, default to all trues. Each Mobile Vitals is responsible for which data the SDK will track and collect for you.
```
 let options = CoralogixExporterOptions(coralogixDomain: CORALOGIX-DOMAIN,
                                           environment: "ENVIRONMENT",
                                           application: "APP-NAME",
                                           version: "APP-VERSION",
                                           publicKey: "API-KEY",
                                           mobileVitals: [.anrDetector: true,
                                                          .cpuDetector: true,
                                                          .warmDetector: true,
                                                          .coldDetector: true,
                                                          .slowFrozenFramesDetector: true,
                                                          .memoryDetector: true
                                                          .renderingDetector: true])
```

### Session Recording
See the [Session Recording Guide](SessionReplay/Sources/Docs/README.md) for installation steps and examples.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
