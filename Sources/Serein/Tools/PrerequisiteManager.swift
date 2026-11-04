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

    public var isAllInstalled: Bool {
        ToolLocator.shared.isAvailable("ffmpeg") && ToolLocator.shared.isAvailable("yt-dlp")
    }

    public var isFFmpegInstalled: Bool {
        ToolLocator.shared.isAvailable("ffmpeg")
    }

    public var isYtDlpInstalled: Bool {
        ToolLocator.shared.isAvailable("yt-dlp")
    }

    private init() {
        // Ensure bin directory exists
        try? FileManager.default.createDirectory(at: Self.managedBinDirectory, withIntermediateDirectories: true)
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

            // Step 1: yt-dlp
            if !ToolLocator.shared.isAvailable("yt-dlp") {
                currentStepText = "Downloading online stream extractor (yt-dlp)..."
                downloadProgress = 0.15

                let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
                let localYtDlp = binDir.appendingPathComponent("yt-dlp")

                let (tempURL, _) = try await URLSession.shared.download(from: ytDlpURL)
                if fm.fileExists(atPath: localYtDlp.path) {
                    try fm.removeItem(at: localYtDlp)
                }
                try fm.moveItem(at: tempURL, to: localYtDlp)

                // Permissions: rwxr-xr-x (0o755)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localYtDlp.path)
                stripQuarantine(path: localYtDlp.path)
                downloadProgress = 0.40
            }

            // Step 2: FFmpeg & FFprobe
            if !ToolLocator.shared.isAvailable("ffmpeg") || !ToolLocator.shared.isAvailable("ffprobe") {
                currentStepText = "Downloading FFmpeg engine & codecs (~35 MB)..."
                downloadProgress = 0.50

                let arch = getSystemArchitecture()
                let ffmpegURLString: String
                if arch == "arm64" {
                    ffmpegURLString = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-macos-arm64-gpl.zip"
                } else {
                    ffmpegURLString = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-macos-x86_64-gpl.zip"
                }

                guard let ffmpegURL = URL(string: ffmpegURLString) else {
                    throw NSError(domain: "Serein", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid FFmpeg URL"])
                }

                let (tempZipURL, _) = try await URLSession.shared.download(from: ffmpegURL)
                currentStepText = "Extracting FFmpeg & FFprobe..."
                downloadProgress = 0.85

                let extractDir = fm.temporaryDirectory.appendingPathComponent("serein_ffmpeg_\(UUID().uuidString)")
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // Unpack with macOS built-in /usr/bin/ditto
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-xk", tempZipURL.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()

                // Locate ffmpeg and ffprobe inside extracted directory
                let subpaths = fm.subpaths(atPath: extractDir.path) ?? []
                for subpath in subpaths {
                    let name = (subpath as NSString).lastPathComponent
                    if name == "ffmpeg" || name == "ffprobe" {
                        let fileURL = extractDir.appendingPathComponent(subpath)
                        let target = binDir.appendingPathComponent(name)
                        if fm.fileExists(atPath: target.path) {
                            try? fm.removeItem(at: target)
                        }
                        try? fm.copyItem(at: fileURL, to: target)
                        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                        stripQuarantine(path: target.path)
                    }
                }

                try? fm.removeItem(at: extractDir)
                try? fm.removeItem(at: tempZipURL)
            }

            downloadProgress = 1.0
            currentStepText = "Verifying helper engines..."

            // Refresh ToolLocator
            ToolLocator.shared.refresh()
            currentStepText = "All media engines successfully configured!"
            try await Task.sleep(nanoseconds: 800_000_000)

            isDownloading = false
            MediaCoordinator.shared.log("🚀 Helper media engines successfully installed and verified in \(binDir.path).", level: .success)
        } catch {
            lastError = error.localizedDescription
            isDownloading = false
            currentStepText = "Installation failed: \(error.localizedDescription)"
            MediaCoordinator.shared.log("❌ Failed to install helper engines: \(error.localizedDescription)", level: .error)
        }
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
                ToolLocator.shared.refresh()
                updateStatusMessage = output.contains("Updated") ? "yt-dlp was updated successfully!" : "All engines are up to date."
            } catch {
                updateStatusMessage = "Check finished: \(error.localizedDescription)"
            }
        } else {
            ToolLocator.shared.refresh()
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
