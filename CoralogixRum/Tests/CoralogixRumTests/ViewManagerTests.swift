//
//  ViewManagerTests.swift
//
//
//  Created by Coralogix DEV TEAM on 19/05/2024.
//

import XCTest
@testable import CoralogixRum


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
        let view1 = CXView(identity: "1", name: "View1")
        viewManager.add(view: view1)
        
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View1")
        XCTAssertEqual(mockKeyChain.storage[Keys.view.rawValue], "View1")
        
        let view2 = CXView(identity: "2", name: "View2")
        viewManager.add(view: view2)
        
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View2")
        XCTAssertEqual(mockKeyChain.storage[Keys.view.rawValue], "View2")
    }
    
    func testDeleteView() {
        let view1 = CXView(identity: "1", name: "View1")
        let view2 = CXView(identity: "2", name: "View2")
        viewManager.add(view: view1)
        viewManager.add(view: view2)
        
        viewManager.delete(identity: "2")
        XCTAssertEqual(viewManager.getDictionary()[Keys.view.rawValue] as? String, "View1")
        
        viewManager.delete(identity: "1")
        XCTAssertTrue(viewManager.getDictionary().isEmpty)
    }
    
    func testGetDictionary() {
        let view = CXView(identity: "1", name: "View1")
        viewManager.add(view: view)
        
        let dict = viewManager.getDictionary()
        XCTAssertEqual(dict[Keys.view.rawValue] as? String, "View1")
    }
    
    func testGetPrevDictionary() {
        mockKeyChain.writeStringToKeychain(service: Keys.service.rawValue, key: Keys.view.rawValue, value: "PreviousView")
        viewManager = ViewManager(keyChain: mockKeyChain)
        
        let prevDict = viewManager.getPrevDictionary()
        XCTAssertEqual(prevDict[Keys.view.rawValue] as? String, "PreviousView")
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
