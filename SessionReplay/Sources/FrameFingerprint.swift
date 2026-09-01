//
//  FrameFingerprint.swift
//  SessionReplay
//
//  Frame-similarity test shared with the Android SDK
//  (`session_replay/internal/frame_capturer/FrameFingerprint.kt` + `Utils.kt`).
//  Any change to the metrics or thresholds here must be mirrored there, or the
//  two platforms will disagree about which frames are worth uploading.
//
//  Two points already diverge, both making this side strictly more willing to keep a frame,
//  and both need mirroring on Android:
//
//  1. The tile scan compares colour, not luma. Rec.601 maps distinct hues onto the same
//     brightness — pure red and mid green both land on 76 — so a luma-only scan cannot see a
//     colour-only change at all. A status dot going red to green scored SSIM 1.000000 and zero
//     changed tiles: invisible to every metric, and dropped.
//  2. Any changed tile keeps the frame. Expressed as a ratio it could not: 16 tiles per axis
//     make the finest non-zero value 1/256 = 0.0039, already under the 0.005 Android ships, so
//     a single changed tile still voted "same" and the one metric meant to catch a local change
//     was blind to the smallest change it exists to detect.
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
    /// Mean absolute per-channel difference at or above which one tile counts as changed.
    let tileMadThreshold: Int
    /// How many changed tiles still count as the same frame. Zero — any tile that moved is a
    /// change worth uploading. See the divergence note at the top of the file.
    let changedTilesMaxSame: Int
    /// How many of the three metrics must agree before a frame is dropped.
    let minVotesForSame: Int

    init(workSize: Int = 64,
         dHashWidth: Int = 9,
         dHashHeight: Int = 8,
         dHashMaxSame: Int = 1,
         ssimMinSame: Double = 0.999,
         tiles: Int = 16,
         tileMadThreshold: Int = 4,
         changedTilesMaxSame: Int = 0,
         minVotesForSame: Int = 3) {
        self.workSize = workSize
        self.dHashWidth = dHashWidth
        self.dHashHeight = dHashHeight
        self.dHashMaxSame = dHashMaxSame
        self.ssimMinSame = ssimMinSame
        self.tiles = tiles
        self.tileMadThreshold = tileMadThreshold
        self.changedTilesMaxSame = changedTilesMaxSame
        self.minVotesForSame = minVotesForSame
    }
}

/// A cheap, comparable summary of one frame: its dimensions, a structure-sensitive
/// difference hash, and a downscaled colour buffer with its luma plane.
///
/// Holding this instead of the previous frame's JPEG is what lets the comparison see
/// *where* a frame changed. A whole-frame average cannot: it divides a local change by
/// the whole screen, so a toggled checkbox or a typed character averages away to nothing
/// and the frame is dropped as a duplicate.
internal struct FrameFingerprint: Equatable {
    let width: Int
    let height: Int
    let dHash: UInt64
    /// `workSize * workSize * 4` samples, row-major, R G B A. The tile scan reads this rather
    /// than `luma` so a change carried entirely in hue is visible to it.
    let rgba: [UInt8]
    /// `workSize * workSize` luma samples, row-major, derived from `rgba`. SSIM reads this.
    let luma: [UInt8]

    /// Builds a fingerprint from the frame the encoder is about to compress. Returns nil
    /// only if the scratch contexts cannot be created, in which case the caller keeps the
    /// frame — a frame shipped twice beats a frame silently lost.
    static func make(from image: CGImage, options: FrameDiffOptions) -> FrameFingerprint? {
        guard let rgba = renderRGBA(image, width: options.workSize, height: options.workSize),
              let hash = dHash64(image, width: options.dHashWidth, height: options.dHashHeight)
        else { return nil }
        return FrameFingerprint(width: image.width, height: image.height,
                                dHash: hash, rgba: rgba, luma: lumaPlane(from: rgba))
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
    ///
    /// The tile scan carries most of that weight in practice. Measured over a range of edits on
    /// a 402x874 frame, dHash called all but a half-screen fill "same": a 9x8 hash of a phone
    /// screen rarely dissents, so treat the vote as SSIM and the tile scan with dHash as a
    /// tie-breaker, and keep the tile scan the sensitive one.
    static func isSame(_ previous: FrameFingerprint,
                       _ next: FrameFingerprint,
                       options: FrameDiffOptions) -> Bool {
        guard previous.width == next.width, previous.height == next.height else { return false }
        guard previous.luma.count == next.luma.count,
              previous.rgba.count == next.rgba.count else { return false }

        let hamming = (previous.dHash ^ next.dHash).nonzeroBitCount
        let ssim = ssimGlobal(previous.luma, next.luma)
        let changedTiles = changedTileCount(previous.rgba, next.rgba,
                                            size: options.workSize,
                                            tiles: options.tiles,
                                            tileThreshold: options.tileMadThreshold)

        var votes = 0
        if hamming <= options.dHashMaxSame { votes += 1 }
        if ssim >= options.ssimMinSame { votes += 1 }
        if changedTiles <= options.changedTilesMaxSame { votes += 1 }
        return votes >= options.minVotesForSame
    }
}

// MARK: - Metrics

/// Rec.601 luma, matching the coefficients Android uses so the two platforms produce the
/// same buffer for the same frame.
private func luma(r: Int, g: Int, b: Int) -> UInt8 {
    UInt8(min(255, Int(0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b))))
}

/// Renders `image` at the requested size into a tightly-packed RGBA buffer: `width * height * 4`
/// bytes, premultiplied, four channels per pixel in R, G, B, A order, no row padding.
///
/// Black-filled rather than transparent because a captured frame may carry alpha, and Android
/// composites onto black before sampling — a transparent region has to compare as black on both
/// platforms, not as whatever the buffer happened to hold.
///
/// Shared so both metrics sample the same pixels by construction. They are blind to different
/// things on purpose, but only while they are looking at the same rendering: a divergence in
/// colour space, fill, or interpolation between two copies of this setup would have them
/// disagreeing about the rendering rather than about the frame.
internal func renderRGBA(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    guard width > 0, height > 0 else { return nil }
    var rgba = [UInt8](repeating: 0, count: width * height * 4)

    let drawn: Bool = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let base = buffer.baseAddress,
              let context = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? rgba : nil
}

/// Collapses a tightly-packed RGBA buffer to one luma sample per pixel, for SSIM — which
/// measures structure, and reads brightness rather than colour.
internal func lumaPlane(from rgba: [UInt8]) -> [UInt8] {
    let count = rgba.count / 4
    var out = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
        let p = i * 4
        out[i] = luma(r: Int(rgba[p]), g: Int(rgba[p + 1]), b: Int(rgba[p + 2]))
    }
    return out
}

/// Samples `image` down to a `size * size` single-channel luma buffer.
internal func downscaleToLuma(_ image: CGImage, size: Int) -> [UInt8]? {
    guard size > 0, let rgba = renderRGBA(image, width: size, height: size) else { return nil }
    return lumaPlane(from: rgba)
}

/// 64-bit difference hash: one bit per horizontally adjacent pair, set when the left
/// sample is brighter. Structure-sensitive and very cheap.
internal func dHash64(_ image: CGImage, width: Int, height: Int) -> UInt64? {
    guard width > 1, let rgba = renderRGBA(image, width: width, height: height) else { return nil }

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

/// How many tiles have a mean absolute per-channel difference reaching `tileThreshold`.
///
/// This is the metric that sees a small, local edit: the change is averaged over one
/// tile rather than the whole screen. It reads all three colour channels, so a change
/// carried entirely in hue registers here even where luma is identical.
///
/// Both buffers are `size * size * 4` RGBA. Alpha is skipped — the render composites onto
/// opaque black, so it holds no information about the frame.
internal func changedTileCount(_ a: [UInt8], _ b: [UInt8],
                               size: Int, tiles: Int, tileThreshold: Int) -> Int {
    let total = max(0, tiles * tiles)
    guard size > 0, tiles > 0,
          a.count == size * size * 4, b.count == size * size * 4 else { return total }
    let tw = max(1, size / tiles)
    var changed = 0
    for ty in 0..<tiles {
        for tx in 0..<tiles {
            var sum = 0
            var samples = 0
            for y in 0..<tw {
                let row = (ty * tw + y) * size + (tx * tw)
                for x in 0..<tw {
                    let p = (row + x) * 4
                    guard p + 2 < a.count else { continue }
                    sum += abs(Int(a[p]) - Int(b[p]))
                        + abs(Int(a[p + 1]) - Int(b[p + 1]))
                        + abs(Int(a[p + 2]) - Int(b[p + 2]))
                    samples += 3
                }
            }
            if samples > 0, sum / samples >= tileThreshold { changed += 1 }
        }
    }
    return changed
}
