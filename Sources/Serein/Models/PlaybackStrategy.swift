import Foundation

/// Strategy determined by the Media Coordinator for optimum playback performance.
public enum PlaybackStrategy: Hashable, Sendable {
    case directNative(playableURL: URL, reason: String)
    case remuxOnly(inputURL: URL, streamURL: URL, reason: String)
    case audioTranscodeOnly(inputURL: URL, streamURL: URL, reason: String)
    case fullTranscode(inputURL: URL, streamURL: URL, reason: String)
    case onlineDirect(streamURL: URL, originalURL: URL, title: String, reason: String)
    case onlineTranscode(streamURL: URL, originalURL: URL, title: String, reason: String)

    public var strategyTitle: String {
        switch self {
        case .directNative:
            return "Direct Native Playback"
        case .remuxOnly:
            return "Fast Stream-Copy Remux"
        case .audioTranscodeOnly:
            return "Video-Copy & Audio Transcode"
        case .fullTranscode:
            return "Hardware VideoToolbox Transcode"
        case .onlineDirect:
            return "Direct Online Stream"
        case .onlineTranscode:
            return "Online Stream Compatibility Bridge"
        }
    }

    public var badgeLabel: String {
        switch self {
        case .directNative: return "DIRECT NATIVE"
        case .remuxOnly: return "STREAM COPY"
        case .audioTranscodeOnly: return "AUDIO TRANSCODE"
        case .fullTranscode: return "FULL HW TRANSCODE"
        case .onlineDirect: return "ONLINE DIRECT"
        case .onlineTranscode: return "ONLINE TRANSCODE"
        }
    }

    public var iconName: String {
        switch self {
        case .directNative: return "bolt.fill"
        case .remuxOnly: return "arrow.triangle.swap"
        case .audioTranscodeOnly: return "waveform"
        case .fullTranscode: return "cpu"
        case .onlineDirect: return "globe"
        case .onlineTranscode: return "network.badge.shield.half.filled"
        }
    }

    public var estimatedCpuImpact: String {
        switch self {
        case .directNative: return "0% (Zero overhead)"
        case .remuxOnly: return "< 1% (I/O only, no re-encoding)"
        case .audioTranscodeOnly: return "< 4% (Audio DSP only)"
        case .fullTranscode: return "~12% (Apple Silicon VideoToolbox HW)"
        case .onlineDirect: return "0% (Native network buffer)"
        case .onlineTranscode: return "~5-15% (Dynamic remux & stream)"
        }
    }

    public var latencyDescription: String {
        switch self {
        case .directNative: return "Instant (< 5ms)"
        case .remuxOnly: return "Ultra Fast (< 150ms)"
        case .audioTranscodeOnly: return "Fast (< 300ms)"
        case .fullTranscode: return "Smooth Buffer (~800ms)"
        case .onlineDirect: return "Network Dependent"
        case .onlineTranscode: return "Network & Buffer (~1.2s)"
        }
    }

    public var explanation: String {
        switch self {
        case .directNative(_, let reason): return reason
        case .remuxOnly(_, _, let reason): return reason
        case .audioTranscodeOnly(_, _, let reason): return reason
        case .fullTranscode(_, _, let reason): return reason
        case .onlineDirect(_, _, _, let reason): return reason
        case .onlineTranscode(_, _, _, let reason): return reason
        }
    }

    public var activeStreamURL: URL {
        switch self {
        case .directNative(let url, _): return url
        case .remuxOnly(_, let url, _): return url
        case .audioTranscodeOnly(_, let url, _): return url
        case .fullTranscode(_, let url, _): return url
        case .onlineDirect(let url, _, _, _): return url
        case .onlineTranscode(let url, _, _, _): return url
        }
    }

    public var isDirectNative: Bool {
        switch self {
        case .directNative, .onlineDirect:
            return true
        default:
            return false
        }
    }
}
