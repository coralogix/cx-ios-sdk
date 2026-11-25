//
//  CoralogixExporter+ErrorOnly.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// The drain is built in the exporter's `init`, before `self` can be captured.
final class WeakExporter {
    weak var exporter: CoralogixExporter?
}

/// Sessions held until an error (`SessionMode.errorOnly`): every final event — after URL masking and every `beforeSend`,
/// native and hybrid — of such a session is held in `errorOnlyBuffer`, unless its category is in
/// `instrumentationsToSend`. The first event with error severity triggers the session: it is held
/// last, and what was held is drained, error included, in paced requests (`ErrorOnlyDrain`);
/// everything after it is sent as it happens.
extension CoralogixExporter {

    /// Whether `span` belongs to a session held until an error, from its creation-time stamp.
    func isErrorOnly(_ span: SpanDataProtocol) -> Bool {
        attributeStringValue(forKey: Keys.spanSessionOnlyWithErrorMode.rawValue, span: span) == String(true)
    }

    /// Splits final events into those sent now, which it returns, and those held for an error.
    ///
    /// Keyed by each event's own session, so a late event of a session that has since ended can
    /// neither trigger the live one nor land in its buffer. Within `ErrorOnlyBuffer.endedSessionGrace`
    /// of its end it is still held for, and triggers, its own session; after that it is sent only
    /// if that session had its error, and dropped otherwise.
    ///
    /// Releases the kept-back `tracesExporter` spans of every event it is handed, and of `released`.
    func routeErrorOnly(_ events: [[String: Any]], releasing released: Set<String> = []) -> [[String: Any]] {
        let options = getOptions()
        guard options.holdsSessionsForErrors else { return events }
        let sendsBeforeError = Set(options.onlyWithErrorConfig.instrumentationsToSend.map(\.eventType.rawValue))

        var live: [[String: Any]] = []
        var settled: [String: Bool] = [:]
        var triggered: [String] = []
        for event in events {
            guard let route = ErrorOnlyRoute(event) else {
                live.append(event)
                continue
            }
            let sends: Bool
            if errorOnlyBuffer.isTriggered(route.sessionId) {
                live.append(OtelSpan.markingSessionHasError(event))
                sends = true
            } else if !getSessionManager().isLiveSession(route.sessionId) && !errorOnlyBuffer.isInGrace(route.sessionId) {
                Log.d("[CoralogixExporter] event of ended session \(route.sessionId) held for an error — dropped")
                sends = false
            } else if route.isError {
                let error = OtelSpan.markingSessionHasError(event)
                if !holdTrigger(error, of: route) { live.append(error) }
                triggered.append(route.sessionId)
                sends = true
            } else if sendsBeforeError.contains(route.eventType ?? "") {
                live.append(event)
                sends = true
            } else if hold(event, sessionId: route.sessionId) {
                sends = false
            } else {
                // Its session had its error on another thread since the check above.
                live.append(OtelSpan.markingSessionHasError(event))
                sends = true
            }
            if let spanId = route.spanId { settled[spanId] = sends }
        }
        forwardErrorOnlyTraces(settled, releasing: released.union(events.compactMap(Self.spanId)))
        startErrorOnlyDrains(triggered)
        return live
    }

    /// Triggers the event's session, keeping the error with what the session held, so it is sent
    /// in the same requests and shares their retries and their survival of a restart: the backend
    /// gets the session in the order it happened. Returns false when it could not be kept: the error is then sent live.
    ///
    /// An error whose delivery is awaited (an ANR or a React Native fatal, whose stored copy is
    /// sent by the next launch unless it is delivered) is kept the same way: an ANR's copy exists
    /// only while its hang lasts, so live would leave a recovered hang nothing to retry it. Its
    /// waiter is answered as delivered once it is kept, since the buffer now carries it: answered
    /// only when its request lands, a launch ending first would send it twice.
    private func holdTrigger(_ error: [String: Any], of route: ErrorOnlyRoute) -> Bool {
        guard JSONSerialization.isValidJSONObject(error),
              let data = try? JSONSerialization.data(withJSONObject: error) else {
            errorOnlyBuffer.trigger(route.sessionId)
            return false
        }
        let isAwaited = route.spanId.map(isAwaitingLiveDelivery) ?? false
        guard errorOnlyBuffer.triggerHolding(data, sessionId: route.sessionId, isAwaited: isAwaited) else { return false }
        if let spanId = route.spanId { handOverLiveDelivery(of: spanId) }
        return true
    }

    /// Returns false when the session turned out to have had its error: the event is not held.
    private func hold(_ event: [String: Any], sessionId: String) -> Bool {
        guard JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event) else {
            Log.e("[CoralogixExporter] an event held for an error could not be encoded — dropped")
            return true
        }
        return errorOnlyBuffer.hold(data, sessionId: sessionId)
    }

    /// A stored crash, encoded: if its session is held until an error, the crash is its trigger,
    /// provided `beforeSend` left it an error. Returns what to send. The session drains once the
    /// crash is finished with (`recordCrashOutcome`).
    func crashOfErrorOnlySession(_ encoded: [[String: Any]]) -> [[String: Any]] {
        guard let event = encoded.first, let route = ErrorOnlyRoute(event) else { return encoded }
        guard route.isError || errorOnlyBuffer.isTriggered(route.sessionId) else {
            Log.d("[CoralogixExporter] crash of session \(route.sessionId) is no longer an error after beforeSend — not sent")
            return []
        }
        errorOnlyBuffer.trigger(route.sessionId)
        return encoded.map(OtelSpan.markingSessionHasError)
    }

    /// The mode and session an event is handed to a hybrid `beforeSend` with.
    struct HandedMode {
        let errorOnly: Bool
        let sessionId: String?
    }

    /// Records the mode each event is handed to a hybrid `beforeSend` with.
    func rememberErrorOnlyModes(of events: [[String: Any]]) {
        let modes = events.compactMap { event -> (spanId: String, mode: HandedMode)? in
            guard let cxRum = Self.cxRum(of: event), let spanId = cxRum[Keys.spanId.rawValue] as? String else { return nil }
            let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any]
            return (spanId, HandedMode(errorOnly: session?[Keys.onlyWithErrorMode.rawValue] as? Bool ?? false,
                                       sessionId: session?[Keys.sessionId.rawValue] as? String))
        }
        hybridModesLock.lock()
        defer { hybridModesLock.unlock() }
        hybridModes.append(contentsOf: modes)
        if hybridModes.count > Self.maxHybridModes {
            hybridModes.removeFirst(hybridModes.count - Self.maxHybridModes)
        }
    }

    /// The hybrid return path uploads what JS/Dart hands back verbatim, so both read-only fields
    /// are put back on every event, feature on or off: the mode the event was encoded with, and
    /// no `hasError` (stamped only after this, by routing). An event the SDK did not hand out
    /// falls back to what it knows of the session.
    ///
    /// Returns nil, dropping the event, when sessions can be held and the event could belong to
    /// one that routing cannot reach: its mode is unknown, or it is held until an error but its
    /// session context or id was removed. Sent as it is, it would leak a held session live. So is
    /// a held event handed back under another session id: routed under it, its error would send
    /// that session's held events, or it would be held for a session it never belonged to.
    func restoringErrorOnlyMode(in event: [String: Any]) -> [String: Any]? {
        let cxRum = Self.cxRum(of: event)
        let spanId = cxRum?[Keys.spanId.rawValue] as? String
        let remembered = spanId.flatMap(takeRememberedMode)
        let sessionId = (cxRum?[Keys.sessionContext.rawValue] as? [String: Any])?[Keys.sessionId.rawValue] as? String
        let errorOnly = remembered?.errorOnly ?? sessionId.flatMap(getSessionManager().errorOnlyMode)
        if getOptions().holdsSessionsForErrors {
            let keepsItsSession = remembered.map { !$0.errorOnly || $0.sessionId == sessionId } ?? true
            guard let errorOnly, !errorOnly || sessionId != nil, keepsItsSession else {
                Log.d("[CoralogixExporter] an event handed back by beforeSend cannot be placed in its session — dropped")
                return nil
            }
        }
        return Self.updatingSessionContext(of: event) { session in
            session[Keys.onlyWithErrorMode.rawValue] = errorOnly ?? false
            session[Keys.hasError.rawValue] = nil
        }
    }

    private func takeRememberedMode(_ spanId: String) -> HandedMode? {
        hybridModesLock.lock()
        defer { hybridModesLock.unlock() }
        guard let index = hybridModes.firstIndex(where: { $0.spanId == spanId }) else { return nil }
        return hybridModes.remove(at: index).mode
    }

    /// `event` with its `text.cx_rum.session_context` changed by `change`; unchanged when it has none.
    static func updatingSessionContext(of event: [String: Any],
                                       _ change: (inout [String: Any]) -> Void) -> [String: Any] {
        guard var text = event[Keys.text.rawValue] as? [String: Any],
              var cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              var session = cxRum[Keys.sessionContext.rawValue] as? [String: Any] else {
            return event
        }
        change(&session)
        cxRum[Keys.sessionContext.rawValue] = session
        text[Keys.cxRum.rawValue] = cxRum
        var result = event
        result[Keys.text.rawValue] = text
        return result
    }

    // MARK: - Lifecycle

    /// Takes over what earlier launches left: a buffer that had its error is kept for
    /// `resumeErrorOnlyDrains`; one whose session has a stored crash waits for that crash, its
    /// trigger; the rest is deleted. `crashedSessionIds` nil means the crash records could not be
    /// read yet: no session is deleted for having no crash to come, but the count and byte bounds
    /// on what earlier launches keep still apply.
    func recoverErrorOnlyLeftovers(crashedSessionIds: Set<String>?) {
        _ = errorOnlyBuffer.adoptLeftovers(crashedSessionIds: crashedSessionIds)
    }

    /// Resumes drains a launch, background or offline spell cut short. Does nothing until the
    /// launch's stored crashes have had their pass (`releaseErrorOnlyDrains`).
    func resumeErrorOnlyDrains() {
        startErrorOnlyDrains(errorOnlyBuffer.triggeredSessions())
    }

    /// Starts the drains of `sessionIds` that had their error and wait on no crash. A session
    /// freed from a crash that `beforeSend` dropped or demoted never had its error: what it holds
    /// stays held, under the usual rules.
    func startErrorOnlyDrains(_ sessionIds: [String]) {
        errorOnlyDrain.start(drainableSessions(sessionIds).filter(errorOnlyBuffer.isTriggered))
    }

    /// Called once the stored-crash pass of this launch is over.
    func releaseErrorOnlyDrains() {
        errorOnlyDrainsReleased = true
        resumeErrorOnlyDrains()
    }

    /// What this instance held without an error goes; a buffer that had one, or one an earlier
    /// launch left for its crash, stays for a later launch.
    func shutdownErrorOnly() {
        errorOnlyDrain.stop()
        errorOnlyBuffer.discardAllUntriggered()
    }

    /// One request of held events, through the stored-crash request settings: a slow network
    /// should not lose a request that will not come again this launch.
    func uploadHeld(_ events: [[String: Any]]) -> SpanUploadResult {
        isRetired ? .notAttempted : spanUploader.upload(events, endPoint: endPoint, kind: .storedCrash)
    }

    // MARK: - tracesExporter

    /// The spans `tracesExporter` may see now. A span of an error-only session that has not had its
    /// error is kept back until `routeErrorOnly` knows whether it is sent: a held event never
    /// reaches it. Stored crashes are forwarded as before.
    func holdingErrorOnlyTraces(of spans: [SpanData]) -> [SpanData] {
        var forwarded: [SpanData] = []
        var held: [(spanId: String, span: SpanData)] = []
        for span in spans {
            let sessionId = attributeStringValue(forKey: Keys.sessionId.rawValue, span: span) ?? ""
            let waits = isErrorOnly(span)
                && span.getAttribute(forKey: Keys.crashEventId.rawValue) == nil
                && !errorOnlyBuffer.isTriggered(sessionId)
            if waits {
                held.append((Helper.getTraceAndSpanId(otel: span).spanId, span))
            } else {
                forwarded.append(span)
            }
        }
        guard !held.isEmpty else { return forwarded }
        heldTraceSpansLock.lock()
        heldTraceSpans.append(contentsOf: held)
        if heldTraceSpans.count > Self.maxHeldTraceSpans {
            heldTraceSpans.removeFirst(heldTraceSpans.count - Self.maxHeldTraceSpans)
        }
        heldTraceSpansLock.unlock()
        return forwarded
    }

    /// Forwards the kept-back spans whose events were sent, and forgets the ones held or dropped,
    /// and `released`: spans whose events left the batch without being routed.
    private func forwardErrorOnlyTraces(_ settled: [String: Bool], releasing released: Set<String>) {
        heldTraceSpansLock.lock()
        guard !heldTraceSpans.isEmpty else { heldTraceSpansLock.unlock(); return }
        let sent = heldTraceSpans.filter { settled[$0.spanId] == true }.map(\.span)
        heldTraceSpans.removeAll { settled[$0.spanId] != nil || released.contains($0.spanId) }
        heldTraceSpansLock.unlock()
        forwardTraces(sent)
    }

    /// Forgets the kept-back spans of `spans` that encoding dropped: the native `beforeSend`
    /// removed them, or they could not be encoded. They never reach routing.
    func releaseErrorOnlyTraces(droppedFrom spans: [SpanData], encoded: [[String: Any]]) {
        guard spans.count > encoded.count, hasHeldTraceSpans else { return }
        let encodedIds = Set(encoded.compactMap(Self.spanId))
        let dropped = Set(spans.map { Helper.getTraceAndSpanId(otel: $0).spanId }).subtracting(encodedIds)
        forwardErrorOnlyTraces([:], releasing: dropped)
    }

    private var hasHeldTraceSpans: Bool {
        heldTraceSpansLock.lock()
        defer { heldTraceSpansLock.unlock() }
        return !heldTraceSpans.isEmpty
    }

    /// Records the span ids of a batch handed to a hybrid `beforeSend`, while spans are kept back.
    func recordHandedTraceBatch(_ events: [[String: Any]]) {
        guard getOptions().tracesExporter != nil, getOptions().holdsSessionsForErrors else { return }
        let ids = Set(events.compactMap(Self.spanId))
        guard !ids.isEmpty else { return }
        heldTraceSpansLock.lock()
        defer { heldTraceSpansLock.unlock() }
        handedTraceBatches.append(ids)
        if handedTraceBatches.count > Self.maxHandedTraceBatches {
            handedTraceBatches.removeFirst(handedTraceBatches.count - Self.maxHandedTraceBatches)
        }
    }

    /// Takes the handed batches any of `returnedIds` came back from: all their span ids.
    func takeHandedTraceBatches(_ returnedIds: Set<String>) -> Set<String> {
        heldTraceSpansLock.lock()
        defer { heldTraceSpansLock.unlock() }
        let returned = handedTraceBatches.filter { !$0.isDisjoint(with: returnedIds) }
        handedTraceBatches.removeAll { !$0.isDisjoint(with: returnedIds) }
        return returned.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

    /// The `span_id` of an encoded event.
    static func spanId(of event: [String: Any]) -> String? {
        cxRum(of: event)?[Keys.spanId.rawValue] as? String
    }
}

/// What routing reads from an encoded event of a session held until an error.
private struct ErrorOnlyRoute {
    let sessionId: String
    let spanId: String?
    let eventType: String?
    let isError: Bool

    /// nil for an event of a session that is not held until an error.
    init?(_ event: [String: Any]) {
        guard let cxRum = CoralogixExporter.cxRum(of: event),
              let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any],
              session[Keys.onlyWithErrorMode.rawValue] as? Bool == true,
              let sessionId = session[Keys.sessionId.rawValue] as? String else {
            return nil
        }
        let eventContext = cxRum[Keys.eventContext.rawValue] as? [String: Any]
        self.sessionId = sessionId
        self.spanId = cxRum[Keys.spanId.rawValue] as? String
        self.eventType = eventContext?[Keys.type.rawValue] as? String
        // `event_context.severity`, not the top-level copy; a hybrid callback can return any JSON.
        self.isError = Self.severity(eventContext?[Keys.severity.rawValue]) == CoralogixLogSeverity.error.rawValue
    }

    private static func severity(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }
}
