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
            // Solid native macOS window background
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            // Centered video canvas / welcome screen
            VideoPlayerView(
                coordinator: coordinator,
                playerController: playerController,
                onOpenFile: openFilePicker,
                onOpenURL: { showURLSheet = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea()

            // Floating Stream Inspector (Cmd + I)
            if coordinator.isInspectorPresented {
                HStack {
                    Spacer()
                    MediaInspectorView(coordinator: coordinator) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            coordinator.isInspectorPresented = false
                        }
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 18)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 300, idealHeight: 340)
        .background(WindowGlassAccessor())
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
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
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
