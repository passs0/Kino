import SwiftUI

/// Detailed inspector pane displaying media container analysis, stream codecs, and coordinator rationale.
public struct MediaInspectorView: View {
    @ObservedObject var coordinator: MediaCoordinator
    var onClose: (() -> Void)?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Label("Media Coordinator Inspector", systemImage: "waveform.badge.magnifyingglass")
                        .font(.system(size: 14, weight: .bold))

                    Spacer()

                    if let onClose = onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                if let strategy = coordinator.activeStrategy {
                    strategySection(strategy)
                }

                if let stats = coordinator.pipelineStats {
                    livePipelineSection(stats)
                }

                if let probe = coordinator.probeResult {
                    sourceSection(probe)
                    compatibilityMatrixSection(probe)
                    videoStreamsSection(probe)
                    audioStreamsSection(probe)
                    if !probe.subtitles.isEmpty {
                        subtitleSection(probe.subtitles)
                    }
                } else if let online = coordinator.extractedOnlineInfo {
                    onlineSourceSection(online)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .frame(width: 340)
        .glassEffect(LiquidGlassSettings.shared.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Strategy Section

    private func strategySection(_ strategy: PlaybackStrategy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLAYBACK STRATEGY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(strategy.badgeLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)

                    Text(strategy.strategyTitle)
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()
                }

                Text(strategy.explanation)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("CPU Overhead")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(strategy.estimatedCpuImpact)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Startup Latency")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(strategy.latencyDescription)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Live Pipeline Section

    private func livePipelineSection(_ stats: PipelineStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE COMPATIBILITY PIPELINE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                metricBox(title: "TRANSCODE SPEED", value: stats.speedFactor, icon: "gauge.with.needle")
                metricBox(title: "FPS", value: String(format: "%.1f", stats.fps), icon: "film")
                metricBox(title: "TIME ENCODED", value: stats.currentTime, icon: "clock")
            }
        }
    }

    private func metricBox(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Source Section

    private func sourceSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTAINER & FORMAT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                metaRow(label: "Container", value: probe.containerFormat.friendlyName)
                metaRow(label: "Duration", value: probe.formattedDuration)
                metaRow(label: "File Size", value: probe.formattedSize)
                metaRow(label: "Overall Bitrate", value: probe.formattedBitrate)
                metaRow(label: "Filename", value: probe.filename)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Compatibility Matrix Section

    private func compatibilityMatrixSection(_ probe: MediaProbeResult) -> some View {
        let containerNative = probe.containerFormat.isNativelySupportedByAVPlayer
        let vNative = probe.primaryVideo?.videoCodec?.isNativelyDecodable ?? true
        let aNative = probe.primaryAudio?.audioCodec?.isNativelyDecodable ?? true

        return VStack(alignment: .leading, spacing: 8) {
            Text("NATIVE COMPATIBILITY BREAKDOWN")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                compatRow(
                    title: "Container Demuxing",
                    subtitle: probe.containerFormat.description,
                    isNative: containerNative,
                    actionIfIncompatible: "Remux into HLS stream"
                )
                compatRow(
                    title: "Video Stream",
                    subtitle: probe.primaryVideo?.videoCodec?.description ?? "N/A",
                    isNative: vNative,
                    actionIfIncompatible: "VideoToolbox HW transcode"
                )
                compatRow(
                    title: "Audio Stream",
                    subtitle: probe.primaryAudio?.audioCodec?.description ?? "N/A",
                    isNative: aNative,
                    actionIfIncompatible: "Real-time AAC transcode"
                )
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func compatRow(title: String, subtitle: String, isNative: Bool, actionIfIncompatible: String) -> some View {
        HStack {
            Image(systemName: isNative ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isNative ? .green : .orange)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(isNative ? "Native AVPlayer" : actionIfIncompatible)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isNative ? .green : .orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isNative ? Color.green : Color.orange).opacity(0.12))
                .cornerRadius(4)
        }
    }

    // MARK: - Video Streams Section

    private func videoStreamsSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VIDEO STREAM")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if let v = probe.primaryVideo {
                VStack(spacing: 6) {
                    metaRow(label: "Codec", value: "\(v.codecLongName) (\(v.codecName))")
                    if let res = v.resolutionString {
                        metaRow(label: "Resolution", value: res)
                    }
                    if let fps = v.fpsString {
                        metaRow(label: "Frame Rate", value: fps)
                    }
                    if let prof = v.profile {
                        metaRow(label: "Profile", value: prof)
                    }
                    if let pix = v.pixelFormat {
                        metaRow(label: "Pixel Format", value: pix)
                    }
                    if let br = v.bitrate {
                        metaRow(label: "Stream Bitrate", value: "\(br / 1000) kbps")
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Text("No video stream found.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Audio Streams Section

    private func audioStreamsSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUDIO STREAMS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if let a = probe.primaryAudio {
                VStack(spacing: 6) {
                    metaRow(label: "Codec", value: "\(a.codecLongName) (\(a.codecName))")
                    if let sr = a.sampleRate {
                        metaRow(label: "Sample Rate", value: "\(sr) Hz")
                    }
                    if let ch = a.channels {
                        metaRow(label: "Channels", value: "\(ch) (\(a.channelLayout ?? "unknown"))")
                    }
                    if let br = a.bitrate {
                        metaRow(label: "Bitrate", value: "\(br / 1000) kbps")
                    }
                    if let lang = a.language {
                        metaRow(label: "Language", value: lang)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Text("No audio stream found.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Subtitles Section

    private func subtitleSection(_ subtitles: [MediaStream]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBTITLES (\(subtitles.count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(subtitles) { sub in
                    HStack {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(sub.language?.uppercased() ?? "Track \(sub.index)")
                            .font(.system(size: 11, weight: .medium))
                        if let title = sub.title {
                            Text("— \(title)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(sub.codecName)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Online Source Section

    private func onlineSourceSection(_ info: ExtractedMediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ONLINE EXTRACTION (YT-DLP)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                metaRow(label: "Title", value: info.title)
                if let u = info.uploader {
                    metaRow(label: "Channel / Creator", value: u)
                }
                metaRow(label: "Duration", value: info.formattedDuration)
                metaRow(label: "Available Formats", value: "\(info.formats.count) streams")
                metaRow(label: "Selected URL", value: info.selectedStreamURL.host ?? "Online Host")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No Media Loaded")
                .font(.system(size: 12, weight: .medium))
            Text("Open a local file or paste an online URL to inspect stream compatibility.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
        }
    }
}
