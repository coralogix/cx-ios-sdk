//
//  CrashSim.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation

class CrashSim {
    static func simulateRandomCrash() {
        let crashType = Int.random(in: 1...5)
        switch crashType {
        case 1:
            self.forceUnwrappingOfNil()
        case 2:
            self.indexOutOfRange()
        case 3:
            self.invalidCastsWithTypeCasting()
        case 4:
            self.fatalError()
        case 5:
            self.imulatingMemoryIssues()
        default:
            print("No crash scenario selected")
        }
    }
    
    private static func forceUnwrappingOfNil() {
        let optionalString: String? = nil
        print(optionalString!)
    }
    
    private static func indexOutOfRange() {
        let array = [1, 2, 3]
        _ = array[5]
    }
    
    private static func invalidCastsWithTypeCasting() {
        let someValue: Any = "This is a string"
        _ = someValue as! Int
    }
    
    private static func fatalError() {
        Swift.fatalError("Simulated crash occurred")
    }
    
    private static func imulatingMemoryIssues() {
        imulatingMemoryIssues()
    }
}
