import Foundation

/// Represents an available audio track within a media container or stream.
public struct AudioTrack: Identifiable, Hashable, Sendable {
    public let id: String
    public let streamIndex: Int
    public let name: String
    public let languageCode: String?
    public let codecName: String
    public let channels: Int?
    public let channelLayout: String?
    public let sampleRate: Int?
    public let isDefault: Bool

    public init(
        id: String,
        streamIndex: Int,
        name: String,
        languageCode: String? = nil,
        codecName: String = "",
        channels: Int? = nil,
        channelLayout: String? = nil,
        sampleRate: Int? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.streamIndex = streamIndex
        self.name = name
        self.languageCode = languageCode
        self.codecName = codecName
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.isDefault = isDefault
    }
}
