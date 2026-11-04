import Foundation

/// Stream classification
public enum StreamKind: String, Codable, Sendable {
    case video
    case audio
    case subtitle
    case data
    case attachment
    case unknown

    public init(rawString: String) {
        switch rawString.lowercased() {
        case "video": self = .video
        case "audio": self = .audio
        case "subtitle": self = .subtitle
        case "data": self = .data
        case "attachment": self = .attachment
        default: self = .unknown
        }
    }
}

/// Video codec identification and macOS hardware decoding compatibility.
public enum VideoCodec: Hashable, Sendable, CustomStringConvertible {
    case h264
    case hevc
    case proRes
    case vp9
    case vp8
    case av1
    case mpeg4
    case mpeg2
    case unknown(String)

    public init(name: String) {
        let lowered = name.lowercased()
        if lowered.contains("h264") || lowered.contains("avc") {
            self = .h264
        } else if lowered.contains("hevc") || lowered.contains("h265") {
            self = .hevc
        } else if lowered.contains("prores") {
            self = .proRes
        } else if lowered.contains("vp9") {
            self = .vp9
        } else if lowered.contains("vp8") {
            self = .vp8
        } else if lowered.contains("av1") || lowered.contains("av01") {
            self = .av1
        } else if lowered.contains("mpeg4") || lowered.contains("xvid") || lowered.contains("divx") {
            self = .mpeg4
        } else if lowered.contains("mpeg2") || lowered.contains("mp2") {
            self = .mpeg2
        } else {
            self = .unknown(name)
        }
    }

    /// Whether macOS AVFoundation natively decodes this video codec with hardware acceleration and standard streaming.
    public var isNativelyDecodable: Bool {
        switch self {
        case .h264, .hevc, .proRes:
            return true
        case .vp9, .vp8, .av1, .mpeg4, .mpeg2, .unknown:
            return false
        }
    }

    /// Whether Apple Silicon VideoToolbox provides hardware encoder acceleration for this codec.
    public var hasHardwareEncoder: Bool {
        switch self {
        case .hevc, .h264, .proRes:
            return true
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .h264: return "H.264 (AVC)"
        case .hevc: return "HEVC (H.265)"
        case .proRes: return "Apple ProRes"
        case .vp9: return "Google VP9"
        case .vp8: return "VP8"
        case .av1: return "AOMedia AV1"
        case .mpeg4: return "MPEG-4 Part 2"
        case .mpeg2: return "MPEG-2"
        case .unknown(let s): return s.uppercased()
        }
    }
}

/// Audio codec identification and macOS decoding compatibility.
public enum AudioCodec: Hashable, Sendable, CustomStringConvertible {
    case aac
    case ac3
    case eac3
    case alac
    case pcm
    case mp3
    case flac
    case opus
    case vorbis
    case dts
    case truehd
    case unknown(String)

    public init(name: String) {
        let lowered = name.lowercased()
        if lowered.contains("aac") {
            self = .aac
        } else if lowered.contains("eac3") || lowered.contains("ec-3") || lowered.contains("dolby digital plus") {
            self = .eac3
        } else if lowered.contains("ac3") || lowered.contains("dolby digital") {
            self = .ac3
        } else if lowered.contains("alac") {
            self = .alac
        } else if lowered.contains("pcm") {
            self = .pcm
        } else if lowered.contains("mp3") || lowered.contains("mp3float") {
            self = .mp3
        } else if lowered.contains("flac") {
            self = .flac
        } else if lowered.contains("opus") {
            self = .opus
        } else if lowered.contains("vorbis") {
            self = .vorbis
        } else if lowered.contains("dts") || lowered.contains("dca") {
            self = .dts
        } else if lowered.contains("truehd") {
            self = .truehd
        } else {
            self = .unknown(name)
        }
    }

    /// Whether macOS AVFoundation natively decodes this audio stream without transcoding.
    public var isNativelyDecodable: Bool {
        switch self {
        case .aac, .ac3, .eac3, .alac, .pcm, .mp3, .flac:
            return true
        case .opus, .vorbis, .dts, .truehd, .unknown:
            return false
        }
    }

    public var description: String {
        switch self {
        case .aac: return "AAC"
        case .ac3: return "Dolby Digital (AC-3)"
        case .eac3: return "Dolby Digital Plus (E-AC-3)"
        case .alac: return "Apple Lossless (ALAC)"
        case .pcm: return "Linear PCM"
        case .mp3: return "MP3"
        case .flac: return "FLAC"
        case .opus: return "Opus"
        case .vorbis: return "Vorbis"
        case .dts: return "DTS / DCA"
        case .truehd: return "Dolby TrueHD"
        case .unknown(let s): return s.uppercased()
        }
    }
}
