//
//  SchemaValidationViewController.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 20/08/2024.
//

import UIKit
import Coralogix

class SchemaValidationViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let sessionIdLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let validateButton = UIButton(type: .system)
    private let copyRequestButton = UIButton(type: .system)
    private var lastRequestURL: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Verify schema"
        view.backgroundColor = .systemBackground

        setupUI()
        displaySessionId()
    }

    private func setupUI() {
        // Setup ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        view.addSubview(scrollView)

        // Setup ContentView
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Session ID Label
        sessionIdLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionIdLabel.numberOfLines = 0
        sessionIdLabel.textAlignment = .center
        sessionIdLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        sessionIdLabel.textColor = .label
        contentView.addSubview(sessionIdLabel)

        // Status Label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready to validate schema"
        contentView.addSubview(statusLabel)

        // Activity Indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        contentView.addSubview(activityIndicator)

        // Validate Button
        validateButton.translatesAutoresizingMaskIntoConstraints = false
        validateButton.setTitle("Validate Schema", for: .normal)
        validateButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        validateButton.backgroundColor = .systemBlue
        validateButton.setTitleColor(.white, for: .normal)
        validateButton.layer.cornerRadius = 10
        validateButton.addTarget(self, action: #selector(validateSchema), for: .touchUpInside)
        contentView.addSubview(validateButton)

        // Copy Request Button
        copyRequestButton.translatesAutoresizingMaskIntoConstraints = false
        copyRequestButton.setTitle("Copy Request", for: .normal)
        copyRequestButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        copyRequestButton.backgroundColor = .systemGray4
        copyRequestButton.setTitleColor(.label, for: .normal)
        copyRequestButton.layer.cornerRadius = 8
        copyRequestButton.addTarget(self, action: #selector(copyRequest), for: .touchUpInside)
        contentView.addSubview(copyRequestButton)

        // Constraints
        NSLayoutConstraint.activate([
            // ScrollView constraints
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // ContentView constraints
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Session ID Label
            sessionIdLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            sessionIdLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            sessionIdLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Status Label
            statusLabel.topAnchor.constraint(equalTo: sessionIdLabel.bottomAnchor, constant: 30),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // Activity Indicator
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),

            // Validate Button
            validateButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            validateButton.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 30),
            validateButton.widthAnchor.constraint(equalToConstant: 200),
            validateButton.heightAnchor.constraint(equalToConstant: 50),

            // Copy Request Button
            copyRequestButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            copyRequestButton.topAnchor.constraint(equalTo: validateButton.bottomAnchor, constant: 20),
            copyRequestButton.widthAnchor.constraint(equalToConstant: 150),
            copyRequestButton.heightAnchor.constraint(equalToConstant: 40),

            // Bottom constraint for content view
            copyRequestButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func displaySessionId() {
        if let sessionId = CoralogixRumManager.shared.getSessionId() {
            sessionIdLabel.text = "Session ID:\n\(sessionId.lowercased())"
        } else {
            sessionIdLabel.text = "Session ID:\nNo session available"
        }
    }

    @objc private func validateSchema() {
        guard let sessionId = CoralogixRumManager.shared.getSessionId() else {
            statusLabel.text = "Error: No session ID available"
            statusLabel.textColor = .systemRed
            return
        }

        // Update UI for loading state
        validateButton.isEnabled = false
        activityIndicator.startAnimating()
        statusLabel.text = "Validating schema..."
        statusLabel.textColor = .secondaryLabel

        let proxyUrl = Envs.PROXY_URL.rawValue
        let urlString = "\(proxyUrl)/validate/\(sessionId.lowercased())"
        print("🌐 Schema validation URL: \(urlString)")
        lastRequestURL = urlString // Store for copying
        guard let url = URL(string: urlString) else {
            handleError("Invalid URL")
            return
        }

        // Create and configure the request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        // Create a URLSession configuration that bypasses the proxy
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:] // Disable proxy
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config)

        // Perform the network request
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(data: data, response: response, error: error)
            }
        }

        task.resume()
    }

    @objc private func copyRequest() {
        guard let urlString = lastRequestURL else {
            let alert = UIAlertController(title: nil,
                                          message: "No request URL available",
                                          preferredStyle: .alert)
            present(alert, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                alert.dismiss(animated: true)
            }
            return
        }

        UIPasteboard.general.string = urlString

        // Show feedback
        let alert = UIAlertController(title: nil,
                                      message: "Request URL copied to clipboard!",
                                      preferredStyle: .alert)
        present(alert, animated: true)

        // Auto-dismiss after 1s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            alert.dismiss(animated: true)
        }
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        // Reset UI state
        validateButton.isEnabled = true
        activityIndicator.stopAnimating()

        if let error = error {
            handleError("Network error: \(error.localizedDescription)")
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            handleError("Invalid response")
            return
        }

        if httpResponse.statusCode == 200 {
            validateSchemaResponse(data: data)
        } else {
            handleError("HTTP Error: \(httpResponse.statusCode)")
        }
    }

    private func validateSchemaResponse(data: Data?) {
        guard let data = data else {
            handleError("No data received")
            return
        }

        do {
            // Parse JSON response
            let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]

            guard let data = jsonArray else {
                handleError("Invalid JSON format")
                return
            }
            
            // TESTING: Save validation response for UI tests
            if CommandLine.arguments.contains("--uitesting") {
                saveValidationDataForTesting(data)
            }

            var allValid = true
            var errorMessages: [String] = []

            // Validate each item in the response
            for item in data {
                if let validationResult = item["validationResult"] as? [String: Any],
                   let statusCode = validationResult["statusCode"] as? Int {

                    if statusCode != 200 {
                        allValid = false

                        // Handle message as array of strings
                        if let messageArray = validationResult["message"] as? [String] {
                            // Add each message from the array
                            for message in messageArray {
                                errorMessages.append(message)
                            }
                        } else if let message = validationResult["message"] as? String {
                            // Fallback for single string message
                            errorMessages.append(message)
                        } else {
                            // Fallback for no message
                            errorMessages.append("Invalid status code: \(statusCode)")
                        }

                        // Print the full validationResult for debugging
                        print("❌ Validation failed for item:")
                        print("   validationResult: \(validationResult)")
                        if let messageArray = validationResult["message"] as? [String] {
                            print("   messages:")
                            for (index, message) in messageArray.enumerated() {
                                print("     [\(index)]: \(message)")
                            }
                        }
                    }
                }
            }

            // Check if we have any data to validate
            if data.isEmpty {
                allValid = false
                errorMessages.append("No logs found for validation.")
            }

            // Show appropriate result
            if allValid {
                statusLabel.text = "All logs are valid! ✅"
                statusLabel.textColor = .systemGreen
            } else {
                let errorText = "Validation Failed:\n" + errorMessages.joined(separator: "\n")
                statusLabel.text = errorText
                statusLabel.textColor = .systemRed
            }

        } catch {
            handleError("Failed to parse response: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Testing Support
    
    private func saveValidationDataForTesting(_ validationData: [[String: Any]]) {
        let testDataPath = "/tmp/coralogix_validation_response.json"
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: validationData, options: .prettyPrinted)
            try jsonData.write(to: URL(fileURLWithPath: testDataPath))
            print("💾 Saved validation data for testing: \(testDataPath)")
            print("💾 Saved \(validationData.count) log entries")
        } catch {
            print("❌ Failed to save validation data: \(error)")
        }
    }

    private func handleError(_ message: String) {
        validateButton.isEnabled = true
        activityIndicator.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = .systemRed
    }
}
