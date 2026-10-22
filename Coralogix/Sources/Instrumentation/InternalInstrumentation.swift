//
//  InternalInstrumentation.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 08/09/2025.
//

import Foundation
import CoralogixInternal

extension CoralogixRum {
    /// Startup's `init`, stamped with whichever session is live once the tracer exists. A rotation
    /// earlier in startup cannot send one — its span would reach no exporter — so the state stays
    /// `pending` until here and this call reports whatever that rotation left.
    internal func emitStartupInitSpan() {
        let sampledIn = self.sessionManager?.isSessionSampledIn ?? true
        guard self.advanceInitSpanState(from: [.pending],
                                        to: sampledIn ? .sentSampledIn : .sentSampledOut) else { return }
        self.createInitSpan()
    }

    /// Sends `init` again on the first rotation into a sampled-in session when only a sampled-out
    /// session has had one, so the sampled-in session reports its own whether or not the first one
    /// was exported.
    internal func emitInitSpanOnRotation(sampledIn: Bool) {
        guard sampledIn, self.advanceInitSpanState(from: [.sentSampledOut], to: .sentSampledIn) else { return }
        self.createInitSpan()
    }

    /// The span is created only after the lock is released: building it reads session metadata,
    /// which can rotate the session and fire the rotation callback synchronously on this thread —
    /// re-entering `emitInitSpanOnRotation` while `initSpanLock` was still held would deadlock.
    private func advanceInitSpanState(from allowed: Set<InitSpanState>, to next: InitSpanState) -> Bool {
        self.initSpanLock.lock()
        defer { self.initSpanLock.unlock() }
        guard allowed.contains(self.initSpanState) else { return false }
        self.initSpanState = next
        return true
    }

    internal func createInitSpan() {
        let span = makeSpan(event: .internalKey, source: .console, severity: .info)
        span.end()
    }

    /// Emits the session-replay init log (CX-44984). The snapshot rides on the span as a JSON
    /// string and is decoded back into `internal_context` in `CxRumBuilder.buildInternalContext`.
    internal func createSessionReplayInitSpan(snapshot: [String: Any]) {
        var span = makeSpan(event: .internalKey, source: .console, severity: .info)
        span.setAttribute(key: Keys.internalEventType.rawValue, value: Keys.sessionReplayInit.rawValue)
        span.setAttribute(key: Keys.internalEventData.rawValue,
                          value: Helper.convertDictionaryToJsonString(dict: snapshot))
        span.end()
    }
}
