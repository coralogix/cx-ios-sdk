# Coralogix RUM - Native iOS

>[!IMPORTANT]
 <br/> <b>SwiftUI</b> screen navigation tracking is available from `iOS 13`.

>[!IMPORTANT]
>Requirements:
>- Deployment target of `iOS 13` or higher 
>- Swift Compatibility `5.7` or higher
>- Xcode `14` or higher

## Step 1. Add the Coralogix SDK
### Swift Package Manager:

1. Open _File -> Add Packages_.
2. Search for: `git@github.com:coralogix/cx-ios-sdk`.
3. Select _Up to Next Major Version_.

## Step 2. Establish a connection to Coralogix's server on app launch

>[!NOTE]
>The `API Key` can be found in your Coralogix page under DataFlow -> API Keys.

Identify if your app project contains an `AppDelegate` file or a `SceneDelegate` file. Pure SwiftUI projects do not include either of these files. To use Coralogix in your app, you will need to create one of them.  


1. If using the `AppDelegate` file, implement the following: <br/>

    <details open>
    <summary> <b>Swift Instructions</b><i> - Click to expand or collapse</i></summary>

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
                                               debug: false)
        self.coralogixRum = CoralogixRum(options: options)
        
        // your code in here...
        
        return true
    }
    
    ```
    </details>
    
    <details>
    <summary> <b>SwiftUI Instructions</b><i> - Click to expand or collapse</i></summary>

   ```swift
   import SwiftUI
   import Coralogix

   @main
   struct DemoAppApp: App {
    @State private var coralogixRum: CoralogixRum

     init() {
        let domain = CoralogixDomain.US2
        let options = CoralogixExporterOptions(coralogixDomain: doamin,
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
                                               debug: false)
            self.coralogixRum = CoralogixRum(options: options)
            
            // your code in here...
            
        }
    
        var body: some Scene {
            WindowGroup {
                ContentView(coralogixRum: $coralogixRum)
            }
        }
    }
    ```
    </details>
    <br/>
    2. If using the `SceneDelegate` file, implement the following:

    <details open>
    <summary> <b>Swift Instructions</b><i> - Click to expand or collapse</i></summary>

    ```swift
    import Coralogix
        @State private var coralogixRum: CoralogixRum

        func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
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
                                               debug: false)
            self.coralogixRum = CoralogixRum(options: options)
            
            //  your code here ...
        }
    ```
    </details>
    <br/>

# Coralogix Integration Functions
This document describes the public functions available for interacting with the Coralogix exporter.

## Functions

### setUserContext
```swift
public func setUserContext(userContext: UserContext)
```
Sets the user context for the Coralogix exporter.
#### Parameters
  * userContext: An instance of UserContext containing user information.

### setLabels
```
public func setLabels(labels: [String: Any])
```
Sets the labels for the Coralogix exporter.

#### Parameters
labels: A dictionary containing labels to be added to the Coralogix exporter.
reportError (NSException)
```swift
public func reportError(exception: NSException)
```
* Reports an error to Coralogix using an NSException.

#### Parameters
* exception: An instance of NSException representing the error.

### reportError (NSError)
```swift
public func reportError(error: NSError)
```
Reports an error to Coralogix using an NSError.

#### Parameters
* error: An instance of NSError representing the error.

### reportError (Error)
```swift
public func reportError(error: Error)
```
Reports an error to Coralogix using a Swift Error.

#### Parameters
* error: An instance of Error representing the error.

### reportError (String, [String: Any]?)
```swift
public func reportError(message: String, data: [String: Any]?)
```
Reports an error to Coralogix using a custom message and optional data.

#### Parameters
* message: A string describing the error.
* data: An optional dictionary containing additional data related to the error.

### log
```swift
public func log(severity: CoralogixLogSeverity, message: String, data: [String: Any]?)
```
Logs a message to Coralogix with a specified severity and optional data.

#### Parameters
* severity: The severity level of the log, represented by CoralogixLogSeverity.
* message: A string describing the log message.
* data: An optional dictionary containing additional data related to the log message.

### shutdown
```swift
public func shutdown()
```
Shuts down the Coralogix exporter and marks it as uninitialized.

### Usage Examples
#### Setting User Context
```swift
let userContext = UserContext(userId: "123", userName: "John Doe", userEmail: "john.doe@example.com", userMetadata: ["role": "admin"])
```
coralogixIntegration.setUserContext(userContext: userContext)
#### Setting Labels
```swift
let labels: [String: Any] = ["environment": "production", "version": "1.0.0"]
coralogixIntegration.setLabels(labels: labels)
```
#### Reporting Errors
```swift
let nsException = NSException(name: .genericException, reason: "An error occurred", userInfo: nil)
coralogixIntegration.reportError(exception: nsException)

let nsError = NSError(domain: "com.example.error", code: 1001, userInfo: [NSLocalizedDescriptionKey: "An error occurred"])
coralogixIntegration.reportError(error: nsError)

let error: Error = MyCustomError.someError
coralogixIntegration.reportError(error: error)

coralogixIntegration.reportError(message: "An error occurred", data: ["key": "value"])
```

#### Logging
```swift
coralogixIntegration.log(severity: .error, message: "A critical error occurred", data: ["key": "value"])
```
#### Shutting Down
```swift
coralogixIntegration.shutdown()
```

## About Method Swizzling and SwiftUI Modifiers
### Method Swizzling
Method swizzling is a technique used in Objective-C and Swift that allows the changing of the implementation of an existing selector at runtime. This can be used to inject custom behavior into existing methods without altering the original code. However, method swizzling can lead to maintenance challenges and unpredictable behavior, especially with system APIs.

### SwiftUI Modifiers
In contrast, SwiftUI provides a more declarative and safe approach to modifying views through view modifiers. Modifiers in SwiftUI are reusable, composable, and maintainable. The CXViewModifier is an example of a custom view modifier that integrates seamlessly with SwiftUI, enabling you to add custom behavior to views in a structured and predictable manner.

By using the ```CXViewModifier``` and the ```trackCXView``` method, you can achieve functionality similar to method swizzling but in a more SwiftUI-friendly way. This approach adheres to SwiftUI's declarative syntax, ensuring better readability and maintainability of your code.
Use this manually whenever you want to track Screen Name within swiftUI project.

### Usage:
```swift
    import SwiftUI

    struct ContentView: View {
        var body: some View {
            Text("Hello, World!")
                .trackCXView(name: "ContentView")
        }
    }
```

## Troubleshooting

- For technical issues, please [review open issues]

