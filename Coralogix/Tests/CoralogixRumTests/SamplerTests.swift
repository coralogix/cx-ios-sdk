//
//  SamplerTests.swift
//
//
//  Created by Corologix Dev Team on 14/08/2024.
//

import XCTest
@testable import Coralogix

final class SamplerTests: XCTestCase {
    
    func testSampleRateInitialization() {
        // Test with a value within the range
        let sampler1 = SDKSampler(sampleRate: 50)
        XCTAssertEqual(sampler1.sampleRate, 50)
        
        // Test with a value below the minimum
        let sampler2 = SDKSampler(sampleRate: -10)
        XCTAssertEqual(sampler2.sampleRate, 0)
        
        // Test with a value above the maximum
        let sampler3 = SDKSampler(sampleRate: 150)
        XCTAssertEqual(sampler3.sampleRate, 100)
    }
    
    func testShouldInitialize() {
        // Test with sampleRate = 0, should always return false
        let samplerZero = SDKSampler(sampleRate: 0)
        for _ in 1...100 {
            XCTAssertFalse(samplerZero.shouldInitialized())
        }
        
        // Test with sampleRate = 100, should always return true
        let samplerHundred = SDKSampler(sampleRate: 100)
        for _ in 1...100 {
            XCTAssertTrue(samplerHundred.shouldInitialized())
        }
        
        // Test with sampleRate = 50, should return true about half the time
        let samplerFifty = SDKSampler(sampleRate: 50)
        var trueCount = 0
        var falseCount = 0
        for _ in 1...10000 {
            if samplerFifty.shouldInitialized() {
                trueCount += 1
            } else {
                falseCount += 1
            }
        }
        // Allow some tolerance, should be around 50%
        XCTAssert(abs(trueCount - falseCount) < 1000, "The true and false counts are too far apart.")
    }
}

