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
        let button1 = createButton(title: "🔍 Check SDK Initialization Status", action: #selector(checkLinkedFrameworks))
        let button2 = createButton(title: "🧪 Test UserDefaults (After SDK Init)", action: #selector(testUserDefaultsAfterSDKInit))
        let button3 = createButton(title: "🔄 Run Full Test", action: #selector(runFullTest))
        let clearButton = createButton(title: "🗑️ Clear Logs", action: #selector(clearLogs))
        clearButton.backgroundColor = .systemRed
        
        contentStack.addArrangedSubview(button1)
        contentStack.addArrangedSubview(button2)
        contentStack.addArrangedSubview(button3)
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
        log("📋 Real-World Test:")
        log("• Sentry initialized in AppDelegate (FIRST)")
        log("• Coralogix initialized in AppDelegate (SECOND)")
        log("• This test checks if UserDefaults was corrupted\n")
        log("⚠️ Bug: Sentry's objc_getClassList() triggers")
        log("   CloudKit +initialize, which corrupts UserDefaults")
        log("   Values work in memory but don't persist to disk\n")
        log("🎯 Press 'Run Full Test' to check for corruption\n")
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
    
    @objc private func testUserDefaultsAfterSDKInit() {
        log("\n🧪 Testing UserDefaults (After SDK Initialization)")
        log("─────────────────────────────────────────────")
        log("⚠️  Note: Sentry and Coralogix already initialized in AppDelegate")
        log("   If corruption happened, we'll detect it now\n")
        
        // Clear any previous test value
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.synchronize()
        
        // Write a test value
        let testValue = "test_value_\(Date().timeIntervalSince1970)"
        log("📝 Writing to UserDefaults...")
        log("   Key: \(testKey)")
        log("   Value: \(testValue)")
        
        UserDefaults.standard.set(testValue, forKey: testKey)
        UserDefaults.standard.synchronize()
        
        // Read it back immediately (from memory)
        let readValue = UserDefaults.standard.string(forKey: testKey)
        
        log("\n📖 Reading from UserDefaults (memory)...")
        if readValue == testValue {
            log("   ✅ Read successful: \(readValue ?? "nil")")
        } else {
            log("   ❌ Read failed: \(readValue ?? "nil")")
        }
        
        // Check if it's actually in the plist file (disk)
        log("\n📁 Checking UserDefaults plist file (disk)...")
        if let plistPath = getUserDefaultsPlistPath() {
            log("   Path: \(plistPath)")
            let fileExists = FileManager.default.fileExists(atPath: plistPath)
            log("   File exists: \(fileExists)")
            
            if fileExists, let plistData = FileManager.default.contents(atPath: plistPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                let hasTestKey = plist[testKey] != nil
                let diskValue = plist[testKey] as? String
                
                log("   Contains key '\(testKey)': \(hasTestKey)")
                if hasTestKey {
                    log("   Disk value: \(diskValue ?? "nil")")
                }
                
                // The verdict
                if readValue != nil && !hasTestKey {
                    log("\n❌ BUG DETECTED!")
                    log("   • Value exists in memory: ✅")
                    log("   • Value persisted to disk: ❌")
                    log("   • Corruption confirmed: UserDefaults is in memory-only mode")
                    log("   • Cause: Sentry/Coralogix class scanning triggered CloudKit +initialize")
                } else if readValue != nil && hasTestKey {
                    log("\n✅ NO BUG")
                    log("   • Value exists in memory: ✅")
                    log("   • Value persisted to disk: ✅")
                    log("   • UserDefaults working normally")
                } else {
                    log("\n⚠️  UNEXPECTED STATE")
                    log("   • Memory value: \(readValue ?? "nil")")
                    log("   • Disk value: \(diskValue ?? "nil")")
                }
            } else {
                log("   ⚠️  Could not read plist file")
            }
        } else {
            log("   ❌ Could not determine plist path")
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
    
    
    @objc private func runFullTest() {
        clearLogs()
        log("🚀 Running Real-World UserDefaults Test\n")
        log("⏱️  Timeline:")
        log("   1. AppDelegate.didFinishLaunching (ALREADY RAN)")
        log("      - CloudKitTestHelper.forceLoadCloudKit() ✅")
        log("      - Sentry.initialize() ← Scans 65k classes ⚠️")
        log("      - Coralogix.initialize() ← Scans 65k classes ⚠️")
        log("   2. This test (RUNNING NOW)")
        log("      - Check if UserDefaults corrupted by SDK init\n")
        
        checkLinkedFrameworks()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.testUserDefaultsAfterSDKInit()
            
            self.log("\n═══════════════════════════════════════════")
            self.log("TEST COMPLETE")
            self.log("═══════════════════════════════════════════\n")
            
            if NSClassFromString("CKDatabase") != nil {
                self.log("💡 Interpretation:")
                self.log("   • If bug detected: Sentry/Coralogix class scanning")
                self.log("     triggered CloudKit +initialize during app launch")
                self.log("   • If no bug: Either corruption didn't happen OR")
                self.log("     Apple fixed it in this iOS version")
            } else {
                self.log("⚠️  CloudKit not available")
                self.log("   Bug cannot reproduce without CloudKit")
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
