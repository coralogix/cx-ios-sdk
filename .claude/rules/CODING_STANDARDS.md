# iOS SDK Coding Standards

Read and apply these standards before writing any code in this repository.

---

## Follow existing patterns before introducing new ones

Before creating a new file, class, or abstraction, search for how the same problem is already solved in the codebase. If a pattern exists, follow it. Deviation requires a concrete justification.

**Wrong:** Inventing a new singleton accessor when the existing pattern is a static on `CoralogixRum`:

```swift
// NetworkInstrumentation.swift  ← NEW file
public class NetworkConfigStore {
    public static let shared = NetworkConfigStore()
    var options: CoralogixExporterOptions?
}
```

**Right:** Match the established pattern — instrumentation classes hold their config as a `static` on the type, set at `initialize*Instrumentation()` time:

```swift
// NetworkInstrumentation.swift  ← extension on CoralogixRum, like all the others
extension CoralogixRum {
    static var currentNetworkOptions: NetworkInstrumentationOptions?

    func initializeNetworkInstrumentation(options: NetworkInstrumentationOptions) {
        NetworkInstrumentation.currentNetworkOptions = options
        // …
    }
}
```

---

## Don't work around a protocol — extend it

If a protocol cannot carry the data you need, update the protocol. Do not add a side-channel method on one conformer to bypass the contract.

**Wrong:** Adding a method only the production impl knows about, while the protocol stays unchanged and other conformers silently fall back to no-ops:

```swift
protocol KeyChainProtocol: AnyObject {
    func readStringFromKeychain(service: String, key: String) -> String?
    func writeStringToKeychain(service: String, key: String, value: String)
}

// KeychainManager.swift  ← production conformer
class KeychainManager: KeyChainProtocol {
    // …read, write…
    // Side-channel — not on the protocol
    func deleteFromKeychain(service: String, key: String) { … }
}

// Production code reaches into the concrete type — defeats the protocol
(keyChain as? KeychainManager)?.deleteFromKeychain(service: …, key: …)
```

**Right:** Add the method to the protocol, implement it in every conformer (including mocks):

```swift
protocol KeyChainProtocol: AnyObject {
    func readStringFromKeychain(service: String, key: String) -> String?
    func writeStringToKeychain(service: String, key: String, value: String)
    func deleteFromKeychain(service: String, key: String)
}
```

---

## Tests must make positive, falsifiable claims

A test that asserts the absence of something that was never written is not a real test. It passes trivially and will never catch a regression. Every assertion must reflect a claim that fails if a real mistake is made.

**Wrong:** Asserting a field is absent — passes regardless of what the function does, and would block a correct future change:

```swift
func test_payload_doesNotContainSecretKey() {
    let payload = builder.build()
    XCTAssertNil(payload["secret_key"])  // trivially true, no value
}
```

**Right:** Assert the actual structure — fails if the field is missing, misnamed, or encoded incorrectly:

```swift
func test_payload_includesSessionContextAtTopLevel() {
    let payload = builder.build()
    let session = try XCTUnwrap(payload[Keys.sessionContext.rawValue] as? [String: Any])
    XCTAssertEqual(session[Keys.sessionId.rawValue] as? String, "session_001")
}
```

Before writing a negative assertion, ask: *what real mistake would cause this to fail?* If the answer is "a developer would have to deliberately add this", the test adds no value.

---

## Verify object lifecycle before accessing shared state across queue boundaries

When a closure or `async`-dispatched block reads shared mutable state, verify the state is guaranteed to be non-nil by the time the block runs. `?.` with `?? return` is a silent bail-out — it drops work (a span, an event, a log) with no error surface.

**Wrong:** `currentInstance` is assigned *after* swizzling runs; the swizzled closure may fire before it lands, silently dropping the event:

```swift
class NetworkInstrumentation {
    static var currentInstance: CoralogixRum?

    static func swizzleURLSession() {
        URLSessionInstrumentation.swizzle { request, response in
            // If swizzling fires before initializeNetworkInstrumentation finishes,
            // currentInstance is nil → the span is silently dropped.
            currentInstance?.processNetworkResponse(request, response)
        }
    }
}

// Caller:
NetworkInstrumentation.swizzleURLSession()           // closure registered
NetworkInstrumentation.currentInstance = self         // ← may run after a tap
```

**Right:** Assign the shared state *before* installing the closure, so the closure can never see a nil receiver. If the closure must outlive `self`, capture data into the closure explicitly rather than reading shared state lazily.

---

## Prefer flat models when subtypes carry identical data

A protocol/enum/sealed hierarchy is justified when subtypes carry structurally different data, or when call sites switch on the subtype to change behaviour. If two cases have the same fields and differ only by a string discriminator, collapse them into a single struct with the discriminator as a field.

**Wrong:** Two structurally identical contexts with a `Codable` polymorphic serialiser:

```swift
protocol InternalContext: Codable {
    var event: String { get }
}

struct InitInternalContext: InternalContext {
    let event: String = "init"
    let data: [String: Any]
}

struct SessionReplayInitInternalContext: InternalContext {  // same shape, different default string
    let event: String = "session_replay_init"
    let data: [String: Any]
}
// Plus: polymorphic decoder, registration in two places…
```

**Right:** A flat struct — the `event` string already carries the type information:

```swift
struct InternalContext: Codable {
    let event: String
    let data: [String: Any]
}
```

---

## Never crash the host app

The SDK runs inside a customer's process. A crash in our code crashes their app.

**Forbidden in SDK code (`Coralogix/Sources/`, `CoralogixInternal/Sources/`, `SessionReplay/Sources/`):**

- `fatalError(…)`
- `precondition(…)`
- `assert(…)` and `assertionFailure(…)`
- Force-unwrap (`!`) on any value that could be nil at runtime — including dictionary lookups, casts, and JSON-decoded fields
- Force-cast (`as!`)
- Force-try (`try!`)

**Use instead:**

- `guard … else { return }` for early exit
- `guard … else { Log.e("[Context] reason"); return }` when the bail-out is observable
- `if let` / `guard let` for optional unwrapping
- `as?` for casts, with a `guard let` to handle failure

**Wrong:**

```swift
func processSpan(_ span: SpanData) {
    let attrs = span.attributes!  // force-unwrap — crashes if attrs is nil
    let type = attrs["type"] as! String  // force-cast — crashes if wrong type
    fatalError("unknown event type") // crash on unexpected input
}
```

**Right:**

```swift
func processSpan(_ span: SpanData) {
    guard let attrs = span.attributes, let type = attrs["type"] as? String else {
        Log.e("[Exporter] span missing required attributes — dropping")
        return
    }
    // …
}
```

---

## Guard newer APIs with `#available`

The deployment target is iOS 13.0. Any API newer than iOS 13 must be wrapped in `#available` — Swift will let you call it (the SDK compiles), but the host app crashes on iOS 13 devices at the call site.

**Wrong:**

```swift
let formatter = ISO8601DateFormatter()
formatter.formatOptions = .withFractionalSeconds  // iOS 11+ — OK for our target
let async = AsyncStream<Span> { … }  // iOS 13+ but the host build target may be lower
```

**Right:** Check with `#available` whenever you reach for an API added after iOS 13.0:

```swift
if #available(iOS 14.0, *) {
    UNUserNotificationCenter.current().requestAuthorization(…)
} else {
    // pre-iOS-14 fallback or skip
}
```

---

## Protect shared mutable state

If a property is `var`, accessible from multiple threads, and not declared inside an actor, it MUST be guarded. The standard guards in this codebase:

- `NSLock` (with `lock.lock(); defer { lock.unlock() }` or `NSRecursiveLock` if re-entry is needed)
- A serial `DispatchQueue` used as a mutex (`queue.sync { … }`)
- A concurrent `DispatchQueue` with barrier writes (`queue.async(flags: .barrier) { … }`) for read-heavy / write-rare patterns

**Forbidden:** An unguarded shared `var` that any thread can touch.

**Wrong:**

```swift
class SessionManager {
    var lastSnapshotEventTime: Date?  // touched from span-emit threads AND a periodic timer
}
```

**Right:** Match the existing pattern in the surrounding type (e.g., `ViewManager` uses a concurrent queue with barrier writes):

```swift
class SessionManager {
    private let sessionLock = NSRecursiveLock()
    private var _lastSnapshotEventTime: Date?

    var lastSnapshotEventTime: Date? {
        get { sessionLock.lock(); defer { sessionLock.unlock() }; return _lastSnapshotEventTime }
        set { sessionLock.lock(); defer { sessionLock.unlock() }; _lastSnapshotEventTime = newValue }
    }
}
```

---

## Swizzle hygiene

Method swizzling is global process state. The standard rules:

- Capture the original implementation when swizzling, and restore it on `shutdown()` and in test `tearDown`.
- Swizzling tests that don't restore originals leak state into subsequent tests in the same target — symptoms include cross-test interference and flaky CI.
- Static properties on instrumentation classes (`currentInstance`, `currentNetworkOptions`) are intentionally `static` because swizzling is global. Don't "fix" them to instance properties.

---

## All wire-key strings live in `CoralogixInternal/Sources/Keys.swift`

Span-attribute keys, JSON keys in the cx_rum payload, and keychain account names all live in the `Keys` enum. Inline `"snake_case"` or `"camelCase"` string literals for these elsewhere are a regression — typos won't fail at compile time, and downstream queries break silently.

**Wrong:**

```swift
span.setAttribute(key: "cx_rum.event_context.type", value: type)
result["session_id"] = id
```

**Right:**

```swift
span.setAttribute(key: Keys.eventContextType.rawValue, value: type)
result[Keys.sessionId.rawValue] = id
```

If the key doesn't exist in `Keys.swift`, add it there first.

---

## Comment *why*, not *what*

Default to writing no comments. Identifiers already say what the code does — comments should record information the code can't.

**Worth commenting:**

- Subtle invariants ("this static is intentionally not synchronised because writers are serialised by …")
- Workarounds for specific bugs ("this delay is here because URLSession on iOS 17.0 has a race that drops the first response")
- Decisions that diverge from the obvious approach and why

**Not worth commenting:**

- What the code obviously does (`// increment counter`)
- The fix you just shipped (belongs in the PR description)
- Who used to call this function
- **Ticket numbers** (`CX-XXXXX`, `BUGV2-XXXX`, etc.) in code comments *or* `CHANGELOG.md` entries — git blame, the commit, and the PR already carry them. Comment the *why* in prose so it stands on its own without the reference.

If removing the comment wouldn't confuse a future reader, don't write it.
