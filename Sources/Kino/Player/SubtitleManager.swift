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

    private static let placementDefaultsKey = "KinoSubtitlePlacement"
    private static let legacyPlacementDefaultsKey = "SereinSubtitlePlacement"

    /// Subtitle layout positioning: .letterbox (sits according to display height in black bar)
    /// vs .mediaFrame (sits according to media height inside the video picture).
    @Published public private(set) var placement: SubtitlePlacement = {
        if let saved = UserDefaults.standard.string(forKey: placementDefaultsKey) ?? UserDefaults.standard.string(forKey: legacyPlacementDefaultsKey),
           let p = SubtitlePlacement(rawValue: saved) {
            return p
        }
        return .letterbox
    }()

    private var activeCues: [SubtitleCue] = []
    private var cuesCache: [String: [SubtitleCue]] = [:]
    private var downloadedRangesByTrack: [String: [ClosedRange<Double>]] = [:]
    private var nativeLegibleText: String? = nil
    private var nativeLegiblePosition: SubtitlePosition = .bottom
    private var downloadTask: Task<Void, Never>?
    private var activeFFmpegProcess: Process?

    private init() {}

    /// Sets the subtitle placement mode (Display Height vs Media Height) and persists user preference.
    public func setPlacement(_ newPlacement: SubtitlePlacement) {
        guard placement != newPlacement else { return }
        placement = newPlacement
        UserDefaults.standard.set(newPlacement.rawValue, forKey: Self.placementDefaultsKey)
        let name = (newPlacement == .letterbox) ? "Display Height (In Letterbox)" : "Media Height (Inside Video)"
        PlayerController.shared.showHUD(message: "Subtitles: \(name)", iconName: "captions.bubble")
    }

    /// Toggles subtitle placement between Display Height and Media Height.
    public func togglePlacement() {
        let next: SubtitlePlacement = (placement == .letterbox) ? .mediaFrame : .letterbox
        setPlacement(next)
    }

    /// Sets the list of available subtitle tracks (from local probe, sidecars, or stream metadata).
    public func setAvailableTracks(_ tracks: [SubtitleTrack]) {
        cancelActiveExtraction()
        self.availableTracks = tracks
        self.selectedTrack = nil
        self.currentCueText = nil
        self.nativeLegibleText = nil
        self.activeCues.removeAll()
        self.cuesCache.removeAll()
        self.downloadedRangesByTrack.removeAll()
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
                // Check if current playback time is covered by already demuxed segments
                let cur = PlayerController.shared.currentTime
                if !isTimeCoveredByRanges(cur, forTrackID: track.id) {
                    startEmbeddedExtraction(for: track, seekOffset: max(0, cur - 5))
                }
            }
            return
        }

        // Case 1: Track has a direct WebVTT / SRT URL (e.g. online VTT or local sidecar)
        if let vttURL = track.vttURL {
            downloadTask = Task { [weak self] in
                do {
                    var vttString: String? = nil
                    if vttURL.isFileURL {
                        if let data = try? Data(contentsOf: vttURL) {
                            vttString = Self.decodeSubtitleData(data)
                        }
                    } else {
                        var req = URLRequest(url: vttURL)
                        req.timeoutInterval = 15
                        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard !Task.isCancelled else { return }

                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            vttString = Self.decodeSubtitleData(data)
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

    /// Loads an external subtitle or lyric file (.srt, .vtt, .ass, .ssa, .sub, .lrc) into the session.
    public func loadExternalSubtitle(from url: URL) {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let text = Self.decodeSubtitleData(data) else {
            PlayerController.shared.showHUD(message: "Failed to read subtitle file", iconName: "exclamationmark.triangle")
            return
        }

        let parsed = SubtitleParser.parse(text)
        guard !parsed.isEmpty else {
            PlayerController.shared.showHUD(message: "No cues found in subtitle file", iconName: "exclamationmark.triangle")
            return
        }

        let ext = url.pathExtension.uppercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let trackID = "external_\(UUID().uuidString)"
        let newTrack = SubtitleTrack(
            id: trackID,
            name: "\(baseName) (\(ext))",
            languageCode: nil,
            isAutoGenerated: false,
            vttURL: url,
            streamIndex: nil,
            sourceURL: url,
            isDefault: true
        )

        // Prepend so external track is immediately visible at the top
        availableTracks.insert(newTrack, at: 0)
        cuesCache[newTrack.id] = parsed
        activeCues = parsed
        selectedTrack = newTrack
        updateTime(PlayerController.shared.currentTime)

        PlayerController.shared.showHUD(
            message: "Loaded: \(url.lastPathComponent)",
            iconName: "captions.bubble.fill"
        )
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

        if !isTimeCoveredByRanges(targetSeconds, forTrackID: track.id) {
            cancelActiveExtraction()
            startEmbeddedExtraction(for: track, seekOffset: max(0, targetSeconds - 5))
        }
    }

    private func isTimeCoveredByRanges(_ time: Double, forTrackID trackID: String) -> Bool {
        guard let ranges = downloadedRangesByTrack[trackID], !ranges.isEmpty else { return false }
        return ranges.contains { $0.contains(time) }
    }

    private func recordDownloadedRange(_ newRange: ClosedRange<Double>, forTrackID trackID: String) {
        var ranges = downloadedRangesByTrack[trackID] ?? []
        ranges.append(newRange)
        ranges.sort { $0.lowerBound < $1.lowerBound }

        var merged: [ClosedRange<Double>] = []
        for r in ranges {
            if let last = merged.last {
                if r.lowerBound <= last.upperBound + 5.0 {
                    merged[merged.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
                } else {
                    merged.append(r)
                }
            } else {
                merged.append(r)
            }
        }
        downloadedRangesByTrack[trackID] = merged
    }

    private func cancelActiveExtraction() {
        downloadTask?.cancel()
        downloadTask = nil
        if let proc = activeFFmpegProcess, proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGKILL)
        }
        activeFFmpegProcess = nil
    }

    private func startEmbeddedExtraction(for track: SubtitleTrack, seekOffset: Double) {
        guard let sourceURL = track.sourceURL, let streamIndex = track.streamIndex else { return }

        if sourceURL.isFileURL {
            // Fast local file extraction
            downloadTask = Task { [weak self] in
                guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else { return }
                let tempSub = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kino_sub_\(UUID().uuidString).ass")
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
                       let data = try? Data(contentsOf: tempSub),
                       let content = Self.decodeSubtitleData(data) {
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
                    if now.timeIntervalSince(lastParseTime) >= 0.25 {
                        let text = String(decoding: accumulatedBuffer, as: UTF8.self)
                        if text.contains("Dialogue:") {
                            lastParseTime = now
                            let newlyParsed = SubtitleParser.parse(text)
                            if !newlyParsed.isEmpty {
                                await MainActor.run {
                                    self.mergeProgressiveCues(newlyParsed, forTrackID: track.id, chunkOffset: seekOffset)
                                }
                            }
                        }
                    }
                }

                if process.isRunning {
                    process.terminate()
                }

                if !Task.isCancelled {
                    let finalText = String(decoding: accumulatedBuffer, as: UTF8.self)
                    if !finalText.isEmpty {
                        let finalParsed = SubtitleParser.parse(finalText)
                        if !finalParsed.isEmpty {
                            await MainActor.run {
                                self.mergeProgressiveCues(finalParsed, forTrackID: track.id, chunkOffset: seekOffset)
                            }
                        }
                    }
                }
            }
        }
    }

    private func mergeProgressiveCues(_ newCues: [SubtitleCue], forTrackID trackID: String, chunkOffset: Double) {
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

        if let lastCue = newCues.last {
            let rangeStart = chunkOffset
            let rangeEnd = max(chunkOffset + 30.0, lastCue.endTime + 5.0)
            recordDownloadedRange(rangeStart...rangeEnd, forTrackID: trackID)
        }

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

        // Match the latest active cue, allowing a tiny 50ms tolerance bridge to eliminate micro-gaps and tick jitter
        if let matching = activeCues.last(where: { currentTime >= ($0.startTime - 0.05) && currentTime <= ($0.endTime + 0.05) }) {
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

    /// Multi-encoding data decoder supporting UTF-8, UTF-16, GB18030/GBK, CP1252, and UTF-8 with BOM.
    public static func decodeSubtitleData(_ data: Data) -> String? {
        if data.isEmpty { return nil }

        // 1. Check for BOMs
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }

        // 2. Strict UTF-8
        if let str = String(data: data, encoding: .utf8) {
            return str
        }

        // 3. UTF-16 without BOM heuristic
        if let str = String(data: data, encoding: .utf16LittleEndian), !str.contains("\0") {
            return str
        }

        // 4. GB18030 / Chinese encodings
        let gbEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let str = String(data: data, encoding: String.Encoding(rawValue: gbEncoding)) {
            return str
        }

        // 5. Windows CP1252
        if let str = String(data: data, encoding: .windowsCP1252) {
            return str
        }

        // 6. Lossy UTF-8 fallback
        return String(decoding: data, as: UTF8.self)
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
        downloadedRangesByTrack.removeAll()
    }
}
