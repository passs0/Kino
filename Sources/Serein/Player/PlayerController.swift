import Foundation
import AVFoundation
import AVKit
import Combine

/// Controller managing the AVPlayer instance, playback state, seeking, and metrics.
@MainActor
public final class PlayerController: ObservableObject {
    public static let shared = PlayerController()

    public let player = AVPlayer()
    public weak var activePlayerNSView: SereinPlayerNSView?

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var isBuffering: Bool = false

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
    }

    private var timeObserverToken: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var itemDurationObserver: NSKeyValueObservation?
    private var itemLoadedRangesObserver: NSKeyValueObservation?
    private var itemBufferObserver: NSKeyValueObservation?
    private var itemKeepUpObserver: NSKeyValueObservation?

    public init() {
        setupTimeObserver()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    public func load(url: URL, expectedDuration: Double? = nil) {
        cleanupItemObservers()

        PlayerTimeState.shared.reset()
        if let exp = expectedDuration, exp > 0 {
            PlayerTimeState.shared.duration = exp
        }

        let item = AVPlayerItem(url: url)
        setupItemObservers(for: item)

        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.rate = playbackRate
        player.play()
        isPlaying = true
    }

    /// Explicitly updates duration from metadata (FFprobe or yt-dlp) when available.
    public func setKnownDuration(_ seconds: Double) {
        guard seconds > 0, seconds.isFinite, !seconds.isNaN else { return }
        if PlayerTimeState.shared.duration <= 2.0 || PlayerTimeState.shared.duration < seconds {
            PlayerTimeState.shared.duration = seconds
        }
    }

    public func play() {
        player.rate = playbackRate
        isPlaying = true
    }

    public func pause() {
        player.pause()
        isPlaying = false
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

    public func seek(to seconds: Double) {
        let maxD = PlayerTimeState.shared.duration
        let targetSec = max(0, min(seconds, maxD > 0 ? maxD : seconds))
        let cmTime = CMTime(seconds: targetSec, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                PlayerTimeState.shared.currentTime = targetSec
                SubtitleManager.shared.updateTime(targetSec)
            }
        }
    }

    public func seekRelative(seconds: Double) {
        seek(to: PlayerTimeState.shared.currentTime + seconds)
    }

    public func togglePictureInPicture() {
        activePlayerNSView?.togglePiP()
    }

    public func reset() {
        cleanupItemObservers()
        player.replaceCurrentItem(with: nil)
        SubtitleManager.shared.reset()
        PlayerTimeState.shared.reset()
        isPlaying = false
    }

    // MARK: - Internal Observers

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && !sec.isNaN {
                    PlayerTimeState.shared.currentTime = sec
                    SubtitleManager.shared.updateTime(sec)
                }
            }
        }
    }

    private func setupItemObservers(for item: AVPlayerItem) {
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    let d = CMTimeGetSeconds(observedItem.duration)
                    if d.isFinite && !d.isNaN && d > 2.0 && d > PlayerTimeState.shared.duration {
                        PlayerTimeState.shared.duration = d
                    }
                    self.isBuffering = false
                    if self.isPlaying {
                        self.player.play()
                        self.player.rate = self.playbackRate
                    }
                case .failed:
                    self.isPlaying = false
                    let errDesc = observedItem.error?.localizedDescription ?? "Unknown AVPlayerItem error"
                    print("[AVPlayerItem] Failed error: \(errDesc)")
                    MediaCoordinator.shared.log("❌ AVPlayer item failed: \(errDesc)", level: .error)
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
                guard self != nil else { return }
                if let range = observedItem.loadedTimeRanges.first?.timeRangeValue {
                    let start = CMTimeGetSeconds(range.start)
                    let dur = CMTimeGetSeconds(range.duration)
                    if start.isFinite && dur.isFinite && !start.isNaN && !dur.isNaN {
                        PlayerTimeState.shared.loadedDuration = max(PlayerTimeState.shared.loadedDuration, start + dur)
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
    }

    private func cleanupItemObservers() {
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
