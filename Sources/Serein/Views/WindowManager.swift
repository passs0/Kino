import AppKit
import SwiftUI
import Combine

/// Manages window presentation styles, smooth sizing between Video and Audio layouts,
/// and Desktop Always-On-Top floating behavior.
@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    /// Indicates whether the window is pinned always on top of other desktop windows.
    @Published public private(set) var isPinnedAlwaysOnTop: Bool = false

    public weak var mainWindow: NSWindow?
    private var preAudioFrame: NSRect?

    public static let audioDefaultSize = CGSize(width: 480, height: 530)
    public static let audioMinSize = CGSize(width: 380, height: 450)
    public static let standardDefaultSize = CGSize(width: 900, height: 506)
    public static let standardMinSize = CGSize(width: 640, height: 380)

    private init() {}

    /// Registers the main application window.
    public func register(window: NSWindow) {
        self.mainWindow = window
        window.isMovableByWindowBackground = true
        TrafficLightManager.shared.repositionTrafficLights(for: window)
    }

    /// Adapts window size smoothly based on whether media is pure audio or video.
    public func transitionToMedia(isAudio: Bool, animated: Bool = true) {
        guard let window = mainWindow else { return }

        if isAudio {
            if preAudioFrame == nil || preAudioFrame!.width < Self.standardMinSize.width {
                preAudioFrame = window.frame
            }

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
            window.minSize = Self.standardMinSize
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let targetRect: NSRect
            if let saved = preAudioFrame, saved.width >= Self.standardMinSize.width {
                targetRect = saved
            } else {
                let current = window.frame
                let targetW = Self.standardDefaultSize.width
                let targetH = Self.standardDefaultSize.height
                let targetX = max(40, current.origin.x - (targetW - current.width) / 2)
                let targetY = max(40, current.origin.y - (targetH - current.height) / 2)
                targetRect = NSRect(x: targetX, y: targetY, width: targetW, height: targetH)
            }
            window.setFrame(targetRect, display: true, animate: animated)
        }

        TrafficLightManager.shared.repositionTrafficLights(for: window)
    }

    /// Toggles Always-On-Top floating window level.
    public func togglePinAlwaysOnTop() {
        isPinnedAlwaysOnTop.toggle()
        guard let window = mainWindow else { return }
        window.level = isPinnedAlwaysOnTop ? .floating : .normal
    }
}
