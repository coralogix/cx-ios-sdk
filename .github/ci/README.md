# CI layout

`ci.yml` is the only workflow that reacts to a pull request. Everything it needs
is a reusable workflow, so the same definitions serve PRs, master and manual
dispatch.

```
ci.yml ─┬─ ci-component-unit.yml   SPM unit tests
        ├─ ci-ui-tests.yml         XCUITest, tiers: component + smoke + soak
        │                          (a `quarantine` tier exists and never runs)
        ├─ ci-podspec-lint.yml     the three podspecs, in parallel
        └─ ci-passed               the required status check
```

Shared steps live in `.github/actions/`: `setup-xcode`, `boot-simulator`,
`setup-demo-app`, `cache-xcode-build`.

`.github/ci/ui-suites.json` is the single source of truth for how the XCUITest
suites are tiered and sharded. A UI test that is not listed there does not run,
and the `plan` job fails the build for it.

## The rules live in one place

**`.claude/rules/TESTING_AND_CI.md`** — where a test belongs, how to add one,
how shards are packed, what the leak harness actually verifies, which
optimisations were measured and rejected, and the traps in this setup.

That file is the source of truth so the guidance cannot drift between two
copies. Read it before adding a test or changing a workflow.

## Why the topology looks like this

Three things are worth knowing without opening that file:

- **Build once, fan out.** One build job produces the test products; the shards
  consume them as an artifact. Wall-clock is the slowest shard, not the sum.
- **`plan` runs on ubuntu in ~9s** and rejects every way a shard can silently
  run the wrong thing — `xcodebuild` reports "executed 0 tests" as success, so
  these guards are what stop a test quietly never running.
- **Toolchains are pinned per workflow**, not shared: tests on macOS 15 /
  Xcode 16.4, podspec lint on macOS 14 / Xcode 15.3.
