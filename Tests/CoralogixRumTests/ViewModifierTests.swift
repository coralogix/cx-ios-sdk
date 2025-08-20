//
//  ViewModifierTests.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import XCTest
import SwiftUI
import Combine
@testable import Coralogix

@available(iOS 13, tvOS 13, *)
final class ViewModifierTests: XCTestCase {
    
    var hostingController: UIHostingController<AnyView>!
    var window: UIWindow!
    
    override func setUp() {
        super.setUp()
        let view = AnyView(Text("Hello, World!")
            .trackCXView(name: "TestView"))
        hostingController = UIHostingController(rootView: view)
        window = UIWindow()
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
    }
    
    override func tearDown() {
        hostingController = nil
        window = nil
        super.tearDown()
    }
    
    func testViewModifierNotificationOnAppear() {
        // Expect a single CXView notifyOnAppear notification for "TestView"
        let expectedName = "TestView"
        let exp = expectation(forNotification: .cxRumNotification, object: nil) { note in
            guard let cxView = note.object as? CXView else { return false }
            guard cxView.state == .notifyOnAppear else { return false }
            XCTAssertEqual(cxView.name, expectedName)
            return true
        }

        // Build the SwiftUI view and host it
        let view = Text("Hello, world!").trackCXView(name: expectedName)
        let hostingController = UIHostingController(rootView: view)

        // Ensure the view is loaded, then simulate appearance
        _ = hostingController.view
        hostingController.viewWillAppear(false)
        hostingController.viewDidAppear(false)

        // Wait for the single matching notification
        wait(for: [exp], timeout: 1.0)
    }
}
