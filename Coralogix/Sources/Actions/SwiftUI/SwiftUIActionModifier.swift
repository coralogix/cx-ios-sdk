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
        content.simultaneousGesture(
            TapGesture(count: count).onEnded { _ in
                let tap = [Keys.tapName.rawValue: name,
                           Keys.tapCount.rawValue: count,
                           Keys.tapAttributes.rawValue: attributes]
                NotificationCenter.default.post(name: .cxRumNotificationUserActions, object: tap)
            }
        )
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
