//
//  File.swift
//  
//
//  Created by Coralogix DEV TEAM on 14/04/2024.
//

import Foundation

extension String {
    func matches(for regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            return results.map {
                if let range = Range($0.range, in: self) {
                    return String(self[range])
                }
                return ""
            }
        } catch let error {
            Log.e("Invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}
