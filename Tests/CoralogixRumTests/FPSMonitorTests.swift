//
//  FPSMonitorTests.swift
//
//
//  Created by Coralogix DEV TRAM on 08/09/2024.
//

import XCTest
@testable import Coralogix

final class FPSMonitorTests: XCTestCase {
    var fpsMonitor: FPSMonitor!
    
    override func setUp() {
        super.setUp()
        fpsMonitor = FPSMonitor()
    }
    
    override func tearDown() {
        fpsMonitor = nil
        super.tearDown()
    }
}

