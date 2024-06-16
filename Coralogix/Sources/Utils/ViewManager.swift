//
//  ViewManager.swift
//
//
//  Created by Coralogix DEV TEAM on 16/05/2024.
//

import Foundation
import UIKit

public struct ViewManager {
    var keyChain: KeyChainProtocol?
    var prevViewName: String?
    var visibleView: CXView?

    init(keyChain: KeyChainProtocol?) {
        self.keyChain = keyChain
        if let viewName = keyChain?.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue) {
            self.prevViewName = viewName
        }
    }

    public mutating func set(cxView: CXView?) {

        if let view = cxView {
            if visibleView?.name == view.name {
                return
            }
            
            if view.state == .notifyOnAppear {
                Log.d("view: \(view.name) state: \(view.state.rawValue)")
            }
            keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                            key: Keys.view.rawValue,
                                            value: view.name)
        }
        self.visibleView = cxView
    }
    
    func getDictionary() -> [String: Any] {
        guard let visibleView = self.visibleView else {
            return [String: Any]()
        }
        return [Keys.view.rawValue: visibleView.name]
    }
    
    func getPrevDictionary() -> [String: Any] {
        guard let prevViewName = self.prevViewName else {
            return [String: Any]()
        }
        return [Keys.view.rawValue: prevViewName]
    }
}

extension CoralogixRum {
    public func initializeViewInstrumentation() {
        UIViewController.performSwizzling()
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotification(notification:)), name: .cxRumNotification, object: nil)
    }
    
    @objc func handleNotification(notification: Notification) {
        if let cxView = notification.object as? CXView {
            self.coralogixExporter.set(cxView: cxView)
        } else {
            Log.d("Notification received with no object or with a different object type")
        }
    }
}

extension Notification.Name {
    static let cxRumNotification = Notification.Name("cxRumNotification")
}
