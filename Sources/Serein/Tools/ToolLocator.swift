import Foundation

public struct ToolInfo: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let isAvailable: Bool
    public let version: String?
}

/// Locates external utilities (ffmpeg, ffprobe, yt-dlp) across standard macOS locations.
public final class ToolLocator: @unchecked Sendable {
    public static let shared = ToolLocator()

    private let standardSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/opt/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
    ]

    private var cachedPaths: [String: String] = [:]
    private var cachedVersions: [String: String] = [:]
    private let lock = NSLock()

    private init() {
        refresh()
    }

    public func refresh() {
        lock.lock()
        defer { lock.unlock() }
        cachedPaths.removeAll()
        cachedVersions.removeAll()

        for tool in ["ffprobe", "ffmpeg", "yt-dlp"] {
            if let path = findExecutable(named: tool) {
                cachedPaths[tool] = path
                cachedVersions[tool] = probeVersion(of: path, toolName: tool)
            }
        }
    }

    public func path(for tool: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedPaths[tool]
    }

    public func isAvailable(_ tool: String) -> Bool {
        path(for: tool) != nil
    }

    public func info(for tool: String) -> ToolInfo {
        lock.lock()
        defer { lock.unlock() }
        let p = cachedPaths[tool]
        let v = cachedVersions[tool]
        return ToolInfo(name: tool, path: p, isAvailable: p != nil, version: v)
    }

    public var allTools: [ToolInfo] {
        ["ffprobe", "ffmpeg", "yt-dlp"].map { info(for: $0) }
    }

    private func findExecutable(named name: String) -> String? {
        let fm = FileManager.default

        // Check app bundle resources if bundled
        if let bundlePath = Bundle.main.path(forResource: name, ofType: nil),
           fm.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        // Check standard macOS paths
        for dir in standardSearchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: candidate) && fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Check PATH environment
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":").map(String.init) {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: candidate) && fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func probeVersion(of path: String, toolName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = (toolName == "yt-dlp") ? ["--version"] : ["-version"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (standardSearchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let firstLine = output.components(separatedBy: .newlines).first ?? output
                return firstLine.replacingOccurrences(of: "ffmpeg version ", with: "")
                    .replacingOccurrences(of: "ffprobe version ", with: "")
            }
        } catch {
            return nil
        }
        return nil
    }
}
