# SlowFrozenFramesDetector

The `SlowFrozenFramesDetector` is an advanced performance monitoring tool designed to identify UI unresponsiveness by detecting and quantifying "slow" and "frozen" frames. It provides a statistical summary of UI performance over time using a unique windowed reporting approach, making it ideal for understanding the frequency and severity of UI stutters. 📱💨

---

## Key Concepts

To understand this detector, it's important to grasp three core concepts:

* **Slow Frame**: A frame that takes longer to render than the ideal time budget determined by the screen's refresh rate. For a 60Hz screen, the budget is ~16.7ms; for a 120Hz ProMotion screen, it's ~8.3ms. A slow frame causes minor, often perceptible, stutters or "jank" in animations and scrolling.
* **Frozen Frame**: A frame that takes a significantly long time to render (by default, > 700ms). This indicates a major blockage on the main thread and results in a noticeable, prolonged freeze of the UI.
* **Reporting Window**: Instead of reporting every single bad frame, the detector groups data into configurable time windows (e.g., 60 seconds). At the end of each window, it reports the **total number** of slow and frozen frames that occurred during that period.

---

## How It Works

The detector uses a sophisticated two-timer system to measure and report frame performance.

1.  **Frame Synchronization**: It uses a `CADisplayLink`, a high-precision timer synchronized with the display's refresh rate. This link executes a callback function (`onFrame`) every time the screen is about to be redrawn.
2.  **Per-Frame Analysis**: In the `onFrame` callback, it calculates the time elapsed since the *previous* frame. It then compares this duration against the calculated slow and frozen frame thresholds.
3.  **Real-Time Counting**: If a frame is identified as slow or frozen, a thread-safe counter (`slowCount` or `frozenCount`) is incremented. These counters accumulate all bad frames within the current reporting window.
4.  **Windowed Reporting**: A separate, lower-precision background timer (`DispatchSourceTimer`) fires periodically based on the `reportIntervalMs` (e.g., every 60 seconds). This triggers the `emitWindow` function.
5.  **Data Aggregation**: `emitWindow` takes a snapshot of the current `slowCount` and `frozenCount`, appends these totals to the `windowSlow` and `windowFrozen` arrays, and then resets the counters to zero for the next window.
6.  **Dynamic Adaptation**: The detector automatically adjusts its "slow frame" budget based on the device's screen refresh rate, correctly handling standard 60Hz displays, 120Hz ProMotion displays, and external monitors.

---

## Computed Statistics

The detector provides statistical analysis (`min`, `max`, `avg`, `p95`) over the collected reporting windows. This is a powerful feature that provides high-level insights. For example:

* **`avgSlow`** represents the **average number of slow frames per window**, giving you a baseline for typical UI stuttering.
* **`maxFrozen`** shows the **worst-case number of frozen frames** observed in any single window during the session.

---

## Methods

### `init(frozenThresholdMs:reportIntervalMs:tolerancePercentage:)`
Initializes the detector with custom thresholds.

### `startMonitoring()`
Starts the `CADisplayLink` to begin monitoring frame times and schedules the periodic reporter.

### `stopMonitoring()`
Stops both the display link and the reporter timer, and flushes any remaining data from the current window.

### `reset()`
Clears all stored window data (`windowSlow`, `windowFrozen`) to begin a new measurement session.

### `statsDictionary() -> [String: Any]`
Returns a dictionary containing the latest computed statistics (`min`, `max`, `avg`, `p95`) for both slow and frozen frame counts, ready for logging.

---
