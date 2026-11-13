import Foundation
import Combine

/// Calculates the 64-bit checksum on a media file according to the official OpenSubtitles moviehash specification.
/// Algorithm: Size + 64KB beginning + 64KB end as 64-bit little-endian unsigned integers with 64-bit overflow.
public enum OpenSubtitlesHasher {
    public enum HashError: LocalizedError {
        case fileTooSmall
        case readFailed
        case unreadableFile

        public var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "File is too small to calculate an OpenSubtitles hash (< 128 KB)."
            case .readFailed:
                return "Failed to read data chunks from video file."
            case .unreadableFile:
                return "Could not open video file for hash calculation."
            }
        }
    }

    public static func calculateHash(for url: URL) throws -> String {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw HashError.unreadableFile
        }
        defer {
            try? handle.close()
        }

        let fileSize = handle.seekToEndOfFile()
        let chunkSize: UInt64 = 65536
        if fileSize < chunkSize * 2 {
            throw HashError.fileTooSmall
        }

        var hash: UInt64 = fileSize
        let wordSize = MemoryLayout<UInt64>.size

        // 1. Read first 64 KB
        try handle.seek(toOffset: 0)
        guard let firstChunk = try handle.read(upToCount: Int(chunkSize)), firstChunk.count >= Int(chunkSize) else {
            throw HashError.readFailed
        }
        firstChunk.withUnsafeBytes { rawBuffer in
            for offset in stride(from: 0, to: Int(chunkSize), by: wordSize) {
                let value = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                hash &+= value
            }
        }

        // 2. Read last 64 KB
        try handle.seek(toOffset: fileSize - chunkSize)
        guard let lastChunk = try handle.read(upToCount: Int(chunkSize)), lastChunk.count >= Int(chunkSize) else {
            throw HashError.readFailed
        }
        lastChunk.withUnsafeBytes { rawBuffer in
            for offset in stride(from: 0, to: Int(chunkSize), by: wordSize) {
                let value = rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                hash &+= value
            }
        }

        return String(format: "%016llx", hash)
    }
}

/// Represents an individual subtitle search result from OpenSubtitles.
public struct SubtitleSearchResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let fileId: Int
    public let fileName: String
    public let releaseName: String
    public let languageCode: String
    public let languageName: String
    public let languageFlag: String
    public let hearingImpaired: Bool
    public let isHD: Bool
    public let fps: Double?
    public let rating: Double
    public let votes: Int
    public let downloadCount: Int
    public let isExactHashMatch: Bool
    public let webURL: URL?

    public init(
        id: String,
        fileId: Int,
        fileName: String,
        releaseName: String,
        languageCode: String,
        languageName: String,
        languageFlag: String,
        hearingImpaired: Bool,
        isHD: Bool,
        fps: Double?,
        rating: Double,
        votes: Int,
        downloadCount: Int,
        isExactHashMatch: Bool,
        webURL: URL?
    ) {
        self.id = id
        self.fileId = fileId
        self.fileName = fileName
        self.releaseName = releaseName
        self.languageCode = languageCode
        self.languageName = languageName
        self.languageFlag = languageFlag
        self.hearingImpaired = hearingImpaired
        self.isHD = isHD
        self.fps = fps
        self.rating = rating
        self.votes = votes
        self.downloadCount = downloadCount
        self.isExactHashMatch = isExactHashMatch
        self.webURL = webURL
    }
}

/// Error types for OpenSubtitles API operations.
public enum OpenSubtitlesError: LocalizedError {
    case invalidURL
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case quotaExceeded(message: String, resetTime: String?, webURL: URL?)
    case noResultsFound
    case downloadLinkMissing
    case parsingError

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenSubtitles endpoint URL."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .apiError(let code, let msg):
            return "OpenSubtitles API error (\(code)): \(msg)"
        case .quotaExceeded(let msg, _, _):
            return "Download quota reached: \(msg)"
        case .noResultsFound:
            return "No matching subtitles found for this video."
        case .downloadLinkMissing:
            return "OpenSubtitles did not return a valid download link."
        case .parsingError:
            return "Failed to parse OpenSubtitles response data."
        }
    }
}

/// Manages OpenSubtitles.com REST API v1 interactions: search, hash lookup, credentials, and downloading.
@MainActor
public final class OpenSubtitlesService: ObservableObject {
    public static let shared = OpenSubtitlesService()

    private static let defaultApiKey = "02WzVTIcNbbJ0IOQH3vZIATriQj9slZx"
    private static let baseURL = "https://api.opensubtitles.com/api/v1"
    private static let userAgent = "Kino v1.0.1"

    private static let customApiKeyDefaultsKey = "KinoOpenSubtitlesCustomApiKey"
    private static let userTokenDefaultsKey = "KinoOpenSubtitlesUserToken"
    private static let usernameDefaultsKey = "KinoOpenSubtitlesUsername"
    private static let preferredLanguageDefaultsKey = "KinoOpenSubtitlesPreferredLanguage"

    @Published public private(set) var isLoggedIn: Bool = false
    @Published public private(set) var username: String? = nil
    @Published public private(set) var userToken: String? = nil
    @Published public private(set) var remainingDailyQuota: Int? = nil

    @Published public var customApiKey: String {
        didSet {
            UserDefaults.standard.set(customApiKey, forKey: Self.customApiKeyDefaultsKey)
        }
    }

    public var activeApiKey: String {
        let trimmed = customApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultApiKey : trimmed
    }

    @Published public var preferredLanguage: String {
        didSet {
            UserDefaults.standard.set(preferredLanguage, forKey: Self.preferredLanguageDefaultsKey)
        }
    }

    private init() {
        let savedKey = UserDefaults.standard.string(forKey: Self.customApiKeyDefaultsKey) ?? ""
        let token = UserDefaults.standard.string(forKey: Self.userTokenDefaultsKey)
        let user = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey)

        let initialLang: String
        if let savedLang = UserDefaults.standard.string(forKey: Self.preferredLanguageDefaultsKey) {
            initialLang = savedLang
        } else {
            initialLang = Locale.current.language.languageCode?.identifier ?? "en"
        }

        self.customApiKey = savedKey
        self.userToken = token
        self.username = user
        self.isLoggedIn = (token != nil && !token!.isEmpty)
        self.preferredLanguage = initialLang
    }

    // MARK: - User Authentication

    public func login(username: String, password: String) async throws {
        guard let url = URL(string: "\(Self.baseURL)/login") else {
            throw OpenSubtitlesError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(activeApiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyObj: [String: String] = ["username": username, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.networkError("Invalid HTTP response")
        }

        guard http.statusCode == 200 else {
            var msg = "Authentication failed (HTTP \(http.statusCode))"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["message"] as? String {
                msg = err
            }
            throw OpenSubtitlesError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw OpenSubtitlesError.parsingError
        }

        self.userToken = token
        self.username = username
        self.isLoggedIn = true

        UserDefaults.standard.set(token, forKey: Self.userTokenDefaultsKey)
        UserDefaults.standard.set(username, forKey: Self.usernameDefaultsKey)

        PlayerController.shared.showHUD(message: "Logged in as \(username)", iconName: "person.crop.circle.badge.checkmark")
    }

    public func logout() {
        self.userToken = nil
        self.username = nil
        self.isLoggedIn = false
        self.remainingDailyQuota = nil

        UserDefaults.standard.removeObject(forKey: Self.userTokenDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)

        PlayerController.shared.showHUD(message: "Logged out from OpenSubtitles", iconName: "person.crop.circle")
    }

    // MARK: - Search Subtitles

    /// Searches OpenSubtitles using optional exact moviehash and/or title query and language filter.
    public func search(
        query: String?,
        movieHash: String?,
        languageCode: String?
    ) async throws -> [SubtitleSearchResult] {
        var results: [SubtitleSearchResult] = []
        var seenFileIds = Set<Int>()

        // 1. If movieHash is provided, query by hash first for guaranteed frame-sync matches
        if let hash = movieHash, !hash.isEmpty {
            if let hashResults = try? await performSearchQuery(queryParam: nil, movieHashParam: hash, languageCode: languageCode, isHashQuery: true) {
                for r in hashResults {
                    if !seenFileIds.contains(r.fileId) {
                        seenFileIds.insert(r.fileId)
                        results.append(r)
                    }
                }
            }
        }

        // 2. Query by title/text search
        let cleanedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = cleanedQuery, !q.isEmpty {
            let titleResults = try await performSearchQuery(queryParam: q, movieHashParam: nil, languageCode: languageCode, isHashQuery: false)
            for r in titleResults {
                if !seenFileIds.contains(r.fileId) {
                    seenFileIds.insert(r.fileId)
                    results.append(r)
                }
            }
        }

        return results
    }

    private func performSearchQuery(
        queryParam: String?,
        movieHashParam: String?,
        languageCode: String?,
        isHashQuery: Bool
    ) async throws -> [SubtitleSearchResult] {
        var components = URLComponents(string: "\(Self.baseURL)/subtitles")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "order_by", value: "download_count"),
            URLQueryItem(name: "order_direction", value: "desc")
        ]

        if let q = queryParam, !q.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: q))
        }

        if let h = movieHashParam, !h.isEmpty {
            queryItems.append(URLQueryItem(name: "moviehash", value: h))
        }

        if let lang = languageCode, !lang.isEmpty, lang != "all" {
            queryItems.append(URLQueryItem(name: "languages", value: lang))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw OpenSubtitlesError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(activeApiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = userToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.networkError("Invalid HTTP response")
        }

        guard http.statusCode == 200 else {
            var msg = "Search failed (HTTP \(http.statusCode))"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["message"] as? String {
                msg = err
            }
            throw OpenSubtitlesError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }

        var parsedResults: [SubtitleSearchResult] = []

        for item in items {
            guard let id = item["id"] as? String,
                  let attributes = item["attributes"] as? [String: Any],
                  let files = attributes["files"] as? [[String: Any]],
                  let firstFile = files.first,
                  let fileId = firstFile["file_id"] as? Int else {
                continue
            }

            let fileName = firstFile["file_name"] as? String ?? "Subtitle"
            let releaseName = attributes["release"] as? String ?? fileName
            let langCode = attributes["language"] as? String ?? "en"
            let langName = Self.languageName(for: langCode)
            let langFlag = Self.flagEmoji(for: langCode)
            let hearingImpaired = attributes["hearing_impaired"] as? Bool ?? false
            let isHD = attributes["hd"] as? Bool ?? false
            let fps = attributes["fps"] as? Double
            let rating = attributes["ratings"] as? Double ?? 0.0
            let votes = attributes["votes"] as? Int ?? 0
            let downloadCount = attributes["download_count"] as? Int ?? 0

            var webURL: URL? = nil
            if let urlStr = attributes["url"] as? String, let u = URL(string: urlStr) {
                webURL = u
            }

            let result = SubtitleSearchResult(
                id: id,
                fileId: fileId,
                fileName: fileName,
                releaseName: releaseName,
                languageCode: langCode,
                languageName: langName,
                languageFlag: langFlag,
                hearingImpaired: hearingImpaired,
                isHD: isHD,
                fps: fps,
                rating: rating,
                votes: votes,
                downloadCount: downloadCount,
                isExactHashMatch: isHashQuery,
                webURL: webURL
            )
            parsedResults.append(result)
        }

        return parsedResults
    }

    // MARK: - Download & Cache

    /// Downloads a subtitle file and writes it to a persistent local cache file, returning the local URL.
    public func download(result: SubtitleSearchResult) async throws -> URL {
        guard let url = URL(string: "\(Self.baseURL)/download") else {
            throw OpenSubtitlesError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(activeApiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = userToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "file_id": result.fileId,
            "sub_format": "srt"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSubtitlesError.networkError("Invalid HTTP response")
        }

        // Quota limit exceeded (HTTP 406 or 429)
        if http.statusCode == 406 || http.statusCode == 429 {
            var msg = "Your daily download quota has been exceeded."
            var resetTime: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let m = json["message"] as? String { msg = m }
                if let r = json["reset_time"] as? String { resetTime = r }
            }
            self.remainingDailyQuota = 0
            throw OpenSubtitlesError.quotaExceeded(message: msg, resetTime: resetTime, webURL: result.webURL)
        }

        guard http.statusCode == 200 else {
            var msg = "Download failed (HTTP \(http.statusCode))"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["message"] as? String {
                msg = err
            }
            throw OpenSubtitlesError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadLink = json["link"] as? String,
              let downloadURL = URL(string: downloadLink) else {
            throw OpenSubtitlesError.downloadLinkMissing
        }

        if let remaining = json["remaining"] as? Int {
            self.remainingDailyQuota = remaining
        }

        // Fetch raw subtitle file data from CDN link
        var fetchReq = URLRequest(url: downloadURL)
        fetchReq.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        fetchReq.timeoutInterval = 20

        let (subData, fetchResponse) = try await URLSession.shared.data(for: fetchReq)
        guard let fetchHttp = fetchResponse as? HTTPURLResponse, fetchHttp.statusCode == 200 else {
            throw OpenSubtitlesError.networkError("Failed to fetch subtitle data from CDN.")
        }

        // Cache downloaded subtitle
        let cacheFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kino/Subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)

        let sanitizedName = result.fileName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let finalName = sanitizedName.lowercased().hasSuffix(".srt") ? sanitizedName : "\(sanitizedName).srt"
        let localFileURL = cacheFolder.appendingPathComponent(finalName)

        try subData.write(to: localFileURL, options: .atomic)
        return localFileURL
    }

    // MARK: - Helper Cleaners & Metadata

    /// Cleans scene release tags (1080p, BluRay, x264, etc.) to extract a pristine movie or series search query.
    public static func cleanTitle(from raw: String) -> String {
        // Strip extension if present
        var s = (raw as NSString).deletingPathExtension
        // Replace dots, underscores, dashes with spaces
        s = s.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Remove release tags and anything following them
        let pattern = #"(?i)\b(1080p|720p|2160p|4k|uhd|bluray|blu-ray|bdrip|brrip|web-dl|webrip|web|hdtv|dvdrip|x264|x265|hevc|h264|h265|aac|ac3|dts|remux|hdr|10bit)\b.*$"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }

        // Remove square and round brackets
        let bracketPattern = #"\[.*?\]|\(.*?\)"#
        if let regex = try? NSRegularExpression(pattern: bracketPattern) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }

        // Collapse extra whitespace
        let cleaned = s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func languageName(for code: String) -> String {
        let base = code.components(separatedBy: "-").first ?? code
        let loc = Locale.current
        return loc.localizedString(forLanguageCode: base) ?? code.uppercased()
    }

    public static func flagEmoji(for code: String) -> String {
        switch code.lowercased() {
        case "en": return "🇺🇸"
        case "zh", "zh-cn", "zh-hans": return "🇨🇳"
        case "zh-tw", "zh-hant": return "🇹🇼"
        case "es": return "🇪🇸"
        case "fr": return "🇫🇷"
        case "de": return "🇩🇪"
        case "ja": return "🇯🇵"
        case "ko": return "🇰🇷"
        case "it": return "🇮🇹"
        case "pt", "pt-br": return "🇧🇷"
        case "pt-pt": return "🇵🇹"
        case "ru": return "🇷🇺"
        case "ar": return "🇸🇦"
        case "hi": return "🇮🇳"
        case "id": return "🇮🇩"
        case "vi": return "🇻🇳"
        case "th": return "🇹🇭"
        case "tr": return "🇹🇷"
        case "pl": return "🇵🇱"
        case "nl": return "🇳🇱"
        case "sv": return "🇸🇪"
        case "da": return "🇩🇰"
        case "fi": return "🇫🇮"
        case "no": return "🇳🇴"
        case "el": return "🇬🇷"
        case "he": return "🇮🇱"
        default: return "🌐"
        }
    }
}
