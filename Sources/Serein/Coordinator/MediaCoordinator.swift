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
            }
        } catch {
            log("⚠️ FFprobe inspection warning: \(error.localizedDescription). Proceeding with extension heuristics.", level: .warning)
        }

        // Determine Strategy
        let strategy = CompatibilityMatrix.evaluate(source: .local(fileURL), probe: probe, onlineInfo: nil)
        self.activeStrategy = strategy
        log("💡 Evaluated Strategy: [\(strategy.badgeLabel)] - \(strategy.strategyTitle)", level: .success)
        log("ℹ️ Rationale: \(strategy.explanation)", level: .info)

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
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .remuxCopy)
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
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .audioTranscodeOnly)
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
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode)
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

        // Cloud storage and CDN direct download patterns
        let knownDirectHosts = ["drive.google.com", "dropbox.com", "115.com", "alist", "mediafire.com", "mega.nz", "box.com", "onedrive.live.com"]
        if knownDirectHosts.contains(where: { host.contains($0) }) {
            return true
        }

        // Direct media extensions or download paths
        let mediaExts = ["mp4", "mkv", "mov", "webm", "m3u8", "ts", "avi", "flv", "m4v"]
        if mediaExts.contains(url.pathExtension.lowercased()) {
            return true
        }

        if path.contains("/download") || path.contains("/file/") || path.contains("/stream") || path.contains("/raw") || query.contains("download") {
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

                if extracted.isDirectlyPlayable && !extracted.needsPipedStream {
                    self.activePlayableURL = extracted.selectedStreamURL
                    self.state = .ready(strategy)
                    log("⚡️ Streaming direct progressive/HLS URL in AVPlayer.", level: .success)
                } else {
                    state = .preparingStream("Connecting online stream via yt-dlp & FFmpeg bridge...")
                    log("⚙️ Routing stream through yt-dlp ➔ FFmpeg pipeline...", level: .info)
                    let streamURL = try await ffmpegPipeline.startOnlinePipedSession(webURL: webURL)
                    self.activePlayableURL = streamURL
                    self.state = .ready(strategy)
                    log("✨ Online stream connected to AVPlayer via local bridge.", level: .success)
                }
                return
            } catch {
                if case .ytDlpNotFound = (error as? YtDlpError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                if case .ffmpegNotFound = (error as? FFmpegPipelineError) {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                log("⚠️ yt-dlp note: \(error.localizedDescription). Proceeding with direct stream fallback.", level: .warning)
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
            }
        } catch {
            log("⚠️ FFprobe remote note: \(error.localizedDescription). Attempting direct playback heuristics.", level: .warning)
        }

        let strategy = CompatibilityMatrix.evaluate(source: .online(url: webURL, originalInput: originalInput), probe: probe, onlineInfo: nil)
        self.activeStrategy = strategy
        log("💡 Evaluated Direct Strategy: [\(strategy.badgeLabel)] - \(strategy.strategyTitle)", level: .success)

        switch strategy {
        case .directNative, .onlineDirect:
            self.activePlayableURL = webURL
            self.state = .ready(strategy)
            log("⚡️ AVPlayer direct native online stream connected.", level: .success)

        case .remuxOnly(let inputURL, _, _):
            state = .preparingStream("Remuxing online container into local stream...")
            log("⚙️ Starting zero-reencode HLS remux pipeline for online stream...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .remuxCopy)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Live online remux stream connected to AVPlayer.", level: .success)
            } catch {
                log("⚠️ Remux pipeline failed: \(error.localizedDescription). Falling back to direct AVPlayer stream.", level: .warning)
                self.activePlayableURL = webURL
                self.state = .ready(.directNative(playableURL: webURL, reason: "Direct progressive stream fallback."))
            }

        case .audioTranscodeOnly(let inputURL, _, _):
            state = .preparingStream("Transcoding online audio track to AAC...")
            log("⚙️ Starting online video-copy + AAC transcode pipeline...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .audioTranscodeOnly)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Online audio transcode stream connected to AVPlayer.", level: .success)
            } catch {
                log("⚠️ Audio transcode failed: \(error.localizedDescription). Falling back to direct stream.", level: .warning)
                self.activePlayableURL = webURL
                self.state = .ready(.directNative(playableURL: webURL, reason: "Direct progressive stream fallback."))
            }

        case .fullTranscode(let inputURL, _, _), .onlineTranscode(let inputURL, _, _, _):
            state = .preparingStream("Transcoding online video via VideoToolbox HW encoder...")
            log("⚙️ Starting Apple Silicon VideoToolbox hardware transcode for online stream...", level: .info)
            do {
                let streamURL = try await ffmpegPipeline.startSession(inputURL: inputURL, mode: .fullHardwareTranscode)
                self.activePlayableURL = streamURL
                self.state = .ready(strategy)
                log("✨ Online hardware transcode stream connected to AVPlayer.", level: .success)
            } catch {
                log("⚠️ Transcode failed: \(error.localizedDescription). Falling back to direct stream.", level: .warning)
                self.activePlayableURL = webURL
                self.state = .ready(.directNative(playableURL: webURL, reason: "Direct progressive stream fallback."))
            }
        }
    }

    public func stop() {
        loadTask?.cancel()
        ffmpegPipeline.stop()
        pipelineStats = nil
        activePlayableURL = nil
        activeStrategy = nil
        SubtitleManager.shared.reset()
        state = .idle
        log("Playback stopped and pipelines dismantled.", level: .info)
    }
}
