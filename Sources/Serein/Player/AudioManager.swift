import Foundation
import AVFoundation
import Combine

/// Central manager orchestrating audio track detection, audio switching, and multichannel management.
@MainActor
public final class AudioManager: ObservableObject {
    public static let shared = AudioManager()

    @Published public private(set) var availableTracks: [AudioTrack] = []
    @Published public private(set) var selectedTrack: AudioTrack? = nil

    private init() {}

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
