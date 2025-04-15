//
//  Helper.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 08/12/2024.
//

import UIKit
import CoralogixInternal

class Utils {
    
    /// Saves the provided `CIImage` to the specified URL.
    /// - Parameters:
    ///   - image: The `CIImage` to save.
    ///   - url: The destination file URL.
    /// - Throws: An error if the image could not be saved.
    static func saveImage(_ ciImage: CIImage, outputURL: URL, completion: (Bool) -> Void) {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            Log.e("Failed to create CGImage.")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let pngData = uiImage.pngData() else {
            Log.e("Failed to create PNG data.")
            return
        }
                
        do {
            try pngData.write(to: outputURL)
            Log.d("Image saved to \(outputURL.path)")
            completion(true)
        } catch {
            Log.e("Failed to save image: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    static func saveImage(_ cgImage: CGImage, outputURL: URL, completion: (Bool) -> Void) {
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let pngData = uiImage.pngData() else {
            Log.e("Failed to create PNG data.")
            return
        }
        
        do {
            try pngData.write(to: outputURL)
            Log.d("Image saved to \(outputURL.path)")
            completion(true)
        } catch {
            Log.e("Failed to save image: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    static func convertCIImageToCGImage(_ ciImage: CIImage) -> CGImage? {
        // Create a CIContext instance
        let context = CIContext()
        
        // Use the context to create a CGImage from the CIImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            Log.e("Conversion failed: Unable to create CGImage.")
            return nil
        }
        
        return cgImage
    }
    
    static let creditCardWords: [String] = [
        // Cardholder Information
        "name",
        "cardholder",
        
        // Card Details
        "credit",
        "debit",
        "prepaid",
        "virtual",
        "card",
        "number",
        
        // Issuer Information
        "bank",
        "issuer",
        "financial",
        "institution",
        "company",
        
        // Brand/Network
        "visa",
        "mastercard",
        "mastercard.",
        "american express",
        "american",
        "express",
        "gold",
        "discover",
        "diners club",
        "unionPay",
        "jbc",
        "Visa Gold",
        "© AMEX",
        
        // Security and Features
        "chip",
        "eMV",
        "contactless",
        "tap",
        "payWave",
        "payPass",
        "security",
        "secure",
        "authentication",
        
        // Expiration
        "valid thru",
        "expiration date",
        "expires",
        "mm/yy",
        "mm/yyyy",
        
        // Service and Support
        "customer service",
        "member since",
        "hotline",
        "help",
        "call",
        "support",
        "•payback",
        
        // Additional Info
        "rewards",
        "points",
        "cashback",
        "platinum",
        "gold",
        "silver",
        "black",
        "classic",
        "world",
        "elite",
        
        // Regulatory and Compliance
        "not transferable",
        "authorized signature",
        "terms",
        "conditions",
        "agreement",
        
        // Card Usage
        "use",
        "only",
        "atm",
        "purchase"
    ]
    
    static let creditCardPrefixes: [String] = [
        // Visa
        "4000", "4001", "4002", "4003", "4004", "4005", "4006", "4007", "4008", "4009",
        "4010", "4999", // Visa range
        
        // Mastercard
        "5100", "5101", "5102", "5103", "5104", "5105", "5106", "5107", "5108", "5109",
        "5200", "5599", // Mastercard range
        "2221", "2720", // New Mastercard range
        "5381", // Newly added Mastercard prefix
        
        // American Express
        "3400", "3401", "3402", "3403", "3404", "3405", "3406", "3407", "3408", "3409",
        "3700", "3799", // American Express range
        "3759", // Added American Express test card prefix
        
        // Discover
        "6011",
        "6221", "6222", "6223", "6224", "6225", "6226", "6227", "6228", "6229",
        "6440", "6499", // Discover range
        "6500", "6599", // Discover range
        
        // Diners Club
        "3000", "3059", // Diners Club range
        "3600", "3699",
        "3800", "3899",
        
        // JCB (Japan Credit Bureau)
        "3528", "3529", "3530", "3531", "3532", "3533", "3534", "3535", "3536", "3537",
        "3589", // JCB range
        
        // UnionPay
        "6200", "6299", // UnionPay range
        
        // Maestro
        "5018", "5020", "5038",
        "6304", "6759",
        "6761", "6762", "6763",
        
        // RuPay (India)
        "6070", "6071", "6072", "6073", "6074", "6075", "6076", "6077", "6078", "6079",
        "6521", "6522",
        
        // Testing Cards
        "4111", // Visa test card (popular test card prefix)
        "4012", // Visa test card
        "4000", // Visa generic test
        "5555", // Mastercard generic test
        "2223", // Mastercard test card from newer range
        "3782", // American Express test card
        "3759", // American Express test card
        "5381", // Mastercard test or real card prefix
        "6011", // Discover test card
        "3056", // Diners Club test card
        "3530", // JCB test card
        "6200", // UnionPay test card
        "5018", // Maestro test card
        "4485", // Visa test card
        "4716"  // Visa test card
    ]
    
    static func compareImages(image1: CGImage, image2: CGImage) -> Bool {
        guard let hash1 = image1.sha256Digest(),
              let hash2 = image2.sha256Digest() else {
            Log.e("Failed to compute MD5 hashes for one or both images.")
            return false
        }
        
        Log.d("Hash 1: \(hash1)")
        Log.d("Hash 2: \(hash2)")
        
        return hash1 == hash2
    }
    
    // Save the URLs array to disk
    static func saveURLsToDisk(urls: [URL]) {
        do {
            // Convert array to data
            let data = try PropertyListEncoder().encode(urls)
            
            // Write data to file in Documents directory
            let fileURL = getURLsFilePath()
            try data.write(to: fileURL)
            Log.d("Saved URLs to disk at \(fileURL)")
        } catch {
            Log.e("Failed to save URLs to disk: \(error)")
        }
    }
    
    static func deleteURLsFromDisk() {
        let fileURL = getURLsFilePath()
        let fileManager = FileManager.default
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                Log.d("Deleted URLs file from disk at \(fileURL)")
            } else {
                Log.d("No URLs file exists at \(fileURL) to delete.")
            }
        } catch {
            Log.e("Failed to delete URLs file from disk: \(error)")
        }
    }

    // Get the file path for saving the URLs array
    static func getURLsFilePath() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("savedURLs.plist")
    }
    
    /// Based on the sampling rate,
    /// it returns random value deciding if the SDK should be "initialized" or not.
    /// - Returns: `true` if SDK should be initialized and `false` if it should be dropped.
    static func shouldInitialized(sampleRate: Int) -> Bool {
        return Int.random(in: 0..<100) < sampleRate
    }
}
