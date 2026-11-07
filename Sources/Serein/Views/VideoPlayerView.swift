import SwiftUI
import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// Cinematic Apple QuickTime Video Player Canvas (macOS 26+ Liquid Glass Era)
/// Features decoupled timeline rendering, native NSMenu options, subtitles overlay, and dynamic fullscreen layout.
public struct VideoPlayerView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject var playerController: PlayerController
    @ObservedObject var subtitleManager = SubtitleManager.shared
    @ObservedObject var captionAppearance = CaptionAppearanceManager.shared
    @ObservedObject var glassSettings = LiquidGlassSettings.shared

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
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            let typeId = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.url.identifier
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                var resolvedURL: URL?
                if let url = item as? URL {
                    resolvedURL = url
                } else if let data = item as? Data {
                    resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                }
                if let url = resolvedURL {
                    Task { @MainActor in
                        if url.isFileURL {
                            coordinator.openLocalFile(url: url)
                        } else {
                            coordinator.openOnlineURL(string: url.absoluteString)
                        }
                    }
                }
            }
            return true
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
    }

    private var isAudioMode: Bool {
        coordinator.probeResult?.isAudioOnly == true || coordinator.currentSource?.isAudioTrack == true
    }

    // MARK: - Player Canvas

    private var playerCanvas: some View {
        Group {
            if isAudioMode {
                cleanAudioPlayerView
            } else {
                videoCanvasView
            }
        }
    }

    private var videoCanvasView: some View {
        GeometryReader { geo in
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

                // Layer 3: Subtitles / Captions (scales dynamically with screen/window size and follows ASS semantic position)
                subtitlesOverlay(viewportSize: geo.size)

                // Layer 4: Floating Liquid Glass Controls Overlay
                controlsOverlay
                    .allowsHitTesting(showControls || !playerController.isPlaying)
                    .opacity(showControls || !playerController.isPlaying ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: showControls || !playerController.isPlaying)

                // Layer 5: Resume From Timestamp Toast Banner
                resumeToastView

                // Layer 6: On-Screen HUD Notification Banner
                generalHUDView
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
    }

    // MARK: - Subtitles Overlay (Scales with Screen Size & Accessibility Settings)

    private func subtitlesOverlay(viewportSize: CGSize) -> some View {
        Group {
            if let cueText = subtitleManager.currentCueText, !cueText.isEmpty {
                let h = viewportSize.height > 0 ? viewportSize.height : 720
                let w = viewportSize.width > 0 ? viewportSize.width : 1280

                // In full screen, subtitles scale proportionally with the display height (18pt min to 48pt max)
                let dynamicBaseSize = max(18.0, min(h * 0.036, 48.0))
                let effectiveFontSize = dynamicBaseSize * captionAppearance.fontScale
                let padH = max(12.0, dynamicBaseSize * 0.55)
                let padV = max(5.0, dynamicBaseSize * 0.25)

                let letterboxBarHeight = calculateLetterboxBarHeight(viewportSize: CGSize(width: w, height: h))
                let baseBottomPadding: CGFloat = (showControls || !playerController.isPlaying) ? 104 : 36
                let effectiveBottomPadding = (subtitleManager.placement == .mediaFrame)
                    ? max(letterboxBarHeight + 36, baseBottomPadding)
                    : baseBottomPadding

                let baseTopPadding: CGFloat = (showControls || !playerController.isPlaying) ? 84 : 36
                let effectiveTopPadding = (subtitleManager.placement == .mediaFrame)
                    ? max(letterboxBarHeight + 36, baseTopPadding)
                    : baseTopPadding

                VStack {
                    if subtitleManager.currentCuePosition != .top {
                        Spacer()
                    }

                    Text(cueText)
                        .font(.system(size: effectiveFontSize, weight: .medium, design: .default))
                        .foregroundColor(captionAppearance.textColor)
                        .shadow(
                            color: captionAppearance.hasShadow ? captionAppearance.shadowColor : Color.clear,
                            radius: captionAppearance.hasShadow ? 2.0 : 0,
                            x: 0,
                            y: 1.5
                        )
                        .multilineTextAlignment(.center)
                        .lineSpacing(max(3.0, dynamicBaseSize * 0.16))
                        .padding(.horizontal, padH)
                        .padding(.vertical, padV)
                        .background(
                            RoundedRectangle(cornerRadius: captionAppearance.cornerRadius, style: .continuous)
                                .fill(captionAppearance.backgroundColor)
                        )
                        .padding(.horizontal, 48)
                        .padding(.top, subtitleManager.currentCuePosition == .top ? effectiveTopPadding : 0)
                        .padding(.bottom, subtitleManager.currentCuePosition == .bottom ? effectiveBottomPadding : 0)
                        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: subtitleManager.placement)
                        .animation(.easeInOut(duration: 0.18), value: showControls || !playerController.isPlaying)

                    if subtitleManager.currentCuePosition != .bottom {
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
    }

    /// Calculates the black letterbox bar height when video aspect does not match viewport aspect.
    private func calculateLetterboxBarHeight(viewportSize: CGSize) -> CGFloat {
        guard playerController.isLetterboxed else { return 0 }

        if let playerNSView = playerController.activePlayerNSView {
            let vr = playerNSView.playerLayer.videoRect
            if vr.height > 0 && vr.width > 0 && vr.height < viewportSize.height {
                let bar = (viewportSize.height - vr.height) / 2.0
                if bar > 0 {
                    return bar
                }
            }
        }

        let videoWidth: CGFloat
        let videoHeight: CGFloat
        if let probeW = coordinator.probeResult?.primaryVideo?.width,
           let probeH = coordinator.probeResult?.primaryVideo?.height,
           probeW > 0, probeH > 0 {
            videoWidth = CGFloat(probeW)
            videoHeight = CGFloat(probeH)
        } else if let presSize = playerController.player.currentItem?.presentationSize,
                  presSize.width > 0, presSize.height > 0 {
            videoWidth = presSize.width
            videoHeight = presSize.height
        } else {
            return 0
        }

        let videoAspect = videoWidth / max(1.0, videoHeight)
        let viewportAspect = viewportSize.width / max(1.0, viewportSize.height)

        if viewportAspect < videoAspect {
            let renderedVideoHeight = viewportSize.width / videoAspect
            return max(0, (viewportSize.height - renderedVideoHeight) / 2.0)
        }

        return 0
    }

    // MARK: - Floating Controls Overlay (Native Liquid Glass)

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // TOP BAR: Left has close button (fullscreen) / clearance (windowed) + PiP & AirPlay Video; Middle has Title; Right has Sound & AirPlay Pill Control
            HStack(spacing: 12) {
                // In full screen mode: dedicated 'X' button to quit current video and return to welcome screen!
                if isFullScreen {
                    Button(action: {
                        quitVideoAndReturnToWelcome()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(glassSettings.glass, in: Circle())
                    .help("Close Video and Return to Welcome Screen (Esc / ⌘W)")
                } else {
                    // Inset clearance for standard macOS traffic lights (only when in windowed mode!)
                    Color.clear
                        .frame(width: 68, height: 1)
                        .transition(.opacity)
                }

                // Top-Left: PiP & AirPlay Video Capsule (Video mode)
                HStack(spacing: 8) {
                    // Native Picture in Picture Button
                    Button(action: {
                        playerController.togglePictureInPicture()
                        registerUserActivity()
                    }) {
                        Image(systemName: playerController.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Picture in Picture")

                    GlassDivider(height: 14)

                    // Native macOS AirPlay Video Route Picker (Apple TV / AirPlay Display)
                    AirPlayRoutePicker(player: playerController.player, mode: .video)
                        .frame(width: 24, height: 24)
                        .help("AirPlay Video (Apple TV / External Display)")
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .glassEffect(glassSettings.glass, in: Capsule())

                Spacer(minLength: 12)

                // Top-Middle: Clean Media Title Pill (Non-interactive)
                Text(cleanMediaTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .glassEffect(glassSettings.glass, in: Capsule())
                    .frame(maxWidth: 420)
                    .allowsHitTesting(false)

                Spacer(minLength: 12)

                // Top-Right: Sound & AirPlay Audio Pill Control (macOS Sequoia Control Center style)
                soundPillControl
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
                    .help("Rewind 10 seconds (⌘←)")

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
                    .help("Forward 10 seconds (⌘→)")
                }
            }

            Spacer()

            // BOTTOM OPTIONS ROW: [WebKit Options Menu]
            HStack(alignment: .bottom) {
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
        .environment(\.colorScheme, .dark)
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
        .glassEffect(glassSettings.glass, in: Capsule())
        .help("Playback Options (Subtitles, Speed, Media Statistics)")
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(format: "%.0f", rate)
        }
        return String(format: "%g", rate)
    }

    // MARK: - Sound & AirPlay Pill Control (macOS Sequoia / iOS 18 Control Center style)

    private var soundPillControl: some View {
        HStack(spacing: 8) {
            // Mute / Speaker Icon Button
            Button(action: {
                playerController.toggleMute()
                registerUserActivity()
            }) {
                Image(systemName: volumeIconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(playerController.isMuted ? "Unmute" : "Mute")

            // Apple Native AppKit Volume Slider
            NativeSlider(
                value: Binding(
                    get: { Double(playerController.isMuted ? 0 : playerController.volume) },
                    set: { newVal in
                        playerController.isMuted = false
                        playerController.volume = Float(newVal)
                        registerUserActivity()
                    }
                ),
                in: 0.0...1.0,
                trackFillColor: .white,
                onEditingChanged: { _ in
                    registerUserActivity()
                }
            )
            .frame(width: 84, height: 20)

            GlassDivider(height: 14)

            // Native macOS AirPlay Audio Route Picker (Speakers / HomePod / AirPods)
            AirPlayRoutePicker(player: playerController.player, mode: .audio)
                .frame(width: 22, height: 22)
                .help("AirPlay Audio (HomePod / Speakers)")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .glassEffect(glassSettings.glass, in: Capsule())
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

    // MARK: - Close Media & Return to Welcome Screen

    private func quitVideoAndReturnToWelcome() {
        WindowManager.shared.transitionToMedia(isAudio: false)
        playerController.saveCurrentPosition()
        playerController.pause()
        if isFullScreen, let win = NSApp.keyWindow ?? NSApp.windows.first {
            win.toggleFullScreen(nil)
        }
        coordinator.stop()
        playerController.reset()
    }

    // MARK: - Clean Dedicated Audio Player View

    private var cleanAudioPlayerView: some View {
        ZStack {
            // Background Tap Catch for Play/Pause toggle
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1) {
                    playerController.togglePlayPause()
                    registerUserActivity()
                }

            VStack(spacing: 0) {
                // Top Header Row: Traffic Lights clearance on left, Sound Pill on right
                HStack {
                    if isFullScreen {
                        Button(action: quitVideoAndReturnToWelcome) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(glassSettings.glass, in: Circle())
                        .help("Close Audio (Esc / ⌘W)")
                    }

                    Spacer()

                    // Necessary Control: Sound & AirPlay Audio Control Pill
                    soundPillControl
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 12)

                // Center: Unobscured Album Artwork & Track Metadata
                VStack(spacing: 16) {
                    // 1. Cover Art (200x200, rounded continuous, subtle border & shadow)
                    ZStack {
                        if let art = coordinator.currentArtwork {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 200, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.55), radius: 26, x: 0, y: 10)
                        } else {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.25), Color.black.opacity(0.60)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 200, height: 200)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .shadow(color: Color.blue.opacity(0.20), radius: 24, x: 0, y: 8)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 56, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                )
                        }
                    }

                    // 2. Track Metadata: Title, Artist — Album, Codec Details
                    VStack(spacing: 5) {
                        Text(audioTrackTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 24)

                        if let artistAlbum = audioArtistAndAlbumString {
                            Text(artistAlbum)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                                .padding(.horizontal, 24)
                        }

                        if let probe = coordinator.probeResult {
                            HStack(spacing: 6) {
                                Text(probe.containerFormat.description)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.18))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)

                                if let audio = probe.primaryAudio {
                                    Text(audio.audioDetailsString ?? audio.codecName.uppercased())
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.55))
                                }
                            }
                            .padding(.top, 3)
                        }
                    }
                }

                Spacer(minLength: 14)

                // Transport Controls: [Rewind 10] [Play / Pause] [Forward 10]
                HStack(spacing: 28) {
                    Button(action: {
                        playerController.seekRelative(seconds: -10)
                        registerUserActivity()
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Rewind 10s (⌘←)")

                    Button(action: {
                        playerController.togglePlayPause()
                        registerUserActivity()
                    }) {
                        Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 64, height: 64)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: Color.white.opacity(0.28), radius: 14, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .help(playerController.isPlaying ? "Pause (Space)" : "Play (Space)")

                    Button(action: {
                        playerController.seekRelative(seconds: 10)
                        registerUserActivity()
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Forward 10s (⌘→)")
                }

                Spacer(minLength: 16)

                // Bottom Timeline Scrubber Shelf
                TimelineScrubberShelf(
                    onSeek: { target in
                        playerController.seek(to: target)
                    },
                    onActivity: {
                        registerUserActivity()
                    }
                )
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }

            // Resume & HUD Overlays
            resumeToastView
            generalHUDView
        }
        .environment(\.colorScheme, .dark)
    }

    private var audioTrackTitle: String {
        if let probe = coordinator.probeResult, let t = probe.trackTitle, !t.isEmpty {
            return t
        }
        if let online = coordinator.extractedOnlineInfo {
            return online.title
        }
        if let cur = coordinator.currentSource {
            return cur.displayName
        }
        return "Audio Track"
    }

    private var audioArtistAndAlbumString: String? {
        if let probe = coordinator.probeResult {
            let artist = probe.trackArtist
            let album = probe.trackAlbum
            if let artist = artist, !artist.isEmpty, let album = album, !album.isEmpty {
                return "\(artist) — \(album)"
            } else if let artist = artist, !artist.isEmpty {
                return artist
            } else if let album = album, !album.isEmpty {
                return album
            }
        }
        if let uploader = coordinator.extractedOnlineInfo?.uploader, !uploader.isEmpty {
            return uploader
        }
        return nil
    }

    // MARK: - Resume Toast View

    @ViewBuilder
    private var resumeToastView: some View {
        if let resumeText = playerController.resumeNotificationText {
            VStack {
                HStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(resumeText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Button(action: {
                        playerController.restartFromBeginning()
                    }) {
                        Text("Restart")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(Color.cyan)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            playerController.resumeNotificationText = nil
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .init(white: 0.12, alpha: 0.90)))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                .padding(.top, (showControls || !playerController.isPlaying) ? 66 : 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(150)

                Spacer()
            }
        }
    }

    // MARK: - General On-Screen Notification HUD View

    @ViewBuilder
    private var generalHUDView: some View {
        if let msg = playerController.hudMessage {
            VStack {
                HStack(spacing: 8) {
                    if let icon = playerController.hudIconName {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .init(white: 0.12, alpha: 0.92)))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                .padding(.top, (showControls || !playerController.isPlaying) ? 66 : 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(160)

                Spacer()
            }
            .allowsHitTesting(false)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: playerController.hudMessage)
        }
    }

    // MARK: - Loading View (Always Cinematic Dark with High-Contrast Typography)

    private func loadingView(message: String) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.15)
                    .colorInvert() // Guarantees bright white spinner against dark glass

                Text(message)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .init(white: 0.14, alpha: 0.88)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Error View (Always Cinematic Dark)

    private func errorView(message: String) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                HStack(spacing: 12) {
                    Button("Choose File", action: onOpenFile)
                        .buttonStyle(LiquidCapsuleButtonStyle(isProminent: true))

                    Button("Open URL", action: onOpenURL)
                        .buttonStyle(LiquidCapsuleButtonStyle())
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .init(white: 0.14, alpha: 0.90)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
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
            .glassEffect(glassSettings.glass, in: Circle())
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
            .glassEffect(glassSettings.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    @State private var isDraggingScrubber = false
    @State private var wasPlayingBeforeScrub = false
    @State private var scrubTime: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Elapsed Time
            Text(formatTime(currentTimeValue))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(minWidth: 46, alignment: .leading)

            // Apple Native AppKit Timeline Scrubber
            NativeSlider(
                value: Binding(
                    get: { isDraggingScrubber ? scrubTime : timeState.currentTime },
                    set: { target in
                        scrubTime = target
                        onSeek(target)
                        onActivity()
                    }
                ),
                in: 0.0...max(timeState.duration, 1.0),
                trackFillColor: .white,
                onEditingChanged: { isEditing in
                    if isEditing {
                        isDraggingScrubber = true
                        wasPlayingBeforeScrub = PlayerController.shared.isPlaying
                        if wasPlayingBeforeScrub {
                            PlayerController.shared.pause()
                        }
                    } else {
                        isDraggingScrubber = false
                        onSeek(scrubTime)
                        if wasPlayingBeforeScrub {
                            PlayerController.shared.play()
                            wasPlayingBeforeScrub = false
                        }
                    }
                    onActivity()
                }
            )
            .frame(height: 20)

            // Remaining Time
            Text(formatRemainingTime())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .glassEffect(LiquidGlassSettings.shared.glass, in: Capsule())
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
