//
//  SwiftUIViewModifier.swift
//
//
//  Created by Coralogix DEV TEAM on 15/05/2024.
//

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13, tvOS 13, *)
public struct CXViewModifier: SwiftUI.ViewModifier {
    let name: String
    
    public func body(content: Content) -> some View {
        content.onAppear {
            let cxView = CXView(state: .notifyOnAppear, name: name)
            NotificationCenter.default.post(name: .cxRumNotification, object: cxView)
        }
        .onDisappear {
            let cxView = CXView(state: .notifyOnDisappear, name: name)
            NotificationCenter.default.post(name: .cxRumNotification, object: cxView)
        }
    }
}

@available(iOS 13, tvOS 13, *)
public extension SwiftUI.View {
    func trackCXView(name: String) -> some View {
        return modifier(CXViewModifier(name: name))
    }
}

#endif
