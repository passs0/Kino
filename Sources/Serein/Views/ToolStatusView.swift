import SwiftUI

/// Status popover showing availability and versions of FFprobe, FFmpeg, and yt-dlp.
public struct ToolStatusView: View {
    @ObservedObject private var prerequisiteManager = PrerequisiteManager.shared
    @State private var tools: [ToolInfo] = []

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Media Engines & Dependencies", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh Dependencies")
            }

            Divider()

            VStack(spacing: 10) {
                ForEach(tools) { tool in
                    toolRow(tool)
                }
            }

            Divider()

            if !prerequisiteManager.isAllInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AUTOMATIC SETUP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    Button {
                        NotificationCenter.default.post(name: .openPrerequisitesSheetNotification, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Missing Engines (~45 MB)")
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Or install via Homebrew: brew install ffmpeg yt-dlp")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All media engines active.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                        Text("Zero-copy remuxing and online streaming enabled.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Check Updates") {
                        Task {
                            await prerequisiteManager.checkForUpdates()
                            refresh()
                        }
                    }
                    .disabled(prerequisiteManager.isCheckingUpdates)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear {
            refresh()
        }
    }

    private func toolRow(_ tool: ToolInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(tool.isAvailable ? .green : .red)
                .font(.system(size: 14))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tool.name)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Spacer()
                    if let ver = tool.version {
                        Text(ver)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if let p = tool.path {
                    Text(p)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Not found in standard search paths")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func refresh() {
        ToolLocator.shared.refresh()
        tools = ToolLocator.shared.allTools
    }
}
