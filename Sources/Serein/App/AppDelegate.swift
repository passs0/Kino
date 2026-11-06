import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        setupKeyboardShortcuts()
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

            // Plus / Equals / Keypad Plus (keyCode 24, 69, or char "+", "="): Volume Up
            if keyCode == 24 || keyCode == 69 || chars == "+" || chars == "=" {
                Task { @MainActor in
                    PlayerController.shared.adjustVolume(by: 0.1)
                }
                return nil
            }

            // Minus / Dash / Keypad Minus (keyCode 27, 78, or char "-", "_"): Volume Down
            if keyCode == 27 || keyCode == 78 || chars == "-" || chars == "_" {
                Task { @MainActor in
                    PlayerController.shared.adjustVolume(by: -0.1)
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
            MediaCoordinator.shared.openLocalFile(url: url)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await PlayerController.shared.shutdownAudioCleanly()
            MediaCoordinator.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    public func applicationWillTerminate(_ notification: Notification) {
        PlayerController.shared.player.volume = 0
        PlayerController.shared.player.isMuted = true
        PlayerController.shared.player.pause()
        MediaCoordinator.shared.stop()
    }
}
