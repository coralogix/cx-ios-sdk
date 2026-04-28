import SwiftUI
import Coralogix

struct SchemaValidationView: View {
    @State private var statusText = "Ready to validate schema"
    @State private var statusColor = Color.secondary
    @State private var isValidating = false
    @State private var lastRequestURL: String?
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                sessionIDCard

                statusCard

                VStack(spacing: 12) {
                    Button {
                        validateSchema()
                    } label: {
                        Text("Validate Schema")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidating ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(isValidating)

                    Button {
                        copyRequest()
                    } label: {
                        Text("Copy Request")
                            .font(.subheadline)
                            .frame(maxWidth: 150)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray4))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Verify schema")
        .navigationBarTitleDisplayMode(.inline)
        .trackCXView(name: "Schema Validation")
        .toast(message: $toastMessage)
    }

    private var sessionIDCard: some View {
        let sessionID = CoralogixRumManager.shared.getSessionId()?.lowercased() ?? "No session available"
        return VStack(alignment: .center, spacing: 4) {
            Text("Session ID:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(sessionID)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var statusCard: some View {
        Group {
            if isValidating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Validating schema...")
                        .foregroundColor(.secondary)
                }
            } else {
                Text(statusText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func validateSchema() {
        guard let sessionId = CoralogixRumManager.shared.getSessionId() else {
            statusText = "Error: No session ID available"
            statusColor = .red
            return
        }
        isValidating = true
        statusColor = .secondary

        let proxyUrl = Envs.PROXY_URL.rawValue
        let urlString = "\(proxyUrl)/validate/\(sessionId.lowercased())"
        lastRequestURL = urlString
        guard let url = URL(string: urlString) else {
            handleError("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        URLSession(configuration: config).dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { handleResponse(data: data, response: response, error: error) }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        isValidating = false
        if let error = error { handleError("Network error: \(error.localizedDescription)"); return }
        guard let http = response as? HTTPURLResponse else { handleError("Invalid response"); return }
        if http.statusCode == 200 {
            parseValidationResponse(data: data)
        } else {
            handleError("HTTP Error: \(http.statusCode)")
        }
    }

    private func parseValidationResponse(data: Data?) {
        guard let data = data,
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            handleError("Invalid JSON format")
            return
        }
        if jsonArray.isEmpty {
            handleError("No logs found for validation.")
            return
        }
        var allValid = true
        var errorMessages: [String] = []
        for item in jsonArray {
            if let result = item["validationResult"] as? [String: Any],
               let code = result["statusCode"] as? Int, code != 200 {
                allValid = false
                if let msgs = result["message"] as? [String] { errorMessages.append(contentsOf: msgs) }
                else if let msg = result["message"] as? String { errorMessages.append(msg) }
                else { errorMessages.append("Invalid status code: \(code)") }
            }
        }
        if allValid {
            statusText = "All logs are valid! ✅"
            statusColor = .green
        } else {
            statusText = "Validation Failed:\n" + errorMessages.joined(separator: "\n")
            statusColor = .red
        }
    }

    private func handleError(_ message: String) {
        isValidating = false
        statusText = message
        statusColor = .red
    }

    private func copyRequest() {
        guard let urlString = lastRequestURL else {
            toastMessage = "No request URL available"
            return
        }
        UIPasteboard.general.string = urlString
        toastMessage = "Request URL copied to clipboard!"
    }
}
