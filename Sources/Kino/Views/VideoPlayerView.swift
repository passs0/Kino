import SwiftUI
import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// Apple QuickTime Player Aesthetic Media Canvas
/// Features a single unified floating HUD bar, Apple-native controls,
/// document proxy integration, accessibility subtitles, and smooth aspect-ratio transitions.
public struct VideoPlayerView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject var playerController: PlayerController
    @ObservedObject var subtitleManager = SubtitleManager.shared
    @ObservedObject var captionAppearance = CaptionAppearanceManager.shared

    var onOpenFile: () -> Void
    var onOpenURL: () -> Void

    @State private var showControls = true
    @State private var isHoveringOverControls = false
    @State private var hideTimer: Task<Void, Never>?
    @State private var isFullScreen = false
    @State private var isDraggingScrubber = false
    @State private var wasPlayingBeforeScrub = false
    @State private var scrubTime: Double = 0
    @State private var transientFeedbackIcon: String? = nil
    @State private var transientFeedbackOpacity: Double = 0.0
    @State private var isDropTargeted = false
    @State private var recentDocuments: [URL] = []

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .probing(let msg), .extractingOnline(let msg), .preparingStream(let msg):
                loadingView(message: msg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .ready:
                playerCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .error(let errMsg):
                errorView(message: errMsg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
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
                        let subExts = ["srt", "vtt", "ass", "ssa", "sub", "lrc"]
                        if url.isFileURL && subExts.contains(url.pathExtension.lowercased()) {
                            SubtitleManager.shared.loadExternalSubtitle(from: url)
                        } else if url.isFileURL {
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
            recentDocuments = NSDocumentController.shared.recentDocumentURLs
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

    // MARK: - Player Canvas (Unified Media Surface for Video and Audio)

    private var playerCanvas: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Hardware-Accelerated Video Surface OR Dedicated Audio Presentation
                if isAudioMode {
                    audioArtworkAndMetadataView
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    NativePlayerView(player: playerController.player) { droppedURL in
                        let subExts = ["srt", "vtt", "ass", "ssa", "sub", "lrc"]
                        if droppedURL.isFileURL && subExts.contains(droppedURL.pathExtension.lowercased()) {
                            SubtitleManager.shared.loadExternalSubtitle(from: droppedURL)
                        } else {
                            coordinator.openLocalFile(url: droppedURL)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
                }

                // Layer 2: Background Tap Catch (Single tap: play/pause with transient glyph; Double tap: fullscreen)
                if !isAudioMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .padding(6)
                        .onTapGesture(count: 2) {
                            toggleFullscreen()
                        }
                        .onTapGesture(count: 1) {
                            playerController.togglePlayPause()
                            registerUserActivity()
                            showTransientFeedback(isPlaying: playerController.isPlaying)
                        }
                }

                // Layer 3: Subtitles / Captions
                if !isAudioMode {
                    subtitlesOverlay(viewportSize: geo.size)
                }

                // Layer 4: Transient Play / Pause Center Flash Indicator
                if !isAudioMode, let icon = transientFeedbackIcon, transientFeedbackOpacity > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.60))
                            .frame(width: 76, height: 76)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: icon == "play.fill" ? 3 : 0)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 18)
                    }
                    .opacity(transientFeedbackOpacity)
                    .scaleEffect(transientFeedbackOpacity > 0 ? 1.0 : 0.85)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: transientFeedbackOpacity)
                    .allowsHitTesting(false)
                }

                // Layer 5: Controls Overlay (The Single QuickTime Floating HUD in Video; Clean Card in Audio)
                if !isAudioMode {
                    VStack {
                        Spacer()
                            .allowsHitTesting(false)

                        quickTimeFloatingHUD(availableWidth: geo.size.width)
                            .padding(.horizontal, max(12, min(24, geo.size.width * 0.04)))
                            .padding(.bottom, max(14, min(24, geo.size.height * 0.04)))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(showControls || !playerController.isPlaying)
                    .opacity(showControls || !playerController.isPlaying ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.22), value: showControls || !playerController.isPlaying)
                }

                // Layer 6: Resume From Timestamp Toast Banner
                resumeToastView

                // Layer 7: On-Screen HUD Notification Banner
                generalHUDView
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    registerUserActivity()
                case .ended:
                    if playerController.isPlaying && !isAudioMode && !isHoveringOverControls {
                        scheduleControlsFade(afterSeconds: 1.5)
                    }
                }
            }
        }
    }

    // MARK: - Subtitles Overlay (Apple MediaAccessibility Consistent)

    private func subtitlesOverlay(viewportSize: CGSize) -> some View {
        Group {
            if let cueText = subtitleManager.currentCueText, !cueText.isEmpty {
                let h = viewportSize.height > 0 ? viewportSize.height : 720
                let dynamicBaseSize = max(18.0, min(h * 0.036, 48.0))
                let effectiveFontSize = dynamicBaseSize * captionAppearance.fontScale
                let padH = max(12.0, dynamicBaseSize * 0.55)
                let padV = max(5.0, dynamicBaseSize * 0.25)

                let letterboxBarHeight = calculateLetterboxBarHeight(viewportSize: viewportSize)
                let baseBottomPadding: CGFloat = (showControls || !playerController.isPlaying) ? 96 : 36
                let effectiveBottomPadding = (subtitleManager.placement == .mediaFrame)
                    ? max(letterboxBarHeight + 36, baseBottomPadding)
                    : baseBottomPadding

                let baseTopPadding: CGFloat = (showControls || !playerController.isPlaying) ? 72 : 36
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

    private func calculateLetterboxBarHeight(viewportSize: CGSize) -> CGFloat {
        guard playerController.isLetterboxed else { return 0 }

        if let playerNSView = playerController.activePlayerNSView {
            let vr = playerNSView.playerLayer.videoRect
            if vr.height > 0 && vr.width > 0 && vr.height < viewportSize.height {
                let bar = (viewportSize.height - vr.height) / 2.0
                if bar > 0 { return bar }
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

    // MARK: - Reusable Apple-Grade HUD Icon Button

    private struct HUDIconButton: View {
        let iconName: String
        var size: CGFloat = 13.5
        var weight: Font.Weight = .semibold
        var frameSize: CGFloat = 30
        var helpText: String
        var isSelected: Bool = false
        var xOffset: CGFloat = 0
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: iconName)
                    .font(.system(size: size, weight: weight))
                    .foregroundColor(isSelected ? .cyan : (isHovered ? .white : .white.opacity(0.82)))
                    .offset(x: xOffset)
                    .frame(width: frameSize, height: frameSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(helpText)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }
    }

    // MARK: - Apple QuickTime Player Unified Floating HUD Bar

    private func quickTimeFloatingHUD(availableWidth: CGFloat) -> some View {
        let itemSpacing: CGFloat = 8
        let groupSpacing: CGFloat = 4
        let horizontalPadding: CGFloat = 18

        return HStack(spacing: itemSpacing) {
            // 1. Transport Controls: [Rewind 10] [Play / Pause] [Forward 10]
            HStack(spacing: groupSpacing) {
                HUDIconButton(
                    iconName: "gobackward.10",
                    size: 13.5,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: "Rewind 10 seconds (⌘←)"
                ) {
                    playerController.seekRelative(seconds: -10)
                    registerUserActivity()
                }

                HUDIconButton(
                    iconName: playerController.isPlaying ? "pause.fill" : "play.fill",
                    size: 16.5,
                    weight: .bold,
                    frameSize: 32,
                    helpText: playerController.isPlaying ? "Pause (Space)" : "Play (Space)",
                    xOffset: playerController.isPlaying ? 0 : 1
                ) {
                    playerController.togglePlayPause()
                    registerUserActivity()
                    showTransientFeedback(isPlaying: playerController.isPlaying)
                }

                HUDIconButton(
                    iconName: "goforward.10",
                    size: 13.5,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: "Forward 10 seconds (⌘→)"
                ) {
                    playerController.seekRelative(seconds: 10)
                    registerUserActivity()
                }
            }

            hudDivider

            // 2. Timeline Scrubber
            HStack(spacing: 8) {
                Text(formatTime(currentTimeValue))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.85))
                    .frame(minWidth: 36, alignment: .leading)

                NativeSlider(
                    value: Binding(
                        get: { isDraggingScrubber ? scrubTime : PlayerTimeState.shared.currentTime },
                        set: { target in
                            scrubTime = target
                            playerController.seek(to: target)
                            registerUserActivity()
                        }
                    ),
                    in: 0.0...max(PlayerTimeState.shared.duration, 1.0),
                    trackFillColor: .white,
                    onEditingChanged: { editing in
                        if editing {
                            isDraggingScrubber = true
                            wasPlayingBeforeScrub = playerController.isPlaying
                            if wasPlayingBeforeScrub { playerController.pause() }
                        } else {
                            isDraggingScrubber = false
                            playerController.seek(to: scrubTime)
                            if wasPlayingBeforeScrub {
                                playerController.play()
                                wasPlayingBeforeScrub = false
                            }
                        }
                        registerUserActivity()
                    }
                )
                .frame(minWidth: 40, maxWidth: .infinity)
                .frame(height: 22)

                Text(formatRemainingTime())
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.85))
                    .frame(minWidth: 42, alignment: .trailing)
            }

            hudDivider

            // 3. Volume Control (Always visible in both windowed and full screen modes)
            HStack(spacing: groupSpacing) {
                HUDIconButton(
                    iconName: volumeIconName,
                    size: 13,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: playerController.isMuted ? "Unmute (M)" : "Mute (M)"
                ) {
                    playerController.toggleMute()
                    registerUserActivity()
                }

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
                    onEditingChanged: { _ in registerUserActivity() }
                )
                .frame(width: 50, height: 22)
            }

            hudDivider

            // 4. Auxiliary & Route Actions: [Subtitles & Audio] [PiP] [AirPlay] [Fullscreen]
            HStack(spacing: groupSpacing) {
                HUDIconButton(
                    iconName: "quote.bubble",
                    size: 13,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: "Subtitles and Audio"
                ) {
                    OptionsMenuPresenter.shared.show()
                    registerUserActivity()
                }

                HUDIconButton(
                    iconName: playerController.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    size: 12.5,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: "Picture in Picture",
                    isSelected: playerController.isPictureInPictureActive
                ) {
                    playerController.togglePictureInPicture()
                    registerUserActivity()
                }

                AirPlayRoutePicker(player: playerController.player, mode: .video)
                    .frame(width: 22, height: 22)
                    .help("AirPlay Video (Apple TV / External Display)")

                HUDIconButton(
                    iconName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    size: 12,
                    weight: .semibold,
                    frameSize: 28,
                    helpText: isFullScreen ? "Exit Full Screen (^⌘F)" : "Enter Full Screen (^⌘F)"
                ) {
                    toggleFullscreen()
                    registerUserActivity()
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: 48)
        .frame(maxWidth: 620)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    // Absorb background clicks on the pill so they never reach the video canvas play/pause
                    registerUserActivity()
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 20, x: 0, y: 8)
        .onHover { hovering in
            isHoveringOverControls = hovering
            if hovering {
                hideTimer?.cancel()
                withAnimation(.easeInOut(duration: 0.15)) {
                    showControls = true
                }
            } else {
                if playerController.isPlaying && !isAudioMode {
                    scheduleControlsFade(afterSeconds: 2.5)
                }
            }
        }
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 16)
    }

    private var currentTimeValue: Double {
        isDraggingScrubber ? scrubTime : PlayerTimeState.shared.currentTime
    }

    private func formatRemainingTime() -> String {
        let maxD = PlayerTimeState.shared.duration
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

    // MARK: - Activity & Transient Feedback

    private func showTransientFeedback(isPlaying: Bool) {
        transientFeedbackIcon = isPlaying ? "play.fill" : "pause.fill"
        transientFeedbackOpacity = 1.0
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    transientFeedbackOpacity = 0.0
                }
            }
        }
    }

    private func registerUserActivity() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = true
        }
        NSCursor.unhide()
        WindowManager.shared.updateTitlebarVisibility(visible: true)

        hideTimer?.cancel()
        guard !isHoveringOverControls else { return }

        hideTimer = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if playerController.isPlaying && !isAudioMode && !isHoveringOverControls {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showControls = false
                    }
                    NSCursor.setHiddenUntilMouseMoves(true)
                    WindowManager.shared.updateTitlebarVisibility(visible: false)
                }
            }
        }
    }

    private func scheduleControlsFade(afterSeconds: Double) {
        guard !isHoveringOverControls else { return }
        hideTimer?.cancel()
        hideTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if playerController.isPlaying && !isAudioMode && !isHoveringOverControls {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showControls = false
                    }
                    NSCursor.setHiddenUntilMouseMoves(true)
                    WindowManager.shared.updateTitlebarVisibility(visible: false)
                }
            }
        }
    }

    private func toggleFullscreen() {
        WindowManager.shared.toggleFullScreen()
        registerUserActivity()
    }

    private func quitVideoAndReturnToWelcome() {
        playerController.saveCurrentPosition()
        playerController.pause()
        coordinator.stop()
        playerController.reset()
        WindowManager.shared.transitionToWelcome()
    }

    // MARK: - Audio Mode (Apple Music Aesthetics)

    private var audioArtworkAndMetadataView: some View {
        VStack(spacing: 20) {
            // Album Artwork (220x220, squircle, soft elevation shadow)
            ZStack {
                if let art = coordinator.currentArtwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.40), radius: 24, x: 0, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.40), Color.purple.opacity(0.30), Color.black.opacity(0.60)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 220, height: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: Color.blue.opacity(0.20), radius: 20, x: 0, y: 8)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 64, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        )
                }
            }

            // Track Title, Artist, Album, and Format Pill
            VStack(spacing: 6) {
                Text(audioTrackTitle)
                    .font(.system(size: 19, weight: .bold))
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

                if let badge = audioCodecBadgeString {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .padding(.top, 2)
                }
            }

            // Scrubber & Controls
            VStack(spacing: 12) {
                // Scrubber
                HStack(spacing: 8) {
                    Text(formatTime(currentTimeValue))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.80))
                        .frame(minWidth: 36, alignment: .leading)

                    NativeSlider(
                        value: Binding(
                            get: { isDraggingScrubber ? scrubTime : PlayerTimeState.shared.currentTime },
                            set: { target in
                                scrubTime = target
                                playerController.seek(to: target)
                                registerUserActivity()
                            }
                        ),
                        in: 0.0...max(PlayerTimeState.shared.duration, 1.0),
                        trackFillColor: .white,
                        onEditingChanged: { editing in
                            if editing {
                                isDraggingScrubber = true
                                wasPlayingBeforeScrub = playerController.isPlaying
                                if wasPlayingBeforeScrub { playerController.pause() }
                            } else {
                                isDraggingScrubber = false
                                playerController.seek(to: scrubTime)
                                if wasPlayingBeforeScrub {
                                    playerController.play()
                                    wasPlayingBeforeScrub = false
                                }
                            }
                            registerUserActivity()
                        }
                    )
                    .frame(height: 16)

                    Text(formatRemainingTime())
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.80))
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .padding(.horizontal, 24)

                // Transport: [Back 10] [Play/Pause] [Fwd 10]
                HStack(spacing: 32) {
                    Button(action: { playerController.seekRelative(seconds: -10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help("Rewind 10 seconds")

                    Button(action: {
                        playerController.togglePlayPause()
                    }) {
                        Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                            .offset(x: playerController.isPlaying ? 0 : 2)
                    }
                    .buttonStyle(.plain)
                    .help(playerController.isPlaying ? "Pause" : "Play")

                    Button(action: { playerController.seekRelative(seconds: 10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help("Forward 10 seconds")
                }

                // Bottom Shelf: Volume & AirPlay & Options
                HStack(spacing: 12) {
                    Button(action: { playerController.toggleMute() }) {
                        Image(systemName: volumeIconName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    NativeSlider(
                        value: Binding(
                            get: { Double(playerController.isMuted ? 0 : playerController.volume) },
                            set: { newVal in
                                playerController.isMuted = false
                                playerController.volume = Float(newVal)
                            }
                        ),
                        in: 0.0...1.0,
                        trackFillColor: .white
                    )
                    .frame(width: 80, height: 16)

                    Spacer()

                    AirPlayRoutePicker(player: playerController.player, mode: .audio)
                        .frame(width: 22, height: 22)
                        .help("AirPlay Audio")

                    Button(action: { OptionsMenuPresenter.shared.show() }) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Subtitles and Audio")
                    .help("Audio Options & Media Statistics")
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.85)
                .ignoresSafeArea()
        )
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

    private var audioCodecBadgeString: String? {
        guard let probe = coordinator.probeResult else { return nil }
        var parts: [String] = []
        if let audio = probe.primaryAudio {
            let codecUpper = audio.codecName.uppercased()
            if codecUpper.contains("TRUEHD") {
                parts.append("Dolby TrueHD")
            } else if codecUpper.contains("MLP") {
                parts.append("MLP Lossless")
            } else if codecUpper.contains("FLAC") {
                parts.append("FLAC Lossless")
            } else if codecUpper.contains("ALAC") {
                parts.append("Apple Lossless")
            } else {
                parts.append(codecUpper)
            }

            if let ch = audio.channels {
                if ch >= 8 { parts.append("7.1") }
                else if ch >= 6 { parts.append("5.1") }
                else if ch == 2 { parts.append("Stereo") }
                else if ch == 1 { parts.append("Mono") }
            }

            if let sr = audio.sampleRate, sr > 0 {
                let khz = Double(sr) / 1000.0
                parts.append(String(format: "%.1f kHz", khz))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.40), radius: 12, x: 0, y: 4)
                .padding(.top, 24)
                Spacer()
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(150)
        }
    }

    // MARK: - General HUD View

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
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.40), radius: 12, x: 0, y: 4)
                .padding(.top, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(160)

                Spacer()
            }
            .allowsHitTesting(false)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: playerController.hudMessage)
        }
    }

    // MARK: - Loading View

    private func loadingView(message: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.15)
                    .colorInvert()

                Text(message)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                    Button("Open URL", action: onOpenURL)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Minimalist Welcome Screen (Apple Native macOS Aesthetics)

    private var appIconImage: NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png") ?? Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSApp.applicationIconImage
    }

    private var idleStateView: some View {
        VStack(spacing: 20) {
            // App Icon
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.50, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            }

            VStack(spacing: 5) {
                Text("Kino")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                Text("Drop video or audio here to play")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onOpenFile) {
                    Label("Open File…", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button(action: onOpenURL) {
                    Label("Open URL…", systemImage: "globe")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("u", modifiers: .command)
            }
            .padding(.top, 4)

            if !recentDocuments.isEmpty {
                Menu {
                    ForEach(recentDocuments.prefix(8), id: \.self) { url in
                        Button(action: { coordinator.openLocalFile(url: url) }) {
                            Text(url.lastPathComponent)
                        }
                    }
                    Divider()
                    Button("Clear Recent") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                        recentDocuments = []
                    }
                } label: {
                    Label("Recent Files", systemImage: "clock")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(32)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(6)
                .opacity(isDropTargeted ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        )
        .onAppear {
            recentDocuments = NSDocumentController.shared.recentDocumentURLs
            WindowManager.shared.transitionToWelcome(animated: false)
        }
    }
}
