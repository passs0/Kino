import AppKit
import ObjectiveC

/// Enforces generous breathing room for macOS standard window buttons (traffic lights)
/// tailored for windows with large corner radii (such as 26pt continuous squircles).
/// Consistently insets the close, minimize, and zoom controls away from the corner curve
/// across all states: welcome idle screen, video playback, audio playback, window resizing,
/// and full-screen transitions.
public final class TrafficLightManager: @unchecked Sendable {
    public static let shared = TrafficLightManager()

    /// Offset from left edge of window (26pt clears the 26pt corner arc completely)
    public static let xOffset: CGFloat = 26.0

    /// Offset from top edge of window
    public static let yOffset: CGFloat = 18.0

    /// Inter-button spacing between close, minimize, and zoom
    public static let buttonSpacing: CGFloat = 8.0

    private var isInstalled = false

    private init() {}

    @MainActor
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // Swizzle NSTitlebarView layout so AppKit positions buttons at safe 26pt insets
        if let titlebarClass = NSClassFromString("NSTitlebarView") {
            swizzleLayout(on: titlebarClass)
        }

        // Listen for window resize and fullscreen transitions to ensure immediate alignment
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { notif in
            MainActor.assumeIsolated {
                if let window = notif.object as? NSWindow {
                    TrafficLightManager.shared.repositionTrafficLights(for: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { notif in
            MainActor.assumeIsolated {
                if let window = notif.object as? NSWindow {
                    TrafficLightManager.shared.repositionTrafficLights(for: window)
                }
            }
        }
    }

    @MainActor
    public func repositionTrafficLights(for window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        titlebar.needsLayout = true
        titlebar.layoutSubtreeIfNeeded()
    }

    private func swizzleLayout(on titlebarClass: AnyClass) {
        let origSelector = #selector(NSView.layout)
        let swizzSelector = #selector(NSView.serein_titlebarLayout)

        guard let origMethod = class_getInstanceMethod(titlebarClass, origSelector),
              let swizzMethod = class_getInstanceMethod(NSView.self, swizzSelector) else {
            return
        }

        method_exchangeImplementations(origMethod, swizzMethod)
    }
}

extension NSView {
    @objc func serein_titlebarLayout() {
        self.serein_titlebarLayout()

        guard let win = self.window, !win.styleMask.contains(.fullScreen) else { return }
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var currentX = TrafficLightManager.xOffset

        for type in buttonTypes {
            if let btn = win.standardWindowButton(type), btn.superview == self {
                let btnY = max(0, bounds.height - btn.frame.height - TrafficLightManager.yOffset)
                btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                currentX += btn.frame.width + TrafficLightManager.buttonSpacing
            }
        }

        // Adjust document proxy icon and title text field to follow the shifted traffic lights
        let gap: CGFloat = 8.0
        for sub in subviews {
            if let docBtn = sub as? NSButton, !buttonTypes.contains(where: { win.standardWindowButton($0) == docBtn }) {
                if docBtn.frame.origin.x < currentX + gap {
                    let docY = max(0, bounds.height - docBtn.frame.height - TrafficLightManager.yOffset)
                    docBtn.setFrameOrigin(NSPoint(x: currentX + gap, y: docY))
                    currentX = docBtn.frame.maxX
                }
            } else if let tf = sub as? NSTextField {
                if tf.frame.origin.x < currentX + gap {
                    let tfY = max(0, bounds.height - tf.frame.height - TrafficLightManager.yOffset + 1)
                    tf.setFrameOrigin(NSPoint(x: currentX + gap, y: tfY))
                }
            }
        }
    }
}
