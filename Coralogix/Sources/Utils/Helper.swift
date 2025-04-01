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
import OpenTelemetryApi

class Helper {
    internal static func convertToAnyDict(_ attributeDict: [String: AttributeValue]) -> [String: Any] {
        var anyDict: [String: Any] = [:]

        for (key, attributeValue) in attributeDict {
            switch attributeValue {
            case let .string(value):
                anyDict[key] = value
            case let .bool(value):
                anyDict[key] = value
            case let .int(value):
                anyDict[key] = value
            case let .double(value):
                anyDict[key] = value
            case let .stringArray(value):
                anyDict[key] = value
            case let .boolArray(value):
                anyDict[key] = value
            case let .intArray(value):
                anyDict[key] = value
            case let .doubleArray(value):
                anyDict[key] = value
            case let .set(value):
                anyDict[key] = value // Assuming AttributeSet conforms to Any
            case let.array(value):
                anyDict[key] = value 
            }
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
    
    internal static func isEmptyDictionary(_ dict: [String: Any]) -> Bool {
        for value in dict.values {
            if let stringValue = value as? String, !stringValue.isEmpty {
                return false
            }
        }
        return true
    }
}
