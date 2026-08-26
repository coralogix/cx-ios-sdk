# SessionReplay Documentation

## Overview

The `SessionReplay` module provides functionality for recording user sessions, including capturing images or videos at specified intervals. It also supports masking sensitive data like text, images, and faces during the recording process.

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

### Which masking sources suppress a tap marker and set `is_masked_element`

Only masking that reports geometry to the capture pass can suppress a marker, because the marker is tested against the exact rectangles the frame blacked out — the pixels and the marker can never disagree. The synchronous `UIView` walk reports geometry, and the Flutter plugin reports the rects it masked alongside each bitmap. The Vision-based scanners modify pixels in place and report none, so masking that relies on them cannot suppress a marker.

Interaction events ask a **different question** and so use different geometry. The marker asks *should these pixels be hidden in this frame*; `is_masked_element` asks *may this text leave the device*. Only deliberate masking answers the second: the tap point is tested against `cxMask` rects alone — set directly, inherited from an ancestor, or applied to SwiftUI content via the `.cxMask()` overlay — with the replay's pixel policy (`maskText`, `maskAllImages`) excluded. A tap inside one redacts `target_element_inner_text` to `***` and reports `interaction_context.is_masked_element: true`. The view-tree walk (`cxMask` inheritance) and the sensitive-field traits answer alongside it, and still answer when no geometry is available.

**Flag and marker can therefore legitimately disagree for policy-masked content:** a tap on a `maskText`-matched label draws no marker (its pixels are hidden) but reports `is_masked_element: false` with its real text. This is deliberate, and matches Android and Flutter, which both resolve the verdict from deliberate masking alone. Letting the pixel policy decide the verdict over-masks severely on defaults — a wrapper shipping `maskAllTexts: true` would mark every text tap as masked and ship `***` for all of it. Customers who want the pixel policy to withhold interaction text too use `shouldSendText`, which covers native interactions — clicks, scrolls and swipes alike. Hybrid text arrives pre-resolved in the bridge payload and never reaches it, so redact those in `beforeSend` or have the wrapper send `is_masked`.

> [!NOTE]
> This applies from version 2.17.0, and to **UIKit** views — the ones the pixel policy reports geometry for. On earlier versions it did set `is_masked_element` and redact the interaction text for those. The SwiftUI row below never did, on any version.

| Masking source | Pixels masked | Tap marker suppressed | Interaction text `***` | `is_masked_element` |
|---|---|---|---|---|
| `cxMask` on a `UIView` (and its subviews) | ✅ | ✅ | ✅ | ✅ |
| `.cxMask()` on a SwiftUI view | ✅ | ✅ | ✅ — via overlay mask rect | ✅ |
| `maskText` / `maskAllImages` on **UIKit** views (`UILabel`, `UITextField`, `UITextView`, `UINavigationBar` titles, `UIImageView`) | ✅ | ✅ | ❌ — pixel policy, not deliberate masking | ❌ |
| `maskText` / `maskAllImages` on **SwiftUI** content (OCR / rectangle detection) | ✅ | ❌ | ❌ | ❌ |
| `maskFaces`, `creditCardPredicate` (Vision) | ✅ | ❌ | ❌ | ❌ |
| Flutter (Dart-supplied pre-masked bitmap) | ✅ | ✅ — with plugin-reported rects (`FlutterViewBitmap.maskRects`) | ✅ — via `is_masked` on `setUserInteraction` | ✅ — same |
| Secure text entry / sensitive `textContentType` | n/a (system-drawn dots) | ❌ — paints no rect | ✅ | ✅ |

Interaction reporting does not depend on session replay being initialized: `cxMask` geometry needs none of the replay's options to collect, so the verdict resolves whether or not a replay is running. Password fields and fields with a sensitive `textContentType` are redacted to `***` independently of any of this. Any **new masking source must state which of the two channels it feeds**: geometry to the capture pass (suppresses markers; sets the flag only when it is deliberate masking rather than pixel policy) or pixels only (neither).

`is_masked_element` is always present and defaults to `false` whenever masking cannot be resolved — the flag under-reports rather than over-reports when the SDK has no answer. The known unresolvable cases on iOS: a hybrid `setUserInteraction` payload with no coordinates (React Native scroll and swipe carry none), and no view hierarchy to walk (off the main thread, or no active foreground scene).

> **`element_id` is never redacted.** It carries the view's `accessibilityIdentifier`, which is developer-authored rather than user data, so the SDK reports it as-is even for a view inside a masked subtree. Avoid encoding sensitive values in identifiers: on a masked keypad, per-digit identifiers such as `keypad_key_7` would reconstruct the entered sequence from the tap spans even though the text is `***`. Both demo apps give the masked keypad's keys a single shared identifier for this reason. This matches the Android SDK, which does not redact `resourceId` either. Customers who need identity fields or coordinates withheld implement it in `beforeSend`, keyed on `is_masked_element` — see the root README.

> **SwiftUI:** `.cxMask()` works by overlaying a masked `UIView` on top of the composable content — a sibling, not an ancestor — so the views underneath do not inherit masking through the view tree. Their interaction events are still redacted, because the tap point is tested against the overlay's mask rect. This is why the interaction path tests geometry at all rather than relying on the view-tree walk alone. Text masked only by the pixel policy (`maskText`/`maskAllImages`, whether over UIKit or SwiftUI content) is by design not redacted in interaction events; use `shouldSendText` for those.

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

## Additional Notes

### Credit Card Detection
The `creditCardPredicate` property contains text patterns used to identify credit card content in images. Examples include:
- `"Visa"`
- `"MasterCard"`
- `"American Express"`
- `"4"` (Visa prefix)

By default, this property is optional, and custom patterns can be supplied during initialization.

## Enums

### `RecordingType`
Defines the type of recording:
- `.image`
- `.video`

