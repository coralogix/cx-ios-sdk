//
//  NetworkSim.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import UIKit
import Coralogix
import Alamofire
import AFNetworking
import SDWebImage

//https://github.com/AFNetworking/AFNetworking.git
//https://github.com/Alamofire/Alamofire.git
//https://github.com/SDWebImage/SDWebImage.git

class NetworkSim {
    static let url = "https://jsonplaceholder.typicode.com/posts"
    static let errorUrl = "https://jsonplaceholder.typicode.com/posts1"
    
    static func failureNetworkRequest() {
        let url = URL(string: errorUrl)!
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("GET Request Error:", error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("GET Response Code:", httpResponse.statusCode)
            }
            
            if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                print("GET Response Data:\n", jsonString)
            }
        }
        task.resume()
    }
    
    static func sendSuccesfullRequest() {
        let url = URL(string: url)!
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("GET Request Error:", error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("GET Response Code:", httpResponse.statusCode)
            }
            
            if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                print("GET Response Data:\n", jsonString)
            }
        }
        task.resume()
    }
    
    static func sendAFNetworkingRequest() {
        let manager = AFHTTPSessionManager()
        
        // Set response serializer (JSON in this case)
        manager.responseSerializer = AFJSONResponseSerializer()
        
        // Perform GET request
        manager.get(url, parameters: nil, headers: nil, progress: nil, success: { task, responseObject in
            // Success block
            if let response = responseObject {
                print("Response: \(response)")
            }
        }) { task, error in
            // Failure block
            print("Error: \(error.localizedDescription)")
        }
    }
    
    static func setNetworkRequestContextSuccsess() {
        let dict = ["url" : "\(url)",
                    "host" : "coralogix.com",
                    "method" : "GET",
                    "status_code": 200,
                    "duration" : 5432,
                    "http_response_body_size": 234254,
                    "fragments": "",
                    "schema": "https"] as [String : Any]
        
        CoralogixRumManager.shared.sdk.setNetworkRequestContext(dictionary: dict)
    }
    
    static func setNetworkRequestContextFlutterSuccsess() {
        let dict = ["url" : "\(url)",
                    "host" : "coralogix.com",
                    "method" : "GET",
                    "status_code": 200,
                    "duration" : 5432,
                    "http_response_body_size": 234254,
                    "fragments": "",
                    "schema": "https",
                    "customTraceId":"customTraceId",
                    "customSpanId":"customSpanId"] as [String : Any]
        
        CoralogixRumManager.shared.sdk.setNetworkRequestContext(dictionary: dict)
    }
    
    static func setNetworkRequestContextFailure() {
        let dict = ["url" : errorUrl,
                    "host" : "coralogix.com",
                    "method" : "GET",
                    "status_code": 404,
                    "duration" : 5432,
                    "http_response_body_size": 234254,
                    "fragments": "/404",
                    "schema": "https"] as [String : Any]
        
        CoralogixRumManager.shared.sdk.setNetworkRequestContext(dictionary: dict)
    }
    
    static func performGetRequest() {
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")! // Example API
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("GET Request Error:", error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("GET Response Code:", httpResponse.statusCode)
            }
            
            if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                print("GET Response Data:\n", jsonString)
            }
        }
        
        task.resume()
    }
    
    static func performPostRequest() {
        let url = URL(string: url)! // Example API
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "title": "Swift Request",
            "body": "This is a simulated POST request.",
            "userId": 1
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("POST Request Error:", error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("POST Response Code:", httpResponse.statusCode)
            }
            
            if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                print("POST Response Data:\n", jsonString)
            }
        }
        
        task.resume()
    }
    
    static func succesfullAlamofire() {
        // Create a request using Alamofire
        AF.request(url, method: .get)
            .validate()  // Validates the response status code
            .responseData { response in
                switch response.result {
                case .success(let data):
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: [])
                        print("Request Successful")
                        print("Response Data: \(json)")
                    } catch {
                        print("JSON Parsing Error: \(error)")
                    }
                case .failure(let error):
                    print("Request failed with error: \(error)")
                }
            }
    }
    
    static func failureAlamofire() {
        AF.request(errorUrl, method: .get)
            .validate()  // Validates the response status code
            .responseData { response in
                switch response.result {
                case .success(let data):
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: [])
                        print("Request Successful")
                        print("Response Data: \(json)")
                    } catch {
                        print("JSON Parsing Error: \(error)")
                    }
                case .failure(let error):
                    print("Request failed with error: \(error)")
                }
            }
    }
    
    static func createSampleFile() -> URL? {
        let text = "Test file content"
        let fileName = "sample.txt"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Error writing file: \(error)")
            return nil
        }
    }
    
    static func createSampleFile(sizeInMB: Int = 10) -> URL? {
        let baseText = "This is a line in a large test file.\n"
        let repeatedCount = (sizeInMB * 1024 * 1024) / baseText.utf8.count  // Calculate how many lines needed
        let fileContent = String(repeating: baseText, count: repeatedCount)
        let fileName = "large_sample.txt"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Created file at: \(fileURL), size: ~\(sizeInMB)MB")
            return fileURL
        } catch {
            print("❌ Error writing file: \(error)")
            return nil
        }
    }
    
    static func uploadFile(fileURL: URL?) {
        let url = "https://api.escuelajs.co/api/v1/files/upload"
        
        // Simulated file — use a file from your local bundle or Documents directory
        guard let fileURL = fileURL else {
            print("UploadFile: File URL not found.")
            return
        }
        
        // Start upload
        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(fileURL, withName: "file", fileName: "sample.txt", mimeType: "text/plain")
        }, to: url)
        .uploadProgress { progress in
            print("Upload Progress: \(progress.fractionCompleted)")
        }
        .response { response in
            switch response.result {
            case .success(let data):
                print("Upload succeeded")
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }
            case .failure(let error):
                print("Upload failed: \(error)")
            }
        }
    }
    
    static func downloadImage() {
        let urlString = "https://www.google.com/url?sa=i&url=https%3A%2F%2Funikal.az%2Fnews%2F490204%2Ftramp-meshur-aparicinin-verilisini-baglatdirir&psig=AOvVaw1NJs_lRnGqkjnhDu8j3AOd&ust=1753266023938000&source=images&cd=vfe&opi=89978449&ved=2ahUKEwjIstmFn9COAxX0UqQEHfprJpkQjRx6BAgAEBo"
        guard let url = URL(string: urlString) else { return }
        
        DispatchQueue.global(qos: .background).async {
            SDWebImageDownloader.shared.downloadImage(
                with: url,
                options: [],
                progress: nil
            ) { image, data, error, finished in
                guard let image = image, finished else { return }
                DispatchQueue.main.async {
                    let imageView = UIImageView(image: image)
                    if imageView.image != nil {
                        print("Image downloaded")
                    }
                }
            }
        }
    }
    
    static func callAsyncAwait() {
        Task {
            do {
                let response = try await AuthServiceAsync.shared.simulateAsyncAwaitCall()
                Log.d("Success: \(response.title)")
            } catch {
                Log.e("Error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Simulates customer's SSL pinning scenario:
    /// - URLSession with custom delegate (SSL pinning only)
    /// - Using async/await
    /// - Delegate does NOT implement URLSessionTaskDelegate methods
    /// This replicates the customer's issue where network traces go missing
    static func callAsyncAwaitWithSSLPinning() {
        Task {
            do {
                let response = try await SSLPinningSession.shared.makeRequest()
                Log.d("✅ SSL Pinning Request Success: \(response.title)")
            } catch {
                Log.e("❌ SSL Pinning Request Error: \(error.localizedDescription)")
            }
        }
    }
    
    struct DataResponse: Codable {
        let id: Int
        let title: String
        let body: String
        let userId: Int
    }

    final class AuthServiceAsync {
        static let shared = AuthServiceAsync()
        private init() {}

        enum APIError: Error, LocalizedError {
            case http(status: Int, body: String)

            var errorDescription: String? {
                switch self {
                case .http(let status, let body):
                    return "HTTP \(status): \(body)"
                }
            }
        }

        func simulateAsyncAwaitCall() async throws -> DataResponse {
            guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts") else {
                throw URLError(.badURL)
            }
            
            let requestBody: [String: Any] = [
                "title": "Swift Request",
                "body": "This is a simulated POST request.",
                "userId": 1
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            request.httpBody =  try? JSONSerialization.data(withJSONObject: requestBody, options: [])
    
            let (data, response) = try await URLSession.shared.data(for: request)
            
            
            if let httpResponse = response as? HTTPURLResponse {
                print("POST Response Code:", httpResponse.statusCode)
            }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("POST Response Data:\n", jsonString)
            }
        
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(DataResponse.self, from: data)
        }
    }
    
    /// Replicates customer's SSL pinning setup
    /// This demonstrates the bug where async/await + custom delegate = no instrumentation
    final class SSLPinningSession: NSObject {
        static let shared = SSLPinningSession()
        
        // URLSession with custom delegate (like customer's setup)
        private lazy var session: URLSession = {
            URLSession(
                configuration: .default,
                delegate: self,  // ← Custom delegate for SSL pinning
                delegateQueue: nil
            )
        }()
        
        private override init() {
            super.init()
        }
        
        func makeRequest() async throws -> DataResponse {
            guard let url = URL(string: "https://jsonplaceholder.typicode.com/posts") else {
                throw URLError(.badURL)
            }
            
            let requestBody: [String: Any] = [
                "title": "SSL Pinning Request",
                "body": "Testing async/await with SSL pinning delegate",
                "userId": 1
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
            
            print("🔐 Making async/await request with SSL pinning delegate...")
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔐 SSL Pinning Response Code:", httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(DataResponse.self, from: data)
        }
    }
}

// MARK: - SSL Pinning Delegate (Mimics Customer's Setup)
extension NetworkSim.SSLPinningSession: URLSessionDelegate {
    /// This delegate ONLY handles SSL challenges
    /// It does NOT implement URLSessionTaskDelegate methods
    /// This is exactly like the customer's setup
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        print("🔐 SSL challenge received (would validate cert here)")
        
        // In real app, would validate certificate against pinned certs
        // For demo, just accept default handling
        return (.performDefaultHandling, nil)
    }
}
