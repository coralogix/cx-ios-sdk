//
//  ExtensionsTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 22/04/2025.
//
import XCTest
@testable import SessionReplay

class ExtensionsTestsTests: XCTestCase {
    func testCompressionEquivalence() {
        let sample = "Hello, world! Hello again! 🤖🌍🚀".data(using: .utf8)!
        let bufferSize = 4096
        
        let compressedNew = sample.compressChunk(bufferSize: bufferSize)
        
        XCTAssertEqual(compressedNew?.count, 58)
    }
}
