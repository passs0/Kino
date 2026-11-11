import SwiftUI
import AppKit

/// Notification triggering the Live Captions & Translation settings sheet.
public extension Notification.Name {
    static let openLiveCaptionSheetNotification = Notification.Name("KinoOpenLiveCaptionSheetNotification")
}

/// Native Liquid Glass sheet for configuring live speech recognition and on-device neural translation.
public struct LiveCaptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var liveCaption = LiveCaptionManager.shared
    @StateObject private var coordinator = MediaCoordinator.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 20) {
                    toggleCard
                    languageSelectionCard
                    if liveCaption.isEnabled {
                        livePreviewCard
                    }
                    privacyBadge
                }
                .padding(24)
            }

            Divider().opacity(0.3)
            footerSection
        }
        .frame(width: 480, height: liveCaption.isEnabled ? 520 : 440)
        .background(VisualEffectBackdrop().ignoresSafeArea())
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Live Captions & Translation")
                    .font(.system(size: 16, weight: .bold))
                Text("Real-time on-device speech-to-text & translation for playing media")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Toggle Card

    private var toggleCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Live Captions")
                    .font(.system(size: 14, weight: .semibold))
                Text("Generates live subtitles on screen as dialogue is spoken")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { liveCaption.isEnabled },
                set: { val in
                    if val {
                        liveCaption.startLiveCaptions()
                    } else {
                        liveCaption.stopLiveCaptions()
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Language Selection Card

    private var languageSelectionCard: some View {
        VStack(spacing: 16) {
            // 1. Spoken Language (Audio Source)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken Audio Language")
                        .font(.system(size: 13, weight: .medium))
                    Text("Dialogue language spoken in the video")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Picker("", selection: $liveCaption.selectedSourceID) {
                    ForEach(LiveCaptionManager.availableSourceLanguages) { opt in
                        Text("\(opt.flag)  \(opt.name)").tag(opt.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
            }

            Divider().opacity(0.2)

            // 2. Target Translation Language
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subtitle Translation")
                        .font(.system(size: 13, weight: .medium))
                    Text("Language displayed in on-screen subtitles")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()

                Picker("", selection: $liveCaption.selectedTargetID) {
                    ForEach(LiveCaptionManager.availableTargetLanguages) { opt in
                        Text("\(opt.flag)  \(opt.name)").tag(opt.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Live Preview Card

    private var livePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(liveCaption.isCapturing ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(liveCaption.isCapturing ? "Live On-Device Pipeline Active" : "Waiting for audio playback…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if !liveCaption.liveTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recognized Speech:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(liveCaption.liveTranscript)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                }
            }

            if !liveCaption.liveTranslation.isEmpty && liveCaption.selectedTargetID != "none" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translated Subtitle:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                    Text(liveCaption.liveTranslation)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Privacy Badge

    private var privacyBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
            Text("100% On-Device Neural Processing. Speech and translation never leave your Mac.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Text("Press **⌥⌘C** anytime to toggle settings")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
