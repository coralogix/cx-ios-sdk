//
//  CXViewModifierTests.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import XCTest
import SwiftUI
import Combine
@testable import CoralogixRum

@available(iOS 13, tvOS 13, *)
final class CXViewModifierTests: XCTestCase {
    
    var mockHandler: MockSwiftUIViewHandler!
    var hostingController: UIHostingController<AnyView>!
    var window: UIWindow!
    
    override func setUp() {
        super.setUp()
        mockHandler = MockSwiftUIViewHandler()
        let view = AnyView(Text("Hello, World!")
            .trackCXView(name: "TestView", viewsHandler: mockHandler))
        hostingController = UIHostingController(rootView: view)
        window = UIWindow()
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
    }
    
    override func tearDown() {
        mockHandler = nil
        hostingController = nil
        window = nil
        super.tearDown()
    }
    
    func testNotifyOnAppear() {
        let expectation = self.expectation(description: "View appeared")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertTrue(self.mockHandler.onAppearCalled)
            XCTAssertEqual(self.mockHandler.receivedName, "TestView")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
    }
}

class MockSwiftUIViewHandler: SwiftUIViewHandler {
    var onAppearCalled = false
    var onDisappearCalled = false
    var receivedIdentity: String?
    var receivedName: String?
    
    func notifyOnAppear(identity: String, name: String) {
        onAppearCalled = true
        receivedIdentity = identity
        receivedName = name
    }
    
    func notifyOnDisappear(identity: String) {
        onDisappearCalled = true
        receivedIdentity = identity
    }
}
