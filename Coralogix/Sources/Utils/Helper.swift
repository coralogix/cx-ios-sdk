//
//  Helper.swift
//  
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

extension AttributeValue {
    var anyValue: Any {
        switch self {
        case let .string(value): return value
        case let .bool(value): return value
        case let .int(value): return value
        case let .double(value): return value
        case let .stringArray(value): return value
        case let .boolArray(value): return value
        case let .intArray(value): return value
        case let .doubleArray(value): return value
        case let .set(value): return value
        }
    }
}

class Helper {
    internal static func convertToAnyDict(_ attributeDict: [String: AttributeValue]) -> [String: Any] {
        var anyDict: [String: Any] = [:]
        for (key, attributeValue) in attributeDict {
            anyDict[key] = attributeValue.anyValue
        }
        return anyDict
    }
    
    internal static func findFirstLabelText(in view: UIView) -> String? {
        for subview in view.subviews {
            if let label = subview as? UILabel {
                return label.text
            } else if let text = findFirstLabelText(in: subview) {
                return text
            }
        }
        return nil
    }
    
    internal static func convertArrayOfStringToJsonString(array: [String]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: array, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            Log.e("Error convertArrayOfStringToJsonString: \(error)")
        }
        return ""
    }
    
    internal static func convertArrayToJsonString(array: [[String: Any]]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: array, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            Log.e("Error convertArrayToJsonString: \(error)")
        }
        return ""
    }
    
    /// Truncates a frame list middle-out: keeps the head (75%) and tail (25%), drops the middle.
    /// The head is weighted heavier because the fault site and its immediate callers matter most;
    /// a short tail anchors the entry point and reveals recursion boundaries. No marker is inserted —
    /// the array keeps its existing element shape, and a gap in the frames' own `frame_number` values
    /// is the self-describing signal that frames were dropped. Returns the input unchanged when
    /// `frames.count <= cap`.
    internal static func truncateMiddleOut<T>(_ frames: [T], cap: Int) -> [T] {
        guard cap > 0, frames.count > cap else { return frames }
        let head = Int((Double(cap) * 0.75).rounded())
        let tail = cap - head
        var result = Array(frames.prefix(head))
        if tail > 0 { result.append(contentsOf: frames.suffix(tail)) }
        return result
    }

    /// Builds the serialized `threads` attribute for a native crash, applying in order:
    ///   1. a contiguous-prefix thread cap that always retains the crashed thread and never
    ///      reorders threads — positions stay stable so `triggered_by_thread` cannot desync;
    ///   2. middle-out frame truncation per kept thread;
    ///   3. a deterministic byte guard that shrinks — first dropping tail threads (never past the
    ///      crashed thread), then trimming frames harder — until the serialized string fits `byteBudget`.
    /// `allFrames` holds every thread's full frame array in report order; `crashedIndex` is the
    /// position of the crashed thread in that array, or nil if unknown.
    internal static func buildTruncatedThreads(allFrames: [[[String: Any]]],
                                               crashedIndex: Int?,
                                               maxThreads: Int,
                                               frameCap: Int,
                                               byteBudget: Int) -> String {
        guard !allFrames.isEmpty else { return convertArrayOfStringToJsonString(array: []) }

        let frameFloor = 4
        let frameTrimStep = 4
        let minKept = min(allFrames.count, crashedIndex.map { $0 + 1 } ?? 1)
        var keptCount = min(allFrames.count, max(maxThreads, minKept))
        var cap = max(1, frameCap)

        func serialize() -> String {
            let kept = allFrames.prefix(keptCount).map {
                convertArrayToJsonString(array: truncateMiddleOut($0, cap: cap))
            }
            return convertArrayOfStringToJsonString(array: Array(kept))
        }

        var json = serialize()
        while json.utf8.count > byteBudget {
            if keptCount > minKept {
                keptCount -= 1
            } else if cap > frameFloor {
                cap = max(frameFloor, cap - frameTrimStep)
            } else {
                break // floor reached — cannot shrink further without dropping the crashed thread
            }
            json = serialize()
        }
        return json
    }

    internal static func convertDictionaryToJsonString(dict: [String: Any]) -> String {
        func encode(_ d: [String: Any]) -> String? {
            // `isValidJSONObject` rejects `Date` and other non-JSON types without raising an Obj‑C
            // `NSInvalidArgumentException` (which Swift `catch` does not handle).
            guard JSONSerialization.isValidJSONObject(d) else { return nil }
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: d, options: [])
                return String(data: jsonData, encoding: .utf8)
            } catch {
                return nil
            }
        }
        if let json = encode(dict) {
            return json
        }
        let sanitized = jsonSerializationSafeDictionary(dict, keyPath: "")
        if let json = encode(sanitized) {
            return json
        }
        Log.e("convertDictionaryToJsonString: serialization failed after sanitization (key count \(dict.count))")
        return ""
    }

    /// JSON-encodes a non-empty dictionary for emission as a span attribute, returning `nil`
    /// when the input is `nil`/empty or when encoding fails. `convertDictionaryToJsonString`
    /// returns `""` on encoding failure; the downstream parser drops empty-string attributes
    /// silently, so callers should suppress the attribute entirely rather than emit `""`.
    internal static func jsonAttributeString(dict: [String: Any]?) -> String? {
        guard let dict, !dict.isEmpty else { return nil }
        let json = convertDictionaryToJsonString(dict: dict)
        return json.isEmpty ? nil : json
    }

    /// Builds a dictionary `JSONSerialization` accepts: unwraps nested `Optional`s, converts `Date`/`URL`/etc.,
    /// and replaces unknown types with `String(describing:)` so one bad value does not drop the whole payload.
    private static func jsonSerializationSafeDictionary(_ dict: [String: Any], keyPath: String) -> [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (key, value) in dict {
            let path = keyPath.isEmpty ? key : "\(keyPath).\(key)"
            out[key] = jsonSerializationSafeValue(value, keyPath: path)
        }
        return out
    }

    private static func jsonSerializationSafeValue(_ value: Any, keyPath: String) -> Any {
        if let inner = unwrapAnyOptional(value) {
            return jsonSerializationSafeValue(inner, keyPath: keyPath)
        }
        switch value {
        case is NSNull:
            return value
        case let v as String:
            return v
        case let v as Bool:
            return v
        case let v as Int:
            return v
        case let v as Int8:
            return Int(v)
        case let v as Int16:
            return Int(v)
        case let v as Int32:
            return Int(v)
        case let v as Int64:
            return Int(v)
        case let v as UInt:
            return v
        case let v as UInt8:
            return UInt(v)
        case let v as UInt16:
            return UInt(v)
        case let v as UInt32:
            return UInt(v)
        case let v as UInt64:
            return v
        case let v as Double:
            return v
        case let v as Float:
            return Double(v)
        case let v as NSNumber:
            return v
        #if canImport(CoreGraphics)
        case let v as CGFloat:
            return Double(v)
        #endif
        case let v as Decimal:
            return NSDecimalNumber(decimal: v).doubleValue
        case let v as Date:
            return iso8601String(from: v)
        case let v as URL:
            return v.absoluteString
        case let v as UUID:
            return v.uuidString
        case let v as Data:
            return v.base64EncodedString()
        case let v as [String: Any]:
            return jsonSerializationSafeDictionary(v, keyPath: keyPath)
        case let v as [Any]:
            return v.map { jsonSerializationSafeValue($0, keyPath: "\(keyPath)[]") }
        case let v as NSDictionary:
            var mapped: [String: Any] = [:]
            for (k, item) in v {
                let ks: String
                if let stringKey = k as? String {
                    ks = stringKey
                } else {
                    ks = String(describing: k)
                    guard !ks.isEmpty else {
                        Log.w("convertDictionaryToJsonString: skipped non-representable NSDictionary key \(Swift.type(of: k)) at \(keyPath)")
                        continue
                    }
                }
                mapped[ks] = jsonSerializationSafeValue(item, keyPath: "\(keyPath).\(ks)")
            }
            return mapped
        case let v as NSArray:
            return v.map { jsonSerializationSafeValue($0, keyPath: "\(keyPath)[]") }
        default:
            Log.w("convertDictionaryToJsonString: non-JSON-serializable type \(Swift.type(of: value)) at \(keyPath) — coercing with String(describing:)")
            return String(describing: value)
        }
    }

    /// Returns `nil` when `value` is not an `Optional`, `.some(inner)`, or when unwrapping is not needed.
    private static func unwrapAnyOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        guard let child = mirror.children.first else {
            return NSNull()
        }
        return child.value
    }

    private static func iso8601String(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
    
    internal static func convertJsonStringToDict(jsonString: String) -> [String: Any]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            Log.e("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            // Convert JSON data to a dictionary
            if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                // Use the dictionary as needed
                return dictionary
            } else {
                Log.e("JSON data is not in the expected format")
                return nil
            }
        } catch {
            Log.e("Error convertJsonStringToDict: \(error)")
            return nil
        }
    }
    
    internal static func convertJsonStringToArray(jsonString: String) -> [[String: Any]]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            Log.e("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            // Convert JSON data to a dictionary
            if let array = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                // Use the dictionary as needed
                return array
            } else {
                Log.e("JSON data is not in the expected format")
                return nil
            }
        } catch {
            Log.e("Error convertJsonStringToArray: \(error)")
            return nil
        }
    }
    
    internal static func convertJsonStringToArrayOfStrings(jsonString: String) -> [String]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            Log.e("Failed to convert JSON string to data")
            return nil
        }
        
        do {
            // Convert JSON data to a dictionary
            if let arrayOfString = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String] {
                // Use the dictionary as needed
                return arrayOfString
            } else {
                Log.e("JSON data is not in the expected format")
                return nil
            }
        } catch {
            Log.e("Error convertJsonStringToArrayOfStrings: \(error)")
            return nil
        }
    }
    
    internal static func convertDictionary(_ inputDict: [AnyHashable: Any]) -> [String: Any] {
        var outputDict: [String: Any] = [:]
        
        for (key, value) in inputDict {
            if let stringKey = key as? String {
                outputDict[stringKey] = value
            } else {
                // Handle non-string keys if needed
            }
        }
        
        return outputDict
    }
    
    internal static func parseStackTrace(_ stackTrace: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        
        // Split the stack trace into lines
        let lines = stackTrace.split(separator: "\n")
        
        // Regular expression to match the stack trace pattern
        guard let regex = try? NSRegularExpression(pattern: "^#(\\d+)\\s+([^\\(]+)\\s+\\((.*):(\\d+):(\\d+)\\)$") else {
            return [[String: Any]]()
        }
        
        for line in lines {
            let lineStr = String(line)
            let range = NSRange(location: 0, length: lineStr.utf16.count)
            
            if let match = regex.firstMatch(in: lineStr, options: [], range: range) {
                var dict: [String: Any] = [:]
                
//                if let range = Range(match.range(at: 1), in: lineStr) {
//                    dict["index"] = Int(lineStr[range])
//                }
                if let range = Range(match.range(at: 2), in: lineStr) {
                    dict["functionName"] = String(lineStr[range])
                }
                if let range = Range(match.range(at: 3), in: lineStr) {
                    dict["fileName"] = String(lineStr[range])
                }
                if let range = Range(match.range(at: 4), in: lineStr) {
                    dict["lineNumber"] = Int(lineStr[range])
                }
                if let range = Range(match.range(at: 5), in: lineStr) {
                    dict["columnNumber"] = Int(lineStr[range])
                }
                
                result.append(dict)
            }
        }
        return result
    }
    
    internal static func convertCFAbsoluteTimeToEpoch(_ cfTime: CFAbsoluteTime) -> Double {
        return (cfTime + kCFAbsoluteTimeIntervalSince1970) * 1000 // returns ms
    }
    
    internal static func getTraceAndSpanId(otel: SpanDataProtocol) -> (traceId: String, spanId: String) {
        let attributeTraceId = otel.getAttribute(forKey: Keys.customTraceId.rawValue) as? String
        let attributeSpanId = otel.getAttribute(forKey: Keys.customSpanId.rawValue) as? String

        let traceId: String
        let spanId: String

        if let attributeTraceId, !attributeTraceId.isEmpty,
           let attributeSpanId, !attributeSpanId.isEmpty {
            traceId = attributeTraceId
            spanId = attributeSpanId
        } else {
            traceId = otel.getTraceId() ?? ""
            spanId = otel.getSpanId() ?? ""
        }

        return (traceId, spanId)
    }
    
    internal static func getLabels(otel: SpanDataProtocol, labels: [String: Any]?) -> [String: Any]? {
        var mergedLabels = labels ?? [:]
        if let jsonString = otel.getAttribute(forKey: Keys.customLabels.rawValue) as? String,
            let customLabels = Helper.convertJsonStringToDict(jsonString: jsonString) {
            mergedLabels.merge(customLabels, uniquingKeysWith: { (_, new) in new })
        }
        return mergedLabels.isEmpty ? nil : mergedLabels
    }

    // MARK: - User actions / session replay decoupling

    /// Resolves whether user actions instrumentation is enabled from optional exporter options.
    /// Used to avoid repeating optional chaining and default in multiple call sites.
    /// When `options` is `nil`, returns `true` (user actions enabled by default).
    internal static func isUserActionsEnabled(options: CoralogixExporterOptions?) -> Bool {
        options.map { $0.shouldInitInstrumentation(instrumentation: .userActions) } ?? true
    }

    /// Returns whether native touch events should produce RUM user_interaction spans.
    /// `false` when hybrid (spans come from setUserInteraction) or when instrumentations[.userActions] is false.
    internal static func shouldEmitUserActionSpan(options: CoralogixExporterOptions?, sdkFramework: SdkFramework) -> Bool {
        isUserActionsEnabled(options: options) && sdkFramework.isNative
    }

    /// Returns whether touch swizzles should be installed (for native spans and/or session replay in hybrid).
    internal static func shouldInstallTouchSwizzles(options: CoralogixExporterOptions?, sdkFramework: SdkFramework) -> Bool {
        isUserActionsEnabled(options: options) || !sdkFramework.isNative
    }
}
