import Foundation

/// Detailed stream metadata extracted from media inspection.
public struct MediaStream: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let kind: StreamKind
    public let codecName: String
    public let codecLongName: String
    public let profile: String?
    public let bitrate: Int64?

    // Video specific
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let pixelFormat: String?
    public let videoCodec: VideoCodec?

    // Audio specific
    public let sampleRate: Int?
    public let channels: Int?
    public let channelLayout: String?
    public let audioCodec: AudioCodec?

    // Subtitle / Track metadata
    public let language: String?
    public let title: String?
    public let isDefault: Bool

    public var resolutionString: String? {
        guard let w = width, let h = height else { return nil }
        return "\(w) × \(h)"
    }

    public var fpsString: String? {
        guard let fps = fps else { return nil }
        return String(format: "%.2f fps", fps)
    }

    public var audioDetailsString: String? {
        var parts: [String] = []
        if let layout = channelLayout {
            parts.append(layout)
        } else if let ch = channels {
            parts.append("\(ch) ch")
        }
        if let sr = sampleRate {
            parts.append("\(sr / 1000) kHz")
        }
        if let br = bitrate {
            parts.append("\(br / 1000) kbps")
        }
        return parts.joined(separator: ", ")
    }
}

/// Comprehensive probe result analyzing the container format and all streams.
public struct MediaProbeResult: Hashable, Sendable {
    public let filename: String
    public let formatName: String
    public let formatLongName: String
    public let duration: Double
    public let sizeBytes: Int64
    public let overallBitrate: Int64
    public let containerFormat: ContainerFormat
    public let streams: [MediaStream]
    public let tags: [String: String]

    public var primaryVideo: MediaStream? {
        streams.first { $0.kind == .video }
    }

    public var primaryAudio: MediaStream? {
        streams.first { $0.kind == .audio }
    }

    public var subtitles: [MediaStream] {
        streams.filter { $0.kind == .subtitle }
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var formattedBitrate: String {
        if overallBitrate > 0 {
            return "\(overallBitrate / 1000) kbps"
        }
        return "Unknown"
    }
}
