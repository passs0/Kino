import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Minimalist Liquid Glass Main Window (macOS 26+)
public struct MainWindowView: View {
    @StateObject private var coordinator = MediaCoordinator.shared
    @StateObject private var playerController = PlayerController.shared

    @State private var showURLSheet = false
    @State private var showPrerequisitesSheet = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .center) {
            // Solid native macOS window background for idle, cinematic black for loading & playback
            (coordinator.state == .idle ? Color(NSColor.windowBackgroundColor) : Color.black)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: coordinator.state == .idle)

            // Centered video canvas / welcome screen
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
        .frame(minWidth: 480, idealWidth: 540, minHeight: 300, idealHeight: 340)
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
            UTType(filenameExtension: "mkv") ?? .data,
            UTType(filenameExtension: "webm") ?? .data,
            UTType(filenameExtension: "avi") ?? .data,
            UTType(filenameExtension: "ts") ?? .data,
            UTType(filenameExtension: "flv") ?? .data,
            UTType(filenameExtension: "m4v") ?? .data
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
            window.isOpaque = true
            window.backgroundColor = isIdle ? .windowBackgroundColor : .black
            window.hasShadow = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert([.fullSizeContentView])
            window.isMovableByWindowBackground = false

            // Position traffic lights cleanly
            let xOffset: CGFloat = 18
            let yOffset: CGFloat = 16
            let spacing: CGFloat = 8
            var currentX = xOffset
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let btn = window.standardWindowButton(type), let superview = btn.superview {
                    btn.translatesAutoresizingMaskIntoConstraints = true
                    let btnY = superview.bounds.height - btn.frame.height - yOffset
                    btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                    currentX += btn.frame.width + spacing
                }
            }
        }
    }
}
