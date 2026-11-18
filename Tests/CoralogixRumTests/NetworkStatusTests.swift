//
//  NetworkStatusTests.swift
//  CoralogixRumTests
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import XCTest
@testable import Coralogix

private struct StubNetworkMonitor: NetworkMonitorProtocol {
    let connection: Connection
    func getConnection() -> Connection { connection }
}

final class NetworkStatusTests: XCTestCase {

    private func statusOffMain(_ connection: Connection) -> (String, String?, Any?) {
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: connection))
        var result: (String, String?, Any?) = ("not-called", nil, nil)
        let done = expectation(description: "status() returned off the main thread")
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            result = sut.status()
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return result
    }

    func test_status_offMainThread_reportsWifi() {
        let (type, subtype, carrier) = statusOffMain(.wifi)
        XCTAssertEqual(type, "wifi")
        XCTAssertNil(subtype)
        XCTAssertNil(carrier)
    }

    func test_status_offMainThread_reportsUnavailable() {
        let (type, _, _) = statusOffMain(.unavailable)
        XCTAssertEqual(type, "unavailable")
    }

    // The simulator has no telephony info, so a cellular connection reports an unknown radio.
    func test_status_offMainThread_reportsCellular() {
        let (type, subtype, carrier) = statusOffMain(.cellular)
        XCTAssertEqual(type, "cell")
        XCTAssertEqual(subtype, "unknown")
        XCTAssertNil(carrier)
    }

    func test_status_onMainThread_reportsWifi() {
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .wifi))
        XCTAssertEqual(sut.status().0, "wifi")
    }

    func test_status_concurrentCallers_allReportTheMonitorValue() {
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular))
        let lock = NSLock()
        var types: [String] = []
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            let type = sut.status().0
            lock.lock(); types.append(type); lock.unlock()
        }
        XCTAssertEqual(types.count, 64)
        XCTAssertEqual(Set(types), ["cell"])
    }
}
#endif
