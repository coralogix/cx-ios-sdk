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
    
    private let queueKey = DispatchSpecificKey<Void>()
    private let syncQueue: DispatchQueue
    
    init(keyChain: KeyChainProtocol?) {
        self.keyChain = keyChain
        self.uniqueViewsPerSession = Set<String>()

        let queue = DispatchQueue(label: Keys.queueViewManagerQueue.rawValue, attributes: .concurrent)
        queue.setSpecific(key: queueKey, value: ())
        self.syncQueue = queue
        
        if let viewName = keyChain?.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue) {
            self.prevViewName = viewName
        }
    }
    
    public func isUniqueView(name: String) -> Bool {
        return syncSafe {
            !uniqueViewsPerSession.contains(name)
        }
    }
    
    public func getUniqueViewCount() -> Int {
        return syncSafe {
            uniqueViewsPerSession.count
        }
    }
    
    public func set(cxView: CXView?) {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let view = cxView {
                if self.visibleView?.name == view.name {
                    return
                }
                
                if view.state == .notifyOnAppear {
                    if self.isUniqueView(name: view.name) {
                        self.uniqueViewsPerSession.insert(view.name)
                    }
                }
                
                self.keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                                     key: Keys.view.rawValue,
                                                     value: view.name)
            }
            self.visibleView = cxView
        }
    }
    
    func getDictionary() -> [String: Any] {
        return syncSafe {
            guard let visibleView = self.visibleView else {
                return [Keys.view.rawValue: Keys.undefined.rawValue]
            }
            return [Keys.view.rawValue: visibleView.name]
        }
    }
    
    func getPrevDictionary() -> [String: Any] {
        return syncSafe {
            guard let prevViewName = self.prevViewName else {
                return [String: Any]()
            }
            return [Keys.view.rawValue: prevViewName]
        }
    }
    
    func reset() {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.uniqueViewsPerSession.removeAll()
            if let currentView = self.visibleView {
                self.uniqueViewsPerSession.insert(currentView.name)
            }
        }
    }
    
    func shutdown() {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.visibleView = nil
            self.prevViewName = nil
            self.uniqueViewsPerSession.removeAll()
        }
    }
    
    deinit {
        // ViewManager deallocated
    }
    
    func syncSafe<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return block()
        } else {
            return syncQueue.sync {
                block()
            }
        }
    }
}
