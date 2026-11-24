//
//  CoralogixRum+Bus.swift
//
//  What RUM publishes to the bus. Only the most recently initialized instance publishes: an older
//  instance that was never shut down, and any instance after its shutdown, stays silent. Checking
//  liveness and publishing are one hold of `liveInstanceLock`, so nothing follows ShuttingDown.

import Foundation

extension CoralogixRum {
    private var isLive: Bool {
        Self.liveInstanceLock.lock()
        defer { Self.liveInstanceLock.unlock() }
        return CoralogixRum.isInitialized && Self.liveInstance === self
    }

    /// Starts reporting `sessionManager`'s session. The first report is the sticky CurrentState, and this
    /// instance becomes the live one in the same step, so no message can reach a subscriber before it.
    internal func attachBus(to sessionManager: SessionManager) {
        sessionManager.forgetRecordedSessions()
        busScreenLock.lock()
        busScreenRaw = nil
        busScreenLock.unlock()
        sessionManager.attachBus(initial: { [weak self] session in
            guard let self else { return }
            Self.liveInstanceLock.lock()
            defer { Self.liveInstanceLock.unlock() }
            Self.liveInstance = self
            RumBus.shared.rumPublish(.currentState(sessionId: session.sessionId,
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
        RumBus.shared.setRumHandler { [weak self] message in self?.handleReplayMessage(message) }
    }

    /// Announces ShuttingDown and silences the bus. RUM is down for the whole process once any instance shuts
    /// down (`isInitialized` is process-wide), so the live instance, whichever it is, is told to stop too.
    internal func shutDownBus() {
        RumBus.shared.setRumHandler(nil)
        sessionManager?.detachBus()
        Self.liveInstanceLock.lock()
        let live = Self.liveInstance
        Self.liveInstanceLock.unlock()
        if live !== self { live?.sessionManager?.detachBus() }
        Self.liveInstanceLock.lock()
        defer { Self.liveInstanceLock.unlock() }
        guard Self.liveInstance != nil else { return }
        RumBus.shared.rumPublish(.shuttingDown)
        Self.liveInstance = nil
    }

    /// Enqueues `message` for subscribers when this is the live instance. Never waits on a subscriber.
    internal func publishToBus(_ message: RumToReplay) {
        Self.liveInstanceLock.lock()
        defer { Self.liveInstanceLock.unlock() }
        guard CoralogixRum.isInitialized, Self.liveInstance === self else { return }
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

    /// Runs on the bus queue with no lock held. Only the live instance acts; the checks here cover a message
    /// that was queued while this instance was live and is handled after it stopped being so.
    internal func handleReplayMessage(_ message: ReplayToRum) {
        guard isLive else { return }
        switch message {
        case .recordingStarted(let sessionId):
            guard isCurrentSession(sessionId) else { return }
            sessionManager?.markRecorded(sessionId)
        case .recordingStopped:
            break // the flag stays: the session did record
        case .screenshotTaken(let screenshotId, let sessionId, let timestamp):
            guard isCurrentSession(sessionId) else { return }
            let span = makeSpan(event: .screenshot, source: nil, severity: .info,
                                startTime: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000))
            span.setAttribute(key: Keys.screenshotId.rawValue, value: screenshotId)
            span.end()
        case .replaySettings(let settings):
            let span = makeSpan(event: .internalKey, source: nil, severity: .info)
            span.setAttribute(key: Keys.internalEventName.rawValue, value: "replay_settings")
            span.setAttribute(key: Keys.internalEventData.rawValue, value: Self.json(settings))
            span.end()
        }
    }

    /// RUM's own session state, which also rotates a session past its max age.
    private func isCurrentSession(_ sessionId: String) -> Bool {
        sessionManager?.getSessionMetadata()?.sessionId == sessionId
    }

    private static func json(_ settings: [String: RumBusScalar]) -> String {
        let object = settings.mapValues { value -> Any in
            switch value {
            case .string(let string): return string
            case .number(let number): return number.isFinite ? number : NSNull() // JSON has no NaN or infinity
            case .bool(let bool): return bool
            case .null: return NSNull()
            }
        }
        let data = try? JSONSerialization.data(withJSONObject: object)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func epochMillis(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1000).rounded())
    }
}
