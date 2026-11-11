import Foundation
import AVFoundation
import Combine

/// Central manager orchestrating audio track detection, audio switching, and multichannel management.
@MainActor
public final class AudioManager: ObservableObject {
    public static let shared = AudioManager()
    private static let enhanceDialogueDefaultsKey = "KinoEnhanceDialogue"

    @Published public private(set) var availableTracks: [AudioTrack] = []
    @Published public private(set) var selectedTrack: AudioTrack? = nil
    @Published public private(set) var isEnhanceDialogueEnabled: Bool = {
        UserDefaults.standard.bool(forKey: "KinoEnhanceDialogue")
    }()

    private init() {}

    /// Toggles the Apple-style Enhance Dialogue speech clarity filter.
    public func toggleEnhanceDialogue() {
        setEnhanceDialogue(!isEnhanceDialogueEnabled)
    }

    /// Sets Enhance Dialogue state and updates user preferences.
    public func setEnhanceDialogue(_ enabled: Bool) {
        guard isEnhanceDialogueEnabled != enabled else { return }
        isEnhanceDialogueEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enhanceDialogueDefaultsKey)

        PlayerController.shared.showHUD(
            message: enabled ? "Enhance Dialogue: On" : "Enhance Dialogue: Off",
            iconName: enabled ? "quote.bubble.fill" : "quote.bubble"
        )
    }

    /// Updates the available audio tracks from container inspection or stream metadata.
    public func setAvailableTracks(_ tracks: [AudioTrack], defaultIndex: Int? = nil) {
        self.availableTracks = tracks
        if let idx = defaultIndex, let match = tracks.first(where: { $0.streamIndex == idx }) {
            self.selectedTrack = match
        } else if let def = tracks.first(where: { $0.isDefault }) {
            self.selectedTrack = def
        } else {
            self.selectedTrack = tracks.first
        }
    }

    /// Selects an audio track.
    public func selectTrack(_ track: AudioTrack) {
        guard selectedTrack?.id != track.id else { return }
        self.selectedTrack = track

        // Case 1: AVPlayer native playback (e.g. MP4/MOV)
        if MediaCoordinator.shared.activeStrategy?.isDirectNative == true {
            PlayerController.shared.syncNativeAudioSelection(for: track)
            return
        }

        // Case 2: FFmpeg remux / transcode pipeline
        Task {
            await MediaCoordinator.shared.switchAudioTrack(to: track)
        }
    }

    public func reset() {
        self.availableTracks.removeAll()
        self.selectedTrack = nil
    }
}
