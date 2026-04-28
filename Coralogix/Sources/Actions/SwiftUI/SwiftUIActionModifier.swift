//
//  SwiftUIActionModifier.swift
//
//
//  Created by Coralogix DEV TEAM on 23/07/2024.
//

import CoralogixInternal
import UIKit
#if canImport(SwiftUI)
import SwiftUI
#endif

@available(iOS 13, *)
internal struct CXTapModifier: SwiftUI.ViewModifier {
    
    let count: Int
    let name: String
    let attributes: [String: Any]

    func body(content: Content) -> some View {
        if #available(tvOS 16.0, iOS 14.0, *) {
            content.simultaneousGesture(
                TapGesture(count: count).onEnded { _ in
                    let tap = [Keys.tapName.rawValue: name,
                               Keys.tapCount.rawValue: count,
                               Keys.tapAttributes.rawValue: attributes] as? [String: Any]
                    NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
                }
            )
        } else {
            content.overlay(
                TapView(count: count) {
                    let tap = [Keys.tapName.rawValue: name,
                               Keys.tapCount.rawValue: count,
                               Keys.tapAttributes.rawValue: attributes] as? [String: Any]
                    NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
                }
            )
        }
    }
}

@available(iOS 13, *)
public extension SwiftUI.View {
    func trackCXTapAction(
        name: String,
        attributes: [String: Any] = [String: Any](),
        count: Int = 1
    ) -> some View {
        return modifier(
            CXTapModifier(
                count: count,
                name: name,
                attributes: attributes
            )
        )
    }
}

@available(iOS 13, *)
struct TapView: UIViewRepresentable {
    let count: Int
    let action: () -> Void

    class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func handleTap() {
            action()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.numberOfTapsRequired = count
        view.addGestureRecognizer(tapGesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - SwiftUI Swipe Detection

/// Subclass of UIPanGestureRecognizer that calls ScrollTracker.discardTouch when the
/// gesture is recognized, preventing cx_sendEvent's processEnded from also emitting a
/// redundant .scroll span for the same gesture.
/// Only discards when state == .ended (recognized) — taps and micro-drags that fail to
/// recognize (state == .failed) do not discard, so their click events still fire.
/// Skips discarding when the gesture's view is nested inside a UIScrollView: in that
/// context the underlying scroll view's own pan gesture is legitimate and its scroll
/// span must not be suppressed.
@available(iOS 13, *)
private final class SwipeDetectorGestureRecognizer: UIPanGestureRecognizer {
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if state == .ended && !isInScrollViewContext() {
            touches.forEach { ScrollTracker.shared.discardTouch($0) }
        }
    }

    /// Returns true if any ancestor of the gesture's view in the responder chain is a
    /// UIScrollView (covers UITableView, UICollectionView, SwiftUI List/ScrollView, etc.).
    private func isInScrollViewContext() -> Bool {
        var ancestor = view?.superview
        while let v = ancestor {
            if v is UIScrollView { return true }
            ancestor = v.superview
        }
        return false
    }
}

/// Transparent overlay UIView that attaches a SwipeDetectorGestureRecognizer to detect
/// single-finger swipes. On gesture end, posts a TouchEvent(.swipe) notification which
/// UserActionsInstrumentation converts into a user-interaction span.
@available(iOS 13, *)
struct SwipeDetectorView: UIViewRepresentable {

    @available(iOS 13, *)
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let loc = gesture.location(in: nil)
            let translation = gesture.translation(in: nil)
            let start = CGPoint(x: loc.x - translation.x, y: loc.y - translation.y)
            guard let dir = ScrollTracker.direction(from: start, to: loc) else { return }
            NotificationCenter.default.post(
                name: .cxRumNotificationUserActions,
                object: TouchEvent(view: view, location: loc, eventType: .swipe, scrollDirection: dir)
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = SwipeDetectorGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan)
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesEnded = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@available(iOS 13, *)
internal struct CXSwipeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(SwipeDetectorView())
    }
}

@available(iOS 13, *)
public extension SwiftUI.View {
    func trackCXSwipeAction() -> some View {
        modifier(CXSwipeModifier())
    }
}
