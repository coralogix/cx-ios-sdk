//
//  TimeIntervalExt.swift
//
//  Created by Coralogix DEV TEAM on 28/03/2024.
//

import Foundation

extension TimeInterval {

    var seconds: Int {
        return Int(self.rounded())
    }

    var milliseconds: Int {
        return Int(self * 1_000)
    }
}
