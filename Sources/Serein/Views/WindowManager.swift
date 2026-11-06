import AppKit
import SwiftUI
import Combine

/// Manages window presentation styles, smooth morphing between Full Canvas and Compact MiniPlayer,
/// and Desktop Always-On-Top floating behavior.
@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    /// Indicates whether the compact MiniPlayer window mode is currently active.
    @Published public private(set) var isMiniPlayer: Bool = false

    /// Indicates whether the window is pinned always on top of other desktop windows.
    @Published public private(set) var isPinnedAlwaysOnTop: Bool = false

    public weak var mainWindow: NSWindow?
    private var preMiniPlayerFrame: NSRect?

    public static let miniPlayerSize = CGSize(width: 440, height: 132)
    public static let standardDefaultSize = CGSize(width: 900, height: 506)
    public static let standardMinSize = CGSize(width: 720, height: 460)

    private init() {}

    /// Registers the main application window.
    public func register(window: NSWindow) {
        self.mainWindow = window
        applyWindowProperties(window, animated: false)
    }

    /// Sets whether MiniPlayer mode is active with fluid window frame animation.
    public func setMiniPlayer(_ active: Bool, animated: Bool = true) {
        guard isMiniPlayer != active else { return }
        isMiniPlayer = active

        guard let window = mainWindow else { return }
        applyWindowProperties(window, animated: animated)
    }

    /// Toggles between Full Canvas and Compact MiniPlayer.
    public func toggleMiniPlayer() {
        setMiniPlayer(!isMiniPlayer)
    }

    /// Toggles Always-On-Top floating window level.
    public func togglePinAlwaysOnTop() {
        isPinnedAlwaysOnTop.toggle()
        guard let window = mainWindow else { return }
        window.level = isPinnedAlwaysOnTop ? .floating : .normal
    }

    private func applyWindowProperties(_ window: NSWindow, animated: Bool) {
        if isMiniPlayer {
            // Save video window frame if not already in miniplayer
            if preMiniPlayerFrame == nil || preMiniPlayerFrame!.width < Self.standardMinSize.width {
                preMiniPlayerFrame = window.frame
            }

            window.minSize = Self.miniPlayerSize
            window.maxSize = CGSize(width: 620, height: 160)
            window.isMovableByWindowBackground = true

            if isPinnedAlwaysOnTop {
                window.level = .floating
            }

            let current = window.frame
            let newWidth = Self.miniPlayerSize.width
            let newHeight = Self.miniPlayerSize.height
            // Keep top-left stable
            let newX = current.origin.x
            let newY = current.origin.y + (current.height - newHeight)

            let targetRect = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            window.setFrame(targetRect, display: true, animate: animated)
        } else {
            window.minSize = Self.standardMinSize
            window.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.isMovableByWindowBackground = false

            if !isPinnedAlwaysOnTop {
                window.level = .normal
            }

            let targetRect: NSRect
            if let saved = preMiniPlayerFrame, saved.width >= Self.standardMinSize.width {
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
}
