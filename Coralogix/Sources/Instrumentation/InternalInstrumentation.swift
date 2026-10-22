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
        self.emitInitSpan(from: .pending, onlyIfSampledIn: false)
    }

    /// Sends `init` again on the first rotation into a sampled-in session when only a sampled-out
    /// session has had one, so the sampled-in session reports its own whether or not the first one
    /// was exported. A rotation captured just before `shutdown()` cleared the callback can still
    /// fire, so this checks the SDK is live, like `topUpInstrumentations`.
    internal func emitInitSpanOnRotation(sampledIn: Bool) {
        guard sampledIn, CoralogixRum.isInitialized else { return }
        self.emitInitSpan(from: .sentSampledOut, onlyIfSampledIn: true)
    }

    /// The state follows the session the span was actually stamped with, never a flag read earlier
    /// or the rotation's own decision: another rotation can land in between, and recording the wrong
    /// one either loses the sampled-in `init` for good or sends it twice. A span that is not sent is
    /// never ended, so it never reaches the exporter.
    ///
    /// The span is built before `initSpanLock` is taken because building it reads session metadata,
    /// which can rotate the session and fire the rotation callback synchronously on this thread —
    /// re-entering here with the lock held would deadlock.
    private func emitInitSpan(from expected: InitSpanState, onlyIfSampledIn: Bool) {
        let span = makeSpan(event: .internalKey, source: .console, severity: .info)
        let stamp = (span as? ReadableSpan)?.toSpanData().attributes[Keys.spanSessionSampledIn.rawValue]
        let sampledIn = stamp.map { $0.description == String(true) } ?? true
        guard sampledIn || !onlyIfSampledIn else { return }

        self.initSpanLock.lock()
        let send = self.initSpanState == expected
        if send {
            self.initSpanState = sampledIn ? .sentSampledIn : .sentSampledOut
        }
        self.initSpanLock.unlock()

        guard send else { return }
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
