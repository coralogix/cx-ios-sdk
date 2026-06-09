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
    // CX-44687: sequence index of the active view within the current session.
    // Starts nil (omitted on events fired before any view appears). The first
    // appearance sets it to 0; subsequent name-differing appearances increment.
    // Persisted to Keychain so a same-session restore (in-process re-init where
    // SessionContext rolls back to the previous session via pid match) recovers
    // the counter rather than starting over.
    private var viewNumber: Int?

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
        // CX-44687: only restore view_number when the persisted PID matches the
        // current process — i.e. the SDK is being re-initialized in-process and
        // SessionContext will roll back to the previous session via pid match.
        // Ordering note: stored-property initializers run before CoralogixRum.init's
        // body, so SessionMetadata has not yet written getpid() to the keychain when
        // we read it here. On a fresh cold launch the keychain still holds the OLD
        // process's PID, which won't match getpid() — and we correctly skip the
        // restore so the first event of the new session doesn't carry a stale
        // counter (sessionEndedCallback does NOT fire on first-init: see
        // SessionManager.fireRotationCallbacks gating on priorExisted).
        let currentPid = String(getpid())
        let storedPid = keyChain?.readStringFromKeychain(service: Keys.service.rawValue,
                                                          key: Keys.pid.rawValue)
        if storedPid == currentPid,
           let persisted = keyChain?.readStringFromKeychain(service: Keys.service.rawValue,
                                                             key: Keys.keyViewNumber.rawValue),
           let value = Int(persisted) {
            self.viewNumber = value
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
                    // CX-44687: every name-differing appearance is a navigation step.
                    // First-ever: nil → 0. Subsequent: previous + 1. Revisits count
                    // as new steps per spec (A→B→C→A ⇒ 0,1,2,3).
                    self.viewNumber = (self.viewNumber ?? -1) + 1
                    self.persistViewNumber()
                }

                self.keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                                     key: Keys.view.rawValue,
                                                     value: view.name)
            }
            self.visibleView = cxView
        }
    }

    /// CX-44687: returns the current sequence index, or nil if no view has appeared yet
    /// (events fired before the first view must omit `view_number`).
    public func getViewNumber() -> Int? {
        return syncSafe { self.viewNumber }
    }

    private func persistViewNumber() {
        let value = self.viewNumber.map(String.init) ?? ""
        self.keyChain?.writeStringToKeychain(service: Keys.service.rawValue,
                                             key: Keys.keyViewNumber.rawValue,
                                             value: value)
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
                // CX-44687: the current view is view #0 of the new session.
                self.viewNumber = 0
            } else {
                self.viewNumber = nil
            }
            self.persistViewNumber()
        }
    }

    func shutdown() {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.visibleView = nil
            self.prevViewName = nil
            self.uniqueViewsPerSession.removeAll()
            self.viewNumber = nil
            self.persistViewNumber()
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
