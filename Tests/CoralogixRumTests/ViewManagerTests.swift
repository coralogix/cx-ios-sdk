//
//  ViewManagerTests.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class ViewManagerTests: XCTestCase {
    var mockKeyChain: MockKeyChain!
    var viewManager: ViewManager!
    
    override func setUpWithError() throws {
        mockKeyChain = MockKeyChain()
        viewManager = ViewManager(keyChain: mockKeyChain)
    }
    
    override func tearDownWithError() throws {
        mockKeyChain = nil
        viewManager = nil
    }
    
    func testAddView() {
        let view1 = CXView(state: .notifyOnAppear, name: "View1")
        viewManager.set(cxView: view1)
        
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View1")
        XCTAssertEqual(mockKeyChain.storage[Keys.view.rawValue], "View1")
        
        let view2 = CXView(state: .notifyOnAppear, name: "View2")
        viewManager.set(cxView: view2)
        
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View2")
        XCTAssertEqual(mockKeyChain.storage[Keys.view.rawValue], "View2")
    }
    
    func testDeleteView() {
        let view1 = CXView(state: .notifyOnAppear, name: "View1")
        let view2 = CXView(state: .notifyOnAppear,name: "View2")
        viewManager.set(cxView: view1)
        viewManager.set(cxView: view2)
        
        viewManager.set(cxView: view1)
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View1")
        
        viewManager.set(cxView: nil)
        let dict = viewManager.getDictionary()
        XCTAssertEqual(dict[Keys.view.rawValue] as? String, Keys.undefined.rawValue)
    }
    
    func testGetDictionary() {
        let view = CXView(state: .notifyOnAppear, name: "View1")
        viewManager.set(cxView: view)
        
        let dict = viewManager.getDictionary()
        XCTAssertEqual(dict[Keys.view.rawValue] as? String, "View1")
    }
    
    func testGetPrevDictionary() {
        mockKeyChain.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue, value: "PreviousView")
        viewManager = ViewManager(keyChain: mockKeyChain)
        
        let prevDict = viewManager.getPrevDictionary()
        XCTAssertEqual(prevDict[Keys.view.rawValue] as? String, "PreviousView")
    }
    
    func testGetPrevDictionary_emptyWhenNoPrevView() {
        let manager = ViewManager(keyChain: nil)
        XCTAssertTrue(manager.getPrevDictionary().isEmpty)
    }
    
    func testReset_clearsAndAddsCurrentVisibleView() {
        let manager = ViewManager(keyChain: nil)
        manager.set(cxView: CXView(state: .notifyOnAppear, name: "Home"))
        manager.set(cxView: CXView(state: .notifyOnAppear, name: "Profile"))
        
        XCTAssertEqual(manager.getUniqueViewCount(), 2)
        
        manager.reset()
        
        XCTAssertEqual(manager.getUniqueViewCount(), 1)
        XCTAssertFalse(manager.isUniqueView(name: "Profile"))
    }
    
    func testShutdown_resetsAllFields() {
        let manager = ViewManager(keyChain: nil)
        manager.set(cxView: CXView(state: .notifyOnAppear, name: "Notifications"))
        manager.shutdown()
        
        XCTAssertNil(manager.visibleView)
        XCTAssertNil(manager.prevViewName)
        XCTAssertEqual(manager.getUniqueViewCount(), 0)
    }
    
    func testSet_doesNotDuplicateSameView() {
        let mockKeychain = MockKeyChain()
        let manager = ViewManager(keyChain: mockKeychain)

        let view = CXView(state: .notifyOnAppear, name: "Dashboard")
        manager.set(cxView: view)
        manager.set(cxView: view)  // setting same view again
        
        XCTAssertEqual(manager.getUniqueViewCount(), 1)
        XCTAssertEqual(mockKeychain.readStringFromKeychain(service: "service", key: "view"), "Dashboard")
    }
}

class MockKeyChain: KeyChainProtocol {
    var storage: [String: String] = [:]
    
    func readStringFromKeychain(service: String, key: String) -> String? {
        return storage[key]
    }
    
    func writeStringToKeychain(service: String, key: String, value: String) {
        storage[key] = value
    }
}
