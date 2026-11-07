import SwiftUI
import AppKit

public struct SereinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var windowManager = WindowManager.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(
                    minWidth: 380,
                    minHeight: 400
                )
                .onOpenURL { url in
                    Task { @MainActor in
                        if url.isFileURL {
                            MediaCoordinator.shared.openLocalFile(url: url)
                        } else {
                            MediaCoordinator.shared.openOnlineURL(string: url.absoluteString)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Media Engines & Codecs...") {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Check for Engine Updates...") {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Open Media File...") {
                    openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Online URL...") {
                    NotificationCenter.default.post(name: .openURLSheetNotification, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)

                Divider()

                Button("Close Video") {
                    NotificationCenter.default.post(name: .closeMediaNotification, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Playback") {
                Button(PlayerController.shared.isPlaying ? "Pause" : "Play") {
                    PlayerController.shared.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Seek Forward 10s") {
                    PlayerController.shared.seekRelative(seconds: 10)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Seek Backward 10s") {
                    PlayerController.shared.seekRelative(seconds: -10)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button(PlayerController.shared.isMuted ? "Unmute" : "Mute") {
                    PlayerController.shared.toggleMute()
                }
                .keyboardShortcut("m", modifiers: .command)

                Divider()

                Menu("Subtitle Placement") {
                    Button("In Letterbox Bar (Display Height)") {
                        SubtitleManager.shared.setPlacement(.letterbox)
                    }
                    Button("Inside Video (Media Height)") {
                        SubtitleManager.shared.setPlacement(.mediaFrame)
                    }

                    Divider()

                    Button("Toggle Subtitle Placement") {
                        SubtitleManager.shared.togglePlacement()
                    }
                }
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Media Inspector") {
                    withAnimation {
                        MediaCoordinator.shared.isInspectorPresented.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button(windowManager.isPinnedAlwaysOnTop ? "Unpin from Always on Top" : "Keep Window Always on Top") {
                    WindowManager.shared.togglePinAlwaysOnTop()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                MediaCoordinator.shared.openLocalFile(url: url)
            }
        }
    }
}

public extension Notification.Name {
    static let openURLSheetNotification = Notification.Name("SereinOpenURLSheetNotification")
    static let openPrerequisitesSheetNotification = Notification.Name("SereinOpenPrerequisitesSheetNotification")
    static let closeMediaNotification = Notification.Name("SereinCloseMediaNotification")
}
