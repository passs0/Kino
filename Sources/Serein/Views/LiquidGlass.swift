import SwiftUI
import AppKit

/// Apple's Official macOS 26+ Liquid Glass System Integration
/// Uses native SwiftUI `Glass.regular` and `.glassEffect(Glass.regular, in: shape)`.
/// Seamlessly uses macOS System Settings Appearance Accent Color.

// MARK: - Apple Control Center Style Pill Slider

/// Apple macOS 26 / iOS 18 Control Center Style Pill Slider
/// Features a continuous capsule rail and an oblong horizontal capsule thumb with tactile spring physics.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 6
    var thumbWidth: CGFloat = 18
    var thumbHeight: CGFloat = 12
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 6,
        thumbWidth: CGFloat = 18,
        thumbHeight: CGFloat = 12,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
        self.onActivity = onActivity
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clampedVal = max(0.0, min(1.0, value))
            let fillWidth = max(0, min(width, width * clampedVal))
            let thumbOffset = max(0, min(width - thumbWidth, fillWidth - (thumbWidth / 2)))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: trackHeight)

                // Filled Active Track
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: trackHeight)

                // Oblong Capsule Thumb (matching Apple Control Center Sound design)
                Capsule()
                    .fill(Color.white)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1.5)
                    .scaleEffect(isDragging ? 1.14 : (isHovering ? 1.06 : 1.0))
                    .offset(x: thumbOffset)
                    .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isDragging || isHovering)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = max(0.0, min(1.0, gesture.location.x / width))
                        value = fraction
                        onActivity?()
                    }
                    .onEnded { gesture in
                        isDragging = false
                        let fraction = max(0.0, min(1.0, gesture.location.x / width))
                        value = fraction
                        onActivity?()
                    }
            )
            .onHover { h in
                isHovering = h
            }
        }
        .frame(height: max(trackHeight, thumbHeight) + 6)
    }
}

// MARK: - Unified Liquid Glass Transport Pill Bar

/// Unified Floating Pill Transport Bar (QuickTime / macOS 26 Era)
/// Groups [Rewind 10] [Play / Pause] [Forward 10] into a single, cohesive Liquid Glass Capsule.
public struct TransportPillBar: View {
    var isPlaying: Bool
    var onRewind: () -> Void
    var onPlayPause: () -> Void
    var onForward: () -> Void

    public init(
        isPlaying: Bool,
        onRewind: @escaping () -> Void,
        onPlayPause: @escaping () -> Void,
        onForward: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.onRewind = onRewind
        self.onPlayPause = onPlayPause
        self.onForward = onForward
    }

    public var body: some View {
        HStack(spacing: 18) {
            // Rewind 10s Button
            TransportItemButton(icon: "gobackward.10", size: 40, iconSize: 18, action: onRewind)
                .help("Rewind 10 seconds (⌘←)")

            GlassDivider(height: 20)

            // Play / Pause Main Button
            TransportItemButton(
                icon: isPlaying ? "pause.fill" : "play.fill",
                size: 50,
                iconSize: 24,
                isPrimary: true,
                action: onPlayPause
            )
            .help(isPlaying ? "Pause (Space)" : "Play (Space)")

            GlassDivider(height: 20)

            // Forward 10s Button
            TransportItemButton(icon: "goforward.10", size: 40, iconSize: 18, action: onForward)
                .help("Forward 10 seconds (⌘→)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(Glass.regular, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 6)
    }
}

private struct TransportItemButton: View {
    var icon: String
    var size: CGFloat
    var iconSize: CGFloat
    var isPrimary: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: isPrimary ? .bold : .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.12 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isHovering)
        .onHover { h in isHovering = h }
    }
}

// MARK: - Circular Liquid Glass Transport Button (Legacy / Standalone)

public struct LiquidCircleButton: View {
    var icon: String
    var size: CGFloat
    var iconSize: CGFloat
    var isBold: Bool
    var action: () -> Void

    @State private var isHovering = false

    public init(
        icon: String,
        size: CGFloat = 56,
        iconSize: CGFloat = 22,
        isBold: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.isBold = isBold
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: isBold ? .bold : .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(Glass.regular, in: Circle())
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovering)
        .onHover { h in isHovering = h }
    }
}

// MARK: - Glass Helpers

/// 1px Vertical Glass Separator
public struct GlassDivider: View {
    var height: CGFloat = 16

    public init(height: CGFloat = 16) {
        self.height = height
    }

    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: height)
    }
}

/// Liquid Glass Capsule Button Style for Dialogs and Actions
public struct LiquidCapsuleButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    @State private var isHovering = false

    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isProminent ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isProminent ? Color.accentColor : Color.clear)
            )
            .glassEffect(Glass.regular, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovering)
            .animation(.spring(response: 0.12, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { h in isHovering = h }
    }
}
