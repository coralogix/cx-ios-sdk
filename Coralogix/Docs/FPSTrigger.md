
# FPSDetector

`FPSDetector` is a class that uses the `FPSMonitor` class to periodically monitor the average FPS over a set duration, typically 5 seconds, and sends the result through a notification.

## Properties

- `private let fpsMonitor = FPSMonitor()`  
  An instance of `FPSMonitor` used to track FPS.

- `internal var timer: Timer?`  
  A timer that triggers FPS monitoring at regular intervals.

- `internal var isRunning = false`  
  A flag indicating whether the monitoring is currently running.

- `static let defaultInterval = 300`  
  The default number of times to trigger FPS monitoring per hour, set to 300 (every 5 minutes).

## Methods

### `startMonitoring(xTimesPerHour: Int = defaultInterval)`

Starts monitoring the FPS periodically. The method calculates the time interval between each FPS monitoring session, which defaults to 5 minutes if not specified. A `Timer` is created to trigger FPS monitoring based on this interval.

### `private func monitorFPS()`

Logs a message and starts monitoring the FPS for 5 seconds. Once the monitoring period is over, the average FPS is logged and sent via `NotificationCenter` as a `cxRumNotificationMetrics` event.

### `func stopMonitoring()`

Stops the monitoring process by invalidating the `Timer` and resetting the `isRunning` flag.

## Usage Example

```swift
let fpsDetector = FPSDetector()
fpsDetector.startMonitoring(xTimesPerHour: 12) // Triggers every 5 minutes

// To stop monitoring
fpsDetector.stopMonitoring()
