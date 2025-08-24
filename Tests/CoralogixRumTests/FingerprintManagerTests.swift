//
//  FingerprintManagerTests.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 24/08/2025.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class FingerprintManagerTests: XCTestCase {

    // Existing value should be returned as-is; no writes should occur.
    func testReturnsExistingFingerprintWithoutWriting() {
        let kc = FakeKeychain()
        kc.setStoredValue("existing-fp-123")

        let sut = FingerprintManager(using: kc)

        XCTAssertEqual(sut.fingerprint, "existing-fp-123")
        XCTAssertEqual(kc.writeCount, 0, "Should not write when a value already exists")
        XCTAssertGreaterThanOrEqual(kc.readCount, 1, "Should read from keychain at least once")
    }

    // When missing, it should generate, persist, and return a lowercase UUID.
    func testGeneratesAndPersistsLowercasedUUIDWhenMissing() {
        let kc = FakeKeychain() // empty

        let sut = FingerprintManager(using: kc)

        guard let stored = kc.currentStoredValue() else {
            return XCTFail("Expected keychain to contain a value after initialization")
        }

        XCTAssertEqual(sut.fingerprint, stored)
        XCTAssertEqual(sut.fingerprint, sut.fingerprint.lowercased(), "Fingerprint should be lowercased")
        XCTAssertNotNil(UUID(uuidString: sut.fingerprint), "Fingerprint should be a valid UUID")
        XCTAssertEqual(kc.writeCount, 1, "Should write exactly once when creating the fingerprint")
    }

    // If a race occurs (another writer overwrites after our write), the manager must adopt the stored value.
    func testConvergesToStoredValueAfterRace() {
        let kc = FakeKeychain()
        kc.postWriteOverride = "canonical-race-value"

        let sut = FingerprintManager(using: kc)

        XCTAssertEqual(sut.fingerprint, "canonical-race-value",
                       "Manager should adopt the canonical stored value after write/read-back")
        XCTAssertEqual(kc.currentStoredValue(), "canonical-race-value")
        XCTAssertEqual(kc.writeCount, 1)
    }

    // Subsequent initializations should use the already persisted value (no extra writes).
    func testSecondInitializationUsesExistingWithoutExtraWrite() {
        let kc = FakeKeychain()

        let first = FingerprintManager(using: kc)
        let firstStored = kc.currentStoredValue()
        XCTAssertEqual(first.fingerprint, firstStored)
        XCTAssertEqual(kc.writeCount, 1)

        let second = FingerprintManager(using: kc)
        XCTAssertEqual(second.fingerprint, firstStored)
        XCTAssertEqual(kc.writeCount, 1, "No additional writes expected when value already exists")
    }

    // Concurrent initializations with a shared keychain should converge to one value for all instances.
    func testConcurrentInitializationsConvergeToSingleValue() {
        let kc = FakeKeychain()
        let group = DispatchGroup()
        let resultsLock = NSLock()
        var results = [String]()

        let iterations = 40
        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let m = FingerprintManager(using: kc)
                resultsLock.lock(); results.append(m.fingerprint); resultsLock.unlock()
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2.0), .success, "Concurrent inits did not finish in time")

        XCTAssertFalse(results.isEmpty)
        let unique = Set(results)
        XCTAssertEqual(unique.count, 1, "All instances should agree on the same fingerprint")
        XCTAssertEqual(unique.first, kc.currentStoredValue(), "The agreed value should match the keychain")
    }

    #if DEBUG
    func testDebugInitializerSetsFingerprintDirectly() {
        let sut = FingerprintManager(testFingerprint: "debug-fp-abc")
        XCTAssertEqual(sut.fingerprint, "debug-fp-abc")
    }
    #endif
}


final class FakeKeychain: KeyChainProtocol {
    func addStringIfAbsent(service: String, key: String, value: String) -> Bool {
        return true
    }
    
    private let lock = NSLock()
    private var value: String?

    // Diagnostics
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var lastWrittenValue: String?

    /// If set, the write will be immediately "overwritten" to simulate a race.
    var postWriteOverride: String?

    // Ignore service/key for the tests; store a single value.
    func readStringFromKeychain(service: String, key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        return value
    }

    func writeStringToKeychain(service: String, key: String, value: String) {
        lock.lock()
        writeCount += 1
        lastWrittenValue = value
        self.value = value
        if let override = postWriteOverride {
            // Simulate another thread/process winning the race.
            self.value = override
        }
        lock.unlock()
    }

    // Helpers for tests
    func setStoredValue(_ v: String?) {
        lock.lock(); value = v; lock.unlock()
    }

    func currentStoredValue() -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
