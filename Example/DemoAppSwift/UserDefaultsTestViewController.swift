//
//  UserDefaultsTestViewController.swift
//  DemoAppSwift
//
//  Created for testing UserDefaults corruption bug
//  Bug: objc_getClassList() triggers CloudKit +initialize which corrupts UserDefaults
//

import UIKit
import Coralogix

final class UserDefaultsTestViewController: UIViewController {
    
    private let testKey = "coralogix_userdefaults_test"
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let logTextView = UITextView()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        // Auto-run test on load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.runFullTest()
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "UserDefaults Bug Test"
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        // Test buttons
        let button1 = createButton(title: "1️⃣ Test Before SDK Init", action: #selector(testBeforeSDKInit))
        let button2 = createButton(title: "2️⃣ Trigger Class Scanning (Simulate SDK)", action: #selector(triggerClassScanning))
        let button3 = createButton(title: "3️⃣ Test After Scanning", action: #selector(testAfterScanning))
        let button4 = createButton(title: "🔄 Run Full Test", action: #selector(runFullTest))
        let clearButton = createButton(title: "🗑️ Clear Logs", action: #selector(clearLogs))
        clearButton.backgroundColor = .systemRed
        
        contentStack.addArrangedSubview(button1)
        contentStack.addArrangedSubview(button2)
        contentStack.addArrangedSubview(button3)
        contentStack.addArrangedSubview(button4)
        contentStack.addArrangedSubview(clearButton)
        
        // Log text view
        logTextView.isEditable = false
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.backgroundColor = .systemGray6
        logTextView.layer.cornerRadius = 8
        logTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(logTextView)
        
        // Constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            
            logTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
        
        log("✅ UserDefaults Bug Test Ready\n")
        log("📋 Instructions:")
        log("1. Press buttons in order (1→2→3)")
        log("2. Or press 'Run Full Test' to run all at once")
        log("3. Watch for UserDefaults corruption after class scanning\n")
        log("⚠️ Bug: If CloudKit classes are initialized during")
        log("   objc_getClassList(), UserDefaults may only work in memory\n")
        log("─────────────────────────────────────────────\n")
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return button
    }
    
    // MARK: - Test Methods
    
    @objc private func testBeforeSDKInit() {
        log("\n🧪 TEST 1: UserDefaults BEFORE class scanning")
        log("─────────────────────────────────────────────")
        
        // Clear any previous test value
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.synchronize()
        
        // Set a test value
        let testValue = "value_before_scanning_\(Date().timeIntervalSince1970)"
        UserDefaults.standard.set(testValue, forKey: testKey)
        UserDefaults.standard.synchronize()
        
        // Read it back
        let readValue = UserDefaults.standard.string(forKey: testKey)
        
        if readValue == testValue {
            log("✅ PASS: UserDefaults working correctly")
            log("   Written: \(testValue)")
            log("   Read:    \(readValue ?? "nil")")
        } else {
            log("❌ FAIL: UserDefaults not working")
            log("   Written: \(testValue)")
            log("   Read:    \(readValue ?? "nil")")
        }
    }
    
    @objc private func triggerClassScanning() {
        log("\n🔬 TEST 2: Triggering class scanning (simulating SDK init)")
        log("─────────────────────────────────────────────")
        log("⚠️  About to call objc_getClassList() + NSStringFromClass()")
        log("   This triggers +initialize on ALL classes including CloudKit\n")
        
        // Simulate what the SDK does
        let expectedClassCount = ObjectiveC.objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(expectedClassCount))
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = ObjectiveC.objc_getClassList(autoreleasingAllClasses, expectedClassCount)
        
        var ckClassCount = 0
        var ubClassCount = 0
        
        for i in 0 ..< actualClassCount {
            let cls = allClasses[Int(i)]
            let className = NSStringFromClass(cls)  // ⚠️ THIS TRIGGERS +initialize
            
            if className.hasPrefix("CK") {
                ckClassCount += 1
                if ckClassCount <= 3 {  // Only log first 3
                    log("   Found CloudKit class: \(className)")
                }
            } else if className.hasPrefix("UB") || className.hasPrefix("_UB") {
                ubClassCount += 1
                if ubClassCount <= 3 {
                    log("   Found iCloud class: \(className)")
                }
            }
        }
        
        allClasses.deallocate()
        
        log("\n📊 Class scan results:")
        log("   Total classes scanned: \(actualClassCount)")
        log("   CloudKit classes (CK*): \(ckClassCount)")
        log("   iCloud classes (UB*, _UB*): \(ubClassCount)")
        
        if ckClassCount > 0 || ubClassCount > 0 {
            log("\n⚠️  WARNING: CloudKit/iCloud classes detected!")
            log("   Their +initialize methods have been called")
            log("   UserDefaults may be corrupted now...")
        } else {
            log("\n✅ No CloudKit/iCloud classes found")
            log("   (App doesn't link CloudKit framework)")
        }
    }
    
    @objc private func testAfterScanning() {
        log("\n🧪 TEST 3: UserDefaults AFTER class scanning")
        log("─────────────────────────────────────────────")
        
        // Try to write a new value
        let testValue = "value_after_scanning_\(Date().timeIntervalSince1970)"
        UserDefaults.standard.set(testValue, forKey: testKey)
        UserDefaults.standard.synchronize()
        
        // Read it back immediately
        let readValue = UserDefaults.standard.string(forKey: testKey)
        
        if readValue == testValue {
            log("✅ PASS: UserDefaults still working")
            log("   Written: \(testValue)")
            log("   Read:    \(readValue ?? "nil")")
            log("\n💡 No corruption detected (or CloudKit not linked)")
        } else {
            log("❌ FAIL: UserDefaults corrupted!")
            log("   Written: \(testValue)")
            log("   Read:    \(readValue ?? "nil")")
            log("\n🐛 BUG REPRODUCED:")
            log("   CloudKit +initialize corrupted UserDefaults")
            log("   Values only persist in memory, not to disk")
        }
        
        // Check file system
        log("\n📁 Checking UserDefaults plist file:")
        if let plistPath = getUserDefaultsPlistPath() {
            log("   Path: \(plistPath)")
            let fileExists = FileManager.default.fileExists(atPath: plistPath)
            log("   File exists: \(fileExists)")
            
            if fileExists, let plistData = FileManager.default.contents(atPath: plistPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                let hasTestKey = plist[testKey] != nil
                log("   Contains test key '\(testKey)': \(hasTestKey)")
                
                if !hasTestKey && readValue != nil {
                    log("\n⚠️  CORRUPTION CONFIRMED:")
                    log("   Value exists in memory but NOT in plist file!")
                }
            }
        }
    }
    
    @objc private func runFullTest() {
        clearLogs()
        log("🚀 Running Full UserDefaults Corruption Test\n")
        
        testBeforeSDKInit()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.triggerClassScanning()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.testAfterScanning()
                
                self.log("\n═══════════════════════════════════════════")
                self.log("TEST COMPLETE")
                self.log("═══════════════════════════════════════════")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getUserDefaultsPlistPath() -> String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let paths = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)
        guard let libraryPath = paths.first else { return nil }
        return "\(libraryPath)/Preferences/\(bundleID).plist"
    }
    
    @objc private func clearLogs() {
        logTextView.text = ""
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        logTextView.text += logMessage
        
        // Auto-scroll to bottom
        let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
        logTextView.scrollRangeToVisible(bottom)
    }
}
