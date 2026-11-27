import SwiftUI
import AppKit

/// Clean, Apple-styled modal sheet for opening online media URLs.
public struct URLInputSheet: View {
    @ObservedObject var coordinator: MediaCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var inputURLString = ""

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Online URL")
                        .font(.headline)
                    Text("Enter a video link, streaming URL, or HLS stream (.m3u8):")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Input field
            HStack(spacing: 8) {
                TextField("https://...", text: $inputURLString)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit {
                        submitURL()
                    }

                if let clipboard = NSPasteboard.general.string(forType: .string),
                   (clipboard.hasPrefix("http://") || clipboard.hasPrefix("https://") || clipboard.hasPrefix("rtmp://")),
                   inputURLString.isEmpty {
                    Button("Paste") {
                        inputURLString = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .controlSize(.large)
                }
            }

            // Action Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)

                Button("Open") {
                    submitURL()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(inputURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               (clipboard.hasPrefix("http://") || clipboard.hasPrefix("https://")) {
                inputURLString = clipboard
            }
        }
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
}
