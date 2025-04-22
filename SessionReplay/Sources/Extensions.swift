//
//  Extensions.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 16/12/2024.
//

import UIKit
import Foundation
import CommonCrypto
import Compression
import zlib
import CoralogixInternal

extension CGImage {
    // Compute SHA-256 hash of pixel data
    public func sha256Digest() -> String? {
        // Rescale the image to maximum of 100 pixels width or height
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let ratio = max(1, size.width / 100, size.height / 100)
        
        let rect = CGRect(
            origin: .zero,
            size: CGSize(
                width: size.width / ratio,
                height: size.height / ratio
            )
        )
        
        // Create a greyscale context
        let context = CGContext(
            data: nil,
            width: Int(rect.width),
            height: Int(rect.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        
        guard let context = context else {
            return nil
        }
        
        // Draw the image with low quality interpolation
        context.interpolationQuality = .low
        context.draw(self, in: rect)
        
        guard let rawData = context.data else {
            return nil
        }
        
        // Compute SHA-256 hash of the raw pixel data
        let length = context.bytesPerRow * context.height
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(rawData, UInt32(length), &digest)
        
        // Convert the hash to a hexadecimal string
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

extension Data {
    public func toBase64String() -> String {
        return self.base64EncodedString()
    }
    
    public func gzipCompressed(maxChunkSize: Int = 1 * 1024 * 1024) -> [Data]? {
        let bufferSize = 64 * 1024 // 64KB buffer
        var compressedChunks: [Data] = []
        var currentIndex = 0
        
        while currentIndex < self.count {
            // Define the chunk range
            let chunkEnd = Swift.min(currentIndex + maxChunkSize, self.count)
            let chunk = self.subdata(in: currentIndex..<chunkEnd)
            
            // Compress the current chunk
            guard let compressedChunk = chunk.compressChunk(bufferSize: bufferSize) else {
                Log.e("Failed to compress chunk at index \(currentIndex)")
                return nil
            }
            
            compressedChunks.append(compressedChunk)
            currentIndex += maxChunkSize
        }
        
        return compressedChunks
    }
    
    internal func compressChunk(bufferSize: Int) -> Data? {
        var compressedData = Data()
        var stream = z_stream()
        
        let result = self.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Int32 in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return Z_ERRNO
            }
            
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            stream.avail_in = uInt(self.count)
            
            return deflateInit2_(
                &stream,
                Z_BEST_COMPRESSION,
                Z_DEFLATED,
                31,
                8,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
        }
        
        guard result == Z_OK else {
            Log.e("Failed to initialize zlib stream for GZIP, error code: \(result)")
            return nil
        }
        
        defer { deflateEnd(&stream) }
        
        let streamPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { streamPointer.deallocate() }
        
        repeat {
            stream.next_out = streamPointer
            stream.avail_out = uInt(bufferSize)
            
            let status = deflate(&stream, Z_FINISH)
            if status == Z_STREAM_ERROR {
                Log.e("Compression error: \(status)")
                return nil
            }
            
            let bytesCompressed = bufferSize - Int(stream.avail_out)
            compressedData.append(streamPointer, count: bytesCompressed)
            
            if status == Z_STREAM_END {
                break
            }
        } while stream.avail_out == 0
        
        return compressedData
    }
    
}
