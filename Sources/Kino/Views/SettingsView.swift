import SwiftUI
import AppKit

/// Apple-native macOS Settings window (⌘,).
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            playbackTab
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }
                .tag(1)

            subtitlesTab
                .tabItem {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
                .tag(2)

            enginesTab
                .tabItem {
                    Label("Engines", systemImage: "wrench.and.screwdriver")
                }
                .tag(3)
        }
        .frame(width: 480, height: 320)
        .padding(20)
    }

    // MARK: - General Tab

    @ObservedObject private var windowManager = WindowManager.shared

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Keep window always on top", isOn: Binding(
                    get: { windowManager.isPinnedAlwaysOnTop },
                    set: { _ in windowManager.togglePinAlwaysOnTop() }
                ))

                Text("Floating window remains above all other desktop applications.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button("Clear Playback Position History") {
                    UserDefaults.standard.removeObject(forKey: "Kino_PlaybackPositions_v1")
                    PlayerController.shared.showHUD(message: "Playback history cleared", iconName: "trash")
                }
                .controlSize(.regular)

                Text("Deletes saved timestamps for all previously played local files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Playback Tab

    @ObservedObject private var enhancer = VideoEnhancer.shared
    @ObservedObject private var audio = AudioManager.shared
    @ObservedObject private var player = PlayerController.shared

    private var playbackTab: some View {
        Form {
            Section("Video") {
                Toggle("Hardware Super-Resolution (Apple MetalFX)", isOn: $enhancer.isAutomaticSuperResolutionEnabled)

                Text("Automatically applies perceptual high-frequency spatial scaling on Retina displays for 720p and 1080p media.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Default Aspect Ratio", selection: Binding(
                    get: { player.isLetterboxed },
                    set: { player.isLetterboxed = $0 }
                )) {
                    Text("Fit to Screen (Letterbox)").tag(true)
                    Text("Fill Screen (Crop)").tag(false)
                }
            }

            Section("Audio") {
                Toggle("Enhance Dialogue", isOn: Binding(
                    get: { audio.isEnhanceDialogueEnabled },
                    set: { audio.setEnhanceDialogue($0) }
                ))

                Text("Isolates and amplifies vocal speech frequencies while softening loud sound effects and explosions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Subtitles Tab

    @ObservedObject private var subtitles = SubtitleManager.shared
    @ObservedObject private var openSubtitles = OpenSubtitlesService.shared

    private var subtitlesTab: some View {
        Form {
            Section("Placement & Appearance") {
                Picker("Default Subtitle Placement", selection: Binding(
                    get: { subtitles.placement },
                    set: { subtitles.setPlacement($0) }
                )) {
                    Text("In Letterbox Bar (Display Height)").tag(SubtitlePlacement.letterbox)
                    Text("Inside Video (Media Height)").tag(SubtitlePlacement.mediaFrame)
                }

                Text("Display Height places captions cleanly inside the black cinema bars below the picture.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("OpenSubtitles.com") {
                HStack {
                    Text("Account Status")
                    Spacer()
                    if openSubtitles.isLoggedIn {
                        Text("Logged in as \(openSubtitles.username ?? "User")")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Text("Free Guest Mode")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                }

                if openSubtitles.isLoggedIn {
                    if let quota = openSubtitles.remainingDailyQuota {
                        Text("\(quota) downloads remaining today.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Log Out") {
                        openSubtitles.logout()
                    }
                    .controlSize(.small)
                } else {
                    Text("Free registered accounts receive 20 subtitle downloads per 24 hours.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Engines Tab

    private var enginesTab: some View {
        Form {
            Section("Playback Engines") {
                engineStatusRow(name: "FFmpeg", tool: "ffmpeg")
                engineStatusRow(name: "FFprobe", tool: "ffprobe")
                engineStatusRow(name: "yt-dlp", tool: "yt-dlp")
            }

            Section {
                Button("Check for Updates / Reinstall Engines…") {
                    NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                }
                .controlSize(.regular)

                Text("Kino automatically manages lightweight static engines in user Application Support.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func engineStatusRow(name: String, tool: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            if let path = ToolLocator.shared.path(for: tool) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(path.contains("Application Support") ? "Managed" : "System")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text("Missing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
    }
}
