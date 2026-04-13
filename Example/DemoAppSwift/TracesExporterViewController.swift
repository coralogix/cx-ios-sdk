//
//  TracesExporterViewController.swift
//  DemoAppSwift
//
//  Test view for the Traces Exporter (OTLP callback) feature.
//

import UIKit
import Coralogix

final class TracesExporterViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private let spanCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.text = "Spans received: 0"
        return label
    }()
    
    private let logTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return textView
    }()
    
    private lazy var reinitButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Reinitialize SDK with Traces Exporter", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: #selector(reinitializeSDK), for: .touchUpInside)
        return button
    }()
    
    private lazy var triggerNetworkButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Trigger Network Request", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: #selector(triggerNetworkRequest), for: .touchUpInside)
        return button
    }()
    
    private lazy var triggerCustomSpanButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Trigger Custom Span", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(self, action: #selector(triggerCustomSpan), for: .touchUpInside)
        return button
    }()
    
    private lazy var clearLogButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Clear Log", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.addTarget(self, action: #selector(clearLog), for: .touchUpInside)
        return button
    }()
    
    private lazy var copyFullLogButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Copy Full Log", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.addTarget(self, action: #selector(copyFullLog), for: .touchUpInside)
        return button
    }()
    
    private lazy var validateOtlpButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Validate OTLP", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.addTarget(self, action: #selector(validateOtlpStructure), for: .touchUpInside)
        return button
    }()
    
    // MARK: - State
    
    private static var isTracesExporterEnabled = false
    private static var totalSpansReceived = 0
    private static var logMessages: [String] = []
    private static var fullJsonLogs: [String] = []
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateStatus()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStatus()
        updateLog()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "Traces Exporter"
        view.backgroundColor = .systemBackground
        
        let buttonStackView = UIStackView(arrangedSubviews: [
            clearLogButton,
            copyFullLogButton,
            validateOtlpButton
        ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 16
        buttonStackView.distribution = .equalCentering
        
        let stackView = UIStackView(arrangedSubviews: [
            statusLabel,
            spanCountLabel,
            reinitButton,
            triggerNetworkButton,
            triggerCustomSpanButton,
            buttonStackView
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .center
        
        view.addSubview(stackView)
        view.addSubview(logTextView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            logTextView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 16),
            logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            logTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    private func updateStatus() {
        if Self.isTracesExporterEnabled {
            statusLabel.text = "✅ Traces Exporter: ENABLED"
            statusLabel.textColor = .systemGreen
            reinitButton.isEnabled = false
            reinitButton.setTitle("SDK already initialized with Traces Exporter", for: .normal)
        } else {
            statusLabel.text = "⚠️ Traces Exporter: DISABLED"
            statusLabel.textColor = .systemOrange
            reinitButton.isEnabled = true
            reinitButton.setTitle("Reinitialize SDK with Traces Exporter", for: .normal)
        }
        spanCountLabel.text = "Spans received: \(Self.totalSpansReceived)"
    }
    
    private func updateLog() {
        logTextView.text = Self.logMessages.joined(separator: "\n\n---\n\n")
        if !Self.logMessages.isEmpty {
            let bottom = NSRange(location: logTextView.text.count - 1, length: 1)
            logTextView.scrollRangeToVisible(bottom)
        }
    }
    
    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)]\n\(message)"
        Self.logMessages.append(logEntry)
        
        if Self.logMessages.count > 50 {
            Self.logMessages.removeFirst()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateLog()
            self?.updateStatus()
        }
    }
    
    // MARK: - Actions
    
    @objc private func reinitializeSDK() {
        let alert = UIAlertController(
            title: "Reinitialize SDK",
            message: "This will shutdown the current SDK and reinitialize it with the tracesExporter callback enabled. The app may need to generate new spans to see OTLP data.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reinitialize", style: .default) { [weak self] _ in
            self?.performReinitialize()
        })
        
        present(alert, animated: true)
    }
    
    private func performReinitialize() {
        CoralogixRumManager.shared.sdk.shutdown()
        
        let userContext = UserContext(
            userId: "traces-exporter-test",
            userName: "Test User",
            userEmail: "test@example.com",
            userMetadata: ["test": "tracesExporter"]
        )
        
        let options = CoralogixExporterOptions(
            coralogixDomain: .EU2,
            userContext: userContext,
            environment: "PROD",
            application: "DemoApp-iOS-TracesExporter",
            version: "1",
            publicKey: Envs.PUBLIC_KEY.rawValue,
            instrumentations: [
                .mobileVitals: true,
                .custom: true,
                .errors: true,
                .userActions: true,
                .network: true,
                .anr: true,
                .lifeCycle: true
            ],
            collectIPData: true,
            tracesExporter: { [weak self] data in
                // Callback runs on the exporter background queue; build the message off the main thread.
                var logMessage = "Received \(data.spanCount) span(s)\n"
                logMessage += "Resource spans: \(data.tracesData.resourceSpans.count)\n"
                
                for (i, resourceSpan) in data.tracesData.resourceSpans.enumerated() {
                    logMessage += "\nResource[\(i)]:\n"
                    for attr in resourceSpan.resource.attributes.prefix(3) {
                        logMessage += "  \(attr.key): \(self?.formatAnyValue(attr.value) ?? "?")\n"
                    }
                    
                    for scopeSpan in resourceSpan.scopeSpans {
                        logMessage += "  Scope: \(scopeSpan.scope.name)\n"
                        for span in scopeSpan.spans {
                            logMessage += "    - \(span.name) [\(span.kind.rawValue)]\n"
                            logMessage += "      traceId: \(span.traceId.prefix(16))...\n"
                            logMessage += "      spanId: \(span.spanId)\n"
                            logMessage += "      status: \(span.status.code.rawValue)\n"
                        }
                    }
                }
                
                if let jsonString = data.jsonString {
                    let truncated = jsonString.count > 500
                        ? String(jsonString.prefix(500)) + "... (truncated, use 'Copy Full Log' for complete JSON)"
                        : jsonString
                    logMessage += "\nJSON Preview:\n\(truncated)"
                }
                
                // Static state and appendLog must match clearLog / copyFullLog / validateOtlpStructure (main thread).
                DispatchQueue.main.async { [weak self] in
                    Self.totalSpansReceived += data.spanCount
                    
                    if let jsonString = data.jsonString {
                        Self.fullJsonLogs.append(jsonString)
                        if Self.fullJsonLogs.count > 50 {
                            Self.fullJsonLogs.removeFirst()
                        }
                    }
                    
                    self?.appendLog(logMessage)
                }
            },
            debug: true
        )
        
        CoralogixRumManager.shared.reinitialize(with: options)
        Self.isTracesExporterEnabled = true
        
        appendLog("SDK reinitialized with tracesExporter callback enabled")
        updateStatus()
        
        showToast("SDK reinitialized with Traces Exporter")
    }
    
    private func formatAnyValue(_ value: OtlpAnyValue) -> String {
        switch value {
        case .stringValue(let s): return s
        case .boolValue(let b): return String(b)
        case .intValue(let i): return String(i)
        case .doubleValue(let d): return String(d)
        case .arrayValue(let arr): return "[\(arr.count) items]"
        case .kvlistValue(let kv): return "{\(kv.count) pairs}"
        }
    }
    
    @objc private func triggerNetworkRequest() {
        guard Self.isTracesExporterEnabled else {
            showToast("Please reinitialize SDK with Traces Exporter first")
            return
        }
        
        appendLog("Triggering network request...")
        NetworkSim.sendSuccesfullRequest()
        showToast("Network request sent - check log for OTLP data")
    }
    
    @objc private func triggerCustomSpan() {
        guard Self.isTracesExporterEnabled else {
            showToast("Please reinitialize SDK with Traces Exporter first")
            return
        }
        
        let rum = CoralogixRumManager.shared.sdk
        guard rum.isInitialized else {
            showToast("SDK not initialized")
            return
        }
        
        appendLog("Creating custom span...")
        
        let tracer = rum.getCustomTracer()
        guard let global = tracer.startGlobalSpan(
            name: "traces-exporter-test.global",
            labels: ["test.source": "TracesExporterViewController"]
        ) else {
            showToast("Failed to create global span")
            return
        }
        
        let child = global.startCustomSpan(name: "traces-exporter-test.child")
        child.setAttribute(key: "test.attribute", value: "hello-otlp")
        child.addEvent(name: "test.event")
        child.setStatus(.ok)
        child.endSpan()
        
        global.endSpan()
        
        showToast("Custom spans created - check log for OTLP data")
    }
    
    @objc private func clearLog() {
        Self.logMessages.removeAll()
        Self.fullJsonLogs.removeAll()
        Self.totalSpansReceived = 0
        updateLog()
        updateStatus()
        showToast("Log cleared")
    }
    
    @objc private func copyFullLog() {
        guard !Self.fullJsonLogs.isEmpty else {
            showToast("No OTLP data to copy")
            return
        }
        
        var fullLog = "=== Traces Exporter Full Log ===\n"
        fullLog += "Total spans received: \(Self.totalSpansReceived)\n"
        fullLog += "Total exports: \(Self.fullJsonLogs.count)\n"
        fullLog += "Generated at: \(ISO8601DateFormatter().string(from: Date()))\n"
        fullLog += "\n"
        
        for (index, json) in Self.fullJsonLogs.enumerated() {
            fullLog += "=== Export #\(index + 1) ===\n"
            fullLog += json
            fullLog += "\n\n"
        }
        
        UIPasteboard.general.string = fullLog
        showToast("Full log copied to clipboard (\(Self.fullJsonLogs.count) exports)")
    }
    
    @objc private func validateOtlpStructure() {
        guard !Self.fullJsonLogs.isEmpty else {
            showValidationResult(title: "No Data", message: "No OTLP data to validate. Generate some spans first.")
            return
        }
        
        var results: [String] = []
        var totalPassed = 0
        var totalFailed = 0
        
        for (index, jsonString) in Self.fullJsonLogs.enumerated() {
            let validation = validateSingleExport(jsonString, exportIndex: index + 1)
            results.append(validation.report)
            totalPassed += validation.passed
            totalFailed += validation.failed
        }
        
        let summary = """
        === OTLP Validation Summary ===
        
        Exports validated: \(Self.fullJsonLogs.count)
        Total checks passed: \(totalPassed)
        Total checks failed: \(totalFailed)
        
        \(results.joined(separator: "\n\n"))
        """
        
        let title = totalFailed == 0 ? "✅ All Validations Passed" : "⚠️ Some Validations Failed"
        showValidationResult(title: title, message: summary)
    }
    
    private struct ValidationResult {
        let report: String
        let passed: Int
        let failed: Int
    }
    
    private func validateSingleExport(_ jsonString: String, exportIndex: Int) -> ValidationResult {
        var checks: [(name: String, passed: Bool, detail: String)] = []
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return ValidationResult(
                report: "Export #\(exportIndex): ❌ Invalid UTF-8 encoding",
                passed: 0,
                failed: 1
            )
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return ValidationResult(
                report: "Export #\(exportIndex): ❌ Invalid JSON",
                passed: 0,
                failed: 1
            )
        }
        checks.append(("Valid JSON", true, ""))
        
        guard let resourceSpans = json["resource_spans"] as? [[String: Any]] else {
            checks.append(("Has resource_spans", false, "Missing or invalid resource_spans array"))
            return buildReport(exportIndex: exportIndex, checks: checks)
        }
        checks.append(("Has resource_spans", true, "\(resourceSpans.count) resource(s)"))
        
        for (rIdx, resourceSpan) in resourceSpans.enumerated() {
            if let resource = resourceSpan["resource"] as? [String: Any],
               let _ = resource["attributes"] as? [[String: Any]] {
                checks.append(("Resource[\(rIdx)] has attributes", true, ""))
            } else {
                checks.append(("Resource[\(rIdx)] has attributes", false, "Missing resource.attributes"))
            }
            
            guard let scopeSpans = resourceSpan["scope_spans"] as? [[String: Any]] else {
                checks.append(("Resource[\(rIdx)] has scope_spans", false, "Missing scope_spans"))
                continue
            }
            checks.append(("Resource[\(rIdx)] has scope_spans", true, "\(scopeSpans.count) scope(s)"))
            
            for (sIdx, scopeSpan) in scopeSpans.enumerated() {
                if let scope = scopeSpan["scope"] as? [String: Any],
                   let _ = scope["name"] as? String {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] has name", true, ""))
                } else {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] has name", false, "Missing scope.name"))
                }
                
                guard let spans = scopeSpan["spans"] as? [[String: Any]] else {
                    checks.append(("Scope[\(rIdx)][\(sIdx)] has spans", false, "Missing spans array"))
                    continue
                }
                checks.append(("Scope[\(rIdx)][\(sIdx)] has spans", true, "\(spans.count) span(s)"))
                
                for (spanIdx, span) in spans.enumerated() {
                    let spanChecks = validateSpan(span, path: "Span[\(rIdx)][\(sIdx)][\(spanIdx)]")
                    checks.append(contentsOf: spanChecks)
                }
            }
        }
        
        return buildReport(exportIndex: exportIndex, checks: checks)
    }
    
    private func validateSpan(_ span: [String: Any], path: String) -> [(name: String, passed: Bool, detail: String)] {
        var checks: [(name: String, passed: Bool, detail: String)] = []
        
        if let traceId = span["trace_id"] as? String {
            let (valid, detail) = validateBase64(traceId, expectedBytes: 16)
            checks.append(("\(path) trace_id", valid, detail))
        } else {
            checks.append(("\(path) trace_id", false, "Missing"))
        }
        
        if let spanId = span["span_id"] as? String {
            let (valid, detail) = validateBase64(spanId, expectedBytes: 8)
            checks.append(("\(path) span_id", valid, detail))
        } else {
            checks.append(("\(path) span_id", false, "Missing"))
        }
        
        if let name = span["name"] as? String, !name.isEmpty {
            checks.append(("\(path) name", true, "'\(name)'"))
        } else {
            checks.append(("\(path) name", false, "Missing or empty"))
        }
        
        if let kind = span["kind"] as? String {
            let validKinds = ["SPAN_KIND_UNSPECIFIED", "SPAN_KIND_INTERNAL", "SPAN_KIND_SERVER", 
                              "SPAN_KIND_CLIENT", "SPAN_KIND_PRODUCER", "SPAN_KIND_CONSUMER"]
            let valid = validKinds.contains(kind)
            checks.append(("\(path) kind", valid, valid ? kind : "Invalid: \(kind)"))
        } else {
            checks.append(("\(path) kind", false, "Missing"))
        }
        
        if let startTime = span["start_time_unix_nano"] as? String {
            let valid = UInt64(startTime) != nil
            checks.append(("\(path) start_time", valid, valid ? "Valid nanoseconds" : "Invalid format"))
        } else {
            checks.append(("\(path) start_time", false, "Missing"))
        }
        
        if let endTime = span["end_time_unix_nano"] as? String {
            let valid = UInt64(endTime) != nil
            checks.append(("\(path) end_time", valid, valid ? "Valid nanoseconds" : "Invalid format"))
        } else {
            checks.append(("\(path) end_time", false, "Missing"))
        }
        
        if let status = span["status"] as? [String: Any],
           let code = status["code"] as? String {
            let validCodes = ["STATUS_CODE_UNSET", "STATUS_CODE_OK", "STATUS_CODE_ERROR"]
            let valid = validCodes.contains(code)
            checks.append(("\(path) status.code", valid, valid ? code : "Invalid: \(code)"))
        } else {
            checks.append(("\(path) status.code", false, "Missing"))
        }
        
        return checks
    }
    
    private func validateBase64(_ string: String, expectedBytes: Int) -> (valid: Bool, detail: String) {
        guard let data = Data(base64Encoded: string) else {
            return (false, "Invalid Base64")
        }
        if data.count == expectedBytes {
            return (true, "\(expectedBytes) bytes")
        } else {
            return (false, "Expected \(expectedBytes) bytes, got \(data.count)")
        }
    }
    
    private func buildReport(exportIndex: Int, checks: [(name: String, passed: Bool, detail: String)]) -> ValidationResult {
        let passed = checks.filter { $0.passed }.count
        let failed = checks.filter { !$0.passed }.count
        
        var report = "--- Export #\(exportIndex) ---\n"
        report += "Passed: \(passed), Failed: \(failed)\n"
        
        for check in checks {
            let icon = check.passed ? "✅" : "❌"
            let detail = check.detail.isEmpty ? "" : " (\(check.detail))"
            report += "\(icon) \(check.name)\(detail)\n"
        }
        
        return ValidationResult(report: report, passed: passed, failed: failed)
    }
    
    private func showValidationResult(title: String, message: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        
        let textView = UITextView()
        textView.text = message
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        let containerView = UIView()
        containerView.addSubview(textView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 300)
        ])
        
        alert.view.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 50),
            containerView.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 10),
            containerView.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -10),
            alert.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
        
        alert.addAction(UIAlertAction(title: "Copy Report", style: .default) { _ in
            UIPasteboard.general.string = message
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        
        present(alert, animated: true)
    }
    
    // MARK: - Toast
    
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }
}
