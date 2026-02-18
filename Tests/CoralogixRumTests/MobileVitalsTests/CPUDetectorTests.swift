//
//  CPUDetectorTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 13/08/2025.
//
import XCTest
@testable import Coralogix

final class CPUDetectorTests: XCTestCase {
    var sut: CPUDetector!
    
    override func setUp() {
        super.setUp()
        // Initialize with a short maxBlockTime for faster tests
        sut = CPUDetector(checkInterval: 0.1)
    }
    
    override func tearDown() {
        sut.stopMonitoring()
        sut = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(sut.minCPU, 0)
        XCTAssertEqual(sut.maxCPU, 0)
        XCTAssertEqual(sut.avgCPU, 0)
        XCTAssertEqual(sut.p95CPU, 0)
        
        XCTAssertEqual(sut.minTotalCpuMs, 0)
        XCTAssertEqual(sut.maxTotalCpuMs, 0)
        XCTAssertEqual(sut.avgTotalCpuMs, 0)
        XCTAssertEqual(sut.p95TotalCpuMs, 0)
        
        XCTAssertEqual(sut.minMainThreadMs, 0)
        XCTAssertEqual(sut.maxMainThreadMs, 0)
        XCTAssertEqual(sut.avgMainThreadMs, 0)
        XCTAssertEqual(sut.p95MainThreadMs, 0)
    }
    
    func testStatsDictionary_withDefaultValues_returnsCorrectDictionary() {
        // Test with normal CPU usage (< 100%)
        sut.usageSamples = [10.0, 20.0, 5.0, 30.0, 15.0]
        sut.totalCpuDeltaMsSamples = [100, 200, 50, 300, 150].map { Double($0) }
        sut.mainThreadDeltaMsSamples = [50, 100, 25, 150, 75].map { Double($0) }

        // When
        let stats = sut.statsDictionary()

        // Then
        XCTAssertEqual(stats.count, 3)

        // Verify CPU Usage
        guard let cpuUsage = stats[MobileVitalsType.cpuUsage.stringValue] as? [String: Any] else {
            XCTFail("CPU Usage section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(cpuUsage[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.percentage.stringValue)
        XCTAssertEqual(cpuUsage[Keys.min.rawValue] as? Double, 5.0)
        XCTAssertEqual(cpuUsage[Keys.max.rawValue] as? Double, 30.0)
        XCTAssertEqual(cpuUsage[Keys.avg.rawValue] as? Double, 16.0)
        XCTAssertEqual(cpuUsage[Keys.p95.rawValue] as? Double, 30.0)

        // Verify Total CPU Time
        guard let totalCpuTime = stats[MobileVitalsType.totalCpuTime.stringValue] as? [String: Any] else {
            XCTFail("Total CPU Time section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(totalCpuTime[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.milliseconds.stringValue)
        XCTAssertEqual(totalCpuTime[Keys.min.rawValue] as? Double, 50.0)
        XCTAssertEqual(totalCpuTime[Keys.max.rawValue] as? Double, 300.0)
        XCTAssertEqual(totalCpuTime[Keys.avg.rawValue] as? Double, 160.0)
        XCTAssertEqual(totalCpuTime[Keys.p95.rawValue] as? Double, 300.0)

        // Verify Main Thread CPU Time
        guard let mainThreadCpuTime = stats[MobileVitalsType.mainThreadCpuTime.stringValue] as? [String: Any] else {
            XCTFail("Main Thread CPU Time section is missing or has the wrong type.")
            return
        }
        XCTAssertEqual(mainThreadCpuTime[Keys.mobileVitalsUnits.rawValue] as? String, MeasurementUnits.milliseconds.stringValue)
        XCTAssertEqual(mainThreadCpuTime[Keys.min.rawValue] as? Double, 25.0)
        XCTAssertEqual(mainThreadCpuTime[Keys.max.rawValue] as? Double, 150.0)
        XCTAssertEqual(mainThreadCpuTime[Keys.avg.rawValue] as? Double, 80.0)
        XCTAssertEqual(mainThreadCpuTime[Keys.p95.rawValue] as? Double, 150.0)
    }
    
    func testCPUUsageCanExceed100Percent_forMultiCoreSaturation() {
        // Given: Simulated multi-core saturation (CPU usage > 100%)
        // This can happen when app uses 2+ cores simultaneously
        // Example: 120% = ~1.2 cores fully saturated, 200% = 2 cores fully saturated
        sut.usageSamples = [80.0, 95.0, 120.0, 140.0, 105.0]
        sut.totalCpuDeltaMsSamples = [800, 950, 1200, 1400, 1050].map { Double($0) }
        sut.mainThreadDeltaMsSamples = [100, 120, 150, 180, 130].map { Double($0) }
        
        // When
        let stats = sut.statsDictionary()
        
        // Then: Should report actual values > 100%, not capped
        guard let cpuUsage = stats[MobileVitalsType.cpuUsage.stringValue] as? [String: Any] else {
            XCTFail("CPU Usage section is missing")
            return
        }
        
        // Max should be 140%, not capped at 100%
        XCTAssertEqual(cpuUsage[Keys.max.rawValue] as? Double, 140.0, 
                       "Max CPU should allow values > 100% to detect multi-core saturation")
        
        // Min should still be normal range
        XCTAssertEqual(cpuUsage[Keys.min.rawValue] as? Double, 80.0)
        
        // Avg should be 108%, not capped
        XCTAssertEqual(cpuUsage[Keys.avg.rawValue] as? Double, 108.0,
                       "Avg CPU should reflect actual multi-core usage")
        
        // P95 should be 140%, not capped at 100%
        XCTAssertEqual(cpuUsage[Keys.p95.rawValue] as? Double, 140.0,
                       "P95 CPU should allow values > 100%")
    }
}
