// Count near-magenta pixels in a JPEG.
//
// Magenta (#FF00FF) is the sentinel color used by the leak harness
// (see project memory `leak_detection_via_pixel_color`). Any pixel
// close to magenta in a captured session-replay frame indicates the
// SDK's mask rect missed part of the sentinel text — i.e. the
// frame-skew bug BUGV2-6045 leaked text from under the mask.
//
// Tolerance accounts for JPEG compression and antialiasing edge
// pixels. A leaked single character renders ~30+ matching pixels.
//
// Usage:
//   swift tool/count_magenta.swift <image>
//
// Prints one integer: number of matching pixels. Exit code 0 always.
// The Dart wrapper aggregates counts per frame and decides leak/no-leak.

import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: count_magenta <image>\n".data(using: .utf8)!)
    exit(2)
}
let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    // Not a decodable image — likely a multi-chunk fragment (the SDK
    // splits large gzipped frames; chunks after the first don't have
    // gzip magic and don't decode as JPEG). Treat as "no leak signal"
    // and exit cleanly so the batch scanner keeps going. The Dart-side
    // wrapper logs a skip so we know to address chunk reassembly if
    // skip count gets material.
    print("SKIP")
    exit(0)
}
let w = cg.width
let h = cg.height
let bpr = w * 4
let pixelData = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
defer { pixelData.deallocate() }
let cs = CGColorSpaceCreateDeviceRGB()
let info = CGImageAlphaInfo.premultipliedLast.rawValue
guard let ctx = CGContext(data: pixelData,
                           width: w,
                           height: h,
                           bitsPerComponent: 8,
                           bytesPerRow: bpr,
                           space: cs,
                           bitmapInfo: info) else {
    FileHandle.standardError.write("failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var count = 0
let n = w * h
for i in 0..<n {
    let r = pixelData[i * 4 + 0]
    let g = pixelData[i * 4 + 1]
    let b = pixelData[i * 4 + 2]
    if r >= 200 && g <= 80 && b >= 200 {
        count += 1
    }
}
print(count)
exit(0)
