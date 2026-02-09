//
//  UserDefaultsTestViewController.swift
//  DemoAppSwift
//
//  Created for testing UserDefaults corruption bug
//  Bug: objc_getClassList() triggers CloudKit +initialize which corrupts UserDefaults
//

import UIKit
import Coralogix
import MachO

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
        let button2 = createButton(title: "2️⃣ Single Class Scan (Coralogix)", action: #selector(triggerClassScanning))
        let button3 = createButton(title: "3️⃣ Multiple Scans (Sentry + Coralogix)", action: #selector(triggerMultipleScans))
        let button4 = createButton(title: "4️⃣ Test After Scanning", action: #selector(testAfterScanning))
        let button5 = createButton(title: "🔄 Run Full Test", action: #selector(runFullTest))
        let button6 = createButton(title: "🔍 Check Linked Frameworks", action: #selector(checkLinkedFrameworks))
        let clearButton = createButton(title: "🗑️ Clear Logs", action: #selector(clearLogs))
        clearButton.backgroundColor = .systemRed
        
        contentStack.addArrangedSubview(button1)
        contentStack.addArrangedSubview(button2)
        contentStack.addArrangedSubview(button3)
        contentStack.addArrangedSubview(button4)
        contentStack.addArrangedSubview(button5)
        contentStack.addArrangedSubview(button6)
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
        log("1. First check linked frameworks (button 6)")
        log("2. Run full test (button 5)")
        log("3. If no bug, try 'Multiple Scans' (button 3)\n")
        log("⚠️ Bug: If CloudKit classes are initialized during")
        log("   objc_getClassList(), UserDefaults may only work in memory")
        log("   This is more likely with multiple SDKs (Sentry + Coralogix)\n")
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
    
    @objc private func checkLinkedFrameworks() {
        log("\n🔍 Checking Linked Frameworks")
        log("─────────────────────────────────────────────")
        
        // Check for common frameworks that might contain CloudKit
        let frameworksToCheck = [
            "CloudKit",
            "CloudKitDistributedSync", 
            "iCloudQuota",
            "Sentry",
            "Firebase",
            "FirebaseCore",
            "Datadog",
            "DatadogCore"
        ]
        
        var foundFrameworks: [String] = []
        
        for framework in frameworksToCheck {
            // Try to get a class from the framework
            if let _ = NSClassFromString(framework) ?? 
                       NSClassFromString("\(framework).Configuration") ??
                       NSClassFromString("CKDatabase") {  // CloudKit specific
                foundFrameworks.append(framework)
            }
        }
        
        if foundFrameworks.isEmpty {
            log("✅ No known APM/CloudKit frameworks detected")
            log("   This might be why the bug doesn't reproduce")
        } else {
            log("⚠️  Found frameworks: \(foundFrameworks.joined(separator: ", "))")
            log("   These frameworks increase corruption risk")
        }
        
        // Check for CloudKit classes specifically
        let ckClasses = ["CKDatabase", "CKContainer", "CKRecord", "CKRecordZone"]
        var foundCKClasses: [String] = []
        
        for className in ckClasses {
            if NSClassFromString(className) != nil {
                foundCKClasses.append(className)
            }
        }
        
        if foundCKClasses.isEmpty {
            log("\n❌ CloudKit classes NOT available")
            log("   Bug cannot reproduce without CloudKit")
            log("\n💡 To reproduce the bug:")
            log("   1. Link CloudKit.framework in Xcode")
            log("   2. Or test in an app that uses iCloud")
        } else {
            log("\n⚠️  CloudKit classes available: \(foundCKClasses.joined(separator: ", "))")
            log("   Bug CAN reproduce in this environment")
        }
        
        // Check if any images have CloudKit
        let loadedImages = _dyld_image_count()
        var hasCloudKit = false
        for i in 0..<loadedImages {
            if let imageName = _dyld_get_image_name(i) {
                let name = String(cString: imageName)
                if name.contains("CloudKit") {
                    hasCloudKit = true
                    log("\n📦 CloudKit loaded from: \(name)")
                    break
                }
            }
        }
        
        if !hasCloudKit {
            log("\n❌ CloudKit.framework NOT loaded in memory")
        }
    }
    
    @objc private func triggerClassScanning() {
        log("\n🔬 TEST 2: Single class scan (Coralogix SDK)")
        log("─────────────────────────────────────────────")
        log("⚠️  About to call objc_getClassList() + NSStringFromClass()")
        log("   This triggers +initialize on ALL classes including CloudKit\n")
        
        performClassScan(label: "Coralogix")
    }
    
    @objc private func triggerMultipleScans() {
        log("\n🔬 TEST 3: Multiple class scans (Sentry + Coralogix)")
        log("─────────────────────────────────────────────")
        log("⚠️  Simulating multiple SDKs scanning classes")
        log("   Real-world scenario: App has Sentry AND Coralogix")
        log("   Each SDK scans ALL classes during initialization\n")
        
        performClassScan(label: "Sentry (1st scan)")
        
        log("\n⏱️  Waiting 100ms...\n")
        Thread.sleep(forTimeInterval: 0.1)
        
        performClassScan(label: "Coralogix (2nd scan)")
        
        log("\n⚠️  Multiple scans can compound the corruption")
        log("   Each scan re-triggers +initialize methods")
    }
    
    private func performClassScan(label: String) {
        log("🔍 \(label) scanning classes...")
        
        let expectedClassCount = ObjectiveC.objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(expectedClassCount))
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = ObjectiveC.objc_getClassList(autoreleasingAllClasses, expectedClassCount)
        
        var ckClassCount = 0
        var ubClassCount = 0
        var sentryCount = 0
        var firebaseCount = 0
        
        for i in 0 ..< actualClassCount {
            let cls = allClasses[Int(i)]
            let className = NSStringFromClass(cls)  // ⚠️ THIS TRIGGERS +initialize
            
            if className.hasPrefix("CK") {
                ckClassCount += 1
                if ckClassCount <= 3 {
                    log("   Found CloudKit class: \(className)")
                }
            } else if className.hasPrefix("UB") || className.hasPrefix("_UB") {
                ubClassCount += 1
                if ubClassCount <= 3 {
                    log("   Found iCloud class: \(className)")
                }
            } else if className.hasPrefix("Sentry") {
                sentryCount += 1
            } else if className.hasPrefix("FIR") || className.hasPrefix("Firebase") {
                firebaseCount += 1
            }
        }
        
        allClasses.deallocate()
        
        log("\n📊 \(label) scan results:")
        log("   Total classes: \(actualClassCount)")
        log("   CloudKit (CK*): \(ckClassCount)")
        log("   iCloud (UB*, _UB*): \(ubClassCount)")
        if sentryCount > 0 {
            log("   Sentry: \(sentryCount)")
        }
        if firebaseCount > 0 {
            log("   Firebase: \(firebaseCount)")
        }
        
        if ckClassCount > 0 || ubClassCount > 0 {
            log("\n⚠️  CloudKit/iCloud classes triggered!")
            log("   +initialize methods have been called")
            log("   UserDefaults corruption risk is HIGH")
        } else {
            log("\n✅ No CloudKit classes (can't reproduce bug)")
        }
    }
    
    @objc private func testAfterScanning() {
        log("\n🧪 TEST 4: UserDefaults AFTER class scanning")
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
        
        checkLinkedFrameworks()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.testBeforeSDKInit()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Use multiple scans to increase chance of reproduction
                self.triggerMultipleScans()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.testAfterScanning()
                    
                    self.log("\n═══════════════════════════════════════════")
                    self.log("TEST COMPLETE")
                    self.log("═══════════════════════════════════════════")
                    
                    if NSClassFromString("CKDatabase") == nil {
                        self.log("\n💡 Tip: Bug requires CloudKit to be linked")
                        self.log("   In production apps with Sentry + CloudKit,")
                        self.log("   this bug is more likely to occur")
                    }
                }
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
