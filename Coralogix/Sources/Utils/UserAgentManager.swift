//
//  UserAgentManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 30/08/2025.
//
import Foundation
import CoralogixInternal
import WebKit

public class UserAgentManager: NSObject, WKNavigationDelegate {
    // A private variable to hold the user agent string.
    private var cachedUserAgent: String?

    // A private queue for any asynchronous work.
    private let userAgentQueue = DispatchQueue(label: Keys.queueUserAgentQueue.rawValue)

    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        return webView
    }()

    public static let shared = UserAgentManager()

    // Private initializer to enforce singleton pattern.
    private override init() {
        super.init()
        // Load an empty HTML page to trigger the delegate method
        self.loadWebView()
    }

    private func loadWebView() {
        // Must be on the main thread
        DispatchQueue.main.async { [weak self] in
            // Use a simple, empty HTML string to load quickly
            let htmlString = "<html><body></body></html>"
            self?.webView.loadHTMLString(htmlString, baseURL: nil)
        }
    }
    /// Public method to get the user agent.
    /// It returns the cached value if available, otherwise a placeholder.
    public func getUserAgent() -> String {
        return cachedUserAgent ?? Keys.undefined.rawValue
    }

    /// Internal method to perform the asynchronous user agent retrieval.
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] (result, error) in
            if let userAgent = result as? String {
                self?.cachedUserAgent = userAgent
            } else {
                Log.e("Error retrieving user agent: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }
}
