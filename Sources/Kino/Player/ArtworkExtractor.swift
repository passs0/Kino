import Foundation
import AppKit
import AVFoundation

/// High-performance embedded album art extraction for FLAC, MP3, M4A, ALAC, and video media.
public enum ArtworkExtractor {

    /// Asynchronously extracts embedded cover/poster artwork from a local media file.
    public static func extractArtwork(from fileURL: URL) async -> NSImage? {
        let ext = fileURL.pathExtension.lowercased()

        // 1. High-speed native FLAC METADATA_BLOCK_PICTURE parser (< 1ms, zero subprocesses)
        if ext == "flac" {
            if let flacImg = extractFromFlac(fileURL: fileURL) {
                return flacImg
            }
        }

        // 2. AVAsset Common Metadata (ID3 APIC for MP3, 'covr' for M4A/MP4, ALAC)
        let asset = AVURLAsset(url: fileURL)
        if let metadata = try? await asset.load(.metadata) {
            let artItems = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
            for item in artItems {
                if let data = try? await item.load(.dataValue), let img = NSImage(data: data) {
                    return img
                }
            }
        }

        // 3. Fast FFmpeg attached picture pipe extraction (for Vorbis, Ogg, MKV covers)
        if let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ffmpegPath)
            proc.arguments = [
                "-v", "quiet",
                "-i", fileURL.path,
                "-an",
                "-vcodec", "copy",
                "-f", "image2pipe",
                "-"
            ]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            do {
                try proc.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if !data.isEmpty, let img = NSImage(data: data) {
                    return img
                }
            } catch {}
        }

        return nil
    }

    /// Pure Swift parser for FLAC METADATA_BLOCK_PICTURE (Block Type 6).
    private static func extractFromFlac(fileURL: URL) -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        // Check standard "fLaC" 4-byte stream marker
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var isLast = false
        while !isLast {
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
            let firstByte = header[0]
            isLast = (firstByte & 0x80) != 0
            let blockType = firstByte & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            if blockType == 6 { // METADATA_BLOCK_PICTURE
                guard let blockData = try? handle.read(upToCount: length), blockData.count == length else { break }
                var offset = 0
                guard blockData.count >= 32 else { break }

                // 4 bytes: picture type (e.g. 3 = Cover Front)
                offset += 4

                // 4 bytes: MIME type length + MIME string
                guard offset + 4 <= blockData.count else { break }
                let mimeLen = Int(blockData[offset]) << 24 | Int(blockData[offset+1]) << 16 | Int(blockData[offset+2]) << 8 | Int(blockData[offset+3])
                offset += 4 + mimeLen

                // 4 bytes: Description length + Description string
                guard offset + 4 <= blockData.count else { break }
                let descLen = Int(blockData[offset]) << 24 | Int(blockData[offset+1]) << 16 | Int(blockData[offset+2]) << 8 | Int(blockData[offset+3])
                offset += 4 + descLen

                // 16 bytes: Width (4), Height (4), Color Depth (4), Indexed Colors (4)
                offset += 16

                // 4 bytes: Picture binary data length
                guard offset + 4 <= blockData.count else { break }
                let dataLen = Int(blockData[offset]) << 24 | Int(blockData[offset+1]) << 16 | Int(blockData[offset+2]) << 8 | Int(blockData[offset+3])
                offset += 4

                guard offset + dataLen <= blockData.count else { break }
                let picData = blockData.subdata(in: offset..<(offset + dataLen))
                return NSImage(data: picData)
            } else {
                // Skip to next block
                let current = (try? handle.offset()) ?? 0
                try? handle.seek(toOffset: current + UInt64(length))
            }
        }

        return nil
    }
}
