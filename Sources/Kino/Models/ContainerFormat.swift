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
    case flac
    case mp3
    case m4a
    case aac
    case wav
    case aiff
    case ogg
    case opus
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
        } else if lowered.contains("flac") {
            self = .flac
        } else if lowered.contains("mp3") {
            self = .mp3
        } else if lowered.contains("m4a") {
            self = .m4a
        } else if lowered.contains("aac") {
            self = .aac
        } else if lowered.contains("wav") || lowered.contains("wave") {
            self = .wav
        } else if lowered.contains("aiff") || lowered.contains("aif") {
            self = .aiff
        } else if lowered.contains("ogg") || lowered.contains("oga") {
            self = .ogg
        } else if lowered.contains("opus") {
            self = .opus
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
        case "flac": return .flac
        case "mp3": return .mp3
        case "m4a": return .m4a
        case "aac": return .aac
        case "wav", "wave": return .wav
        case "aiff", "aif": return .aiff
        case "ogg", "oga": return .ogg
        case "opus": return .opus
        default: return .unknown(fileExtension)
        }
    }

    /// Whether macOS AVFoundation (AVPlayer) can open and demux this container format directly.
    public var isNativelySupportedByAVPlayer: Bool {
        switch self {
        case .mp4, .mov, .m4v, .hls, .ts, .flac, .mp3, .m4a, .aac, .wav, .aiff:
            return true
        case .mkv, .webm, .avi, .flv, .ogg, .opus, .unknown:
            return false
        }
    }

    /// Whether this container generally allows fast stream-copy remuxing into MP4 or HLS without re-encoding.
    public var canStreamCopyRemux: Bool {
        switch self {
        case .mkv, .webm, .ts, .mov, .mp4, .m4v, .avi, .flv, .hls, .flac, .mp3, .m4a, .aac, .wav, .aiff, .ogg, .opus:
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
        case .flac: return "Free Lossless Audio Codec (.flac)"
        case .mp3: return "MPEG Audio Layer III (.mp3)"
        case .m4a: return "Apple Audio (.m4a)"
        case .aac: return "Advanced Audio Coding (.aac)"
        case .wav: return "Waveform Audio (.wav)"
        case .aiff: return "Audio Interchange File Format (.aiff)"
        case .ogg: return "Ogg Audio (.ogg)"
        case .opus: return "Opus Audio (.opus)"
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
        case .flac: return "FLAC"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .aac: return "AAC"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .ogg: return "OGG"
        case .opus: return "OPUS"
        case .unknown(let str): return str.uppercased()
        }
    }

    public var badgeColor: String {
        isNativelySupportedByAVPlayer ? "green" : "orange"
    }
}
