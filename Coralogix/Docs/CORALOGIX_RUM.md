# Coralogix RUM - Native iOS

>[!IMPORTANT]
 <br/> <b>SwiftUI</b> screen navigation tracking is available from `iOS 13`.

>[!IMPORTANT]
>Requirements:
>- Deployment target of `iOS 13` or higher 
>- Swift Compatibility `5.9` or higher
>- Xcode `14` or higher

## Step 1. Add the Coralogix SDK
### Swift Package Manager:

1. Open _File -> Add Packages_.
2. Search for: `git@github.com:coralogix/cx-ios-sdk`.
3. Select _Up to Next Major Version_.

## Step 2. Establish a connection to Coralogix's server on app launch

>[!NOTE]
>The `API Key` can be found in your Coralogix page under DataFlow -> API Keys.

>[!IMPORTANT]
>**Thread Safety:** Coralogix RUM **must be initialized on the main thread**.
>
>✅ **Correct:** Initialize in `application(_:didFinishLaunchingWithOptions:)` or `scene(_:willConnectTo:options:)`
>
>❌ **Incorrect:** Initializing on a background thread will log a warning and may cause blocking or performance issues.
>
>```swift
>// ✅ CORRECT - On main thread
>func application(...) {
>    self.coralogixRum = CoralogixRum(options: options)
>}
>
>// ❌ INCORRECT - On background thread
>DispatchQueue.global().async {
>    self.coralogixRum = CoralogixRum(options: options)  // May block - will synchronously hop to main
>}
>```

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
                                               labels: ["String" : Any],
                                               sessionSampleRate: 100,
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
        let options = CoralogixExporterOptions(coralogixDomain: domain,
                                               userContext: nil,
                                               environment: "ENVIRONMENT",
                                               application: "APP-NAME",
                                               version: "APP-VERSION",
                                               publicKey: "TOKEN",
                                               ignoreUrls: [],
                                               ignoreErrors: [],
                                               labels: ["String" : Any],
                                               sessionSampleRate: 100,
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
                                               labels: ["String" : Any],
                                               sessionSampleRate: 100,
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
public func setUserContext(userContext: UserContext?)
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

### reportError (hybrid stack trace)
```swift
public func reportError(message: String,
                        stackTrace: [[String: Any]],
                        errorType: String?,
                        isCrash: Bool = false,
                        arch: String? = nil,
                        buildId: String? = nil,
                        stackTraceType: String? = nil)
```
Reports an error from a hybrid framework (React Native, Flutter symbolicated) using a pre-parsed stack trace. Each frame is a dictionary with keys such as `functionName`, `fileName`, `lineNumber`, and `columnNumber`.

#### Parameters
* message: A string describing the error.
* stackTrace: An array of frame dictionaries.
* errorType: An optional string identifying the error type (e.g. `"FlutterError"`).
* isCrash: Whether the error was fatal. Defaults to `false`.
* arch: Optional CPU architecture string (e.g. `"arm64"`).
* buildId: Optional build identifier used for symbolication.
* stackTraceType: Optional stack trace type label (e.g. `"symbolicated"`).

### reportError (obfuscated Flutter stack trace)
```swift
public func reportError(message: String,
                        obfuscatedStackTrace: [String],
                        arch: String? = nil,
                        buildId: String? = nil,
                        stackTraceType: String? = Keys.obfuscated.rawValue)
```
Reports a Dart obfuscated error from Flutter. Use this when the stack trace contains raw virtual addresses produced by a `--obfuscate --split-debug-info` build. The server uses `arch` and `buildId` together with the app's debug symbols to symbolicate the addresses.

#### Parameters
* message: A string describing the error.
* obfuscatedStackTrace: An array of virtual address strings (e.g. `["0x00000000003da15f", ...]`). May be empty — the error is still reported with its message and metadata.
* arch: Optional CPU architecture string (e.g. `"arm64"`).
* buildId: Optional build identifier used to symbolicate the addresses on the server.
* stackTraceType: The stack trace type label. Defaults to `"obfuscated"`.

#### Example
```swift
coralogixRum.reportError(
    message: "StateError: bad state",
    obfuscatedStackTrace: [
        "0x00000000003da15f",
        "0x000000000022d923"
    ],
    arch: "arm64",
    buildId: "e4f372b4e5cb2ba87653648d9c509cb1"
)
```

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

## Custom spans (manual tracing)

The Custom Spans API mirrors the Coralogix Browser SDK naming (`startCustomSpan`, `endSpan`, not `startChildSpan` / `end`). Exported RUM matches the browser: `event_context.type` is **`custom-span`**, with **`source`** `code` and **info** severity (unless you override attributes on the underlying OTel span). Nested spans receive the same session and user metadata as the global span so each ended span can be encoded for RUM export.

Only **one** global custom span may exist at a time (same as the Browser SDK). `startGlobalSpan` registers it as the **active OpenTelemetry span**, so auto-instrumented spans and network propagation can share the same `traceId` until `endSpan()` (which restores the prior active context). `withContext` is a no-op when the global span is already active. `shutdown()` clears a leaked global registration.

### Types

- `CoralogixIgnoredInstrument` — `.networkRequests`, `.userInteractions`, `.errors` (values are reserved for future behavior when combining auto-instrumentation with custom traces).
- `CoralogixCustomTracer` — from `getCustomTracer(ignoredInstruments:)`.
- `CoralogixGlobalSpan` — root span from `startGlobalSpan(name:labels:)`; exposes `span`, `withContext(_:)`, `startCustomSpan(name:labels:)`, `endSpan()`.
- `CoralogixCustomSpan` — nested span; exposes `span`, `endSpan()`, `setAttribute`, `addEvent`, `setStatus`.

### Example

```swift
let tracer = coralogixRum.getCustomTracer(ignoredInstruments: [.networkRequests])
guard let global = tracer.startGlobalSpan(name: "checkout", labels: ["step": "payment"]) else { return }

global.withContext {
    let child = global.startCustomSpan(name: "authorize")
    child.setAttribute(key: "result", value: "ok")
    child.endSpan()
}

global.endSpan()
```

`startGlobalSpan` returns `nil` if the SDK did not finish initialization (for example, sampling disabled the SDK).

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

### SDK Initialization Issues

**Warning:** "SDK initialized off main thread - dispatching to main (may block)"

**Cause:** Coralogix RUM was initialized on a background thread instead of the main thread.

**Solution:** Always initialize the SDK on the main thread:

```swift
// ✅ CORRECT - In AppDelegate on main thread
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
    self.coralogixRum = CoralogixRum(options: options)  // Runs on main thread
    return true
}

// ❌ INCORRECT - On background thread
DispatchQueue.global().async {
    self.coralogixRum = CoralogixRum(options: options)  // May cause warning and blocking
}
```

**Impact:** Initializing on a background thread is safe but may cause:
- Warning messages in logs
- May block the background thread while dispatching to main (typically <1ms)
- Potential performance degradation during initialization
- In debug builds: Assertion failure to help catch the issue early

**Best Practice:** Always initialize Coralogix RUM in `application(_:didFinishLaunchingWithOptions:)`, `scene(_:willConnectTo:options:)`, or other main-thread lifecycle methods.

---

### General Issues

- For technical issues, please [review open issues]

