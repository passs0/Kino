import Foundation
import AppKit
import AVFoundation
import MediaPlayer

/// Manages system-wide macOS Now Playing integration, Control Center widget controls,
/// and hardware keyboard media keys via MediaPlayer framework (MPNowPlayingInfoCenter & MPRemoteCommandCenter).
@MainActor
public final class NowPlayingManager: ObservableObject {
    public static let shared = NowPlayingManager()

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private var currentArtwork: MPMediaItemArtwork?
    private var lastLoadedSourceID: String?
    private var lastPeriodicSyncTime: Double = 0
    private var isInstalled = false

    private init() {}

    /// Installs and registers remote command handlers for macOS Control Center & media keys.
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.play()
            }
            return .success
        }

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.pause()
            }
            return .success
        }

        // Toggle Play / Pause command (Headphone buttons, Touch Bar, Keyboard Play/Pause key)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.togglePlayPause()
            }
            return .success
        }

        // Scrubbing & Timeline seeking
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.seek(to: posEvent.positionTime)
            }
            return .success
        }

        // Skip Backward (5s)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 5.0)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.seekRelative(seconds: -5.0)
            }
            return .success
        }

        // Skip Forward (5s)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 5.0)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerController.shared.seekRelative(seconds: 5.0)
            }
            return .success
        }

        // Disable track skipping until playlist support is activated in v0.2.0
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
    }

    /// Informs Now Playing that a new media source or metadata has been loaded.
    public func mediaItemDidChange() {
        let coordinator = MediaCoordinator.shared
        guard let source = coordinator.currentSource else {
            clear()
            return
        }

        // Prevent redundant artwork regeneration if already loaded
        if lastLoadedSourceID != source.id {
            lastLoadedSourceID = source.id
            currentArtwork = nil
            fetchArtwork(for: source)
        }

        updateNowPlayingInfo()
    }

    /// Updates playback state (playing vs paused) and current playback rate.
    public func updatePlaybackState(isPlaying: Bool, rate: Float) {
        infoCenter.playbackState = isPlaying ? .playing : .paused

        var info = infoCenter.nowPlayingInfo ?? [String: Any]()
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = PlayerTimeState.shared.currentTime
        infoCenter.nowPlayingInfo = info
    }

    /// Updates elapsed playback time immediately following a seek or scrub event.
    public func updateElapsedTime(_ time: Double) {
        var info = infoCenter.nowPlayingInfo ?? [String: Any]()
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        infoCenter.nowPlayingInfo = info
    }

    /// Periodic light sync to keep time drifts aligned (throttled to every 5s).
    public func periodicSync(currentTime: Double, duration: Double) {
        guard abs(currentTime - lastPeriodicSyncTime) >= 5.0 else { return }
        lastPeriodicSyncTime = currentTime

        guard var info = infoCenter.nowPlayingInfo else {
            updateNowPlayingInfo()
            return
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        infoCenter.nowPlayingInfo = info
    }

    /// Updates the full Now Playing dictionary.
    public func updateNowPlayingInfo() {
        let coordinator = MediaCoordinator.shared
        guard let source = coordinator.currentSource else {
            clear()
            return
        }

        var info = [String: Any]()

        // Title & Creator
        if let online = coordinator.extractedOnlineInfo {
            info[MPMediaItemPropertyTitle] = online.title
            info[MPMediaItemPropertyArtist] = online.uploader ?? "Web Stream"
        } else {
            info[MPMediaItemPropertyTitle] = source.displayName
            info[MPMediaItemPropertyArtist] = "Serein"
        }

        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue

        // Duration & Progress
        let duration = PlayerTimeState.shared.duration
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        let currentTime = PlayerTimeState.shared.currentTime
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        let isPlaying = PlayerController.shared.isPlaying
        let rate = PlayerController.shared.playbackRate
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0

        infoCenter.playbackState = isPlaying ? .playing : .paused

        // Artwork
        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        infoCenter.nowPlayingInfo = info
    }

    /// Clears Now Playing state when playback is stopped or reset.
    public func clear() {
        lastLoadedSourceID = nil
        currentArtwork = nil
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }

    // MARK: - Artwork Extraction & Fetching

    /// Directly updates the active artwork image.
    public func updateArtwork(_ image: NSImage) {
        applyArtwork(image)
    }

    private func fetchArtwork(for source: MediaSource) {
        switch source {
        case .online(_, _):
            if let thumbURL = MediaCoordinator.shared.extractedOnlineInfo?.thumbnailURL {
                Task { [weak self] in
                    if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
                       let image = NSImage(data: data) {
                        await MainActor.run { [weak self] in
                            self?.applyArtwork(image)
                        }
                    } else {
                        await MainActor.run { [weak self] in
                            self?.applyDefaultAppArtwork()
                        }
                    }
                }
            } else {
                applyDefaultAppArtwork()
            }

        case .local(let url):
            Task.detached(priority: .utility) { [weak self] in
                // 1. Try high-performance artwork extractor (FLAC, MP3, M4A, ALAC)
                if let image = await ArtworkExtractor.extractArtwork(from: url) {
                    await MainActor.run { [weak self] in
                        self?.applyArtwork(image)
                    }
                    return
                }

                // 2. Fall back to video frame generator (for video files)
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 512, height: 512)

                let targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let (cgImage, _) = try? await generator.image(at: targetTime) {
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    await MainActor.run { [weak self] in
                        self?.applyArtwork(image)
                    }
                } else {
                    await MainActor.run { [weak self] in
                        self?.applyDefaultAppArtwork()
                    }
                }
            }
        }
    }

    private func applyArtwork(_ image: NSImage) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.currentArtwork = artwork
        if var info = infoCenter.nowPlayingInfo {
            info[MPMediaItemPropertyArtwork] = artwork
            infoCenter.nowPlayingInfo = info
        }
    }

    private func applyDefaultAppArtwork() {
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            applyArtwork(appIcon)
        }
    }
}
