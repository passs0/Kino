import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Presents the native macOS WebKit HTML5 video options menu via NSMenu.
/// This completely bypasses SwiftUI body invalidation during playback, eliminating menu blinking
/// and ensuring submenus open immediately and smoothly.
@MainActor
public final class OptionsMenuPresenter: NSObject {
    public static let shared = OptionsMenuPresenter()

    private override init() {
        super.init()
    }

    public func show(from event: NSEvent? = nil, in view: NSView? = nil) {
        let menu = NSMenu(title: "Playback Options")
        menu.autoenablesItems = false

        let isAudio = MediaCoordinator.shared.probeResult?.isAudioOnly == true
            || MediaCoordinator.shared.currentSource?.isAudioTrack == true

        if isAudio {
            // MARK: - Audio Mode (Spacious & Clean Options Menu)

            // 1. Audio Tracks Submenu (if multiple streams available)
            let audioTracks = AudioManager.shared.availableTracks
            if audioTracks.count > 1 {
                let audioItem = createMenuItem(title: "Audio Track", systemImage: "waveform")
                let audioMenu = NSMenu(title: "Audio Track")
                audioMenu.autoenablesItems = false
                let currentAudio = AudioManager.shared.selectedTrack

                for track in audioTracks {
                    let item = NSMenuItem(title: track.name, action: #selector(handleSelectAudioTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = track
                    item.state = (currentAudio?.id == track.id) ? .on : .off
                    audioMenu.addItem(item)
                }

                audioItem.submenu = audioMenu
                menu.addItem(audioItem)
            }

            // 2. Subtitles / Lyrics Submenu
            let subsItem = createMenuItem(title: "Subtitles / Lyrics", systemImage: "quote.bubble")
            let subsMenu = NSMenu(title: "Subtitles / Lyrics")
            subsMenu.autoenablesItems = false

            let currentSub = SubtitleManager.shared.selectedTrack

            let offItem = NSMenuItem(title: "Off", action: #selector(handleSelectSubOff), keyEquivalent: "")
            offItem.target = self
            offItem.state = (currentSub == nil) ? .on : .off
            subsMenu.addItem(offItem)

            let subTracks = SubtitleManager.shared.availableTracks
            if !subTracks.isEmpty {
                subsMenu.addItem(NSMenuItem.separator())
                for track in subTracks {
                    let item = NSMenuItem(title: track.name, action: #selector(handleSelectTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = track
                    item.state = (currentSub?.id == track.id) ? .on : .off
                    subsMenu.addItem(item)
                }
            }

            subsMenu.addItem(NSMenuItem.separator())
            let loadAudioSubsItem = createMenuItem(title: "Load External Lyrics/Subtitles…", systemImage: "folder", action: #selector(handleLoadExternalSubtitles))
            subsMenu.addItem(loadAudioSubsItem)

            subsItem.submenu = subsMenu
            menu.addItem(subsItem)

            menu.addItem(NSMenuItem.separator())

            // 3. Playback Speed Submenu
            let speedItem = createMenuItem(title: "Playback Speed", systemImage: "gauge.with.needle")
            let speedMenu = NSMenu(title: "Playback Speed")
            speedMenu.autoenablesItems = false

            let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
            let currentRate = PlayerController.shared.playbackRate
            for r in rates {
                let label = r == 1.0 ? "1x" : "\(formatRate(Double(r)))x"
                let item = NSMenuItem(title: label, action: #selector(handleSelectSpeed(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = r
                item.state = (abs(currentRate - r) < 0.01) ? .on : .off
                speedMenu.addItem(item)
            }

            speedItem.submenu = speedMenu
            menu.addItem(speedItem)

            menu.addItem(NSMenuItem.separator())

            // 4. Media Statistics & Codec Inspector
            let isInspectorOpen = MediaCoordinator.shared.isInspectorPresented
            let statsItem = createMenuItem(
                title: isInspectorOpen ? "Hide Media Statistics" : "Show Media Statistics",
                systemImage: "chart.bar.xaxis",
                action: #selector(handleToggleStats),
                keyEquivalent: "i"
            )
            statsItem.state = isInspectorOpen ? .on : .off
            menu.addItem(statsItem)

            // 5. Media Engines & Codecs Setup
            let enginesItem = createMenuItem(
                title: "Media Engines & Codecs...",
                systemImage: "gearshape",
                action: #selector(handleOpenEngines),
                keyEquivalent: ","
            )
            menu.addItem(enginesItem)

        } else {
            // MARK: - Video Mode (Spacious & Clean Options Menu)

            // 1. Subtitles Submenu
            let subsItem = createMenuItem(title: "Subtitles", systemImage: "captions.bubble")
            let subsMenu = NSMenu(title: "Subtitles")
            subsMenu.autoenablesItems = false

            let currentSub = SubtitleManager.shared.selectedTrack

            // Off option
            let offItem = NSMenuItem(title: "Off", action: #selector(handleSelectSubOff), keyEquivalent: "")
            offItem.target = self
            offItem.state = (currentSub == nil) ? .on : .off
            subsMenu.addItem(offItem)

            let tracks = SubtitleManager.shared.availableTracks
            if !tracks.isEmpty {
                subsMenu.addItem(NSMenuItem.separator())

                let manual = tracks.filter { !$0.isAutoGenerated }
                for track in manual {
                    let item = NSMenuItem(title: track.name, action: #selector(handleSelectTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = track
                    item.state = (currentSub?.id == track.id) ? .on : .off
                    subsMenu.addItem(item)
                }

                let auto = tracks.filter { $0.isAutoGenerated }
                if !auto.isEmpty {
                    subsMenu.addItem(NSMenuItem.separator())
                    for track in auto {
                        let item = NSMenuItem(title: track.name, action: #selector(handleSelectTrack(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = track
                        item.state = (currentSub?.id == track.id) ? .on : .off
                        subsMenu.addItem(item)
                    }
                }
            } else {
                subsMenu.addItem(NSMenuItem.separator())
                let noneItem = NSMenuItem(title: "No Subtitles Available", action: nil, keyEquivalent: "")
                noneItem.isEnabled = false
                subsMenu.addItem(noneItem)
            }

            subsMenu.addItem(NSMenuItem.separator())
            let loadExternalItem = createMenuItem(title: "Load External Subtitles…", systemImage: "folder", action: #selector(handleLoadExternalSubtitles))
            subsMenu.addItem(loadExternalItem)

            subsMenu.addItem(NSMenuItem.separator())

            // Subtitle Placement Submenu (Display Height vs Media Height)
            let placementItem = createMenuItem(title: "Placement", systemImage: "arrow.up.and.down.text.horizontal")
            let placementMenu = NSMenu(title: "Placement")
            placementMenu.autoenablesItems = false

            let curPlacement = SubtitleManager.shared.placement

            let letterboxItem = NSMenuItem(
                title: "In Letterbox Bar (Display Height)",
                action: #selector(handleSetPlacementLetterbox),
                keyEquivalent: ""
            )
            letterboxItem.target = self
            letterboxItem.state = (curPlacement == .letterbox) ? .on : .off
            placementMenu.addItem(letterboxItem)

            let mediaItem = NSMenuItem(
                title: "Inside Video (Media Height)",
                action: #selector(handleSetPlacementMediaFrame),
                keyEquivalent: ""
            )
            mediaItem.target = self
            mediaItem.state = (curPlacement == .mediaFrame) ? .on : .off
            placementMenu.addItem(mediaItem)

            placementItem.submenu = placementMenu
            subsMenu.addItem(placementItem)

            subsItem.submenu = subsMenu
            menu.addItem(subsItem)

            // 2. Audio Track Submenu
            let audioItem = createMenuItem(title: "Audio Track", systemImage: "waveform")
            let audioMenu = NSMenu(title: "Audio Track")
            audioMenu.autoenablesItems = false

            let audioTracks = AudioManager.shared.availableTracks
            let currentAudio = AudioManager.shared.selectedTrack

            if !audioTracks.isEmpty {
                for track in audioTracks {
                    let item = NSMenuItem(title: track.name, action: #selector(handleSelectAudioTrack(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = track
                    item.state = (currentAudio?.id == track.id) ? .on : .off
                    audioMenu.addItem(item)
                }
            } else {
                let defaultItem = NSMenuItem(title: "Default Audio", action: nil, keyEquivalent: "")
                defaultItem.isEnabled = false
                defaultItem.state = .on
                audioMenu.addItem(defaultItem)
            }

            audioItem.submenu = audioMenu
            menu.addItem(audioItem)

            menu.addItem(NSMenuItem.separator())

            // 3. Playback Speed Submenu
            let speedItem = createMenuItem(title: "Playback Speed", systemImage: "gauge.with.needle")
            let speedMenu = NSMenu(title: "Playback Speed")
            speedMenu.autoenablesItems = false

            let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
            let currentRate = PlayerController.shared.playbackRate
            for r in rates {
                let label = r == 1.0 ? "1x" : "\(formatRate(Double(r)))x"
                let item = NSMenuItem(title: label, action: #selector(handleSelectSpeed(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = r
                item.state = (abs(currentRate - r) < 0.01) ? .on : .off
                speedMenu.addItem(item)
            }

            speedItem.submenu = speedMenu
            menu.addItem(speedItem)

            // 4. Aspect Ratio Submenu
            let aspectItem = createMenuItem(title: "Aspect Ratio", systemImage: "aspectratio")
            let aspectMenu = NSMenu(title: "Aspect Ratio")
            aspectMenu.autoenablesItems = false

            let isLetterboxed = PlayerController.shared.isLetterboxed

            let fitItem = NSMenuItem(title: "Fit to Screen (Preserve Aspect)", action: #selector(handleSetLetterboxFit), keyEquivalent: "")
            fitItem.target = self
            fitItem.state = isLetterboxed ? .on : .off
            aspectMenu.addItem(fitItem)

            let fillItem = NSMenuItem(title: "Fill Screen (Crop)", action: #selector(handleSetLetterboxFill), keyEquivalent: "")
            fillItem.target = self
            fillItem.state = (!isLetterboxed) ? .on : .off
            aspectMenu.addItem(fillItem)

            aspectItem.submenu = aspectMenu
            menu.addItem(aspectItem)

            // 5. Video Upscaler & Enhancer Submenu (GPU-accelerated native upscaling)
            let enhanceItem = createMenuItem(title: "Video Upscaler & Enhancer", systemImage: "sparkles")
            let enhanceMenu = NSMenu(title: "Video Upscaler & Enhancer")
            enhanceMenu.autoenablesItems = false

            let currentMode = VideoEnhancer.shared.activeMode
            for mode in VideoEnhancer.EnhancementMode.allCases {
                let item = NSMenuItem(title: mode.rawValue, action: #selector(handleSelectEnhancementMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mode
                item.state = (currentMode == mode) ? .on : .off
                item.toolTip = mode.shortDescription
                enhanceMenu.addItem(item)
            }

            enhanceItem.submenu = enhanceMenu
            menu.addItem(enhanceItem)

            menu.addItem(NSMenuItem.separator())

            // 6. Media Statistics (Canonical access point for media information & technical inspector)
            let isInspectorOpen = MediaCoordinator.shared.isInspectorPresented
            let statsItem = createMenuItem(
                title: isInspectorOpen ? "Hide Media Statistics" : "Show Media Statistics",
                systemImage: "chart.bar.xaxis",
                action: #selector(handleToggleStats),
                keyEquivalent: "i"
            )
            statsItem.state = isInspectorOpen ? .on : .off
            menu.addItem(statsItem)

            // 7. Media Engines & Codecs Setup
            let enginesItem = createMenuItem(
                title: "Media Engines & Codecs...",
                systemImage: "gearshape",
                action: #selector(handleOpenEngines),
                keyEquivalent: ","
            )
            menu.addItem(enginesItem)
        }

        // Pop up the menu at the cursor event position or comfortably above the HUD pill
        if let ev = event, (ev.type == .rightMouseDown || ev.type == .leftMouseDown), let win = NSApp.keyWindow ?? NSApp.windows.first {
            let targetView = view ?? win.contentView ?? NSView()
            NSMenu.popUpContextMenu(menu, with: ev, for: targetView)
        } else if let win = NSApp.keyWindow ?? NSApp.windows.first, let cv = view ?? win.contentView {
            let mousePt = cv.convert(win.mouseLocationOutsideOfEventStream, from: nil)
            // Position comfortably above HUD pill so bottom shadow doesn't overlap the ellipsis button
            let pt = NSPoint(x: mousePt.x, y: max(mousePt.y + 22, 78))
            menu.popUp(positioning: nil, at: pt, in: cv)
        }
    }

    private func createMenuItem(
        title: String,
        systemImage: String? = nil,
        action: Selector? = nil,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifierMask
        }
        if let icon = systemImage, let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            img.isTemplate = true
            item.image = img
        }
        return item
    }

    @objc private func handleSelectSubOff() {
        SubtitleManager.shared.selectTrack(nil)
    }

    @objc private func handleSetPlacementLetterbox() {
        SubtitleManager.shared.setPlacement(.letterbox)
    }

    @objc private func handleSetPlacementMediaFrame() {
        SubtitleManager.shared.setPlacement(.mediaFrame)
    }

    @objc private func handleSelectTrack(_ sender: NSMenuItem) {
        if let track = sender.representedObject as? SubtitleTrack {
            SubtitleManager.shared.selectTrack(track)
        }
    }

    @objc private func handleLoadExternalSubtitles() {
        let panel = NSOpenPanel()
        panel.title = "Load Subtitles or Lyrics"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .text,
            UTType(filenameExtension: "vtt") ?? .text,
            UTType(filenameExtension: "ass") ?? .text,
            UTType(filenameExtension: "ssa") ?? .text,
            UTType(filenameExtension: "sub") ?? .text,
            UTType(filenameExtension: "lrc") ?? .text
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            SubtitleManager.shared.loadExternalSubtitle(from: url)
        }
    }

    @objc private func handleSelectAudioTrack(_ sender: NSMenuItem) {
        if let track = sender.representedObject as? AudioTrack {
            AudioManager.shared.selectTrack(track)
        }
    }

    @objc private func handleSelectSpeed(_ sender: NSMenuItem) {
        if let rate = sender.representedObject as? Float {
            PlayerController.shared.playbackRate = rate
        }
    }

    @objc private func handleSetLetterboxFit() {
        PlayerController.shared.isLetterboxed = true
    }

    @objc private func handleSetLetterboxFill() {
        PlayerController.shared.isLetterboxed = false
    }

    @objc private func handleSelectEnhancementMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? VideoEnhancer.EnhancementMode {
            VideoEnhancer.shared.setMode(mode)
        }
    }

    @objc private func handleToggleStats() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            MediaCoordinator.shared.isInspectorPresented.toggle()
        }
    }

    @objc private func handleOpenEngines() {
        NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(format: "%.0f", rate)
        }
        return String(format: "%g", rate)
    }
}
