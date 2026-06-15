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

// Frames whose filename starts with one of these prefixes are still scanned
// and reported, but their leaks are non-blocking (warn instead of fail). Set
// via CX_LEAK_WARN_ONLY_PREFIXES (comma-separated). Empty/unset → every leak
// is blocking (the strict default, used for local runs). CI opts the known
// navigation-transition leak into warn-only; tracked in CX-45948.
let warnOnlyPrefixes = (ProcessInfo.processInfo.environment["CX_LEAK_WARN_ONLY_PREFIXES"] ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

func isWarnOnly(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    return warnOnlyPrefixes.contains { name.hasPrefix($0) }
}

var fatal: [(path: String, count: Int)] = []
var warn: [(path: String, count: Int)] = []
var skipped = 0

for f in frames {
    if let n = countMagenta(at: f) {
        guard n > 0 else { continue }
        if isWarnOnly(f) { warn.append((f.path, n)) } else { fatal.append((f.path, n)) }
    } else {
        skipped += 1
    }
}

if skipped > 0 { print("[leak-check] skipped \(skipped) non-image file(s)") }
fatal.sort { $0.count > $1.count }
warn.sort { $0.count > $1.count }

if !warn.isEmpty {
    print("[leak-check] WARN — \(warn.count)/\(frames.count) frame(s) leaked but are non-blocking (CX_LEAK_WARN_ONLY_PREFIXES); tracked in CX-45948:")
    for l in warn { print("  (warn) \(l.path)  \(l.count) px") }
}

if fatal.isEmpty {
    let suffix = warn.isEmpty ? "" : " (\(warn.count) non-blocking frame(s) warned)"
    print("[leak-check] OK — 0 blocking leaks across \(frames.count) frame(s) in \(dir.path)\(suffix)")
    exit(0)
}

print("[leak-check] FAIL — \(fatal.count)/\(frames.count) frame(s) leaked magenta pixels:")
for l in fatal { print("  \(l.path)  \(l.count) px") }
exit(1)
