import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            NSLog("🔥 UNCAUGHT EXCEPTION: %@ - %@", exception.name.rawValue, exception.reason ?? "no reason")
            NSLog("🔥 CALL STACK: %@", exception.callStackSymbols.joined(separator: "\n"))
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindow.installFrameSafetySwizzle()
        TrafficLightManager.shared.install()
        NowPlayingManager.shared.install()
        setupKeyboardShortcuts()
        DispatchQueue.main.async { [weak self] in
            self?.cleanupDuplicateMenus()
        }

        // Handle file passed via CLI arguments if any
        let args = CommandLine.arguments.dropFirst().filter { !$0.starts(with: "-") }
        if let first = args.first {
            let url = URL(fileURLWithPath: first)
            Task { @MainActor in
                MediaCoordinator.shared.openLocalFile(url: url)
            }
        }
    }

    private func cleanupDuplicateMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        var seenTitles = Set<String>()
        var indicesToRemove: [Int] = []
        for (idx, item) in mainMenu.items.enumerated() {
            let title = item.title.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && seenTitles.contains(title) {
                indicesToRemove.append(idx)
            } else if !title.isEmpty {
                seenTitles.insert(title)
            }
        }
        for idx in indicesToRemove.reversed() {
            mainMenu.removeItem(at: idx)
        }
    }

    private func setupKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Allow typing when an active text field or editor is focused
            if let responder = NSApp.keyWindow?.firstResponder as? NSTextView, responder.isFieldEditor {
                return event
            }

            let isCommand = event.modifierFlags.contains(.command)
            let isControl = event.modifierFlags.contains(.control)
            let isOption = event.modifierFlags.contains(.option)
            let isShift = event.modifierFlags.contains(.shift)

            // Do not intercept command/control shortcuts (like Cmd+W, Cmd+I, Cmd+Q)
            guard !isCommand && !isControl else {
                return event
            }

            let keyCode = event.keyCode
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Option + G (⌥G): Reset Subtitle Delay to 0.0s
            if isOption && (keyCode == 5 || chars == "g") {
                Task { @MainActor in
                    SubtitleManager.shared.resetSubtitleDelay()
                }
                return nil
            }

            // If any other Option combination, pass through to system
            guard !isOption else {
                return event
            }

            // Escape (keyCode 53): Dismiss Media Statistics HUD if presented, or exit Full Screen
            if keyCode == 53 {
                if MainActor.assumeIsolated({ MediaCoordinator.shared.isInspectorPresented }) {
                    MainActor.assumeIsolated {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            MediaCoordinator.shared.isInspectorPresented = false
                        }
                    }
                    return nil
                } else if let win = WindowManager.shared.mainWindow, win.styleMask.contains(.fullScreen) {
                    WindowManager.shared.toggleFullScreen()
                    return nil
                }
            }

            // Space (keyCode 49): Play / Pause
            if keyCode == 49 {
                Task { @MainActor in
                    PlayerController.shared.togglePlayPause()
                }
                return nil
            }

            // Left Arrow (keyCode 123): Backward
            if keyCode == 123 {
                Task { @MainActor in
                    PlayerController.shared.seekRelative(seconds: -5.0)
                }
                return nil
            }

            // Right Arrow (keyCode 124): Fast Forward
            if keyCode == 124 {
                Task { @MainActor in
                    PlayerController.shared.seekRelative(seconds: 5.0)
                }
                return nil
            }

            // Plus / Equals / Up Arrow (keyCode 24, 69, 126, or char "+", "="): Volume Up
            if keyCode == 24 || keyCode == 69 || keyCode == 126 || chars == "+" || chars == "=" {
                Task { @MainActor in
                    PlayerController.shared.adjustVolume(by: 0.1)
                }
                return nil
            }

            // Minus / Dash / Down Arrow (keyCode 27, 78, 125, or char "-", "_"): Volume Down
            if keyCode == 27 || keyCode == 78 || keyCode == 125 || chars == "-" || chars == "_" {
                Task { @MainActor in
                    PlayerController.shared.adjustVolume(by: -0.1)
                }
                return nil
            }

            // J / j (keyCode 38 or char "j"): Rewind 10s
            if keyCode == 38 || chars == "j" {
                Task { @MainActor in
                    PlayerController.shared.seekRelative(seconds: -10.0)
                }
                return nil
            }

            // K / k (keyCode 40 or char "k"): Play / Pause
            if keyCode == 40 || chars == "k" {
                Task { @MainActor in
                    PlayerController.shared.togglePlayPause()
                }
                return nil
            }

            // L / l (keyCode 37 or char "l"): Forward 10s
            if keyCode == 37 || chars == "l" {
                Task { @MainActor in
                    PlayerController.shared.seekRelative(seconds: 10.0)
                }
                return nil
            }

            // F / f (keyCode 3 or char "f"): Toggle Full Screen
            if keyCode == 3 || chars == "f" {
                Task { @MainActor in
                    WindowManager.shared.toggleFullScreen()
                }
                return nil
            }

            // M / m (keyCode 46 or char "m"): Mute / Unmute
            if keyCode == 46 || chars == "m" {
                Task { @MainActor in
                    PlayerController.shared.toggleMute()
                }
                return nil
            }

            // Z / z (keyCode 6 or char "z"): Toggle Subtitle Placement (Display Height vs Media Height)
            if keyCode == 6 || chars == "z" {
                Task { @MainActor in
                    SubtitleManager.shared.togglePlacement()
                }
                return nil
            }

            // C / c (keyCode 8 or char "c"): Toggle Video Aspect Ratio (Fit vs Fill Screen)
            if keyCode == 8 || chars == "c" {
                Task { @MainActor in
                    PlayerController.shared.toggleLetterbox()
                }
                return nil
            }

            // G / g (keyCode 5 or char "g"): Subtitle Delay Earlier (-0.1s, or -0.5s with Shift)
            if keyCode == 5 || chars == "g" {
                let delta = isShift ? -0.5 : -0.1
                Task { @MainActor in
                    SubtitleManager.shared.adjustSubtitleDelay(by: delta)
                }
                return nil
            }

            // H / h (keyCode 4 or char "h"): Subtitle Delay Later (+0.1s, or +0.5s with Shift)
            if keyCode == 4 || chars == "h" {
                let delta = isShift ? 0.5 : 0.1
                Task { @MainActor in
                    SubtitleManager.shared.adjustSubtitleDelay(by: delta)
                }
                return nil
            }

            // . (keyCode 47 or char "."): Step Forward 1 Frame
            if !isShift && (keyCode == 47 || chars == ".") {
                Task { @MainActor in
                    PlayerController.shared.stepFrame(by: 1)
                }
                return nil
            }

            // , (keyCode 43 or char ","): Step Backward 1 Frame
            if !isShift && (keyCode == 43 || chars == ",") {
                Task { @MainActor in
                    PlayerController.shared.stepFrame(by: -1)
                }
                return nil
            }

            return event
        }
    }

    public func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        Task { @MainActor in
            MediaCoordinator.shared.openLocalFile(url: url)
            WindowManager.shared.mainWindow?.makeKeyAndOrderFront(nil)
        }
        application.reply(toOpenOrPrint: .success)
    }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        Task { @MainActor in
            MediaCoordinator.shared.openLocalFile(url: url)
            WindowManager.shared.mainWindow?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = WindowManager.shared.mainWindow {
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    public func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    public func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        performShutdown()
        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        performShutdown()
    }

    private func performShutdown() {
        PlayerController.shared.shutdownOnQuit()
        SleepPreventionManager.shared.setSleepDisabled(false)
        SubtitleManager.shared.reset()
        MediaCoordinator.shared.stop()
    }
}
