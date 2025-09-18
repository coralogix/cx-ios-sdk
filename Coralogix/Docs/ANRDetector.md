# ANRDetector

The `ANRDetector` is a Swift class designed to detect "Application Not Responding" (ANR) events on the main thread of an iOS application. An ANR occurs when the main thread is blocked for an extended period, making the user interface unresponsive.

---

## How It Works

1.  **Monitoring Start**: When `startMonitoring()` is called, a `Timer` is scheduled on a background thread. This timer fires repeatedly at a specified `checkInterval`.
2.  **Responsiveness Check**: Each time the timer fires, the `checkForANR()` method is executed.
    * It sets a flag, `isMainThreadResponsive`, to `false`.
    * It then asynchronously dispatches a block of code to the main thread.
3.  **Main Thread Task**: The task dispatched to the main thread, if executed promptly, will:
    * Set the `isMainThreadResponsive` flag back to `true`.
    * Update the `lastCheckTimestamp` to the current time.
4.  **ANR Detection**: If the main thread is blocked, it won't execute its dispatched task in time. On a subsequent check, the `checkForANR()` method will find that `isMainThreadResponsive` is still `false`. If the time elapsed since `lastCheckTimestamp` also exceeds `maxBlockTime`, the detector concludes that an ANR has occurred and calls the `handleANR()` method.

---

## Properties

* `timer: Timer?`
    * The timer instance that triggers the responsiveness checks at regular intervals.

* `checkInterval: TimeInterval`
    * The time interval in seconds between each check. **Default**: `1.0` second.

* `maxBlockTime: TimeInterval`
    * The maximum duration in seconds the main thread can be unresponsive before an ANR is declared. **Default**: `5.0` seconds.

* `handleANRClosure: (([String: Any]) -> Void)?`
    * An optional closure that is executed when an ANR is detected. This is primarily useful for testing and custom handling logic.

---

## Methods

### `init(checkInterval: TimeInterval = 1.0, maxBlockTime: TimeInterval = 5.0)`

Initializes a new instance of the `ANRDetector` with a specified check interval and maximum block time.

### `startMonitoring()`

Starts the ANR detection process by creating and scheduling the background timer.

### `stopMonitoring()`

Stops the ANR detection by invalidating and releasing the timer.

### `handleANR()`

This method is called when an ANR event is detected. It logs a message to the console and invokes the `handleANRClosure` if one is provided.

---
