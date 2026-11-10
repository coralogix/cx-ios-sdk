//
//  CrashContextEnvelope.swift
//  Coralogix
//

import Foundation
import CoralogixInternal
#if canImport(CoralogixBootstrap)
import CoralogixBootstrap
#endif

/// The crash context a PLCrashReporter report carries in its custom data, as `CRXCrashContext`
/// wrote it. Decoding is tolerant: anything that is not a version-1 envelope reads as no context,
/// never as an error that loses the crash.
struct CrashContextEnvelope: Equatable {
    static let supportedVersion = 1

    struct Session: Equatable {
        let id: String
        /// Epoch milliseconds. Absent when the session was seeded before the SDK initialized.
        let creationTimeMillis: Int64?
        let sampledIn: Bool?
    }

    struct Cxx: Equatable {
        let type: String
        let what: String?
    }

    let session: Session?
    let cxx: Cxx?

    init?(data: Data?) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json[Keys.crashContextVersion.rawValue] as? NSNumber)?.intValue == Self.supportedVersion else {
            return nil
        }
        session = (json[Keys.crashContextSession.rawValue] as? [String: Any]).flatMap(Self.session)
        cxx = (json[Keys.crashContextCxx.rawValue] as? [String: Any]).flatMap(Self.cxx)
    }

    private static func session(_ json: [String: Any]) -> Session? {
        guard let id = json[Keys.sessionId.rawValue] as? String, !id.isEmpty else { return nil }
        return Session(id: id,
                       creationTimeMillis: (json[Keys.crashContextSessionCreationTime.rawValue] as? NSNumber)?.int64Value,
                       sampledIn: (json[Keys.spanSessionSampledIn.rawValue] as? NSNumber)?.boolValue)
    }

    private static func cxx(_ json: [String: Any]) -> Cxx? {
        guard let type = json[Keys.type.rawValue] as? String, !type.isEmpty else { return nil }
        return Cxx(type: type, what: json[Keys.crashContextCxxWhat.rawValue] as? String)
    }
}

/// Writes the live session into the crash context, so a crash report names the session it
/// happened in. Called under `SessionManager`'s session lock on every rotation and sampling
/// decision: it only hands a small dictionary to `CRXCrashContext`.
enum CrashContextSession {
    static func write(_ stamp: SessionManager.CrashStamp) {
        CRXCrashContext.setSection(Keys.crashContextSession.rawValue, value: [
            Keys.sessionId.rawValue: stamp.sessionId,
            Keys.crashContextSessionCreationTime.rawValue: Int64(stamp.creationDate.milliseconds),
            Keys.spanSessionSampledIn.rawValue: stamp.sampledIn
        ])
    }
}
