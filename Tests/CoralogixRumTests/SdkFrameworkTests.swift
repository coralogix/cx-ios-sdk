//
//  SdkFrameworkTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 28/07/2025.
//

import XCTest
@testable import Coralogix

final class SdkFrameworkTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSwiftFrameworkProperties() {
         let framework: SdkFramework = .swift
         
         XCTAssertEqual(framework.name, "swift")
         XCTAssertTrue(framework.isNative)
         XCTAssertEqual(framework.version, Global.sdk.rawValue)
         XCTAssertEqual(framework.nativeVersion, Keys.undefined.rawValue)
     }

     func testFlutterFrameworkProperties() {
         let framework: SdkFramework = .flutter(version: "3.13.0")
         
         XCTAssertEqual(framework.name, "flutter")
         XCTAssertFalse(framework.isNative)
         XCTAssertEqual(framework.version, "3.13.0")
         XCTAssertEqual(framework.nativeVersion, Global.sdk.rawValue)
     }

     func testReactNativeFrameworkProperties() {
         let framework: SdkFramework = .reactNative(version: "0.72.4")
         
         XCTAssertEqual(framework.name, "react-native")
         XCTAssertFalse(framework.isNative)
         XCTAssertEqual(framework.version, "0.72.4")
         XCTAssertEqual(framework.nativeVersion, Global.sdk.rawValue)
     }
}
