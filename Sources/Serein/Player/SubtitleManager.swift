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
    private var nativeLegibleText: String? = nil
    private var nativeLegiblePosition: SubtitlePosition = .bottom
    private var downloadTask: Task<Void, Never>?
    private var activeFFmpegProcess: Process?

    private init() {}

    /// Sets the list of available subtitle tracks (from local probe or stream metadata).
    public func setAvailableTracks(_ tracks: [SubtitleTrack]) {
        cancelActiveExtraction()
        self.availableTracks = tracks
        self.selectedTrack = nil
        self.currentCueText = nil
        self.nativeLegibleText = nil
        self.activeCues.removeAll()
        self.cuesCache.removeAll()
    }

    /// Selects a subtitle track, or passes nil to turn subtitles off.
    public func selectTrack(_ track: SubtitleTrack?) {
        cancelActiveExtraction()
        self.selectedTrack = track
        self.currentCueText = nil
        self.nativeLegibleText = nil
        self.activeCues.removeAll()

        PlayerController.shared.syncNativeSubtitleSelection(for: track)

        guard let track = track else { return }

        // Check memory cache first
        if let cached = cuesCache[track.id], !cached.isEmpty {
            self.activeCues = cached
            self.updateTime(PlayerController.shared.currentTime)
            if let sourceURL = track.sourceURL, !sourceURL.isFileURL {
                // Continue progressive extraction from current playback time if needed
                let cur = PlayerController.shared.currentTime
                if !isTimeCoveredByCues(cur, in: cached) {
                    startEmbeddedExtraction(for: track, seekOffset: max(0, cur - 5))
                }
            }
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
                        req.timeoutInterval = 15
                        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard !Task.isCancelled else { return }

                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            vttString = String(data: data, encoding: .utf8)
                        }
                    }

                    if let text = vttString {
                        let parsed = SubtitleParser.parse(text)
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
        if track.sourceURL != nil, track.streamIndex != nil {
            let startOffset = max(0, PlayerController.shared.currentTime - 5)
            startEmbeddedExtraction(for: track, seekOffset: startOffset)
        }
    }

    /// Receives live subtitle text extracted natively by AVPlayerItemLegibleOutput (e.g. mov_text/tx3g in PikPak/MP4 streams).
    public func updateNativeLegibleText(_ rawText: String?) {
        guard selectedTrack != nil else {
            nativeLegibleText = nil
            return
        }
        if let raw = rawText, !raw.isEmpty {
            let (pos, cleaned) = SubtitleParser.cleanSubtitleFormattingAndExtractPosition(raw, fallbackPosition: .bottom)
            nativeLegibleText = cleaned.isEmpty ? nil : cleaned
            nativeLegiblePosition = pos
        } else {
            nativeLegibleText = nil
            nativeLegiblePosition = .bottom
        }
        refreshDisplayedCue(for: PlayerController.shared.currentTime)
    }

    /// Notifies SubtitleManager when the user scrubs/seeks to a new timestamp.
    public func handleUserSeek(to targetSeconds: Double) {
        nativeLegibleText = nil
        refreshDisplayedCue(for: targetSeconds)

        guard let track = selectedTrack,
              let sourceURL = track.sourceURL,
              !sourceURL.isFileURL,
              track.streamIndex != nil else {
            return
        }

        if !isTimeCoveredByCues(targetSeconds, in: activeCues) {
            cancelActiveExtraction()
            startEmbeddedExtraction(for: track, seekOffset: max(0, targetSeconds - 5))
        }
    }

    private func isTimeCoveredByCues(_ time: Double, in cues: [SubtitleCue]) -> Bool {
        guard let first = cues.first, let last = cues.last else { return false }
        return time >= max(0, first.startTime - 30) && time <= last.endTime + 15
    }

    private func cancelActiveExtraction() {
        downloadTask?.cancel()
        downloadTask = nil
        if let proc = activeFFmpegProcess, proc.isRunning {
            proc.terminate()
        }
        activeFFmpegProcess = nil
    }

    private func startEmbeddedExtraction(for track: SubtitleTrack, seekOffset: Double) {
        guard let sourceURL = track.sourceURL, let streamIndex = track.streamIndex else { return }

        if sourceURL.isFileURL {
            // Fast local file extraction
            downloadTask = Task { [weak self] in
                guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else { return }
                let tempSub = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("serein_sub_\(UUID().uuidString).ass")
                let baseArgs: [String] = [
                    "-nostdin", "-y",
                    "-discard:v", "all",
                    "-discard:a", "all",
                    "-i", sourceURL.path,
                    "-vn", "-an",
                    "-map", "0:\(streamIndex)"
                ]

                let assArgs = baseArgs + ["-c:s", "ass", "-f", "ass", tempSub.path]
                do {
                    var result = try await ProcessRunner.run(executablePath: ffmpegPath, arguments: assArgs, timeout: 45)
                    if !result.isSuccess || !FileManager.default.fileExists(atPath: tempSub.path) {
                        let vttArgs = baseArgs + ["-c:s", "webvtt", "-f", "webvtt", tempSub.path]
                        result = try await ProcessRunner.run(executablePath: ffmpegPath, arguments: vttArgs, timeout: 45)
                    }
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: tempSub)
                        return
                    }
                    if FileManager.default.fileExists(atPath: tempSub.path),
                       let content = try? String(contentsOf: tempSub, encoding: .utf8) {
                        try? FileManager.default.removeItem(at: tempSub)
                        let parsed = SubtitleParser.parse(content)
                        await MainActor.run {
                            self?.cuesCache[track.id] = parsed
                            self?.activeCues = parsed
                            self?.updateTime(PlayerController.shared.currentTime)
                        }
                    }
                } catch {
                    try? FileManager.default.removeItem(at: tempSub)
                }
            }
        } else {
            // Progressive stdout streaming extraction for remote HTTP streams (PikPak, cloud drives, MKV/MP4 over HTTP)
            downloadTask = Task.detached(priority: .utility) { [weak self] in
                guard let self = self, let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else { return }

                var args: [String] = [
                    "-nostdin", "-y",
                    "-loglevel", "error",
                    "-user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                    "-reconnect", "1",
                    "-reconnect_streamed", "1",
                    "-reconnect_delay_max", "5"
                ]

                if seekOffset > 5.0 {
                    args.append(contentsOf: ["-ss", String(format: "%.1f", seekOffset)])
                }

                args.append(contentsOf: [
                    "-discard:v", "all",
                    "-discard:a", "all",
                    "-i", sourceURL.absoluteString,
                    "-vn", "-an",
                    "-copyts",
                    "-map", "0:\(streamIndex)",
                    "-c:s", "ass",
                    "-f", "ass",
                    "-flush_packets", "1",
                    "pipe:1"
                ])

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                process.arguments = args

                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = FileHandle.nullDevice

                await MainActor.run {
                    self.activeFFmpegProcess = process
                }

                do {
                    try process.run()
                } catch {
                    return
                }

                let handle = outPipe.fileHandleForReading
                var accumulatedBuffer = Data()
                var lastParseTime = Date.distantPast

                while !Task.isCancelled {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        break
                    }
                    accumulatedBuffer.append(chunk)

                    let now = Date()
                    if now.timeIntervalSince(lastParseTime) >= 0.35,
                       let text = String(data: accumulatedBuffer, encoding: .utf8),
                       text.contains("Dialogue:") {
                        lastParseTime = now
                        let newlyParsed = SubtitleParser.parse(text)
                        if !newlyParsed.isEmpty {
                            await MainActor.run {
                                self.mergeProgressiveCues(newlyParsed, forTrackID: track.id)
                            }
                        }
                    }
                }

                if process.isRunning {
                    process.terminate()
                }

                if !Task.isCancelled,
                   let finalText = String(data: accumulatedBuffer, encoding: .utf8),
                   !finalText.isEmpty {
                    let finalParsed = SubtitleParser.parse(finalText)
                    if !finalParsed.isEmpty {
                        await MainActor.run {
                            self.mergeProgressiveCues(finalParsed, forTrackID: track.id)
                        }
                    }
                }
            }
        }
    }

    private func mergeProgressiveCues(_ newCues: [SubtitleCue], forTrackID trackID: String) {
        guard selectedTrack?.id == trackID else { return }
        var combined = cuesCache[trackID] ?? []
        for cue in newCues {
            let exists = combined.contains {
                abs($0.startTime - cue.startTime) < 0.05 &&
                abs($0.endTime - cue.endTime) < 0.05 &&
                $0.text == cue.text
            }
            if !exists {
                combined.append(cue)
            }
        }
        combined.sort { $0.startTime < $1.startTime }
        cuesCache[trackID] = combined
        activeCues = combined
        refreshDisplayedCue(for: PlayerController.shared.currentTime)
    }

    /// Updates active subtitle text according to current playback timestamp.
    public func updateTime(_ currentTime: Double) {
        refreshDisplayedCue(for: currentTime)
    }

    private func refreshDisplayedCue(for currentTime: Double) {
        guard selectedTrack != nil else {
            if currentCueText != nil {
                currentCueText = nil
                currentCuePosition = .bottom
            }
            return
        }

        if let matching = activeCues.first(where: { currentTime >= $0.startTime && currentTime <= $0.endTime }) {
            if currentCueText != matching.text || currentCuePosition != matching.position {
                currentCueText = matching.text
                currentCuePosition = matching.position
            }
            return
        }

        if let nativeText = nativeLegibleText, !nativeText.isEmpty {
            if currentCueText != nativeText || currentCuePosition != nativeLegiblePosition {
                currentCueText = nativeText
                currentCuePosition = nativeLegiblePosition
            }
            return
        }

        if currentCueText != nil {
            currentCueText = nil
            currentCuePosition = .bottom
        }
    }

    /// Clears all tracks and cues when playback resets.
    public func reset() {
        cancelActiveExtraction()
        availableTracks.removeAll()
        selectedTrack = nil
        currentCueText = nil
        currentCuePosition = .bottom
        nativeLegibleText = nil
        nativeLegiblePosition = .bottom
        activeCues.removeAll()
        cuesCache.removeAll()
    }
}
