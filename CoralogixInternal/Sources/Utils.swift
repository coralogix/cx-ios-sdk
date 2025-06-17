//
//  Utils.swift
//
//
//  Created by Coralogix DEV TEAM on 14/01/2025.
//

#if canImport(UIKit)
import UIKit
#endif


public enum ImageFormat {
    case png
    case jpeg(compressionQuality: CGFloat)
}

public enum Global: String {
    case sdk = "1.0.23"
    case swiftVersion = "5.9"
    case coralogixPath = "/browser/v1beta/logs"
    case sessionReplayPath = "/browser/alpha/sessionrecording"

    public enum BatchSpan: Int {
        case maxExportBatchSize = 50
        case scheduleDelay = 2
    }
    
    static let monitoredPaths: Set<String> = [
        Global.coralogixPath.rawValue,
        Global.sessionReplayPath.rawValue
    ]
    
    // Function to check if the URL contains any monitored path
    public static func containsMonitoredPath(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return monitoredPaths.contains(url.path)
    }
    
    public static func appVersionInfo(indludeBuild: Bool = true) -> String {
        let dictionary = Bundle.main.infoDictionary!
        if let version = dictionary["CFBundleShortVersionString"] as? String,
           let build = dictionary["CFBundleVersion"] as? String {
            return indludeBuild ? version + " (" + build + ")" : version
        }
        return ""
    }
    
    public static func getOs() -> String {
        return UIDevice.current.systemName.lowercased()
    }
    
    public static func appName() -> String {
        return ProcessInfo.processInfo.processName
    }
    
    public static func getKeyWindow(connectedScenes: Set<UIScene> = UIApplication.shared.connectedScenes) -> UIWindow? {
        guard let windowScene = connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            Log.e("No active window scene found")
            return nil
        }
        return windowScene.windows.first(where: { $0.isKeyWindow })
    }
    
    public static func cgImage(from data: Data) -> CGImage? {
        // Create a CGImageSource from the data
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            Log.e("Failed to create image source.")
            return nil
        }
        
        // Create CGImage from the source
        let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        return cgImage
    }
    
    public static func osVersionInfo() -> String {
        return ProcessInfo.processInfo.operatingSystemVersionString
    }
    
    public static func getDeviceModel() -> String {
        return UIDevice.current.model
    }
    
    public static func modelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo) // Loads the underlying hardware info into sysinfo
        let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))
        let identifier = String(bytes: data, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "unknown"
        return identifier
    }
    
    public static var identifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        
        let identifier = mirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }()
    
    public static func ciImageToData(_ ciImage: CIImage, format: ImageFormat = .png, context: CIContext = CIContext()) -> Data? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        switch format {
        case .png:
            return uiImage.pngData()
        case .jpeg(let compressionQuality):
            return uiImage.jpegData(compressionQuality: compressionQuality)
        }
    }
    
    
    public static func updateLocation(tapData: inout [String: Any], touch: UITouch) {
        let locationInScreen = touch.location(in: nil) // UIKit coordinate system (top-left origin)
        tapData[Keys.positionX.rawValue] = locationInScreen.x
        tapData[Keys.positionY.rawValue] = locationInScreen.y
    }
    
    public static func isEmulator() -> Bool {
#if targetEnvironment(simulator)
        // Code to execute on the Simulator
        return true
#else
        // Code to execute on a real device
        return false
#endif
    }
    // swiftlint:disable function_body_length
    // swiftlint:disable cyclomatic_complexity
    public static func getDeviceName() -> String {
        switch identifier {
#if os(iOS)
        case "iPod5,1": return "iPodTouch5"
        case "iPod7,1": return "iPodTouch6"
        case "iPod9,1": return "iPodTouch7"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3": return "iPhone4"
        case "iPhone4,1": return "iPhone4s"
        case "iPhone5,1", "iPhone5,2": return "iPhone5"
        case "iPhone5,3", "iPhone5,4": return "iPhone5c"
        case "iPhone6,1", "iPhone6,2": return "iPhone5s"
        case "iPhone7,2": return "iPhone6"
        case "iPhone7,1": return "iPhone6Plus"
        case "iPhone8,1": return "iPhone6s"
        case "iPhone8,2": return "iPhone6sPlus"
        case "iPhone9,1", "iPhone9,3": return "iPhone7"
        case "iPhone9,2", "iPhone9,4": return "iPhone7Plus"
        case "iPhone8,4": return "iPhoneSE"
        case "iPhone10,1", "iPhone10,4": return "iPhone8"
        case "iPhone10,2", "iPhone10,5": return "iPhone8Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhoneX"
        case "iPhone11,2": return "iPhoneXS"
        case "iPhone11,4", "iPhone11,6": return "iPhoneXSMax"
        case "iPhone11,8": return "iPhoneXR"
        case "iPhone12,1": return "iPhone11"
        case "iPhone12,3": return "iPhone11Pro"
        case "iPhone12,5": return "iPhone11ProMax"
        case "iPhone12,8": return "iPhoneSE2"
        case "iPhone13,2": return "iPhone12"
        case "iPhone13,1": return "iPhone12Mini"
        case "iPhone13,3": return "iPhone12Pro"
        case "iPhone13,4": return "iPhone12ProMax"
        case "iPhone14,5": return "iPhone13"
        case "iPhone14,4": return "iPhone13Mini"
        case "iPhone14,2": return "iPhone13Pro"
        case "iPhone14,3": return "iPhone13ProMax"
        case "iPhone14,6": return "iPhoneSE3"
        case "iPhone14,7": return "iPhone14"
        case "iPhone14,8": return "iPhone14Plus"
        case "iPhone15,2": return "iPhone14Pro"
        case "iPhone15,3": return "iPhone14ProMax"
        case "iPhone15,4": return "iPhone15"
        case "iPhone15,5": return "iPhone15Plus"
        case "iPhone16,1": return "iPhone15Pro"
        case "iPhone16,2": return "iPhone15ProMax"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4": return "iPad2"
        case "iPad3,1", "iPad3,2", "iPad3,3": return "iPad3"
        case "iPad3,4", "iPad3,5", "iPad3,6": return "iPad4"
        case "iPad4,1", "iPad4,2", "iPad4,3": return "iPadAir"
        case "iPad5,3", "iPad5,4": return "iPadAir2"
        case "iPad6,11", "iPad6,12": return "iPad5"
        case "iPad7,5", "iPad7,6": return "iPad6"
        case "iPad11,3", "iPad11,4": return "iPadAir3"
        case "iPad7,11", "iPad7,12": return "iPad7"
        case "iPad11,6", "iPad11,7": return "iPad8"
        case "iPad12,1", "iPad12,2": return "iPad9"
        case "iPad13,18", "iPad13,19": return "iPad10"
        case "iPad13,1", "iPad13,2": return "iPadAir4"
        case "iPad13,16", "iPad13,17": return "iPadAir5"
        case "iPad2,5", "iPad2,6", "iPad2,7": return "iPadMini"
        case "iPad4,4", "iPad4,5", "iPad4,6": return "iPadMini2"
        case "iPad4,7", "iPad4,8", "iPad4,9": return "iPadMini3"
        case "iPad5,1", "iPad5,2": return "iPadMini4"
        case "iPad11,1", "iPad11,2": return "iPadMini5"
        case "iPad14,1", "iPad14,2": return "iPadMini6"
        case "iPad6,3", "iPad6,4": return "iPadPro9Inch"
        case "iPad6,7", "iPad6,8": return "iPadPro12Inch"
        case "iPad7,1", "iPad7,2": return "iPadPro12Inch2"
        case "iPad7,3", "iPad7,4": return "iPadPro10Inch"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPadPro11Inch"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPadPro12Inch3"
        case "iPad8,9", "iPad8,10": return "iPadPro11Inch2"
        case "iPad8,11", "iPad8,12": return "iPadPro12Inch4"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPadPro11Inch3"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPadPro12Inch5"
        case "iPad14,3", "iPad14,4": return "iPadPro11Inch4"
        case "iPad14,5", "iPad14,6": return "iPadPro12Inch6"
        case "AudioAccessory1,1": return "homePod"
        case "i386", "x86_64", "arm64": return ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"
#endif
        default: return identifier
        // swiftlint:enable function_body_length
        // swiftlint:enable cyclomatic_complexity
        }
    }
}

public enum CoralogixDomain: String {
    case EU1 = "https://ingress.eu1.rum-ingress-coralogix.com" // eu-west-1 (Ireland)
    case EU2 = "https://ingress.eu2.rum-ingress-coralogix.com" // eu-north-1 (Stockholm)
    case US1 = "https://ingress.us1.rum-ingress-coralogix.com" // us-east-2 (Ohio)
    case US2 = "https://ingress.us2.rum-ingress-coralogix.com" // us-west-2 (Oregon)
    case AP1 = "https://ingress.ap1.rum-ingress-coralogix.com" // ap-south-1 (Mumbai)
    case AP2 = "https://ingress.ap2.rum-ingress-coralogix.com" // ap-southeast-1 (Singapore)
    case AP3 = "https://ingress.ap3.rum-ingress-coralogix.com" // ap-southeast-3 (Jakarta)
    case STG = "https://ingress.staging.rum-ingress-coralogix.com"

    func stringValue() -> String {
        switch self {
        case .EU1:
            return "EU1"
        case .EU2:
            return "EU2"
        case .US1:
            return "US1"
        case .US2:
            return "US2"
        case .AP1:
            return "AP1"
        case .AP2:
            return "AP2"
        case .AP3:
            return "AP3"
        case .STG:
            return "STG"
        }
    }
}
