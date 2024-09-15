
# FPSMonitor

`FPSMonitor` is a class used to track the frames per second (FPS) in an application. It monitors the rendering performance by measuring how many frames are rendered within a given time frame.

## Properties

- `private var displayLink: CADisplayLink?`  
  Used to synchronize the app’s rendering cycle with the screen refresh rate.

- `private var frameCount: Int = 0`  
  Tracks the number of frames rendered.

- `var startTime: CFTimeInterval = 0`  
  Stores the time when the monitoring starts.

## Methods

### `startMonitoring()`

Starts monitoring the FPS by initializing a `CADisplayLink` instance, which triggers the `trackFrame` method whenever the screen refreshes. The `frameCount` is reset to zero, and the `startTime` is set to the current time using `CACurrentMediaTime()`.

### `stopMonitoring() -> Double`

Stops monitoring the FPS by invalidating the `CADisplayLink`. It calculates the average FPS over the time period between when `startMonitoring` was called and when `stopMonitoring` is called. This is calculated as:


{Average FPS} = {frameCount} / {elapsedTime}


### `@objc internal func trackFrame()`

Increases the frame count every time the screen refreshes, allowing the FPS to be tracked.

## Usage Example

```swift
let fpsMonitor = FPSMonitor()
fpsMonitor.startMonitoring()

// Call this after some time to stop monitoring and retrieve the average FPS.
let averageFPS = fpsMonitor.stopMonitoring()
print("Average FPS: \(averageFPS)")
