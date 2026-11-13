import SwiftUI
import AppKit

/// Apple QuickTime-style compact floating Movie Inspector palette (⌘I).
/// Floats gracefully in the corner of the media canvas without blocking playback or tinting the video.
public struct MediaInspectorView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject private var playerController = PlayerController.shared
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
            VStack(alignment: .leading, spacing: 9) {
                // 1. Source / Format
                inspectorRow(
                    label: "Source",
                    value: sourceName,
                    subvalue: containerFormat
                )

                // 2. Viewport
                if let viewport = viewportString {
                    inspectorRow(
                        label: "Viewport",
                        value: viewport,
                        subvalue: nil
                    )
                }

                // 3. Resolution & FPS (Works for both local files & online streams)
                if let resFPS = resolutionAndFPSString {
                    inspectorRow(
                        label: "Resolution",
                        value: resFPS,
                        subvalue: nil
                    )
                }

                // 4. Frames (Dropped / Total)
                if let frames = framesString {
                    inspectorRow(
                        label: "Frames",
                        value: frames,
                        subvalue: nil
                    )
                }

                // 5. Codecs
                if let codecs = codecsString {
                    inspectorRow(
                        label: "Codecs",
                        value: codecs,
                        subvalue: nil
                    )
                }

                // 6. Color Space
                if let color = colorString {
                    inspectorRow(
                        label: "Color",
                        value: color,
                        subvalue: nil
                    )
                }

                // 7. Audio Details
                if let audio = coordinator.probeResult?.primaryAudio,
                   let details = audio.audioDetailsString, !details.isEmpty {
                    inspectorRow(
                        label: "Audio",
                        value: details,
                        subvalue: nil
                    )
                }

                // 8. Data Rate / Bitrate
                if let bitrate = currentBitrate {
                    inspectorRow(
                        label: "Data Rate",
                        value: bitrate,
                        subvalue: nil
                    )
                }

                // 9. Playback Strategy
                if let strategy = coordinator.activeStrategy {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Engine")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 68, alignment: .leading)

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
        .frame(width: 292)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .task {
            while !Task.isCancelled {
                await playerController.refreshLiveMetrics()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func inspectorRow(label: String, value: String, subvalue: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 68, alignment: .leading)

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

    private var viewportString: String? {
        guard let win = WindowManager.shared.mainWindow ?? NSApp.mainWindow,
              let size = win.contentView?.bounds.size,
              size.width > 0 && size.height > 0 else {
            return nil
        }
        let scale = Int(win.backingScaleFactor.rounded())
        return "\(Int(size.width.rounded()))×\(Int(size.height.rounded())) (\(max(1, scale))×)"
    }

    private var effectiveFPS: Double? {
        coordinator.probeResult?.primaryVideo?.fps ?? playerController.liveMetrics.fps
    }

    private var resolutionAndFPSString: String? {
        let w = coordinator.probeResult?.primaryVideo?.width ?? playerController.liveMetrics.width
        let h = coordinator.probeResult?.primaryVideo?.height ?? playerController.liveMetrics.height
        guard let width = w, let height = h, width > 0, height > 0 else {
            return nil
        }
        if let fps = effectiveFPS, fps > 0 {
            let rounded = (fps - fps.rounded()).magnitude < 0.05
                ? String(format: "%.0f fps", fps.rounded())
                : String(format: "%.2f fps", fps)
            return "\(width)×\(height) (\(rounded))"
        }
        return "\(width)×\(height)"
    }

    private var framesString: String? {
        let w = coordinator.probeResult?.primaryVideo?.width ?? playerController.liveMetrics.width
        guard w != nil else { return nil }
        let dropped = playerController.liveMetrics.droppedFrames
        if let fps = effectiveFPS, fps > 0 {
            let approxTotal = max(dropped, Int((PlayerTimeState.shared.currentTime * fps).rounded()))
            if approxTotal > 0 {
                return "\(dropped) dropped of \(approxTotal)"
            }
        }
        return "\(dropped) dropped"
    }

    private var codecsString: String? {
        let vCodec = coordinator.probeResult?.primaryVideo?.codecName.uppercased() ?? playerController.liveMetrics.videoCodec
        let aCodec = coordinator.probeResult?.primaryAudio?.codecName.uppercased() ?? playerController.liveMetrics.audioCodec
        let parts = [vCodec, aCodec].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private var colorString: String? {
        coordinator.probeResult?.primaryVideo?.colorInfo ?? playerController.liveMetrics.colorInfo
    }

    private var currentBitrate: String? {
        if let stats = coordinator.pipelineStats, !stats.bitrate.isEmpty {
            return stats.bitrate
        }
        if let br = coordinator.probeResult?.overallBitrate, br > 0 {
            return String(format: "%.1f Mbps", Double(br) / 1_000_000.0)
        }
        if let ind = playerController.liveMetrics.indicatedBitrate, ind > 0 {
            return String(format: "%.1f Mbps", ind / 1_000_000.0)
        }
        return nil
    }
}
