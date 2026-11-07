import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Minimalist Liquid Glass Main Window (macOS 26+)
public struct MainWindowView: View {
    @StateObject private var coordinator = MediaCoordinator.shared
    @StateObject private var playerController = PlayerController.shared
    @StateObject private var windowManager = WindowManager.shared

    @State private var showURLSheet = false
    @State private var showPrerequisitesSheet = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .center) {
            // Solid native macOS window background for idle, cinematic black for loading & playback
            (coordinator.state == .idle ? Color(NSColor.windowBackgroundColor) : Color.black)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: coordinator.state == .idle)

            // Centered player canvas / welcome screen
            VideoPlayerView(
                coordinator: coordinator,
                playerController: playerController,
                onOpenFile: openFilePicker,
                onOpenURL: { showURLSheet = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea()

            // Centered Floating Media Statistics HUD (Cmd + I / Options Menu)
            if coordinator.isInspectorPresented {
                ZStack(alignment: .center) {
                    // Subtle dimmed backdrop scrim to guarantee legibility and quick dismissal
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
        }
        .frame(
            minWidth: 380,
            minHeight: 400
        )
        .background(WindowGlassAccessor(isIdle: coordinator.state == .idle))
        .sheet(isPresented: $showURLSheet) {
            URLInputSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $showPrerequisitesSheet) {
            PrerequisiteInstallSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openURLSheetNotification)) { _ in
            showURLSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPrerequisitesSheetNotification)) { _ in
            showPrerequisitesSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeMediaNotification)) { _ in
            if coordinator.state != .idle {
                playerController.saveCurrentPosition()
                playerController.pause()
                coordinator.stop()
                playerController.reset()
            }
        }
        .onChange(of: coordinator.activePlayableURL) { _, newURL in
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
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            WindowManager.shared.register(window: window)
            window.isOpaque = true
            window.backgroundColor = isIdle ? .windowBackgroundColor : .black
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert([.fullSizeContentView])
            window.isMovableByWindowBackground = true

            // Position traffic lights cleanly with generous breathing room
            TrafficLightManager.shared.repositionTrafficLights(for: window)
        }
    }
}
