# Crash reports lost when Firebase Crashlytics initialises before the Coralogix SDK — plan

Ticket: TBD (CX). Branch: `claude/plcrashreporter-firebase-conflict-bd4591`.
Affects: native iOS customers that call `FirebaseApp.configure()` before `CoralogixRum.init`, and
**every** React Native / Flutter customer with Crashlytics (Firebase is configured natively, the
Coralogix SDK is initialised from JS / Dart seconds later).

Sources verified: PLCrashReporter 1.12 (`.build/index-build/checkouts/plcrashreporter`) and
firebase-ios-sdk 12.13.0 (the DemoApp's SPM checkout). Line numbers below refer to those.

## In one paragraph

Firebase Crashlytics handles a native crash before we do and, while handling it, removes our
crash handler — so our report is never written, and the customer sees the crash only in Firebase.
Registration order decides who gets removed, and in React Native / Flutter apps Firebase is
always registered first. The fix moves our crash handler to switch on at image load, before the
app's own code runs, so Firebase captures it as pre-existing and puts it back at crash time —
using Firebase's own interop mechanism. Customers change nothing: native apps update the SDK,
RN / Flutter apps update the plugin.

## Root cause (verified in both codebases)

The report is **never written**. Nothing deletes it at relaunch — neither SDK touches the other's
files (PLCrashReporter: `Caches/com.plausiblelabs.crashreporter.data/<bundle-id>/`,
`PLCrashReporter.m:934`; Crashlytics: its own `com.crashlytics` tree).

Sequence when Firebase installs first:

1. `FirebaseApp.configure()` → Crashlytics installs BSD signal handlers and a **Mach exception
   server** for `EXC_BAD_ACCESS | BAD_INSTRUCTION | ARITHMETIC | BREAKPOINT | GUARD`
   (`FIRCLSMachException.c:101`). While doing so it snapshots the sigactions that existed at that
   moment as `originalActions` (`FIRCLSSignal.c:100-106`) — empty, because we are not there yet.
   Installation runs **asynchronously** on a global queue with no wait
   (`FIRCLSContext.m:174-198`, `dispatch_group_notify` at 227).
2. `CoralogixRum.init` → `initializeCrashInstrumentation` → PLCrashReporter `sigaction`s its BSD
   handler (`.BSD` mode installs **no** Mach port).
3. A hardware fault happens. Mach exceptions are delivered **before** any BSD signal is generated,
   so Crashlytics' server gets it regardless of registration order. Its dispatch
   (`FIRCLSMachException.c:245`) calls `FIRCLSSignalSafeInstallPreexistingHandlers`, which first
   sets every fatal signal to `SIG_DFL` (`FIRCLSSignal.c:149-164`) and then re-installs only
   `originalActions` — nothing. **Our sigaction is gone.** Crashlytics records, replies
   `KERN_SUCCESS`, the thread resumes, re-faults, and dies on `SIG_DFL`.
4. Next launch: `hasPendingCrashReport()` is `false`. There was never anything to find.

Consequences:

- **Lost:** everything in Crashlytics' Mach mask. Measured on arm64: `fatalError`, force-unwrap
  and out-of-bounds all raise `SIGTRAP` (EXC_BREAKPOINT); bad pointers raise `SIGSEGV`. That is
  essentially every Swift runtime crash.
- **Survives:** `abort()` and uncaught `NSException` (`SIGABRT` is BSD-only; our handler is
  top-most and chains to Crashlytics via `previous_action_callback`, `PLCrashSignalHandler.mm:112`).
- The "Firebase first in source" order is a **race** we almost always lose in native apps and
  **always** lose in RN/Flutter (our init waits for the JS/Dart runtime).
- If Coralogix installs first, Crashlytics snapshots *our* handler and restores it at crash time —
  the fault is re-delivered to us and both reports are written. **Being first is the fix.**
- `PLCrashReporterSignalHandlerTypeMach` makes it **worse**: PLCrashReporter forwards to the
  previous port first and writes nothing when it answers `KERN_SUCCESS`
  (`PLCrashReporter.m:255`). Ruled out.
- Crashlytics installs nothing while a debugger is attached (`FIRCLSContext.m:174`): the bug does
  **not** reproduce from Xcode.

## Design decision

**Install PLCrashReporter at image load (`+load`), before `main()`.** Nothing the host app does
— `configure()` in `AppDelegate`, Remote Config, React Native's bridge — can run earlier, so
Crashlytics always captures our handler as pre-existing and restores it at crash time. We use its
own interop mechanism instead of fighting it.

- Unconditional. No arming flag, no purge-when-disabled policy: `.errors` off is the customer's
  choice, and the handler's output is simply never read. PLCrashReporter opens the report with
  `O_TRUNC` (`PLCrashReporter.m:147`), so at most one — the latest — report waits on disk.
- Lives in the **iOS SDK**. Native customers update the SDK; RN and Flutter plugins bump the pod.
  **No customer code change, no new public API.**
- `.BSD` mode is kept. Symbolication strategy is kept at `.all` so this fix changes ordering
  only, not report content (see *Out of scope*).
- Report directory moves out of `Caches` (OS-purgeable) to `Application Support/CoralogixRum`,
  next to `CrashEventStore`. A one-time read of the legacy location covers the upgrade.

Rejected: a customer-called early-install API (customers on RN cannot move Firebase; Remote
Config customers cannot move `configure()`); a constructor in the RN plugin (redundant once the
SDK carries its own `+load`); MetricKit as a second source (a feature, not this fix — see below).

## What changes for a customer — nothing in their code

### Native app

Their `AppDelegate` today is their `AppDelegate` after the fix:

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    FirebaseApp.configure()                              // still first — fine now
    // … Remote Config fetch, feature flags, anything …
    self.coralogixRum = CoralogixRum(options: options)   // still later — no longer loses crashes
    return true
}
```

Only *when* our crash catcher switches on changes:

```
dyld loads the app image
  └─ Coralogix +load          → PLCrashReporter enabled            ← ours, first, always
main()
  └─ didFinishLaunching
       ├─ FirebaseApp.configure()   → Crashlytics snapshots existing handlers = ours
       └─ CoralogixRum(options:)    → adopts the enabled reporter, reads any pending report
crash
  └─ Crashlytics' Mach handler restores the "pre-existing" handlers = ours
     → the fault is re-delivered → we write our report too
```

Customer action: update the SDK version (SPM tag or `pod update Coralogix`).

### React Native app

Native and JS sides stay exactly as they are:

```objc
// ios/MyApp/AppDelegate.mm — unchanged
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [FIRApp configure];                       // required here by @react-native-firebase/app — stays
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}
```

```ts
// index.ts — unchanged, still runs seconds later
CoralogixRum.init({ application: 'MyApp', version: '1.0.0', publicKey: '…', coralogixDomain: 'US2' });
```

The SDK's `+load` runs inside the RN app binary at image load — before `AppDelegate`, before
`[FIRApp configure]`, before the bridge exists. The only change is in **our** plugin's podspec
(see *React Native* below). Customer action: bump the npm package, `pod install`.

## iOS — exact steps

### 1. New SPM target `CoralogixCrashBootstrap` (Objective-C)

`+load` is not expressible in Swift and SPM targets are single-language.

```
CoralogixCrashBootstrap/
  Sources/
    include/CRXCrashBootstrap.h
    CRXCrashBootstrap.m
```

`Package.swift`:

```swift
.target(
    name: "CoralogixCrashBootstrap",
    dependencies: [.product(name: "CrashReporter", package: "plcrashreporter")],
    path: "CoralogixCrashBootstrap/Sources/",
    publicHeadersPath: "include"
),
.target(
    name: "Coralogix",
    dependencies: [
        .target(name: "CoralogixInternal"),
        .target(name: "CoralogixCrashBootstrap"),
        .product(name: "CrashReporter", package: "plcrashreporter")
    ],
    path: "Coralogix/Sources/"
),
```

`CRXCrashBootstrap.h`:

```objc
#import <Foundation/Foundation.h>
@class PLCrashReporter;

NS_ASSUME_NONNULL_BEGIN

/// Enables PLCrashReporter at image load — before main(), before the host's AppDelegate, and
/// therefore before any other crash reporter the host configures. Read by the Swift side.
@interface CRXCrashBootstrap : NSObject
/// The reporter enabled in +load, or nil if enabling failed (see enableError).
@property (class, nonatomic, readonly, nullable) PLCrashReporter *reporter;
/// Why enabling failed, if it did. Logged by the Swift side once Log is available.
@property (class, nonatomic, readonly, nullable) NSError *enableError;
/// Directory PLCrashReporter writes under: Application Support/CoralogixRum.
@property (class, nonatomic, readonly) NSString *basePath;
@end

NS_ASSUME_NONNULL_END
```

`CRXCrashBootstrap.m`:

```objc
#import "CRXCrashBootstrap.h"
#if __has_include(<CrashReporter/CrashReporter.h>)
#import <CrashReporter/CrashReporter.h>   // CocoaPods framework
#else
@import CrashReporter;                     // SPM module
#endif

// Written once in +load, on the main thread, before any other code of ours can run; read-only
// afterwards. That ordering is the synchronisation — no lock.
static PLCrashReporter *_reporter;
static NSError *_enableError;

@implementation CRXCrashBootstrap

+ (void)load {
    @autoreleasepool {
        // Crashlytics re-installs, at crash time, whichever signal handlers existed when it
        // installed its own. Being enabled at image load puts us in that set no matter how
        // early the host calls FirebaseApp.configure().
        PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc]
            initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
                symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll
                             basePath:self.basePath];
        PLCrashReporter *reporter = [[PLCrashReporter alloc] initWithConfiguration:config];
        NSError *error = nil;
        if ([reporter enableCrashReporterAndReturnError:&error]) {
            _reporter = reporter;
        } else {
            _enableError = error;
        }
    }
}

+ (PLCrashReporter *)reporter { return _reporter; }
+ (NSError *)enableError { return _enableError; }

+ (NSString *)basePath {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                            NSUserDomainMask, YES).firstObject;
    return [(support ?: NSTemporaryDirectory()) stringByAppendingPathComponent:@"CoralogixRum"];
}

@end
```

No `Log` here: `CoralogixInternal` is Swift and must not be imported into a pre-main path. The
error is stored and logged by the Swift side.

### 2. `Coralogix/Sources/Instrumentation/CrashInstrumentation.swift`

```swift
#if canImport(CoralogixCrashBootstrap)
import CoralogixCrashBootstrap   // SPM module; under CocoaPods the class is in this pod already
#endif

public func initializeCrashInstrumentation() {
    guard let crashReporter = Self.bootstrappedCrashReporter() else { return }

    switch FirebaseRuntimeDetector.presence() { … }        // unchanged, log only

    // No enable() here: enabled in +load, or in the fallback below.

    if crashReporter.hasPendingCrashReport() { … }          // unchanged
    else { self.recoverLegacyPendingCrashReport() }         // step 3

    self.resendPendingStoredCrashEvents()                   // unchanged
}

/// The reporter `CRXCrashBootstrap` enabled at image load. If +load did not run or failed,
/// enable one here — today's behaviour, minus the ordering guarantee — rather than lose crash
/// reporting altogether.
private static func bootstrappedCrashReporter() -> PLCrashReporter? {
    if let reporter = CRXCrashBootstrap.reporter { return reporter }
    if let error = CRXCrashBootstrap.enableError {
        Log.e("Crash bootstrap failed to enable PLCrashReporter at load: \(error)")
    }
    let config = PLCrashReporterConfig(signalHandlerType: .BSD,
                                       symbolicationStrategy: .all,
                                       basePath: CRXCrashBootstrap.basePath)
    guard let reporter = PLCrashReporter(configuration: config) else {
        Log.e("Could not create an instance of PLCrashReporter")
        return nil
    }
    reporter.enable()
    return reporter
}
```

Make the candidate injectable (`bootstrappedCrashReporter(candidate: PLCrashReporter? = CRXCrashBootstrap.reporter)`)
so the fallback path is unit-testable — `+load` cannot be undone in the test process.

### 3. Legacy report location (upgrade path)

Versions ≤ 2.18.x wrote under PLCrashReporter's default `Caches` directory. A reporter created
with the **default** config and **never enabled** resolves that directory; `hasPendingCrashReport`,
`loadPendingCrashReportDataAndReturnError` and `purgePendingCrashReport` need no handler.

```swift
/// One-time read of a report written by an SDK version that used PLCrashReporter's default
/// Caches location. Runs only when the current location has nothing pending: the recovery
/// state (`pendingCrashPurge` / `pendingCrashReportId`) holds one report per launch, and the
/// current one is the more recent. Remove once no supported version predates the move.
private func recoverLegacyPendingCrashReport() {
    let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
    guard let legacy = PLCrashReporter(configuration: config),
          legacy.hasPendingCrashReport() else { return }
    // identical to the pending-report branch of initializeCrashInstrumentation, with `legacy`
    // as the reporter — extract that branch into `recoverPendingCrashReport(from:)` and call
    // it from both places.
}
```

### 4. `Coralogix.podspec` — mixed-language pod

```ruby
spec.source_files        = ['Coralogix/Sources/**/*.swift',
                            'CoralogixCrashBootstrap/Sources/**/*.{h,m}']
spec.public_header_files = 'CoralogixCrashBootstrap/Sources/include/*.h'
```

Swift files in the pod see the ObjC class through the pod's module; no `import` needed (hence
`#if canImport` above). `spec.static_framework = true` stays. Lint under
`pod lib lint Coralogix.podspec --include-podspecs=CoralogixInternal.podspec` on the CI toolchain
(macOS 14 / Xcode 15.3) **and** in a sample app Podfile with
`use_frameworks! :linkage => :static` — what RN + Firebase requires.

Dead-strip: the Swift SDK references `CRXCrashBootstrap` from `initializeCrashInstrumentation`,
so the object file is linked (and `+load` runs) in every configuration; RN Podfiles with Firebase
also pass `-ObjC`.

### 5. Distribution (`build.sh`)

`build.sh` archives the `Coralogix` scheme and converts products to dynamic frameworks (line 58).
The bootstrap target links statically into `Coralogix.framework`; verify the xcframework built by
`./build.sh` still runs `+load` pre-main when the framework is linked (not `dlopen`ed) by a host.

### 6. Tests (`Tests/CoralogixRumTests`)

- `CRXCrashBootstrap.reporter` is non-nil in the test process and its report path is under
  `Application Support/CoralogixRum` — proves `+load` ran and the directory moved.
- `bootstrappedCrashReporter(candidate: nil)` returns an enabled fallback reporter (once per
  process — PLCrashReporter refuses a second `enable`; structure the test accordingly).
- Legacy recovery: place a report fixture at the legacy path, run
  `recoverLegacyPendingCrashReport`, assert the crash span carries the fixture's signal name /
  process fields, and that purge is deferred to upload confirmation exactly as in
  `CrashDeliveryTests`. Fixture: `generateLiveReport()` from a non-enabled reporter, written to
  the legacy `crashReportPath` (verify the API works un-enabled; otherwise commit a `.plcrash`).
- No new keys, no new swizzles; `pendingCrashPurge` / `pendingCrashReportId` semantics unchanged.

No UI test: Crashlytics needs a valid `GoogleService-Info.plist`, which CI does not have. The
end-to-end check is manual (below).

### 7. Version, CHANGELOG, README

- **Patch bump** via `/bump-version` (fix-shaped; wire format unchanged).
- `CHANGELOG.md`, one line: *Crash reporting now captures native crashes when another crash
  reporter (for example Firebase Crashlytics) is set up before the Coralogix SDK. No integration
  change is required.*
- README: **no change** — no public API, nothing a customer does differently.

## React Native (`cx-react-native-plugin`) — exact steps

`libs/cx-plugin/CxSdk.podspec` pins `Coralogix`, `CoralogixInternal`, `SessionReplay` at 2.15.1.
Bump all three to the fixed version. **No native or JS code change**: the SDK's `+load` runs in
the RN app binary at image load, before `AppDelegate` and before `[FIRApp configure]`.

Verify in the RN example app: Podfile has `use_frameworks! :linkage => :static` (required by RN +
Firebase); `pod install`; the matrix below with Firebase configured in `AppDelegate`.

## Flutter (`cx-flutter-plugin`)

Same: bump the iOS pod dependency. No plugin code.

## Verification — manual, on device, **detached from the debugger**

Crashlytics installs nothing under a debugger, so launch from the home screen (or Release).

Setup: `Example/DemoAppSwift/AppDelegate.swift` currently configures Firebase **after**
Coralogix (line 79) — the good order. Move `FirebaseApp.configure()` above the Coralogix init
for the test, with a valid `GoogleService-Info.plist`.

| Trigger | Signal | Before fix | After fix |
|---|---|---|---|
| force-unwrap `nil` / `fatalError` | SIGTRAP | Crashlytics only | both |
| write to `0x10` | SIGSEGV | Crashlytics only | both |
| `NSException.raise()` | SIGABRT | both | both |
| Same three, no Firebase linked | — | Coralogix | Coralogix (unchanged) |

For each: crash → relaunch → expect a crash span with the matching `exceptionType`, anchored to
the crashed session (`overrideSessionForCrashedSession`), and Crashlytics still receiving its
report (its console log). Also:

- **Upgrade path:** install a 2.18.2 build, crash, install the fixed build, launch → the legacy
  report is delivered once and purged after confirmation.
- **RN example app**, same matrix, Firebase in `AppDelegate`; plus a JS crash as a control (goes
  through the bridge → `CrashEventStore`, unaffected by any of this).

## Accepted behaviour

- `.errors` disabled: the handler is live, its single latest report is never read. If the
  customer later enables `.errors`, that crash is reported on that launch, attributed to the
  last-known session — exact if it was the previous launch, approximate otherwise. Customer's
  choice; no code.
- Handler enabled in apps that link the SDK but never initialise it: a file in Application
  Support, nothing sent.

## Out of scope — separate tickets

1. **MetricKit `MXCrashDiagnostic` as a second crash source** (iOS 14+). OS-produced, cannot be
   pre-empted in-process, also covers stack overflow and watchdog terminations that
   PLCrashReporter cannot catch on iOS. `MyMetricSubscriber` already receives
   `MXDiagnosticPayload` and drops `crashDiagnostics`. Needs a converter, a source tag and
   `pastDiagnosticPayloads` on registration. A feature with backend work — not this fix.
2. **Crashlytics loses NSException details when we are present.** PLCrashReporter's
   `uncaught_exception_handler` calls `abort()` without chaining (`PLCrashReporter.m:346-362`);
   Crashlytics hooks `std::set_terminate` (`FIRCLSException.mm:70`), which never runs. Their
   report shows a bare `SIGABRT`. Pre-existing.
3. **Symbolication strategy.** PLCrashReporter recommends `.none` for release; we use `.all`.
   Switching changes frame content and depends on backend dSYM symbolication — decide separately.
