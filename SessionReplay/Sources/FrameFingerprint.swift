//
//  FrameFingerprint.swift
//  SessionReplay
//
//  Frame-similarity test shared with the Android SDK
//  (`session_replay/internal/frame_capturer/FrameFingerprint.kt` + `Utils.kt`).
//  Any change to the metrics or thresholds here must be mirrored there, or the
//  two platforms will disagree about which frames are worth uploading.
//

import Foundation
import CoreGraphics

/// Thresholds for the three-metric similarity vote. Defaults match Android's
/// `FrameDiffOptions` exactly.
internal struct FrameDiffOptions {
    /// Edge of the square luma buffer both SSIM and the tile scan run on.
    let workSize: Int
    let dHashWidth: Int
    let dHashHeight: Int
    /// Hamming distance at or below which the difference hashes count as "same".
    let dHashMaxSame: Int
    let ssimMinSame: Double
    /// Tiles per axis; the scan runs over `tiles * tiles` cells.
    let tiles: Int
    /// Mean absolute luma difference at or above which one tile counts as changed.
    let tileMadThreshold: Int
    let changedTilesMaxRatio: Double
    /// How many of the three metrics must agree before a frame is dropped.
    let minVotesForSame: Int

    init(workSize: Int = 64,
         dHashWidth: Int = 9,
         dHashHeight: Int = 8,
         dHashMaxSame: Int = 1,
         ssimMinSame: Double = 0.999,
         tiles: Int = 16,
         tileMadThreshold: Int = 4,
         changedTilesMaxRatio: Double = 0.005,
         minVotesForSame: Int = 3) {
        self.workSize = workSize
        self.dHashWidth = dHashWidth
        self.dHashHeight = dHashHeight
        self.dHashMaxSame = dHashMaxSame
        self.ssimMinSame = ssimMinSame
        self.tiles = tiles
        self.tileMadThreshold = tileMadThreshold
        self.changedTilesMaxRatio = changedTilesMaxRatio
        self.minVotesForSame = minVotesForSame
    }
}

/// A cheap, comparable summary of one frame: its dimensions, a structure-sensitive
/// difference hash, and a downscaled luma buffer.
///
/// Holding this instead of the previous frame's JPEG is what lets the comparison see
/// *where* a frame changed. A whole-frame average cannot: it divides a local change by
/// the whole screen, so a toggled checkbox or a typed character averages away to nothing
/// and the frame is dropped as a duplicate.
internal struct FrameFingerprint: Equatable {
    let width: Int
    let height: Int
    let dHash: UInt64
    /// `workSize * workSize` luma samples, row-major.
    let luma: [UInt8]

    /// Builds a fingerprint from the frame the encoder is about to compress. Returns nil
    /// only if the scratch contexts cannot be created, in which case the caller keeps the
    /// frame — a frame shipped twice beats a frame silently lost.
    static func make(from image: CGImage, options: FrameDiffOptions) -> FrameFingerprint? {
        guard let luma = downscaleToLuma(image, size: options.workSize),
              let hash = dHash64(image, width: options.dHashWidth, height: options.dHashHeight)
        else { return nil }
        return FrameFingerprint(width: image.width, height: image.height,
                                dHash: hash, luma: luma)
    }
}

// MARK: - The similarity vote

internal enum FrameSimilarity {
    /// True when `next` is close enough to `previous` that uploading it would add nothing.
    ///
    /// Three independent metrics vote, and by default all three must call it the same
    /// frame. They fail in different ways — dHash is blind to uniform brightness shifts,
    /// SSIM to tiny high-contrast edits, the tile scan to changes spread thinly across the
    /// whole screen — so requiring agreement means a change any one of them can see is
    /// enough to keep the frame.
    static func isSame(_ previous: FrameFingerprint,
                       _ next: FrameFingerprint,
                       options: FrameDiffOptions) -> Bool {
        guard previous.width == next.width, previous.height == next.height else { return false }
        guard previous.luma.count == next.luma.count else { return false }

        let hamming = (previous.dHash ^ next.dHash).nonzeroBitCount
        let ssim = ssimGlobal(previous.luma, next.luma)
        let ratio = changedTileRatio(previous.luma, next.luma,
                                     size: options.workSize,
                                     tiles: options.tiles,
                                     tileThreshold: options.tileMadThreshold)

        var votes = 0
        if hamming <= options.dHashMaxSame { votes += 1 }
        if ssim >= options.ssimMinSame { votes += 1 }
        if ratio < options.changedTilesMaxRatio { votes += 1 }
        return votes >= options.minVotesForSame
    }
}

// MARK: - Metrics

/// Rec.601 luma, matching the coefficients Android uses so the two platforms produce the
/// same buffer for the same frame.
private func luma(r: Int, g: Int, b: Int) -> UInt8 {
    UInt8(min(255, Int(0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b))))
}

/// Draws `image` into a `size * size` RGBA scratch over black and returns its luma.
///
/// Black-filled rather than transparent because a captured frame may carry alpha, and
/// Android composites onto black before sampling.
internal func downscaleToLuma(_ image: CGImage, size: Int) -> [UInt8]? {
    guard size > 0 else { return nil }
    let bytesPerRow = size * 4
    var rgba = [UInt8](repeating: 0, count: size * size * 4)

    let drawn: Bool = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress,
              let context = CGContext(data: base,
                                      width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return true
    }
    guard drawn else { return nil }

    var out = [UInt8](repeating: 0, count: size * size)
    for i in 0..<(size * size) {
        let p = i * 4
        out[i] = luma(r: Int(rgba[p]), g: Int(rgba[p + 1]), b: Int(rgba[p + 2]))
    }
    return out
}

/// 64-bit difference hash: one bit per horizontally adjacent pair, set when the left
/// sample is brighter. Structure-sensitive and very cheap.
internal func dHash64(_ image: CGImage, width: Int, height: Int) -> UInt64? {
    guard width > 1, height > 0 else { return nil }
    let bytesPerRow = width * 4
    var rgba = [UInt8](repeating: 0, count: width * height * 4)

    let drawn: Bool = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress,
              let context = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }

    var gray = [Int](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
        let p = i * 4
        gray[i] = Int(luma(r: Int(rgba[p]), g: Int(rgba[p + 1]), b: Int(rgba[p + 2])))
    }

    var hash: UInt64 = 0
    var bit = 0
    for y in 0..<height {
        var x = 0
        while x < width - 1 && bit < 64 {
            let idx = y * width + x
            if gray[idx] > gray[idx + 1] { hash |= (1 << UInt64(63 - bit)) }
            bit += 1
            x += 1
        }
    }
    return hash
}

/// Global (windowless) SSIM over two equal-length luma buffers.
internal func ssimGlobal(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, a.count > 1 else { return 1.0 }
    let n = a.count

    var muA = 0.0, muB = 0.0
    for i in 0..<n { muA += Double(a[i]); muB += Double(b[i]) }
    muA /= Double(n); muB /= Double(n)

    var sigmaA = 0.0, sigmaB = 0.0, sigmaAB = 0.0
    for i in 0..<n {
        let da = Double(a[i]) - muA
        let db = Double(b[i]) - muB
        sigmaA += da * da
        sigmaB += db * db
        sigmaAB += da * db
    }
    let d = Double(n - 1)
    sigmaA /= d; sigmaB /= d; sigmaAB /= d

    let L = 255.0, k1 = 0.01, k2 = 0.03
    let c1 = (k1 * L) * (k1 * L)
    let c2 = (k2 * L) * (k2 * L)

    let num = (2 * muA * muB + c1) * (2 * sigmaAB + c2)
    let den = (muA * muA + muB * muB + c1) * (sigmaA + sigmaB + c2)
    guard den != 0 else { return 1.0 }
    return min(1.0, max(-1.0, num / den))
}

/// Fraction of tiles whose mean absolute luma difference reaches `tileThreshold`.
///
/// This is the metric that sees a small, local edit: the change is averaged over one
/// tile rather than the whole screen.
internal func changedTileRatio(_ a: [UInt8], _ b: [UInt8],
                               size: Int, tiles: Int, tileThreshold: Int) -> Double {
    guard size > 0, tiles > 0,
          a.count == size * size, b.count == size * size else { return 1.0 }
    let tw = max(1, size / tiles)
    var changed = 0
    for ty in 0..<tiles {
        for tx in 0..<tiles {
            var sum = 0
            for y in 0..<tw {
                let row = (ty * tw + y) * size + (tx * tw)
                for x in 0..<tw {
                    let i = row + x
                    guard i < a.count else { continue }
                    sum += abs(Int(a[i]) - Int(b[i]))
                }
            }
            if sum / (tw * tw) >= tileThreshold { changed += 1 }
        }
    }
    let total = tiles * tiles
    return total == 0 ? 1.0 : Double(changed) / Double(total)
}
