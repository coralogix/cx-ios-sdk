//
//  TestUtils.swift
//  Coralogix
//
//  Created by Tomer Har Yoffi on 21/04/2025.
//

import Foundation
import XCTest

extension XCTestCase {
    /// Creates a unique copy of a file with a random name in a temporary directory.
    ///
    /// - Parameters:
    ///   - originalURL: The URL of the original file.
    ///   - extension: The file extension for the new file (optional; inferred if nil).
    /// - Returns: The URL of the newly created unique file.
    /// - Throws: An error if the file copy operation fails.
    func createUniqueFile(from originalURL: URL, withExtension fileExtension: String? = nil) throws -> URL {
        // Create a unique directory for the test
        let uniqueTestDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: uniqueTestDir, withIntermediateDirectories: true)
        
        // Generate a random file name
        let randomFileName = UUID().uuidString
        let fullFileName = fileExtension != nil ? "\(randomFileName).\(fileExtension!)" : randomFileName
        
        // Generate the URL for the unique file
        let uniqueFileURL = uniqueTestDir.appendingPathComponent(fullFileName)
        
        // Copy the original file to the unique location
        try FileManager.default.copyItem(at: originalURL, to: uniqueFileURL)
        
        return uniqueFileURL
    }
}
