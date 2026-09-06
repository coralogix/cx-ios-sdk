# CI layout

`ci.yml` is the only workflow that reacts to a pull request. Everything it needs
is a reusable workflow, so the same definitions serve PRs, master, the nightly
run and manual dispatch.

```
ci.yml ─┬─ ci-component-unit.yml   SPM unit tests
        ├─ ci-ui-tests.yml         XCUITest, tiers: component + smoke
        ├─ ci-podspec-lint.yml     the three podspecs, in parallel
        └─ ci-passed               the one status branch protection requires

ci-nightly.yml ── ci-ui-tests.yml  tier: soak
```

Shared steps live in `.github/actions/`: `setup-xcode`, `boot-simulator`,
`setup-demo-app`, `cache-xcode-build`.

## Test tiers

| Tier | What belongs in it | Runs on |
|---|---|---|
| `component` | One test drives one feature and asserts on it. | every PR |
| `smoke` | One test walks a path that joins several features — interaction capture + session context + export + schema validation. | every PR |
| `soak` | Leak and performance probes. Not feature tests; too slow and too environment-sensitive to gate a PR. | nightly |

The SPM unit tests in `Tests/` are the `component` tier at the unit level and run
as a single job — see the header of `ci-component-unit.yml` for why they are not
sharded.

## Adding a UI test

Add its identifier to a shard in `ui-suites.json`. The `plan` job fails the build
if a test method exists in source but is in no shard, or if a declared identifier
matches no test — a shard whose `-only-testing` filter matches nothing runs zero
tests, which `xcodebuild` reports as success.

Shards run as parallel jobs against one shared build, so a tier costs its
*slowest* shard, not the sum of its tests. `seconds` records each shard's
measured runtime so the packing can be rebalanced from data; keep shards under
roughly 200s.

## Things that will bite you

- **Build and test runners must share a CPU architecture.** The shards run the
  build job's simulator binaries. GitHub's `-large` macOS runners are Intel while
  `macos-15` and `-xlarge` are Apple Silicon, so the larger runner that pairs
  with a standard `macos-15` shard is `-xlarge`. A shard-side `lipo` check fails
  loudly rather than letting this surface as a simulator launch error.
- **The simulator runtime is derived from the selected Xcode's SDK.** A runner
  can carry runtimes newer than its SDK (18.6 and 26.x alongside an 18.5 SDK) and
  picking one of those fails at launch. Overriding `runtime` opts out of that.
- **Xcode is pinned, not probed.** A fallback ladder silently changes the
  compiler under you, so a green run proves nothing about which toolchain ran.
- **Unit tests stay serial.** The SDK swizzles global process state, so tests
  sharing a process must not interleave.

## What actually makes this fast

Measured, so that the next person optimising here starts from evidence:

| lever | effect |
|---|---|
| parallel shards / matrix | UI 32m → ~8.5m, podspec lint 10.5m → ~7m |
| `macos-15-xlarge` for the build | build 5m50s → ~1.5m |
| `ARCHS` pinned to one slice | not a win over the old workflow — it offsets one. A *concrete* destination (what the old job used) already built one arch; `generic/platform` builds arm64 *and* x86_64, so pinning restores parity while keeping the build simulator-free |
| SPM / Pods caches | small; `pod install` is 8s and the SPM graph is mostly binary targets |
| DerivedData cache | **removed — it made things slower** |

The DerivedData cache is the trap. `actions/cache` resets mtimes on extraction,
so every source file looks newer than its build products and xcodebuild rebuilds
regardless: the unit job hit both cache keys exactly and still took 302s against
282s cold, having spent 99s on the restore. The UI build compiles in ~111s with
every cache missing, because firebase-ios-sdk ships most of its weight as binary
targets. Don't re-add it without measuring first.

## Running a tier by hand

```bash
# One shard, exactly as CI runs it
xcodebuild test -workspace Example/DemoApp.xcworkspace -scheme DemoAppSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  $(jq -r '.shards[] | select(.id=="smoke-interaction") | .tests[] | "-only-testing:" + .' .github/ci/ui-suites.json)
```
