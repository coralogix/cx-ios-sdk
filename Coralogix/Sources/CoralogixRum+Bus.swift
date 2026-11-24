//
//  CoralogixRum+Bus.swift
//
//  What RUM publishes to the bus. Only the most recently initialized instance publishes: an older
//  instance that was never shut down, and any instance after its shutdown, stays silent.

import Foundation

extension CoralogixRum {
    private var isLive: Bool {
        Self.liveInstanceLock.lock()
        defer { Self.liveInstanceLock.unlock() }
        return Self.liveInstance === self
    }

    /// Makes this the live instance and starts reporting `sessionManager`'s session. The first report is the
    /// sticky CurrentState, so a subscriber that arrives later still hears the session as it stands.
    internal func attachBus(to sessionManager: SessionManager) {
        Self.liveInstanceLock.lock()
        Self.liveInstance = self
        Self.liveInstanceLock.unlock()
        busScreenLock.lock()
        busScreenRaw = nil
        busScreenLock.unlock()
        sessionManager.attachBus(initial: { [weak self] session in
            self?.publishToBus(.currentState(sessionId: session.sessionId,
                                             sessionStartTime: Self.epochMillis(session.creationDate),
                                             kept: session.kept,
                                             idle: session.idle,
                                             currentScreen: nil,
                                             maskTag: RumBus.maskTag))
        }, changed: { [weak self] session in
            self?.publishToBus(.sessionChanged(sessionId: session.sessionId,
                                               sessionStartTime: Self.epochMillis(session.creationDate),
                                               kept: session.kept,
                                               idle: session.idle))
        })
    }

    internal func detachBus() {
        sessionManager?.detachBus()
        Self.liveInstanceLock.lock()
        if Self.liveInstance === self { Self.liveInstance = nil }
        Self.liveInstanceLock.unlock()
    }

    /// Enqueues `message` for subscribers when this is the live instance. Never waits on a subscriber.
    internal func publishToBus(_ message: RumToReplay) {
        guard isLive else { return }
        RumBus.shared.rumPublish(message)
    }

    /// Announces a view change: the masked name goes out, the raw name decides whether the view changed.
    internal func publishViewToBus(raw: String, masked: String) {
        guard !raw.isEmpty, isLive else { return }
        busScreenLock.lock()
        defer { busScreenLock.unlock() }
        guard raw != busScreenRaw else { return }
        busScreenRaw = raw
        publishToBus(.viewChanged(screen: masked))
    }

    private static func epochMillis(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }
}
