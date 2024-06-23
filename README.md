# Official Coralogix SDK for iOS.

## The Coralogix RUM Mobile SDK is lirary (Swift package) for iOS
The SDK provides mobile Telemetry instrumentation that captures:

1. HTTP requests, using URLSession instrumentation
2. Unhandled exceptions (NSException, NSError, Error)
3. Custom Log ()
4. Crashes - using PLCrashReporter
5. Page navigation (Swift use swizzeling / SwiftUI use modifier)


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
import CoralogixRum

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var coralogixRum: CoralogixRum?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "API-KEY",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               customDomainUrl: "",
                                               labels: ["String" : Any],
                                               debug: false)
        self.coralogixRum = CoralogixRum(options: options)
        return true
    }
````


Or if you are using ```swiftUI```
```swift
import SwiftUI
import CoralogixRum

@main
struct DemoAppApp: App {
    @State private var coralogixRum: CoralogixRum

    init() {
             let options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "TOKEN",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               customDomainUrl: "",
                                               labels: ["String" : Any],
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

