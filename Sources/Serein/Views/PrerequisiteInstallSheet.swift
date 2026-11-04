import SwiftUI
import AppKit

/// A native macOS sheet that informs the user about helper media engines
/// and provides 1-click automated downloading to Application Support.
public struct PrerequisiteInstallSheet: View {
    @ObservedObject private var manager = PrerequisiteManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 44))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .padding(.top, 8)

                Text("Modern Codecs & Media Engines")
                    .font(.system(size: 18, weight: .bold))

                Text("Serein is engineered as the modern successor to QuickTime Player. To stream web media and play modern containers (MKV, WebM, Opus, ASS subtitles) with hardware acceleration, Serein uses lightweight helper engines.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
            }

            Divider()

            // Component Status Cards
            VStack(spacing: 12) {
                componentCard(
                    title: "FFmpeg & FFprobe Engine",
                    description: "Zero-copy HLS remuxing, audio transcoding & embedded subtitle extraction",
                    isInstalled: manager.isFFmpegInstalled,
                    toolName: "ffmpeg"
                )

                componentCard(
                    title: "yt-dlp Stream Extractor",
                    description: "High-resolution web stream resolution & authenticated platform bridge",
                    isInstalled: manager.isYtDlpInstalled,
                    toolName: "yt-dlp"
                )
            }
            .padding(.horizontal, 12)

            // Progress or Error status
            if manager.isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                    Text(manager.currentStepText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            } else if let err = manager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
            } else if let updateMsg = manager.updateStatusMessage {
                Text(updateMsg)
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
            }

            Divider()

            // Action Buttons
            HStack(spacing: 12) {
                if !manager.isAllInstalled {
                    Button("Not Now") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        Task {
                            await manager.downloadAndInstallComponents()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(manager.isDownloading ? "Downloading..." : "Download & Install (~45 MB)")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isDownloading)
                } else {
                    Button {
                        Task {
                            await manager.checkForUpdates()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(manager.isCheckingUpdates ? "Checking..." : "Check for Updates")
                        }
                    }
                    .disabled(manager.isCheckingUpdates)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(20)
        .frame(width: 480)
        .background(VisualEffectBackground())
        .onAppear {
            manager.refreshStatus()
        }
    }

    private func componentCard(title: String, description: String, isInstalled: Bool, toolName: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundColor(isInstalled ? .green : .orange)
                .font(.system(size: 18))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if isInstalled {
                        Text("Ready")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                    } else {
                        Text("Missing")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let path = ToolLocator.shared.path(for: toolName) {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .sheet
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
