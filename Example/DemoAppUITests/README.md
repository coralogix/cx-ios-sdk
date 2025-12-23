# DemoApp UI Tests

This directory contains UI tests for the DemoApp iOS application.

## Running the Tests

```bash
cd ..
xcodebuild test -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

Or to run only the UI tests:

```bash
xcodebuild test -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:DemoAppUITests
```

## Test Cases

### `testSchemaValidationFlow()`

This comprehensive end-to-end test validates that the Coralogix SDK correctly captures and reports telemetry data that conforms to the expected schema.

#### Tests Covered:

1. **Failing Network Request** - Validates schema for failed network calls
2. **Successful Network Request** - Validates schema for successful network calls
3. **Error (Swift Error Type)** - Validates schema for Swift Error objects
4. **Error (Custom Log)** - Validates schema for custom error logs
5. **Stack Trace Error** - RN / Flutter 
6. **Send Custom Measurement** - Validates schema for custom performance metrics
7. **Log with Custom Labels** - Validates schema for logs with custom label metadata
