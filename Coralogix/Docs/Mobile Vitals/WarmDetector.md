# WarmDetector

The `WarmDetector` is a Swift class that measures the **warm start time** of an application. A warm start occurs when a user returns to the app while it's still resident in memory (i.e., suspended in the background). This detector measures the time elapsed from when the app begins its transition to the foreground until it becomes fully active and ready for user interaction. ⏱️

---

## How It Works

The detector hooks into the standard `UIApplication` lifecycle notifications to measure the duration accurately. The process is as follows:

1.  **Arming**: When the app moves to the background (`UIApplication.didEnterBackgroundNotification`), the detector sets an internal flag, `warmMetricIsActive`, to `true`. This "arms" the detector, indicating that the next foreground event should be measured as a warm start.
2.  **Start Measurement**: As the app begins returning to the foreground (`UIApplication.willEnterForegroundNotification`), the detector checks the flag. If it's armed, it records the current time as `foregroundStartTime`.
3.  **End Measurement**: When the app has finished its transition and is fully active (`UIApplication.didBecomeActiveNotification`), the detector captures the `foregroundEndTime`.
4.  **Calculation**: The duration between the start and end times is calculated, converted to milliseconds, and passed to the `handleWarmClosure` for reporting. This logic is designed to run only once per foregrounding event.
5.  **Cleanup**: The `deinit` method automatically removes all notification observers to prevent memory leaks.

### Framework Compatibility

This detector works across all supported frameworks: **native Swift**, **Flutter**, and **React Native**.

`UIApplication` lifecycle notifications (`willEnterForegroundNotification`, `didBecomeActiveNotification`, `didEnterBackgroundNotification`) are standard iOS system notifications fired by the OS for every iOS app, regardless of the framework running on top of UIKit. Flutter and React Native apps receive these notifications identically to native apps.

---

## Properties

* `foregroundStartTime: CFAbsoluteTime?`
    * Stores the timestamp when the app begins to enter the foreground.

* `foregroundEndTime: CFAbsoluteTime?`
    * Stores the timestamp when the app becomes fully active. It also serves as a flag to prevent duplicate calculations.

* `warmMetricIsActive: Bool`
    * A flag that is set to `true` when the app enters the background, arming the detector to measure the next foreground transition.

* `handleWarmClosure: (([String: Any]) -> Void)?`
    * An optional closure that is executed with the warm start data once the measurement is complete.

---

## Methods

### `startMonitoring()`

Initializes the detector by adding observers for the necessary `UIApplication` lifecycle notifications (`didEnterBackground`, `willEnterForeground`, `didBecomeActive`).

### `@objc` Notification Handlers

* `appDidEnterBackgroundNotification()`: Arms the detector for the next warm start measurement.
* `appWillEnterForegroundNotification()`: Captures the start time for the measurement.
* `appDidBecomeActiveNotification()`: Captures the end time, performs the calculation, and triggers the handler closure.

---

