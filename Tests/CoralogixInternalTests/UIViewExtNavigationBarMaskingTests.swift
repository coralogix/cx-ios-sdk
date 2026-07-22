//
//  UIViewExtNavigationBarMaskingTests.swift
//  CoralogixInternalTests
//

import XCTest
import UIKit
@testable import CoralogixInternal

final class UIViewExtNavigationBarMaskingTests: XCTestCase {

    // MARK: - textMatchesAny

    func testTextMatchesAny_substringIsCaseInsensitive() {
        XCTAssertTrue(UIView.textMatchesAny("My Password Field", ["password"]))
        XCTAssertFalse(UIView.textMatchesAny("Username", ["password"]))
    }

    func testTextMatchesAny_regexWildcardMatchesAnyText() {
        XCTAssertTrue(UIView.textMatchesAny("anything at all", [".*"]))
    }

    func testTextMatchesAny_regexPattern() {
        XCTAssertTrue(UIView.textMatchesAny("Order #4821", ["#\\d+"]))
        XCTAssertFalse(UIView.textMatchesAny("Order ABC", ["#\\d+"]))
    }

    // MARK: - collectMatchingNavigationBarRects

    func testMatchingNavigationBarRects_masksBarWhenTitleMatches() {
        let bar = UINavigationBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.items = [UINavigationItem(title: "Secret Screen")]
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        root.addSubview(bar)

        let rects = UIView().collectMatchingNavigationBarRects(in: root, maskText: ["Secret"])

        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects.first, bar.convert(bar.bounds, to: root))
    }

    func testMatchingNavigationBarRects_ignoresBarWhenTitleDoesNotMatch() {
        let bar = UINavigationBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.items = [UINavigationItem(title: "Home")]
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        root.addSubview(bar)

        let rects = UIView().collectMatchingNavigationBarRects(in: root, maskText: ["password"])

        XCTAssertTrue(rects.isEmpty)
    }

    func testMatchingNavigationBarRects_emptyWhenNoMaskText() {
        let bar = UINavigationBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.items = [UINavigationItem(title: "Secret Screen")]
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        root.addSubview(bar)

        XCTAssertTrue(UIView().collectMatchingNavigationBarRects(in: root, maskText: nil).isEmpty)
        XCTAssertTrue(UIView().collectMatchingNavigationBarRects(in: root, maskText: []).isEmpty)
    }
}
