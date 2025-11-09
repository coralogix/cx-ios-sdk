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

public struct CxMaskView: UIViewRepresentable {
    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.cxMask = true // from your existing UIKit extension
        view.backgroundColor = .clear
        return view
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {}
}

@available(iOS 13, tvOS 13, *)
public extension SwiftUI.View {
    func trackCXView(name: String) -> some View {
        return modifier(CXViewModifier(name: name))
    }
    
    func cxMask() -> some View {
        self.overlay(CxMaskView().allowsHitTesting(false))
    }
}

#endif
