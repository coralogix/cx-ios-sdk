//
//  RumBus.swift
//
//  The two-way channel the session-replay wrapper subscribes to. One serial queue carries every
//  delivery in both directions, in publish order; publishers never wait. Reached only through
//  `@_spi(RumBus) import Coralogix`.

import Foundation

/// A scalar value of a `ReplaySettings` entry (string | number | boolean | null).
@_spi(RumBus) public enum RumBusScalar: Sendable, Equatable { case string(String), number(Double), bool(Bool), null }

/// RUM to replay messages.
@_spi(RumBus) public enum RumToReplay: Sendable, Equatable {
    case currentState(sessionId: String, sessionStartTime: Int, kept: Bool, idle: Bool, currentScreen: String?, maskTag: String)
    case sessionChanged(sessionId: String, sessionStartTime: Int, kept: Bool, idle: Bool)
    case viewChanged(screen: String)
    case shuttingDown
    case flushing
}

/// Replay to RUM messages.
@_spi(RumBus) public enum ReplayToRum: Sendable, Equatable {
    case recordingStarted(sessionId: String)
    case recordingStopped(sessionId: String)
    case screenshotTaken(screenshotId: String, sessionId: String, timestamp: Int)
    case replaySettings(settings: [String: RumBusScalar])
}

/// Replay keeps this to stop listening to RUM (`cancel()`).
@_spi(RumBus) public final class RumBusSubscription: @unchecked Sendable {
    fileprivate let handler: @Sendable (RumToReplay) -> Void
    fileprivate var cancelled = false
    fileprivate var hasState = false // got a CurrentState: a later (re)initialize sends SessionChanged instead
    private weak var bus: RumBus?

    fileprivate init(_ handler: @escaping @Sendable (RumToReplay) -> Void, _ bus: RumBus) {
        self.handler = handler
        self.bus = bus
    }

    /// Nothing queued after this call is delivered.
    public func cancel() { bus?.cancel(self) }
}

/// The process-wide bus: it outlives RUM init, shutdown and re-init, so a subscriber hears RUM's state across them.
@_spi(RumBus) public final class RumBus: @unchecked Sendable {
    internal static let shared = RumBus()
    /// What replay is told to mark masked views with.
    internal static let maskTag = "cxMask"

    private let queue = DispatchQueue(label: "com.coralogix.rum.bus")
    private let lock = NSLock() // guards everything below; held only to enqueue, never across a handler
    private var subs: [RumBusSubscription] = []
    private var sticky: RumToReplay? // latest CurrentState, nil while RUM is not initialized
    private var rumHandler: (@Sendable (ReplayToRum) -> Void)?

    private init() {}

    /// A subscriber gets the sticky `CurrentState` first (once RUM is initialized), then every later message.
    internal func subscribe(_ handler: @escaping @Sendable (RumToReplay) -> Void) -> RumBusSubscription {
        let sub = RumBusSubscription(handler, self)
        lock.lock()
        defer { lock.unlock() }
        subs.append(sub)
        if let sticky {
            sub.hasState = true
            queue.async { [weak self] in self?.deliver(sticky, to: sub) }
        }
        return sub
    }

    fileprivate func cancel(_ sub: RumBusSubscription) {
        lock.lock()
        defer { lock.unlock() }
        sub.cancelled = true
        subs.removeAll { $0 === sub }
    }

    /// Replay talks to RUM; never waits. RUM's handler, if one is installed, runs later on the bus queue.
    internal func publish(_ message: ReplayToRum) {
        queue.async { [self] in
            lock.lock()
            let handler = rumHandler
            lock.unlock()
            handler?(message)
        }
    }

    /// RUM installs (or removes, with nil) its receiver for replay to RUM messages.
    internal func setRumHandler(_ handler: (@Sendable (ReplayToRum) -> Void)?) {
        lock.lock()
        rumHandler = handler
        lock.unlock()
    }

    /// RUM publishes to replay and the bus keeps the sticky state current. `.currentState` means "RUM initialized":
    /// subscribers that already had one get a SessionChanged instead. `.shuttingDown` clears the sticky state.
    internal func rumPublish(_ message: RumToReplay) {
        lock.lock()
        defer { lock.unlock() }
        var perSub: (RumBusSubscription) -> RumToReplay = { _ in message }
        switch (message, sticky) {
        case let (.currentState(id, start, kept, idle, _, _), _):
            let initial = message
            perSub = { $0.hasState ? .sessionChanged(sessionId: id, sessionStartTime: start, kept: kept, idle: idle) : initial }
            sticky = message
        case let (.sessionChanged(id, start, kept, idle), .currentState(_, _, _, _, screen, mask)?):
            sticky = .currentState(sessionId: id, sessionStartTime: start, kept: kept, idle: idle, currentScreen: screen, maskTag: mask)
        case let (.viewChanged(screen), .currentState(id, start, kept, idle, _, mask)?):
            sticky = .currentState(sessionId: id, sessionStartTime: start, kept: kept, idle: idle, currentScreen: screen, maskTag: mask)
        case (.shuttingDown, _):
            sticky = nil
        default:
            break
        }
        for sub in subs {
            let m = perSub(sub)
            if case .currentState = m { sub.hasState = true }
            queue.async { [weak self] in self?.deliver(m, to: sub) }
        }
    }

    /// Runs on the bus queue; the handler is called with no lock held.
    private func deliver(_ message: RumToReplay, to sub: RumBusSubscription) {
        lock.lock()
        let cancelled = sub.cancelled
        lock.unlock()
        if !cancelled { sub.handler(message) }
    }

    /// Test seam: returns once every delivery queued before the call has run.
    internal func drain() { queue.sync {} }
}

extension CoralogixRum {
    /// Replay listens to RUM; the subscriber hears RUM's state before and across RUM's init and shutdown.
    @_spi(RumBus) public static func subscribe(_ handler: @escaping @Sendable (RumToReplay) -> Void) -> RumBusSubscription {
        RumBus.shared.subscribe(handler)
    }

    /// Replay talks to RUM; enqueues and returns.
    @_spi(RumBus) public static func publish(_ message: ReplayToRum) {
        RumBus.shared.publish(message)
    }

    /// Test seam: returns once every delivery queued on the bus before the call has run.
    internal static func drainBus() { RumBus.shared.drain() }
}
