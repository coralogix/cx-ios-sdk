//
//  UserContextTest.swift
//
//
//  Created by Coralogix DEV TEAM on 06/05/2024.
//

import XCTest
@testable import CoralogixRum

final class UserContextTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testGetDictionary() {
        // 1. Setup: Create an instance of UserContext
        let userId = "123"
        let userName = "John Doe"
        let userEmail = "john.doe@example.com"
        let userMetadata = ["role": "admin", "department": "engineering"]
        
        let userContext = UserContext(userId: userId, userName: userName, userEmail: userEmail, userMetadata: userMetadata)
        
        // 2. Action: Call the method to test
        let dictionary = userContext.getDictionary()
        
        // 3. Assertion: Check the result is as expected
        XCTAssertEqual(dictionary[Keys.userId.rawValue] as? String, userId, "The userId should be correctly set in the dictionary.")
        XCTAssertEqual(dictionary[Keys.userName.rawValue] as? String, userName, "The userName should be correctly set in the dictionary.")
        XCTAssertEqual(dictionary[Keys.userEmail.rawValue] as? String, userEmail, "The userEmail should be correctly set in the dictionary.")
        XCTAssertEqual(dictionary[Keys.userMetadata.rawValue] as? [String: String], userMetadata, "The userMetadata should be correctly set in the dictionary.")
    }
}
