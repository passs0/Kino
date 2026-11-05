import SwiftUI
import AppKit

/// Apple's Official macOS 26+ Liquid Glass System Integration
/// Uses native SwiftUI `Glass.regular` and `.glassEffect(Glass.regular, in: shape)`.
/// Seamlessly uses macOS System Settings Appearance Accent Color.

// MARK: - Apple Control Center Style Pill Slider

/// Apple macOS / visionOS Liquid Glass Pill Slider
/// True Apple Liquid Glass implementation matching the official design specification:
/// - Oblong 3D Liquid Glass pill thumb with real-time optical refraction (`Glass.regular`) and specular crescent highlight.
/// - The continuous background rail runs across the slider width.
/// - The active track enters the glass thumb and terminates smoothly at the thumb's center with a rounded capsule cap,
///   allowing the inactive track to pass through the right half of the glass lens.
/// - Fluid spring physics with tactile interaction response on hover and drag.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 5.0
    var thumbWidth: CGFloat = 36
    var thumbHeight: CGFloat = 20
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.0,
        thumbWidth: CGFloat = 36,
        thumbHeight: CGFloat = 20,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
        self.onActivity = onActivity
    }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.0,
        idleThumbWidth: CGFloat = 36,
        idleThumbHeight: CGFloat = 20,
        activeThumbWidth: CGFloat = 38,
        activeThumbHeight: CGFloat = 21,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.thumbWidth = idleThumbWidth
        self.thumbHeight = idleThumbHeight
        self.onActivity = onActivity
    }

    private var isInteracting: Bool {
        isDragging || isHovering
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clampedVal = max(0.0, min(1.0, value))

            let scale: CGFloat = isInteracting ? 1.06 : 1.0
            let currentThumbWidth = thumbWidth * scale
            let currentThumbHeight = thumbHeight * scale

            let thumbCenterX = currentThumbWidth / 2 + clampedVal * (width - currentThumbWidth)

            GlassEffectContainer {
                ZStack(alignment: .leading) {
                    // 1. Continuous Inactive Background Rail (full width)
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: width, height: trackHeight)

                    // 2. Active Filled Track (extends seamlessly to thumb center)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(trackHeight, thumbCenterX), height: trackHeight)

                    // 3. True Apple Liquid Glass Pill Thumb
                    ZStack {
                        // Volumetric Glass Body with Native Optical Refraction
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .glassEffect(Glass.regular, in: Capsule())

                        // 3D Specular Rim with multi-stop refraction gradient
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.85), location: 0.0),
                                        .init(color: Color.white.opacity(0.25), location: 0.35),
                                        .init(color: Color.black.opacity(0.35), location: 0.70),
                                        .init(color: Color.white.opacity(0.20), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )

                        // Upper Crescent Specular Glint (Light Reflection)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .frame(width: currentThumbWidth - 3, height: currentThumbHeight * 0.45)
                            .offset(y: -currentThumbHeight * 0.24)
                            .blur(radius: 0.5)
                            .mask(Capsule().stroke(lineWidth: 1.5))
                    }
                    .frame(width: currentThumbWidth, height: currentThumbHeight)
                    .shadow(color: Color.black.opacity(0.42), radius: 6, x: 0, y: 2.5)
                    .position(x: thumbCenterX, y: geo.size.height / 2)
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
        .frame(height: thumbHeight + 6)
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
