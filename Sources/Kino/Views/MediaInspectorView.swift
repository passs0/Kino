import SwiftUI
import AppKit

/// Apple QuickTime-style compact floating Movie Inspector palette (⌘I).
/// Floats gracefully in the corner of the media canvas without blocking playback or tinting the video.
public struct MediaInspectorView: View {
    @ObservedObject var coordinator: MediaCoordinator
    var onClose: (() -> Void)?

    public init(coordinator: MediaCoordinator, onClose: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inspector Header
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Movie Inspector")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.60))
                    }
                    .buttonStyle(.plain)
                    .help("Close Inspector (⌘I / Esc)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.12))

            // QuickTime Metric Rows
            VStack(alignment: .leading, spacing: 10) {
                // 1. Source / Format
                inspectorRow(
                    label: "Source",
                    value: sourceName,
                    subvalue: containerFormat
                )

                // 2. Video
                if let video = coordinator.probeResult?.primaryVideo {
                    inspectorRow(
                        label: "Video",
                        value: "\(video.codecName.uppercased())",
                        subvalue: "\(video.width ?? 0) × \(video.height ?? 0) • \(video.fpsString ?? "24 fps")"
                    )
                } else if let online = coordinator.extractedOnlineInfo {
                    inspectorRow(
                        label: "Video",
                        value: "Web Stream",
                        subvalue: online.uploader ?? "Online"
                    )
                }

                // 3. Audio
                if let audio = coordinator.probeResult?.primaryAudio {
                    inspectorRow(
                        label: "Audio",
                        value: "\(audio.codecName.uppercased())",
                        subvalue: audio.audioDetailsString
                    )
                }

                // 4. Data Rate / Bitrate
                if let bitrate = currentBitrate {
                    inspectorRow(
                        label: "Data Rate",
                        value: bitrate,
                        subvalue: nil
                    )
                }

                // 5. Playback Strategy
                if let strategy = coordinator.activeStrategy {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Engine")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 62, alignment: .leading)

                        Text(strategy.badgeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.18))
                            .cornerRadius(4)

                        Spacer()
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func inspectorRow(label: String, value: String, subvalue: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(value)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let sub = subvalue, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    private var sourceName: String {
        if let source = coordinator.currentSource {
            return source.displayName
        }
        return "None"
    }

    private var containerFormat: String? {
        if let fmt = coordinator.probeResult?.formatName {
            return fmt.uppercased()
        }
        if let ext = coordinator.currentSource?.fileExtension, !ext.isEmpty {
            return ext.uppercased()
        }
        return nil
    }

    private var currentBitrate: String? {
        if let stats = coordinator.pipelineStats, !stats.bitrate.isEmpty {
            return stats.bitrate
        }
        if let br = coordinator.probeResult?.overallBitrate, br > 0 {
            return String(format: "%.1f Mbps", Double(br) / 1_000_000.0)
        }
        return nil
    }

    private func formatFPS(_ fps: Double?) -> String {
        guard let f = fps, f > 0 else { return "Variable fps" }
        return String(format: "%.2f fps", f)
    }

    private func formatSampleRate(_ rate: Int?) -> String {
        guard let r = rate, r > 0 else { return "48 kHz" }
        return "\(r / 1000) kHz"
    }
}
