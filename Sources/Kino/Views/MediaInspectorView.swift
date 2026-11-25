import SwiftUI
import AppKit

/// Apple QuickTime-style compact floating Movie Inspector palette (⌘I).
/// Floats gracefully in the corner of the media canvas without blocking playback or tinting the video.
public struct MediaInspectorView: View {
    @ObservedObject var coordinator: MediaCoordinator
    @ObservedObject private var playerController = PlayerController.shared
    @ObservedObject private var metricsManager = LiveMetricsManager.shared
    var onClose: (() -> Void)?

    public init(coordinator: MediaCoordinator, onClose: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.onClose = onClose
    }

    public var body: some View {
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
            .frame(width: 296)
            .task {
            while !Task.isCancelled {
                await metricsManager.refresh(from: playerController.player.currentItem)
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
        coordinator.probeResult?.primaryVideo?.fps ?? metricsManager.liveMetrics.fps
    }

    private var resolutionAndFPSString: String? {
        let w = coordinator.probeResult?.primaryVideo?.width ?? metricsManager.liveMetrics.width
        let h = coordinator.probeResult?.primaryVideo?.height ?? metricsManager.liveMetrics.height
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
        let w = coordinator.probeResult?.primaryVideo?.width ?? metricsManager.liveMetrics.width
        guard w != nil else { return nil }
        let dropped = metricsManager.liveMetrics.droppedFrames
        if let fps = effectiveFPS, fps > 0 {
            let approxTotal = max(dropped, Int((PlayerTimeState.shared.currentTime * fps).rounded()))
            if approxTotal > 0 {
                return "\(dropped) dropped of \(approxTotal)"
            }
        }
        return "\(dropped) dropped"
    }

    private var codecsString: String? {
        let vCodec = coordinator.probeResult?.primaryVideo?.codecName.uppercased() ?? metricsManager.liveMetrics.videoCodec
        let aCodec = coordinator.probeResult?.primaryAudio?.codecName.uppercased() ?? metricsManager.liveMetrics.audioCodec
        let parts = [vCodec, aCodec].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private var colorString: String? {
        coordinator.probeResult?.primaryVideo?.colorInfo ?? metricsManager.liveMetrics.colorInfo
    }

    private var currentBitrate: String? {
        if let stats = coordinator.pipelineStats, !stats.bitrate.isEmpty {
            return stats.bitrate
        }
        if let br = coordinator.probeResult?.overallBitrate, br > 0 {
            return String(format: "%.1f Mbps", Double(br) / 1_000_000.0)
        }
        if let ind = metricsManager.liveMetrics.indicatedBitrate, ind > 0 {
            return String(format: "%.1f Mbps", ind / 1_000_000.0)
        }
        return nil
    }
}

/// Manages the native QuickTime-style floating Movie Inspector utility panel (⌘I).
@MainActor
public final class InspectorPanelController: NSObject, NSWindowDelegate {
    public static let shared = InspectorPanelController()

    private var panel: NSPanel?

    private override init() {
        super.init()
    }

    public func setVisible(_ visible: Bool, relativeTo parentWindow: NSWindow?) {
        if visible {
            show(relativeTo: parentWindow)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show(relativeTo parentWindow: NSWindow?) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 296, height: 260),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.title = "Movie Inspector"
            p.isFloatingPanel = true
            p.hidesOnDeactivate = true
            p.level = .floating
            p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.delegate = self
            p.contentViewController = NSHostingController(
                rootView: MediaInspectorView(coordinator: MediaCoordinator.shared)
                    .preferredColorScheme(.dark)
            )
            if let parent = parentWindow {
                let targetX = parent.frame.maxX + 12
                let targetY = parent.frame.maxY - p.frame.height
                p.setFrameOrigin(NSPoint(x: targetX, y: targetY))
            } else {
                p.center()
            }
            self.panel = p
        }
        panel?.orderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        MediaCoordinator.shared.isInspectorPresented = false
    }
}
