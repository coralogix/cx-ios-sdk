//
//  FrameFingerprintTests.swift
//  SessionReplayTests
//
//  The frame-similarity test ported from Android. The case that matters most is
//  `testSmallLocalEditIsNotADuplicate`: the average-difference check this replaced
//  called that frame identical and dropped it.
//

import XCTest
import CoreGraphics
@testable import SessionReplay

final class FrameFingerprintTests: XCTestCase {

    // A real capture on the device this was validated against.
    private let screen = CGSize(width: 402, height: 874)
    private let options = FrameDiffOptions()

    // MARK: - Helpers

    private func makeImage(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let context = CGContext(data: nil, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        draw(context)
        return context.makeImage()!
    }

    private func fingerprint(_ image: CGImage) -> FrameFingerprint {
        guard let fp = FrameFingerprint.make(from: image, options: options) else {
            XCTFail("fingerprint could not be built"); fatalError()
        }
        return fp
    }

    private func isSame(_ a: CGImage, _ b: CGImage) -> Bool {
        FrameSimilarity.isSame(fingerprint(a), fingerprint(b), options: options)
    }

    /// Mean absolute channel difference, normalised 0–1 — what the replaced check measured.
    private func meanChannelDifference(_ a: CGImage, _ b: CGImage) -> Double {
        func pixels(_ img: CGImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
            buf.withUnsafeMutableBytes { p in
                let ctx = CGContext(data: p.baseAddress, width: img.width, height: img.height,
                                    bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
            return buf
        }
        let pa = pixels(a), pb = pixels(b)
        var total = 0.0
        for i in stride(from: 0, to: pa.count, by: 4) {
            for c in 0..<3 { total += abs(Double(pa[i + c]) - Double(pb[i + c])) }
        }
        return total / (Double(pa.count / 4) * 3.0 * 255.0)
    }

    // MARK: - Duplicates are still dropped

    func testUnchangedFrameIsADuplicate() {
        let a = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 20, y: 100, width: 360, height: 40))
        }
        let b = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 20, y: 100, width: 360, height: 40))
        }
        XCTAssertTrue(isSame(a, b), "an unchanged screen must still be deduplicated")
    }

    // MARK: - The regression this port fixes

    func testSmallLocalEditIsNotADuplicate() {
        let before = makeImage(screen) { _ in }
        let after = makeImage(screen) { ctx in
            // A control changing state — a checkbox, a typed word, a badge.
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 40, y: 300, width: 60, height: 20))
        }

        // The replaced check divided this by the whole screen and saw nothing.
        let mean = meanChannelDifference(before, after)
        XCTAssertLessThan(mean, 0.01,
                          "guard: this edit is below the old average-difference threshold, "
                          + "which is exactly why it used to be dropped")

        XCTAssertFalse(isSame(before, after),
                       "a small local edit is a real change and must ship")
    }

    /// Rec.601 maps pure red and mid green onto the same brightness, so a luma-only comparison
    /// scored a whole screen changing between them at SSIM 1.000000 with zero changed tiles and
    /// dropped it. The average-difference check this port replaced did see it — over RGB.
    func testColourOnlyChangeIsNotADuplicate() {
        let red = makeImage(screen) { ctx in
            ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: self.screen))
        }
        let green = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 130.0 / 255.0, blue: 0, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: self.screen))
        }

        // Guard: the two frames really are indistinguishable by brightness.
        let lumaRed = downscaleToLuma(red, size: options.workSize)
        let lumaGreen = downscaleToLuma(green, size: options.workSize)
        XCTAssertEqual(lumaRed, lumaGreen,
                       "guard: these frames share a luma plane, which is what made them invisible")

        XCTAssertFalse(isSame(red, green),
                       "a screen changing colour is a real change and must ship")
    }

    /// A status dot, a validation field, a selected chip: small and distinguished by hue alone.
    /// This one needs both fixes — the tile scan has to see colour, and one changed tile out of
    /// 256 has to count as a change.
    func testSmallColourOnlyChangeIsNotADuplicate() {
        func dot(_ red: Double, _ green: Double) -> CGImage {
            makeImage(screen) { ctx in
                ctx.setFillColor(red: red, green: green, blue: 0, alpha: 1)
                ctx.fillEllipse(in: CGRect(x: 200, y: 500, width: 12, height: 12))
            }
        }
        XCTAssertFalse(isSame(dot(1, 0), dot(0, 130.0 / 255.0)),
                       "a 12pt status dot changing from red to green must ship")
    }

    func testFullScreenChangeIsNotADuplicate() {
        let a = makeImage(screen) { _ in }
        let b = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: self.screen))
        }
        XCTAssertFalse(isSame(a, b))
    }

    func testDifferentDimensionsAreNeverDuplicates() {
        let a = makeImage(screen) { _ in }
        let b = makeImage(CGSize(width: 402, height: 875)) { _ in }
        XCTAssertFalse(isSame(a, b))
    }

    // MARK: - Metrics

    func testLumaBufferHasWorkSizeSquaredSamples() {
        let image = makeImage(screen) { _ in }
        let luma = downscaleToLuma(image, size: options.workSize)
        XCTAssertEqual(luma?.count, options.workSize * options.workSize)
    }

    func testSsimIsOneForIdenticalBuffersAndLowerForDifferentOnes() {
        let flat = [UInt8](repeating: 128, count: 64 * 64)
        XCTAssertEqual(ssimGlobal(flat, flat), 1.0, accuracy: 1e-9)

        var noisy = flat
        for i in stride(from: 0, to: noisy.count, by: 3) { noisy[i] = 20 }
        XCTAssertLessThan(ssimGlobal(flat, noisy), options.ssimMinSame)
    }

    func testChangedTileCountCountsOnlyTilesThatMoved() {
        let base = [UInt8](repeating: 0, count: 64 * 64 * 4)
        XCTAssertEqual(changedTileCount(base, base, size: 64, tiles: 16, tileThreshold: 4), 0)

        // Fill exactly the top-left 4x4 tile, green channel only.
        var oneTile = base
        for y in 0..<4 {
            for x in 0..<4 { oneTile[(y * 64 + x) * 4 + 1] = 255 }
        }
        XCTAssertEqual(changedTileCount(base, oneTile, size: 64, tiles: 16, tileThreshold: 4), 1,
                       "one tile moved, in one channel — the scan must see exactly that tile")
    }

    /// The scan reads colour, so a difference confined to one channel registers. Measured
    /// against the buffer size it is given: a luma-plane buffer is the wrong length and must
    /// be refused rather than read as if it were RGBA.
    func testChangedTileCountRefusesABufferThatIsNotRGBA() {
        let luma = [UInt8](repeating: 0, count: 64 * 64)
        XCTAssertEqual(changedTileCount(luma, luma, size: 64, tiles: 16, tileThreshold: 4), 256,
                       "a mis-sized buffer must report every tile changed, so the frame is kept")
    }

    func testDHashDistinguishesStructure() {
        let a = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 201, height: 874))
        }
        let b = makeImage(screen) { ctx in
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 201, y: 0, width: 201, height: 874))
        }
        let ha = dHash64(a, width: options.dHashWidth, height: options.dHashHeight)!
        let hb = dHash64(b, width: options.dHashWidth, height: options.dHashHeight)!
        XCTAssertGreaterThan((ha ^ hb).nonzeroBitCount, options.dHashMaxSame,
                             "mirrored halves must not hash the same")
    }

    func testDefaultsMatchTheAndroidFrameDiffOptions() {
        // Mirrored from android-sdk FrameDiffOptions.kt — a divergence here means the two
        // platforms would disagree about which frames are worth uploading.
        XCTAssertEqual(options.workSize, 64)
        XCTAssertEqual(options.dHashWidth, 9)
        XCTAssertEqual(options.dHashHeight, 8)
        XCTAssertEqual(options.dHashMaxSame, 1)
        XCTAssertEqual(options.ssimMinSame, 0.999)
        XCTAssertEqual(options.tiles, 16)
        XCTAssertEqual(options.tileMadThreshold, 4)
        XCTAssertEqual(options.minVotesForSame, 3)
    }

    /// The one option that deliberately does not mirror Android, pinned so the divergence is a
    /// decision rather than a drift. Android's ratio form cannot express it: 16 tiles per axis
    /// make the finest non-zero ratio 1/256 = 0.0039, already below the 0.005 it ships, so a
    /// single changed tile voted "same" and the local metric was blind to the smallest change
    /// it exists to detect.
    func testAnyChangedTileKeepsTheFrame() {
        XCTAssertEqual(options.changedTilesMaxSame, 0)
        XCTAssertLessThan(1.0 / Double(options.tiles * options.tiles), 0.005,
                          "guard: the ratio form Android ships cannot reject a single tile")
    }
}
