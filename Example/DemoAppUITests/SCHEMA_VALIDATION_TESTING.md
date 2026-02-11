# Schema Validation Testing Approach

## Overview

The network instrumentation UI tests now use **end-to-end schema validation** instead of local file-based logging. This ensures requests actually reach the Coralogix backend and conform to the expected schema.

## Architecture

```
┌─────────────────┐
│   UI Test       │
│  (XCTest)       │
└────────┬────────┘
         │ 1. Triggers network requests
         ▼
┌─────────────────┐
│   DemoApp       │
│  (Test Target)  │
└────────┬────────┘
         │ 2. SDK instruments & sends data
         ▼
┌─────────────────┐
│  Coralogix      │
│   Backend       │
└────────┬────────┘
         │ 3. Stores logs
         ▼
┌─────────────────┐
│ Schema          │
│ Validator API   │
└────────┬────────┘
         │ 4. Returns validation results
         ▼
┌─────────────────┐
│ Schema          │
│ Validation VC   │
└────────┬────────┘
         │ 5. UI test reads validation data
         ▼
┌─────────────────┐
│ Verification    │
│ & Assertions    │
└─────────────────┘
```

## Changes Made

### 1. SchemaValidationViewController.swift

**Added test mode support:**

```swift
// In validateSchemaResponse()
if CommandLine.arguments.contains("--uitesting") {
    saveValidationDataForTesting(data)
}

// New method
private func saveValidationDataForTesting(_ validationData: [[String: Any]]) {
    let testDataPath = "/tmp/coralogix_validation_response.json"
    
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: validationData, options: .prettyPrinted)
        try jsonData.write(to: URL(fileURLWithPath: testDataPath))
        print("💾 Saved validation data for testing: \(testDataPath)")
        print("💾 Saved \(validationData.count) log entries")
    } catch {
        print("❌ Failed to save validation data: \(error)")
    }
}
```

**What it does:**
- When running in test mode (`--uitesting` flag)
- Saves raw validation response to `/tmp/coralogix_validation_response.json`
- Allows UI tests to read and verify specific requests

### 2. NetworkInstrumentationUITests.swift

**Complete rewrite:**

#### Old Approach (File-based logging):
```swift
// ❌ Old: Write logs to file
Log.testLog("[URLSessionInstrumentation] Logging response...")

// ❌ Old: Read from file
let logs = try? String(contentsOfFile: "/tmp/coralogix_test_logs.txt")

// ❌ Old: Check if logs contain expected strings
XCTAssertTrue(logs.contains("status: 200"))
```

**Problems:**
- Only validates local logging, not actual backend transmission
- No schema compliance validation
- Timing issues with file I/O
- Doesn't test production flow

#### New Approach (Schema validation):
```swift
// ✅ New: Trigger all network requests
navigateToNetworkInstrumentation()
app.staticTexts["Async/Await example"].tap()
app.staticTexts["Alamofire success"].tap()
// ... etc

// ✅ New: Navigate to schema validation
navigateToSchemaValidation()
triggerValidation()

// ✅ New: Verify schema passed
verifySchemaValidationPassed()

// ✅ New: Verify specific status codes
let expectedRequests = [
    ("jsonplaceholder.typicode.com/posts", 201, "Async/Await POST"),
    ("jsonplaceholder.typicode.com/posts1", 404, "Failing GET"),
    // ... etc
]
verifyExpectedRequests(expectedRequests)
```

**Benefits:**
- ✅ Validates actual backend transmission
- ✅ Confirms schema compliance
- ✅ Production-like testing
- ✅ Single comprehensive test
- ✅ No file I/O timing issues

## Test Flow

### Step-by-Step:

1. **Setup** (`setUpWithError`)
   - Launch app with `--uitesting` flag
   - Clear previous validation data

2. **Trigger Requests** (`testAllNetworkInstrumentationWithSchemaValidation`)
   ```swift
   // Navigate to network instrumentation screen
   navigateToNetworkInstrumentation()
   
   // Trigger all network request types
   app.staticTexts["Async/Await example"].tap()
   app.staticTexts["Alamofire success"].tap()
   app.staticTexts["Alamofire failure"].tap()
   // ... etc (9 different request types)
   
   // Wait for SDK to batch and send
   Thread.sleep(forTimeInterval: 5)
   ```

3. **Validate Schema** 
   ```swift
   // Navigate to schema validation screen
   navigateBackToMainMenu()
   navigateToSchemaValidation()
   
   // Tap "Validate Schema" button
   triggerValidation()
   ```

4. **Verify Results**
   ```swift
   // Check UI shows success
   verifySchemaValidationPassed()
   
   // Read saved validation data
   let validationData = readValidationData()
   
   // Verify each expected request
   for request in expectedRequests {
       verifyRequestInValidationData(
           validationData: validationData,
           urlPattern: request.url,
           expectedStatusCode: request.statusCode
       )
   }
   ```

## Validation Data Format

The validation response saved by `SchemaValidationViewController` has this structure:

```json
[
  {
    "network_request_context": {
      "url": "https://jsonplaceholder.typicode.com/posts",
      "status_code": 201,
      "method": "POST",
      "host": "jsonplaceholder.typicode.com",
      "duration": 1234
    },
    "validationResult": {
      "statusCode": 200,
      "message": []
    },
    "session_context": { ... },
    "user_context": { ... }
  },
  {
    "network_request_context": {
      "url": "https://jsonplaceholder.typicode.com/posts1",
      "status_code": 404,
      "method": "GET"
    },
    "validationResult": {
      "statusCode": 200,
      "message": []
    }
  }
  // ... more log entries
]
```

## Test Coverage

| # | Request Type | Library | Method | Status Code | Instrumentation Method |
|---|-------------|---------|--------|-------------|------------------------|
| 1 | Async/Await POST | URLSession | async/await | 201 | FakeDelegate |
| 2 | Successful GET | URLSession | Completion | 200 | Completion wrapper |
| 3 | Failing GET | URLSession | Completion | 404 | Completion wrapper |
| 4 | POST request | URLSession | Completion | 201 | Completion wrapper |
| 5 | GET request | URLSession | Completion | 200 | Completion wrapper |
| 6 | Alamofire success | Alamofire | Delegate | 200 | setState: fallback |
| 7 | Alamofire failure | Alamofire | Delegate | 404 | setState: fallback |
| 8 | Alamofire upload | Alamofire | Upload | 201 | setState: fallback |
| 9 | AFNetworking | AFNetworking | Delegate | 200 | setState: fallback |

**Total: 9 comprehensive E2E tests in a single test method**

## Running Tests

### Xcode UI:
1. Open `Example/DemoApp.xcworkspace`
2. Select `DemoAppUITests` scheme
3. Click the diamond (◇) next to `testAllNetworkInstrumentationWithSchemaValidation()`
4. Wait ~30 seconds for completion

### Command Line:
```bash
cd Example
xcodebuild test \
  -workspace DemoApp.xcworkspace \
  -scheme DemoAppUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:DemoAppUITests/NetworkInstrumentationUITests/testAllNetworkInstrumentationWithSchemaValidation
```

### Quick Smoke Test:
```bash
# Faster test with single request
-only-testing:DemoAppUITests/NetworkInstrumentationUITests/testQuickSmokeTest
```

## Verification Points

Each test verifies:

1. ✅ **Schema Compliance**
   - UI shows "All logs are valid! ✅"
   - Backend validates against Coralogix schema
   - No validation errors in response

2. ✅ **Status Codes**
   - Each request logged with correct HTTP status
   - 200 for successful requests
   - 201 for POST/upload requests
   - 404 for failure requests

3. ✅ **URL Patterns**
   - Correct endpoints called
   - Request URLs match expectations

4. ✅ **Backend Transmission**
   - Data actually reaches Coralogix backend
   - Not just local logging
   - End-to-end validation

## Debugging

If a test fails:

1. **Check UI status label:**
   ```
   ❌ SCHEMA VALIDATION FAILED!
   📋 Status labels found:
      - Validation Failed:
      - network_request_context.url: Required field is missing
   ```

2. **Check console output:**
   ```
   📊 Read 15 log entries from validation response
   ✅ Found: jsonplaceholder.typicode.com/posts with status 201
   ❌ Missing: api.escuelajs.co/api/v1/files/upload with status 201
   ```

3. **Inspect validation data:**
   ```bash
   cat /tmp/coralogix_validation_response.json | jq '.[] | .network_request_context'
   ```

4. **Common issues:**
   - Backend unavailable → Check proxy URL in `envs.swift`
   - Schema validation fails → Check SDK version matches expected schema
   - Missing requests → Increase wait times for SDK batching

## Migration Notes

### Removed:
- ❌ `clearTestLogs()` - No longer needed
- ❌ `getTestLogs()` - No longer needed
- ❌ `verifyLogContains()` - Replaced by schema validation
- ❌ `Log.testLog()` calls - No longer needed for verification
- ❌ Individual test methods for each request type

### Added:
- ✅ `navigateToSchemaValidation()` - Navigate to validation screen
- ✅ `triggerValidation()` - Tap validate button
- ✅ `verifySchemaValidationPassed()` - Check success message
- ✅ `readValidationData()` - Read saved validation JSON
- ✅ `verifyRequestInValidationData()` - Check specific requests
- ✅ `verifyExpectedRequests()` - Batch verification
- ✅ `testAllNetworkInstrumentationWithSchemaValidation()` - Comprehensive E2E test
- ✅ `testQuickSmokeTest()` - Fast smoke test

## Advantages Over Previous Approach

| Aspect | Old (File-based) | New (Schema validation) |
|--------|------------------|-------------------------|
| **Validation** | Local logs only | Backend schema compliance |
| **Reliability** | File I/O timing issues | Direct API validation |
| **Coverage** | Per-request tests | Comprehensive E2E |
| **Production** | Mock behavior | Real backend flow |
| **Maintenance** | Many test methods | Single comprehensive test |
| **Speed** | 9 separate tests | 1 combined test |
| **Debugging** | Console logs | Structured JSON response |

## Future Enhancements

Potential improvements:

1. **Parallel request triggering** - Reduce test duration
2. **Retry logic** - Handle transient backend failures
3. **Schema version validation** - Verify SDK matches backend schema version
4. **Performance metrics** - Track request latency in validation data
5. **Custom validation rules** - Domain-specific assertions

## Conclusion

The new schema validation approach provides **true end-to-end testing** that validates:
- ✅ Requests leave the device
- ✅ SDK sends data to backend
- ✅ Logs conform to Coralogix schema
- ✅ Status codes match expectations
- ✅ Production-like behavior

This is a **significant improvement** over local file-based logging and provides much higher confidence in the SDK's network instrumentation capabilities.
