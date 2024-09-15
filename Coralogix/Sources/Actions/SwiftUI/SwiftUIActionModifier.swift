//
//  SwiftUIActionModifier.swift
//
//
//  Created by Coralogix DEV TEAM on 23/07/2024.
//

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
