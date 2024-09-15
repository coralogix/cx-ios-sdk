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
        let exp = expectation(description: "Notification onAppear")
        
        let view = Text("Hello, world!")
            .trackCXView(name: "TestView")
        
        let hostingController = UIHostingController(rootView: view)
        
        let observer = NotificationCenter.default.addObserver(
            forName: .cxRumNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let cxView = notification.object as? CXView, cxView.state == .notifyOnAppear {
                XCTAssertEqual(cxView.name, "TestView")
                exp.fulfill()
            }
        }
        
        // Trigger viewDidAppear manually
        hostingController.viewWillAppear(false)
        hostingController.viewDidAppear(false)
        
        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
