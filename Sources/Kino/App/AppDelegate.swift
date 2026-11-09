import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        TrafficLightManager.shared.install()
        NowPlayingManager.shared.install()
        setupKeyboardShortcuts()

        // Handle file passed via CLI arguments if any
        let args = CommandLine.arguments.dropFirst().filter { !$0.starts(with: "-") }
        if let first = args.first {
            let url = URL(fileURLWithPath: first)
            Task { @MainActor in
                MediaCoordinator.shared.openLocalFile(url: url)
            }
        }
    }

    private func setupKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Allow typing when an active text field or editor is focused
            if let responder = NSApp.keyWindow?.firstResponder as? NSTextView, responder.isFieldEditor {
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else {
                return event // Do not intercept command/control shortcuts (like Cmd+W, Cmd+I)
            }

            let keyCode = event.keyCode
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

            // Escape (keyCode 53): Dismiss Media Statistics HUD if presented
            if keyCode == 53 && MainActor.assumeIsolated({ MediaCoordinator.shared.isInspectorPresented }) {
                MainActor.assumeIsolated {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        MediaCoordinator.shared.isInspectorPresented = false
                    }
                }
                return nil
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
                    NSApp.keyWindow?.toggleFullScreen(nil)
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

            return event
        }
    }

    public func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        Task { @MainActor in
            if application.windows.count > 1, let main = WindowManager.shared.mainWindow {
                for win in application.windows where win !== main {
                    win.close()
                }
            }
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
        true
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
        MediaCoordinator.shared.stop()
    }
}
