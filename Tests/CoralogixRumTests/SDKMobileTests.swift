//
//  SDKMobileTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 28/07/2025.
//

import XCTest
@testable import Coralogix

final class SDKMobileTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    func testSwiftFrameworkDictionary() {
        let sdk = SDKMobile(sdkFramework: .swift)
        let dict = sdk.getDictionary()
        
        XCTAssertEqual(dict[Keys.framework.rawValue] as? String, "swift")
        XCTAssertEqual(dict[Keys.sdkVersion.rawValue] as? String, Global.sdk.rawValue)
        XCTAssertEqual(dict[Keys.operatingSystem.rawValue] as? String, Global.getOs())
        XCTAssertNil(dict[Keys.nativeVersion.rawValue]) // Not present for .swift
    }
    
    func testHybridFlutterFrameworkDictionary() {
        let sdk = SDKMobile(sdkFramework: .flutter(version: "3.13.0"))
        let dict = sdk.getDictionary()
        
        XCTAssertEqual(dict[Keys.framework.rawValue] as? String, "flutter")
        XCTAssertEqual(dict[Keys.sdkVersion.rawValue] as? String, "3.13.0")
        XCTAssertEqual(dict[Keys.nativeVersion.rawValue] as? String, Global.sdk.rawValue)
        XCTAssertEqual(dict[Keys.operatingSystem.rawValue] as? String, Global.getOs())
    }
    
    func testHybridReactNativeFrameworkDictionary() {
        let sdk = SDKMobile(sdkFramework: .reactNative(version: "0.72.4"))
        let dict = sdk.getDictionary()
        
        XCTAssertEqual(dict[Keys.framework.rawValue] as? String, "react-native")
        XCTAssertEqual(dict[Keys.sdkVersion.rawValue] as? String, "0.72.4")
        XCTAssertEqual(dict[Keys.nativeVersion.rawValue] as? String, Global.sdk.rawValue)
        XCTAssertEqual(dict[Keys.operatingSystem.rawValue] as? String, Global.getOs())
    }
}
