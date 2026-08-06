import XCTest
import CoralogixInternal
@testable import Coralogix

final class LifeCycleInstrumentationTests: XCTestCase {
    var options: CoralogixExporterOptions?
    var coralogixRum: CoralogixRum?

    override func setUpWithError() throws {
        options = CoralogixExporterOptions(
            coralogixDomain: CoralogixDomain.US2,
            userContext: nil,
            environment: "TEST",
            application: "TestApp-iOS",
            version: "1.0",
            publicKey: "test-token",
            ignoreUrls: [],
            ignoreErrors: [],
            labels: [:],
            sessionSampleRate: 100,
            debug: false
        )
    }

    override func tearDownWithError() throws {
        coralogixRum?.shutdown()
        coralogixRum = nil
        options = nil
        CoralogixRum.isInitialized = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testFlushMethodCanBeCalled() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        let flushExpectation = expectation(description: "flush should complete")

        coralogixRum?.flush {
            flushExpectation.fulfill()
        }

        wait(for: [flushExpectation], timeout: 10.0)
    }

    func testLifeCycleInstrumentationDoesNotCrash() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        coralogixRum?.log(severity: .info, message: "test log")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
        }

        let backgroundFlushExpectation = expectation(description: "background should not crash")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            backgroundFlushExpectation.fulfill()
        }

        wait(for: [backgroundFlushExpectation], timeout: 5.0)
    }
}
