import Foundation

/// DTO structures matching FFprobe JSON output schema.
private struct RawProbeRoot: Codable {
    let streams: [RawProbeStream]?
    let format: RawProbeFormat?
}

private struct RawProbeFormat: Codable {
    let filename: String?
    let format_name: String?
    let format_long_name: String?
    let duration: String?
    let size: String?
    let bit_rate: String?
    let tags: [String: String]?
}

private struct RawProbeStream: Codable {
    let index: Int
    let codec_name: String?
    let codec_long_name: String?
    let profile: String?
    let codec_type: String?
    let width: Int?
    let height: Int?
    let pix_fmt: String?
    let r_frame_rate: String?
    let avg_frame_rate: String?
    let bit_rate: String?
    let sample_rate: String?
    let channels: Int?
    let channel_layout: String?
    let tags: [String: String]?
    let disposition: [String: Int]?
}

public enum FFprobeError: LocalizedError, Sendable {
    case ffprobeNotFound
    case analysisFailed(String)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .ffprobeNotFound:
            return "FFprobe was not found on this system. Please install via Homebrew ('brew install ffmpeg')."
        case .analysisFailed(let detail):
            return "Failed to probe media: \(detail)"
        case .invalidOutput:
            return "FFprobe returned invalid or unparseable JSON data."
        }
    }
}

/// Service that invokes ffprobe to extract comprehensive container and codec metrics.
public final class FFprobeService: Sendable {
    public static let shared = FFprobeService()

    private init() {}

    public func probe(url: URL) async throws -> MediaProbeResult {
        guard let probePath = ToolLocator.shared.path(for: "ffprobe") else {
            throw FFprobeError.ffprobeNotFound
        }

        let inputArg = url.isFileURL ? url.path : url.absoluteString

        var arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams"
        ]

        if !url.isFileURL {
            arguments.append(contentsOf: [
                "-user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
            ])
        }

        arguments.append(inputArg)

        let result = try await ProcessRunner.run(executablePath: probePath, arguments: arguments)

        guard result.isSuccess else {
            throw FFprobeError.analysisFailed(result.stderr.isEmpty ? "Exit code \(result.exitCode)" : result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw FFprobeError.invalidOutput
        }

        do {
            let root = try JSONDecoder().decode(RawProbeRoot.self, from: data)
            return parseResult(root: root, fallbackURL: url)
        } catch {
            throw FFprobeError.analysisFailed("Failed to parse probe output: \(error.localizedDescription)")
        }
    }

    private func parseResult(root: RawProbeRoot, fallbackURL: URL) -> MediaProbeResult {
        let fmt = root.format
        let formatName = fmt?.format_name ?? fallbackURL.pathExtension
        let formatLong = fmt?.format_long_name ?? "Media File"
        let durationSec = Double(fmt?.duration ?? "0") ?? 0
        let size = Int64(fmt?.size ?? "0") ?? 0
        let overallBitrate = Int64(fmt?.bit_rate ?? "0") ?? 0
        let container = ContainerFormat(rawString: formatName)
        let tags = fmt?.tags ?? [:]

        var parsedStreams: [MediaStream] = []

        for raw in (root.streams ?? []) {
            let kind = StreamKind(rawString: raw.codec_type ?? "unknown")
            let cName = raw.codec_name ?? "unknown"
            let cLong = raw.codec_long_name ?? cName

            var vCodec: VideoCodec? = nil
            var aCodec: AudioCodec? = nil

            if kind == .video {
                vCodec = VideoCodec(name: cName)
            } else if kind == .audio {
                aCodec = AudioCodec(name: cName)
            }

            // Parse FPS
            var fps: Double? = nil
            if let rRate = raw.r_frame_rate, let calculated = parseFraction(rRate) {
                fps = calculated
            } else if let avgRate = raw.avg_frame_rate, let calculated = parseFraction(avgRate) {
                fps = calculated
            }

            let sampleRate = raw.sample_rate != nil ? Int(raw.sample_rate!) : nil
            let streamBitrate = raw.bit_rate != nil ? Int64(raw.bit_rate!) : nil

            let isDefault = (raw.disposition?["default"] ?? 0) == 1
            let lang = raw.tags?["language"] ?? raw.tags?["LANGUAGE"]
            let title = raw.tags?["title"] ?? raw.tags?["TITLE"]

            let stream = MediaStream(
                index: raw.index,
                kind: kind,
                codecName: cName,
                codecLongName: cLong,
                profile: raw.profile,
                bitrate: streamBitrate,
                width: raw.width,
                height: raw.height,
                fps: fps,
                pixelFormat: raw.pix_fmt,
                videoCodec: vCodec,
                sampleRate: sampleRate,
                channels: raw.channels,
                channelLayout: raw.channel_layout,
                audioCodec: aCodec,
                language: lang,
                title: title,
                isDefault: isDefault
            )
            parsedStreams.append(stream)
        }

        return MediaProbeResult(
            filename: fmt?.filename ?? fallbackURL.lastPathComponent,
            formatName: formatName,
            formatLongName: formatLong,
            duration: durationSec,
            sizeBytes: size,
            overallBitrate: overallBitrate,
            containerFormat: container,
            streams: parsedStreams,
            tags: tags
        )
    }

    private func parseFraction(_ string: String) -> Double? {
        let parts = string.split(separator: "/")
        if parts.count == 2,
           let num = Double(parts[0]),
           let den = Double(parts[1]),
           den > 0 {
            let res = num / den
            return res.isFinite && res > 0 ? res : nil
        } else if let val = Double(string) {
            return val
        }
        return nil
    }
}
