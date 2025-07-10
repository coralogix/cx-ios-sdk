# SessionReplay Documentation

## Overview

The `SessionReplay` module provides functionality for recording user sessions, including capturing images or videos at specified intervals. It also supports masking sensitive data like text, images, and faces during the recording process.

---

## Classes

### 1. `SessionReplayOptions`

#### Description
Holds the configuration used to initialize SessionReplay. This includes capture mode, timing, scale, compression, sampling, and masking rules.
#### Properties
- `autoStartSessionRecording`: If true, recording begins automatically upon initialization.
- `recordingType`: The recording mode – .image (available) or .video (TBD).
- `captureTimeInterval`: Time interval between each capture in seconds.
- `captureScale`: Scale factor for image resolution.
- `captureCompressionQuality`: Compression level for image quality (0.0–1.0).
- `sessionRecordingSampleRate`: Sampling percentage (0–100) to determine whether the session is recorded.
- `maskText`: Text patterns (strings or regex) to redact from captured content.
- `maskImages`: Whether specific images should be masked (default: `false`).
- `maskAllImages`: Whether all images should be masked. If `false`, only credit card images will be masked (default: `true`).
- `maskFaces`: Whether faces should be masked (default: `false`).
- `creditCardPredicate`: Custom text patterns to identify images that may contain credit card content.

#### Initializer
```swift
public init(
    recordingType: RecordingType = .image,
    captureTimeInterval: TimeInterval = 10,
    captureScale: CGFloat = 2.0,
    captureCompressionQuality: CGFloat = 1.0,
    sessionRecordingSampleRate: Int = 100,
    maskText: [String]? = nil,
    maskImages: Bool = false,
    maskAllImages: Bool = true,
    maskFaces: Bool = false,
    creditCardPredicate: [String]? = nil,
    autoStartSessionRecording: Bool = false
)
```

#### Example Usage
```swift
let options = SessionReplayOptions(
    recordingType: .image,
    captureTimeInterval: 5.0,
    maskText: ["Confidential", ".*"], // ".*" mask all text
    maskImages: true,
    maskFaces: true,
    autoStartSessionRecording: true
)

SessionReplay.initializeWithOptions(sessionReplayOptions: options)
```

---

### 2. `SessionReplay`

#### Description
Singleton class responsible for session capture, and masking sensitive content.

#### Access
- `SessionReplay.shared` // must be initialized first using initializeWithOptions

#### Initializer
```swift
SessionReplay.initializeWithOptions(sessionReplayOptions: options)
```

#### Methods

##### `startSessionRecording`
Starts recording the session and captures data at the configured interval.

```swift
SessionReplay.shared.startRecording()
```

##### `stopSessionRecording`
Stops the session recording and releases resources.

```swift
SessionReplay.shared.stopRecording()
```

##### `captureEvent`
Captures a specific event during the session.

```swift
let result = SessionReplay.shared.captureEvent()
```

#### Example Usage
```swift
let options = SessionReplayOptions(
    recordingType: .image,
    captureTimeInterval: 5.0,
    maskText: [".*"], // ".*" mask all text
    maskImages: true,
    maskFaces: true,
    autoStartSessionRecording: false
)

SessionReplay.initializeWithOptions(sessionReplayOptions: options)
SessionReplay.shared.startRecording()
_ = SessionReplay.shared.captureEvent(properties: nil)
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
- `.video`

---

