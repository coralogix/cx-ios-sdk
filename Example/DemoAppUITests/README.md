# DemoApp UI Tests

This directory contains UI tests for the DemoApp iOS application.

## Test Files

- `DemoAppUITests.swift` - Contains the main UI test cases
- `Info.plist` - Configuration file for the UI test target

## Test Cases

### testClickClockButton()
This test:
1. Launches the DemoApp
2. Resets network logs (if debug mode)
3. Finds and taps the "Clock" button in the table
4. Waits for the Clock view controller to load
5. Navigates to the Debug Network Logs screen
6. Verifies that a network request to "/logs" was made with status code 200
7. Prints all network logs for debugging

## Network Monitoring

The test uses a custom URLProtocol (`TestNetworkObserver`) that:
- Intercepts all network requests made by the app
- Logs the URL and status code of each response
- Exposes the logs through a debug UI accessible to UI tests
- Only runs in DEBUG builds (does not affect production)

## Debug Features

In DEBUG builds, the app includes:
- A "Debug Network Logs" button in the main menu
- A debug screen showing all network requests and their status codes
- Ability to clear logs and refresh the display

## Setup Instructions

1. Open `DemoApp.xcodeproj` in Xcode
2. Right-click on the project in the navigator
3. Select "New Target"
4. Choose "iOS" → "UI Testing Bundle"
5. Set the following options:
   - Product Name: `DemoAppUITests`
   - Language: `Swift`
   - Target to be Tested: `DemoAppSwift`
6. Click "Finish"

## Running the Tests

### Option 1: Using Xcode UI
1. Select the `DemoAppSwift` scheme in Xcode
2. Press `Cmd+U` to run tests
3. Or select Product → Test from the menu

### Option 2: Using Command Line (Single Simulator)
Run tests on a single simulator (recommended to avoid multiple simulator instances):

```bash
cd Example
xcodebuild test -project DemoApp.xcodeproj -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoAppUITests -parallel-testing-enabled NO
```

### Option 3: Using Command Line (Parallel Testing)
Run tests with parallel testing (may open multiple simulators):

```bash
cd Example
xcodebuild test -project DemoApp.xcodeproj -scheme DemoAppSwift -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'
```

### Available Simulators
To see available simulators, run:
```bash
xcrun simctl list devices
```

## Test Requirements

- iOS Simulator or physical device
- DemoAppSwift target must be built successfully
- The app must be able to launch and display the main table view

## Troubleshooting

If tests fail:
1. Make sure the DemoAppSwift target builds successfully
2. Verify that the "Clock" button text is exactly "Clock" in the Keys.swift file
3. Check that the ClockViewController is properly implemented
4. Ensure the simulator/device is running the correct iOS version 
