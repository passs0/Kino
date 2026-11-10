import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Minimalist Liquid Glass Main Window (macOS 26+)
public struct MainWindowView: View {
    public static let idleBackgroundColor = Color(red: 0.118, green: 0.118, blue: 0.118)
    public static let idleNSBackgroundColor = NSColor(calibratedRed: 0.118, green: 0.118, blue: 0.118, alpha: 1.0)

    @StateObject private var coordinator = MediaCoordinator.shared
    @StateObject private var playerController = PlayerController.shared
    @StateObject private var windowManager = WindowManager.shared

    @State private var showURLSheet = false
    @State private var showPrerequisitesSheet = false
    @State private var isFullScreen = false

    public init() {}

    public var body: some View {
        mainContent
            .ignoresSafeArea()
            .frame(minWidth: 440, minHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 26, style: .continuous))
            .background(WindowGlassAccessor(isIdle: coordinator.state == .idle))
            .sheet(isPresented: $showURLSheet) {
                URLInputSheet(coordinator: coordinator)
            }
            .sheet(isPresented: $showPrerequisitesSheet) {
                PrerequisiteInstallSheet()
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
    }

    private var inspectorOverlay: some View {
        ZStack(alignment: .center) {
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        coordinator.isInspectorPresented = false
                    }
                }

            MediaInspectorView(coordinator: coordinator) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    coordinator.isInspectorPresented = false
                }
            }
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
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
                windowManager.setMediaDocument(url: nil, title: s.displayName)
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

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            WindowManager.shared.register(window: window)
            window.isOpaque = true
            window.backgroundColor = isIdle ? MainWindowView.idleNSBackgroundColor : .black
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.titleVisibility = isIdle ? .hidden : .visible
            window.styleMask.insert([.fullSizeContentView])
            window.isMovableByWindowBackground = true

            // macOS 26 corner radius physics
            let isFS = window.styleMask.contains(.fullScreen)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = isFS ? 0 : 26
            window.contentView?.layer?.cornerCurve = .continuous
            window.contentView?.layer?.masksToBounds = !isFS

            // Clear any AppKit titlebar materials or visual effect backdrops so the window is 100% unified
            if let titlebar = window.standardWindowButton(.closeButton)?.superview {
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

            TrafficLightManager.shared.repositionTrafficLights(for: window)
        }
    }
}
