import Foundation

public struct PipelineStats: Sendable {
    public let fps: Double
    public let speedFactor: String
    public let currentTime: String
    public let bitrate: String
    public let isReadyForPlayback: Bool
}

public enum PipelineMode: Sendable {
    case remuxCopy
    case audioTranscodeOnly
    case fullHardwareTranscode
}

public enum FFmpegPipelineError: LocalizedError, Sendable {
    case ffmpegNotFound
    case sessionDirectoryCreationFailed
    case pipelineLaunchFailed(String)
    case timedOutWaitingForPlaylist

    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg was not found. Use Media Engines & Codecs (⌘,) to install automatically."
        case .sessionDirectoryCreationFailed:
            return "Could not create temporary session directory for streaming."
        case .pipelineLaunchFailed(let msg):
            return "Failed to launch FFmpeg pipeline: \(msg)"
        case .timedOutWaitingForPlaylist:
            return "Timed out waiting for initial HLS stream segments to be produced."
        }
    }
}

/// Manages active FFmpeg stream copy, remuxing, or transcoding pipelines.
public final class FFmpegPipeline: @unchecked Sendable {
    private var activeProcess: Process?
    private var activeYtDlpProcess: Process?
    private var sessionDir: URL?
    private let streamingServer = LocalStreamingServer()
    private let syncQueue = DispatchQueue(label: "kino.pipeline.sync")

    public var onStatsUpdated: (@Sendable (PipelineStats) -> Void)?
    public var onLogLine: (@Sendable (String) -> Void)?

    public init() {}

    public var isRunning: Bool {
        syncQueue.sync { activeProcess?.isRunning ?? false }
    }

    public var activeSessionDirectory: URL? {
        sessionDir
    }

    /// Prepares and starts the FFmpeg streaming session, returning the local playback URL.
    public func startSession(inputURL: URL, mode: PipelineMode, audioStreamIndex: Int? = nil, seekTime: Double? = nil) async throws -> URL {
        stop()

        guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else {
            throw FFmpegPipelineError.ffmpegNotFound
        }

        // Create isolated session directory in /tmp
        let sessionID = UUID().uuidString.prefix(8)
        let tempDir = URL(fileURLWithPath: "/tmp").appendingPathComponent("kino_stream_\(sessionID)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw FFmpegPipelineError.sessionDirectoryCreationFailed
        }
        self.sessionDir = tempDir

        // Attempt starting local HTTP server (falls back seamlessly to native file:// HLS)
        _ = try? streamingServer.start(serving: tempDir)
        let playlistFile = tempDir.appendingPathComponent("playlist.m3u8")
        let segmentPattern = tempDir.appendingPathComponent("segment_%03d.ts").path

        // Build FFmpeg arguments based on requested mode
        var args: [String] = [
            "-nostdin",
            "-y"
        ]

        if let sTime = seekTime, sTime > 0.5 {
            args.append(contentsOf: [
                "-ss", String(format: "%.2f", sTime)
            ])
        }

        if !inputURL.isFileURL {
            args.append(contentsOf: [
                "-user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                "-reconnect", "1",
                "-reconnect_streamed", "1",
                "-reconnect_delay_max", "5",
                "-analyzeduration", "10000000",
                "-probesize", "10000000"
            ])
        }

        args.append(contentsOf: [
            "-i", inputURL.isFileURL ? inputURL.path : inputURL.absoluteString
        ])

        let audioMap = (audioStreamIndex != nil) ? "0:\(audioStreamIndex!)" : "0:a:0?"

        switch mode {
        case .remuxCopy:
            // Zero video re-encoding: stream copy video, preserve multichannel audio in studio-grade high-fidelity AAC
            args.append(contentsOf: [
                "-map", "0:v:0?",
                "-map", audioMap,
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "640k",
                "-ar", "48000"
            ])
        case .audioTranscodeOnly:
            // Copy native video stream, transcode audio to studio-grade high-fidelity AAC preserving multichannel audio
            args.append(contentsOf: [
                "-map", "0:v:0?",
                "-map", audioMap,
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "640k",
                "-ar", "48000"
            ])
        case .fullHardwareTranscode:
            // Hardware accelerated Apple Silicon VideoToolbox encoding.
            // Preserves studio-grade high-fidelity audio up to multichannel surround.
            args.append(contentsOf: [
                "-map", "0:v:0?",
                "-map", audioMap,
                "-c:v", "h264_videotoolbox",
                "-pix_fmt", "yuv420p",
                "-b:v", "6000k",
                "-c:a", "aac",
                "-b:a", "640k",
                "-ar", "48000"
            ])
        }

        // HLS segmentation parameters for fast startup
        args.append(contentsOf: [
            "-f", "hls",
            "-hls_time", "2",
            "-hls_list_size", "0"
        ])

        args.append(contentsOf: [
            "-hls_segment_filename", segmentPattern,
            playlistFile.path
        ])

        onLogLine?("🚀 Launching FFmpeg [\(mode)] pipeline: \(ffmpegPath)")

        let proc = try ProcessRunner.spawnStreaming(
            executablePath: ffmpegPath,
            arguments: args,
            onOutput: { [weak self] line in
                self?.onLogLine?(line)
            },
            onError: { [weak self] line in
                self?.parseProgress(line: line)
                self?.onLogLine?(line)
            }
        )

        syncQueue.sync {
            self.activeProcess = proc
        }

        // Wait until playlist.m3u8 exists and has at least one segment
        let timeoutSec: Double = inputURL.isFileURL ? 8.0 : 22.0
        let ready = await waitForFirstSegment(playlistURL: playlistFile, timeout: timeoutSec)
        guard ready else {
            stop()
            throw FFmpegPipelineError.timedOutWaitingForPlaylist
        }

        let playbackURL = streamingServer.serverURL?.appendingPathComponent("playlist.m3u8") ?? playlistFile
        onLogLine?("✅ Local stream ready at \(playbackURL.absoluteString)")
        return playbackURL
    }

    /// Serves a synthesized multi-variant HLS master playlist through the local HTTP server.
    /// This connects directly to CDN nodes with full line speed, adaptive bitrate, zero CPU transcode overhead, and instant seeking.
    public func startHLSProxySession(masterPlaylist: String) throws -> URL {
        stop()

        let sessionID = UUID().uuidString.prefix(8)
        let tempDir = URL(fileURLWithPath: "/tmp").appendingPathComponent("kino_hls_\(sessionID)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw FFmpegPipelineError.sessionDirectoryCreationFailed
        }
        self.sessionDir = tempDir

        let playlistFile = tempDir.appendingPathComponent("playlist.m3u8")
        try masterPlaylist.write(to: playlistFile, atomically: true, encoding: .utf8)

        let serverBaseURL = try streamingServer.start(serving: tempDir)
        let playbackURL = serverBaseURL.appendingPathComponent("playlist.m3u8")
        onLogLine?("⚡️ Local HLS manifest proxy ready at \(playbackURL.absoluteString)")
        return playbackURL
    }

    /// Pipes yt-dlp stdout directly into ffmpeg stdin to stream online sources without 403 Forbidden errors.
    public func startOnlinePipedSession(webURL: URL, seekTime: Double? = nil) async throws -> URL {
        stop()

        guard let ytPath = ToolLocator.shared.path(for: "yt-dlp") else {
            throw YtDlpError.ytDlpNotFound
        }
        guard let ffmpegPath = ToolLocator.shared.path(for: "ffmpeg") else {
            throw FFmpegPipelineError.ffmpegNotFound
        }

        let sessionID = UUID().uuidString.prefix(8)
        let tempDir = URL(fileURLWithPath: "/tmp").appendingPathComponent("kino_stream_\(sessionID)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw FFmpegPipelineError.sessionDirectoryCreationFailed
        }
        self.sessionDir = tempDir

        _ = try? streamingServer.start(serving: tempDir)
        let playlistFile = tempDir.appendingPathComponent("playlist.m3u8")
        let segmentPattern = tempDir.appendingPathComponent("segment_%03d.ts").path

        var env = ProcessInfo.processInfo.environment
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let kinoBin = appSupport?.appendingPathComponent("Kino/bin").path ?? ""
        let sereinBin = appSupport?.appendingPathComponent("Serein/bin").path ?? ""
        env["PATH"] = "\(kinoBin):\(sereinBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(env["PATH"] ?? "")"

        // yt-dlp extraction process outputting to pipe:
        let ytProc = Process()
        ytProc.executableURL = URL(fileURLWithPath: ytPath)
        var ytArgs = [
            "-o", "-",
            "--ffmpeg-location", ffmpegPath,
            "--format-sort", "lang,quality",
            "-f", "bestvideo[vcodec^=avc]+(bestaudio[format_id!*=dub][format_note!*=dub]/bestaudio[format_id!*=dub]/bestaudio)/bestvideo+(bestaudio[format_id!*=dub]/bestaudio)/best",
            "--merge-output-format", "mkv",
            "--no-playlist",
            "--no-part",
            "--buffer-size", "1M"
        ]

        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/deno") || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/node") {
            ytArgs.append(contentsOf: ["--js-runtimes", "deno:/opt/homebrew/bin/deno,node:/opt/homebrew/bin/node"])
        }

        if let sTime = seekTime, sTime > 0.5 {
            ytArgs.append(contentsOf: ["--download-sections", "*\(Int(sTime))-inf"])
        }

        ytArgs.append(webURL.absoluteString)
        ytProc.arguments = ytArgs
        ytProc.environment = env

        // ffmpeg process receiving from pipe:0
        // Stream copies video (already AVC H.264) and transcodes audio to stereo AAC for immediate startup
        let ffmpegProc = Process()
        ffmpegProc.executableURL = URL(fileURLWithPath: ffmpegPath)
        let ffmpegArgs = [
            "-nostdin",
            "-y",
            "-i", "pipe:0",
            "-map", "0:v:0?",
            "-map", "0:a:0?",
            "-c:v", "copy",
            "-c:a", "aac",
            "-ac", "2",
            "-b:a", "256k",
            "-ar", "48000",
            "-f", "hls",
            "-hls_time", "2",
            "-hls_list_size", "0",
            "-hls_segment_filename", segmentPattern,
            playlistFile.path
        ]
        ffmpegProc.arguments = ffmpegArgs
        ffmpegProc.environment = env

        // Inter-process pipe: yt-dlp stdout -> ffmpeg stdin
        let streamPipe = Pipe()
        ytProc.standardOutput = streamPipe
        ffmpegProc.standardInput = streamPipe

        let ytErrPipe = Pipe()
        ytProc.standardError = ytErrPipe

        let ffmpegErrPipe = Pipe()
        ffmpegProc.standardError = ffmpegErrPipe

        ytErrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                self?.onLogLine?("[yt-dlp] \(line)")
            }
        }

        ffmpegErrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                self?.parseProgress(line: line)
                self?.onLogLine?("[ffmpeg] \(line)")
            }
        }

        onLogLine?("🚀 Spawning yt-dlp ➔ FFmpeg streaming bridge for \(webURL.host ?? "stream")...")

        do {
            try ytProc.run()
            try ffmpegProc.run()
        } catch {
            stop()
            throw FFmpegPipelineError.pipelineLaunchFailed(error.localizedDescription)
        }

        syncQueue.sync {
            self.activeYtDlpProcess = ytProc
            self.activeProcess = ffmpegProc
        }

        // Wait for first segment to be written
        let ready = await waitForFirstSegment(playlistURL: playlistFile, timeout: 30.0)
        guard ready else {
            stop()
            throw FFmpegPipelineError.timedOutWaitingForPlaylist
        }

        let playbackURL = streamingServer.serverURL?.appendingPathComponent("playlist.m3u8") ?? playlistFile
        onLogLine?("✅ Online stream bridged successfully at \(playbackURL.absoluteString)")
        return playbackURL
    }

    public func stop() {
        syncQueue.sync {
            if let proc = activeProcess, proc.isRunning {
                proc.terminate()
            }
            activeProcess = nil

            if let yt = activeYtDlpProcess, yt.isRunning {
                yt.terminate()
            }
            activeYtDlpProcess = nil
        }
        streamingServer.stop()

        if let dir = sessionDir {
            try? FileManager.default.removeItem(at: dir)
            sessionDir = nil
        }
    }

    private func parseProgress(line: String) {
        // Example ffmpeg progress line:
        // frame=  150 fps=32.4 q=-1.0 size=N/A time=00:00:05.00 bitrate=N/A speed=18.4x
        guard line.contains("time=") || line.contains("speed=") else { return }

        var fps: Double = 0
        var speed = "1.0x"
        var time = "00:00:00"
        var bitrate = ""

        let components = line.split(separator: " ").filter { !$0.isEmpty }
        for comp in components {
            let str = String(comp)
            if str.hasPrefix("fps=") {
                fps = Double(str.replacingOccurrences(of: "fps=", with: "")) ?? 0
            } else if str.hasPrefix("speed=") {
                speed = str.replacingOccurrences(of: "speed=", with: "")
            } else if str.hasPrefix("time=") {
                time = str.replacingOccurrences(of: "time=", with: "")
            } else if str.hasPrefix("bitrate=") {
                bitrate = str.replacingOccurrences(of: "bitrate=", with: "")
            }
        }

        let stats = PipelineStats(fps: fps, speedFactor: speed, currentTime: time, bitrate: bitrate, isReadyForPlayback: true)
        onStatsUpdated?(stats)
    }

    private func waitForFirstSegment(playlistURL: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let fm = FileManager.default

        while Date() < deadline {
            if fm.fileExists(atPath: playlistURL.path) {
                if let content = try? String(contentsOf: playlistURL, encoding: .utf8),
                   content.contains(".ts") {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms check
        }
        return false
    }
}
