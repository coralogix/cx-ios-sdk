
# CPUDetector

The `CPUDetector` is a sophisticated utility class for monitoring and analyzing the CPU performance of a Swift application. It periodically samples CPU usage and provides detailed statistics for both the entire application process and the main thread specifically. 🖥️

---

## How It Works

The detector uses a timer-based approach combined with low-level system calls to gather precise performance data.

1.  **Periodic Sampling**: A `Timer` fires at a configurable `checkInterval` (e.g., every 1 second).
2.  **Low-Level APIs**: At each "tick," the detector uses the **Mach kernel APIs** (`task_info` for the process, `thread_info` for the main thread) to get the cumulative CPU time consumed.
3.  **Delta Calculation**: It calculates the change (delta) in real-world "wall clock" time and the delta in CPU time since the last tick.
4.  **Metric Computation**: Using these deltas, it computes key metrics for that interval and appends them to internal sample arrays.
5.  **Lifecycle Management**: The detector automatically pauses the timer when the app enters the background (`willResignActive`) and cleanly resumes when it becomes active again. This prevents measuring long periods of inactivity and ensures the collected data is relevant to the user-facing experience.

---

## Key Metrics Collected

For each sample interval, the detector calculates and stores three primary metrics:

* **CPU Usage (%)**: The app's total CPU consumption as a percentage of the device's total CPU capacity (all cores combined). This is calculated as `(CPU Time Delta / (Wall Clock Time Delta * Number of Cores)) * 100`.
* **Total Process CPU Time (ms)**: The raw amount of time, in milliseconds, that the CPU spent executing code for the *entire application process* during the interval.
* **Main Thread CPU Time (ms)**: The raw amount of CPU time, in milliseconds, spent executing code *specifically on the main thread*. This is critical for identifying UI stutters and performance bottlenecks.

---

## Computed Statistics

Instead of just providing raw data points, the `CPUDetector` automatically calculates and exposes a rich set of statistical summaries for all collected samples over a monitoring period:

* **Minimum** (`min`)
* **Maximum** (`max`)
* **Average** (`avg`)
* **95th Percentile** (`p95`)

These statistics are available for all three of the key metrics listed above.

---

## Methods

### `init(checkInterval: TimeInterval = 1.0)`
Initializes the detector with a specific sampling interval in seconds.

### `startMonitoring()`
Starts the periodic sampling process and registers for app lifecycle notifications.

### `stopMonitoring()`
Stops the sampling timer, removes notification observers, and clears all collected data.

### `reset()`
Clears all stored sample arrays (`usageSamples`, `totalCpuDeltaMsSamples`, `mainThreadDeltaMsSamples`) without stopping the timer. This is useful for starting a new measurement window.

### `statsDictionary() -> [String: Any]`
Returns a dictionary containing the latest computed statistics (`min`, `max`, `avg`, `p95`) for all three key metrics, formatted and ready for logging or serialization.

---
