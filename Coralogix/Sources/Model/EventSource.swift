//
//  EventSource.swift
//
//  Created by Coralogix DEV TEAM.
//

import Foundation
import CoralogixInternal

/// The value written to `cx_rum.event_context.source`.
///
/// Only errors, logs and network requests carry a source; every other event leaves the key out,
/// matching the browser SDK. On an error it records how the error was caught. The raw values are
/// byte-identical to the Android SDK's.
enum EventSource: String {
    case captured
    case crash
    case anr
    case console
    case code
    case fetch

    /// The values a hybrid wrapper (Flutter, React Native) may send with an error. `anr` and
    /// `fetch` are produced natively only.
    private static let hybridValues: Set<EventSource> = [.captured, .crash, .console, .code]

    /// Resolves the source a hybrid wrapper sent with an error. A missing or unknown value falls
    /// back to `captured` — a wrapper that predates the field only reaches native through its
    /// customer-facing `reportError`.
    static func hybrid(_ raw: String?) -> EventSource {
        guard let raw else { return .captured }
        guard let source = EventSource(rawValue: raw), hybridValues.contains(source) else {
            Log.w("[EventSource] unsupported hybrid error source '\(raw)', reporting as captured")
            return .captured
        }
        return source
    }
}
