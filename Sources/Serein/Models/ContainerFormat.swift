import Foundation

/// Represents the multimedia container format enclosing video and audio tracks.
public enum ContainerFormat: Hashable, Sendable, CustomStringConvertible {
    case mp4
    case mov
    case m4v
    case mkv
    case webm
    case avi
    case ts
    case flv
    case hls
    case unknown(String)

    public init(rawString: String) {
        let lowered = rawString.lowercased()
        if lowered.contains("matroska") || lowered.contains("mkv") {
            self = .mkv
        } else if lowered.contains("quicktime") || lowered.contains("mov") {
            self = .mov
        } else if lowered.contains("mp4") || lowered.contains("isom") || lowered.contains("iso2") {
            self = .mp4
        } else if lowered.contains("m4v") {
            self = .m4v
        } else if lowered.contains("webm") {
            self = .webm
        } else if lowered.contains("avi") {
            self = .avi
        } else if lowered.contains("mpegts") || lowered.contains("ts") {
            self = .ts
        } else if lowered.contains("flv") {
            self = .flv
        } else if lowered.contains("hls") || lowered.contains("m3u8") {
            self = .hls
        } else {
            self = .unknown(rawString)
        }
    }

    public static func from(fileExtension: String) -> ContainerFormat {
        switch fileExtension.lowercased() {
        case "mp4": return .mp4
        case "mov": return .mov
        case "m4v": return .m4v
        case "mkv": return .mkv
        case "webm": return .webm
        case "avi": return .avi
        case "ts": return .ts
        case "flv": return .flv
        case "m3u8": return .hls
        default: return .unknown(fileExtension)
        }
    }

    /// Whether macOS AVFoundation (AVPlayer) can open and demux this container format directly.
    public var isNativelySupportedByAVPlayer: Bool {
        switch self {
        case .mp4, .mov, .m4v, .hls:
            return true
        case .ts:
            return true
        case .mkv, .webm, .avi, .flv, .unknown:
            return false
        }
    }

    /// Whether this container generally allows fast stream-copy remuxing into MP4 or HLS without re-encoding.
    public var canStreamCopyRemux: Bool {
        switch self {
        case .mkv, .webm, .ts, .mov, .mp4, .m4v, .avi, .flv, .hls:
            return true
        case .unknown:
            return true
        }
    }

    public var friendlyName: String {
        switch self {
        case .mp4: return "MPEG-4 Part 14 (.mp4)"
        case .mov: return "Apple QuickTime (.mov)"
        case .m4v: return "Apple Video (.m4v)"
        case .mkv: return "Matroska Media Container (.mkv)"
        case .webm: return "WebM Media (.webm)"
        case .avi: return "Audio Video Interleave (.avi)"
        case .ts: return "MPEG-2 Transport Stream (.ts)"
        case .flv: return "Flash Video (.flv)"
        case .hls: return "HTTP Live Streaming (.m3u8)"
        case .unknown(let str): return "Custom (\(str))"
        }
    }

    public var description: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .m4v: return "M4V"
        case .mkv: return "MKV"
        case .webm: return "WebM"
        case .avi: return "AVI"
        case .ts: return "MPEG-TS"
        case .flv: return "FLV"
        case .hls: return "HLS"
        case .unknown(let str): return str.uppercased()
        }
    }

    public var badgeColor: String {
        isNativelySupportedByAVPlayer ? "green" : "orange"
    }
}
