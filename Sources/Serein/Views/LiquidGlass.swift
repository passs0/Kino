import SwiftUI
import AppKit

/// Apple's Official macOS 26+ Liquid Glass System Integration
/// Uses native SwiftUI `Glass.regular` and `.glassEffect(Glass.regular, in: shape)`.
/// Seamlessly uses macOS System Settings Appearance Accent Color.

// MARK: - Apple Control Center Style Pill Slider

/// Apple macOS 26 / iOS 18 Control Center Style Pill Slider
/// Features a continuous capsule rail and an oblong horizontal capsule thumb with tactile spring physics.
/// True Apple Liquid Glass behavior: displays as a solid white pill when idle, and seamlessly morphs
/// into translucent, refractive Liquid Glass with a 3D specular rim when hovered or dragged.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 5.5
    var thumbWidth: CGFloat = 17
    var thumbHeight: CGFloat = 11
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.5,
        thumbWidth: CGFloat = 17,
        thumbHeight: CGFloat = 11,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
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
            let thumbOffset = max(0, min(width - thumbWidth, fillWidth - (thumbWidth / 2)))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: trackHeight)

                // Filled Active Track (visible through the translucent glass thumb)
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: trackHeight)

                // Oblong Capsule Thumb (Morphic Liquid Glass on interaction)
                LiquidGlassThumb(
                    isInteracting: isInteracting,
                    isDragging: isDragging,
                    thumbWidth: thumbWidth,
                    thumbHeight: thumbHeight
                )
                .offset(x: thumbOffset)
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
        .frame(height: max(trackHeight, thumbHeight) + 8)
    }
}

// MARK: - Apple Liquid Glass Slider Thumb

/// Apple Control Center Style Thumb that seamlessly morphs from a solid white pill into
/// translucent Liquid Glass when hovered or dragged.
public struct LiquidGlassThumb: View {
    public var isInteracting: Bool
    public var isDragging: Bool
    public var thumbWidth: CGFloat
    public var thumbHeight: CGFloat

    public init(
        isInteracting: Bool,
        isDragging: Bool,
        thumbWidth: CGFloat = 17,
        thumbHeight: CGFloat = 11
    ) {
        self.isInteracting = isInteracting
        self.isDragging = isDragging
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
    }

    public var body: some View {
        ZStack {
            // 1. Idle State: Crisp Solid White Pill
            Capsule()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.30), radius: 2.5, x: 0, y: 1)
                .opacity(isInteracting ? 0 : 1)

            // 2. Interacting State: True Apple Liquid Glass Pill (Refractive, Translucent, Specular Bezel)
            ZStack {
                // Frosted refractive backdrop lens
                Capsule()
                    .fill(Color(white: 0.18).opacity(0.38))
                    .glassEffect(Glass.regular, in: Capsule())

                // Inner specular highlight (top illumination)
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.30), location: 0.0),
                                .init(color: Color.white.opacity(0.06), location: 0.45),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 3D Specular Bezel / Glass Rim (Light rim on top, dark refractive edge on bottom)
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.75), location: 0.0),
                                .init(color: Color.white.opacity(0.28), location: 0.35),
                                .init(color: Color.black.opacity(0.20), location: 0.70),
                                .init(color: Color.black.opacity(0.60), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: Color.black.opacity(0.50), radius: isDragging ? 6 : 4, x: 0, y: isDragging ? 3 : 2)
            .opacity(isInteracting ? 1 : 0)
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .scaleEffect(isDragging ? 1.34 : (isInteracting ? 1.18 : 1.0))
        .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isInteracting)
        .animation(.spring(response: 0.20, dampingFraction: 0.75), value: isDragging)
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
