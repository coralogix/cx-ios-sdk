# ColdDetector

The `ColdDetector` measures the **cold start time** of an iOS application — the time elapsed from
the moment the OS spawned the process until the app became interactive for the first time.

---

## What Is Measured

| Point | Moment | How |
|-------|--------|-----|
| **Start** | Kernel process birth | `sysctl(KERN_PROC_PID)` reads the exact time the OS created the process, before `main()` runs |
| **End** | App becomes interactive | `UIApplication.didBecomeActiveNotification` — the standard iOS signal that the app is ready for user input |

**Result:** duration in milliseconds, reported once per process lifetime.

---

## How It Works

1. **`startMonitoring()`** is called during SDK initialisation (inside `application(_:didFinishLaunchingWithOptions:)`).
   - Calls `ColdDetector.processStartTime()` which reads the kernel process birth time via `sysctl`.
   - Falls back to `CFAbsoluteTimeGetCurrent()` (SDK init time) if the syscall fails.
   - Registers an observer for `UIApplication.didBecomeActiveNotification`.

2. **`UIApplication.didBecomeActiveNotification`** fires when the app first becomes interactive.
   - Captures the current time as `launchEndTime`.
   - Removes the observer immediately — cold start is a one-shot measurement.
   - Calculates duration, packages it into a dictionary, and calls `handleColdClosure`.

3. **`deinit`** removes all remaining observers to prevent memory leaks.

---

## Why `sysctl` for the Start Point

The previous implementation recorded `CFAbsoluteTimeGetCurrent()` during SDK init inside
`didFinishLaunchingWithOptions`. This missed all pre-main work:

```
Process birth
    │
    ├─ dyld loads frameworks           ← not captured before
    ├─ ObjC +load / Swift initializers ← not captured before
    ├─ main() starts
    ├─ AppDelegate init
    ├─ didFinishLaunchingWithOptions    ← old start point
    │       SDK init / startMonitoring()
    │
    └─ didBecomeActive                  ← end point (both old and new)
```

With `sysctl`, we capture from **process birth** — the same reference point used by
Apple's MetricKit and Instruments.app. This typically recovers 200–500 ms of pre-main
work that was previously missing from the measurement.

---

## Why `didBecomeActive` for the End Point

`UIApplication.didBecomeActiveNotification` is the standard iOS end point for cold start.
It is consistent with Apple's own MetricKit `applicationLaunchMetrics` and fires exactly
once on cold launch, before any background/foreground cycle begins.

This replaces the previous approach of observing a custom `.cxViewDidAppear` notification
posted from a swizzled `UIViewController.viewDidAppear`. The new approach has no swizzling
dependency for cold start measurement.

---

## Properties

| Property | Type | Purpose |
|----------|------|---------|
| `launchStartTime` | `CFAbsoluteTime?` | Process birth time from kernel (or SDK init fallback) |
| `launchEndTime` | `CFAbsoluteTime?` | Time when `didBecomeActive` fired; also guards against duplicate reports |
| `handleColdClosure` | `(([String: Any]) -> Void)?` | Called once with the cold start metric dictionary |

---

## Output Format

```swift
[
    "cold": [
        "units": "ms",
        "value": 412.0   // milliseconds from process birth to didBecomeActive
    ]
]
```

---

## Methods

### `startMonitoring()`

Begins cold start measurement. Reads the kernel process start time and registers for
`didBecomeActiveNotification`. Safe to call once per process lifetime.

### `processStartTime() -> CFAbsoluteTime?` *(static)*

Queries `sysctl(KERN_PROC_PID)` for the kernel process birth timestamp and converts it
to `CFAbsoluteTime`. Returns `nil` if the syscall fails (e.g. in a restricted sandbox).

### `calculateTime(start:stop:) -> Double`

Returns `max(0, stop - start)` in milliseconds. Clamps to zero to prevent negative values
from clock skew or fallback timing.

---

## Known Limitations

- **No "fully displayed" API**: Cold start ends at `didBecomeActive`, not when the first
  meaningful screen finishes rendering. A future `reportFullyDisplayed()` API could provide
  a more precise "time to full display" metric for apps that load data before showing content.

- **Pre-warm processes**: iOS may pre-warm apps in the background. In pre-warmed launches,
  `didBecomeActive` fires much later than the process birth time, producing an artificially
  large cold start value. Pre-warm detection (via `ActivePrewarm` environment variable) is
  not currently implemented.
