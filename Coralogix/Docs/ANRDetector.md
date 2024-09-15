## Overview

`ANRDetector` is a utility class designed to monitor the application's main thread and detect Application Not Responding (ANR) incidents. If the main thread becomes unresponsive for longer than a specified threshold, the detector will trigger a predefined action (e.g., logging or notifying the user). This class is particularly useful for debugging and performance monitoring in mobile applications.

### Key Features
- **Customizable Monitoring**: The class allows you to specify the time interval for checking ANR and the maximum allowable time for the main thread to be blocked.
- **Automatic Monitoring**: The class uses a timer to periodically check for main thread responsiveness.
- **ANR Handling**: Provides a closure for handling ANR incidents, which can be customized for specific actions like logging or sending notifications.

---

```swift
let anrDetector = ANRDetector(checkInterval: 1.0, maxBlockTime: 5.0)
anrDetector.startMonitoring()

// Custom ANR handler
anrDetector.handleANRClosure = {
    print("ANR detected! Custom handling logic goes here.")
}

// Stop monitoring when needed
anrDetector.stopMonitoring()
