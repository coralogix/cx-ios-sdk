# ColdDetector

The `ColdDetector` is a Swift class designed to measure the **cold start time** of an application. A cold start occurs when the application is launched from a terminated state (i.e., not from the background). This metric is crucial for performance monitoring, as it measures the time from the initial launch process until the first user interface is displayed.

---

## How It Works

The detector's mechanism relies on observing a specific point in the application's launch sequence.

1.  **Initiation**: The `startMonitoring()` method is called at the earliest possible point in the application's lifecycle, typically within the `AppDelegate`'s `application(_:didFinishLaunchingWithOptions:)`. It immediately records the current time as `launchStartTime`.
2.  **Listening**: The detector registers as an observer for a custom `Notification` named `.cxViewDidAppear`.
3.  **Completion Signal**: Another part of the application is responsible for posting the `.cxViewDidAppear` notification when the first view controller's UI becomes visible to the user (e.g., in its `viewDidAppear(_:)` method). This notification must contain the timestamp of the event.
4.  **Calculation**: Upon receiving the notification, the `handleNotification(notification:)` method is triggered. It retrieves the end timestamp from the notification's payload, calculates the total duration in milliseconds, and ensures this calculation is performed only once per launch.
5.  **Handling**: The final cold start duration is packaged into a dictionary and passed to the `handleColdClosure` for custom processing, such as sending the metric to an analytics service.
6.  **Cleanup**: The `deinit` method properly removes the notification observer to prevent memory leaks and dangling references.

---

## Properties

* `launchStartTime: CFAbsoluteTime?`
    * Stores the timestamp when monitoring begins. This marks the start of the cold launch measurement.

* `launchEndTime: CFAbsoluteTime?`
    * Stores the timestamp when the first UI is displayed. It also acts as a flag to ensure the cold start duration is calculated only once.

* `handleColdClosure: (([String: Any]) -> Void)?`
    * An optional closure that is executed with the cold start data once the measurement is complete. This allows for flexible handling of the result.

---

## Methods

### `startMonitoring()`

Begins the cold start measurement process. It records the start time and sets up the listener for the `.cxViewDidAppear` notification.

### `handleNotification(notification: Notification)`

The function executed when the `.cxViewDidAppear` notification is received. It finalizes the measurement, calculates the duration, and calls the handler closure.

### `calculateTime(start: Double, stop: Double) -> Double`

A helper function that computes the difference between two epoch timestamps, ensuring the result is non-negative.

---

