import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

/// Live playback telemetry extracted directly from AVPlayerItem / AVAssetTrack.
public struct LiveMediaMetrics: Sendable, Equatable {
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    public var colorInfo: String?
    public var droppedFrames: Int = 0
    public var indicatedBitrate: Double?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        fps: Double? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        colorInfo: String? = nil,
        droppedFrames: Int = 0,
        indicatedBitrate: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.colorInfo = colorInfo
        self.droppedFrames = droppedFrames
        self.indicatedBitrate = indicatedBitrate
    }
}

/// Isolated telemetry manager for live playback diagnostics.
/// Kept separate from PlayerController so frequent Movie Inspector metric polling
/// NEVER fires `PlayerController.objectWillChange` or invalidates root SwiftUI App Scenes / NSMenus.
@MainActor
public final class LiveMetricsManager: ObservableObject {
    public static let shared = LiveMetricsManager()

    @Published public private(set) var liveMetrics = LiveMediaMetrics()

    private init() {}

    public func reset() {
        if liveMetrics != LiveMediaMetrics() {
            liveMetrics = LiveMediaMetrics()
        }
    }

    public func refresh(from item: AVPlayerItem?) async {
        guard let item = item else {
            reset()
            return
        }

        var metrics = LiveMediaMetrics()

        if let videoTrack = (try? await item.asset.loadTracks(withMediaType: .video))?.first {
            if let size = try? await videoTrack.load(.naturalSize), size.width > 0 && size.height > 0 {
                metrics.width = Int(size.width.rounded())
                metrics.height = Int(size.height.rounded())
            }
            if let rate = try? await videoTrack.load(.nominalFrameRate), rate > 0 {
                metrics.fps = Double(rate)
            }
            if let formats = try? await videoTrack.load(.formatDescriptions), let desc = formats.first {
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                let fourCC = Self.fourCCString(subType)
                if !fourCC.isEmpty {
                    metrics.videoCodec = fourCC
                }

                if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                    var parts: [String] = []
                    if let primaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String,
                       let short = Self.shortColorName(primaries) {
                        parts.append(short)
                    }
                    if let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String,
                       let short = Self.shortColorName(transfer) {
                        parts.append(short)
                    }
                    if let matrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String,
                       let short = Self.shortColorName(matrix) {
                        parts.append(short)
                    }
                    if !parts.isEmpty {
                        metrics.colorInfo = parts.joined(separator: " / ")
                    }
                }
            }
        }

        if let audioTrack = (try? await item.asset.loadTracks(withMediaType: .audio))?.first,
           let formats = try? await audioTrack.load(.formatDescriptions),
           let desc = formats.first {
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            let fourCC = Self.fourCCString(subType)
            if !fourCC.isEmpty {
                metrics.audioCodec = fourCC
            }
        }

        if let lastEvent = item.accessLog()?.events.last {
            metrics.droppedFrames = max(0, lastEvent.numberOfDroppedVideoFrames)
            if lastEvent.indicatedBitrate > 0 {
                metrics.indicatedBitrate = lastEvent.indicatedBitrate
            }
        }

        // Only update if there is a real diff, minimizing view invalidations
        if self.liveMetrics != metrics {
            self.liveMetrics = metrics
        }
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return bytes.map { $0 >= 32 && $0 <= 126 ? String(UnicodeScalar($0)) : "" }
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private static func shortColorName(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if raw.contains("ITU_R_709") { return "bt709" }
        if raw.contains("ITU_R_2020") { return "bt2020" }
        if raw.contains("SMPTE_ST_2084") || raw.contains("PQ") { return "pq" }
        if raw.contains("HLG") { return "hlg" }
        if raw.contains("P3_D65") { return "p3" }
        if raw.contains("ITU_R_601") || raw.contains("SMPTE_C") { return "bt601" }
        return raw.replacingOccurrences(of: "CVImageBuffer", with: "")
    }
}
