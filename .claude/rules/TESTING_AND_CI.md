# Testing & CI

Read this before adding a test, changing a workflow, or trying to make CI faster.

---

## Where a new test goes

| The test… | Target | Runs in |
|---|---|---|
| exercises SDK logic in-process | `Tests/CoralogixRumTests`, `Tests/CoralogixInternalTests`, `Tests/SessionReplayTests` | `component · unit` |
| drives the demo app and asserts one feature | `Example/DemoAppUITests` | a `component` UI shard |
| drives a path joining several features (interaction + session + export + schema) | `Example/DemoAppUITests` | a `smoke` shard |
| probes for leaks or performance | `Example/DemoAppUITests/SessionReplayLeakUITests` | a `soak` shard, **via the harness** |

A SwiftUI-side UI test goes in `Example/DemoAppSwiftUIUITests` against the
`DemoAppSwiftUI` scheme. Demo-app parity still applies: a new screen or control
must land in both demo apps.

---

## A new UI test MUST be registered

Add its identifier to a shard in `.github/ci/ui-suites.json`. The `plan` job
fails the build if you don't, and that guard exists because
`DemoAppSwiftUIUITests` sat wired into a scheme executing **zero tests** without
anyone noticing.

`plan` rejects every way a shard can silently run the wrong thing — all of which
`xcodebuild` otherwise reports as success:

- a test in the source but in no shard
- a declared identifier matching no test (its shard would run nothing)
- a shard with an empty `tests` array (no `-only-testing` filter runs the *whole* bundle)
- a harness shard holding more than one test (only the first would run)
- a shard naming a scheme with no shared `.xcscheme`, or one that does not build
  the target its tests live in

Identifiers are `TestTarget/TestClass/testMethod`.

---

## Shard packing

Shards run as parallel jobs against one shared build, so a tier costs its
**slowest shard**, not the sum. But:

> **Per-shard overhead is ~5-6 minutes** — simulator boot (~60-76s), artifact
> unpack (4-104s), and xcodebuild's app install/launch (143-193s) — for 2-3
> minutes of actual testing.

So:

- **Don't create a shard for less than ~2 minutes of tests.** It will spend more
  on setup than it saves.
- **Do split a shard that dominates the critical path.** Two leak tests paired
  were one ~8.8m shard; split one-per-shard they run ~6.5m each in parallel.
- Record measured runtime in `seconds` so the next repack is a data decision.
- Shard wall-clock varies **±4 minutes run to run for identical tests**. Never
  tune packing from a single run, and never quote a single run as "the" number.

---

## Harness shards (`"harness": true`)

`SessionReplayLeakUITests` asserts only that a screen appeared. The leak check is
a pixel scan for unmasked sentinels performed by `tool/run_leak_harness.sh` over
frames captured by its mock upload server. **Running those tests without the
harness proves nothing.**

- A harness shard holds **exactly one test** — the harness takes a single
  `-only-testing` filter. `plan` enforces this.
- CI passes `CX_IOS_XCTESTRUN` (reuse the shared build, don't rebuild) and
  `CX_IOS_ONLY_TESTING` (one scenario per shard). Both default to standalone
  behaviour, so `tool/run_leak_harness.sh` still works locally with no arguments.
- Exit codes are meaningful: **1 = a real leak, 2 = infrastructure failure and
  not a verdict.** Keep them distinguishable in any error reporting you touch.

---

## Caching — measure before you add any

The instinct to cache is usually wrong here, and it was wrong twice:

- **Never cache DerivedData.** `actions/cache` resets mtimes on extraction, so
  every source looks newer than its build products and xcodebuild rebuilds
  anyway. Measured: an exact cache hit produced a **slower** build (302s vs 282s
  cold) after paying 99s to restore. Removing it took the UI build 2.3m → 1.5m.
- The demo app's SPM graph is mostly **binary** targets (firebase-ios-sdk, grpc,
  abseil), so it was never the expensive thing. The UI build compiles in ~111s
  with every cache missing.
- SPM and CocoaPods caches are cheap and fine. **Bump the cache key whenever you
  change the cached paths**, or `restore-keys` will keep returning entries that
  lack the new content.
- Shards read no cache at all — they consume the build artifact — so caching
  barely touches the critical path.

**What actually made CI fast:** parallelism, a larger runner for the one build
job, pinning `ARCHS` to a single slice, and not running the unit tests twice.

---

## Things that will bite you

- **`pod lib lint` runs the unit tests.** `Coralogix.podspec` and
  `SessionReplay.podspec` declare `test_spec` blocks. Lint passes `--skip-tests`
  because `component · unit` already covers them, over all three targets rather
  than two. If you add a `test_spec` expecting CI to run it, it won't.
- **Build and test runners must share a CPU architecture.** Shards execute the
  build job's simulator binaries. GitHub's `-large` macOS runners are Intel;
  `macos-15` and `-xlarge` are Apple Silicon. A `lipo` check fails loudly if this
  ever diverges.
- **Pin Xcode, never probe it.** A fallback ladder silently changes the compiler,
  so a green run proves nothing about which toolchain ran. Toolchains differ per
  workflow — tests on macOS 15 / Xcode 16.4, podspec lint on macOS 14 / Xcode 15.3.
- **The simulator runtime is derived from the selected Xcode's SDK.** A runner
  carries runtimes newer than its SDK (18.6 and 26.x beside an 18.5 SDK); picking
  one fails at launch.
- **`xcodebuild ... | head` aborts with 134.** `head` closes the pipe, xcodebuild
  takes the EPIPE as an uncaught Foundation exception. Capture output in full,
  then parse.
- **`xcrun simctl boot` blocks.** Detach it if you want it overlapped with other
  setup; a "non-blocking" flag that only skips the later wait buys nothing.
- **Don't relocate the demo app's SPM checkouts.** Its Crashlytics run script
  resolves Firebase at `${BUILD_DIR%/Build/*}/SourcePackages/...`, which only
  exists at the default location under `-derivedDataPath`.

---

## Unit tests stay serial, and un-retried

`-parallel-testing-enabled NO` is deliberate: the SDK swizzles global process
state, so tests sharing a process must not interleave.

UI shards use `-retry-tests-on-failure` because they round-trip through a live
schema-validator and absorb network blips. **Do not add retries to the unit
job** — there, a flaky test is more likely to be a real swizzling race, and a
retry would hide exactly the signal worth having.

---

## Before claiming a speed-up

State whether a number is **measured or estimated**, and say which run it came
from. Given ±4m shard variance, a single green run is not evidence. Compare
against a baseline on the *same commit* — comparing across branches once made a
10.9m job look like a 4m15s regression that never happened.
