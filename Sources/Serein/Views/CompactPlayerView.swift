import SwiftUI
import AppKit

/// Sleek macOS Liquid Glass Compact MiniPlayer for Music and Background Audio.
public struct CompactPlayerView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject var playerController: PlayerController
    @ObservedObject var timeState = PlayerTimeState.shared
    @ObservedObject var windowManager = WindowManager.shared

    @State private var isDraggingTimeline = false
    @State private var dragScrubTime: Double = 0
    @State private var wasPlayingBeforeScrub = false

    public init(coordinator: MediaCoordinator, playerController: PlayerController) {
        self.coordinator = coordinator
        self.playerController = playerController
    }

    private var activeDuration: Double {
        if let kd = coordinator.knownDuration, kd > 0 { return kd }
        if timeState.duration > 0 { return timeState.duration }
        return 0
    }

    private var activeCurrentTime: Double {
        isDraggingTimeline ? dragScrubTime : timeState.currentTime
    }

    private var displayTitle: String {
        coordinator.probeResult?.trackTitle ?? coordinator.currentSource?.displayName ?? "Audio Track"
    }

    private var displayArtistAndAlbum: String {
        if let artist = coordinator.probeResult?.trackArtist {
            if let album = coordinator.probeResult?.trackAlbum {
                return "\(artist) — \(album)"
            }
            return artist
        }
        return "Unknown Artist"
    }

    private var codecLabel: String {
        if let audio = coordinator.probeResult?.primaryAudio {
            let codec = audio.codecName.uppercased()
            if let rate = audio.sampleRate, rate > 0 {
                let khz = String(format: "%.1f kHz", Double(rate) / 1000.0)
                return "\(codec) · \(khz)"
            }
            return codec
        }
        return "AUDIO"
    }

    public var body: some View {
        ZStack {
            // Dark liquid glass base
            Color(white: 0.08)
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                // Top Utility Bar: Traffic light breathing room on left, Pin & Expand on right
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 68)

                    Spacer()

                    // Always-on-Top Pin Button
                    Button(action: {
                        windowManager.togglePinAlwaysOnTop()
                    }) {
                        Image(systemName: windowManager.isPinnedAlwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(windowManager.isPinnedAlwaysOnTop ? .yellow : .white.opacity(0.70))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(windowManager.isPinnedAlwaysOnTop ? 0.18 : 0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(windowManager.isPinnedAlwaysOnTop ? "Unpin from Always-on-Top" : "Pin Always-on-Top")

                    // Expand to Full Canvas Button
                    Button(action: {
                        windowManager.setMiniPlayer(false)
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.70))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Expand to Full Player (⌥⌘M)")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Main Content: Cover Art + Track Details & Controls
                HStack(spacing: 12) {
                    // Artwork Squircle (76×76)
                    ZStack {
                        if let art = coordinator.currentArtwork {
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.40), radius: 8, x: 0, y: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 76, height: 76)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)

                            Image(systemName: "music.note")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(.white.opacity(0.95))
                        }
                    }

                    // Metadata + Timeline + Controls Column
                    VStack(alignment: .leading, spacing: 4) {
                        // Title & Formatted Time (Clean Proportional Typography)
                        HStack(alignment: .firstTextBaseline) {
                            Text(displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            Text(timeDisplayText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                        }

                        // Artist / Album & Codec Badge
                        HStack(spacing: 6) {
                            Text(displayArtistAndAlbum)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.70))
                                .lineLimit(1)

                            Text(codecLabel)
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                                .foregroundColor(.white.opacity(0.85))
                        }

                        // Apple Native AppKit Timeline Slider
                        NativeSlider(
                            value: Binding(
                                get: { isDraggingTimeline ? dragScrubTime : activeCurrentTime },
                                set: { target in
                                    dragScrubTime = target
                                    playerController.seek(to: target)
                                }
                            ),
                            in: 0.0...max(activeDuration, 1.0),
                            trackFillColor: .white,
                            onEditingChanged: { isEditing in
                                if isEditing {
                                    isDraggingTimeline = true
                                    wasPlayingBeforeScrub = playerController.isPlaying
                                    if wasPlayingBeforeScrub {
                                        playerController.pause()
                                    }
                                } else {
                                    isDraggingTimeline = false
                                    playerController.seek(to: dragScrubTime)
                                    if wasPlayingBeforeScrub {
                                        playerController.play()
                                        wasPlayingBeforeScrub = false
                                    }
                                }
                            }
                        )
                        .frame(height: 20)

                        // Transport Controls Row
                        HStack(spacing: 14) {
                            Button(action: {
                                playerController.seekRelative(seconds: -10)
                            }) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Rewind 10 seconds")

                            Button(action: {
                                playerController.togglePlayPause()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 26, height: 26)

                                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                        .offset(x: playerController.isPlaying ? 0 : 0.5)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(playerController.isPlaying ? "Pause (Space)" : "Play (Space)")

                            Button(action: {
                                playerController.seekRelative(seconds: 10)
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Fast Forward 10 seconds")

                            Spacer()

                            // Native Mini Volume Control
                            HStack(spacing: 5) {
                                Button(action: {
                                    playerController.isMuted.toggle()
                                }) {
                                    Image(systemName: playerController.isMuted || playerController.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.70))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)

                                // Apple Native AppKit Volume Slider
                                NativeSlider(
                                    value: Binding(
                                        get: { Double(playerController.isMuted ? 0 : playerController.volume) },
                                        set: { newVol in
                                            playerController.volume = Float(newVol)
                                            if playerController.isMuted { playerController.isMuted = false }
                                        }
                                    ),
                                    in: 0.0...1.0,
                                    trackFillColor: .white
                                )
                                .frame(width: 64, height: 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 420, maxWidth: 620, minHeight: 130, maxHeight: 160)
    }

    private var timeDisplayText: String {
        let cur = formatSeconds(activeCurrentTime)
        let dur = formatSeconds(activeDuration)
        return "\(cur) / \(dur)"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let secs = total % 60
        let mins = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%02d:%02d", mins, secs)
        }
    }
}


