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
        // Clamp head to cap - 1 whenever cap >= 2 so at least one tail frame (the entry point) is
        // always kept — rounding could otherwise take the whole budget as head (e.g. cap == 2 →
        // head 2, tail 0, dropping the entry frame).
        let head = cap == 1 ? 1 : min(Int((Double(cap) * 0.75).rounded()), cap - 1)
        let tail = cap - head
        var result = Array(frames.prefix(head))
        if tail > 0 { result.append(contentsOf: frames.suffix(tail)) }
        return result
    }

    /// Builds the serialized `threads` attribute for a native crash. It keeps every thread in
    /// report order and applies a deterministic byte guard that shrinks until the serialized string
    /// fits `byteBudget`:
    ///   1. drop tail threads (never past the crashed thread);
    ///   2. trim every kept thread's frames middle-out down to a floor;
    ///   3. last resort — when positional alignment forces keeping more threads than fit even at the
    ///      floor, empty the context (before-crashed) threads' frame arrays and, if still needed,
    ///      trim the crashed thread below the floor toward a single frame.
    /// Threads are never reordered and the crashed thread plus its positional slot are always
    /// retained, so `triggered_by_thread` cannot desync. The number of threads reported is bounded
    /// solely by this guard (there is no separate thread-count knob). The result always fits
    /// `byteBudget` unless even the minimal positional-safe form (one frame + empty context slots)
    /// exceeds it, in which case that minimal form is returned as a best effort.
    /// `allFrames` holds every thread's full frame array in report order; `crashedIndex` is the
    /// position of the crashed thread in that array, or nil if unknown.
    internal static func buildTruncatedThreads(allFrames: [[[String: Any]]],
                                               crashedIndex: Int?,
                                               frameCap: Int,
                                               byteBudget: Int) -> String {
        guard !allFrames.isEmpty else { return convertArrayOfStringToJsonString(array: []) }

        let frameFloor = 4
        let frameTrimStep = 4
        let crashed = crashedIndex.map { min(max(0, $0), allFrames.count - 1) }
        let keepIndex = crashed ?? 0                          // thread whose frames we protect longest
        let minKept = (crashed.map { $0 + 1 }) ?? 1
        var keptCount = allFrames.count
        var cap = max(1, frameCap)

        // When `emptyContext` is set, every kept thread except `keepIndex` is serialized as an empty
        // frame array. This shrinks the payload while preserving array positions, so the crashed
        // thread stays at its index and `triggered_by_thread` cannot desync.
        func serialize(emptyContext: Bool = false) -> String {
            let kept = allFrames.prefix(keptCount).enumerated().map { index, frames -> String in
                if emptyContext && index != keepIndex {
                    return convertArrayToJsonString(array: [])
                }
                return convertArrayToJsonString(array: truncateMiddleOut(frames, cap: cap))
            }
            return convertArrayOfStringToJsonString(array: Array(kept))
        }

        // Stages 1–2: drop tail threads, then trim frames to the floor.
        var json = serialize()
        while json.utf8.count > byteBudget {
            if keptCount > minKept {
                keptCount -= 1
            } else if cap > frameFloor {
                cap = max(frameFloor, cap - frameTrimStep)
            } else {
                break
            }
            json = serialize()
        }
        if json.utf8.count <= byteBudget { return json }

        // Stage 3 (last resort): positional alignment forces keeping `minKept` threads that still
        // exceed the budget at the floor. Empty the context threads (positions preserved) and, if
        // needed, trim the crashed thread below the floor toward a single frame.
        json = serialize(emptyContext: true)
        while json.utf8.count > byteBudget && cap > 1 {
            cap -= 1
            json = serialize(emptyContext: true)
        }
        return json
    }

    /// Trims a fully-assembled native-crash log record so its serialized JSON fits `byteBudget`.
    /// Export-time counterpart to `buildTruncatedThreads`: rather than budgeting the `threads` string
    /// alone and *estimating* the rest of the payload, it measures the actual record that goes on the
    /// wire (post-assembly, post-`beforeSend`) and derives the space left for `threads` from that
    /// measurement — so whatever the user context, view name, or labels add is already accounted for.
    /// The trimming itself is `buildTruncatedThreads`, unchanged; it just receives a record-derived budget.
    ///
    /// `threadsTransport` is the SDK's own `threads` attribute (from `Keys.threads`, in report order)
    /// and is the source of truth for the array — NOT the record's `error_context.threads`, which
    /// `beforeSend` can reorder, drop, or reshape (either would desync `crashedIndex` or hide the array
    /// from the guard). Crash threads are SDK-owned diagnostic data, so the guard rebases the record on
    /// them and `beforeSend` edits to the array don't survive. `crashedIndex` is the crashed thread's
    /// position in that array (from `Keys.crashedThreadIndex`); the guard never drops past it. Returns
    /// the record untouched when it carries no crash threads or already fits, and logs when even the
    /// minimal form can't fit (the envelope alone exceeds the budget) — best effort, never crashing.
    internal static func fitCrashRecordToByteBudget(record: [String: Any],
                                                    threadsTransport: String?,
                                                    crashedIndex: Int?,
                                                    frameCap: Int,
                                                    byteBudget: Int) -> [String: Any] {
        // Only native crashes carry the threads transport attribute; non-crash spans return here for
        // free (a nil check, no record traversal or serialization).
        guard let threadsTransport else { return record }
        let threads = decodeThreadsTransport(threadsTransport)
        guard !threads.isEmpty else { return record }

        // Rebase the record on the SDK's own threads so measurement, trimming, and crashedIndex stay
        // consistent no matter what beforeSend did to error_context.threads. A no-op (returns the input)
        // when beforeSend removed the crash context entirely — there's nothing to write into.
        let base = replacingCrashThreads(in: record, with: threads)
        guard let recordBytes = jsonByteCount(base), recordBytes > byteBudget else { return base }
        guard let envelopeBytes = jsonByteCount(replacingCrashThreads(in: base, with: [])) else {
            return base
        }

        // `buildTruncatedThreads` fits the escaped transport form (array-of-strings) to its budget,
        // while the record embeds `threads` as a plain nested array (smaller) — so fitting the
        // transport form to `byteBudget - envelope` lands the reassembled record at or under budget.
        // The bounded loop re-measures the real record and tightens the budget on the off chance the
        // two encodings diverge enough to matter.
        var budget = max(0, byteBudget - envelopeBytes)
        var result = base
        for _ in 0..<5 {
            let trimmedJson = buildTruncatedThreads(allFrames: threads, crashedIndex: crashedIndex,
                                                    frameCap: frameCap, byteBudget: budget)
            result = replacingCrashThreads(in: base, with: decodeThreadsTransport(trimmedJson))
            let bytes = jsonByteCount(result) ?? Int.max
            if bytes <= byteBudget || budget == 0 { break }
            budget = Int(Double(budget) * 0.85)
        }
        if let bytes = jsonByteCount(result), bytes > byteBudget {
            // A fat envelope (large session context / labels / user context) can leave no room even
            // after threads shrink to the minimum. We don't drop customer-owned envelope fields —
            // surface it so it's diagnosable rather than silently over budget.
            Log.w("[Crash] log record is \(bytes)B after trimming, over the \(byteBudget)B budget — the envelope alone may exceed it")
        }
        return result
    }

    /// Decodes the `threads` transport form produced by `buildTruncatedThreads` (a JSON array of
    /// per-thread JSON strings) back into the nested frame arrays the record embeds. An empty
    /// per-thread string decodes to an empty frame array, preserving the thread's position.
    private static func decodeThreadsTransport(_ json: String) -> [[[String: Any]]] {
        guard let threadStrings = convertJsonStringToArrayOfStrings(jsonString: json) else { return [] }
        return threadStrings.map { convertJsonStringToArray(jsonString: $0) ?? [] }
    }

    private static func replacingCrashThreads(in record: [String: Any],
                                              with threads: [[[String: Any]]]) -> [String: Any] {
        guard var text = record[Keys.text.rawValue] as? [String: Any],
              var cxRum = text[Keys.cxRum.rawValue] as? [String: Any],
              var errorContext = cxRum[Keys.errorContext.rawValue] as? [String: Any] else {
            return record
        }
        errorContext[Keys.threads.rawValue] = threads
        cxRum[Keys.errorContext.rawValue] = errorContext
        text[Keys.cxRum.rawValue] = cxRum
        var result = record
        result[Keys.text.rawValue] = text
        return result
    }

    private static func jsonByteCount(_ object: [String: Any]) -> Int? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return (try? JSONSerialization.data(withJSONObject: object, options: []))?.count
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
