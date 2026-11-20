//
//  SessionWithErrorConfig.swift
//  Coralogix
//

import Foundation
import CoralogixInternal

/// Settings for sessions that are sent only if an error happens in them.
///
/// Such a session holds its events on the device. When an error is reported in it, everything it
/// held is sent and the rest of the session is reported as usual; a session that ends without an
/// error sends nothing.
public struct SessionWithErrorConfig {
    public static let defaultMaxRumEvents = 5_000
    public static let maxAllowedRumEvents = 20_000

    /// Holds every session until an error happens in it, whatever `sessionSampleRate` decided.
    public let enable: Bool

    /// How many events a session holds while it waits for an error. Past this, what it held is
    /// discarded and it starts holding again. 5000 by default, at most 20000.
    public let maxRumEvents: Int

    /// Event categories sent at once even before an error, instead of being held.
    public let instrumentationsToSend: Set<ExcludableInstrumentation>

    /// - Parameters:
    ///   - maxRumEvents: 0 or less uses 5000; more than 20000 uses 20000.
    public init(enable: Bool = false,
                maxRumEvents: Int = SessionWithErrorConfig.defaultMaxRumEvents,
                instrumentationsToSend: Set<ExcludableInstrumentation> = []) {
        self.enable = enable
        self.maxRumEvents = Self.resolveMaxRumEvents(maxRumEvents)
        self.instrumentationsToSend = instrumentationsToSend
    }

    static func resolveMaxRumEvents(_ requested: Int) -> Int {
        guard requested > 0 else { return defaultMaxRumEvents }
        guard requested <= maxAllowedRumEvents else {
            Log.w("[SessionWithErrorConfig] maxRumEvents \(requested) is above the maximum — using \(maxAllowedRumEvents)")
            return maxAllowedRumEvents
        }
        return requested
    }

    var initData: [String: Any] {
        [Keys.enable.rawValue: enable,
         Keys.maxRumEvents.rawValue: maxRumEvents,
         Keys.instrumentationsToSend.rawValue: instrumentationsToSend.map(\.rawValue).sorted()]
    }
}

/// How a session is reported, decided once per session from its sampling roll and the options.
enum SessionMode: Equatable {
    /// Every event is sent as it happens.
    case full
    /// Events are held until an error happens in the session (`SessionWithErrorConfig`).
    case errorOnly
    /// Only what `excludeFromSampling` lists is sent.
    case dropped

    /// Whether the session's events can reach the backend at all, so its instrumentation runs and
    /// its requests carry a sampled `traceparent`.
    var reports: Bool { self != .dropped }
}
