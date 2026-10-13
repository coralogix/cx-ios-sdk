//
//  UserAgentManager.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 30/08/2025.
//
import Foundation
import CoralogixInternal
#if os(iOS)
import WebKit
#endif

public class UserAgentManager: NSObject {
    // A private variable to hold the user agent string.
    private var cachedUserAgent: String?

    // A private queue for any asynchronous work.
    private let userAgentQueue = DispatchQueue(label: Keys.queueUserAgentQueue.rawValue)

    #if os(iOS)
    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        return webView
    }()
    #endif

    public static let shared = UserAgentManager()

    // Private initializer to enforce singleton pattern.
    private override init() {
        super.init()
        // Load an empty HTML page to trigger the delegate method
        self.loadWebView()
    }

    private func loadWebView() {
        // Without WebKit (tvOS) there is no web view to ask, so the user agent stays undefined.
        #if os(iOS)
        // Must be on the main thread
        DispatchQueue.main.async { [weak self] in
            // Use a simple, empty HTML string to load quickly
            let htmlString = "<html><body></body></html>"
            self?.webView.loadHTMLString(htmlString, baseURL: nil)
        }
        #endif
    }
    /// Public method to get the user agent.
    /// It returns the cached value if available, otherwise a placeholder.
    public func getUserAgent() -> String {
        return cachedUserAgent ?? Keys.undefined.rawValue
    }
}

#if os(iOS)
extension UserAgentManager: WKNavigationDelegate {
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
#endif
