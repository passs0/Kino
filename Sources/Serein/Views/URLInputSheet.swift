import SwiftUI

/// Modal sheet for entering online media URLs or selecting test media profiles.
public struct URLInputSheet: View {
    @ObservedObject var coordinator: MediaCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var inputURLString = ""
    @State private var isExtracting = false

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Label("Open Online Source", systemImage: "globe.americas.fill")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter video or online stream URL:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack {
                    TextField("https://example.com/video.mp4 or https://.../playlist.m3u8", text: $inputURLString)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            submitURL()
                        }

                    Button("Paste") {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            inputURLString = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }

            // Quick Samples Section
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK TEST SAMPLES & CODEC PROFILES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 6) {
                    sampleButton(
                        title: "Local MP4 (H.264 + AAC)",
                        desc: "Direct Hardware Native Playback (0% CPU)",
                        path: "/tmp/serein_sample_native.mp4"
                    )

                    sampleButton(
                        title: "Local MKV (H.264 + AAC in Matroska)",
                        desc: "Fast Stream-Copy Remux to Local HLS (< 100ms)",
                        path: "/tmp/serein_sample_remux.mkv"
                    )

                    sampleButton(
                        title: "Local WebM (VP9 + Opus)",
                        desc: "VideoToolbox Hardware Transcode Stream",
                        path: "/tmp/serein_sample_transcode.webm"
                    )

                    sampleURLButton(
                        title: "Standard Test HLS Stream (Apple BipBop Basic)",
                        url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
                    )

                    sampleURLButton(
                        title: "Progressive MP4 Stream Sample (Big Buck Bunny)",
                        url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
                    )
                }
            }

            Divider()

            HStack {
                Spacer()

                Button("Open & Coordinate") {
                    submitURL()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(inputURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func submitURL() {
        let trimmed = inputURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") {
            let clean = trimmed.replacingOccurrences(of: "file://", with: "")
            coordinator.openLocalFile(url: URL(fileURLWithPath: clean))
        } else {
            coordinator.openOnlineURL(string: trimmed)
        }
        dismiss()
    }

    private func sampleButton(title: String, desc: String, path: String) -> some View {
        Button(action: {
            coordinator.openLocalFile(url: URL(fileURLWithPath: path))
            dismiss()
        }) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Load")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func sampleURLButton(title: String, url: String) -> some View {
        Button(action: {
            inputURLString = url
            submitURL()
        }) {
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(url)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Select")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
