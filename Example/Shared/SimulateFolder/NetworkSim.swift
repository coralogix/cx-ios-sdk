//
//  NetworkSim.swift
//  Elastiflix-iOS
//
//  Created by Coralogix DEV TEAM on 08/04/2024.
//

import Foundation
import  UIKit
import Coralogix
//import Alamofire
//import AFNetworking

class NetworkSim {
    static func failureNetworkRequest() {
        let url = URL(string: "https://www.google.com/404")!
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            //            if let data = data {
            //                let string = String(decoding: data, as: UTF8.self)
            //                print(string)
            //            }
        }
        task.resume()
    }
    
    static func sendSuccesfullRequest() {
        let url = URL(string: "https://www.coralogix.com")!
        let request = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            //            if let data = data {
            //                let string = String(decoding: data, as: UTF8.self)
            //                print(string)
            //            }
        }
        task.resume()
    }
    
    static func semdAFNetworkingRequest() {
//        let urlString = "https://jsonplaceholder.typicode.com/posts111"
//        let manager = AFHTTPSessionManager()
//        
//        // Set response serializer (JSON in this case)
//        manager.responseSerializer = AFJSONResponseSerializer()
//        
//        // Perform GET request
//        manager.get(urlString, parameters: nil, headers: nil, progress: nil, success: { task, responseObject in
//            // Success block
//            if let response = responseObject {
//                print("Response: \(response)")
//            }
//        }) { task, error in
//            // Failure block
//            print("Error: \(error.localizedDescription)")
//        }
    }
    
    static func setNetworkRequestContextSuccsess() {
        let dict = ["url" : "https://www.coralogix.com",
                    "host" : "coralogix.com",
                    "method" : "GET",
                    "status_code": 200,
                    "duration" : 5432,
                    "http_response_body_size": 234254,
                    "fragments": "",
                    "schema": "https"] as [String : Any]
        
        CoralogixRumManager.shared.sdk.setNetworkRequestContext(dictionary: dict)
    }
    
    static func setNetworkRequestContextFailure() {
        let dict = ["url" : "https://www.coralogix.com/404",
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
           let url = URL(string: "https://jsonplaceholder.typicode.com/posts")! // Example API

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
    
//    static func succesfullAlmofire() {
//        // Define the URL
//        let url = "https://jsonplaceholder.typicode.com/posts"
//        
//        // Create a request using Alamofire
//        AF.request(url, method: .get)
//            .validate()  // Validates the response status code
//            .responseData { response in
//                switch response.result {
//                case .success(let data):
//                    do {
//                        let json = try JSONSerialization.jsonObject(with: data, options: [])
//                        print("Request Successful")
//                        print("Response Data: \(json)")
//                    } catch {
//                        print("JSON Parsing Error: \(error)")
//                    }
//                case .failure(let error):
//                    print("Request failed with error: \(error)")
//                }
//            }
//    }
    
//    static func failureAlmofire() {
//        let url = "https://www.coralogix.com/404"
//        
//        // Create a request using Alamofire
//        AF.request(url, method: .get)
//            .validate()  // Validates the response status code
//            .responseData { response in
//                switch response.result {
//                case .success(let data):
//                    do {
//                        let json = try JSONSerialization.jsonObject(with: data, options: [])
//                        print("Request Successful")
//                        print("Response Data: \(json)")
//                    } catch {
//                        print("JSON Parsing Error: \(error)")
//                    }
//                case .failure(let error):
//                    print("Request failed with error: \(error)")
//                }
//            }
//    }
}
