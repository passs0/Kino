import SwiftUI

/// Detailed centered modal HUD displaying media container analysis, stream codecs, and coordinator rationale.
public struct MediaInspectorView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject private var enhancer = VideoEnhancer.shared
    var onClose: (() -> Void)?

    @State private var innerContentHeight: CGFloat = 0

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Media Statistics")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("Technical Stream Inspector")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.60))
                }

                Spacer()

                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help("Close (Esc)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.white.opacity(0.12))

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    if let strategy = coordinator.activeStrategy {
                        strategySection(strategy)
                    }

                    if coordinator.probeResult?.isAudioOnly != true && coordinator.currentSource?.isAudioTrack != true {
                        videoEnhancementSection
                    }

                    if let stats = coordinator.pipelineStats {
                        livePipelineSection(stats)
                    }

                    if let probe = coordinator.probeResult {
                        sourceSection(probe)
                        compatibilityMatrixSection(probe)
                        if probe.primaryVideo != nil {
                            videoStreamsSection(probe)
                        }
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
                .padding(18)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: InspectorContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: innerContentHeight > 0 ? min(innerContentHeight, 480) : nil)
            .onPreferenceChange(InspectorContentHeightKey.self) { height in
                if height > 0 {
                    innerContentHeight = height
                }
            }
        }
        .frame(minWidth: 320, maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 10)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Strategy Section

    private func strategySection(_ strategy: PlaybackStrategy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLAYBACK STRATEGY")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(strategy.badgeLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.25))
                        .foregroundColor(Color.accentColor)
                        .cornerRadius(4)

                    Text(strategy.strategyTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()
                }

                Text(strategy.explanation)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(Color.white.opacity(0.10))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU Overhead")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.white.opacity(0.60))
                        Text(strategy.estimatedCpuImpact)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Startup Latency")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.white.opacity(0.60))
                        Text(strategy.latencyDescription)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
        }
    }

    // MARK: - Video Enhancement Section

    private var videoEnhancementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VIDEO ENHANCEMENT & UPSCALING")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: enhancer.activeMode.iconName)
                        .foregroundColor(enhancer.activeMode == .off ? Color.white.opacity(0.6) : Color.accentColor)
                        .font(.system(size: 13, weight: .semibold))

                    Text(enhancer.activeMode.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(enhancer.activeMode.technologyBadge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(enhancer.activeMode == .off ? Color.white.opacity(0.6) : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((enhancer.activeMode == .off ? Color.white : Color.accentColor).opacity(0.12))
                        .cornerRadius(4)
                }

                Text(enhancer.activeMode.shortDescription)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(cardBackground)
        }
    }

    // MARK: - Live Pipeline Section

    private func livePipelineSection(_ stats: PipelineStats) -> some View {
        let isHardware: Bool = {
            if case .fullTranscode = coordinator.activeStrategy { return true }
            return false
        }()
        let speedTitle = isHardware ? "TRANSCODE SPEED" : "STREAM SPEED"
        let timeTitle = isHardware ? "TIME ENCODED" : "TIME BUFFERED"
        let isRemote = coordinator.currentSource?.isOnline == true
        let speedNum = Double(stats.speedFactor.replacingOccurrences(of: "x", with: "")) ?? 1.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isHardware ? "LIVE HARDWARE ENCODING PIPELINE" : "LIVE COMPATIBILITY PIPELINE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.65))

                if !isHardware && isRemote && speedNum < 1.0 {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Server bandwidth limited (< 1.0x)")
                            .font(.system(size: 8.5, weight: .medium))
                    }
                    .foregroundColor(.orange.opacity(0.9))
                }
            }

            HStack(spacing: 10) {
                metricBox(title: speedTitle, value: stats.speedFactor, icon: isHardware ? "gauge.with.needle" : "network")
                metricBox(title: "FPS", value: String(format: "%.1f", stats.fps), icon: "film")
                metricBox(title: timeTitle, value: stats.currentTime, icon: "clock")
            }
        }
    }

    private func metricBox(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(Color.white.opacity(0.60))
            Text(value)
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Source Section

    private func sourceSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTAINER & FORMAT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

            VStack(spacing: 6) {
                metaRow(label: "Container", value: probe.containerFormat.friendlyName)
                metaRow(label: "Duration", value: probe.formattedDuration)
                metaRow(label: "File Size", value: probe.formattedSize)
                metaRow(label: "Overall Bitrate", value: probe.formattedBitrate)
                metaRow(label: "Filename", value: probe.filename)
            }
            .padding(12)
            .background(cardBackground)
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
                .foregroundColor(Color.white.opacity(0.65))

            VStack(spacing: 8) {
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
            .background(cardBackground)
        }
    }

    private func compatRow(title: String, subtitle: String, isNative: Bool, actionIfIncompatible: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isNative ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isNative ? Color(red: 0.30, green: 0.85, blue: 0.45) : Color.orange)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.65))
            }

            Spacer()

            Text(isNative ? "Native AVPlayer" : actionIfIncompatible)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(isNative ? Color(red: 0.40, green: 0.95, blue: 0.55) : Color.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((isNative ? Color.green : Color.orange).opacity(0.18))
                .cornerRadius(4)
        }
    }

    // MARK: - Video Streams Section

    private func videoStreamsSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VIDEO STREAM")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

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
                .background(cardBackground)
            } else {
                Text("No video stream found.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.60))
                    .padding(12)
                    .background(cardBackground)
            }
        }
    }

    // MARK: - Audio Streams Section

    private func audioStreamsSection(_ probe: MediaProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUDIO STREAMS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

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
                .background(cardBackground)
            } else {
                Text("No audio stream found.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.60))
                    .padding(12)
                    .background(cardBackground)
            }
        }
    }

    // MARK: - Subtitles Section

    private func subtitleSection(_ subtitles: [MediaStream]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBTITLES (\(subtitles.count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

            VStack(spacing: 4) {
                ForEach(subtitles) { sub in
                    HStack {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.70))
                        Text(sub.language?.uppercased() ?? "Track \(sub.index)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                        if let title = sub.title {
                            Text("— \(title)")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.75))
                        }
                        Spacer()
                        Text(sub.codecName)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.60))
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(12)
            .background(cardBackground)
        }
    }

    // MARK: - Online Source Section

    private func onlineSourceSection(_ info: ExtractedMediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ONLINE EXTRACTION (YT-DLP)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.white.opacity(0.65))

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
            .background(cardBackground)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundColor(Color.white.opacity(0.60))
            Text("No Media Loaded")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Open a local file or paste an online URL to inspect stream compatibility.")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.60))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color.white.opacity(0.65))
                .frame(width: 105, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(2)
            Spacer()
        }
    }
}

private struct InspectorContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
