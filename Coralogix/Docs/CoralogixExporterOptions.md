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

### customDomainUrl
```swift
let customDomainUrl: String?
```
Ignore CoralogixDomain URL and route all data calls to a specific URL. This is an optional property.

### labels
```swift
var labels: [String: Any]?
```
Sets labels that are added to every Span. This is an optional property.

### sampleRate
```swift
let sampleRate: Int?
```
Sets sample rate, value between `0.0` and `100.0`, where `0.0` means SDK will not initialized and `100.0` means ALL events will be sent.


