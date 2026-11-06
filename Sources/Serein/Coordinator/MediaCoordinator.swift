import Foundation
import Combine

public enum CoordinatorState: Equatable, Sendable {
    case idle
    case probing(String)
    case extractingOnline(String)
    case preparingStream(String)
    case ready(PlaybackStrategy)
    case error(String)
}

public struct CoordinatorLogItem: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public enum LogLevel: String, Sendable {
        case info = "INFO"
        case success = "SUCCESS"
        case warning = "WARN"
        case error = "ERROR"
        case transcode = "TRANSCODE"
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// The central Media Coordinator orchestrating source detection, extraction, probing, and playback strategy.
@MainActor
public final class MediaCoordinator: ObservableObject {
    public static let shared = MediaCoordinator()

    @Published public private(set) var state: CoordinatorState = .idle
    @Published public private(set) var currentSource: MediaSource?
    @Published public private(set) var probeResult: MediaProbeResult?
    @Published public private(set) var extractedOnlineInfo: ExtractedMediaInfo?
    @Published public private(set) var activeStrategy: PlaybackStrategy?
    @Published public private(set) var activePlayableURL: URL?
    @Published public private(set) var pipelineStats: PipelineStats?
    @Published public private(set) var logs: [CoordinatorLogItem] = []

    @Published public var isInspectorPresented: Bool = false

    /// Debug and preview helper to populate inspector state
    public func setDebugInspectorData(strategy: PlaybackStrategy?, onlineInfo: ExtractedMediaInfo?, probe: MediaProbeResult? = nil) {
        self.activeStrategy = strategy
        self.extractedOnlineInfo = onlineInfo
        self.probeResult = probe
    }

    public var knownDuration: Double? {
        if let p = probeResult, p.duration > 0 {
            return p.duration
        }
        if let o = extractedOnlineInfo, let d = o.duration, d > 0 {
            return d
        }
        return nil
    }

    private let ffmpegPipeline = FFmpegPipeline()
    private var loadTask: Task<Void, Never>?

    public init() {
        setupPipelineCallbacks()
        log("Media Coordinator initialized. Ready for local files & online URLs.", level: .info)
    }

    private func setupPipelineCallbacks() {
        ffmpegPipeline.onStatsUpdated = { [weak self] stats in
            Task { @MainActor [weak self] in
                self?.pipelineStats = stats
            }
        }

        ffmpegPipeline.onLogLine = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.log(line, level: .transcode)
            }
        }
    }

    public func log(_ message: String, level: CoordinatorLogItem.LogLevel = .info) {
        let item = CoordinatorLogItem(timestamp: Date(), level: level, message: message)
        logs.append(item)
        if logs.count > 1000 {
            logs.removeFirst(100)
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Main Coordination Workflow

    public func openSource(_ source: MediaSource) {
        loadTask?.cancel()
        ffmpegPipeline.stop()
        pipelineStats = nil
        AudioManager.shared.reset()

        currentSource = source
        probeResult = nil
        extractedOnlineInfo = nil
        activeStrategy = nil
        activePlayableURL = nil

        log("📂 Ingesting media source: [\(source.displayName)]", level: .info)

        loadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.processSource(source)
        }
    }

    public func openLocalFile(url: URL) {
        openSource(.local(url))
    }

    public func openOnlineURL(string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            state = .error("Invalid URL format.")
            log("Invalid URL provided: \(string)", level: .error)
            return
        }
        openSource(.online(url: url, originalInput: string))
    }

    private func processSource(_ source: MediaSource) async {
        switch source {
        case .local(let fileURL):
            await processLocalFile(fileURL)
        case .online(let webURL, let originalInput):
            await processOnlineURL(webURL: webURL, originalInput: originalInput)
        }
    }

    private func processLocalFile(_ fileURL: URL) async {
        state = .probing("Inspecting container & codecs with FFprobe...")
        log("🔍 Running FFprobe deep container analysis on \(fileURL.lastPathComponent)", level: .info)

        var probe: MediaProbeResult? = nil
        do {
            probe = try await FFprobeService.shared.probe(url: fileURL)
            self.probeResult = probe
            if let p = probe {
                if p.duration > 0 {
                    PlayerController.shared.setKnownDuration(p.duration)
                }
                log("📊 Container: \(p.containerFormat.friendlyName) | Duration: \(p.formattedDuration) | Bitrate: \(p.formattedBitrate)", level: .success)
                if let v = p.primaryVideo {
                    log("🎥 Video Stream #\(v.index): \(v.codecLongName) (\(v.videoCodec?.description ?? v.codecName)) \(v.resolutionString ?? "") @ \(v.fpsString ?? "")", level: .info)
                }
                if let a = p.primaryAudio {
                    log("🔊 Audio Stream #\(a.index): \(a.codecLongName) (\(a.audioCodec?.description ?? a.codecName)) [\(a.audioDetailsString ?? "")]", level: .info)
                }

                // Populate Subtitles
                let localSubTracks = p.subtitles.map { sub -> SubtitleTrack in
                    let name = sub.title ?? (sub.language != nil ? (Locale.current.localizedString(forLanguageCode: sub.language!) ?? sub.language!.uppercased()) : "Track \(sub.index)")
                    return SubtitleTrack(
                        id: "stream_\(sub.index)",
                        name: name,
                        languageCode: sub.language,
                        isAutoGenerated: false,
                        vttURL: nil,
                        streamIndex: sub.index,
                        sourceURL: fileURL,
                        isDefault: sub.isDefault
                    )
                }
                SubtitleManager.shared.setAvailableTracks(localSubTracks)
                if let initial = localSubTracks.first(where: { $0.isDefault }) ?? localSubTracks.first {
                    SubtitleManager.shared.selectTrack(initial)
                }
                if !localSubTracks.isEmpty {
                    log("💬 Detected \(localSubTracks.count) subtitle tracks in container.", level: .info)
                }

                // Populate Audio Tracks
                let localAudioTracks = p.audioStreams.map { a -> AudioTrack in
                    let lang = a.language
                    let langDisplay = lang != nil ? (Locale.current.localizedString(forLanguageCode: lang!) ?? lang!.uppercased()) : nil
                    let title = a.title
                    var name = title ?? langDisplay ?? "Track \(a.index)"
                    if let ch = a.channels {
                        let chStr = ch == 1 ? "Mono" : (ch == 2 ? "Stereo" : (ch == 6 ? "5.1 Surround" : (ch == 8 ? "7.1 Surround" : "\(ch) ch")))
                        name += " (\(chStr))"
                    }
                    return AudioTrack(
                        id: "audio_\(a.index)",
                        streamIndex: a.index,
                        name: name,
                        languageCode: lang,
                        codecName: a.codecName,
                        channels: a.channels,
                        channelLayout: a.channelLayout,
                        sampleRate: a.sampleRate,
                        isDefault: a.isDefault
                    )
                }
                AudioManager.shared.setAvailableTracks(localAudioTracks)
                if !localAudioTracks.isEmpty {
                    log("🔊 Detected \(localAudioTracks.count) audio track(s) in container.", level: .info)
                }
            }
        } catch {
            log("⚠️ FFprobe inspection warning: \(error.localizedDescription). Proceeding with extension heuristics.", level: .warning)
        }

        // Determine Strategy
        let strategy = CompatibilityMatrix.evaluate(source: .local(fileURL), probe: probe, onlineInfo: nil)
        self.activeStrategy = strategy
        log("💡 Evaluated Strategy: [\(strategy.badgeLabel)] - \(strategy.strategyTitle)", level: .success)
        log("ℹ️ Rationale: \(strategy.explanation)", level: .info)

        let selectedAudioIndex = AudioManager.shared.selectedTrack?.streamIndex

        // Execute Strategy
        switch strategy {
        case .directNative(let url, _):
            self.activePlayableURL = url
            self.state = .ready(strategy)
            log("⚡️ AVPlayer direct native hardware playback started.", level: .success)

        case .remuxOnly(let inputURL, _, _):
            state = .preparingStream("Fast Remuxing into local stream...")
            log("⚙️ Starting zero-reencode HLS remux pipeline...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .remuxCopy, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Live remux stream connected to AVPlayer.", level: .success)
            } catch {
                if case .ffmpegNotFound = (error as? FFmpegPipelineError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                state = .error("Remux pipeline failed: \(error.localizedDescription)")
                log("❌ Remux failed: \(error.localizedDescription)", level: .error)
            }

        case .audioTranscodeOnly(let inputURL, _, _):
            state = .preparingStream("Transcoding audio track to AAC...")
            log("⚙️ Starting video-copy + AAC audio transcode pipeline...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .audioTranscodeOnly, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Audio transcode stream connected to AVPlayer.", level: .success)
            } catch {
                if case .ffmpegNotFound = (error as? FFmpegPipelineError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                state = .error("Audio transcode pipeline failed: \(error.localizedDescription)")
                log("❌ Audio transcode failed: \(error.localizedDescription)", level: .error)
            }

        case .fullTranscode(let inputURL, _, _):
            state = .preparingStream("Transcoding video via VideoToolbox HW encoder...")
            log("⚙️ Starting Apple Silicon VideoToolbox hardware transcode...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Hardware transcode stream connected to AVPlayer.", level: .success)
            } catch {
                if case .ffmpegNotFound = (error as? FFmpegPipelineError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                state = .error("Transcode pipeline failed: \(error.localizedDescription)")
                log("❌ Transcode failed: \(error.localizedDescription)", level: .error)
            }

        default:
            break
        }
    }

    private func isDirectDownloadOrMediaURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""

        // Known video and streaming platforms MUST always be extracted via yt-dlp:
        let videoPlatforms = [
            "youtube.com", "youtu.be", "vimeo.com", "bilibili.com", "twitch.tv",
            "tiktok.com", "twitter.com", "x.com", "dailymotion.com", "facebook.com",
            "instagram.com", "reddit.com", "soundcloud.com", "nicovideo.jp"
        ]
        if videoPlatforms.contains(where: { host.contains($0) }) {
            return false
        }

        // Direct media extensions (e.g. .mp4, .mkv, .m3u8, .mov, etc.)
        let mediaExts = ["mp4", "mkv", "mov", "webm", "m3u8", "ts", "avi", "flv", "m4v"]
        if mediaExts.contains(url.pathExtension.lowercased()) {
            return true
        }

        // Cloud storage and CDN direct download patterns (e.g. PikPak, Google Drive, Alist)
        let knownDirectHosts = ["mypikpak.com", "pikpak", "drive.google.com", "dropbox.com", "115.com", "alist", "mediafire.com", "mega.nz", "box.com", "onedrive.live.com"]
        if knownDirectHosts.contains(where: { host.contains($0) }) {
            return true
        }

        if path.contains("/download") || path.contains("/file/") || path.contains("/stream") || path.contains("/raw") || query.contains("download") || query.contains("fid=") {
            return true
        }

        return false
    }

    private func processOnlineURL(webURL: URL, originalInput: String) async {
        let isDirect = isDirectDownloadOrMediaURL(webURL)

        if !isDirect {
            state = .extractingOnline("Resolving stream metadata with yt-dlp...")
            log("🌐 Invoking yt-dlp extractor for \(originalInput)", level: .info)

            do {
                let extracted = try await YtDlpService.shared.extract(url: webURL)
                self.extractedOnlineInfo = extracted
                NowPlayingManager.shared.mediaItemDidChange()
                if let d = extracted.duration, d > 0 {
                    PlayerController.shared.setKnownDuration(d)
                }
                SubtitleManager.shared.setAvailableTracks(extracted.subtitles)
                if let initial = extracted.subtitles.first(where: { !$0.isAutoGenerated && ($0.languageCode == "en" || $0.isDefault) }) ?? extracted.subtitles.first(where: { !$0.isAutoGenerated }) ?? extracted.subtitles.first {
                    SubtitleManager.shared.selectTrack(initial)
                }
                if !extracted.subtitles.isEmpty {
                    log("💬 Loaded \(extracted.subtitles.count) subtitles/captions (including auto-generated).", level: .info)
                }
                log("🎯 Resolved online media: \"\(extracted.title)\" by \(extracted.uploader ?? "Unknown") [\(extracted.resolution ?? "Auto")]", level: .success)

                let strategy = CompatibilityMatrix.evaluate(
                    source: .online(url: webURL, originalInput: originalInput),
                    probe: nil,
                    onlineInfo: extracted
                )
                self.activeStrategy = strategy
                log("💡 Evaluated Online Strategy: [\(strategy.badgeLabel)]", level: .success)

                if let masterPlaylist = extracted.hlsMasterPlaylist {
                    state = .preparingStream("Connecting high-speed native HLS stream...")
                    do {
                        let streamURL = try ffmpegPipeline.startHLSProxySession(masterPlaylist: masterPlaylist)
                        self.activePlayableURL = streamURL
                        self.state = .ready(strategy)
                        log("⚡️ Connected high-speed native HLS multi-variant stream to AVPlayer via local proxy.", level: .success)
                        return
                    } catch {
                        log("⚠️ HLS proxy failed: \(error.localizedDescription). Falling back to piped stream...", level: .warning)
                    }
                }

                if extracted.isDirectlyPlayable && !extracted.needsPipedStream {
                    self.activePlayableURL = extracted.selectedStreamURL
                    self.state = .ready(strategy)
                    log("⚡️ Streaming direct progressive/HLS URL in AVPlayer.", level: .success)
                    return
                }

                state = .preparingStream("Connecting online stream via yt-dlp & FFmpeg bridge...")
                log("⚙️ Routing stream through yt-dlp ➔ FFmpeg pipeline...", level: .info)
                let streamURL = try await ffmpegPipeline.startOnlinePipedSession(webURL: webURL)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Online stream connected to AVPlayer via local bridge.", level: .success)
                return
            } catch {
                if case .ytDlpNotFound = (error as? YtDlpError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                    state = .error("yt-dlp is required for this URL. Please install it via Prerequisites.")
                    return
                }
                if case .ffmpegNotFound = (error as? FFmpegPipelineError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                    state = .error("FFmpeg is required for this stream. Please install it via Prerequisites.")
                    return
                }
                log("❌ Online video extraction error: \(error.localizedDescription)", level: .error)
                state = .error("Failed to load online video: \(error.localizedDescription)")
                return
            }
        }

        // Direct Stream & Cloud Drive fallback (e.g. CDN, direct progressive files)
        await processDirectOnlineStream(webURL: webURL, originalInput: originalInput)
    }

    private func processDirectOnlineStream(webURL: URL, originalInput: String) async {
        state = .probing("Probing online media stream with FFprobe...")
        log("🌐 Inspecting direct stream from \(webURL.host ?? "remote host")...", level: .info)

        var probe: MediaProbeResult? = nil
        do {
            probe = try await FFprobeService.shared.probe(url: webURL)
            self.probeResult = probe
            if let p = probe {
                if p.duration > 0 {
                    PlayerController.shared.setKnownDuration(p.duration)
                }
                log("📊 Container: \(p.containerFormat.friendlyName) | Duration: \(p.formattedDuration) | Bitrate: \(p.formattedBitrate)", level: .success)
                if let v = p.primaryVideo {
                    log("🎥 Video Stream #\(v.index): \(v.codecLongName) (\(v.videoCodec?.description ?? v.codecName)) \(v.resolutionString ?? "") @ \(v.fpsString ?? "")", level: .info)
                }
                if let a = p.primaryAudio {
                    log("🔊 Audio Stream #\(a.index): \(a.codecLongName) (\(a.audioCodec?.description ?? a.codecName))", level: .info)
                }
                let localSubTracks = p.subtitles.map { sub -> SubtitleTrack in
                    let name = sub.title ?? (sub.language != nil ? (Locale.current.localizedString(forLanguageCode: sub.language!) ?? sub.language!.uppercased()) : "Track \(sub.index)")
                    return SubtitleTrack(
                        id: "stream_\(sub.index)",
                        name: name,
                        languageCode: sub.language,
                        isAutoGenerated: false,
                        vttURL: nil,
                        streamIndex: sub.index,
                        sourceURL: webURL,
                        isDefault: sub.isDefault
                    )
                }
                SubtitleManager.shared.setAvailableTracks(localSubTracks)
                if let initial = localSubTracks.first(where: { $0.isDefault }) ?? localSubTracks.first {
                    SubtitleManager.shared.selectTrack(initial)
                }
                if !localSubTracks.isEmpty {
                    log("💬 Loaded \(localSubTracks.count) subtitle tracks in online stream.", level: .info)
                }

                // Populate Audio Tracks for online stream
                let onlineAudioTracks = p.audioStreams.map { a -> AudioTrack in
                    let lang = a.language
                    let langDisplay = lang != nil ? (Locale.current.localizedString(forLanguageCode: lang!) ?? lang!.uppercased()) : nil
                    let title = a.title
                    var name = title ?? langDisplay ?? "Track \(a.index)"
                    if let ch = a.channels {
                        let chStr = ch == 1 ? "Mono" : (ch == 2 ? "Stereo" : (ch == 6 ? "5.1 Surround" : (ch == 8 ? "7.1 Surround" : "\(ch) ch")))
                        name += " (\(chStr))"
                    }
                    return AudioTrack(
                        id: "audio_\(a.index)",
                        streamIndex: a.index,
                        name: name,
                        languageCode: lang,
                        codecName: a.codecName,
                        channels: a.channels,
                        channelLayout: a.channelLayout,
                        sampleRate: a.sampleRate,
                        isDefault: a.isDefault
                    )
                }
                AudioManager.shared.setAvailableTracks(onlineAudioTracks)
                if !onlineAudioTracks.isEmpty {
                    log("🔊 Loaded \(onlineAudioTracks.count) audio track(s) in online stream.", level: .info)
                }
            }
        } catch {
            log("⚠️ FFprobe remote note: \(error.localizedDescription). Attempting direct playback heuristics.", level: .warning)
        }

        let strategy = CompatibilityMatrix.evaluate(source: .online(url: webURL, originalInput: originalInput), probe: probe, onlineInfo: nil)
        self.activeStrategy = strategy
        log("💡 Evaluated Direct Strategy: [\(strategy.badgeLabel)] - \(strategy.strategyTitle)", level: .success)

        let selectedAudioIndex = AudioManager.shared.selectedTrack?.streamIndex

        switch strategy {
        case .directNative, .onlineDirect:
            self.activePlayableURL = webURL
            self.state = .ready(strategy)
            log("⚡️ AVPlayer direct native online stream connected.", level: .success)

        case .remuxOnly(let inputURL, _, _):
            state = .preparingStream("Remuxing online container into local stream...")
            log("⚙️ Starting zero-reencode HLS remux pipeline for online stream...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .remuxCopy, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Live online remux stream connected to AVPlayer.", level: .success)
            } catch {
                log("⚠️ Remux pipeline note: \(error.localizedDescription). Falling back to Apple Silicon hardware transcode...", level: .warning)
                do {
                    state = .preparingStream("Transcoding online video via VideoToolbox HW encoder...")
                    let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode, audioStreamIndex: selectedAudioIndex)
                    self.activePlayableURL = streamURL
                    self.state = .ready(.fullTranscode(inputURL: inputURL, streamURL: streamURL, reason: "Hardware transcode fallback."))
                    log("✨ Online hardware transcode stream connected to AVPlayer.", level: .success)
                } catch {
                    log("❌ Transcode failed: \(error.localizedDescription)", level: .error)
                    state = .error("Stream pipeline failed: \(error.localizedDescription)")
                }
            }

        case .audioTranscodeOnly(let inputURL, _, _):
            state = .preparingStream("Transcoding online audio track to AAC...")
            log("⚙️ Starting online video-copy + AAC transcode pipeline...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .audioTranscodeOnly, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Online audio transcode stream connected to AVPlayer.", level: .success)
            } catch {
                log("⚠️ Audio transcode note: \(error.localizedDescription). Falling back to Apple Silicon hardware transcode...", level: .warning)
                do {
                    state = .preparingStream("Transcoding online video via VideoToolbox HW encoder...")
                    let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode, audioStreamIndex: selectedAudioIndex)
                    self.activePlayableURL = streamURL
                    self.state = .ready(.fullTranscode(inputURL: inputURL, streamURL: streamURL, reason: "Hardware transcode fallback."))
                    log("✨ Online hardware transcode stream connected to AVPlayer.", level: .success)
                } catch {
                    log("❌ Transcode failed: \(error.localizedDescription)", level: .error)
                    state = .error("Stream pipeline failed: \(error.localizedDescription)")
                }
            }

        case .fullTranscode(let inputURL, _, _), .onlineTranscode(let inputURL, _, _, _):
            state = .preparingStream("Transcoding online video via VideoToolbox HW encoder...")
            log("⚙️ Starting Apple Silicon VideoToolbox hardware transcode for online stream...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode, audioStreamIndex: selectedAudioIndex)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Online hardware transcode stream connected to AVPlayer.", level: .success)
            } catch {
                log("❌ Transcode failed: \(error.localizedDescription)", level: .error)
                state = .error("Hardware transcode failed: \(error.localizedDescription)")
            }
        }
    }

    /// Switches the active audio track for the current stream in real-time.
    public func switchAudioTrack(to track: AudioTrack) async {
        guard let source = currentSource else { return }
        let currentSec = PlayerController.shared.currentTime
        log("🔊 Switching audio track to '\(track.name)' (Stream #\(track.streamIndex)) at \(PlayerController.shared.formattedCurrentTime)", level: .info)

        switch source {
        case .local(let fileURL):
            do {
                let mode: PipelineMode
                switch activeStrategy {
                case .audioTranscodeOnly:
                    mode = .audioTranscodeOnly
                case .fullTranscode:
                    mode = .fullHardwareTranscode
                default:
                    mode = .remuxCopy
                }
                let streamURL = try await ffmpegPipeline.startSession(
                    inputURL: fileURL,
                    mode: mode,
                    audioStreamIndex: track.streamIndex,
                    seekTime: currentSec
                )
                self.activePlayableURL = streamURL
                log("✨ Audio track switched successfully.", level: .success)
            } catch {
                log("❌ Failed to switch audio track: \(error.localizedDescription)", level: .error)
            }
        case .online(let webURL, _):
            do {
                let streamURL = try await ffmpegPipeline.startSession(
                    inputURL: webURL,
                    mode: .remuxCopy,
                    audioStreamIndex: track.streamIndex,
                    seekTime: currentSec
                )
                self.activePlayableURL = streamURL
                log("✨ Online audio track switched successfully.", level: .success)
            } catch {
                log("❌ Failed to switch online audio track: \(error.localizedDescription)", level: .error)
            }
        }
    }

    public var isPipelineActive: Bool {
        ffmpegPipeline.isRunning
    }

    /// Fast-forwards / seeks an active streaming or transcoding session directly to an unloaded timestamp.
    public func seekPipeline(to targetSeconds: Double) async {
        guard let source = currentSource, ffmpegPipeline.isRunning else { return }
        log("⏩ Seeking stream pipeline to \(formatSeconds(targetSeconds))...", level: .info)

        let selectedAudioIndex = AudioManager.shared.selectedTrack?.streamIndex
        let knownD = self.knownDuration

        switch source {
        case .local(let fileURL):
            do {
                let mode: PipelineMode
                switch activeStrategy {
                case .audioTranscodeOnly:
                    mode = .audioTranscodeOnly
                case .fullTranscode:
                    mode = .fullHardwareTranscode
                default:
                    mode = .remuxCopy
                }
                let streamURL = try await ffmpegPipeline.startSession(
                    inputURL: fileURL,
                    mode: mode,
                    audioStreamIndex: selectedAudioIndex,
                    seekTime: targetSeconds
                )
                self.activePlayableURL = streamURL
                PlayerController.shared.loadStreamFromSeek(url: streamURL, expectedDuration: knownD, timeOffset: targetSeconds)
                log("✨ Pipeline fast-forwarded to \(formatSeconds(targetSeconds)).", level: .success)
            } catch {
                log("❌ Seek pipeline failed: \(error.localizedDescription)", level: .error)
            }

        case .online(let webURL, _):
            do {
                if let strategy = activeStrategy, case .onlineTranscode = strategy {
                    // Video platform stream (YouTube, Vimeo, etc.)
                    let streamURL = try await ffmpegPipeline.startOnlinePipedSession(webURL: webURL, seekTime: targetSeconds)
                    self.activePlayableURL = streamURL
                    PlayerController.shared.loadStreamFromSeek(url: streamURL, expectedDuration: knownD, timeOffset: targetSeconds)
                    log("✨ Online stream fast-forwarded to \(formatSeconds(targetSeconds)).", level: .success)
                } else {
                    let mode: PipelineMode
                    switch activeStrategy {
                    case .audioTranscodeOnly:
                        mode = .audioTranscodeOnly
                    case .fullTranscode:
                        mode = .fullHardwareTranscode
                    default:
                        mode = .remuxCopy
                    }
                    let streamURL = try await ffmpegPipeline.startSession(
                        inputURL: webURL,
                        mode: mode,
                        audioStreamIndex: selectedAudioIndex,
                        seekTime: targetSeconds
                    )
                    self.activePlayableURL = streamURL
                    PlayerController.shared.loadStreamFromSeek(url: streamURL, expectedDuration: knownD, timeOffset: targetSeconds)
                    log("✨ Stream fast-forwarded to \(formatSeconds(targetSeconds)).", level: .success)
                }
            } catch {
                log("❌ Online seek failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    /// Gracefully recovers from unexpected AVPlayer playback failures (e.g. HLS CDN 404) by falling back to piped streaming.
    public func handlePlaybackFailure(error: String) {
        Task { @MainActor in
            guard let source = self.currentSource, case .online(let webURL, _) = source,
                  self.extractedOnlineInfo?.hlsMasterPlaylist != nil else { return }

            self.log("⚠️ Native HLS stream reported playback error: \(error). Recovering via online piped stream bridge...", level: .warning)
            self.extractedOnlineInfo?.hlsMasterPlaylist = nil
            self.state = .preparingStream("Switching to compatible piped stream...")

            do {
                let streamURL = try await self.ffmpegPipeline.startOnlinePipedSession(webURL: webURL)
                self.activePlayableURL = streamURL
                let fallbackStrategy: PlaybackStrategy = .onlineTranscode(
                    streamURL: streamURL,
                    originalURL: webURL,
                    title: self.extractedOnlineInfo?.title ?? "Online Stream",
                    reason: "Dynamic fallback compatibility bridge"
                )
                self.activeStrategy = fallbackStrategy
                self.state = .ready(fallbackStrategy)
                self.log("✨ Seamlessly recovered playback via online piped bridge.", level: .success)
            } catch {
                self.state = .error("Stream playback failed: \(error)")
                self.log("❌ Stream recovery failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = (total % 3600) / 60
        let s = total % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    public func stop() {
        loadTask?.cancel()
        ffmpegPipeline.stop()
        pipelineStats = nil
        activePlayableURL = nil
        activeStrategy = nil
        SubtitleManager.shared.reset()
        AudioManager.shared.reset()
        NowPlayingManager.shared.clear()
        state = .idle
        log("Playback stopped and pipelines dismantled.", level: .info)
    }
}
