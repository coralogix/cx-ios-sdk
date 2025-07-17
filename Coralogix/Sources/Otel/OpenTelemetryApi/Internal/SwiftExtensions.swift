/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public extension TimeInterval {
    /// `TimeInterval` represented in milliseconds (capped to `UInt64.max`).
    var toMilliseconds: UInt64 {
        let milliseconds = self * 1_000
        return UInt64(withReportingOverflow: milliseconds) ?? .max
    }

    var toMicroseconds: UInt64 {
        let microseconds = self * 1_000_000
        return UInt64(withReportingOverflow: microseconds) ?? .max
    }

    /// `TimeInterval` represented in nanoseconds (capped to `UInt64.max`).
    var toNanoseconds: UInt64 {
        let nanoseconds = self * 1_000_000_000
        return UInt64(withReportingOverflow: nanoseconds) ?? .max
    }

    static func fromMilliseconds(_ millis: Int64) -> TimeInterval {
        return Double(millis) / 1_000
    }

    static func fromMicroseconds(_ micros: Int64) -> TimeInterval {
        return Double(micros) / 1_000_000
    }

    static func fromNanoseconds(_ nanos: Int64) -> TimeInterval {
        return Double(nanos) / 1_000_000_000
    }
}

private extension FixedWidthInteger {
    init?<T: BinaryFloatingPoint>(withReportingOverflow floatingPoint: T) {
        guard let converted = Self(exactly: floatingPoint.rounded()) else {
            return nil
        }
        self = converted
    }
}

extension Array where Element == [String: Any] {
    /// Returns a full deep copy of self, recursively copying any nested
    /// [String: Any] dictionaries or [Any] arrays.
    func deepCopy() -> [[String: Any]] {
        return self.map { dict in
            return dict.deepCopy()
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Recursively deep‐copies this dictionary
    func deepCopy() -> [String: Any] {
        var copy: [String: Any] = [:]
        for (key, value) in self {
            copy[key] = deepCopy(value: value)
        }
        return copy
    }

    /// Helper that inspects a value and copies dicts / arrays recursively
    private func deepCopy(value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return dict.deepCopy()
        case let array as [Any]:
            return array.deepCopyAnyArray()
        default:
            // Primitives (String, Int, Double, Bool, etc.) are value types
            return value
        }
    }
}

extension Array where Element == Any {
    /// Recursively deep‐copies this array
    func deepCopyAnyArray() -> [Any] {
        return self.map { element in
            switch element {
            case let dict as [String: Any]:
                return dict.deepCopy()
            case let array as [Any]:
                return array.deepCopyAnyArray()
            default:
                return element
            }
        }
    }
}
