//
//  Keys.swift
//  DemoAppSwift
//
//  Created by Coralogix DEV TEAM on 23/05/2024.
//

import Foundation

enum Keys: String {
    case failureNetworkRequest = "❌ Failure Network Request"
    case succesfullNetworkRequest = "✅ Succesfull Network Request"
    case sendNSException = "NSException"
    case sendNSError = "NSError"
    case sendErrorString = "Error String"
    case sendErrorStacktraceString = "Error Stacktrace (Flutter)"
    case sendLogWithData = "Custom Log"
    case sendCrash = "Crash"
    case shutDownCoralogixRum = "SDK Shutdown"
    case updateLabels = "Update Labels"
    case pageController = "PageControl view"
    case failureNetworkRequestFlutter = "❌ Failure Network Request (Flutter)"
    case succesfullNetworkRequestFlutter = "✅ Succesfull Network Request (Flutter)"
    case networkInstumentation =  "Network Instumentation"
    case errorInstumentation =  "Error Instumentation"
    case sdkFunctions = "SDK Functions"
    case userActionsInstumentation = "User Actions Instumentation"
    case modalPresentation = "Modal Presentation"
    case segmentedCollectionView = "Segmented / Collection"
    case simulateANR = "Simulate ANR"
    case succesfullAlamofire = "✅ Succesfull Alamofire Request"
    case failureAlamofire = "❌ Failure Alamofire Request"
    case sessionReplay = "Session Replay"
    case startRecoding = "Start Recoding"
    case stopRecoding = "Stop Recoding"
    case splitRecoding = "Split Recoding"
    case captureEvent = "Capture Event"
    case creditCardElement = "CreditCard Element"
    case creditCardImgElement = "Credit Card Img Element"
    case updateSessionId = "Update session Id"
    case afnetworkingRequest = "🔌 AFNetworking Request"
    case postRequestToServer = "🔌 Post Request to Server"
    case getRequestToServer = "🔌 Get Request to Server"
    case clock = "Clock"
    case alamofireUploadRequest = "🔌 Upload Alamofire Request"
    case downloadSDWebImage = "🔌 Download SDWebImage"
    case schemaValidation = "Verify schema"
    case reportMobileVitalsMeasurement = "Report Mobile Vitals Measurement"
    case customLabels = "Log with Custom Labels"
}
