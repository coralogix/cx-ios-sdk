//
//  SessionReplay.swift
//  session-replay
//
//  Created by Coralogix DEV TEAM on 31/10/2024.
//

import AVFoundation
import Vision
import CoreImage
import CoralogixInternal

public class VideoMaskingProcessor {
    
    private var videoAsset: AVAsset?
    private var videoTrack: AVAssetTrack?
    private var assetReader: AVAssetReader?
    private var videoAssetReaderOutput: AVAssetReaderTrackOutput?
    
    var frames: [CGImage] = []
    
    // MARK: For writing video
    private let writerQueue = DispatchQueue(label: "mediaInputQueue")
    
    // MARK: video properties
    // frames per second
    var frameRate: Float32?
    
    // Indicates the minimum duration of the track's frames
    var minFrameDuration: Float64? {
        if let cmMinFrameDuration = cmMinFrameDuration {
            return CMTimeGetSeconds(cmMinFrameDuration)
        }
        return nil
    }
    var cmMinFrameDuration: CMTime?
    
    // Provides access to an array of AVMetadataItems for all metadata identifiers for which a value is available
    var metadata: [AVMetadataItem]?
    
    // transform specified in the track's storage container as the preferred transformation of the visual media data for display purposes: Value returned is often but not always `.identity`
    var affineTransform: CGAffineTransform!
    
    public var duration: Float64?
    
    public var progressCallback: ((String) -> Void)?
    private var completedCallback: (() -> Void)?
    
    public init() {
        // Initialization code
        self.frames = []
    }
    
    private func removeOldVideo(outputURL: URL) {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
                Log.d("File successfully removed.")
            } catch {
                Log.e("Failed to remove file: \(error)")
            }
        } else {
            Log.e("File does not exist at path: \(outputURL.path)")
        }
    }
    
    // MARK: Functions For reading video from URL
//    public func loadVideo(_ url: URL) async -> Bool {
//        self.videoAsset = AVAsset(url: url)
//        let tracks = try? await self.videoAsset?.loadTracks(withMediaType: AVMediaType.video)
//        
//        if let videoTrack = tracks?.first {
//            self.videoTrack = videoTrack
//            do {
//                let (affineTransform, metadata, cmMinFrameDuration, frameRate) = try await self.videoTrack!.load(.preferredTransform, .metadata, .minFrameDuration, .nominalFrameRate)
//                self.affineTransform = affineTransform
//                self.metadata = metadata
//                self.cmMinFrameDuration = cmMinFrameDuration
//                self.frameRate = frameRate
//                let duration = try await self.videoAsset!.load(.duration)
//                self.duration = CMTimeGetSeconds(duration)
//                
//            } catch (let error) {
//                Log.e("error loading data: \(error.localizedDescription)")
//                return false
//            }
//        } else {
//            return false
//        }
//        
//        return self.readAsset()
//    }
    
    public func calculateFrames() {
        while true {
            guard let frameImage = self.getNextFrame() else {
                break
            }
            self.frames.append(frameImage)
        }
        print("loading finishes: total frame: \(self.frames.count)")
    }
    
    private func getNextFrame() -> CGImage? {
        guard let videoAssetReaderOutput = self.videoAssetReaderOutput,
              let sampleBuffer = videoAssetReaderOutput.copyNextSampleBuffer(),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        return CIImage(cvImageBuffer: imageBuffer).transformed(by: self.affineTransform ?? .identity).cgImage
    }
    
    private func readAsset() -> Bool {
        guard let videoAsset = self.videoAsset, let videoTrack = self.videoTrack else {
            Log.e("nil video reader output")
            return false
        }
        
        do {
            self.assetReader = try AVAssetReader(asset: videoAsset)
        } catch {
            Log.e("Failed to create AVAssetReader object: \(error)")
            return false
        }
        
        self.videoAssetReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange])
        
        if let videoAssetReaderOutput = self.videoAssetReaderOutput,
           let assetReader = self.assetReader {
            videoAssetReaderOutput.alwaysCopiesSampleData = true
            guard assetReader.canAdd(videoAssetReaderOutput) else {
                Log.e("cannot add output")
                return false
            }
            assetReader.add(videoAssetReaderOutput)
            return assetReader.startReading()
        }
        
        return false
    }
    
    public func processVideo(outputURL: URL) {
        guard let frameDuration = self.cmMinFrameDuration else {
            print("frame duration not defined")
            return
        }
        
        guard let width = frames.first?.width, let height = frames.first?.height else {
            print("width and height not found")
            return
        }
        
        guard let _ = self.videoTrack else {
            Log.e("VideoTrack is nil")
            return
        }
        
        let avOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        
        guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mov) else {
            Log.e("AVAssetWriter creation failed")
            return
        }
        
        guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
            Log.e("Cannot apply output setting.")
            return
        }
        
        let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: avOutputSettings)
        
        guard assetWriter.canAdd(assetWriterInput) else {
            Log.e("cannot add writer input")
            return
        }
        assetWriter.add(assetWriterInput)
        
        // The pixel buffer adaptor must be created before writing
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(height))
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
        )
        
        Thread.sleep(forTimeInterval: 0.2)
        
        guard assetWriter.startWriting() else {
            Log.e("cannot starting writing with error: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
            return
        }
        
        // start writing session
        assetWriter.startSession(atSourceTime: CMTime.zero)
        
        //new implementaions
        var frameCount = 0
        var frameBuffers = frames.map { $0.cvPixelBuffer }
                
        // write buffer
        assetWriterInput.requestMediaDataWhenReady(on: writerQueue) {
            while !frameBuffers.isEmpty {
                if assetWriterInput.isReadyForMoreMediaData == false {
                    // break out of the loop.
                    // frameBuffers.isEmpty == false and the escaping block will be called again when ready
                    print("more buffers need to be written.")
                    break
                }
                
                guard let buffer = frameBuffers.removeFirst() else {
                    print("nil buffer on frame \(frameCount)")
                    continue
                }
                
                // Convert buffer to CIImage for masking
                let ciImage = CIImage(cvPixelBuffer: buffer)
                
                // Apply mask to the image
                
                let maskedCIImage = self.maskText(in: ciImage)
                
                // Convert the masked CIImage back to CVPixelBuffer
                var maskedBuffer: CVPixelBuffer?
                let pixelBufferOptions: [String: Any] = [
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    Int(maskedCIImage.extent.width),
                    Int(maskedCIImage.extent.height),
                    kCVPixelFormatType_32BGRA,
                    pixelBufferOptions as CFDictionary,
                    &maskedBuffer
                )
                
                let context = CIContext()
                if let maskedBuffer = maskedBuffer {
                    context.render(maskedCIImage, to: maskedBuffer)
                }
                
                guard let finalBuffer = maskedBuffer else {
                    print("Failed to create masked pixel buffer at frame count \(frameCount)")
                    continue
                }
                
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))
                let success = pixelBufferAdaptor.append(finalBuffer, withPresentationTime: presentationTime)
                if !success {
                    print("fail to add image at frame count \(frameCount)")
                    continue
                }
                
                frameCount = frameCount + 1
            }
            
            // if frameBuffers.isEmpty == false, the escaping block will be called again when ready
            // else: processing finished
            if frameBuffers.isEmpty {
                assetWriterInput.markAsFinished()
                assetWriter.finishWriting() {
                    if assetWriter.status == .completed {
                        Log.d("Video writing finished successfully.")
                    } else if assetWriter.status == .failed {
                        Log.d("Writing failed: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
                    }
                    DispatchQueue.main.async {
                        self.completedCallback?()
                        return
                    }
                }
            }
        }
        
        print("end")
    }

    func maskText(in image: CIImage) -> CIImage {
        let blackColor = CIColor.black
        var maskLayer = CIImage.empty().cropped(to: image.extent) // Start with an empty mask layer
        
        // Create the text recognition request
        let request = VNRecognizeTextRequest { (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                Log.e("No text detected or an error occurred: \(String(describing: error))")
                return
            }
            
            for observation in results {
                let boundingBox = observation.boundingBox
                
                // Map Vision's normalized coordinates to CIImage's coordinates
                let adjustedRect = CGRect(
                    x: boundingBox.minX * image.extent.width,
                    y: (1 - boundingBox.minY - boundingBox.height) * image.extent.height,
                    width: boundingBox.width * image.extent.width,
                    height: boundingBox.height * image.extent.height
                )
                
                // Create a black mask cropped to the adjusted rect
                let mask = CIImage(color: blackColor).cropped(to: adjustedRect)
                
                // Add the mask to the mask layer (composite each mask onto the layer)
                maskLayer = mask.composited(over: maskLayer)
            }
        }
        
        // Perform the text recognition request
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        
        // Flip the mask layer only, not the original image
        let flippedMaskLayer = maskLayer
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: image.extent.height))
        
        // Composite the flipped mask over the original image
        let maskedImage = flippedMaskLayer.composited(over: image)
        
        return maskedImage
    }
}

extension CIImage {
    var cgImage: CGImage? {
        let ciContext = CIContext(options: nil)
        return ciContext.createCGImage(self, from: self.extent)
    }
}

extension CGImage {
    var cvPixelBuffer: CVPixelBuffer? {
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            self.width,
            self.height,
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )
        
        guard (status == kCVReturnSuccess) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixelData,
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))

        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer
    }
}



/*
 1. Test init mask of regex
 2. Meta data on event/
 4. Versions -
 5. Performance on backgrounds
 6. Compress
 7. Break to parts 10 sec to session id
 8. Logs should mark has recording true
 9. Split movie on importing events error navigation
 3. Flutter / tv os
 
 */


// Calculate progress
//                if let videoAssetReaderOutput = self.videoAssetReaderOutput,
//                   let sampleBuffer = videoAssetReaderOutput.copyNextSampleBuffer() {
//                    let currentTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
//                    if let duration  = self.duration {
//                        let progress = Float(currentTime / duration)
//
//                        if progress - lastProgress >= 0.01 {
//                            lastProgress = progress
//                            DispatchQueue.main.async {
//                                self.progressCallback?(String(format: "Progress: %.2f%%", progress * 100))
//                            }
//                        }
//                    }
//                }
