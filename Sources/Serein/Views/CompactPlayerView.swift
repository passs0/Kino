import SwiftUI
import AppKit

/// Sleek macOS Liquid Glass Compact MiniPlayer for Music and Background Audio.
public struct CompactPlayerView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject var playerController: PlayerController
    @ObservedObject var timeState = PlayerTimeState.shared
    @ObservedObject var windowManager = WindowManager.shared

    @State private var isDraggingTimeline = false
    @State private var dragScrubTime: Double = 0

    public init(coordinator: MediaCoordinator, playerController: PlayerController) {
        self.coordinator = coordinator
        self.playerController = playerController
    }

    private var activeDuration: Double {
        if let kd = coordinator.knownDuration, kd > 0 { return kd }
        if timeState.duration > 0 { return timeState.duration }
        return 0
    }

    private var activeCurrentTime: Double {
        isDraggingTimeline ? dragScrubTime : timeState.currentTime
    }

    private var displayTitle: String {
        coordinator.probeResult?.trackTitle ?? coordinator.currentSource?.displayName ?? "Audio Track"
    }

    private var displayArtistAndAlbum: String {
        if let artist = coordinator.probeResult?.trackArtist {
            if let album = coordinator.probeResult?.trackAlbum {
                return "\(artist) — \(album)"
            }
            return artist
        }
        return "Unknown Artist"
    }

    private var codecLabel: String {
        if let audio = coordinator.probeResult?.primaryAudio {
            let codec = audio.codecName.uppercased()
            if let rate = audio.sampleRate, rate > 0 {
                let khz = String(format: "%.1f kHz", Double(rate) / 1000.0)
                return "\(codec) · \(khz)"
            }
            return codec
        }
        return "AUDIO"
    }

    public var body: some View {
        ZStack {
            // Dark liquid glass base
            Color(white: 0.08)
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                // Top Utility Bar: Traffic light breathing room on left, Pin & Expand on right
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 68)

                    Spacer()

                    // Always-on-Top Pin Button
                    Button(action: {
                        windowManager.togglePinAlwaysOnTop()
                    }) {
                        Image(systemName: windowManager.isPinnedAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(windowManager.isPinnedAlwaysOnTop ? .yellow : .white.opacity(0.70))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(windowManager.isPinnedAlwaysOnTop ? 0.18 : 0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(windowManager.isPinnedAlwaysOnTop ? "Unpin from Always-on-Top" : "Pin Always-on-Top")

                    // Expand to Full Canvas Button
                    Button(action: {
                        windowManager.setMiniPlayer(false)
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.70))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Expand to Full Player (⌥⌘M)")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Main Content: Cover Art + Track Details & Controls
                HStack(spacing: 12) {
                    // Artwork Squircle (76×76)
                    ZStack {
                        if let art = coordinator.currentArtwork {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.40), radius: 8, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 76, height: 76)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

                            Image(systemName: "music.note")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))
                        }
                    }

                    // Metadata + Timeline + Controls Column
                    VStack(alignment: .leading, spacing: 4) {
                        // Title & Formatted Time (Clean Proportional Typography)
                        HStack(alignment: .firstTextBaseline) {
                            Text(displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            Text(timeDisplayText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                        }

                        // Artist / Album & Codec Badge
                        HStack(spacing: 6) {
                            Text(displayArtistAndAlbum)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .lineLimit(1)

                            Text(codecLabel)
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .foregroundColor(.white.opacity(0.85))
                        }

                        // Highly Responsive Native AppKit Timeline Scrubber
                        MiniScrubberRepresentable(
                            currentTime: activeCurrentTime,
                            duration: activeDuration,
                            onSeek: { target in
                                playerController.seek(to: target)
                            },
                            onScrubbingChanged: { isScrubbing, time in
                                isDraggingTimeline = isScrubbing
                                dragScrubTime = time
                            }
                        )
                        .frame(height: 24)

                        // Transport Controls Row
                        HStack(spacing: 14) {
                            Button(action: {
                                playerController.seekRelative(seconds: -10)
                            }) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Rewind 10 seconds")

                            Button(action: {
                                playerController.togglePlayPause()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 26, height: 26)

                                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: playerController.isPlaying ? 0 : 0.5)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(playerController.isPlaying ? "Pause (Space)" : "Play (Space)")

                            Button(action: {
                                playerController.seekRelative(seconds: 10)
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Fast Forward 10 seconds")

                            Spacer()

                            // Native Mini Volume Control
                            HStack(spacing: 5) {
                                Button(action: {
                                    playerController.isMuted.toggle()
                                }) {
                                    Image(systemName: playerController.isMuted || playerController.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.70))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)

                                MiniVolumeSliderRepresentable(
                                    volume: playerController.volume,
                                    isMuted: playerController.isMuted,
                                    onVolumeChanged: { newVol in
                                        playerController.volume = newVol
                                        if playerController.isMuted { playerController.isMuted = false }
                                    }
                                )
                                .frame(width: 44, height: 18)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 420, maxWidth: 620, minHeight: 130, maxHeight: 160)
    }

    private var timeDisplayText: String {
        let cur = formatSeconds(activeCurrentTime)
        let dur = formatSeconds(activeDuration)
        return "\(cur) / \(dur)"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let secs = total % 60
        let mins = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}

// MARK: - Native AppKit Mini Scrubber (Immune to Window Background Dragging)

public struct MiniScrubberRepresentable: NSViewRepresentable {
    var currentTime: Double
    var duration: Double
    var onSeek: (Double) -> Void
    var onScrubbingChanged: ((Bool, Double) -> Void)?

    public func makeNSView(context: Context) -> MiniScrubberNSView {
        let view = MiniScrubberNSView()
        view.currentTime = currentTime
        view.duration = duration
        view.onSeek = onSeek
        view.onScrubbingChanged = onScrubbingChanged
        return view
    }

    public func updateNSView(_ nsView: MiniScrubberNSView, context: Context) {
        nsView.currentTime = currentTime
        nsView.duration = duration
        nsView.onSeek = onSeek
        nsView.onScrubbingChanged = onScrubbingChanged
        nsView.needsDisplay = true
    }
}

public final class MiniScrubberNSView: NSView {
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var onSeek: ((Double) -> Void)?
    public var onScrubbingChanged: ((Bool, Double) -> Void)?

    private var isDragging = false
    private var dragTime: Double = 0
    private var wasPlayingBeforeScrub = false

    // Prevent macOS from intercepting timeline scrubbing as a window drag
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackHeight: CGFloat = 5.5
        let trackY = (bounds.height - trackHeight) / 2.0
        let trackRect = CGRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)

        // 1. Unplayed continuous background rail
        let bgPath = CGPath(roundedRect: trackRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // 2. Played rail
        let activeTime = isDragging ? dragTime : currentTime
        let progress = duration > 0 ? max(0, min(1.0, activeTime / duration)) : 0
        let playedWidth = bounds.width * CGFloat(progress)

        let thumbWidth: CGFloat = isDragging ? 24.0 : 20.0
        let thumbHeight: CGFloat = isDragging ? 19.5 : 16.0
        let thumbX = max(0, min(bounds.width - thumbWidth, playedWidth - (thumbWidth / 2.0)))
        let thumbY = (bounds.height - thumbHeight) / 2.0
        let thumbRect = CGRect(x: thumbX, y: thumbY, width: thumbWidth, height: thumbHeight)

        if playedWidth > 0 {
            // When scrubbing, outer played rail terminates cleanly at left edge of thumb
            let playedOuterWidth = isDragging ? min(playedWidth, thumbX + 2) : playedWidth
            let playedRect = CGRect(x: 0, y: trackY, width: max(trackHeight, playedOuterWidth), height: trackHeight)
            let playedPath = CGPath(roundedRect: playedRect, cornerWidth: trackHeight / 2, cornerHeight: trackHeight / 2, transform: nil)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.addPath(playedPath)
            ctx.fillPath()
        }

        // 3. Native Apple Scrubber Thumb (Resting white capsule -> Scrubbing Liquid Glass Lens)
        QuickTimeLiquidGlassRenderer.draw(
            in: ctx,
            isScrubbing: isDragging,
            thumbRect: thumbRect,
            trackY: trackY,
            trackHeight: trackHeight
        )
    }

    public override func mouseDown(with event: NSEvent) {
        if !isDragging {
            wasPlayingBeforeScrub = PlayerController.shared.isPlaying
            if wasPlayingBeforeScrub {
                PlayerController.shared.pause()
            }
        }
        updateFromEvent(event, isFinal: false)
    }

    public override func mouseDragged(with event: NSEvent) {
        updateFromEvent(event, isFinal: false)
    }

    public override func mouseUp(with event: NSEvent) {
        updateFromEvent(event, isFinal: true)
        if wasPlayingBeforeScrub {
            PlayerController.shared.play()
            wasPlayingBeforeScrub = false
        }
    }

    private func updateFromEvent(_ event: NSEvent, isFinal: Bool) {
        let loc = convert(event.locationInWindow, from: nil)
        let pct = max(0, min(1.0, Double(loc.x / bounds.width)))
        let targetTime = pct * (duration > 0 ? duration : 1.0)

        if !isFinal {
            isDragging = true
            dragTime = targetTime
            onScrubbingChanged?(true, targetTime)
            onSeek?(targetTime)
            needsDisplay = true
        } else {
            isDragging = false
            onScrubbingChanged?(false, targetTime)
            onSeek?(targetTime)
            needsDisplay = true
        }
    }
}

// MARK: - Native AppKit Mini Volume Slider (Immune to Window Background Dragging)

public struct MiniVolumeSliderRepresentable: NSViewRepresentable {
    var volume: Float
    var isMuted: Bool
    var onVolumeChanged: (Float) -> Void

    public func makeNSView(context: Context) -> MiniVolumeSliderNSView {
        let view = MiniVolumeSliderNSView()
        view.volume = volume
        view.isMuted = isMuted
        view.onVolumeChanged = onVolumeChanged
        return view
    }

    public func updateNSView(_ nsView: MiniVolumeSliderNSView, context: Context) {
        nsView.volume = volume
        nsView.isMuted = isMuted
        nsView.onVolumeChanged = onVolumeChanged
        nsView.needsDisplay = true
    }
}

public final class MiniVolumeSliderNSView: NSView {
    public var volume: Float = 1.0
    public var isMuted: Bool = false
    public var onVolumeChanged: ((Float) -> Void)?

    public override var mouseDownCanMoveWindow: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let trackHeight: CGFloat = 3.5
        let trackY = (bounds.height - trackHeight) / 2.0
        let trackRect = NSRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)

        let bgPath = NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        NSColor.white.withAlphaComponent(0.18).setFill()
        bgPath.fill()

        let activeVol = isMuted ? 0 : CGFloat(volume)
        let volWidth = bounds.width * max(0, min(1.0, activeVol))
        if volWidth > 0 {
            let volRect = NSRect(x: 0, y: trackY, width: max(trackHeight, volWidth), height: trackHeight)
            let volPath = NSBezierPath(roundedRect: volRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
            NSColor.white.setFill()
            volPath.fill()
        }
    }

    public override func mouseDown(with event: NSEvent) {
        updateFromEvent(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        updateFromEvent(event)
    }

    private func updateFromEvent(_ event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let pct = Float(max(0, min(1.0, loc.x / bounds.width)))
        volume = pct
        onVolumeChanged?(pct)
        needsDisplay = true
    }
}
