# CoralogixLogSeverity

The `CoralogixLogSeverity` enum represents the different severity levels for logs in the Coralogix logging system. Each case has an associated integer value.

## Cases

### debug
```swift
case debug = 1
```
Represents debug-level severity. This is used for detailed troubleshooting information.

### verbose
```swift
case verbose = 2
```
Represents verbose-level severity. This is used for more detailed informational events than the standard info level.

### info
```swift
case info = 3
```
Represents informational severity. This is used for general informational messages.

### warn
```swift
case warn = 4
```
Represents warning-level severity. This is used for potentially harmful situations.

### error
```swift
case error = 5
```
Represents error-level severity. This is used for error events that might still allow the application to continue running.

### critical
```swift
case critical = 6
```
Represents critical-level severity. This is used for severe error events that will presumably lead the application to abort.

### Usage Example
Here is an example of how to use the CoralogixLogSeverity enum:

```swift
func logMessage(severity: CoralogixLogSeverity, message: String) {
    switch severity {
    case .debug:
        print("DEBUG: \(message)")
    case .verbose:
        print("VERBOSE: \(message)")
    case .info:
        print("INFO: \(message)")
    case .warn:
        print("WARN: \(message)")
    case .error:
        print("ERROR: \(message)")
    case .critical:
        print("CRITICAL: \(message)")
    }
}

logMessage(severity: .error, message: "An error occurred in the application.")
```
This enum provides a straightforward way to classify and handle log messages based on their severity level.

