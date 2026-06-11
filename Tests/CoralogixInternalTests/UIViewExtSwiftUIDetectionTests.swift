//
//  UIViewExtSwiftUIDetectionTests.swift
//  CoralogixInternalTests
//
//  Created by Coralogix DEV TEAM on 11/06/2026.
//

import XCTest
import UIKit
import SwiftUI
@testable import CoralogixInternal

/// Fake Flutter view registered under the exact Objective-C runtime name the SDK
/// resolves (`NSClassFromString("FlutterView")`). Lets tests exercise the
/// FlutterView short-circuit without the Flutter framework on the classpath.
@objc(FlutterView)
private class FakeFlutterView: UIView {}

final class UIViewExtSwiftUIDetectionTests: XCTestCase {

    func testPlainUIKitTree_isNotDetectedAsSwiftUI() {
        let root = UIView()
        let container = UIView()
        let label = UILabel()
        label.text = "hello"
        container.addSubview(label)
        root.addSubview(container)
        root.addSubview(UIImageView())

        XCTAssertFalse(UIView.subtreeContainsSwiftUIHostingView(root))
    }

    func testHostingControllerView_isDetected() {
        let hosting = UIHostingController(rootView: Text("x"))
        // Accessing .view loads the real SwiftUI hosting view
        // (_TtGC7SwiftUI14_UIHostingView…).
        let hostingView: UIView = hosting.view

        XCTAssertTrue(UIView.subtreeContainsSwiftUIHostingView(hostingView))
    }

    func testHostingViewNestedInUIKitTree_isDetected() {
        let hosting = UIHostingController(rootView: Text("x"))
        let root = UIView()
        let wrapper = UIView()
        wrapper.addSubview(hosting.view)
        root.addSubview(UIView())
        root.addSubview(wrapper)

        XCTAssertTrue(UIView.subtreeContainsSwiftUIHostingView(root))
    }

    func testFlutterSubtree_shortCircuitsDetection() {
        let flutterView = FakeFlutterView()
        let hosting = UIHostingController(rootView: Text("x"))
        // Hosting view hidden inside a FlutterView subtree must NOT trigger
        // SwiftUI masking — Flutter frames arrive pre-masked from Dart.
        flutterView.addSubview(hosting.view)

        XCTAssertFalse(UIView.subtreeContainsSwiftUIHostingView(flutterView))

        let root = UIView()
        root.addSubview(flutterView)
        XCTAssertFalse(UIView.subtreeContainsSwiftUIHostingView(root))
    }
}
