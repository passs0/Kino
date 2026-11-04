import SwiftUI

/// Banner displaying the active Playback Strategy determined by the Media Coordinator.
public struct StrategyBannerView: View {
    let strategy: PlaybackStrategy
    var onInspect: (() -> Void)?

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: strategy.iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(badgeForegroundColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(strategy.badgeLabel)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeBackgroundColor)
                        .foregroundColor(badgeForegroundColor)
                        .cornerRadius(4)

                    Text(strategy.strategyTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(strategy.explanation)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Label(strategy.estimatedCpuImpact, systemImage: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                Label(strategy.latencyDescription, systemImage: "bolt.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                if let onInspect = onInspect {
                    Button(action: onInspect) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Inspect Media & Stream Architecture")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(badgeForegroundColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private var badgeBackgroundColor: Color {
        switch strategy {
        case .directNative, .onlineDirect:
            return Color.green.opacity(0.2)
        case .remuxOnly:
            return Color.blue.opacity(0.2)
        case .audioTranscodeOnly:
            return Color.purple.opacity(0.2)
        case .fullTranscode, .onlineTranscode:
            return Color.orange.opacity(0.2)
        }
    }

    private var badgeForegroundColor: Color {
        switch strategy {
        case .directNative, .onlineDirect:
            return Color.green
        case .remuxOnly:
            return Color.blue
        case .audioTranscodeOnly:
            return Color.purple
        case .fullTranscode, .onlineTranscode:
            return Color.orange
        }
    }
}
