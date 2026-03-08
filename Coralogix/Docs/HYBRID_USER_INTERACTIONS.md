# Hybrid User Interactions (Flutter / React Native)

This document explains how user interaction events are handled when using hybrid frameworks (Flutter, React Native) with the Coralogix iOS SDK.

## Overview

When integrating Coralogix with a hybrid framework, user interaction events can originate from two sources:

1. **Native iOS SDK** — Detects taps, gestures, scrolls via UIKit swizzling
2. **Hybrid bridge** — Events sent from Flutter/React Native via `setUserInteraction(_:)`

If both sources are active, **duplicate events** will be emitted for the same user action.

## Recommended Configuration

For hybrid apps, **disable native user interaction tracking** so events flow exclusively through the bridge API. This ensures:
- No duplicate events
- Consistent event payloads with framework-specific context
- Full control over which interactions are tracked

### Swift Configuration

```swift
let options = CoralogixExporterOptions(
    coralogixDomain: .US2,
    environment: "production",
    application: "my-flutter-app",
    version: "1.0.0",
    publicKey: "YOUR_API_KEY",
    instrumentations: [
        .userActions: false   // ← Disable native user interaction spans
    ]
)
let coralogixRum = CoralogixRum(options: options)
```

### What Happens Internally

| Configuration | Native spans | Bridge spans | Swizzling active |
|---------------|--------------|--------------|------------------|
| `.userActions: true` (default) | ✅ Emitted | ✅ Emitted | ✅ Yes |
| `.userActions: false` | ❌ Suppressed | ✅ Emitted | ✅ Yes (for Session Replay) |

> **Note:** Even with `.userActions: false`, UIKit swizzling remains active so Session Replay can capture click coordinates. The only change is that native RUM spans are **not** emitted.

## Bridge API: `setUserInteraction`

The hybrid layer sends interaction events via:

```swift
coralogixRum.setUserInteraction([
    "event_name": "click",                    // Required: click | scroll | swipe | double_click | long_press
    "target_element": "CheckoutButton",       // Required: element identifier
    "element_classes": "UIButton",            // Optional: UI class name
    "element_id": "btn_checkout",             // Optional: accessibility identifier
    "target_element_inner_text": "Checkout",  // Optional: visible text
    "scroll_direction": "up",                 // Optional: up | down | left | right (for scroll/swipe)
    "attributes": [                           // Optional: custom key-value pairs
        "x": 321.33,
        "y": 640.67
    ]
])
```

### Key Naming

The SDK accepts **both snake_case and camelCase** for all keys:

| snake_case | camelCase |
|------------|-----------|
| `event_name` | `eventName` |
| `target_element` | `targetElement` |
| `element_classes` | `elementClasses` |
| `element_id` | `elementId` |
| `target_element_inner_text` | `targetElementInnerText` |
| `scroll_direction` | `scrollDirection` |

This ensures compatibility with both Dart (snake_case) and JavaScript (camelCase) conventions.

## Resulting RUM Payload

The `interaction_context` in the exported RUM payload always includes all keys:

```json
{
  "interaction_context": {
    "event_name": "click",
    "target_element": "CheckoutButton",
    "element_classes": "UIButton",
    "element_id": null,
    "target_element_inner_text": null,
    "scroll_direction": null,
    "attributes": {
      "x": 321.33,
      "y": 640.67
    }
  }
}
```

Optional fields are serialised as `null` when not provided, ensuring a stable JSON shape for downstream consumers.

## Summary

| Scenario | Configuration |
|----------|---------------|
| Native iOS app | Default (no change needed) |
| Flutter app | `instrumentations: [.userActions: false]` |
| React Native app | `instrumentations: [.userActions: false]` |

Disabling `.userActions` for hybrid apps is the recommended pattern to avoid duplicate events while retaining Session Replay click capture.
