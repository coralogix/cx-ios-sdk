# CI layout

`ci.yml` is the only workflow that reacts to a pull request. Everything it needs
is a reusable workflow, so the same definitions serve PRs, master and manual
dispatch.

```
ci.yml ─┬─ ci-component-unit.yml   SPM unit tests
        ├─ ci-ui-tests.yml         XCUITest, tiers: component + smoke
        ├─ ci-podspec-lint.yml     the three podspecs, in parallel
        ├─ ci-passed               the real gate
        └─ legacy-required-check    mirrors it as "Run DemoApp UI Tests", the
                                    name master's protection still requires;
                                    delete once protection points at ci-passed

```

Shared steps live in `.github/actions/`: `setup-xcode`, `boot-simulator`,
`setup-demo-app`, `cache-xcode-build`.

## Test tiers

| Tier | What belongs in it | Runs on |
|---|---|---|
| `component` | One test drives one feature and asserts on it. | every PR |
| `smoke` | One test walks a path that joins several features — interaction capture + session context + export + schema validation. | every PR |
| `soak` | Leak probes, run through `tool/run_leak_harness.sh`. The slowest shards here, so they set the critical path. | every PR |

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

## The soak tier needs the harness

`SessionReplayLeakUITests` asserts only that the screen appeared. The leak check
is a pixel scan for unmasked magenta sentinels, run by
`tool/run_leak_harness.sh` over frames captured by its mock upload server — so
running those tests bare proves nothing beyond "the app did not crash while
scrolling".

Shards marked `"harness": true` therefore invoke the script instead of calling
xcodebuild directly. The workflow passes it `CX_IOS_XCTESTRUN` so it reuses the
shared build rather than rebuilding the workspace, and `CX_IOS_ONLY_TESTING` so
each scenario gets its own shard and the two run in parallel. Both default to
standalone behaviour when unset, which is how the script still works locally:

```bash
tool/run_leak_harness.sh          # builds and runs the whole leak suite
```

Exit codes are meaningful: 1 is a real leak, 2 is an infrastructure failure and
not a verdict. A harness shard must hold exactly one test — the harness takes a
single `-only-testing` filter — and the plan job enforces that.

## What actually makes this fast

Measured, so that the next person optimising here starts from evidence:

| lever | effect |
|---|---|
| parallel shards / matrix | UI 32m → ~8.5m, podspec lint 10.5m → ~7m |
| `--skip-tests` on podspec lint | ~7m → ~1m; lint was re-running 1081 unit tests |
| `macos-15-xlarge` for the build | build 5m50s → ~1.5m |
| `ARCHS` pinned to one slice | not a win over the old workflow — it offsets one. A *concrete* destination (what the old job used) already built one arch; `generic/platform` builds arm64 *and* x86_64, so pinning restores parity while keeping the build simulator-free |
| SPM / Pods caches | small; `pod install` is 8s and the SPM graph is mostly binary targets |
| DerivedData cache | **removed — it made things slower** |
| zstd instead of gzip for the test-products artifact | gzip decompression was costing each shard 33-48s |

The DerivedData cache is the trap. `actions/cache` resets mtimes on extraction,
so every source file looks newer than its build products and xcodebuild rebuilds
regardless: the unit job hit both cache keys exactly and still took 302s against
282s cold, having spent 99s on the restore. The UI build compiles in ~111s with
every cache missing, because firebase-ios-sdk ships most of its weight as binary
targets. Don't re-add it without measuring first.

## Where the unit tests run

Once, in `ci-component-unit.yml`, over all three targets (1133 tests).

`pod lib lint` used to run them a second time, because `Coralogix.podspec` and
`SessionReplay.podspec` declare `test_spec` blocks. That was dropped with
`--skip-tests`: it covered only two of the three targets
(`CoralogixInternal.podspec` has no `test_spec`), it was the copy that flaked,
and SDK logic does not change with the distribution channel. Lint still builds
each pod under `--use-static-frameworks`, which is the part that genuinely
differs from the SPM path.

If you add a `test_spec` to a podspec expecting CI to run it, it will not —
remove `--skip-tests` from `ci-podspec-lint.yml` first, and be explicit about
what that buys over the unit job.

## Running a tier by hand

```bash
# One shard, exactly as CI runs it
xcodebuild test -workspace Example/DemoApp.xcworkspace -scheme DemoAppSwift \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  $(jq -r '.shards[] | select(.id=="smoke-interaction") | .tests[] | "-only-testing:" + .' .github/ci/ui-suites.json)
```
