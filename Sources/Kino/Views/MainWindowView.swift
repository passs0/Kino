import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Translation

/// Minimalist Liquid Glass Main Window (macOS 26+)
public struct MainWindowView: View {
    public static var idleNSBackgroundColor: NSColor {
        .windowBackgroundColor
    }
    public static var idleBackgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    @StateObject private var coordinator = MediaCoordinator.shared
    @StateObject private var playerController = PlayerController.shared
    @StateObject private var windowManager = WindowManager.shared
    @StateObject private var liveCaption = LiveCaptionManager.shared

    @State private var showURLSheet = false
    @State private var showPrerequisitesSheet = false
    @State private var showSubtitleSearchSheet = false
    @State private var showLiveCaptionSheet = false
    @State private var isFullScreen = false

    public init() {}

    public var body: some View {
        mainContent
            .ignoresSafeArea()
            .frame(minWidth: 320, minHeight: 180)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WindowGlassAccessor(isIdle: coordinator.state == .idle))
            .sheet(isPresented: $showURLSheet) {
                URLInputSheet(coordinator: coordinator)
            }
            .sheet(isPresented: $showPrerequisitesSheet) {
                PrerequisiteInstallSheet()
            }
            .sheet(isPresented: $showSubtitleSearchSheet) {
                SubtitleSearchSheet()
            }
            .sheet(isPresented: $showLiveCaptionSheet) {
                LiveCaptionSheet()
            }
            .translationTask(liveCaption.translationConfig) { session in
                liveCaption.registerTranslationSession(session)
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
            .onReceive(NotificationCenter.default.publisher(for: .openURLSheetNotification)) { _ in
                showURLSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPrerequisitesSheetNotification)) { _ in
                showPrerequisitesSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSubtitleSearchSheetNotification)) { _ in
                showSubtitleSearchSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLiveCaptionSheetNotification)) { _ in
                showLiveCaptionSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeMediaNotification)) { _ in
                handleCloseMedia()
            }
            .onChange(of: coordinator.currentSource) { _, newSource in
                handleSourceChange(newSource)
            }
            .onChange(of: coordinator.activePlayableURL) { _, newURL in
                handlePlayableURLChange(newURL)
            }
            .onChange(of: coordinator.probeResult) { _, newProbe in
                handleProbeChange(newProbe)
            }
            .onChange(of: coordinator.extractedOnlineInfo?.duration) { _, newDuration in
                if let d = newDuration, d > 0 {
                    playerController.setKnownDuration(d)
                }
            }
            .onChange(of: coordinator.extractedOnlineInfo?.title) { _, newTitle in
                if let t = newTitle, !t.isEmpty {
                    windowManager.setMediaDocument(url: nil, title: t)
                }
            }
    }

    private var mainContent: some View {
        ZStack(alignment: .center) {
            (coordinator.state == .idle ? MainWindowView.idleBackgroundColor : Color.black)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: coordinator.state == .idle)

            VideoPlayerView(
                coordinator: coordinator,
                playerController: playerController,
                onOpenFile: openFilePicker,
                onOpenURL: { showURLSheet = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea()

            if coordinator.isInspectorPresented {
                inspectorOverlay
            }
        }
        .preferredColorScheme(coordinator.state == .idle ? nil : .dark)
    }

    private var inspectorOverlay: some View {
        VStack {
            HStack {
                Spacer()
                MediaInspectorView(coordinator: coordinator) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        coordinator.isInspectorPresented = false
                    }
                }
                .padding(.top, 48)
                .padding(.trailing, 20)
            }
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
        .zIndex(200)
    }

    private func handleCloseMedia() {
        if coordinator.state != .idle {
            playerController.saveCurrentPosition()
            playerController.pause()
            playerController.reset()
            coordinator.stop()
            windowManager.transitionToWelcome()
        } else {
            WindowManager.shared.mainWindow?.close()
        }
    }

    private func handleSourceChange(_ source: MediaSource?) {
        if let s = source {
            if case .local(let url) = s {
                windowManager.setMediaDocument(url: url, title: s.displayName)
            } else {
                let streamTitle = coordinator.extractedOnlineInfo?.title ?? s.displayName
                windowManager.setMediaDocument(url: nil, title: streamTitle)
            }
        } else {
            windowManager.setMediaDocument(url: nil, title: "Kino")
        }
    }

    private func handlePlayableURLChange(_ newURL: URL?) {
        if let url = newURL {
            if !playerController.isSeeking {
                let expDuration = coordinator.knownDuration
                let initTime = coordinator.pendingInitialTime
                coordinator.pendingInitialTime = nil
                playerController.load(url: url, expectedDuration: expDuration, initialTime: initTime)
            }
        } else {
            playerController.reset()
        }
    }

    private func handleProbeChange(_ probe: MediaProbeResult?) {
        if let d = probe?.duration, d > 0 {
            playerController.setKnownDuration(d)
        }
        if let video = probe?.primaryVideo, let w = video.width, let h = video.height, w > 0, h > 0 {
            let size = CGSize(width: w, height: h)
            windowManager.transitionToMedia(isAudio: false, videoSize: size)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .movie,
            .video,
            .quickTimeMovie,
            .mpeg4Movie,
            .audio,
            .mp3,
            UTType(filenameExtension: "flac") ?? .data,
            UTType(filenameExtension: "alac") ?? .data,
            UTType(filenameExtension: "m4a") ?? .data,
            UTType(filenameExtension: "aac") ?? .data,
            UTType(filenameExtension: "wav") ?? .data,
            UTType(filenameExtension: "aiff") ?? .data,
            UTType(filenameExtension: "ogg") ?? .data,
            UTType(filenameExtension: "opus") ?? .data,
            UTType(filenameExtension: "mkv") ?? .data,
            UTType(filenameExtension: "webm") ?? .data,
            UTType(filenameExtension: "avi") ?? .data,
            UTType(filenameExtension: "ts") ?? .data,
            UTType(filenameExtension: "flv") ?? .data,
            UTType(filenameExtension: "m4v") ?? .data,
            UTType(filenameExtension: "thd") ?? .data,
            UTType(filenameExtension: "truehd") ?? .data
        ]

        if panel.runModal() == .OK, let url = panel.url {
            coordinator.openLocalFile(url: url)
        }
    }
}

/// Helper that configures the parent NSWindow for native window background and insets traffic lights.
private struct WindowGlassAccessor: NSViewRepresentable {
    var isIdle: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            WindowManager.shared.register(window: window)
            window.isOpaque = true
            window.backgroundColor = isIdle ? MainWindowView.idleNSBackgroundColor : .black
            window.appearance = isIdle ? nil : NSAppearance(named: .darkAqua)
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.titleVisibility = isIdle ? .hidden : .visible
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            window.isMovableByWindowBackground = isIdle

            // Do not alter layers or titlebars during Full Screen transitions
            guard !WindowManager.shared.isTransitioningFullScreen else { return }

            let isFS = window.styleMask.contains(.fullScreen)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.masksToBounds = true

            // Clear any AppKit titlebar materials or visual effect backdrops so the window is 100% unified
            if !isFS, let titlebar = window.standardWindowButton(.closeButton)?.superview {
                titlebar.wantsLayer = true
                titlebar.layer?.backgroundColor = NSColor.clear.cgColor
                if let container = titlebar.superview {
                    container.wantsLayer = true
                    container.layer?.backgroundColor = NSColor.clear.cgColor
                    for sub in container.subviews {
                        if let effect = sub as? NSVisualEffectView {
                            effect.isHidden = true
                            effect.alphaValue = 0.0
                        }
                    }
                }
            }
        }
    }
}
