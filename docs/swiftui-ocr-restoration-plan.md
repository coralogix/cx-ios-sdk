# SwiftUI Masking — OCR Restoration Plan (BUGV2-6045 interim fix)

**Status:** APPROVED by Dan, ready to implement. Written 2026-06-11 as a fresh-context
handoff — everything needed to execute is in this doc.

---

## 0. TL;DR for fresh context

Restore the old Vision/OCR-based text masking (`TextScanner`) and the old
rectangle-detection image masking (`ImageScanner maskAll` mode), **scoped to captures
whose scene contains SwiftUI content**. UIKit and Flutter capture paths must remain
byte-for-byte untouched (customers are waiting on the Flutter fix; that's the
priority). Drop the uncommitted accessibility-based collectors — they are a verified
dead end. Accepted trade-off: OCR masking is probabilistic ("flaky but functional");
a deterministic approach (Sentry-style class-name matching) is deliberately deferred —
see `docs/swiftui-masking-investigation.md` for the full analysis.

## 1. Decisions already made (do not re-litigate)

1. Restore `TextScanner` (Vision OCR) for SwiftUI text masking — leaks possible, accepted.
2. Restore `ImageScanner` `maskAll` (rectangle detection) for SwiftUI image masking —
   "flaky but works most of the time" explicitly preferred for now.
3. Both restored stages run **only when the captured scene contains a SwiftUI hosting
   view**; non-SwiftUI apps keep current behavior exactly.
4. AX collectors in `UIViewExt.swift` (uncommitted): **delete**, including all
   `[SR-acc-debug]` logs. Verified unusable in production: SwiftUI only materializes
   its accessibility tree when an AX client (VoiceOver/XCUITest) is attached — never
   true in the field. Evidence: same build, 0 rects/frame normally, 13 rects/frame
   with sim AX defaults forced on. Details: `docs/swiftui-masking-investigation.md` §2.
5. No Hebrew / adversarial OCR sentinels in the harness — explicitly declined.
6. Sentry/Datadog approaches are future work, documented in the investigation doc.

## 2. Current branch state (`BUGV2-6045-flutter-bitmap-provider`)

Uncommitted working-tree changes and their disposition:

| File | Contents | Action |
|---|---|---|
| `CoralogixInternal/Sources/Extention/UIViewExt.swift` | AX collectors (`walkAccessibilityElements`, `collectAccessibilityTextRects`, `collectAccessibilityImageRects`, `accessibilityInteractiveInsetFraction`) + 2 call sites inside `captureScreenshotImage` + SR-acc-debug logs | **Revert all of it** (`git checkout -- <file>` is fine — the committed version has none of it and is correct) |
| `Example/DemoAppSwiftUI/DemoAppSwiftUIApp.swift` | `--leak-harness-swiftui[-navigate]` launch-arg wiring, harness SR options (`maskText: [".*"]`, scale 1.0) | Keep |
| `Example/DemoAppSwiftUI/LeakHarnessSwiftUIView.swift` (untracked) | SwiftUI sentinel harness views (list + nav scenarios) | Keep |
| `Example/DemoAppSwiftUIUITests/SessionReplaySwiftUILeakUITests.swift` (untracked) | XCUITest driver for both SwiftUI scenarios | Keep |
| `Example/DemoApp.xcodeproj/project.pbxproj` | New files registered | Keep |
| `Example/DemoAppSwift/LeakHarnessViewController.swift` | `cxMask` removed from sentinels (harness exercises `maskText` only) | Keep |
| `tool/run_leak_harness.sh` | SwiftUI test phase (2b); log predicate fixed to `BEGINSWITH "DemoAppSwift"` (old `==` missed the DemoAppSwiftUI process); UDID resolved from `$IOS_DESTINATION` + `bootstatus -b` before streaming | Keep |
| `tool/leak-harness/mock_upload_server.swift` | Non-multipart content-type warnings de-noised (warn once per type, `warnedContentTypes` set guarded by `stateQueue`) | Keep |

## 3. What to restore, from where

The deletion commit is `6006933` ("BUGV2-6045: iOS session-replay mask-skew fix…").
Restore from its parent:

```bash
git show 6006933^:SessionReplay/Sources/TextScanner.swift            > SessionReplay/Sources/TextScanner.swift
git show 6006933^:Tests/SessionReplayTests/TextScannerTests.swift    > Tests/SessionReplayTests/TextScannerTests.swift
```

`TextScanner` is restored as-is — it already contains hard-won config (do not
simplify): `.accurate` recognition, `usesLanguageCorrection = false`, explicit
per-iOS-version multi-script language list intersected with runtime support,
`automaticallyDetectsLanguage` on iOS 16+, and for match-all patterns a second
geometric `VNDetectTextRectanglesRequest` pass that catches lines the recognizer
can't transcribe.

`ImageScanner` was **not** deleted — it still exists with full `maskAll` support
(`SessionReplay/Sources/ImageScanner.swift`). Only its pipeline invocation was
narrowed to credit-card-only. No restoration needed, just re-wiring.

### Old pipeline semantics to restore (from `git show 6006933^:SessionReplay/Sources/ScannerPipeline.swift`)

- Gates: `isTextScannerEnabled = !(options.maskText?.isEmpty ?? true)`;
  `isImageScannerEnabled = options.maskAllImages`;
  ImageScanner call used `maskAll: !options.maskOnlyCreditCards`.
- Stage order: **image → text → face → click** (current code runs image → face → click).
- TextScanner ran on the full composited `CIImage` with `options.maskText`.

## 4. Implementation steps

### Step 1 — Revert `UIViewExt.swift` to HEAD
`git checkout -- CoralogixInternal/Sources/Extention/UIViewExt.swift`. That removes
the AX code and its call sites in one shot; the committed version (UIKit walks,
`cxMask`, Flutter branch, transition skip) is the correct baseline.

### Step 2 — Restore TextScanner + tests
Commands above. Fix anything that drifted (Log API etc. — likely compiles clean,
deletion was only 2.5 weeks ago). SessionReplay target is SPM/podspec
directory-globbed; no project-file surgery needed for SDK sources or
`Tests/SessionReplayTests/`.

### Step 3 — SwiftUI scene detection (main thread, capture time)
In `UIViewExt.swift`, next to the existing Flutter detection helpers:

```swift
/// True when any view in the subtree is a SwiftUI hosting view.
/// Class-name string matching (no NSClassFromString — avoids +initialize side
/// effects; see Sentry's SentryUIRedactBuilder for precedent).
/// Short-circuits at FlutterView subtrees.
static func subtreeContainsSwiftUIHostingView(_ view: UIView) -> Bool
```

Match: `NSStringFromClass(type(of: view)).contains("UIHostingView")` — covers
`_TtGC7SwiftUI14_UIHostingView…` generics (verified: root hosting views in a SwiftUI
app and `UIHostingController` embeddings in hybrid apps all contain it; SwiftUI
List cells live inside a hosting view, so root detection suffices).

### Step 4 — Thread the flag through `URLEntry`
- `URLEntry` (struct, `SessionReplay/Sources/URLManager.swift:15`): add
  `var containsSwiftUIContent: Bool = false`.
- `SessionReplayModel` builds the entry at `SessionReplayModel.swift:464` (function
  around `saveScreenshotToFileSystem`/`handleCapturedData`); the detection must run
  on the **main thread during capture** (same place the capture happens —
  `prepareScreenshotImageOnMain` / `captureScreenshotImage` path), then flow with the
  properties to entry construction. Follow how `point` (click point) flows — same
  pattern. Do not call the detection off-main.

### Step 5 — Re-add pipeline stages (`ScannerPipeline.swift`)
- `let needsSwiftUIMasking = urlEntry.containsSwiftUIContent`
- `isTextScannerEnabled  = needsSwiftUIMasking && !(options.maskText?.isEmpty ?? true)`
- ImageScanner gate: keep current credit-card-only behavior for everyone, **plus**
  when `needsSwiftUIMasking && options.maskAllImages` run with
  `maskAll: !options.maskOnlyCreditCards` (i.e. old behavior, SwiftUI-scoped):
  `isImageScannerEnabled = options.maskOnlyCreditCards || (needsSwiftUIMasking && options.maskAllImages)`
  with `maskAll: needsSwiftUIMasking && options.maskAllImages && !options.maskOnlyCreditCards`.
- Restore old stage order: image → text → face → click.
- Update the header comment block (currently says "TextScanner removed").
- Pipeline already runs off-main (`URLObserver` processing queue,
  `URLManager.swift:46-60`) — no threading work needed.

### Step 6 — Tests
- Restored `TextScannerTests` must pass (`swift test` or the Xcode invocation in
  CLAUDE.md).
- New unit tests: `subtreeContainsSwiftUIHostingView` (use a real
  `UIHostingController(rootView: Text("x")).view` for positive; plain UIKit tree +
  Flutter-named fake for negative/short-circuit) and ScannerPipeline gating
  (flag off → text stage skipped even with maskText set).
- Repo rules (CLAUDE.md): no assert/precondition/fatalError; iOS 13 min —
  `#available` guards (TextScanner already handles its iOS-version surface);
  shared mutable state needs NSLock/serial queue.

### Step 7 — Harness validation
```bash
tool/run_leak_harness.sh        # requires a booted simulator
```
- UIKit scenarios (`1fps`, `navigate`): must stay 0-leak — path untouched.
- SwiftUI scenarios (`swiftui_list`, `swiftui_navigate`): now validate the OCR path,
  which is production-honest (OCR has **no AX dependence**, unlike the dead-end AX
  approach which only worked because XCUITest activates the AX runtime).
- Sentinels are high-contrast monospaced Latin → OCR-friendly; expect green. Note in
  PR that harness-green ≠ field-no-leak for OCR (accepted).
- Check `[SR-perf]` timings in the logs; OCR stage is off-main, watch frame cadence.
- Last known-good artifacts for comparison: Jun-9 runs had 0 leaks/188 frames
  (`$TMPDIR/cx_leak_harness_48627`).

### Step 8 — Docs + changelog
- `docs/swiftui-masking-investigation.md`: add "Option 0 (chosen interim): restored
  Vision OCR + rectangle image masking, SwiftUI-scoped" + update §5 disposition table.
- CHANGELOG entry (next unreleased version; current released is 2.8.0).
- Demo-app parity rule: harness views exist in DemoAppSwiftUI only by design (they
  test the SwiftUI-specific path; UIKit harness already exists in DemoAppSwift) — no
  parity action needed.

## 5. Key files quick reference

| File | Role |
|---|---|
| `CoralogixInternal/Sources/Extention/UIViewExt.swift` | Capture + sync mask-rect walks; add SwiftUI detection helper here |
| `SessionReplay/Sources/SessionReplayModel.swift` | Capture orchestration; URLEntry construction at :464 |
| `SessionReplay/Sources/URLManager.swift` | `URLEntry` struct (:15), `URLObserver` pipeline invocation (:46) |
| `SessionReplay/Sources/ScannerPipeline.swift` | Async post-capture stages; re-add text stage + image maskAll here |
| `SessionReplay/Sources/ImageScanner.swift` | Exists, full maskAll support, needs only re-wiring |
| `SessionReplay/Sources/TextScanner.swift` | To be restored from `6006933^` |
| `Tests/SessionReplayTests/TextScannerTests.swift` | To be restored from `6006933^` |
| `tool/run_leak_harness.sh` | E2E leak harness (keep this session's fixes) |
| `docs/swiftui-masking-investigation.md` | Full investigation: AX dead end, Sentry/Datadog analysis, future options |

## 6. Estimate

~2–3 days: day 1 = steps 1–5; day 2 = tests + harness + perf; day 3 = buffer/docs/PR.
