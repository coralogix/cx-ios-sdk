//
//  DeepCopy.swift
//  Coralogix
//

import Foundation

extension Array where Element == [String: Any] {
    /// A copy whose nested dictionaries and arrays are not shared with `self`, so the
    /// hybrid beforeSend callback cannot change what the SDK still holds through them.
    func deepCopy() -> [[String: Any]] {
        map { $0.deepCopy() }
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Recursively copies nested `[String: Any]` dictionaries and `[Any]` arrays
    /// (bridged NSDictionary/NSArray included). Any other value is kept as is.
    func deepCopy() -> [String: Any] {
        mapValues(deepCopyValue)
    }
}

private func deepCopyValue(_ value: Any) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.deepCopy()
    case let array as [Any]:
        return array.map(deepCopyValue)
    default:
        return value
    }
}
