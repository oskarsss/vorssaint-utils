// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RecorderGIFWriterTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-gif-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try animation(suite, folder: folder)
            try workspaces(suite, root: folder.appendingPathComponent("scratch", isDirectory: true))
        } catch {
            suite.expect(false, "streaming GIF fixture failed: \(error)")
        }
    }

    private static func animation(_ suite: TestSuite, folder: URL) throws {
        // Different palettes and alpha ensure concatenation does not reuse the
        // previous frame's color table or show its pixels through transparency.
        let pictures = [picture(red: 1, green: 0, transparent: false),
                        picture(red: 0, green: 1, transparent: true)]
        let expectedPixels = try pictures.map { image -> [UInt8] in
            let data = NSMutableData()
            guard let sink = CGImageDestinationCreateWithData(
                data, UTType.gif.identifier as CFString, 1, nil) else {
                throw RecorderGIFWriter.Failure.invalidFrame
            }
            CGImageDestinationAddImage(sink, image, nil)
            guard CGImageDestinationFinalize(sink),
                  let source = CGImageSourceCreateWithData(data, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw RecorderGIFWriter.Failure.invalidFrame
            }
            return rgba(decoded)
        }
        for fps in [8, 12, 15] {
            let url = folder.appendingPathComponent("\(fps).gif")
            let writer = try RecorderGIFWriter(url: url, fps: fps)
            for index in 0..<450 { try writer.append(pictures[index % 2]) }
            try writer.finish()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                suite.expect(false, "streamed animation decodes at \(fps) fps")
                continue
            }
            suite.expect(CGImageSourceGetCount(source) == 450,
                         "all 450 frames survive streaming at \(fps) fps")
            let properties = CGImageSourceCopyProperties(source, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
            suite.expect((gif?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0,
                         "streamed animation loops indefinitely")
            var duration = 0.0
            var decoded = 0
            var coloursCorrect = true
            for index in 0..<CGImageSourceGetCount(source) {
                autoreleasepool {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
                    duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
                    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return }
                    decoded += 1
                    let pixels = rgba(image)
                    coloursCorrect = coloursCorrect && pixels == expectedPixels[index % 2]
                    if index % 2 == 1 { coloursCorrect = coloursCorrect && pixels[3] == 0 }
                }
            }
            suite.expect(decoded == 450 && coloursCorrect,
                         "every frame retains its own palette and clears preceding transparent pixels")
            suite.expectClose(duration, 450.0 / Double(fps),
                              "centisecond delays preserve the whole timeline at \(fps) fps", tol: 0.0051)
            do {
                try writer.append(pictures[0])
                suite.expect(false, "finished GIF writer rejects new frames")
            } catch { suite.expect(true, "finished GIF writer rejects new frames") }
        }

        let encoded = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(encoded, UTType.gif.identifier as CFString, 1, nil)
        else { throw RecorderGIFWriter.Failure.invalidFrame }
        CGImageDestinationAddImage(sink, pictures[0], nil)
        guard CGImageDestinationFinalize(sink) else { throw RecorderGIFWriter.Failure.invalidFrame }
        let data = encoded as Data
        // Exercise every truncation boundary, not just a bad magic signature.
        var rejected = 0
        for count in 0..<data.count {
            if (try? RecorderGIFWriter.frame(from: Data(data.prefix(count)))) == nil { rejected += 1 }
        }
        suite.expect(rejected == data.count, "truncated native GIF blocks are rejected safely")
        let mismatch = try RecorderGIFWriter(url: folder.appendingPathComponent("mismatch.gif"), fps: 12)
        try mismatch.append(pictures[0])
        do {
            try mismatch.append(picture(red: 1, green: 0, transparent: false, width: 16))
            suite.expect(false, "changing frame dimensions fails instead of corrupting the canvas")
        } catch { suite.expect(true, "changing frame dimensions fails instead of corrupting the canvas") }
        let empty = try RecorderGIFWriter(url: folder.appendingPathComponent("empty.gif"), fps: 12)
        do {
            try empty.finish()
            suite.expect(false, "an empty GIF cannot be finalized")
        } catch { suite.expect(true, "an empty GIF cannot be finalized") }
    }

    private static func workspaces(_ suite: TestSuite, root: URL) throws {
        let manager = FileManager.default
        let first = try RecorderGIFWorkspace(root: root)
        try Data("partial animation".utf8).write(to: first.fileURL)
        let second = try RecorderGIFWorkspace(root: root)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(manager.fileExists(atPath: first.fileURL.path)
                && manager.fileExists(atPath: second.folder.path),
                     "new exports and sweeping preserve every live export lease")

        // A crashed process releases its lock even though the file stays.
        let orphan = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: orphan, withIntermediateDirectories: false)
        let lease = Darwin.open(orphan.appendingPathComponent(".lease").path, O_CREAT | O_RDWR, 0o600)
        guard lease >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lease)
            throw CocoaError(.fileWriteUnknown)
        }
        try Data("crash remainder".utf8).write(to: orphan.appendingPathComponent("animation.gif"))
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(manager.fileExists(atPath: orphan.path), "an external live lease is retained")
        Darwin.close(lease)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(!manager.fileExists(atPath: orphan.path),
                     "released crash scratch is swept immediately without an age threshold")

        // A crash between mkdir and acquiring the lease is also recoverable.
        let unfinished = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: unfinished, withIntermediateDirectories: false)
        let unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let link = root.appendingPathComponent(UUID().uuidString)
        try manager.createSymbolicLink(at: link, withDestinationURL: unrelated)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(!manager.fileExists(atPath: unfinished.path)
                && manager.fileExists(atPath: unrelated.path) && manager.fileExists(atPath: link.path),
                     "sweep removes only export folders and never follows symlinks")
        first.discard()
        first.discard()
        second.discard()
        suite.expect(!manager.fileExists(atPath: first.folder.path)
                && !manager.fileExists(atPath: second.folder.path),
                     "export completion removes its scratch immediately and idempotently")
    }

    private static func picture(red: CGFloat, green: CGFloat, transparent: Bool, width: Int = 32) -> CGImage {
        let context = CGContext(data: nil, width: width, height: 32, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        let x = transparent ? width / 2 : 0
        context.fill(CGRect(x: x, y: 0, width: width - x, height: 32))
        return context.makeImage()!
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
