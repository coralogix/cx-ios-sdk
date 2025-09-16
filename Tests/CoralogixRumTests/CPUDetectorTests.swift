//
//  CPUDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//
import XCTest
@testable import Coralogix

final class CPUDetectorTests: XCTestCase {
    var cpuDetector: CPUDetector!
    var cpuDetected = false
    
    override func setUp() {
        super.setUp()
        // Initialize with a short maxBlockTime for faster tests
        cpuDetector = CPUDetector(checkInterval: 0.1)
        
        // Override the handleANR with a closure to test ANR detection
        cpuDetector.handleCpuClosure = { [weak self] in
            self?.cpuDetected = true
        }
    }
    
    override func tearDown() {
        cpuDetector.stopMonitoring()
        cpuDetector = nil
        cpuDetected = false
        super.tearDown()
    }
}

