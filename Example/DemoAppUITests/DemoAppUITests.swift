//
//  DemoAppUITests.swift
//  DemoAppUITests
//
//  Created by UI Test on 2024.
//

import XCTest

// Network interceptor for UI tests
class TestNetworkInterceptor: URLProtocol {
    static var capturedRequests: [(url: String, statusCode: Int)] = []
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Capture the request details
            let url = self.request.url?.absoluteString ?? "unknown"
            var statusCode = 0
            if let httpResponse = response as? HTTPURLResponse {
                statusCode = httpResponse.statusCode
            } else if error != nil {
                statusCode = -1 // Error
            }
            
            TestNetworkInterceptor.capturedRequests.append((url: url, statusCode: statusCode))
            
            // Forward the response to the original request
            if let client = self.client {
                if let response = response {
                    client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    client.urlProtocol(self, didLoad: data)
                }
                if let error = error {
                    client.urlProtocol(self, didFailWithError: error)
                } else {
                    client.urlProtocolDidFinishLoading(self)
                }
            }
        }
        task.resume()
    }
    
    override func stopLoading() {
        // Nothing to do here
    }
}

final class DemoAppUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Register the network interceptor
        URLProtocol.registerClass(TestNetworkInterceptor.self)
        
        // Initialize the app
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Clear captured requests
        TestNetworkInterceptor.capturedRequests.removeAll()
        
        // Unregister the network interceptor
        URLProtocol.unregisterClass(TestNetworkInterceptor.self)
        
        app = nil
    }
    
    func testClickClockButton() throws {
        // Clear any previous captured requests
        TestNetworkInterceptor.capturedRequests.removeAll()
        
        // Click the Clock button
        let clockButton = app.cells.containing(.staticText, identifier: "Clock").firstMatch
        clockButton.tap()
        
        // Wait for the new screen to load (Clock view controller)
        let timeLabel = app.staticTexts.firstMatch
        XCTAssertTrue(timeLabel.waitForExistence(timeout: 5), "Clock screen should load after tapping Clock button")
        
        // Wait a bit for any network requests to complete
        Thread.sleep(forTimeInterval: 5.0)
        
        // Check captured network requests
        print("📋 Captured Network Requests:")
        for request in TestNetworkInterceptor.capturedRequests {
            print("[\(request.statusCode)] \(request.url)")
        }
        
        // Verify that we captured some network requests
        XCTAssertTrue(!TestNetworkInterceptor.capturedRequests.isEmpty, "Should have captured some network requests")
        
        // Check that at least one request returned 200 status
        let successfulRequests = TestNetworkInterceptor.capturedRequests.filter { $0.statusCode == 200 }
        XCTAssertTrue(!successfulRequests.isEmpty, "Should have at least one request with 200 status code")
        
        print("✅ Successfully clicked the Clock button and verified network requests with 200 status!")
    }
}
