//
//  WindowProvider.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 22/05/2025.
//

public protocol KeyWindowProvider {
    static func getKeyWindow() -> UIWindow?
}

public class WindowProvider: KeyWindowProvider {
    static func getKeyWindow() -> UIWindow? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return nil
        }
        return windowScene.windows.first(where: { $0.isKeyWindow })
    }
}
