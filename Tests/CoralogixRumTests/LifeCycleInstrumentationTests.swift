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

    func testBackgroundNotificationTriggersFlush() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        let flushExpectation = expectation(description: "flush should complete on background")

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        coralogixRum?.flush { [weak self] in
            flushExpectation.fulfill()
        }

        wait(for: [flushExpectation], timeout: 5.0)
    }

    func testBackgroundNotificationEmitsLifeCycleSpan() {
        guard let options else {
            XCTFail("Options not initialized")
            return
        }

        coralogixRum = CoralogixRum(options: options)
        XCTAssertTrue(CoralogixRum.isInitialized)

        let spanExpectation = expectation(description: "lifecycle span should be emitted")
        var spanReceived = false

        NotificationCenter.default.addObserver(
            forName: Notification.Name.cxRumNotification,
            object: nil,
            queue: .main
        ) { _ in
            if !spanReceived {
                spanReceived = true
                spanExpectation.fulfill()
            }
        }

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        wait(for: [spanExpectation], timeout: 2.0)
    }
}
