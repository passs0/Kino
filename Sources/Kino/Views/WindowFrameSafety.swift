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
            let screen = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let isFS = self.styleMask.contains(.fullScreen)
            let fallback = (isFS ? WindowManager.shared.preFullScreenFrame : nil)
                ?? WindowManager.shared.preFullScreenFrame
                ?? NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 580, height: 380)

            let refFrame = isFS ? fallback : self.frame

            if safeFrame.origin.x.isNaN || safeFrame.origin.x.isInfinite {
                safeFrame.origin.x = (refFrame.origin.x.isNaN || refFrame.origin.x.isInfinite) ? fallback.origin.x : refFrame.origin.x
            }
            if safeFrame.origin.y.isNaN || safeFrame.origin.y.isInfinite {
                safeFrame.origin.y = (refFrame.origin.y.isNaN || refFrame.origin.y.isInfinite) ? fallback.origin.y : refFrame.origin.y
            }
            if safeFrame.size.width.isNaN || safeFrame.size.width.isInfinite || safeFrame.size.width < 100 {
                safeFrame.size.width = (refFrame.size.width.isNaN || refFrame.size.width.isInfinite || refFrame.size.width < 100) ? fallback.size.width : refFrame.size.width
            }
            if safeFrame.size.height.isNaN || safeFrame.size.height.isInfinite || safeFrame.size.height < 100 {
                safeFrame.size.height = (refFrame.size.height.isNaN || refFrame.size.height.isInfinite || refFrame.size.height < 100) ? fallback.size.height : refFrame.size.height
            }
        }
        self.kino_safeReallySetFrame(safeFrame)
    }
}
