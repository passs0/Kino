import Foundation

/// Manages persistent playback timestamps in UserDefaults to allow seamless resume across restarts and accidental quits.
public final class PlaybackResumeManager: @unchecked Sendable {
    public static let shared = PlaybackResumeManager()

    private let userDefaultsKey = "Serein_PlaybackPositions_v1"
    private let lock = NSLock()

    private init() {}

    /// Canonical storage key for a MediaSource (normalized file path or URL string).
    public func key(for source: MediaSource) -> String {
        switch source {
        case .local(let fileURL):
            return "local:\(fileURL.standardizedFileURL.path)"
        case .online(let webURL, _):
            return "online:\(webURL.absoluteString)"
        }
    }

    /// Retrieves the saved timestamp (in seconds) for a media source, or nil if none or finished.
    public func savedPosition(for source: MediaSource) -> Double? {
        let k = key(for: source)
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] ?? [:]
        guard let pos = dict[k], pos > 3.0 else { return nil }
        return pos
    }

    /// Saves the current playback timestamp for a media source.
    /// If near the end (> 95% or remaining < 15s), the record is cleared so subsequent playback starts from the beginning.
    public func savePosition(_ seconds: Double, duration: Double, for source: MediaSource) {
        guard seconds.isFinite, !seconds.isNaN, seconds > 0 else { return }
        let k = key(for: source)
        lock.lock()
        defer { lock.unlock() }

        var dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] ?? [:]

        // If completed or near completion, remove to avoid resuming in the end credits
        if duration > 15.0 && (seconds >= duration - 15.0 || (seconds / duration) >= 0.96) {
            dict.removeValue(forKey: k)
        } else if seconds >= 5.0 {
            dict[k] = seconds
            // Cap history to 200 items
            if dict.count > 250 {
                let keysToRemove = Array(dict.keys.prefix(50))
                for remK in keysToRemove { dict.removeValue(forKey: remK) }
            }
        }

        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
    }

    /// Clears the saved position for a specific media source.
    public func clearPosition(for source: MediaSource) {
        let k = key(for: source)
        lock.lock()
        defer { lock.unlock() }
        var dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: Double] ?? [:]
        dict.removeValue(forKey: k)
        UserDefaults.standard.set(dict, forKey: userDefaultsKey)
    }
}
