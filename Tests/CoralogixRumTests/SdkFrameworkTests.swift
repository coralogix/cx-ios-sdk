//
//  SdkFrameworkTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 28/07/2025.
//

import XCTest
@testable import Coralogix

final class SdkFrameworkTests: XCTestCase {
    func testSwiftFrameworkProperties() {
         let framework: SdkFramework = .swift
         
         XCTAssertEqual(framework.name, "swift")
         XCTAssertTrue(framework.isNative)
         XCTAssertFalse(framework.isFlutter)
         XCTAssertEqual(framework.version, Global.sdk.rawValue)
         XCTAssertEqual(framework.nativeVersion, Keys.undefined.rawValue)
     }

     func testFlutterFrameworkProperties() {
         let framework: SdkFramework = .flutter(version: "3.13.0")
         
         XCTAssertEqual(framework.name, "flutter")
         XCTAssertFalse(framework.isNative)
         XCTAssertTrue(framework.isFlutter, "Any Flutter version is Flutter")
         XCTAssertEqual(framework.version, "3.13.0")
         XCTAssertEqual(framework.nativeVersion, Global.sdk.rawValue)
     }

     func testReactNativeFrameworkProperties() {
         let framework: SdkFramework = .reactNative(version: "0.72.4")
         
         XCTAssertEqual(framework.name, "react-native")
         XCTAssertFalse(framework.isNative)
         XCTAssertFalse(framework.isFlutter, "React Native shares the hybrid path but not Flutter's capture timing")
         XCTAssertEqual(framework.version, "0.72.4")
         XCTAssertEqual(framework.nativeVersion, Global.sdk.rawValue)
     }
}
