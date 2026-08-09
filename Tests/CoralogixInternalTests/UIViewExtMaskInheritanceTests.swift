//
//  UIViewExtMaskInheritanceTests.swift
//  CoralogixInternalTests
//

import XCTest
import UIKit
@testable import CoralogixInternal

/// Masking is inherited downward — everything inside a masked view is masked — and the rects the
/// capture pass paints are the single definition of "masked" that the tap check reuses.
final class UIViewExtMaskInheritanceTests: XCTestCase {

    // MARK: - isInsideMaskedSubtree

    func testDirectlyMaskedView_isInsideMaskedSubtree() {
        let view = UIView()
        view.cxMask = true

        XCTAssertTrue(view.isInsideMaskedSubtree)
    }

    func testUnmaskedStandaloneView_isNotInsideMaskedSubtree() {
        XCTAssertFalse(UIView().isInsideMaskedSubtree)
    }

    /// The keypad case: the key carries no masking signal of its own, and hit-testing resolves the
    /// key rather than the masked container. Asking the key alone must still answer "masked".
    func testUnmaskedChildOfMaskedContainer_isInsideMaskedSubtree() {
        let container = UIView()
        container.cxMask = true
        let key = UIButton()
        container.addSubview(key)

        XCTAssertTrue(key.isInsideMaskedSubtree,
                      "A child of a masked container must inherit masking")
    }

    func testMaskingIsInheritedThroughMultipleLevels() {
        let masked = UIView()
        masked.cxMask = true
        let middle = UIView()
        let leaf = UILabel()
        masked.addSubview(middle)
        middle.addSubview(leaf)

        XCTAssertTrue(leaf.isInsideMaskedSubtree,
                      "Masking must reach a descendant at any depth, not just direct children")
    }

    func testSiblingSubtreeOfMaskedContainerStaysUnmasked() {
        let root = UIView()
        let maskedContainer = UIView()
        maskedContainer.cxMask = true
        let insideKey = UIButton()
        maskedContainer.addSubview(insideKey)
        let outsideButton = UIButton()
        root.addSubview(maskedContainer)
        root.addSubview(outsideButton)

        XCTAssertTrue(insideKey.isInsideMaskedSubtree)
        XCTAssertFalse(outsideButton.isInsideMaskedSubtree,
                       "A sibling of a masked container must not be masked")
    }

    // MARK: - collectNativeMaskRects

    /// One collector feeds both the capture pass and the interaction-time masking resolution:
    /// every mask family combines, offset to the window's screen position, so the tap test and
    /// the painted pixels derive from the same geometry.
    func testCollectNativeMaskRects_combinesFamiliesAndAppliesWindowOffset() {
        let window = UIWindow(frame: CGRect(x: 10, y: 20, width: 300, height: 300))
        window.isHidden = false  // windows are born hidden; the walk skips hidden views
        let masked = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        masked.cxMask = true
        let label = UILabel(frame: CGRect(x: 100, y: 0, width: 50, height: 20))
        label.text = "secret code"
        let image = UIImageView(frame: CGRect(x: 0, y: 100, width: 40, height: 40))
        window.addSubview(masked)
        window.addSubview(label)
        window.addSubview(image)

        let rects = window.collectNativeMaskRects(in: window,
                                                  maskText: ["secret"],
                                                  maskAllImages: true)

        XCTAssertEqual(rects.count, 3, "cxMask, maskText, and maskAllImages must all contribute")
        XCTAssertTrue(rects.contains(CGRect(x: 10, y: 20, width: 50, height: 50)),
                      "The cxMask rect must be offset by the window's screen origin")
        XCTAssertTrue(rects.contains(CGRect(x: 110, y: 20, width: 50, height: 20)),
                      "The maskText rect must be offset by the window's screen origin")
        XCTAssertTrue(rects.contains(CGRect(x: 10, y: 120, width: 40, height: 40)),
                      "The maskAllImages rect must be offset by the window's screen origin")
    }

    func testCollectNativeMaskRects_withoutTextOrImageOptions_stillCollectsCxMask() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false  // windows are born hidden; the walk skips hidden views
        let masked = UIView(frame: CGRect(x: 5, y: 6, width: 50, height: 50))
        masked.cxMask = true
        let label = UILabel(frame: CGRect(x: 100, y: 0, width: 50, height: 20))
        label.text = "secret code"
        window.addSubview(masked)
        window.addSubview(label)

        let rects = window.collectNativeMaskRects(in: window, maskText: nil, maskAllImages: false)

        XCTAssertEqual(rects, [CGRect(x: 5, y: 6, width: 50, height: 50)],
                       "Only the cxMask rect is collected when no other masking is configured")
    }

    // MARK: - collectCxMaskRects

    /// A masked container whose keys are *not* individually masked contributes exactly one rect.
    /// The keys inherit masking for interaction purposes, but they carry no `cxMask` of their own,
    /// so the rect walk must not invent rects for them.
    func testMaskedContainerWithUnmaskedKeysYieldsOneRect() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let keypad = UIView(frame: CGRect(x: 20, y: 40, width: 200, height: 160))
        keypad.cxMask = true
        for index in 0..<9 {
            let key = UIButton(frame: CGRect(x: (index % 3) * 60, y: (index / 3) * 50,
                                             width: 50, height: 40))
            keypad.addSubview(key)
        }
        root.addSubview(keypad)

        let rects = root.collectCxMaskRects(in: root)

        XCTAssertEqual(rects.count, 1,
                       "Unmasked keys inside a masked container must not each add a rect")
        XCTAssertEqual(rects.first, CGRect(x: 20, y: 40, width: 200, height: 160))
    }

    /// The keys of a masked keypad carry no masking signal of their own, so the container's rect
    /// is the only thing covering them. It must span the whole keypad.
    func testMaskedContainerRectCoversItsUnmaskedKeys() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let keypad = UIView(frame: CGRect(x: 20, y: 40, width: 200, height: 160))
        keypad.cxMask = true
        let key = UIButton(frame: CGRect(x: 60, y: 50, width: 50, height: 40))
        keypad.addSubview(key)
        root.addSubview(keypad)

        let rects = root.collectCxMaskRects(in: root)

        XCTAssertEqual(rects.count, 1)
        let keyInRoot = key.convert(key.bounds, to: root)
        XCTAssertTrue(rects[0].contains(keyInRoot),
                      "The container's mask rect must cover its keys")
        XCTAssertTrue(rects[0].contains(CGPoint(x: keyInRoot.midX, y: keyInRoot.midY)),
                      "A tap at the centre of a key must fall inside the container's mask rect")
    }

    /// An unmasked container must still yield the rects of the masked views inside it — stopping
    /// at a masked node must not turn into stopping at any node.
    func testUnmaskedContainerYieldsItsMaskedDescendants() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let plainContainer = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let maskedA = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        maskedA.cxMask = true
        let maskedB = UIView(frame: CGRect(x: 10, y: 100, width: 80, height: 30))
        maskedB.cxMask = true
        plainContainer.addSubview(maskedA)
        plainContainer.addSubview(maskedB)
        root.addSubview(plainContainer)

        let rects = root.collectCxMaskRects(in: root)

        XCTAssertEqual(rects.count, 2)
        XCTAssertTrue(rects.contains(CGRect(x: 10, y: 10, width: 50, height: 20)))
        XCTAssertTrue(rects.contains(CGRect(x: 10, y: 100, width: 80, height: 30)))
    }

    /// A masked subview that extends beyond its masked parent's bounds must still be masked over
    /// its whole area. Subviews are not clipped unless `clipsToBounds` is set, so the parent's
    /// rect does not necessarily cover its descendants — collapsing a masked subtree to the
    /// ancestor's rect alone would leave the overflow visible.
    func testMaskedSubviewOverflowingItsMaskedParentIsStillCovered() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        parent.cxMask = true
        let overflowing = UIView(frame: CGRect(x: 50, y: 50, width: 200, height: 200))
        overflowing.cxMask = true
        parent.addSubview(overflowing)
        root.addSubview(parent)

        let rects = root.collectCxMaskRects(in: root)

        // A point inside the overflowing subview but outside the parent.
        let overflowPoint = CGPoint(x: 200, y: 200)
        XCTAssertFalse(rects.contains { $0.contains(CGPoint(x: 300, y: 300)) },
                       "Sanity: a point outside both views must not be masked")
        XCTAssertTrue(rects.contains { $0.contains(overflowPoint) },
                      "The part of a masked subview outside its masked parent must stay masked")
    }

    /// A masked view inside a scrolled scroll view must report its rect at the scrolled position,
    /// not its unscrolled layout position — otherwise the mask lands somewhere the content is not
    /// and the tap check consults the wrong region.
    func testMaskedViewInsideScrolledScrollViewReportsScrolledPosition() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let masked = UIView(frame: CGRect(x: 0, y: 200, width: 100, height: 50))
        masked.cxMask = true
        scrollView.addSubview(masked)
        scrollView.contentSize = CGSize(width: 300, height: 600)
        root.addSubview(scrollView)

        let unscrolled = root.collectCxMaskRects(in: root)
        XCTAssertEqual(unscrolled.first?.origin.y, 200)

        scrollView.contentOffset = CGPoint(x: 0, y: 150)
        let scrolled = root.collectCxMaskRects(in: root)

        XCTAssertEqual(scrolled.first?.origin.y, 50,
                       "The mask rect must follow the content as it scrolls")
    }

    func testHiddenMaskedViewYieldsNoRect() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let masked = UIView(frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        masked.cxMask = true
        masked.isHidden = true
        root.addSubview(masked)

        XCTAssertTrue(root.collectCxMaskRects(in: root).isEmpty,
                      "A hidden view is not painted, so it masks nothing")
    }

}
