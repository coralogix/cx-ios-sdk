//
//  ViewControllerWindowTests.swift
//

import XCTest
@testable import Coralogix

final class ViewControllerWindowTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // A scene-based app shows its first screen while the scene is still foregroundInactive,
    // so no foreground-active key window exists yet. The controller's own window must be
    // used, or the first screen is never reported as a navigation.
    func test_getWindow_withoutActiveKeyWindow_returnsControllersOwnWindow() throws {
        let hasActiveKeyWindow = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .contains { $0.isKeyWindow }
        try XCTSkipIf(hasActiveKeyWindow, "host has an active key window; getWindow() returns it first")

        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = controller
        window.isHidden = false
        self.window = window

        XCTAssertTrue(controller.getWindow() === window)
        XCTAssertTrue(window.visibleViewController() === controller)
    }
}
