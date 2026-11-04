import SwiftUI
import AppKit

/// Minimalist modal sheet for opening online media URLs.
public struct URLInputSheet: View {
    @ObservedObject var coordinator: MediaCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var inputURLString = ""

    public var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack {
                Label("Open Online URL", systemImage: "globe")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter a direct media link, HLS playlist (.m3u8), or online video page URL:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("https://...", text: $inputURLString)
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

            HStack {
                Spacer()

                Button("Open Stream") {
                    submitURL()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(inputURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
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
