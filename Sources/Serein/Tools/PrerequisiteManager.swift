import Foundation
import Combine

/// Manages on-demand downloading, local storage, and updating of external media engines
/// (FFmpeg, FFprobe, yt-dlp) inside user Application Support without requiring Homebrew or sudo.
@MainActor
public final class PrerequisiteManager: ObservableObject {
    public static let shared = PrerequisiteManager()

    /// Standard user Application Support directory for Serein helper binaries:
    /// ~/Library/Application Support/Serein/bin/
    public static var managedBinDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Serein/bin", isDirectory: true)
    }

    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var currentStepText: String = ""
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var isCheckingUpdates: Bool = false
    @Published public private(set) var updateStatusMessage: String? = nil
    @Published public private(set) var isFFmpegInstalled: Bool = false
    @Published public private(set) var isYtDlpInstalled: Bool = false

    public var isAllInstalled: Bool {
        isFFmpegInstalled && isYtDlpInstalled
    }

    private init() {
        try? FileManager.default.createDirectory(at: Self.managedBinDirectory, withIntermediateDirectories: true)
        refreshStatus()
    }

    public func refreshStatus() {
        ToolLocator.shared.refresh()
        isFFmpegInstalled = ToolLocator.shared.isAvailable("ffmpeg") && ToolLocator.shared.isAvailable("ffprobe")
        isYtDlpInstalled = ToolLocator.shared.isAvailable("yt-dlp")
    }

    // MARK: - Download & Installation

    /// Downloads and installs missing helper engines into ~/Library/Application Support/Serein/bin/
    public func downloadAndInstallComponents() async {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0.0
        lastError = nil
        currentStepText = "Preparing download environment..."

        let fm = FileManager.default
        let binDir = Self.managedBinDirectory

        do {
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
            refreshStatus()

            // Step 1: yt-dlp
            if !isYtDlpInstalled {
                currentStepText = "Downloading online stream extractor (yt-dlp)..."
                downloadProgress = 0.15

                let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
                let localYtDlp = binDir.appendingPathComponent("yt-dlp")
                try await downloadBinary(from: ytDlpURL, to: localYtDlp)
                downloadProgress = 0.40
            }

            // Step 2: FFmpeg & FFprobe
            let arch = getSystemArchitecture() == "arm64" ? "arm64" : "x64"

            if !ToolLocator.shared.isAvailable("ffmpeg") {
                currentStepText = "Downloading FFmpeg hardware engine..."
                downloadProgress = 0.50

                let ffmpegURL = URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-\(arch)")!
                let localFFmpeg = binDir.appendingPathComponent("ffmpeg")
                try await downloadBinary(from: ffmpegURL, to: localFFmpeg)
                downloadProgress = 0.75
            }

            if !ToolLocator.shared.isAvailable("ffprobe") {
                currentStepText = "Downloading FFprobe stream analyzer..."
                downloadProgress = 0.80

                let ffprobeURL = URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffprobe-darwin-\(arch)")!
                let localFFprobe = binDir.appendingPathComponent("ffprobe")
                try await downloadBinary(from: ffprobeURL, to: localFFprobe)
                downloadProgress = 0.95
            }

            currentStepText = "Verifying helper engines..."
            refreshStatus()

            guard isAllInstalled else {
                throw NSError(
                    domain: "Serein",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Engine verification failed after download."]
                )
            }

            downloadProgress = 1.0
            currentStepText = "All media engines successfully configured!"
            try? await Task.sleep(nanoseconds: 600_000_000)

            isDownloading = false
            MediaCoordinator.shared.log("🚀 Helper media engines successfully installed and verified in \(binDir.path).", level: .success)
        } catch {
            refreshStatus()
            lastError = error.localizedDescription
            isDownloading = false
            currentStepText = "Installation failed: \(error.localizedDescription)"
            MediaCoordinator.shared.log("❌ Failed to install helper engines: \(error.localizedDescription)", level: .error)
        }
    }

    private func downloadBinary(from url: URL, to destination: URL) async throws {
        let fm = FileManager.default
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? fm.removeItem(at: tempURL)
            throw NSError(
                domain: "Serein",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(http.statusCode) for \(url.lastPathComponent)"]
            )
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        stripQuarantine(path: destination.path)
    }

    // MARK: - Check for Updates

    /// Runs update check on yt-dlp
    public func checkForUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateStatusMessage = "Checking for engine updates..."

        let managedYtDlp = Self.managedBinDirectory.appendingPathComponent("yt-dlp")
        if FileManager.default.isExecutableFile(atPath: managedYtDlp.path) {
            let proc = Process()
            proc.executableURL = managedYtDlp
            proc.arguments = ["-U"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                refreshStatus()
                updateStatusMessage = output.contains("Updated") ? "yt-dlp was updated successfully!" : "All engines are up to date."
            } catch {
                updateStatusMessage = "Check finished: \(error.localizedDescription)"
            }
        } else {
            refreshStatus()
            updateStatusMessage = "Using system installed engines."
        }

        try? await Task.sleep(nanoseconds: 2_500_000_000)
        isCheckingUpdates = false
        updateStatusMessage = nil
    }

    // MARK: - Helpers

    private func getSystemArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
        return machine
    }

    private func stripQuarantine(path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-cr", path]
        try? proc.run()
        proc.waitUntilExit()
    }
}
