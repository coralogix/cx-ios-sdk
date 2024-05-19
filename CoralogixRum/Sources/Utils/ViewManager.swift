//
//  ViewManager.swift
//
//
//  Created by Coralogix DEV TEAM on 16/05/2024.
//

import Foundation

public struct ViewManager {
    private var viewStack: [CXView]
    var keyChain: KeyChainProtocol?
    var prevViewName: String?

    init(keyChain: KeyChainProtocol?) {
        self.viewStack = [CXView]()
        self.keyChain = keyChain
        if let viewName = keyChain?.readStringFromKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue) {
            self.prevViewName = viewName
        }
    }

    public mutating func add(view: CXView) {
        if view.identity == viewStack.last?.identity{
            return
        }
    
        viewStack.removeAll(where: { $0.identity == view.identity })
        viewStack.append(view)

        keyChain?.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue, value: view.name)
        Log.d("add view: \(view.name)")
    }

    public mutating func delete(identity: String) {
        guard identity == viewStack.last?.identity else {
            if let view = viewStack.first(where: { $0.identity == identity }) {
                Log.d("delete view: \(view.name)")
            }
            return viewStack.removeAll(where: { $0.identity == identity })
        }
        let view = viewStack.removeLast()
        Log.d("delete view: \(view.name)")
    }
    
    func getDictionary() -> [String: Any] {
        guard let view = viewStack.last else {
            return [String: Any]()
        }
        return [Keys.view.rawValue: view.name]
    }
    
    func getPrevDictionary() -> [String: Any] {
        guard let prevViewName = self.prevViewName else {
            return [String: Any]()
        }
        return [Keys.view.rawValue: prevViewName]
    }
}
