import SwiftUI
import AppKit

public struct SafariExtensionSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Safari Companion Extension")
                        .font(.system(size: 16, weight: .bold))
                    Text("1-click playback from Safari directly into Serein")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Step 1: Developer Settings (Allow Unsigned Extensions)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Text("1")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow Unsigned Extensions in Safari")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Because Serein is built with an open-source ad-hoc signature, Safari requires enabling 'Allow unsigned extensions' once in Developer Settings.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        SafariExtensionManager.shared.openSafariDeveloperSettings()
                    } label: {
                        Label("Open Safari Developer Settings", systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            // Step 2: Extensions Preferences (Enable Extension)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Text("2")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable 'Play in Serein' Extension")
                            .font(.system(size: 13, weight: .semibold))
                        Text("In Safari Settings ➔ Extensions, check the box next to 'Play in Serein' and choose 'Always Allow on Every Website'.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        SafariExtensionManager.shared.openSafariExtensionsPreferences()
                    } label: {
                        Label("Open Safari Extensions Preferences", systemImage: "puzzlepiece.extension")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            // Features summary / Tip
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text("Once enabled, click the Serein icon in Safari's toolbar or right-click any video to play. Serein automatically pauses the browser video and syncs playback time.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 480)
    }
}
