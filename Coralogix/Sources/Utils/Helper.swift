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
    
    internal static func convertDictionayToJsonString(dict: [String: Any]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            Log.e("Error: \(error)")
        }
        return ""
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
}
