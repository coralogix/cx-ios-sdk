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
        button.setTitle("Copy Full Log to Clipboard", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.addTarget(self, action: #selector(copyFullLog), for: .touchUpInside)
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
            copyFullLogButton
        ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 20
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
                Self.totalSpansReceived += data.spanCount
                
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
                    Self.fullJsonLogs.append(jsonString)
                    if Self.fullJsonLogs.count > 50 {
                        Self.fullJsonLogs.removeFirst()
                    }
                    
                    let truncated = jsonString.count > 500 
                        ? String(jsonString.prefix(500)) + "... (truncated, use 'Copy Full Log' for complete JSON)"
                        : jsonString
                    logMessage += "\nJSON Preview:\n\(truncated)"
                }
                
                self?.appendLog(logMessage)
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
    
    // MARK: - Toast
    
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }
}
