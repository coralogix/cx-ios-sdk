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

/// Sessions held until an error (`SessionMode.errorOnly`), as the browser SDK's
/// `handleSessionWithError` does it: every final event — after URL masking and every `beforeSend`,
/// native and hybrid — of such a session is held in `errorOnlyBuffer`, unless its category is in
/// `instrumentationsToSend`. The first event with error severity triggers the session: it is sent,
/// with everything after it, and what was held is drained in paced requests (`ErrorOnlyDrain`).
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
    func routeErrorOnly(_ events: [[String: Any]]) -> [[String: Any]] {
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
                errorOnlyBuffer.trigger(route.sessionId)
                triggered.append(route.sessionId)
                live.append(OtelSpan.markingSessionHasError(event))
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
        forwardErrorOnlyTraces(settled)
        errorOnlyDrain.start(triggered)
        return live
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
    /// provided `beforeSend` left it an error. Returns what to send, and the session to drain.
    func crashOfErrorOnlySession(_ encoded: [[String: Any]]) -> ([[String: Any]], String?) {
        guard let event = encoded.first, let route = ErrorOnlyRoute(event) else { return (encoded, nil) }
        guard route.isError || errorOnlyBuffer.isTriggered(route.sessionId) else {
            Log.d("[CoralogixExporter] crash of session \(route.sessionId) is no longer an error after beforeSend — not sent")
            return ([], nil)
        }
        errorOnlyBuffer.trigger(route.sessionId)
        return (encoded.map(OtelSpan.markingSessionHasError), route.sessionId)
    }

    /// Records the mode each event is handed to a hybrid `beforeSend` with.
    func rememberErrorOnlyModes(of events: [[String: Any]]) {
        let modes = events.compactMap { event -> (spanId: String, errorOnly: Bool)? in
            guard let cxRum = Self.cxRum(of: event), let spanId = cxRum[Keys.spanId.rawValue] as? String else { return nil }
            let session = cxRum[Keys.sessionContext.rawValue] as? [String: Any]
            return (spanId, session?[Keys.onlyWithErrorMode.rawValue] as? Bool ?? false)
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
    func restoringErrorOnlyMode(in event: [String: Any]) -> [String: Any] {
        let spanId = Self.cxRum(of: event)?[Keys.spanId.rawValue] as? String
        let remembered = spanId.flatMap(takeRememberedMode)
        let sessionManager = getSessionManager()
        return Self.updatingSessionContext(of: event) { session in
            let sessionId = session[Keys.sessionId.rawValue] as? String
            session[Keys.onlyWithErrorMode.rawValue] = remembered
                ?? sessionId.map(sessionManager.isErrorOnlySession) ?? false
            session[Keys.hasError.rawValue] = nil
        }
    }

    private func takeRememberedMode(_ spanId: String) -> Bool? {
        hybridModesLock.lock()
        defer { hybridModesLock.unlock() }
        guard let index = hybridModes.firstIndex(where: { $0.spanId == spanId }) else { return nil }
        return hybridModes.remove(at: index).errorOnly
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
    /// read yet, so nothing is deleted.
    func recoverErrorOnlyLeftovers(crashedSessionIds: Set<String>?) {
        _ = errorOnlyBuffer.adoptLeftovers { metadata in
            metadata.triggered || crashedSessionIds?.contains(metadata.sessionId) ?? true
        }
    }

    /// Resumes drains a launch, background or offline spell cut short.
    func resumeErrorOnlyDrains() {
        errorOnlyDrain.start(errorOnlyBuffer.triggeredSessions())
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

    /// Forwards the kept-back spans whose events were sent, and forgets the ones held or dropped.
    private func forwardErrorOnlyTraces(_ settled: [String: Bool]) {
        guard !settled.isEmpty else { return }
        heldTraceSpansLock.lock()
        let sent = heldTraceSpans.filter { settled[$0.spanId] == true }.map(\.span)
        heldTraceSpans.removeAll { settled[$0.spanId] != nil }
        heldTraceSpansLock.unlock()
        forwardTraces(sent)
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
