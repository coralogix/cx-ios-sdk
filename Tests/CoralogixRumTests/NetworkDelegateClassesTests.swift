//
//  NetworkDelegateClassesTests.swift
//

import XCTest
@testable import Coralogix

final class NetworkDelegateClassesTests: XCTestCase {

    private final class FakeReactNativeHandler: NSObject {}

    func test_reactNativeHandlerPresent_returnsThatClass() throws {
        let className = NSStringFromClass(FakeReactNativeHandler.self)

        let classes = CoralogixRum.urlSessionDelegateClassesForReactNative(className: className)

        XCTAssertEqual(classes.count, 1)
        let only = try XCTUnwrap(classes.first)
        XCTAssertTrue(only == FakeReactNativeHandler.self)
    }

    func test_reactNativeHandlerAbsent_returnsEmptyList() {
        let classes = CoralogixRum.urlSessionDelegateClassesForReactNative(className: "CXNoSuchDelegateClass")

        XCTAssertEqual(classes.count, 0)
    }
}
