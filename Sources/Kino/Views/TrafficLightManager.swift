import AppKit
import ObjectiveC

/// Enforces generous breathing room for macOS standard window buttons (traffic lights)
/// tailored for windows with large corner radii (such as 26pt continuous squircles).
/// Consistently insets the close, minimize, and zoom controls away from the corner curve
/// and ensures the window title and document proxy icon are strictly in line on the
/// exact same horizontal center axis across all states.
public final class TrafficLightManager: @unchecked Sendable {
    public static let shared = TrafficLightManager()

    /// Offset from left edge of window (26pt clears the 26pt corner arc completely)
    public static let xOffset: CGFloat = 26.0

    /// Offset from top edge of window to the top of the traffic light buttons
    public static let yOffset: CGFloat = 16.0

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

        // Align buttons only after window has fully finished returning to windowed mode
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { notif in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                MainActor.assumeIsolated {
                    if let window = notif.object as? NSWindow {
                        TrafficLightManager.shared.repositionTrafficLights(for: window)
                    }
                }
            }
        }
    }

    @MainActor
    public func repositionTrafficLights(for window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), !WindowManager.shared.isTransitioningFullScreen else { return }
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        titlebar.needsLayout = true
    }

    private func swizzleLayout(on titlebarClass: AnyClass) {
        let origSelector = #selector(NSView.layout)
        let swizzSelector = #selector(NSView.kino_titlebarLayout)

        guard let origMethod = class_getInstanceMethod(titlebarClass, origSelector),
              let swizzMethod = class_getInstanceMethod(NSView.self, swizzSelector) else {
            return
        }

        method_exchangeImplementations(origMethod, swizzMethod)
    }
}

extension NSView {
    @objc func kino_titlebarLayout() {
        self.kino_titlebarLayout()

        guard let win = self.window,
              !win.styleMask.contains(.fullScreen),
              !WindowManager.shared.isTransitioningFullScreen else { return }

        // Clear any default background or visual effect views so the titlebar blends 100% seamlessly
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        if let container = self.superview {
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.clear.cgColor
            for sub in container.subviews {
                if let effect = sub as? NSVisualEffectView {
                    effect.isHidden = true
                    effect.alphaValue = 0.0
                }
            }
        }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        let btnHeight: CGFloat = 14.0
        // Target vertical center for all titlebar elements (traffic lights, doc proxy, and title text)
        let targetCenterY: CGFloat = bounds.height - TrafficLightManager.yOffset - (btnHeight / 2.0)
        let btnY = round(targetCenterY - (btnHeight / 2.0))

        var currentX = TrafficLightManager.xOffset
        for type in buttonTypes {
            if let btn = win.standardWindowButton(type), btn.superview == self {
                btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                currentX += btn.frame.width + TrafficLightManager.buttonSpacing
            }
        }

        // Locate document proxy button and title text field
        var docButton: NSButton? = nil
        var titleField: NSTextField? = nil

        for sub in subviews {
            if let btn = sub as? NSButton, !buttonTypes.contains(where: { win.standardWindowButton($0) == btn }) {
                docButton = btn
            } else if let tf = sub as? NSTextField {
                titleField = tf
            }
        }

        let leadingGap: CGFloat = 12.0

        // Position document proxy icon perfectly in line with traffic lights
        if let doc = docButton {
            let docX = currentX + leadingGap
            let docY = round(targetCenterY - (doc.frame.height / 2.0))
            doc.setFrameOrigin(NSPoint(x: docX, y: docY))
            currentX = doc.frame.maxX
        }

        // Position window title text field perfectly in line with traffic lights
        if let tf = titleField {
            let tfGap: CGFloat = (docButton != nil) ? 4.0 : leadingGap
            let tfX = currentX + tfGap
            let tfY = round(targetCenterY - (tf.frame.height / 2.0))
            tf.setFrameOrigin(NSPoint(x: tfX, y: tfY))
        }
    }
}
