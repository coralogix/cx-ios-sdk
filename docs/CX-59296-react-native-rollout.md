# CX-59296 — React Native rollout

The fix ([CX-59296](https://coralogix.atlassian.net/browse/CX-59296)) is entirely in the iOS SDK:
PLCrashReporter is enabled from `+load`, before `main()`, so a crash reporter the host app
configures first — Firebase Crashlytics — reinstates our signal handlers instead of replacing
them. React Native inherits it through the pod dependency.

**No plugin code changes, and no app-side changes.** `@react-native-firebase/app` keeps calling
`[FIRApp configure]` in the native AppDelegate and `CxSdk.initialize` keeps running from JS
seconds later; the handler is already installed before either.

RN is why this matters most: it is the only order RN apps can have, so the loss there is
deterministic rather than a race.

## Remaining work

### 1. Publish the iOS SDK to CocoaPods

RN is CocoaPods-only. Publish in dependency order with CDN propagation waits —
`./lint_and_push_cocoapods.sh` does this interactively:

```
CoralogixInternal  →  SessionReplay + Coralogix
```

Already verified locally: `pod lib lint Coralogix.podspec --include-podspecs=CoralogixInternal.podspec
--platforms=iOS --use-static-frameworks` passes. `--use-static-frameworks` is the linkage RN +
Firebase requires (`use_frameworks! :linkage => :static`), so the packaging is known good.

### 2. Bump `libs/cx-plugin/CxSdk.podspec`

It pins **2.15.1** for all three pods — three minors behind:

```ruby
s.dependency 'Coralogix',         '2.15.1'   # → the published version
s.dependency 'CoralogixInternal', '2.15.1'
s.dependency 'SessionReplay',     '2.15.1'
```

This is not just a number change. Jumping 2.15 → 2.18 brings everything in between, including the
Session Replay touch contract change (drop capture on a nil Flutter frame; interaction spans
without a screenshot id), interaction masking resolved from deliberate masking only, and the crash
re-send cap. Review those against the plugin's expectations before publishing the npm package.

### 3. Confirm `+load` fires in an RN app binary

Under static linking an object file nothing references is dropped, and `+load` with it. The Swift
side references `CRXCrashBootstrap`, and the class and its `+load` were confirmed present in the
built static framework (`nm` on `Coralogix.framework`), so this should hold — but it has only been
proven in an SPM build, not an RN one. Check it in the RN example app before release.

### 4. Reproduce end to end in the RN example app

Podfile needs `use_frameworks! :linkage => :static` (already required by RN + Firebase), Firebase
configured in the native AppDelegate, and a valid `GoogleService-Info.plist`.

**Launch detached from the debugger** — Crashlytics installs no handlers while one is attached, so
an Xcode run cannot reproduce the bug or prove the fix.

| Trigger | Expected |
|---|---|
| Native crash from a native module (force-unwrap nil) | crash event in Coralogix **and** in Firebase |
| JS crash | reaches Coralogix over the bridge as today — unaffected by this fix, a useful control |

Before the fix the native row produced a Firebase report and nothing in Coralogix.

## Flutter

Same shape: Firebase is configured natively, the SDK initializes from Dart. Bump the iOS pod
dependency in `cx-flutter-plugin`; no plugin code changes.

## Escape hatch

Deliberately absent from the README, and from the docs site with it: setting this key restores the
bug the fix removes, and the customers most likely to find it in public docs are the ones who can
least afford to flip it. This section is where support finds it instead.

**Reach for it only** when a customer reports something that began with 2.18.4 and looks tied to
the SDK being active before their own startup code — a conflict with another pre-`main()` library,
or a launch-time failure they cannot otherwise isolate. It settles the question in one build
instead of downgrading the whole SDK.

### What the customer changes

One key in their **app's** `Info.plist` — no code, nothing to call:

```xml
<key>CoralogixDisableEarlyCrashHandler</key>
<true/>
```

In Xcode: app target, **Info** tab, **+** on any row, key `CoralogixDisableEarlyCrashHandler`,
type **Boolean**, value **YES**. A string `"YES"` is accepted too. The key is read from the app
bundle at launch, so it needs a rebuild rather than just a restart.

| | Path |
|---|---|
| Native iOS | `<AppName>/Info.plist` |
| React Native | `ios/<AppName>/Info.plist` |
| Flutter | `ios/Runner/Info.plist` |

### What it does, and what it costs

Crash reporting stays on. Only the load-time install is skipped, so the SDK enables
PLCrashReporter at `CoralogixRum.init` — exactly how 2.18.3 and earlier behaved.

What is given up is the ordering guarantee. If the app configures another crash reporter before
our init, that reporter can displace our handler again and native crashes are lost, which is the
whole failure CX-59296 fixes. Removing the key and rebuilding reverts it.

### Confirming it took effect

Two independent signals in the device log (Console.app, filtered to the app):

- Ours, at warning level so ordinary log collection carries it:

  ```
  [CrashInstrumentation] early crash-handler install disabled by
  CoralogixDisableEarlyCrashHandler — enabling at init instead…
  ```

- Crashlytics', one line per signal, which reappear only when the early install is skipped:

  ```
  [Crashlytics] The signal SIGTRAP has a non-Crashlytics handler (plcrash_signal_handler).
  ```

  With the key absent those lines are gone. That contrast is how the switch was verified.
