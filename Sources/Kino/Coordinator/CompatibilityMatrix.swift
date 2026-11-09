import Foundation

/// Decision engine determining the optimal playback strategy for any media container and stream configuration.
public struct CompatibilityMatrix: Sendable {
    public static func evaluate(
        source: MediaSource,
        probe: MediaProbeResult?,
        onlineInfo: ExtractedMediaInfo?
    ) -> PlaybackStrategy {
        // Online stream evaluation
        if case .online(let webURL, _) = source {
            if let info = onlineInfo {
                if info.isDirectlyPlayable {
                    return .onlineDirect(
                        streamURL: info.selectedStreamURL,
                        originalURL: webURL,
                        title: info.title,
                        reason: "Native streaming format detected (\(info.selectedStreamURL.pathExtension.uppercased())). Playing direct online stream with zero conversion."
                    )
                } else {
                    return .onlineTranscode(
                        streamURL: info.selectedStreamURL,
                        originalURL: webURL,
                        title: info.title,
                        reason: "Online source requires format adaptation. Streaming via compatibility bridge."
                    )
                }
            }
        }

        let rawURL = source.rawURL

        // Fallback heuristics ONLY when probe is unavailable
        guard let p = probe else {
            let ext = source.fileExtension.lowercased()
            if ["mp4", "mov", "m4v", "flac", "mp3", "m4a", "aac", "wav", "aiff", "aif"].contains(ext) && !source.isOnline {
                return .directNative(playableURL: rawURL, reason: "Native container detected (\(ext.uppercased())). Attempting direct hardware playback.")
            } else if ["mkv", "webm"].contains(ext) {
                return .remuxOnly(inputURL: rawURL, streamURL: rawURL, reason: "Container \(ext.uppercased()) requires stream copy remuxing.")
            } else {
                return .fullTranscode(inputURL: rawURL, streamURL: rawURL, reason: "Stream without recognized extension or uncommon container. Forcing hardware transcoding bridge.")
            }
        }

        let containerNative = p.containerFormat.isNativelySupportedByAVPlayer
        let vStream = p.primaryVideo
        let aStream = p.primaryAudio

        let videoNative = vStream == nil || (vStream?.videoCodec?.isNativelyDecodable ?? false)
        let audioNative = aStream == nil || (aStream?.audioCodec?.isNativelyDecodable ?? false)

        // Case 1: Container and all streams are natively supported by macOS AVFoundation directly
        // For online streams, AVPlayer strictly requires a clean static .mp4/.mov/.m4v file path without query-string download endpoints.
        // Download endpoints (with /download/?fid=... or dynamic parameters) return application/octet-stream and must be remuxed by FFmpeg.
        let isCleanNativeURL = !source.isOnline || (
            ["mp4", "mov", "m4v", "flac", "mp3", "m4a", "aac", "wav", "aiff"].contains(rawURL.pathExtension.lowercased()) &&
            !rawURL.path.contains("/download") &&
            rawURL.query == nil
        )

        if containerNative && videoNative && audioNative && isCleanNativeURL {
            let vName = vStream?.videoCodec?.description ?? "No Video"
            let aName = aStream?.audioCodec?.description ?? "No Audio"
            return .directNative(
                playableURL: rawURL,
                reason: "Direct Hardware Playback: Container (\(p.containerFormat)) and streams (\(vName), \(aName)) are fully native. Zero re-encoding, zero latency."
            )
        }

        // Modern Apple fMP4 HLS supports bit-for-bit stream-copy of any codec natively decodable on Apple Silicon (H.264, HEVC / H.265, ProRes).
        let isStreamCopyableVideo = vStream == nil || vStream?.videoCodec?.isNativelyDecodable == true

        // Case 2: Native video (H.264/HEVC) and native audio, but non-native container or cloud download URL requiring local fMP4 HLS packaging
        if isStreamCopyableVideo && audioNative {
            let vName = vStream?.videoCodec?.description ?? "Video"
            let aName = aStream?.audioCodec?.description ?? "Audio"
            let reasonStr = source.isOnline
                ? "Cloud Stream Copy: Demuxing remote \(p.containerFormat) stream with FFmpeg and packaging into local fMP4 HLS in real-time. Zero video quality loss, 0% CPU."
                : "Fast Stream Copy: \(p.containerFormat) container rejected by AVPlayer, but contains native \(vName) & \(aName). Remuxing on-the-fly to fMP4 HLS in < 100ms with zero video quality loss."
            return .remuxOnly(
                inputURL: rawURL,
                streamURL: rawURL,
                reason: reasonStr
            )
        }

        // Case 3: Native video (H.264/HEVC), but audio requires transcoding (e.g. MKV with DTS, TrueHD, FLAC, Opus)
        if isStreamCopyableVideo && !audioNative {
            let vName = vStream?.videoCodec?.description ?? "Video"
            let aName = aStream?.audioCodec?.description ?? aStream?.codecName ?? "Incompatible Audio"
            return .audioTranscodeOnly(
                inputURL: rawURL,
                streamURL: rawURL,
                reason: "Zero-Copy Video & Audio Transcode: \(vName) video is stream-copied bit-for-bit with 0% CPU loss. Incompatible audio (\(aName)) is transcoded in real-time to studio-grade multichannel AAC in fMP4 HLS."
            )
        }

        // Case 4: Video codec is truly incompatible with macOS hardware decoders (e.g. VP9, VP8, AV1, MPEG-2, VC-1)
        let vName = vStream?.videoCodec?.description ?? vStream?.codecName ?? "Unsupported Video"
        return .fullTranscode(
            inputURL: rawURL,
            streamURL: rawURL,
            reason: "Hardware VideoToolbox Transcode: Video codec (\(vName)) requires hardware transcoding to compliant format for AVPlayer. Real-time Apple Silicon VideoToolbox engaged."
        )
    }
}
