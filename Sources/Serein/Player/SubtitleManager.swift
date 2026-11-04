import Foundation
import Combine

/// Central manager for loading, parsing, and rendering video captions and subtitles.
@MainActor
public final class SubtitleManager: ObservableObject {
    public static let shared = SubtitleManager()

    @Published public private(set) var availableTracks: [SubtitleTrack] = []
    @Published public private(set) var selectedTrack: SubtitleTrack? = nil
    @Published public private(set) var currentCueText: String? = nil
    @Published public private(set) var currentCuePosition: SubtitlePosition = .bottom

    private var activeCues: [SubtitleCue] = []
    private var cuesCache: [String: [SubtitleCue]] = [:]
    private var downloadTask: Task<Void, Never>?

    private init() {}

    /// Sets the list of available subtitle tracks (from local probe or stream metadata).
    public func setAvailableTracks(_ tracks: [SubtitleTrack]) {
        downloadTask?.cancel()
        self.availableTracks = tracks
        self.selectedTrack = nil
        self.currentCueText = nil
        self.activeCues.removeAll()
        self.cuesCache.removeAll()
    }

    /// Selects a subtitle track, or passes nil to turn subtitles off.
    public func selectTrack(_ track: SubtitleTrack?) {
        downloadTask?.cancel()
        self.selectedTrack = track
        self.currentCueText = nil
        self.activeCues.removeAll()

        guard let track = track else { return }

        // Check memory cache first
        if let cached = cuesCache[track.id], !cached.isEmpty {
            self.activeCues = cached
            self.updateTime(PlayerController.shared.currentTime)
            return
        }

        // Case 1: Track has a direct WebVTT URL (e.g. online VTT)
        if let vttURL = track.vttURL {
            downloadTask = Task { [weak self] in
                do {
                    var vttString: String? = nil
                    if vttURL.isFileURL {
                        vttString = try? String(contentsOf: vttURL, encoding: .utf8)
                    } else {
                        var req = URLRequest(url: vttURL)
                        req.timeoutInterval = 12
                        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard !Task.isCancelled else { return }

                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            vttString = String(data: data, encoding: .utf8)
                        }
                    }

                    if let text = vttString {
                        let parsed = SubtitleParser.parseWebVTT(text)
                        await MainActor.run {
                            self?.cuesCache[track.id] = parsed
                            self?.activeCues = parsed
                            self?.updateTime(PlayerController.shared.currentTime)
                        }
                    }
                } catch {
                    print("[SubtitleManager] Error loading VTT subtitle: \(error.localizedDescription)")
                }
            }
            return
        }

        // Case 2: Track is embedded inside media container (e.g. mov_text, srt, ass in MOV/MP4/MKV)
        if let sourceURL = track.sourceURL, let streamIndex = track.streamIndex {
            downloadTask = Task { [weak self] in
                guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else {
                    print("[SubtitleManager] FFmpeg binary not found for subtitle extraction.")
                    return
                }

                let tempVtt = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("serein_sub_\(UUID().uuidString).vtt")
                var args: [String] = ["-nostdin", "-y"]

                if !sourceURL.isFileURL {
                    args.append(contentsOf: [
                        "-user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                        "-reconnect", "1",
                        "-reconnect_streamed", "1",
                        "-reconnect_delay_max", "5"
                    ])
                }

                args.append(contentsOf: [
                    "-i", sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString,
                    "-map", "0:\(streamIndex)",
                    "-c:s", "webvtt",
                    "-f", "webvtt",
                    tempVtt.path
                ])

                do {
                    _ = try await ProcessRunner.run(executablePath: ffmpegPath, arguments: args, timeout: 30)
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: tempVtt)
                        return
                    }

                    if FileManager.default.fileExists(atPath: tempVtt.path),
                       let content = try? String(contentsOf: tempVtt, encoding: .utf8) {
                        try? FileManager.default.removeItem(at: tempVtt)
                        let parsed = SubtitleParser.parseWebVTT(content)
                        await MainActor.run {
                            self?.cuesCache[track.id] = parsed
                            self?.activeCues = parsed
                            self?.updateTime(PlayerController.shared.currentTime)
                        }
                    }
                } catch {
                    print("[SubtitleManager] FFmpeg subtitle extraction failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Updates active subtitle text according to current playback timestamp.
    public func updateTime(_ currentTime: Double) {
        guard !activeCues.isEmpty else {
            if currentCueText != nil {
                currentCueText = nil
                currentCuePosition = .bottom
            }
            return
        }

        // Fast search for matching cue
        let matching = activeCues.first { cue in
            currentTime >= cue.startTime && currentTime <= cue.endTime
        }

        let newText = matching?.text
        let newPos = matching?.position ?? .bottom
        if currentCueText != newText || currentCuePosition != newPos {
            currentCueText = newText
            currentCuePosition = newPos
        }
    }

    /// Clears all tracks and cues when playback resets.
    public func reset() {
        downloadTask?.cancel()
        availableTracks.removeAll()
        selectedTrack = nil
        currentCueText = nil
        currentCuePosition = .bottom
        activeCues.removeAll()
        cuesCache.removeAll()
    }
}
