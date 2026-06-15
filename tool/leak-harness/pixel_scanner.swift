#!/usr/bin/env swift
// Native-Swift replacement for pixel_scanner.dart + count_magenta.swift.
//
// Counts near-magenta pixels (r≥200, g≤80, b≥200) in every *.jpg file
// under the given directory. Any frame with a non-zero count is a leak.
//
// Usage: swift pixel_scanner.swift <frames_dir>
//
// Exit codes:
//   0  — no leaks (or directory empty)
//   1  — at least one frame has magenta pixels
//   2  — usage error / directory not found

import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: pixel_scanner.swift <frames_dir>\n", stderr)
    exit(2)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
guard FileManager.default.fileExists(atPath: dir.path) else {
    fputs("[leak-check] FATAL: directory not found: \(dir.path)\n", stderr)
    exit(2)
}

func countMagenta(at url: URL) -> Int? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = cg.width, h = cg.height
    let px = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
    defer { px.deallocate() }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: px, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    var n = 0
    for i in 0..<(w * h) {
        let r = px[i*4], g = px[i*4+1], b = px[i*4+2]
        if r >= 200 && g <= 80 && b >= 200 { n += 1 }
    }
    return n
}

let frames = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "jpg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    ?? []

if frames.isEmpty {
    print("[leak-check] WARNING: no .jpg files found in \(dir.path)")
    exit(0)
}

var leaks: [(path: String, count: Int)] = []
var skipped = 0

for f in frames {
    if let n = countMagenta(at: f) {
        if n > 0 { leaks.append((f.path, n)) }
    } else {
        skipped += 1
    }
}

if skipped > 0 { print("[leak-check] skipped \(skipped) non-image file(s)") }
leaks.sort { $0.count > $1.count }

if leaks.isEmpty {
    print("[leak-check] OK — 0 leaks across \(frames.count) frame(s) in \(dir.path)")
    exit(0)
}

print("[leak-check] FAIL — \(leaks.count)/\(frames.count) frame(s) leaked magenta pixels:")
for l in leaks { print("  \(l.path)  \(l.count) px") }
exit(1)
