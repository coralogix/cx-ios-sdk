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
}
