import AppKit
import ObjectiveC

/// Enforces generous breathing room for macOS standard window buttons (traffic lights)
/// consistently across all states: welcome idle screen, video playback, live window resizing,
/// and full-screen transitions.
public final class TrafficLightManager: @unchecked Sendable {
    public static let shared = TrafficLightManager()

    /// Horizontal offset from the left edge of the window to the close button
    public static let xOffset: CGFloat = 18.0

    /// Vertical offset from the top edge of the window to the top of the buttons
    public static let yOffset: CGFloat = 16.0

    /// Inter-button spacing between close, minimize, and zoom
    public static let buttonSpacing: CGFloat = 8.0

    private var isInstalled = false

    private init() {}

    @MainActor
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // Swizzle NSTitlebarView layout so AppKit cannot reset traffic lights on layout/resize
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
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var currentX = Self.xOffset
        for type in buttonTypes {
            if let btn = window.standardWindowButton(type), let superview = btn.superview {
                btn.translatesAutoresizingMaskIntoConstraints = true
                let btnY = superview.bounds.height - btn.frame.height - Self.yOffset
                btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                currentX += btn.frame.width + Self.buttonSpacing
            }
        }
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
        var currentX = TrafficLightManager.xOffset
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttonTypes {
            if let btn = win.standardWindowButton(type), btn.superview == self {
                let btnY = bounds.height - btn.frame.height - TrafficLightManager.yOffset
                btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                currentX += btn.frame.width + TrafficLightManager.buttonSpacing
            }
        }
    }
}
