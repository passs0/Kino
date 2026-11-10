import Foundation

/// Represents the origin of a media asset in Kino.
public enum MediaSource: Identifiable, Hashable, Sendable {
    case local(URL)
    case online(url: URL, originalInput: String)

    public var id: String {
        switch self {
        case .local(let url):
            return "local:\(url.path)"
        case .online(let url, let originalInput):
            return "online:\(originalInput):\(url.absoluteString)"
        }
    }

    public var displayName: String {
        switch self {
        case .local(let url):
            return url.lastPathComponent
        case .online(let url, let originalInput):
            if let host = URL(string: originalInput)?.host {
                let cleanHost = host.replacingOccurrences(of: "www.", with: "")
                let path = url.lastPathComponent
                if !path.isEmpty && path != "/" && !path.contains("watch") && !path.contains("video") {
                    return "\(path) (\(cleanHost))"
                }
                return "\(cleanHost) Video"
            }
            return originalInput
        }
    }

    public var displaySubtitle: String {
        switch self {
        case .local(let url):
            return url.deletingLastPathComponent().path
        case .online(_, let originalInput):
            return originalInput
        }
    }

    public var isLocal: Bool {
        switch self {
        case .local:
            return true
        case .online:
            return false
        }
    }

    public var isOnline: Bool {
        !isLocal
    }

    public var fileExtension: String {
        switch self {
        case .local(let url):
            return url.pathExtension.lowercased()
        case .online(let url, _):
            return url.pathExtension.lowercased()
        }
    }

    public var isAudioTrack: Bool {
        let audioExts: Set<String> = ["flac", "alac", "mp3", "m4a", "wav", "aac", "ogg", "opus", "aiff", "thd", "truehd", "mlp"]
        return audioExts.contains(fileExtension)
    }

    public var rawURL: URL {
        switch self {
        case .local(let url):
            return url
        case .online(let url, _):
            return url
        }
    }
}
