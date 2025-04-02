import XCTest
@testable import Coralogix

final class CoralogixRumTests: XCTestCase {
    var options: CoralogixExporterOptions?
    
    override func setUpWithError() throws {
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 100,
                                           debug: true)
    }
    
    override func tearDownWithError() throws {
        options = nil
    }
    
    func testInit() {
        let coralogixRum = CoralogixRum(options: options!)
        if let options = coralogixRum.coralogixExporter?.getOptions() {
            
            // Verify that options are set correctly
            XCTAssertEqual(options.application, "TestApp-iOS")
            XCTAssertEqual(options.version, "1.0")
            
            // Verify that isDebug flag is set correctly
            XCTAssertTrue(CoralogixRum.isDebug)
            
            // Verify that isInitialized flag is set to true
            XCTAssertTrue(CoralogixRum.isInitialized)
        }
    }
    
    func testInitSamplerOff() {
        CoralogixRum.isInitialized = false
        options = CoralogixExporterOptions(coralogixDomain: CoralogixDomain.US2,
                                           userContext: nil,
                                           environment: "PROD",
                                           application: "TestApp-iOS",
                                           version: "1.0",
                                           publicKey: "token",
                                           ignoreUrls: [], //[".*\\.il$", "https://www.coralogix.com/academy"],
                                           ignoreErrors: [], //[".*errorcode=.*", "Im cusom Error"],
                                           labels: ["item" : "banana", "itemPrice" : 1000],
                                           sampleRate: 0,
                                           debug: true)
        _ = CoralogixRum(options: options!)
        XCTAssertFalse(CoralogixRum.isInitialized)
    }
    
    // Test setUserContext method
    func testSetUserContext() {
        let coralogixRum = CoralogixRum(options: options!)
            let userContext = UserContext(userId: "1234",
                                          userName: "Daffy Duck",
                                          userEmail: "daffy.duck@coralogix.com",
                                          userMetadata: ["age": "18", "profession" : "duck"])
            coralogixRum.setUserContext(userContext: userContext)
            
        if let options = coralogixRum.coralogixExporter?.getOptions() {
            
            // Verify that userContext is set correctly
            XCTAssertEqual(options.userContext, userContext)
        }

    }
    
    func testSetLabels() {
        let coralogixRum = CoralogixRum(options: options!)
        if let labels = coralogixRum.coralogixExporter?.getOptions().labels {
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels["item"] as? String, "banana")
            XCTAssertEqual(labels["itemPrice"] as? Int, 1000)
        }
        
        let newLabel = ["device": "iphone"]
        coralogixRum.setLabels(labels: newLabel)
        if let labels = coralogixRum.coralogixExporter?.getOptions().labels {
            XCTAssertEqual(labels.count, 1)
            XCTAssertEqual(labels["device"] as? String, "iphone")
        }
    }
    
    func testShutdown() {
        let coralogixRum = CoralogixRum(options: options!)
        coralogixRum.shutdown()
        XCTAssertFalse(CoralogixRum.isInitialized)
    }
}

class CoralogixExporterOptionsTests: XCTestCase {
    
    // Test initialization with required parameters
    func testInit() {
        // Arrange
        let coralogixDomain = CoralogixDomain.US2 // Example domain
        let userContext = UserContext(userId: "1234",
                                      userName: "Daffy Duck",
                                      userEmail: "daffy.duck@coralogix.com",
                                      userMetadata: ["age": "18", "profession" : "duck"]) 
        let environment = "development"
        let application = "TestApp"
        let version = "1.0"
        let publicKey = "publicKey"
        
        // Act
        let options = CoralogixExporterOptions(
            coralogixDomain: coralogixDomain,
            userContext: userContext,
            environment: environment,
            application: application,
            version: version,
            publicKey: publicKey
        )
        
        // Assert
        XCTAssertEqual(options.coralogixDomain, coralogixDomain)
        XCTAssertEqual(options.userContext, userContext)
        XCTAssertEqual(options.environment, environment)
        XCTAssertEqual(options.application, application)
        XCTAssertEqual(options.version, version)
        XCTAssertEqual(options.publicKey, publicKey)
    }
}
