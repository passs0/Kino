import SwiftUI
import AppKit
import AVFoundation
import AVKit

/// Cinematic Apple QuickTime Video Player Canvas (macOS 26+ Liquid Glass Era)
/// Features decoupled timeline rendering, native NSMenu options, subtitles overlay, and dynamic fullscreen layout.
public struct VideoPlayerView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject var playerController: PlayerController
    @ObservedObject var subtitleManager = SubtitleManager.shared
    @ObservedObject var captionAppearance = CaptionAppearanceManager.shared

    var onOpenFile: () -> Void
    var onOpenURL: () -> Void

    @State private var showControls = true
    @State private var hideTimer: Task<Void, Never>?
    @State private var isFullScreen = false

    public init(
        coordinator: MediaCoordinator,
        playerController: PlayerController,
        onOpenFile: @escaping () -> Void,
        onOpenURL: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.playerController = playerController
        self.onOpenFile = onOpenFile
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        ZStack {
            switch coordinator.state {
            case .idle:
                idleStateView

            case .probing(let msg), .extractingOnline(let msg), .preparingStream(let msg):
                loadingView(message: msg)

            case .ready:
                playerCanvas

            case .error(let errMsg):
                errorView(message: errMsg)
            }
        }
        .onAppear {
            if let win = NSApp.keyWindow {
                isFullScreen = win.styleMask.contains(.fullScreen)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                isFullScreen = false
            }
        }
        .onChange(of: coordinator.activePlayableURL) { _, newURL in
            if let url = newURL {
                let expDuration = coordinator.knownDuration
                playerController.load(url: url, expectedDuration: expDuration)
            } else {
                playerController.reset()
            }
        }
        .onChange(of: coordinator.probeResult) { _, newProbe in
            if let d = newProbe?.duration, d > 0 {
                playerController.setKnownDuration(d)
            }
        }
        .onChange(of: coordinator.extractedOnlineInfo?.duration) { _, newDuration in
            if let d = newDuration, d > 0 {
                playerController.setKnownDuration(d)
            }
        }
    }

    // MARK: - Player Canvas

    private var playerCanvas: some View {
        ZStack {
            // Layer 1: Hardware-Accelerated Video Surface
            NativePlayerView(player: playerController.player) { droppedURL in
                coordinator.openLocalFile(url: droppedURL)
            }
            .ignoresSafeArea()

            // Layer 2: Background Tap Catch (only for empty canvas clicks, beneath interactive controls)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    toggleFullscreen()
                }
                .onTapGesture(count: 1) {
                    playerController.togglePlayPause()
                    registerUserActivity()
                }

            // Layer 3: Subtitles / Captions (renders non-interactively over video)
            subtitlesOverlay

            // Layer 4: Floating Liquid Glass Controls Overlay
            controlsOverlay
                .allowsHitTesting(showControls || !playerController.isPlaying)
                .opacity(showControls || !playerController.isPlaying ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: showControls || !playerController.isPlaying)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                registerUserActivity()
            case .ended:
                if playerController.isPlaying {
                    scheduleControlsFade(afterSeconds: 1.0)
                }
            }
        }
    }

    // MARK: - Subtitles Overlay (System Settings Accessibility Captions)

    private var subtitlesOverlay: some View {
        Group {
            if let cueText = subtitleManager.currentCueText, !cueText.isEmpty {
                VStack {
                    Spacer()
                    Text(cueText)
                        .font(.system(size: 20 * captionAppearance.fontScale, weight: .medium, design: .default))
                        .foregroundColor(captionAppearance.textColor)
                        .shadow(
                            color: captionAppearance.hasShadow ? captionAppearance.shadowColor : Color.clear,
                            radius: captionAppearance.hasShadow ? 2.0 : 0,
                            x: 0,
                            y: 1.5
                        )
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: captionAppearance.cornerRadius, style: .continuous)
                                .fill(captionAppearance.backgroundColor)
                        )
                        .padding(.horizontal, 48)
                        .padding(.bottom, (showControls || !playerController.isPlaying) ? 104 : 36)
                        .animation(.easeInOut(duration: 0.18), value: showControls || !playerController.isPlaying)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Floating Controls Overlay (Native Liquid Glass)

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // TOP BAR: Left has traffic lights (windowed) / far-left (fullscreen) + PiP & AirPlay; Right has Volume
            HStack(spacing: 12) {
                // Inset clearance for standard macOS traffic lights (only when in windowed mode!)
                if !isFullScreen {
                    Color.clear
                        .frame(width: 68, height: 1)
                        .transition(.opacity)
                }

                // Top-Left: PiP & AirPlay Capsule
                HStack(spacing: 8) {
                    // Native Picture in Picture Button
                    Button(action: {
                        playerController.togglePictureInPicture()
                        registerUserActivity()
                    }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Picture in Picture")

                    GlassDivider(height: 14)

                    // Native macOS AirPlay Route Picker
                    AirPlayRoutePicker(player: playerController.player)
                        .frame(width: 26, height: 26)
                        .help("AirPlay")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .glassEffect(Glass.regular, in: Capsule())

                Spacer()

                // Top-Right: Volume Slider Capsule
                volumeCapsule
            }
            .padding(.top, 16)
            .padding(.horizontal, 20)

            Spacer()

            // CENTER TRANSPORT CONTROLS: [Rewind 10]  [Play / Pause]  [Forward 10]
            GlassEffectContainer {
                HStack(spacing: 28) {
                    LiquidCircleButton(icon: "gobackward.10", size: 54, iconSize: 20) {
                        playerController.seekRelative(seconds: -10)
                        registerUserActivity()
                    }
                    .help("Rewind 10 seconds")

                    LiquidCircleButton(
                        icon: playerController.isPlaying ? "pause.fill" : "play.fill",
                        size: 80,
                        iconSize: 32,
                        isBold: true
                    ) {
                        playerController.togglePlayPause()
                        registerUserActivity()
                    }
                    .help(playerController.isPlaying ? "Pause (Space)" : "Play (Space)")

                    LiquidCircleButton(icon: "goforward.10", size: 54, iconSize: 20) {
                        playerController.seekRelative(seconds: 10)
                        registerUserActivity()
                    }
                    .help("Forward 10 seconds")
                }
            }

            Spacer()

            // BOTTOM INFO ROW: [Title] ... [WebKit Options Menu]
            HStack(alignment: .bottom) {
                // Clean Media Title Pill (Non-interactive)
                Text(cleanMediaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(Glass.regular, in: Capsule())

                Spacer()

                // WebKit HTML5 Options Capsule (Subtitles, Speed, Media Statistics)
                webKitOptionsCapsule
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // BOTTOM TIMELINE SCRUBBER SHELF
            TimelineScrubberShelf(
                onSeek: { target in
                    playerController.seek(to: target)
                },
                onActivity: {
                    registerUserActivity()
                }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - WebKit HTML5 Style Options Capsule (Single Source for Options & Stats)

    private var webKitOptionsCapsule: some View {
        Button(action: {
            OptionsMenuPresenter.shared.show()
            registerUserActivity()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                if playerController.playbackRate != 1.0 {
                    Text("\(formatRate(Double(playerController.playbackRate)))x")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.accentColor)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular, in: Capsule())
        .help("Playback Options (Subtitles, Speed, Media Statistics)")
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(format: "%.0f", rate)
        }
        return String(format: "%g", rate)
    }

    // MARK: - Volume Capsule

    private var volumeCapsule: some View {
        HStack(spacing: 8) {
            // Interactive Slider Bar
            GeometryReader { geo in
                let width = geo.size.width
                let currentVal = Double(playerController.isMuted ? 0 : playerController.volume)
                let fillWidth = max(0, min(width, width * currentVal))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: fillWidth, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, fillWidth - 4.5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            playerController.isMuted = false
                            playerController.volume = Float(fraction)
                            registerUserActivity()
                        }
                )
            }
            .frame(width: 90, height: 20)

            // Mute / Speaker Icon
            Button(action: {
                playerController.toggleMute()
                registerUserActivity()
            }) {
                Image(systemName: volumeIconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(playerController.isMuted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(Glass.regular, in: Capsule())
    }

    private var volumeIconName: String {
        if playerController.isMuted || playerController.volume == 0 {
            return "speaker.slash.fill"
        }
        if playerController.volume < 0.33 {
            return "speaker.wave.1.fill"
        }
        if playerController.volume < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    // MARK: - Dynamic Title

    private var cleanMediaTitle: String {
        var raw = ""
        if let online = coordinator.extractedOnlineInfo {
            raw = online.title
        } else if let probe = coordinator.probeResult {
            if let tagTitle = probe.tags["title"] ?? probe.tags["TITLE"], !tagTitle.isEmpty {
                raw = tagTitle
            } else {
                raw = probe.filename
            }
        } else if let source = coordinator.currentSource {
            raw = source.displayName
        } else {
            return "Serein Player"
        }

        // If title is a raw URL or query-string download link
        if raw.contains("://") || raw.hasPrefix("?") || raw.contains("download?") || raw.contains("&fid=") {
            if let host = coordinator.currentSource?.rawURL.host ?? URL(string: raw)?.host {
                return "Online Stream (\(host))"
            } else {
                return "Online Stream"
            }
        }

        if let last = raw.split(separator: "/").last { raw = String(last) }
        if let dot = raw.lastIndex(of: "."), dot > raw.startIndex {
            let ext = raw[dot...].lowercased()
            if [".mkv", ".mp4", ".mov", ".webm", ".avi", ".ts", ".flv"].contains(ext) {
                raw = String(raw[..<dot])
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\s*\[[a-zA-Z0-9_-]{8,16}\]"#) {
            raw = regex.stringByReplacingMatches(in: raw, options: [], range: NSRange(location: 0, length: raw.utf16.count), withTemplate: "")
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Controls Visibility & Fullscreen

    private func registerUserActivity() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = true
        }
        NSCursor.unhide()

        hideTimer?.cancel()
        hideTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if playerController.isPlaying {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showControls = false
                    }
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
    }

    private func scheduleControlsFade(afterSeconds: Double) {
        hideTimer?.cancel()
        hideTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if playerController.isPlaying {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showControls = false
                    }
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
    }

    private func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
        registerUserActivity()
    }

    // MARK: - Loading View

    private func loadingView(message: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.1)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(24)
        .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Button("Choose File", action: onOpenFile)
                    .buttonStyle(LiquidCapsuleButtonStyle(isProminent: true))

                Button("Open URL", action: onOpenURL)
                    .buttonStyle(LiquidCapsuleButtonStyle())
            }
        }
        .padding(28)
        .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Minimalist Idle State (Centered Native Window Background + Apple Minimalism)

    private var idleStateView: some View {
        VStack(spacing: 20) {
            // Elegant Liquid Glass Play Orb (System Neutral, No hardcoded blue ball)
            ZStack {
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
                    .frame(width: 62, height: 62)

                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.primary)
                    .offset(x: 2)
            }
            .glassEffect(Glass.regular, in: Circle())
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)

            VStack(spacing: 4) {
                Text("Serein")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                Text("Universal Hardware-Accelerated Video Player")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }

            // Minimalist Drop Target Card
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.secondary)

                Text("Drop Any Video Here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text("MKV · MP4 · MOV · WebM · AVI · TS · HLS · Streams")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button(action: onOpenFile) {
                        Label("Open File…", systemImage: "folder")
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle(isProminent: false))

                    Button(action: onOpenURL) {
                        Label("Open URL…", systemImage: "globe")
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle(isProminent: false))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
            .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }
}

// MARK: - Decoupled Timeline Scrubber Shelf (High Performance)

struct TimelineScrubberShelf: View {
    @ObservedObject var timeState = PlayerTimeState.shared
    var onSeek: (Double) -> Void
    var onActivity: () -> Void

    @State private var isScrubberHovered = false
    @State private var isDraggingScrubber = false
    @State private var scrubTime: Double = 0
    @State private var hoverLocationX: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // Elapsed Time
            Text(formatTime(currentTimeValue))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .monospacedDigit()
                .frame(minWidth: 46, alignment: .leading)

            // Interactive Progress Bar
            GeometryReader { geo in
                let width = geo.size.width
                let maxDuration = max(timeState.duration, 1.0)
                let currentVal = isDraggingScrubber ? scrubTime : timeState.currentTime
                let playedFraction = max(0.0, min(1.0, currentVal / maxDuration))
                let bufferFraction = max(0.0, min(1.0, timeState.loadedDuration / maxDuration))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 4.5)

                    Capsule()
                        .fill(Color.white.opacity(0.40))
                        .frame(width: width * bufferFraction, height: 4.5)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: width * playedFraction, height: 4.5)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .offset(x: max(0, width * playedFraction - 5.5))
                        .opacity(isScrubberHovered || isDraggingScrubber ? 1 : 0.8)

                    // Floating Hover Tooltip
                    if isScrubberHovered && !isDraggingScrubber && width > 0 {
                        let hoverFraction = max(0.0, min(1.0, hoverLocationX / width))
                        let hoverSec = hoverFraction * maxDuration

                        Text(formatTime(hoverSec))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .glassEffect(Glass.regular, in: Capsule())
                            .offset(x: max(0, min(width - 45, hoverLocationX - 22)), y: -24)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingScrubber = true
                            let fraction = max(0.0, min(1.0, value.location.x / width))
                            scrubTime = fraction * maxDuration
                            onActivity()
                        }
                        .onEnded { value in
                            let fraction = max(0.0, min(1.0, value.location.x / width))
                            let target = fraction * maxDuration
                            onSeek(target)
                            isDraggingScrubber = false
                            onActivity()
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        isScrubberHovered = true
                        hoverLocationX = loc.x
                    case .ended:
                        isScrubberHovered = false
                    }
                }
            }
            .frame(height: 24)

            // Remaining Time
            Text(formatRemainingTime())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .monospacedDigit()
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .glassEffect(Glass.regular, in: Capsule())
    }

    private var currentTimeValue: Double {
        isDraggingScrubber ? scrubTime : timeState.currentTime
    }

    private func formatRemainingTime() -> String {
        let maxD = timeState.duration
        let cur = currentTimeValue
        if maxD > 0 {
            let rem = max(0, maxD - cur)
            return "-\(formatTime(rem))"
        }
        return "--:--"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
