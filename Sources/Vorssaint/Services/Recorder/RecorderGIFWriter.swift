// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO quantizes and compresses one picture at a time. Only that picture's
/// GIF data is resident; its palette and compressed image block are appended
/// to disk immediately. A multi-image ImageIO destination retains all frames.
///
/// GIF89a permits a separate local color table for each image. We retain the
/// native encoder's palette, transparency and LZW data rather than implementing
/// a new color quantizer or compressor.
final class RecorderGIFWriter {
    enum Failure: Error { case invalidFrame, closed, empty }

    private let file: FileHandle
    private let fps: Int
    private var frameCount = 0
    private var dimensions: (width: Int, height: Int)?
    private var closed = false

    init(url: URL, fps: Int) throws {
        guard (1...100).contains(fps) else { throw Failure.invalidFrame }
        self.fps = fps
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
    }

    deinit { try? file.close() }

    func append(_ image: CGImage) throws {
        guard !closed else { throw Failure.closed }
        // ImageIO's autoreleased quantizer and frame data must be released on
        // every iteration, including exports run on a long-lived worker task.
        try autoreleasepool {
            let data = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(
                data, UTType.gif.identifier as CFString, 1, nil) else {
                throw Failure.invalidFrame
            }
            CGImageDestinationAddImage(encoder, image, nil)
            guard CGImageDestinationFinalize(encoder) else { throw Failure.invalidFrame }
            let frame = try Self.frame(from: data as Data)
            if let dimensions {
                guard dimensions.width == frame.width, dimensions.height == frame.height else {
                    throw Failure.invalidFrame
                }
            } else {
                dimensions = (frame.width, frame.height)
                var header = Data("GIF89a".utf8)
                header.append(contentsOf: Self.word(frame.width) + Self.word(frame.height))
                // No global table: every full-canvas image carries its own.
                header.append(contentsOf: [0x70, 0, 0])
                // Infinite animation loop, matching the previous exporter.
                header.append(contentsOf: [0x21, 0xFF, 11])
                header.append(Data("NETSCAPE2.0".utf8))
                header.append(contentsOf: [3, 1, 0, 0, 0])
                try file.write(contentsOf: header)
            }
            // Full pictures replace the canvas. Restore the background between
            // them so transparent pixels cannot retain the preceding picture.
            var control = Data([0x21, 0xF9, 4, 0x08 | frame.transparencyFlag])
            // GIF ticks are centiseconds. Quantize the cumulative clock, not
            // each delay, so 12/15 fps do not drift over a long recording.
            let start = (Double(frameCount) * 100 / Double(fps)).rounded()
            let end = (Double(frameCount + 1) * 100 / Double(fps)).rounded()
            control.append(contentsOf: Self.word(Int(end - start)))
            control.append(contentsOf: [frame.transparentIndex, 0])
            try file.write(contentsOf: control)
            try file.write(contentsOf: frame.imageBlock)
            frameCount += 1
        }
    }

    func finish() throws {
        guard !closed else { throw Failure.closed }
        guard dimensions != nil else { throw Failure.empty }
        try file.write(contentsOf: Data([0x3B]))
        try file.synchronize()
        try file.close()
        closed = true
    }

    struct Frame {
        let width: Int
        let height: Int
        let transparencyFlag: UInt8
        let transparentIndex: UInt8
        let imageBlock: Data
    }

    /// Parses only native, single-frame GIF output. Reject missing palettes,
    /// cropped frames and truncated sub-blocks rather than publishing a broken
    /// animation. The compressed bytes and interlace flag are kept verbatim.
    static func frame(from data: Data) throws -> Frame {
        guard data.count >= 13,
              ["GIF87a", "GIF89a"].contains(String(decoding: data.prefix(6), as: UTF8.self)) else {
            throw Failure.invalidFrame
        }
        func word(at offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        let width = word(at: 6), height = word(at: 8)
        guard width > 0, height > 0 else { throw Failure.invalidFrame }
        let globalFlags = data[10]
        let globalCount = globalFlags & 0x80 == 0 ? 0 : 3 * (1 << (Int(globalFlags & 7) + 1))
        var offset = 13 + globalCount
        guard offset <= data.count else { throw Failure.invalidFrame }
        var transparency: UInt8 = 0, transparentIndex: UInt8 = 0

        func skipBlocks(_ offset: inout Int) throws {
            while offset < data.count {
                let length = Int(data[offset])
                offset += 1
                guard length <= data.count - offset else { throw Failure.invalidFrame }
                offset += length
                if length == 0 { return }
            }
            throw Failure.invalidFrame
        }

        while offset < data.count {
            switch data[offset] {
            case 0x21:
                guard offset + 2 < data.count else { throw Failure.invalidFrame }
                let label = data[offset + 1]
                offset += 2
                if label == 0xF9 {
                    guard offset + 6 <= data.count, data[offset] == 4,
                          data[offset + 5] == 0 else { throw Failure.invalidFrame }
                    transparency = data[offset + 1] & 1
                    transparentIndex = data[offset + 4]
                }
                try skipBlocks(&offset)
            case 0x2C:
                guard offset + 10 <= data.count,
                      word(at: offset + 1) == 0, word(at: offset + 3) == 0,
                      word(at: offset + 5) == width, word(at: offset + 7) == height else {
                    throw Failure.invalidFrame
                }
                var descriptor = data.subdata(in: offset..<(offset + 10))
                let flags = descriptor[9]
                offset += 10
                let localCount = flags & 0x80 == 0 ? 0 : 3 * (1 << (Int(flags & 7) + 1))
                let palette: Data
                if localCount > 0 {
                    guard localCount <= data.count - offset else { throw Failure.invalidFrame }
                    palette = data.subdata(in: offset..<(offset + localCount))
                    offset += localCount
                } else {
                    guard globalCount > 0 else { throw Failure.invalidFrame }
                    palette = data.subdata(in: 13..<(13 + globalCount))
                    descriptor[9] = (flags & 0x78) | 0x80 | (globalFlags & 7)
                }
                guard transparency == 0 || Int(transparentIndex) < palette.count / 3,
                      offset < data.count, (2...8).contains(data[offset]) else {
                    throw Failure.invalidFrame
                }
                let imageStart = offset
                offset += 1 // LZW minimum code size
                try skipBlocks(&offset)
                guard offset + 1 == data.count, data[offset] == 0x3B else {
                    throw Failure.invalidFrame
                }
                descriptor.append(palette)
                descriptor.append(data.subdata(in: imageStart..<offset))
                return Frame(width: width, height: height,
                             transparencyFlag: transparency, transparentIndex: transparentIndex,
                             imageBlock: descriptor)
            default:
                throw Failure.invalidFrame
            }
        }
        throw Failure.invalidFrame
    }

    private static func word(_ value: Int) -> [UInt8] {
        [UInt8(value & 255), UInt8((value >> 8) & 255)]
    }
}
