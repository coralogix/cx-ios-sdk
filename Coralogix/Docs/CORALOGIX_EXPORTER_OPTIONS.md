# CoralogixExporterOptions

The `CoralogixExporterOptions` struct provides configuration options for the Coralogix exporter. Below are the detailed descriptions of its properties.

## Properties

### userContext
```swift
var userContext: UserContext?
Configuration for user context. This is an optional property.
```
### debug
```swift
let debug: Bool
```
Turns on/off internal debug logging. This is a required property.

### ignoreUrls
```swift
let ignoreUrls: [String]?
```
URLs that partially match any regex in ignoreUrls will not be traced. In addition, URLs that are exact matches of strings in ignoreUrls will also not be traced. This is an optional property.

### ignoreErrors
```swift
let ignoreErrors: [String]?
```
A pattern for error messages which should not be sent to Coralogix. By default, all errors will be sent. This is an optional property.

### coralogixDomain
```swift
let coralogixDomain: CoralogixDomain
```
Coralogix account domain. This is a required property.

### publicKey
```swift
var publicKey: String
```
Coralogix token, publicly-visible public_key value. This is a required property.

### environment
```swift
let environment: String
```
Specifies the environment, such as development, staging, or production. This is a required property.

### application
```swift
let application: String
```
Name of the application. This is a required property.

### version
```swift
let version: String
```
Version of the application. This is a required property.

### labels
```swift
var labels: [String: Any]?
```
Sets labels that are added to every Span. This is an optional property.

### sessionSampleRate (init parameter)
```swift
sessionSampleRate: Int = 100  // percent 0–100
```
Session sampling: percentage of sessions that initialize the SDK. `0` means the SDK will not initialize; `100` means all sessions are sampled. Stored internally via `sdkSampler`.

### networkExtraConfig
```swift
var networkExtraConfig: [NetworkCaptureRule]?
```
Per-URL rules for capturing request/response headers and body payloads for matching network requests. `nil` (default) disables all such capture. Each rule specifies a URL matcher (substring or regex), optional allowlists for `reqHeaders`/`resHeaders`, and optional `collectReqPayload`/`collectResPayload`. Only allowlisted header names appear in RUM; only allowlist URLs and headers you are comfortable logging (e.g. avoid `Authorization` unless intentional). Bodies are stringified by content-type (e.g. JSON, text); those over 1024 characters are **dropped**, not truncated. File URLs (download tasks) are read with a size cap. See `NetworkCaptureRule` for initializers and behavior.

### mobileVitalsFPSSamplingRate
```swift
let mobileVitalsFPSSamplingRate: Int
```
Defines the interval, in seconds, at which the SDK will perform FPS sampling. This value determines how frequently the FPS (Frames Per Second) calculator should be triggered, allowing the SDK to monitor rendering performance at regular intervals.

### Usage Examples
#### Ignoring Specific URLs
You can exclude certain URLs from being captured or instrumented by using the ignoreUrl property. There are two ways to define which URLs to ignore:

1. Exact Match
Provide the full URL string to ignore a specific request:

```swift
ignoreUrl: ["https://jsonplaceholder.typicode.com/posts"]
```
This will ignore only the exact URL above — it won't match any variations like query parameters or sub-paths.

2. Regex Pattern
Use a regex string to match a broader pattern. For example, to ignore any URL containing /posts, such as:

    https://jsonplaceholder.typicode.com/posts

    https://jsonplaceholder.typicode.com/posts/1

    https://jsonplaceholder.typicode.com/posts/123?userId=4

you can use:

```swift
ignoreUrl: [#"/posts(/\d+)?(\?.*?)?"#]
```

This pattern matches /posts, /posts/ID, and optional query parameters.

⚠️ Regex patterns must follow Swift's raw string literal syntax (#""#) when defined in code.

