//
//  SwiftUIViewModifier.swift
//
//
//  Created by Coralogix DEV TEAM on 15/05/2024.
//

#if canImport(SwiftUI)
import SwiftUI

public protocol SwiftUIViewHandler {
    func notifyOnAppear(identity: String, name: String)
    func notifyOnDisappear(identity: String)
}

@available(iOS 13, tvOS 13, *)
public struct CXViewModifier: SwiftUI.ViewModifier {
    let identity: String = UUID().uuidString
    let name: String
    var viewsHandler: SwiftUIViewHandler?
    
    init(name: String, viewsHandler: SwiftUIViewHandler? = nil) {
        self.name = name
        self.viewsHandler = viewsHandler
    }
    
    public func body(content: Content) -> some View {
        content.onAppear {
            self.viewsHandler?.notifyOnAppear(identity: identity, name: name)
        }
        .onDisappear {
            self.viewsHandler?.notifyOnDisappear(identity: identity)
        }
    }
}

@available(iOS 13, tvOS 13, *)
public extension SwiftUI.View {
    public func trackCXView(name: String, viewsHandler: SwiftUIViewHandler?) -> some View {
        return modifier(CXViewModifier(name: name, viewsHandler: viewsHandler))
    }
}

#endif

