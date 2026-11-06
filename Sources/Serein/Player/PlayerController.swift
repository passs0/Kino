import Foundation
import AVFoundation
import AVKit
import Combine
import SwiftUI

/// Controller managing the AVPlayer instance, playback state, seeking, and metrics.
@MainActor
public final class PlayerController: ObservableObject {
    public static let shared = PlayerController()

    public let player = AVPlayer()
    public weak var activePlayerNSView: SereinPlayerNSView?

    @Published public private(set) var isPlaying: Bool = false {
        didSet {
            SleepPreventionManager.shared.setSleepDisabled(isPlaying)
        }
    }
    @Published public private(set) var isBuffering: Bool = false
    @Published public var isPictureInPictureActive: Bool = false
    @Published public var resumeNotificationText: String? = nil
    @Published public var hudMessage: String? = nil
    @Published public var hudIconName: String? = nil
    private var hudDismissTask: Task<Void, Never>?

    /// Current base time offset for active transcode / HLS streaming pipelines.
    @Published public private(set) var streamTimeOffset: Double = 0

    /// State indicating an active seek/scrub operation is in progress, preventing periodic time observer snapback.
    @Published public private(set) var isSeeking: Bool = false
    private var seekTargetTime: Double? = nil
    private var seekTimeoutTask: Task<Void, Never>?
    private var streamSeekTask: Task<Void, Never>?

    private var pendingResumeTime: Double? = nil
    private var lastSavedResumeTime: Double = 0
    private var resumeToastTask: Task<Void, Never>?

    public var currentTime: Double {
        get { PlayerTimeState.shared.currentTime }
        set { PlayerTimeState.shared.currentTime = newValue }
    }
    public var duration: Double {
        get { PlayerTimeState.shared.duration }
        set { PlayerTimeState.shared.duration = newValue }
    }
    public var loadedDuration: Double {
        get { PlayerTimeState.shared.loadedDuration }
        set { PlayerTimeState.shared.loadedDuration = newValue }
    }

    @Published public var volume: Float = 1.0 {
        didSet { player.volume = isMuted ? 0 : volume }
    }
    @Published public var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
                NowPlayingManager.shared.updatePlaybackState(isPlaying: true, rate: playbackRate)
            }
        }
    }
    @Published public var isLetterboxed: Bool = true {
        didSet {
            activePlayerNSView?.playerLayer.videoGravity = isLetterboxed ? .resizeAspect : .resizeAspectFill
        }
    }

    public func toggleLetterbox() {
        isLetterboxed.toggle()
        let mode = isLetterboxed ? "Fit to Screen (Preserve Aspect)" : "Fill Screen (Crop)"
        showHUD(message: "Video Aspect: \(mode)", iconName: "aspectratio")
    }

    /// Displays a transient, non-intrusive on-screen notification pill (HUD).
    public func showHUD(message: String, iconName: String = "info.circle") {
        hudDismissTask?.cancel()
        hudMessage = message
        hudIconName = iconName
        hudDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.hudMessage = nil
                self?.hudIconName = nil
            }
        }
    }

    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemLoadedRangesObserver: NSKeyValueObservation?
    private var itemBufferObserver: NSKeyValueObservation?
    private var itemKeepUpObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private lazy var legibleDelegateBridge = LegibleOutputBridge { [weak self] text in
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            SubtitleManager.shared.updateNativeLegibleText(text)
        }
    }

    public init() {
        setupTimeObserver()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    public func load(url: URL, expectedDuration: Double? = nil, initialTime: Double? = nil) {
        cleanupItemObservers()
        seekTimeoutTask?.cancel()
        streamSeekTask?.cancel()
        isSeeking = false
        seekTargetTime = nil
        streamTimeOffset = 0
        resumeToastTask?.cancel()
        resumeNotificationText = nil
        player.volume = 0
        let wasPlaying = self.isPlaying
        player.pause()

        if let initTime = initialTime, initTime > 0 {
            PlayerTimeState.shared.currentTime = initTime
            self.pendingResumeTime = nil
        } else {
            PlayerTimeState.shared.reset()
            // Check if there is a saved resume position for this media source
            if let src = MediaCoordinator.shared.currentSource,
               let saved = PlaybackResumeManager.shared.savedPosition(for: src) {
                self.pendingResumeTime = saved
            } else {
                self.pendingResumeTime = nil
            }
        }

        if let exp = expectedDuration, exp > 0 {
            PlayerTimeState.shared.duration = exp
        }

        let item = AVPlayerItem(url: url)
        setupItemObservers(for: item, autoResumePlayback: wasPlaying)

        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.volume = isMuted ? 0 : volume
        player.isMuted = isMuted
        player.rate = playbackRate
        player.play()
        isPlaying = true
        NowPlayingManager.shared.mediaItemDidChange()
    }

    /// Explicitly updates duration from metadata (FFprobe or yt-dlp) when available.
    public func setKnownDuration(_ seconds: Double) {
        guard seconds > 0, seconds.isFinite, !seconds.isNaN else { return }
        if PlayerTimeState.shared.duration <= 2.0 || PlayerTimeState.shared.duration < seconds {
            PlayerTimeState.shared.duration = seconds
            NowPlayingManager.shared.updateNowPlayingInfo()
        }
    }

    public func play() {
        player.rate = playbackRate
        isPlaying = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, rate: playbackRate)
    }

    public func pause() {
        player.pause()
        isPlaying = false
        saveCurrentPosition()
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, rate: 0.0)
    }

    public func saveCurrentPosition() {
        if let src = MediaCoordinator.shared.currentSource {
            PlaybackResumeManager.shared.savePosition(
                PlayerTimeState.shared.currentTime,
                duration: PlayerTimeState.shared.duration,
                for: src
            )
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func toggleMute() {
        isMuted.toggle()
    }

    public func adjustVolume(by delta: Float) {
        if isMuted && delta > 0 {
            isMuted = false
        }
        volume = max(0.0, min(1.0, volume + delta))
    }

    /// Checks if a given timestamp is already contained in AVPlayer's loaded time ranges.
    public func isTimestampBuffered(_ targetSeconds: Double) -> Bool {
        guard let item = player.currentItem else { return false }
        for val in item.loadedTimeRanges {
            let range = val.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let dur = CMTimeGetSeconds(range.duration)
            if start.isFinite && dur.isFinite && !start.isNaN && !dur.isNaN {
                if targetSeconds >= start && targetSeconds <= (start + dur - 0.5) {
                    return true
                }
            }
        }
        return false
    }

    public func seek(to seconds: Double) {
        let maxD = max(PlayerTimeState.shared.duration, MediaCoordinator.shared.knownDuration ?? 0)
        let targetSec = max(0, min(seconds, maxD > 0 ? maxD : seconds))
        let relativeSec = max(0, targetSec - streamTimeOffset)
        let cmTime = CMTime(seconds: relativeSec, preferredTimescale: 600)
        SubtitleManager.shared.handleUserSeek(to: targetSec)

        // Prevent periodic time observer snapback during user seeking
        isSeeking = true
        seekTargetTime = targetSec
        PlayerTimeState.shared.currentTime = targetSec
        NowPlayingManager.shared.updateElapsedTime(targetSec)

        seekTimeoutTask?.cancel()
        seekTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.isSeeking = false
            self?.seekTargetTime = nil
        }

        // Check if the target timestamp is already buffered in AVPlayer
        let isLoaded = isTimestampBuffered(relativeSec)

        if !isLoaded && MediaCoordinator.shared.isPipelineActive {
            // Seeking to an unloaded timestamp in an active transcoding / HLS stream:
            streamSeekTask?.cancel()
            streamSeekTask = Task { @MainActor in
                // 100ms debounce to coalesce rapid seek interactions
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                await MediaCoordinator.shared.seekPipeline(to: targetSec)
            }
            return
        }

        // Seeking within buffered data or direct native stream with sample-accurate tolerance
        let exactTolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: exactTolerance, toleranceAfter: exactTolerance) { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self = self, completed else { return }
                self.isSeeking = false
                self.seekTargetTime = nil
                self.seekTimeoutTask?.cancel()

                let actualSec = CMTimeGetSeconds(self.player.currentTime())
                let settledEffective = (actualSec.isFinite && !actualSec.isNaN) ? (self.streamTimeOffset + actualSec) : targetSec
                PlayerTimeState.shared.currentTime = settledEffective
                SubtitleManager.shared.updateTime(settledEffective)
            }
        }
    }

    /// Seamlessly connects the player to a newly re-aligned stream segment pipeline without resetting duration or timeline state.
    public func loadStreamFromSeek(url: URL, expectedDuration: Double? = nil, timeOffset: Double) {
        cleanupItemObservers()
        resumeToastTask?.cancel()
        resumeNotificationText = nil

        self.streamTimeOffset = timeOffset
        self.isSeeking = true
        self.seekTargetTime = timeOffset
        PlayerTimeState.shared.currentTime = timeOffset

        if let exp = expectedDuration, exp > 0 {
            PlayerTimeState.shared.duration = exp
        }

        let item = AVPlayerItem(url: url)
        setupItemObservers(for: item, autoResumePlayback: true)

        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.volume = isMuted ? 0 : volume
        player.isMuted = isMuted
        player.rate = playbackRate
        player.play()
        isPlaying = true
    }

    public func seekRelative(seconds: Double) {
        seek(to: PlayerTimeState.shared.currentTime + seconds)
    }

    public func togglePictureInPicture() {
        activePlayerNSView?.togglePiP()
    }

    public func reset() {
        cleanupItemObservers()
        seekTimeoutTask?.cancel()
        streamSeekTask?.cancel()
        isSeeking = false
        seekTargetTime = nil
        streamTimeOffset = 0
        player.volume = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        SubtitleManager.shared.reset()
        PlayerTimeState.shared.reset()
        isPlaying = false
        NowPlayingManager.shared.clear()
    }

    /// Smoothly fades out audio to zero before pausing and tearing down the player item to prevent CoreAudio clicks/pops on quit.
    public func shutdownAudioCleanly() async {
        if let src = MediaCoordinator.shared.currentSource {
            PlaybackResumeManager.shared.savePosition(
                PlayerTimeState.shared.currentTime,
                duration: PlayerTimeState.shared.duration,
                for: src
            )
        }
        let startVol = player.volume
        if isPlaying && !isMuted && startVol > 0 {
            let steps = 5
            for step in 1...steps {
                let fraction = Float(steps - step) / Float(steps)
                player.volume = startVol * fraction
                try? await Task.sleep(nanoseconds: 12_000_000) // 12ms per step (~60ms total ramp)
            }
        }
        player.volume = 0
        player.isMuted = true
        player.pause()
        try? await Task.sleep(nanoseconds: 25_000_000) // Allow CoreAudio hardware output buffer to drain zero-crossing samples
        cleanupItemObservers()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        NowPlayingManager.shared.clear()
    }

    // MARK: - Internal Observers

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                guard sec.isFinite && !sec.isNaN else { return }

                let effectiveTime = self.streamTimeOffset + sec

                // If user is actively seeking or awaiting stream repositioning:
                if self.isSeeking, let target = self.seekTargetTime {
                    if abs(effectiveTime - target) <= 2.0 || self.player.rate > 0 {
                        self.isSeeking = false
                        self.seekTargetTime = nil
                        self.seekTimeoutTask?.cancel()
                    } else {
                        // Hold intended seek target so the scrubber does not snap back while buffering
                        return
                    }
                }

                PlayerTimeState.shared.currentTime = effectiveTime
                SubtitleManager.shared.updateTime(effectiveTime)
                NowPlayingManager.shared.periodicSync(currentTime: effectiveTime, duration: PlayerTimeState.shared.duration)

                // Throttle saving playback position every 2.5 seconds
                if abs(effectiveTime - self.lastSavedResumeTime) >= 2.5,
                   let src = MediaCoordinator.shared.currentSource {
                    self.lastSavedResumeTime = effectiveTime
                    PlaybackResumeManager.shared.savePosition(
                        effectiveTime,
                        duration: PlayerTimeState.shared.duration,
                        for: src
                    )
                }
            }
        }
    }

    private func setupItemObservers(for item: AVPlayerItem, autoResumePlayback: Bool = false) {
        let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
        output.suppressesPlayerRendering = true
        output.setDelegate(legibleDelegateBridge, queue: .main)
        item.add(output)
        self.legibleOutput = output

        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    let d = CMTimeGetSeconds(observedItem.duration)
                    if d.isFinite && !d.isNaN && d > 2.0 && d > PlayerTimeState.shared.duration {
                        PlayerTimeState.shared.duration = d
                        NowPlayingManager.shared.updateNowPlayingInfo()
                    }
                    self.isBuffering = false
                    self.syncNativeSubtitleSelection(for: SubtitleManager.shared.selectedTrack)
                    self.syncNativeAudioSelection(for: AudioManager.shared.selectedTrack)

                    // Auto-discover native audio tracks if not already detected by FFprobe
                    Task { @MainActor in
                        if AudioManager.shared.availableTracks.isEmpty,
                           let group = try? await observedItem.asset.loadMediaSelectionGroup(for: .audible) {
                            let tracks = group.options.enumerated().map { (idx, opt) -> AudioTrack in
                                let lang = opt.extendedLanguageTag ?? opt.locale?.language.languageCode?.identifier
                                return AudioTrack(
                                    id: "native_audio_\(idx)",
                                    streamIndex: idx,
                                    name: opt.displayName,
                                    languageCode: lang,
                                    isDefault: opt == group.defaultOption
                                )
                            }
                            if !tracks.isEmpty {
                                AudioManager.shared.setAvailableTracks(tracks)
                            }
                        }
                    }

                    // Perform auto-resume if saved position exists (> 4s)
                    if let resumeSec = self.pendingResumeTime, resumeSec > 4.0 {
                        self.pendingResumeTime = nil
                        self.seek(to: resumeSec)
                        self.showResumeToast(time: resumeSec)
                    }

                    if self.isPlaying || autoResumePlayback {
                        self.isPlaying = true
                        self.player.play()
                        self.player.rate = self.playbackRate
                    }
                case .failed:
                    self.isPlaying = false
                    let errDesc = observedItem.error?.localizedDescription ?? "Unknown AVPlayerItem error"
                    print("[AVPlayerItem] Failed error: \(errDesc)")
                    MediaCoordinator.shared.log("❌ AVPlayer item failed: \(errDesc)", level: .error)
                    MediaCoordinator.shared.handlePlaybackFailure(error: errDesc)
                default:
                    break
                }
            }
        }

        itemDurationObserver = item.observe(\.duration, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                let d = CMTimeGetSeconds(observedItem.duration)
                if d.isFinite && !d.isNaN && d > 2.0 && d > PlayerTimeState.shared.duration {
                    PlayerTimeState.shared.duration = d
                }
            }
        }

        itemLoadedRangesObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let range = observedItem.loadedTimeRanges.first?.timeRangeValue {
                    let start = CMTimeGetSeconds(range.start)
                    let dur = CMTimeGetSeconds(range.duration)
                    if start.isFinite && dur.isFinite && !start.isNaN && !dur.isNaN {
                        PlayerTimeState.shared.loadedDuration = max(PlayerTimeState.shared.loadedDuration, self.streamTimeOffset + start + dur)
                    }
                }
            }
        }

        itemBufferObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = observedItem.isPlaybackBufferEmpty
            }
        }

        itemKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if observedItem.isPlaybackLikelyToKeepUp {
                    self.isBuffering = false
                    if self.isPlaying && self.player.rate == 0 {
                        self.player.play()
                        self.player.rate = self.playbackRate
                    }
                }
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPlaying = false
            }
        }
    }

    private func cleanupItemObservers() {
        if let obs = itemEndObserver {
            NotificationCenter.default.removeObserver(obs)
            itemEndObserver = nil
        }
        if let output = legibleOutput, let currentItem = player.currentItem {
            currentItem.remove(output)
        }
        legibleOutput = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        itemDurationObserver?.invalidate()
        itemDurationObserver = nil
        itemLoadedRangesObserver?.invalidate()
        itemLoadedRangesObserver = nil
        itemBufferObserver?.invalidate()
        itemBufferObserver = nil
        itemKeepUpObserver?.invalidate()
        itemKeepUpObserver = nil
    }

    /// Synchronizes AVPlayerItem's native legible media selection group with SubtitleManager's selected track.
    public func syncNativeSubtitleSelection(for track: SubtitleTrack?) {
        guard let item = player.currentItem else { return }
        Task { @MainActor in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            guard let track = track else {
                item.select(nil, in: group)
                SubtitleManager.shared.updateNativeLegibleText(nil)
                return
            }

            let options = group.options
            guard !options.isEmpty else { return }

            if let lang = track.languageCode?.lowercased() {
                if let matched = options.first(where: {
                    let optLang = $0.extendedLanguageTag?.lowercased() ?? $0.locale?.language.languageCode?.identifier.lowercased() ?? ""
                    return optLang == lang || optLang.hasPrefix(lang) || lang.hasPrefix(optLang)
                }) {
                    item.select(matched, in: group)
                    return
                }
            }

            if let matchedByName = options.first(where: {
                $0.displayName.localizedCaseInsensitiveContains(track.name) ||
                track.name.localizedCaseInsensitiveContains($0.displayName)
            }) {
                item.select(matchedByName, in: group)
                return
            }

            if let def = group.defaultOption ?? options.first {
                item.select(def, in: group)
            }
        }
    }

    /// Synchronizes AVPlayerItem's native audible media selection group with AudioManager's selected track.
    public func syncNativeAudioSelection(for track: AudioTrack?) {
        guard let item = player.currentItem else { return }
        Task { @MainActor in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            let options = group.options
            guard !options.isEmpty else { return }

            if let track = track {
                if let lang = track.languageCode?.lowercased() {
                    if let matched = options.first(where: {
                        let optLang = $0.extendedLanguageTag?.lowercased() ?? $0.locale?.language.languageCode?.identifier.lowercased() ?? ""
                        return optLang == lang || optLang.hasPrefix(lang) || lang.hasPrefix(optLang)
                    }) {
                        item.select(matched, in: group)
                        return
                    }
                }
                if let matchedByName = options.first(where: {
                    $0.displayName.localizedCaseInsensitiveContains(track.name) ||
                    track.name.localizedCaseInsensitiveContains($0.displayName)
                }) {
                    item.select(matchedByName, in: group)
                    return
                }
            }

            if let def = group.defaultOption ?? options.first {
                item.select(def, in: group)
            }
        }
    }

    /// Shows a transient macOS notification toast indicating auto-resume from a saved position.
    public func showResumeToast(time: Double) {
        let formatted = formatSeconds(time)
        resumeNotificationText = "Resumed from \(formatted)"

        resumeToastTask?.cancel()
        resumeToastTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.resumeNotificationText = nil
                }
            }
        }
    }

    /// Re-starts playback from the very beginning and clears the saved position.
    public func restartFromBeginning() {
        resumeToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            resumeNotificationText = nil
        }
        if let src = MediaCoordinator.shared.currentSource {
            PlaybackResumeManager.shared.clearPosition(for: src)
        }
        seek(to: 0)
    }

    // MARK: - Formatted Strings

    public var formattedCurrentTime: String {
        formatSeconds(currentTime)
    }

    public var formattedDuration: String {
        formatSeconds(duration)
    }

    public var formattedRemainingTime: String {
        let rem = max(0, duration - currentTime)
        return "-\(formatSeconds(rem))"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let s = total % 60
        let m = (total % 3600) / 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

/// Delegate bridge receiving real-time legible subtitle cues directly from AVPlayerItem.
private final class LegibleOutputBridge: NSObject, AVPlayerItemLegibleOutputPushDelegate {
    private let onText: (String?) -> Void

    init(onText: @escaping (String?) -> Void) {
        self.onText = onText
    }

    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let combined = strings.map { $0.string }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        onText(combined.isEmpty ? nil : combined)
    }

    func outputSequenceWasFlushed(_ output: AVPlayerItemOutput) {
        onText(nil)
    }
}
