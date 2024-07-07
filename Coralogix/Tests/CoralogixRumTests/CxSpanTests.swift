//
//  CxSpanTests.swift
//
//
//  Created by Coralogix DEV TEAM on 08/05/2024.
//

import XCTest
import Foundation

@testable import Coralogix

final class CxSpanTests: XCTestCase {
    var mockSpanData: SpanDataProtocol!
    var mockVersionMetadata: VersionMetadata!
    var mockSessionManager: SessionManager!
    var mockNetworkManager: NetworkManager!
    var mockViewManager: ViewManager!
    
    override func setUpWithError() throws {
        mockSpanData = MockSpanData(attributes: [Keys.severity.rawValue: AttributeValue("3"),
                                                 Keys.eventType.rawValue: AttributeValue("log"),
                                                 Keys.source.rawValue: AttributeValue("console"),
                                                 Keys.environment.rawValue: AttributeValue("prod"),
                                                 Keys.userId.rawValue: AttributeValue("12345"),
                                                 Keys.userName.rawValue: AttributeValue("John Doe"),
                                                 Keys.userEmail.rawValue: AttributeValue("john.doe@example.com")],
                                    startTime: Date(), spanId: "20", traceId: "30")
        mockVersionMetadata = VersionMetadata(appName: "ExampleApp", appVersion: "1.1.1")
        mockSessionManager = SessionManager()
        mockNetworkManager = NetworkManager()
        mockViewManager = ViewManager(keyChain: KeychainManager())
    }
    
    override func tearDownWithError() throws {
        mockSpanData = nil
        mockVersionMetadata = nil
        mockSessionManager = nil
        mockNetworkManager = nil
    }
    
    func testInitialization() {
        let cxSpan = CxSpan(otel: mockSpanData,
                            versionMetadata: mockVersionMetadata,
                            sessionManager: mockSessionManager, 
                            networkManager: mockNetworkManager,
                            viewManager: mockViewManager,
                            userMetadata: nil,
                            labels: nil)
        
        XCTAssertEqual(cxSpan.applicationName, "ExampleApp")
        XCTAssertNotNil(cxSpan.versionMetadata)
        XCTAssertEqual(cxSpan.subsystemName, Keys.cxRum.rawValue)
        XCTAssertEqual(cxSpan.severity, 3)
        XCTAssertNotNil(cxSpan.timeStamp)
        XCTAssertNotNil(cxSpan.cxRum)
    }
    
    func testGetDictionary() {
        let cxSpan = CxSpan(otel: mockSpanData,
                            versionMetadata: mockVersionMetadata,
                            sessionManager: mockSessionManager, 
                            networkManager: mockNetworkManager,
                            viewManager: mockViewManager,
                            userMetadata: nil,
                            labels: nil)
        
        let dictionary = cxSpan.getDictionary()
        
        XCTAssertEqual(dictionary[Keys.applicationName.rawValue] as? String, "ExampleApp")
        if let metaData = dictionary[Keys.versionMetaData.rawValue] as? [[String: String]] {
            if let appName = metaData.first {
                XCTAssertEqual(appName[Keys.appName.rawValue], "ExampleApp")
            }
            if let appVersion = metaData.last {
                XCTAssertEqual(appVersion[Keys.appVersion.rawValue], "1.1.1")
            }
        }
        XCTAssertEqual(cxSpan.subsystemName, Keys.cxRum.rawValue)
        XCTAssertNotNil(cxSpan.timeStamp)
        if let text = dictionary[Keys.text.rawValue] as? [String: Any],
           let cxRum = text[Keys.cxRum.rawValue] as? [String: Any] {
            
            if let mobileSdk = cxRum[Keys.mobileSdk.rawValue] as? [String: Any] {
                XCTAssertEqual(mobileSdk[Keys.operatingSystem.rawValue] as? String, Keys.ios.rawValue)
                XCTAssertEqual(mobileSdk[Keys.sdkVersion.rawValue] as? String, Global.sdk.rawValue)
                XCTAssertEqual(mobileSdk[Keys.framework.rawValue] as? String, Keys.swift.rawValue)
            }
            
            if let deviceState = cxRum[Keys.deviceState.rawValue] as? [String: Any] {
                if let networkConnectionType = deviceState[Keys.networkConnectionType.rawValue] as? String {
                    XCTAssertEqual(networkConnectionType, "")
                }
                
                if let networkConnectionSubtype = deviceState[Keys.networkConnectionSubtype.rawValue] as? String {
                    XCTAssertEqual(networkConnectionSubtype, "")
                }
                
                if let battery = deviceState[Keys.battery.rawValue] as? String {
                    XCTAssertEqual(battery, "-1.0")
                }
                
                if let networkType = deviceState[Keys.networkType.rawValue] as? String {
                    XCTAssertEqual(networkType, "No connection or unknown type")
                }
            }
            
            if let sessionContext = cxRum[Keys.sessionContext.rawValue] as? [String: Any] {
                XCTAssertEqual(sessionContext[Keys.operatingSystem.rawValue] as? String, Global.getOs())
                XCTAssertNotNil(sessionContext[Keys.sessionCreationDate.rawValue])
                XCTAssertNotNil(sessionContext[Keys.sessionId.rawValue])
                XCTAssertEqual(sessionContext[Keys.userEmail.rawValue] as? String, "john.doe@example.com")
                XCTAssertEqual(sessionContext[Keys.userName.rawValue] as? String, "John Doe")
                XCTAssertEqual(sessionContext[Keys.userId.rawValue] as? String, "12345")
                XCTAssertEqual(sessionContext[Keys.osVersion.rawValue] as? String, Global.osVersionInfo())
                XCTAssertEqual(sessionContext[Keys.device.rawValue] as? String, Global.getDeviceModel())
            }
            
            XCTAssertEqual(cxRum[Keys.spanId.rawValue] as? String, "20")
            XCTAssertEqual(cxRum[Keys.traceId.rawValue] as? String, "30")
            XCTAssertNotNil(cxRum[Keys.timestamp.rawValue])
            XCTAssertEqual(cxRum[Keys.environment.rawValue] as? String, "prod")
            XCTAssertEqual(cxRum[Keys.platform.rawValue] as? String, Keys.mobile.rawValue)
            
            
            if let eventContext = cxRum[Keys.eventContext.rawValue] as? [String: Any] {
                XCTAssertEqual(eventContext[Keys.type.rawValue] as? String, "log")
                XCTAssertEqual(eventContext[Keys.source.rawValue] as? String, Keys.console.rawValue)
                XCTAssertEqual(eventContext[Keys.severity.rawValue] as? Int, 3)
            }
            
            if let versionMetaData =  cxRum[Keys.versionMetaData.rawValue] as? [String: Any] {
                XCTAssertEqual(versionMetaData[Keys.appName.rawValue] as? String, "ExampleApp")
                XCTAssertEqual(versionMetaData[Keys.appVersion.rawValue] as? String, "1.1.1")
            }
            
            if let logContext = cxRum[Keys.logContext.rawValue] as? [String: Any] {
                XCTAssertEqual(logContext[Keys.message.rawValue] as? String, "")
            }
        }
        XCTAssertEqual(dictionary[Keys.subsystemName.rawValue] as? String, Keys.cxRum.rawValue)
        XCTAssertEqual(dictionary[Keys.severity.rawValue] as? Int, 3)
        XCTAssertNotNil(dictionary[Keys.timestamp.rawValue])
    }
}

class VersionMetadataTests: XCTestCase {
    func testGetDictionary() {
        // Setup
        let versionMetadata = VersionMetadata(appName: "TestApp", appVersion: "1.0")
        
        // Execution
        let dictionary = versionMetadata.getDictionary()
        
        // Verification
        XCTAssertEqual(dictionary[Keys.appName.rawValue] as? String, "TestApp", "The appName should be correctly set in the dictionary.")
        XCTAssertEqual(dictionary[Keys.appVersion.rawValue] as? String, "1.0", "The appVersion should be correctly set in the dictionary.")
    }
}

class SessionMetadataTests: XCTestCase {
    func testSessionMetadataInitializationNoPrevSession() {
        let mockKeyschainManager = MockKeyschainManager()
        let metadata = SessionMetadata(sessionId: "sessionId123", sessionCreationDate: 1622505600, keychain: mockKeyschainManager)
        XCTAssertEqual(metadata.sessionId, "sessionId123")
        XCTAssertEqual(metadata.sessionCreationDate, 1622505600)
    }
    
    func testSessionMetadataInitializationWithPrevSession() {
        let pidStr = String(getpid())
        let timeInterval = Date().timeIntervalSince1970
        let mockKeyschainManager = MockKeyschainManager()
        mockKeyschainManager.writeStringToKeychain(service: "com.coralogix.sdk", key: "pid", value: pidStr)
        mockKeyschainManager.writeStringToKeychain(service: "com.coralogix.sdk", key: "sessionId", value: "session12345")
        mockKeyschainManager.writeStringToKeychain(service: "com.coralogix.sdk", key: "sessionTimeInterval", value: String(timeInterval))

        let metadata = SessionMetadata(sessionId: "sessionId123", sessionCreationDate: 1622505600, keychain: mockKeyschainManager)

        XCTAssertEqual(metadata.sessionId, "sessionId123")
        XCTAssertEqual(metadata.sessionCreationDate, 1622505600)
        XCTAssertEqual(metadata.oldPid, pidStr)
        XCTAssertEqual(metadata.oldSessionId, "session12345")
        XCTAssertEqual(metadata.oldSessionTimeInterval, timeInterval)
    }

    func testResetSessionMetadata() {
        let mockKeyschainManager = MockKeyschainManager()
        var metadata = SessionMetadata(sessionId: "sessionId123", sessionCreationDate: 1622505600, keychain: mockKeyschainManager)
        metadata.resetSessionMetadata()

        XCTAssertEqual(metadata.sessionId, "")
        XCTAssertEqual(metadata.sessionCreationDate, 0)
    }
}
