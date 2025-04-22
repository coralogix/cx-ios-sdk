//
//  ViewManager.swift
//
//
//  Created by Coralogix DEV TEAM on 16/05/2024.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoralogixInternal

public class ViewManager {
    var keyChain: KeyChainProtocol?
    var prevViewName: String?
    var visibleView: CXView?
    var uniqueViewsPerSession: Set<String>
    
    init(keyChain: KeyChainProtocol?) {
        self.keyChain = keyChain
        if let viewName = keyChain?.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue) {
            self.prevViewName = viewName
        }
        self.uniqueViewsPerSession = Set<String>()
    }
    
    public func isUniqueView(name: String) -> Bool {
        return !uniqueViewsPerSession.contains(name)
    }
    
    public func getUniqueViewCount() -> Int {
        return uniqueViewsPerSession.count
    }
    
    public func set(cxView: CXView?) {
        if let view = cxView {
            if visibleView?.name == view.name {
                return
            }
            
            if view.state == .notifyOnAppear {
                if self.isUniqueView(name: view.name) {
                    uniqueViewsPerSession.insert(view.name)
                }
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
    
    func reset() {
        self.uniqueViewsPerSession.removeAll()
    }
    
    func shutdown() {
        self.visibleView = nil
        self.prevViewName = nil
        self.uniqueViewsPerSession.removeAll()
    }
    
    deinit {
        Log.d("deinint ViewManager")
    }
}
