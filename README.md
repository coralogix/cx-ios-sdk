# Official Coralogix SDK for iOS.

## The Coralogix RUM Mobile SDK is lirary (Swift package) for iOS
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
         let options = CoralogixExporterOptions(coralogixDomain: domain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "API-KEY",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               customDomainUrl: "",
                                               labels: ["String" : Any],
                                               sampleRate: 100,
                                               mobileVitalsFPSSamplingRate: 300, // minimum every 5 minute
                                               instrumentations: [.navigation: true,
                                                                  .mobileVitals: true,
                                                                  .custom: true,
                                                                  .errors: true,
                                                                  .userActions: true,
                                                                  .network: true,
                                                                  .anr: true],
                                               debug: false)
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
             let options = CoralogixExporterOptions(coralogixDomain: domain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "TOKEN",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               customDomainUrl: "",
                                               labels: ["String" : Any],
                                               sampleRate: 100,
                                               mobileVitalsFPSSamplingRate: 300, // minimum every 5 minute
                                               instrumentations: [.navigation: true,
                                                                  .mobileVitals: true,
                                                                  .custom: true,
                                                                  .errors: true,
                                                                  .userActions: true,
                                                                  .network: true,
                                                                  .anr: true],
                                               debug: false)
        self.coralogixRum = CoralogixRum(options: options)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(coralogixRum: $coralogixRum)
        }
    }
}
```
## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

