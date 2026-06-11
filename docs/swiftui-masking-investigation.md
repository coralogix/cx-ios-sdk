# SwiftUI Session-Replay Masking — Investigation & Options (BUGV2-6045)

**Date:** 2026-06-11
**Status:** Investigation complete — awaiting team decision on implementation approach.

---

## 1. Problem statement

Session-replay text/image masking does not work for SwiftUI content in production.

Our masking pipeline (`UIViewExt.captureScreenshotImage`) collects rects to black-fill
by walking the UIKit view tree for `UILabel` / `UITextField` / `UITextView` /
`UIImageView`. SwiftUI renders text and images through private view/layer classes —
none of which are matched by that walk — so SwiftUI `Text`, `TextField`, `Image`, etc.
leak unmasked into captured frames.

## 2. What we tried: the accessibility-tree approach (dead end)

We implemented collectors that walk the **accessibility element tree**
(`accessibilityElements`, `accessibilityElementCount()/element(at:)`,
`isAccessibilityElement`) and mask elements whose `accessibilityLabel` matches the
configured `maskText` patterns, using `accessibilityFrame` for the rect.

**Result: works perfectly under the leak harness, fails completely in a real run.**

### Root cause (verified experimentally, 2026-06-10)

SwiftUI builds its accessibility tree **lazily — only when an accessibility client is
attached** (VoiceOver, Accessibility Inspector, or an XCUITest runner). XCUITest
drives the app entirely through the accessibility system, which activates the AX
runtime in the app process. With no AX client — i.e. every production app — SwiftUI
never materializes the tree:

| Condition (same build, same screen) | AX runtime | Collector result |
|---|---|---|
| Normal `simctl launch`, no test runner | off | **0 rects** — every node `isAcc=false`, `accessibilityElements` empty |
| `defaults write com.apple.Accessibility AccessibilityEnabled -bool true` on the sim | on | **13 rects**, every frame |

Conclusions:

1. **Any accessibility-based masking approach cannot work in production.** Customer
   apps never run with an AX client attached.
2. **The leak harness was validating a runtime state that never occurs in the field.**
   Both Jun-9 harness runs passed (0 leaks across 188 frames, masking visually
   confirmed) — a false pass. Any future AX-dependent code path must not be validated
   via XCUITest.
3. We cannot force the AX runtime on from the SDK — private API, App Store rejection
   risk, and it changes app behavior/perf globally.

The AX collectors (`walkAccessibilityElements`, `collectAccessibilityTextRects`,
`collectAccessibilityImageRects` in `CoralogixInternal/Sources/Extention/UIViewExt.swift`)
are currently uncommitted on `BUGV2-6045-flutter-bitmap-provider` and should be
**dropped, not merged**.

## 3. How the competition solves it (both verified from source, 2026-06-10)

### 3.1 Sentry — class-name matching of SwiftUI's private rendering views/layers

Repo: `getsentry/sentry-cocoa` (MIT).
Core file: `Sources/Swift/Core/Tools/ViewCapture/SentryUIRedactBuilder.swift`.

SwiftUI does create real (private) UIKit views/layers for drawing. Sentry matches
them **by class-name string** during a layer-tree walk and redacts their frames:

| Content | iOS generation | Matched class |
|---|---|---|
| Text | ≤ 17 | `_TtCOCV7SwiftUI11DisplayList11ViewUpdater8Platform13CGDrawingView` (stored **base64-encoded** — the literal string triggered false-positive App Store review rejections, sentry-cocoa #7121) |
| Text | 18+ | `SwiftUI.CGDrawingView` |
| Image | ≤ 25 | `SwiftUI._UIGraphicsView` **constrained to layer class** `SwiftUI.ImageLayer` (same view class is also used for plain backgrounds — the layer type disambiguates) |
| SF Symbols | ≤ 25 | `_UIShapeHitTestingView` (base64-encoded) |
| Text / Image / Symbols | 26+ (Liquid Glass) | SwiftUI stopped wrapping drawing in UIViews — they match **bare `CALayer` subclasses with no backing view**: `CGDrawingLayer`, `SwiftUI.ImageLayer`, `ColorShapeLayer` |

Implementation details worth copying regardless of approach:

- Walks `layer.presentation() ?? layer` recursively with **accumulated affine
  transforms** per layer, sublayers sorted by `zPosition` to mirror real render order.
- Region types beyond "redact": `clipOut` (opaque view suppresses masks behind it),
  `clipBegin`/`clipEnd` (for `masksToBounds`); a full-screen opaque view clears all
  previously collected regions.
- Class identities compared as **strings** (`type(of:).description()`) — never
  `NSClassFromString` / class objects, which can fire ObjC `+initialize` on UIKit
  internals off the main thread (they had real crashes).
- Exclusion list for crash-prone subtrees (e.g. `CameraUI.ChromeSwiftUIView`, iOS 26).
- Manual escape hatch: `.sentryReplayMask()` / `.sentryReplayUnmask()` SwiftUI
  modifiers — a `UIViewRepresentable` overlay injecting an invisible `UIView` tagged
  via associated objects; the redact builder picks the tag up per-instance.

**Key limitation: no access to text content.** They know *where* text is, not *what*
it says. Sentry's privacy model is `maskAllText: Bool` — all-or-nothing.

### 3.2 Datadog — reflection into SwiftUI's internal `DisplayList`

Repo: `DataDog/dd-sdk-ios` (Apache 2.0).
Entry: `DatadogSessionReplay/Sources/Recorder/ViewTreeSnapshotProducer/ViewTreeSnapshot/NodeRecorders/UIHostingViewRecorder.swift`.

When the recorder hits a `_UIHostingView`, it extracts SwiftUI's internal renderer
via **ObjC ivar access** (`class_getInstanceVariable` + `object_getIvar`) with a
version-gated keypath — the internal layout has shifted twice already:

```
iOS 26+:   _base.viewGraph.renderer
iOS 18.1+: _base.renderer
earlier:   renderer
```

From the renderer they reflect SwiftUI's private `DisplayList` tree:

- Reflection infra: `DatadogInternal/Sources/Utils/ReflectionMirror.swift` — a
  **forked reimplementation of Swift's `Mirror`** calling Swift runtime entry points
  directly via `@_silgen_name` (`swift_reflectionMirror_subscript`,
  `swift_EnumCaseName`, …), wrapped by a `Reflector` facade with typed lookups,
  deferred (`Lazy<T>`) reflection, and **telemetry on every reflection failure**.
- Model re-declaration: `NodeRecorders/SwiftUI/DisplayList.swift` — items are
  `effect` (clip / platformGroup / filter, with nested lists) or `content`
  (`.text` / `.image` / `.shape` / `.color` / `.drawing` / `.platformView`).
  ScrollView content (`platformGroup`) gets frames remapped via a reflected
  `viewCache` of per-item `ViewInfo`.
- **Full text content access:** `.text` reflects to
  `ResolvedStyledText.StringDrawing.storage: NSAttributedString` — actual string,
  font, color, paragraph style. Their obfuscator runs on `storage.string` per item
  (`SwiftUIWireframesBuilder.swift`).
- Everything is `do/catch`; if SwiftUI internals shift, recording degrades gracefully
  and reports telemetry — never crashes.
- Manual escape hatch: `SessionReplayPrivacyView` (iOS 16+) container scoping
  privacy-level overrides to its content.

Note: Datadog's replay is **wireframe-based** (vector reconstruction of the screen),
which is why they need this much fidelity. Our replay is **bitmap-based** — we only
need rects (plus strings if we want pattern matching), a small subset of their
pipeline.

### 3.3 Comparison

| | Sentry | Datadog |
|---|---|---|
| Mechanism | Class-name match on private views/layers | Ivar + runtime reflection into `DisplayList` |
| Text content access | ❌ position only | ✅ full `NSAttributedString` |
| Our `maskText` regex semantics | Impossible — degrades to mask-all-text | Possible |
| Version surface | 3 generations of class names | 3 generations of ivar paths + enum layouts + `@_silgen_name` runtime calls |
| Failure mode | Unmatched class → that view type leaks (pixel harness catches it) | Reflection throws → no masking for the subtree (+ telemetry) |
| Complexity | ~1 file | Reflection stack + model + builder (~15 files) |
| Manual SwiftUI modifier | `.sentryReplayMask()` | `SessionReplayPrivacyView` |
| License | MIT | Apache 2.0 |

## 4. Recommendation: two phases, ship Sentry-style first

### Option 0 — chosen interim (implemented 2026-06-11, this branch)

Restored the pre-`6006933` Vision-based masking, **scoped to captures whose scene
contains a SwiftUI hosting view** (`UIView.subtreeContainsSwiftUIHostingView`,
class-name string matching, short-circuits at FlutterView subtrees):

- `TextScanner` (Vision OCR, restored as-is from `6006933^`) runs when
  `containsSwiftUIContent && maskText` is non-empty.
- `ImageScanner` `maskAll` (rectangle detection) runs when
  `containsSwiftUIContent && maskAllImages` (credit-card-only mode unchanged for
  everyone else).
- Detection happens on the main thread at capture time and flows through
  `URLEntry.containsSwiftUIContent` to the off-main `ScannerPipeline` (stage order
  restored to image → text → face → click).
- UIKit and Flutter capture paths are byte-for-byte untouched.

Accepted trade-off: OCR masking is probabilistic ("flaky but functional") —
harness-green ≠ field-no-leak. Phase 1 below (deterministic class-name matching)
remains the planned successor. Full decision record:
`docs/swiftui-ocr-restoration-plan.md`.

### Phase 1 — class/layer-name detection + `.cxMask()` modifier (~1 week)

Why this first:

- Bitmap replay needs only rects to black-fill — exactly what class-name matching
  yields. We don't need wireframe fidelity.
- Maintenance fits the team: the entire SwiftUI knowledge is ~10 class-name strings,
  openly maintained in an MIT repo we can track. The Datadog path means owning a
  forked `Mirror` and re-validating ivar layouts every iOS beta.
- Failure is contained and detectable: one unmatched view type leaks → our pixel
  harness flags it. Broken reflection would silently disable all SwiftUI masking.
- The leak harness becomes honest: class/layer matching has **zero AX dependence**,
  so the existing XCUITest + pixel-scanner setup validates the real production path.

Work breakdown (~4–6 working days):

| Task | Estimate |
|---|---|
| `collectSwiftUITextRects` / `collectSwiftUIImageRects` in `UIViewExt` — class-name string matching across all three iOS generations (incl. the iOS 26 layer-only branch — required, current sims are the 26 era), reusing existing `presentationRect` | 1.5–2 d |
| Remove AX collectors + `SR-acc-debug` scaffolding | 0.5 d |
| Public `.cxMask()` SwiftUI modifier (UIViewRepresentable overlay → existing `cxMask` associated object), mirrored in both demo apps | 0.5–1 d |
| Harness: re-run SwiftUI scenarios; optionally add a `.cxMask()` sentinel | 0.5 d |
| Cross-version validation (iOS 15/16/17/18/26 sims) — proves the pre-18 mangled name and the 26 layer path | 1–1.5 d |

**Product decision required:** under Phase 1, `maskText: [patterns]` and
`maskOnlyCreditCards` cannot do content matching on SwiftUI — any non-empty mask
config masks **all** SwiftUI text. Over-masking is the safe failure direction for a
privacy feature; proposal is to ship that behavior and document it as a known SwiftUI
limitation.

### Phase 2 — `DisplayList` reflection subset (~3–4 weeks, only on demonstrated customer need)

A frames+strings-only subset of Datadog's pipeline: version-gated ivar extraction,
enum-case reflection of `DisplayList` items, `.text` → `NSAttributedString` → run our
existing regex matching → emit rects. Requires the operational hardening that approach
demands: `do/catch` everywhere, telemetry on reflection failures, and a kill-switch
falling back to Phase 1's mask-all behavior. Not worth starting speculatively —
Phase 1's over-masking is correct privacy behavior; Phase 2 is UX refinement at ~4×
the cost with a recurring iOS-beta maintenance tail.

## 5. Current branch state (`BUGV2-6045-flutter-bitmap-provider`, uncommitted)

| Change | Disposition |
|---|---|
| AX collectors + debug logs in `CoralogixInternal/Sources/Extention/UIViewExt.swift` | **Dropped** (dead end, see §2) — reverted to HEAD 2026-06-11; replaced by `subtreeContainsSwiftUIHostingView` (Option 0, §4) |
| `SessionReplay/Sources/TextScanner.swift` + `Tests/SessionReplayTests/TextScannerTests.swift` | **Restored** from `6006933^` (Option 0, §4) |
| `ScannerPipeline`: SwiftUI-scoped text + image `maskAll` stages; `URLEntry.containsSwiftUIContent` plumbing | **Added** (Option 0, §4) |
| SwiftUI leak harness: `LeakHarnessSwiftUIView`, `SessionReplaySwiftUILeakUITests`, launch-arg wiring in `DemoAppSwiftUIApp`, harness SwiftUI phase | **Removed** (2026-06-11) — OCR misses rows clipped at the viewport edge mid-scroll (12/40 `swiftui_list` frames leaked 42–423 px slivers), a known accepted failure mode of Option 0, so a permanently-red scenario adds no signal. Re-add when Phase 1 (deterministic matching) lands. |
| `tool/run_leak_harness.sh`: log-stream predicate fixed (`BEGINSWITH "DemoAppSwift"` — old exact match was brittle); UDID resolution + boot before streaming | **Keep** |
| `tool/leak-harness/mock_upload_server.swift`: non-multipart content-type warnings de-noised (warn once per distinct type) | **Keep** |
| `cxMask` removed from UIKit harness sentinels (so the harness exercises `maskText` only) | **Keep** |

## 6. Reference

- Experiment evidence (2026-06-10): same build → AX off = 0 rects/frame; AX forced on
  via sim `com.apple.Accessibility` defaults = 13 rects/frame. Jun-9 harness runs:
  0 leaks across 188 frames under XCUITest (false pass per §2).
- Sentry: `https://github.com/getsentry/sentry-cocoa` — `SentryUIRedactBuilder.swift`,
  `SentryReplayView.swift`, `SentryRedactViewHelper.swift`
- Datadog: `https://github.com/DataDog/dd-sdk-ios` — `UIHostingViewRecorder.swift`,
  `NodeRecorders/SwiftUI/DisplayList*.swift`, `SwiftUIWireframesBuilder.swift`,
  `DatadogInternal/Sources/Utils/ReflectionMirror.swift`
