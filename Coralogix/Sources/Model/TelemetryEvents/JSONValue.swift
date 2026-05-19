//
//  JSONValue.swift
//
//
//  Created by Coralogix DEV TEAM on 18/05/2026.
//

import Foundation

/// A `Codable`, heterogeneous JSON value. Used by `TelemetryEvent` structs that
/// carry free-form user-supplied sub-dicts (e.g. `UserActionEvent.attributes`).
/// `[String: Any]` is not `Codable`; this enum is the typed bridge.
///
/// Round-trip caveat: JSON itself does not distinguish `2` from `2.0`, so a
/// whole-number `Double` is not round-trip safe through Codable:
///   `.double(2.0)`  -> encoded as `2`   -> decoded as `.int(2)`
///   `.double(2.5)`  -> encoded as `2.5` -> decoded as `.double(2.5)`
///   `.int(2)`       -> encoded as `2`   -> decoded as `.int(2)`
/// `Int` is tried first on decode by design — most user-supplied numeric
/// values are integers (counts, IDs) and demoting them to `Double` would
/// change the `toAny()` runtime type for the common case. Callers that need
/// to preserve "this was a Double" semantics for whole values must do so
/// outside `JSONValue`.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)               { self = .bool(v); return }
        if let v = try? c.decode(Int.self)                { self = .int(v); return }
        if let v = try? c.decode(Double.self)             { self = .double(v); return }
        if let v = try? c.decode(String.self)             { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self)        { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Converts to a `JSONSerialization`-compatible value
    /// (`NSNull`, `Bool`, `Int`, `Double`, `String`, `[Any]`, `[String: Any]`).
    func toAny() -> Any {
        switch self {
        case .null:          return NSNull()
        case .bool(let v):   return v
        case .int(let v):    return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v):  return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }
}
