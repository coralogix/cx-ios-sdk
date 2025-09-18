
# MemoryDetector

The `MemoryDetector` is a powerful class for monitoring an application's memory consumption. It periodically samples memory usage using low-level system APIs and provides a detailed statistical analysis, helping developers identify memory leaks, excessive usage, and overall performance characteristics. 🧠

---

## How It Works

The detector operates by sampling memory usage at regular intervals and aggregating the results.

1.  **Periodic Sampling**: A `Timer` fires at a regular interval, triggering a memory reading via the `sampleOnce()` method.
2.  **Low-Level Data Fetching**: Each sample uses the **Mach kernel API** (`task_info` with `TASK_VM_INFO`) to get precise, low-level memory data directly from the operating system.
3.  **Metric Calculation**: The raw data from the kernel is processed into three distinct, high-level metrics (Footprint, Resident Size, and Utilization).
4.  **Data Aggregation**: These metrics are stored in sample arrays to build a history of memory usage over time.
5.  **Lifecycle Awareness**: The detector intelligently pauses monitoring when the app is in the background (`willResignActive`) and resumes when it returns to the foreground (`didBecomeActive`), ensuring efficiency and data relevance.

---

## Key Metrics Collected

The detector captures and analyzes three different aspects of memory usage:

* **Memory Footprint (MB)**: This is the most accurate and recommended metric for measuring memory usage on modern iOS. It represents the physical memory (RAM) being used by the app that is not shared with other processes. This is the primary value to watch for memory pressure and potential leaks.
* **Resident Size (MB)**: This is the traditional Resident Set Size (RSS), which includes memory from shared libraries. It's provided for reference and comparison but is generally less precise for diagnostics than the footprint.
* **Memory Utilization (%)**: This metric calculates the app's memory footprint as a percentage of the total physical RAM available on the device, providing context for how much of the system's resources the app is consuming.

---

## Computed Statistics

The `MemoryDetector` provides more than just raw data. It automatically calculates and exposes a rich set of statistical summaries for all collected samples over a monitoring period:

* **Minimum** (`min`)
* **Maximum** (`max`)
* **Average** (`avg`)
* **95th Percentile** (`p95`)

These statistics are available for all three of the key metrics listed above.

---

## Methods

### `startMonitoring()`
Starts the periodic memory sampling process and registers for app lifecycle notifications.

### `stopMonitoring()`
Stops the sampling timer, removes notification observers, and clears all collected data.

### `reset()`
Clears all stored sample arrays without stopping the timer. This is useful for starting a new measurement window (e.g., after a user completes a specific task).

### `statsDictionary() -> [String: Any]`
Returns a dictionary containing the latest computed statistics (`min`, `max`, `avg`, `p95`) for all three key metrics, formatted and ready for logging or serialization.

---
