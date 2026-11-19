//
//  NetworkStatusTests.swift
//  CoralogixRumTests
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreTelephony
import XCTest
@testable import Coralogix

private struct StubNetworkMonitor: NetworkMonitorProtocol {
    let connection: Connection
    func getConnection() -> Connection { connection }
}

// Stands in for the device's telephony info, which the simulator does not provide. Its reads
// record how many run at once, so a test can see whether CoreTelephony is read concurrently.
private final class StubTelephonyInfo: CTTelephonyNetworkInfo {
    private let lock = NSLock()
    private var _serviceId: String?
    private var _radioTech: [String: String]?
    private var activeReads = 0
    private(set) var maxConcurrentReads = 0
    private(set) var totalReads = 0
    // Before iOS 16 status() reports a radio only when the data service has a carrier.
    let carrier = CTCarrier()

    init(serviceId: String?, radioTech: [String: String]?) {
        _serviceId = serviceId
        _radioTech = radioTech
        super.init()
    }

    func set(serviceId: String?, radioTech: [String: String]?) {
        lock.lock(); defer { lock.unlock() }
        _serviceId = serviceId
        _radioTech = radioTech
    }

    override var dataServiceIdentifier: String? { read { _serviceId } }
    override var serviceCurrentRadioAccessTechnology: [String: String]? { read { _radioTech } }
    override var serviceSubscriberCellularProviders: [String: CTCarrier]? {
        read { _serviceId.map { [$0: carrier] } }
    }

    private func read<T>(_ value: () -> T) -> T {
        lock.lock()
        activeReads += 1
        totalReads += 1
        maxConcurrentReads = max(maxConcurrentReads, activeReads)
        lock.unlock()
        usleep(200)
        lock.lock(); defer { activeReads -= 1; lock.unlock() }
        return value()
    }
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

    func test_status_cellular_reportsRadioTechnologyOfTheDataService() {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyLTE,
                                                 "0000000100000002": CTRadioAccessTechnologyEdge])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        let (type, subtype, _) = sut.status()
        XCTAssertEqual(type, "cell")
        XCTAssertEqual(subtype, "LTE")
    }

    func test_status_cellular_reportsTheCarrierOnlyBeforeiOS16() {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyLTE])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        let carrier = sut.status().2 as? CTCarrier
        if #available(iOS 16.0, *) {
            XCTAssertNil(carrier)
        } else {
            XCTAssertTrue(carrier === info.carrier)
        }
    }

    func test_status_cellular_offMainThread_reportsRadioTechnology() {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyNR])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        var subtype: String?
        let done = expectation(description: "status() returned off the main thread")
        DispatchQueue.global().async {
            subtype = sut.status().1
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(subtype, "NR")
    }

    func test_status_cellular_followsTelephonyDelegateUpdates() throws {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyLTE])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        XCTAssertEqual(sut.status().1, "LTE")

        info.set(serviceId: "0000000100000002",
                 radioTech: ["0000000100000002": CTRadioAccessTechnologyEdge])
        let delegate = try XCTUnwrap(info.delegate)
        delegate.dataServiceIdentifierDidChange?("0000000100000002")

        XCTAssertEqual(sut.status().1, "EDGE")
    }

    func test_status_cellular_followsRadioTechnologyChangeNotification() {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyLTE])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        XCTAssertEqual(sut.status().1, "LTE")

        info.set(serviceId: "0000000100000001",
                 radioTech: ["0000000100000001": CTRadioAccessTechnologyNR])
        NotificationCenter.default.post(name: .CTServiceRadioAccessTechnologyDidChange,
                                        object: "0000000100000001")

        XCTAssertEqual(sut.status().1, "NR")
    }

    // A data-SIM switch fires the delegate and the radio notification together, off our queues.
    func test_refresh_concurrentDelegateCallbacks_neverReadTelephonyInfoConcurrently() throws {
        let info = StubTelephonyInfo(serviceId: "0000000100000001",
                                     radioTech: ["0000000100000001": CTRadioAccessTechnologyLTE])
        let sut = NetworkStatusClass(with: StubNetworkMonitor(connection: .cellular), networkInfo: info)
        let delegate = try XCTUnwrap(info.delegate)
        let readsBefore = info.totalReads
        let lock = NSLock()
        var subtypes: [String?] = []
        var refreshes = 0

        DispatchQueue.concurrentPerform(iterations: 64) { i in
            switch i % 3 {
            case 0:
                delegate.dataServiceIdentifierDidChange?("0000000100000001")
                lock.lock(); refreshes += 1; lock.unlock()
            case 1:
                NotificationCenter.default.post(name: .CTServiceRadioAccessTechnologyDidChange,
                                                object: "0000000100000001")
                lock.lock(); refreshes += 1; lock.unlock()
            default:
                let subtype = sut.status().1
                lock.lock(); subtypes.append(subtype); lock.unlock()
            }
        }

        // Every callback refreshed: two reads each, plus the carrier read before iOS 16.
        let readsPerRefresh: Int
        if #available(iOS 16.0, *) { readsPerRefresh = 2 } else { readsPerRefresh = 3 }
        XCTAssertEqual(info.totalReads - readsBefore, refreshes * readsPerRefresh)
        XCTAssertEqual(info.maxConcurrentReads, 1)
        XCTAssertEqual(Set(subtypes), ["LTE"])
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
