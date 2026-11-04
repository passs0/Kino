import Foundation

public struct ExtractedFormat: Identifiable, Hashable, Sendable {
    public var id: String { formatId }
    public let formatId: String
    public let formatNote: String?
    public let ext: String
    public let resolution: String?
    public let vcodec: String?
    public let acodec: String?
    public let tbr: Double?
    public let url: URL?

    public var isVideoOnly: Bool {
        (vcodec != nil && vcodec != "none") && (acodec == nil || acodec == "none")
    }

    public var isAudioOnly: Bool {
        (acodec != nil && acodec != "none") && (vcodec == nil || vcodec == "none")
    }

    public var isMuxed: Bool {
        (vcodec != nil && vcodec != "none") && (acodec != nil && acodec != "none")
    }

    public var isNativeCompatible: Bool {
        guard let vc = vcodec, let ac = acodec else { return false }
        let videoOk = vc.contains("avc") || vc.contains("h264") || vc.contains("mp4v")
        let audioOk = ac.contains("mp4a") || ac.contains("aac") || ac.contains("mp3")
        let extOk = ext.lowercased() == "mp4" || ext.lowercased() == "m4a"
        return videoOk && audioOk && extOk
    }
}

public struct ExtractedMediaInfo: Sendable {
    public let id: String
    public let title: String
    public let uploader: String?
    public let duration: Double?
    public let thumbnailURL: URL?
    public let webpageURL: URL
    public let formats: [ExtractedFormat]
    public let selectedStreamURL: URL
    public let isDirectlyPlayable: Bool
    public let needsTranscodeOrMux: Bool
    public let needsPipedStream: Bool
    public let resolution: String?
    public let subtitles: [SubtitleTrack]

    public var formattedDuration: String {
        guard let d = duration, d > 0 else { return "Live / Unknown" }
        let total = Int(d)
        let m = (total % 3600) / 60
        let s = total % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

public enum YtDlpError: LocalizedError, Sendable {
    case ytDlpNotFound
    case extractionFailed(String)
    case unparseableResponse
    case noStreamFound

    public var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return "yt-dlp was not found. Use Media Engines & Codecs (⌘,) to install automatically."
        case .extractionFailed(let message):
            return "Failed to extract online media: \(message)"
        case .unparseableResponse:
            return "The extractor returned an unexpected response format."
        case .noStreamFound:
            return "No compatible playback streams could be resolved from this URL."
        }
    }
}

/// Service that utilizes yt-dlp to extract direct media streams, formats, and metadata.
public final class YtDlpService: Sendable {
    public static let shared = YtDlpService()

    private init() {}

    public func extract(url: URL) async throws -> ExtractedMediaInfo {
        guard let ytPath = ToolLocator.shared.path(for: "yt-dlp") else {
            throw YtDlpError.ytDlpNotFound
        }

        let arguments = [
            "-J",
            "--all-subs",
            "--no-check-certificates",
            "--skip-download",
            "--no-warnings",
            "--no-playlist",
            url.absoluteString
        ]

        let result = try await ProcessRunner.run(executablePath: ytPath, arguments: arguments)

        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw YtDlpError.extractionFailed(stderr.isEmpty ? "Exit code \(result.exitCode)" : stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw YtDlpError.unparseableResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YtDlpError.unparseableResponse
        }

        return try parseExtractionJSON(json, originalURL: url)
    }

    private func parseExtractionJSON(_ json: [String: Any], originalURL: URL) throws -> ExtractedMediaInfo {
        let id = json["id"] as? String ?? UUID().uuidString
        let title = json["title"] as? String ?? "Online Stream (\(id))"
        let uploader = json["uploader"] as? String ?? json["channel"] as? String
        let duration = json["duration"] as? Double
        let thumbString = json["thumbnail"] as? String
        let thumbURL = thumbString.flatMap { URL(string: $0) }

        // Parse Subtitles & Auto-generated Captions
        var parsedSubtitles: [SubtitleTrack] = []

        // 1. Manual / Author-provided Subtitles
        if let subsDict = json["subtitles"] as? [String: [[String: Any]]] {
            for (lang, formats) in subsDict {
                let vttFormat = formats.first(where: { ($0["ext"] as? String) == "vtt" }) ?? formats.first
                guard let urlStr = vttFormat?["url"] as? String, let streamURL = URL(string: urlStr) else { continue }
                let rawName = vttFormat?["name"] as? String
                let langName = Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
                let displayName = rawName ?? langName
                parsedSubtitles.append(SubtitleTrack(
                    id: "manual_\(lang)",
                    name: displayName,
                    languageCode: lang,
                    isAutoGenerated: false,
                    vttURL: streamURL
                ))
            }
        }

        // 2. Auto-generated Captions
        if let autoDict = json["automatic_captions"] as? [String: [[String: Any]]] {
            for (lang, formats) in autoDict {
                // Ensure we don't duplicate if a manual track already exists
                if parsedSubtitles.contains(where: { $0.languageCode == lang && !$0.isAutoGenerated }) {
                    continue
                }
                let vttFormat = formats.first(where: { ($0["ext"] as? String) == "vtt" }) ?? formats.first
                guard let urlStr = vttFormat?["url"] as? String, let streamURL = URL(string: urlStr) else { continue }
                let rawName = vttFormat?["name"] as? String
                let langName = Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
                let baseName = rawName ?? langName
                let displayName = "\(baseName) [Auto-generated]"
                parsedSubtitles.append(SubtitleTrack(
                    id: "auto_\(lang)",
                    name: displayName,
                    languageCode: lang,
                    isAutoGenerated: true,
                    vttURL: streamURL
                ))
            }
        }

        // Sort: Manual first, then auto-generated; English and common languages towards the top
        parsedSubtitles.sort { a, b in
            if a.isAutoGenerated != b.isAutoGenerated {
                return !a.isAutoGenerated // manual first
            }
            let aCode = a.languageCode?.lowercased() ?? ""
            let bCode = b.languageCode?.lowercased() ?? ""
            if aCode == "en" { return true }
            if bCode == "en" { return false }
            return a.name < b.name
        }

        var parsedFormats: [ExtractedFormat] = []
        if let rawFormats = json["formats"] as? [[String: Any]] {
            for item in rawFormats {
                guard let fId = item["format_id"] as? String,
                      let urlStr = item["url"] as? String,
                      let streamURL = URL(string: urlStr) else { continue }

                let ext = item["ext"] as? String ?? "mp4"
                let vcodec = item["vcodec"] as? String
                let acodec = item["acodec"] as? String
                let note = item["format_note"] as? String
                let resolution = item["resolution"] as? String
                let tbr = item["tbr"] as? Double

                parsedFormats.append(ExtractedFormat(
                    formatId: fId,
                    formatNote: note,
                    ext: ext,
                    resolution: resolution,
                    vcodec: vcodec,
                    acodec: acodec,
                    tbr: tbr,
                    url: streamURL
                ))
            }
        }

        // Direct native HLS (.m3u8) streams from online hosts
        if originalURL.pathExtension.lowercased() == "m3u8",
           let m3u8Format = parsedFormats.first(where: { $0.url?.absoluteString.contains(".m3u8") == true }) {
            return ExtractedMediaInfo(
                id: id,
                title: title,
                uploader: uploader,
                duration: duration,
                thumbnailURL: thumbURL,
                webpageURL: originalURL,
                formats: parsedFormats,
                selectedStreamURL: m3u8Format.url!,
                isDirectlyPlayable: true,
                needsTranscodeOrMux: false,
                needsPipedStream: false,
                resolution: m3u8Format.resolution,
                subtitles: parsedSubtitles
            )
        }

        // For online media streaming platforms:
        // Direct media links to CDN nodes (e.g. googlevideo, akamai, etc.) return HTTP 403 Forbidden
        // when accessed directly by AVPlayer without authentication cookies or client headers.
        // Piping yt-dlp stdout directly into FFmpeg HLS segmentation provides:
        // 1. Zero HTTP 403 errors (yt-dlp authenticates with the platform).
        // 2. Highest available resolution (1080p/4K) merged with authentic original audio.
        // 3. Apple Silicon VideoToolbox real-time encoding with 0 stalls.
        return ExtractedMediaInfo(
            id: id,
            title: title,
            uploader: uploader,
            duration: duration,
            thumbnailURL: thumbURL,
            webpageURL: originalURL,
            formats: parsedFormats,
            selectedStreamURL: originalURL,
            isDirectlyPlayable: false,
            needsTranscodeOrMux: true,
            needsPipedStream: true,
            resolution: json["resolution"] as? String ?? "Best Available (HD)",
            subtitles: parsedSubtitles
        )
    }
}
