# Code Review Instructions

Read these in order. Section 1 (Versioning) is always checked first. Section 4 (iOS SDK invariants) is what makes an iOS RUM SDK review different from a generic Swift review — flag any violation as a blocker.

## 1. Versioning (CRITICAL — check first)

**When reviewing PRs that modify `*.podspec`, `Package.swift`, `CoralogixInternal/Sources/Utils.swift` (the `Global.sdk` constant), or `CHANGELOG.md`:**

1. Extract the version bump (e.g., 3.9.0 → 4.0.0)
2. Check all commit messages in the PR for change types:
   - `feat!:` or `BREAKING CHANGE:` → requires **MAJOR** bump (X.0.0)
   - `feat:` → requires **MINOR** bump (x.Y.0)
   - `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`, `update:` → requires **PATCH** bump (x.y.Z)

3. **FLAG AS ERROR if:**
   - Major version bump without `feat!:` or `BREAKING CHANGE:` in commits
   - Minor version bump without any `feat:` commits
   - Version not bumped but changes warrant it
   - **Version is bumped in one file but not the others.** iOS distributes through CocoaPods AND has an in-source SDK version constant. Four files must move together: `Coralogix.podspec`, `CoralogixInternal.podspec`, `SessionReplay.podspec`, and `Global.sdk` in `CoralogixInternal/Sources/Utils.swift`. Any disagreement is a blocker.

> **Example violation:** PR has `feat: add user tracking` but bumps 2.0.0 → 3.0.0. This is WRONG — should be 2.1.0. Flag immediately.

> **Example violation:** Three podspecs say `2.8.0` but `Global.sdk` still says `2.7.0`. The SDK will report its own version incorrectly. Flag immediately.

**Conventional Commits:** `feat:`, `feat!:`, `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:`, `update:`

## 2. Principles

- **Follow SOLID principles** — Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, and Dependency Inversion.

- **Write clean, modular, and testable code**
  - Keep functions small, focused, and doing one thing — no "and/or" in names
  - Max 2–3 parameters; use options objects for more
  - No boolean flags — split into separate functions or use named options
  - No magic numbers/strings — extract literals into named constants (and for span attribute keys, that constant lives in `Keys.swift`)
  - Avoid deep nesting; use guard clauses and early returns
  - Positive conditionals — no double negatives; extract complex predicates
  - Minimize side effects; prefer pure functions
  - Comment *why*, not *what* — intent and trade-offs only

## 3. Review checklist (generic)

- [ ] SemVer bump matches change type
- [ ] No runtime exceptions — property access is guarded
- [ ] No framework interference
- [ ] No performance regressions
- [ ] No forbidden imports in utility/core files
- [ ] SDK errors fail silently, never crash host app
- [ ] OTel spans are always ended
- [ ] Tests included for new features/bug fixes

## 4. iOS SDK invariants — flag any violation as a blocker

These rules are specific to this codebase. Violations should fail review regardless of how clean the code otherwise looks.

### 4.1 Never crash the host app

The SDK runs inside a customer's process. Any of these in `Coralogix/Sources/`, `CoralogixInternal/Sources/`, `SessionReplay/Sources/` is a hard block:

- `fatalError(…)`, `precondition(…)`, `assert(…)`, `assertionFailure(…)`
- Force-unwrap (`!`) on a value that could be nil at runtime — including dictionary lookups, casts (`as!`), and `try!`
- Throwing an error that isn't caught at the SDK boundary

Use `guard … else { return }` (or `… else { Log.e("[Context] reason"); return }` when observable) instead.

### 4.2 Thread safety

Any new shared mutable state must be guarded. Accepted guards in this codebase:

- `NSLock` / `NSRecursiveLock` with paired `lock()` / `defer { unlock() }`
- A serial `DispatchQueue` used as a mutex (`queue.sync { … }`)
- A concurrent `DispatchQueue` with barrier writes for read-heavy / write-rare patterns

Flag an unguarded shared `var` as a blocker. Mention which existing pattern it should match.

### 4.3 Wire-key ownership

All span attribute keys, JSON cx_rum keys, keychain account names, and any string that appears in an outgoing payload must be defined as a `case` in `CoralogixInternal/Sources/Keys.swift`. Inline `"snake_case"` / `"camelCase"` string literals for these are a regression — typos won't fail at compile time and downstream queries break silently.

Grep the diff for any new attribute-shaped string literals (`*.setAttribute(key: "…")`, `result["…"] = …`, `keychain.*From*(service: …, key: "…")`). If they're not coming from `Keys.swift`, flag it.

### 4.4 `beforeSend` editable-subset discipline

The customer's `beforeSend` callback can mutate the cx_rum dict. Span identity, dedup, SDK-owned counters, and SDK observations must survive any edit. They belong in `CxSpan.readOnlyCxRumKeys`. Categories that must NEVER be customer-editable:

- Identity (`traceId`, `spanId`, `fingerPrint`, `prevSession`)
- Dedup / runtime constants (`isSnapshotEvent`, `snapshotContext`, `mobileSdk`, `timestamp`, `platform`)
- SDK-owned counters (e.g. per-session sequence counters)
- SDK observations (boolean flags recording what the SDK detected, set once at build time)

When a PR adds a new field at the cx_rum top level, the author must decide explicitly: customer-editable, or SDK-owned? Flag PRs that add a field without making this call.

The protection is two layers:
1. **Strip** the field from the editable subset that `beforeSend(cxRum)` receives (so customers don't see fields they can't change).
2. **Restore** the original value after the merge step (so a callback that injects the field into its return dict can't tamper with it).

### 4.5 Wire-shape parity (`text.cx_rum` ↔ `otelSpan.attributes`)

Any field emitted at `text.cx_rum.*` must also be mirrored into `instrumentation_data.otelSpan.attributes` under the corresponding `cx_rum.*` snake_case key. The mapping lives in `Coralogix/Sources/Model/InstrumentationData.swift` (`AttrKey` enum + the two `buildRumContextAttributes` variants — live and post-`beforeSend` dict).

Touching one side without the other is a blocker. A PR that adds a new top-level cx_rum field should grep for `AttrKey` and `buildRumContextAttributes` to confirm both variants are updated.

### 4.6 Cross-platform parity

Before changing the wire shape of any public-facing attribute (key name, casing, nesting, value type), check the sister SDKs:

- **Android SDK:** `/Users/tomer.haryoffi/Development/android-sdk` (locally)
- **Browser SDK:** canonical wire shape — escalate to Daniel if iOS and Android disagree
- **React Native plugin:** `/Users/tomer.haryoffi/Development/cx-react-native-plugin`
- **Flutter plugin:** `/Users/tomer.haryoffi/Development/cx-flutter-plugin`

`grep -rn "<key-name>"` in the sibling repos before approving a wire-shape change. Inconsistency across SDKs is a blocker unless explicitly justified.

### 4.7 Tests must make positive, falsifiable claims

`XCTAssertNil(payload["field_that_was_never_added"])` is not a test — it passes trivially and won't catch a regression. Flag tests that:

- Assert the absence of something that was never written
- Have all `XCTAssertEqual(x, x)` shape (tautological)
- Have no `XCTAssert*` at all (forgot to add the assertion)
- Compare against the result of the same function call (`XCTAssertEqual(f(), f())`)

A test must reflect a claim that fails if a real mistake is made.

### 4.8 Swizzle hygiene

If the diff touches a swizzled method:

- Swizzling must be installed once (not in a re-entrant init path)
- Originals must be captured and restored on `shutdown()`
- Swizzling tests must restore originals in `tearDown` — leaked swizzles cause cross-test interference
- Static properties on instrumentation classes (`currentInstance`, `currentNetworkOptions`) are intentionally `static` — don't "fix" them to instance properties

### 4.9 Demo-app parity

`Example/DemoAppSwift` (UIKit) and `Example/DemoAppSwiftUI` (SwiftUI) are kept symmetrical. When a PR adds a new screen, section, or interactive control to one demo app, it must mirror in the other, including the UI tests (`DemoAppUITests`, `DemoAppSwiftUIUITests`). Flag asymmetric changes.

### 4.10 iOS 13.0 minimum

The deployment target is iOS 13.0. Any API newer than iOS 13 must be wrapped in `#available(iOS …, *)`. Swift compiles the call (no warning), but the host app crashes on iOS 13 devices. Flag any unguarded use of an API added after iOS 13.

### 4.11 No back-compat hacks

If a public API or internal symbol is removed:

- Delete it entirely (don't leave a renamed `_var` or a `// removed` comment)
- Don't add deprecation shims unless the user explicitly asks
- The commit message and CHANGELOG explain the removal

## 5. Use the right skill

When the diff matches one of these patterns, the PR author should use the registered skill rather than reinventing the flow:

| If the PR is… | Expected skill |
|---|---|
| Bumping the SDK version (any `.podspec` or `Global.sdk` change) | `/bump-version` (runs the project's script to keep the four files in sync) |
| Fixing review comments from an earlier round | `/fix-issues` (handles findings one at a time, stopping for approval) |
| Implementing a new Jira ticket | `/implement` (fetches ticket, branches, plans, stops before commit) |
| Manually verifying a change end-to-end | `/verify` (runs the demo app, observes behaviour, not just tests) |
| Generating release notes for a tag range | `/release-notes-sdk` |

Flag PRs that hand-edit versions in the four podspec/source files individually — that's the exact thing `/bump-version` exists to prevent.
