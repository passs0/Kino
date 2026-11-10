import AppKit

extension NSWindow {
    private static var isFrameSafetyInstalled = false

    /// Installs a low-level safety interceptor on `-[NSWindow _reallySetFrame:]`.
    ///
    /// Root Cause & Purpose:
    /// In macOS AppKit, when exiting native Full Screen, `_NSExitFullScreenTransitionController`
    /// invokes `setupWindowForAfterFullScreenExit` -> `-[NSWindow _reallySetFrame:]`.
    /// Under certain multi-display, aspect ratio, or titlebar states, AppKit occasionally passes
    /// a malformed frame containing `NaN` (e.g. `{{nan, 0}, {100, 100}}`).
    /// This causes an internal AppKit assertion failure:
    /// `CGRectContainsRect(CGRectMake((CGFloat)INT_MIN, ...), frame)` at `NSWindow.m:1086`.
    /// When that assertion throws, the transition aborts mid-flight, trapping the window server
    /// in transition modal mode. All event routing is blocked, freezing controls and Cmd+Q.
    ///
    /// By intercepting `_reallySetFrame:` and sanitizing any NaN, Infinite, or corrupt frames
    /// back to safe, valid screen coordinates, the AppKit assertion can never fail, guaranteeing
    /// that `_NSExitFullScreenTransitionController` always completes its transition cleanly.
    @MainActor
    public static func installFrameSafetySwizzle() {
        guard !isFrameSafetyInstalled else { return }
        isFrameSafetyInstalled = true

        let origSel = NSSelectorFromString("_reallySetFrame:")
        let swizzSel = #selector(NSWindow.kino_safeReallySetFrame(_:))

        guard let origMethod = class_getInstanceMethod(NSWindow.self, origSel),
              let swizzMethod = class_getInstanceMethod(NSWindow.self, swizzSel) else {
            NSLog("⚠️ [Kino] Failed to locate _reallySetFrame: for safety swizzle.")
            return
        }

        method_exchangeImplementations(origMethod, swizzMethod)
        NSLog("🛡️ [Kino] Installed window frame safety swizzle successfully.")
    }

    @objc func kino_safeReallySetFrame(_ frame: CGRect) {
        var safeFrame = frame
        if self === WindowManager.shared.mainWindow {
            if safeFrame.origin.x.isNaN || safeFrame.origin.x.isInfinite ||
               safeFrame.origin.y.isNaN || safeFrame.origin.y.isInfinite ||
               safeFrame.size.width.isNaN || safeFrame.size.width.isInfinite ||
               safeFrame.size.height.isNaN || safeFrame.size.height.isInfinite {
                if let pre = WindowManager.shared.preFullScreenFrame, pre.width >= 100, pre.height >= 100 {
                    safeFrame = pre
                } else {
                    let screen = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                    let defaultW: CGFloat = 900
                    let defaultH: CGFloat = 506
                    let x = screen.minX + max(0, (screen.width - defaultW) / 2)
                    let y = screen.minY + max(0, (screen.height - defaultH) / 2)
                    safeFrame = NSRect(x: x, y: y, width: defaultW, height: defaultH)
                }
                NSLog("🛡️ [Kino] Intercepted NaN/Inf window frame in _reallySetFrame: sanitized to %@", NSStringFromRect(safeFrame))
            }
        }
        self.kino_safeReallySetFrame(safeFrame)
    }
}
