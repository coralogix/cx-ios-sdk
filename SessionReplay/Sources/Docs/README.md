# SessionReplay Documentation

## Overview

The `SessionReplay` module provides functionality for recording user sessions, including capturing images or videos at specified intervals. It also supports masking sensitive data like text, images, and faces during the recording process.

---

## Classes

### 1. `SessionReplayOptions`

#### Description
Represents the configuration options for session replay functionality.

#### Properties
- `autoStartSessionRecording`: Automatically starts session recording if enabled in the options.
- `recordingType`: The type of recording (`image` or `video`).
- `captureTimeInterval`: Time interval between each capture in seconds.
- `captureScale`: Scale factor for captured images.
- `captureCompressionQuality`: Compression quality for captured images (range: 0.0 to 1.0).
- `sessionRecordingSampleRate`: The sampling rate for session recording events.
- `maskText`: Array of text patterns to mask (supports strings and regex).
- `maskImages`: Whether specific images should be masked (default: `false`).
- `maskAllImages`: Whether all images should be masked. If `false`, only credit card images will be masked (default: `true`).
- `maskFaces`: Whether faces should be masked (default: `false`).
- `creditCardPredicate`: Optional array of text patterns to identify potential credit card content.

#### Initializer
```swift
public init(
    recordingType: RecordingType = .image,
    captureTimeInterval: TimeInterval = 10,
    captureScale: CGFloat = 2.0,
    captureCompressionQuality: CGFloat = 1.0,
    maskText: [String]? = nil,
    maskImages: Bool = false,
    maskAllImages: Bool = true,
    maskFaces: Bool = false,
    creditCardPredicate: [String]? = nil
)
```

#### Example Usage
```swift
let options = SessionReplayOptions(
    recordingType: .image,
    captureTimeInterval: 5.0,
    maskText: ["Confidential", "\d{16}"], // Regex for credit card numbers
    maskImages: true,
    maskFaces: true
)
```

---

### 2. `SessionReplay`

#### Description
Manages session replay functionality, including recording, event capture, and masking sensitive content.

#### Properties
- `sessionReplayModel`: Internal model managing session replay data and operations.

#### Initializer
```swift
public init(sessionId: String, sessionReplayOptions: SessionReplayOptions)
```

#### Methods

##### `startSessionRecording`
Starts recording the session and captures data at the configured interval.

```swift
public func startSessionRecording()
```

##### `stopSessionRecording`
Stops the session recording and releases resources.

```swift
public func stopSessionRecording()
```

##### `captureEvent`
Captures a specific event during the session.

```swift
public func captureEvent()
```

#### Example Usage
```swift
let sessionReplay = SessionReplay(sessionId: "12345", sessionReplayOptions: options)
sessionReplay.startSessionRecording()

// After some events
sessionReplay.captureEvent()

// Stop recording
sessionReplay.stopSessionRecording()
```

---

## Additional Notes

### Credit Card Detection
The `creditCardPredicate` property contains text patterns used to identify credit card content in images. Examples include:
- `"Visa"`
- `"MasterCard"`
- `"American Express"`
- `"4"` (Visa prefix)

By default, this property is optional, and custom patterns can be supplied during initialization.

---

## Enums

### `RecordingType`
Defines the type of recording:
- `.image`
- `.video` - Not supported at the moment

---
