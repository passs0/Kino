import SwiftUI
import AppKit

/// Apple's Official macOS 26+ Liquid Glass System Integration
/// Uses native SwiftUI `Glass.regular` and `.glassEffect(Glass.regular, in: shape)`.
/// Seamlessly uses macOS System Settings Appearance Accent Color.

// MARK: - Apple Control Center Style Pill Slider

/// Apple macOS / iOS Control Center Style Pill Slider
/// True Apple Liquid Glass behavior:
/// - When idle: An opaque solid white pill thumb resting on the continuous capsule rail.
/// - When hovered or dragged: Fluidly transforms into a larger, native Liquid Glass pill with optical refraction and liquid-like spring physics.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 5.5
    var idleThumbWidth: CGFloat = 16
    var idleThumbHeight: CGFloat = 11
    var activeThumbWidth: CGFloat = 26
    var activeThumbHeight: CGFloat = 17
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.5,
        idleThumbWidth: CGFloat = 16,
        idleThumbHeight: CGFloat = 11,
        activeThumbWidth: CGFloat = 26,
        activeThumbHeight: CGFloat = 17,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.idleThumbWidth = idleThumbWidth
        self.idleThumbHeight = idleThumbHeight
        self.activeThumbWidth = activeThumbWidth
        self.activeThumbHeight = activeThumbHeight
        self.onActivity = onActivity
    }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.5,
        thumbWidth: CGFloat = 16,
        thumbHeight: CGFloat = 11,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.idleThumbWidth = thumbWidth
        self.idleThumbHeight = thumbHeight
        self.activeThumbWidth = max(24, thumbWidth + 10)
        self.activeThumbHeight = max(15, thumbHeight + 6)
        self.onActivity = onActivity
    }

    private var isInteracting: Bool {
        isDragging || isHovering
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clampedVal = max(0.0, min(1.0, value))
            let fillWidth = max(0, min(width, width * clampedVal))
            let currentThumbWidth = isInteracting ? activeThumbWidth : idleThumbWidth
            let thumbOffset = max(0, min(width - currentThumbWidth, fillWidth - (currentThumbWidth / 2)))

            GlassEffectContainer {
                ZStack(alignment: .leading) {
                    // Continuous Background Rail
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: trackHeight)

                    // Active Filled Track
                    Capsule()
                        .fill(Color.white)
                        .frame(width: fillWidth, height: trackHeight)

                    // Thumb: Idle is solid white pill; Interacting is bigger native Liquid Glass pill with true optical refraction
                    Group {
                        if isInteracting {
                            Capsule()
                                .fill(Color.clear)
                                .frame(width: activeThumbWidth, height: activeThumbHeight)
                                .glassEffect(Glass.regular, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
                        } else {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: idleThumbWidth, height: idleThumbHeight)
                                .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                        }
                    }
                    .offset(x: thumbOffset)
                    .animation(.spring(response: 0.28, dampingFraction: 0.70), value: isInteracting)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
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
        .frame(height: max(trackHeight, activeThumbHeight) + 6)
    }
}

// MARK: - Circular Liquid Glass Transport Button

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
