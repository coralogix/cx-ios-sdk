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

    // MARK: - CX-44687: view_number sequence

    func testViewNumber_isNilBeforeAnyView() {
        XCTAssertNil(viewManager.getViewNumber(),
                     "view_number must be nil until the first view appears")
    }

    func testViewNumber_firstAppearance_isZero() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "Home"))
        XCTAssertEqual(viewManager.getViewNumber(), 0)
    }

    func testViewNumber_increments_onDifferentName() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "B"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "C"))
        XCTAssertEqual(viewManager.getViewNumber(), 2)
    }

    func testViewNumber_revisitCountsAsNewStep() {
        // Spec example: A → B → C → A ⇒ 0, 1, 2, 3 (revisits MUST increment).
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "B"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "C"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        XCTAssertEqual(viewManager.getViewNumber(), 3)
    }

    func testViewNumber_doesNotIncrement_onSameName() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))  // duplicate
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        XCTAssertEqual(viewManager.getViewNumber(), 0,
                       "setting the same view repeatedly must not bump the counter")
    }

    func testViewNumber_persistsToKeychainOnEveryIncrement() {
        // Verify persistence end-to-end: after a sequence of appearances, a fresh
        // ViewManager built from the same keychain must restore the latest counter.
        // We avoid reading the mock dict directly because that race-conditions with
        // the syncQueue barrier writes — the production restore path goes through
        // `readStringFromKeychain` and is what we actually ship.
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "B"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "C"))
        // Sync-flush via the production read path before we hand the keychain to a
        // restored instance — guarantees the barrier writes are complete.
        XCTAssertEqual(viewManager.getViewNumber(), 2)

        let restored = ViewManager(keyChain: mockKeyChain)
        XCTAssertEqual(restored.getViewNumber(), 2,
                       "every increment must be persisted; a fresh ViewManager built from the same keychain restores the latest value")
    }

    func testViewNumber_restoresFromKeychainOnInit() {
        mockKeyChain.writeStringToKeychain(service: Keys.service.rawValue,
                                            key: Keys.keyViewNumber.rawValue,
                                            value: "7")
        let restored = ViewManager(keyChain: mockKeyChain)
        XCTAssertEqual(restored.getViewNumber(), 7,
                       "ViewManager init must restore view_number from keychain so a same-session restore keeps the sequence intact")
    }

    func testViewNumber_initWithoutPersistedValue_isNil() {
        let fresh = ViewManager(keyChain: MockKeyChain())
        XCTAssertNil(fresh.getViewNumber())
    }

    func testViewNumber_reset_withVisibleView_setsToZero() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "B"))
        XCTAssertEqual(viewManager.getViewNumber(), 1)

        viewManager.reset()
        XCTAssertEqual(viewManager.getViewNumber(), 0,
                       "the current view is view #0 of the new session after rotation")
        // End-to-end persistence check: a restored ViewManager sees view #0.
        let restored = ViewManager(keyChain: mockKeyChain)
        XCTAssertEqual(restored.getViewNumber(), 0,
                       "reset must persist the new counter so a same-process restore reflects the rotation")
    }

    func testViewNumber_reset_withoutVisibleView_clearsToNil() {
        // No view ever set → reset should leave the counter nil and clear the keychain entry.
        mockKeyChain.writeStringToKeychain(service: Keys.service.rawValue,
                                            key: Keys.keyViewNumber.rawValue,
                                            value: "5")
        let manager = ViewManager(keyChain: mockKeyChain)
        XCTAssertEqual(manager.getViewNumber(), 5)

        manager.reset()
        XCTAssertNil(manager.getViewNumber())
        // End-to-end: a restored ViewManager sees nil (the persisted "" parses to nil).
        let restored = ViewManager(keyChain: mockKeyChain)
        XCTAssertNil(restored.getViewNumber(),
                     "reset with no visible view must clear the persisted counter")
    }

    func testViewNumber_shutdown_clears() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "Home"))
        XCTAssertEqual(viewManager.getViewNumber(), 0)

        viewManager.shutdown()
        XCTAssertNil(viewManager.getViewNumber())
        // End-to-end persistence check.
        let restored = ViewManager(keyChain: mockKeyChain)
        XCTAssertNil(restored.getViewNumber(),
                     "shutdown must clear the persisted counter")
    }

    func testViewNumber_disappearEvent_doesNotIncrement() {
        viewManager.set(cxView: CXView(state: .notifyOnAppear, name: "A"))
        XCTAssertEqual(viewManager.getViewNumber(), 0)

        // notifyOnDisappear-state events must NOT bump the counter — only appearances do.
        // Use a different name to bypass the same-name early-return so we exercise the
        // state check rather than coincidentally passing on the name guard.
        viewManager.set(cxView: CXView(state: .notifyOnDisappear, name: "B"))
        XCTAssertEqual(viewManager.getViewNumber(), 0)
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
