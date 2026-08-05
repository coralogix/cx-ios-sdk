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
- `maskText`: List of strings to mask by case-insensitive substring match (UILabel, UITextField, UITextView).
- `maskAllImages`: Whether all images should be masked.
- `maskFaces`: Whether faces should be masked (default: `false`).
- `creditCardPredicate`: Custom text patterns to identify images that may contain credit card content.

See [Masking a specific view (`cxMask`)](#masking-a-specific-view-cxmask) for opting an individual view in, regardless of these global options.

#### Initializer
```swift
public init(
    recordingType: RecordingType = .image,
    captureTimeInterval: TimeInterval = 10,
    captureScale: CGFloat = 2.0,
    captureCompressionQuality: CGFloat = 1.0,
    sessionRecordingSampleRate: Int = 100,
    maskText: [String]? = nil,
    maskAllImages: Bool = true,
    maskFaces: Bool = false,
    creditCardPredicate: [String]? = nil,
    autoStartSessionRecording: Bool = false
)
```

#### Example Usage
```swift
// Mask specific strings
let options = SessionReplayOptions(
    recordingType: .image,
    captureTimeInterval: 5.0,
    maskText: ["Confidential", "Account Number"],
    maskAllImages: true,
    maskFaces: true,
    autoStartSessionRecording: true
)

SessionReplay.initializeWithOptions(sessionReplayOptions: options)
```

---

## Masking a specific view (`cxMask`)

Opts a single view into Coralogix masking, regardless of the global masking policy.

```swift
accountNumberLabel.cxMask = true
```

Masking applies to the **whole subtree**: every subview is masked too, and a subview cannot be opted back out. Applying it to a container is therefore enough to cover its contents, which is the recommended way to protect a composite element such as a PIN keypad whose keys are individually tappable.

A masked view, and anything inside it:

- is covered by a black rectangle in session replays;
- absorbs tap markers — a tap landing anywhere inside it draws no marker in the recording, so the replay does not reveal which part of the masked area was touched;
- reports its text as `***` in user interaction events.

Masking does not suppress the interaction event itself, and the event still carries the touch coordinates. Masking hides *what* an element is and *what it says*, not *that it was used*.

### Which masking sources suppress a tap marker

Only masking that reports geometry to the capture pass can suppress a marker, because the marker is tested against the exact rectangles the frame blacked out — the pixels and the marker can never disagree.

| Masking source | Pixels masked | Tap marker suppressed | Interaction text `***` |
|---|---|---|---|
| `cxMask` on a `UIView` (and its subviews) | ✅ | ✅ | ✅ |
| `.cxMask()` on a SwiftUI view | ✅ | ✅ | ❌ — see below |
| `maskText`, `maskAllImages`, `maskFaces`, `creditCardPredicate` | ✅ | ❌ | ❌ |
| Flutter (Dart-supplied pre-masked bitmap) | ✅ | ❌ | ❌ |

The global policy options and the Flutter path deliberately do not affect interaction text: they answer "should these pixels be hidden in this frame", which is not the same question as "may this text leave the device". Password fields and fields with a sensitive `textContentType` are redacted to `***` independently of any of this.

> **Limitation — SwiftUI:** `.cxMask()` works by overlaying a masked `UIView` on top of the composable content. That overlay masks the pixels and suppresses tap markers over the area, but it is a sibling of the content rather than an ancestor of it, so the views underneath do not inherit masking and their interaction events still report their real text. If a SwiftUI control's text is sensitive, use the `shouldSendText` option to redact it.

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
    maskText: ["password", "card"],
    maskAllImages: true,
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

