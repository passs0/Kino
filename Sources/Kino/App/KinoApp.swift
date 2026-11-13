import SwiftUI
import AppKit

public struct KinoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {}

    public var body: some Scene {
        Window("Kino", id: "main") {
            MainWindowView()
                .ignoresSafeArea()
                .onOpenURL { url in
                    Task { @MainActor in
                        handleIncomingURL(url)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 580, height: 380)

        Settings {
            SettingsView()
        }
        .commands {
            KinoCommands()
        }
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }

        if url.isFileURL {
            MediaCoordinator.shared.openLocalFile(url: url)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "kino" || scheme == "serein" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if components.host?.lowercased() == "open" {
                    if let targetURL = components.queryItems?.first(where: { $0.name == "url" })?.value {
                        let timeParam = components.queryItems?.first(where: { $0.name == "time" })?.value
                        let initTime = timeParam.flatMap { Double($0) }
                        MediaCoordinator.shared.openOnlineURL(string: targetURL, initialTime: initTime)
                        return
                    }
                }
            }

            let absolute = url.absoluteString
            for prefix in ["kino://", "serein://"] {
                if absolute.hasPrefix(prefix) {
                    let stripped = String(absolute.dropFirst(prefix.count))
                    if stripped.hasPrefix("http://") || stripped.hasPrefix("https://") {
                        MediaCoordinator.shared.openOnlineURL(string: stripped)
                        return
                    }
                }
            }
        }

        MediaCoordinator.shared.openOnlineURL(string: url.absoluteString)
    }
}

// MARK: - Native Commands
struct KinoCommands: Commands {
    @ObservedObject var windowManager = WindowManager.shared
    @ObservedObject var playerController = PlayerController.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Media File…") {
                openFileDialog()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Online URL…") {
                NotificationCenter.default.post(name: .openURLSheetNotification, object: nil)
            }
            .keyboardShortcut("u", modifiers: .command)

            Menu("Open Recent") {
                let recents = NSDocumentController.shared.recentDocumentURLs
                if recents.isEmpty {
                    Text("No Recent Documents")
                } else {
                    ForEach(recents.prefix(10), id: \.self) { url in
                        Button(url.lastPathComponent) {
                            Task { @MainActor in
                                MediaCoordinator.shared.openLocalFile(url: url)
                            }
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }
            }

            Divider()

            Button("Close") {
                NotificationCenter.default.post(name: .closeMediaNotification, object: nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(replacing: .sidebar) {
            Button("Actual Size") {
                WindowManager.shared.zoomToActualSize()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Double Size") {
                WindowManager.shared.zoomToDoubleSize()
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Fit to Screen") {
                WindowManager.shared.zoomToFitScreen()
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Enter Full Screen") {
                WindowManager.shared.toggleFullScreen()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])

            Divider()

            Button(windowManager.isPinnedAlwaysOnTop ? "Unpin from Always on Top" : "Keep Window Always on Top") {
                WindowManager.shared.togglePinAlwaysOnTop()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button(playerController.isLoopEnabled ? "Disable Loop" : "Loop") {
                PlayerController.shared.toggleLoop()
            }
            .keyboardShortcut("l", modifiers: [.option, .command])

            Divider()

            Menu("Chapters") {
                if playerController.chapters.isEmpty {
                    Text("No Chapters")
                } else {
                    Button("Previous Chapter") {
                        PlayerController.shared.previousChapter()
                    }
                    .keyboardShortcut("[", modifiers: .command)

                    Button("Next Chapter") {
                        PlayerController.shared.nextChapter()
                    }
                    .keyboardShortcut("]", modifiers: .command)

                    Divider()

                    let currentChapID = playerController.currentChapter?.id
                    ForEach(playerController.chapters) { chapter in
                        Button {
                            PlayerController.shared.jumpToChapter(chapter)
                        } label: {
                            if chapter.id == currentChapID {
                                Label("\(chapter.title) (\(chapter.formattedStartTime))", systemImage: "checkmark")
                            } else {
                                Text("\(chapter.title) (\(chapter.formattedStartTime))")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Movie Inspector") {
                withAnimation {
                    MediaCoordinator.shared.isInspectorPresented.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandMenu("Playback") {
            Button(playerController.isPlaying ? "Pause" : "Play") {
                PlayerController.shared.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Step Forward 5s") {
                PlayerController.shared.seekRelative(seconds: 5)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Step Backward 5s") {
                PlayerController.shared.seekRelative(seconds: -5)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Jump Forward 30s") {
                PlayerController.shared.seekRelative(seconds: 30)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Jump Backward 30s") {
                PlayerController.shared.seekRelative(seconds: -30)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Step Forward 1 Frame") {
                PlayerController.shared.stepFrame(by: 1)
            }
            .keyboardShortcut(".", modifiers: [])

            Button("Step Backward 1 Frame") {
                PlayerController.shared.stepFrame(by: -1)
            }
            .keyboardShortcut(",", modifiers: [])

            Divider()

            Button(PlayerController.shared.isMuted ? "Unmute" : "Mute") {
                PlayerController.shared.toggleMute()
            }
            .keyboardShortcut("m", modifiers: [])

            Button(AudioManager.shared.isEnhanceDialogueEnabled ? "Disable Enhance Dialogue" : "Enhance Dialogue") {
                AudioManager.shared.toggleEnhanceDialogue()
            }

            Divider()

            Menu("Playback Speed") {
                ForEach(PlaybackSpeedMenuPresenter.availableRates, id: \.self) { r in
                    Button {
                        PlayerController.shared.playbackRate = r
                        let label = r == 1.0 ? "1× (Normal)" : "\(PlaybackSpeedMenuPresenter.formatRate(r))×"
                        PlayerController.shared.showHUD(message: "Playback Speed: \(label)", iconName: "gauge.with.dots.needle.50percent")
                    } label: {
                        let label = r == 1.0 ? "1× (Normal)" : "\(PlaybackSpeedMenuPresenter.formatRate(r))×"
                        if abs(playerController.playbackRate - r) < 0.01 {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }

            Divider()

            Menu("Subtitles") {
                Button("Search Subtitles Online…") {
                    NotificationCenter.default.post(name: .openSubtitleSearchSheetNotification, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Divider()

                Menu("Subtitle Delay") {
                    Button("Earlier by 0.5s") {
                        SubtitleManager.shared.adjustSubtitleDelay(by: -0.5)
                    }
                    .keyboardShortcut("G", modifiers: [.shift])

                    Button("Earlier by 0.1s") {
                        SubtitleManager.shared.adjustSubtitleDelay(by: -0.1)
                    }
                    .keyboardShortcut("g", modifiers: [])

                    Button("Reset Delay to 0.0s") {
                        SubtitleManager.shared.resetSubtitleDelay()
                    }
                    .keyboardShortcut("g", modifiers: [.option])

                    Button("Later by 0.1s") {
                        SubtitleManager.shared.adjustSubtitleDelay(by: 0.1)
                    }
                    .keyboardShortcut("h", modifiers: [])

                    Button("Later by 0.5s") {
                        SubtitleManager.shared.adjustSubtitleDelay(by: 0.5)
                    }
                    .keyboardShortcut("H", modifiers: [.shift])
                }

                Divider()

                Menu("Placement") {
                    Button("In Letterbox Bar (Display Height)") {
                        SubtitleManager.shared.setPlacement(.letterbox)
                    }
                    Button("Inside Video (Media Height)") {
                        SubtitleManager.shared.setPlacement(.mediaFrame)
                    }

                    Divider()

                    Button("Toggle Placement") {
                        SubtitleManager.shared.togglePlacement()
                    }
                    .keyboardShortcut("z", modifiers: [])
                }
            }

            Button("Toggle Aspect Ratio (Fit / Fill)") {
                PlayerController.shared.toggleLetterbox()
            }
            .keyboardShortcut("c", modifiers: [])
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
    static let openURLSheetNotification = Notification.Name("KinoOpenURLSheetNotification")
    static let openPrerequisitesSheetNotification = Notification.Name("KinoOpenPrerequisitesSheetNotification")
    static let openSubtitleSearchSheetNotification = Notification.Name("KinoOpenSubtitleSearchSheetNotification")
    static let closeMediaNotification = Notification.Name("KinoCloseMediaNotification")
}
