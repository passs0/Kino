import AppKit
import SwiftUI
import Combine

/// Manages window presentation styles, smooth sizing to video natural resolution,
/// aspect-ratio preservation, titlebar proxy icons, and Desktop Always-On-Top floating behavior.
@MainActor
public final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = WindowManager()

    /// Indicates whether the window is pinned always on top of other desktop windows.
    @Published public private(set) var isPinnedAlwaysOnTop: Bool = false

    public weak var mainWindow: NSWindow?
    private var preMediaFrame: NSRect?
    private var currentNaturalSize: CGSize?
    private var fullScreenExitObserver: NSObjectProtocol?

    public static let welcomeDefaultSize = CGSize(width: 580, height: 380)
    public static let audioDefaultSize = CGSize(width: 440, height: 500)
    public static let audioMinSize = CGSize(width: 380, height: 440)
    public static let videoMinSize = CGSize(width: 480, height: 270)

    private override init() {
        super.init()
    }

    /// Registers the main application window.
    public func register(window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.title = "Kino"
        if MediaCoordinator.shared.state == .idle {
            transitionToWelcome(animated: false)
        }
    }

    /// Adapts window size smoothly based on whether media is pure audio, video, or idle.
    public func transitionToMedia(isAudio: Bool, videoSize: CGSize? = nil, animated: Bool = true) {
        guard let window = mainWindow else { return }

        if isAudio {
            currentNaturalSize = nil
            window.contentAspectRatio = .zero
            window.minSize = Self.audioMinSize
            window.maxSize = CGSize(width: 720, height: 800)

            let current = window.frame
            let newWidth = Self.audioDefaultSize.width
            let newHeight = Self.audioDefaultSize.height
            let newX = max(40, current.origin.x + (current.width - newWidth) / 2)
            let newY = max(40, current.origin.y + (current.height - newHeight) / 2)

            let targetRect = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            window.setFrame(targetRect, display: true, animate: animated)
        } else {
            let natSize = videoSize ?? currentNaturalSize ?? CGSize(width: 900, height: 506)
            currentNaturalSize = natSize

            // Lock content aspect ratio to prevent letterbox bars when dragging window edges!
            window.contentAspectRatio = natSize
            window.minSize = Self.videoMinSize
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let maxW = screen.width * 0.82
            let maxH = screen.height * 0.82

            var targetW = natSize.width
            var targetH = natSize.height

            // Scale down to fit screen if needed
            let scaleW = maxW / max(targetW, 1)
            let scaleH = maxH / max(targetH, 1)
            let fitScale = min(1.0, min(scaleW, scaleH))

            targetW *= fitScale
            targetH *= fitScale

            // Ensure not smaller than minimum size
            if targetW < Self.videoMinSize.width {
                let up = Self.videoMinSize.width / targetW
                targetW *= up
                targetH *= up
            }

            let current = window.frame
            let newX = max(screen.minX + 20, current.origin.x - (targetW - current.width) / 2)
            let newY = max(screen.minY + 20, current.origin.y - (targetH - current.height) / 2)

            let targetRect = NSRect(x: newX, y: newY, width: targetW, height: targetH)
            window.setFrame(targetRect, display: true, animate: animated)
        }
    }

    /// Returns the window to the clean, compact Welcome screen presentation.
    public func transitionToWelcome(animated: Bool = true) {
        guard let window = mainWindow else { return }

        // If currently in macOS native Full Screen, exit full screen first to prevent AppKit animation freezes
        if window.styleMask.contains(.fullScreen) {
            if let existing = fullScreenExitObserver {
                NotificationCenter.default.removeObserver(existing)
            }
            fullScreenExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    if let obs = self.fullScreenExitObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self.fullScreenExitObserver = nil
                    }
                    self.transitionToWelcome(animated: animated)
                }
            }
            window.toggleFullScreen(nil)
            return
        }

        currentNaturalSize = nil
        window.contentAspectRatio = .zero
        window.minSize = CGSize(width: 440, height: 320)
        window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.representedURL = nil
        window.title = "Kino"
        updateTitlebarVisibility(visible: true, animated: animated)

        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let targetW = Self.welcomeDefaultSize.width
        let targetH = Self.welcomeDefaultSize.height
        let newX = screen.minX + (screen.width - targetW) / 2
        let newY = screen.minY + (screen.height - targetH) / 2

        let targetRect = NSRect(x: newX, y: newY, width: targetW, height: targetH)
        window.setFrame(targetRect, display: true, animate: animated)
    }

    /// Sets the document URL and title for macOS document proxy icon integration.
    public func setMediaDocument(url: URL?, title: String?) {
        guard let window = mainWindow else { return }
        window.representedURL = url
        window.title = title ?? (url?.deletingPathExtension().lastPathComponent ?? "Kino")
    }

    /// Fades the titlebar in or out with QuickTime-style timing.
    public func updateTitlebarVisibility(visible: Bool, animated: Bool = true) {
        guard let window = mainWindow, !window.styleMask.contains(.fullScreen) else { return }
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        let targetAlpha: CGFloat = visible ? 1.0 : 0.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                titlebar.animator().alphaValue = targetAlpha
            }
        } else {
            titlebar.alphaValue = targetAlpha
        }
    }

    /// QuickTime Zoom: Actual Size (⌘1)
    public func zoomToActualSize() {
        guard let window = mainWindow, let size = currentNaturalSize, size.width > 0, size.height > 0 else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = screen.width * 0.95
        let maxH = screen.height * 0.95
        let scale = min(1.0, min(maxW / size.width, maxH / size.height))
        let targetW = size.width * scale
        let targetH = size.height * scale
        let current = window.frame
        let newX = max(screen.minX, current.origin.x - (targetW - current.width) / 2)
        let newY = max(screen.minY, current.origin.y - (targetH - current.height) / 2)
        window.setFrame(NSRect(x: newX, y: newY, width: targetW, height: targetH), display: true, animate: true)
    }

    /// QuickTime Zoom: Double Size (⌘2)
    public func zoomToDoubleSize() {
        guard let window = mainWindow, let size = currentNaturalSize, size.width > 0, size.height > 0 else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let targetW = min(screen.width * 0.95, size.width * 2.0)
        let targetH = targetW / (size.width / size.height)
        let current = window.frame
        let newX = max(screen.minX, current.origin.x - (targetW - current.width) / 2)
        let newY = max(screen.minY, current.origin.y - (targetH - current.height) / 2)
        window.setFrame(NSRect(x: newX, y: newY, width: targetW, height: targetH), display: true, animate: true)
    }

    /// QuickTime Zoom: Fit to Screen (⌘3 or ⌘0)
    public func zoomToFitScreen() {
        guard let window = mainWindow, let size = currentNaturalSize, size.width > 0, size.height > 0 else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let aspect = size.width / size.height
        let screenAspect = screen.width / screen.height
        let targetW: CGFloat
        let targetH: CGFloat
        if screenAspect > aspect {
            targetH = screen.height * 0.92
            targetW = targetH * aspect
        } else {
            targetW = screen.width * 0.92
            targetH = targetW / aspect
        }
        let newX = screen.minX + (screen.width - targetW) / 2
        let newY = screen.minY + (screen.height - targetH) / 2
        window.setFrame(NSRect(x: newX, y: newY, width: targetW, height: targetH), display: true, animate: true)
    }

    /// Toggles Always-On-Top floating window level.
    public func togglePinAlwaysOnTop() {
        isPinnedAlwaysOnTop.toggle()
        guard let window = mainWindow else { return }
        window.level = isPinnedAlwaysOnTop ? .floating : .normal
    }
}

// MARK: - NSWindowDelegate
extension WindowManager {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if MediaCoordinator.shared.state != .idle {
            NotificationCenter.default.post(name: .closeMediaNotification, object: nil)
            return false
        }
        return true
    }

    public func windowWillClose(_ notification: Notification) {
        PlayerController.shared.shutdownOnQuit()
        SleepPreventionManager.shared.setSleepDisabled(false)
        SubtitleManager.shared.reset()
        MediaCoordinator.shared.stop()
    }
}
