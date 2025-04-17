//
//  MobileVitalsContextTests.swift
//  
//
//  Created by Coralogix DEV TEAM on 11/09/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class MobileVitalsContextTests: XCTestCase {

    var mockSpanData: SpanDataProtocol!
    
    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [
            Keys.mobileVitalsType.rawValue: AttributeValue("fps"),
            Keys.mobileVitalsValue.rawValue: AttributeValue("80"),
        ])
    }
    
    override func tearDownWithError() throws {
        mockSpanData = nil
    }
    
    func testEventContextInitialization() {
        // Initialize EventContext with mock SpanData
        let context = MobileVitalsContext(otel: mockSpanData)
        
        // Verify the properties are set correctly
        XCTAssertEqual(context.mobileVitalsType, "fps")
        XCTAssertEqual(context.mobileVitalsValue, "80")
    }
}
