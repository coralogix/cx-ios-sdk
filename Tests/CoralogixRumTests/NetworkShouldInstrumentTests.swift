import XCTest
import CoralogixInternal
@testable import Coralogix

final class NetworkShouldInstrumentTests: XCTestCase {
    private let tagged = URLRequest(url: URL(string: "https://api.example.com/internal-hop")!)
    private let untagged = URLRequest(url: URL(string: "https://api.example.com/users")!)

    private func makeOptions(shouldInstrumentNetworkRequest: ((URLRequest) -> Bool)? = nil) -> CoralogixExporterOptions {
        CoralogixExporterOptions(coralogixDomain: .US2,
                                 environment: "test",
                                 application: "TestApp",
                                 version: "1.0",
                                 publicKey: "token",
                                 shouldInstrumentNetworkRequest: shouldInstrumentNetworkRequest)
    }

    func testRejectedRequestIsNotInstrumented() {
        let options = makeOptions { $0.url?.path != "/internal-hop" }

        XCTAssertFalse(CoralogixRum.shouldInstrument(tagged, options: options))
        XCTAssertTrue(CoralogixRum.shouldInstrument(untagged, options: options))
    }

    func testEveryRequestIsInstrumentedWithoutTheOption() {
        XCTAssertTrue(CoralogixRum.shouldInstrument(tagged, options: makeOptions()))
        XCTAssertTrue(CoralogixRum.shouldInstrument(tagged, options: nil))
    }

    func testRejectedRequestStartsNoSpanAndGetsNoTraceHeaders() {
        let configuration = URLSessionInstrumentationConfiguration(
            shouldInstrument: { request in
                CoralogixRum.shouldInstrument(request, options: self.makeOptions { _ in false })
            },
            shouldInjectTracingHeaders: { _ in true }
        )
        let instrumentation = URLSessionInstrumentation(configuration: configuration)
        let taskId = UUID().uuidString

        let instrumented = URLSessionLogger.processAndLogRequest(tagged,
                                                                 sessionTaskId: taskId,
                                                                 instrumentation: instrumentation,
                                                                 shouldInjectHeaders: true)

        XCTAssertNil(instrumented, "A rejected request must be sent unchanged, without a traceparent")
        let span = URLSessionLogger.runningSpansQueue.sync { URLSessionLogger.runningSpans[taskId] }
        XCTAssertNil(span, "A rejected request must not start a network span")
    }
}
